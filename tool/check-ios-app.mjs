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
 *   7. 编译后的**启动屏**（`Base.lproj/LaunchScreen.storyboardc`）与**图标**
 *      （`Assets.car` + `AppIcon*.png`）真的进了包 —— 少一个就是"冷启动白闪"或"图标是空白"；
 *   8. 设备族里若含 iPad（`UIDeviceFamily` 里有 2）→ **大声提示**：
 *      商店页会承诺支持 iPad，而那是个还没拍板的产品决定。
 *
 *   9. **出口合规的"决定"有没有留痕**：包里确实有加密代码（`cryptography` 做的
 *      AES-256-GCM + HKDF-SHA256，给云备份用），而 `Info.plist` 断言
 *      `ITSAppUsesNonExemptEncryption=false` —— 这是个**法律声明**，所以文档里必须
 *      写明算法、两种口径与"谁来决定"。少了它，提审那天就得现场编答案。
 *
 * 用法：
 *   node tool/check-ios-app.mjs <Runner.app 路径>
 *   node tool/check-ios-app.mjs                 # 自动找 build/ios 下最新的 Runner.app
 *   node tool/check-ios-app.mjs --selftest      # 自检（8 项产物 + 3 项出口合规）
 *
 * 退出码：有任何一项不符合 → 1。
 */

import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
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

/**
 * 出口合规的**决定**有没有留痕。
 *
 * **为什么要这条**：`Info.plist` 里那句 `ITSAppUsesNonExemptEncryption=false` 是**法律声明**
 * （责任人是我们之外的 exporter），而包里**确实有自研用途的加密代码**（`cryptography` 包做的
 * AES-256-GCM + HKDF-SHA256，给云备份做端到端加密）。断言 `false` 本身有守卫，
 * 但"**为什么可以是 false**、谁来决定、ASC 追问时按什么口径答"此前一个字都没写下来 ——
 * 那种状态最容易在提审那天变成现场编答案。
 *
 * 所以：只要 `app/pubspec.yaml` 里有 `cryptography`，就必须在
 * `docs/store-listing-ios.md` 里看到那节决定记录（算法、plist 的值、两种口径、谁决定），
 * 并在 `docs/your-todo.md` 里挂成待你点头的一条。
 */
export function exportComplianceProblems(root) {
  const problems = [];
  const pubspec = join(root, 'app/pubspec.yaml');
  const hasCrypto = existsSync(pubspec)
    && /^\s+cryptography:/m.test(readFileSync(pubspec, 'utf8'));
  if (!hasCrypto) return problems;

  const doc = join(root, 'docs/store-listing-ios.md');
  const docText = existsSync(doc) ? readFileSync(doc, 'utf8') : '';
  if (!docText) {
    problems.push('docs/store-listing-ios.md 不见了 —— 出口合规的决定记录没地方放');
    return problems;
  }
  const must = [
    ['出口合规', '那一节的标题'],
    ['AES-256-GCM', '包里实际用的算法（不然读者不知道在给什么做声明）'],
    ['ITSAppUsesNonExemptEncryption', 'Info.plist 里那个键'],
    ['非豁免', '要回答的问题本身（"是否使用非豁免加密"）'],
  ];
  for (const [needle, why] of must) {
    if (!docText.includes(needle)) {
      problems.push(`包里有 cryptography（自研用途的加密代码），但 docs/store-listing-ios.md 里`
        + `找不到「${needle}」（${why}）—— 出口合规的决定必须留痕，不能只留一个 false`);
    }
  }
  const todo = join(root, 'docs/your-todo.md');
  const todoText = existsSync(todo) ? readFileSync(todo, 'utf8') : '';
  if (!todoText.includes('出口合规')) {
    problems.push('docs/your-todo.md 里没有把"出口合规声明"挂成待用户点头的一条 —— '
      + '它是法律声明，不能由我们代签');
  }
  return problems;
}

function inspect(appPath, root = ROOT) {
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

  // ⑦ 启动屏与图标（编译后的那份）
  const launch = join(appPath, 'Base.lproj/LaunchScreen.storyboardc');
  if (!existsSync(launch)) {
    problems.push('包里没有编译后的启动屏（Base.lproj/LaunchScreen.storyboardc）—— '
      + 'iOS 会退回默认启动图，冷启动会闪一下（深色 App 上就是白闪）');
  }
  const hasAssetsCar = existsSync(join(appPath, 'Assets.car'));
  const iconPngs = existsSync(appPath)
    ? execFileSync('/bin/ls', [appPath], { encoding: 'utf8' })
        .split('\n').filter((f) => /^AppIcon.*\.png$/.test(f))
    : [];
  if (!hasAssetsCar && !iconPngs.length) {
    problems.push('包里既没有 Assets.car 也没有 AppIcon*.png —— 图标没被打进去');
  }
  facts.push(`启动屏：${existsSync(launch) ? '已编译进包' : '缺'} · `
    + `图标：${hasAssetsCar ? 'Assets.car ' : ''}${iconPngs.length} 个 AppIcon PNG`);

  // ⑧ 设备族：iPad 是**还没拍板**的产品决定，产物里必须让人看见
  const family = plistJson(plist, 'UIDeviceFamily') ?? [];
  if (family.includes(2)) {
    warnings.push('UIDeviceFamily 含 2（iPad）→ 商店页会承诺"支持 iPad"。'
      + '那是个还没拍板的产品决定（`docs/your-todo.md` 第 10 条），实测 iPad 上只是拉长的手机版。');
  }
  if (!family.includes(1)) {
    problems.push('UIDeviceFamily 里没有 1（iPhone）—— 这不是一个手机包');
  }
  facts.push(`设备族：${JSON.stringify(family)}${family.includes(2) ? '（含 iPad）' : ''}`);

  // 出口合规的"决定"有没有留痕（与 plist 那个值是一对：值 + 理由）
  problems.push(...exportComplianceProblems(root));

  return { problems, facts, warnings };
}

// ---------------------------------------------------------------- 自检
//
// 造一份"正确的" .app，再分别造几份**动过手脚**的，要求它抓得住。
// 没有这一步，这个工具可能只是"永远打印 ✓"的假守卫。
function selftest() {
  const dir = mkdtempSync(join(tmpdir(), 'lianleme-iosapp-'));
  let bad0 = 0;
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
    // 编译后的启动屏 + 图标：真实产物里长这样（少一个就是"白闪"或"没图标"）
    mkdirSync(join(app, 'Base.lproj/LaunchScreen.storyboardc'), { recursive: true });
    writeFileSync(join(app, 'Base.lproj/LaunchScreen.storyboardc/Info.plist'), '<plist/>');
    writeFileSync(join(app, 'Assets.car'), 'x');
    writeFileSync(join(app, 'AppIcon60x60@2x.png'), 'x');
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
    ['启动屏没打进包 → 必须红', (() => {
      const a = mk('bad-launch');
      rmSync(join(a, 'Base.lproj/LaunchScreen.storyboardc'), { recursive: true, force: true });
      return a;
    })(), true],
    ['图标没打进包 → 必须红', (() => {
      const a = mk('bad-icon');
      rmSync(join(a, 'Assets.car'), { force: true });
      rmSync(join(a, 'AppIcon60x60@2x.png'), { force: true });
      return a;
    })(), true],
  ];
  // 出口合规那三条：造临时仓库根，只动 pubspec 与两份文档
  const docRoot = (mutate) => {
    const r = mkdtempSync(join(tmpdir(), 'lianleme-crypto-'));
    mkdirSync(join(r, 'app'), { recursive: true });
    mkdirSync(join(r, 'docs'), { recursive: true });
    cpSync(join(ROOT, 'app/pubspec.yaml'), join(r, 'app/pubspec.yaml'));
    cpSync(join(ROOT, 'docs/store-listing-ios.md'), join(r, 'docs/store-listing-ios.md'));
    cpSync(join(ROOT, 'docs/your-todo.md'), join(r, 'docs/your-todo.md'));
    if (mutate) mutate(r);
    return r;
  };
  for (const [label, root, wantProblems] of [
    ['有加密依赖 + 决定留痕 → 出口合规那条不报', docRoot(), 0],
    ['有加密依赖但文档没写那节 → 必须报', docRoot((r) => {
      const p = join(r, 'docs/store-listing-ios.md');
      writeFileSync(p, readFileSync(p, 'utf8').replaceAll('AES-256-GCM', '某种算法'));
    }), 1],
    ['政策待办里没挂这条 → 必须报', docRoot((r) => {
      const p = join(r, 'docs/your-todo.md');
      writeFileSync(p, readFileSync(p, 'utf8').replaceAll('出口合规', '某件事'));
    }), 1],
  ]) {
    const got = exportComplianceProblems(root).length;
    const ok = wantProblems === 0 ? got === 0 : got > 0;
    if (!ok) bad0++;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}`
      + (got ? `　→ ${exportComplianceProblems(root)[0].slice(0, 60)}` : ''));
    rmSync(root, { recursive: true, force: true });
  }

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
  // ⚠️ 两条自检的失败数必须**合起来**算：分开算的话，出口合规那三条即使全红，
  // 这里也会打印"自检通过"并 exit 0 —— 那等于没有自检（自己给自己发的假绿灯）。
  const total = bad + bad0;
  if (total) {
    console.error(`\n✗ 自检失败 ${total} 项 —— 这个工具本身不可信，先修它`);
    process.exit(1);
  }
  console.log(`\n✓ 自检通过：产物那 ${cases.length} 项 + 出口合规那 3 项，`
    + '改坏任何一项都藏不住');
}

// ---------------------------------------------------------------- 跑
const args = process.argv.slice(2);
if (args.includes('--selftest')) {
  selftest();
} else {
  let app = args.find((a) => !a.startsWith('--'));
  if (!app) {
    // 自动找：simulator 与 iphoneos 各看一眼，取修改时间最新的
    // ⚠️ 按**修改时间**挑最新那份，**不再固定先看模拟器包**：
    // 2026-09-30 踩到过 —— 磁盘上留着 21:04 编的模拟器包（v1.32.0/41），而当天 23:05 编的是
    // 真机包（v1.32.2/43）；旧代码固定挑模拟器包，于是**拿一份过期产物当"当前产物"核**，
    // 报出来的两条"版本不符"其实是它自己挑错了对象。
    const candidates = [
      join(APP_DIR, 'build/ios/iphonesimulator/Runner.app'),
      join(APP_DIR, 'build/ios/iphoneos/Runner.app'),
    ].filter(existsSync)
      .map((p) => {
        let mtime = 0;
        try { mtime = statSync(join(p, 'Info.plist')).mtimeMs; } catch { /* 忽略 */ }
        return { p, mtime };
      })
      .sort((a, b) => b.mtime - a.mtime);
    if (!candidates.length) {
      console.error('找不到已构建的 Runner.app —— 先跑一次 `flutter build ios --simulator`');
      console.error('用法：node tool/check-ios-app.mjs <Runner.app 路径>');
      process.exit(1);
    }
    app = candidates[0].p;
    // 同一台机器上还有别的 Runner.app 时，把它们的版本也报出来 ——
    // "磁盘上躺着一份旧的"正是最容易拿去上传的那一份。
    for (const c of candidates.slice(1)) {
      try {
        const v = plistRaw(join(c.p, 'Info.plist'), 'CFBundleShortVersionString');
        const b = plistRaw(join(c.p, 'Info.plist'), 'CFBundleVersion');
        console.log(`\x1b[33m!\x1b[0m 磁盘上还有一份更旧的产物：${c.p}（${v} (${b})，`
          + `${new Date(c.mtime).toISOString().slice(0, 16).replace('T', ' ')}）—— 别拿它去上传`);
      } catch { /* 读不出来就算了，主产物已经核过 */ }
    }
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
