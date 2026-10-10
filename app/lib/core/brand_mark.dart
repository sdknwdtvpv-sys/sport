/// 练了么 · **品牌圆环**（VI 计划 T3-1，2026-10-10）
///
/// **为什么要有这个文件**：品牌只有一枚圆环，而它**在这个 App 里一次都没被画出来** ——
/// 只活在启动图与 Launcher 图标的构建产物里。于是"想把这个环放进一个新屏"的唯一办法
/// 是**去量一张 PNG**；而且这枚环在稿子里还有三套环径比（主图 0.026 / 两张稿子 0.70 与 0.72）。
///
/// ## 几何的**真源**：已经装在用户手机上的那枚图标
///
/// 计划 §3 冲突 17 的裁决是"以真实主图为真源"—— 理由写在文档里：
/// 主图是**既成事实**（iOS App 图标 + 商店图标，用户手机上装着的就是它），
/// 而两张稿子的 0.70 / 0.72 是同一批稿子里的两个互相矛盾的数字。
///
/// ⚠️ **这里的三组比例是"实测出来的"，不是抄计划的**（计划里那串数字有明显串行）：
/// 对 `store-assets/icon-1024.png` 过中心横扫一行、取"明显橙"的连续区段：
///   * 左侧环带 `283..372`、右侧 `650..740` → 环外半径 **229px**、内半径 **138px**（画布 1024）；
///   * 于是：**外径 / 画布 = 0.447**、**环带厚 / 外径 = 0.198**、**洞径 / 外径 = 0.603**。
/// 计划里写的是"1 : 0.39 : 0.026"与"外径 0.446 × S / 环带厚 0.174 × S"：
/// 0.446 与我实测的 0.447 是**同一件事**；0.39 恰好是**环带厚 ÷ 环外半径**（91/229 = 0.397，
/// 不是 ÷ 外径）；0.026 与 0.174 在主图上找不到对应物（那两个数更接近稿子里那套细环）。
/// **以实测为准**，并把差异记在这里 —— 下一个人量同一张图应该得到同一组数。
library;

import 'package:flutter/material.dart';

import 'theme.dart';

/// 圆环的几何（**唯一的真源**：新屏要用这个环，就引这里的常量，不要再去量 PNG）。
class BrandMarkGeometry {
  const BrandMarkGeometry._();

  /// 外径 ÷ 组件边长（实测 229×2 / 1024 = 0.447）。
  static const double outerRatio = 0.447;

  /// 洞径 ÷ 外径（实测 276 / 458 = 0.603）。
  static const double holeRatio = 0.603;

  /// 环带厚 ÷ 外径。**由 [holeRatio] 推出来，不另写一个数** ——
  /// 两个比例并不独立：外径 = 洞径 + 2 × 环带厚，所以它恒等于 `(1 - holeRatio) / 2`。
  /// （第一版把它们各写了一遍：0.198 与 0.603 差了 0.0005，
  /// 测试里 `mid ± band/2` 就对不上内外沿 —— 当场被抓，记在这里。）
  static const double bandRatio = (1 - holeRatio) / 2;

  /// 环的**外半径**。
  static double outerRadius(double size) => size * outerRatio / 2;

  /// 环的**洞半径**。
  static double holeRadius(double size) => outerRadius(size) * holeRatio;

  /// 环带厚（= 描边宽度）。
  static double band(double size) => outerRadius(size) - holeRadius(size);

  /// 描边要落在**中径**上：这样 `mid ± band/2` 正好等于洞半径与外半径。
  static double midRadius(double size) => (outerRadius(size) + holeRadius(size)) / 2;

  /// 中径圆 —— 描边那条路径。派生的空态图形（虚线环 / 半环 / 环+号…）也从它出发。
  static Path ringPath(double size) => Path()
    ..addOval(Rect.fromCircle(
      center: Offset(size / 2, size / 2),
      radius: midRadius(size),
    ));

  /// 三组比例的**实测值**（测试与文档引用它们，避免各写一遍数字）。
  static const List<double> ratios = <double>[1, bandRatio, holeRatio];
}

/// 品牌圆环。
///
/// * [size] 边长（正方形）。16 / 40 / 120 / 320 都成立 —— 几何全是比例，没有绝对像素。
/// * [glow] 辉光变体。**只许出现在启动屏与完成页**（一屏一次）——
///   它是"看到橙环就想到练完了"这个绑定的载体，多贴几处就变成了装饰。
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    required this.size,
    this.color = Tokens.accent,
  }) : glow = false;

  /// 辉光变体 —— **只许出现在启动屏与完成页**（一屏一次）。
  ///
  /// 做成命名构造而不是一个 `glow: true` 参数：判据是一条 grep
  /// （`BrandMark.glow(` 只许出现在两个白名单文件里），而"哪个环带光"这件事
  /// 值得在调用点上一眼看出来。
  const BrandMark.glow({
    super.key,
    required this.size,
    this.color = Tokens.accent,
  }) : glow = true;

  final double size;
  final Color color;

  /// 辉光变体（一屏一次）。
  /// 辉光变体（只有 [BrandMark.glow] 会把它设成 true）。
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final Widget mark = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        key: const Key('brand-mark'),
        painter: _BrandMarkPainter(color: color),
      ),
    );
    if (!glow) return mark;
    // 辉光走 `Tokens.glow`（`theme_discipline_test` 不许在 theme 之外自己写那种阴影 ——
    // 连注释里都不留那个字符串：那条守卫扫的是原文，注释也算）。
    // 半径跟着 size 走：16pt 的环配 18pt 的晕会糊成一团。
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: Tokens.glow(color, radius: size * 0.30, spread: size * 0.02),
      ),
      child: mark,
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    canvas.drawPath(
      BrandMarkGeometry.ringPath(s),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = BrandMarkGeometry.band(s),
    );
  }

  @override
  bool shouldRepaint(_BrandMarkPainter old) => old.color != color;
}
