# 健康数据对接（HealthKit / Health Connect）：先做哪些、卡在哪、怎么验

> 2026-10-08。用户拍板：**「HealthKit/Health Connect 准备做」**。
> 这一份是**动手前的准备**：把"能做什么、要改哪些东西、哪两件事只能真机验"写清楚，
> 免得代码写完才发现卡在权限或审核上（这个仓库里已经有过这种教训：云备份的合规面比代码面大）。

## 一、一句话结论

技术上可行，**但它不是"接个 SDK"那么简单** —— 在我们这个仓库里，它的成本主要在
**合规面**（新的健康权限 = 新的单独同意 + 政策中英 + 两张商店表单 + 隐私标签），
而且有**两件事必须先真机验证**，其中一件可能直接决定这条路走不走得通（见 §四）。

## 二、我们要它做什么（把范围钉死）

| 做什么 | 不做什么 |
|---|---|
| **读**系统健康库里的体成分：体重、体脂率、身高（腰围看平台支持） | ❌ 读心率 / 睡眠 / 运动轨迹这类与训练记录无关的东西 |
| 按**天**合并进本机 `body_metric`，标注"来源：来自健康" | ❌ 写回期间不覆盖我们自己记的那一条（见 §五 的合并策略） |
| 用户不开这个开关时，**一个字节都不读** | ❌ 后台定时同步（只在用户打开 App 且开关开着时读一次） |

**为什么先只读不双向**：写回去要考虑"同一天两条记录谁赢"、删掉我们那条之后系统里那份算什么
—— 那是两套数据源的合并问题，先只读能把它绕开（而且用户真正的诉求是"别让我两头抄"）。

## 三、要改的东西（施工单，按依赖顺序）

### ① 合规先写（不能后补）
* `docs/privacy-facts.json` 新增 `healthSync` 块：读哪些类型、为什么、**默认关**、
  `policyPhrases`（中英各一句必须出现的说法）；
* `docs/privacy-policy{,.en}.md` 新增一节「从系统健康库读取（可选）」：说清
  **只读、按天、可随时关、不上传**（与云备份那节同一套口径）；
* 应用内**单独的同意门**：与"体重属敏感个人信息"那道门同构（PIPL 第 29 条）——
  第一次打开这个开关时单独说明一次，点了才读；撤回入口与身体数据那一页放一起；
* 商店表单两处：Apple 的**健康与健身**数据类别 + 隐私标签；Play 的**健康数据申报**
  （[Health apps declaration](https://support.google.com/googleplay/android-developer/answer/14738291)）；
* `tool/privacy-audit.mjs` 把这三处加进被核名单（否则又是一处会静默烂掉的文本）。

### ② 权限与清单
| 平台 | 要加什么 | 注意 |
|---|---|---|
| iOS | `HealthKit` 能力 + `NSHealthShareUsageDescription`（读）+ `NSHealthUpdateUsageDescription`（**只为将来双向预留，先不加**）；`PrivacyInfo.xcprivacy` 里那一栏 | 见 §四·1 —— **免费签名能不能勾这个能力要先验** |
| Android | manifest 里按类型声明 `android.permission.health.READ_WEIGHT` / `READ_BODY_FAT_PERCENTAGE` / `READ_HEIGHT`；权限说明里要能点进**隐私政策 URL** | Health Connect 在 Android 14+ 是系统内置，13 及以下要装那个独立 App（[官方说明](https://developer.android.google.cn/health-and-fitness/guides/health-connect/publish/declare-access)） |

### ③ 代码（照仓库现有的两个模式来）
* **平台通道**：iOS 走 Swift 桥（`ios/Runner/` 下与 `GlassBridge` / `ReminderBridge` 并列），
  Android 走 Kotlin（下游插件或自建通道）；
* **一个接口 + 一个假实现**：`HealthSyncService`（`Future<List<BodyMetricData>> pull()`），
  测试注入假实现 —— 这样"合并策略"能被单测钉死，不需要真健康库；
* **编译期开关**：与云备份同一套做法（`isCloudBackupConfigured` 那种）——
  **没配就不出现入口**，免得商店审核看到"申请了健康权限却没有任何入口"。

### ④ 合并策略（这一段最值得先想清楚）
按**天**对齐 `body_metric`，规则：
1. 那一天**我们自己已经有记录** → 谁的字段谁说了算？→ **我们的字段不覆盖**，
   只把系统里有、我们没有的字段补上（体重/体脂/身高分开看）；
2. 那一天只有系统记录 → 新建一条，`note` 写"来自健康"（**来源必须留痕**，
   否则用户删掉健康权限之后会不明白这条哪来的）；
3. 一次读入的所有条都在**同一次事务**里，失败就整批不写（不半途留一半）。

## 四、两件只能真机验证的事（**这也是"准备"的第一批动作**）

1. ~~免费 Apple ID 能不能给 Runner 勾上 HealthKit 能力~~ → ✅ **已查实：可以，而且 2026-10-09 在真机上验过了**。
   Apple 官方的《支持的能力（iOS）》表里，**HealthKit 这一行在 ADP / ADEP / Apple Developer
   （免费档）三列都是勾**（[开发者账号帮助 · Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios)），
   所以**不需要 99 美元的会员**就能加这个能力。
   ✅ **真机证据（这一条比文档硬）**：2026-10-09 00:47 用 `tool/ios-device-run.sh` 把包
   装进 iPhone 17 Pro 时，Xcode **当场新下了一份描述文件**
   （`cb6aa92e-6eed-492e-b2e0-66d642aa0ef5`，到期 2026-10-15），它的能力清单里**真的带
   `com.apple.developer.healthkit`**（连同 `healthkit.access` / `healthkit.background-delivery`）；
   装进手机那个包的签名里也读得到 `com.apple.developer.healthkit = True`。
   ⚠️ 免费个人团队**只能签 `com.sdknwdtvpv.lianleme.dev`** 这个后缀 id
   （`com.sdknwdtvpv.lianleme` 已被另一个团队占用，bundle id 全局唯一）——
   这就是那个脚本要临时换 id 的原因，不是它多此一举。
   ⚠️ 但注意同一张表里的 **`HealthKit Estimate Recalibration` 那一行免费档是空的** ——
   那是"估算校准"这类子能力，**我们用不到**（我们只读体重/体脂/身高），别把它和 HealthKit 本体搞混。
   ⚠️ **"本机 Xcode 的 Apple ID 掉线了"这个判断是错的（2026-10-09 查清）**：
   `IDEProvisioningTeamByIdentifier` 里一直有 `LSBQAS2A45`「Elliot LI (Personal Team)」，
   钥匙串里那张 `Apple Development: 919500973@qq.com` 证书**有效期到 2027-10-04**，
   `security find-identity -v -p codesigning` 报 `1 valid identities found`。
   所以**不要去 `Settings → Accounts` 折腾**（用户当时找不到它是对的 —— 那一步本来就不需要）。
   Xcode 里点 ▶️ 报的那句 `Signing for "Runner" requires a development team` 的真正原因是
   **工程里刻意没写 `DEVELOPMENT_TEAM`**（脚本装真机时临时写、退出改回；写进仓库会把免费签名的
   Team 钉死）。**要真机装包就走那条脚本**，不要在 Xcode 界面里修。
   ✅ **2026-10-08 把这一步从"要用户手点"改成了"工程里已经挂好"**
   （**这次没有切版**：一行 Dart / Swift / Kotlin 代码都没改，按 `CHANGELOG.md` 开头那条
   "版本号只跟随 `app/` 下的**代码**改动"，纯工程配置的改动跟下一次改代码的发布一起走；`dist/` 里
   也仍然是 v1.64.0 的 Android 产物，没动 —— 它们本来就不含 iOS 的东西）：
   用户按上面那条入口找了两遍都没找到 `Health` —— 原因不在他：**Xcode 那个
   `+ Capability` 列表要从 Apple ID 在线拉，账号掉线时它是空的/搜不出东西**，
   而账号恰好正掉线（见上一条）。
   所以改成**直接写进工程**，三处一起：
   * `app/ios/Runner/Runner.entitlements`（新建）→ `com.apple.developer.healthkit = true`；
   * `project.pbxproj` 的 Runner 三个配置（Debug/Release/Profile）各加一行
     `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;`
     —— 打开工程时 **Signing & Capabilities 面板会直接显示 HealthKit 能力卡**，
     **不用再去 `+ Capability` 里搜**；
   * 同一个 target 的 `TargetAttributes` 里登记 `SystemCapabilities = { com.apple.HealthKit = { enabled = 1; }; }`
     （Xcode 的 UI 是照这里显示卡片的，只挂 entitlements 文件时卡片有时不出现）。
   ⚠️ **只挂了能力，没写任何功能代码**：`Info.plist` 里**故意没有**
   `NSHealthShareUsageDescription` —— 那一句是功能上线那一版的事（与政策/商店表单同期）。
   验过的部分：`flutter build ios --simulator --debug` 通过、`xcodebuild -showBuildSettings`
   读到 `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements`、两份 plist/工程文件 `plutil -lint` OK。
   ⚠️ 想手点也行（**先把账号登回来**，否则列表还是空的）：左栏点**最上面那个蓝色的项目图标**
   （不是黄色文件夹）→ 编辑器左侧 TARGETS 选 **Runner** → 顶栏切到 **Signing & Capabilities**
   → 右上角 **`+ Capability`** → 搜 `Health` → 选 **HealthKit**（不是右键菜单里找）。
2. **乐刻到底往不往系统健康库里写体成分**。
   ❌ **2026-10-09 用户决定：这一条不做了。** 所以"真的读到数"就一直没验（见 §七末）——
   功能本身不受影响：健康库里没数据时它如实说"没找到"。
   ⚠️ **我在网上找过了（2026-10-09），没有公开答案**：搜到的全是应用商店的下载页与介绍页，
   没有任何一处说明它写不写 HealthKit / Health Connect。这件事的权威答案只在**你那台手机的
   健康库里**（下面那条路），所以别再从网上找 —— 一分钟能亲自看完。
   在 iPhone「健康」App → 右上角头像 →「隐私与安全」→「App」里找乐刻，
   看它有没有"写入"体重/体脂率这类权限。**有** → 我们读健康库就等于读到了乐刻的体测；
   **没有** → 这条路对"从乐刻同步"这件事就无效，只能回到手动录入（或照抄表单）。
   Android 那边同理：Health Connect → 应用权限里看乐刻。

## 五、这一份落地之后的样子（说清"做完是什么体验"）

* 「身体数据」页顶部多一行入口：「从系统健康同步（可选）」；
* 第一次点它 → 单独同意门（说清只读哪些、只在本机、随时可关）→ 系统权限弹窗 → 拉一次；
* 拉进来的记录带"来自健康"标记，和手记的并存；
* 「设置 → 隐私与关于」里能看到这个开关的状态，并能撤回（撤回后不再读，**已读进来的历史保留**
  —— 与身体数据那条 PIPL 口径一致：撤回的是同意，不是数据）。

## 六、明确不在这一版里

* ❌ 写回健康库（双向）
* ❌ 后台/定时同步
* ❌ 心率、睡眠、运动记录（训练记录我们自己有，Apple 那边是 Workout 类型，语义对不上）
* ❌ 与乐刻做任何"账号级对接"（它没有公开 API，见 `docs/plan-ux-2026-10-08-b.md` §三·5）

## 七、落地情况（2026-10-09 更新：**iOS 做完了，Android 还没做**）

**做完了的（iPhone）**：

* 合规先落地：`docs/privacy-facts.json` 新增 `healthSync` 块；中英政策各新增 §2.4
  「从系统健康库读取（可选）」；`tool/privacy-audit.mjs` 新增 ⑩之六 把三头对起来
  （政策说法 ↔ 代码里那道单独同意与撤回入口 ↔ **只读不写**：Swift 里 `toShare` 必须是空数组、
  Info.plist 里不许出现写回用的用法说明）；应用内「个人信息收集清单」多一节；
  两张商店表单各加一行/一节；
* 权限：`NSHealthShareUsageDescription`（**故意不写** `NSHealthUpdateUsageDescription`）；
  HealthKit 能力早在 v1.65 前那一版就挂进工程了（`Runner.entitlements`），
  免费 Apple ID 也签过（见 §四·1 的真机证据）；
* 代码：`app/lib/health/health_bridge.dart`（通道 `lianleme/health`）、
  `app/lib/health/health_sync.dart`（**先看同意、再碰平台**；按本地日分组，每个字段取那天最新值）、
  `app/ios/Runner/HealthBridge.swift`（HealthKit 只读三样）；
  合并规则落在 `BodyMetricRepository.mergeHealthDays`（同一个事务；
  **我们的字段不覆盖**，只补缺的；那天只有系统有就新建并写备注「来自系统健康」；
  **用户删过的那天不复活**）；
* 同意门：`user_profile.health_consent_at_ms`（**这一版加的**，是 v25 那次迁移；库现在到 v29），
  页面上的入口 `Key('health-sync-entry')`、同意框 `health-consent`、撤回 `health-revoke`；
* 测试：`app/test/health_sync_test.dart` 22 条（含"**没同意时桥一次都没被调用**"、
  "两道门互不干扰"、"安卓上这个入口根本不出现"）；
* **真机/真运行时验过的两件事**（不只是单测）：
  1. `app/integration_test/health_entry_gate_test.dart` —— 同一份测试**在真的 iOS 与真的安卓上各跑一遍**：
     iOS 模拟器上 `entry=shown`、安卓模拟器上 `entry=hidden`，两次都过。它补的正是单测补不上的那一段：
     单测里平台是 `debugDefaultTargetPlatformOverride` **伪装**的，而这条走的是真 App + 真平台判断 + 真导航路径。
     ⚠️ 它**故意不去点那个入口** —— 点下去第一个副作用是系统级健康授权弹窗，那是测试框架既点不到也关不掉的 UI，
     整条测试会永远卡住（与"Mac 锁屏时钥匙串弹窗卡住 `codesign`"同一类问题）；点进去之后的流程由假桥那 22 条覆盖；
  2. 那张卡在真 iOS 运行时里的样子：`docs/images/legacy-5tab/v165-health-sync-card-ios.png`
     （模拟器实拍：标题 + 「只读体重、体脂率、身高 · 可选」+ 右侧箭头，位置在摘要卡下面、「记这一天的」上面；
     同时那一趟 `overflowed` / `RenderFlex` 计数为 **0**，没有布局溢出）。

**与施工单（§三③）还有三处差别，一并写清楚**（免得下一个人对着施工单找不存在的开关）：

1. ~~编译期开关~~ → **没有这个开关**，换成"**平台自己回答能不能读**"（`HealthBridge.isAvailable`）。
   施工单当初是照云备份那套抄的（`isCloudBackupConfigured`），但那套的理由是"**服务端地址是编译期配置**"——
   健康库这件事**没有任何编译期配置**，硬加一个开关只会多一个能配错的东西。
   而"商店审核看到申请了健康权限却没有入口"那个担心也不成立：入口**照能力出现**，
   能读的设备上一定有入口，读不到的设备上一定没有。
2. 服务的方法名是 `sync()` 不是 `pull()`：它比"拉一把"多做了一步 —— 拉回来要**按天合并进库**、
   再把逐日结果（新建几天 / 补了几天 / 几天没动）报给界面。形状在 `app/lib/health/health_sync.dart`。
3. **假实现放在测试里**（`app/test/health_sync_test.dart` 的 `FakeHealthBridge`），不放 `lib/`——
   与仓库里 `FakeReminder` / `_FakeScreenAwake` / `FakeBackupTransport` 的惯例一致
   （`lib/` 里只有 `NoopHealthBridge`，那是"平台没实现"的降级实现，不是测试替身）。

**与 §五 那份"落地之后的样子"有一处**有意的差别**：§五 说「设置 → 隐私与关于」里也能看到这个开关、
并撤回；实际做的时候**只把撤回入口放在「身体数据」页**（`Key('health-revoke')`，与身体数据那道门并排）。
理由是这个仓库自己的一条原则：**收集发生在哪儿，撤回入口就该在哪儿** —— 而这一页就是数据进来的地方。
再在设置里放第二个撤回按钮，等于同一个动作有两个入口、两处文案要同步（而 PIPL 要的是"提供撤回方式"，
它已经提供了）。**如果以后觉得设置页也该有**，加的是"状态 + 跳转"，不该再加一个能直接撤回的按钮。

**Android 那一半：2026-10-09 也做完了 —— 但方式和当初计划的**不一样**，这里要说清楚。**

计划里写的是"抬 `minSdk` 24→26 + 加 `androidx.health.connect:connect-client`"。真去做的时候查了两件事，
换了另一条路：

* **那个 Jetpack 库确实要求 minSdk 26**：把 `connect-client-1.1.0.aar` 下下来解开看，
  它的 `AndroidManifest.xml` 里就一行 `android:minSdkVersion="26"`（这不是猜的，是读出来的）。
  用它就得放弃 Android 7 的用户 —— **那是产品承诺，不是顺手能改的数字**。
* **而 Android 14+ 的 Health Connect 是系统内置的**：平台自己就有
  `android.health.connect.HealthConnectManager`（`readRecords` 等）与
  `android.permission.health.READ_WEIGHT` / `READ_BODY_FAT` / `READ_HEIGHT` 三个运行时权限
  （2026-10-09 从 `android.jar`（`$ANDROID_SDK_ROOT/platforms/android-36/` 那一份） 里逐个读出来的）。
  **一行依赖都不用加**，也就没有"新 SDK → 政策依赖表 + 两张商店表单各加一条"那笔连带账 ——
  与这个仓库"依赖越少越好"的一贯做法一致。

所以落地的是：`app/android/app/src/main/kotlin/com/sdknwdtvpv/lianleme/HealthConnectApi34.kt`（整份标 `@RequiresApi(34)`，
只有真走上 34+ 那条分支时才会被加载，老设备上连类都不解析）+ `HealthBridge.kt`（通道与权限请求）
+ manifest 里三条**只读**权限。

**代价说清楚**：**Android 13 及以下读不到**（那一档要靠 Jetpack 库 + 抬 minSdk 才能覆盖）。
所以那一档上 **`isAvailable` 返回 false，界面上那个入口根本不出现** ——
宁可没有，也不给一个点下去什么都读不到的入口。要不要为 Android 8–13 再走那条路（抬 minSdk + 加依赖），
是**产品决定**，挂在 `docs/your-todo.md` 第 16 条。

⚠️ 顺带改掉施工单里的一处**错**：§三② 原来写的权限名是 `READ_BODY_FAT_PERCENTAGE`，
而平台上**根本没有这个名字**（真名是 `READ_BODY_FAT`）—— 照它写会永远拿不到授权。已就地改掉。

**还没做的（Android 提交侧，不影响功能）**：Play 的**健康数据申报**（入口与要求在
`docs/store-listing.md` §五那节里）与**权限说明里要能点进的隐私政策 URL** ——
后者要等公网政策页的地址定下来（`docs/release-admin.md` §四），所以先不建那个说明页，
免得挂一个打不开的链接。

**产物级也核了**（2026-10-09）：`tool/check-ios-app.mjs` 多一条 —— 拿**真的 Runner.app** 核两件事：
`Info.plist` 里必须有 `NSHealthShareUsageDescription`、**必须没有** `NSHealthUpdateUsageDescription`；
而且只要这份产物是**签过能力的**（`codesign -d --entitlements` 读得到非空字典），就必须带
`com.apple.developer.healthkit`。真机那份读出来是「用法说明是只读那一句 · 签名里带 healthkit」，
模拟器那份读出来是「没带 entitlements（模拟器不签能力），能力那条跳过」—— 两条分支都验过。
⚠️ 判"有没有签能力"要看**字典里有没有键**，不能看那段输出非不非空：模拟器构建会打印一份合法的
**空字典**，按非空判会误报（加这条时当场踩了一次）。源码级的那一半在 `privacy-audit` 的 ⑩之六。

**验到什么程度**（与 iOS 那半边同一个标准）：编得过（APK 构建）、
`app/integration_test/health_entry_gate_test.dart` 在**真的 Android 16 模拟器**上跑过 ——
`平台说能读=true → 入口出现`（那一台系统里确实有 Health Connect 模块
`com.google.android.healthconnect.controller`）；**没验的**是"真的读到数"，
那要有数据可读（见下一段）。

**还没验的那一件事**（真机上）：从 iPhone「健康」里真的读到数、并进来、显示出来。
代码与构建都验过了（模拟器编译 + 真机安装），但"健康库里有数据 → 并进本机"这一步
需要健康库里**真的躺着**体成分记录（§四·2 那件事查完才知道有没有）。

---

## 八、腰围（2026-10-09 落地：10.9 清单第 9 条）

用户 10.9 拍板：「**腰围**先接；静息心率 / 睡眠 / 步数另给方案（要连合规代价一起说）」。

**腰围为什么可以直接接**：它**不是新的一类数据**。两端系统健康库里它都归在体成分
（HealthKit 的 `HKQuantityTypeIdentifier.waistCircumference`（iOS 11+）、
Health Connect 的 `WaistCircumferenceRecord`），而本机 `body_metric.waist_cm` 这一列
**v20 起就在库里**（v1.52 的「身体数据」扩展）。所以它与其他三样**同一道单独同意门、
同一次读取** —— 不新开一道门、不新加一类敏感数据。

**改了哪儿**（模板就是三样那套，逐层加一格）：

| 层 | 改动 |
|---|---|
| Dart 桥 | `HealthSample.waistCm` + 解析 `waistCm` |
| Dart 同步 | `health_sync.dart` 按天分组时多一个 `waistByDay`；`HealthDayValues.waistCm` |
| 合并 | `mergeHealthDays`：**我们的字段不覆盖，只补缺的**（那一列以前恒为 null，现在真的写）；"那天只有腰围"也算有内容 → 会建一条 |
| iOS | `readTypes` 加 `.waistCircumference`；查询用 `HKUnit.meterUnit(with: .centi)`（与库里 cm 同单位） |
| Android | ⚠️ **读不到** —— 见下面那段"被构建打回来的一次" |
| 合规 | 中英政策 §2.4 + 权限表各加一行；`privacy-facts.json` 加一条权限事实；重新生成 `app/assets/privacy-policy.txt` 与收集清单、公网政策页 |
| 界面 | 「从系统健康同步」那一行的小字、同意框正文、空态提示都从"三样"改成"四样" |

**验收**：`privacy-audit`（代码 ↔ 事实 ↔ 政策三方对账）绿；
`health_sync_test` 新增三条 —— 腰围按字段各取最新、**只量了腰围的那天也要建记录**、
用户自己记过的腰围**不许被覆盖**（"我们的字段不覆盖，只补缺的"）。

### ⚠️ 被构建打回来的一次：**Android 读不到腰围**（2026-10-09，值得记下来）

上表原来写的是"Android 加一条 `READ_WAIST_CIRCUMFERENCE` + 查 `WaistCircumferenceRecord`"，
依据是"两端的健康库里腰围都归在体成分"。**那是我的推测，不是事实** ——
`flutter build apk --release` 当场红：

```
e: HealthConnectApi34.kt:12:41 Unresolved reference 'WaistCircumferenceRecord'.
```

顺着查了两处，都指向同一件事：

* `android-36` 的 `android.jar` 里 `android/health/connect/datatypes/` 下**没有**任何
  Waist 类（只有 WeightRecord / BodyFatRecord / HeightRecord / BoneMassRecord…）；
* `android.health.connect.HealthPermissions` 的常量表里**没有任何 WAIST**
  （`javap` 打出来 30 多条 READ_*，READ_WEIGHT / READ_HEIGHT 在，WAIST 一个都没有）。

也就是说：**Health Connect 没有"腰围"这一类数据**，Android 这一端根本读不到它 ——
只有 HealthKit（iOS）有 `waistCircumference`。

于是这一条的落地形状变成**两端不一样，而且界面上也这么说**：

| | 读哪几样 |
|---|---|
| iPhone | 体重、体脂率、身高、**腰围** |
| Android | 体重、体脂率、身高（**三样**） |

* manifest 与 `READ_PERMISSIONS` 都**没有**加那条不存在的权限（加了就是一条假声明，
  `test/reminder_test.dart` 的穷举清单也会红 —— 它本来就该红）；
* 界面上的小字与同意框正文走新的纯函数 `healthReadSummary(TargetPlatform)`
  （与 `healthEmptyHint` 同一套做法）：Android 上写"三样"，不写腰围；
* 中英政策 §2.4 改成**分平台**写清哪几样，权限表里删掉那一条；
* `privacy-facts.json` 里那条权限事实也删掉（事实源不能留一条代码里没有的权限）。

**教训**（与仓库里其它"猜 vs 查"的教训同源）：**"另一个平台大概也有"不是一条事实**。
两端的能力表都要**从 SDK 里读出来**再写——这次是构建帮忙拦住的，而它拦住的原因
恰好是"编译不过"；如果那边只是"权限名写错、编译能过"，就会一路进到用户的手机里。

⚠️ **还没验的**：真机上从健康库读到腰围（**只有 iPhone 有这条路**；与另外三样同一件没验的事，
见 §七末段）。

## 九、静息心率 / 睡眠 / 步数：方案与**合规代价**（2026-10-09，待拍板）

用户要的是"连合规代价一起给方案"。结论先说：**这三类与体成分不是一回事**，
接它们不是"再加三列"，而是**开一个新功能**。

### 9.1 为什么不能顺手接

| 面 | 体成分（现在这四样） | 心率 / 睡眠 / 步数 |
|---|---|---|
| 数据性质 | 用户**自己量**的身体数值 | **连续的行为与生理监测数据**（睡眠阶段、全天心率、逐小时步数） |
| 数据量 | 一天 0–3 条 | 睡眠一晚几十段、心率一天上千点、步数随时更新 —— **差 3–4 个数量级** |
| 本机要不要存 | 一天一行（`body_metric`） | 我们现在**没有**放它的地方：按天聚合要新表，按点存要新库（体积、备份、导出全变） |
| 敏感度 | 敏感个人信息（PIPL 第 29 条，一道单独同意） | 敏感个人信息，**而且更"可推断"**：睡眠与心率能推出作息、饮酒、疾病、怀孕 |
| 系统权限 | 一次读权限 | iOS 是**每个类型一条**读权限（静息心率 / 睡眠分析 / 步数），Android 同样是**三个独立权限**；睡眠在 iOS 还要 `NSHealthClinicalHealthRecords` **之外**的额外说明 |
| 商店申报 | 一行 | Apple 的 Health 用法说明、Google Play 的**健康数据申报**都要**逐一**写清新用途 |

一句话：**多一类就要多一轮「代码 + 政策中英 + 两张商店表单 + 隐私事实表 + 收集清单」的对账**，
而这一轮的成本与"多读一个体重字段"完全不是一个量级。

### 9.2 真要接，先回答"读来给用户看什么"

这是那份方案里**最该先答的一问**（答不出来就是白拿权限）。三类里各自成立与不成立的用途：

| 类型 | 成立的用途（我建议） | 不成立的用途（**不要做**） |
|---|---|---|
| **静息心率** | 在「进步」上画一条**长期趋势**（月度均值），与训练量放在一起看 —— 恢复状态的粗略信号 | ❌ 不要做"今天该不该练"的判断（证据不足，而且会被当成医嘱） |
| **睡眠** | 只显示**时长**（昨晚睡了几个小时）+ 与训练日的对照（练得重的第二天睡得更长？） | ❌ 不要显示睡眠分期（深睡/REM）做成"睡眠分"——那是把系统的黑箱再包装一次 |
| **步数** | **几乎没用**：我们的用户来记力量训练，步数既不进容量也不进连续天数 | ❌ 不要拿步数凑"活动量"徽章（会诱导刷步数） |

**我的建议**：按**静息心率 → 睡眠时长**的顺序做，**步数不做**（说不出用途就不申请）。
而且第一步只做**静息心率的月度趋势**，不做任何判断性文案。

### 9.3 施工量（如果做静息心率这一条）

| # | 改哪 | 内容 | 量级 |
|---|---|---|---|
| 1 | 新表 `resting_hr_daily`（date + bpm + 来源） | 只存**按天聚合**的均值，不存逐点（体积与备份范围都可控） | 中 |
| 2 | 桥 + 两端原生 | iOS `restingHeartRate`（一条读权限）；Android `RestingHeartRateRecord` + `READ_RESTING_HEART_RATE` | 中 |
| 3 | 同步与合并 | 与体成分**同一道同意门**（它也是"从系统读"，不是新目的），但**新增一类数据** → 政策要单独点名 | 小 |
| 4 | 界面 | 「进步」页加一张长期趋势卡（复用 `ViAreaChart`） | 小 |
| 5 | 合规四件套 | 政策中英各一段 + 权限表一行 + `privacy-facts.json` + 两张商店表单 | **中**（这一项是最容易被低估的） |
| 6 | 测试 | 同步/合并/不覆盖/权限未给时不读（与体成分那几条同构） | 小 |

**结论（给他拍板的三件）**：
1. **接不接**：我建议**先只接静息心率**那一条（月度趋势），睡眠与步数先不做；
2. **存多久**：按天聚合、**只留最近 2 年**（与"长期趋势"这个用途对得上；
   逐点数据不存，否则备份体积与"删除权"都跟着变难）；
3. **那段文案**：只说"这是从系统健康读来的静息心率趋势"，**一个字都不做健康建议**。

⚠️ 这三条一旦点头，**清单里的第 5 项（合规四件套）必须与代码同一批做完** ——
先上代码后补政策，在这个仓库里是硬红（`privacy-audit` 会当场判）。
