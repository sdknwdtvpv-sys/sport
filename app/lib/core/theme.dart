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

  /// 分隔线：稿子里用的是**半透明白**（4%–8%），不是实心灰 —— 这样它叠在任何一层
  /// 背景上都自动正确（旧版是 #2A2A31 那种实心灰，底色一换就得逐个重算）。
  static const Color line = Color(0x0FFFFFFF); // 白 6%
  static const Color lineStrong = Color(0x14FFFFFF); // 白 8%

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
  );
}
