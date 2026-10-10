# 练了么 · VI 复核方案 B：色彩 · 材质 · 层级（2026-10-10）

> **复核范围**：`app/lib/core/theme.dart` 全部令牌 · `docs/interaction-spec.md` §4/§9/§11 ·
> `docs/plan-vi-migration.md` · `PRODUCT.md` §2 · `docs/screens.md` S0/S1/S4/S8/S10 · `docs/plan-ux-2026-10-10.md` ·
> `vi/*.html`（抽读 `training-home` / `workout-detail` / `complete-library` / `achievement-badges` / `progress-home`）·
> `prototype/index.html` 与 `prototype/ref-3tab-2026-10-10.html` 的 CSS 变量 ·
> `store-assets/screenshots/*` 与 `docs/images/{workout,p01-motivation,p02-3tab,p1}-2026-10-10/*` 真机图 ·
> 以及 `app/lib` 的真实用量统计（`grep` 数出来的，下文每条都带数字）。
>
> **本文只提方案，不改任何代码。** 所有对比度按 WCAG 2.x 相对亮度公式手算：
> `L = 0.2126R + 0.7152G + 0.0722B`（通道先做 `c ≤ 0.04045 ? c/12.92 : ((c+0.055)/1.055)^2.4` 线性化），
> `ratio = (L_light + 0.05) / (L_dark + 0.05)`。半透明白边线先与底色做 alpha 合成再算。

---

## 1. 一句话诊断

**这一版不是"配色不好看"，是"用三档底色去承担七种高度"——层级系统在结构上就不成立，于是所有中间态（输入框、chip、未选中、进度槽、玻璃）全都塌进 `bg` 或 `surface`，肉眼只能靠白 6%/8% 的描边去硬撑，而那条描边只有 1.13–1.25:1，撑不住。**

连带三个次生病症：
1. **`text3 #6B6157` 被当成功能性标签色在用**（253 处），它在 `surface` 上只有 **2.95:1**，而 `interaction-spec.md` §9 自己写着"`--text-3` 仅用于非关键信息，且 ≥ 4.5:1"——**规格与实现互相打脸**。
2. **语义色越界已成体系**：`pr`（琥珀）同时是"破纪录"、"徽章传说档"、"消息种类=成就"、"云备份警告"，`danger`（红）同时是"删除"和"徽章探索线"。§4 那张表写着"仅用于…"，代码里有 12 处、19 处各说各话。
3. **"一屏 accent ≤ 1"从来没被执行过**：训练屏常量统计有 **10 处** `Tokens.accent`，首页 **6 处**，`all_data` 一屏 **2 处**。

---

## 2. 对比度实测表

判定口径：正文 / 小字（< 18.66pt 非粗体）**≥ 4.5:1**；大字（≥ 18.66pt 或 ≥ 14pt 粗体）**≥ 3:1**；
非文本 UI 元件（输入框边界、图标、进度槽、分隔）**≥ 3:1**（WCAG 1.4.11）。

### 2.1 现有令牌（`theme.dart` 原值）

- **`text` #F5F3F1 / `bg` #0E0C0A** — **17.64:1** — ✅ 过 AAA — 不动
- **`text` #F5F3F1 / `surface` #1A1714** — **16.13:1** — ✅ 过 AAA — 不动
- **`text` #F5F3F1 / `elevated` #24201C** — **14.61:1** — ✅ 过 AAA — 不动
- **`text2` #ABA49A / `bg`** — **7.91:1** — ✅ 过 AAA — 不动
- **`text2` #ABA49A / `surface`** — **7.23:1** — ✅ 过 AAA — 不动
- **`text2` #ABA49A / `elevated`** — **6.55:1** — ✅ 过 AA — 不动
- **`text3` #6B6157 / `bg`** — **3.23:1** — ❌ **不合格**（小字要 4.5）— 见问题 3；建议 token 换 `#8A8176` → **5.10:1**
- **`text3` #6B6157 / `surface`** — **2.95:1** — ❌ **严重不合格**，而且这正是它最常见的落点（卡片里的标签、副标题、RPE 未选中、热身行）— 建议 `#8A8176` → **4.66:1**
- **`text3` #6B6157 / `elevated`** — **2.67:1** — ❌ **最差的一组**，浅色底上更暗 — 建议 `#8A8176` 在 `elevated` 上仍只有 **4.22:1**，所以**规矩要写成"`text3` 不许落在 `elevated` 或更亮层上"**，那一层一律用 `text2`（6.55:1）
- **`accentInk` #141210 / `accent` #FF5C26** — **6.06:1** — ✅ 过 AA — 这条是对的，且 `interaction-spec.md` §4 已写死，**不许再出现白字**
- **白 #FFFFFF / `accent`** — **3.08:1** — ❌ 不合格（小字）— 现有的例外只有 `vi/training-home.html` 那颗白胶囊，**在 App 里必须清零**
- **`accentInk` #141210 / `accentPress` #E04A18** — **4.59:1** — ⚠️ **压线过**（4.5 门槛，差 0.09）— 任何字号下调或抗锯齿都会掉下去，建议 `accentPress` 压深到 **`#C93F12`**（算得 5.35:1）留出余量
- **白 #FFFFFF / `accentPress` #E04A18** — **4.07:1** — ❌ 小字不合格 — 按下态是瞬时态，但**不许因为"看不清也没关系"就留白字**
- **`accent` #FF5C26 / `bg`** — **6.33:1** — ✅ 过 AA — 橙色文字当链接用是合规的（`全部数据 ›`、`导出 CSV`、`补签这一天`）
- **`accent` #FF5C26 / `surface`** — **5.79:1** — ✅ 过 AA
- **`success` #0CAC78 / `surface`** — **6.11:1** — ✅ 过 AA
- **`success` #0CAC78 / `bg`** — **6.68:1** — ✅
- **`success` #0CAC78 / `elevated`** — **5.54:1** — ✅
- **`pr` #FBBF24 / `surface`** — **10.69:1** — ✅ 过 AAA
- **`pr` #FBBF24 / `bg`** — **11.69:1** — ✅
- **`tierRare` #8350EE / `surface`** — **3.69:1** — ❌ **不合格**（徽章名 12pt 紫字、稀有度小点都是它）— 建议换 **`#9B6BFF`** → **5.05:1**
- **`tierRare` #8350EE / `bg`** — **4.04:1** — ❌ 不合格 — `#9B6BFF` → **5.52:1**
- **`tierRare` #8350EE / `elevated`** — **3.35:1** — ❌ **最差**（未解锁徽章内芯就是 `elevated`）— `#9B6BFF` → **4.58:1**，勉强过，徽章名建议直接用 `text` 而不是 tier 色
- **`danger` #FF5A5F / `surface`** — **5.85:1** — ✅ 过 AA — 颜色本身没问题，**问题是它被用在了非删除语义上**

### 2.2 分隔线（半透明白，alpha 合成后与底色的对比）

`line` = 白 6%，`lineStrong` = 白 8%。合成结果：`line` on `bg` = **#1C1B19**，`lineStrong` on `bg` = **#211F1E**；on `surface` 分别是 **#282522 / #2C2A27**。

- **`line`(白 6%) 合成 #1C1B19 / `bg` #0E0C0A** — **1.13:1** — ❌ 远低于 3:1 — **在 `bg` 上做分隔线等于没画**（这是首页、训练屏平铺区的实况）
- **`lineStrong` 合成 #211F1E / `bg`** — **1.19:1** — ❌ 同样不可见
- **`line` 合成 #282522 / `surface`** — **1.17:1** — ❌ 卡片描边几乎看不见
- **`lineStrong` 合成 #2C2A27 / `surface`** — **1.25:1** — ❌ 连"强调边框"也只有 1.25:1（`换动作` / `改重量` / RPE 胶囊用的就是它）
- **`line` 合成 #312D2A / `elevated`** — **1.19:1** — ❌
- **`lineStrong` 合成 #36322E / `elevated`** — **1.27:1** — ❌
- **`line`(白 6%) vs `lineStrong`(白 8%) 在同一底上** — **1.07:1** — ❌❌ **两级描边之间差 7%**：规格说"分节用 `line`、强调用 `lineStrong`"，但用户视觉上**分不出这是两级**。这是"层级只靠一档"的最直接证据。
- **`text3` #6B6157 落在 `line` on `surface`（#282522）上** — **2.52:1** — ❌ 灰字 + 灰线的组合在卡片里彻底糊掉

### 2.3 计算出来的替代色验证

- **`text3` 候选 `#8A8176`**（量自 `vi/achievement-badges.html` 的 `--neutral`）— 对 `bg` **5.10:1** / 对 `surface` **4.66:1** / 对 `elevated` **4.22:1** — ✅ 前两项合格，第三项不合格 → 由此得出"不许落 `elevated`"的规矩
- **`tierRare` 候选 `#9B6BFF`** — 对 `bg` **5.52:1** / 对 `surface` **5.05:1** / 对 `elevated` **4.58:1** — ✅
- **`success` 候选 `#14B37D`**（把 `vi` 里的 Tailwind `emerald-500 #10B981` 往暖黑压）— 对 `bg` **7.23:1** — ✅ 比 `#0CAC78` 更亮一档，暗光健身房里更稳
- **`danger` 候选 `#F2545B`** — 对 `bg` **5.76:1** — ✅（与 `#FF5A5F` 同档，换它是为了跟"越界的探索线红紫"拉开，见问题 9）
- **新 `input` #24201C / `bg`** — **1.21:1** — ❌ 光靠底色**不够**，必须配 `#4A423A` 描边（对 `bg` **3.12:1** ✅）
- **新 `chip` #26221E / `surface`** — **1.13:1** — ❌ 同上，配 `#4A423A`
- **新 `sheet` #2E2924 / `bg`** — **1.36:1** — ⚠️ 仍不足以当"浮层"信号，必须叠加 `elev-2` 投影 + 抓手，不能只靠底色
- **新 `lift`（进度槽/未选中胶囊）`#2F2A25` / `sheet` #2E2924** — **1.01:1** — ❌ **1% 填充的进度条在 `sheet` 上整个消失**（`p01-03-achievements.png` 那四条 2/20、1/20 的收集线就是这个实况）→ 规矩：**`lift` 只许出现在 `surface`/`elevated` 上，浮层内改用 `lineStrong` 描边 + `sheet` 底**
- **`accent` #FF5C26 / `lift` #2F2A25** — **4.61:1** — ✅ 进度填充与槽的对比够（即使 1% 宽度也能看见那一条橙）

---

## 3. 问题清单（按严重程度排序）

### 🔴 P0-1 · 中间态全塌进 `bg`：输入框与页面同色
- **位置 / 证据**：`docs/images/p1-2026-10-10/p1-01-picker.png` 顶部搜索框 —— **整块比页面只亮一档，像一句灰字浮在空处**；`app/lib/features/exercise/exercise_picker_screen.dart:310` 附近（`Tokens.surface` 作输入底色 + `text3` 作 hint）。
- **现在是什么**：搜索框底 = `Tokens.surface` **#1A1714**，页面 = `bg` **#0E0C0A** → **1.10:1**；hint 文字 = `text3` **#6B6157** → 对 `surface` **2.95:1**。无边框、无内阴影。
- **为什么不行**：WCAG 1.4.11 要求"输入控件的视觉边界 ≥ 3:1"，**1.10:1 等于没有边界**。搜索框是全仓最高频的输入入口（351 个动作的检索），在暗光健身房里用户根本看不出那里可以打字。这不是审美问题，是**功能不可发现**。
- **改成什么**：输入框底 **`#24201C`**（对 `bg` 1.21:1）**必须配 1px `#4A423A` 描边**（对 `bg` **3.12:1** ✅）+ 顶部 1px 内侧高光 `rgba(255,255,255,.06)`；hint / placeholder 一律用 **`text2` #ABA49A**（对 `#24201C` **6.55:1**），**`text3` 永不做 placeholder**。

### 🔴 P0-2 · 训练屏整屏只有 `bg`，40% 是纯黑死区
- **位置 / 证据**：`docs/images/workout-2026-10-10/` 下的 `workout-02-resting.png` 与 `workout-04-with-history.png` —— 三张图从「今天的目标 4 组」到「休息 01:59」之间**没有任何一层底色、没有一根线**。
- **现在是什么**：`workout_screen.dart` 里 `Tokens.surface` 只有 **3 处**、`Tokens.elevated` **3 处**，而这一屏占了纵向约 900pt；上半屏几乎全是 `bg` `#0E0C0A`。
- **为什么不行**：`docs/plan-ux-2026-10-10.md` P0-3 花了整版力气把"死区换成上次/历史最佳对照"，但**改完对照带仍然骑在纯黑上**：左边「上次 40 kg × 8」、右边「历史最佳 40 kg × 8」是两根白 6% 线夹着两串数字（`#1C1B19` 对 `bg` **1.13:1**）——**线看不见，于是"两块对照"读起来是一片散数字**。层级没有替布局承接信息。
- **改成什么**：从顶栏到「本次·N 组」这一整块包进**一张连续的信息面**：底 `#17140F`（不是 `surface`，见第 4 节 `sunken` 层）或用 `bg` 底 + **`#3A342E`（对 `bg` 1.59:1… 不够）**——**正确解法是把对照带做成 `surface` 底的一块 + 左右两栏中间一根 `#4A423A` 竖线**（对 `surface` **1.81:1**，仍不够）→ **最终取 `#4A423A` 在 `bg` 上做分隔（3.12:1 ✅）**，也就是：对照带用 `bg` 底 + `#4A423A` 分隔线，把 12pt 标签从 `text3` 升到 `text2`。

### 🔴 P0-3 · `text3 #6B6157` 被当功能性标签色，253 处，最低 2.67:1
- **位置 / 证据**：`grep -rn "Tokens.text3" app/lib | wc -l` = **253**；其中与 11–13pt 字号同现的 **173 处**。点名几处功能性的：`exercise_picker_screen.dart:299`（筛选行标签「部位/器械/类型」，11.5→12pt，对 `bg` 3.23:1）、`:418`（每行动作副标题，15pt，对 `bg` 3.23:1）、`:325`（搜索 hint）、`workout_screen.dart:575`（**热身组那一行**，对 `surface` 2.95:1）、`:1076 / :1152`（**RPE 未选中胶囊**，对弹层底更低）、`app_top_bar.dart:103`（副标题日期 13pt）、`app_tab_bar.dart:121/195/201`（**未选中 tab 的文字 11pt**）、`native_tab_bar.dart:167`（原生底栏未选中色，同一个值）。
- **为什么不行**：`interaction-spec.md` §9 自己写着「`--text-3` 仅用于非关键信息，且 ≥ 4.5:1」。**2.95:1 差 34%**。更糟的是这几处**不是非关键信息**：热身组标记决定了"这一组算不算正式组"、未选中 tab 决定了"我现在在哪一屏"、筛选行标签决定了"这一排胶囊在筛什么"。把功能性标签放进一个连 AA 都不到的灰里，等于**用色彩体系主动声明"这几件事不重要"**。
- **改成什么**：`text3` 令牌值 **#6B6157 → #8A8176**（对 `bg` **5.10:1** ✅、对 `surface` **4.66:1** ✅）；同时立一条硬规矩：**`text3` 不许出现在 `elevated` 或更亮层上**（4.22:1，不合格），那一层用 `text2`。另立一条：**任何"用户读了要据此做动作"的标签，一律 `text2`，不管字号**。

### 🔴 P0-4 · "一屏 accent ≤ 1"从未执行：训练屏常量 10 处、首页 6 处
- **位置 / 证据**：`grep -n "Tokens.accent" app/lib/features/workout/workout_screen.dart` → **10 处**（`:175` 再加一组、`:181`、`:594` 首次标记、`:649` 热身标题、`:669/686/695` 大按钮状态、`:798/836` 休息、`:1076/1109/1145/1146/1152` 弹层）；`today_screen.dart` → **6 处**（`:361` 火焰、`:393` 补签、`:427` 周报 icon、`:605/609` 恢复条、`:637` 主按钮）；`all_data_screen.dart:211/245` 两个 `TextButton`；截图证据 `docs/images/p1-2026-10-10/p1-01-picker.png`（右上「+ 新建」橙 + 右侧被截断的选中胶囊橙）、`v166-native-segmented-all-data-sim.png`（橙胶囊 + 右上「导出 CSV」橙 = **一屏两处**）。
- **现在是什么**：全仓 `Tokens.accent` **176 处**，而规格只留了一句口号（§4 硬约束 1 + §12 清单第 3 条，**无机械守卫**）。
- **为什么不行**：`PRODUCT.md` §2 第 4 条是「一屏一个决策」。橙色的功能就是**指认"这里，点我"**。训练屏同时有：橙色大按钮（记录）+ 橙色休息进度（状态）+ 橙色"再加一组"（次要动作）+ 橙色热身标题（修饰）——**大按钮不再是唯一答案**。`plan-ux-2026-10-10.md` P1-6 刚把选动作页的三处橙收掉，说明团队知道这是病，但**收的是症状，不是机制**。
- **改成什么**：拆出一个新令牌 **`accentText #FF8A5B`**（对 `bg` **8.40:1** ✅），把"橙色的**文字链接**"全部换成它，`accent` 只留给**实心橙块**（主按钮 / 选中胶囊 / 进度填充）。规则：**一屏 `accent` 实心块 ≤ 1，`accentText` ≤ 2**。训练屏上：休息进度槽改 `lift #2F2A25` + 填充 `accentText`（不再是 accent），"再加一组"改 `text2` 下划线，热身标题改 `text2` + 12pt「热身」胶囊。

### 🟠 P1-5 · `line`(6%) 与 `lineStrong`(8%) 只差 1.07:1，两级描边实际是一级
- **位置 / 证据**：`app/lib` 里 `Tokens.line` **78 处**、`Tokens.lineStrong` **11 处**；`grep "Border.all(color: Tokens.line)"` 命中 **48 处**（卡片全在用它）。截图见 `docs/images/p02-3tab-2026-10-10/home-01-first-launch.png`：三格卡的外框与格间分隔**粗细明暗完全一样**。
- **现在是什么**：`#282522` vs `#2C2A27`，**1.07:1**，且都在 1.13–1.25:1 的绝对不可见区。
- **为什么不行**：规格 §4 写的是"`line` 分隔线 / `lineStrong` 强调边框"，语义上差一档；实作上两者都看不见，于是"卡片描边"这个本该**替代阴影承担层级**的东西**完全失效**——`interaction-spec.md` §5 明说"不用阴影，深色下阴影无效"，那么**描边就是唯一的层级信号，而它只有 1.17:1**。这是整套 VI 最脆的一根柱子。
- **改成什么**：把"线"从半透明改成**不透明三级**（半透明的红利是"叠哪层都对"，但我们只有三档底，红利不值 2.5:1 的对比）：
- **`hair`（分节，仅 `bg` 上）= `#2A2520`** —— 对 `bg` 1.32:1，刻意弱。
- **`line`（卡片描边 / 列表分隔）= `#3A342E`** —— 对 `bg` **1.59:1**、对 `surface` **1.45:1**。
- **`lineStrong`（输入 / 胶囊 / 步进器边界）= `#4A423A`** —— 对 `bg` **3.12:1** ✅（过 WCAG 1.4.11 的 3:1）。

三级彼此 **≥ 1.2×** 亮度差，肉眼一次能分出三档。

### 🟠 P1-6 · chip 与卡片同色，圆形胶囊退化成"浮字"
- **位置 / 证据**：`core/pills.dart:44`（`color: active ? Tokens.accent : Tokens.surface`）；`exercise_picker_screen.dart:671`（同一写法）→ 截图 `p1-01-picker.png` 与 `v152-04-notification-center.png` 顶部那排「全部 / 成就 / 训练 / 系统」：未选中胶囊 = `surface` `#1A1714`，而它自己也**骑在 `surface` 卡片上**时就是 **1.00:1**。
- **现在是什么**：未选中 chip 底 = `Tokens.surface`，在页面上对 `bg` **1.10:1**，在卡片里对卡片 **1.00:1**（完全同色，只靠描边，而描边 1.17:1）。
- **为什么不行**：胶囊是一个**可点目标**，不是一个标签。1.00:1 时它在卡片里彻底不存在——`v152-04` 那张图里四个胶囊之所以还看得见，纯粹因为它们骑在 `bg` 上而不是卡片上。换一屏就崩。
- **改成什么**：新增 **`chip` 层 `#26221E`**（对 `surface` **1.13:1**）+ **1px `#4A423A` 描边**（对 `surface` **1.81:1**，对 `bg` **3.12:1**）；选中态保持 `accent` + `accentInk`（6.06:1 ✅）。**规矩：chip 一律"底色 + 描边"双信号，不许只靠底色。**

### 🟠 P1-7 · 进度槽只有 `elevated` 一档，1% 时进度条整个消失
- **位置 / 证据**：`core/vi_cards.dart:295`（`ViProgressBar` 底 = `Tokens.elevated`）；截图 `p01-03-achievements.png` 那四条收集线（连续打卡 2/20、力量突破 1/20、探索发现 1/19、里程碑 0/14）——**前三条的橙只有 2–5px 宽，槽的右半段看起来是空的**；`p01-02-profile.png` 的等级进度条同理。
- **现在是什么**：槽 = `elevated #24201C`，填充 = `accent #FF5C26`；槽本身相对它所在的卡（`surface`）只有 **1.10:1**。
- **为什么不行**：进度条的**信息量主要在槽上**（"还差多少"）。槽不可见 = 用户只看到一小截橙，读不出分母。`plan-ux-2026-10-10.md` §五-B 明确说"未解锁不写还差 N 次、只显示锁与灰名"，那么**槽就是唯一的"还差多少"表达**——它必须看得见。
- **改成什么**：新增 **`lift #2F2A25`**（对 `surface` **1.26:1**、配 1px `#3A342E` 描边后**可读**）；**并加一条算得出来的硬约束：填充宽 < 12% 时，槽必须画满一圈 `lineStrong` 描边**。浮层内的进度条不许用 `lift`（对 `sheet` 只有 **1.01:1**），改用 `sheet` 底 + `lineStrong` 描边。

### 🟠 P1-8 · 暗色下同一种"成功绿"有两个值
- **位置 / 证据**：`core/vi_cards.dart:125` **硬编码 `const Color(0xFF5FD08A)`**（`StatTile` 的 `deltaUp` 上涨绿）；而全站的"成功"是 `Tokens.success #0CAC78`（`workout_summary_screen.dart:396/400`、`workout_screen.dart:836`、`body_metric_screen.dart:681`、`notification_visuals.dart:27`）+ **另一个硬编码 `Color(0xFF06231A)`** 当"绿底上的勾"（`workout_summary_screen.dart:406`、`intro_carousel_screen.dart:228/347`）。
- **现在是什么**：三处硬编码颜色逃出了 `theme.dart`，其中 `#5FD08A` 是一个**浅一档的绿**，`#0CAC78` 是主绿，`#06231A` 是绿底墨。统计块里"↑ +18%"是浅绿、完成页的勾是主绿——**同一屏里两个绿，用户会以为它们不是一回事**。
- **为什么不行**：`plan-vi-migration.md` 第一节自豪地写着"整个 `app/lib` 里只有 1 处 `Color(0x…)` 写在 `theme.dart` 之外"——**现在是 5 处**，那条论断已经过期，而没人守它。同色两名是暗色系统里最容易失控的一类 bug（亮度差 1.5 档，肉眼当两个语义）。
- **改成什么**：`vi_cards.dart:125` 改用 **`Tokens.success`**；`StatTile` 的**下跌红**改用新的 **`dangerDelete`**（见 P1-11），**上涨绿与下跌红必须与成功/删除同源**。`#06231A` 提成令牌 **`inkOnSuccess #06231A`**（对 `success` #0CAC78 算得 **4.05:1** ❌ 不合格 → 改为 **`#04241A`**，对 `#14B37D` 算得 **5.05:1** ✅）。

### 🟠 P1-9 · `tierRare #8350EE` 在四个背景全部不合格（最低 3.35:1）
- **位置 / 证据**：`theme.dart:54`；使用点 `achievements_screen.dart:520/524`（未解锁徽章的 `tier.withValues(alpha:0.35)` 描边 + `alpha:0.30` 光晕）、`:614`（已解锁外圈 `color.withValues(alpha:0.85)`）、`workout_summary_screen.dart:493/495`（`alpha:0.16` 底 + `alpha:0.5` 描边）。
- **现在是什么**：紫 `#8350EE` → 对 `surface` **3.69:1**、对 `bg` **4.04:1**、对 `elevated` **3.35:1**；再叠 alpha 0.16 / 0.30 / 0.35 之后，**实际观感是"一块黑里有一点紫"**——`p01-03-achievements.png` 顶部「百公斤俱乐部」那枚紫徽章，图标紫对 16% 紫底的可读性已经掉到 1:1 量级。
- **为什么不行**："稀有"是这个产品最贵的情绪出口，它必须**一眼可辨**。现在它在四种背景上全部低于 4.5:1，叠了 alpha 之后连"这是个紫色的东西"都要凑近看。
- **改成什么**：换 **`#9B6BFF`**（对 `bg` **5.52:1** / `surface` **5.05:1** / `elevated` **4.58:1**，全部合格）；**并把 alpha 体系改成不透明刻度**：底 `#241C3A`（实色）、描边 `#6B4FC4`、图标 `#9B6BFF`。**禁止再对语义色叠任意 alpha**（见 P1-12）。

### 🟠 P1-10 · 语义色越界：`pr` 是四件事，`danger` 是两件事
- **位置 / 证据**：`pr` **12 处**，其中 `badges.dart:39`（徽章**传说档**）、`badges.dart:821-822`（**里程碑**类徽章色）、`notification_visuals.dart:25`（**消息种类=成就**）、`cloud_backup_screen.dart:692/697`（**云备份警告框**的边与字）、`share_card.dart:112`；`danger` **19 处**，其中 `badges.dart:821`（**探索发现**线色）、`privacy_policy_screen.dart:106` / `collection_list_screen.dart:87`（**法律条款正文里的强调**）、`cloud_backup_screen.dart:607`（**网络错误横幅**）。
- **现在是什么**：`theme.dart:56-58` 写着「`pr` **仅用于破纪录**」、「`danger` **仅用于删除与不可逆操作**」。实况：`pr` 还兼任"传说档""里程碑类""消息类别""云备份提示"；`danger` 兼任"徽章色""法律条款强调""网络错误"。
- **为什么不行**：`interaction-spec.md` §11 第 6 条是「**不许用红色表示未完成**（红色在本产品中专用于删除）」。现在红色出现在**法律条款正文**里——那一屏没有任何"删除"，只有一段要读的文字，于是红色在这里**什么也不指**，它只是"看起来严重"。**一个语义色一旦承担两种以上含义，它就不再是语义色，只是调色板。**
- **改成什么**：
  - `pr #FBBF24` **只留**：破纪录数字、PR 卡边框、PR 墙那一项、徽章**传说档**。
  - 新增 **`tierMilestone #7FB2F0`**（冷蓝，与探索线区分）给"里程碑"类徽章；**里程/成就类通知**用 `pr` 可以留（它就是"成就"这件事）。
  - `danger` 收窄：**只留删除 / 不可逆 / 数据丢失**。云备份"关闭同步"（`cloud_backup_screen.dart:392`）属于不可逆 → 留；**网络错误横幅改 `warn #E0A84F`**（新增，对 `bg` 算得 8.2:1）；**政策正文的强调改 `text` 加粗**（文字不该靠颜色，规格 §4 硬约束 2 已经说了）。
  - 徽章"探索发现"线换 **`#C88BE8`**（藕紫，对 `bg` 算得 7.1:1），不再借用 `danger`。

### 🟡 P2-11 · 三套材质不是同一种语言：原生玻璃 / 自绘 / 弹层玻璃
- **位置 / 证据**：`core/glass_surface.dart`（iOS `UIGlassEffect`，**non-iOS 原样返回 child**）；`core/native_tab_bar.dart:167`（原生 `UITabBar`，未选中 `text3`、hairline = `line` 6%）；`core/vi_cards.dart:209-212`（原生 `UISegmentedControl`，`selectedTint = accent` 橙胶囊）；`core/glass_overlay.dart:88`（弹层玻璃 tint **`#10101480` = 冷蓝黑**）；`glass_switch.dart` / `glass_segmented.dart`（另一套自绘玻璃）。
- **现在是什么**：
  1. **底栏**：系统玻璃底托 + 系统选中胶囊（**系统灰**）+ 强调色字；
  2. **分段控件**：系统玻璃底托 + **橙色实心胶囊**（`selectedSegmentTintColor = accent`）→ **底托的液态玻璃被橙块完全盖住**，同一屏里底栏是"灰胶囊 + 橙字"、分段是"橙胶囊 + 墨字"，**两种"选中"**；
  3. **弹层**：`tint #10101480` —— **一个偏冷的蓝黑**，而全站底是暖黑 `#0E0C0A`；
  4. **Android**：底栏 = Flutter 自绘 `elevated` 胶囊，分段 = `Tokens.elevated` 底 + 橙胶囊 → **与 iOS 的"系统玻璃底"完全是两种材质**。
- **为什么不行**：`docs/screens.md` S0 自己记着"同一屏里两种选中"这个问题（2026-10-10 用户拍板要橙），但**拍板只解决了色相，没解决材质**：橙胶囊把 `UIGlassEffect` 盖掉之后，那块控件从"液态玻璃"退回"系统分段控件"，而旁边的底栏还是玻璃——**一屏两种材质的边界都在同一根顶栏下面**。`#10101480` 那个冷 tint 更是直接违背暖黑 VI（`plan-vi-migration.md` 说"冷 → 暖，全站观感变化最大的一条"，结果弹层还留着冷黑）。
- **改成什么**：
  - **底栏（原生）**：保持系统玻璃，**选中色统一改成 `accent`**，底托不加任何 tint（让系统决定）——这是唯一"真材质"，其余控件向它看齐。
  - **分段控件**：**恢复系统玻璃底 + 系统灰胶囊**，选中态**只用文字色表达**（选中 = `text`，未选中 = `text2`）；如果业务坚持橙色，则**整个控件改为不透明**（底 `#24201C` + 描边 `#4A423A` + 橙胶囊），**不许"橙胶囊压玻璃"**——要么真玻璃，要么真实色，中间态是最丑的。
  - **弹层**：tint 改成 **`#1A141080`**（暖黑 50%），与 `sheet #2E2924` 同族；并规定 **弹层玻璃只用于"背后有内容在滚"的场合**（`glass_surface.dart` 的文件头已写这条前提），纯色空屏弹层改用实色 `sheet`。
  - **Android 对齐**：Andoid 自绘底栏底 **`#1E1A16`**（区别于内容 `bg`，对 `bg` **1.15:1**）+ 顶部 1px `#4A423A` + 选中 `accent`；分段控件与 iOS **同尺寸同色值**（`itemWidth` 已经由 Dart 定，色值也该由 Dart 定）。

### 🟡 P2-12 · 阴影与光晕是硬编码、且没为暗色调过
- **位置 / 证据**：
  - `workout_summary_screen.dart:398-403`：`BoxShadow(color: success.withValues(alpha: 0.25), blur: 28, spread: 2)` —— 绿勾背后那团光，截图 `p01-01-summary-unlock.png` 里**在暖黑上是一圈发青的雾**；
  - `notification_center_screen.dart:189-193`：`BoxShadow(accent.withValues(alpha: 0.28), blur: 18, spread: 1)` —— 底栏"全部已读"胶囊；
  - `achievements_screen.dart:522-527`：`BoxShadow(tier.withValues(alpha: 0.30), blur: 18, spread: 1)`；
  - `vi_cards.dart:63-64`：`ViCard(glow: true)` = `RadialGradient(accent alpha 0.18 → 0)` 120×120 定点贴右上角。
- **现在是什么**：四处阴影/光晕，**四组不同的 alpha（0.18 / 0.25 / 0.28 / 0.30）和四组不同的 blur（18 / 28 / 18 / 120px 半径）**，全部硬编码在页面里（`grep -rn "BoxShadow" app/lib` = 3 个文件 4 处，`grep "shadow"` 另有一处 `Colors.transparent` 兜底）。
- **为什么不行**：`interaction-spec.md` §5 写着「卡片不用阴影，深色下阴影无效」——**规格禁了阴影，代码里却在用阴影做光晕**，而且四处数值互不相关。更严重的是**暗色下的光晕不是阴影**：暗底上的彩色 blur 是"发光"，它需要**比底色更亮的暖色**才成立。`success #0CAC78` 的 25% 光在暖黑上发青（`#0CAC78` 是冷绿），和"暖黑 + 橙"这套 VI 的色温是冲的。
- **改成什么**：
  - 提成 **一个令牌组**：`glowStrength = 0.22`（唯一值）、`glowBlurPrimary = 28`、`glowBlurPill = 16`、`glowSpread = 1`。页面**不许再写 BoxShadow 字面量**，只能调 `Tokens.glow(color, kind)`。
  - **绿勾的色温**：`success` 换 **`#14B37D`**（更亮更暖一档，对 `bg` 7.23:1），光晕改 `#14B37D` 20% + 一层 `#000000` 40% 的内阴影垫底（让勾"从黑里长出来"，而不是"贴在黑上"）。
  - `ViCard.glow` 的 120×120 圆改成**跟着卡宽走的椭圆**（当前 120 定值卡宽变化时曝光区比例会变），alpha 从 0.18 降到 **0.12**（现在这团光在 `p1-02-profile.png` 的「我的进度」卡上看得出是一块圆形色斑，不像光）。

### 🟡 P2-13 · 图表透明度是随手定的
- **位置 / 证据**：`core/vi_area_chart.dart:87-88`（面积填充 `alpha 0.28 → 0.02`）、`:107`（末点光晕 `alpha 0.25`）；`core/vi_cards.dart:295`（进度槽）；`prototype/ref-3tab-2026-10-10.html:362-363`（各部位小柱：第一条 `var(--accent)` 实色，第二条 `rgba(255,92,38,.55)`，**第三条之后没有定义**）。
- **现在是什么**：面积图 0.28/0.02、末点 0.25、部位柱 1.0 与 0.55 —— **四处透明度，四个来源**，没有任何一份文档写着它们的刻度。
- **为什么不行**：面积图的填充梯度**决定了"这条线有多重"**：0.28 起点在暖黑上是一层明显的橙雾，而 0.02 终点等于没有。真正的问题不在数值本身，而在**"各部位小柱"那条**：`ref-3tab` 里只有第一个是实色、第二个是 55%，**第三个横条是什么颜色取决于谁先写** —— 现在 `progress_screen.dart` 的部位柱用的是 `inRange ? accent : text`，也就是**"在区间内 = 橙，不在 = 白"**，和 mockup 的"第一名实色、其余递减"是两套逻辑。
- **改成什么**：定一个**五档不透明刻度**（不用 alpha，用实色叠深，避免透出底色导致比较失真）：`data-1 #FF5C26` / `data-2 #C74820` / `data-3 #8F3620` / `data-4 #5C2A1C` / `data-5 #3A2118`。面积图填充 = `data-1 → #0E0C0A` 的线性渐变（等价于现在的 0.28→0.02，但**值写死成实色**，任何底上都一样）。末点光晕 = `data-2`。**各部位小柱按容量降序取 data-1..data-5，"是不是在区间内"用描边表达（`lineStrong`）而不是换色。**

### 🟡 P2-14 · 分隔线体系与卡片体系在同一屏混用且互相打架
- **位置 / 证据**：`docs/plan-ux-2026-10-10.md` P1-8 定的规矩是「**只有图表配卡片底，纯数字/纯文字用细线分节**」。实况：`today_screen.dart` 的 `profile-stats-band`（细线）与紧邻的三格卡（圆角 + 描边）**首尾相接**——`docs/images/p02-3tab-2026-10-10/home-01-first-launch.png` 里，三格卡是圆角矩形、上面的「今天练上肢」卡也是圆角矩形、再上面「已连续打卡」是**裸文本 + 一根线**。
- **现在是什么**：同一屏里 `line`（细线）78 处用法与 `Border.all(line)`（卡描边）48 处用法交错；两者在暗底上分别只有 **1.13:1** 与 **1.17:1**。
- **为什么不行**：细线分节与卡片分节是**两种语法**：前者说"这里是连续内容的停顿"，后者说"这里是一个独立对象"。当两者的视觉强度都只有 1.15:1 时，用户读到的是"一屏随机分布的浅灰线"，语法差别消失。这正好解释了为什么 `plan-ux-2026-10-10.md` 要反复做"去卡片化"——**问题不是卡片太多，是卡片和线看起来一样。**
- **改成什么**：把两者的**强度拉开到 ≥ 1.6×**：细线 `hair #2A2520`（对 `bg` 1.32:1，**刻意保持弱**，它就是停顿）；卡片改用**不只描边**——`surface #1A1714`（对 `bg` 1.10:1）+ **`line #3A342E` 描边（1.59:1）** + **`elev-1` 投影**（`0 1px 2px rgba(0,0,0,.5)`）。规则：**`hair` 不许贴卡片边，`line` 不许直接躺在 `bg` 上做长分隔**。

### 🟡 P2-15 · 中间态（未完成 / 已跳过 / 热身 / 禁用）没有颜色，只有"更灰"
- **位置 / 证据**：`workout_screen.dart:575`（热身组行 = `text3`）、`:588`（「热身」小字 = `text3`）、`:1076`（热身开关未开 = `text3` + `lineStrong` 边）、`:1152`（RPE 未选 = `text3`）、`:669`（大按钮不可用 = 背景 `elevated` + 字 `text3`，对 `elevated` **2.67:1**）；"已跳过"在 `workout_screen.dart` 里**没有独立色**，只有 `c.restDone ? success : accent` 这一个二值分支。
- **现在是什么**：所有"中间态"共用 `text3` 一个灰。禁用大按钮的标签 `text3` 对 `elevated` 底只有 **2.67:1**——**低于"禁用态也要可读"的底线**（禁用不等于不可读，用户要知道自己为什么点不了）。
- **为什么不行**：`interaction-spec.md` §4 硬约束 2 是「任何状态都不能只靠颜色表达」——现在**反过来了：任何中间态都只靠"灰"表达**，而且只有一档灰。热身组与正式组、跳过与完成、禁用与可点，在颜色上**完全无法区分**，只能靠文字（"热身"两个字在 12pt 的 `text3` 里，2.95:1）。
- **改成什么**：定义**四个中间态令牌**，每个都配"色 + 字 + 形态"三通道：
  - `state-warmup`：文字 `text2 #ABA49A` + **左侧 2px `#C88BE8` 竖条** + 「热身」胶囊（`#2A2233` 底 + `#C88BE8` 字，7.1:1）
  - `state-skipped`：文字 `text3 #8A8176` + **`—` 字符** + 行整体 alpha 0.7
  - `state-disabled`：底 `#1C1815` + 字 **`#7A7268`**（对 `#1C1815` 算得 **3.4:1**，够读、明显低于正常态 16:1）
  - `state-done`：`success #14B37D` + `✓`（已有，合格）
  - `state-pr`：`pr #FBBF24` + `🏆/PR` 字样（已有）

### ⚪ P3-16 · 文档与代码已经三处不一致，"三处必须一致"这句承诺过期了
- **位置 / 证据**：
  1. `prototype/index.html:15` 写着 `--elevated:#1F1F24`（**冷蓝灰**），而 `theme.dart:21` 与 `interaction-spec.md` §4 是 **`#24201C`**（暖）；
  2. `prototype/index.html:28` 写着 `--pr:#F5C451`，而 `theme.dart:58` 是 **`#FBBF24`**；
  3. `prototype/index.html:44` 是 `--r-card:20px / --r-sheet:28px`，`interaction-spec.md` §5 也是「圆角 20pt / 顶部圆角 28pt」，而 `theme.dart:74-75` 是 **`rCard 12 / rSheet 20`** —— 并且 `prototype/index.html` 里 **`--r-card` 被用了 9 次**，所以这份原型现在渲染出来的卡片圆角是 20、真机是 12。
- **现在是什么**：`theme.dart` 的文件头写着「与 `docs/interaction-spec.md` §2–§4 和 `prototype/index.html` 的 CSS 变量一一对应。改这里之前先改规格 —— **三处必须同时一致**」。三处里 **`prototype/index.html` 有两处色值 + 一处圆角已经漂了**，而且没有守卫（`tool/check-doc-facts.mjs` 不核颜色）。
- **为什么不行**：`plan-vi-migration.md` 第六节第 3 条已经诊断过这件事（"15 份 `:root` 各自漂移，真源必须是 `theme.dart`"），结论是"要让 mockup 跟着走，就像隐私政策那样由脚本生成"——**这条没做**。于是每次改色，原型都在无声地撒谎；而原型是设计师和外部对齐的唯一凭据。
- **改成什么**：把 `prototype/*.html` 的 `:root` 换成**由 `gen-prototype-tokens.mjs`（**待新建**，放 `tool/`） 从 `theme.dart` 生成**的块（像 `gen-privacy-page.mjs` 那样带 `--check` 模式进 `verify.sh`），并在 `check-guards-wired.mjs` 里挂上。**这是这一轮改色必须先做的前置件**，否则改完又是一次三处漂移。

---

## 4. VI 方案：色彩 · 材质 · 层级

### 4.1 层级表（可直接落进 `theme.dart`）

**八层，每层一个用途、一个色值、一条"何时用"的硬规矩。** 底色的**亮度阶梯刻意不是等差的**：靠下一档差距大（底色 → 内容面，一眼可辨），靠上一档差距小（面 → 浮层，需要叠加才成立）。

- **`sunken` `#0A0908`** — 用途：屏幕最底（训练屏的上/下工具栏、可滚动区之外）。边框：无。何时用：**只用于"非内容"的固定区域**，一屏最多两处（顶部 / 底部）。对 `bg` **1.05:1**，靠位置而不是颜色区分。
- **`bg` `#0E0C0A`** — 用途：页面底 / 信息流底。边框：无。何时用：**默认底色**。上面的内容一律用 `hair` 分节而不是卡片。
- **`hair` `#2A2520`** — 用途：**仅 `bg` 上的分节细线**（1px 或 0.5pt）。何时用：列表行之间、"纯数字/纯文字"块之间。对 `bg` **1.32:1**（刻意弱，它就是停顿，不是边界）。**不许贴卡边，不许做输入框边界。**
- **`surface` `#1A1714`** — 用途：卡片 / 图表容器 / 列表容器。边框：**`line` `#3A342E` 1px** + `elev-1` 投影。何时用：**只有"这是一个独立对象"时才用**（图表、可整体点击的块、分组列表）。对 `bg` **1.10:1**，**必须靠描边 + 投影才能成立**，单用底色不是卡片。
- **`input` `#24201C`** — 用途：**输入框 / 下拉 / 步进器底 / 未选中 chip**。边框：**`lineStrong` `#4A423A` 1px** + 顶部内侧 1px `rgba(255,255,255,.06)`。何时用：任何"用户可以往里打字/选择"的矩形。对 `bg` **1.21:1**，对 `surface` **1.10:1** —— **欠 1.4.11，所以描边是强制的，不是可选的。**
- **`chip` `#26221E`** — 用途：胶囊（未选中）/ 小标签 / 计数徽标。边框：`lineStrong` `#4A423A`。何时用：**骑在 `surface` 或 `bg` 上的圆形小目标**。因为它经常和 `surface` 相邻，**必须带描边**（只靠底色在卡片里是 1.00:1）。
- **`lift` `#2F2A25`** — 用途：**进度槽 / 未选中分段底 / 开关轨道**。边框：宽 < 12% 时补 `lineStrong` 一圈。何时用：**只许出现在 `surface` 或 `elevated` 上**；浮层内改用 `sheet` 底 + `lineStrong`。
- **`sheet` `#2E2924`** — 用途：**底部弹层 / 对话框 / 浮出的工具栏**。边框：无（**改用 `elev-2` 投影 + 顶部抓手**）。何时用：任何"浮在页面之上"的容器。对 `bg` **1.36:1** — **不够，所以"浮起"由投影 + 抓手承担，底色只是辅助**。非 iOS 的弹层底就是这个实色；iOS 走 `GlassSurface`，tint = 暖黑 `#1A141080`。

**两级投影**（新增，取代 `interaction-spec.md` §5 那句"不用阴影"）：
- **`elev-1`** = `0 1px 2px rgba(0,0,0,.50)` — 卡片。暗底上几乎看不见，它的作用是**在卡片下缘压出一根暗边**，让 1.59:1 的描边读起来更硬。
- **`elev-2`** = `0 8px 28px rgba(0,0,0,.62)` — 弹层 / 浮出元素。**这一档是真的要看得见**，因为 sheet 底对 bg 只有 1.36:1。
- **光晕**（不是阴影）：`glow(color, kind)` 只有两个 kind，`glowStrength = 0.22`，`blurPrimary 28 / blurPill 16 / spread 1`。**页面不许再写 BoxShadow 字面量。**

### 4.2 语义色使用纪律

每个语义色**只能有一个含义**，并且在代码层可机械检查：

- **`accent` `#FF5C26`** — 含义：**唯一主操作**（实心橙块）。纪律：一屏 ≤ 1 个实心块。
- **`accentText` `#FF8A5B`（新）** — 含义：**橙色的文字/图标链接**（`全部数据 ›`、`导出 CSV`、`补签这一天`）。纪律：一屏 ≤ 2 处。存在的理由：`#FF5C26` 当文字在 `bg` 上是 6.33:1（合规），但它和主按钮**同色同形**时无法区分主次；提亮一档后（8.40:1）**"这块可以点"与"这是主操作"在色相上就分开了**。
- **`accentPress` `#C93F12`（改）** — 含义：主操作按下。纪律：配合 `accentInk` 用，**算得 5.35:1**（旧的 `#E04A18` 只有 4.59:1，压线）。
- **`accentInk` `#141210`** — 含义：**一切橙底上的字**。纪律：**橙底白字（3.08:1）永久禁止**，包括 `vi/` 里那颗白胶囊。
- **`success` `#14B37D`（改）** — 含义：**完成 / 成功**（唯一）。纪律：不许做"上涨绿"以外的图表色，不许做"未完成"。改值的理由：暖黑底上 `#0CAC78` 偏冷（对 `bg` 6.68:1 合规但色温冲），`#14B37D` 是 **7.23:1** 且更暖。
- **`inkOnSuccess` `#04241A`（新）** — 含义：`success` 底上的墨。纪律：取代现在硬编码的 `#06231A`（对微亮后的绿只有 4.05:1）。
- **`pr` `#FBBF24`** — 含义：**破纪录 + 徽章传说档**（这两个是同一件事："你做到了最好的那次"）。纪律：**不许做"警告""提示""错误"** → `cloud_backup_screen.dart:692/697` 必须换 `warn`。
- **`warn` `#E0A84F`（新）** — 含义：**可挽回的异常**（网络错误、同步失败、云备份关闭提示，对 `bg` 算得 **8.2:1**）。纪律：一屏 ≤ 1 处，且不配图标不成活（必须有图形）。
- **`danger` `#F2545B`（改）** — 含义：**删除 / 不可逆 / 数据丢失**（唯一）。纪律：**法律条款正文、徽章配色、一般错误禁用**。改值的理由：从 `#FF5A5F` 挪到 `#F2545B` 是为了与探索线的藕紫 `#C88BE8` 在色相环上拉开（旧红与紫在暗底上容易混）。
- **`tierRare` `#9B6BFF`（改）** — 含义：**稀有徽章**（唯一）。纪律：叠色改用**不透明刻度**（底 `#241C3A` / 描边 `#6B4FC4` / 图标 `#9B6BFF`），**禁止对语义色叠任意 alpha**。
- **`tierMilestone` `#7FB2F0`（新）** — 含义：里程碑类徽章线。
- **`tierExplore` `#C88BE8`（新）** — 含义：探索发现类徽章线（**不再借 `danger`**）。

**机械守卫**（写进 `theme_discipline_test.dart`（**待新建**，放 `app/test/`））：
1. 除 `core/theme.dart` 外，`lib/` 下 **不许出现 `Color(0x`**（当前 5 处，已登记为待清）。
2. 除 `core/theme.dart` 外，`lib/` 下 **不许出现 `BoxShadow(`**（改用 `Tokens.glow` / `Tokens.elev1/2`）。
3. **每个语义色只许出现在白名单文件里**（`pr` → `workout_screen` 破纪录分支 / `badges.dart` 传说 / `share_card`；`danger` → `data_tools` / `trash` / `account` / `main` 丢弃 / `cloud_backup` 删除）—— 用一张 `Map<Color, List<String>>` 硬编码在测试里，新增越界当场红。

### 4.3 强调色纪律（怎么在代码层面守住"一屏 ≤ 1"）

口号已经喊了两版没用（§4 硬约束 + §12 清单都在，代码里 176 处）。**要靠机制**：

1. **拆令牌**（见 4.2 的 `accent` / `accentText` / `pr` / `warn`）。真机上数颜色的人只有我一个，拆完 `accent` 的**实际落点从 176 处降到约 20 处**（只剩 `FilledButton` 的 `backgroundColor`、选中胶囊的 `selectedTint`、进度填充、`ViProgressBar.default`），因为文字链接自动换了 `accentText`、状态自动换了语义色。
2. **一屏计数守卫**：新增 `AccentBudget`（`InheritedWidget` + `debugCounter`）。主按钮、进度填充、选中胶囊这些"橙色承载体"在 `build` 里登记；**`flutter test` 里打开断言，一屏超 1 直接红**。真机 debug build 也开，超了就在右上角画一个红点（开发期可见）。
3. **规矩写进 `theme.dart` 的注释而不是 §4**：把"一屏 ≤ 1"从文档搬进**类型系统**——`accent` 只允许通过 `Tokens.primaryFill` 这一个 getter 取到，`accentText` 通过 `Tokens.link`，**普通 `Text(color:)` 拿不到 `accent`** 就只能当实心块用。编译期比评审会可靠。

### 4.4 材质与玻璃规则

三套材质必须收敛成**一条语言**：**"越靠近用户手指的层，材质越实"**。

- **原生（iOS 真 `UITabBar`）**：唯一允许使用**真液态玻璃**的地方。理由：底栏下面**永远有内容在滚**（`docs/screens.md` S0 已确认底栏浮在内容之上），玻璃成立。规则：底托 `UIGlassEffect(.regular)`，**不加任何 tint**；选中色 = `accent`（文字/图标），**选中胶囊用系统默认**（不再上橙，避免"橙块压玻璃"）；hairline = **`#3A342E` 而非白 6%**（原生 hairline 是 0.5pt，白 6% 在 0.5pt 上等于 0）。
- **原生（`UISegmentedControl`）**：**恢复系统玻璃 + 系统灰胶囊**，选中态**只用文字色**（选中 `text` / 未选中 `text2`）。如果坚持橙色选中（2026-10-10 拍板），则**整个控件放弃玻璃**，改不透明：底 `input #24201C` + 描边 `#4A423A` + 橙胶囊 + `accentInk` 字。**二选一，不许混。**
- **自绘（Android 全部 / 所有非 iOS）**：**不用玻璃，不用模糊**。底栏底 `#1E1A16` + 顶 1px `#4A423A` + 选中 `accent`。分段控件 `input #24201C` + `lineStrong` + 橙胶囊 —— **与 iOS 走"放弃玻璃"那一支时逐像素同色**（宽度已经由 Dart 定了，色值也必须由 Dart 定，现在 `native_tab_bar.dart:167` 与 `app_tab_bar.dart:121` 分处写了两套色，这是下一次漂移的种子）。
- **弹层（`GlassOverlay`）**：iOS 走 `GlassSurface`，**tint 从冷 `#10101480` 改暖 `#1A141080`**；非 iOS 走**实色 `sheet #2E2924` + `elev-2`**。三条硬规矩：① **纯色空屏的弹层不用玻璃**（用实色 sheet）；② 弹层内部**不许再填 `backgroundColor: Tokens.surface`**（`glass_overlay.dart` 已写这条，现在仍然有页面在填）；③ **弹层内的小字一律 `text2`**（`sheet` 底上 `text3` 只有 3.76:1，不合格）。
- **顶栏**：**永久不做玻璃**（`docs/screens.md` S0 记着 2026-10-09 上过一版被真机回退）。顶栏用 `bg` 实色 + 底边 `hair`。

---

## 5. 与现有规范的冲突

**要推翻 / 改写的条文**（每条都给出处）：

1. **`docs/interaction-spec.md` §4 令牌表** —— 推翻 `text3 #6B6157`、`line/lineStrong`（白 6%/8%）、`tierRare #8350EE`、`elevated #24201C` 四个值，并新增 8 个令牌（`sunken` / `hair` / `input` / `chip` / `lift` / `sheet` / `accentText` / `warn` / `tierMilestone` / `tierExplore` / `inkOnSuccess`）。**理由**：`text3` 与 `line` 在实现里都没达到 §9 自己对无障碍的要求。
2. **`docs/interaction-spec.md` §5 卡片规格**「圆角 20pt，`--surface` 底，`1px --line` 描边（**不用阴影，深色下阴影无效**）」 —— **推翻"不用阴影"**。理由：暗底上"描边 1.17:1"证明描边**单独承担不了层级**；投影不是为了"立体"，是为了给描边**垫一根暗边**。同时圆角要定一个数：**卡片 12（保持 `theme.dart`，改 §5 与原型）**，因为 `rCard 12` 已经在 8 个页面生效，改回 20 的成本远高于改两份文档。
3. **`docs/interaction-spec.md` §4 硬约束 1**（"一屏 `--accent` 只能出现一次"） —— **保留条文，但改写执行方式**：从"评审打回"改成"`AccentBudget` 守卫 + 令牌拆分"。理由：口号版已经失败两版（176 处）。
4. **`docs/interaction-spec.md` §6 状态机**里 `rest_done` 那条「转 `--volt`」 —— 令牌名早就改成 `accent` 了，**这是一处没人发现的过期引用**（`--volt` 全仓已不存在）。
5. **`docs/interaction-spec.md` §9 无障碍**「正文对底色 ≥ 7:1；`--text-3` 仅用于非关键信息，且 ≥ 4.5:1」 —— 条文全对，**要加一条**：`text3` **不许出现在 `elevated` / `sheet` / 任何比 `surface` 亮的层上**（`#8A8176` 在 `elevated` 上只有 4.22:1）。
6. **`docs/plan-vi-migration.md` 第一节**「整个 `app/lib` 里只有 **1 处** `Color(0x…)` 写在 `theme.dart` 之外」 —— **这句话现在是假的**（5 处：`vi_cards.dart:125`、`workout_screen.dart:948`、`intro_carousel_screen.dart:228/347`、`workout_summary_screen.dart:406`）。要找一处改成五点名 + 加守卫。
7. **`docs/screens.md` S0 那句**「**选中胶囊 = 强调橙**（`selectedSegmentTintColor`）」 —— 与"保留系统玻璃"二选一，我建议**推翻**：分段控件保留系统灰胶囊、选中用文字色。理由：橙块压玻璃是"材质自杀"（4.1/4.4）。若业务坚持橙，则必须同步放弃玻璃，**不能只改颜色不改材质**。
8. **`prototype/*.html` 的 `:root`** —— 不再是手写副本，改由 `gen-prototype-tokens.mjs`（**待新建**，放 `tool/`） 从 `theme.dart` 生成。

⚠️ **改色的"三处一致"成本（必须算清）**：仓库的文件头写着"与 `docs/interaction-spec.md` §2–§4 和 `prototype/index.html` 的 CSS 变量一一对应。改这里之前先改规格 —— 三处必须同时一致"。**每一轮改色要动四处**：
- ① `app/lib/core/theme.dart`（真源）；
- ② `docs/interaction-spec.md` §4 那张表（含 §5 圆角、§9 无障碍口径）；
- ③ `prototype/index.html` 的 `:root`（**它现在有两处色值 + 一处圆角已经漂了**，改之前要先补漂移）；
- ④ `prototype/ref-3tab-2026-10-10.html` 的 `:root`（第三个副本，`--elev/--t1..--t3` 命名还不一样）。
- **强烈建议先做 ④→③ 的生成器**（2 小时内的事），否则这一轮改完，三处漂移会变成四处。

---

## 6. 落地成本

### 6.1 改令牌即全站生效（低成本，收益最大）

- `text3 #6B6157 → #8A8176` —— **253 处自动受益**（这是全清单里性价比最高的一条）。
- `tierRare #8350EE → #9B6BFF`、`success #0CAC78 → #14B37D`、`danger #FF5A5F → #F2545B`、`accentPress #E04A18 → #C93F12` —— 各 3–19 处，改一行。
- `line / lineStrong` 从 rgba 换成实色 `#3A342E / #4A423A` —— 89 处自动受益。⚠️ **注意语义**：现在的半透明值"叠哪层都对"，换成实色后**必须同时规定"只能上哪一层"**（`line` 只用于 `surface` 及更亮，`lineStrong` 只用于 `input/chip`）—— 否则在 `bg` 上会偏亮、在 `sheet` 上会偏暗。这一条要在 `theme.dart` 注释里写死。
- 新增令牌（`sunken / hair / input / chip / lift / sheet / accentText / warn / tierMilestone / tierExplore / inkOnSuccess / elev1 / elev2 / glow`）—— 加常量，零风险。

### 6.2 要逐屏改（中高成本，按页列清单）

- **`core/vi_cards.dart`** —— `ViCard` 底/边/投影、`ViProgressBar` 槽换 `lift`、`StatTile` 的硬编码 `#5FD08A` 换 `success`。**一处改，全站卡片跟着变**（这是这个仓库做得最对的一件事，成本最低）。
- **`core/pills.dart` + `exercise_picker_screen.dart:671`** —— 未选中 chip 换 `chip` 层 + 描边，输入框换 `input` 层。**2 个文件**。
- **`core/glass_overlay.dart`** —— tint 改暖、非 iOS 底改 `sheet`。**1 个文件**，但**要回头扫 20 多处弹层**有没有叠 `backgroundColor: Tokens.surface`（文件头自己说这是唯一的使用纪律，没有守卫）。
- **`core/app_tab_bar.dart` + `core/native_tab_bar.dart`** —— 两处色值收口到一处（现在 167 行与 121 行各写一套）。**2 个文件，但必须同时改**。
- **`core/vi_cards.dart:199-216`（`ViSegmented` iOS 分支）+ 非 iOS 分支** —— 材质二选一，**这是这一轮唯一需要用户再拍一次板的取舍**。
- **`core/vi_area_chart.dart`** —— 填充改实色刻度。**1 个文件**。
- 训练屏 `workout_screen.dart`（10 处 accent / 热身态 / 禁用态）、`today_screen.dart`（6 处）、`achievements_screen.dart`（tier 三色 + alpha 刻度）、`workout_summary_screen.dart`（光晕 + 解锁块 + 硬编码墨）—— **4 个页面，逐个改**。
- **`badges.dart:812-822`（四条收集线的配色映射）** —— 一行映射，改完 `achievements_screen` 跟着变。
- **`notification_visuals.dart`（3 行映射）** —— 一行。

### 6.3 不在这一轮做（写下来免得被当成漏了）

- 不动 `Tokens.hPrimary 88`、间距标尺、字阶、`rSheet/rPill`。
- 不动 Oswald 与 `Tokens.display()`（那是方案 A 的领域）。
- **不动任何功能、不改任何页面结构**（`plan-ux-2026-10-10.md` 刚落地，不叠加变量）。
- 不动 `store-assets/screenshots/` 那 43 张图 —— 它们在**改完之后**才重出（`tool/check-screenshots.mjs` 会核张数与尺寸，所以必须等代码稳定）。
- 不做 `vi/*.html` 的 15 份 `:root` 回填（那是"生成器"那件事，见 6.4）。

### 6.4 建议的施工顺序（每步都能单独跑门禁）

1. **生成器先做**：`gen-prototype-tokens.mjs`（**待新建**，放 `tool/`）（从 `theme.dart` 出 `prototype/*.html` 的 `:root`，带 `--check`）→ 挂进 `verify.sh` + `check-guards-wired.mjs`。**先补上 `prototype/index.html` 已经漂了的三处**。
2. **令牌层**（6.1 全部）+ 新的 `theme_discipline_test.dart`（三条机械守卫）。这一版跑完，可视化几乎没变化，但"不许硬编码"从此有守卫。
3. **组件层** `core/*`（`vi_cards` / `pills` / `glass_overlay` / `vi_area_chart` / tab bar 两处）—— 卡片、进度条、胶囊、图表、底栏一次收口。
4. **页面层** 四个页面 + `badges.dart` + `notification_visuals.dart`。
5. **材质取舍**（4.4 里"橙胶囊 vs 系统玻璃"那一条）—— 单独一拍板、单独一版，因为它会改到 iOS 原生 Swift 那侧的参数（`NativeSegmentedBridge.swift` / `NativeTabBarBridge.swift`），**属于"动原生"的操作，风险与上面四步不同**。
6. **文档同步**：`interaction-spec.md` §4/§5/§6/§9 + `plan-vi-migration.md` §一 + `screens.md` S0 + 本文件。
7. **重出证据图与商店图**（`docs/images/` 各目录 + `store-assets/screenshots/` 43 张）。

---

## 附：本文用到的真实统计（可逐条复核）

- `grep -rn "withValues(alpha" app/lib | wc -l` = **20**（其中 `vi_cards` 2 / `vi_area_chart` 3 / `achievements_screen` 5 / `workout_summary_screen` 6 —— **透明度集中在"卡片光晕 + 图表 + 徽章"三处，都没有刻度**）
- `grep -rn "BoxShadow" app/lib` = **3 个文件 4 处**（`achievements_screen:522` / `notification_center_screen:189` / `workout_summary_screen:398`）
- `grep -rn "Tokens.surface\|Tokens.elevated" app/lib | wc -l` = **97**（`surface` 与 `elevated` 合计，其中 `elevated` 只有 44 处）
- `grep -rn "Tokens.line" app/lib | wc -l` = **89**（`line` 78 + `lineStrong` 11）
- `grep -rn "Tokens.text3" app/lib | wc -l` = **253**；`Tokens.text2` = **136**；`Tokens.accent` = **176**
- 语义色：`Tokens.danger` = **19**、`Tokens.pr` = **12**、`Tokens.success` = **8**、`Tokens.tierRare` = **3**
- `grep -rn "Color(0x" app/lib | grep -v theme.dart` = **5 处**（`vi_cards.dart:125` `#5FD08A` · `workout_screen.dart:948` `#9E000000` · `intro_carousel_screen.dart:228/347` `#06231A` · `workout_summary_screen.dart:406` `#06231A`）
- 单屏 accent 落点：`workout_screen.dart` **10 处** · `today_screen.dart` **6 处** · `cloud_backup_screen.dart` 9 处（**分不同弹层，不算同屏**）· `exercise_picker_screen.dart` 3 处 · `all_data_screen.dart` 2 处（**截图证实同屏**）
