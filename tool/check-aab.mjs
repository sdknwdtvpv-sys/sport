#!/usr/bin/env node
/**
 * 练了么 · 核一遍 .aab（商店用产物）
 *
 * **为什么需要这个**：`flutter build appbundle --release` 在当前这台机器上
 * **必然报一句假的失败**：
 *
 *     Release app bundle failed to strip debug symbols from native libraries.
 *
 * 而 .aab **其实已经正常产出了**。真相在 `-v` 的日志里：
 *
 *     executing: [.../android-sdk/cmdline-tools/latest/bin/apkanalyzer files list ...app-release.aab
 *     apkanalyzer: line 173: test: : integer expression expected
 *     错误: 找不到或无法加载主类 SSD.harness-deps.android-sdk.cmdline-tools.latest
 *     原因: java.lang.ClassNotFoundException: SSD.harness-deps.android-sdk.cmdline-tools.latest
 *
 * 根因：**SDD 的卷名里有一个空格**（`/Volumes/Elliot's SSD`），而
 * `apkanalyzer` 是个 shell 脚本，它把自己的位置拼进 classpath 时**没加引号** ——
 * 于是路径在空格处被劈开，Java 把 `SSD.harness-deps...` 当成类名。
 * flutter_tools 拿不到 apkanalyzer 的输出，就认定"没剥掉调试符号"。
 *
 * 于是"flutter 说失败了"和"产物到底能不能用"是两件事。这个脚本负责后者：
 * 它**不调用 flutter**，只拆开那个 .aab 检查里面的东西，然后拿它的版本号
 * 跟 `app/lib/core/app_info.dart` 对一遍（页眉版本号与申请表必须一致，见
 * `docs/copyright-manual.md`）。
 *
 * 用法：
 *   node tool/check-aab.mjs                      # 默认核 build/app/outputs/bundle/release/app-release.aab
 *   node tool/check-aab.mjs path/to/foo.aab
 *
 * 退出码：不对 → 1。
 */

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const DEFAULT_AAB = join(
  ROOT,
  'app/build/app/outputs/bundle/release/app-release.aab',
);

/** 期望覆盖的 ABI —— 与 `docs/release-checklist.md` 里"三 ABI 齐全"那句话对应 */
const REQUIRED_ABIS = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];

function listEntries(aab) {
  // `unzip -Z1` 只列条目名，一行一个，好解析
  try {
    return execFileSync('unzip', ['-Z1', aab], { encoding: 'utf8' })
      .split('\n')
      .map((s) => s.trim())
      .filter(Boolean);
  } catch (e) {
    throw new Error(`读不了这个 .aab（不是合法 zip？）：${e.message}`);
  }
}

function versionFromAppInfo() {
  const src = readFileSync(join(ROOT, 'app/lib/core/app_info.dart'), 'utf8');
  const m = src.match(/kAppVersion\s*=\s*'([^']+)'/);
  if (!m) throw new Error('app/lib/core/app_info.dart 里找不到 kAppVersion');
  return m[1];
}

/** 从 .aab 的 protobuf 版 AndroidManifest.xml 里抠版本号（字符串在 protobuf 里仍可读） */
function versionFromAab(aab) {
  let raw;
  try {
    raw = execFileSync('unzip', ['-p', aab, 'base/manifest/AndroidManifest.xml'], {
      encoding: 'buffer',
      maxBuffer: 32 * 1024 * 1024,
    });
  } catch {
    // 连 manifest 都取不出来 —— 上面 ① 那条会报"缺少 base/manifest/AndroidManifest.xml"，
    // 这里安静地返回空数组就行，别甩一段 unzip 的堆栈吓人。
    return [];
  }
  const text = raw.toString('latin1');
  // protobuf 把字符串连在一起，形如 com.pkg ... 1.22.0 ... 24
  const versions = [...text.matchAll(/\d+\.\d+\.\d+/g)].map((m) => m[0]);
  return versions;
}

// ---------------------------------------------------------------- 跑
const aab = process.argv[2] ?? DEFAULT_AAB;
if (!existsSync(aab)) {
  console.error(`✗ 找不到 .aab：${aab}`);
  console.error('  先跑：cd app && ORG_GRADLE_PROJECT_allowDebugSigning=true flutter build appbundle --release');
  process.exit(1);
}

const problems = [];
const entries = listEntries(aab);

// ① 骨架三件套：少了任何一个都不是可用的 Android App Bundle
for (const need of [
  'BundleConfig.pb',
  'base/manifest/AndroidManifest.xml',
  'base/dex/classes.dex',
]) {
  if (!entries.includes(need)) problems.push(`.aab 里没有 ${need}`);
}

// ② 三个 ABI 的原生库都要在（缺一个，对应机型装上就崩）
for (const abi of REQUIRED_ABIS) {
  for (const so of ['libsqlite3.so', 'libflutter.so', 'libapp.so']) {
    const want = `base/lib/${abi}/${so}`;
    if (!entries.includes(want)) problems.push(`.aab 里没有 ${want}`);
  }
}

// ③ 版本号必须与 app_info.dart 一致（页眉/申请表/仓库三处对齐）
const want = versionFromAppInfo();
const found = versionFromAab(aab);
if (!found.includes(want)) {
  problems.push(
    `.aab 里找不到版本号 ${want}（找到的是：${[...new Set(found)].join(' / ') || '一个都没有'}）`,
  );
}

const sizeMb = (readFileSync(aab).length / 1024 / 1024).toFixed(1);
console.log(`Android App Bundle 核对　${aab.replace(ROOT + '/', '')}\n`);
console.log(`  条目 ${entries.length} 个 · ${sizeMb} MB`);
console.log(`  ABI ${REQUIRED_ABIS.join(' / ')} 的原生库齐全`);
console.log(`  版本号 ${want}（与 app/lib/core/app_info.dart 一致）`);

if (problems.length) {
  console.error(`\n✗ ${problems.length} 处不对：`);
  for (const p of problems) console.error(`  · ${p}`);
  process.exit(1);
}
console.log('\n✓ 这个 .aab 是可用的商店产物（即使 flutter 那句"failed to strip"是假的）');
