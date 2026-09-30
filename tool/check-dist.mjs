#!/usr/bin/env node
/**
 * 练了么 · 交付目录核对（`dist/` 里放着要交出去的东西，别让它骗人）
 *
 * **它为什么存在**：`dist/` 是**生成物**（.gitignore 掉、不进仓库），但它是**交付口** ——
 * 真机安装用那个 APK、商店上传用那个 AAB、软著提交用那些 PDF。而生成物最容易出的一类事故是
 * **"留着上一版的"**：切版重出之后，旧文件还在同一个目录里，交的时候随手挑一个就拿错了。
 * 2026-09-30 真的发生过两次：`dist/` 里躺着 V1.28.0 与 V1.31.0 两份软著 PDF；
 * 以及更早一次，`dist/练了么-v1.30.0.apk` 其实是**上一版**的包（构建失败被管道吞掉了）。
 *
 * 软著那半已经由 `tool/copyright-pdf.mjs --check-docs` 盯着（不许有非当前版本的 PDF）。
 * 这个工具补另外一半：**APK / AAB**。
 *
 * 它核三件事：
 *   1. **文件名与内容都得是当前版本**：`dist/` 里所有 APK/AAB 的版本必须等于
 *      `app/lib/core/app_info.dart` 的 `kAppVersion`；有别的版本 → 红（拿错的风险）；
 *   2. **当前这个 APK 真的是那个版本**：用 `aapt2 dump badging` 读**包内**的
 *      versionName / versionCode，与 `kAppVersion` + `pubspec.yaml` 的 build number 对齐
 *      （文件名可以改，包里的版本号改不了 —— 所以这条才是真证据）；
 *   3. **它是合法 APK**：badging 读不出来就红（曾经有过"文件在那儿、其实是坏的"）。
 *
 * ⚠️ **它的边界**：`dist/` 不存在时（干净克隆、CI）整个跳过 —— 那种环境本来就没有交付物，
 * 不是失败。而"有 APK 却读不了（找不到 aapt2）"**算失败**：那种"看着像核过了"的状态最危险。
 *
 * 用法：
 *   node tool/check-dist.mjs              # 核 dist/
 *   node tool/check-dist.mjs --selftest   # 自检（造几个假的 dist/，验它抓得住）
 *
 * 退出码：任何一项不符 → 1。
 */

import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** 版本真源：`app/lib/core/app_info.dart` 的 kAppVersion 与 pubspec 的 build number。 */
function expectations() {
  const info = readFileSync(join(ROOT, 'app/lib/core/app_info.dart'), 'utf8');
  const version = /kAppVersion\s*=\s*'([^']+)'/.exec(info)[1];
  const pubspec = readFileSync(join(ROOT, 'app/pubspec.yaml'), 'utf8');
  // `version: 1.32.0+41` 里的 41 就是 versionCode
  const buildNumber = /^version:\s*[\d.]+\+(\d+)/m.exec(pubspec)?.[1] ?? null;
  return { version, buildNumber };
}

/** 找 aapt2（安卓 build-tools 里那个）。找不到返回 null —— 调用方决定这算不算失败。 */
function findAapt2() {
  const sdk = process.env.ANDROID_SDK_ROOT || process.env.ANDROID_HOME
    || (() => {
      // 与 verify.sh 同一个口径：DEPS 的真源是 tool/dev-env.sh
      try {
        const dev = readFileSync(join(ROOT, 'tool/dev-env.sh'), 'utf8');
        const m = /^DEPS="([^"]+)"/m.exec(dev);
        return m ? join(m[1], 'android-sdk') : null;
      } catch { return null; }
    })();
  if (!sdk || !existsSync(join(sdk, 'build-tools'))) return null;
  const versions = readdirSync(join(sdk, 'build-tools')).sort().reverse();
  for (const v of versions) {
    const p = join(sdk, 'build-tools', v, 'aapt2');
    if (existsSync(p)) return p;
  }
  return null;
}

function inspect(root, { aapt2 = findAapt2() } = {}) {
  const problems = [];
  const facts = [];
  const dist = join(root, 'dist');
  const { version, buildNumber } = expectations();

  if (!existsSync(dist)) {
    facts.push('dist/ 不在（干净克隆或 CI 上正常）—— 没有交付物可核，跳过');
    return { problems, facts, skipped: true };
  }

  const files = readdirSync(dist);
  const apks = files.filter((f) => f.toLowerCase().endsWith('.apk'));
  const aabs = files.filter((f) => f.toLowerCase().endsWith('.aab'));

  // ── 1. 不许留别的版本
  for (const [kind, list] of [['APK', apks], ['AAB', aabs]]) {
    for (const f of list) {
      const m = /v?(\d+\.\d+\.\d+)/.exec(f);
      if (!m) {
        problems.push(`dist/${f} 的文件名里没有版本号 —— 交付目录里的东西必须一眼能看出是哪一版`);
      } else if (m[1] !== version) {
        problems.push(`dist/${f} 是 v${m[1]}，当前版本是 v${version} —— `
          + '交付目录里留着旧版本，就有"拿错一份"的风险（删掉或重出）');
      }
    }
  }
  facts.push(`dist/：APK ${apks.length} 个 · AAB ${aabs.length} 个 · 当前版本 v${version}+${buildNumber}`);

  // ── 2/3. 当前那个 APK 的包内版本必须对得上
  const current = apks.find((f) => f.includes(version));
  if (apks.length && !current) {
    problems.push(`dist/ 里没有 v${version} 的 APK —— 交付物不是当前版本`);
  }
  if (current) {
    const apkPath = join(dist, current);
    if (!aapt2) {
      problems.push(`有 ${current} 却找不到 aapt2，没法读包内版本 —— 这种"看着像核过了"的状态`
        + '最危险；装好安卓 build-tools 再跑，或说明为什么不能核');
    } else {
      let badging = '';
      try {
        badging = execFileSync(aapt2, ['dump', 'badging', apkPath], { encoding: 'utf8' });
      } catch (e) {
        problems.push(`aapt2 读不了 ${current}（${String(e.message).split('\n')[0]}）—— `
          + '文件在那儿但读不出来，说明它不是一个合法 APK（先前的"坏包"就是这么露出来的）');
      }
      if (badging) {
        const vn = /versionName='([^']+)'/.exec(badging)?.[1];
        const vc = /versionCode='(\d+)'/.exec(badging)?.[1];
        if (vn !== version) {
          problems.push(`dist/${current} 包内的 versionName 是 ${vn}，应为 ${version} —— `
            + '文件名可以改，包里的版本号改不了，所以这条才是真证据');
        }
        if (buildNumber && vc !== buildNumber) {
          problems.push(`dist/${current} 包内的 versionCode 是 ${vc}，pubspec 的 build number 是 ${buildNumber}`);
        }
        const pkg = /package: name='([^']+)'/.exec(badging)?.[1];
        facts.push(`${current}：包内 ${pkg} · ${vn} (${vc})`);
      }
    }
  }

  return { problems, facts, skipped: false };
}

// ───────────────────────────────────────────────────────────── 自检
function selftest() {
  const makeTree = (files) => {
    const root = mkdtempSync(join(tmpdir(), 'lianleme-dist-'));
    mkdirSync(join(root, 'dist'), { recursive: true });
    for (const [name, content] of Object.entries(files)) {
      writeFileSync(join(root, 'dist', name), content);
    }
    return root;
  };
  const { version } = expectations();

  const cases = [
    ['dist 不在 → 跳过（干净克隆/CI）', null, true, '跳过'],
    [`只有当前版本 APK（内容合法由真跑覆盖）→ 只报"读不出来"`, { [`练了么-v${version}.apk`]: 'PK\u0003\u0004not-a-real-apk' }, false, '读不了'],
    [`多个旧版本 APK → 必须报`, { [`练了么-v${version}.apk`]: 'PK', '练了么-v1.31.0.apk': 'PK' }, false, '就有"拿错一份"的风险'],
    ['文件名没有版本号 → 必须报', { 'lianleme.apk': 'PK' }, false, '没有版本号'],
    ['旧版本 AAB → 必须报', { 'app-release-v1.31.0.aab': 'PK' }, false, '就有"拿错一份"的风险'],
  ];

  let bad = 0;
  for (const [label, files, wantGreen, expect] of cases) {
    const root = files === null
      ? mkdtempSync(join(tmpdir(), 'lianleme-dist-none-'))
      : makeTree(files);
    // 自检里统一用一个"不存在的 aapt2"，把"读不出来"这条路固定下来
    const { problems } = inspect(root, { aapt2: files && Object.keys(files).some((f) => f.endsWith('.apk')) ? '/nonexistent/aapt2' : null });
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
  console.log('\n✓ 自检通过：交付目录里混进旧版本、文件名没版本号、包读不出来都藏不住');
}

// ───────────────────────────────────────────────────────────────── 跑
if (process.argv.includes('--selftest')) {
  selftest();
} else {
  const rootArg = process.argv.find((a) => a.startsWith('--root='));
  const { problems, facts, skipped } = inspect(rootArg ? rootArg.slice('--root='.length) : ROOT);
  console.log('交付目录核对（dist/）\n');
  for (const f of facts) console.log(`  ${f}`);
  if (problems.length) {
    console.log('');
    for (const p of problems) console.error(`  \x1b[31m✗\x1b[0m ${p}`);
    console.error(`\n✗ ${problems.length} 处不对 —— dist/ 是交付口，交出去之前先把它核干净`);
    process.exit(1);
  }
  console.log(skipped
    ? '\n✓ 没有交付物需要核（dist/ 不在）'
    : `\n✓ 交付目录里只有 v${expectations().version} 的东西，且包内版本与真源一致`);
}
