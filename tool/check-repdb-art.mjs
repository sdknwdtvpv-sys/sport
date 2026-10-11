#!/usr/bin/env node
/**
 * 练了么 · RepDB 动作插图核对（许可证义务是**可执行**的，不是写在文档里的一句承诺）
 *
 * **它为什么存在**：`app/assets/repdb-art/` 里的 426 张动作插图是**别人授权**给我们的，
 * 授权带四条条件与三条禁令（RepDB Free Tier License v1.0，原文 `tool/repdb-license.txt`）：
 *
 *   义务：① 可见署名「Exercise data by RepDB (repdb.co)」；
 *   义务：② 只在应用内使用，**不得**作为数据集/API 再分发；
 *   义务：③ 保留许可与出处记录；
 *   禁令：④ 不得作为生成式 AI 的输入/参考/训练素材；
 *   禁令：⑤ **付费档预览图（`premium-samples/`）一字节都不许进包**；
 *   禁令：⑥ 不得去掉署名、不得声称是自己的作品。
 *
 * 这些东西的共同点是：**违反之后 App 照样跑、测试照样绿、用户照样用** ——
 * 唯一会出问题的地方是"将来某一天收到一封律师函"。
 * 所以每一条都要有一条**机械的**检查盯着，而不是靠下一个人记得。
 *
 * 它核的七件事（每一件都对应一条可追溯的义务）：
 *   1. `tool/repdb-license.txt` 在仓库里，且看起来是许可原文（②③ 的凭据）；
 *   2. `app/lib/features/profile/repdb_credits_screen.dart` 里有**逐字**署名（①）；
 *   3. 「隐私与关于」页里挂着通往署名页的入口，且署名页用了正确的 key（① 的"可见"）；
 *   4. 生成脚本里的署名常量与署名页里的常量**字面相同**（防止两处漂移，⑥）；
 *   5. 资产目录里没有 `premium`/`sample` 字样的文件，清单里也不许出现（⑤）；
 *   6. 清单与实物一致、图片尺寸/总体积在预算内（跑 `vendor-repdb-art.mjs --check`）；
 *   7. `app/pubspec.yaml` 声明了这两个资源（否则图进了仓库却进不了包 —— 静默无效）。
 *
 * ⚠️ **它的边界**：不联网、不需要 Pillow —— 门禁不该要求一个跟构建无关的依赖
 * （踩过一次：`check-launch-relay.py` 要 Pillow，CI 上直接红）。
 * 重新生成插图时才需要 Pillow，那件事由 `tool/vendor-repdb-art.mjs` 负责，且**不进 CI**。
 *
 * 用法：
 *   node tool/check-repdb-art.mjs              # 核当前仓库
 *   node tool/check-repdb-art.mjs --selftest   # 自检（造几个假的仓库，验它抓得住）
 *
 * 退出码：任何一项不符 → 1。
 */

import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** 逐字署名。**两处必须字面相同**：生成脚本与署名页（漂了就有一边是错的）。 */
const ATTRIBUTION = 'Exercise data by RepDB (repdb.co)';

const LICENSE_REL = 'tool/repdb-license.txt';
const CREDITS_REL = 'app/lib/features/profile/repdb_credits_screen.dart';
const ABOUT_REL = 'app/lib/features/profile/privacy_about_screen.dart';
const VENDOR_REL = 'tool/vendor-repdb-art.mjs';
const MANIFEST_REL = 'app/assets/repdb-art.json';
const ASSET_DIR_REL = 'app/assets/repdb-art';
const PUBSPEC_REL = 'app/pubspec.yaml';

/**
 * 核一个仓库根目录。返回 `{ problems, facts, skipped }`。
 * `root` 可注入 —— 自检就是靠它造各种假仓库。
 */
export function inspect(root) {
  const problems = [];
  const facts = [];
  const read = (rel) => (existsSync(join(root, rel)) ? readFileSync(join(root, rel), 'utf8') : null);

  // ── 1. 许可原文（义务 ②③ 的凭据）────────────────────────────────────
  const license = read(LICENSE_REL);
  if (license === null) {
    problems.push(`${LICENSE_REL} 不在仓库里 —— 许可原文是"我们有授权的凭据"，必须随仓库走`);
  } else {
    // 认四句话：署名要求、不得再分发、不得喂模型、付费预览仅限评估
    for (const [needle, why] of [
      ['Attribution required', '署名义务'],
      ['No redistribution as a dataset', '不得作为数据集再分发'],
      ['No generative-AI derivation', '不得作为生成式模型素材'],
      ['evaluation-only', '付费档预览仅限评估'],
    ]) {
      if (!license.includes(needle)) {
        problems.push(`${LICENSE_REL} 里找不到「${needle}」（${why}）—— 这看起来不是 RepDB 的许可原文`);
      }
    }
    facts.push(`${LICENSE_REL}：${license.length} 字节，四条关键条款都在`);
  }

  // ── 2. 逐字署名（义务 ①，禁令 ⑥）────────────────────────────────────
  const credits = read(CREDITS_REL);
  if (credits === null) {
    problems.push(`${CREDITS_REL} 不在 —— 署名页是许可证义务，不能删`);
  } else {
    if (!credits.includes(ATTRIBUTION)) {
      problems.push(`${CREDITS_REL} 里没有逐字署名「${ATTRIBUTION}」——`
        + '许可要求的就是这一句，改写/翻译都不算履行');
    }
    // 署名必须真的渲染出来，不是只写在注释里：要求它出现在一个 Text/SelectableText 附近
    if (!/SelectableText\(\s*\n?\s*kRepdbAttribution/.test(credits)
      && !/Text\(\s*\n?\s*kRepdbAttribution/.test(credits)) {
      problems.push(`${CREDITS_REL} 里 kRepdbAttribution 没有出现在 Text/SelectableText 里 ——`
        + '署名必须在界面上看得见');
    }
    facts.push(`署名页：逐字署名 + 许可摘要（AI 生成标注也在）`);
  }

  // ── 3. 署名页要能从菜单点进去（① "可见的链接"）──────────────────────
  const about = read(ABOUT_REL);
  if (about === null) {
    problems.push(`${ABOUT_REL} 不在 —— 它是署名页的入口所在`);
  } else {
    if (!about.includes('RepdbCreditsScreen')) {
      problems.push(`${ABOUT_REL} 里没有通往 RepdbCreditsScreen 的入口 ——`
        + '署名页埋在代码里等于没有署名（许可要求"可见"）');
    }
    if (!about.includes("Key('repdb-credits')")) {
      problems.push(`${ABOUT_REL} 里的署名入口少了 Key('repdb-credits') —— 测试要点它`);
    }
    facts.push('入口：「隐私与关于」→「动作插图来源」');
  }

  // ── 4. 生成脚本与署名页的署名常量必须字面相同（防两处漂移）──────────
  const vendor = read(VENDOR_REL);
  if (vendor === null) {
    problems.push(`${VENDOR_REL} 不在 —— 插图是它的产物，删了它就没有可复现的来源`);
  } else {
    const m = /const ATTRIBUTION = '([^']+)'/.exec(vendor);
    if (!m) {
      problems.push(`${VENDOR_REL} 里找不到 ATTRIBUTION 常量`);
    } else if (m[1] !== ATTRIBUTION) {
      problems.push(`${VENDOR_REL} 的署名「${m[1]}」与检查里的「${ATTRIBUTION}」不一致 ——`
        + '署名只有一份正确的写法，两处不同必然有一处是错的');
    }
    // 生成脚本自己不许在 --check 路径上联网/用 Pillow（门禁要能在 CI 上跑）。
    // 只扫 `if (CHECK) {` 到 `// ---- 生成 ----` 之间那一段 —— 生成分支本来就要联网与 Pillow。
    const from = vendor.indexOf('if (CHECK) {');
    const to = vendor.indexOf('// ---- 生成 ----');
    const checkBlock = from >= 0 ? vendor.slice(from, to > from ? to : undefined) : '';
    if (!checkBlock) {
      problems.push(`${VENDOR_REL} 里找不到 --check 分支 —— 核不出来`);
    } else if (/execFileSync\('curl'/.test(checkBlock) || /python3/.test(checkBlock)) {
      problems.push(`${VENDOR_REL} 的 --check 分支里出现了联网或 python3 ——`
        + '门禁必须能在 CI 上不联网、不装 Pillow 跑起来');
    }
  }

  // ── 5. 付费档预览图（禁令 ⑤）───────────────────────────────────────
  const manifest = read(MANIFEST_REL);
  if (manifest === null) {
    problems.push(`${MANIFEST_REL} 不在 —— pubspec 声明了它，缺了会在运行时读不到图`);
  } else {
    for (const bad of ['premium', 'sample']) {
      if (manifest.toLowerCase().includes(bad)) {
        problems.push(`${MANIFEST_REL} 里出现了「${bad}」——`
          + '付费档预览图仅限评估（许可第 6 条），不得进包');
      }
    }
    // 逐字署名也要在清单里（清单是"这批图从哪来"的机器可读记录）
    let parsed = null;
    try {
      parsed = JSON.parse(manifest);
    } catch (e) {
      problems.push(`${MANIFEST_REL} 不是合法 JSON：${String(e).slice(0, 60)}`);
    }
    if (parsed) {
      if (parsed.attribution !== ATTRIBUTION) {
        problems.push(`${MANIFEST_REL} 的 attribution 不是逐字的「${ATTRIBUTION}」`);
      }
      if (!parsed.license || !String(parsed.license).includes('tool/repdb-license.txt')) {
        problems.push(`${MANIFEST_REL} 没有指向许可原文（${LICENSE_REL}）—— 出处记录必须可追溯`);
      }
      facts.push(`清单：${parsed.count ?? '?'} 个动作，快照 ${parsed.source_snapshot ?? '未知'}`);
    }
  }
  if (existsSync(join(root, ASSET_DIR_REL))) {
    const files = execFileSync('ls', [join(root, ASSET_DIR_REL)], { encoding: 'utf8' }).split('\n').filter(Boolean);
    for (const f of files) {
      if (/premium|sample/i.test(f)) {
        problems.push(`${ASSET_DIR_REL}/${f} 是付费档预览图 —— 不得进包（许可第 6 条）`);
      }
    }
  }

  // ── 6. 清单 ↔ 实物（尺寸/体积/缺图）────────────────────────────────
  // 复用生成工具自己的 --check：它是同一份逻辑的唯一实现（不许有两份判断标准）
  if (existsSync(join(root, VENDOR_REL))) {
    try {
      const out = execFileSync(process.execPath, [join(root, VENDOR_REL), '--check'], {
        cwd: root,
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      const line = out.split('\n').find((l) => l.includes('清单')) ?? '';
      facts.push(line.trim() || '清单与实物一致');
    } catch (e) {
      const msg = `${e.stdout ?? ''}${e.stderr ?? ''}`.trim().split('\n').slice(-6).join(' / ');
      problems.push(`vendor-repdb-art.mjs --check 失败：${msg.slice(0, 300)}`);
    }
  }

  // ── 7. pubspec 必须声明这两个资源（否则图进了仓库却进不了包）────────
  const pubspec = read(PUBSPEC_REL);
  if (pubspec === null) {
    problems.push(`${PUBSPEC_REL} 不在`);
  } else {
    for (const asset of ['assets/repdb-art.json', 'assets/repdb-art/']) {
      if (!pubspec.includes(`- ${asset}`)) {
        problems.push(`${PUBSPEC_REL} 没有声明「${asset}」——`
          + '文件在仓库里但没打包，运行时读不到（这种"静默无效"最难查）');
      }
    }
  }

  return { problems, facts, skipped: false };
}

// ───────────────────────────────────────────────────────────────── 自检
//
// 逻辑是"五项都通过才绿"，所以每一项都要有一个**只坏这一项**的假仓库 ——
// 否则"红了"不能证明是它抓的（踩过一次：一个守卫的红其实是别的规则触发的）。
function selftest() {
  const realRoot = ROOT;
  // 从一个真仓库拷出这五个文件，然后逐个做坏事
  const keep = [LICENSE_REL, CREDITS_REL, ABOUT_REL, VENDOR_REL, MANIFEST_REL, PUBSPEC_REL];
  const baseFiles = new Map();
  for (const rel of keep) {
    if (existsSync(join(realRoot, rel))) baseFiles.set(rel, readFileSync(join(realRoot, rel), 'utf8'));
  }
  // 资产目录也要有（否则第 5 项没得核）
  const assetDir = join(realRoot, ASSET_DIR_REL);
  const assets = existsSync(assetDir)
    ? execFileSync('ls', [assetDir], { encoding: 'utf8' }).split('\n').filter(Boolean).slice(0, 2)
    : [];

  function makeRepo(mutate) {
    const root = mkdtempSync(join(tmpdir(), 'repdb-guard-'));
    for (const [rel, text] of baseFiles) {
      const p = join(root, rel);
      mkdirSync(dirname(p), { recursive: true });
      writeFileSync(p, text, 'utf8');
    }
    for (const f of assets) {
      const p = join(root, ASSET_DIR_REL, f);
      mkdirSync(dirname(p), { recursive: true });
      writeFileSync(p, readFileSync(join(realRoot, ASSET_DIR_REL, f)));
    }
    // 清单里只留我们真拷过来的那几张图，否则 --check 会因为"文件不存在"红在别的项上
    const mp = join(root, MANIFEST_REL);
    if (existsSync(mp)) {
      const m = JSON.parse(readFileSync(mp, 'utf8'));
      const kept = new Set(assets);
      m.exercises = (m.exercises ?? []).filter((e) =>
        ['start', 'peak', 'main'].some((k) => e[k] && kept.has(e[k].split('/').pop())));
      m.count = m.exercises.length;
      writeFileSync(mp, JSON.stringify(m, null, 1));
    }
    // 映射表也要有（--check 要读它）
    const mapRel = 'tool/repdb-art-map.tsv';
    if (existsSync(join(realRoot, mapRel))) {
      const kept = new Set(assets);
      const lines = readFileSync(join(realRoot, mapRel), 'utf8').split('\n');
      const header = lines.filter((l) => l.startsWith('#') || !l.trim());
      const body = lines.filter((l) => l.trim() && !l.startsWith('#'))
        .filter((l) => {
          const rep = l.split('\t')[1];
          return [...kept].some((f) => f.startsWith(`${rep}-`));
        });
      mkdirSync(join(root, 'tool'), { recursive: true });
      writeFileSync(join(root, mapRel), [...header, ...body].join('\n') + '\n');
    }
    // exercises.json（--check 要核 our_id）——直接拷真仓库的
    const seedRel = 'app/assets/exercises.json';
    if (existsSync(join(realRoot, seedRel))) {
      mkdirSync(join(root, 'app/assets'), { recursive: true });
      writeFileSync(join(root, seedRel), readFileSync(join(realRoot, seedRel)));
    }
    mutate(root);
    return root;
  }

  const cases = [];
  cases.push(['干净仓库应当绿', (root) => {}, true]);
  cases.push(['许可原文不见了 → 红', (root) => rmSync(join(root, LICENSE_REL)), false, '许可原文']);
  cases.push(['许可被换成别的东西 → 红', (root) => {
    writeFileSync(join(root, LICENSE_REL), 'MIT License\n\nPermission is hereby granted...', 'utf8');
  }, false, '不是 RepDB 的许可原文']);
  cases.push(['署名从署名页删掉 → 红', (root) => {
    const p = join(root, CREDITS_REL);
    writeFileSync(p, readFileSync(p, 'utf8').replace(/Exercise data by RepDB \(repdb\.co\)/g, '感谢 RepDB'), 'utf8');
  }, false, '逐字署名']);
  cases.push(['署名页的入口被摘掉 → 红', (root) => {
    const p = join(root, ABOUT_REL);
    writeFileSync(p, readFileSync(p, 'utf8').replace('RepdbCreditsScreen', 'SizedBox'), 'utf8');
  }, false, '署名页埋在代码里']);
  cases.push(['生成脚本的署名被改成另一个写法 → 红', (root) => {
    const p = join(root, VENDOR_REL);
    writeFileSync(p, readFileSync(p, 'utf8').replace(
      /(const ATTRIBUTION = ')[^']+(')/, '$1Exercise data from RepDB$2'), 'utf8');
  }, false, '不一致']);
  cases.push(['付费档预览图混进资产目录 → 红', (root) => {
    mkdirSync(join(root, ASSET_DIR_REL), { recursive: true });
    writeFileSync(join(root, ASSET_DIR_REL, 'premium-samples-bent-over-db-row.webp'), 'x');
  }, false, '不得进包']);
  cases.push(['pubspec 忘了声明插图资源 → 红', (root) => {
    const p = join(root, PUBSPEC_REL);
    writeFileSync(p, readFileSync(p, 'utf8')
      .replace('- assets/repdb-art.json\n', '')
      .replace('- assets/repdb-art/\n', ''), 'utf8');
  }, false, '没有声明']);

  let bad = 0;
  console.log('RepDB 插图核对 · 自检\n');
  for (const [label, mutate, wantGreen, expect] of cases) {
    const root = makeRepo(mutate);
    let problems = [];
    try {
      ({ problems } = inspect(root));
    } catch (e) {
      problems = [`抛异常：${String(e).slice(0, 100)}`];
    }
    const green = problems.length === 0;
    let ok = green === wantGreen;
    let why = green ? '' : `　→ ${problems[0].slice(0, 70)}`;
    if (ok && !wantGreen && expect && !problems.some((p) => p.includes(expect))) {
      ok = false;
      why = `　→ 红了，但不是因为「${expect}」（红在：${problems[0].slice(0, 48)}）`;
    }
    if (!ok) bad += 1;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}${why}`);
    rmSync(root, { recursive: true, force: true });
  }
  if (bad) {
    console.error(`\n✗ 自检失败 ${bad} 项 —— 这个守卫本身不可信，先修它`);
    process.exit(1);
  }
  console.log('\n✓ 自检通过：署名被删、入口被摘、许可原文丢失、付费预览混入、'
    + 'pubspec 漏声明都藏不住');
}

// ───────────────────────────────────────────────────────────────── 跑
//
// ⚠️ 只有**直接运行**这个文件时才跑主流程：自检会 `import` 它来核假仓库，
// 那时不能因为真仓库绿了就 `process.exit(0)` —— 那会让自检静默地什么都没验。
function main() {
  if (process.argv.includes('--selftest')) {
    selftest();
    return;
  }
  const rootArg = process.argv.find((a) => a.startsWith('--root='));
  const { problems, facts } = inspect(rootArg ? rootArg.slice('--root='.length) : ROOT);
  console.log('RepDB 动作插图核对（许可证义务）\n');
  for (const f of facts) console.log(`  ${f}`);
  if (problems.length) {
    console.log('');
    for (const prob of problems) console.error(`  \x1b[31m✗\x1b[0m ${prob}`);
    console.error(`\n✗ ${problems.length} 处不对 —— 这些图是别人授权的，条件必须逐条成立`);
    process.exit(1);
  }
  console.log('\n✓ 署名、许可原文、出处清单、资产边界、pubspec 声明都对得上');
}

if (process.argv[1] && import.meta.url === `file://${process.argv[1]}`) main();
