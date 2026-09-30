# 练了么 · 上架前的**行政前置**（软著 / App 备案 / 隐私政策 URL / 商店材料）

> 这份文件回答一个问题：**"技术上已经能出包了，为什么还不能上架？"**
> 答案是四件与代码无关的事。它们**按周计**，所以必须最早启动 ——
> 代码可以边等边改，行政流程不能。
>
> 事实性内容标注了来源与**核实日期（2026-09-29）**；政策类规定会变，
> 办理前请以官方渠道与目标商店的最新要求为准。

---

## 一、现状：我们有什么、缺什么

| 项 | 状态 | 说明 |
|---|---|---|
| 可安装的 release 包 | ✅ | `app/build/apk/lianleme-v1.12.0-release.apk`（debug 签名，仅供自测） |
| 正式签名接线 | ✅ **已验证** | 配了 `key.properties` 就用正式密钥；缺失时**硬失败**（见 `docs/release-checklist.md` §2） |
| 隐私政策文本 | 🟡 **草案** | `docs/privacy-policy.md`（+ 英文版）与代码**可对账**（`tool/privacy-audit.mjs` 已进门禁）；**未经法务审核** |
| 隐私政策**公网 URL** | 🟡 | 页面已生成并入库（见第四节）；**只差你选托管方式** |
| 软件著作权登记（软著） | 🟡 | 材料已起草（说明书 + 申请表 + 源代码 + 4 张截图）；差你的身份信息（见第三节） |
| App 备案 | ❌ | **小米自 2024-11-01 起强制**（见第二节） |
| 商店材料（图标/截图/描述） | 🟡 | **图标已做**；**截图 4 张已生成**（一条命令重跑，见 [`screenshots.md`](screenshots.md)）；差文案定稿 |
| 真机验收 | 🟡 | 开发者在真机上走过关键路径；**5 人可用性测试与"带手机去健身房练一次"未做**（`docs/usability-test-kit.md`） |

---

## 二、App 备案（**最硬的一条，先起**）

**依据**：《工业和信息化部关于开展移动互联网应用程序备案工作的通知》。
小米应用商店的标准修订于 2024-10-09 公示、**2024-11-01 正式生效**：
> 应用发布上架时，需按相关规定履行 APP 备案手续，且同一 APP，其 **APP 主办单位、APP 名称、
> APP 包名**均要与备案系统保持一致。未履行备案手续的，不得从事 APP 互联网信息服务。
> —— [小米应用商店：APP 备案标准](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1983)（核实于 2026-09-29）

**对我们意味着什么**：

- 备案是**主体**（个人或公司）行为，不是应用内的事 —— 需要你的实名信息/企业资质
- 备案信息里的 **名称与包名** 必须与商店里的一致。我们的是：
  - 包名 **`com.sdknwdtvpv.lianleme`**（真源：`app/android/app/build.gradle.kts` 的 `applicationId`；
    仓库名是 `sdknwdtvpv-sys`，拼写里是 **vpv** 不是 vp —— 提交前再核一次）
  - 应用名「练了么」
  - ⚠️ **一旦备案，包名就不能再改**（改了要重新备案）。所以先定包名、再备案
- 备案需要一个**可访问的服务**：本项目当前**没有后端**（`_NullTransport` / `InMemorySyncQueue`），
  但备案通常要求填写域名/服务器信息 —— 这一步需要你决定"有没有服务器"，
  没有的话以备案系统的"无服务器"情形与接入商指引为准
- 流程一般通过**接入服务商**（如阿里云/腾讯云备案系统）提交，
  参考：[APP 备案全流程解析（腾讯云）](https://developer.cloud.tencent.cn/article/2516021)
  —— 周期以备案系统与接入商的实际进度为准（请勿以本文估计为准）

---

## 二之三、核实过的硬要求（2026-09-30 逐条对过官方文档）

这几条都不是「听说」，出处写在每行后面 —— 前两轮正是靠这种核对发现了
「鉴别材料要 PDF 而不是 txt」与「软件全称必须与商店名称一致」两个坑。

| 要求 | 出处 | 对项目的影响 |
|---|---|---|
| **软著是所有应用上架的必备资质**，且「办理中不能先上架」 | 小米[应用资质FAQ](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=2251) Q5 | 软著在**关键路径**上：30–75 工作日，别的事都得等它 |
| **APP 备案也是所有应用必备**；新应用自 2023-09-01 起须备案后才可上架 | 同上 + [备案指引](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1739) | 与软著并行办 |
| **软件名称 / 应用名称 / APP 备案名称三者必须一致** | [名称基本原则](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1796) | 三处统一用「练了么」；填错要重办 |
| **应用内需在显著位置展示 APP 备案编号，且编号可点击跳转备案系统** | 同上（第四节） | **这是一个 app 侧改动**，见下方待做 |
| 备案时限：省级通信管理局 **20 个工作日**；软著：自受理起 **60 日内**审查完成 | 同上 | 时间账：软著 30–75 工作日 ≫ 备案 20 工作日 |
| 应用名称每自然年**只能改 2 次**，更名需先改软著与备案 | 同上（第五节） | 名字现在就要定死 |
| 备案走**接入商**（华为云 / 阿里云 / 腾讯云）代办 | 同上（第四节） | 需要一个接入商账号；**本 App 没有服务器**，接入信息怎么填待定 |

### 待你确认的一个技术问题：没有服务器，备案的「接入信息」怎么填

备案要填「APP 接入信息」（服务地址 / 域名）。而本项目的设计是**完全离线**：
训练数据只在手机本地，上报通道默认没有地址（`_NullTransport`）。可能的走法：

1. 按「无服务器」申报（以接入商口径为准）；
2. 为备案买一个最小的云资源，作为接入信息；
3. 直接问接入商客服。

**这一条我没有把握，所以只列出来、不替你猜。** 建议在开工软著之前先问一次接入商。

### 待做（app 侧，等真机/模拟器可用 + 拿到备案号）

| 事项 | 说明 |
|---|---|
| 应用内展示 APP 备案编号 | 建议位置：「我」页的隐私/关于区块；编号必须**可点击跳转到备案系统**。拿到备案号后实现，并同步隐私政策 |

## 二之四、iOS 侧（「双端先上」的欠账）

**已与安卓对齐（2026-09-30，都不需要 Xcode 就能做）**：

| 项 | 状态 |
|---|---|
| bundle id | ✅ `com.sdknwdtvpv.lianleme`（与安卓一致，已不是模板的 `com.example.*`） |
| 应用图标 | ✅ 15 个尺寸，满幅不透明、不切圆角（iOS 要求），由 `tool/gen-icons.py` 与安卓同源生成 |
| 启动屏 | ✅ 与 App 同色 `#0B0B0D` + 居中 volt「练」（原来是模板纯白，会白闪） |
| 显示名 | ✅ 「练了么」（原来是模板的 `Lianleme`） |
| 存相册权限 | ✅ `NSPhotoLibraryAddUsageDescription`（**只申请"仅新增"**，不读相册） |
| 提审合规 | ✅ `ITSAppUsesNonExemptEncryption=false`；`UIUserInterfaceStyle=Dark` |
| 守卫 | ✅ `tool/asset-check.mjs` 已覆盖 iOS（图标不是模板图、无透明、1024 齐全、显示名、权限键、启动屏不是纯白）——负向验证过：把模板图标放回去会红 |

**还缺的（卡在工具链上）**：这台机器**没有 Xcode**（只有 Command Line Tools），
所以 iOS 一行都跑不了。`flutter doctor` 的原话：

```
[!] Xcode - develop for iOS and macOS
    ✗ Xcode installation is incomplete; a full installation is necessary for iOS and macOS development.
    ! CocoaPods not installed.
      Without CocoaPods, plugins will not work on iOS or macOS.
```

需要你：

1. 从 App Store 装 **Xcode**（约 20G，**只能装在 `/Applications`**，不能放 SSD）
   —— 装好后我做：模拟器跑通、用 integration_test 出 iOS 截图、逐屏差异走查
2. 装 **CocoaPods**（⚠️ **这台机器上没有，是本轮新查出来的缺口**）。
   我们有 `share_plus` / `gal` 两个插件，**没有 CocoaPods 就必然构建失败**。
   本机也**没有 Homebrew**，所以三条路：
   * `brew install cocoapods` —— 得先装 Homebrew（装到内置盘，约 1G）；
   * 系统自带的 Ruby 是 **2.6**（Apple 已不维护）→ `sudo gem install cocoapods`
     能用，但把依赖装进系统 Ruby；
   * 装一份自带 Ruby 3.x 到 SSD 再 `gem install`（最守"依赖都在 SSD"这条约定，也最费事）。
   **这一步需要你定用哪条路**（涉及装 Homebrew 或动系统 Ruby）；定好之后我来装并验证。
3. 注册 **Apple Developer 账号**（个人 ¥688/年）—— **「双端先上」就意味着这笔开销**，
   而且上架与真机调试都需要它（模拟器不需要）

## 二之四之一、第一次 iOS 构建会**改动几个受版本控制的文件**（先知道，别慌）

这一条是查出来的，不是猜的：Flutter 的 `cocoapods.dart` 里有个
`_addPodsDependencyToFlutterXcconfig`（`build` 时调用），**发现 xcconfig 里没有 Pods 那行就自己加**：

```
cocoapods.dart:307-310
  final include = '#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.${mode}.xcconfig"';
  file.writeAsStringSync('$include\n$content', flush: true);
```

我们的 `ios/Flutter/{Debug,Release}.xcconfig` **现在只有** `#include "Generated.xcconfig"`，
所以第一次 `flutter build ios` / `pod install` 之后会变成：

| 文件 | 会发生什么 | 要不要提交 |
|---|---|---|
| `ios/Flutter/Debug.xcconfig`、`Release.xcconfig` | 被 Flutter 自动加一行 `#include? "Pods/…"`（`cocoapods.dart:303-310`） | **要**（不然下次构建又会被改一遍） |
| `ios/Flutter/AppFrameworkInfo.plist` | 被 Flutter 写入 `MinimumOSVersion`（`build_system/targets/ios.dart:742` 的 `_updateMinimumOSVersion`） | **要** |
| `ios/Podfile` | 由 `pod install` 新建 | **要**（团队/CI 都靠它复现依赖） |
| `ios/Podfile.lock` | 由 `pod install` 新建 | **要**（锁版本；不提交等于每次解析出不同版本） |
| `ios/Runner.xcworkspace/contents.xcworkspacedata` | `pod install` 会往工作区里加 `Pods/Pods.xcodeproj` 引用 | **要** |
| `ios/Pods/`、`Flutter/Generated.xcconfig`、`Flutter/ephemeral/` | 生成物 | **不要**（`ios/.gitignore` 已经忽略了） |

> 顺带核过两条**不会**发生的"惊喜"：① `IOSDeploymentTargetMigration` 只改**旧值**
> （8.0/9.0/11.0/12.0），我们的 `IPHONEOS_DEPLOYMENT_TARGET = 15.0` 与
> `AppFrameworkInfo.plist` 里根本没有这个键，所以它什么都不做；
> ② 我们的 `AppFrameworkInfo.plist` 与当前 Flutter 模板**逐字节同形**
> （模板这版确实不含 `MinimumOSVersion`，是构建时才写进去的）。

也就是说：**装好 Xcode + CocoaPods 之后的第一次构建，会留下 6 个需要提交的改动**，
这是正常的、预期的。不写清楚的话，下一次 `git status` 会让人以为"谁动了工程文件"。

## 二之四之二、依赖的 iOS 可用性（静态核过，2026-09-30）

**结论：现在每个直接依赖都能在 iOS 上跑。** 判据是各包自己 pubspec 里的
`flutter: plugin: platforms:` 声明，由 `tool/ios-deps.mjs` 核（已进 `verify.sh`）：

| 依赖 | iOS 支持 | 依据 |
|---|---|---|
| `drift` / `drift_flutter` | ✅ | 纯 Dart 包（无 plugin 段） |
| `cryptography` | ✅ | 纯 Dart 包 —— 端到端加密那一层在 iOS 上不需要任何原生代码 |
| `share_plus` | ✅ | 声明 `ios`（拉起系统分享面板） |
| `gal` | ✅ | 声明 `ios`（存相册；iOS 侧用"仅新增"权限） |

**原生 SQLite 从哪来**（这条容易误会）：`sqlite3` 3.6.0 **自带各平台的预编译二进制**，
其中 iOS 是 `arm64`（真机）+ `arm64` / `x64`（模拟器）——见该包 README 的
"Supported platforms"。它通过 **hook（native assets）** 在构建时把库放进去，
所以**不需要单独的 `sqlite3_flutter_libs`**。
⚠️ 但 `drift_flutter` 至今**仍然传递依赖** `sqlite3_flutter_libs: ^0.6.0+eol`
（那个包现在只剩一个 Dart 壳、没有原生代码）—— 所以 pubspec 里那句"不要自己加它"
依然成立：它不是我们加的，也**不要**手动加。

**守卫**：`tool/ios-deps.mjs` 拦的是"顺手加一个只有 Android 实现的插件"这种事
（pub.dev 上大量 `xxx_android` 只有单平台）。它**负向验证过**
（把 `gal` 复制一份、删掉 `ios:` 声明 → 判红）。
⚠️ 它只能证明"根本不可能支持"的依赖进不来，**证明不了真的能编过** —— 那要 Xcode。

## 二之四之三、iOS 与安卓的差异清单

**静态核对**（现在就能确定）：

| 项 | 安卓 | iOS | 备注 |
|---|---|---|---|
| 显示名 | 练了么 | 练了么 | 与商店名一致（三处一致是硬要求） |
| 包标识 | `com.sdknwdtvpv.lianleme` | 同 | 上架后不能改 |
| 图标 / 启动屏 | 一套配方两端生成 | 同 | `tool/gen-icons.py` 出，`asset-check.mjs` 守着 |
| 相册权限 | `WRITE_EXTERNAL_STORAGE`（仅 API ≤29）+ 系统隐含的 READ | `NSPhotoLibraryAddUsageDescription`（**仅新增**） | iOS 那边**更窄**：完全不读相册 |
| 其他权限 | INTERNET | 无（iOS 联网不需要声明） | |
| 最低系统 | `minSdk 24` | `IPHONEOS_DEPLOYMENT_TARGET = 15.0` | |
| 数据库 | `libsqlite3.so`（三 ABI，native assets） | sqlite3 预编译 `arm64` | 同一个 `sqlite3` 包，取库的方式不同 |
| 版本号 | `versionCode` / `versionName` | `CFBundleVersion` / `CFBundleShortVersionString` | 都由 pubspec 的 version 生成 |
| 出口合规 | 不涉及 | `ITSAppUsesNonExemptEncryption=false` | 已声明，免得每次提审都被问 |
| 商店表单 | 数据安全表单（Play）/ 各商店自有表单 | **App Privacy 隐私标签** | 见 `docs/store-listing-ios.md` |
| 设备族 | 手机（未锁方向） | **`TARGETED_DEVICE_FAMILY = "1,2"`（iPhone + iPad）** | ⚠️ 见下方待拍板 |

**只有 Xcode 能给的答案（现在全是"未验证"）**：

1. 真的能编过吗（`pod install` + 链接 + 部署目标 15.0 是否与所有依赖兼容）
2. 布局在 iOS 上长什么样（安全区、状态栏、返回手势、字体回退到苹方后的换行）
3. 分享面板与"存到相册"在 iOS 上的真实行为（权限弹窗文案、被拒之后的路径）
4. 深色主题 + 启动屏在 iPhone 上的实际观感（有没有白闪）
5. **横屏**：两端都没有锁方向，而**从来没有在横屏下走过任何一屏** ——
   这是安卓与 iOS **共有**的欠账，不是 iOS 特有的

## 二之四之四、需要你拍板：要不要在 iPad 上跑

`TARGETED_DEVICE_FAMILY = "1,2"` 是 Flutter 模板的默认值，意思是 **iPhone + iPad 都支持**。
两条路：

* **A（我建议）改成 `"1"`（只支持 iPhone）**：与"单手、在健身房站着用"这个定位一致；
  iPad 用户仍能在兼容模式（放大显示）下用。**不需要 iPad 截图**，商店材料少一大块。
  理由很实在：**我们从没在 iPad 上看过任何一屏**，宣布"支持 iPad"等于承诺一件没验证过的事。
* **B 保持 `"1,2"`**：需要 **iPad 13" 截图**，并且要在 iPad 模拟器上逐屏走查
  （大屏下 S4 那个 88pt 大按钮的位置、列表宽度、横屏布局都要重新看）。

它动的是**产品承诺**（商店页会写"支持 iPad"），所以**等你定**。
`docs/store-listing-ios.md` 的截图表已按这条分叉。

**iOS 商店材料**：见 `docs/store-listing-ios.md`（与安卓那份组织方式一致，
含 App Privacy 标签的两个变体、截图规格、审核备注）。

## 二之五、应用内必须能读到隐私政策（小米的合规指引，2026-09-30 补）

**这条此前是缺的**：隐私政策只在仓库与商店页面里，**应用内一个字都没有**。
小米应用商店《隐私政策不合规的问题解析和修改指引》写得很直白：

> *"应用需要在**应用内**添加独立的隐私政策，且**尽量保证在四步操作之内**可以查看到"*；
> *"应用在应用内添加的独立的隐私政策**必须是可以正常打开和查看的状态**"*；
> 规则来源：国信办秘字〔2019〕191 号（同页还要求首次启动**主动弹窗**征求同意、
> 同意/拒绝按钮语义明确、**不得默认勾选**）。

现在做到了的：

| 项 | 状态 |
|---|---|
| 应用内独立的隐私政策 | ✅ 「我 → 隐私政策」＝**两次点击**（页面：`app/lib/features/profile/privacy_policy_screen.dart`） |
| 内容与公网那份同源 | ✅ 由 `tool/gen-privacy-page.mjs` 从 `docs/privacy-policy.md` **同一份 Markdown** 生成 `app/assets/privacy-policy.txt`，且**有防漂守卫**（改了政策没重生成 → 门禁判红） |
| 内容干净 | ✅ 内部注记（状态/待办/文件路径/核对命令）用一对标记圈起来，**三份生成物（公网中文页、英文页、应用内那份）都剥掉** |
| 备案号 | ⬜ 备案通过后填 `kAppFilingNumber`，那一行自动出现（空 = 不显示） |
| **首次启动的同意门** | ✅ 已做（v1.25.0）：整屏征求同意，`同意并继续` / `不同意` 两个按钮（**不设勾选框**，也就没有"默认勾选"与"点按钮等于勾上"这两种被禁的形态）；`阅读《隐私政策》` 可当场读全文；拒绝后给"再看一遍"与"退出"两条路，**且两种情况下都不收集**；同意状态落库（v11，`user_profile.privacy_consent_at_ms`），重启不再问 |
| **拒绝也能用** | ✅ v1.27.0：点「不同意」→ 照常进 App（离线功能本就不需要联网与权限），**但一条都不收集**；拒绝单独落库（`privacy_declined_at_ms`，v12），既不当成同意、也不再重复骚扰。191 号文四.2 禁止的"因不同意非必需收集而拒绝提供业务功能"由此消除。⚠️ 仍差一步：「匿名统计默认开」本身可被判为**默认同意**，改成默认关闭需要用户点头 |
| **同意之前不收集** | ✅ 由启动顺序保证：`main.dart` 把 `_initAnalytics()` / 种子导入都放在同意**之后**；`privacy_consent_test.dart` 用 outbox 行数当证据（同意前 0 条，同意后才开始记 `app_open`） |
| **第三方依赖（SDK）清单** | ✅ 政策 §三之五（中英各一份）：**装进包里的每一个直接依赖**都列出名称、版本、功能、会不会收集信息、许可。同一份指引要求「集中展示第三方 SDK 的名称、功能及其处理个人信息的规则」—— 而加依赖在本仓库太容易（pubspec 加一行），所以 `privacy-audit` 会拿 pubspec 逐个核：**少一个就判红**（负向验证过）。⚠️ 但它的作用域是「`pubspec.yaml` 的**直接**依赖」——**不**检查政策里有没有多列、也不检查有没有链接（2026-09-30 一次对抗性审计指出的） |

## 三、软件著作权登记（软著）

**为什么**：国内主流安卓商店（华为、小米、OPPO、vivo 等）对**个人开发者**或**新主体**
上架通常要求提供软著证书；有公司主体时也常被要求。**具体要求以目标商店的开发者文档为准。**

> 2026-09-30 查证：**华为明确要求提交软著证书**；小米 / VIVO / OPPO 接受"软著证书 /
> App 电子版权证书 / 软件著作权认证证书"三选一。它们**还各自要求** ICP 备案、
> **App 安全评估报告**、**全国互联网安全管理服务平台（公安联网备案）审批截图** ——
> 完整清单与出处见 [`your-todo.md`](your-todo.md) §一之二。

**周期**：一般 **30–75 个工作日**，加急可显著缩短（
[来源](https://www.guozunlaw.com/m/news-81001.html)，非官方口径，**以中国版权保护中心与代办为准**）。

**通常要准备**（以及本项目现在的状态）：

| 材料 | 状态 | 位置 / 怎么来 |
|---|---|---|
| 鉴别材料 PDF（源程序 60 页） | ✅ 已能生成 | `node tool/copyright-pdf.mjs --owner "姓名"` → `dist/copyright/*.pdf`（A4 纵向、每页 50 行、页眉带版本与页码） |
| 鉴别材料 PDF（说明书） | ✅ 已能生成 | 同上，由 `docs/copyright-manual.md` 排版而来 |
| 软件说明书（用户手册） | ✅ 已起草（差 7 屏截图） | [`copyright-manual.md`](copyright-manual.md) |
| 申请表填写参考 | ✅ 已填好能核的字段 | [`copyright-application.md`](copyright-application.md) |
| 界面截图 | 🟡 已出 4 张 | [`screenshots.md`](screenshots.md) → `store-assets/screenshots/` |
| 主体证明材料（身份证 / 营业执照） | ⬜ **你的** | 只有你能提供 |

> 说明书与申请表不再是"待写"：2026-09-30 起草完成，**每一条事实都能在代码里核到**
> （写的时候发现我凭印象写的算法描述是错的 —— 引擎里 DELOAD 是保持重量而不是降 10% ——
> 已按 `engine/progression.mjs` 逐条改正）。剩下真正卡住的只有：你的身份信息、
> 以及真机安装放行后补齐其余 7 屏截图。
> 当前导出：**105 个源文件 / 26,353 行 → 528 页**，交前 30 页 + 后 30 页（含页码与文件定位）。
> （2026-09-30 起 `.py` 也收录 —— `tool/gen-icons.py` 是我们自己写的程序，之前被漏在外面。）
> 说明书草稿见 [`docs/store-listing.md`](store-listing.md) 第七节（你补真实截图即可）。
> **必须你做的**：实名、提交、缴费、拿证。

---

## 四、隐私政策的公网 URL

商店审核会**实际打开这个 URL**，所以它必须：公网可访问、内容与 App 内一致、有生效日期。

| 方案 | 优点 | 代价 |
|---|---|---|
| A. 仓库转公开 + GitHub Pages | 免费、随仓库更新 | 代码公开（本项目当前是私有仓库）；GitHub Pages 在国内访问不稳定 |
| B. 对象存储静态页（阿里云 OSS / 腾讯云 COS） | 国内访问快 | 若用自有域名，需域名+备案；用厂商默认域名则受限（以厂商规则为准） |
| C. 已有公司站点的 `/privacy` 路径 | 最专业 | 需要有站点 |

**建议**：如果本来就要做备案（第二节），顺手把域名/站点一起解决，用 **B** 或 **C**；
否则用 **A** 最快。**这一步需要你选一个方向** —— 页面本身已经生成好了（见下）。

### 页面已经做好，只差"放哪"

**2026-09-30 起，公开页面是生成物、且入库**：

| | |
|---|---|
| 文件 | `store-assets/privacy/index.html`（中文）+ `en.html`（英文） |
| 来源 | `docs/privacy-policy.md` / `.en.md` —— **唯一事实来源**，页面由它渲染 |
| 重新生成 | `node tool/gen-privacy-page.mjs` |
| 防漂移 | `node tool/gen-privacy-page.mjs --check`，已进 `verify.sh` 第 2 层：改了正文没重生成就红 |

页面是**自包含**的（样式内联、无外部资源、无 JS、无字体请求），
三种方案都直接能用：GitHub Pages 丢进仓库、对象存储上传单个文件、公司站点放进去
即可 —— 不需要构建步骤、不依赖任何 CDN。

> 为什么不直接手写一份 HTML：公开页与随包政策一旦各写各的，早晚对不上，
> 而这是最不该漂移的一类文本。生成 + 门禁是唯一能保证同源的做法。
> （第一次生成就抓到了英文版写着"339 个动作"和"4 个埋点事件"，实际是 351 与 9
> —— 当时两版不一致这件事**没有任何东西会发现**，因为检查只读中文版。）

同一份 URL 也会填进 Google Play / 华为 / 小米等各商店的表单（`docs/release-checklist.md` §7）。

---

## 五、商店材料（清单）

| 材料 | 谁做 | 说明 |
|---|---|---|
| 应用图标 | ✅ 已做（我） | `store-assets/icon-512.png`；Android 全套（传统 5 密度 + 自适应 + 圆形 + 主题剪影）
| 应用图标·怎么重做 | 一条命令 | `python3 tool/gen-icons.py`（方向 A）或 `--alt`（深底版）；`tool/asset-check.mjs` 守着"不许是 Flutter 默认图" |
| 截图 | 你（或设计师） | 主流要求 3–8 张；**注意**：截图必须来自真实 App，不能拿原型图充数 |
| 应用描述（短/长） | ✅ **已备好** | [`docs/store-listing.md`](store-listing.md) §2/§3，可直接粘贴 |
| 分类 / 内容分级 | ✅ **已备好答案** | [`docs/store-listing.md`](store-listing.md) §4（逐题答案，你确认即可） |
| 隐私政策 URL | 见第四节 | |
| 数据安全表单（Google Play / 国内商店的"个人信息收集清单"） | ✅ **已备好两套** | [`docs/store-listing.md`](store-listing.md) §5：**按"这个包有没有配上报地址"分 A/B 两版** —— 填错属申报不实 |
| 联系人 / 客服邮箱 | 你 | 商店必填 |

---

## 六、建议的启动顺序（并行，别串行）

**关键路径是软著**：商店明文规定「软著办理中不能先上架」，而它 30–75 工作日；
备案只要 20 工作日，反而在后面。所以顺序不是"哪个简单先做"，是**软著先起**。

```
第 1 天   ┌─ 你：确认三处名称都用「练了么」（App 名 / 软著 / 备案 —— 必须一致）
          ├─ 你：问一次接入商「没有服务器的 App 备案，接入信息怎么填」（见二之三）
          └─ 你：填身份信息 → 提交软著（**从今天开始算 30–75 工作日**）
            材料已就绪：node tool/copyright-pdf.mjs --owner "姓名"  → 两份 PDF
第 1 周   ├─ 你：软著受理后，并行起 App 备案（20 工作日，需要接入商账号）
          ├─ 你 + 我：5 人可用性测试（半天）与"带手机去健身房练一次"
          └─ 你：选隐私政策托管方式并上传（✅ 页面已生成，见第四节）
拿到软著后 ┌─ 你：生成真密钥并备份（✅ 接线与脚本已验证）
          ├─ 我：实现"应用内展示备案编号"（小改动，切版 + 装真机）
          └─ 你 + 我：商店提交（图标与 11 屏截图已就绪）
```

---

## 附：这份文件本身怎么保持不过期

- 事实性条目**都标了来源与核实日期**；规定变化时改这一处，不要散落在别处
- 与代码有关的部分（签名、隐私政策事实、权限）由工具守：
  `node tool/privacy-audit.mjs`（已进 `./verify.sh`）
