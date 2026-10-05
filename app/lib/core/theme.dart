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
  static const Color text3 = Color(0xFF6B6157);

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

  /// 仅用于破纪录，不用于普通成功态。
  static const Color pr = Color(0xFFF5C451);

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
