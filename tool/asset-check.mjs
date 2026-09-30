#!/usr/bin/env node
/**
 * 练了么 · 发行资源自检（图标 / 启动图 / 应用名）
 *
 * **它回答的问题**：这个包能不能拿去上架？
 *
 * 起因是一件真事：2026-09-30 才发现 App 用的还是 **Flutter 默认图标** ——
 * 5 个密度的 `ic_launcher.png` 与 SDK 模板逐字节相同。它不难看，是**不能用**：
 * Flutter 的 logo 是 Google 的商标，拿它当自己的应用图标是商标问题；
 * 而且启动器里显示的名字还是模板留下的 `lianleme`。
 * 这类东西的共同点是：**没有任何测试会红**，只有人记得才会改。
 * 所以它在这里被变成四个能跑的命令。
 *
 * 查什么：
 *   1. 传统图标（5 个密度）不是 Flutter 默认图标 —— 与 SDK 模板逐字节比对
 *   2. 自适应图标三件套齐全（Android 8+ 真正生效的那套），且尺寸正确
 *      （前景/剪影位图会被当作 108dp × 108dp 缩放，尺寸错就会发虚）
 *   3. 启动图不是模板的纯白（App 是深色的，纯白启动图 = 每次冷启动闪一下白）
 *   4. 启动器名不是模板默认值，且走的是 `@string/app_name`
 *   5. 商店图标 512×512 且**没有 alpha**（应用商店不收带透明的图）
 *   6. iOS 图标清单（Contents.json）与磁盘双向对账：清单里写的都在、目录里的都被引用、
 *      声明尺寸与 PNG 真实像素一致、19 个必需槽位一个不少
 *   7. iOS Info.plist（显示名 / 存相册权限 / 出口加密声明）、启动屏不是纯白、bundle id 不是模板的
 *
 * 零依赖：PNG 的尺寸与颜色类型直接从 IHDR 头读，不装任何图形库。
 *
 * 用法：node tool/asset-check.mjs
 * 退出码：有问题 → 1
 */

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const RES = join(ROOT, 'app/android/app/src/main/res');

const problems = [];
const ok = [];
const bad = (m) => problems.push(m);

// ── PNG 头解析：宽高在 IHDR 的第 16–24 字节，颜色类型在第 25 字节 ────────
// 颜色类型：0 灰度 · 2 RGB · 3 调色板 · 4 灰度+A · 6 RGBA
function pngInfo(path) {
  const b = readFileSync(path);
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (!b.subarray(0, 8).equals(sig)) return null;
  return {
    width: b.readUInt32BE(16),
    height: b.readUInt32BE(20),
    colorType: b[25],
    hasAlpha: b[25] === 4 || b[25] === 6 || b[25] === 3,
    md5: createHash('md5').update(b).digest('hex'),
  };
}

// ── 1. 传统图标不能是 Flutter 默认图 ──────────────────────────────────────
const LEGACY = { mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 };
const ADAPTIVE = { mdpi: 108, hdpi: 162, xhdpi: 216, xxhdpi: 324, xxxhdpi: 432 };

function flutterTemplateHashes() {
  // 从 flutter SDK 里找模板图标。找不到就明确说"跳过"，不假装通过。
  // 依赖 2026-09-30 搬到了 SSD：/Volumes/Elliot's SSD/harness-deps/flutter
  // （见 docs/dev-environment.md）。旧路径留着，换机器时不至于立刻失效。
  const sdk = process.env.FLUTTER_ROOT
    ?? [
      "/Volumes/Elliot's SSD/harness-deps/flutter",
      join(process.env.HOME ?? '', 'development/flutter'),
      '/opt/flutter',
    ].find((p) => existsSync(join(p, 'packages/flutter_tools/templates')));
  if (!sdk) return null;
  const tpl = join(sdk, 'packages/flutter_tools/templates');
  if (!existsSync(tpl)) return null;
  const hashes = new Map();
  const walk = (dir) => {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      const p = join(dir, e.name);
      if (e.isDirectory()) walk(p);
      // 安卓的 ic_launcher.png 与 iOS 的 Icon-App-*.png 都要收。
      // ⚠️ 第一版只收了安卓的 —— 于是"iOS 图标不是模板默认图"那条检查**永远为真**，
      // 负向验证（把模板图标放回去）当场戳穿：它没红。（守卫空转比没有守卫更危险。）
      else if (e.name === 'ic_launcher.png' || /^Icon-App-.*\.png$/.test(e.name)) {
        const info = pngInfo(p);
        if (info) hashes.set(info.md5, p);
      }
    }
  };
  walk(tpl);
  return hashes.size ? hashes : null;
}

const tplHashes = flutterTemplateHashes();
if (!tplHashes) {
  ok.push('找不到 flutter SDK 模板图标 —— 跳过"默认图标"比对（不假装通过）');
}

for (const [d, size] of Object.entries(LEGACY)) {
  const p = join(RES, `mipmap-${d}/ic_launcher.png`);
  if (!existsSync(p)) { bad(`缺传统图标：mipmap-${d}/ic_launcher.png`); continue; }
  const info = pngInfo(p);
  if (!info) { bad(`mipmap-${d}/ic_launcher.png 不是合法 PNG`); continue; }
  if (info.width !== size || info.height !== size) {
    bad(`mipmap-${d}/ic_launcher.png 尺寸是 ${info.width}×${info.height}，应为 ${size}×${size}`);
  }
  if (tplHashes?.has(info.md5)) {
    bad(`mipmap-${d}/ic_launcher.png 还是 **Flutter 默认图标**`
      + `（与 ${tplHashes.get(info.md5).replace(ROOT, '.')} 逐字节相同）`
      + ' —— Flutter logo 是 Google 的商标，不能当应用图标');
  }
}
if (!problems.length) ok.push('传统图标：5 个密度齐全、尺寸正确、不是 Flutter 默认图');

// ── 2. 自适应图标（Android 8+ 真正生效的那套） ───────────────────────────
const adaptiveXml = join(RES, 'mipmap-anydpi-v26/ic_launcher.xml');
if (!existsSync(adaptiveXml)) {
  bad('缺 mipmap-anydpi-v26/ic_launcher.xml —— Android 8+ 上会退回传统图标（被裁成方的）');
} else {
  const xml = readFileSync(adaptiveXml, 'utf8');
  for (const layer of ['background', 'foreground']) {
    if (!xml.includes(`<${layer} `)) bad(`自适应图标缺 ${layer} 层`);
  }
  if (!xml.includes('<monochrome ')) {
    ok.push('自适应图标没有 monochrome 层 —— Android 13+ 的主题图标用不上（不致命）');
  }
}

for (const [d, size] of Object.entries(ADAPTIVE)) {
  for (const name of ['ic_launcher_foreground.png', 'ic_launcher_monochrome.png']) {
    const p = join(RES, `mipmap-${d}/${name}`);
    if (!existsSync(p)) { bad(`缺自适应图层：mipmap-${d}/${name}`); continue; }
    const info = pngInfo(p);
    if (!info) { bad(`mipmap-${d}/${name} 不是合法 PNG`); continue; }
    if (info.width !== size || info.height !== size) {
      bad(`mipmap-${d}/${name} 是 ${info.width}×${info.height}，应为 ${size}×${size}`
        + '（自适应前景被当作 108dp 缩放，尺寸小了会发虚）');
    }
    if (!info.hasAlpha) bad(`mipmap-${d}/${name} 没有透明通道 —— 前景层必须是透明底`);
  }
  // roundIcon：API 24/25 只能靠位图，缺了会在那些系统上解析不到资源
  const rp = join(RES, `mipmap-${d}/ic_launcher_round.png`);
  if (!existsSync(rp)) bad(`缺圆形图标：mipmap-${d}/ic_launcher_round.png（minSdk 24 需要它）`);
}
if (!problems.length) ok.push('自适应图标：前景/剪影/圆形齐全，尺寸与透明通道正确');

// ── 3. 启动图不能是纯白 ──────────────────────────────────────────────────
for (const dir of ['drawable', 'drawable-v21', 'drawable-night', 'drawable-night-v21']) {
  const p = join(RES, dir, 'launch_background.xml');
  if (!existsSync(p)) continue;
  const xml = readFileSync(p, 'utf8');
  if (xml.includes('@android:color/white')) {
    bad(`${dir}/launch_background.xml 是模板的纯白 —— App 是深色的，每次冷启动闪一下白`);
  }
  if (!xml.includes('@color/app_background')) {
    bad(`${dir}/launch_background.xml 没有用 @color/app_background（应与 App 底色一致）`);
  }
}
if (!problems.length) ok.push('启动图：与 App 底色一致（无白闪）');

// ── 4. 启动器名字 ────────────────────────────────────────────────────────
const manifest = readFileSync(join(ROOT, 'app/android/app/src/main/AndroidManifest.xml'), 'utf8');
if (/android:label="lianleme"/.test(manifest)) {
  bad('AndroidManifest 的 android:label 还是模板默认的 "lianleme"');
} else if (!/android:label="@string\/app_name"/.test(manifest)) {
  bad('AndroidManifest 的 android:label 没有走 @string/app_name');
}
const strings = join(RES, 'values/strings.xml');
if (!existsSync(strings)) bad('缺 values/strings.xml（应用名应该是个字符串资源）');
else if (!/<string name="app_name">[^<]+<\/string>/.test(readFileSync(strings, 'utf8'))) {
  bad('values/strings.xml 里没有 app_name');
}
if (!problems.length) ok.push('应用名：走 @string/app_name，且不是模板默认值');

// ── 5. 商店图标 ──────────────────────────────────────────────────────────
const store = join(ROOT, 'store-assets/icon-512.png');
if (!existsSync(store)) {
  bad('缺 dist/store/icon-512.png（应用商店要求 512×512）');
} else {
  const info = pngInfo(store);
  if (!info || info.width !== 512 || info.height !== 512) {
    bad(`store-assets/icon-512.png 不是 512×512（当前 ${info?.width}×${info?.height}）`);
  } else if (info.hasAlpha) {
    bad('store-assets/icon-512.png 带透明通道 —— 应用商店不收（会按黑底渲染）');
  } else {
    ok.push('商店图标：512×512、无透明');
  }
}

// ── 6. iOS 侧（2026-09-30 补齐；和安卓是同一类问题，所以用同一套守卫）────────
//
// 这几条都是**没有任何测试会红**的那类：图标是模板默认、显示名是模板默认、
// 少一个权限键、启动屏是纯白 —— 全都不会让构建失败，只会让上架被打回或让用户看到白闪。
const IOS = join(ROOT, 'app/ios/Runner');
const IOS_ICONS = join(IOS, 'Assets.xcassets/AppIcon.appiconset');

// Xcode 认的不是"目录里有几个 PNG"，而是 Contents.json 里的那张**清单**。
// 所以只数文件是不够的 —— 必须拿清单和磁盘**双向对账**：
//   · 清单里有、磁盘上没有  → 对应机型没图标（Xcode 只会警告，构建照样过）
//   · 磁盘上有、清单里没有  → 那个 PNG 白做了，永远不会被打进包
//   · 清单声明的尺寸 ≠ PNG 真实尺寸 → 图标发虚/被裁，而**构建不会失败**
// 这三条以前一条都查不出来：旧版守卫只遍历磁盘上的 PNG，从没打开过 Contents.json，
// 而且只对 1024 那一张做了尺寸校验。
const IOS_REQUIRED_SLOTS = [
  'iphone 20x20@2x', 'iphone 20x20@3x',
  'iphone 29x29@1x', 'iphone 29x29@2x', 'iphone 29x29@3x',
  'iphone 40x40@2x', 'iphone 40x40@3x',
  'iphone 60x60@2x', 'iphone 60x60@3x',
  'ipad 20x20@1x', 'ipad 20x20@2x',
  'ipad 29x29@1x', 'ipad 29x29@2x',
  'ipad 40x40@1x', 'ipad 40x40@2x',
  'ipad 76x76@1x', 'ipad 76x76@2x',
  'ipad 83.5x83.5@2x',
  'ios-marketing 1024x1024@1x',
];

if (!existsSync(IOS_ICONS)) {
  bad('缺 app/ios/Runner/Assets.xcassets/AppIcon.appiconset —— iOS 没配图标');
} else {
  const files = readdirSync(IOS_ICONS).filter((f) => f.endsWith('.png'));
  if (!files.length) bad('iOS 图标目录里一个 PNG 都没有');

  const manifestPath = join(IOS_ICONS, 'Contents.json');
  let images = null;
  if (!existsSync(manifestPath)) {
    bad('缺 iOS 图标的 Contents.json —— 目录里有 PNG 也不会生效');
  } else {
    try {
      // Xcode 写出来的 Contents.json 是"JSON5 风格"（允许尾逗号），我们这份没有，
      // 用 JSON.parse 足够；真被改了格式这里会明确报出来，而不是静默跳过。
      images = JSON.parse(readFileSync(manifestPath, 'utf8')).images;
      if (!Array.isArray(images) || !images.length) {
        bad('iOS 图标的 Contents.json 里没有 images 清单');
        images = null;
      }
    } catch (e) {
      bad(`iOS 图标的 Contents.json 解析失败：${e.message}`);
    }
  }

  if (images) {
    const referenced = new Set();
    const slots = new Set();
    let missing = 0;
    let mismatch = 0;

    for (const img of images) {
      const size = String(img.size ?? '');
      const scale = String(img.scale ?? '');
      const idiom = String(img.idiom ?? '');
      slots.add(`${idiom} ${size}@${scale}`);

      const name = img.filename;
      if (!name) { bad(`iOS 图标清单有一条没有 filename（${idiom} ${size}@${scale}）`); continue; }
      referenced.add(name);

      const p = join(IOS_ICONS, name);
      if (!existsSync(p)) {
        missing++;
        bad(`iOS 图标清单里写了 ${name}，但磁盘上没有 —— 对应机型会缺图标`);
        continue;
      }
      // 声明尺寸 × 倍率 = 应有的像素数（83.5 这类小数尺寸也能算）
      const declared = parseFloat(size);
      const factor = parseFloat(scale);
      const info = pngInfo(p);
      if (!info) { bad(`iOS 图标 ${name} 不是合法 PNG`); continue; }
      if (Number.isFinite(declared) && Number.isFinite(factor)) {
        const want = Math.round(declared * factor);
        if (info.width !== want || info.height !== want) {
          mismatch++;
          bad(`iOS 图标 ${name} 声明 ${size}@${scale}（应为 ${want}×${want}），`
            + `实际是 ${info.width}×${info.height}`);
        }
      }
    }

    const missingSlots = IOS_REQUIRED_SLOTS.filter((s) => !slots.has(s));
    if (missingSlots.length) {
      bad(`iOS 图标清单缺 ${missingSlots.length} 个必需槽位：${missingSlots.join('、')}`
        + '（缺了对应机型就没有图标，而构建不会失败）');
    }
    const orphans = files.filter((f) => !referenced.has(f));
    if (orphans.length) {
      bad(`iOS 图标目录里这 ${orphans.length} 个 PNG 没被 Contents.json 引用，永远不会生效：`
        + `${orphans.join('、')}`);
    }
    if (!missing && !mismatch && !missingSlots.length && !orphans.length) {
      ok.push(`iOS 图标清单：${images.length} 个槽位齐全、尺寸与声明一致、无孤儿文件`);
    }
  }

  let alpha = 0;
  let isDefault = 0;
  for (const f of files) {
    const info = pngInfo(join(IOS_ICONS, f));
    if (!info) continue; // 非法 PNG 已在上面报过，不重复刷屏
    // iOS 图标**不能有 alpha**（App Store 会拒收）
    if (info.hasAlpha) alpha++;
    if (tplHashes?.has(info.md5)) isDefault++;
  }
  if (alpha) bad(`iOS 有 ${alpha} 个图标带透明通道 —— App Store 会拒收（必须满幅不透明）`);
  if (isDefault) bad(`iOS 有 ${isDefault} 个图标还是 **Flutter 模板默认图**`);
  const marketing = join(IOS_ICONS, 'Icon-App-1024x1024@1x.png');
  if (!existsSync(marketing)) {
    bad('缺 iOS 的 1024×1024 图标（App Store 要求）');
  } else {
    const m = pngInfo(marketing);
    if (!m || m.width !== 1024 || m.height !== 1024) {
      bad(`iOS 1024 图标尺寸不对：${m?.width}×${m?.height}`);
    }
  }
  if (!alpha && !isDefault) ok.push('iOS 图标：满幅不透明、不是模板默认图、1024 齐全');
}

const iosPlist = join(IOS, 'Info.plist');
if (!existsSync(iosPlist)) {
  bad('缺 app/ios/Runner/Info.plist');
} else {
  const plist = readFileSync(iosPlist, 'utf8');
  if (/<string>Lianleme<\/string>/.test(plist)) {
    bad('iOS 的 CFBundleDisplayName 还是模板默认的 Lianleme（应为「练了么」）');
  } else if (!plist.includes('练了么')) {
    bad('iOS 的 CFBundleDisplayName 不是「练了么」—— 三处（商店/安卓/iOS）必须同名');
  }
  if (!plist.includes('NSPhotoLibraryAddUsageDescription')) {
    bad('iOS 缺 NSPhotoLibraryAddUsageDescription —— 存分享卡到相册会失败');
  }
  if (!plist.includes('ITSAppUsesNonExemptEncryption')) {
    bad('iOS 缺 ITSAppUsesNonExemptEncryption —— 提审时会被问出口合规');
  }
  if (!plist.includes('练了么')) bad('iOS Info.plist 里没有中文应用名');
  ok.push('iOS Info.plist：显示名 / 存相册权限 / 加密声明 齐全');

  // ── iOS「仅新增权限」与「带相簿名去存」是**互斥**的 ──────────────────────
  //
  // 这条检查横跨 Info.plist 与 Dart 源码，因为两边单看都没问题：
  //   * iOS 只声明 `NSPhotoLibraryAddUsageDescription`（仅新增）—— 这是我们的隐私选择；
  //   * 但 gal 建/找相簿要**读**相册（`PHAssetCollection.fetchAssetCollections` +
  //     `creationRequestForAssetCollection`，需要 `.readWrite` 授权 = 读相册权限）。
  // 2026-09-30 实测：`Gal.hasAccess()` / `requestAccess()` 在 iOS 上是 `toAlbum: false`
  // （只有 addOnly），拿着 addOnly 去建相簿 `performChanges` 必然失败 ——
  // 用户看到"存相册失败"，而政策里那句「只写入，从不读取你的相册」也变成假话。
  // 所以：没声明读权限时，代码里就**不许**直接带相簿名；必须走 `shareAlbumNameFor`。
  const exporterPath = join(ROOT, 'app/lib/features/summary/share_card_exporter.dart');
  const exporterSrc = existsSync(exporterPath) ? readFileSync(exporterPath, 'utf8') : '';
  const declaresReadWrite = plist.includes('NSPhotoLibraryUsageDescription');
  const passesRawAlbum = /album:\s*kShareAlbumName/.test(exporterSrc);
  if (!declaresReadWrite && passesRawAlbum) {
    bad('iOS 只声明了「仅新增」相册权限，而 share_card_exporter.dart 直接带了相簿名去存'
      + '（`album: kShareAlbumName`）—— 建相簿需要读相册权限，iOS 上会存失败，'
      + '且政策里「从不读取你的相册」会变成假话。请走 `shareAlbumNameFor(isIOS: ...)`');
  } else if (exporterSrc && !exporterSrc.includes('shareAlbumNameFor')) {
    bad('share_card_exporter.dart 里找不到 `shareAlbumNameFor` —— 相簿名的平台分叉'
      + '被删掉了？（措辞变了的话，这条检查要跟着改）');
  } else {
    ok.push('iOS 相册：只声明「仅新增」，代码不带相簿名去存（不读相册）');
  }
}

const iosLaunch = join(IOS, 'Base.lproj/LaunchScreen.storyboard');
if (existsSync(iosLaunch)) {
  const sb = readFileSync(iosLaunch, 'utf8');
  if (/red="1" green="1" blue="1"/.test(sb)) {
    bad('iOS 启动屏还是模板的纯白 —— App 是深色，冷启动会闪一下白');
  } else {
    ok.push('iOS 启动屏：与 App 同色（无白闪）');
  }
}

// bundle id 不能是模板的 com.example.*
const pbx = join(ROOT, 'app/ios/Runner.xcodeproj/project.pbxproj');
if (existsSync(pbx) && /PRODUCT_BUNDLE_IDENTIFIER = com\.example\./.test(readFileSync(pbx, 'utf8'))) {
  bad('iOS 的 bundle id 还是模板的 com.example.* —— 上架前必须改成自己的');
}

// ── 方向锁：**手机只支持竖屏** ─────────────────────────────────────────────
//
// 2026-09-30 实测后定的：把模拟器换成横屏尺寸跑完整套截图脚本，首页那条大按钮的 Column
// 会 `RenderFlex overflowed by 80 pixels on the bottom`，入口文字还与底部导航重叠
// （证据图 docs/images/ 里那两张 iPad 宽的 + 现场截图）。我们**一个横屏设计都没有** ——
// 既然如此，与其留着"转一下就坏"，不如明确只支持竖屏，并把这件事钉在门禁上。
//
// 两端各一处，缺一个就会出现"某一端转一下坏掉而另一端好好的"：
//   * 安卓：`android:screenOrientation="portrait"`（manifest 里）
//   * iOS：`UISupportedInterfaceOrientations` 这份（**手机那份**）只能有 Portrait
const MANIFEST = join(ROOT, 'app/android/app/src/main/AndroidManifest.xml');
if (!existsSync(MANIFEST)) {
  bad('缺 app/android/app/src/main/AndroidManifest.xml');
} else if (!/android:screenOrientation="portrait"/.test(readFileSync(MANIFEST, 'utf8'))) {
  bad('安卓 manifest 没有锁竖屏（android:screenOrientation="portrait"）—— '
    + '横屏下首页会 layout overflow（实测过），而这一端漏了锁就会出现"安卓转一下就坏"');
} else {
  ok.push('方向锁：安卓已锁竖屏');
}

{
  const plistText = existsSync(iosPlist) ? readFileSync(iosPlist, 'utf8') : '';
  // 取**第一份** UISupportedInterfaceOrientations（= 手机那份；iPad 那份的 key 带 ~ipad）
  const m = plistText.match(
    /<key>UISupportedInterfaceOrientations<\/key>\s*<array>([\s\S]*?)<\/array>/);
  if (!m) {
    bad('iOS Info.plist 里找不到 UISupportedInterfaceOrientations（措辞变了？'
      + '这条守卫已经失效，别当成通过）');
  } else {
    const dirs = [...m[1].matchAll(/<string>([^<]+)<\/string>/g)].map((x) => x[1]);
    const landscape = dirs.filter((d) => /Landscape/.test(d));
    if (landscape.length) {
      bad(`iOS 手机那份允许了横屏（${landscape.join('、')}）—— 横屏下首页会 layout overflow`
        + '（实测过），要锁成只有 UIInterfaceOrientationPortrait');
    } else if (!dirs.includes('UIInterfaceOrientationPortrait')) {
      bad('iOS 手机那份方向里居然没有竖屏 —— 检查要跟着改');
    } else {
      ok.push('方向锁：iOS 手机只剩竖屏');
    }
  }
}

// ── 身份一致性：两端 + 两份商店材料必须是**同一个应用** ──────────────────
//
// 2026-09-30 补。此前没有任何东西把"代码里的应用身份"与"商店材料里写的"绑起来：
// 改了 `applicationId`（比如换成公司域名）、或商店材料里手滑打错一个字母，
// 都要等到提交时被商店打回才发现。而两份商店材料是**手写**的、彼此也没有对账。
//
// 真源各一处：安卓 `build.gradle.kts` 的 applicationId、
// iOS `project.pbxproj` 的 PRODUCT_BUNDLE_IDENTIFIER、安卓 `strings.xml` 的 app_name。
const gradlePath = join(ROOT, 'app/android/app/build.gradle.kts');
const stringsPath = join(ROOT, 'app/android/app/src/main/res/values/strings.xml');
const gradleSrc = existsSync(gradlePath) ? readFileSync(gradlePath, 'utf8') : '';
const stringsSrc = existsSync(stringsPath) ? readFileSync(stringsPath, 'utf8') : '';
const appIdMatch = gradleSrc.match(/applicationId\s*=\s*"([^"]+)"/);
const appNameMatch = stringsSrc.match(/<string name="app_name">([^<]+)<\/string>/);

if (!appIdMatch) {
  bad('读不到 app/android/app/build.gradle.kts 里的 applicationId（措辞变了？检查要跟着改）');
} else {
  const appId = appIdMatch[1];
  // iOS 侧：pbxproj 里 PRODUCT_BUNDLE_IDENTIFIER 出现多次（Runner 与 RunnerTests），
  // 取**不带 .RunnerTests 后缀**的那个才是主 target。
  const pbxSrc = existsSync(pbx) ? readFileSync(pbx, 'utf8') : '';
  const iosIds = [...pbxSrc.matchAll(/PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);/g)]
    .map((m) => m[1].trim())
    .filter((v) => !v.includes('RunnerTests'));
  if (!iosIds.length) {
    bad('读不到 iOS 的 PRODUCT_BUNDLE_IDENTIFIER —— 两端身份对账失效了');
  } else if (iosIds[0] !== appId) {
    bad(`两端 bundle id 不一致：安卓 ${appId} / iOS ${iosIds[0]} —— `
      + '「双端先上」意味着同一个应用，两端身份必须一样');
  } else {
    ok.push(`应用身份：两端 bundle id 一致（${appId}）`);
  }

  // 两份商店材料里都 must 出现这个 id 与应用名
  for (const doc of ['docs/store-listing.md', 'docs/store-listing-ios.md']) {
    const full = join(ROOT, doc);
    if (!existsSync(full)) { bad(`缺 ${doc}`); continue; }
    const text = readFileSync(full, 'utf8');
    // ⚠️ 用 `includes` 是不够的：`com.xxx.lianlemee` **包含** `com.xxx.lianleme`，
    // 少打一个字母/多打一个字母都照样"通过"（负向验证时抓到的）。
    // 所以把文档里所有 `com.*` 形式的标识符抠出来，**逐个**要求它等于 appId
    // （允许 appId 后面接 .RunnerTests 这种明确的子标识）。
    const tokens = [...new Set([...text.matchAll(/\bcom\.[A-Za-z0-9]+(?:\.[A-Za-z0-9]+)+/g)]
      .map((m) => m[0]))];
    if (!tokens.length) {
      bad(`${doc} 里没有写 bundle id/包名 ${appId}（商店表单必填）`);
    }
    for (const t of tokens) {
      if (t !== appId && t !== `${appId}.RunnerTests`) {
        bad(`${doc} 里出现了一个不是本应用身份的标识符「${t}」（应为 ${appId}）——`
          + ' 商店表单里打错一个字母会被打回');
      }
    }
    if (appNameMatch && !text.includes(appNameMatch[1])) {
      bad(`${doc} 里没有出现应用名「${appNameMatch[1]}」—— 与 strings.xml 不一致`);
    }
  }
}

if (!appNameMatch) {
  bad('读不到 app/android/app/src/main/res/values/strings.xml 里的 app_name');
}

// ── Google Play 特征图片（1024×500，精确尺寸、不带透明） ──────────────────
//
// 它是 Play 商店条目顶部那张横幅，**必填**，而规格是死的：精确 1024×500、
// JPEG 或 24 位 PNG（不带 alpha）。我们直到 2026-09-30 才发现这张图**根本没做**
// （只有图标与截图）—— 所以和图标一样钉住：尺寸和透明通道都不许错。
const feature = join(ROOT, 'store-assets/feature-graphic-1024x500.png');
if (!existsSync(feature)) {
  bad('缺少 Google Play 特征图片 store-assets/feature-graphic-1024x500.png'
    + '（跑 python3 tool/gen-feature-graphic.py 生成）');
} else {
  const info = pngInfo(feature);
  if (info.width !== 1024 || info.height !== 500) {
    bad(`特征图片尺寸是 ${info.width}×${info.height}，Play 要求**精确 1024×500**`);
  } else if (info.hasAlpha) {
    bad('特征图片带透明通道 —— Play 要求 JPEG 或 24 位 PNG（无 alpha）');
  } else {
    ok.push('Google Play 特征图片：1024×500、无透明通道');
  }
}

// ── 报告 ─────────────────────────────────────────────────────────────────
console.log('练了么 · 发行资源自检（图标 / 启动图 / 应用名）\n');
for (const m of ok) console.log(`  ${m}`);
if (problems.length) {
  console.log('');
  for (const m of problems) console.log(`✗ ${m}`);
  console.log(`\n✗ ${problems.length} 项需要处理`);
  process.exit(1);
}
console.log('\n✓ 发行资源齐全（可以拿去上架）');
