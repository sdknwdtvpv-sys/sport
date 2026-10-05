/// 练了么 · **面积图**（容量趋势，零依赖自绘）
///
/// 与 `core/sparkline.dart` 的分工：sparkline 是**卡片里那条细线**（7 天趋势、没有坐标），
/// 这里是**界面稿里那张大图**：有基线、有渐变填充、有横轴标签与最后一点的强调点。
///
/// 为什么不引图表库：本项目 pubspec 的规矩是"依赖保持最小"，
/// 而这里要画的东西只有一条折线加一块渐变 —— 为它加一个包不值得。
library;

import 'package:flutter/material.dart';

import 'theme.dart';

/// [points] 是 0..1 的比例（长度即点数）。**空数组也能渲染**（画一条基线），
/// 因为"还没有数据"是常态，不该让调用方到处写 if。
class ViAreaChart extends StatelessWidget {
  const ViAreaChart({
    super.key,
    required this.points,
    this.height = 132,
    this.labels = const <String>[],
    this.color,
  });

  final List<double> points;
  final double height;

  /// 横轴标签（左 → 右）。数量与 [points] 不必相等，画家只取首尾与中间。
  final List<String> labels;

  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: ViAreaChartPainter(points, color: color ?? Tokens.accent),
        ),
      );
}

class ViAreaChartPainter extends CustomPainter {
  ViAreaChartPainter(this.points, {this.color = Tokens.accent});

  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double baseline = size.height - 1;
    // 基线：任何情况下都在，哪怕是空数据 —— 空图也不该是一片纯黑
    canvas.drawLine(
      Offset(0, baseline),
      Offset(size.width, baseline),
      Paint()
        ..color = Tokens.line
        ..strokeWidth = 1,
    );
    if (points.isEmpty || size.width <= 0) return;

    final double step = points.length > 1 ? size.width / (points.length - 1) : 0;
    final List<Offset> pts = <Offset>[
      for (int i = 0; i < points.length; i++)
        Offset(
          points.length > 1 ? i * step : size.width / 2,
          baseline - (points[i].clamp(0.0, 1.0)) * (size.height - 8),
        ),
    ];

    // 折线 + 填充
    final Path line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      line.lineTo(pts[i].dx, pts[i].dy);
    }
    final Path fill = Path.from(line)
      ..lineTo(pts.last.dx, baseline)
      ..lineTo(pts.first.dx, baseline)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    // 最后一个点强调一下（"今天"）
    canvas.drawCircle(pts.last, 3.5, Paint()..color = color);
    canvas.drawCircle(
      pts.last,
      6,
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(ViAreaChartPainter old) =>
      old.points != points || old.color != color;
}
