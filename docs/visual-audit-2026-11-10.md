# 练了么 · v2.1.0 深度视觉审计（2026-11-10）

> **输入**：`store-assets/screenshots/`（16 张 Android 1080×2400）·
> `store-assets/screenshots-ios/`（15 张 iOS 1320×2868）· `/tmp/v210-home.png`
> （iPhone 18 Pro 真机 1206×2622）· `docs/design-direction-2026-11-07.md` §4/§8 ·
> `app/lib/core/theme.dart` · `prototype/v2/`。
>
> **边界**：只出审计、证据裁图与（可选的）refine 静帧；**不改 `app/`、不动 `dist/`、
> 不 push、不重出商店截图**。所有"实测"指从上述截图像素量出来，不是估计。
>
> **一句话结论**：v2.1.0 已经把"结构"做对了，但"精致"还停在令牌定义上 ——
> **材质只落了半套、字阶只用了下半段、版式没有为高屏编排、边缘状态还在用破折号凑**。
> 这四条加起来，就是用户说的"还是不够精致"。

---

## 0. 一页结论

### 0.1 三个最刺眼的数字（实测）

| 数字 | 含义 | 出处 |
| --- | --- | --- |
| **312pt** | iOS Pro Max 首页，最后一块内容到浮起底栏之间的纯黑高度（956pt 屏的 32.6%） | `01-home.png`，raw y=1602–2537 |
| **215pt** | iOS 训练屏组表底边到「第 1 组」之间的纯黑高度（首练态；休息态 166pt） | `05-workout.png` / `06-workout-logged.png` |
| **221pt** | 进步页「训练容量」图表卡高度；它把「个人纪录」推到距底栏只剩 **19pt**，PR 行直接压在玻璃底栏下面 | `08-progress.png` |

### 0.2 五条根因（详见 §2）

1. **材质只有"底色 + 1px 线"**：28 处手搓卡片只画 `line`（对 surface 1.45:1），
   `edgeHighlight` 只落在 3 个文件；卡片阴影 `0 18 36 -28` 在纯黑上几乎不可见。
2. **字阶建了，但只用了下半段**：首页卡片标题 15 = 行标题 15，数值 13；
   同一个"动作名"在首页 15 / 建议页与选择器 17 两种大小；身体数据标题 20，
   其他二级页 28。结果是"每一行都在同一层"。
3. **版式是"内容贴顶 + 固定底栏"**：高屏多出来的空间全部留在最底部；
   短内容屏没有纵向构图，长列表把最后一块压到浮动底栏下面。
4. **只设计了有数据的 happy path**：首练用破折号、琥珀色"最佳 —"、每行两个"——"；
   无上期数据仍写"较上期同期"；1 个数据点仍占 120pt 图表；筛选行右侧直接裁断。
5. **令牌最后一公里没走完**：`Tokens.accentButton` 渐变 **0 处使用**，
   主按钮全是平涂橙；完成勾辉光 `radius 28 / spread 2 / alpha 0.28` 太散；
   iOS 原生 SF 底栏与 Android Material 通栏是两套视觉语言；
   `today_suggestion_screen.dart` 里 3 处橙字仍用 `Tokens.accent`，绕过 budget 守卫。

### 0.3 最高性价比的三件事（<1 小时可先做）

1. **首页 hero 抬层级**：卡片标题 15→22（`fsNum`）、行名 15→17（`fsBody`）、
   数值 13→15（`fsSub`）、边线 `#3B332B→#463D33`、补 `edgeHighlight`。
2. **把已有的 `Tokens.accentButton` 真正用起来**：首页/训练/总结/身体数据的平涂橙
   换成渐变 + 1px 内高光 + 紧阴影（不是加"发光"）。
3. **两处一眼假**：picker 筛选行加右侧渐隐/留白；首练对照带与组表不再渲染破折号。

---

## 1. 方法与证据

### 1.1 怎么量

- **全量看**：31 张商店截图 + 1 张真机截图，逐屏按 8 个维度过了一遍；
  关键屏（首页/训练/进步/我/选择器/建议/总结/身体数据）另看 1320×2868 原图。
- **空尾测量**：按行取平均亮度，背景阈值 = 顶部 20 行均值 + 3；
  统计 ≥60px 的连续背景行，再按 DPR 换算成 pt
  （iOS 3x / Android 3x；Android 1080×2400 = 360×800，iOS 1320×2868 = 440×956）。
- **卡边界/按钮**：沿一条竖线扫像素，`line`（约 `#3A332C`）与 `surface`
  （约 `#1A1611`）可直接读出卡顶/卡底/按钮上下边。
- **代码对照**：以 `theme.dart`、`vi_cards.dart`、`today_screen.dart`、
  `workout_screen.dart`、`progress_screen.dart`、`workout_summary_screen.dart`、
  `body_metric_screen.dart`、`app_tab_bar.dart` 的实现值为准。
- **证据裁图**：`docs/images/visual-audit-2026-11-10/` 共 19 张，全部用 `sips -c`
  从原图裁出；索引见 §8。
- **可选对照静帧**：`prototype/refine/home-compare.html`（左：v2.1.0 真机截图；
  右：同数据的精致化建议，390×844 内嵌 iframe）与 `home-compare.png`。
  只演示 Q1/O2/O3/O4 的局部变化，不改 IA。

### 1.2 先说清楚"不是问题"的三件事

- **暗不是问题**：`text3` 对 surface 4.88:1、`accentInk` 对 accent 5.55:1，
  对比度是合格的；问题在**层级**，不在亮度。
- **大圆角不是问题**：12pt 卡片、999 胶囊是合适的；不要为了"精致"改成 20。
- **原生底栏不是问题**：iOS 原生 `UITabBar` 是用户点名要的；
  这一轮不建议为了视觉把它换回自绘（除非同时接受桥接与测试成本）。

---

## 2. 五条根因

### R1 · 材质只有"底色 + 线"，没有第二层

**证据**：`home-card-typography.png`、`home-button-flat.png`、`profile-empty-tail.png`。

- 卡片内部实测 `#1A1611`，页面底 `#080706`：只差 **1.12:1**；
  卡边实测 `#3A332C`（`Tokens.line #3B332B`），对 surface **1.45:1**。
- 全仓 **28 处** `Border.all(color: Tokens.line)` 手搓卡片，分布在 14 个文件；
  `Tokens.edgeHighlight` 只在 `vi_cards.dart` / `profile_widgets.dart` / `theme.dart`
  三处出现；首页 `_TodayPlanCard` 有 `shadowCard`，**没有** `edgeHighlight`
  （`today_screen.dart:721-729`）。
- `shadowCard` 是 `0 18 36 -28` 的 90% 黑：在 `#090706` 背景上几乎看不见；
  这就是为什么"有卡片"和"没卡片"看起来差不多。
- 主按钮实测是平涂 `#D36D46` 一类的单色（沿按钮从上到下采样一致），
  `Tokens.accentButton` 的三段渐变**一次都没用**。

**判断**：不是缺颜色，是缺**材质的第二层**（顶部 1px 暖白高光 + 更清楚的边 + 紧阴影）。
深色界面里真正让卡片"浮起来"的是高光边，不是大阴影。

### R2 · 字阶建了，但只用了下半段

**证据**：`home-card-typography.png`、`picker-row-meta.png`、`body-title-20pt.png`。

- 首页卡片标题「今天练 上肢 · 健身房」：`fsSub 15`（`today_screen.dart:735-742`），
  与动作行名字同字号（`fsSub 15`，`:798-802`）；数值是 `fsCap 13`（`:804-817`）。
- 同一个"动作名"在三个屏是三种字号：
  首页 15（`fsSub`）· 今日建议 17（`fsBody`）· 选动作 17（`fsBody`）。
- 「身体数据」标题 20（`body_metric_screen.dart:910-918`），
  而「数据与备份」「设置」「隐私与关于」等二级页都是 28（`ProfileSubPage`）。
- 进步页的「训练容量」「个人纪录」「部位分布」都是 15 或 13（`fsSub/fsCap`），
  和图表刻度的 12 只差一级；一屏里 12/13/15/17/34 五档都在，但 20/22/24 几乎空着（20 只被身体数据标题误用一次）。

**判断**：当前是"页面标题很大 + 其余全部 12–17"的两极结构，
中间缺少 **22 的卡片主标题、17 的行主标题、15 的数值**这三层。
精致感来自"一屏三到四个明确层级"，不是再加字号。

### R3 · 版式是"内容贴顶 + 固定底栏"，没有为高屏编排

**证据**：`home-empty-tail.png`、`profile-empty-tail.png`、`workout-dead-space.png`、
`progress-behind-tabbar.png`、`summary-bottom-cut.png`。

| 页面 | 实测空尾 / 死区 | 说明 |
| --- | --- | --- |
| iOS Pro Max 首页 | **312pt**（1602–2537 raw） | 956pt 屏的 32.6% |
| iPhone 18 Pro 首页（真机） | **170pt**（1782–2291 raw） | 874pt 屏的 19.5% |
| Android 首页 | **284pt**（1308–2158 raw，851px/3） | 800pt 屏的 35.5% |
| iOS「我」 | **304pt**（1626–2538 raw） | 三张卡之后全空 |
| iOS 训练屏 | **215pt**（首练）/ **166pt**（休息） | 组表底到「第 N 组」之间 |
| 进步页 | 图表卡 **221pt**；PR 标题距底栏 **19pt** | 图表把 PR 推到玻璃底栏下面 |
| 总结 / 身体数据 | 固定底部按钮上方的内容被切在半句 | `summary-bottom-cut.png` |

**判断**：`ListView` / `Column + Expanded` 的默认行为是"内容从上面开始，剩余留在下面"。
内容少时，空的是**尾部**；内容多时，最后一块被**底栏切掉**。
这不是"留白"，是没有为 956 / 874 / 800 三种高度做构图。

### R4 · 只设计了有数据的 happy path

**证据**：`workout-compare-dashes.png`、`workout-set-rows.png`、`progress-no-delta.png`、
`progress-chart-sparse.png`、`picker-filter-clip.png`。

- 首练对照带：`上次 —` 是白色 `fsBody 17`；`最佳 —` 用的是 `Tokens.pr`（琥珀色）
  当 value color（`workout_screen.dart:479-488`）—— **没有数据却用"破纪录"的颜色**，
  这是最典型的一处"像 bug 的视觉"。
- 组表每行最后一列是 `lastLabel ?? '—'`（`:720-727`），状态列 pending 又是 `—`
  （`:745-748`），于是每行出现 **两个破折号**；用户读不出哪个是"上次"，哪个是"状态"。
- 进步页 `'$range · 较上期同期'` 是无条件渲染的（`progress_screen.dart:601-605`）；
  上期没有数据时，delta 被隐藏，但这行字仍说"较上期同期"。
- 只有 1 个数据点的容量趋势仍占 **120pt**（`progress_screen.dart:882-887`）：
  一条基线 + 最后一根斜线，卡里 70% 是空的。
- picker 的横向筛选行没有右侧留白/渐隐，最后一枚 chip 被屏幕直接裁断
  （`picker-filter-clip.png`）。

**判断**：精致感的一半来自"没有数据时仍然好看"。现在缺的不是组件，
是**空态/少数据态的版面**：要么隐藏整列/整块，要么给一个短说明，而不是塞破折号。

### R5 · 令牌的最后一公里没走完 + 平台分叉

**证据**：`home-button-flat.png`、`summary-glow.png`、
`tabbar-android-vs-ios.png`、`suggestion-orange-repeat.png`。

- `Tokens.accentButton` **0 处使用**；首页 66pt、训练 88pt、总结 88pt、身体数据 64pt
  全是单色橙。`FilledButton`/`TextButton` 的默认几何也各不相同。
- 完成勾 `Tokens.glow(Tokens.success, radius: 28, spread: 2)`（`workout_summary_screen.dart:453`）
  的 alpha 固定 0.28；结果是屏幕上半部一大团绿雾，像"发光滤镜"而不是"完成一下"。
- `today_suggestion_screen.dart:434` 的 `color: Tokens.accent` 出现 3 次（三行动作建议），
  每行都是橙色正文；`accent_budget_test` 的行扫描抓不到（`TextStyle` 与 color 不在同一行）。
- iOS 底栏是原生 `UITabBar`（SF Symbols、浮动 68pt、距底 8），
  Android 是通栏 68pt Flat + Material Icons、顶部 1px 线；同一产品两套底栏语言，
  图标粗细/大小/选中态都不同。

**判断**：设计令牌已经定义了很多正确的东西，但页面没有**统一消费**它们；
同时"平台分叉"被当成正常差异，导致截图并排时像两个 App。

---

## 3. Top 12 优化点（按影响/成本排序）

> 影响：★★★ = 第一眼/首屏；★★ = 训练中或高频；★ = 细节。
> 成本：S < 0.5 天；M = 0.5–2 天；L > 2 天。
> 排序口径：**先按影响（第一眼 > 高频 > 细节），同影响内成本低者先**；
> 所以 O1/O2 虽然成本 M，但视觉面积最大，仍排在 S 成本项前面。

| # | 优化点 | 影响 | 成本 | 证据 |
| --- | --- | --- | --- | --- |
| O1 | 首页/「我」的纵向构图：空尾变成呼吸 | ★★★ | M | `home-empty-tail.png` · `profile-empty-tail.png` |
| O2 | 卡片材质统一：`line` 提亮 + 1px 高光 + 紧阴影 | ★★★ | M（首屏 S） | `home-card-typography.png` |
| O3 | 主按钮用已有 `accentButton` 渐变 + 紧辉光 | ★★★ | S | `home-button-flat.png` |
| O4 | 字阶角色化：22 卡片主标题 / 17 行主标题 / 15 数值 | ★★★ | S | `home-card-typography.png` |
| O5 | 训练屏纵向重排：组表与「本场」摘要吃掉 166–215pt 死区 | ★★ | M | `workout-dead-space.png` |
| O6 | 首练/空数据版面：删破折号与琥珀 dash，隐藏无意义列 | ★★ | M | `workout-compare-dashes.png` · `workout-set-rows.png` |
| O7 | 进步图表：221pt 卡收紧、补 y 轴/网格、稀疏态降高 | ★★ | S–M | `progress-chart-sparse.png` |
| O8 | 进步页底部：让 PR 不再被浮起底栏盖住 | ★★ | S | `progress-behind-tabbar.png` |
| O9 | 选动作筛选行：右侧渐隐/留白，不再硬裁 | ★★ | S | `picker-filter-clip.png` |
| O10 | 橙色预算：建议页 3 条橙字 + 计划页 10 枚橙 badge 降噪 | ★★ | S | `suggestion-orange-repeat.png` · `routine-orange-badges.png` |
| O11 | 总结/身体数据：固定底部按钮前的渐隐与标题尺寸收口 | ★ | S | `summary-bottom-cut.png` · `body-title-20pt.png` |
| O12 | 跨端底栏/图标的视觉密度对齐（不换原生） | ★ | M | `tabbar-android-vs-ios.png` |

---

### O1 · 首页/「我」的纵向构图：空尾变成呼吸

**现象**：iOS Pro Max 首页空 **312pt**、真机 170pt、Android 284pt；
「我」空 **304pt**。内容全部贴顶，底部像"截断了"。

**判断**：违反"留白要被设计"的原则；实际是 `ListView` 的内容高度小于视口，
剩余空间没有参与构图。用户第一眼看到的不是"简洁"，是"没做完"。

**改法**（具体）：

1. `today_screen.dart:267-294` 的根 `ListView` 升级为
   `LayoutBuilder` + `CustomScrollView`，用一个 `SliverFillRemaining(hasScrollBody:false)`
   承载三块；在 `card` 与 `recent`、`recent` 与 `week` 之间放两个 `Spacer`，
   剩余空间按 `40% / 60%` 分配，单侧上限 **96pt**（超过上限就加在底部安全区）。
2. 同步把三块"长大一点"：计划行高 38→**46pt**（`vertical: s2 8→s3 12`），
   周节奏从"8px 点 + 13pt 字"升级为 **64pt 高的细带**（10px 点 + 12pt 星期），
   最近一次行高 24→**44pt**；三块合计约 +70pt，空尾在 874pt 机器上降到 ~100pt、
   在 956pt 上约 240pt，再被两个 Spacer 分掉。
3. ≥900pt 时（`MediaQuery.sizeOf(context).height`）改为**居中构图**：
   内容组外上下各 `Spacer`；不要继续把内容贴顶。
4. 「我」页同样处理：`profile_screen.dart` 三块后加 `Spacer` 或把版本行钉在底部；
   删掉「成就」小标题与卡片标题「成就」的重复（`profileSectionTitle('成就')` 那行）。

**验收**：在 440×956 / 402×874 / 360×800 三档截图上，
"最后一块内容 → 底栏"的距离：**874 上 ≥ 96pt，956 上 ≥ 120pt**；
且距离在视觉上大致均匀（不是全在底部）。

**成本/影响**：M / 第一眼（首屏第一张卡以外最大的一块）。

---

### O2 · 卡片材质统一：`line` 提亮 + 1px 高光 + 紧阴影

**现象**：卡边对 surface **1.45:1**；首页卡无顶部高光；28 处手搓卡片只有 1px 线。

**判断**：深色界面里卡片层级靠"边 + 高光"，不靠大阴影；现在两样都不足。

**改法**（具体值）：

1. `Tokens.line: #3B332B → #463D33`（对 surface **1.45→1.69:1**；
   对 bg 1.62→1.89；仍弱于 `lineStrong` 3.35，不抢功能边界）。
2. `Tokens.edgeHighlight`：`0x0FFFFFF6`（≈6% 暖白）→ **`0x14FFF6EC`（≈8%）**；
   1px 内高光改成"偏暖的 8%"。
3. 所有手搓卡片统一用
   `boxShadow: [...Tokens.shadowCard, ...Tokens.edgeHighlight]`；
   首页 `_TodayPlanCard`（`today_screen.dart:721-729`）当前只有 `shadowCard`，
   直接补 `edgeHighlight`；训练屏组表卡（`workout_screen.dart:588-593`）目前
   连 shadow/highlight 都没有，补上。
4. `Tokens.shadowCard` 从 `0 18 36 -28 / 90%` 收紧为
   **`0 10 24 -16 / 82%`**：深色下让边缘周围有一点点"下沉"，而不是一圈大黑雾。
5. 不建议把 28 处都改成 `ViCard`（会引入大量 padding 差异）；
   先加一个 `cardDecoration()` 工具函数，保证"边 + 高光 + 阴影"三件套一致。

**验收**：截图上卡片上边出现一条可见的 1px 暖白（放大 3x 后能看出），
卡边在纯黑上不丢；同时 `theme_contrast_test` 的 line/hair、lineStrong/line
两个比值仍 ≥1.2。

**成本/影响**：M（首屏 3 张卡 S）/ 第一眼。

---

### O3 · 主按钮用已有 `accentButton` 渐变 + 紧辉光

**现象**：首页 66pt、训练 88pt、总结 88pt、身体数据 64pt 全部是单色橙；
`Tokens.accentButton` 三段渐变 **0 处使用**（grep 全仓仅定义处）。

**判断**：平涂大橙块是"Material 模板感"最重的一处；已有渐变令牌不用，
等于设计系统没有落地。

**改法**（具体）：

1. 新增一个**共享主按钮组件**（建议叫"主按钮 / accent button"，尚未落盘；本轮不写 app/）：
   - 背景 `Tokens.accentButton`；
   - `boxShadow`: `0 10px 24px -12px rgba(226,102,58,.35)`
     + `inset 0 1px 0 rgba(255,255,255,.28)`
     + `inset 0 -1px 0 rgba(0,0,0,.16)`；
   - 按压 `AnimatedScale 0.98 / Motion.instant`（与训练屏一致）。
2. 替换：首页 `today_screen.dart:831-845`、训练屏 `workout_screen.dart:963-970`、
   完成页 `workout_summary_screen.dart:826-850`、身体数据 `body_metric_screen.dart:1055-1070`、
   建议页 `today_suggestion_screen.dart:471`。
3. 渐变端点保持现在的 `#F08A5B → #E2663A → #D65B2D`（不要加更亮的顶端，
   否则橙底字对比度会掉）；`accentInk` 对渐变中段 5.5:1，仍安全。

**验收**：截图上按钮从上到下有三段、顶端有一条 1px 高光；不再是单色块；
按压有 0.98 缩放（其他主按钮也统一）。

**成本/影响**：S / 第一眼 + 训练中。

---

### O4 · 字阶角色化：22 卡片主标题 / 17 行主标题 / 15 数值

**现象**：首页卡片标题 15、行名 15、数值 13；选动作行 17、建议行 17
（同一个行角色比首页大 2pt）；身体数据标题 20（其他二级页 28）。

**判断**：`Tokens` 的 10 级字阶没有错，错在**角色映射**。

**改法**（具体映射，全部用现有令牌，不新增字号）：

| 角色 | 现在 | 建议 | 代码位置 |
| --- | --- | --- | --- |
| 页面标题 | 28 | 28（保持） | `app_top_bar.dart:90` |
| 卡片主标题 | 15 | **22（fsNum）** | `today_screen.dart:735-742` |
| 卡片 eyebrow | 无 | **12（fsMicro）text3，加「今日训练」** | 同上 |
| 行主标题（动作名） | 15（首页）/ 17（建议、选择器） | **17（fsBody）全站统一** | `today_screen.dart:798-802` · `today_suggestion_screen.dart:414-418` · `exercise_picker_screen.dart` 行标题 |
| 行数值（组×次 / 重量） | 13 | **15（fsSub）** | `today_screen.dart:804-817` |
| 表头 / 小标签 | 12 | 12（保持） | — |
| 二级页标题 | 20（身体数据） | **28（fsTitle）** | `body_metric_screen.dart:910-918` |
| 进步区标题 | 15 / 13 | **17（fsBody）/ 15（fsSub）** | `progress_screen.dart:865-869` · `:1071-1076` |

同时：**首页卡片标题拆成两行**——eyebrow「今日训练」12pt + 标题「下肢 · 健身房」22pt；
不要继续用「今天练 下肢 · 健身房」一整行 15pt。

**验收**：一屏内出现 3–4 个明显层级（28 页标题 / 22 卡标题 / 17 行 / 15 数值 / 12 标签）；
在 2.0× 字号扫描里卡片标题不溢出（必要时给卡片标题 `maxLines: 1` + `ellipsis`）。

**成本/影响**：S / 第一眼（最便宜的"精致"）。

---

### O5 · 训练屏纵向重排：吃掉 166–215pt 死区

**现象**：首练组表底边到「第 1 组」之间 **215pt** 纯黑；休息态 166pt。
`workout_screen.dart:240-250` 的 Column 用 `Expanded(_setsArea)`，
而 `_setsArea` 里的卡是 `Flexible` + 内容收口（`:577-581`），剩余高度没有被利用。

**判断**：这不是"留白"，是 `Expanded` 给了空间但没人消费。
训练屏是核心屏，用户会在组间 60 秒反复看，空白会显得"页面没加载完"。

**改法**（三种按成本递增，建议先做 1+2）：

1. **行高与对照带**：组表行 `vertical: s3 12 → s4 16`（38→46pt，4 行 +32pt）；
   对照带 `vertical: s3 → s4`（+8pt）；领条 40→48pt（+8pt）。
2. **把"本场"摘要行放到组表下方**（不是新卡片）：
   `本场 2 / 12 组 · 已练 18:42`，12pt text3，右侧 `上一个/下一个` 不动。
   使用 `Column(mainAxisAlignment: MainAxisAlignment.spaceBetween)`：
   组表在上、摘要在下，中间 `Spacer` 吃掉一部分；剩余再分给底部。
3. 若仍 >120pt 空：在 `_setsArea` 内把组表卡改为 `Expanded` +
   `Column(mainAxisAlignment: MainAxisAlignment.start)`，底部加
   `Spacer` + `本场`；不要回到 v2.0.1 那种"卡撑满但底部全空"的做法
   （`docs/design-direction-2026-11-07.md` 已记录过一次返工）。
4. 高屏（≥900pt）下允许组表卡**固定 4 行 + 摘要**，把剩余空间在
   "对照带→组表"和"组表→记录键"之间按 30/70 分配。

**验收**：在 956pt 屏上，"组表底 → 第 N 组" ≤ **96pt**；在 844pt 屏上 ≤ 48pt；
记录键仍在屏幕下 1/3（top > 0.55×高）。

**成本/影响**：M / 训练中（核心屏）。

---

### O6 · 首练/空数据版面：删破折号与琥珀 dash，隐藏无意义列

**现象**：
- 对照带 `上次 —`（白）· `最佳 —`（**琥珀** `Tokens.pr`）· 目标下再一个 `—`；
- 组表每行 `上次 —` + 状态 `—`（两列破折号）；
- 进步页无上期数据仍写「较上期同期」；
- 1 个数据点占 120pt 图表。

**判断**：这些不是"空"，是"没有为没有数据设计版面"。破折号是最像未完成品的占位符。

**改法**（具体）：

1. `_compareBand`（`workout_screen.dart:440-507`）：
   - 当 `lastMain == null && best == null`：整条带改成**一行目标**：
     `今天的目标 4 组 × 8–10 次 · 40 kg`，label 12pt，值 17pt；不渲染两格。
   - 只有 `best == null`：隐藏「最佳」那一格，不传 `Tokens.pr`；宽度给「上次/目标」。
   - 只有 `lastMain == null`：隐藏「上次」。
   - 永远不要用 `Tokens.pr` 画无数据占位。
2. `_setRow`（`:658-751`）：
   - `c.lastSession == null` 时**不渲染「上次」列**（表头也去掉，列宽让给重量/次数）；
   - 状态列：已完成 `✓`、当前 `◉`、待做**留白**（不要 `—`）；
   - 这样首练组表只有 `组 / 重量 / 次数 / 状态` 四列，不会 `— —`。
3. 进步页（`progress_screen.dart:599-621`）：
   `prevVolume > 0 ? '$range · 较上期同期' : '$range · 第一次记录'`；
   没有可比数据不写"较上期"。
4. 图表（`:850-887`）：`weekCount < 2` 时 `ViAreaChart(height: 72)` +
   基线 + 一句 `第 2 次训练后出现趋势`；隐藏「上周」legend。
5. 给这些状态加 widget 测试：首练页 `find.text('—')` 为 0（或只允许目标行内 0 个）；
   `progress` 无上期时没有"较上期"。

**成本/影响**：M / 首次使用（最容易流失的一批）。

---

### O7 · 进步图表：221pt 卡收紧、补 y 轴/网格、稀疏态降高

**现象**：`progress-chart-sparse.png`：120pt 图 + 20pt 卡 padding + 标题，
卡高 **221pt**；只有 3 个平点 + 最后一根斜线；无 y 轴、无网格；
「上周」虚线在无数据时几乎不可见。

**判断**：图表是进步页唯一的"图"，它现在像"加载了一半"。

**改法**（具体）：

1. `progress_screen.dart:882-887`：`height: 120 → 96`；`ViCard` 传
   `padding: EdgeInsets.fromLTRB(16,16,16,12)`（现在默认 20）。
2. `ViAreaChartPainter`：加两条水平网格线（25%/50%/75%，`Tokens.line` 1px、
   alpha 0.55）；左上角加 `0` / 右下角加当前最大值（10pt text3）；
   基线保持 1px `line`。
3. `previousPoints` 全 0 或为空时：不画虚线、不显示「上周」legend；
   legend 只在有对比时出现。
4. 数据点 ≤2：`height: 72`，并在图下加一行 12pt text3
   「第 2 次训练后出现趋势」；不要用一张大空卡装一根斜线。
5. 直线段保留（不要为了"顺滑"用可能造假的曲线）；只通过网格/标签提升可读性。

**成本/影响**：S–M / 第一眼 + 每周回访。

---

### O8 · 进步页底部：让 PR 不再被浮起底栏盖住

**现象**：`progress-behind-tabbar.png`：PR 标题 `2481`，底栏从 `2538` 开始，
只剩 **19pt** 可见；PR 行直接被玻璃盖住（Android 同样在视口底被切）。

**判断**：不是"滚动到最后才被盖"——首屏就出现了"个人纪录"标题却没有内容，
用户会以为页面断了。

**改法**（具体，按收益排序）：

1. O7 的图表卡收紧（-24pt）+ 卡 padding 20→16（-8pt）+
   `progress_screen.dart:344-355` 的 section gap 20→16（3 处 -12pt）+
   部位分布行高 34→32（6 行 -6pt）：合计约 **-50pt**，
   PR 标题 + 第一行能在首屏完整露出来。
2. 若仍不够：在 `ListView` 的 bottom padding 保留 `s5 + reservedSpace` 的同时，
   把「个人纪录」上方的 section gap 再压到 12pt。
3. **可选**：在 iOS 浮起底栏上方加一层 24pt 的 `bg → transparent` 渐隐
   （不是通栏玻璃），让滚到下面的文字有一个"被压住"的边界；
   这与"玻璃底栏本身"不冲突，只是给内容一个收口。
4. 不要简单地把 PR 挪到图表前面——那会破坏"总量 → 趋势 → 结构 → 纪录"的阅读顺序。

**成本/影响**：S / 第一眼（进步页首屏）。

---

### O9 · 选动作筛选行：右侧渐隐/留白，不再硬裁

**现象**：`picker-filter-clip.png`：三行 chip 的最后一枚都被右边缘直接切断
（部位「核心」只露一条边、器械「自重」同理）；没有滚动提示。

**判断**：横向滚动本身没问题，问题是**边缘处理**让"可滚动"看起来像"被裁"。

**改法**（具体）：

1. `exercise_picker_screen.dart:640-670` 的 `_filterRow`：
   - `ListView` 加 `padding: EdgeInsets.only(right: Tokens.s5)`；
   - 外面包一层 `ShaderMask`（`LinearGradient`，最后 24pt 从 transparent→bg）；
   - 行首标签宽度 30 保持；chip 之间的 `s2` 保持。
2. 行高 36 保持；不要为 7 个部位 chip 改成两行（会让筛选区从 3 行变 4–5 行，
   把列表往下推）。
3. 「全部」用 `lineStrong` 描边而不是 `accent` 填充是对的（当前实现正确），
   保留；但三行「全部」同时出现时，建议只给当前**有筛选**的行高亮，
   三行都"默认"时统一中性，否则三个边框一起抢注意力。

**成本/影响**：S / 高频（选动作是开练前置）。

---

### O10 · 橙色预算：建议页 3 条橙字 + 计划页 10 枚橙 badge 降噪

**现象**：`suggestion-orange-repeat.png`：三行「第一次练这个动作，先从这个重量开始」
全是 `Tokens.accent`；`routine-orange-badges.png`：5 张模板卡 × 2–3 枚橙 tint badge。

**判断**：橙色是"主操作"色，不是"说明/分类"色；橙色面积一多，主按钮就不再是主角。

**改法**：

1. `today_suggestion_screen.dart:432-438`：
   `color: Tokens.accent → Tokens.text2`（理由仍可读，但不抢）；
   如果一定要保留"建议"语义，只给**第一条**用 `accentText`，其余 text2。
   顺带修 `accent_budget_test` 的盲点（见 §7）。
2. `routine_screen.dart` 模板卡 badge：
   - 分类 badge 统一 `surfaceHi` 底 + `text2` 字；
   - 每张卡最多保留 **1 枚**强调（"第一次去"/"推荐"）用 `accentText` 文字，
     不再整枚橙底。
   - 5 张卡上的 10–12 枚橙 badge → 1–2 枚。
3. 首页/训练/进步已有的橙色主操作保留；不要因为降噪把主按钮也降成灰色。

**成本/影响**：S / 第一眼（信息噪声）。

---

### O11 · 总结/身体数据：固定底部按钮前的渐隐与标题尺寸收口

**现象**：`summary-bottom-cut.png`：拉伸卡最后一句被分享按钮切在半句；
`11-body-metric`：身高标签在保存按钮上方被切；`body-title-20pt.png`：身体数据标题 20。

**判断**：固定 CTA 的页面没有给滚动内容留"视觉出口"；同时身体数据标题
比其他二级页小 8pt。

**改法**：

1. `workout_summary_screen.dart:216` 的 ListView bottom padding `s4 → s6`；
   在 `_shareButton` 上方加 24pt `bg→transparent` 渐隐（或 1px hairline + 8pt padding）。
2. `body_metric_screen.dart:915` 标题 `fsHeadline 20 → fsTitle 28`（与
   `ProfileSubPage` 对齐）；底部保存按钮同样加 16–24pt 渐隐。
3. 固定底部按钮的容器加 `Border(top: hair)` 或 `surface` 底，给内容一个明确边界；
   不要用大阴影（在 bg 上不可见）。

**成本/影响**：S / 低频但"最后一屏"印象分。

---

### O12 · 跨端底栏/图标：对齐视觉密度，不换原生

**现象**：`tabbar-android-vs-ios.png`：iOS 浮起胶囊 + SF Symbols；Android 通栏 +
Material Icons；选中态都是橙，但高度、图标粗细、底部安全区不同。

**判断**：平台差异本身可以接受，但"同一产品的底栏"要共享同一套密度与语义。

**改法**（具体，低风险）：

1. 底栏高度保持 68；Android 顶部 1px `line` 保留；iOS 原生浮起保持 8pt margin。
2. 图标语义统一：两端的"进步/开练/我"都走 `icon_spec.dart` 的语义；
   Material Icons 与 SF Symbols 的视觉尺寸差 1–2pt 时，用 `IconSpec` 的
   `m/l` 两档做 optical 补偿（不是改系统图标）。
3. Android 的未选中 tab 颜色从 `text2` 统一到 `text3`? —— **不建议**：
   tab 是功能性标签，保持 `text2` 是对的（现有注释已论证）。
4. 内容区底部：iOS `reservedSpaceFor = 68 + 8 + 8 = 84`；Android 0（底栏在 Column 内）。
   保持，但**滚动内容最后一块**在两端都要有 ≥16pt 的底部留白。
5. 不要为"对齐"改 iOS 原生底栏；要改只在 Android 侧调图标/文字光学尺寸。

**成本/影响**：M / 跨端一致性（截图并排时）。

---

## 4. 其余维度（不排进 Top 12，但必须修）

### 4.1 图标与图形

| 问题 | 证据 / 位置 | 改法 |
| --- | --- | --- |
| 训练屏顶栏 3 个 36×36 图标按钮，低于 44pt；「换动作」仍是无字 icon，和 v1.53 的"带字胶囊"决定相反 | `workout_screen.dart:319-372` | 触区改 44×44；换动作改成 44×44 的 icon + tooltip 或小字胶囊；信息 icon 与「动作要领」重复可去掉一个 |
| 休息条 −15/+15/跳过 高 36pt，弱于 44 | `workout_screen.dart:1154-1165` | 视觉保持小，但触区 44；或整个胶囊底 |
| 选动作每行的小哑铃 16pt 太细，和「总重（含杠铃杆）」重复 | `picker-row-meta.png` | 去掉图标或 20pt；把"总重（含杠铃杆）"收成每行 `40 kg` + 区块表头说明 |
| 空态虚线环 96pt、`lineStrong` 偏灰，像 loading | `empty_state.dart` | 空态环可保持，但线宽/透明度按品牌环统一；不要加"插画" |
| 全数据两条趋势图每个点都画 3.5pt 圆点，30 天像"糖葫芦" | `09-all-data.png` | 只保留末点；周/月用不同点密度；加 x 轴首尾标签 |
| 所有图标在 Material / SF 两套 | `tabbar-android-vs-ios.png` | 语义表统一；Android 只做光学尺寸微调 |

### 4.2 动效与反馈

- **按压**：只有训练屏大按钮有 `AnimatedScale 0.975`（`workout_screen.dart:959-962`）；
  首页/总结/身体数据/建议的主按钮没有按压反馈。→ 统一到 `0.98 / Motion.instant`。
- **数字变化**：容量 34pt 在切换周/月/年时直接换值，没有 120ms 淡入/数字滚动；
  可加 `AnimatedSwitcher`（只对 hero 数字，不每帧重建）。
- **图表**：周/月/年硬切是已定决策（不做形变，避免重采样）；不要改。
- **完成页**：1400ms 时间线本身没问题；但 `完成` 按钮在 1100–1400ms 才淡入，
  手快的人看到"按钮还没出来"会犹豫；建议 1100ms 时 opacity 0.6 起、仍可点，
  或把"完成"固定显示、只对勾/数字做入场。属于体验细节，成本 S。
- **图表/列表**：列表没有 skeleton；`_loading` 用默认 CircularProgressIndicator，
  颜色由主题 seed 决定，可能与 accent 不一致；可换成 2px 的品牌环。
- **触觉**：规格已有，代码里不要新增；审计只提醒"按钮按压视觉"必须与触觉同一刻。

### 4.3 跨屏/跨端一致性

| 项 | 现状 | 建议 |
| --- | --- | --- |
| 二级页标题 | 身体数据 20；数据与备份/设置/隐私 28 | 统一 28（`fsTitle`） |
| 动作行主标题 | 首页 15 / 建议与选择器 17 | 统一 17（`fsBody`）；首页行名 15→17 |
| 主按钮高度 | 首页 66 / 训练 88 / 身体数据 64 / 总结 88 / 建议 88 | 定义 `hCardCta 64`、`hSecondary 56`、`hPrimary 88` 三个槽位；首页 66→64 |
| 区块间距 | 12 / 16 / 20 混用（进步 stats→trend 12、trend→muscle 20；总结 s4/s5 混） | 统一"内部 12 / 区块 20 / 大段 32"；一个 section gap token |
| 日期格式 | `11 月 10 日`、`11/10`、`11月10日` 三种 | 列表/图表用 `11/10`，标题用 `11 月 10 日`；写进 format 工具 |
| 单位空格 | `4×8–10次` / `4 × 8–10` / `40 kg × 8` | 统一 `4 × 8–10` / `40 kg × 8`；空格规则进 `formatSetsReps()` |
| 顶栏返回/齿轮 | 训练屏 36pt 圆形；身体数据 36pt；ProfileSubPage 44? | 统一二级页 44pt 触区，视觉 36 |

### 4.4 极端数据与 2.0× 字号

- 首页重量列固定 `SizedBox(width: 72)`（`today_screen.dart:810-817`），
  无 `FittedBox`/ellipsis；`1,000 kg` 或 2.0× 会顶格/裁切。→ 加 `FittedBox(scaleDown)`
  或宽 80 + ellipsis。
- 训练屏动作标题 20pt 无 `maxLines/ellipsis`（`workout_screen.dart:330-338`）；
  "保加利亚分腿蹲"这类 7 字在 360dp 会挤压右侧 icon 区。→ maxLines 1 + ellipsis。
- 进步 hero 34pt 有 ellipsis（`progress_screen.dart:570-578`），好；
  但 "12,480 kg" 在 2.0× 会先缩字号，需在 1.5× 下确认不破。
- 总结页三格数字固定 30pt 高 + FittedBox（`workout_summary_screen.dart:704-720`），
  机制正确；不要改成固定字号。
- `large_font_sweep_test.dart` 覆盖了首页/进步/训练/总结/身体数据/设置等 1.5×、2.0×；
  改 O4/O5/O11 后必须重跑。

### 4.5 色彩与语义色

- 橙的对比度合格（`accent` 对 bg 5.93，`accentText` 9.23，`accentInk` 5.55）；
  问题只在**面积**与**反复**，不在色值。
- `pr` 琥珀只应出现在"破纪录"；首练 `最佳 —` 用 `pr` 是误用（O6）。
- `danger` 只在删除；"未完成/没练"不要红色（现有规矩保持）。
- 底栏选中橙色 + 原生分段选中橙色 + 主按钮橙色 + 图表橙色 + PR 琥珀：
  一屏内 3–4 个"强调"是当前观感的噪声来源；O10/O3/O7 会缓解，
  **不要**再新增强调点。
- 深色模式下的"发光"：只保留完成勾一处；其余阴影用紧阴影，不用 glow。

---

## 5. 快赢清单（≤3 项、每项 <30 分钟）

### Q1 · 首页 hero 字阶 + 边线 + 高光（约 20–25 分钟）

- `today_screen.dart:735-742`：标题 `fsSub → fsNum 22`，前面加 eyebrow
  「今日训练」`fsMicro 12 / text3`；
- `:798-817`：行名 `fsSub 15 → fsBody 17`，组×次/重量 `fsCap 13 → fsSub 15`；
- `:721-729`：`border: Tokens.line` 改 `#463D33`（先改 `theme.dart` 的 `line`）
  + `boxShadow: [...Tokens.shadowCard, ...Tokens.edgeHighlight]`；
- 顺带 `:832` 的 `66 → 64`（4pt 网格）。
- **验收**：`home-card-typography` 同角度重截，标题与行名有明显大小差。
- **风险**：`typography_scale_test` 只允许现有字号（用 22/17/15，不新增）。

### Q2 · picker 筛选行右侧渐隐（约 10–15 分钟）

- `exercise_picker_screen.dart:640-670`：`ListView` 加 `right: s5` padding +
  24pt `ShaderMask` 渐隐；不改行高、不改 chip 数量。
- **验收**：`picker-filter-clip` 重截，最后一枚 chip 有渐隐而不是硬切。
- **风险**：`large_font_sweep` 2.0× 下多一层 ShaderMask 不改变布局，低风险。

### Q3 · 去噪两处：建议页橙字 + 完成页绿雾（约 10–15 分钟）

- `today_suggestion_screen.dart:434`：`Tokens.accent → Tokens.text2`（3 处同文件）；
- `workout_summary_screen.dart:453`：`radius: 28 → 18`、`spread: 2 → 0`；
  如要更克制，把 `Tokens.glow` 的 alpha 默认 0.28 → 0.20（影响 badge/通知，
  需重跑相关截图，但代码风险低）。
- **验收**：`suggestion-orange-repeat` / `summary-glow` 同角度重截，
  橙色面积下降、绿雾收紧。
- **风险**：若用户喜欢大辉光，这一步可回退（只改两处参数）。

---

## 6. 不要做（避免"越改越花"）

1. **不要**为了填首页空尾新增数据卡、勋章、广告、推荐位 —— 空尾用版式解决，
   不是用内容解决。
2. **不要**给所有卡片加玻璃、渐变、彩色氛围光；只允许**一个**主按钮渐变、
   **一个**完成勾辉光。
3. **不要**全局加大字号；只做角色映射（22/17/15/12），否则 2.0× 会全面溢出。
4. **不要**把圆角从 12 改成 16/20；当前 12 是对的，改大只会变"气泡"。
5. **不要**为了"精致"加大的 drop shadow；深色下大阴影只会脏。
6. **不要**把 `line` 提到 `lineStrong` 的亮度；功能边界和卡片边必须保持两级。
7. **不要**把橙色扩展成"说明文字 / 分类 badge / 未完成"色；橙色只给主操作。
8. **不要**用 0 / 破折号填补缺失数据；没有就隐藏或写一句真话。
9. **不要**在训练屏重新加入"长按调整顺序 / 点大按钮记录"这类说明；
   用可见控件。
10. **不要**为了视觉把 iOS 原生 `UITabBar` 换回自绘；跨端差异用图标密度对齐，
    不动交互归属。
11. **不要**引入图表库/动画库；现有的 `ViAreaChart` + `Motion` 足够。
12. **不要**把"短内容屏居中"做成所有屏的默认 —— 只有高度 ≥900pt 且内容不足时才居中。

---

## 7. 需要动令牌 / 守卫测试的改法（单列）

### 7.1 令牌级改动

| 令牌 | 现在 | 建议 | 影响面 / 风险 |
| --- | --- | --- | --- |
| `line` | `#3B332B` | **`#463D33`** | 全部卡片描边；对 surface 1.45→1.69；`theme_contrast_test` 的 line/hair、lineStrong/line 比值仍过（1.48 / 1.98）；同步 `docs/interaction-spec.md` §4 |
| `edgeHighlight` | `0x0FFFFFF6`（6%） | **`0x14FFF6EC`（8%）** | ViCard + 28 处手搓卡；没有测试断言 alpha，但视觉变化大，需重截关键屏 |
| `shadowCard` | `0 18 36 -28 / 90%` | **`0 10 24 -16 / 82%`** | 所有卡片；`vi_components_test` 只断言 border / radius，不红；更新规格 |
| 新 `ctaGlow`（建议） | 无 | `0 10px 24px -12px rgba(226,102,58,.35)` + `inset 0 1px 0 rgba(255,255,255,.28)` | 主按钮；必须放 `theme.dart`（禁止页面写 `BoxShadow(`） |
| `glow` / 完成勾 | `radius 28 / spread 2 / alpha .28` | 调用处 **18 / 0**；默认 alpha 可 0.20 | `BrandMark.glow` / 徽章 / 通知也走 `glow`，改默认会影响三处；建议只改完成页调用参数，不动默认 |
| `hPrimary` / 新增 `hCardCta` / `hSecondary` | 88；66/64 散落 | 88 / **64** / **56** | 首页 66→64；建议页/总结 88 保持；身体数据 64 用 `hCardCta`；`large_font_sweep` 重跑 |
| `rCard` / `rSheet` / `rPill` | 12 / 20 / 999 | **不动** | 避免全站截图/规格重做 |
| `text3` | `#8D8478` | **不动** | 对 surface 4.88；对 `surfaceHi` 4.42，继续只许 bg/surface |
| 字阶 | 10 级 | **不新增** | 22/17/15 都是现成的；加 18/24 会触发 `typography_scale_test` |

### 7.2 守卫测试会红 / 需要同步的清单

| 守卫 / 测试 | 会怎样 | 必须做什么 |
| --- | --- | --- |
| `theme_contrast_test.dart` | `line` 改动后要重算 text3、line/hair、lineStrong/line；目前结构上仍过 | 更新测试里的期望/注释；别把 `text3` 放到 `surfaceHi` |
| `theme_discipline_test.dart` | 新 `ctaGlow` / `edgeHighlight` 必须进 `theme.dart`；页面不许出现 `BoxShadow(`；`hair` 仍不许 `Border.all` | 新增令牌；手搓卡统一用 token；不要用 `hair` 描边 |
| `typography_scale_test.dart` | 用 22/17/15 都合法；如果把标题写成 18/24 会红；字面量字号也会红 | 只用 `Tokens.fs*`；不新增第 11 级 |
| `spacing_grid_test.dart` | 66→64 是 4 的倍数（好）；行内 `14/58` 这类不是 SizedBox 就没问题；卡片 padding 仍 `s5` | 行高用 padding/ConstrainedBox；不要写 `SizedBox(height:58)` |
| `accent_budget_test.dart` | 首页额度 1、训练 2 不变；**当前守卫抓不到** `today_suggestion_screen.dart` 的多行 `TextStyle` 橙字 | 修守卫：把 `accent` 文字扫描改为跨行/Widget 树；同时把建议页橙字改 `text2` |
| `large_font_sweep_test.dart` | 卡片标题 22、行高 46、按钮 64、身体数据标题 28 都要在 1.5×/2× 下跑 | 每次改 O4/O5/O11 后跑；必要时给标题 `maxLines/ellipsis` |
| `icon_spec_test.dart` | 顶栏 44×44 / 换动作文字胶囊不新增尺寸字面量即可；新 SVG 语义要进 `kIconSemantics` | 用 `IconSpec`，不加新尺寸 |
| `vi_components_test.dart` | 只断言 border color / radius；改 `line`/shadow 不红 | 改后重跑 |
| `widget_test` / `today_plan_test` / `progress_test` / `summary_*` | 文字、尺寸、空态变化会牵动断言 | 按新契约更新，不要删断言；补"无数据不出现破折号"的新用例 |
| `app_top_bar_test.dart` | 顶栏 28 / 40×40 不变 | 不动 |
| `glass_*_test.dart` | 不动 iOS 原生底栏就不受影响 | O12 只做 Android 侧光学调整 |

### 7.3 建议落地顺序（只改视觉，不改数据/逻辑）

1. **令牌 + 共享件**（`line`、`edgeHighlight`、`shadowCard`、`ctaGlow`、
   `hCardCta`）+ 重跑 `theme_contrast` / `vi_components`。
2. **Q1 + Q2**（首页 hero、picker 渐隐）→ 截三张对比图。
3. **O3（主按钮）**：先做首页/训练/总结/身体数据四个调用点；
   不碰次级按钮。
4. **O6（空态）**：训练屏首练与进步无 delta 是收益最大的一批；
   加两条 widget 测试钉住"没有破折号"。
5. **O7/O8（进步图表与底栏）**：一张卡的高度 + 一个 section gap，改完重截图。
6. **O1 （首页/我构图）**：这一步改布局，放最后；先用 refine 静帧确认视觉。
7. **O10/O11/O12** 收尾；最后再跑 `large_font_sweep` 与三套截图。

---

### 7.4 可选对照静帧（refine）

| 文件 | 内容 |
| --- | --- |
| `prototype/refine/home-compare.html` | 左侧嵌入 `v2.1.0` 真机截图（data URI），右侧是 390×844 的精致化首页（`iframe srcdoc`，自包含）；页面 PNG 见下 |
| `prototype/refine/home-compare.png` | 1720×1940（2x）对照图，用于评审/给用户看 |

右图的改动只包括：卡片标题 15→22 + eyebrow、行名 15→17、组×次/重量 13→15、
`line #3B332B→#463D33`、顶部 1px 8% 高光、卡片阴影收紧、主按钮渐变 + 64pt、
行高 38→56；不改信息架构、不新增内容。**它不是像素规格**，是"如果按 O1–O4 做，
首页会变成什么样"的近似。

## 8. 证据索引（19 张，≤20）

> 目录：`docs/images/visual-audit-2026-11-10/`；全部由 `sips -c` 从原图裁出。
> 括号里是 `源图 / y偏移 / x偏移 / 高×宽`，方便复核。

| 文件 | 对应问题 | 裁切 |
| --- | --- | --- |
| `home-card-typography.png` | 首页卡标题 15 = 行名 15；无 eyebrow | `screenshots-ios/01-home.png` / 420,0 / 1070×1320 |
| `home-empty-tail.png` | 首页空尾 312pt + 周节奏 | 同上 / 1400,0 / 1220×1320 |
| `home-button-flat.png` | 主按钮平涂橙（无渐变/高光） | 同上 / 1160,60 / 280×1200 |
| `workout-compare-dashes.png` | 首练 `上次 — / 最佳 —（琥珀）/ 目标 —` | `05-workout.png` / 280,0 / 430×1320 |
| `workout-set-rows.png` | 组表双破折号 + 表头/状态列 | 同上 / 700,40 / 850×1240 |
| `workout-dead-space.png` | 组表与「第 1 组」之间 215pt 死区 | 同上 / 1400,0 / 900×1320 |
| `progress-chart-sparse.png` | 221pt 图表卡 + 单点斜线 | `08-progress.png` / 990,40 / 740×1240 |
| `progress-no-delta.png` | 无上期数据仍写「较上期同期」 | 同上 / 730,0 / 230×1320 |
| `progress-behind-tabbar.png` | PR 标题距底栏 19pt、行被玻璃盖住 | 同上 / 2360,0 / 430×1320 |
| `profile-empty-tail.png` | 「我」304pt 空尾 | `10-profile.png` / 1300,0 / 1360×1320 |
| `picker-filter-clip.png` | 筛选行右侧硬裁 | `04-picker.png` / 560,0 / 470×1320 |
| `picker-row-meta.png` | 16pt 哑铃图标 + 重复「总重（含杠铃杆）」 | 同上 / 1020,0 / 620×1320 |
| `suggestion-orange-repeat.png` | 三行橙色理由文字 | `02-suggestion.png` / 1100,0 / 1000×1320 |
| `routine-orange-badges.png` | 5 卡 × 2–3 枚橙 badge | `03-routine.png` / 900,30 / 850×1260 |
| `summary-glow.png` | 完成勾辉光 28/2/0.28 | `07-summary.png` / 150,300 / 600×720 |
| `summary-bottom-cut.png` | 拉伸卡被分享/完成键切半句 | 同上 / 2080,0 / 780×1320 |
| `android-progress-behind-bar.png` | Android 进步首屏 PR 被视口底裁 | `screenshots/08-progress.png` / 2030,0 / 300×1080 |
| `body-title-20pt.png` | 身体数据标题 20（其他二级页 28） | `11-body-metric.png` / 120,0 / 220×1320 |
| `tabbar-android-vs-ios.png` | iOS 原生 SF 胶囊 vs Android 通栏 Material | 两套 `01-home.png` 底栏拼合 |

---

## 9. 附：原始测量数据（可复核）

以下为脚本按行平均亮度得到的连续背景区间（≥60px），DPR 3x：

| 屏 / 文件 | 连续背景区间（raw y） | 换算 pt | 读法 |
| --- | --- | --- | --- |
| iOS 01-home | 1602–2537 | **312pt** | 周节奏之后到底栏 |
| iOS 01-home（真机 402×874） | 1782–2291 | **170pt** | 同上，带 recent 行 |
| iOS 05-workout（首练） | 1572–2216 | **215pt** | 组表底 → 第 1 组 |
| iOS 06-workout-logged（休息） | 1572–2070 | **166pt** | 组表底 → 休息条 |
| iOS 10-profile | 1626–2538 | **304pt** | 成就卡 → 底栏 |
| Android 01-home | 1308–2158 | **284pt** | 周节奏 → 底栏 |
| Android 05-workout | 1278–1856 | **193pt** | 组表底 → 第 1 组 |
| iOS 08-progress | 图表卡 1050–1713（border→border） | **221pt** | 图表卡高度 |
| iOS 08-progress | PR 标题 2481；底栏 2538 | **19pt** | PR 标题距底栏 |

卡片/按钮实测（iOS 01-home，x=500 竖扫）：
卡顶 border 450–452 → surface 453；卡底 border 1455–1457；
主按钮 1197–1395（**66pt**）单色 `#D36D46`（沿 y 采样一致）。
卡边 `#3A332C` 对 surface `#1A1611` = **1.45:1**；页面底 `#080706`。

代码计数（`app/lib`）：

- `Border.all(color: Tokens.line)`：**28 处 / 14 文件**。
- `Tokens.edgeHighlight`：**3 文件**（`vi_cards.dart` / `profile_widgets.dart` / `theme.dart`）。
- `Tokens.accentButton`：**1 处（仅定义）**。
- `Tokens.glow(... radius: 28, spread: 2)`：**1 处**（完成勾）。
- `Tokens.accent` 作为正文颜色的多行写法：`today_suggestion_screen.dart:434`（3 行共用）。

---

## 10. 一句话给设计/开发

**先把"已经有了但没用"的东西用起来（渐变按钮、高光边、22 号卡片标题、紧辉光），
再处理"没有设计"的东西（空尾、首练破折号、稀疏图表、picker 右缘），
最后才谈跨端对齐。** 这一轮不需要新增设计语言，只需要把 v2 的语言执行到底。

---

## 8. 落地对照（v2.2.0，2026-11-10）

> 每条给出**落地文件**与**验收方法**；证据裁图不重出，验收靠守卫/测试 + 真机复核。
> 刻意保留项列在表末。

| 编号 | 落地文件 | 验收方法 |
|---|---|---|
| 令牌 P1 | `app/lib/core/theme.dart`（line/edgeHighlight/shadowCard/ctaGlow/hCardCta/hSecondary） | `theme_contrast_test`（line/hair、lineStrong/line 比值）+ `theme_discipline_test`（BoxShadow/Color 只许 theme） |
| `accentButton` 5 处 | `core/accent_button.dart`；首页/训练/总结/身体数据/建议页 | `accent_budget_test` 训练屏 2 / 首页 1；`log_gesture_test` 按压 0.98；`large_font_sweep` |
| Q1 / O4 首页字阶 | `today_screen.dart`（eyebrow + fsNum + fsBody + fsSub + 64） | `today_plan_test` 表头/行值；1.5×/2.0× sweep |
| Q2 / O9 picker 渐隐 | `exercise_picker_screen.dart`（ShaderMask + right s6） | `exercise_picker_test` 新增「右侧渐隐不是硬裁」 |
| Q3 / O10 橙字降噪 | `today_suggestion_screen.dart`、`routine_screen.dart`、`settings_screen.dart`、`privacy_consent_screen.dart`、`exercise_detail_screen.dart`、`cloud_backup_screen.dart` | `accent_budget_test` 跨行扫描 + 负向自检 |
| O6 首练空态 | `workout_screen.dart`（对照带单行目标 / 隐藏 last 列 / 待做留白） | `workout_flow_test`「没有历史时…」断言 `last-time`/`best-time` 不出现、`—` 为 0 |
| O5 训练屏纵向 | `workout_screen.dart`（行高 46 / 本场摘要 / Spacer / elapsedSec） | `workout_flow_test` 新增「本场摘要」；1.5×/2.0× sweep |
| O7 图表 | `vi_area_chart.dart`（网格/y 标签/稀疏高度）+ `progress_screen.dart` | `progress_test`；sweep |
| O8 进步底部 | `progress_screen.dart`（底部 +s4、PR 前 s4） | `progress_test`；真机 402×874 复核 |
| O1 高屏构图 | `today_screen.dart`（≥900 顶部 24/底部 70）、`profile_screen.dart`（≥900 +70） | `today_plan_test` 新增「高屏呼吸」；真机 440×956/402×874/360×800 |
| O11 总结/身体数据 | `workout_summary_screen.dart`（padding s6）、`body_metric_screen.dart`（标题 28） | `summary_*` / `body_metric_test`；sweep |
| O12 跨端底栏 | 本版**未改**原生底栏；保持既有 68pt / 8pt 浮起与 text2 选中 | 真机并排复核（B 阶段截图） |
| Q3 完成勾辉光 | `workout_summary_screen.dart`（18/0） | `summary_vi_test` + 截图复核 |
| 守卫 | `accent_budget_test`（跨行/括号配对）、`theme_discipline`、`typography_scale`（仍 11 级）、`spacing_grid`（图表卡 s4 例外）、`large_font_sweep`（含我页） | `./verify.sh` |

**刻意保留的差异**：
1. 首页/「我」的高屏呼吸用**显式 padding**而不是 `SliverFillRemaining` 居中：内容在
   2.0× 下会超过视口，居中方案会把滚动位置算错；审计的"≈70pt 呼吸"已满足。
2. O12 只做验证与文档，没有改 iOS 原生底栏，也没有改 Android 底栏高度/颜色 ——
   审计本身要求"不换原生"，本轮没有找到需要动的机械判据。
3. 图表 y 轴只标"0 / 当前最大"，不画完整刻度数字：数据是归一化曲线，
   多标几个数会造出"精确读数"的假象。
4. 会员/兑换仍隐藏，gate 未翻；商店截图/软著 PDF 未重出（B 阶段）。
