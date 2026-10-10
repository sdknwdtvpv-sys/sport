/// 练了么 · 设计令牌
///
/// 与 `docs/interaction-spec.md` §2–§4 和 `prototype/index.html` 的 CSS 变量一一对应。
/// 改这里之前先改规格 —— 三处必须同时一致。
///
/// ⚠️ **2026-10-05：整套色板换成用户给的新 VI**（`vi/` 那 15 个界面稿）。换的原因与
/// 逐屏对齐表在 `docs/plan-vi-migration.md`。**值不是抄 `:root` 抄来的**：
/// `vi/*.html` 里 15 个文件各写了一份变量（14 种变体），所以底色与卡片色是
/// **从渲染出来的界面稿上采样**得到的；边线用的是稿子里真正在用的半透明白（4%–8%），
/// 不是后人凑的灰。
///
/// 旧值（volt 绿 + 冷黑）的清单在 `docs/plan-vi-migration.md` 第二节的对照表里。
library;

import 'package:flutter/material.dart';

abstract final class Tokens {
  // 背景层级（暖黑：采样自界面稿，App 底 #0E0C0A / 卡片 #1A1714）
  static const Color bg = Color(0xFF0E0C0A);
  static const Color surface = Color(0xFF1A1714);
  static const Color elevated = Color(0xFF24201C);

  /// **三级线**（2026-10-10，VI 计划 T0-4）。原来只有 `line`（白 6%）与 `lineStrong`（白 8%），
  /// 两者**只差 1.07:1**，而且都落在"绝对看不见"的区间里（对 `bg` 1.13 / 1.19）——
  /// 于是"卡片描边"这个本该承担层级的东西**完全失效**：它既分不出两级，也几乎看不见。
  ///
  /// 现在改成**实色三级**，每一级都有明确职责（别再随手挑一个用）：
  ///   * [hair] 1.30:1 —— **页面级的长分隔**（「进步」的数字带、训练屏的对照带、
  ///     「我」的统计带上下那两条）。它躺在 `bg` 上，最淡就够；
  ///   * [line] 1.59:1（对 `surface` 1.45）—— **卡片描边**与**卡片内部**的行分隔；
  ///   * [lineStrong] 3.18:1 —— **功能性边界**：输入框、未选中胶囊、分段控件外壳
  ///     （配 [field] 那块抬升底一起用）。这一条是 WCAG 1.4.11 那条"界面组件的边界要 3:1"。
  ///
  /// ⚠️ 为什么放弃半透明：半透明线的红利是"叠在任何底色上都自动正确"，
  /// 但代价是**它永远只有一档可见度** —— 而层级需要的是"两档之间看得出差"。
  /// 换成实色之后，"哪一级只能上哪一层"就成了必须写下来的规矩：
  /// **`hair` 只做上下分隔（不许 `Border.all`）、`line` 不上页面长的分隔、`lineStrong` 只给功能边界。**
  /// `theme_discipline_test.dart`（放 `app/test/`）扫这几条。
  /// **「抬起来的材料」**（2026-10-10，VI 计划 T1-2）：卡片里的**进度槽**、**锁态徽章**、
  /// **未选中胶囊**、**输入框底** —— 都是它。对 `surface` 1.33:1、对 `bg` 1.45:1。
  ///
  /// ⚠️ **它不许用在弹层（`sheet`）里**：`lift` 对 `sheet` 只有 **1.10:1**，
  /// 浮层里的进度条用它等于整条消失（成就页那四条 2/20、1/20 的收集线就是实况）。
  /// `theme_contrast_test.dart` 把这两条都钉着。
  ///
  /// ⚠️ 计划文档里把它拆成 `lift` 与 `field` 两个名字；实现时**合成一个**（`field` 是别名）——
  /// 两个名字如果永远取同一个值，第二个名字只是下一处漂移的入口。
  static const Color lift = Color(0xFF332E28);

  /// **弹层底**（对话框 / 底弹层 / SnackBar）：对 `bg` 1.32:1 —— 比 `surface` 再抬一档，
  /// 因为弹层打开时底层被遮罩压暗，它必须比卡片更"浮"。
  static const Color sheet = Color(0xFF2B2723);

  /// 遮罩（弹层后面那层黑）：0x9E ≈ 62%。
  static const Color scrim = Color(0x9E000000);

  /// **成功色上的字**（那颗绿勾里的深墨）：`#06231A` 对 `success` `#0CAC78` = 5.0:1。
  static const Color inkOnSuccess = Color(0xFF06231A);

  /// **一团彩色辉光**（破纪录、未读点、完成勾）—— 三处原来各写一份 `BoxShadow`，
  /// 于是同一个"发光"有三种模糊半径。统一到这里，半径按语义给。
  static List<BoxShadow> glow(Color c, {double radius = 18, double spread = 1}) =>
      <BoxShadow>[
        BoxShadow(color: c.withValues(alpha: 0.28), blurRadius: radius, spreadRadius: spread),
      ];

  /// **可交互的"抬升字段"底**（2026-10-10，VI 计划 T0-2）：输入框与**未选中胶囊**共用。
  ///
  /// 为什么需要它：搜索框原来的底是 `surface`，对页面 `bg` 只有 **1.10:1** 且**没有边框** ——
  /// 在暗光健身房里用户看不出那里能打字（这是**功能不可发现**，不是审美）。
  /// 未选中胶囊更糟：骑在 `surface` 卡片上时对卡片是 **1.00:1**（完全看不见）。
  ///
  /// ⚠️ **这一条的口径与计划文档略有出入，如实写在这里**：计划里写的是
  /// `contrast(input, bg) >= 3.0`，而 WCAG 1.4.11 管的是**界面组件的边界**（边界要 3:1），
  /// 不是填充 —— 填充只要**可分辨**即可（否则深色界面里的输入框会变成一块浅灰板）。
  /// 所以：**填充用 [field]（对 `bg` 1.39:1、对 `surface` 1.27:1 = 可分辨），
  /// 边界用 [lineStrong]（对 `bg` 3.18:1 = 达标）**。`theme_contrast_test.dart` 两条都钉着。
  static const Color field = lift; // 别名：与 `lift` 是同一种材料（见上）

  static const Color hair = Color(0xFF2A2622);
  static const Color line = Color(0xFF3A342E);
  static const Color lineStrong = Color(0xFF6A6055);

  // 前景层级（VI 的 neutral-50 / 300 / 500）
  static const Color text = Color(0xFFF5F3F1);
  static const Color text2 = Color(0xFFABA49A);
  /// ⚠️ **2026-10-10 提亮**（VI 计划 T0-3，`docs/plan-vi-2026-10-10.md`）：`#6B6157` → `#8A8176`。
  ///
  /// 旧值在 `surface` 上只有 **2.95:1**、在 `bg` 上 3.23:1，而 `docs/interaction-spec.md` §9
  /// 自己写着「`--text-3` 仅用于非关键信息，**且 ≥ 4.5:1**」—— 规格与实现互相打脸，
  /// 而它被用了 **253 处**（其中 173 处在 11–13pt 的小字里）。
  ///
  /// 新值：对 `bg` **5.06:1**、对 `surface` **4.66:1**（都过 4.5），
  /// 但对 `elevated` 只有 **4.22:1** —— 所以多了一条硬规矩：
  /// **`text3` 只有权落在 `bg` / `surface` 上，不许上 `elevated` 或更亮的层**
  /// （`theme_contrast_test.dart`（放 `app/test/`）会在真实界面树上扫这一条）。
  ///
  /// 配套（同一天做的）：凡是「用户读了要据此做动作」的标签**一律改 `text2`**，
  /// 不管字号 —— 未选中 tab、选动作页的筛选行标签与每行副标题、搜索 hint、RPE 未选中值都改了。
  static const Color text3 = Color(0xFF8A8176);

  // 强调色
  /// 唯一主操作色。**一屏之内只允许出现一次**，出现两次即说明主次不分。
  ///
  /// 名字从 `volt` 改成 `accent`：旧名字是"电压绿"的意思，颜色换成橙之后
  /// **名字本身就是一句假话**（这个仓库最防的就是这个）。
  static const Color accent = Color(0xFFFF5C26);
  static const Color accentPress = Color(0xFFE04A18);

  /// **橙色文字**（链接、弹层里的文字按钮、橙色的标签）。
  ///
  /// 为什么要单独一个：`accent`（#FF5C26）是**实心块**的颜色，拿它写字在暖黑底上
  /// 只有 5.3:1 —— 而"可点的文字"要 4.5:1 以上**并且**在暖黑底上看着不能发闷。
  /// 提亮到 #FF8A5B 之后对 `bg` 是 **8.40:1**（`theme_contrast_test` 钉着）。
  ///
  /// ⚠️ 这一条是 VI 计划 §3 冲突 5 的裁决（"拆令牌：文字链接走 `accentText`"），
  /// 而它**在批次 1 漏掉了** —— 裁决写了 ✅、代码里没有这个常量，于是全 App 59 处
  /// `color: Tokens.accent` 里那 22 处**橙字**一直用的是实心块的颜色。
  /// 2026-10-10 收尾时补上（`accent_budget_test` 现在盯着"橙字不许再用 accent"）。
  static const Color accentText = Color(0xFFFF8A5B);

  /// 橙底上的字色。**必须用深色**：橙底 + 白字只有 3.08:1（AA 小字要 4.5），
  /// 深色是 6.06:1。界面稿里两种都出现过（训练首页那颗白胶囊是例外），这里按 6:1 那条来。
  static const Color accentInk = Color(0xFF141210);

  /// **成功/完成**（训练完成页那个勾）。值量自界面稿（`vi/complete-library.html` 渲染出来的
  /// 绿色主体是 #0AA674–#0CAD79）。新 VI 之前这个语义色根本不存在 ——
  /// 完成页原来只有一行文字。
  static const Color success = Color(0xFF0CAC78);

  /// **稀有徽章的紫**（2026-10-05 加的，量自 `vi/achievement-badges.html` 的稀有度那三个圆：
  /// 普通 #EB5220 / 稀有 #8551F0 / 传说 #F0A71A）。
  /// 三档里只新加这一个颜色 —— 普通用 [accent]、传说用 [pr]，
  /// 免得同一套里出现两个几乎一样的琥珀（#F0A71A 与 pr #FBBF24 肉眼分不出）。
  static const Color tierRare = Color(0xFF8350EE);

  /// 仅用于破纪录，不用于普通成功态。**2026-10-05 跟着新 VI 换成更亮的琥珀**：
  /// 界面稿里那张 PR 卡是 #FBBF24（旧的 #F5C451 在暖黑底上偏灰，不够"奖杯"）。
  static const Color pr = Color(0xFFFBBF24);

  /// 仅用于删除与不可逆操作。**新 VI 没给这个语义色** —— 保留旧的，
  /// 而不是"为了统一"把它也做成橙色（那样删除和主操作就分不出来了）。
  static const Color danger = Color(0xFFFF5A5F);

  // 间距标尺（不允许出现奇数间距）
  // ══════════════════════════════════════════════════════════════════════
  // **字阶**（2026-10-10，VI 计划 T1-1）
  //
  // 为什么必须建它：全仓 **468 处 `fontSize:` 落在 21 个不同字号上**（规格只定义 7 级），
  // 行高 10 个字面量、字重 5 种、字距 8 种 —— 而 `theme.dart` 里有色值、间距、圆角，
  // **唯独没有字号**。所以"换 VI 只换掉了皮"：色值改一处全站生效，字号要改 178 处。
  //
  // **10 级**（这是全站唯一允许的字号集合；`typography_scale_test.dart` 扫全仓钉着）：
  //   `fsHero 30` 训练屏大按钮上的值 / 引导页大标题；
  //   `fsTitle 28` 页面标题（顶栏、建议页、同意页、完成页）；
  //   `fsNumL 24` 大数字（「我」、身体数据摘要）；
  //   `fsNum 22` 中等数字与标题（徽章名、动作详情）；
  //   `fsHeadline 20` 卡片标题、输入框、分段控件；
  //   `fsBody 17` 正文 / 搜索框；
  //   `fsBodyS 16` 次级正文；
  //   `fsSub 15` 说明文字、列表里的值；
  //   `fsCap 13` 小标签、Tab、胶囊；
  //   `fsMicro 12` 最小说明、hint。
  //
  // 折进来的那些（**每一条都是有意的**）：
  //   19 → 20、18 → 17、14.5 → 15、**14 → 15**、13.5 → 13、12.5 → 12、
  //   11.5 → 12、**11 → 12**（11pt 在健身房里太小，P2 的结论也是提上去）、10 → 12、26 → 28。
  //
  // 行高只有 4 档、字重只有 3 档、字距只有 3 档 —— 同样由守卫扫。
  // ══════════════════════════════════════════════════════════════════════

  /// 字号（10 级，见上面那张表）。
  static const double fsHero = 30;
  static const double fsTitle = 28;
  static const double fsNumL = 24;
  static const double fsNum = 22;
  static const double fsHeadline = 20;
  static const double fsBody = 17;
  static const double fsBodyS = 16;
  static const double fsSub = 15;
  static const double fsCap = 13;
  static const double fsMicro = 12;

  /// 行高（4 档）。`tight` 给标题（26pt 以上才用）、`snug` 给小字标签、
  /// `normal` 给正文、`loose` 给"要多说一句话"的空态。
  static const double lhTight = 1.2;
  static const double lhSnug = 1.35;
  static const double lhNormal = 1.5;
  static const double lhLoose = 1.7;

  /// 字重（3 档）。**`w500` 与 `w800` 不再存在**：它们全仓只有 4 处，
  /// 是"随手写的"而不是设计决定（`typography_scale_test.dart` 钉着）。
  static const FontWeight fwBody = FontWeight.w400;
  static const FontWeight fwStrong = FontWeight.w600;
  static const FontWeight fwBold = FontWeight.w700;

  /// 字距（4 档）。前两档是"数字大要收一点"，第三档是"全大写短标签放开一点"，
  /// 第四档只给**账号 ID** 这种"要一个字符一个字符数过去"的串。
  ///
  /// ⚠️ [lsSpaced] 是 T1-7 从 `identity_screen.dart` 里捞出来的：那里写着
  /// `letterSpacing: id == null ? 0 : 1.2` —— 一个字面量藏在三元表达式里，
  /// 连"grep `letterSpacing: -?[0-9]`"和当时的扫描器都漏了。
  static const double lsTight = -0.5;
  static const double lsSnug = -0.3;
  static const double lsWide = 0.3;
  static const double lsSpaced = 1.2;

  /// **字标的字距**（VI 计划 T3-3）：分享卡卡头那种"三个汉字当标志用"的场合。
  ///
  /// 为什么它不能复用 `lsWide`（0.3）：字标要的是"**看起来像三个独立的字**"，
  /// 而正文里放开 0.3 是"别挤在一起"—— 两件事，量级也差一个数量级。
  /// 分享卡会被压到朋友圈缩略图（约 200pt 宽）去看，那时 16pt 的字只剩 ~9pt 高，
  /// 字距拉开一点是它能被认出是"练了么"的关键。
  static const double lsWordmark = 6;

  /// 字体族：数字与拉丁走 Oswald（`docs/plan-vi-migration.md` §六第 2 条的结论），
  /// 中文回落系统字体 —— 这个机制保留，只是从"注释里的约定"变成这个常量。
  static const String? fontFamilyLatn = 'Oswald';

  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;

  // 圆角（VI：--radius-sm 8 / --radius-md 12 / 底部弹层 20 / 胶囊全圆）
  static const double rCard = 12;
  static const double rSheet = 20;
  static const double rPill = 999;

  /// 主按钮高度 —— 单手可达的硬约束，任何字号下都不允许压缩。
  static const double hPrimary = 88;

  // 展示字体（VI：Oswald 管数字与拉丁标题，中文正文走系统字体）
  /// 字体族名，与 `pubspec.yaml` 里声明的一致。
  static const String displayFont = 'Oswald';

  /// **等宽数字**（`tabularFigures`）：倒计时、备份条数这类"会跳数字"的地方。
  ///
  /// 为什么收成一个常量（VI 计划 §7 B 组那条"3 处调用 → 定义处一处"）：
  /// 等宽数字不是审美，是**防止数字跳动**——而它要在**同一个段落里每一处**都开，
  /// 一处漏了就那一处跳。三个调用点各写一遍 `FontFeature.tabularFigures()` 的后果，
  /// 就是下一处新数字没人记得加。现在写 `fontFeatures: Tokens.tabular` 就行。
  static const List<FontFeature> tabular = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  /// 展示数字/拉丁的一站式样式。
  ///
  /// **只给数字与拉丁字符串用**：Oswald 不含汉字，中文会**回落到系统字体** ——
  /// 混排时会出现"数字是 Oswald、汉字是系统字"的效果，这正是 VI 的做法。
  /// 反过来说，**别拿它包整句中文**（那就等于没换字体，还多一层困惑）。
  ///
  /// `wght` 轴 200–700 由 [fontVariations] 驱动：可变字体单文件出所有字重，
  /// 只声明 `fontWeight` 在多数平台上不会真的选到那一档。
  static TextStyle display(
    double size, {
    double weight = 600,
    Color color = text,
    double? height,
    double letterSpacing = 0,
  }) =>
      TextStyle(
        fontFamily: displayFont,
        fontSize: size,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
        fontWeight: FontWeight.w600,
        fontVariations: <FontVariation>[FontVariation('wght', weight)],
      );
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Tokens.accent,
    brightness: Brightness.dark,
  ).copyWith(
    surface: Tokens.bg,
    primary: Tokens.accent,
    onPrimary: Tokens.accentInk,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: Tokens.bg,
    splashFactory: NoSplash.splashFactory,
    // ── 列表行（T1-8）────────────────────────────────────────────────────
    //
    // **为什么必须在 theme 里**：`ListTile` 全仓 26 处，其中 15 处各自写了
    // `contentPadding: …s4`，而自绘行走 20pt —— 同一台手机上，两类列表的文字
    // 不在同一列（数据工具页 x=36、全部记录页 x=20）。这类"每个使用点各写一遍"
    // 的几何约束，正是该由主题一处说了算的东西。
    //
    // 取值 `Tokens.s5`（20）：与自绘行的 20 对齐；卡片内的行由"卡片自身的内边距"
    // 提供（`settingsCard` / `all_data_screen._card` 都按同一档给）。
    //
    // `visualDensity` 竖直收 1 档：行高 56/72 → 52/68。风险如实记在
    // `docs/plan-vi-2026-10-10.md` T1-8 里 —— 文案长的行会更容易换行。
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: Tokens.s5),
      visualDensity: VisualDensity(vertical: -1),
      iconColor: Tokens.text3,
      // 这两条是**基线**：行里自己写的 `Text(stStyle: …)` 会盖掉它们。
      // 26 处里的显式样式还没收（那是批次 3 的清理），但基线本身必须是令牌 ——
      // 否则"没写样式的行"会落到 Material 默认的 `titleMedium` 上，那是另一套字阶。
      titleTextStyle: TextStyle(
        color: Tokens.text,
        fontSize: Tokens.fsSub,
        fontWeight: Tokens.fwBody,
      ),
      subtitleTextStyle: TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap),
    ),
  );
}
