#!/usr/bin/env node
/**
 * 练了么 · 产物 ↔ 构建参数核对（**交付出去的那个包，到底是不是"变体 B"**）
 *
 * **它为什么存在**（`docs/feature-backlog.md` 第 13 项「政策 ↔ 商店表单 ↔ 产物的三边对账」）：
 * 政策与两张商店表单都已经按**变体 B**（配了服务器地址的正式包）写，而且这前两条腿各有守卫：
 *   * `tool/privacy-audit.mjs` —— 政策 ↔ 事实源 ↔ 代码；
 *   * `tool/check-store-forms.mjs` —— 事实源 ↔ Play 数据安全表 ↔ App Store 隐私标签；
 *   * 但**产品腿没有**：`tool/check-dist.mjs` 只核交付目录里的**版本号**。
 * 而"这个包到底配没配那两个地址"取决于**编译期 `--dart-define`**，
 * 它不在源码里、不在版本号里 —— 忘了带某一个，包就是一个用户装不到的形态，
 * 而商店表单仍按"会真的发送"填 → **申报不实**。
 *
 * 这不是假想：2026-10-06 真的先出过一个"云备份入口根本不出现"的包
 * （`docs/release-checklist.md` §9 自己写着"这一条**没有任何守卫**"）。所以现在把它变成守卫。
 *
 * **判据（真源尽量只有一处）**：
 *   1. **正式构建配方**从 `docs/release-checklist.md` §9 那段出包命令里读
 *      （`--dart-define=名字=http(s)://…`）—— 文档里的那几条就是"正式包必须带什么"，
 *      这里不另写一份地址；
 *   2. 配方自己要与事实源**同向**：`privacy-facts.json` 的
 *      `cloudBackup.enabledInDistributedBuild` 为 true ⇒ 配方里必须有云备份地址；
 *      为 false ⇒ 配方里不许还配着它（否则包与政策相反）。
 *      云备份地址存在时，`LIANLEME_BACKUP_DISCLOSED=true` 也必须在配方里
 *      （只给地址不给声明，入口不出现 —— 源码 `backup_config.dart` 的注释写着理由）；
 *   3. `dist/` 里**当前版本**的 APK（优先）或 AAB：每个 ABI 的 `libapp.so` 里必须真的
 *      含有配方里那些地址。缺一个 → 红（这个包就是变体 A，而表单/政策按变体 B 写）。
 *
 * **边界（如实写清）**：`LIANLEME_BACKUP_DISCLOSED` 是 `bool.fromEnvironment`，
 * 编译期就折成 true/false 常量、**键名不留在 AOT 产物里** —— 所以产物腿只能核"地址在不在"，
 * 核不了这个布尔开关；后者由配方那条检查兜着（配方缺它就是红）。
 * 干净克隆 / CI 上没有 `dist/` → 跳过（不是失败：那种环境本来就没有交付物可核）。
 *
 * 用法：
 *   node tool/check-dist-variant.mjs              # 核 dist/ 里当前版本的包（没有就跳过）
 *   node tool/check-dist-variant.mjs --selftest   # 自检（造几个假包/假配方，验它抓得住）
 *
 * 退出码：配方与事实源不一致、或产物里缺地址 → 1。
 */

import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const CHECKLIST = 'docs/release-checklist.md';
const APP_INFO = 'app/lib/core/app_info.dart';
const FACTS = 'docs/privacy-facts.json';
/** 与 `tool/check-aab.mjs` 的 REQUIRED_ABIS 同一份口径（release-checklist §9 也逐个点名）。 */
const REQUIRED_ABIS = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];

/** 从 release-checklist 里读正式构建配方（`--dart-define=名字=值`）。 */
function readRecipe(root) {
  const text = readFileSync(join(root, CHECKLIST), 'utf8');
  const defines = new Map();
  for (const m of text.matchAll(/--dart-define=([A-Z][A-Z0-9_]*)=([^\s\\]+)/g)) {
    defines.set(m[1], m[2]);
  }
  return defines;
}

/**
 * 只保留**地址类** define：值必须是纯 ASCII 的 http(s) 链接。
 * 文档里还有示例写法（`https://你的域名`）与布尔开关（`...=true`），它们都不是"地址"。
 */
function addressDefines(defines) {
  return [...defines.entries()]
    .filter(([, v]) => /^https?:\/\/[\x21-\x7e]+$/.test(v))
    .map(([name, url]) => ({ name, url }));
}

/** 当前版本的交付物：dist/ 里文件名带 `kAppVersion` 的 APK（优先）/ AAB。 */
function currentArtifact(root) {
  const dist = join(root, 'dist');
  if (!existsSync(dist)) return { skipped: 'dist/ 不在（干净克隆或 CI 上正常）—— 没有交付物可核' };
  let version;
  try {
    version = /kAppVersion\s*=\s*'([^']+)'/.exec(readFileSync(join(root, APP_INFO), 'utf8'))?.[1];
  } catch { /* 下面报 */ }
  if (!version) return { error: `读不到 ${APP_INFO} 的 kAppVersion —— 版本真源没了，这条检查已经失效` };
  const files = readdirSync(dist);
  const apk = files.find((f) => f.toLowerCase().endsWith('.apk') && f.includes(version));
  const aab = files.find((f) => f.toLowerCase().endsWith('.aab') && f.includes(version));
  if (!apk && !aab) {
    return { skipped: `dist/ 里没有 v${version} 的 APK/AAB —— 出包之前这条没有对象可核` };
  }
  return { version, apk: apk && join(dist, apk), aab: aab && join(dist, aab) };
}

/** 从 zip 里取一个条目（`.apk` / `.aab` 都是 zip；`unzip -p` 只解压这一个条目）。 */
function readEntryFromZip(zipPath, entry) {
  try {
    return execFileSync('unzip', ['-p', zipPath, entry], { maxBuffer: 256 * 1024 * 1024 });
  } catch {
    return null;
  }
}

function inspect(root, { readEntry = readEntryFromZip } = {}) {
  const problems = [];
  const facts = [];

  // ── ① 正式构建配方（真源 = release-checklist 那段出包命令）
  let recipe;
  try {
    recipe = readRecipe(root);
  } catch (e) {
    return { problems: [`读不了 ${CHECKLIST}：${e.message}`], facts };
  }
  const has = (name) => recipe.has(name);
  const urls = addressDefines(recipe);
  if (!urls.length) {
    problems.push(`${CHECKLIST} 里解析不到「--dart-define=名字=http(s)://…」—— `
      + '出包命令的写法变了？这条检查已经失效，别当成通过');
  }

  // ── ② 配方必须与事实源同向（否则"配方出的包"与"政策/表单"从源头就相反）
  let pf;
  try {
    pf = JSON.parse(readFileSync(join(root, FACTS), 'utf8'));
  } catch (e) {
    return { problems: [`读不了 ${FACTS}：${e.message}`], facts };
  }
  const backupEnabled = pf.cloudBackup?.enabledInDistributedBuild;
  if (typeof backupEnabled !== 'boolean') {
    problems.push(`${FACTS} 的 cloudBackup.enabledInDistributedBuild 读不到 —— 这条检查已经失效`);
  } else if (backupEnabled && !has('LIANLEME_BACKUP_URL')) {
    problems.push(`事实源说这一版**云备份已启用**，但 ${CHECKLIST} 的正式出包命令里没有 `
      + '`--dart-define=LIANLEME_BACKUP_URL=…` —— 这样一个包不会出现云备份入口，'
      + '而政策与商店表单按"有云备份"写');
  } else if (!backupEnabled && has('LIANLEME_BACKUP_URL')) {
    problems.push(`事实源说这一版**云备份未启用**，但 ${CHECKLIST} 的正式出包命令里还配着 `
      + '`LIANLEME_BACKUP_URL` —— 包会把入口放出来，而政策写着"本版本未提供云备份"');
  }
  if (backupEnabled && has('LIANLEME_BACKUP_URL') && recipe.get('LIANLEME_BACKUP_DISCLOSED') !== 'true') {
    problems.push(`${CHECKLIST} 的正式出包命令只给了云备份地址、没给 `
      + '`--dart-define=LIANLEME_BACKUP_DISCLOSED=true` —— 只给地址的包会让入口出现而政策没改；'
      + '源码 `backup_config.dart` 就要求这两个一起给（缺一个就不算配）');
  }
  // 统计地址：正式包从 v1.43.0 起就配了（`store-listing-ios.md` 与数据安全表都按"会真的发送"填）。
  if (!has('LIANLEME_ANALYTICS_URL')) {
    problems.push(`${CHECKLIST} 的正式出包命令里没有「--dart-define=LIANLEME_ANALYTICS_URL=…」—— `
      + '而两张商店表单与政策都按"统计会真的发送"写；要么把地址加回去，要么先改表单与政策');
  }
  facts.push(`正式构建配方：${[...recipe.keys()].join(' / ')}`);

  // ── ③ 产物腿：dist/ 里当前版本的包里，每个 ABI 的 libapp.so 都要真的带上那些地址
  const art = currentArtifact(root);
  if (art.skipped) { facts.push(art.skipped); return { problems, facts, skipped: true }; }
  if (art.error) { problems.push(art.error); return { problems, facts }; }
  const target = art.apk
    ? { path: art.apk, prefix: 'lib/', kind: 'APK' }
    : { path: art.aab, prefix: 'base/lib/', kind: 'AAB' };
  facts.push(`核产物：${target.path.replace(`${root}/`, '')}（当前版本 v${art.version}，${target.kind}）`);

  let checkedAbis = 0;
  for (const abi of REQUIRED_ABIS) {
    const entry = `${target.prefix}${abi}/libapp.so`;
    const buf = readEntry(target.path, entry);
    if (!buf || !buf.length) {
      problems.push(`${target.path.replace(`${root}/`, '')} 里读不到 ${entry} —— `
        + '缺这个 ABI 的包装到对应机型上会崩（或这不是一个合法包），先重出再核');
      continue;
    }
    checkedAbis += 1;
    let hits = 0;
    for (const { name, url } of urls) {
      const count = buf.toString('latin1').split(url).length - 1;
      if (count > 0) { hits += 1; continue; }
      problems.push(`${target.path.replace(`${root}/`, '')} 的 ${abi}/libapp.so 里**没有** `
        + `\`${name}=${url}\` —— 出包时漏了这个 --dart-define：这个包就是"变体 A"，`
        + '而商店表单与政策是按变体 B 写的（申报不实，审核当天才会疼）');
    }
    if (hits === urls.length) {
      facts.push(`${abi}：${hits}/${urls.length} 条地址都在`);
    }
  }
  if (!checkedAbis) {
    return { problems, facts };
  }

  return { problems, facts, skipped: false };
}

// ───────────────────────────────────────────────────────────── 自检
function selftest() {
  const VERSION = '9.9.9';
  // ⚠️ 地址从**真清单**里读，不在自检里抄一份：文档里的出包命令换了域名之后，
  // 这里应当跟着换，而不是让自检红在一个"夹具写死"的假原因上（本仓库踩过这种假红）。
  const URLS = addressDefines(readRecipe(ROOT)).map((x) => x.url);
  if (URLS.length < 2) throw new Error('自检夹具失效：release-checklist 里解析不到两条地址');

  const makeTree = ({ mutate, withDist = true } = {}) => {
    const root = mkdtempSync(join(tmpdir(), 'lianleme-dist-variant-'));
    mkdirSync(join(root, 'docs'), { recursive: true });
    mkdirSync(join(root, 'app/lib/core'), { recursive: true });
    writeFileSync(join(root, CHECKLIST), readFileSync(join(ROOT, CHECKLIST)));
    writeFileSync(join(root, FACTS), readFileSync(join(ROOT, FACTS)));
    writeFileSync(join(root, APP_INFO), `const String kAppVersion = '${VERSION}';\n`);
    if (withDist) {
      mkdirSync(join(root, 'dist'), { recursive: true });
      writeFileSync(join(root, 'dist', `练了么-v${VERSION}.apk`), 'PK');
    }
    if (mutate) mutate(root);
    return root;
  };
  /** 假包：每个 ABI 的 libapp.so = 两个地址拼起来的字节（跳过真实的 unzip）。 */
  const fakeEntries = ({ missing = [], abis = REQUIRED_ABIS, aab = false } = {}) => {
    const entries = new Map();
    for (const abi of abis) {
      if (missing.includes(abi)) continue;
      entries.set(`${aab ? 'base/lib/' : 'lib/'}${abi}/libapp.so`,
        Buffer.from(`xx ${URLS.join(' yy ')} zz`));
    }
    return (zipPath, entry) => entries.get(entry) ?? null;
  };
  const docEdit = (root, from, to) => {
    const p = join(root, CHECKLIST);
    const s = readFileSync(p, 'utf8');
    if (!s.includes(from)) throw new Error(`自检夹具失效：清单里没有「${from}」`);
    writeFileSync(p, s.split(from).join(to));
  };
  const factsEdit = (root, fn) => {
    const p = join(root, FACTS);
    const d = JSON.parse(readFileSync(p, 'utf8'));
    fn(d);
    writeFileSync(p, JSON.stringify(d, null, 2));
  };

  const cases = [
    ['dist/ 不在 → 跳过（干净克隆/CI）', { withDist: false }, true, '没有交付物可核'],
    ['配方与事实源一致、包带全两条地址 → 绿', {}, true, null],
    ['某个 ABI 少了统计地址（出包漏了 --dart-define）→ 必须报', {}, false, '没有',
      { missing: [] , entriesFor: 'dropAnalytics' }],
    ['某个 ABI 的 libapp.so 根本不在（缺 ABI / 坏包）→ 必须报', {}, false, '读不到',
      { entriesFor: 'missingAbi' }],
    ['整个包是变体 A（两个地址都没有）→ 必须报', {}, false, '变体 A', { entriesFor: 'noUrls' }],
    ['正式出包命令里漏了统计地址 → 必须报（表单还按"会发送"填）',
      { mutate: (r) => docEdit(r, '--dart-define=LIANLEME_ANALYTICS_URL=', '--dart-define=LIANLEME_ANALYTICS_URL_X=') },
      false, 'LIANLEME_ANALYTICS_URL'],
    ['事实源说云备份未启用，配方里却还配着地址 → 必须报',
      { mutate: (r) => factsEdit(r, (d) => { d.cloudBackup.enabledInDistributedBuild = false; }) },
      false, '云备份未启用'],
    ['配方只给云备份地址、没给 DISCLOSED → 必须报',
      { mutate: (r) => docEdit(r, '--dart-define=LIANLEME_BACKUP_DISCLOSED=true', '') },
      false, 'LIANLEME_BACKUP_DISCLOSED'],
    ['没有 APK、只有当前版本 AAB，条目路径是 base/lib/… → 绿', { mutate: (r) => {
      rmSync(join(r, 'dist', `练了么-v${VERSION}.apk`));
      writeFileSync(join(r, 'dist', `练了么-v${VERSION}.aab`), 'PK');
    } }, true, null, { aab: true }],
  ];

  let bad = 0;
  for (const [label, treeOpts, wantGreen, expect, readOpts = {}] of cases) {
    const root = makeTree(treeOpts);
    let readEntry;
    if (readOpts.entriesFor === 'noUrls') {
      // 条目在、但里面没有任何地址（= 出包时一个 define 都没带出来的"变体 A"包）
      readEntry = () => Buffer.from('nothing here');
    } else if (readOpts.entriesFor === 'none') {
      readEntry = () => null;
    } else if (readOpts.entriesFor === 'missingAbi') {
      readEntry = fakeEntries({ missing: ['armeabi-v7a'], aab: !!readOpts.aab });
    } else if (readOpts.entriesFor === 'dropAnalytics') {
      const orig = fakeEntries({ aab: !!readOpts.aab });
      readEntry = (p, e) => {
        const b = orig(p, e);
        return b ? Buffer.from(b.toString('latin1').replace(URLS[1], 'XX')) : null;
      };
    } else {
      readEntry = fakeEntries({ aab: !!readOpts.aab });
    }
    const { problems, facts } = inspect(root, { readEntry });
    const green = problems.length === 0;
    let ok = green === wantGreen;
    let why = green ? '' : `　→ ${problems[0].slice(0, 70)}`;
    if (ok && !wantGreen && expect) {
      const hit = problems.some((p) => p.includes(expect)) || facts.some((f) => f.includes(expect));
      if (!hit) {
        ok = false;
        why = `　→ 红了，但不是因为「${expect}」（红在：${problems[0]?.slice(0, 48) ?? '（没红）'}）`;
      }
    }
    if (!ok) bad += 1;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}${why}`);
    rmSync(root, { recursive: true, force: true });
  }
  if (bad) {
    console.error(`\n✗ 自检失败 ${bad} 项 —— 这个工具本身不可信，先修它`);
    process.exit(1);
  }
  console.log('\n✓ 自检通过：出包漏地址（整个包变体 A / 某个 ABI / 单条地址）、'
    + '缺 ABI、配方漏项、配方与事实源相反都藏不住；dist/ 不在时如实跳过');
}

// ───────────────────────────────────────────────────────────────── 跑
if (process.argv.includes('--selftest')) {
  selftest();
} else {
  const rootArg = process.argv.find((a) => a.startsWith('--root='));
  const { problems, facts, skipped } = inspect(rootArg ? rootArg.slice('--root='.length) : ROOT);
  console.log('产物 ↔ 构建参数核对（正式包里到底有没有那两个 --dart-define 地址）\n');
  for (const f of facts) console.log(`  ${f}`);
  if (problems.length) {
    console.log('');
    for (const p of problems) console.error(`  \x1b[31m✗\x1b[0m ${p}`);
    console.error(`\n✗ ${problems.length} 处对不上 —— 这个包与政策/商店表单说的不是同一形态，别交出去`);
    process.exit(1);
  }
  console.log(skipped
    ? '\n✓ 这次没有交付物可核（dist/ 或当前版本的包不在）；出包后这条才真的有对象'
    : '\n✓ 正式包确实带着配方里那两条地址（每个 ABI 都在）');
}
