#!/usr/bin/env node
/**
 * 练了么 · 文档里的路径**是不是真的存在**
 *
 * **它为什么存在**：文档里到处都是 `` `tool/xxx.mjs` ``、`` `app/lib/.../foo.dart` `` 这种引用，
 * 而它们会**悄悄指空**：文件改名、搬家、删掉之后，文档照样写着 —— 读者照着敲就是"文件不存在"。
 * 这类漂移没人会去逐个点一遍，而它已经发生过几次（工具改名、目录搬家、iOS 那条
 * `app/build/ios` 的引用……）。所以把它变成机械检查。
 *
 * 判据（写得偏保守，宁可漏报也不误报 —— 假阳性会让人把守卫关掉）：
 *   * 只看**行内代码**里、**含斜杠且有扩展名**的记号（`` `foo.dart` `` 这种裸文件名不算 ——
 *     它们在正文里是"提到某个文件"，不承诺路径）；
 *   * 依次在几个已知根下解析：仓库根、`app/`、`app/android/`、`app/ios/`、`server/`、
 *     `store-assets/`、`docs/`、`tool/`、`seed/`、`engine/`；
 *   * **跳过**：URL、绝对路径、`~`、`dist/` 与 `app/build/` 这类**构建产物目录**
 *     （它们本来就可能不存在，尤其干净克隆上），以及含占位符（`<`、`…`、`*`、`__`）的记号。
 *
 * 用法：
 *   node tool/check-doc-paths.mjs              # 扫 README + docs/*.md
 *   node tool/check-doc-paths.mjs --selftest   # 自检（造几个假的文档，验它抓得住）
 *
 * 退出码：任何一处指空 → 1。
 */

import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { allDocFiles } from './lib/docs.mjs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** 解析路径时依次尝试的根（文档里的相对路径习惯不同：有的从仓库根写，有的从 app/ 写）。 */
const ROOTS = [
  '', 'app', 'app/lib', 'app/test', 'app/tool', 'app/integration_test', 'app/assets',
  'app/android', 'app/android/app/src/main', 'app/ios', 'app/ios/Runner',
  'server', 'store-assets', 'docs', 'tool', 'seed', 'engine', '.github/workflows',
];

/**
 * **已知的"不在仓库里 / 只是条件性存在"的引用** —— 每条都得写清理由。
 *
 * 为什么要有这份名单而不是直接跳过：这些引用是**有意义的**（讲依赖内部结构、
 * 模拟器内部路径、或"走另一条路线时才会出现的文件"），只是它们本来就不该在仓库里。
 * 名单要求**写出理由**，这样下一个人看到时能判断它是否还成立。
 */
const NOT_OURS = [
  ['hook/build.dart', '依赖内部的 Dart Native Assets 钩子（sqlite3 / objective_c），不在我们仓库'],
  ['harness-deps/', '依赖目录在 SSD 上（`tool/dev-env.sh` 的 DEPS），不在仓库里'],
  ['data/Media/', 'iOS 模拟器内部的相册路径 —— 证据在哪，不在仓库'],
  ['ios/Podfile', '只有走 CocoaPods 路线才会出现的文件；本工程走 SPM，文档是在讲"那条路线会怎样"'],
  ['ios/Podfile.lock', '同上'],
  ['ios/Pods/', '同上'],
  ['Pods/Pods.xcodeproj', '同上（`pod install` 往工作区里加的那条引用）'],
  ['ios/Flutter/Debug.xcconfig', 'CocoaPods 路线下 Flutter 会改的文件，本工程没有'],
  ['ios/Flutter/Release.xcconfig', '同上'],
  ['ios/Flutter/AppFrameworkInfo.plist', '同上（CocoaPods 路线才会被写入 MinimumOSVersion）'],
  ['app/ios/Runner/PrivacyInfo.xcprivacy', '文档写的是"**如果**收到 ITMS-91053 才加"的文件，现在还没有'],
  ['bundle/release/app-release.aab', '构建产物路径（文档在讲构建输出在哪）'],
  // ⚠️ 2026-10-05：这两条是**CI 抓出来的**（本地一直绿，因为文件在本机真的存在）——
  // 签名密钥与口令故意不入库（见 `.gitignore`），所以干净克隆上一定找不到。
  // 判据本来就该是"文档指向的东西要么在仓库里、要么在下面这份名单里（并写明理由）"。
  ['app/android/upload-keystore.p12', '签名密钥，**故意不入库**（`.gitignore`）；只在开发机 + 密码管理器/离线介质里'],
  ['app/android/key.properties', '同上：Gradle 读的签名配置（含口令），故意不入库'],
  // ⚠️ 下面五条是**2026-10-05 在干净克隆里跑 `check-doc-paths` 才发现的**：
  // 它们在开发机上都存在（都是"跑过一次构建/同步之后就会有"的文件），
  // 所以本地怎么跑都绿 —— CI 一跑就红。这正是"干净克隆"这个动作的价值。
  ['app/android/local.properties', 'Flutter 生成的 SDK 路径文件，**不入库**；一次 `flutter build` 之后才会有'],
  ['app/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java',
    '构建时生成的插件注册码（跑过 `flutter build`/`flutter drive` 才有）'],
  ['app/ios/Flutter/Generated.xcconfig', '`flutter build ios` 生成的编译常量文件（不入库）'],
  ['Flutter/Generated.xcconfig', '同一个文件的另一种写法（文档从 `app/ios/` 出发写相对路径）'],
  // ⚠️ 2026-10-06：这三条是"同一个坑的另一面"—— 那两个文件**存在过、但里头的
  // `FLUTTER_ROOT` 是过期的**（指着已经搬走的 Flutter），所以 `dev-environment.md` 让读者
  // **删掉它们**再构建。既然是"让人删的文件"，干净克隆上当然没有 —— 名字得写进这份名单。
  ['app/ios/Flutter/flutter_export_environment.sh', '`flutter build ios` 生成（不入库）；文档在讲"删掉它让 flutter 重写"'],
  ['app/ios/Flutter/ephemeral/flutter_native_integration.env', '同上，ephemeral 里的生成物（整个 `ephemeral/` 都不入库）'],
  ['Flutter/flutter_export_environment.sh', '同一个文件的另一种写法（文档从 `app/ios/` 出发写相对路径）'],
  ['ephemeral/flutter_native_integration.env', '同上'],
  ['server/data/events-2026-09-29.jsonl', '本机收集端的运行时数据（`server/data/` 已 gitignore）；文档在讲"看板的数据从哪来"'],
];

/** 这些前缀是**构建产物**，不存在是正常的（尤其干净克隆上）。 */
const SKIP_PREFIX = ['dist/', 'app/build/', 'build/', 'bundle/', 'app/.dart_tool/', '.dart_tool/'];

const TOKEN = /`([A-Za-z0-9_./\-\u4e00-\u9fff]+\.[A-Za-z0-9]{2,12})`/g;

function inspect(root) {
  const problems = [];
  let checked = 0;
  const docs = allDocFiles(root);
  const exists = (p) => {
    try { readFileSync(join(root, p)); return true; } catch { return false; }
  };
  // 目录也要能"存在"，用 readdirSync 试
  const dirExists = (p) => {
    try { readdirSync(join(root, p)); return true; } catch { return false; }
  };

  for (const rel of docs) {
    let text;
    try { text = readFileSync(join(root, rel), 'utf8'); } catch { continue; }
    const lines = text.split('\n');
    lines.forEach((line, i) => {
      for (const m of line.matchAll(TOKEN)) {
        const tok = m[1];
        if (!tok.includes('/')) continue;                       // 裸文件名：不承诺路径
        if (tok.startsWith('/') || tok.startsWith('~') || tok.includes('://')) continue;
        if (/[<>*…]|__/.test(tok)) continue;                     // 占位符
        if (SKIP_PREFIX.some((p) => tok.startsWith(p))) continue;
        if (NOT_OURS.some(([pfx]) => tok.startsWith(pfx))) continue;
        checked += 1;
        const hit = ROOTS.some((r) => {
          const p = r ? `${r}/${tok}` : tok;
          return exists(p) || dirExists(p);
        });
        if (!hit) {
          problems.push(`${rel}:${i + 1} 写的 \`${tok}\` 在仓库里找不到（试过 ${ROOTS.length} 个根）—— `
            + '文档指向了一个不存在的文件（改过名/搬过家？）');
        }
      }
    });
  }
  return { problems, checked };
}

// ───────────────────────────────────────────────────────────── 自检
function selftest() {
  const makeTree = (docs, rootDoc) => {
    const root = mkdtempSync(join(tmpdir(), 'lianleme-docpaths-'));
    mkdirSync(join(root, 'docs'), { recursive: true });
    mkdirSync(join(root, 'tool'), { recursive: true });
    mkdirSync(join(root, 'app/lib'), { recursive: true });
    writeFileSync(join(root, 'tool/real-tool.mjs'), '// x');
    // 夹具里也要有"从 app/ 起算"能解到的文件，否则那条用例红在夹具缺文件上（假红）
    writeFileSync(join(root, 'app/lib/main.dart'), '// x');
    writeFileSync(join(root, 'README.md'), '# x\n');
    for (const [rel, text] of Object.entries(docs)) writeFileSync(join(root, rel), text);
    if (rootDoc) writeFileSync(join(root, 'ROADMAP.md'), rootDoc);
    return root;
  };
  const cases = [
    ['引用的文件真的在 → 绿', { 'docs/a.md': '见 `tool/real-tool.mjs`\n' }, true, null],
    ['引用的文件不在 → 必须报', { 'docs/a.md': '见 `tool/gone-tool.mjs`\n' }, false, '找不到'],
    ['裸文件名不算（正文里提到文件，不承诺路径）', { 'docs/a.md': '改 `db.dart` 那一行\n' }, true, null],
    ['构建产物不算（干净克隆上本来就没有）', { 'docs/a.md': '产物在 `dist/练了么-v1.0.0.apk`\n' }, true, null],
    ['占位符不算', { 'docs/a.md': '跑 `tool/<名字>.mjs`\n' }, true, null],
    ['带 URL 的不算', { 'docs/a.md': '见 `https://example.com/a.md`\n' }, true, null],
    ['从 app/ 起算的相对路径也算数', { 'docs/a.md': '见 `lib/main.dart`\n' }, true, null],
    ['名单里的"不在仓库"引用不算（依赖内部/模拟器内部）', { 'docs/a.md': '见 `hook/build.dart` 与 `data/Media/x.png`\n' }, true, null],
    ['名单没有正当理由就跳过 —— 名单本身是公开的（不是任意路径都能侥幸通过）',
      { 'docs/a.md': '见 `some/random/gone.dart`\n' }, false, '找不到'],
    // ★ 真实事故的回归：`ROADMAP.md` 里 `drift/native.dart` 指着依赖内部的文件
    //   （正确写法是 `package:drift/native.dart`）。根目录文档当时不在扫描范围内，
    //   所以这一处既没被发现、也没机会被纠正成更准确的写法。
    ['根目录 ROADMAP.md 里的指空路径 → 必须报', { 'docs/a.md': '# a\n' }, false, '找不到',
      '见 `tool/gone-in-roadmap.mjs`\n'],
  ];
  let bad = 0;
  for (const [label, docs, wantGreen, expect, rootDoc] of cases) {
    const root = makeTree(docs, rootDoc);
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
  console.log('\n✓ 自检通过：指空的路径藏不住；裸文件名、构建产物、占位符、URL 都不误报');
}

// ───────────────────────────────────────────────────────────────── 跑
if (process.argv.includes('--selftest')) {
  selftest();
} else {
  const rootArg = process.argv.find((a) => a.startsWith('--root='));
  const { problems, checked } = inspect(rootArg ? rootArg.slice('--root='.length) : ROOT);
  console.log('文档路径核对（README + docs/*.md）\n');
  console.log(`  核了 ${checked} 个带斜杠的路径引用`);
  if (problems.length) {
    console.log('');
    for (const p of problems) console.error(`  \x1b[31m✗\x1b[0m ${p}`);
    console.error(`\n✗ ${problems.length} 处指空 —— 读者照着文档敲，会得到"文件不存在"`);
    process.exit(1);
  }
  console.log('\n✓ 文档里引用的路径都真的存在');
}
