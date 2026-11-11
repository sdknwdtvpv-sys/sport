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
    this.previousPoints = const <double>[],
    this.yMaxLabel,
    this.showEndDot = true,
  });

  final List<double> points;
  final double height;

  /// 横轴标签（左 → 右）。数量与 [points] 不必相等，画家只取首尾与中间。
  final List<String> labels;

  final Color? color;

  /// 上一周期同点位（虚线对照）。空 = 不画。
  final List<double> previousPoints;

  /// 右上角 y 轴上限文案（null = 不画 y 轴标签）。
  final String? yMaxLabel;

  /// v3.1.0：全部数据合并图不要末端大点（0 值日不画点）。
  final bool showEndDot;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: ViAreaChartPainter(points,
              color: color ?? Tokens.accent,
              previousPoints: previousPoints,
              yMaxLabel: yMaxLabel,
              showEndDot: showEndDot),
        ),
      );
}

class ViAreaChartPainter extends CustomPainter {
  ViAreaChartPainter(this.points,
      {this.color = Tokens.accent,
      this.previousPoints = const <double>[],
      this.yMaxLabel,
      this.showEndDot = true});

  final List<double> points;
  final Color color;
  final List<double> previousPoints;
  final String? yMaxLabel;
  final bool showEndDot;

  @override
  void paint(Canvas canvas, Size size) {
    // v3.1.0：顶部留 24pt 给最大值标签，左右各留 6pt 防末点被裁。
    const double topPad = 24;
    const double sidePad = 6;
    final double baseline = size.height - 1;
    final double plotH = baseline - topPad;
    // 基线：任何情况下都在，哪怕是空数据 —— 空图也不该是一片纯黑
    canvas.drawLine(
      Offset(0, baseline),
      Offset(size.width, baseline),
      Paint()
        ..color = Tokens.line
        ..strokeWidth = 1,
    );
    // 25 / 50 / 75% 网格（v2.2.0，O7）+ y 轴标签；不改变折线数据
    for (final double f in <double>[0.25, 0.5, 0.75]) {
      final double y = baseline - f * plotH;
      canvas.drawLine(Offset(0, y), Offset(size.width, y),
          Paint()..color = Tokens.line.withValues(alpha: 0.55)..strokeWidth = 1);
    }
    if (yMaxLabel != null) {
      final TextPainter tp = TextPainter(
        text: TextSpan(text: yMaxLabel, style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
        textDirection: TextDirection.ltr,
      )..layout();
      // 左上角：不压末点
      tp.paint(canvas, const Offset(0, 0));
    }
    if (points.isEmpty || size.width <= 0) return;

    final double plotW = size.width - sidePad * 2;
    final double step = points.length > 1 ? plotW / (points.length - 1) : 0;
    final List<Offset> pts = <Offset>[
      for (int i = 0; i < points.length; i++)
        Offset(
          sidePad + (points.length > 1 ? i * step : plotW / 2),
          baseline - (points[i].clamp(0.0, 1.0)) * plotH,
        ),
    ];

    // 上一周期：虚线（本周实线 + 上周虚线）
    if (previousPoints.isNotEmpty) {
      final double pstep = previousPoints.length > 1
          ? plotW / (previousPoints.length - 1)
          : 0;
      final Paint dashed = Paint()
        ..color = Tokens.text3.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      Offset? prev;
      for (int i = 0; i < previousPoints.length; i++) {
        final Offset pt = Offset(
          sidePad + (previousPoints.length > 1 ? i * pstep : plotW / 2),
          baseline - previousPoints[i].clamp(0.0, 1.0) * plotH,
        );
        if (prev != null) {
          // 手动虚线：每 6px 画 4px
          final double dist = (pt - prev).distance;
          final Offset dir = (pt - prev) / dist;
          double d = 0;
          while (d < dist) {
            final double end = (d + 4).clamp(0, dist);
            canvas.drawLine(prev + dir * d, prev + dir * end, dashed);
            d += 10;
          }
        }
        prev = pt;
      }
    }

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
    // 最后一个点强调一下（"今天"）；合并图/0 值关闭
    if (showEndDot) {
      canvas.drawCircle(pts.last, 3.5, Paint()..color = color);
      canvas.drawCircle(
        pts.last,
        6,
        Paint()
          ..color = color.withValues(alpha: 0.25)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(ViAreaChartPainter old) =>
      old.points != points || old.color != color || old.previousPoints != previousPoints || old.yMaxLabel != yMaxLabel
      || old.showEndDot != showEndDot;
}
