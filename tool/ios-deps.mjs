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
 *   * 没有 `plugin:` 段 → 纯 Dart 包，两端都能用（例如 `cryptography`）；
 *   * `flutter` / `flutter_test` / SDK 包 → 跳过。
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
  if (!isPlugin) return { name, verdict: 'pure', note: '纯 Dart 包（无 plugin 段）' };
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
  label = `${PUBSPEC.replace(ROOT + '/', '')} 的直接依赖`;
}

const results = targets.map((t) => ({ ...checkOne(t), dev: Boolean(t.dev) }));

console.log(`iOS 可用性核对　${label}\n`);
let bad = 0;
for (const r of results) {
  const mark =
    r.verdict === 'ios' || r.verdict === 'pure'
      ? '\x1b[32m✓\x1b[0m'
      : r.dev
        ? '\x1b[33m!\x1b[0m'
        : '\x1b[31m✗\x1b[0m';
  const devTag = r.dev ? '（dev，不打进包里）' : '';
  console.log(`  ${mark} ${r.name.padEnd(18)} ${r.note}${devTag}`);
  if (r.verdict !== 'ios' && r.verdict !== 'pure' && !r.dev) bad++;
}

if (bad) {
  console.error(`\n✗ ${bad} 个直接依赖不支持 iOS —— 「双端先上」会被它挡住。`);
  console.error('  要么换一个两端都支持的包，要么在 docs/release-admin.md 里写明 iOS 缺这个功能。');
  process.exit(1);
}
console.log('\n✓ 每个直接依赖都声明了 iOS 支持（或本来就是纯 Dart）');
console.log('  ⚠️ 这只证明"不可能性"被挡住了，不证明真的能编过 —— 那要 Xcode。');
