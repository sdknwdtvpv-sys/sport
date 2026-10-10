# 练了么 · VI 复核方案 D —— 动效（2026-10-10）

> **复核人立场**：动效设计师（iOS/Android 双端系统级动效规范 + Flutter 落地）。
> **只读代码与证据图，不动一行代码。**
>
> **复核范围（按要求的顺序走了一遍）**：
> `docs/interaction-spec.md`（§7 手势 / §8 动效与触觉 / §9 无障碍 / §11 反模式 / §12 验收清单）→
> `app/lib/core/theme.dart`（令牌）→ `core/app_tab_bar.dart` / `core/native_tab_bar.dart` /
> `core/native_segmented.dart` / `core/glass_overlay.dart` / `core/glass_surface.dart` /
> `core/app_top_bar.dart` / `core/glass_segmented.dart` / `core/vi_cards.dart` / `core/vi_area_chart.dart` →
> `features/workout/workout_screen.dart` / `workout_controller.dart` / `workout_session.dart` /
> `haptics.dart` / `rest_cue.dart` / `rest_activity.dart` →
> `features/summary/workout_summary_screen.dart`（完成页 + `summary-unlock`）→
> `app/lib/main.dart`（外壳 / 冷启动 / `_selectTab` / `PageView` / 三道路由）→
> `features/onboarding/*`（`privacy_consent_screen.dart` / `intro_carousel_screen.dart` /
> `onboarding_screen.dart`）→ `features/progress/progress_screen.dart` / `achievements_screen.dart` →
> `docs/screens.md`（S0/S1/S4/S7/S16/S18）→ `docs/plan-ux-2026-10-10.md`（刚落地的大改版）→
> `vi/splash-screen.html` / `vi/onboarding.html` / `vi/rest-timer.html` / `vi/complete-library.html` /
> `vi/tab-icon-system.html`（客户原始 VI 里**已经画出来的**动效意图）→ **看图** 12 张
> （`store-assets/screenshots/00-intro|01-home|05-workout|06-workout-logged|07-summary.png`、
> `docs/images/workout-2026-10-10/workout-05-with-history-resting.png`、
> `docs/images/p01-motivation-2026-10-10/p01-01-summary-unlock.png`、
> `docs/images/p02-3tab-2026-10-10/home-01-first-launch.png`，以及
> `app/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png` 的逐点采样）→
> `app/ios/Runner/GlassBridge.swift`（原生弹簧的**真参数**）→
> `docs/vi-proposal-a-typography-2026-10-10.md` / `vi-proposal-b-*.md` / `vi-proposal-c-brand-2026-10-10.md`
> （C 那份已经列了 18 条动效方向，本文与它衔接、不打架，**只在两处修正它**）。
>
> ⚠️ **本文不用 markdown 表格**（`tool/check-doc-tables.mjs` 会扫 `docs/*.md`）。
> ⚠️ **本文只提方案，不改任何代码、不跑构建。** 所有数字都是数出来的，统计口径写在每一节里。

---

## 一、一句话诊断

**这个 App 没有"动感"问题，它有"不存在"问题：36986 行动布里，动画控制器 0 个、Tween 0 个、Ticker 0 个 ——
它现在唯一真正的"动效"是三处补间，而其中一处是错的，另两处用户根本看不到。**

**证据（口径：`grep` 整个 `app/lib`，129 个 dart 文件、36986 行）**

- `AnimationController` = **0**、`Tween` = **0**、`TickerProvider` = **0**；
  `AnimatedContainer` / `AnimatedOpacity` / `TweenAnimationBuilder` / `Hero(` / `AnimatedSwitcher` /
  `AnimatedList` / `AnimatedScale` = **全部 0**。
- `Curves.` = **2** 处，就是全部的曲线资产：
  `app/lib/main.dart:277`（`_selectTab` 的 `PageView.animateToPage`，`Curves.easeOutCubic`）
  与 `app/lib/features/onboarding/intro_carousel_screen.dart:154`（引导页指示点，`Curves.easeOut`）。
- `Duration(milliseconds` = **5** 处，其中 3 处不是动效而是时长计算
  （`domain/models.dart:457`、`analytics/flusher.dart:51`）与触觉节奏
  （`features/workout/haptics.dart:64`）。**真正的 UI 时长只有 2 个数字：220 与 260 + 90×距离。**
- `disableAnimations` / `reducedMotion` / `accessibleNavigation` = **0 命中** ——
  `interaction-spec.md` §12 那条「`prefers-reduced-motion` 下无动效残留」是**写给一个不存在的实现**的判据。
- `onTapDown` / `onTapUp` / `onTapCancel` / `Matrix4` / `Transform.scale` = **0 命中**，
  而 `buildAppTheme()` 里写着 `splashFactory: NoSplash.splashFactory`：
  **这个 App 的每一个按钮，按下去没有任何反馈**——不是"反馈很弱"，是屏幕上一帧都不变。
- `pageTransitionsTheme` = **0 命中**：38 处 `MaterialPageRoute` 全走 Flutter 的**平台默认**。
  iOS 上那恰好是对的（`CupertinoPageTransitionsBuilder` 带视差与边缘返回手势），
  Android 上走 Material 的 `ZoomPageTransitionsBuilder`。**也就是说：同一台产品，两台设备的
  二级页转场是两套完全不同的动效语言，而规格书里从来没定义过二级页转场。**
- `RefreshIndicator` = **0** 命中、骨架屏 = **0**、`Shimmer`/`Skeleton` = **0**；
  `CircularProgressIndicator` = **21 处**（22 命中里 1 处是注释）——**这个 App 的"加载"只有一种语言：转圈**。
- 触觉 **11 处命中、3 个真实触发点**（`haptics.dart` 的 `setLogged` / `restFinished` / `targetReached`），
  三者全部走 Flutter 自带 `HapticFeedback`，且 `targetReached` 的"两下"是
  `haptics.dart:64` 的**全仓唯一一处 `Future.delayed`** —— 它**不参与帧时间**，
  一旦掉帧，两个脉冲的间隔就会漂（而"轻-轻"与"单次重"的区分全靠这个间隔）。
  **11 处触觉、0 处与之同帧的视觉变化**（唯一勉强算同步的是 `setLogged`，
  但那一行"长出来"的新行本身没有任何入场动画）。

**最刺眼的一处错误**（这是本文 §四 第 1 条要修的东西）：

`workout_screen.dart` 的休息条是一条 3pt 的 `LinearProgressIndicator`，图上写的是
**`还剩 99%`**（看图：`docs/images/workout-2026-10-10/workout-05-with-history-resting.png`），
而它旁边那条进度条的 `value` 是 `1 - restRemainingSec / total`——**填的是"已经过掉的百分比"**。
于是**数字在减少、进度条在增长**，两个方向相反的信号并排放在同一行里，而这一行是核心场景
（组间 60 秒）里唯一的时间线索。就算不管动效，这一条今天就是错的；加了动画只会让它更明显。

**一句话**：**规格书上写着"记录一组 = 新行 280ms pop 入场 + 触觉"，代码里是"一行字瞬间出现 + 手机震一下"；
用户拿到的信息量只有触觉那一条通道，而这条通道在健身房（手机在器械上、环境有震动）本来就最容易丢。
这个 App 的动效缺口不是"不够华丽"，是"没有第二条确认通道"。**

---

## 二、动效令牌表

**两个令牌族，一个文件**：`motion.dart`（**待新建**，放 `app/lib/core/`）——
与 `theme.dart` 并列，是 `Tokens` 的兄弟。**所有动效只许从这里取值。**
另有 `reduced_motion.dart`（**待新建**，放 `app/lib/core/`）持有唯一那个降级开关。

### 2.1 时长档（5 档 + 2 个专用值）

- **`Motion.instant` = 100ms** —— 用在：按下态（`onTapDown`）、触觉的视觉锚点、颜色类变化
  （选中态换色、进度条变色）。
  取值理由：60Hz 下 100ms ≈ 6 帧，是一只手能分辨"有反应"与"没反应"的下限；
  98 或 104 都不必——**这一档不要动**，它已经贴着感知阈值的上沿。
- **`Motion.fast` = 180ms** —— 用在：松手回弹（120～180 区间，取 180 是因为它同时要覆盖
  "未读点出现""休息条变色"），局部小元素（≤ 24pt）的入场。
- **`Motion.base` = 260ms** —— **默认档**。用在：位移（页面推入用 300，见 §2.3）、
  弹层入场、卡片/横条入场、新行入场（280 是它的近亲，见下）、Tab 指示器落位。
- **`Motion.slow` = 400ms** —— 用在：PR 徽章的"到达"（唯一允许大过冲的位移类）、
  数字滚动（容量/时长/组数的计数）、`ViProgressBar` 的填充、面积图曲线形变。
- **`Motion.celebrate` = 600ms** —— **只给"训练完成那一刻"的数字计数用**（一屏一次）。
  它不是"第六档时长"，它是**编排里的一个节拍**：600ms 是读一个 3–4 位数从 0 滚到终值、
  眼睛来得及跟上的最长值；再长就变成"等它"。
- **专用 `Motion.restTick` = 1000ms** —— **休息条那一根进度条的线性补间**，见 §四 第 3 条。
  它不是"慢"，它是"把每秒一跳的离散值补成连续运动"。
- **专用 `Motion.pageTransition` = 300ms** —— 二级页位移 + 淡入。
  理由：iOS 系统 push 是 350ms，Material 是 300ms，**取 300 会让两端都不觉得慢**；
  而它必须与 `CupertinoPageTransitionsBuilder` 的返回手势共存（见 §九 第 4 条）。

原则：**位置变化按距离选档（同屏内 260，跨屏 300），其余一律按"要不要被看见"选档**。
一个动效写不出它属于哪一档，说明这个动效不该存在。

### 2.2 曲线档（4 档 + 1 个 iOS 原生）

全部写成 `Cubic` 的具体数值，并给出等价的 `Curves.` 名。**括号里是 u = (x1,y1,x2,y2)。**

- **`Motion.standard` = (0.0, 0.55, 0.45, 1.0)** —— **位置与尺寸的默认曲线**。
  无过冲、单调收敛，比 `Curves.easeOutCubic` (0.33,1.0,0.68,1.0) 前段更"给力"、
  比 `Curves.easeOutQuint` (0.22,1.0,0.36,1.0) 尾段更"收得住"。
  Flutter 侧写 `const Cubic(0.0, 0.55, 0.45, 1.0)`（**`Curves` 里没有这一档，必须自己建**）。
- **`Motion.enter` = (0.16, 1.0, 0.30, 1.0)** —— **入场**（元素从无到有）。
  ≈ `Curves.easeOutQuint` 的语感，但起点更缓（0.16 而不是 0.22），
  于是"出现"这件事看起来是**被放上去的**，不是"弹出来的"。
- **`Motion.exit` = (0.42, 0.0, 1.0, 1.0)** —— **出场**。
  与 `Curves.easeIn` 完全等价（`Curves.easeIn` 就是 (0.42,0,1,1)），所以这里**直接用 `Curves.easeIn`**。
  唯一纪律：**出场时长必须是入场时长的 0.7 倍**（260 进 → 180 出）。出场比入场慢 = 页面在"赖着不走"。
- **`Motion.arrival` = (0.34, 1.56, 0.64, 1.0)** —— **"到达"类**：指示器落位、PR 徽章出现、
  新增组数字弹一下。等价于 `Curves.easeOutBack`（实测峰值 y = **1.0978**，即 **9.8% 过冲**）。
  ⚠️ **只用于"到达"（元素已经在屏幕上、只是换了位置/尺度），不用于"出现"** ——
  这条 `vi-proposal-c-brand-2026-10-10.md` §3.3 已经写过，我**同意并且给出可执行判据**：
  出现类动画用 `arrival` 直接判不合格，因为"从 0 放大到 1 并过冲"会在屏幕上留下一圈溢出的
  半透明边缘（Flutter 的 `Transform.scale` 不裁剪，这是真会看到的脏边）。
- **`Motion.iosSpring`** —— iOS 原生控件的那根弹簧，**参数不是我编的**，是从仓库里量出来的：
  `app/ios/Runner/GlassBridge.swift:542-552` 与 `:569-580` 写死了两组：
  - **按下**：`duration 0.42s, usingSpringWithDamping 0.32, initialSpringVelocity 1.0`
    → 阻尼比 ζ = 0.32 → **过冲 34.6%**（"Q 弹"，会过冲再收）；
  - **落位/松手**：`duration 0.5s, damping 0.72, velocity 0.3`
    → ζ = 0.72 → **过冲 3.8%**。
  **Android/Flutter 那一条必须向 ζ = 0.72 那一组对齐**：`Motion.standard`（0 过冲）用于位移，
  `Motion.arrival`（9.8% 过冲）用于指示器落位。**9.8% 与 3.8% 差 6 个点，这就是我承认的、
  无法消除的端间差异**（见 §九 第 5 条），但方向、节奏、总时长（260ms vs 原生 0.5s 的
  视觉可感段落 ≈ 300ms）是对齐的——手不会觉得"换了个 App"。

### 2.3 什么时候用哪一档（属性 × 档位，直接可查）

- **位置变化（位移 / 转场 / 滚动跟随）** → 默认 `Motion.standard`；
  跨屏位移用 `pageTransition`(300ms) + `standard`；指示器落位用 `base`(260ms) + `arrival`。
- **尺寸变化（放大缩小 / 高度展开 / 进度填充）** → `standard`；
  用户按下的缩放用 `instant`(100ms) + `Curves.easeOut`（下压）；
  松手回弹用 `fast`(180ms) + `arrival`；
  进度填充用 `slow`(400ms) + `standard`，**只有休息条那一条例外**（`restTick` + `Curves.linear`）。
- **透明度** → **恒不用带过冲的曲线**（过冲会让 alpha > 1 被裁、视觉上是"闪一下"）。
  入用 `base`(260ms) + `enter`，出用 `fast`(180ms) + `Curves.easeIn`。
- **强调（过冲 / 脉冲 / 计数）** → `slow`(400ms) + `arrival`；完成页数字用 `celebrate`(600ms) + `standard`。
- **颜色变化** → 恒 `instant`(100ms) + `Curves.easeOut`（`AnimatedContainer`/`ColorTween` 默认即可）。
  理由：颜色是**状态信息**，不是运动；慢了会让人以为界面卡在半路。

---

## 三、全链路动效清单

> 每条七字段：**触发 / 时长 / 曲线 / 可中断 / 触觉 / reduced-motion 降级 / 验收判据**。
> 编号 `D-xx` 是本方案的编号；`D-01` 与 C 方案 `M-01` 的对应关系在每条尾注里写。
> **可中断性**的定义：动画跑到一半时用户又做了下一个动作（再点一次、反向拖、返回），
> 是"从当前帧继续"还是"从头重来"还是"必须跑完"。

### 3.1 冷启动 → 首页（三道路由）

**背景事实（必须写下来，因为它决定了这一段的设计）**：现在冷启动是**三段**，视觉上互不相干：
① 原生启动图（iOS `LaunchScreen.storyboard` 底 `#0E0C0A`，正中一张 288×288 的 PNG；
Android `launch_background.xml` 底 `#0E0C0A`，正中 `launch_glyph.png`）→
② Flutter 首帧：`main.dart:1832-1834` 在 `_consented == null` 期间渲染
**`Scaffold(backgroundColor: Tokens.bg, body: SizedBox.expand())` = 一块纯色空屏**（没有圆环、没有字标、没有加载点）→
③ 数据库读完，落在同意门 / 引导页 / 首页。
**这块纯色空屏就是白屏闪一下的等价物**——它不闪白，但它闪"什么都没有"，
而它持续的时间正好是 `openAppDatabase()` + `privacyConsentAtMs()` 两个异步读的时长。
**而客户 VI 稿里明明画了这一段**：`vi/splash-screen.html` 有 `.icon-ring`（120pt 圆环、18pt 边框、
`ringPulse 2.5s ease-in-out infinite`）+ `.app-name-cn` 字标 + 三个 `loadDot`（1.4s 周期、错峰 0.2s）。
`vi-proposal-c-brand-2026-10-10.md` 也已经把这一段判成 P0-9「App 内启动过渡」。
**本节把它的时序、可中断性、降级与判据全部补齐。**

- **D-01 原生启动图 → 第一帧：零位移接力**（新增）
  - **触发**：`runApp` 后第一帧（`LianLeMeApp.build`）。
  - **时长**：**不做入场动画**（0ms）。启动图上那颗圆环的位置/尺寸/颜色与 `SplashMark` 第一帧逐点一致，
    于是"接力"是 0 帧的——**这是唯一能让 Flutter App 看起来像原生启动的做法**。
  - **曲线**：无。
  - **可中断**：不适用（瞬时）。
  - **触觉**：无（启动不该震）。
  - **降级**：不变（本来就没有动画）。
  - **验收判据**：① 取 `LaunchImage@3x.png` 的非透明像素包围盒，与 `SplashMark` 在 iPhone 390×844
    逻辑坐标下渲染出的包围盒，**中心点偏差 ≤ 2pt、直径偏差 ≤ 2pt**（一条 Python 采样脚本 + 一条 golden 测试）；
    ② ⚠️ **今天这一步是不成立的，得先修**：`LaunchImage@3x.png` 的**环心是不透明的白色**
    （逐点采样：`(144,144)` = `(251,250,253,255)`，而四角 `(0,0,0,0)`），
    所以原生启动图在深底上渲出来是一个**白饼 + 橙环**（看图即可确认），
    与 App 内那颗空心圆环（`intro_carousel_screen.dart` 的 `_TapArt`，同为 172pt、18pt 边框）**不是一个东西**。
    判据：`LaunchImage@*x.png` 环心 alpha < 8。
  - **衔接**：C 的 M-17。

- **D-02 内启动屏：直接显示、不淡入**（新增）
  - **触发**：`_consented == null` 期间（也就是 D-01 之后的整个异步窗口）。
  - **时长**：**入场 0ms**（首帧就是成品，否则会在启动图之后**再闪一次**——
    这是"启动闪屏"这个坑最常见的踩法：前一段还没消失，后一段已经淡入了一半）。
  - **曲线**：无（入场）。
  - **可中断**：**可中断且必须可中断** —— 数据只要读完就立刻切走，不设"最短展示时长"以外的等待。
  - **触觉**：无。
  - **降级**：入场不变（本来就 0ms）。
  - **验收判据**：① `main.dart` 里 `_consented == null` 那一支渲染的不再是 `SizedBox.expand()`，
    而是 `SplashMark`（圆环 + 字标 + 三个加载点），且**首帧就画**；
    ② 一条 widget 测试：注入一个永不完成的 `privacyConsentAtMs()`，断言屏幕上能找到圆环的 key
    （证明它不是"先空屏再出圆环"）。

- **D-03 加载点：最早 400ms 才出现**（新增）
  - **触发**：D-02 开始计时。
  - **时长**：单点周期 **1400ms**（与 `vi/splash-screen.html` 的 `loadDot 1.4s` 一致），
    三个点错峰 **200ms**，透明度 `0.2 → 1.0`、缩放 `0.8 → 1.2`。
  - **曲线**：`Curves.easeInOut`（两端对称）。
  - **可中断**：可中断（数据读完直接切走；点立刻消失，不做淡出）。
  - **触觉**：无。
  - **降级**：**保留**（它不是装饰动画，它是"还在读"这个事实的唯一表达；
    关掉它，用户看到的就是一张静止的图 —— 那才是不安）。
    但降级时把三个独立点换成**一个静止的不透明点**（不是三个半透明的），
    避免"三个点常亮"被读成"三个通知"。
  - **验收判据**：① `< 400ms` 完成时，屏幕上**找不到**加载点的 key（防"闪一下就没"的脏帧）；
    ② 三个点由**同一个** `AnimationController` 驱动（`grep` 该文件不得出现第二个
    `AnimationController`，也不得出现 `Future.delayed`）。
  - **衔接**：C 的 M-17 后半段。**这一条我加严了两处**：C 写的是"超过 400ms 未完成才显示"，
    但没写"小于 400ms 时不能显示"；也没写三个点必须共用一个控制器。

- **D-04 内启动屏淡出 → 落到目标屏**（新增）
  - **触发**：数据就绪（`_consented` 从 null 变成 true/false，或 `_introPending` 判定完成）。
  - **时长**：**260ms**。
  - **曲线**：`Motion.standard`（透明度 + 一点点缩放 `1.0 → 0.985`）。
  - **可中断**：**不可中断**（260ms 跑完）。理由：这是唯一一次"App 在决定给你看哪一屏"，
    中途反向会在同一次冷启动里暴露两屏。
  - **触觉**：无。
  - **降级**：**保留淡出，但去掉那 1.5% 的缩放**（只做透明度）。
    理由：直接硬切会有跳帧感（C 的 M-18 第②条例外同源）；而缩放是"运动"，
    减弱动态效果下必须去掉。
  - **验收判据**：真机录屏（`xcrun simctl io … recordVideo`）逐帧看：启动图 → 内启动屏 → 目标屏
    三个状态之间**没有任何一帧是"两屏各一半"**（除 D-04 那 260ms），
    且 D-04 的淡出里没有位移。

- **D-05 同意门 → 引导页 → 首页**（新增）
  - **触发**：`_onPrivacyAgreed()`（`main.dart:463`）/ `_onPrivacyDeclined()`（`:450`）/
    `onSkip`（`:1846`）/ `onStartFirst`（`:1847`）。
  - **时长**：**220ms**（沿用 `intro_carousel_screen.dart:153` 已有的那个 220 —— 它是对的，不动它）。
  - **曲线**：`Motion.enter`。
  - **可中断**：可中断（每次推入独立，用户可以连点两下"跳过"→ 第二次无效果，因为页面已经切了）。
  - **触觉**：**一次 `selectionClick`**（在"同意并继续"上；这是不可逆的法律动作，需要一次确认）。
    ⚠️ 「跳过」**不震**（见 §五 的原则："震"要贵）。
  - **降级**：瞬时（`Duration.zero`），但**保留触觉**。
  - **验收判据**：从同意门到首页，`ModalRoute` 层数变化 = 1 帧之内完成（不得出现"同意门在下、首页在上、
    中间夹一层空白"）；引导页的指示点宽度变化（6 → 18）走同一个 `Motion.base`，
    不得仍是硬切（今天指示点**没有动效**，`Curves.` 那 2 处命中里的 1 处是"翻页"而不是"指示点"）。

- **D-06 老用户直接落到「开练」那一屏**（新增）
  - **触发**：`_consented == true` 且 `_introPending == false` → 直接进 `PageView(initialPage: 1)`。
  - **时长**：**0ms**（不动画）。**这一条是刻意的**：老用户冷启动的唯一诉求是"立刻能开练"，
    给首页加一个入场编排（哪怕只有 260ms）就是在北极星指标的分母上加摩擦。
  - **曲线**：无。
  - **可中断**：不适用。
  - **触觉**：无。
  - **降级**：不变。
  - **验收判据**：`main.dart` 里**不得出现**针对 `initialPage` 的入场动画；
    冷启动到"大按钮可点"的时间在真机上 ≤ 1.5s（`docs/ios-device-testing.md` 第 2 条已有的判据）。

### 3.2 外壳（三格底栏 / 顶栏 / 铃铛 / 齿轮）

**背景事实**：iOS 的底栏是**真的 `UITabBar`**（`core/native_tab_bar.dart` + `NativeTabBarBridge.swift`，
`UiKitView` + `EagerGestureRecognizer`），Android 是 Flutter 自绘（`app_tab_bar.dart` 的 `Container` + `Row`）；
外壳在 iOS 上还有 `PageView` 可以左右拖（`main.dart:1900-1924`）。
**这就是整个项目最危险的一段动效，因为它同时有：平台视图、PageView、以及一条平台早返回。**

- **D-07 点底栏切 tab（iOS / 原生 `UITabBar`）**（修正现有）
  - **触发**：原生 `onTabSelected` → Dart `_selectTab(i)`（`main.dart:269`）。
  - **时长**：`260 + 90 × |i − from| ms`（**保持现值**，C 的 M-11 也主张保留）。
    i=开练→我 是 260，进步→我 是 350。
  - **曲线**：`Motion.standard`（现在是 `Curves.easeOutCubic`，**改掉**：
    easeOutCubic 前段太软，跨 2 格时会觉得"起步慢、末段冲"）。
  - **可中断**：**可中断，且这是必须做对的一条** —— 用户连着点两个不同的格时，
    第二次 `animateToPage` 必须从**当前页位置**出发（`PageController.animateToPage` 天然如此），
    不得 `jumpToPage` 抢帧。
  - **触觉**：**无**（C 的 H-12，我同意）。理由写在 §五：底栏是最高频动作，每次震会让整条通道钝化。
  - **降级**：瞬时（`jumpToPage`），**但指示器仍然要落位**（那是状态，不是装饰）。
  - **验收判据**：① 指示器（原生那颗胶囊）的落位由**原生自己**完成，Dart **不得**再叠一层补间
    （见 §九 第 5 条：不许 Dart 追 UIKit）；② 一条 widget 测试断言 `_selectTab` 的
    `duration` 计算式对 `|i−from|=0/1/2` 分别给出 260/350/440；③ 真机：连点"进步 → 我 → 进步"
    三次不出错帧。

- **D-08 点底栏切 tab（Android / Flutter 自绘）**（新增）
  - **触发**：`AppTabBar` 的 `InkWell.onTap` → `onChanged(i)`。
  - **时长**：同 D-07（260 + 90×距离）。
  - **曲线**：`Motion.standard`。
  - **可中断**：同 D-07。**⚠️ 但 Android 今天根本没有过渡**：`_selectTab` 在
    `if (!GlassSurface.isSupportedPlatform) return;`（`main.dart:273`）**之后**才动画，
    所以 Android 上是**瞬切**——`vi-proposal-c-brand-2026-10-10.md` 【P0-11】已经点名过这一条
    （"同一台产品，两台设备的 Tab 切换是两种手感"）。**本条要删掉那句平台早返回**，
    Android 也走一个 `PageView`（或在 `_bodyFor` 外面套一层 `AnimatedSwitcher` + 水平位移）。
  - **触觉**：无（与 D-07 一致）。
  - **降级**：瞬时。
  - **验收判据**：`grep "isSupportedPlatform" app/lib/main.dart` 在 `_selectTab` 内**0 命中**；
    一条 widget 测试（跑在 Android 目标平台上）断言切 tab 后 260ms 内页面的水平偏移单调递减到 0。

- **D-09 PageView 拖动时的顶栏标题切换**（新增）
  - **触发**：`onPageChanged`（`main.dart:1908`）—— 注意它只在**落页**时触发，
    所以标题是"松手后换"，拖到一半时顶栏还写着上一屏的名字。
  - **时长**：**180ms**（比页面位移短，因为标题是"跟着页面走的从属信息"，
    同速会让它看起来像主体的竞争者）。
  - **曲线**：`Motion.enter`。
  - **可中断**：可中断（反向拖回去时，标题文字回退到上一屏，不从头淡入）。
  - **触觉**：无。
  - **降级**：瞬时（`Duration.zero`）。
  - **验收判据**：拖到 `page = 0.5` 时**不得**出现两屏标题交叉淡入（那会读成"标题也在一页页翻"），
    必须是**一个标题先走完再换下一个**；实现上就是 `AnimatedSwitcher` 而不是两行 Text 叠着改 opacity。

- **D-10 未读点数变化（铃铛上那个点）**（新增）
  - **触发**：`_unreadNotifications` 从 0 → >0（`main.dart:646`）；以及 >0 → 0（读完了）。
  - **时长**：出现 **180ms**（`scale 0.6 → 1.0` + 淡入）；消失 **100ms**（淡出，不缩）。
  - **曲线**：出现 `Motion.arrival`；消失 `Curves.easeIn`。
  - **可中断**：可中断（连收两条消息时，第二次出现从当前 scale 继续）。
  - **触觉**：**无**。理由：未读点是"回头看"的信息，不是"现在动手"的信息，
    用户在训练中不需要被它打断。⚠️ 这与 C 的 H-15（M-15 未读点）**不冲突**——C 只给了动效、没给触觉。
  - **降级**：瞬时出现（不留 `scale`，直接显示终态）。
  - **验收判据**：① `app_top_bar.dart:164-172` 那个 `Container` 不再是裸的（今天它硬切）；
    ② 一条 widget 测试：`unread: 0 → 3` 后 `pump(180ms)` 与 `pump(400ms)` 的
    `Transform.scale` 值分别为**中间值**与 **1.0**（证明它真的在动，且会停）。

- **D-11 齿轮出现/消失（只在「我」那一格）**（新增）
  - **触发**：`_tab` 在 2 与其他之间切换（`AppTopBar.showSettings = _tab == 2`，`main.dart:1874`）。
  - **时长**：**100ms**（`instant`），只做**淡入淡出 + 宽度展开**。
    不做位移（从右边滑进来会与铃铛抢位置，而铃铛是常在的）。
  - **曲线**：`Curves.easeOut`。
  - **可中断**：可中断。
  - **触觉**：无。
  - **降级**：瞬时。
  - **验收判据**：切到「我」时，铃铛的**中心 x 坐标在整段动画里不得变化**
    （一条 widget 测试量 `tester.getCenter`），否则就是齿轮挤动了铃铛——
    那是"布局在动"，比"元素在动"更糟。

### 3.3 二级页转场（全部数据 / 计划 / 成就 / 动作库 / 动作详情 / 设置 / 通知中心）

**背景事实**：38 处 `Navigator.push` **全部**是裸 `MaterialPageRoute<void>`（或 `MaterialPageRoute<T>`），
`pageTransitionsTheme` 0 命中 → **两端各走系统默认，而这个 App 从没决定过它想要哪种转场。**

**我的结论：按"类型"分，而不是按"页面"分。分两类，只分两类。**

- **「查看」类**（结果页：全部数据、成就册、动作库、动作详情、通知中心、设置）
  → **不做自定义转场**。iOS 保持 `CupertinoPageTransitionsBuilder` 的
  **视差 + 圆角 + 边缘返回手势**，Android 保持平台默认。
  理由：① 这两套都是**用户手机里其它 App 的转场**，它是"原生感"的一部分，改掉就是减分；
  ② iOS 的边缘返回手势**与 `CupertinoPageTransitionsBuilder` 是耦合的**，
  自定义转场会丢掉那个能从边缘拖回去的手势——对一个"打开就练"的 App 来说，
  丢掉返回手势是硬伤（健身房单手、屏幕有汗）。
  **这一条是对 C 的 M-12 的修正**：C 主张在 `buildAppTheme()` 里设 `pageTransitionsTheme`
  给 38 处统一换成一个"位移 + 淡入"。**我判它错**，理由见 §八 第 2 条。

- **「选择」类**（动作选择器、单位选择、分享卡样式、计划模板——即
  `MaterialPageRoute<T>` 有返回值的那些）→ **显式给一个转场**：
  从**底部**推入（不是右侧），260ms，`Motion.standard`，返回 `Motion.exit`(180ms)。
  理由：这一类的心智是"**我进来挑一个东西再出去**"，与"我去看一屏内容"不同；
  而从右侧推入与"查看"类完全一样，用户分不出来自己进的是哪一种。
  底部推入在两端都能表达"这是一个模式"。

- **D-12 「查看」类转场：保持平台默认**（新增，一条"不做"的决定）
  - **触发**：`Navigator.push`（查看类，约 22 处）。
  - **时长/曲线**：平台默认（iOS ≈ 350ms，Android Material）。
  - **可中断**：iOS 边缘返回手势**必须可用**。
  - **触觉**：无。
  - **降级**：系统自己处理（iOS 的"减弱动态效果"会给交叉溶解，那是系统行为，我们不干预）。
  - **验收判据**：① `theme.dart` 的 `buildAppTheme()` 里 **不得出现**
    `pageTransitionsTheme:`（一条 `grep` 判定 + 一条单测把"不得出现"钉住，
    与 `test/glass_segmented_test.dart` 最后那条机械扫描同一个思路）；
    ② 真机：从屏幕左边缘 8pt 内起手右拖，能一路拖回上一屏并且中途可取消。

- **D-13 「选择」类转场：底部推入 + 返回值**（新增）
  - **触发**：`Navigator.push<T>`（选择类，约 16 处）。落地方式：一个
    `app_route.dart`（**待新建**，放 `app/lib/core/`）里两个工厂
    `pushView(...)` / `pushPicker<T>(...)`，**38 处逐处改成调它**（不许顺手全改，见 §七 顺序）。
  - **时长**：进 260ms / 出 180ms（入场 × 0.7）。
  - **曲线**：进 `Motion.enter`，出 `Curves.easeIn`。
  - **可中断**：可中断（iOS 上支持从底部下拖关闭；Android 上支持系统返回手势取消）。
  - **触觉**：**一次 `selectionClick`**（推入那一刻）。理由：它是"进入一个模式"，
    模式切换值得一次轻确认；而"查看"类**不震**（那是最高频的导航，同 D-07 的逻辑）。
  - **降级**：瞬时（`Duration.zero`）。
  - **验收判据**：① 选择类页面的 `ModalRoute` 是自建的（一条单测断言
    `pushPicker` 返回的 route 的 `transitionDuration == 260ms`）；
    ② 从页面顶部往下拖能关闭，且拖到 1/3 处松手会回弹（真机手测 + 录屏）。

- **D-14 动作详情 / 动作库的共享元素**（**明确不做**）
  - **结论**：不对动作库列表 → 动作详情做 `Hero`。理由：
    ① 列表行里没有图（`vi-proposal-c-brand-2026-10-10.md` 的图标系统还没落地），
    `Hero` 只能搬一行文字，收益为负；
    ② `Hero` 在 `ListView` 里回收时会撞上"同一 tag 出现两次"的崩溃，
    而这个列表是分页 + 筛选的，风险不值。
  - **替代**：详情页进入时给**标题一行** 180ms `Motion.enter` 的淡入（D-15）。
  - 这一条写下来是为了**防止下一个人顺手加 `Hero`**。

### 3.4 训练主屏（最重要）

**背景事实（这一段的设计全从它出发）**：
`WorkoutController` 每秒 `notifyListeners()`（`workout_controller.dart:811-842` 的 `Timer.periodic(1s)`），
`WorkoutSession` 转发，`WorkoutScreen._onChange()` 里 **`setState(() {})` 整屏重建**
（`workout_screen.dart:128-136`，注释自己写着"`_onChange` 会因为**任何**状态变化被叫到
（记组、休息倒数、切动作…）"）。**所以训练屏每秒整屏重建一次，持续 60 秒。**
这一段的所有动效都必须在这个前提下设计，否则就是把掉帧写进核心场景。

- **D-15 进入训练（从首页大按钮 / 计划 / 继续上次）**（新增）
  - **触发**：`_trainSession(...)` 完成、`WorkoutScreen` 首次 build。
  - **时长**：**只做一件事：大按钮从 0.94 缩到 1.0，180ms**。其余元素**不动**。
  - **曲线**：`Motion.arrival`（按钮是"到达"）。
  - **可中断**：不可中断（180ms），但它不阻塞任何输入（按钮在动画期间就可点）。
  - **触觉**：**无**。理由：用户刚点完首页那颗大按钮，那里已经有一次按下反馈了；
    进门再震一次是重复计数。
  - **降级**：瞬时（按钮直接以 1.0 出现）。
  - **验收判据**：进训练屏后 `pump(0)` 与 `pump(180ms)` 的按钮 scale 分别是 0.94 与 1.0，
    而**"第 N 组""动作 x/y""对照带"这些文字的 opacity 全程恒为 1**
    （不得有整屏的入场编排——那会拖慢"打开就练"）。

- **D-16 记一组：大按钮按下 / 松手**（新增，**这是全 App 最重要的 100ms**）
  - **触发**：`onTapDown` / `onTapUp` / `onTapCancel`（`workout_screen.dart:656-702` 的
    `GestureDetector` 今天一个都没挂）。
  - **时长**：按下 **100ms** 缩到 **0.975**；松手 **180ms** 回到 1.0（**允许 9.8% 过冲**——
    这是"松手回弹"最该用 `arrival` 的地方）。
    ⚠️ 与 `interaction-spec.md` §5 逐字一致（"按压缩放 0.975，时长 100ms ease"），
    **这一条规格是对的，只是没实现**。
  - **曲线**：按下 `Curves.easeOut`；松手 `Motion.arrival`。
  - **可中断**：**必须可中断**：`onTapCancel`（手指滑出按钮）时立刻回弹到 1.0（180ms），
    **且不得触发记录**。这一条今天也不成立（没有 `onTapCancel` 处理器）。
  - **触觉**：按下 **不发**，松手且**真的写库成功**那一刻发 `setLogged()`（`mediumImpact`）。
    ⚠️ 与 C 的 H-01 一致（medium，不是 spec 里写的 light）。
    理由在 §五。
  - **降级**：**不做缩放，但保留触觉**（减弱动态效果不等于失去确认）。
  - **验收判据**：① 一条 widget 测试：`startGesture` → `moveBy(0, 200)` → `up()`，
    断言按钮 scale 回到 1.0 **且** `store.setsFor(workoutId).length` 不变（防误记）；
    ② 真机上"按下→松手"的视觉与触觉同帧（录屏 240fps + `haptics` 的调用点断言：
    `setLogged()` 必须与 `setState` 在同一个同步块里，**不许 `await` 之后才震**）。

- **D-17 记一组：新行"长出来"**（新增）
  - **触发**：写入成功、`done-list` 多一行（`workout_screen.dart:506-546`）。
  - **时长**：**280ms**（`interaction-spec.md` §8 第 1 条的原值，C 的 M-01 也主张保留）。
  - **曲线**：`Motion.enter`；位移 `Offset(0, 6) → 0` + opacity `0 → 1`。
  - **可中断**：可中断（连点两下时两行各自独立入场；
    **不许**用 `AnimatedList` 的队列——那会在快速连点时排队播动画，
    而健身房连点两下是常态）。
  - **触觉**：与 D-16 的 `mediumImpact` **同帧**（同一次 `setState` 之前调用，`unawaited`）。
  - **降级**：**瞬时出现，但保留行的终态**（就是"新行直接在那里"）。
  - **验收判据**：① 记一组后 `pump(140ms)` 时新行的 `opacity` 严格在 (0,1) 之间（证明在动）；
    ② 连点两次（间隔 80ms）后 `pump(600ms)`，两行都在且**没有任何一行的入场被吞掉**。
  - **衔接**：C 的 M-01。**我加的一条**：280ms 与 D-16 的 180ms 回弹是**同一时刻开始的两条并行曲线**
    （手指松手 = 按钮回弹 = 新行入场 = 触觉），三者起点必须是同一帧，否则会听出"震了两下"的错觉。

- **D-18 记一组：组数与"下次建议"数字变化**（新增）
  - **触发**：`set-number`（第 N 组）与 `primaryButtonLabel`（`45 kg × 10 ✓`）变化。
  - **时长**：**瞬时（0ms）**。
  - **曲线**：无。
  - **可中断**：不适用。
  - **触觉**：无（与 D-16 同帧的那一次触觉已经承担了这一组的确认）。
  - **降级**：不变。
  - **验收判据**：这两个文本**不得**包在任何 `TweenAnimationBuilder` / `AnimatedSwitcher` 里
    （一条单测：记一组后 `pump(50ms)` 与 `pump(300ms)` 读到的 label 完全相同）。
    **理由（重要）**：大按钮上写的是"将要写入的值"（`interaction-spec.md` §5 的硬约束）。
    如果这个值在动画，用户在动画中途点下去，写进去的可能是**动画中间那一帧代表的旧值**——
    那是"记录了一个我没同意的数字"。**任何"将要写入的值"都不许有动画。**

- **D-19 休息开始：进度条与倒计时**（**修正现有**，见 §四 第 3 条）
  - **触发**：`_beginRest(...)`（`workout_controller.dart:791`）→ `restRunning == true`。
  - **时长**：进度条**每跳 1000ms 线性补间**（`Motion.restTick` + `Curves.linear`）；
    倒计时数字**每跳瞬时**（不带任何补间，理由同 D-18：数字是"还剩多久"这个事实，
    补间会让它显示一个不存在的秒数）。
  - **曲线**：`Curves.linear`（进度条）；数字无曲线。
  - **可中断**：**可中断，且这是这条设计的核心**：`−15 / +15`（D-21）与"恢复会话"
    都会把 `restEndsAtMs` 改掉，进度条必须在**下一帧**就从当前视觉位置接到新的总时长上，
    不得重头填一遍。
  - **触觉**：**休息开始不震**（把通道留给结束那一下）。
  - **降级**：**进度条改为"每秒一格直接跳"**（去掉补间），数字照旧。
    理由：降级要去掉的是**运动**，不是信息——百分比与颜色都保留。
  - **验收判据**：① 进度条的填充方向与 `还剩 N%` **方向一致**
    （今天的实现是反的：`value = 1 - restRemainingSec/total` 让条在**增长**而百分比在**减少**）——
    一条单测：`restRemainingSec = 0.5 × total` 时条的宽度 ≤ 全宽的 0.55 且 ≥ 0.45，
    且**随剩余时间减少而变短**；
    ② 每次跳动的视觉前进量 ≤ 全宽的 1/总秒数 × 1.2（防"某一次跳了两格"）。

- **D-20 休息结束（归零）**（新增）
  - **触发**：`left <= 0`（`workout_controller.dart:823-837`）。
  - **时长**：进度条颜色 `accent → success` **180ms**；`休息` 二字与 `01:59` 数字
    **弹一下**（scale `1.0 → 1.08 → 1.0`）**220ms**。
  - **曲线**：颜色 `Curves.easeOut`；弹一下 `Motion.arrival`。
  - **可中断**：不可中断（220ms），但**不阻塞**"点大按钮记下一组"——
    用户在弹的那 220ms 里点下去必须立刻记上（这一条今天天然成立，加动画时别弄坏它）。
  - **触觉**：`restFinished()` = **`heavyImpact`**，与颜色变化的**第一帧同帧**（C 的 H-02）。
    ⚠️ 这是**全 App 最重的一次触觉**，也是"触觉是唯一的时钟"这条设计意图的落点。
  - **降级**：**颜色切换保留（瞬时完成）、弹一下去掉**（C 的 M-18 例外③，我同意）。
  - **验收判据**：一条测试断言"颜色变化与 `haptics.restFinished()` 在同一个同步块内调用"；
  另一条测试：`restDone` 那一刻立刻调 `onBigButtonTap()`，新组仍写入
  （防"动画把主按钮吃掉了"）。

- **D-21 −15 / +15 改休息时长**（新增，有一条**强约束**）
  - **触发**：`rest-minus` / `rest-plus`（`workout_screen.dart:818-823`）。
  - **时长**：进度条与数字 **下一帧生效**（`instant`，100ms 内的线性重定位）；
    **不做"从旧值滑到新值"的补间**。
  - **曲线**：`Curves.linear`（进度条重定位）。
  - **可中断**：可中断（连点 +15 三次 = 加 45 秒，每次从当前视觉位置继续）。
  - **触觉**：每次按 **一次 `selectionClick`**（C 的 H-09 同源，但那条讲的是重量步进；
    这里我给的是同一个结论）。
  - **降级**：不变（本来就是瞬时的）。
  - **验收判据**：**点 +15 之后，进度条的总长不允许"从 0 重新长一遍"**。
    这一条是**必须写进测试**的：`restTotalSec` 变化时，条的当前宽度与
    "按新的总时长算出来的宽度"之间的差必须 ≤ 2 帧的移动量。
    **理由**：休息条是"我还剩多久"的唯一空间线索，重填一次等于告诉用户"休息重新开始了"——
    而用户按 +15 的心智恰恰是"延长，不是重来"。

- **D-22 跳过休息**（新增）
  - **触发**：`skip-rest`（`workout_screen.dart:825`）→ `skipRest()`（`workout_controller.dart:518`）。
  - **时长**：**180ms**（整条休息带 `height → 0` + opacity → 0，`AnimatedSize` 或 `SizeTransition`）；
    大按钮**不下移**（它已经贴着屏幕下 1/3，条消失后那块空间留给 `改重量` 行，
    位置变化用同一段 180ms 的 `standard`）。
  - **曲线**：`Motion.exit`。
  - **可中断**：可中断。
  - **触觉**：**不震**。理由：跳过是"我不要这次提示"，用一次震去确认"你取消了提示"是荒谬的。
  - **降级**：瞬时消失。
  - **验收判据**：`pump(90ms)` 时条的高度严格在 (0, 26) 之间；大按钮的
    `top` 在整段里移动 ≤ 4pt（防"跳过之后主按钮跳一下"）。

- **D-23 换动作：左右转场**（新增）
  - **触发**：`session.next()` / `previous()`（`workout_session.dart:71-83`）、
    底部 `next-exercise` / `prev-exercise` 按钮、整屏横向拖拽
    （`_onHorizontalDragEnd`，`workout_screen.dart:116-126`，阈值 200 px/s）。
  - **时长**：**260ms**；位移方向 = 手势方向（下一个从右进，上一个从左进）；
    幅度**只有内容的 12%**（不是整屏宽 —— 整屏滑动会让"这是一次换动作"看起来像"换了一屏"）。
    同时 opacity `0 → 1`。
  - **曲线**：`Motion.enter`。
  - **可中断**：**必须可中断**：手势要求一定速度（今天已实现），
    但**转场一旦开始，反向滑动必须能立刻反向**（用 `AnimatedSwitcher` + `reverseDuration`
    做不到，得用同一个 `AnimationController` 的 `Tween` 反向跑）。这一条是本段最容易做错的地方。
  - **触觉**：**不震**。理由：换动作不是"完成了一件事"，而且它是会**连续发生**的
    （用户可能连翻四个动作找器械），每一次都震会让通道钝化。
  - **降级**：瞬时切换（无位移、无淡入）。
  - **验收判据**：① 转场进行到 130ms 时反向滑一次，画面必须**从当前位置往反方向走**
    （不是先跑完再反向）——一条 `pump` 半程 + 反向手势的 widget 测试；
    ② 拖拽未达 200 px/s 时**不切动作**（已有行为，加动画后不得被破坏）。

- **D-24 撤销一组**（新增）
  - **触发**：长按 `done-list` 里任意一行 500ms（`interaction-spec.md` §7 定的 500ms）。
  - **时长**：被撤销那一行 **180ms 淡出 + 右移 12pt 后整行收起**（`SizeTransition`）；
    上面/下面的行**同时**上移（同一段 180ms，`Curves.easeOut`），不排队。
  - **曲线**：`Motion.exit`。
  - **可中断**：不可中断（180ms）。撤销是终态操作，一次一组。
  - **触觉**：**长按到 500ms 阈值那一刻发一次 `mediumImpact`**（C 的 H-10，我同意）。
    理由：长按是**隐形手势**，成功与否必须在手上被确认，否则用户会怀疑自己按到了没有。
    ⚠️ 撤销本身**再震一次 `lightImpact`**（C 的 H-11）—— 长按那一下是"进入了编辑"，
    撤销是"真的删了"，两件事。
  - **降级**：瞬时（行直接消失）。
  - **验收判据**：① 长按 499ms 松开 → **不触发**撤销、不发触觉；
    长按 500ms → 触发（一条用 `tester.longPress` 与自定义时长的手势测试）；
    ② 撤销后大按钮上的值**不变**（`interaction-spec.md` §10 的既有行为，加动画后必须保住）。

- **D-25 做满计划组数时那个弹窗**（新增）
  - **触发**：`_maybeAskPlanDone()`（`workout_screen.dart:148-196`），
    走的是 `showAppDialog`（`core/glass_overlay.dart`）。
  - **时长**：iOS 上**玻璃弹层由 Material 的 `DialogRoute` 自己走**（系统曲线 + 系统时长）；
    ⚠️ **Dart 侧不做两件事**：不给弹层加自定义 `transitionDuration`，
    也不给遮罩加补间（`glass_overlay.dart` 已经把 `backgroundColor` 打通了，
    再叠一层 Dart 动画就会出现"玻璃在动、后面的 Flutter 内容也在动"的割裂，
    这正是 `docs/screens.md` §S0 里顶栏玻璃那次的翻车形态）。
    Android 上走 Material 默认（`fast` 语感）。
  - **曲线**：平台默认。
  - **可中断**：可中断（点遮罩关闭 = 什么都不做，已有行为）。
  - **触觉**：**一次 `selectionClick`**（弹层打开）。理由：这一刻发生的事情是
    "**你要选一条路**"，需要被确认；而且它是低频的（每个动作只弹一次，
    `_askedPlanDone` 记着），震一次不伤通道。
  - **降级**：系统处理。
  - **验收判据**：`showAppDialog` **不得**新增 `transitionDuration` 参数
    （一条 `grep` 判定）；弹层出现时背面的训练屏**不得**有任何位移或缩放。

- **D-26 热身态切换**（新增）
  - **触发**：`toggleWarmup`（`workout_controller.dart:471` → `_warmup = !_warmup`）。
  - **时长**：`set-number` 从「第 3 组」变「热身组」**100ms 交叉淡入**；
    同时 `set-number` 的文字色从 `text2` 变 `accent`（同一段 100ms）。
  - **曲线**：`Motion.enter`（淡入）/ `Curves.easeOut`（颜色）。
  - **可中断**：可中断（连点两次回到原态）。
  - **触觉**：**一次 `selectionClick`**（模式切换，与 D-13 同源的理由）。
  - **降级**：瞬时（文字与颜色直接变）。
  - **验收判据**：切换后 `pump(100ms)` 时 `set-number` 的颜色是 `accent`，
    且**大按钮的 label 全程不变**（热身不改"将要写入的值"，只改组类型）。

- **D-27 计时动作（平板支撑）的秒数**（新增）
  - **触发**：`_holdTimer` 每 1000ms（`workout_controller.dart:586`）。
  - **时长**：数字**瞬时**（同 D-18 的理由：它是"将要写入的值"）。
    唯一允许的动效是**大按钮底色从 `accent` 微微加深**（`accentPress`），
    用 1000ms 的 `Curves.linear` 跟着秒数走——**这是全 App 唯一一处"连续的、由计时驱动的颜色动画"**，
    它表达的是"正在走"，而数字表达"走到哪了"。
  - **曲线**：`Curves.linear`。
  - **可中断**：可中断（点一下记下，颜色立刻停）。
  - **触觉**：到今天的秒数时 `targetReached()`（`lightImpact` ×2，间隔 120ms）——
    **保持现状，但实现要改**：从 `Future.delayed(120ms)` 换成由**一个
    `AnimationController`（duration 120ms）**驱动第二下，见 §五 与 §八 第 3 条。
  - **降级**：去掉底色渐变（只留数字），**保留两下触觉**。
  - **验收判据**：`grep Future.delayed app/lib` 在 `haptics.dart` 里 **0 命中**。

### 3.5 完成那一刻（完成页 / 「✦ 新解锁 N 枚」/ 分享卡）

**背景事实**：`workout_summary_screen.dart` 的 `_body()` 是一个 `ListView` + 底部两颗按钮；
`_doneMark()` 是**静止**的绿圆 + 白勾（`Icon(Icons.check_rounded)`）；
`_stats(s)` 三格数字（`summary-volume` / `summary-duration` / `summary-sets`）是**直接出终值**；
`_unlockBlock()`（`summary-unlock`）是**静止**的一整块。
**这是全 App 最有分享欲的一屏，而它现在一帧都不动。**
看图（`docs/images/p01-motivation-2026-10-10/p01-01-summary-unlock.png`）：
一条橙边的"✦ 新解锁 4 枚"横条 + 两枚圆 + 名字，排在三个数字下面 ——
**它现在的位置已经对了，缺的只是"什么时候出现"。**

- **D-28 完成页编排（一条时间轴，总 1400ms）**（新增）
  - **触发**：完成页首帧（`_summary != null` 且 `_loading == false`）。
  - **时长/曲线/顺序（逐拍，起点都是首帧 = t0）**：
    1. **t0 + 0ms，勾"画出来" 420ms** —— `Motion.standard`。
       ⚠️ 不是 `Icon(Icons.check_rounded)`，是**自绘描边勾**（`PathMetric` + `Path`），
       从 0 到全长（`vi-proposal-c-brand-2026-10-10.md` 的 M-08 已经要求自绘，我同意并补时序）。
       绿底圆 **同时**从 `scale 0.92 → 1.0`（420ms，`arrival`）。
    2. **t0 + 300ms，「训练完成！」+ 一句人话 240ms** —— `Motion.enter`，
       `Offset(0, 8) → 0` + 淡入。**不延迟到勾画完**：文字与勾有 120ms 的重叠，
       这是让整段看起来"是一口气"而不是"三步走"的关键。
    3. **t0 + 420ms，三格数字计数 600ms** —— `Motion.celebrate` + `Motion.standard`。
       容量 / 时长 / 组数**同时**从 0 滚到终值（不是错峰 —— 三个数字错峰会让眼睛来回跳）。
       ⚠️ **`4 组`不要滚**：只有 1 位数的值滚起来等于没滚，还多一次重绘。
       1 位数直接出，2 位数以上才滚。
    4. **t0 + 900ms，「✦ 新解锁 N 枚」横条 320ms** —— `Motion.enter`，
       `Offset(0, 12) → 0` + 淡入；**横条里的两枚圆再错峰 80ms** 各做一次
       `scale 0.7 → 1.0`（`arrival`，每枚 260ms）。
       ⚠️ **没有新解锁时整块不存在**（`plan-ux-2026-10-10.md` §五-B 第 4 条已定），
       此时第 4 拍**不占时间**（总时长退化成 1100ms，不是留一段空白）。
    5. **t0 + 1100ms，「完成」按钮 `accent` 渐显 260ms** —— `Motion.enter`，
       只做透明度（不做位移：它是**主操作**，主操作不该"飞进来"）。
  - **可中断**：**编排本身不可中断**（一条时间轴跑完）；
    但**「完成」「分享训练卡」两个按钮从 t0 起就可点**（不许 `IgnorePointer`）。
    用户在 1400ms 里点了「完成」就直接走，不许"等动画跑完"。
  - **触觉**：
    - 勾画完那一刻（t0 + 420ms）**`heavyImpact`**（C 的 H-04，我同意）——
      **这是全 App 唯一一次"用户没有做任何操作却收到重震"**，而它是对的：
      这是整个产品的情绪顶点。
    - 新解锁横条出现那一刻（t0 + 900ms）**`lightImpact` ×2，间隔 120ms**（C 的 H-06）。
      ⚠️ 它与 H-04 相隔 480ms，不会糊成一片。
    - 破纪录（`s.hasPr`）出现那一刻 **`mediumImpact` ×2，间隔 160ms**（C 的 H-05）。
      ⚠️ **如果同时有新解锁和破纪录，只发破纪录那一组**（更重的信息吃掉轻的）——
      这一条 C 没写，我补上：**同一屏 1400ms 内最多两组触觉**。
  - **降级**：**全部瞬时**，但**保留三件东西**：
    ① 自绘勾的**终态**（画满的勾必须出现——它是信息，不是装饰）；
    ② 三格数字的**终值**；
    ③ 全部触觉（H-04 / H-05 / H-06 一次不少）。
    **减弱动态效果不等于"这次训练完成得没那么好"。**
  - **验收判据**：① 一个假时钟的 widget 测试：在 t=420 / 900 / 1100 / 1400ms 四个时刻
    分别断言（勾的画满比例 / 三格数字值 / 横条 opacity / 按钮 opacity），
    **四个时刻的值必须各不相同且单调**（证明它真的是一条时间轴，不是"一起淡入"）；
    ② 系统开启"减弱动态效果"后，t=0 那一帧就必须能看到画满的勾 + 三个终值
    （一条 `MediaQuery(data: MediaQueryData(disableAnimations: true))` 的 widget 测试）；
    ③ 1400ms 内点「完成」能立刻返回（`pump` 一次即断言路由弹出）。

- **D-29 新解锁的徽章（横条里那两枚圆）**（新增）
  - **触发**：`summary-badge-${id}` 第一次可见。
  - **时长**：每枚 **260ms**，两枚错峰 **80ms**。
  - **曲线**：`Motion.arrival`（scale 0.7 → 1.0，**允许 9.8% 过冲** —— 这是"到达"）。
  - **可中断**：可中断（用户滚走就停）。
  - **触觉**：见 D-28 第 4 拍。
  - **降级**：瞬时出现（scale 直接 1.0）。
  - **验收判据**：两枚圆的 `AnimationController` **起点相差 80ms**（一条断言
    `tester.pump(80ms)` 时第一枚已在动、第二枚还没动）。

- **D-30 分享卡预览与导出**（新增）
  - **触发**：`summary-share` → `share_card_preview_screen.dart`。
  - **时长**：预览页推入 → **不做底部推入**（它属于"查看"类，走平台默认）。
    卡面本身在进入时 **260ms 淡入 + `scale 0.96 → 1.0`**（一次，不做循环呼吸）。
  - **曲线**：`Motion.enter` + `Motion.standard`（scale 用 standard，不用 arrival——
    卡面是"被放上来"的，过冲会让它在屏幕边缘露出来）。
  - **可中断**：可中断。
  - **触觉**：无。
  - **降级**：瞬时（直接显示卡面）。
  - **验收判据**：预览页**不得**有循环动画（`grep "repeat(" app/lib` 在该文件 0 命中）——
    持续动画会让"扫码/截图"这件事变得不确定（截到哪一帧？）。

### 3.6 进步 / 数据 / 我

**背景事实**：周/月/年切换是 `ViSegmented`（`progress_screen.dart:497`）→ `setState(() => _range = ...)`
→ `volumeSeries(...)` 重算 → `ViAreaChart`（`core/vi_area_chart.dart`，一个**无状态**
`CustomPainter`）**直接画新数据**。所以今天是**硬切**：曲线在 1 帧内换了一条形状。
`ViProgressBar`（`core/vi_cards.dart:272-304`）是 `FractionallySizedBox`，**改 value 就是瞬变**。

- **D-31 周 / 月 / 年切换：曲线形变**（新增）
  - **触发**：`ViSegmented.onChanged`（含 iOS 原生 `UISegmentedControl` 回调）。
  - **时长**：**400ms**（`Motion.slow`）。
  - **曲线**：`Motion.standard`。
  - **可中断**：可中断 —— **连点三个档位时，曲线从当前形状插值到最后一个目标的形状**
    （不得先跑完中间那一段）。
  - **触觉**：**不震**（分段控件的选中由**控件自己**表达，iOS 上原生已经有它的选中动画；
    加震是重复）。
  - **降级**：瞬时换曲线（不形变）。
  - **验收判据**：① **两条序列必须先重采样到同一分辨率**（例如都重采样到 24 点）才能插值 ——
    周 7 点 / 月 30 点 / 年 12 点**长度不同**，直接逐点插值会数组越界或画错；
    一条纯函数单测：`resample(7→24)` 与 `resample(30→24)` 都返回 24 个值，且首尾保持；
    ② `pump(200ms)` 时画出来的点数与起点、终点都不同（证明在插值）；
    ③ 切档位时**轴的刻度标签**（`ends.first` / `ends.last`）**不得**与曲线同时动
    （标签跟着动会读不清）—— 标签 100ms 淡换，曲线 400ms 形变。

- **D-32 大数字要不要滚动**（**明确决定：不滚**）
  - **结论**：**「进步」页的统计带、「我」页的经验/连续天数、全部数据页的数字 —— 全部不滚。**
    只有**完成页那三个数字滚**（D-28 第 3 拍）。
  - **理由（这是本文最"不给面子"的一条决定）**：
    ① 数字滚动的价值在于"**从 0 长出来**"这个仪式感，它是**一次性事件**的语言；
    ② 「进步」页是**反复回来查看**的页面（一周看五次），每次进来都滚一遍 =
       每次都要等 600ms 才能读到自己的数据 —— 那是把装饰放在了信息前面；
    ③ 更硬的一条：滚动中的数字**与你最终要读的数字不是同一个**，
       而这个 App 的整个价值主张是"数字是真的"（`interaction-spec.md` §10 那一堆"不写假数据"）。
  - **替代**：数字**瞬时出终值**，但**整块统计带走一次 180ms 的错峰淡入**
    （每格错峰 40ms，上限 3 格）—— 有"信息到达"的节奏，而没有"等数字"的代价。
  - **验收判据**：`grep "TweenAnimationBuilder" app/lib/features/progress` **0 命中**。

- **D-33 细线带 / 卡片的入场**（新增）
  - **触发**：`ProgressScreen` / `ProfileScreen` / `AllDataScreen` 首次可见（`_loading` 结束后）。
  - **时长**：每块 **260ms**，**错峰 40ms**，**上限 4 块**（第 5 块起同时入场）。
  - **曲线**：`Motion.enter`，`Offset(0, 10) → 0` + opacity `0 → 1`。
  - **可中断**：可中断（进页立刻滚动就停）。
  - **触觉**：无。
  - **降级**：瞬时全显。
  - **验收判据**：① 用户**第二次**进入同一页时，入场**必须仍然发生**吗？——
    **不。** 只有**本次冷启动的第一次**进这一屏才播（用一个进程内标记），
    来回切 tab 不该每次都重播。判据：切到「进步」→ 切到「开练」→ 切回「进步」，
    第二次不播入场（`pump(0)` 时内容已可见）；
    ② 到底部时**不得**用入场动画加载更多（滚动到底部的加载见 D-38）。

- **D-34 成就册网格与徽章解锁动画**（新增）
  - **触发**：进入「我 → 成就」（`achievements_screen.dart`）。
  - **时长**：网格**分批入场**：每行 260ms，**行间隔 60ms**，**最多 3 批**（第 4 批起直接全显）。
    单枚徽章：**外圈环形进度 600ms 从 0 画到 `progress`**（`Motion.celebrate` + `Motion.standard`，
    C 的 M-09 已主张，我同意）。
  - **曲线**：入场 `Motion.enter`；环形进度 `Motion.standard`。
  - **可中断**：可中断（滚走就停）。
  - **触觉**：**不震**（翻看收藏册不是成就**发生**的时刻；成就在完成页那一次已经震过了）。
    ⚠️ 这一条与 C 的 H-06 不同：C 把"徽章解锁"的触觉挂在**收藏册内**（M-09 同帧）。
    **我判它应该只挂在完成页那一刻**（D-28 第 4 拍）——理由：收藏册里用户可能一次看到 12 枚
    已解锁徽章，按 C 的写法会连震 12 组（每组两下 = 24 下），那不是庆祝，那是手机在抽搐。
  - **降级**：瞬时（环直接画满、网格直接全显）。
  - **验收判据**：① 进入收藏册的**触觉调用数 = 0**（一条测试断言 `Haptics` 的所有方法未被调用）；
    ② 一次进入最多 3 批入场（`pump(600ms)` 后全部可见）。

- **D-35 滚动到底部的加载**（新增）
  - **触发**：`ListView` 滚到距底 < 200pt（下一页）。
  - **时长**：**底部一条 3pt 的细线，长度从 0 到 100% 用 400ms 循环**（`Motion.slow`，`Curves.linear`），
    或**已加载到最后一页时**：一条 180ms 淡入的「没有更多了」。
  - **曲线**：`Curves.linear`。
  - **可中断**：可中断（加载完成立刻消失，不做淡出）。
  - **触觉**：无。
  - **降级**：**改成一个静止的、不动的 3pt 半透明条**（保留"在加载"，去掉"在动"）。
  - **验收判据**：**不得**使用 `CircularProgressIndicator` 作为滚动加载指示
    （转圈会把列表底部撑高 36pt 导致"到底了又跳一下"）；细线的高度恒为 3pt，
    不参与布局（`Positioned` 或 `SizedBox(height: 3)`），列表内容高度不变。

### 3.7 微交互

- **D-36 长按（撤销 / 改重量 / 换动作）**（新增）
  - **触发**：`GestureDetector.onLongPress`（大按钮 `:658`、已完成行 `:546`、今天安排行）。
  - **时长**：**500ms 阈值**（`interaction-spec.md` §7 定的，不动）；
    阈值到达时的反馈 = 元素 **scale 0.97 并保持**（100ms `Curves.easeOut`），
    弹层出现后回到 1.0。**在阈值之前没有任何进度提示**（不做环形进度、不做震动预告）——
    理由：长按是"隐形手势"，给它做预告等于承认它隐形，而 `plan-ux-2026-10-10.md` §四 第 1 条
    已经决定用**看得见的等价入口**（「改重量」胶囊）来替代预告。
  - **曲线**：`Curves.easeOut`。
  - **可中断**：**必须可中断**：在 500ms 之前松手 → 立刻回弹（100ms）**且不触发长按**
    （这就是"长按 500ms 不误记组"那条验收清单的执行体）。
  - **触觉**：阈值到达那一刻 **`mediumImpact`**（D-24 / C 的 H-10）。
  - **降级**：**不做缩放，保留阈值与触觉**（长按的成功确认不能只靠视觉）。
  - **验收判据**：`interaction-spec.md` §12 那条「长按 500ms 不误记组」今天已有测试；
    加动画后必须仍然绿（缩放的 `Transform` 不得改变命中区域 —— 用
    `Transform.scale` 而不是改 `Container` 尺寸）。

- **D-37 下拉刷新**（**明确不做**，除一处例外）
  - **结论**：**全 App 不做下拉刷新**。`interaction-spec.md` §7 已经明写"训练中不允许下拉刷新"，
    而数据页面的刷新是**本地库**（毫秒级），给本地库做下拉刷新是假的仪式感。
  - **例外**：`cloud_backup_screen.dart`（云备份）—— 那一处是**真的网络请求**，
    给它一个 `CupertinoSliverRefreshControl` 风格的细线（iOS）/ Material 默认（Android），
    时长与曲线**交给平台**，Dart 不介入。
  - **验收判据**：`grep RefreshIndicator app/lib` 的命中数 **≤ 1**，且那 1 处在 cloud backup 相关文件里。

- **D-38 滑动切动作**（→ D-23，不重复）

- **D-39 按钮按下（全站统一）**（新增）
  - **触发**：所有 `GestureDetector`（31 处）与 `InkWell`（3 处）的按下。
  - **时长**：**100ms 下压 / 180ms 回弹**。
  - **曲线**：下压 `Curves.easeOut`；回弹 `Motion.arrival`。
  - **可中断**：可中断（`onTapCancel` 立刻回弹）。
  - **触觉**：**只有这几类震**：记一组（medium）、休息结束（heavy）、长按阈值（medium）、
    撤销（light）、模式切换（selection）、破纪录/新解锁（在完成页）。
    **其余一律不震**（导航、Tab、滚动、分段控件、开关）。
  - **降级**：不缩放，保留触觉与颜色变化。
  - **验收判据**：① 全站按下缩放的**比例只有三个值**：0.975（大按钮）、0.97（长按目标）、
    0.98（次级按钮）。`grep "scale(0\." app/lib` 去重后 ≤ 3 种；
    ② `splashFactory` 保持 `NoSplash`（这个 App 用缩放代替水波纹，
    两套反馈同时存在会让点击看起来"糊"）。

- **D-40 弹出层（底部弹层 / glass overlay）**（新增）
  - **触发**：`showAppSheet`（6 处）。
  - **时长**：`interaction-spec.md` §5 已定义 **260ms `cubic-bezier(.32,.72,0,1)`**，
    iOS 上**交给系统**（`showModalBottomSheet` 自己的曲线），
    Android 上**照规格执行**（Flutter 的 `BottomSheet` 默认时长不是 260，
    需要在 Android 分支显式设 `transitionAnimationController` 的 duration）。
  - **曲线**：Android 用 `Cubic(0.32, 0.72, 0.0, 1.0)`（规格原值，**保留不改**——
    它是"从底部快速上来 + 末端收住"，与 iOS 的 sheet 手感接近）。
  - **可中断**：可中断（下拖关闭，`enableDrag: true` 已有）。
  - **触觉**：**一次 `selectionClick`**（弹层打开）。⚠️ 与 D-25 一致；
    但**关掉不震**（关一个弹层不需要确认）。
  - **降级**：瞬时。
  - **验收判据**：Android 分支的 `transitionAnimationController?.duration == 260ms`
    （一条 widget 测试）；iOS 分支**不得**设它（`glass_overlay.dart` 里
    `isSupportedPlatform` 两条分支的参数必须逐参数一致——那条文件头自己写的纪律）。

- **D-41 Toast / 提示 / 行内提示**（新增）
  - **触发**：所有"一句话反馈"（`ScaffoldMessenger.showSnackBar` 之类）。
  - **时长**：进 **260ms**（`Motion.enter`，从屏幕底部上移 12pt + 淡入）；
    停留 **3000ms**；出 **180ms**（`Curves.easeIn`，淡出 + 再上移 6pt，**不下沉**——
    下沉会与"下一条提示"的入场方向冲突）。
  - **曲线**：见上。
  - **可中断**：可中断（新提示直接顶掉旧的，不从队尾排）。
  - **触觉**：**不震**（提示是文字信息，用震去强调一句话会让所有震都贬值）。
  - **降级**：瞬时进出，**停留时长不变**（3000ms 是"读一句话"的时间，不是动画）。
  - **验收判据**：同时发两条提示时，**屏幕上永远只有一条**，且第二条的入场起点
    是"第一条所在的位置"（不是从屏幕外重新飞进来）。

- **D-42 Tab 与列表的选中态**（新增）
  - **触发**：`ViSegmented` 选中变化 / 列表行选中 / 底栏选中（D-07 / D-08）。
  - **时长**：颜色 **100ms**（`Curves.easeOut`）；指示器位置（Flutter 那一条）**260ms**。
  - **曲线**：颜色 `Curves.easeOut`；位置 `Motion.standard`；
    ⚠️ **iOS 的原生 `UISegmentedControl` 与 `UITabBar` 的指示器由原生自己动，Dart 不介入**
    （§九 第 5 条）。
  - **可中断**：可中断。
  - **触觉**：无（D-31 同源）。
  - **降级**：颜色仍 100ms（颜色变化不属于"运动"，且它是状态信息）；
    位置瞬时。
  - **验收判据**：Flutter 那一条（Android）的指示器位置变化走同一个 `AnimationController`，
    连点三格不出现"卡在中间"。

### 3.8 空态与加载

- **D-43 骨架屏 vs spinner 的选择规则**（新增，**一条规则，不是一张清单**）
  - **规则**：**"知道内容的形状"就用骨架屏；"不知道形状"才用 spinner。**
    逐处判：
    - **骨架屏（要新建）**：`progress_screen`（统计带 4 格 + 曲线卡 + PR 墙）、
      `all_data_screen`、`achievements_screen`（网格）、`exercise_picker_screen`（列表行）、
      `notification_center_screen`（列表行）、`workout_summary_screen`（完成页）。
      理由：这些都是"有固定版式的列表/网格"，骨架能**同时表达"在加载"与"加载完长什么样"**，
      并且它消掉了"内容出现时整页跳一下"（spinner 只有 36pt，位置与最终内容完全不同）。
    - **保留 spinner**：`settings_screen` / `identity_screen` / `trash_screen` /
      `privacy_*_screen` / `cloud_backup_screen` / `body_metric_screen` 的**局部**加载。
      理由：这些是"某个按钮后面的一次请求"，没有可预测的版式，
      给它们画骨架是**编一个不存在的布局**。
  - **时长（骨架屏的"呼吸"）**：**1200ms 一周期**，透明度 `0.04 → 0.08`（底色 `line` 的 alpha 附近）
    循环，`Curves.easeInOut`。
    ⚠️ **严格禁止 shimmer 扫光**：扫光是"亮条从左到右"，在我们的暖黑底上会像一条进度，
    而它并不表示进度 —— 那是骗人。
  - **可中断**：可中断（数据到了立刻换真内容，不做淡出 —— 骨架淡出会让"内容出现"看起来更晚）。
  - **触觉**：无。
  - **降级**：骨架**保留但静止**（不呼吸）；spinner **保留**（它是系统的"忙"语汇，
    而且减弱动态效果下 iOS 的系统 spinner 本来就不转）。
  - **验收判据**：① 骨架屏的**外框尺寸与真实内容的外框尺寸误差 ≤ 2pt**
    （一条 golden 测试对每个用骨架的页面各拍两张：骨架态 / 内容态，比较首个卡片的高度）——
    做不到这一条就**不要用骨架**，用 spinner；
    ② `grep -i "shimmer\|gradient.*translate" app/lib` 在骨架实现里 0 命中。

- **D-44 spinner 的尺寸与色**（新增）
  - **时长**：系统默认（不干预）。
  - **曲线**：系统默认。
  - **可中断**：不适用。
  - **触觉**：无。
  - **降级**：系统处理。
  - **验收判据**：全站 `CircularProgressIndicator` 的 `strokeWidth` 只允许两档：
    **2（局部/行内）与默认 4（整页）**；颜色只允许 `Tokens.accent` 或默认。
    今天有 21 处，其中至少 3 处没有传色（在暖黑底上会取 Material 的默认紫/青）——
    一条 `grep` 判据把"未传色的整页 spinner"数列出来。

### 3.9 全局规则（什么时候**必须不做**动画 + 性能预算 + 平台取舍）

- **D-45 训练中 60 秒的"减量纪律"**（新增，**这是本方案最重要的一条约束**）
  - **规则**：在 `WorkoutScreen` 活着的期间，**同时运行的动画 ≤ 1 条**。
    允许的那一条是休息进度条（D-19）。
  - **禁止**：任何循环/呼吸/脉冲动画（`AnimationController.repeat()`）在训练屏出现；
    任何装饰性的入场编排；任何与"记一组"无关的转场。
  - **理由（写清楚，免得被当成教条）**：
    ① 60 秒里用户的手是汗的、注意力在器械上，**超出必要的信息就是噪音**；
    ② 更重要：`_onChange` 每秒整屏 `setState`，
    任何额外动画都在抢同一帧的预算（见 D-47 的性能预算）；
    ③ 这个产品的差异化楔子是"不做数据分析，做今天练什么"——
    **训练屏上少一个动画，就多一分"这 App 不烦"**。
  - **验收判据**：一条机械扫描：`workout_screen.dart` 与 `workout_controller.dart` 里
    `repeat(` = 0 命中、`AnimationController` 数量 ≤ 2
    （一条给休息条、一条给计时动作的底色）。
  - **同时**：D-46 列出的"**必须不做**"清单，它们没有例外。

- **D-46 什么时候必须不做动画（清单）**
  - **一、任何"将要写入的值"**（大按钮 label、重量/次数/距离/时长的数字）—— 恒瞬时。
    理由见 D-18：动画中途的点击会写下一个用户没同意过的值。
  - **二、`MediaQuery.disableAnimationsOf(context) == true` 时**，除 §四 列出的
    "降级后仍保留"的那几项以外，全部瞬时。
  - **三、App 在后台 / `AppLifecycleState.paused`**：一律不启动动画
    （回到前台时不补播，直接给终态）。理由：补播会在回前台的第一帧抢资源，
    而"回来"这一帧正是用户最急着操作的一帧（组间休息里切了微信又切回来）。
  - **四、低电量模式 / `MediaQuery.of(context).accessibleNavigation`**：
    与 reduce-motion 同一套降级（`accessibleNavigation` 是"旁白/辅助功能在跑"，
    此时任何非必要动画都在与辅助技术抢时间）。
  - **五、训练屏上任何装饰性动画**（D-45）。
  - **六、完成页的分享卡预览里的循环动画**（D-30）。
  - **七、任何"为了填满等待时间"的动画**（加载超过 400ms 时给加载点／骨架，
    但**不给**"有趣的插画动画"—— 那会让慢变成一种表演）。
  - **验收判据**：§四 的降级矩阵表 + 一条守卫测试：扫 `app/lib` 里所有
    `duration:` 字面量，必须来自 `Motion.*`（与 `tool/check-user-text.mjs` 同一思路，
    C 的 M-18 已提出，我同意并给出"豁免名单"：`haptics.dart` 的间隔、
    `domain/models.dart` / `analytics/flusher.dart` 的时长计算）。

- **D-47 性能预算（platform view + PageView 并存）**
  - **预算（写死，可测量）**：
    - iOS：**训练屏 120Hz 设备上不掉帧**（iPhone 17 Pro 是 ProMotion）；
      外壳（含 `UITabBar` 平台视图 + `PageView`）**≥ 100fps**；
      完成页编排期间 **≥ 100fps**（它是唯一允许同时跑 4 条补间的时刻）。
    - Android：**中端机 60fps**，掉帧率 < 1%（`flutter run --profile` +
      DevTools 的 Frame chart）。
  - **风险清单（按严重度）**：
    1. **`UiKitView`（`UITabBar`）活着期间，Flutter 的栅格化不再与 Dart 并行**
       （`glass_surface.dart` 文件头自己写着这一条："整屏代价"）。
       而 iOS 上 `PageView` 与它**同屏**。**这是本 App 最大的性能风险，
       且它今天没有被测过**（`docs/screens.md:88` 与
       `docs/feature-backlog.md` §〇「⑦」都记着"真机 release 帧率还没测"）。
       **D-47 的第一件事就是把这个测量补上**，见"怎么测量"。
    2. **`_onChange` 每秒整屏 `setState`**（D-19/D-21 相关）：
       60 秒 × 60 帧 = 3600 次 build 里，有 60 次是整屏重建。
       在 `UITabBar` 平台视图存在于同一棵树上时，整屏重建会让平台视图的
       overlay surface 反复重排。**修法：把休息条抽成独立的 `AnimatedBuilder`**
       （`ListenableBuilder(listenable: c)`），让每秒的 `notifyListeners()`
       只重建那条 ~26pt 的带子，而不是整屏。
       ⚠️ 这一条**是纯性能改动、零视觉变化**，所以它应该排在落地顺序的第一批（§七）。
    3. **`GlassSurface` 在弹层里**（`glass_overlay.dart`）：弹层已经是第二个平台视图，
       而弹层出现时背后还有 `UITabBar` —— 两个平台视图同屏 + 一次转场。
       **规矩：弹层打开期间不许有其它的位移/缩放动画**（D-25 已经写了）。
    4. **`CustomPainter` 的无动画重绘**（`ViAreaChart`）：切档位时每秒重绘 24 点是小事，
       但**如果按 D-31 做形变，就必须保证 `shouldRepaint` 正确**——
       今天 `ViAreaChartPainter` 是每次 build 新建的 painter，
       `shouldRepaint` 的实现要看（若不比较 `points` 就会漏绘，若比较引用就会白绘）。
  - **怎么测量（具体命令与判据）**：
    1. `flutter run --profile` + `flutter drive --profile` 跑
       `integration_test`（已有 `app/integration_test/`），跑三段：
       **冷启动到首页**、**连点三个 tab 十次**、**记 10 组（含休息）**。
    2. iOS 用 `Instruments` 的 **Core Animation**（勾 Color Offscreen-Rendered Yellow /
       Color Blended Layers）+ **Time Profiler**；Android 用
       `flutter run --profile --trace-skia` 或 DevTools Performance。
    3. **判据**：三段里 "Build" 与 "Raster" 的 p95 都 ≤ 8ms（120Hz）/
       ≤ 16ms（60Hz），**且 Raster 没有一帧 > 33ms**。
    4. ⚠️ **平台视图不进 Flutter 的截图**（`docs/screenshots.md` 写过），
       所以**帧率也必须用设备级手段量**，不能只看 `flutter run` 的 console。
  - **与 iOS 系统弹簧共存时的取舍**（§九 第 5 条详述）。

---

## 四、触觉清单

> **口径**：全部走 Flutter 自带的 `HapticFeedback`（**不引入第三方包**，与现状一致）。
> 四档强度：`selectionClick`（最轻）/ `lightImpact` / `mediumImpact` / `heavyImpact`。
> **一条纪律**：**每条触觉必须与一个视觉状态变更在同一个同步块里发起**（`unawaited` 之后立刻 `setState`），
> **不许 `await` 之后再震、不许 `Future.delayed` 串**。
> 全仓今天唯一的 `Future.delayed`（`haptics.dart:64`）就是这条纪律的反例。
>
> **命名建议**：现在 `Haptics` 只有三个方法（`setLogged` / `restFinished` / `targetReached`），
> 而下面这张清单要 8 个。**不要新增 8 个方法** —— 改成
> `Haptics.play(HapticCue cue)`，`HapticCue` 是一个枚举
> （`setLogged` / `restFinished` / `targetReached` / `longPressArmed` / `undone` /
> `modeSwitch` / `recordBroken` / `badgeUnlocked`）。
> 理由：接口按"语义"命名、实现按"档位"映射，改档位时只改一处；
> 而 8 个方法会让每个调用点都能"顺手加一个"。

- **H-01 记一组** —— `mediumImpact`（**不是规格 §8 写的 `light`**，C 的第 1 条冲突我同意）。
  触发时机：**写库成功后**（`workout_controller.dart:743` 已在做，位置对）。
  与视觉的同步：与 D-16 的**松手回弹**（`arrival` 起点）和 D-17 的**新行入场**（`enter` 起点）**同帧**。
  理由：手机在器械上、环境有震动，`light` 会被吃掉；而这是"不用看屏幕的确认"的唯一承载。
- **H-02 休息结束** —— `heavyImpact`。触发时机：`left <= 0` 那一跳（今天已做）。
  与视觉的同步：与 D-20 的**颜色变化第一帧**同帧。这是全 App 最重的一次。
- **H-03 长按进入编辑（阈值到达）** —— `mediumImpact`，**一次**。
  与视觉的同步：与 D-36 的**按下并保持的 scale 0.97** 同帧。
  理由：长按是隐形手势，成功必须在手上被确认。
- **H-04 撤销一组** —— `lightImpact`，**一次**。
  与视觉的同步：与 D-24 的**行开始淡出**同帧。比 H-03 轻一档（H-03 是"我按到了"，H-04 是"删了"）。
- **H-05 模式切换**（底部弹层打开 / 热身态切换 / 「选择」类页面推入 / ±步进） —— `selectionClick`。
  **高频**类（±步进）每次一次；**低频**类（弹层、热身、选择页）每次一次。
  理由：它是"经过了一格"的语汇，最轻，不伤通道。
- **H-06 训练完成** —— `heavyImpact`，**一次**。与 D-28 第 1 拍（勾画完）同帧。
  ⚠️ 这是全 App 唯一一次"用户没操作却收到重震"，而它是对的（情绪顶点）。
- **H-07 破纪录** —— `mediumImpact` **两次，间隔 160ms**。
  实现纪律：第二下由**一个 `AnimationController(duration: 160ms)` 的 `completed`** 驱动，
  **不用 `Future.delayed`**（掉帧时会漂）。
  ⚠️ 与 H-06 的 420ms 相隔，不糊。
- **H-08 新解锁徽章（完成页那一次）** —— `lightImpact` **两次，间隔 120ms**（同 H-07 的实现纪律）。
  ⚠️ **只在完成页发**，收藏册里翻看不发（见 D-34）。
- **H-09 计时动作到达目标** —— `lightImpact` **两次，间隔 120ms**（`targetReached`，保持现状语义，
  只把实现从 `Future.delayed` 换到控制器时间点）。
- **H-10 休息最后 3 秒预告** —— **见下，本节的核心结论。**
- **H-11 Tab 切换** —— **无触觉**（有意，C 的 H-12 我同意）。
- **H-12 下拉刷新 / 滚动 / 分段控件选中 / Toast** —— **无触觉**。

### 「休息还剩 3 秒要不要触觉提示」—— 我的结论：**要，但不是"提示"，是"预告"**

`docs/plan-ux-2026-10-10.md` §四 第 2 条把它标成"待定"（"休息结束那一下已经有震动，
再多一次可能是噪音，需要在真机上试"）。**我不认为这件事需要真机才能判 —— 它有三个能当场算清的维度。**

- **结论**：**做。具体形态是：还剩 3 秒时 `selectionClick` 一次（最轻档），
  同时倒计时数字变 `accent` 色（180ms 淡变）、进度条末端做一次 220ms 的 `arrival` 脉冲（scale 1.0 → 1.06 → 1.0）。
  只此一次，不做 3-2-1 三下连震。**
- **理由（四条，按硬度排序）**：
  1. **它是"预告"，不是"提示"。** 组间休息的真实行为是"我还差一点就想开始下一组了"——
     用户需要知道的是"**还有一点点**"，好在最后一组动作里收尾。
     3 秒正好是"放下手机、走到器械前、抓杠"的时间。**这不是提醒，这是发令枪的前半声。**
  2. **`heavyImpact`（H-02）单独出现有一个真问题：它是"已经到点了"，不是"快到了"。**
     而"到点了"这一下在**用户已经开始下一组**时会显得像误报 ——
     他可能已经在做动作了，手机却在包里震了一下。**提前 3 秒的那一下把"到点"从
     "通知"变成"确认"**：用户提前知道了，到点那一下就成了"对，我猜到了"。
  3. **通道不冲突（这是它唯一的反对理由，可以当场算清）。**
     60 秒里触觉的完整时间线是：
     `t=0` 记一组（medium）→ `t=57s` 预告（selection，最轻）→ `t=60s` 结束（heavy）。
     三个点**强度递增**（中 → 最轻 → 重），**间隔分别是 57 秒与 3 秒**。
     "更多一次会变噪音"这个担心的成立条件是"两次触觉太近、强度相近"——
     这里强度差两档、语义完全不同。**算得清，不必真机也能判。**
  4. **不做 3-2-1 连震**：那才是真的噪音（三下轻震在 3 秒内 = 手机在抖）。
     **一次最轻的 `selectionClick` 是"预告"的物理上限。**
- **代价（写清楚）**：如果用户把休息调到 15 秒或更短，`t=12s` 的预告会与 `t=0` 的记组
  （medium）相隔 12 秒 —— 仍然够远。但如果用户按了 `+15`（D-21），**预告时刻必须跟着重算**
  （`restEndsAtMs` 是唯一真源，预告也读它），否则会出现"预告响了但还剩 18 秒"。
  **这一条是它的实现难点，也是判据。**
- **判据**：① 一条假时钟测试：`restTotalSec = 60` 时，`selectionClick` 恰好在
  `restRemainingSec` 从 4 变 3 那一帧被调用**一次**（不是两次、不是每秒一次）；
  ② 在还剩 10 秒时按 `+15`，**不得**已经发过预告（预告时刻随后移到还剩 3 秒）；
  ③ `restTotalSec <= 5` 时**不发预告**（那是"按下就结束"，预告没有意义）。
- **降级**：**保留那一次触觉**，去掉数字变色与进度条脉冲的**动画**（颜色直接切）。
  理由：对"看不见屏幕"的用户，这一次触觉是**信息**，减弱动态效果不该拿走它。

---

## 五、reduced-motion 方案

**开关的唯一读取点**：`reduced_motion.dart`（**待新建**，放 `app/lib/core/`）。
**唯一实现**：`MediaQuery.disableAnimationsOf(context)`。

⚠️ 两条纪律：

1. **必须用 `MediaQuery.disableAnimationsOf(context)`，不要用 `MediaQuery.of(context).disableAnimations`** ——
   前者是 Flutter 3.10+ 提供的正确 API（含默认值处理），后者在测试里造数据时容易被写成"忘了给"。
2. **一处读取、传到底**：`reducedMotion(context)` 返回 `bool`，
   所有 `Motion.*` 的 duration 经过它短路。**不许任何页面自己写 `if (disableAnimations)`** ——
   那一定会漏掉某几处（今天全仓 0 处，所以从 0 建规矩比从 137 处收口便宜得多）。

### 「不是全部关掉」：降级后每一段保留什么

**原则：降级拿走的是"运动"，不是"信息"。**
一条判据可以判所有条目：**关掉动画之后，用户是否还能知道"发生了什么"？**
如果答案是"不知道"，那这一条就不能全关。

- **3.1 冷启动 → 首页**：
  - **去掉**：D-04 淡出里的那 1.5% 缩放。
  - **保留**：D-04 的**淡出本身**（硬切会在同一次冷启动里闪两屏）；
    D-03 加载点（**但改成静止的单点**，见 D-03 的降级）。
  - **不变**：D-01（本来就 0ms）、D-06（老用户直接落首页）。
- **3.2 外壳**：
  - **去掉**：D-08/D-07 的页面位移（`jumpToPage`）、D-09 的标题交叉淡入、D-11 的齿轮展开。
  - **保留**：**选中态的落位**（iOS 原生那条由原生管；
    Android 的**指示器直接出现在新位置** —— 它必须在，因为它是状态）。
  - **不变**：D-10（未读点）→ 瞬时出现（不留 scale）。
- **3.3 二级页转场**：
  - **交给系统**：iOS 在减弱动态效果下会给**交叉溶解**而不是推入（这是系统行为，
    我们不干预也不覆盖）。
    ⚠️ 这一条很重要：**如果我们自己实现了 `pageTransitionsTheme`（C 的 M-12），
    系统那条降级就失效了** —— 这是反对 M-12 的第四个理由（见 §八 第 2 条）。
  - **保留**：边缘返回手势（它是导航，不是动画）。
- **3.4 训练主屏（最重要的一段）**：
  - **去掉**：D-15 的按钮缩放入场、D-16 的按下缩放与松手回弹、
    D-17 的新行位移（**保留瞬时出现**）、D-22 的收起位移、D-23 的换动作转场（**瞬时切**）、
    D-24 的行淡出与收起（**瞬时消失**）、D-27 的计时底色渐变。
  - **保留（三件，一件都不能少）**：
    ① **休息进度条的宽度变化**（改成"每秒一格直接跳" —— 它必须能看出"还剩多少"）；
    ② **D-20 的颜色切换**（`accent → success`，**瞬时完成**，不做弹一下）；
    ③ **D-19 / D-20 / D-21 的全部触觉**，以及 **H-10 的 3 秒预告**。
  - **理由**：训练屏是整个产品唯一"用户不看屏幕"的场景。
    **在减弱动态效果下把触觉也降掉，等于把这个产品对这类用户关掉。**
- **3.5 完成那一刻**：
  - **去掉**：全部编排（勾的"画出"、标题上浮、数字滚动、横条推入、按钮渐显）。
  - **保留（这是最不能全关的一屏）**：
    ① **画满的勾的终态**（必须出现）；
    ② **三个数字的终值**（必须出现）；
    ③ **「✦ 新解锁 N 枚」整块**（必须出现，只是不再推入）；
    ④ **全部触觉**（H-06 / H-07 / H-08 一次不少）。
  - **理由**：减弱动态效果 ≠ 这次训练完成得没那么好。
- **3.6 进步 / 数据 / 我**：
  - **去掉**：D-31 的曲线形变（**瞬时换曲线**）、D-33 的错峰入场、D-34 的网格入场与环形进度。
  - **保留**：环形进度的**终态**（弧长 = 真实 progress，它是数据）、
    分段控件的选中态、D-32 的数字（本来就不滚）。
- **3.7 微交互**：
  - **去掉**：全部缩放（按下无反馈）、Toast 的位移、骨架屏的呼吸。
  - **保留**：长按阈值与 H-03 触觉（**阈值本身不是动画**）、
    D-41 的停留时长（3000ms）、D-40 的颜色变化、骨架屏（**静止版**）。
- **3.8 空态与加载**：
  - **保留**：骨架屏本身（改成静止）与 spinner。
    理由：它们表达"在加载"，这是信息。
- **3.9 全局**：见 D-46 第三条（后台不启动动画）与第四条（`accessibleNavigation` 同一套降级）。

### 执行与守卫

- **守卫测试（一条）**：扫 `app/lib` 里所有 `duration:` / `Duration(` 字面量与
  `Curves.` 字面量，**必须来自 `Motion.*`**，豁免名单写在测试里
  （`haptics.dart` 的触觉间隔、`domain/models.dart` 与时长的算术、`analytics/flusher.dart` 的退避）。
  与 `tool/check-user-text.mjs` 同一思路（机械扫描 + 白名单 + 反向验过）。
- **归 C 的 M-18**：C 已经提出这条守卫；我同意，并**补上豁免名单**（C 没写，
  没有豁免名单这条守卫第一天就会红）。
- **修正 `interaction-spec.md` §12 的那条判据**：「`prefers-reduced-motion` 下无动效残留」
  → 改成两条可执行判据（C 的第 5 条冲突我完全同意）：
  ① 全仓 `duration:` 与 `Curves.` 都来自 `Motion.*`（一条守卫测试）；
  ② 系统开启后，**D-17 / D-22 / D-23 / D-24 / D-28 / D-31 / D-33 / D-34 / D-39 全部瞬时**，
  而 **D-19 的进度条宽度、D-20 的颜色、D-28 的勾与三个终值、以及全部触觉仍然发生**。

---

## 六、性能与平台风险

> D-47 已经把预算与风险列了。这一节写**具体怎么查、按什么顺序修、以及为什么 iOS 上有一段
> 本质上无法做到"和原生一样"**。

### 6.1 iOS platform view + PageView 的协同（最危险的一段）

- **事实**：iOS 上同屏最多会有 **3 个平台视图**：`UITabBar`（底栏，常在）、
  `UISegmentedControl`（「进步」页那个周/月/年）、以及弹层里的 `GlassSurface`。
  而 `PageView` 让底栏与内容**一起动**。
- **根因（写下来，因为它决定了修法）**：`glass_surface.dart` 的文件头自己写着 ——
  "它是一个平台视图：活着的期间 Flutter 的栅格化不再与 Dart 并行（**整屏代价**）"。
  所以 **`UITabBar` 存在 = 整个外壳放弃了 iOS 的并行栅格化**。
  这不是"某个动画慢"，这是"整个 App 在这个平台上的渲染模型变了"。
- **修法（按优先级，全部是"减少同屏平台视图数 / 减少整屏重建"）**：
  1. **休息条抽成独立 `ListenableBuilder`**（D-47 第 2 条）。**零视觉变化、收益最大**，
     所以它排在落地顺序第一批。
  2. **弹层打开期间禁止任何位移/缩放动画**（D-25）。弹层是第 3 个平台视图。
  3. **`ViSegmented` 的原生分支：切档位时不要让整页 build**（D-31 的形变只在曲线那一块内部做）。
  4. **不要为了"丝滑"给平台视图加遮罩动画**（`Opacity` / `ClipRect` 包在 `UiKitView` 外
     会强制 offscreen render，代价比不加高一倍以上）。
  5. **`RepaintBoundary` 的取舍**：给 `ViAreaChart` 与 `done-list` 加 `RepaintBoundary`
     是有效的（它们每秒在同一个位置重绘）；**但给平台视图外面加 `RepaintBoundary` 无效**
     （平台视图本来就在自己的 layer 上）。
- **一段"本质上做不到"的地方（如实写）**：
  iOS 26 的 `UITabBar` 在滚动时的**自动收起**（scroll-to-hide）与"浮动胶囊"长在
  `UITabBarController` 身上，本工程只有一个 `UITabBar`（`native_tab_bar.dart` §1 已写）。
  所以**我们永远拿不到那段系统的滚动联动动效**。
  这一条不是性能问题，是**动效无法复刻**的问题 —— 写在这里，免得有人以为是没做。

### 6.2 与 iOS 系统弹簧共存时的取舍（**这是本文最技术的一条**）

**四个"不做"，每一条都有理由**：

1. **Dart 不许"追" UIKit 的弹簧。** 用户点 iOS 底栏那一格时，
   `UITabBar` 自己会用系统弹簧把选中态滑过去，而 Dart 同时收到 `onTabSelected` →
   `_selectTab` → `PageView.animateToPage(260+90×距离, Motion.standard)`。
   **两条曲线是独立的、参数不同的**。今天它们"看起来还行"是巧合（260ms 与 0.5s 的视觉长度接近）。
   **正确的取舍**：**PageView 的位移以"内容"为准（Dart 控制），底栏的选中以"控件"为准（原生控制），
   两者各自跑完，不互相等、不互相测。**
   代价：极端情况下（连点两格、或系统 Reduce Motion 开着导致原生瞬切而 Dart 还在滑）
   会有一瞬间"底栏已经选好了、页面还在路上"。
   **这是可以接受的** —— 反过来（Dart 等原生 / 原生等 Dart）会让底栏变得迟钝，
   而底栏是最高频动作。
2. **不给原生控件包 Dart 动画。** 不要给 `NativeTabBar` / `NativeSegmented` 外面套
   `AnimatedOpacity` / `AnimatedScale` / `SlideTransition`。
   理由：① 会让平台视图在动画期间被合成到 offscreen（见 6.1 第 4 条）；
   ② 系统的弹簧已经在做形变了，再叠一层就是两个运动叠加（`glass_surface.dart` 的
   `interactive: true` 那条注释讲的正是系统自己会做形变）。
3. **不在 iOS 上给"选中态"补 Dart 的过渡。** `NativeTabBar.didUpdateWidget` 里那句
   `invokeMethod('setSelected')` 只**发命令**，不允许在 Dart 侧同时改一个副本的颜色再淡入 ——
   那会与原生自己的选中动画打架，得到"两段式变色"。
4. **Android 必须向 iOS 的实测参数对齐，而不是向"苹果的感觉"对齐。**
   这是可执行的：`GlassBridge.swift` 量出来的是 ζ = 0.72（过冲 3.8%）与 ζ = 0.32（过冲 34.6%）。
   Android 侧的指示器落位用 `Motion.arrival`（过冲 9.8%）+ 260ms，
   而**不是**随手写一个 `Curves.easeOutBack` + 300ms（那会冲过头、又慢半拍）。
   **残留的端间差异 ≈ 6 个百分点的过冲**，我承认它存在，并认为这是"两套系统控件"这个
   架构决定必须付的代价（用户 10-09 拍板要真 `UITabBar` 的时候就该知道这一条）。
5. **Dart 侧不主动给平台视图发"开始/结束"动画通知。** 没有这样的 API，
   也不需要 —— 一旦需要，说明我们在做"混合动画"，那正是 `docs/screens.md` §S0 里
   顶栏玻璃那次翻车（"平台视图与 Flutter 内容的层叠关系在真机上坏了"）的形态。
   **规矩：平台视图要么完全由原生管，要么完全由 Dart 管，不许分工。**

### 6.3 哪些动画会掉帧（按风险排序）

1. **`PageView` 拖动 + `UITabBar` 同屏**（iOS）—— 每次拖动都在重排平台视图的 overlay surface。
   风险最高，且**没有 Dart 侧的修复手段**（只能靠减少同屏平台视图数）。
2. **休息条每秒整屏 `setState`** —— 60 次整屏重建落在 60 秒里，
   与"记一组的入场动画"抢同一帧的概率不低（用户往往在休息结束的同一秒点下一组）。
   修法：D-47 第 2 条。
3. **`CustomPainter` 的曲线形变（D-31）** —— 400ms 内每帧重算 24 个点的路径 +
   渐变填充。风险中等（画的东西少），但**`shouldRepaint` 写错会变成"每帧都重绘"或"不重绘"**，
   两个方向都坏。修法：painter 的 `shouldRepaint` 比较**重采样之后的 points 列表**
   （`listEquals`），并且把 `RepaintBoundary` 加在 `ViAreaChart` 外面。
4. **完成页编排（D-28）** —— 唯一允许同时跑 4 条补间的时刻。
   风险点在**数字计数**：`TweenAnimationBuilder<int>` 每帧触发一次 `Text` 重建，
   三格 = 每帧 3 次。可接受（600ms × 60 = 36 帧 × 3），但
   **必须给三格数字加 `RepaintBoundary`**，否则会带着整个 `ListView` 重绘。
5. **骨架屏的呼吸（D-43）** —— 1200ms 循环、alpha 变化。
   ⚠️ **alpha 动画会强制 offscreen render**（与 6.1 第 4 条同一个坑）。
   修法：**不要动画 `Opacity`**，直接动画一个 `Color` 的 alpha
   （`Container(color: ...)` 的 `Color.withValues(alpha:)`）—— 那是 paint 属性，不是 layer 属性。
6. **`AnimatedSwitcher` 包 `ListView`（D-33）** —— 错峰入场时每个子元素各自一条补间，
   4 块 = 4 条。可接受，但**不要**在 `ListView.builder` 的 `itemBuilder` 里建控制器
   （滚动回收会泄漏）；用 `TweenAnimationBuilder`（无状态、随 widget 生死）。

### 6.4 怎么测量（可执行）

- **工具链（不能用 `flutter` 命令的场合怎么读代码）**：本机当前 `PATH` 里没有 `dart` / `flutter` /
  `node`（`which` 全空），所以**本文的所有静态统计都是 `grep` 出来的**，没有跑过分析器。
  §七 的落地顺序里每一步都写明了"要跑什么命令验证"，**在能跑构建的环境里执行**。
- **三段基准（每段都要量）**：
  1. **冷启动**：`xcrun simctl` / 真机录屏 240fps，量"启动图消失 → 首页大按钮可点"的帧数；
     判据：**没有任何一帧是纯色空屏**（D-01/D-02 的验收）。
  2. **外壳**：连点三个 tab 各 10 次（`debugSwitchTab` 是现成的入口，
     见 `main.dart:176` 的 `debugSwitchTab`）；判据：p95 build ≤ 8ms、raster ≤ 8ms。
  3. **训练**：记 10 组（含 60 秒休息 ×2）；判据：**休息期间 raster 没有一帧 > 16ms**
     （60Hz）/ > 8ms（120Hz）。
- **一张必须出的证据图**：`docs/images/` 下加一张
  `motion-probe-2026-10-10.png` —— 把上面三段的时间线画在一张图上（横轴 ms、纵轴帧时长），
  并在图上标出"平台视图活着"的区间。**没有这张图，§六 的所有结论都只是推理。**

---

## 七、落地顺序

**排序判据**：**"用户能感知到" × "成本低"**。
第一梯队必须是"一天内做完、当天就能在真机上看到差别"的三件。

### 第一批（感知最大 × 成本最低，建议同一个 PR）

- **① 令牌 + 降级开关（地基，零视觉变化但解锁一切）**
  - 新建：`motion.dart`（待新建，放 `app/lib/core/`）、`reduced_motion.dart`（待新建，放 `app/lib/core/`）。
  - 改动：`app/lib/core/theme.dart`（只加 import 与两个常量，不动任何现有令牌）。
  - 为什么排第一：它是后面每一条的前置；而且**它本身可以立刻验收**
    （守卫测试能跑、`reducedMotion(context)` 有单测）。
  - 验证：守卫测试（扫 `duration:` / `Curves.`）+ 一条 `reduced_motion_test.dart`。
- **② 训练屏：休息条的"整屏重建 → 局部重建" + 进度条方向修正 + 1000ms 线性补间**
  - 改动：`app/lib/features/workout/workout_screen.dart`（`_restStrip` 抽成独立
    `ListenableBuilder` + 进度条用 `TweenAnimationBuilder` + **修正 `value` 方向**）。
  - 为什么排第二：**它是唯一一条"零装饰、纯正确性 + 纯性能"的改动**，
    而且修的是一个今天就是错的视觉信号（数字在减、条在长）。
    核心场景（组间 60 秒）里，这一条用户当天就能看出来。
  - 验证：① 判据 D-19（方向 + 每次前进量 ≤ 一格）；
    ② 真机 `--profile` 量"休息期间 raster 无 > 16ms 帧"。
- **③ 记一组的完整确认链（按下 → 松手 → 触觉 → 新行长出来）**
  - 改动：`app/lib/features/workout/workout_screen.dart`（`onTapDown`/`onTapUp`/`onTapCancel`
    + 新行入场）与 `app/lib/features/workout/haptics.dart`（接口改成 `play(cue)`）。
  - 为什么排第三：**这是全 App 最高频的一次交互**（一次训练 12–25 组），
    而它今天是"一行字瞬间出现 + 震一下"。做完这一条，用户第一次会觉得"这 App 有手感"。
  - 验证：D-16 / D-17 / D-39 的判据 + `interaction-spec.md` §12 那条"长按 500ms 不误记组"仍绿。

### 第二批（用户能感知，成本中等）

- **④ 完成页编排（D-28 + D-29 + H-06/H-07/H-08）** —— 感知极强、只动一个文件
  （`workout_summary_screen.dart` + 一个自绘勾的 widget）。
- **⑤ 外壳：Android 的 Tab 过渡 + 撤销掉 `_selectTab` 的平台早返回（D-08）**
  —— 两端一致，成本一个函数。
- **⑥ 冷启动接力（D-01～D-04）** —— 需要改 iOS 的 `LaunchImage` 资源（**环心透明**）
  与 `main.dart` 的加载态；感知极强（每次冷启动都看），但涉及资源重新导出，成本中。

### 第三批（结构性，单独评估）

- **⑦ 「选择」类转场（D-13）** —— 要逐处改 38 处 push 里的约 16 处，且要新增 `app_route.dart`
  （待新建，放 `app/lib/core/`）。**建议先只改动作选择器一处**，真机上用一周再铺开。
- **⑧ 骨架屏（D-43）** —— 逐页做 golden 对位，成本高（6 个页面 × 2 张图）。
- **⑨ 曲线形变（D-31）** —— 需要重采样纯函数 + painter 的 `shouldRepaint` 重构。

### 明确"不排期"的

- **C 的 M-12（统一 `pageTransitionsTheme`）** —— 我反对，见 §八 第 2 条。
- **任何 `Hero`** —— D-14。
- **任何 shimmer 扫光** —— D-43。
- **「进步 / 我」页的大数字滚动** —— D-32。

---

## 八、与现有规范的冲突

> 格式：**推翻哪一条 / 为什么 / 代价是什么**。
> C 方案里已经推翻过的（§8「记录一组 → light」、§6「rest_done 不震动」、
> `screens.md` S16 的"还差 N"、§12 的 reduced-motion 判据）我**同意，不重复**。

1. **修正 `docs/plan-ux-2026-10-10.md` §四 第 2 条的"待定"结论。**
   原文：*"「还剩 3 秒」要不要触觉提示 —— **待定**（休息结束那一下已经有震动，
   再多一次可能是噪音，需要在真机上试）"*。
   **我判：不用真机，直接定"做"**（形态见 §四 的 H-10：`selectionClick` 一次 + 数字变色，
   **不做 3-2-1 连震**）。
   理由：这是能算清的三个维度（语义是"预告"不是"提示"；强度差两档、间隔 57 秒/3 秒，
   不构成噪音；一次最轻震是预告的物理上限），不是"需要手感的偏好"。
   **代价**：60 秒里从 2 次触觉变成 3 次；如果真机反馈说吵，**要撤的是"3 秒预告"，
   不是"休息结束那一下"**（后者是这一类用户唯一的时间线索）。

2. **推翻 `docs/vi-proposal-c-brand-2026-10-10.md` 的 M-12「统一页面推入转场」。**
   原文（§3.3）：*"**M-12 页面推入** — 触发：`Navigator.push`（38 处）| 300ms `easeOutCubic`
   位移 + 淡入（`SlideTransition` 从 `Offset(0, 0.04)`）| 落地方式：在 `buildAppTheme()` 里设
   `pageTransitionsTheme`，给两端各指定一个 `PageTransitionsBuilder`（**一处改，38 处受益**）"*。
   **我判它错，四个理由**：
   ① **它会吃掉 iOS 的边缘返回手势**。`CupertinoPageTransitionsBuilder` 与
      `CupertinoPageRoute` 的**交互式返回**是耦合的；换成一个自绘的
      `SlideTransition` builder 之后，用户不能再从屏幕左边缘拖回去 ——
      对一个健身房单手、屏幕有汗的 App，这是硬伤。
   ② **它会吃掉系统在"减弱动态效果"下的那套降级**（iOS 会给交叉溶解）。
      自己实现转场 = 自己承担无障碍，而 C 自己在 M-18 里也只列了三条例外。
   ③ **它把"选择"类与"查看"类做成一样**。而这两类的心智不同（见 D-12/D-13）：
      前者是"进来挑一个再出去"，后者是"看一屏内容"。都给右滑推入，用户分不出自己进了哪种。
   ④ **`Offset(0, 0.04)` 那个 4% 的下滑入场在 iOS 上是错的手势语汇** ——
      iOS 的 push 是**水平**的，垂直微移是 Android 的旧 Material 形态；
      在 iOS 上垂直微移会被读成"这是一个弹层"，而随后它又占据了整个导航栈。
   **代价（如实写）**：不统一转场 = 两端的二级页转场**继续不一样**（iOS 视差推入、
   Android Material zoom）。**我接受这个代价**，因为"两端各自像自己的系统"比
   "两端一样但都不像系统"好；而这一点与用户 10-09 拍板要真 `UITabBar` 的取向是一致的。
   **替代方案**：D-13 的"选择类走底部推入 + 验收判据"。

3. **推翻 `docs/interaction-spec.md` §8 第 1 条的一处措辞（不是推翻它的行为）**：
   原文：*"记录一组 | 新行 `pop` 入场 280ms（透明度 + 上移 6pt）"*。
   **"`pop`"这个词要删掉**。理由：`pop` 在动效语境里指"带回弹的弹出"，
   而这一条的曲线写的是 `easeOutCubic`（`vi-proposal-c-brand-2026-10-10.md` M-01 的 `standard`），
   **两者矛盾**：280ms 的 `pop` 会过冲，而它同时又写"上移 6pt"（一个很小的位移，
   过冲会在 6pt 上留下 0.6pt 的越界，看不见但会让文字边缘抖一下）。
   改成：*"新行入场 280ms（透明度 + 上移 6pt，`Motion.enter`，**无过冲**）"*。
   **代价**：无（行为不变，只是把一句自相矛盾的话说清楚）。
   ⚠️ 顺带：这一条是 `interaction-spec.md` §8 里**唯一一条曲线没写、时长写了**的，
   而 §8 另外四条里"步进调整：无动效"与我的 D-21 一致（保留），
   "弹层 260ms 弹簧曲线"里的"弹簧"同样是个模糊词 —— 按 D-40，
   iOS 交给系统、Android 用 `Cubic(0.32, 0.72, 0, 1)`（**它不是弹簧，它没有过冲**，
   规格里的"弹簧曲线"是误称，也要改）。

4. **补一条 `docs/interaction-spec.md` §8 完全缺失的内容：二级页转场。**
   全文 222 行里**没有一处定义二级页转场**（§5 只管底部弹层，§6 只管训练屏状态机）。
   而 38 处 `Navigator.push` 全在跑平台默认。按 D-12/D-13 补：
   *"查看类转场 = 平台默认（iOS 视差推入 + 边缘返回手势必须可用）；
   选择类转场 = 底部推入 260ms `Motion.enter`，出场 180ms。两类都不许在
   `ThemeData` 里统一覆盖 `pageTransitionsTheme`。"*

5. **补一条 `interaction-spec.md` §8 的元规则（这是本文最想留下的一句）。**
   §8 现在是一张"场景 → 动效 → 触觉"的表，**没有元规则**，所以它必然会漂
   （已经漂了：全仓 0 个动画控制器）。补上：
   *"一、任何'将要写入的值'（大按钮 label、重量/次数/距离/时长数字）**不许有动画**，
   恒瞬时；二、训练屏活着期间**同时运行的动画 ≤ 1 条**，禁止循环动画；
   三、所有时长与曲线只许来自 `motion.dart`，且必须经过 `reduced_motion.dart` 短路；
   四、每条触觉必须与一个视觉状态变更同帧发起，不许 `Future.delayed`。"*
   **这四条是判据，不是建议**（每条都能写成一条机械扫描）。

---

## 九、一句话收尾

**这个 App 现在的问题不是"动效不够好看"，是"它还没有决定要不要有动效"。**
规格书上写着 5 条动效、验收清单写着 1 条降级判据，代码里 0 个控制器——
**而用户每天在组间那 60 秒里，只有一次震动在告诉他"记上了"。**
第一批三件事（令牌 + 休息条 + 记一组的确认链）加起来不到一天，
做完之后它就会开始像一个"有手感"的 App；而真正的分水岭是那句元规则：
**训练屏上，少一个动画就多一分"这 App 不烦"。**
