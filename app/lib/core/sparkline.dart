/// 练了么 · 自绘折线（容量趋势）
///
/// 不引图表库：为一条线加一个依赖不值得（项目 pubspec 里写着「依赖保持最小」）。
///
/// 从 `progress_screen.dart` 提出来共用 —— S8「进步」的 7 天曲线和
/// S9「全部数据」的动作容量趋势要的是同一种东西，抄一份迟早会分叉。
library;

import 'package:flutter/material.dart';

import 'theme.dart';

/// [values] 是 0..1 的比例，长度即点数。
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.color});

  final List<double> values;

  /// 默认用强调色；S9 里区分不同指标时可以换。
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: SparklinePainter(values, color: color ?? Tokens.accent),
      );
}

class SparklinePainter extends CustomPainter {
  SparklinePainter(this.values, {this.color = Tokens.accent});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final Paint line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final Paint dot = Paint()..color = color;
    final Paint baseline = Paint()
      ..color = Tokens.line
      ..strokeWidth = 1;

    // 底部基线：全 0 时也让用户看得出这是"一条线"，而不是空白
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      baseline,
    );

    final double stepX =
        values.length > 1 ? size.width / (values.length - 1) : 0;
    final double usableH = size.height - 8;

    final Path path = Path();
    for (int i = 0; i < values.length; i++) {
      final double x = stepX * i;
      final double y = size.height - 4 - usableH * values[i].clamp(0.0, 1.0);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, line);

    for (int i = 0; i < values.length; i++) {
      final double x = stepX * i;
      final double y = size.height - 4 - usableH * values[i].clamp(0.0, 1.0);
      canvas.drawCircle(Offset(x, y), 3, dot);
    }
  }

  @override
  bool shouldRepaint(SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

/// 把一串非负数值归一化成 0..1（全 0 时返回全 0，不除以 0）。
List<double> normalize(List<double> raw) {
  if (raw.isEmpty) return const <double>[];
  final double maxV = raw.reduce((double a, double b) => a > b ? a : b);
  if (maxV <= 0) return List<double>.filled(raw.length, 0);
  return raw.map((double v) => v / maxV).toList();
}
