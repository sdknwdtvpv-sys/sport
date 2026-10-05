#!/usr/bin/env node
/**
 * 练了么 · 文档里的"**当前版本**"说法有没有过期
 *
 * **它为什么存在**：这个仓库最勤劳的一类漂移就是**版本号**。`verify.sh` 第 2 层已经守着
 * 三处"真机装的是哪一版"（README / ROADMAP / release-checklist），但文档里还有**别的**
 * 地方在陈述"现在是什么版本" —— 产物行、终局核验行、iOS 那一大行里的"在 vX 上重编重核"……
 * 2026-09-30 一查就有三处停在 v1.31.0/40 或 v1.32.0，而仓库已经是 v1.32.2/43。
 *
 * 过期状态**比没有状态更坏**：它让人以为某件事已经在那一版上做过了。
 *
 * 判据（只认"陈述现状"的写法，历史叙述一律放过）：
 *   * `versionCode <N>`、`包内 X.Y.Z (N)`、`跑的是/装的是 vX.Y.Z`、`在 vX.Y.Z 上重核`；
 *   * 这些数字必须等于 `app/lib/core/app_info.dart` 的 `kAppVersion` 与 `pubspec.yaml` 的 build；
 *   * **跳过**含「历史 / 曾经 / 之前 / 旧 / 改来 / 当时 / 停在 / CHANGELOG」的行 ——
 *     文档里复盘旧版本是正常的（这一条是为了不误报，也是自检里专门有用例的地方）。
 *
 * 用法：
 *   node tool/check-doc-versions.mjs              # 扫 README + docs/*.md
 *   node tool/check-doc-versions.mjs --selftest   # 自检（造几份过期文档，验它抓得住）
 *
 * 退出码：任何一处过期 → 1。
 */

import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { allDocFiles, isHistorical } from './lib/docs.mjs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** 真源：`app_info.dart` 的版本 + `pubspec.yaml` 的 build number。 */
function truth(root) {
  const info = readFileSync(join(root, 'app/lib/core/app_info.dart'), 'utf8');
  const version = /kAppVersion\s*=\s*'([^']+)'/.exec(info)[1];
  const pubspec = readFileSync(join(root, 'app/pubspec.yaml'), 'utf8');
  const build = /^version:\s*[\d.]+\+(\d+)/m.exec(pubspec)?.[1] ?? null;
  return { version, build };
}

/** 只认"陈述现状"的写法；历史叙述跳过。 */
const PATTERNS = [
  [/versionCode\s*[`\s]*(\d+)/, 'versionCode', 'build'],
  [/包内\s*[`*]*(\d+\.\d+\.\d+)\s*\((\d+)\)/, '包内版本', 'both'],
  [/(?:跑的?是|装的?是)\s*\*{0,2}v(\d+\.\d+\.\d+)/, '设备上的版本', 'version'],
  [/在\s*v(\d+\.\d+\.\d+)\s*上(?:重编)?重核/, '重核版本', 'version'],
];
// "这是过去的事"的判定与**文档枚举**都搬到 `tool/lib/docs.mjs` 了（三处守卫共用一份）：
//   * 枚举：以前三个 check-doc-* 各抄一遍，加一个文档目录要改三处；
//   * 历史窗口：⚠️ 这里踩过一次坑（2026-09-30）——判据原本是**整行**匹配，
//     而文档里的表格行很长，行尾一句"旧行写的 59.8M 是 v1.22 那会儿的"就能把
//     **同一行里当期的版本说法**一起放过（`release-checklist.md` 的"构建链"行
//     写着 v1.32.2、而仓库已经 v1.33.0，守卫全绿）。现在看这一处说法前后 40 个字。

function inspect(root) {
  const problems = [];
  const { version, build } = truth(root);
  const docs = allDocFiles(root);
  let checked = 0;
  for (const rel of docs) {
    let text;
    try { text = readFileSync(join(root, rel), 'utf8'); } catch { continue; }
    text.split('\n').forEach((line, i) => {
      for (const [rx, what, kind] of PATTERNS) {
        for (const m of line.matchAll(new RegExp(rx.source, 'g'))) {
          if (isHistorical(line, m.index, m[0].length)) continue;
          checked += 1;
          const bad = (kind === 'build' && m[1] !== build)
            || (kind === 'version' && m[1] !== version)
            || (kind === 'both' && (m[1] !== version || m[2] !== build));
          if (bad) {
            const got = kind === 'both' ? `${m[1]} (${m[2]})` : m[1];
            const want = kind === 'build' ? build : (kind === 'both' ? `${version} (${build})` : version);
            problems.push(`${rel}:${i + 1} 写着「${what} = ${got}」，而当前是 ${want} —— `
              + '过期状态比没有状态更坏（会让人以为那一版上已经做过了）');
          }
        }
      }
    });
  }
  return { problems, checked, version, build };
}

// ───────────────────────────────────────────────────────────── 自检
function selftest() {
  const makeTree = (doc, rootDoc) => {
    const root = mkdtempSync(join(tmpdir(), 'lianleme-docver-'));
    mkdirSync(join(root, 'app/lib/core'), { recursive: true });
    mkdirSync(join(root, 'docs'), { recursive: true });
    writeFileSync(join(root, 'app/lib/core/app_info.dart'), "const String kAppVersion = '9.9.9';\n");
    writeFileSync(join(root, 'app/pubspec.yaml'), 'version: 9.9.9+77\n');
    writeFileSync(join(root, 'README.md'), '# x\n');
    writeFileSync(join(root, 'docs/a.md'), doc);
    if (rootDoc) writeFileSync(join(root, 'ROADMAP.md'), rootDoc);
    return root;
  };
  const cases = [
    ['版本对得上 → 绿', '真机装的是 **v9.9.9**（versionCode 77）\n', true, null],
    ['versionCode 过期 → 必须报', '产物 `versionCode 76 · versionName 9.9.8`\n', false, 'versionCode = 76'],
    ['设备版本过期 → 必须报', '真机装的是 **v9.9.8**\n', false, '设备上的版本'],
    ['重核版本过期 → 必须报', '**2026-09-30 在 v9.9.8 上重编重核**\n', false, '重核版本'],
    ['历史叙述不算（不能误报）', '首次装上真机时是 v1.0.0 / versionCode 1（历史记录）\n', true, null],
    ['"之前停在 vX"这类也不算', '这条之前停在 v1.31.0\n', true, null],
    // ⚠️ 这一条是踩过的坑：判据原本按**整行**看有没有"历史"字样，
    // 于是长表格行里行尾一句"旧行写的…"就能把同一行里**当期**的版本说法一起放过
    // （`release-checklist.md` 的"构建链"行就这么绿着过期了）。
    ['长行里别处的"旧"不能放过当期版本 → 必须报',
      '旧行写的 59.8M/55.9M 是 v1.22 那会儿的；**2026-09-30 在 v9.9.8 上重编重核**\n', false, '重核版本'],
    ['历史标记紧挨着这处说法 → 也算历史', '历史上装的是 v1.0.0 / versionCode 1（当时）\n', true, null],
    // ★ 真实事故的回归：`ROADMAP.md` 抬头那句 versionCode 与同一页表里的互相矛盾，
    //   而当时没有任何守卫扫这个文件（清单只在 README + docs/*.md 里找）。
    ['根目录 ROADMAP.md 里的过期版本 → 必须报', '# a\n', false, 'versionCode = 76',
      '## 一眼看懂\n\n> 已切版并装在真机上（`versionCode 76`）。\n'],
  ];
  let bad = 0;
  for (const [label, doc, wantGreen, expect, rootDoc] of cases) {
    const root = makeTree(doc, rootDoc);
    const { problems } = inspect(root);
    const green = problems.length === 0;
    let ok = green === wantGreen;
    let why = green ? '' : `　→ ${problems[0].slice(0, 62)}`;
    if (ok && !wantGreen && expect && !problems.some((p) => p.includes(expect))) {
      ok = false;
      why = `　→ 红了，但不是因为「${expect}」（红在：${problems[0].slice(0, 44)}）`;
    }
    if (!ok) bad += 1;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}${why}`);
    rmSync(root, { recursive: true, force: true });
  }
  if (bad) {
    console.error(`\n✗ 自检失败 ${bad} 项 —— 这个工具本身不可信，先修它`);
    process.exit(1);
  }
  console.log('\n✓ 自检通过：过期的 versionCode / 设备版本 / 重核版本都藏不住；'
    + '历史叙述不误报');
}

// ───────────────────────────────────────────────────────────────── 跑
if (process.argv.includes('--selftest')) {
  selftest();
} else {
  const rootArg = process.argv.find((a) => a.startsWith('--root='));
  const { problems, checked, version, build } = inspect(rootArg ? rootArg.slice('--root='.length) : ROOT);
  console.log('文档里的"当前版本"核对\n');
  console.log(`  当前真源：v${version}+${build} · 核了 ${checked} 处"陈述现状"的版本写法`);
  if (problems.length) {
    console.log('');
    for (const p of problems) console.error(`  \x1b[31m✗\x1b[0m ${p}`);
    console.error(`\n✗ ${problems.length} 处版本说法过期 —— 过期状态比没有状态更坏`);
    process.exit(1);
  }
  console.log('\n✓ 文档里陈述现状的版本号都与真源一致');
}
