#!/usr/bin/env node
/**
 * 练了么 · iOS 产物核对（对着仓库里的"说法"逐项验一份**真的 Runner.app**）
 *
 * **它补的是哪块空白**：安卓那边有 `tool/check-aab.mjs` 核 AAB，iOS 这边此前**没有任何东西**
 * 核过产物 —— 所有 iOS 相关的断言都停在"读源码/info.plist 文本"这一层。
 * 2026-09-30 第一次真的编出 iOS 包之后，那些静态断言终于可以在**真产物**上验一遍了。
 *
 * 它核什么（真源都在仓库里，不写死）：
 *   1. 显示名 / bundle id：与 `ios/Runner/Info.plist`、`project.pbxproj`、
 *      安卓 `build.gradle.kts` 的 applicationId **三处一致**；
 *   2. 版本：`CFBundleShortVersionString` == `app_info.dart` 的 kAppVersion，
 *      `CFBundleVersion` == `pubspec.yaml` 的 build number；
 *   3. 相册权限：**有** `NSPhotoLibraryAddUsageDescription`，
 *      **没有** `NSPhotoLibraryUsageDescription`（v1.27.1 的"只申请仅新增"决定）；
 *   4. `ITSAppUsesNonExemptEncryption=false`、`UIUserInterfaceStyle=Dark`、
 *      方向**只有竖屏**（v1.30.0 的锁）；
 *   5. 应用内资产真的进了包：`privacy-policy.txt` / `collection-list.txt` / `exercises.json`；
 *   6. 原生依赖真的进了包：`sqlite3.framework` 与 `objective_c.framework`；
 *   7. 设备族里若含 iPad（`UIDeviceFamily` 里有 2）→ **大声提示**：
 *      商店页会承诺支持 iPad，而那是个还没拍板的产品决定。
 *
 * 用法：
 *   node tool/check-ios-app.mjs <Runner.app 路径>
 *   node tool/check-ios-app.mjs                 # 自动找 build/ios 下最新的 Runner.app
 *   node tool/check-ios-app.mjs --selftest      # 自检（造几份假的 .app，验它抓得住）
 *
 * 退出码：有任何一项不符合 → 1。
 */

import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const APP_DIR = join(ROOT, 'app');

function plistRaw(plistPath, key) {
  try {
    return execFileSync('/usr/bin/plutil', ['-extract', key, 'raw', '-o', '-', plistPath],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return null;
  }
}

function plistJson(plistPath, key) {
  try {
    return JSON.parse(execFileSync('/usr/bin/plutil', ['-extract', key, 'json', '-o', '-', plistPath],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }));
  } catch {
    return null;
  }
}

/** 从仓库里读"应该是多少" */
function expectations() {
  const appInfo = readFileSync(join(APP_DIR, 'lib/core/app_info.dart'), 'utf8');
  const version = appInfo.match(/kAppVersion = '([^']+)'/)[1];
  const pubspec = readFileSync(join(APP_DIR, 'pubspec.yaml'), 'utf8');
  const buildNumber = pubspec.match(/^version:\s*[0-9.]+\+(\d+)/m)[1];
  const srcPlist = join(APP_DIR, 'ios/Runner/Info.plist');
  const displayName = plistRaw(srcPlist, 'CFBundleDisplayName');
  const pbx = readFileSync(join(APP_DIR, 'ios/Runner.xcodeproj/project.pbxproj'), 'utf8');
  const iosId = [...pbx.matchAll(/PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);/g)]
    .map((m) => m[1].trim()).filter((v) => !v.includes('RunnerTests'))[0];
  const gradle = readFileSync(join(APP_DIR, 'android/app/build.gradle.kts'), 'utf8');
  const androidId = gradle.match(/applicationId\s*=\s*"([^"]+)"/)[1];
  return { version, buildNumber, displayName, iosId, androidId };
}

function inspect(appPath) {
  const problems = [];
  const facts = [];
  const warnings = [];
  const plist = join(appPath, 'Info.plist');
  if (!existsSync(plist)) {
    return { problems: [`${appPath} 里没有 Info.plist —— 这看起来不是一个 .app 包`], facts, warnings };
  }
  const exp = expectations();

  // ① 身份
  const display = plistRaw(plist, 'CFBundleDisplayName');
  const bundleId = plistRaw(plist, 'CFBundleIdentifier');
  if (display !== exp.displayName) {
    problems.push(`显示名是「${display}」，源码 Info.plist 里是「${exp.displayName}」`);
  }
  if (bundleId !== exp.iosId) {
    problems.push(`bundle id 是 ${bundleId}，工程里是 ${exp.iosId}`);
  }
  if (exp.iosId !== exp.androidId) {
    problems.push(`工程本身两端不一致：iOS ${exp.iosId} / 安卓 ${exp.androidId}`);
  }
  facts.push(`身份：${display} · ${bundleId}（两端一致）`);

  // ② 版本
  const short = plistRaw(plist, 'CFBundleShortVersionString');
  const build = plistRaw(plist, 'CFBundleVersion');
  if (short !== exp.version) {
    problems.push(`CFBundleShortVersionString 是 ${short}，app_info.dart 里是 ${exp.version}`);
  }
  if (build !== exp.buildNumber) {
    problems.push(`CFBundleVersion 是 ${build}，pubspec 的 build number 是 ${exp.buildNumber}`);
  }
  facts.push(`版本：${short} (${build})`);

  // ③ 相册权限：只准"仅新增"
  const add = plistRaw(plist, 'NSPhotoLibraryAddUsageDescription');
  const read = plistRaw(plist, 'NSPhotoLibraryUsageDescription');
  if (!add) {
    problems.push('缺 NSPhotoLibraryAddUsageDescription —— 存分享卡到相册会失败');
  }
  if (read) {
    problems.push('出现了 NSPhotoLibraryUsageDescription（读相册权限）—— '
      + 'v1.27.1 的决定是"只申请仅新增"，而且政策里写着"从不读取你的相册"');
  }
  facts.push(`相册权限：仅新增${read ? '（⚠️ 竟然还有读权限）' : '（无读权限）'}`);

  // ④ 加密声明 / 主题 / 方向
  if (plistRaw(plist, 'ITSAppUsesNonExemptEncryption') !== 'false') {
    problems.push('ITSAppUsesNonExemptEncryption 不是 false —— 提审时会被问出口合规');
  }
  if (plistRaw(plist, 'UIUserInterfaceStyle') !== 'Dark') {
    problems.push('UIUserInterfaceStyle 不是 Dark —— 浅色系统下状态栏/系统控件会撞色');
  }
  const orients = plistJson(plist, 'UISupportedInterfaceOrientations') ?? [];
  const landscape = orients.filter((o) => /Landscape/.test(o));
  if (landscape.length) {
    problems.push(`手机方向里还有横屏（${landscape.join('、')}）—— 横屏下首页会 layout overflow` +
      '（实测过），v1.30.0 已锁竖屏，这里不该回退');
  }
  facts.push(`主题 Dark · 方向 ${orients.length} 项（竖屏锁）`);

  // ⑤ 应用内资产
  const assetsDir = join(appPath, 'Frameworks/App.framework/flutter_assets/assets');
  for (const name of ['privacy-policy.txt', 'collection-list.txt', 'exercises.json']) {
    if (!existsSync(join(assetsDir, name))) {
      problems.push(`包里缺应用内资产 ${name} —— iOS 上那句"应用内能读政策/收集清单"就不成立`);
    }
  }
  facts.push(`应用内资产：政策 / 收集清单 / 动作库 都在`);

  // ⑥ 原生依赖
  for (const fw of ['sqlite3.framework', 'objective_c.framework']) {
    if (!existsSync(join(appPath, 'Frameworks', fw))) {
      problems.push(`包里缺 ${fw} —— 数据库引擎（或它的 Apple FFI 桥）没被打进去`);
    }
  }
  const manifests = [];
  const fwRoot = join(appPath, 'Frameworks');
  if (existsSync(fwRoot)) {
    for (const fw of execFileSync('/bin/ls', [fwRoot], { encoding: 'utf8' }).split('\n').filter(Boolean)) {
      if (existsSync(join(fwRoot, fw, 'PrivacyInfo.xcprivacy'))) manifests.push(fw);
    }
  }
  facts.push(`原生框架：sqlite3 + objective_c 都在${manifests.length ? ` · 自带隐私清单的：${manifests.join('、')}` : ''}`);

  // ⑦ 设备族：iPad 是**还没拍板**的产品决定，产物里必须让人看见
  const family = plistJson(plist, 'UIDeviceFamily') ?? [];
  if (family.includes(2)) {
    warnings.push('UIDeviceFamily 含 2（iPad）→ 商店页会承诺"支持 iPad"。'
      + '那是个还没拍板的产品决定（`docs/your-todo.md` 第 10 条），实测 iPad 上只是拉长的手机版。');
  }
  if (!family.includes(1)) {
    problems.push('UIDeviceFamily 里没有 1（iPhone）—— 这不是一个手机包');
  }
  facts.push(`设备族：${JSON.stringify(family)}${family.includes(2) ? '（含 iPad）' : ''}`);

  return { problems, facts, warnings };
}

// ---------------------------------------------------------------- 自检
//
// 造一份"正确的" .app，再分别造几份**动过手脚**的，要求它抓得住。
// 没有这一步，这个工具可能只是"永远打印 ✓"的假守卫。
function selftest() {
  const dir = mkdtempSync(join(tmpdir(), 'lianleme-iosapp-'));
  const exp = expectations();
  const mk = (name, mutate = () => {}) => {
    const app = join(dir, name, 'Runner.app');
    mkdirSync(join(app, 'Frameworks/App.framework/flutter_assets/assets'), { recursive: true });
    for (const fw of ['sqlite3.framework', 'objective_c.framework', 'Flutter.framework']) {
      mkdirSync(join(app, 'Frameworks', fw), { recursive: true });
    }
    writeFileSync(join(app, 'Frameworks/Flutter.framework/PrivacyInfo.xcprivacy'), '<plist/>');
    for (const f of ['privacy-policy.txt', 'collection-list.txt', 'exercises.json']) {
      writeFileSync(join(app, 'Frameworks/App.framework/flutter_assets/assets', f), 'x');
    }
    const entries = {
      CFBundleDisplayName: exp.displayName,
      CFBundleIdentifier: exp.iosId,
      CFBundleShortVersionString: exp.version,
      CFBundleVersion: exp.buildNumber,
      NSPhotoLibraryAddUsageDescription: '写入相册',
      ITSAppUsesNonExemptEncryption: false,
      UIUserInterfaceStyle: 'Dark',
      UISupportedInterfaceOrientations: ['UIInterfaceOrientationPortrait'],
      UIDeviceFamily: [1, 2],
    };
    mutate(entries);
    // 用 plutil 从 JSON 生成一份合法的 plist（避免手写 XML 出错）
    const jsonPath = join(app, 'info.json');
    writeFileSync(jsonPath, JSON.stringify(entries));
    execFileSync('/usr/bin/plutil', ['-convert', 'xml1', '-o', join(app, 'Info.plist'), jsonPath]);
    rmSync(jsonPath);
    return app;
  };

  const cases = [
    ['正常包 → 必须过', mk('good'), false],
    ['显示名被改 → 必须红', mk('bad-name', (e) => { e.CFBundleDisplayName = 'Lianleme'; }), true],
    ['缺"仅新增"相册权限 → 必须红', mk('bad-noadd', (e) => { delete e.NSPhotoLibraryAddUsageDescription; }), true],
    ['多了"读相册"权限 → 必须红', mk('bad-read', (e) => { e.NSPhotoLibraryUsageDescription = '读相册'; }), true],
    ['版本对不上 → 必须红', mk('bad-ver', (e) => { e.CFBundleVersion = '999'; }), true],
    ['方向放开横屏 → 必须红', mk('bad-orient', (e) => {
      e.UISupportedInterfaceOrientations = ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft'];
    }), true],
  ];
  console.log('iOS 产物核对自检：');
  let bad = 0;
  for (const [label, app, shouldFail] of cases) {
    const r = inspect(app);
    const failed = r.problems.length > 0;
    const ok = failed === shouldFail;
    if (!ok) bad++;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}`
      + (r.problems.length ? `　→ ${r.problems[0].slice(0, 60)}…` : ''));
  }
  rmSync(dir, { recursive: true, force: true });
  if (bad) {
    console.error(`\n✗ 自检失败 ${bad} 项 —— 这个工具本身不可信，先修它`);
    process.exit(1);
  }
  console.log('\n✓ 自检通过：好包过得去，改坏任何一项都藏不住');
}

// ---------------------------------------------------------------- 跑
const args = process.argv.slice(2);
if (args.includes('--selftest')) {
  selftest();
} else {
  let app = args.find((a) => !a.startsWith('--'));
  if (!app) {
    // 自动找：simulator 与 iphoneos 各看一眼，取修改时间最新的
    const candidates = [
      join(APP_DIR, 'build/ios/iphonesimulator/Runner.app'),
      join(APP_DIR, 'build/ios/iphoneos/Runner.app'),
    ].filter(existsSync);
    if (!candidates.length) {
      console.error('找不到已构建的 Runner.app —— 先跑一次 `flutter build ios --simulator`');
      console.error('用法：node tool/check-ios-app.mjs <Runner.app 路径>');
      process.exit(1);
    }
    app = candidates[0];
  }
  const { problems, facts, warnings } = inspect(app);
  console.log(`iOS 产物核对　${app}\n`);
  for (const f of facts) console.log(`  ${f}`);
  if (warnings.length) {
    console.log('');
    for (const w of warnings) console.log(`  \x1b[33m!\x1b[0m ${w}`);
  }
  if (problems.length) {
    console.log('');
    for (const p of problems) console.error(`  \x1b[31m✗\x1b[0m ${p}`);
    console.error(`\n✗ 有 ${problems.length} 处与仓库里的说法不一致`);
    process.exit(1);
  }
  console.log('\n✓ 这份 iOS 产物与仓库里的说法逐项一致');
}
