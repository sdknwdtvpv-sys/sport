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
 *   8. 设备族**只有 iPhone**（`UIDeviceFamily` == `[1]`）—— 2026-09-30 拍板"只支持 iPhone"，
 *      所以含 2（iPad）现在是**红**，不再是提示：商店页会承诺支持 iPad，
 *      而 iPad 上只是拉长的手机版，没人给它做过适配。
 *
 *  11. **从系统健康库读体成分那件事的两条硬约束**（2026-10-09 加）：
 *      `Info.plist` 里**必须有** `NSHealthShareUsageDescription`（没有它，iOS 上请求读健康数据
 *      会直接失败），**必须没有** `NSHealthUpdateUsageDescription`（政策承诺的是"只读、不写回"）；
 *      另外，**只要这份产物是签过能力的**（`codesign -d --entitlements` 读得到非空字典），
 *      就必须带 `com.apple.developer.healthkit`。源码级的那一半在 `tool/privacy-audit.mjs` 的 ⑩之六，
 *      这一条核的是**产物**：源码写对了、构建时掉了，是另一回事。
 *
 *  10. **应用级隐私清单**（`PrivacyInfo.xcprivacy`）真的在包里、且 `NSPrivacyTracking = false`。
 *      为什么单列一条：漏了它会在**上传时**收到 `ITMS-91053: Missing API declaration` ——
 *      一条只有上传才看得见的错误（详见 `docs/release-admin.md` §二之四）。
 *      Flutter 引擎与插件各自带清单，但**应用级那一份要我们自己放**（2026-10-01 补的）。
 *
 *   9. **出口合规的"决定"有没有留痕**：包里确实有加密代码（`cryptography` 做的
 *      AES-256-GCM + HKDF-SHA256，给云备份用），而 `Info.plist` 断言
 *      `ITSAppUsesNonExemptEncryption=false` —— 这是个**法律声明**，所以文档里必须
 *      写明算法、两种口径与"谁来决定"。少了它，提审那天就得现场编答案。
 *
 * **读 plist 的两种读法（2026-09-30）**：有 `/usr/bin/plutil`（macOS）时用它读真产物；
 * 没有时（Linux/CI）用仓库自己的 `tool/lib/plist.mjs` —— 用户拍板"CI 直接跑 `./verify.sh`"
 * 之后，这条自检必须在 ubuntu 上也能跑，否则它就成了"只在某台机器上存在"的假守卫。
 *
 * 用法：
 *   node tool/check-ios-app.mjs <Runner.app 路径>
 *   node tool/check-ios-app.mjs                 # 自动找最新的一份（build/ios 的真机/模拟器包、
 *                                              #   以及免费签名脚本用的 build/ios-dd）
 *   node tool/check-ios-app.mjs --selftest      # 自检（9 项产物 + 3 项出口合规）
 *
 * 退出码：有任何一项不符合 → 1。
 */

import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdtempSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { hasPlutil, readPlistJson, readPlistRaw, toPlistXml } from './lib/plist.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const APP_DIR = join(ROOT, 'app');

/** 读法跟着机器走：有 plutil 用它，没有就用仓库自己的解析器（CI 上）。 */
let PLIST_ENGINE = hasPlutil() ? 'plutil' : 'builtin';
const plistRaw = (plistPath, key) => readPlistRaw(plistPath, key, PLIST_ENGINE);
const plistJson = (plistPath, key) => readPlistJson(plistPath, key, PLIST_ENGINE);

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

  // ⑪ 从系统健康库读体成分：两条硬约束（用法说明只读、能力在产物里）
  {
    const share = plistRaw(plist, 'NSHealthShareUsageDescription');
    const update = plistRaw(plist, 'NSHealthUpdateUsageDescription');
    if (!share) {
      problems.push('缺 NSHealthShareUsageDescription —— iOS 上请求读健康数据会**直接失败**，'
        + '而政策 §2.4 承诺了我们会读');
    }
    if (update) {
      problems.push('出现了 NSHealthUpdateUsageDescription（写回健康库的用法说明）—— '
        + '政策承诺的是"只读、不写回"，代码里 `toShare` 也是空数组；写了这一条就是在向用户申请一件我们不做的事');
    }
    // 能力：只有**签过能力**的产物才读得到 entitlements。
    // ⚠️ 模拟器构建不签能力（实测 dict 是空的），所以那种产物上这条**跳过并如实说**，
    // 不能因为读不到就判红 —— 那是环境差异，不是产物有问题；反过来，读到了就必须有 healthkit。
    let entitlementDict = '';
    try {
      entitlementDict = execFileSync('codesign',
        ['-d', '--entitlements', ':-', appPath], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    } catch { entitlementDict = ''; }
    // ⚠️ 判"有没有签能力"要**看字典里有没有键**，不能只看那段输出非空：
    // 模拟器构建的 `codesign -d --entitlements` 会打印一份**合法的空字典**
    // （`<dict></dict>`，2026-10-09 实测），按"非空字符串"判会把它当成"签了却缺 healthkit"而误报。
    const hasEntitlements = /<key>/.test(entitlementDict);
    if (/com\.apple\.developer\.healthkit/.test(entitlementDict)) {
      facts.push('HealthKit：用法说明是"只读"那一句 · 产物签名里带 com.apple.developer.healthkit');
    } else if (hasEntitlements) {
      problems.push('这份产物**签了能力**（读得到 entitlements），但里面没有 '
        + 'com.apple.developer.healthkit —— 源码里挂了、构建/签名时掉了，'
        + '那样真机上请求读健康数据会失败');
    } else {
      facts.push('HealthKit：用法说明是"只读"那一句 · 这份产物没带 entitlements'
        + '（模拟器构建不签能力），能力那一条跳过');
    }
  }

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

  // ⑧ 设备族：2026-09-30 拍板"只支持 iPhone"（`TARGETED_DEVICE_FAMILY = "1"`），
  //    所以含 2 从"提示"升级成"红"—— 产物说的必须和商店页说的一致。
  const family = plistJson(plist, 'UIDeviceFamily') ?? [];
  if (family.includes(2)) {
    problems.push('UIDeviceFamily 含 2（iPad）—— 已经拍板只支持 iPhone'
      + '（`docs/your-todo.md` 第 2 条），商店页不该承诺 iPad，iPad 上也只是拉长的手机版');
  }
  if (!family.includes(1)) {
    problems.push('UIDeviceFamily 里没有 1（iPhone）—— 这不是一个手机包');
  }
  facts.push(`设备族：${JSON.stringify(family)}${family.includes(2) ? '（含 iPad）' : ''}`);

  // ⑩ 应用级隐私清单：必须在包里、必须声明不做追踪、必须写明用到哪些 required-reason API
  const appManifest = join(appPath, 'PrivacyInfo.xcprivacy');
  if (!existsSync(appManifest)) {
    problems.push('包里没有**应用级** PrivacyInfo.xcprivacy —— 上传时会收到 '
      + 'ITMS-91053（Missing API declaration），而那条错误只有上传才看得见。'
      + '引擎与插件的清单不算：那份要我们自己放在 app/ios/Runner/ 下');
  } else {
    const tracking = plistRaw(appManifest, 'NSPrivacyTracking');
    if (tracking !== 'false') {
      problems.push(`应用级隐私清单里 NSPrivacyTracking = ${tracking}（应为 false）—— `
        + '我们不做跨 App 追踪，写了 true 等于在隐私标签之外又声明了一件不成立的事');
    }
    const apiTypes = plistJson(appManifest, 'NSPrivacyAccessedAPITypes') ?? [];
    if (!Array.isArray(apiTypes) || apiTypes.length === 0) {
      problems.push('应用级隐私清单里没有声明任何 NSPrivacyAccessedAPITypes —— '
        + '那这份清单就只是占位，上传时该报的还是会报');
    } else {
      const cats = apiTypes
        .map((x) => String(x?.NSPrivacyAccessedAPIType ?? ''))
        .map((x) => x.replace('NSPrivacyAccessedAPICategory', ''))
        .filter(Boolean);
      facts.push(`应用级隐私清单：追踪 ${tracking} · required-reason ${cats.length} 类（${cats.join('、')}）`);
    }

    // ⚠️ **2026-10-11 加的判据**：数据类别的申报必须与"包里到底配没配上报地址"一致。
    //
    // 为什么要有它：那份清单长期写着"当前发布版本不向任何地方发送数据（默认关、没配上报地址）"，
    // 而**默认值 2026-10-07 改成了开、正式包两个地址也都配了** —— 于是它在**对 Apple 说假话**
    // （`NSPrivacyCollectedDataTypes = []` 是"变体 A：Data Not Collected"的写法）。
    // 人眼看不出来（清单在包里，谁也不会每次翻），所以让机器对着**产物**核一遍：
    // 二进制里有上报地址 = 变体 B = 必须声明数据类别。
    const bin = join(appPath, 'Runner');
    const hasAnalyticsUrl = existsSync(bin)
      && readFileSync(bin).includes(Buffer.from('api.elliotli.work'));
    const collected = plistJson(appManifest, 'NSPrivacyCollectedDataTypes') ?? [];
    if (hasAnalyticsUrl && (!Array.isArray(collected) || collected.length === 0)) {
      problems.push('包里**配了上报地址**（`Runner` 二进制里能找到 `api.elliotli.work`），'
        + '但应用级隐私清单的 `NSPrivacyCollectedDataTypes` 是空的 —— 那是"变体 A"的写法，'
        + '等于对外声明"我们不收集任何数据"。按 `docs/store-listing-ios.md` §三 的**变体 B** 逐条声明'
        + '（EmailAddress 关联身份；DeviceID / ProductInteraction / Fitness 用途 Analytics）');
    } else if (hasAnalyticsUrl) {
      facts.push(`应用级隐私清单：数据类别 ${collected.length} 类（与"包里配了上报地址"一致 ✓）`);
    }
  }

  // ⑪ 组间休息的 Live Activity：**扩展必须真的躺在 PlugIns 里**
  //
  // 为什么单独一条：这个功能的失败方式特别安静 —— 扩展没被嵌进去时，
  // App 照常跑、Dart 侧的测试照常全绿，**只有锁屏上什么都没有**。
  // 配套的端到端测试是 `app/integration_test/rest_activity_e2e_test.dart`
  // （它断言"系统里真的开出了 1 条"），这里管的是**产物**那一半。
  {
    const pluginsDir = join(appPath, 'PlugIns');
    const appexes = existsSync(pluginsDir)
      ? readdirSync(pluginsDir).filter((f) => f.endsWith('.appex'))
      : [];
    if (appexes.length === 0) {
      problems.push('包里没有 PlugIns/*.appex —— 「组间休息」的 Live Activity 扩展'
        + '（app/ios/RestWidget）没被嵌进产物，锁屏上会什么都没有，而 App 照常跑');
    } else {
      const seen = [];
      for (const name of appexes) {
        const appexPlist = join(pluginsDir, name, 'Info.plist');
        if (!existsSync(appexPlist)) {
          problems.push(`PlugIns/${name} 里没有 Info.plist —— 这不是一个可用的扩展`);
          continue;
        }
        // ⚠️ `plistRaw` 是**平铺**取值（不支持点路径），嵌套的那份要用 plistJson 取回来
        const extSection = plistJson(appexPlist, 'NSExtension');
        const point = extSection?.NSExtensionPointIdentifier ?? null;
        const extId = plistRaw(appexPlist, 'CFBundleIdentifier');
        if (point !== 'com.apple.widgetkit-extension') {
          problems.push(`PlugIns/${name} 的扩展点是 ${point}（应为 `
            + 'com.apple.widgetkit-extension）—— Live Activity 只可能由 widget 扩展提供');
        }
        if (typeof extId !== 'string' || !extId.startsWith(`${exp.iosId}.`)) {
          problems.push(`PlugIns/${name} 的 bundle id 是 ${extId}，`
            + `它必须是主 App（${exp.iosId}）的子标识 —— 否则安装时报签名/标识不匹配`);
        }
        seen.push(name.replace(/\.appex$/, ''));
      }
      if (seen.length) {
        // App 侧还得声明"我用 Live Activity"，少了这一位 Activity.request 直接抛错
        if (plistRaw(plist, 'NSSupportsLiveActivities') !== 'true') {
          problems.push('App 的 Info.plist 里 NSSupportsLiveActivities 不是 true —— '
            + '少了这一位，Activity.request 会直接抛错（扩展在包里也没用）');
        } else {
          facts.push(`Live Activity 扩展：${seen.join('、')}.appex · `
            + 'NSSupportsLiveActivities=true');
        }
      }
    }
  }

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
    // 应用级隐私清单：真实产物里就该有这一份（2026-10-01 起）
    writeFileSync(join(app, 'PrivacyInfo.xcprivacy'), toPlistXml({
      NSPrivacyTracking: false,
      NSPrivacyTrackingDomains: [],
      // 变体 B：配了上报地址的正式包必须声明这些（与 docs/store-listing-ios.md §三 一致）
      NSPrivacyCollectedDataTypes: [
        {
          NSPrivacyCollectedDataType: 'NSPrivacyCollectedDataTypeDeviceID',
          NSPrivacyCollectedDataTypeLinked: false,
          NSPrivacyCollectedDataTypeTracking: false,
          NSPrivacyCollectedDataTypePurposes: ['NSPrivacyCollectedDataTypePurposeAnalytics'],
        },
      ],
      NSPrivacyAccessedAPITypes: [
        {
          NSPrivacyAccessedAPIType: 'NSPrivacyAccessedAPICategoryUserDefaults',
          NSPrivacyAccessedAPITypeReasons: ['CA92.1'],
        },
      ],
    }));
    writeFileSync(join(app, 'AppIcon60x60@2x.png'), 'x');
    // 主二进制：真实正式包里能找到上报地址（新判据靠它判断"这是变体 B 的包"）
    writeFileSync(join(app, 'Runner'), 'x api.elliotli.work y');
    // Live Activity 扩展（真实产物里就有：PlugIns/RestWidget.appex）
    mkdirSync(join(app, 'PlugIns/RestWidget.appex'), { recursive: true });
    writeFileSync(join(app, 'PlugIns/RestWidget.appex/Info.plist'), toPlistXml({
      CFBundleIdentifier: `${exp.iosId}.RestWidget`,
      NSExtension: { NSExtensionPointIdentifier: 'com.apple.widgetkit-extension' },
    }));
    const entries = {
      CFBundleDisplayName: exp.displayName,
      CFBundleIdentifier: exp.iosId,
      CFBundleShortVersionString: exp.version,
      CFBundleVersion: exp.buildNumber,
      NSPhotoLibraryAddUsageDescription: '写入相册',
      NSHealthShareUsageDescription: '读取你健康里的体重、体脂率和身高',
      ITSAppUsesNonExemptEncryption: false,
      UIUserInterfaceStyle: 'Dark',
      UISupportedInterfaceOrientations: ['UIInterfaceOrientationPortrait'],
      UIDeviceFamily: [1],
      NSSupportsLiveActivities: true,
    };
    mutate(entries);
    // 用仓库自己的序列化写一份合法的 plist（**不再依赖 plutil**：
    // CI 是 ubuntu，没有 plutil —— 靠系统工具造夹具的自检在 CI 上根本跑不起来）
    writeFileSync(join(app, 'Info.plist'), toPlistXml(entries));
    return app;
  };

  const cases = [
    ['正常包 → 必须过', mk('good'), false],
    ['Live Activity 扩展没进包 → 必须红', (() => {
      const a = mk('bad-no-appex');
      rmSync(join(a, 'PlugIns'), { recursive: true, force: true });
      return a;
    })(), true],
    ['扩展点写错（不是 widgetkit）→ 必须红', (() => {
      const a = mk('bad-appex-point');
      writeFileSync(join(a, 'PlugIns/RestWidget.appex/Info.plist'), toPlistXml({
        CFBundleIdentifier: `${exp.iosId}.RestWidget`,
        NSExtension: { NSExtensionPointIdentifier: 'com.apple.share-services' },
      }));
      return a;
    })(), true],
    ['扩展的 bundle id 不在主 App 之下 → 必须红', (() => {
      const a = mk('bad-appex-id');
      writeFileSync(join(a, 'PlugIns/RestWidget.appex/Info.plist'), toPlistXml({
        CFBundleIdentifier: 'com.example.someone-else.RestWidget',
        NSExtension: { NSExtensionPointIdentifier: 'com.apple.widgetkit-extension' },
      }));
      return a;
    })(), true],
    ['App 没声明 NSSupportsLiveActivities → 必须红', mk('bad-no-la-flag',
      (e) => { delete e.NSSupportsLiveActivities; }), true],
    ['显示名被改 → 必须红', mk('bad-name', (e) => { e.CFBundleDisplayName = 'Lianleme'; }), true],
    ['缺"仅新增"相册权限 → 必须红', mk('bad-noadd', (e) => { delete e.NSPhotoLibraryAddUsageDescription; }), true],
    ['多了"读相册"权限 → 必须红', mk('bad-read', (e) => { e.NSPhotoLibraryUsageDescription = '读相册'; }), true],
    ['版本对不上 → 必须红', mk('bad-ver', (e) => { e.CFBundleVersion = '999'; }), true],
    ['应用级隐私清单被删 → 必须红', (() => {
      const a = mk('bad-privacy');
      rmSync(join(a, 'PrivacyInfo.xcprivacy'), { force: true });
      return a;
    })(), true],
    ['隐私清单把追踪写成 true → 必须红', (() => {
      const a = mk('bad-tracking');
      writeFileSync(join(a, 'PrivacyInfo.xcprivacy'), toPlistXml({
        NSPrivacyTracking: true,
        NSPrivacyAccessedAPITypes: [
          {
            NSPrivacyAccessedAPIType: 'NSPrivacyAccessedAPICategoryUserDefaults',
            NSPrivacyAccessedAPITypeReasons: ['CA92.1'],
          },
        ],
      }));
      return a;
    })(), true],
    ['配了上报地址、清单却声明"不收集任何数据" → 必须红', (() => {
      const a = mk('bad-privacy-empty');
      writeFileSync(join(a, 'PrivacyInfo.xcprivacy'), toPlistXml({
        NSPrivacyTracking: false,
        NSPrivacyCollectedDataTypes: [],
        NSPrivacyAccessedAPITypes: [
          {
            NSPrivacyAccessedAPIType: 'NSPrivacyAccessedAPICategoryUserDefaults',
            NSPrivacyAccessedAPITypeReasons: ['CA92.1'],
          },
        ],
      }));
      return a;
    })(), true],
    ['设备族里带上了 iPad → 必须红', mk('bad-ipad', (e) => { e.UIDeviceFamily = [1, 2]; }), true],
    ['设备族里没有 iPhone → 必须红', mk('bad-nophone', (e) => { e.UIDeviceFamily = [2]; }), true],
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
    // ⚠️ 2026-10-09：健康库那两条 —— 缺"读"的用法说明、或悄悄加上"写"的那句，都必须红
    ['缺 NSHealthShareUsageDescription → 必须红', mk('bad-no-healthshare',
      (e) => { delete e.NSHealthShareUsageDescription; }), true],
    ['多了 NSHealthUpdateUsageDescription（写回）→ 必须红', mk('bad-healthupdate',
      (e) => { e.NSHealthUpdateUsageDescription = '写回健康库'; }), true],
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
  // **两种读法各跑一遍**：macOS 上默认是 plutil，CI 上是内置解析器。
  // 只跑默认那条的话，"另一种读法"永远没人验过 —— 而 CI 用的恰好是另一种。
  const engines = hasPlutil() ? ['plutil', 'builtin'] : ['builtin'];
  for (const engine of engines) {
    PLIST_ENGINE = engine;
    console.log(`  ${engine === 'plutil' ? '（读法：系统 plutil）' : '（读法：内置 XML 解析器 —— CI 用的就是这条）'}`);
    for (const [label, app, shouldFail] of cases) {
      const r = inspect(app);
      const failed = r.problems.length > 0;
      const ok = failed === shouldFail;
      if (!ok) bad++;
      console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}`
        + (r.problems.length ? `　→ ${r.problems[0].slice(0, 60)}…` : ''));
    }
  }
  PLIST_ENGINE = hasPlutil() ? 'plutil' : 'builtin';
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
    // ⚠️ 2026-10-04 又踩了一次同类：`tool/ios-device-run.sh`（免费 Apple ID 真机装包）
    // 用的是**另一个 derivedData 目录** `build/ios-dd`，旧名单里没有它 ——
    // 于是自动发现只在 `build/ios` 里挑，挑中了 8 小时前那份 **1.41.0 模拟器包**，
    // 报出两条"版本不符"，而当时真正最新的产物（1.42.3 真机包）就在隔壁目录里躺着。
    // 教训：**产物路径变多了，发现逻辑要跟着变**，否则守卫会拿过期对象核当前状态。
    const candidates = [
      join(APP_DIR, 'build/ios/iphonesimulator/Runner.app'),
      join(APP_DIR, 'build/ios/iphoneos/Runner.app'),
      join(APP_DIR, 'build/ios-dd/Build/Products/Release-iphoneos/Runner.app'),
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
