#!/usr/bin/env node
/**
 * 练了么 · iOS 可用性：每个直接依赖都得能在 iOS 上跑
 *
 * **为什么单独一条**：这个项目的目标是「双端先上」，但**没有任何东西会拦住**
 * "顺手加一个只有 Android 实现的插件" —— 它在本机（只有安卓真机）上完全正常，
 * 等到装上 Xcode 才发现 iOS 编译不过，而那时已经过去很久、也忘了是谁加的。
 * 这类"一半平台"的依赖在 pub.dev 上很常见（大量 `xxx_android` / 只有 android 平台的插件）。
 *
 * 判据（按 pubspec 声明，不看感觉）：
 *   * 有 `flutter: plugin: platforms:` → 必须同时声明 `ios` 或 `darwin` 之一；
 *   * 有 `hook/build.dart` → **原生资源包**（Dart hooks / code assets），
 *     hook 里必须能找到 iOS 目标（`OS.iOS` / `OS.macOS` / `'ios'` / `'macos'`）；
 *   * 没有 `plugin:` 段也没有 hook → 纯 Dart 包，两端都能用（例如 `cryptography`）；
 *   * `flutter` / `flutter_test` / SDK 包 → 跳过。
 *
 * **2026-09-30 补的第三类：Apple 隐私清单（PrivacyInfo.xcprivacy）**。
 * 苹果要求"用到 required-reason API 就要在清单里声明理由"，而且会对着**二进制**扫
 * （邮件 ITMS-91053/91054）。安卓侧完全看不到这件事 —— 典型的"另一个平台才会暴露"。
 * 所以凡是有 Apple 原生源码（.swift/.m/.mm）的**非 dev** 依赖，都必须自带清单；
 * 自带的例外要在这里**写明理由**（现在只有两个，都是上游确实没有、且已查清原因）。
 *
 * **2026-09-30 补的第二类（原版漏掉的）**：原版只读 `plugin: platforms:`，
 * 于是"没有 plugin 段"被一路当成"纯 Dart、两端都能用"。可 `package:sqlite3` 3.x
 * 恰恰没有 plugin 段 —— 它把原生库交给 `hook/build.dart` 现编/现下。
 * 它就是我们**唯一的数据库引擎**（经 `drift_flutter`），而且它是**传递依赖**，
 * 连直接依赖清单都不在。原版守卫对它完全瞎，一旦某个 hook 包只有 Android 分支，
 * 门禁照样全绿，等装完 Xcode 才发现 iOS 编不出来。
 * 所以现在：**闭包里所有 hook 包**都要有 iOS 证据（不只是直接依赖）。
 *
 * 用法：
 *   node tool/ios-deps.mjs                    # 核 app/pubspec.yaml 的直接依赖
 *   node tool/ios-deps.mjs --pkg-dir <目录>    # 只核一个包（诊断用；负向验证也靠它）
 *
 * 退出码：有依赖不支持 iOS → 1。
 *
 * ⚠️ 这个脚本**不能**替代"真的在 iOS 上构建一次"。它挡的是"根本不可能支持"的依赖，
 * 挡不住"声明支持但实际编不过"的情况 —— 后者只有 Xcode 能给答案。
 */

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const APP = join(ROOT, 'app');
const PUBSPEC = join(APP, 'pubspec.yaml');

/** SDK 自带的包不算第三方依赖 */
const SKIP = new Set([
  'flutter',
  'flutter_test',
  'flutter_localizations',
  'flutter_web_plugins',
  'integration_test',
  'sky_engine',
]);

/** 从 pubspec 里抠出某个顶层段落（`dependencies:` / `dev_dependencies:`）下的两空格缩进包名 */
function packagesIn(text, section) {
  const lines = text.split('\n');
  const start = lines.findIndex((l) => l.startsWith(`${section}:`));
  if (start < 0) return [];
  const out = [];
  for (let i = start + 1; i < lines.length; i++) {
    const line = lines[i];
    if (line.trim() === '' || line.trimStart().startsWith('#')) continue;
    if (!/^\s/.test(line)) break; // 回到顶层，段落结束
    const m = line.match(/^ {2}([a-z0-9_]+):/);
    if (m) out.push(m[1]);
  }
  return out;
}

/** 这个包的 pubspec 声明了哪些平台（从 `flutter: plugin: platforms:` 里读） */
function declaredPlatforms(pkgDir) {
  const file = join(pkgDir, 'pubspec.yaml');
  if (!existsSync(file)) return { platforms: null, isPlugin: null };
  const text = readFileSync(file, 'utf8');
  const lines = text.split('\n');

  const platIdx = lines.findIndex((l) => /^\s*platforms:\s*$/.test(l));
  // `platforms:` 也可能出现在别的段落里（例如 flutter.hooks），所以要求它缩进更深、
  // 且上面能找到 plugin: —— 免得把无关的 platforms 当成插件平台声明。
  const pluginIdx = lines.findIndex((l) => /^\s*plugin:\s*$/.test(l));
  if (platIdx < 0 || pluginIdx < 0) {
    return { platforms: [], isPlugin: pluginIdx >= 0 };
  }

  const baseIndent = lines[platIdx].match(/^\s*/)[0].length;
  const platforms = [];
  for (let i = platIdx + 1; i < lines.length; i++) {
    const line = lines[i];
    if (line.trim() === '' || line.trimStart().startsWith('#')) continue;
    const indent = line.match(/^\s*/)[0].length;
    if (indent <= baseIndent) break;
    const m = line.match(/^\s*([a-z_]+):/);
    if (m) platforms.push(m[1]);
  }
  return { platforms, isPlugin: true };
}

/** 原生资源包：`hook/build.dart`（Dart hooks）—— 它在构建时产出原生库 */
function isNativeAssetPackage(dir) {
  return existsSync(join(dir, 'hook', 'build.dart'));
}

/** hook 目录里所有 Dart 源码拼起来（递归，层数不多） */
function hookSource(dir) {
  const hookDir = join(dir, 'hook');
  if (!existsSync(hookDir)) return '';
  const parts = [];
  const walk = (d, depth) => {
    if (depth > 4) return;
    for (const e of readdirSync(d, { withFileTypes: true })) {
      const full = join(d, e.name);
      if (e.isDirectory()) walk(full, depth + 1);
      else if (e.name.endsWith('.dart')) parts.push(readFileSync(full, 'utf8'));
    }
  };
  walk(hookDir, 0);
  return parts.join('\n');
}

/** hook 里能不能找到 iOS 目标 —— 找不到就是"这个包只会给 Android 造原生库" */
function hookMentionsIos(dir) {
  const src = hookSource(dir);
  // `OS.iOS` / `OS.macOS`（code_assets 的枚举）或字符串形式的 'ios' / 'macos'
  return /OS\.(iOS|macOS)\b|['"](ios|macos)['"]/.test(src);
}

/** 包里有没有 Apple 原生源码（.swift/.m/.mm），排除 example/test/tool —— 那些不进包 */
function appleNativeSources(dir) {
  const out = [];
  const skipDirs = new Set(['example', 'test', 'tool', 'build', '.dart_tool', 'Pods']);
  const walk = (d, depth) => {
    if (depth > 6) return;
    let entries;
    try {
      entries = readdirSync(d, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      const full = join(d, e.name);
      if (e.isDirectory()) {
        if (!skipDirs.has(e.name)) walk(full, depth + 1);
      } else if (/\.(swift|m|mm)$/.test(e.name)) {
        out.push(full);
      }
    }
  };
  walk(dir, 0);
  return out;
}

/** 包里有没有苹果隐私清单（放哪儿都行，只要不带 example/） */
function privacyManifest(dir) {
  let found = null;
  const walk = (d, depth) => {
    if (depth > 6 || found) return;
    let entries;
    try {
      entries = readdirSync(d, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      if (found) return;
      if (e.isDirectory()) {
        if (e.name !== 'example' && e.name !== 'build' && e.name !== '.dart_tool') {
          walk(join(d, e.name), depth + 1);
        }
      } else if (e.name === 'PrivacyInfo.xcprivacy') {
        found = join(d, e.name);
      }
    }
  };
  walk(dir, 0);
  return found;
}

/**
 * 明知上游不带清单、但我们**查清过原因**的例外。
 * 每条都必须写清"为什么可以不带"；一旦上游补了清单，这个表会被下面的检查逼着删掉。
 */
const MANIFEST_EXCEPTIONS = new Map([
  ['objective_c',
    'Apple 侧是 ObjC 运行时桥（src/*.m，经 hook 编进包），上游不带隐私清单 —— '
    + '它只碰 objc 运行时，不碰 UserDefaults/文件时间戳/磁盘空间/开机时间这些 required-reason API；'
    + '兜底方案见 docs/release-admin.md §二之四（首次上传若收到 ITMS-91053 就加 app 级清单）'],
]);

/** 从 .dart_tool/package_config.json 找到某个包在磁盘上的位置 */
function resolvePackages(names) {
  const cfgPath = join(APP, '.dart_tool/package_config.json');
  if (!existsSync(cfgPath)) {
    throw new Error(`没有 ${cfgPath} —— 先跑一次 flutter pub get`);
  }
  const cfg = JSON.parse(readFileSync(cfgPath, 'utf8'));
  const byName = new Map(
    cfg.packages.map((p) => [
      p.name,
      p.rootUri.startsWith('file://')
        ? decodeURIComponent(p.rootUri.slice(7))
        : resolve(APP, p.rootUri),
    ]),
  );
  return names.map((n) => ({ name: n, dir: byName.get(n) ?? null }));
}

function checkOne({ name, dir }) {
  if (!dir) return { name, verdict: 'missing', note: 'package_config 里找不到（先 pub get）' };
  const { platforms, isPlugin } = declaredPlatforms(dir);
  if (platforms === null) return { name, verdict: 'missing', note: '读不到 pubspec.yaml' };
  if (!isPlugin) {
    if (isNativeAssetPackage(dir)) {
      const ios = hookMentionsIos(dir);
      return {
        name,
        verdict: ios ? 'native-ios' : 'native-android-only',
        note: ios
          ? '原生资源包（hook/build.dart），hook 里有 iOS 目标'
          : '原生资源包（hook/build.dart），但 hook 里**看不到 iOS 目标**',
      };
    }
    return { name, verdict: 'pure', note: '纯 Dart 包（无 plugin 段、无 hook）' };
  }
  const ios = platforms.includes('ios') || platforms.includes('darwin');
  return {
    name,
    verdict: ios ? 'ios' : 'android-only',
    note: platforms.length ? platforms.join(' / ') : '(没有声明任何平台)',
  };
}

// ---------------------------------------------------------------- 跑
const argv = process.argv.slice(2);
const pkgDirArg = argv.indexOf('--pkg-dir');

/** 闭包里所有"会产出原生代码"的包（原生资源包优先，因为它们没有联邦插件兜底） */
function nativeAssetClosure() {
  const cfgPath = join(APP, '.dart_tool/package_config.json');
  if (!existsSync(cfgPath)) return [];
  const cfg = JSON.parse(readFileSync(cfgPath, 'utf8'));
  const out = [];
  for (const p of cfg.packages) {
    if (SKIP.has(p.name)) continue;
    const dir = p.rootUri.startsWith('file://')
      ? decodeURIComponent(p.rootUri.slice(7))
      : resolve(APP, p.rootUri);
    if (isNativeAssetPackage(dir)) out.push({ name: p.name, dir });
  }
  return out;
}

let targets;
let label;
if (pkgDirArg >= 0) {
  const dir = argv[pkgDirArg + 1];
  if (!dir) {
    console.error('✗ --pkg-dir 后面要给一个目录');
    process.exit(1);
  }
  targets = [{ name: dir, dir }];
  label = `只核一个包：${dir}`;
} else {
  const text = readFileSync(PUBSPEC, 'utf8');
  const deps = packagesIn(text, 'dependencies').filter((n) => !SKIP.has(n));
  const devDeps = packagesIn(text, 'dev_dependencies').filter((n) => !SKIP.has(n));
  // dev 依赖不打进包里，所以只报告不拦（integration_test 就是这种）
  targets = [...resolvePackages(deps), ...resolvePackages(devDeps).map((t) => ({ ...t, dev: true }))];
  // 闭包里的原生资源包**也**要核：它们不在直接依赖清单里（sqlite3 就是这样），
  // 却是真正会把原生库编进包里的那些。标 transitive 只为在报告里区分来源。
  const direct = new Set(targets.map((t) => t.name));
  targets = [
    ...targets,
    ...nativeAssetClosure().filter((t) => !direct.has(t.name)).map((t) => ({ ...t, transitive: true })),
  ];
  label = `${PUBSPEC.replace(ROOT + '/', '')} 的直接依赖 + 闭包里的原生资源包`;
}

const results = targets.map((t) => ({ ...checkOne(t), dev: Boolean(t.dev), transitive: Boolean(t.transitive) }));

// ── 第三类：Apple 隐私清单 ────────────────────────────────────────────────
// 只查会打进包里的（跳过 dev）且真的有 Apple 原生源码的包。
const manifestRows = [];
const manifestProblems = [];
for (const t of targets) {
  if (t.dev || !t.dir) continue;
  const sources = appleNativeSources(t.dir);
  if (!sources.length) continue;
  const manifest = privacyManifest(t.dir);
  const exception = MANIFEST_EXCEPTIONS.get(t.name);
  manifestRows.push({
    name: t.name,
    sources: sources.length,
    manifest,
    exception,
    ok: Boolean(manifest) || Boolean(exception),
    // 例外过期：上游补了清单，我们这条例外就该删掉（否则表会烂成谎话）
    staleException: Boolean(manifest) && Boolean(exception),
  });
}

console.log(`iOS 可用性核对　${label}\n`);
let bad = 0;
for (const r of results) {
  const okVerdict = r.verdict === 'ios' || r.verdict === 'pure' || r.verdict === 'native-ios';
  const mark = okVerdict ? '\x1b[32m✓\x1b[0m' : r.dev ? '\x1b[33m!\x1b[0m' : '\x1b[31m✗\x1b[0m';
  const tags = [r.dev ? '（dev，不打进包里）' : '', r.transitive ? '（传递依赖）' : ''].join('');
  console.log(`  ${mark} ${r.name.padEnd(18)} ${r.note}${tags}`);
  // 原生资源包即使来自传递依赖也要拦：它没有联邦插件的兜底实现
  if (!okVerdict && (!r.dev || r.verdict === 'native-android-only')) bad++;
}

// 隐私清单单独一张小表：Android 侧永远看不到这件事
if (manifestRows.length) {
  console.log('\nApple 隐私清单（PrivacyInfo.xcprivacy）');
  for (const r of manifestRows) {
    if (r.staleException) {
      manifestProblems.push(`${r.name} 已经自带隐私清单了 —— 请把 tool/ios-deps.mjs`
        + ' 里那条例外删掉（留着就是一句过期的话）：MANIFEST_EXCEPTIONS');
    }
    const mark = r.ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m';
    const how = r.manifest ? '自带清单' : (r.exception ? '例外（已写明理由）' : '**没有清单**');
    console.log(`  ${mark} ${r.name.padEnd(18)} ${String(r.sources).padStart(2)} 个 Apple 原生源文件 · ${how}`);
    if (!r.ok) {
      manifestProblems.push(`${r.name} 有 ${r.sources} 个 Apple 原生源文件，`
        + '却不带 Apple 隐私清单 —— 苹果会对着二进制扫 required-reason API'
        + '（ITMS-91053/91054）。要么换依赖，要么在 tool/ios-deps.mjs 的 '
        + 'MANIFEST_EXCEPTIONS 里写清为什么可以不带');
    }
  }
}

for (const msg of manifestProblems) {
  console.error(`  \x1b[31m✗\x1b[0m ${msg}`);
  bad++;
}

if (bad) {
  console.error(`\n✗ ${bad} 个依赖不支持 iOS —— 「双端先上」会被它挡住。`
    + '（含闭包里"只给 Android 造原生库"的原生资源包，以及 Apple 隐私清单缺失/例外过期）');
  console.error('  要么换一个两端都支持的包，要么在 docs/release-admin.md 里写明 iOS 缺这个功能。');
  process.exit(1);
}
console.log('\n✓ 每个直接依赖都声明了 iOS 支持（或本来就是纯 Dart），闭包里的原生资源包也都有 iOS 目标');
console.log('  ⚠️ 这只证明"不可能性"被挡住了，不证明真的能编过 —— 那要 Xcode。');
