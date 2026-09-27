/// 练了么 · 设计令牌
///
/// 与 `docs/interaction-spec.md` §2–§4 和 `prototype/index.html` 的 CSS 变量一一对应。
/// 改这里之前先改规格 —— 三处必须同时一致。
library;

import 'package:flutter/material.dart';

abstract final class Tokens {
  // 背景层级
  static const Color bg = Color(0xFF0B0B0D);
  static const Color surface = Color(0xFF16161A);
  static const Color elevated = Color(0xFF1F1F24);
  static const Color line = Color(0xFF2A2A31);
  static const Color lineStrong = Color(0xFF3A3A44);

  // 前景层级
  static const Color text = Color(0xFFF5F5F7);
  static const Color text2 = Color(0xFF9A9AA5);
  static const Color text3 = Color(0xFF5E5E68);

  // 强调色
  /// 唯一主操作色。**一屏之内只允许出现一次**，出现两次即说明主次不分。
  static const Color volt = Color(0xFFD8FF47);
  static const Color voltPress = Color(0xFFC2E63A);
  static const Color voltInk = Color(0xFF12180A);

  /// 仅用于破纪录，不用于普通成功态。
  static const Color pr = Color(0xFFF5C451);

  /// 仅用于删除与不可逆操作。
  static const Color danger = Color(0xFFFF5A5F);

  // 间距标尺（不允许出现奇数间距）
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;

  // 圆角
  static const double rCard = 20;
  static const double rSheet = 28;
  static const double rPill = 999;

  /// 主按钮高度 —— 单手可达的硬约束，任何字号下都不允许压缩。
  static const double hPrimary = 88;
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Tokens.volt,
    brightness: Brightness.dark,
  ).copyWith(
    surface: Tokens.bg,
    primary: Tokens.volt,
    onPrimary: Tokens.voltInk,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: Tokens.bg,
    splashFactory: NoSplash.splashFactory,
  );
}
