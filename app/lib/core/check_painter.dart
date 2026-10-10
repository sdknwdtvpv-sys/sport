/// 练了么 · **自绘的完成勾**（VI 计划 T2-3，2026-10-10）
///
/// 为什么不用 `Icons.check`：那是**现成的一枚字形**，画不出来"一勾写下去"这个过程。
/// 而完成页最该被记住的恰恰是这个过程 —— 用户练完一场，看的就是那 0.42 秒。
///
/// 做法是 `Path` + `PathMetric.extractPath`：先定义完整的勾（两段折线、圆头圆角），
/// 再按 [progress] 把它的前百分之多少"抽"出来画 —— 于是笔画是**写出来**的，
/// 不是淡入出来的（淡入的勾在眼角的余光里与"静态图"没有差别）。
library;

import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import 'theme.dart';

/// 一枚"写出来"的勾。
class CheckPainter extends CustomPainter {
  const CheckPainter({
    required this.progress,
    required this.color,
    this.strokeWidth = 4,
  });

  /// 0 = 一笔没写，1 = 写完。
  final double progress;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final double t = progress.clamp(0.0, 1.0);
    if (t <= 0) return;
    // 勾的三个点：起笔（左下）/ 折点（中下）/ 收笔（右上）。
    // 用相对坐标而不是绝对像素：这个 painter 会被用在 76pt 的圆里，
    // 以后换尺寸不该重新调这三个数。
    final Path full = Path()
      ..moveTo(size.width * 0.24, size.height * 0.53)
      ..lineTo(size.width * 0.43, size.height * 0.71)
      ..lineTo(size.width * 0.77, size.height * 0.32);
    final PathMetric metric = full.computeMetrics().first;
    final Path drawn = metric.extractPath(0, metric.length * t);
    canvas.drawPath(
      drawn,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(CheckPainter old) =>
      old.progress != progress || old.color != color || old.strokeWidth != strokeWidth;

  /// 勾的图形本身（给测试与"要不要重绘"之外的地方用）。
  static const Color defaultColor = Tokens.inkOnSuccess;
}
