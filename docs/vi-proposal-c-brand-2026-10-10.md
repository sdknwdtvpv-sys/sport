# 练了么 · VI 复核方案 C —— 图形语言 · 品牌资产 · 动效（2026-10-10）

> **复核人立场**：资深视觉设计，品牌 VI 全套落地 + App 动效规范方向。**只读代码、只读证据图，不动一行代码。**
>
> **复核范围（按要求的顺序走了一遍）**：
> `app/lib/core/theme.dart`（令牌）→ `app_tab_bar` / `app_top_bar` → `glass_overlay` / `glass_surface` /
> `native_tab_bar` / `native_segmented`（材质与平台差异）→ `features/progress/badges.dart`（73 枚）与
> `achievements_screen.dart` → `features/summary/share_card.dart` 与 `share_card_preview_screen.dart` →
> `docs/interaction-spec.md`（§8 动效与触觉 / §9 无障碍 / §11 反模式）、`docs/copy.md`、`PRODUCT.md`（§0/§2/§3）→
> `docs/screens.md`（S0/S1/S4/S7/S16/S18 精读）、`docs/plan-ux-2026-10-10.md`（刚落地的大改版）→
> `vi/*.html` 8 张（`tab-icon-system` / `splash-screen` / `achievement-badges` / `share-card` /
> `onboarding` / `complete-library` / `progress-home` / `profile`）→ **看图 30+ 张**（`store-assets/screenshots/*`、
> `docs/images/{workout,p01-motivation,p02-3tab,p1}-2026-10-10/*`、`v166-native-tabbar-iphone-2.png`、
> `v166-native-segmented-iphone.png`，以及 `icon/`、`store-assets/`、`app/ios/.../LaunchImage*`、
> 启动图那张 `launch_glyph.png`（**待新建**，Android 各密度目录下） 这几张品牌资产本身）→ 代码里的图形与动效事实（下文每条都带可复现的统计）。
>
> ⚠️ **本文不用 markdown 表格**（`tool/check-doc-tables.mjs` 会扫 `docs/*.md`；这份全是"一条一行"的清单，
> 用表格只会给守卫添误报面）。
>
> ⚠️ **本文只提方案，不改任何代码、不跑构建。** 所有数字都是数出来的，统计口径写在每一节里。
>
> **与 A / B 两份的关系**：A 管字阶与节奏、B 管色彩与层级。这一份管**图形（图标与徽章的形状）、
> 品牌资产（字标 / 启动 / 完成 / 空态的图形）、动效与触觉**。凡与 A/B 重叠处（例如字号、
> `text3` 对比度）本文只引用结论、不重复开条目。

---

## 一、一句话诊断

**这一版的图形病根是：这套产品有「主色」，没有「图形」。**

橙 `#FF5C26` 是一个真令牌，颜色一改全站同步；但**图形层从来没有被立成系统** ——
166 处 `Icons.`、112 个互不相同的字形（Material 图标名口径，见下），散在 86 个调用点上，
没有尺寸档（12 个字号值 11～42）、没有线宽档（Material 图标是字体字形，**根本没有线宽这个轴**，
唯一的例外是 4 处 `_outlined`/`_rounded` 后缀）、没有语义映射表（同一个火焰在 6 个地方指 6 件事、
同一个"换"在三屏用了 `refresh` / `swap_horiz` / `shuffle` 三个隐喻）；
品牌只有一枚「圆环」图形，而它**在 App 里一次都没被画出来**（只活在启动图与 Launcher 图标的构建产物里），
且这枚圆环自己就有 4 个不同的环径比；能代表品牌的另外两个出口（完成那一刻、分享卡）一个是静止色块、
一个连标都没有。

**最要命的是动效**：全仓 `AnimationController` **0 个、Tween 0 个、TickerProvider 0 个**，
`Curves.` 全仓只有 **2 处**、`Duration(milliseconds:` 只有 **5 处**（其中 1 处还是埋点退避）。
而 `interaction-spec.md` §8 已经写了 **5 条动效规格**，验收清单 §12 还有一条
「`prefers-reduced-motion` 下无动效残留」—— 那条判据在代码里**没有任何对应物**：
全仓 grep `disableAnimations` / `accessibleNavigation`，**0 命中**。
也就是说：规格书上的动效是写给一个不存在的实现的。

一句话：**「不做数据分析，做今天练什么」是一个很强的产品楔子，但它现在没有一个能被人一眼认出来的视觉楔子。
用户第一次练完、想截一张图发出去的那一刻，这个 App 拿不出任何属于它自己的东西。**

---

## 二、问题清单（28 条，按严重程度从高到低）

> 每条 = 【位置 / 证据】+【现在什么样】+【为什么不行】+【改成什么】。
> 前 12 条是 P0（用户能直接感知），中间 10 条 P1，最后 6 条 P2。

### 【P0-1】全仓没有一套图标系统：112 个字形、12 个字号、3 个族混用
- **位置 / 证据**：`app/lib` 全目录。统计口径与结果：
  `grep -ro "Icons\.[a-z_0-9]*" app/lib | wc -l` → **166 处**；
  去重后 `sort -u | wc -l` → **112 个不同字形**；
  后缀族分布 → 无后缀（Material 基础族，实心）**150**、`_outlined` **12**、`_rounded` **3**、
  `_filled` **1**（`replay_circle_filled`）、`_sharp` **0**、`_two_tone` **0**。
  字号分布（`grep -rho "size: *[0-9]*"` 落在 `Icon(` 上下文里）→
  **20(23) · 18(19) · 22(5) · 26(2) · 16(3) · 15(2) · 42(1) · 30(1) · 23(1) · 19(1) · 14(1) · 11(1)**。
- **现在什么样**：Material 图标是**字体字形**，只有"哪个字形"这一个自由度；线宽、圆头、端点全都写死在字形里。
  App 因此只能靠"换后缀"来表达粗细 —— 于是同一屏里 `Icons.check_rounded`（圆族）、
  `Icons.lock_outline`（线框族）、`Icons.check_circle`（基础实心族）并排出现在**同一个 `_statusChip` 里**
  （`achievements_screen.dart:559`）；底栏 `Icons.show_chart / fitness_center / person_outline` 里，
  第三个是线框、前两个是实心（`app_tab_bar.dart:81-86`）；iOS 那一支同一格却换成 SF Symbol
  `chart.line.uptrend.xyaxis / dumbbell.fill / person`，其中 `dumbbell.fill` 是**实心**而
  `person` 是**线框** —— 同一个底栏，两台设备三套粗细。
- **为什么不行**：这是这个 App"看起来不像一个品牌"的第一现场。图标不是一个词表，是一套**笔**。
  现在同时用了三支笔（实心字体、线框字体、原生 SF Symbol），还没有任何一支被声明为"我们的笔"。
  更要命的是客户给的 15 张界面稿**全部是自绘 SVG 描边图标**（见 [[P0-3]] 的统计）—— 也就是说
  连"VI 想用什么笔"这件事都是明确的，只是从来没被搬进代码。
- **改成什么**：**立 Material Symbols 可变字体为唯一图标源，并把它作为依赖外的随包资产引入**
  （一个 `.ttf`，与已随包的 Oswald 同一类做法，不加 pub 依赖）：
  1. **族**：全站统一 `MaterialSymbolsOutlined[FILL,wght,GRAD,opsz]` 的**可变轴**，
     `FILL` 轴只允许 **0 或 1** 两个值，**其余族（Rounded / Sharp / Two-tone）从代码里清零**；
  2. **线宽**：名义 `wght = 400`（≈ 24 单位网格上 2.0pt 视觉线宽）；**只有一处例外允许 `wght = 500`**
     —— 训练屏主按钮里那个勾（因为它压在橙底上，需要 +1 档视觉重量）。
     其余任何地方**不允许出现第二个 `wght`**；
  3. **尺寸档只留 4 档**（把现有 12 个值收干净）：
     `inline 16`（列表行尾、紧跟 13/14pt 文字）、
     `control 20`（顶栏动作、卡片头、通知行 —— 现状最常用的一档，保留）、
     `tab 24`（底栏、分段控件、导航）、
     `hero 40`（完成标记、空态主图形、徽章内芯）。
     **删除 11 / 14 / 15 / 18 / 19 / 22 / 23 / 26 / 30 / 42 这 10 个值**
     （18 → 20 或 16 按上下文二选一；22/23/26 → 24；42 → 40）。
  4. **线宽与尺寸的关系写死成比例**：`stroke = size / 12`（16→1.33、20→1.67、24→2.0、40→3.33）。
     这就是"差 0.2pt 也看得出来"的那条规则 —— 现在它连被写下来的机会都没有。
  5. **族的选择不按平台分，按"这一格是不是系统控件"分**：
     iOS 的 `UITabBar` / `UISegmentedControl` 里**继续用 SF Symbol**（那是系统语汇，VoiceOver 与选中态字重都靠它，
     这一条不要推翻，见 `app_tab_bar.dart:91-99` 的注释）；**系统控件之外的一切（99% 的界面）
     必须用 Material Symbols Outlined**。现在的病不是"两套并置"，而是"两套并置**且没有边界**"。

### 【P0-2】同一个字形在 6 个地方指 6 件事；同一个动作在 3 屏用 3 个隐喻
- **位置 / 证据**：
  `local_fire_department`（火焰）**6 处、指 5 件事**：
  `badges.dart:67`（`first_workout` 首训徽章）、`badges.dart:827`（"连续打卡"整条线的徽记）、
  `today_screen.dart:359-360`（首页连续天数那行事实，还带 `_outlined` 变体）、
  `profile_screen.dart:552`（「我」页连续天数）、`share_card.dart:183`（分享卡"连续打卡 N 天"）、
  `workout_summary_screen.dart:522`（完成页新解锁徽章圆的图标，"连续打卡"类）。
  "换"这件事用了**三个隐喻 + 三个尺寸**：
  `today_screen.dart:729` `Icons.refresh`（"换一批"，15pt，最不起眼）、
  `day_plan_editor.dart:227` `Icons.swap_horiz`（换动作，⇄）、
  `badges.dart:121` `Icons.shuffle`（"一场十个动作"徽章）。
  训练这件事用了**两个**：底栏 `Icons.fitness_center`（`app_tab_bar.dart:84`）、
  首页快捷入口 `Icons.menu_book_outlined`（动作库）。
  进步这件事用了**两个**：底栏 `Icons.show_chart`（`app_tab_bar.dart:83`）、
  首页 `Icons.insights`（`today_screen.dart:427`，18pt 强调色）。
- **现在什么样**：没有语义映射表，所以"这个动作该用哪个图形"每次都是现场决定。
  证据图 `docs/images/p02-3tab-2026-10-10/home-01-first-launch.png` 里，"今天练一次，就开始记连续天数"
  上面那枚图标几乎看不见（线框 + 低对比），而它在「我」页是实心火焰、在分享卡又是另一个尺寸。
- **为什么不行**：图标不是装饰，是**动词的缩写**。用户第二次看到火焰时如果它指的是"首训徽章"，
  第三次它指"连续 2 天"，那么它第 N 次就什么都不指了 —— 这一步走完，App 就失去了图标这一整条表达通道。
  "换一批 / 换动作 / 换一批动作"这三个动作是**同一类心智**（我不喜欢这个，给我别的），
  现在却要用户学三个符号。
- **改成什么**：落一张**语义映射表**（13 组、每组一个规范图形、给全部同义场景）：
  - **今天 / 开练入口** → `exercise`（哑铃形，替代现在的 `fitness_center` 与 `menu_book_outlined` 两种）
  - **进步 / 趋势** → `trending_up`（替代 `show_chart` + `insights` 两种）
  - **我** → `person`
  - **连续打卡 / 坚持** → `local_fire_department`（**唯一含义**：连续天数；徽章里凡是"连续/频率"类一律改走这条）
  - **力量 / 容量** → `fitness_center`（只在"力量突破"这一族用）
  - **里程碑 / 记录** → `emoji_events`
  - **探索 / 发现** → `explore`
  - **换（任何"给我别的"）** → `refresh`（**全站唯一**：换一批、换动作、换建议、换模板都用它；
    `swap_horiz` 只保留给"左右互换"这种真正的对调语义，`shuffle` 只保留给"随机"）
  - **换动作（左右切）** → `chevron_left` / `chevron_right`（已经是 19+9 处最常用的两个字形，顺势立为规范）
  - **破纪录** → `trophy`（**现在完全缺失**：`workout_summary_screen.dart` 的 PR 块只有文字，见 [[P1-2]]）
  - **休息 / 计时** → `timer`
  - **消息** → `notifications`
  - **设置** → `settings`
  - **重量单位** → 现在那个 `Ɣ` 形的重量符号（`exercise_picker_screen.dart`）与 `labels.dart:158-159`
    的"总重（含杠铃杆）/ 单只"是同一件事的两半，**改成同一个图形的两种文案后缀**。

### 【P0-3】客户的 15 张界面稿是"2.0 描边自绘图标"，App 用的是实心字体图标 —— 整条 VI 的笔是错的
- **位置 / 证据**：`vi/*.html` 逐张统计 `<svg>` 数量与 `stroke-width` 值：
  `detail 用的 training-home` 18 个 svg / 1.8 与 2.0、`workout-detail` 14 / 2.0 与 3.0、
  `achievement-badges` 16 / **全 2.0**、`notifications-settings` 23 / **全 2.0**、
  `complete-library` 12 / 2.0 与 3.0、`tab-icon-system` 12 / **全 1.8**、
  `onboarding` 5 / 2.5 与 3.0、`progress-home` 16 / 1.5 与 1.8 与 2.0 与 3.0。
  `vi/achievement-badges.html` 里那 16 个 svg **全部自带 2.0 描边**，是"线框 + 圆头"的插画式勋章图标。
- **现在什么样**：App 里对应位置用的是 `Icons.local_fire_department` / `Icons.fitness_center` /
  `Icons.emoji_events` 这类**实心字体字形**。同名的东西、同一个位置，一个细笔、一个实心块。
  证据对照：`docs/images/p01-motivation-2026-10-10/p01-03-achievements.png`（实心火焰在橙圆里）
  对 `vi/achievement-badges.html`（描边火焰，线宽 2.0）。
- **为什么不行**：**图标笔触是最容易被眼睛记住的 VI 层**，比色值更容易认。橙色是"色调"，
  线宽与端点是"字迹"。现在字迹是错的，所以再换一次色也救不回辨识度。
- **改成什么**：即 [[P0-1]] 第 1～4 条。补一条**与稿子对齐的写法**：稿子的 2.0 是画在 **24 单位 viewBox** 上的，
  换算到 20pt 渲染尺寸就是 `stroke = 2.0 × 20 / 24 = 1.67` —— 与 [[P0-1]] 第 4 条
  `stroke = size / 12` 完全一致。**也就是说这条规则能一次对齐稿子、又能数学自洽**，
  不需要"凭感觉调"。稿子里 1.5 / 1.8 那几个值属于稿子自身的不一致（见 [[P2-3]]），**以 2.0 为准**。

### 【P0-4】品牌只有一枚圆环，它没有被画进 App；而它在 4 个地方有 4 个不同的环径比
- **位置 / 证据**（我逐张量了像素，用橙色像素的扫描线宽度算环径）：
  - **真实主图** `store-assets/icon-1024.png` 与 `app/ios/.../Icon-App-1024x1024@1x.png`（二者 md5 相同）：
    中线扫描 `[(283,373),(490,502),(520,530),(650,740)]` → 内环半径 `(502-490)/2=6`、
    外环半径 `(740-283)/2=228.5`、**洞 / 环径 = 6/228.5 = 0.026**、
    环带厚 `90/228.5 = 0.39`、外径占比 **0.446**。
  - **iOS 启动图** `app/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png`：
    扫描 `[(79,104),(138,141),(146,148),(182,208)]` → 洞/环径 **0.030**、环带厚 **0.37**、外径 128px。
    几何上与主图同族（这条是**对的**，我原先怀疑它不一致，量完撤销了这个怀疑）。
  - **`vi/splash-screen.html`** 的 `.icon-ring`：`width:120px; border:18px solid` →
    洞 / 环径 = **42/60 = 0.70**、环带厚 0.30。
  - **`vi/onboarding.html`** 的 `.illus-ring`：`width:200px; border:28px solid` →
    洞 / 环径 = **72/100 = 0.72**、环带厚 0.28。
- **现在什么样**：主图与 iOS 启动图是"细环"（洞只有环径的 3%），
  两张界面稿是"粗甜甜圈"（洞占 70%）。物理上这是**两个不同的标记**：
  一个是"发光的小孔环"，一个是"甜甜圈"。而 App 内部（`onboarding` 那一屏的
  `Icons.bolt` + 绿勾气泡，见 [[P0-9]]）用的是第三种画法。
- **为什么不行**：品牌标记的第一条纪律是**几何可复现**。现在同一个"圆环"有 3 套比例，
  且**没有一处几何是写在代码里的**（`app/lib` 里没有任何地方画它）。
  也就是说：任何一个新设计师想把这个环放进一个新屏，他只能去量一张 PNG。
- **改成什么**：
  1. **把圆环立成唯一品牌标记，并写死几何**（以真实主图为真源）：
     **外径 : 环带厚 : 洞径 = 1 : 0.39 : 0.026**（也就是环带占半径的 39%，洞是半径的 2.6%）。
     落地时按外径反算：给定画布边长 `S`，外径取 `0.446 × S`，环带厚 `0.174 × S`。
     实现成一个 `BrandMark` 组件（`CustomPaint`，**零依赖**，与 `sparkline.dart` / `vi_area_chart.dart`
     同一类做法，那两个已经在自绘了）。
  2. **两个变体**，不许再有第三个：
     - `BrandMark.flat`（默认）：纯橙环 + 中心一个 2pt 的点，**无发光**。用于底栏、分享卡、空态、加载。
     - `BrandMark.glow`：加一层 `accent` 18% 的径向辉光（就是现在 App 图标里那圈）。
       只允许用在**启动屏与完成页**这两个"仪式性"位置，一屏一次。
  3. **`vi/splash-screen.html` 与 `vi/onboarding.html` 的 0.70/0.72 环径比视为稿子笔误**，
     按 0.026 重画（见 [[P2-3]] 的处理原则）。

### 【P0-5】启动图里的标记是"白盘橙环"——环的洞是白的，iOS 与 Android 两平台都错
- **位置 / 证据**：我对 `LaunchImage@3x.png`（288×288）逐点取样：
  环心 `(144,144)` = **`(251,250,253,255)` 近白**，环心旁边辉光 `(144,100)` = `(254,131,79)` 橙、
  `(144,90)` = `(255,139,82)` 橙、`(100,144)` = `(253,100,61)` 橙；
  而品牌主图里同一个位置是**深色底 + 一个亮点**。四角与外围 `alpha = 0`（这部分是对的，深色由 storyboard 的
  `backgroundColor` 提供：`red=0.0549 green=0.0471 blue=0.0392` ≈ `#0E0C0A`，与 `Tokens.bg` 一致）。
  同一张图在 Android 是 `app/android/app/src/main/res/drawable-nodpi/launch_glyph.png`（同为 288×288），
  在 `launch_background.xml` 里 `android:gravity="center"` 摆上去。
- **现在什么样**：冷启动时屏幕正中是一个**白底圆盘 + 橙环 + 中心针尖亮点**。在暖黑 `#0E0C0A` 上，
  这个白盘是整屏最亮的东西，尺寸 128pt。App 图标里那个洞是**暗的**、里面只有一颗星点。
- **为什么不行**：这是用户**每次冷启动都会看 0.5–1 秒**的画面，是品牌的第一印象与最后印象。
  现在它传达的是"一个白色圆盘"，不是那个环。而且白盘在暖黑上会有一圈明显的硬边（AA 边缘 + 白到黑），
  看起来像**图片没加载完**。
- **改成什么**：
  1. 重出 `LaunchImage`（1x/2x/3x）与 `launch_glyph.png`：把环心挖成**全透明**，
     只保留环带与中心点，让 storyboard / `app_background` 的 `#0E0C0A` 透上来；
  2. 外径从 128pt 保持不变（`LaunchImage@3x` 288px ÷ 3 = 96pt 名义、环径 128px ÷ 3 ≈ 42.7pt，
     按 [[P0-4]] 的外径占比 0.446 反算，画布 96pt 对应的外径应是 **42.8pt** —— **这一处其实恰好是对的**，
     不要动尺寸，只改洞的颜色）；
  3. **不要**在这一步加发光动画：启动图是静态资源，动效交给 [[P1-7]] 的 App 内启动过渡（`BrandMark.glow` 淡入）。

### 【P0-6】徽章的图形语言在两张屏上是两套；且完成页的图标来源与注释里写的不是一回事
- **位置 / 证据**：
  - 收藏册（`achievements_screen.dart:437-566` `_BadgeTile`）：外圈 64 / 内芯 46 / 环形进度线宽 3 /
    右下角 20 的锁或勾戳 / **每枚徽章按 `badgeIcon(id)` 取自己的图形**（73 条显式映射，`badges.dart:65-147`）。
  - 完成页（`workout_summary_screen.dart:483-527`）：38 的圆 / 无环 / 无戳 / **按 `b.category` 取类图标**，
    且 `_badgeIcon` 只有 4 个分支。
  - **`workout_summary_screen.dart:515` 的注释原文**：「徽章圆里那枚图标：照类别给（收藏册里是同一套，
    见 `achievements_screen.dart`）。」——**这句话是假的**，收藏册是照 id 给、73 套图形；
    完成页是照类别给、4 套图形。
- **现在什么样**：证据图 `p01-01-summary-unlock.png` 里，完成页那条横条上两枚圆**都是火焰**
  （"首训"与"早鸟"都属于连续打卡类）；而同一枚"首训"在 `p01-03-achievements.png` 的收藏册里
  也是火焰（碰巧对上了），但"早鸟"在收藏册里是 `wb_sunny_outlined`（**太阳**），完成页里却是火焰。
  同一个徽章，两张屏两个图形。
- **为什么不行**：徽章系统的全部价值在于**"这一枚是独一无二的"**。收藏册里做到了（73 枚 73 个图形，
  有 `badge_visuals_test.dart` 钉着 id 不重复）；完成页把它降级成 4 个类图标，
  于是"一次解锁了 4 枚"在完成页看起来像"我拿了 4 个一样的"。这是**在最有仪式感的那一刻**把奖励贬值。
  另外，注释写假话正是这个仓库最防的那类问题（与 `theme.dart` 里把 `volt` 改名成 `accent` 是同一条纪律）。
- **改成什么**：
  1. 把徽章圆**抽成一个公共组件** `BadgeMedallion({required BadgeStatus b, required double size, bool showRing, bool showChip})`，
     放 `badge_medallion.dart`（**待新建**，放 `app/lib/features/progress/`），**完成页与收藏册共用同一个渲染器**；
     完成页用 `size: 38, showRing: false, showChip: false`，收藏册用 `size: 64, showRing: true, showChip: true`。
  2. **图形一律走 `badgeIcon(id)`**，删掉 `workout_summary_screen.dart` 里的 `_badgeIcon`
     与那句假注释。完成页的"两枚圆"必须与收藏册里那两枚**长得一模一样**。
  3. 尺寸档写进规格：`compact 38` / `list 48` / `grid 64` 三档，**不允许第四档**
     （现在 38 与 64 是唯一的两个值，正好收成两档，`list 48` 留给通知中心的徽章消息）。

### 【P0-7】未解锁徽章违反了产品自己刚拍板的两条设计决定；三档稀有度在执行上已经三色不分
- **位置 / 证据**：
  - `docs/plan-ux-2026-10-10.md` §五-B 第 3 条原文：「**未解锁的勋章不写"还差 N 次"，只显示锁与灰名**。
    收藏册不该变成 73 条待办清单。」
    而 `achievements_screen.dart:474-484` 现在渲染的是：
    `badge.unlocked ? badge.how : (badge.hidden ? '？？？' : '还差 ${badge.target - badge.current}')`
    —— **"还差 N" 在全站最多会同时出现 69 条**（73 枚里只有 4 枚隐藏徽章走 `？？？`）。
    证据图 `p01-03-achievements.png` 里"三天不断"下面就是"还差 2"、"一周不断"下面"还差 6"。
  - 同一节第 4 条现状还有：收藏册一屏里除了 `4 / 73`，另有"已解锁 4 / 73 枚徽章"、
    "白银 · 3 枚"、"还差 4 枚到黄金"、"收集进度 4 / 73"、"收集线"四条各一根进度条、
    "本周挑战 · 1 / 3 次"、"连续打卡 2 / 20"—— **一屏 8 个数字、6 根进度条**，
    正是 §一 说要收敛掉的"四套心智"。
  - 稀有度三档在代码里：`common → Tokens.accent #FF5C26`、
    `rare → Tokens.tierRare #8350EE`、`epic → Tokens.pr #FBBF24`（`badges.dart:36-40`）。
    而 `badgeTierColor` 同时被用在**环形进度的弧线**上（`_BadgeRingPainter`）——
    **未解锁的徽章也用档位色画弧**（`color.withValues(alpha: 0.85)`）。
- **现在什么样**：在 `p01-03-achievements.png` 里，"三天不断"（**未解锁**）的外圈是满的橙金色，
  与旁边"首训"（**已解锁**）的外圈**肉眼几乎分不出**。`achievements_screen.dart:433-436` 的注释
  明确写着「三件事同时在说"拿没拿到"……**颜色：三档稀有度只说"这枚值多少"，不说"拿没拿到"**」——
  但代码把档位色画到了进度弧上，弧的**长度**才表示进度、**颜色**却与已解锁态同色，
  于是"注释说的"与"眼睛看到的"不一致。
- **为什么不行**：这一屏的设计意图（`screens.md` S16 三条纪律）是"未解锁的照样显示，让人知道目标在哪"。
  但**目标感与待办清单只差一个执行**：69 条"还差 N" = 待办清单，就是用户 10.10 明确否掉的东西。
  而颜色执行上，最该被第一眼读出的"拿没拿到"这个二值信息，被三档颜色与进度弧一起模糊掉了。
- **改成什么**：
  1. **严格执行 §五-B 第 3 条**：未解锁的徽章**只有锁 + 灰名**。
     删掉 `'还差 N'` 那一支，未解锁的一律走 `'？？？'` 之外的第三条：
     **不显示任何第二行**（`Text` 整块不出现，不是显示空串）。
     进度感改由**外圈环形进度的长度**一条通道承担（已经画了，够了）。
  2. **档位色只出现在"内芯"**：环形弧线（track 与进度弧）**统一走中性灰**，
     已解锁时弧线走 `Tokens.text3`、未解锁时走 `Color.lerp(Tokens.elevated, Tokens.text3, 0.35)`
     （这个中间灰已经在用，保留）。**"已解锁 = 有色内芯 + 勾戳"、"未解锁 = 灰弧 + 无内芯色 + 锁戳"** ——
     这样"拿没拿到"变成二值可辨，档位色退回它该待的地方。
  3. **三档的区分度加两重非颜色通道**（`interaction-spec.md` §4 第二条硬约束：
     "任何状态都不能只靠颜色表达"—— 这条现在只被勾/锁满足了"解锁"这一个维度，
     稀有度这个维度**完全靠颜色**）：
     - **内芯描边档**：普通 0pt（无描边）/ 稀有 1pt / 史诗 2pt；
     - **外形档**：普通 = 正圆；稀有 = 正圆 + 外圈一道 1pt 断开弧（4 段）；
       史诗 = 正圆 + 外圈一道 1pt 全环 + 顶部一个小尖角。
     这样黑白打印、色盲、强光下三种情况都能读。
  4. **一屏数字收敛**：收藏册顶部只留 `已解锁 N / 73` 一个数字 + 段位一行文字；
     "收集进度"整块与"收集线"四条进度条**合并成一条总进度**（四条线改用四个不同颜色的
     **小色块 + 文字**并列，不再各画一根条）。目标：一屏进度条从 6 根降到 **1 根**。

### 【P0-8】空态与错误态全是"一行灰字"，且那句话本身不合格（对比度 + 缺图形语言）
- **位置 / 证据**（全仓空态/错误态字符串）：
  `progress_screen.dart:284`「还没有训练记录。\n练完第一次，这里就会长出曲线和纪录。」
  `all_data_screen.dart:303`「这个动作还没有记录。练过一次再来。」、
  `all_data_screen.dart:470`「这段时间还没有记录」、
  `today_screen.dart:324`「还没有训练记录」、
  `today_screen.dart:760`「今天还没有排动作」、
  `routine_screen.dart:242`「还没有计划。\n先用下面任意一套模板，」、
  `routine_screen.dart:353`「还没有动作」、`routine_screen.dart:563`「还没有动作。加几个，下次直接照着练。」、
  `plan_screen.dart:269`「今天还没有排动作 —— 回首页点「开始今天的训练」会自动生成。」、
  `plan_screen.dart:414`「还没有练过。\n练完第一次，这里会按周记下你练了几次、多少容量。」、
  `profile_screen.dart:363`「还没有训练记录。练完第一次，这里就有数了。」、
  `exercise_picker_screen.dart:416`「没找到这个动作。\n换个词试试，或者点右上角「＋ 新建」自建一个。」、
  `exercise_detail_screen.dart:215`「这个动作还没有写说明 —— 你可以先按自己的做法练，」、
  `notification_center_screen.dart:127`「还没有消息。\n成就解锁、错过的提醒、备份结果都会记在这里。」、
  `cloud_backup_screen.dart:670`「云端还没有备份」、
  `privacy_about_screen.dart:223`「还没有攒下事件。先练一次再回来导」。
  **共 16 处，全部是"一到两行灰字、无图形、无按钮"**（唯一的例外是"没找到这个动作"里那句
  指向上一个可见入口的文字指引）。字号基本 13pt、颜色几乎全是 `Tokens.text3`。
  `Tokens.text3` 在 `bg` 上 **3.23:1**、在 `surface` 上 **2.95:1**（我手算了 WCAG 相对亮度）；
  **全仓 `color: Tokens.text3` 出现 220 次，是所有颜色里的第一名** —— 空态正是它的主要落点之一。
  `today_screen.dart:324` 那处更糟：它是首页主卡片下方的一行「还没有训练记录」，
  在证据图 `home-01-first-launch.png` 里就是**屏幕下半部唯一的内容**，孤零零一行灰字。
- **为什么不行**：`docs/copy.md` 给空态定的判据是第 4 条「**下一步**」——
  "空状态 / 失败状态里告诉用户现在该干什么"。这 16 处里做到"下一步"这个要求的只有 5 处，
  其余 11 处只是在陈述"这里没有东西"。而 3.23:1 的灰字连"被读到"都保证不了，
  更不用说它出现在一个**深色、暗光、屏幕有汗**的健身房场景里（`PRODUCT.md` §1）。
  健身类 App 的空态该说的是**"你现在的下一步动作是什么，几秒钟能做完"**，
  而不是"这里还没有数据"（那是数据库在说话，不是产品在说话）。
- **改成什么**：
  1. **建一套空态图形语言（这是品牌资产里最容易做、回报最快的一项）**：
     一个统一的空态块 `EmptyState({required EmptyArt art, required String line, String? next, Widget? action})`，
     三件套 **图形 + 事实句 + 下一步**，垂直居中、左对齐、占屏高 40% 左右。
  2. **图形**：**只做 5 个**，全部是 `BrandMark` 的派生（同一个笔、同一个橙）：
     - `dashedRing`（虚线圈）—— "还没有数据"（进步页、全部数据页、体测）
     - `halfRing`（半环 + 箭头）—— "还没开始"（首页无记录、计划页无历史）
     - `ringWithPlus`（环 + 加号）—— "去新建 / 去添加"（动作库空、计划空、自建动作）
     - `ringWithLock`（环 + 锁）—— "还没授权 / 还没开启"（健康授权、云备份）
     - `ringSearch`（环 + 放大镜）—— "没搜到"（搜索无结果）
     全部 `stroke = 2.0 @ 24 网格`，渲染尺寸 **120pt**，颜色 `Tokens.text3` 提到
     **`#8A8176`**（B 方案给的修正值，在 `bg` 上 5.10:1），中心那个点用 `Tokens.accent` —— 
     **一屏一个重点**，让空态也有焦点。
  3. **事实句 + 下一步句**：事实句 15pt `Tokens.text2`（7.91:1 过关）；下一步句 13pt `Tokens.text2` 配
     **一个真按钮**（次级按钮规格：高 48、透明底、按下 `elevated`）——
     现在 16 处空态里**一个按钮都没有**，这是最大的问题，不是少了一张插画。
  4. **优先改 6 处**（用户会真的撞上的）：首页无记录、进步页无记录、全部数据页无记录、
     动作库无结果、通知中心空、计划页无历史。

### 【P0-9】完成那一刻没有资产：设计稿的完成页是一个有编排的画面，App 是一块静止色块
- **位置 / 证据**：
  - `vi/complete-library.html` 的完成屏（`<div class="complete-screen">`）元素清单：
    `complete-icon-wrap` > `complete-circle` > 勾 svg；`complete-title`「训练完成！」；
    `complete-sub`「干得漂亮，又变强了一点」；**`complete-workout-name`（训练名，App 里没有这一行）**；
    `complete-stats` 三格（时长 / 动作数 / 总容量）；**`pr-popup`（🏆 emoji + "新纪录！卧推 65kg" +
    "较上次提升 5kg，继续保持！"，一个独立的浮层）**；`exercise-summary`（动作一览，
    四行"动作名 + 4组 × 60-65kg"）；两个按钮「分享成绩」/「返回」。
  - App 的完成页（`workout_summary_screen.dart:388-425` `_doneMark`）：
    **76×76 的 `Tokens.success` 实心圆 + `Icons.check_rounded` 42pt + 一行 28pt 标题 + 一行 14pt 副标题**，
    下面是三格数字、新解锁横条、一句话输入、下一次、拉伸、两个按钮。
  - `_doneMark` 之外**没有任何动画**：`grep AnimationController|Tween|TickerProvider` 在
    `workout_summary_screen.dart` 里 **0 命中**。
  - 证据图 `store-assets/screenshots/07-summary.png`（旧版）与
    `docs/images/p01-motivation-2026-10-10/p01-01-summary-unlock.png`（新版）：
    绿色圆是一个**平涂色块 + 白勾 + 一圈 25% 绿的模糊**，没有任何"出现了"的感觉。
  - 那一格的勾是 `Icons.check_rounded`（**Rounded 族**）、色值是写死的 `Color(0xFF06231A)`，
    与 `Tokens.accentInk = #141210` **不是同一个色**；同屏的 `Tokens.success` 也会出现在
    通知中心的**系统消息**上（`notification_visuals.dart:24`）。
- **现在什么样**：一个用户练完一场、最有分享欲的那一屏，视觉上是一个**静止的绿圆**。
  绿圆里的勾与设计稿的勾笔触不同（稿子 `stroke-width: 2`、24 网格，App 是字体字形的圆族）。
  设计稿里最有传播力的两个元素（**训练名** 与 **PR 浮层**）在 App 里一个都没有：
  PR 只有一行 13pt 文字"这次破了纪录"（`share_card.dart:110` 也是同样处理）。
- **为什么不行**：`PRODUCT.md` §0 的楔子是"打开就练，练完就记"。**"练完"是产品的第二个锚点**，
  它现在既没有动画节奏、也没有品牌符号、也没有一个值得截图的编排。
  用户不会因为一个数字截图，会因为"这个画面值一个赞"截图。
- **改成什么**（这一条是本文最值钱的一条，建议优先做）：
  1. **完成页加一根"时间轴编排"**（总额 1400ms，见 §四 动效清单 M-08）：绿勾"画"出来 →
     标题上浮 → **三格数字依次滚动**（现在 `Tokens.display` 的 Oswald 是可变字体，
     数字滚动是它的天然优势）→ 新解锁横条从下推入 → 完成按钮的橙色渐显。
  2. **绿勾换掉**：不用 `Icons.check_rounded`，用一条自绘的**描边勾**（`CustomPainter` + `Path`，
     `strokeWidth = 4`、圆头圆角、用 `PathMetric` 做"画出来"的动画）。
     色值统一到 `Tokens.accentInk`，删掉那个 `Color(0xFF06231A)`。
  3. **补两件缺失的资产**：
     - **训练名**：把这张训练的部位名（引擎已经算出来了，`today_planner` 里的"上肢/下肢"）
       放在"训练完成！"下面一行 15pt `Tokens.text2`。**这一行是分享卡标题的同一句话**，两处必须同一个源。
     - **PR 浮层**：设计稿的 `pr-popup` 完全没做。做一个：
       `Tokens.pr` 琥珀底 12% + 琥珀 28% 描边 + 左侧一枚 24pt 的 `trophy` 图标 +
       "新纪录！卧推 65kg" + "较上次 +5kg"。**它是露出 3000ms 后淡出的浮层**（不是常驻卡片），
       只在 `hasPr` 时出现。现在 PR 只有一行字，这是产品差异化（"渐进超负荷"）最该被看见的瞬间。
  4. **完成页背景加一层 `BrandMark.glow`**（外径 0.446 × 320pt ≈ 143pt，透明度 6%），
     放在绿勾后面做"光环"。这一下就把"完成"和品牌标记绑在一起了 ——
     以后用户看到橙环就想到"练完了"。

### 【P0-10】分享卡是这个产品唯一的对外输出，但它在微信里认不出来
- **位置 / 证据**：
  - `share_card.dart:75-83`：品牌位是**一段橙色文字**「练了么」（15pt、`w700`、`letterSpacing: 1`），
    **没有图形**。`grep -n "练了么" app/lib/**/*.dart` 全仓只有两处是"界面上的字标"：
    这里（15pt）与 `privacy_consent_screen.dart:85`（28pt、`w800`、**无 letterSpacing**）。
  - `vi/share-card.html` 的对应位是一个 `<div class="brand-icon"></div>`（**一个图形**，
    CSS 里有尺寸与形状，不是文字）＋ `.brand-name`；卡片底部是 `.user-info`（`.avatar` 圆形字母 +
    `.user-name`「练了么用户」）＋ `.share-badge`（「分享自练了么」/「LIANLE.ME」）。
  - `vi/share-card.html` 的正文结构：`.workout-title`（训练名）→ `.workout-subtitle`（N 个动作 · N 分钟）→
    `.stats-row`（三格数字，**主数字 320 大、另两格小**）→ `.exercises-list`（**三行动作明细：
    动作名 + 60kg × 4组**）。
  - App 的实现：标题固定为「训练完成」（不是训练名）→ 三行 `_stat`（**等权重**，没有主次）→
    **没有动作明细**，底部只有一行 `${exerciseCount} 个动作 · ${totalSets} 组`；
    `_streakCard` 的底部是一个 **26pt 橙圆里写一个「练」字**（`share_card.dart:200-212`）——
    这是全 App 唯一的"字母标"，而它是个汉字。
  - 尺寸：`kShareCardWidth = 360`、`kShareCardHeight = 460`、`kShareCardPixelRatio = 3`
    → 导出 **1080 × 1380**（3:4 竖版）。
- **现在什么样**：这张卡导出后是一张**深色底、橙色小字"练了么"、三行等权数字**的图。
  在微信聊天流里，它与其他健身 App 的分享卡（普遍带 logo + 大数字 + 明细）**没有任何可区分的形**。
- **为什么不行**：`PRODUCT.md` §4 写着「一期的社交用"训练结束生成一张分享卡 → 微信"替代」——
  这张卡承担了**全部的获客职能**。它现在的品牌露出是一个 15pt 的橙字，
  在朋友圈缩略图尺寸（约 200pt 宽）下，那三个字只有约 8pt 高，**不可读**。
  另外 `docs/copy.md` §一 明确写着「商店素材、分享卡上的字不在本次范围」——
  也就是说这张卡上的文案从来没被那把尺子量过，它是全产品唯一一块**没被设计过的地方**。
- **改成什么**：
  1. **卡头换成 `BrandMark` + 字标**：左侧 `BrandMark.flat` 28pt（外径 12.5pt）+ 右侧字标
     「练了么」用 **`Tokens.display(16, weight: 700, letterSpacing: 2)`**（Oswald 走拉丁、
     中文回落系统字体，与 `theme.dart` 的字体策略一致）。**字标必须与 [[P1-5]] 字标规范逐字一致**。
  2. **加动作明细（这是微信里唯一能被读的内容）**：`summary` 里已经有动作数据，
     按稿子的 `.exercises-list` 加**前三行**：动作名 13pt `text` + 右侧 `60kg × 4组` 13pt `text2`。
     卡片高度从 460 提到 **520**（导出 1080 × 1560，仍是安全的竖版比例）。
  3. **三格数字立主次**：主格（容量）走 `Tokens.display(34)`，另两格走 `Tokens.display(20)` 且颜色 `text2`
     —— 现在三行等权，眼睛没有落点。
  4. **底部去掉那个汉字圆，换成 `BrandMark.flat` + 「分享自练了么」**（与稿子的 `.share-badge` 一致）。
  5. **两款版式加"卡内差异"**：明细版主数字是容量；打卡版主数字是 `DAY N`（已经是 44pt Oswald，是对的）。
     两款都要带上同一枚 `BrandMark`，让"哪张卡、哪个 App"一眼可认。
  6. **必须验证缩略图可读性**：在 200pt 宽的预览下，字标与主数字必须仍可读。
     这是这张卡唯一真正的验收标准，现在没有任何测试或检查在看这件事。

### 【P0-11】动效规格写在一份"没有实现"的规格书里：全仓 0 个动画控制器、2 条曲线、5 个时长
- **位置 / 证据**：
  - `grep -rn "AnimationController\|SingleTickerProvider\|TickerProvider\|Tween\|AnimatedBuilder\|AnimatedSwitcher\|AnimatedContainer\|AnimatedOpacity\|AnimatedScale\|AnimatedPositioned\|AnimatedAlign\|AnimatedPadding\|Hero(" app/lib` → **0 命中**。
  - `grep -rn "Curves\." app/lib` → **2 命中**：
    `main.dart:277` `Curves.easeOutCubic`（iOS 换 tab 时的 `PageView.animateToPage`）、
    `intro_carousel_screen.dart:154` `Curves.easeOut`（引导页指示点）。
  - `grep -rn "Duration(milliseconds" app/lib` → **5 命中**：
    `main.dart:276`（`260 + 90 * |i-from|`，iOS tab 切换）、
    `intro_carousel_screen.dart:153`（220）、`haptics.dart:64`（触觉间隔 120）、
    `analytics/flusher.dart:51`（埋点退避，与 UI 无关）、
    `domain/models.dart:457`（**时长计算，不是动效**）。
    **真正的 UI 动效只有 3 处**。
  - 而 `interaction-spec.md` §8 已经定义了 **5 条**动效（记录一组 280ms / 弹层 260ms /
    步进无动效 / PR 400ms / 训练结束 600ms 数字滚动），
    §12 验收清单还有「`prefers-reduced-motion` 下无动效残留」。
  - `grep -rn "disableAnimations\|accessibleNavigation" app/lib app/ios app/android` → **0 命中**。
  - **平台不一致**（这条是真 bug 级）：`main.dart:268-278` 的 `_selectTab` 里，
    `if (!GlassSurface.isSupportedPlatform) return;` ——
    **Android 上点底栏是瞬切，iOS 上是 260–350ms 缓动滑动**。
    同一台产品，两台设备的 Tab 切换是两种手感，且**规格书里从来没定义过 Tab 切换的动效**。
- **现在什么样**：`vi/*.html` 里的稿子是有动效的（`splash-screen.html` 的
  `@keyframes ringPulse` 2.5s / `dotGlow` 2.5s / `loadDot` 1.4s 错峰；
  `tab-icon-system.html` 的 `.tab-item { transition: all 0.2s ease; }`）——
  客户给的稿子都在动，App 里除了 iOS 换 tab 什么都没动。
- **为什么不行**：动效是这个产品**唯一能替代"解释性文案"的东西**（`copy.md` 刚把解释性文案删干净了）。
  删掉文案之后不补动效，用户就失去了"发生了什么"的全部线索。
  最典型的是**记一组**：现在点大按钮，一行新行凭空出现（`workout_screen.dart` 的已完成列表），
  排在前面的行会整体上跳 —— 没有 `AnimatedList`、没有入场位移，
  用户在小屏上会**怀疑自己是不是点了两次**。这正是 `PRODUCT.md` §1 那个"组间 60 秒、一只手、屏幕有汗"
  的场景里最不能发生的事。
- **改成什么**：见 §四 的**动效清单**（18 条，每条给触发 / 时长 / 曲线 / 降级）。
  工程上要做三件事：
  1. **建 `motion.dart`（**待新建**，放 `app/lib/core/`）**：导出 4 条曲线常量与 5 个时长常量
     （`Tokens` 的兄弟文件，与 `theme.dart` 并列）。**所有动效只许从这里取值**，
     与"颜色只许从 `Tokens` 取"是同一条纪律。现在 2 条曲线是各写各的，所以才会漂。
  2. **建 `reduced_motion.dart`（**待新建**，放 `app/lib/core/`）**：一个 `bool reducedMotion(BuildContext)`，
     读 `MediaQuery.disableAnimationsOf(context)`（Flutter 对
     iOS「减弱动态效果」/ Android「移除动画」的原生映射），
     并把它作为**所有** `duration` 的短路：`duration: reducedMotion(ctx) ? Duration.zero : Motion.fast`。
     **不允许任何一处绕过它**（验收判据：在系统开启减弱动态效果后，
     全站 grep 出的每一个 `Motion.*` 都被这一层包住）。
  3. **Android 的 Tab 切换必须补动效**，删掉 `_selectTab` 里那句平台早返回，
     两支共用同一段 `animateToPage`（iOS 多一层原生玻璃弹簧，Android 走同一时长同一曲线）。

### 【P0-12】触觉与视觉不同步：3 个触发点、3 个强度，且与动效规格互相矛盾
- **位置 / 证据**：
  - 全部触觉只有 **3 个触发点**（`haptics.dart:50-66`）：
    `setLogged → HapticFeedback.mediumImpact()`、
    `restFinished → HapticFeedback.heavyImpact()`、
    `targetReached → lightImpact + 120ms + lightImpact`。
    调用点只有 3 处（`workout_controller.dart:596 / 743 / 834`），全部 `unawaited`。
  - 而 `interaction-spec.md` §8 那张表里写了 **6 个**触觉（记录一组 `light impact` /
    弹层 `selection` / 步进调整 `selection` / 破纪录 `success notification` /
    训练结束 `success notification`）。
    **规格里的 6 个，代码里实现的是另外 3 个，且强度对不上**：
    规格说"记录一组 = light"，代码是 `mediumImpact`；
    规格说"训练结束 = success notification"，代码**根本没有 success 这一档**。
  - **与视觉不同步的三处**：
    ① 休息倒计时那条细进度走到 100% 的那一帧**没有触觉**，触觉在 `restFinished` 里
      （`workout_controller.dart:834`），而进度条的绘制与它是两条独立的路径 ——
      快速滑过时会有可见的先后差；
    ② 记一组时**新行入场没有任何动效**（见 [[P0-11]]），但触觉已经震了 ——
      手先知道、眼睛后知道，且眼睛看到的是一次"跳变"；
    ③ 破纪录（`prCount` 增长）**既没有触觉也没有动效**，只有一行 13pt 琥珀字。
  - `targetReached` 的"两下"用 `Future.delayed(120ms)` 实现 —— 它**不参与 Flutter 的帧时间**，
    所以在掉帧时这个节奏会漂（一次中等/一次重的区分也会跟着漂）。
- **为什么不行**：触觉是"不用看屏幕的确认"（`haptics.dart` 文件头自己写的），
  而"不用看屏幕"的前提是**触觉必须与视觉同一拍**。现在触觉是独立的一层，
  视觉是另一层，两者靠代码顺序凑在一起 —— 一旦有人加一条动效，就会错。
  另外 `interaction-spec.md` §8 与 `haptics.dart` 的 6 vs 3 差异说明：
  **规格书没有跟着实现走，或者实现没有跟着规格书走，且没有任何守卫在看这件事**
  （对比 `docs/copy.md` 有 `tool/check-user-text.mjs` 在守）。
- **改成什么**：见 §五 的**触觉清单**（12 条）。三条纪律：
  1. **触觉必须由"视觉状态变更"这一件事触发，不由控件回调触发**。
     落地做法：把触觉挂在同一个 `setState` 的状态迁移上，
     与动效的 `AnimationController.forward()` 同一个调用点。
  2. **iOS 用 `HapticFeedback` 的四档**（`lightImpact` / `mediumImpact` / `heavyImpact` /
     `selectionClick`），**Android 用 `HapticFeedback` 的同样调用**（Flutter 会映射到
     `View.performHapticFeedback` 的对应常量）。**不在这一版引入第三方触觉包**
     （与 `pubspec.yaml` 的"依赖保持最小"一致）。
  3. **补上"重"的那一档**：`HapticFeedback.heavyImpact` 现在只给"休息结束"，
     而"训练完成"（真正的高潮）**没有任何触觉**。这一个是必须补的。

---

### 【P1-1】通知中心三类消息用了三支不同的笔，且"成功绿"在这里被用在"云消息"上
- **位置 / 证据**：`notification_visuals.dart:17-25`：
  成就 → `Icons.emoji_events_outlined`（**线框族**）、
  提醒 → `Icons.alarm`（**基础实心族**）、
  系统 → `Icons.cloud_outlined`（**线框族**）。
  颜色：成就 → `Tokens.pr`（琥珀）、提醒 → `Tokens.accent`（橙）、系统 → `Tokens.success`（绿）。
- **现在什么样**：三类消息在同一列里，笔触两个族、颜色三个语义。
  `Tokens.success` 在 `theme.dart:45-48` 的注释写的是「**成功/完成**（训练完成页那个勾）」，
  在这里被用作"系统消息/云"的**种类**色。
- **为什么不行**：`theme.dart` 自己写着"每个色都是**一整屏的意思**"。
  绿 = "完成"是用户唯一学过的一次绑定（完成页那个勾）；一旦绿也指"云"，
  那条绑定就没了。B 方案已经在记"语义色越界"，这一条是图形侧的同一个病。
- **改成什么**：三类颜色改为 `Tokens.accent`（成就，它本来就是"奖励"）/
  `Tokens.text2`（提醒，中性）/ `Tokens.text2`（系统，中性）；
  用**图形**区分种类而不是颜色：成就 `trophy`、提醒 `timer`、系统 `cloud`（全走 [[P0-1]] 的族与线宽）。

### 【P1-2】破纪录（PR）没有任何视觉资产：产品最强的差异化，在界面上的存在感是一行 13pt 字
- **位置 / 证据**：`share_card.dart:108-133`（分享卡上 `hasPr` 时是"这次破了纪录" + 最多两条 + "还有 N 项"）；
  `workout_summary_screen.dart` 的 PR 块（同 `screens.md` S7 里那行「★ 破纪录（若有）」）。
  设计稿 `vi/complete-library.html` 的 `pr-popup` 是**一个独立的浮层**（🏆 + 标题 + 描述）。
  全仓 grep `trophy` / `emoji_events`：只有 `badges.dart` 的徽章与 `notification_visuals.dart`。
  **完成页没有奖杯图形。**
- **现在什么样**：破了纪录，用户看到的是琥珀色的一行小字。
  `Tokens.pr` 是 `#FBBF24`，在 `surface` 上 **10.69:1**（我手算的）—— 颜色本身是全场最强的，
  却被用在一行 13pt 字上。
- **为什么不行**：`PRODUCT.md` §6 的差异化楔子是"渐进超负荷"（双重渐进）。
  **PR 是这个楔子唯一的高光时刻**，现在它比"新解锁徽章"弱得多（后者有一整条带渐变与描边的横条）。
  这是权重倒置：奖励（徽章）比成就（PR）更响。
- **改成什么**：做 `PrBadge` 组件（设计稿的 `pr-popup` 落地）：
  `Tokens.pr` 12% 底 + 28% 描边 + `rCard` 圆角 + 左 24pt `trophy`（`Tokens.pr`）+
  主行 15pt `w700`「新纪录！{动作名} {重量}」+ 副行 13pt `text2`「较上次 +{delta}kg」。
  **入场 400ms（M-06），停留 3000ms，淡出 300ms**。完成页与分享卡共用同一个数据源与同一个视觉。

### 【P1-3】首页快捷入口那三格：三个图标来自三个族，其中两个是线框、一个是实心
- **位置 / 证据**：`today_screen.dart:501-505`：
  `Icons.menu_book_outlined`（线框）/ `Icons.monitor_weight_outlined`（线框）/
  `Icons.timer_outlined`（线框）—— 这一组是**一致的**（三枚全线框）。
  但同一屏的另外几处是混的：`:427` `Icons.insights`（实心、18pt、`accent` 色）、
  `:481` `Icons.balance`（实心）、`:609` `Icons.play_circle_outline`（线框）、
  `:729` `Icons.refresh`（实心、15pt）、`:753` `Icons.chevron_right`（实心）。
  证据图 `home-01-first-launch.png`：三格图标比左右两处箭头明显更"轻"。
- **现在什么样**：同一屏最多同时出现实心与线框两种笔。
- **为什么不行**：见 [[P0-1]]。同一屏内混族是最刺眼的，用户说不出为什么"看着不整齐"。
- **改成什么**：全屏统一 `MaterialSymbolsOutlined`（`FILL=0`），尺寸 20（快捷格用 24，
  因为它在"看一眼就知道去哪"的位置，`plan-ux-2026-10-10.md` §P1-5 已经定为 23pt 的字号级别 → 改 24）。

### 【P1-4】底栏在两台上是两种东西：iOS 三格完全等同，Android 中间那格大一号且永远强调色
- **位置 / 证据**：`app_tab_bar.dart:53-56` 写着 `centerIconSize = 26` / `iconsize = 22`，
  并在 Android 支路（`:175-183` 走 `_centerCell`）执行"大一号 + 永远 accent"；
  而 iOS 支路走 `NativeTabBar`（`:140-150`），`native_tab_bar.dart:14-20` 明确写着
  「**五格一视同仁** —— 原生的 `UITabBarItem` 没有'某一格更大'」，
  且 `NativeTabBarBridge.swift:116-119` 只设了 `iconColor` / `titleTextAttributes`，**没有任何尺寸差异**。
- **现在什么样**：安卓用户看到"中间那格大一号 + 橙色"，iOS 用户看到三个一模一样的灰图标
  （选中才变橙）。**"开练"这个最重要的入口在 iOS 上失去了它的视觉优先级。**
- **为什么不行**：`plan-ux-2026-10-10.md` §五-A 拍板的是「仍然居中、**仍然是强调色**」，
  这条决定在 Android 达成了、在 iOS 没有。而 SF Symbol 其实**有能力表达这件事**：
  `UIImage(systemName:withConfiguration:)` 可以给 `UIImage.SymbolConfiguration(pointSize:)`，
  iOS 侧可以给中间那一格单独一个更大的 `pointSize`。原生限制影响的是"选中态"，不是"尺寸"。
- **改成什么**：
  1. **iOS 侧给中间格更大字号的 symbol**：在 `NativeTabBarBridge.swift` 生成 items 时，
     对 `index == centerIndex` 用 `UIImage.SymbolConfiguration(pointSize: 26, weight: .medium)`；
     其余用 `pointSize: 22`。**`selectedColor` 仍然只给选中态**（不破坏系统语汇）；
  2. **在 `native_tab_bar.dart` 的 `NativeTabBarSpec` 里加一个 `centerIndex` 字段**，
     不要在 Swift 里写死 1（现在 `app_tab_bar.dart:89` 的 `_centerIndex = 1` 是 Dart 侧的私有常量，
     平台两侧各写一个"中间是第几个"迟早会漂）；
  3. 如果第 1 步在真机上被证实不稳定（SF Symbol 的 pointSize 与 UITabBarItem 的布局有已知摩擦），
     **退路**：接受 iOS 三格等同，但把 Android 的 `centerIconSize` 也改成 22 ——
     **两台设备一致 > 某一台更好看**。这一条要么两台都强调，要么两台都不强调，不允许只有一台。

### 【P1-5】字标（文字商标）从来没有被定过：三个地方三种写法
- **位置 / 证据**：
  - `share_card.dart:75-83`：「练了么」15pt / `w700` / `letterSpacing: 1` / `Tokens.accent`。
  - `privacy_consent_screen.dart:85-93`：「练了么」28pt / `w800` / **无 letterSpacing** / `Tokens.accent`。
  - `vi/splash-screen.html`：`.app-name-cn` 28pt / `w700` / **`letter-spacing: 8px`** / `--fg`（白，不是橙）；
    另有 `.app-name`（拉丁，42pt / `w700` / `letter-spacing: 2px` / Oswald / `text-transform: uppercase`）。
  - `store-assets/feature-graphic-1024x500.png`（我看了）：左侧橙环图标 + 右侧「练了么」白色大字 +
    「一次点击记一组」灰色小字 + 一条橙色短横线。这一份的**中文是白色、不是橙色**。
- **现在什么样**：中文名在四处有四种字号/字重/字距/颜色组合；拉丁名（`LIANLE.ME`，
  稿子 `vi/share-card.html` 的 `.share-badge` 里有）**在 App 里一次都没出现过**。
- **为什么不行**：字标是 VI 里最基础的资产，它的作用是"把这四个字在任意尺寸下都认出来"。
  一个没有字距规则的汉字标，在 15pt 与 28pt 下会呈现完全不同的密度，
  于是它在分享卡上和在同意页上**看起来是两个不同的品牌**。
- **改成什么**：立**字标规范**（两条，不含糊）：
  - **中文标「练了么」**：`letterSpacing: 6`（对 28pt 而言 ≈ 0.21em，取整到 6pt）、
    `fontWeight: w700`、**颜色只用 `Tokens.accent` 或 `Tokens.text` 二选一**：
    在深色无图区域用 `Tokens.accent`；在**已有大面积橙色的画面**（启动屏、完成页）用 `Tokens.text`（白）
    —— 这是唯一的颜色规则，因为它解决的是"橙上再放橙"的问题（启动屏就是橙环 + 橙字，现在是错的）。
  - **拉丁标「LIANLE.ME」**：Oswald `w600`、`letterSpacing: 2`、**全大写**、
    只用在分享卡底部与商店素材。**引入它是为了分享卡在跨语言场景下的可识别**。
  - **最小尺寸**：字标在屏幕上的最小宽度 **64pt**（当前 15pt × 3 字 ≈ 45pt 已低于这个门槛）。
    分享卡上的字标必须 ≥ 16pt（见 [[P0-10]] 第 1 条）。

### 【P1-6】`vi/onboarding.html` 的三张插画在 App 里被换成了两个 Material 图标
- **位置 / 证据**：
  - 稿子三张插画：`.illus-ring`（200pt 环 + 中心光点）+ `.illus-check`（48pt 绿圆 + 白勾，`stroke-width:3`）
    + `.illus-bolt`（40pt 实心橙闪电）；
    第二张 `.illus-calendar`（180pt 卡片 + 内部几行）；
    第三张 `trend-up`（折线 + 箭头）。
  - App（`intro_carousel_screen.dart:198-235` 的 `_TapArt`）：一个橙环（`Container` + `border`）里
    塞 `Icons.bolt` 30pt + 一个绿圆（`Color(0xFF06231A)` 勾）——
    **抄了构图，换了笔**；另两张 `_PlanArt` / `_ProgressArt` 是 `Icons` 拼的。
  - 证据图 `store-assets/screenshots/00-intro.png`：实拍就是这个"橙环里一个白闪电 + 右下角绿勾气泡"。
- **现在什么样**：这一屏是**用户见到的第一个画面**（`00-intro` 是商店第一张截图，也是冷启动后第一屏），
  它的图形是"看起来像稿子但笔不对"的版本。
- **为什么不行**：首次印象的三屏里，第一屏用的是"描边环 + 实心字体图标"的混合体，
  第二三屏更弱。`docs/plan-ux-2026-10-10.md` 全篇没提 onboarding —— 它在这次大改版里**被跳过了**。
- **改成什么**：
  1. 三张插画**按稿子重画成 `CustomPainter`**（零依赖，与 `sparkline.dart` 同一做法），
     全部 `stroke = 2.0 @ 24 网格` 等比放大，**橙色只出现在环与箭头**，
     **绿勾只出现在第一张**（"记上了"这个隐喻只该出现一次）。
  2. 第一张的环径比按 [[P0-4]] 的 0.026 修正（现在稿子写的是 0.70）。
  3. 三张的共同骨架是 `BrandMark` 的三种"长出来的样子"（环 → 环 + 日历 → 环 + 折线），
     这样 onboarding 就变成了品牌标记的展开，而不是三张无关的图。

### 【P1-7】启动屏与 App 内首帧之间没有任何过渡；`vi/splash-screen.html` 的加载点从未实现
- **位置 / 证据**：`vi/splash-screen.html` 有完整的启动页编排：
  `.splash-content` 的 `radial-gradient(ellipse at 50% 40%, rgba(255,92,38,0.12), transparent 55%)`
  橙光晕、`.icon-ring` 的 `ringPulse` 2.5s `ease-in-out` infinite、
  `.icon-ring::before` 中心点的 `dotGlow` 2.5s、
  以及底部的 `.loading-indicator`（三个 6pt 橙点，`loadDot` 1.4s 错峰 0.2s）。
  **App 里这三样一个都没有**（`grep keyframes|AnimationController` 全仓 0 命中，
  启动只有静态的 `LaunchImage`）。
- **现在什么样**：冷启动 = 一块近黑的底 + 一个白盘橙环（见 [[P0-5]]）→ 直接切到首页。
  中间没有任何"品牌在等你"的瞬间。安卓上还会因为 Flutter 首帧稍慢而**多黑一下**。
- **为什么不行**：这是最容易做、回报最直观的一段品牌动效。
  客户稿子里连"加载点跳动的节奏"都给了，实现成本是 40 行代码 +
  一张自绘的渐变背景，是整个 VI 方案里**性价比最高的一项**。
- **改成什么**：
  1. **不在原生启动图上做动画**（那是不可能也不该做的），而是在
     **Flutter 第一帧**上做一个"接管过渡"：首帧渲染 `SplashOverlay`，
     内容是稿子的三样：橙色径向光晕（`accent` 12% → 透明，`Alignment(0, -0.2)`）、
     `BrandMark.glow`（外径 0.446 × 120pt ≈ 54pt）、字标（`Tokens.text`，见 [[P1-5]]）；
  2. 时序：首帧直接显示（不做淡入，否则会有白闪）→ 数据加载完成或 **最短 600ms 后**
     整体淡出 260ms `easeOutCubic`；
  3. **加载点只在真的还在加载时出现**（`vi/splash-screen.html` 的三个点）：
     超过 400ms 未完成才显示，三个点用同一个 `AnimationController` 驱动
     （`Interval(0, .7)` / `Interval(.2, .9)` / `Interval(.4, 1.1)`），
     `Curves.easeInOut`，周期 1400ms。**不要用三个独立的 `Future.delayed`**（会漂）。
  4. **减弱动态效果下**：**不做无限脉冲**，只保留静态 `BrandMark` + 字标 + 淡出（见 §四 M-18）。

### 【P1-8】训练屏：唯一一处"记得最牢"的动效缺口是"记一组"的新行入场
- **位置 / 证据**：`workout_screen.dart` 的已完成组列表是一段普通的 `Column`/`ListView`
  （`grep AnimatedList|AnimatedSwitcher` 在该文件 **0 命中**）。
  `interaction-spec.md` §8 第一条写的是「记录一组：新行 `pop` 入场 280ms（透明度 + 上移 6pt）」。
  证据图对照：`store-assets/screenshots/06-workout-logged.png`（旧版，两组已记）
  与 `docs/images/workout-2026-10-10/workout-04-with-history.png`（新版，一组已记）。
- **现在什么样**：点大按钮 → 列表里瞬间多一行，无位移、无淡入。
  同时**主按钮上的数字不变**（规格 §6 说"立即回落，缩放反馈"，那个 0.975 的按压缩放也没有实现 ——
  `theme.dart:126` 把 `splashFactory` 设成了 `NoSplash`，而按压缩放从未写过）。
- **为什么不行**：这是**全产品调用最频繁的一次交互**（一次训练 12–24 次）。
  它现在没有任何反馈动效，用户唯一的确认来自触觉（[[P0-12]]）与那行文字。
  在"组间 60 秒、屏幕有汗、注意力在器械上"的场景里，这直接对应
  `PRODUCT.md` §5 那条硬约束「1 次点击 = 1 组」的**可信度**。
- **改成什么**：
  1. 已完成列表换成 `AnimatedList`（或给每行包一层 `SizeTransition` +
     `FadeTransition`）：新行入场 **280ms `Curves.easeOutCubic`**，
     起点 `opacity 0 → 1`、`translateY +6pt → 0`；
  2. **主按钮补按压缩放**：`GestureDetector` 的 `onTapDown/onTapUp` 驱动一个 `scale 0.975`，
     **100ms `Curves.easeOut`**（规格 §5 已定义），松手 `120ms` 回弹；
  3. **触觉与入场同拍**：`haptics.setLogged()` 与 `AnimatedList.insertItem` **在同一个
     `setState` 里、同一帧**发起（见 §五 H-01）。

### 【P1-9】休息倒计时：进度条与数字不同源，归零那一帧没有任何视觉事件
- **位置 / 证据**：`workout_screen.dart` 的休息区（`04-with-history` 证据图里那一行
  `休息 01:59 还剩 99% -15 +15 跳过` 与下面那条橙色细进度）。
  `restFinished` 的触觉在 `workout_controller.dart:834`。
  `interaction-spec.md` §6 的 `rest_done` 状态写着「变为「休息结束」，转 `--volt`；**不弹窗、不响铃、不震动提示**」
  —— **与 §8 那张表里的「训练结束 → success notification」以及 `haptics.dart` 里
  `restFinished → heavyImpact` 三处互相矛盾**。
- **现在什么样**：休息条是一个 1% 的橙点（证据图里那一小段），走到 100% 时
  数字与进度条同时停止，**没有任何"到达"的视觉**，然后手机会重震一下。
- **为什么不行**：`PRODUCT.md` §1 说这个 App 服务的唯一场景是"组间休息的 60 秒"。
  **这 60 秒的终点是整个产品最该被设计好的一帧** —— 用户此时多半在看器械或手机背面，
  他需要一个"到了"的信号，且这个信号要**视觉与触觉同时发生**。
  现在规格书自己在三处写了三种不同的行为，实现选了第三种（只有触觉）。
- **改成什么**：
  1. **进度条与数字同源**：两者都由同一个 `AnimationController(duration: restTotal)` 驱动，
     `addListener` 里同时更新百分比文字与 `FractionallySizedBox.widthFactor`。
     现在的做法（数字来自控制器、进度来自另一个计算）必然会漂。
  2. **归零那一帧做三件事，同一帧**：
     进度条**颜色从 `accent` 切到 `success`**（180ms `easeOut`）、
     数字**从 00:00 弹一下**（`scale 1.0 → 1.08 → 1.0`，220ms）、
     `haptics.restFinished()`。**三件事共用一个帧回调**，不许用 `Future.delayed` 串。
  3. **最后 3 秒加一次预告触觉**（`selectionClick`，在 `plan-ux-2026-10-10.md` §四第 2 条里
     标着"待定"）—— 我建议**做**，但只给一次、用最轻的一档，且必须与视觉上的
     数字变色（`text2 → text`）同帧。理由是"注意力在器械上"的场景里，
     一次轻预告的收益大于它能造成的噪音。

### 【P1-10】记一组之后没有任何"完成了多少"的视觉累积；`ViProgressBar` 是全仓唯一的进度语言却没有动效
- **位置 / 证据**：`vi_cards.dart:272-303` 的 `ViProgressBar`：
  一个 `ClipRRect` + `Stack` + `FractionallySizedBox(widthFactor: v)`。
  **没有任何动画**（改 `value` 就是瞬变）。它被用在成就页（收集进度、4 条收集线、周挑战）
  与「我」页（等级进度）。
- **现在什么样**：用户解锁一枚徽章、完成一次周挑战，那条进度条**跳**过去。
  这跟"完成"这件事的情绪完全不匹配。
- **为什么不行**：进度条是这个 App 唯一的"量化进展"语言，它出现在 6 个地方。
  一条跳变的进度条会让用户怀疑"是不是刷新了"。
- **改成什么**：给 `ViProgressBar` 加一个可选 `animate: bool = true`，
  内部用 `TweenAnimationBuilder<double>`（**这是 Flutter 自带的隐式动画，不需要
  `AnimationController`，且天然支持 `duration: Duration.zero` 降级**）：
  时长 **420ms `Curves.easeOutCubic`**；`reducedMotion` 为真时传 `Duration.zero`。
  **所有调用点默认就是动画的** —— 一处改、六处受益，这是这个组件层存在的意义。

### 【P1-11】底栏图标在两台上语义不对齐，且 iOS 的 SF Symbol 与 Material 的"配对表"是隐式的
- **位置 / 证据**：`app_tab_bar.dart:81-99`：
  `tabs[0] = (Icons.show_chart, '进步')` 对 `_sfSymbols[0] = 'chart.line.uptrend.xyaxis'`；
  `tabs[1] = (Icons.fitness_center, '开练')` 对 `_sfSymbols[1] = 'dumbbell.fill'`；
  `tabs[2] = (Icons.person_outline, '我')` 对 `_sfSymbols[2] = 'person'`。
- **现在什么样**：三对里有两对**形状不一致**：
  `show_chart`（折线 + 一根竖线）与 `chart.line.uptrend.xyaxis`（折线 + 双坐标轴）；
  `person_outline`（**线框**）与 `person`（**实心**）；
  `fitness_center`（哑铃，横放）与 `dumbbell.fill`（哑铃，**带斜杠配重块、更细长**）。
  证据图 `v166-native-tabbar-iphone-2.png`（iOS）与 `p02-3tab`（Android）对比看：
  同一个"进步"，一台是折线带箭头、一台是柱状图似的折线。
- **为什么不行**：底栏是全 App 出现频率最高的图形（每一屏都在）。
  两台上形状不同 = 用户在两台设备上学的不是同一套符号。这是 VI 一致性的底线。
- **改成什么**：
  1. 建一张**平台配对表**（写进 `icon_spec.dart`（**待新建**，放 `app/lib/core/`） 的注释里，不另建文档）：
     每一格同时给 `IconData`（Material Symbols 名）与 `String`（SF Symbol 名），
     **配对判据是"外轮廓一致"，不是"意思一样"**。
     按这条重挑：进步 → `trending_up` / `chart.line.uptrend.xyaxis`（已有，形状更接近）；
     开练 → `exercise` / `figure.strengthtraining.traditional`（SF 侧换成更接近哑铃横放的）；
     我 → `person` / `person`（**Material 侧从 `person_outline` 改成 `person`**，两台都实心）。
  2. **配对表必须有测试**：一条纯 Dart 测试核对两个列表长度相等、
     且每个 SF Symbol 字符串在 `icon_spec.dart` 里被显式列出（防"加了一格忘加另一格"）。
     现在这两个列表是**两个独立的常量数组**（`tabs` 与 `_sfSymbols`），
     长度不同会直接崩、但语义错位**没有任何东西会发现**。

### 【P1-12】权重单位那个符号：图形与文案是分开的两半，且图形本身是"私有 Unicode 字形"
- **位置 / 证据**：`exercise_picker_screen.dart` 每行右侧有一个重量符号 + "40 kg 总重（含杠铃杆）"/
  "5 kg 单只"/"自重"（证据图 `p1-01-picker.png` 里那个像 `Ɣ` 的符号）；
  文案的判据在 `labels.dart:146-160`（`'barbell' => '总重（含杠铃杆）'`、`'dumbbell' || 'kettlebell' => '单只'`）。
- **现在什么样**：`labels.dart` 的判据设计得很好（有证据、有口径、明确了"没有乘 2"），
  但**图形侧是一枚孤立的花体字形**，它与"总重/单只"这个口径**没有任何视觉关联**，
  而且在 13pt 下是一个难以辨认的小符号（`p1-01-picker.png` 里它看起来像乱码）。
- **为什么不行**：`copy.md` 收录了这条文案作为"判据"类（第 3 条），说明它是重要的；
  一个重要的判据配一个不可辨认的符号，等于把判据藏起来。
- **改成什么**：把那个符号换成 [[P0-1]] 规范里的**两枚明确图形**：
  `weight`（杠铃，表示总重）与 `dumbbell`（哑铃，表示单只），
  **尺寸 16、颜色 `Tokens.text3`**，紧跟其后的文案保持 `labels.dart` 的原文不变。
  图形与文案的距离固定 `Tokens.s2`。

---

### 【P2-1】`vi/*.html` 自身的图标线宽就有 5 个值，稿子这一层需要一次清洗
- **位置 / 证据**：逐文件 `stroke-width` 去重：
  `progress-home` → **1.5 / 1.8 / 2 / 3（4 个值）**；
  `body-tracking` / `onboarding` / `rest-timer` / `training-plan` / `complete-library` / `auth-setup`
  → **2 / 2.5 / 3** 中的 2–3 个；`tab-icon-system` → **全 1.8**；`achievement-badges` 与
  `notifications-settings` → **全 2**（这两张最干净）。
- **现在什么样**：稿子自己是混的。`progress-home` 一张稿里 4 个线宽。
- **为什么不行**：VI 交付物里最重要的一条是"下一个照做的人不会做错"。
  稿子混着，App 就一定会混（`app/lib` 现在 112 个字形、12 个尺寸，正是这件事的下游）。
- **改成什么**：**以 2.0 @ 24 网格为唯一线宽**（因为 `achievement-badges` 与 `notifications-settings`
  这两张最完整的稿是全 2.0），把 `vi/*.html` 里 1.5 / 1.8 / 2.5 / 3 **全部改成 2.0**，
  只有两种例外：**主按钮里压在大色块上的勾用 2.5**、**120pt 以上的大插画用 3.0**
  （大尺寸下线宽要等比放大才不失重）。

### 【P2-2】`store-assets/screenshots/` 是 5 tab 旧版（2026-10-08/09），与 10.10 已落地的 3 tab 不符
- **位置 / 证据**：文件时间戳：`store-assets/screenshots/01-home.png` = **2026-10-08 23:27**、
  `screenshots-ios/01-home.png` = **2026-10-09 02:39**、`screenshots-play/01-home.png` = **2026-10-08 23:28**。
  而我打开 `store-assets/screenshots/01-home.png` 看到的是**五格底栏**
  （`v166-native-tabbar-iphone-2.png` 同样五格），
  而 `docs/images/p02-3tab-2026-10-10/home-01-first-launch.png` 与 `home-2026-10-10/` 是三格。
  两者 md5 不同、日期差两天。
- **现在什么样**：三套商店截图（`screenshots` / `screenshots-ios` / `screenshots-play`）
  全是旧版 IA。而 `docs/plan-ux-2026-10-10.md` §P0-2 已经标 ✅ 落地。
- **为什么不行**：商店素材是**对外唯一一份"这套 VI 长什么样"的正式说明**。
  它现在展示的是一个已经不存在的底栏结构，且会误导任何看这份素材做评审的人
  （我第一轮就被它误导，以为 `p01-02-profile.png` 里那个玻璃叠影是当前状态，
  实际它是五格时代的残留样例）。
- **改成什么**：切版（v1.67.0）前**重出三套商店截图**，并把这些当作验收前置项：
  截图必须体现 ① 三格底栏 ② 完成页新解锁横条 ③ 分享卡两款版式 ④ 成就册（缩略图那张）。
  这条与 `tool/check-screenshots.mjs` 有关系，值得把"截图里的底栏格数"做成一条可核对的判据。

### 【P2-3】品牌标记与字标没有任何"尺寸下限"：最小的那一处是分享卡上 15pt 的橙字
- **位置 / 证据**：字标出现的两处：分享卡 15pt（`share_card.dart:79`）、同意页 28pt
  （`privacy_consent_screen.dart:88`）。圆环标记在 App 内**不出现**；在启动图上是 42.7pt。
- **现在什么样**：没有"最小可用尺寸"这条规则，于是分享卡（最重要的对外输出）
  用了全产品最小的字标。
- **为什么不行**：品牌资产必须给"最小尺寸"，否则它一定会在最需要它的地方被缩到看不见。
- **改成什么**：写进规范：**字标最小宽度 64pt**（≈16pt 字号 × 3 字 + 字距）、
  **圆环标记最小 16pt**（低于此只保留环带、去掉中心点与辉光 —— 与 macOS/iOS 的小尺寸图标
  同一套做法）、**两者同时出现时最小间距 `Tokens.s3`**。

### 【P2-4】`store-assets/feature-graphic-1024x500.png` 与 App 内的品牌呈现不一致
- **位置 / 证据**：我看过这张图（1024×500）：左侧 `BrandMark`（带辉光）+ 右侧「练了么」
  **白色大字** + 「一次点击记一组」灰字 + **一条橙色短横线**（作为装饰）。App 内的字标是橙色。
- **现在什么样**：商店主图用白字 + 橙短线；App 内用橙字。两处是两套。
- **为什么不行**：商店主图是用户第一次看到这个品牌的地方，它与 App 内不一致 = 用户在
  "点击安装"到"打开 App"之间会经历一次品牌断层。
- **改成什么**：按 [[P1-5]] 的字标规范统一（橙底场景用白、深底场景用橙），
  并把装饰性那条橙短线**升格成一个资产**：它是目前唯一一个"非圆环"的品牌图形元素，
  可以在分享卡底部与空态里复用（我把它写进 §三 品牌资产清单的 `brand rule` 一项）。
  商店主图那一版是"深底 → 应该用橙色字标"，所以**主图要改字色**。

### 【P2-5】`Colors.transparent` 弹层里还有一处 `Tokens.elevated` 覆写，玻璃会被盖住
- **位置 / 证据**：`glass_overlay.dart:45-49` 的文件头注释明确写着：
  「⚠️ 弹层内部**不要再写 `backgroundColor: Tokens.surface`**……这会盖住玻璃」。
  而 `share_card_preview_screen.dart:123` 的存相册授权弹层写的是
  `AlertDialog(backgroundColor: Tokens.elevated, ...)` ——
  **这是同一个文件里唯一一处覆写**（`showAppDialog` 已经把 `dialogTheme.backgroundColor`
  设成透明，再写 `Tokens.elevated` 就等于把它盖回去）。
- **现在什么样**：iOS 26 上这个弹层不是玻璃，是一个实心 `#24201C` 方块，
  与同屏其他弹层（玻璃）不一致。这个弹层出现频率低，但它是隐私授权说明 —— **最该显得"正规"的那一个**。
- **为什么不行**：`glass_overlay.dart` 建立公共入口的目的就是"避免有的弹层是玻璃、有的不是"，
  而这里恰好漏了一个。注释里说"要留就留"，但没说不许留 —— 所以这不是 bug，是**规范的漏洞**。
- **改成什么**：删掉这一处的 `backgroundColor`；并在 `glass_overlay.dart` 文件头把那条
  "少数地方为了非 iOS 兜底留着也行"改成**硬约束**：
  「弹层内部一律不写 `backgroundColor`；非 iOS 需要的底色由 `showAppDialog` 在非 iOS 分支里统一补」。

### 【P2-6】成果资产的"证据图"命名与内容不同步，导致复核者会看到过期状态
- **位置 / 证据**：`docs/images/` 下同时存在五格时代（`v166-native-tabbar-iphone-2.png`、
  `v166-native-segmented-iphone.png`、`store-assets/screenshots/*`）与三格时代
  （`p02-3tab-2026-10-10/`、`home-2026-10-10/`）的证据图，**文件名里没有一处标明"这是旧 IA"**。
  我按任务要求看了 `v166-native-tabbar-iphone-2.png` 与 `v166-native-segmented-iphone.png`，
  两张都是五格；而同一天的 `p01-02-profile.png` 是三格 —— 同一天的两张图两种 IA。
- **现在什么样**：证据图目录靠文件名与时间戳区分，没有"已过期"标记。
- **为什么不行**：这个仓库的纪律是"证据图是唯一能验 iOS 分支的东西"（`glass_surface.dart` 文件头）。
  证据图一旦过期且无标记，它就从"证据"变成"误导"，比没有更坏。
- **改成什么**：`docs/images/` 里凡是**旧 IA（5 tab）**的图，文件名统一加 `legacy-` 前缀
  （或移进 `docs/images/legacy-5tab/`），并在 `docs/images/README` 或
  `docs/screenshots.md` 里写一行"这一批是 5 格时代的证据，只用于追溯，不是当前状态"。

---

## 三、VI 方案（图形 · 品牌 · 动效）

### 3.1 图标规范

**唯一真源**：`app/assets/fonts/MaterialSymbolsOutlined[FILL,GRAD,opsz,wght].ttf`（随包，不加 pub 依赖），
在 `pubspec.yaml` 的 `fonts:` 里注册为 `MaterialSymbols`，
并在 `icon_spec.dart`（**待新建**，放 `app/lib/core/`） 里提供 `IconData` 常量（`fontFamily: 'MaterialSymbols'`）。

**四条硬规则**：

1. **族**：只用 `MaterialSymbolsOutlined`。`FILL` 轴两个值：
   `0`（默认，占 95%）、`1`（仅"选中态"与"已解锁"两类语义）。**Rounded / Sharp / Two-tone 清零。**
2. **线宽**：`wght = 400`（= 24 网格上 2.0pt）；唯一例外：训练屏主按钮内的勾 `wght = 500`。
   渲染尺寸与线宽的关系写死：`视觉线宽 = 尺寸 ÷ 12`。
3. **尺寸只 4 档**：`inline 16` / `control 20` / `tab 24` / `hero 40`。
   **删除** 11、14、15、18、19、22、23、26、30、42 这 10 个值。
   徽章另有三档（见 3.5），不属于"界面图标"这一组。
4. **颜色只 3 档**：`text2`（默认，功能性图标）/ `text3`（装饰性、非关键）/
   `accent`（一屏只允许一处 —— 与 `interaction-spec.md` §4 第二条硬约束同源）。
   **不允许**图标用 `success` / `pr` / `danger` / `tierRare`，唯一例外是
   "破纪录"用 `pr`、"删除"用 `danger`（语义绑定，一屏各一次）。

**语义映射表**（13 组，每组一个规范图形 + 全部同义场景 + 两台配对）：

- **今天 / 开练** — Material `exercise` / SF `dumbbell.fill` — 用于：底栏中格、首页主卡、训练屏标题
- **进步** — Material `trending_up` / SF `chart.line.uptrend.xyaxis` — 用于：底栏左格、进步页标题、容量趋势
- **我** — Material `person` / SF `person` — 用于：底栏右格、「我」页标题
- **连续打卡 / 坚持** — Material `local_fire_department` / SF `flame` — 用于：连续天数（唯一含义）、
  "连续打卡"这条收集线、分享卡的连续天数
- **力量 / 容量** — Material `fitness_center` / SF `dumbbell` — 用于："力量突破"收集线、容量相关
- **里程碑 / 记录** — Material `emoji_events` / SF `trophy` — 用于："里程碑"收集线、成就
- **探索 / 发现** — Material `explore` / SF `safari` — 用于："探索发现"收集线、动作库
- **破纪录** — Material `trophy` / SF `trophy.fill` — 用于：完成页 PR 浮层、分享卡 PR 行
  （**当前缺失，必须新建**）
- **换（任何"给我别的"）** — Material `refresh` / SF `arrow.clockwise` — 用于：换一批、换动作、
  换建议、换模板。`swap_horiz` 只保留"左右对调"，`shuffle` 只保留"随机"
- **上一个 / 下一个** — Material `chevron_left` / `chevron_right` / SF `chevron.left` / `chevron.right`
  — 全站唯一的方向语言
- **更多 / 进入** — Material `chevron_right` / SF `chevron.right` — 列表行尾
- **休息 / 计时** — Material `timer` / SF `timer` — 休息条、计时动作
- **消息 / 设置** — Material `notifications` / `settings` — 顶栏两枚动作（40×40 触区不变）
- **重量单位** — Material `weight`（总重）/ `dumbbell`（单只），尺寸 16，
  紧跟 `labels.dart` 的现有文案
- **搜索 / 空结果** — Material `search` / `search_off` — 动作库搜索

### 3.2 品牌资产清单（要做的东西，逐项可交付）

- **`BrandMark`**（圆环标记）—— 新建 `brand_mark.dart`（**待新建**，放 `app/lib/core/`），`CustomPaint` 零依赖。
  几何写死：**外径 : 环带厚 : 洞径 = 1 : 0.39 : 0.026**；画布边长 `S` 时外径 = `0.446 × S`。
  两个变体 `flat`（默认）/ `glow`（仅启动屏与完成页）。
  **这是整套 VI 的第一优先级资产** —— 它一落地，启动页、分享卡、空态、完成页四件事同时有解。
- **字标** —— 中文「练了么」`letterSpacing 6` / `w700` / 深底橙字 or 橙底白字；
  拉丁「LIANLE.ME」Oswald `w600` / `letterSpacing 2` / 全大写。
  最小宽度 64pt。落地成一个 `BrandWordmark({bool latin = false})` 组件（内联样式即可，不必新文件）。
- **启动过渡** —— `splash_overlay.dart`（**待新建**，放 `app/lib/features/onboarding/`）：橙色径向光晕 +
  `BrandMark.glow` + 字标 + 三加载点（>400ms 才出现）。时序见 §四 M-17 / M-18。
- **完成动画** —— 见 §四 M-08 的 1400ms 编排 + `PrBadge` 组件 + 自绘描边勾
  `check_painter.dart`（**待新建**，放 `app/lib/core/`）（`PathMetric` 驱动的"画出来"）。
- **空态图形语言** —— `EmptyState` 组件 + 5 个派生艺术字（`dashedRing` / `halfRing` /
  `ringWithPlus` / `ringWithLock` / `ringSearch`），全部由 `BrandMark` 几何派生，
  渲染 120pt，中心点用 `accent`。见 [[P0-8]]。
- **徽章系统** —— `BadgeMedallion` 公共渲染器（三档尺寸 38/48/64）+ 稀有度的三重非颜色通道
  （内芯描边 0/1/2pt + 外形档：正圆 / 4 段断弧 / 全环 + 尖角）。见 [[P0-6]] [[P0-7]]。
- **分享卡模板** —— `BrandMark.flat` 28pt + 字标 16pt + 前三行动作明细 + 主数字 34pt /
  副数字 20pt + 底部 `BrandMark` + 「分享自练了么」。尺寸 360 × **520**（导出 1080 × 1560）。见 [[P0-10]]。
- **`brand rule`**（橙色短横线）—— 从商店主图里提炼：一条 `accent` 色、宽 `56pt`、高 `3pt`、
  圆头的横线。用于：字标下方、空态下方、分享卡底部。**它是唯一一个非环形的品牌元素**，
  作用是在环不能用的地方（横版构图）仍然有品牌感。
- **商店素材** —— 三套截图重出；主图字标改橙色（见 [[P2-4]]）。

### 3.3 动效清单（18 条）

> 全部时长/曲线从 `motion.dart`（**待新建**，放 `app/lib/core/`） 取值：
> `Motion.instant = 100ms` / `fast = 180ms` / `base = 260ms` / `slow = 400ms` / `long = 600ms`；
> `Motion.standard = Curves.easeOutCubic` / `enter = Curves.easeOut` / `exit = Curves.easeIn` /
> `spring = Curves.easeOutBack`（**只用于"到达"类，不用于"出现"类**）。
> **每一条的 `duration` 都必须经过 `reducedMotion(context)` 短路**（见 M-18）。

- **M-01 记录一组（新行入场）** — 触发：写入成功 | 280ms | `standard` | 降级：瞬时出现。
  同时发起 H-01。
- **M-02 主按钮按压** — 触发：`onTapDown` / `onTapUp` | 100ms 下压、120ms 回弹 |
  `enter` / `spring` | 降级：无缩放（但保留 H-01 触觉）。
- **M-03 底部弹层入场** — 触发：`showAppSheet` | 260ms `translateY(102% → 0)` | `standard` |
  降级：瞬时（规格 §5 已有此条，**这是唯一一条已被规格定义却未实现的**，照规格做）。
- **M-04 弹层遮罩** — 触发：同上 | 同 260ms | `standard` | 降级：瞬时。
- **M-05 步进调整** — 触发：±按钮 | **无动效，数字直变** | — | 降级：无变化
  （规格 §8 已定义，保持）。
- **M-06 破纪录出现** — 触发：`prs.isNotEmpty` | 400ms 放大 `0.92 → 1.0` + 淡入 |
  `spring` | 降级：直接显示。停留 3000ms 后 300ms 淡出。
- **M-07 训练结束数字滚动** — 触发：完成页首帧 | 600ms 数字从 0 滚到终值 |
  `standard`（Oswald 可变字体，用 `TweenAnimationBuilder<int>` 即可）| 降级：直接显示终值。
- **M-08 完成页编排（总额 1400ms）** — 触发：完成页首帧 | 勾"画出" 420ms → 标题上浮 240ms
  （延迟 300ms）→ 三格数字滚动 600ms（延迟 420ms）→ 新解锁横条推入 320ms（延迟 900ms）→
  完成按钮 `accent` 渐显 260ms（延迟 1100ms）| `standard` | 降级：全部瞬时，但**保留 H-04 触觉与
  勾的最终状态**（减弱动态效果不等于失去"完成"的确认）。
- **M-09 徽章解锁（收藏册内）** — 触发：进入收藏册时首次可见 | 外圈环形进度从 0 画到
  `progress`，600ms | `standard` | 降级：直接画满。
- **M-10 进度条变化（`ViProgressBar`）** — 触发：`value` 变化 | 420ms |
  `standard` | 降级：`Duration.zero`（见 [[P1-10]]）。
- **M-11 Tab 切换** — 触发：点底栏 | `260 + 90 × |i − from|` ms（保持现值）| `standard` |
  降级：瞬时。**iOS 与 Android 都要跑这一条**（删掉 `_selectTab` 里的平台早返回）。
- **M-12 页面推入** — 触发：`Navigator.push`（38 处）| 300ms `easeOutCubic` 位移 +
  淡入（`SlideTransition` 从 `Offset(0, 0.04)`）| `standard` | 降级：瞬时。
  落地方式：在 `buildAppTheme()` 里设 `pageTransitionsTheme`，
  给两端各指定一个 `PageTransitionsBuilder`（**一处改，38 处受益**）。
- **M-13 休息进度条** — 触发：休息开始 | 由同一个控制器驱动（总时长 = `restTotalSec`）|
  线性 | 降级：`Duration.zero`（数字仍走真实时间）。
- **M-14 休息归零** — 触发：倒计时到 0 | 进度条 `accent → success` 180ms + 数字弹一下 220ms |
  `standard` / `spring` | 降级：瞬时变色。**与 H-03 同帧**。
- **M-15 通知未读点** — 触发：有新未读 | 180ms 缩放出现 | `spring` | 降级：瞬时。
- **M-16 底栏 iOS 玻璃** — 由原生 `UITabBar` 负责，**Dart 侧不干预**（保持现有边界）。
- **M-17 启动过渡** — 触发：Flutter 首帧 | 光晕 + `BrandMark.glow` + 字标**直接显示**
  （不做淡入，避免白闪）；数据就绪后整体淡出 260ms | `standard` | 降级：只保留淡出。
- **M-18 减弱动态效果（全局降级）** — 触发：`MediaQuery.disableAnimationsOf(context) == true` |
  所有 `Motion.*` 返回 `Duration.zero`；**三条例外保留**：
  ① M-08 的勾的**最终状态**（它是信息，不是装饰）；
  ② M-17 的**淡出**（否则会有跳帧感）；
  ③ M-14 的**颜色切换**（同样瞬时完成，只是不做位移与缩放）。
  落地：`reduced_motion.dart`（**待新建**，放 `app/lib/core/`） + 一条"守卫"测试，扫 `app/lib` 里
  所有 `duration:` 参数是否都来自 `Motion.*`（与 `tool/check-user-text.mjs` 同一思路）。

### 3.4 触觉清单（12 条）

> 全部走 Flutter 自带的 `HapticFeedback`（**不引入第三方包**）。四档强度：
> `selectionClick`（最轻，可用作"经过"）/ `lightImpact` / `mediumImpact` / `heavyImpact`。
> **每条必须与一个视觉状态变更同帧发起**（不许 `Future.delayed` 串）。

- **H-01 记录一组** — `mediumImpact` — 与 M-01 新行入场同帧。
  **注意**：规格 §8 写的是 `light`，实现是 `medium`。我判**保留 `medium`**：
  健身房里手机多半在器械上，`light` 会被环境震动吃掉；但这意味着规格书要改（见 §四 冲突 1）。
- **H-02 休息结束** — `heavyImpact` — 与 M-14 同帧。
- **H-03 休息最后 3 秒预告** — `selectionClick` — 与数字变色同帧。**新增**（`plan-ux` 里标着待定，我判"做"）。
- **H-04 训练完成** — `heavyImpact` — 与 M-08 的勾画完那一刻同帧。**新增，必需**。
- **H-05 破纪录** — `mediumImpact` **两次，间隔 160ms**（用 `AnimationController` 的两个
  时间点驱动，不用 `Future.delayed`）— 与 M-06 同帧。**新增**。
- **H-06 徽章解锁** — `lightImpact` 两次，间隔 120ms — 与 M-09 同帧。**新增**。
- **H-07 记时动作到达目标** — `lightImpact` 两次，间隔 120ms — 保持现状
  （`haptics.dart:60-66` 的语义是对的，只把实现从 `Future.delayed` 换到控制器时间点）。
- **H-08 弹层打开** — `selectionClick` — 与 M-03 同帧。**新增**（规格 §8 已定义，未实现）。
- **H-09 步进调整**（重量/次数 ±） — `selectionClick` — 每次步进一次。**新增**（规格 §8 已定义）。
- **H-10 长按进入编辑** — `mediumImpact`（一次，在 500ms 阈值触发那一刻）— **新增**。
  理由是"长按成功"必须被确认，否则用户会怀疑自己按到了没有。
- **H-11 撤销一组** — `lightImpact` — **新增**。
- **H-12 Tab 切换** — **无触觉**（有意）。理由：底栏是最高频动作之一，
  每次切换都震会让触觉通道迅速钝化，而这条通道的前三个用途（H-01/H-02/H-04）比它重要得多。

---

## 四、与现有规范的冲突（推翻哪一条、为什么）

1. **推翻 `interaction-spec.md` §8「记录一组 → `light impact`」** → 改用 `mediumImpact`。
   理由：本产品的唯一场景是健身房（`PRODUCT.md` §1），手机在器械上、环境有震动与噪音，
   `light` 在生产环境里会被淹没。H-01 是"不用看屏幕的确认"这条设计意图的**唯一承载**，
   它必须能被感知。**代价**：整条触觉音量上升一档，所以 H-12（Tab 切换不震）与
   H-11（撤销只用最轻）必须同时执行，否则通道会钝。

2. **推翻 `interaction-spec.md` §6「`rest_done`：不弹窗、不响铃、**不震动提示**」** → 休息归零必须给触觉。
   理由：同一份规格的 §8 那张表里写着「训练结束 → `success notification`」，
   而 `haptics.dart` 的实现是 `restFinished → heavyImpact` —— **三处三种说法**。
   我判**实现是对的、§6 那句话是错的**：`PRODUCT.md` §1 说这个 App 服务的唯一场景是
   "组间休息的 60 秒"，用户此时注意力在器械上，**触觉是唯一的时钟**。
   建议把 §6 那一格改成「变为「休息结束」，转 `--success`；触觉一次 `heavyImpact`，不弹窗、不响铃」。

3. **推翻 `docs/screens.md` §S16 第三条纪律「未解锁的照样显示，并写出「还差 N」」** →
   改为"未解锁只显示锁与灰名、不写数字"。
   理由：这条纪律与 `plan-ux-2026-10-10.md` §五-B 第 3 条（用户已拍板）**直接冲突**，
   而后者更新（10.10 vs 10.05）且是用户决定。69 条"还差 N"就是用户明确否掉的"待办清单"。
   `screens.md` S16 那份 ASCII 线框图里画的 `还差 3` / `还差 6` 也要一起改。

4. **推翻 `docs/screens.md` §S16 第二条纪律「三档稀有度各有颜色……但那是**第二重**信息」**
   的执行方式 → 颜色只出现在内芯，环形弧线走中性灰。
   理由：现在的实现让未解锁徽章的弧线与已解锁同色，于是"拿没拿到"这个二值信息
   **被颜色与弧长两条通道一起覆盖**，反而读不出来。纪律本身是对的，执行错了。
   另外补上第三种非颜色通道（内芯描边档 + 外形档）—— 三档稀有度**当前完全靠颜色**，
   违反 §4 第二条硬约束（"任何状态都不能只靠颜色表达"）。

5. **修正 `docs/interaction-spec.md` §12 验收清单那条「`prefers-reduced-motion` 下无动效残留」** →
   它现在是一条**不可执行**的判据（全仓 0 处 `disableAnimations`）。
   改成两条可执行判据：
   ① `reduced_motion.dart`（**待新建**，放 `app/lib/core/`） 存在，且 `app/lib` 里所有 `duration:` 参数都来自 `Motion.*`；
   ② 系统开启"减弱动态效果"后，M-01 / M-03 / M-06 / M-07 / M-08 / M-10 / M-12 全部瞬时完成，
   而 M-08 的勾、M-17 的淡出、M-14 的变色**仍然发生**（降级不等于丢信息）。

6. **修正 `docs/plan-ux-2026-10-10.md` §五-B 第 4 条的一个未完成项**：
   该条要求"未解锁的勋章只显示锁与灰名"，但同节的"要新做的只有：收藏册那一页（分组网格 +
   最近解锁）"是**低估**——按本文 [[P0-7]]，还要做的是：删掉 69 条"还差 N"、
   收敛一屏 6 根进度条到 1 根、改掉三档稀有度的颜色执行。这三件事同属该节的目标，
   应当补进那份文档的待办。

7. **修正 `workout_summary_screen.dart:515` 的注释**（代码内，不是文档）：
   「收藏册里是同一套，见 `achievements_screen.dart`」**是假的** —— 完成页按 category 给 4 个图标、
   收藏册按 id 给 73 个。按本文 [[P0-6]] 改成共用一个 `BadgeMedallion` 渲染器，注释随之删除。
   这一条与 `theme.dart` 把 `volt` 改名成 `accent` 是同一条纪律：**名字/注释不许说假话**。

8. **`interaction-spec.md` §11 反模式清单第 6 条「用红色表示"未完成"（红色在本产品中专用于删除）」**
   在徽章那一屏被违反了：`badges.dart:818-823` 把 `Tokens.danger` 用作"探索发现"收集线的**颜色**。
   代码注释自己也承认了（"它是唯一一个还没被别的语义占用的语义色"）——
   这是**用"没被占用"当作理由**，而那条反模式的判据是"红色的意思只许有一个"。
   建议：探索线改用**青色系**（新增一个 `Tokens.tierExplore = #38BDF8`，只用于这一条线，
   在 `bg` 上约 7.5:1），把红色还给删除。

---

## 五、落地成本与优先级（按"用户能感知到"排序）

> 排序判据不是工时，是**用户能不能立刻看见**。同一档内按"改动面 ÷ 收益"排。

**第一档 —— 一个版本内必须做完（用户当天就能看见）**

1. **完成那一刻的编排（M-08 + H-04 + PrBadge + 自绘勾 + BrandMark.glow）** ——
   产品第二个锚点，最容易做出"值得截图"的一屏。改动面集中在一个文件 + 两个新组件，风险低。
2. **`BrandMark` 组件 + 启动过渡（M-17 / M-18）** —— 一个 40 行的 `CustomPaint` +
   一个 overlay，把品牌标记第一次带进 App 内部（现在它在 App 里完全不存在）。一次投入，四处复用。
3. **`EmptyState` + 5 个空态图形 + 先改 6 处文案/按钮** —— 16 处空态里 11 处只有"陈述没东西"。
   加一个按钮 + 一个图形，是这个 App 里"从丑到像产品"最快的一步。
4. **分享卡改版（`BrandMark` + 字标 + 动作明细 + 主次数字）** —— 唯一的对外输出，
   直接影响获客。改动面在 `share_card.dart` 一个文件内。
5. **图标系统落地（`MaterialSymbols` 字体 + `icon_spec.dart` + 4 档尺寸 + 13 组映射）** ——
   改动面最大（166 处），但可以**分屏推进**：先做底栏 + 顶栏 + 训练屏 + 完成页这四个高频面，
   其余随版本迭代。**这条决定"看着像不像一个品牌"，但它不是第一批可感知的改动** ——
   所以排在第一档最后。

**第二档 —— 下一个版本（细节敏感的用户能看出来）**

6. **动效基础设施（`motion.dart` + `reduced_motion.dart` + `pageTransitionsTheme` + Android tab 动效）** ——
   基础设施先行，然后 M-01 / M-02 / M-03 / M-10 四条高频动效立刻生效。
7. **触觉补齐（H-03 / H-04 / H-05 / H-06 / H-08 / H-09 / H-10 / H-11）** ——
   前提是先把"触觉与视觉同帧"这条纪律落成代码结构（见 [[P0-12]] 第 1 条）。
8. **徽章收藏册收敛（删 69 条"还差 N" + 一屏 1 根进度条 + 稀有度三重通道 + `BadgeMedallion` 统一）** ——
   这一屏现在信息过载，是"看截图就觉得乱"的典型。
9. **休息归零那一帧（M-14 + H-03）** —— 改动小、场景核心（`PRODUCT.md` §1 就这一个场景）。

**第三档 —— 收尾与资产治理**

10. **`vi/*.html` 线宽清洗（全部 2.0 @ 24 网格）** —— 客户资产的最后一次修正，防止下一轮又漂。
11. **三套商店截图重出 + 主图字色统一 + `docs/images/` 旧 IA 加 `legacy-` 前缀** ——
    资产治理，不做的话下一轮复核还会被误导（我自己就被误导了一轮）。
12. **onboarding 三张插画重画（`CustomPainter`）+ 字标规范落地** ——
    首次印象，但只影响新用户，优先级低于上面各项。

---

## 附：本文用到的可复现命令

```bash
# 图标用量与族分布
grep -ro "Icons\.[a-z_0-9]*" app/lib | wc -l
grep -ro "Icons\.[a-z_0-9]*" app/lib | sed 's/.*Icons\.//' | sort -u | wc -l
grep -ro "Icons\.[a-z_0-9]*" app/lib | sed 's/.*Icons\.//' | awk '{if (/_outlined$/) o++; else if (/_rounded$/) r++; else if (/_filled$/) f++; else p++} END {print p, o, r, f}'

# 图标尺寸档
grep -rn -A3 "Icon(" app/lib | grep -o "size: *[0-9.]*" | sort | uniq -c | sort -rn

# 动效事实
grep -rn "AnimationController\|Tween\|TickerProvider\|AnimatedBuilder\|AnimatedSwitcher\|AnimatedList" app/lib | wc -l
grep -rn "Curves\." app/lib
grep -rn "Duration(milliseconds" app/lib
grep -rn "disableAnimations\|accessibleNavigation" app/lib app/ios app/android

# 触觉
grep -rn "HapticFeedback" app/lib

# 稿子的线宽
for f in vi/*.html; do echo "$f: $(grep -o 'stroke-width: *[0-9.]*' $f | sort -u | tr '\n' ' ')"; done

# 证据图新旧
md5 -q store-assets/screenshots/01-home.png docs/images/p02-3tab-2026-10-10/home-01-first-launch.png
stat -f '%Sm %N' -t '%Y-%m-%d %H:%M' store-assets/screenshots/01-home.png docs/images/p02-3tab-2026-10-10/home-01-first-launch.png
```

**环径比与洞色的量法**（我用的是逐点采样 + 中线扫描，脚本见下）：

```bash
python3 - <<'PY'
from PIL import Image
p='app/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png'
im=Image.open(p).convert('RGBA'); w,h=im.size; px=im.load(); row=h//2
runs=[]; cur=None
for x in range(w):
    r,g,b,a=px[x,row]
    orange = a>40 and r>140 and r-b>50
    if orange and cur is None: cur=x
    if not orange and cur is not None: runs.append((cur,x-1)); cur=None
print(im.size, runs)
print('中心像素（洞的颜色）', im.getpixel((w//2,h//2)))
PY
```
