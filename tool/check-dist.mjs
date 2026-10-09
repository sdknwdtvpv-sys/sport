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
 * 它核四件事：
 *   1. **文件名与内容都得是当前版本**：`dist/` 里所有 APK/AAB 的版本必须等于
 *      `app/lib/core/app_info.dart` 的 `kAppVersion`；有别的版本 → 红（拿错的风险）；
 *   2. **当前这个 APK 真的是那个版本**：用 `aapt2 dump badging` 读**包内**的
 *      versionName / versionCode，与 `kAppVersion` + `pubspec.yaml` 的 build number 对齐
 *      （文件名可以改，包里的版本号改不了 —— 所以这条才是真证据）；
 *   3. **它是合法 APK**：badging 读不出来就红（曾经有过"文件在那儿、其实是坏的"）；
 *   4. **它不比源码旧**（2026-10-09 加，见下面那段注释）：`app/` 下真的会被打进包的那些东西
 *      只要比包新，就说明"改了 app/ 却没重出包"—— **同一版本号下也会发生**，而版本号一比看不出来。
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
import { findAapt2 } from './lib/android-sdk.mjs';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, utimesSync, writeFileSync } from 'node:fs';
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

  // ── 3. dist/ 里那个 AAB 交给 check-aab.mjs 深核一遍（它此前**从没在门禁里跑过**）
  //
  // 为什么放在这里：`check-aab.mjs` 需要一份**真的 AAB**，而"真的 AAB"就在 `dist/` 里
  // （干净克隆上没有 → 自然跳过）。不这么接的话，那个工具只在人想起来时被跑一次 ——
  // 而它核的是"能不能拿去商店"（骨架三件套 + 三 ABI + 版本号），正好是交付口这一环。
  const currentAab = aabs.find((f) => f.includes(version));
  if (currentAab && aapt2) {
    const p = join(dist, currentAab);
    try {
      const out = execFileSync(process.execPath,
        [join(ROOT, 'tool/check-aab.mjs'), p], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
      const last = out.trim().split('\n').slice(-1)[0];
      facts.push(`AAB 深核（check-aab.mjs）：${last.replace(/\u001b\[[0-9;]*m/g, '').trim()}`);
    } catch (e) {
      const detail = `${e.stdout ?? ''}${e.stderr ?? ''}`.trim().split('\n').slice(-1)[0];
      problems.push(`dist/${currentAab} 没通过 check-aab.mjs 的深核：${detail || e.message}`);
    }
  } else if (currentAab) {
    facts.push(`AAB（${currentAab}）没深核 —— 找不到 aapt2`);
  }

  // ── 4. 包**不比源码旧**（2026-10-09 加；这一条是真踩出来的）
  //
  // **踩到的那次**：01:32 切版编了 APK/AAB，之后在**同一个 1.65.0** 下又写了 Android 那一半
  // （Kotlin 桥 + manifest 三条权限）。版本号没变 → 上面 1/2/3 条全绿 → `dist/` 里躺着一个
  // **不含安卓那一半**的包，还被装进了真机。发现方式是手工 `aapt2 dump badging` 看权限。
  //
  // 判据（刻意只比"**真的会被打进这个包**"的东西，免得天天误报）：
  //   * **代码/配置**比 mtime：`app/lib/**.dart`（**排除生成的 `*.g.dart`** —— 它们每次 build_runner
  //     都会重写，比包新是常态）、`app/android/**`、`app/pubspec.yaml` / `pubspec.lock`；
  //   * **资产比内容**：`app/assets/**` 逐个与**包内那份**（`assets/flutter_assets/assets/...`）
  //     逐字节比。⚠️ 为什么不能比 mtime：`app/assets/exercises.json` 是 `seed/build.mjs` 生成的，
  //     而门禁**每次都跑它**（`verify.sh` 第 2 层）→ 每跑一次门禁它的 mtime 就被刷新一次，
  //     比 mtime 会**每次都红**（2026-10-09 加上这条守卫的当天就撞上了，正是这么发现的）；
  //     内容比对还能多抓一件事：政策文本改了却没重出包；
  //   * 不参与：文档、工具、测试与 `integration_test/`（不进 release 包）、`app/ios/**`
  //     （安卓包里没有 iOS 代码；iOS 产物由 `tool/check-ios-app.mjs` 那一路管）。
  //
  // 边界写清楚：**mtime 不是内容哈希**。`touch` 一下源码就会红一次（重出包即可，不算误报）；
  // 反过来，在**同一秒内**改源码再编包有可能漏掉 —— 这条查的是"忘了重出"，
  // 不是"内容一定一致"（那需要可复现构建，是另一件事）。
  if (current || currentAab) {
    const artifact = join(dist, current || currentAab);
    const artifactMtime = statSync(artifact).mtimeMs;
    const newest = { file: '', mtime: 0 };
    // ⚠️ 跳过**工具自己生成**的东西：它们在门禁里每次都会被重写，mtime 天然比包新 ——
    //    * `build/` `.dart_tool/` `.gradle/` `.cxx/`：构建产物；
    //    * `*.g.dart`：build_runner（drift）生成；
    //    * `GeneratedPluginRegistrant.java` / `local.properties`：
    //      `flutter pub get` 与 Flutter Gradle 插件自己写的（门禁第 3 层就跑 pub get）。
    //    这条清单是**照着"谁被工具重写过"**列的，不是凭印象 —— 2026-10-09 加这条守卫时，
    //    先是 exercises.json（seed 生成）把它们抓了个正着，改成内容比对之后，
    //    GeneratedPluginRegistrant.java 又来了一次，才把这张单子列全。
    const SKIP_DIRS = /(^|\/)(build|\.dart_tool|\.gradle|\.cxx|\.kotlin)(\/|$)/;
    const SKIP_NAMES = new Set([
      'local.properties',
      'GeneratedPluginRegistrant.java',
      'GeneratedPluginRegistrant.m',
      'GeneratedPluginRegistrant.h',
    ]);
    const walk = (dir) => {
      if (!existsSync(dir)) return;
      for (const entry of readdirSync(dir, { withFileTypes: true })) {
        const full = join(dir, entry.name);
        if (SKIP_DIRS.test(full)) continue;
        if (entry.isDirectory()) {
          walk(full);
        } else if (!entry.name.endsWith('.g.dart') && !SKIP_NAMES.has(entry.name)) {
          const m = statSync(full).mtimeMs;
          if (m > newest.mtime) {
            newest.file = full;
            newest.mtime = m;
          }
        }
      }
    };
    for (const rel of ['app/lib', 'app/android']) walk(join(root, rel));
    // ⚠️ **不把 `pubspec.lock` 算进来**：`flutter pub get` 每次都会重写它，
    // 而门禁第 3 层就跑 pub get —— 比 mtime 会每跑一次红一次（这是这条守卫的**第三个**
    // 同类假阳性，前两个是 seed 生成的 assets 与 flutter 生成的 GeneratedPluginRegistrant）。
    // 依赖真的变了的话，`pubspec.yaml` 一定也跟着变，那一头看着就够了。
    for (const rel of ['app/pubspec.yaml']) {
      const full = join(root, rel);
      if (existsSync(full) && statSync(full).mtimeMs > newest.mtime) {
        newest.file = full;
        newest.mtime = statSync(full).mtimeMs;
      }
    }
    if (newest.mtime > artifactMtime + 1000) {
      const mins = Math.round((newest.mtime - artifactMtime) / 60000);
      problems.push(`${current || currentAab} 比源码旧（${mins} 分钟）：`
        + `${newest.file.replace(`${root}/`, '')} 比它新 —— `
        + '**同一个版本号下改过 app/ 也必须重出包**，否则交付口躺着的是"少了半件事"的包'
        + '（2026-10-09 真发生过：包比 Android 那一半早，而版本号一比完全看不出来）');
    } else {
      facts.push(`产物不比源码旧（最新源码：${newest.file.replace(`${root}/`, '') || '（没有可比的文件）'}）`);
    }

    // 资产：与**包内那份**逐字节比（理由见上面那段 —— 比 mtime 会被 seed/build.mjs 刷新的时间戳骗到）
    if (current) {
      const assetsDir = join(root, 'app/assets');
      if (existsSync(assetsDir)) {
        const staleAssets = [];
        const compareAsset = (rel) => {
          const src = join(assetsDir, rel);
          const entry = `assets/flutter_assets/assets/${rel}`;
          let packed = null;
          try {
            packed = execFileSync('unzip', ['-p', join(dist, current), entry], { maxBuffer: 64 * 1024 * 1024 });
          } catch {
            packed = null;
          }
          if (packed === null) {
            staleAssets.push(`${rel}（包里根本没有这一项）`);
          } else if (!packed.equals(readFileSync(src))) {
            staleAssets.push(rel);
          }
        };
        const walkAssets = (dir, prefix) => {
          for (const entry of readdirSync(dir, { withFileTypes: true })) {
            const full = join(dir, entry.name);
            const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
            if (entry.isDirectory()) walkAssets(full, rel);
            else compareAsset(rel);
          }
        };
        walkAssets(assetsDir, '');
        if (staleAssets.length) {
          problems.push(`${current} 里的应用内资产与源码**不一致**：${staleAssets.slice(0, 3).join('、')}`
            + `${staleAssets.length > 3 ? ` 等 ${staleAssets.length} 项` : ''} —— `
            + '改了 `app/assets/` 就必须重出包（应用内政策/收集清单是商店要看的，包里那份才是用户真的读到的）');
        } else {
          facts.push('应用内资产与包内逐字节一致（政策 / 收集清单 / 动作库）');
        }
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
    // ⚠️ 2026-10-09：这一条是被真事逼出来的 —— 包比源码旧，而版本号一模一样。
    ['包比源码旧（同一版本号下改过 app/）→ 必须报',
      { [`练了么-v${version}.apk`]: 'PK' }, false, '比源码旧', 'stale-source'],
  ];

  let bad = 0;
  for (const [label, files, wantGreen, expect, kind] of cases) {
    const root = files === null
      ? mkdtempSync(join(tmpdir(), 'lianleme-dist-none-'))
      : makeTree(files);
    if (kind === 'stale-source') {
      // 造一个"源码比包新"的现场：把包的时间戳往回拨 5 分钟，再放一个刚写过的 lib 文件
      const past = new Date(Date.now() - 5 * 60 * 1000);
      utimesSync(join(root, 'dist', `练了么-v${version}.apk`), past, past);
      mkdirSync(join(root, 'app/lib'), { recursive: true });
      writeFileSync(join(root, 'app/lib/newer.dart'), '// 刚改过的源码\n');
    }
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
  console.log('\n✓ 自检通过：交付目录里混进旧版本、文件名没版本号、包读不出来、'
    + '包比源码旧都藏不住');
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
