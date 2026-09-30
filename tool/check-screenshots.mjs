#!/usr/bin/env node
/**
 * 练了么 · 商店截图核对（目录里那两套图，是不是"齐、对、没夹带"）
 *
 * **它为什么存在**：截图是**交付物**（软著说明书、国内商店、Google Play 都用它），
 * 但它是全仓库里唯一一类"没有任何东西核过"的产物 —— 图标有 `asset-check.mjs` 核宽高与
 * 透明通道，AAB 有 `check-aab.mjs`，iOS 包有 `check-ios-app.mjs`，就截图全靠人记得。
 *
 * 而它真的坏过，只是没人发现：**`11-body-metric.png` 比 App 旧了一个版本。**
 * v1.31.0 起「体重」前面多了一道**敏感信息单独同意**的门（PIPL 第 29 条），
 * 而截图脚本当时假定"点开就是表单" —— 在**已同意**的设备上跑，它拍到的确实是表单；
 * 在**干净安装**上跑，它拍到的会是对话框，然后**照样命名成 `11-body-metric`**。
 * 也就是说：同一份脚本，出什么图取决于设备状态，而目录里看不出来。
 * 修法是让脚本走用户真实路径（同意 → 再拍），并**多留一张门的图**当合规证据；
 * 这个工具则负责让"那张门不见了"这件事**没法悄悄发生**。
 *
 * 它核四件事（前三条红，第四条也红 —— 都别想蒙过去）：
 *   1. **齐**：该有的每一张都在（清单写在下面，是显式的，改名单要改这里）；
 *   2. **对**：每张的实际像素 == 这套的尺寸（1080×2400 / 1080×1920）——
 *      挡住"被谁顺手缩过一遍""拿错设备出的图"；
 *   3. **没夹带**：目录里不许有清单外的 PNG。典型的是 `zz-fail-<步骤>.png`：
 *      那是脚本某一步失败时自动拍的现场图，**它在 = 这一套图不全，不能上架**；
 *   4. **那道门必须在**（`11a-body-consent.png`，只在国内/软著那套要求）：
 *      它不见了，通常就意味着"这次是在已经同意过的设备上跑的" —— 而那正是
 *      上面那个旧 bug 的形状。
 *
 * 用法：
 *   node tool/check-screenshots.mjs              # 核仓库里那两套
 *   node tool/check-screenshots.mjs --selftest   # 自检（造几套假的，验它抓得住）
 *
 * 退出码：有任何一项不符合 → 1。
 */

import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { deflateSync } from 'node:zlib';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

// ── 11 屏：两套图共有的部分（脚本 `integration_test/screenshots_test.dart` 按这个顺序拍）
const CORE = [
  '01-home',
  '02-suggestion',
  '03-routine',
  '04-picker',
  '05-workout',
  '06-workout-logged',
  '07-summary',
  '08-progress',
  '09-all-data',
  '10-profile',
  '11-body-metric',
];

/**
 * 两套图各自的规格。尺寸是**这套图的定义**：换设备重拍就改这里 + 改 docs/screenshots.md，
 * 而不是让工具"看情况"（宽松的守卫等于没有守卫）。
 */
const SETS = [
  {
    dir: 'store-assets/screenshots',
    label: '国内商店 / 软著说明书那套（20:9）',
    width: 1080,
    height: 2400,
    files: [
      ...CORE,
      // 全新安装的空态首页：`adb screencap` 抓的整屏，2026-09-30 那批就是这么来的
      '01b-home-fresh-install',
      // **敏感信息单独同意**那道门。它是合规证据，不是给商店上传的图 ——
      // 商店那几屏里夹一张对话框反而不好看（`docs/screenshots.md` 写了这件事）。
      '11a-body-consent',
    ],
  },
  {
    dir: 'store-assets/screenshots-play',
    label: 'Google Play 那套（9:16，宽高比在两种口径下都合法）',
    width: 1080,
    height: 1920,
    files: [...CORE],
  },
];

/** PNG 头解析：IHDR 的宽高在第 16–24 字节（与 `tool/asset-check.mjs` 同一套口径）。 */
function pngSize(path) {
  const b = readFileSync(path);
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (b.length < 24 || !b.subarray(0, 8).equals(sig)) return null;
  return { width: b.readUInt32BE(16), height: b.readUInt32BE(20) };
}

function inspect(root) {
  const problems = [];
  const lines = [];

  for (const set of SETS) {
    const dir = join(root, set.dir);
    if (!existsSync(dir)) {
      problems.push(`${set.dir}/ 不存在 —— 这一套图整个没了`);
      continue;
    }
    const found = readdirSync(dir).filter((f) => f.toLowerCase().endsWith('.png'));
    const names = new Set(found.map((f) => f.replace(/\.png$/, '')));

    // 1. 齐
    for (const want of set.files) {
      if (!names.has(want)) problems.push(`${set.dir}/${want}.png 不见了`);
    }

    // 3. 没夹带
    for (const f of found) {
      const name = f.replace(/\.png$/, '');
      if (!set.files.includes(name)) {
        const hint = name.startsWith('zz-fail-')
          ? '　← 这是某一步失败时的现场图：**这一套图不全，别拿去上架**'
          : '';
        problems.push(`${set.dir}/${f} 不在清单里${hint}`);
      }
    }

    // 2. 对
    let checked = 0;
    for (const want of set.files) {
      const p = join(dir, `${want}.png`);
      if (!existsSync(p)) continue;
      const size = pngSize(p);
      if (!size) {
        problems.push(`${set.dir}/${want}.png 不是合法 PNG（读不出宽高）`);
        continue;
      }
      checked += 1;
      if (size.width !== set.width || size.height !== set.height) {
        problems.push(`${set.dir}/${want}.png 是 ${size.width}×${size.height}，`
          + `这套图规定 ${set.width}×${set.height}`);
      }
    }

    // 4. 那道门（写进清单就够了，这里只是把"为什么"说在输出里）
    if (set.files.includes('11a-body-consent') && !names.has('11a-body-consent')) {
      lines.push(`  ! ${set.dir}：没有 11a-body-consent —— 多半是在**已同意**的设备上拍的，`
        + '干净安装看到的第一屏会是对话框而不是表单');
    }

    lines.push(`  ${set.dir}　${checked}/${set.files.length} 张 · `
      + `规定 ${set.width}×${set.height} · 目录里共 ${found.length} 个 PNG`);
  }

  return { problems, lines };
}

// ─────────────────────────────────────────────────────────── 自检
/** 造一张**真的**最小 PNG（zlib + CRC32），宽高可指定 —— 自检要能验"尺寸不对就红"。 */
function crc32(buf) {
  let c;
  const table = [];
  for (let n = 0; n < 256; n += 1) {
    c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  let crc = 0xffffffff;
  for (const byte of buf) crc = table[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const t = Buffer.from(type, 'latin1');
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([t, data])));
  return Buffer.concat([len, t, data, crc]);
}

function writePng(path, width, height) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // 位深
  ihdr[9] = 2; // 真彩色（与截图一致，不用调色板）
  const raw = Buffer.alloc(height * (1 + width * 3)); // 每行一个 filter 字节 + RGB，全 0 = 纯黑
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]));
}

function makeTree(mutate) {
  const root = mkdtempSync(join(tmpdir(), 'lianleme-shots-'));
  for (const set of SETS) {
    for (const name of set.files) {
      writePng(join(root, set.dir, `${name}.png`), set.width, set.height);
    }
  }
  if (mutate) mutate(root);
  return root;
}

function selftest() {
  const cases = [
    ['好的两套：全绿', null, true],
    ['少一张 11-body-metric', (r) => rmSync(join(r, 'store-assets/screenshots-play/11-body-metric.png')), false],
    ['那道门不见了（旧 bug 的形状）', (r) => rmSync(join(r, 'store-assets/screenshots/11a-body-consent.png')), false],
    ['夹带一张失败现场图', (r) => writePng(join(r, 'store-assets/screenshots-play/zz-fail-05-workout.png'), 1080, 1920), false],
    ['某张尺寸不对（被缩过）', (r) => writePng(join(r, 'store-assets/screenshots/04-picker.png'), 1080, 1920), false],
    ['目录里混进清单外的图', (r) => writePng(join(r, 'store-assets/screenshots/12-whatever.png'), 1080, 2400), false],
    ['整套没了', (r) => rmSync(join(r, 'store-assets/screenshots-play'), { recursive: true }), false],
  ];

  let bad = 0;
  for (const [label, mutate, wantGreen] of cases) {
    const root = makeTree(mutate);
    const { problems } = inspect(root);
    const green = problems.length === 0;
    const ok = green === wantGreen;
    if (!ok) bad += 1;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}`
      + (green ? '' : `　→ ${problems[0].slice(0, 62)}`));
    rmSync(root, { recursive: true, force: true });
  }
  if (bad) {
    console.error(`\n✗ 自检失败 ${bad} 项 —— 这个工具本身不可信，先修它`);
    process.exit(1);
  }
  console.log('\n✓ 自检通过：好图过得去，少一张、多一张、尺寸不对、夹带现场图都藏不住');
}

// ───────────────────────────────────────────────────────────────── 跑
if (process.argv.includes('--selftest')) {
  selftest();
} else {
  const { problems, lines } = inspect(ROOT);
  console.log('商店截图核对\n');
  for (const l of lines) console.log(l);
  if (problems.length) {
    console.log('');
    for (const p of problems) console.error(`  \x1b[31m✗\x1b[0m ${p}`);
    console.error(`\n✗ ${problems.length} 处不对 —— 截图是交付物，重拍或改清单，别放着`);
    process.exit(1);
  }
  console.log('\n✓ 两套截图齐、尺寸对、没夹带失败现场图');
}
