/// 练了么 · **空态**（VI 计划 T3-2，2026-10-10）
///
/// **为什么要有这个文件**：全 App 16 处空态**全部**是"一到两行灰字、无图形、无按钮"，
/// 其中只有 5 处做到了 `docs/copy.md` 判据第 4 条的"说出下一步"。
/// 而 `text3` 在 `bg` 上只有 3.23:1 —— 连"被读到"都保证不了，更不用说它出现在一个
/// 深色、暗光、屏幕有汗的健身房里。
///
/// 两条纪律，都做进了**类型**里而不是只写在文档里：
///   1. **按钮必填**（[EmptyState.action] + [EmptyState.onAction] 都是必填参数）——
///      "说完事实就走人"的空态在编译期就写不出来；
///   2. **图形只许是品牌环的派生**（[EmptyArt] 的五个 painter 都从
///      [BrandMarkGeometry] 取几何）—— 空态是这套视觉语言里最容易长出"随手画的插图"的地方。
library;

import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import 'brand_mark.dart';
import 'theme.dart';

/// 空态的图形。五种都从品牌环派生（缺什么、找什么、被挡住，各对应一种改法）。
enum EmptyArt {
  /// 虚线的环：**还没有开始**（第一次训练、第一次记录）。
  dashedRing,

  /// 只有下半圈的环：**攒了一半**（练了一点、还看不出趋势）。
  halfRing,

  /// 环里一个加号：**这里可以加东西**（没有记录 → 去加一条）。
  ringWithPlus,

  /// 环里一把锁：**要解锁才有**（成就、需要权限的东西）。
  ringWithLock,

  /// 环里一个放大镜：**没找到**（搜索无结果）。
  ringSearch,
}

/// 一处空态：图形 + 一句事实 +（可选）一句解释 + **一个下一步**。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.art,
    required this.title,
    required this.action,
    required this.onAction,
    this.body,
  });

  final EmptyArt art;

  /// 事实句（**别在这里抒情** —— `docs/copy.md` 说不动的句子保持原样搬进来）。
  final String title;

  /// 一句解释（可选）。没有就不写 —— 空态最容易在这里长出一段废话。
  final String? body;

  /// 下一步的按钮文案。
  final String action;

  /// 下一步真的做什么。**必填**：空态不许只说话不给出路。
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _EmptyArtPaint(art: art, diameter: 96),
        const SizedBox(height: Tokens.s4),
        Text(
          title,
          key: const Key('empty-title'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            // ⚠️ `text3` → `text2`（T0-3 的口径）：空态这句话是**功能性文本**，
            // 它得先被读到，才谈得上"下一步"。
            color: Tokens.text2,
            fontSize: Tokens.fsSub,
            height: Tokens.lhNormal,
          ),
        ),
        if (body != null) ...<Widget>[
          const SizedBox(height: Tokens.s1),
          Text(
            body!,
            key: const Key('empty-body'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Tokens.text3,
              fontSize: Tokens.fsCap,
              height: Tokens.lhNormal,
            ),
          ),
        ],
        const SizedBox(height: Tokens.s3),
        // 下一步：胶囊底用 `Tokens.field`（T0-2 定下来的"可交互的底"），
        // **不抢 accent** —— 空态所在的屏往往已经有一个主按钮（首页那颗"开始今天的训练"），
        // 一屏 accent ≤ 1 这条不变量要守住。
        TextButton(
          key: const Key('empty-action'),
          onPressed: onAction,
          style: TextButton.styleFrom(
            backgroundColor: Tokens.field,
            foregroundColor: Tokens.text,
            padding: const EdgeInsets.symmetric(horizontal: Tokens.s5, vertical: Tokens.s3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Tokens.rPill),
            ),
          ),
          child: Text(action,
              style: const TextStyle(fontSize: Tokens.fsSub, fontWeight: Tokens.fwStrong)),
        ),
      ],
    );
  }
}

/// 图形那一层（**全部几何都来自 [BrandMarkGeometry]**）。
class _EmptyArtPaint extends StatelessWidget {
  const _EmptyArtPaint({required this.art, required this.diameter});

  final EmptyArt art;

  /// 图形的边长。**不叫 `size`**：`icon_spec_test` 有一条守卫扫 `size: <数字>`
  /// （图标只有 4 档），而这是图形的直径、与图标那套无关 —— 换个名字比放宽守卫诚实。
  final double diameter;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: diameter,
        height: diameter,
        child: CustomPaint(
          key: const Key('empty-art'),
          painter: EmptyArtPainter(art: art, color: Tokens.lineStrong),
        ),
      );
}

/// 把 [EmptyArt] 画出来。公开是为了让测试直接验"五个图形都由品牌环派生"。
class EmptyArtPainter extends CustomPainter {
  const EmptyArtPainter({required this.art, required this.color});

  final EmptyArt art;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    // 品牌环那三件套：外径 / 环带 / 洞 —— 五种图形全部从这里取，不另编一套尺寸。
    final double outer = BrandMarkGeometry.outerRadius(s);
    final double hole = BrandMarkGeometry.holeRadius(s);
    final double band = BrandMarkGeometry.band(s);
    final Path ring = BrandMarkGeometry.ringPath(s);

    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = band
      ..strokeCap = StrokeCap.round;
    final Paint thin = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = band * 0.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (art) {
      case EmptyArt.dashedRing:
        // 虚线：沿中径圆把笔画切成一段段（`PathMetric.extractPath` —— 与完成页那枚勾同一套做法）
        final PathMetric m = ring.computeMetrics().first;
        const int dashes = 12;
        final double seg = m.length / (dashes * 2);
        for (int i = 0; i < dashes; i++) {
          canvas.drawPath(m.extractPath(i * seg * 2, i * seg * 2 + seg), stroke);
        }
      case EmptyArt.halfRing:
        // 下半圈：用同一个中径画弧（起点 -180°，扫 180°）
        canvas.drawArc(
          Rect.fromCircle(center: Offset(s / 2, s / 2), radius: (outer + hole) / 2),
          math.pi,
          math.pi,
          false,
          stroke,
        );
      case EmptyArt.ringWithPlus:
        canvas.drawPath(ring, stroke);
        final double r = hole * 0.45;
        canvas.drawLine(Offset(s / 2 - r, s / 2), Offset(s / 2 + r, s / 2), thin);
        canvas.drawLine(Offset(s / 2, s / 2 - r), Offset(s / 2, s / 2 + r), thin);
      case EmptyArt.ringWithLock:
        canvas.drawPath(ring, stroke);
        final double w = hole * 0.62;
        final double h = hole * 0.46;
        final Rect body = Rect.fromCenter(
            center: Offset(s / 2, s / 2 + h * 0.22), width: w, height: h);
        canvas.drawRRect(
            RRect.fromRectAndRadius(body, Radius.circular(h * 0.28)), thin);
        canvas.drawArc(
          Rect.fromCenter(
              center: Offset(s / 2, s / 2 - h * 0.30), width: w * 0.72, height: h * 1.1),
          math.pi,
          math.pi,
          false,
          thin,
        );
      case EmptyArt.ringSearch:
        canvas.drawPath(ring, stroke);
        final Offset c = Offset(s / 2 - hole * 0.10, s / 2 - hole * 0.10);
        final double r = hole * 0.34;
        canvas.drawCircle(c, r, thin);
        canvas.drawLine(
          Offset(c.dx + r * 0.72, c.dy + r * 0.72),
          Offset(c.dx + r * 1.6, c.dy + r * 1.6),
          thin,
        );
    }
  }

  @override
  bool shouldRepaint(EmptyArtPainter old) => old.art != art || old.color != color;
}
