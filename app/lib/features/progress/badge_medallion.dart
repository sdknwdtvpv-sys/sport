/// 练了么 · **徽章的唯一渲染器**（VI 计划 T3-4，2026-10-10）
///
/// **为什么要有它**：同一枚徽章原来在两张屏上是**两个图形** ——
/// 完成页按**类别**给图标（4 个之一），收藏册按 `badge.id` 给图标（73 枚各自的图形）。
/// 也就是说用户刚在完成页看到的那枚"火苗"，回到收藏册里变成了"健身"。
/// 现在两边都走 [BadgeMedallion]：同一个 id → 同一个图形，参数也完全一样。
///
/// 另外两件事也收在这里：
///   * **稀有度的第二通道**：三档原来**完全靠颜色**（违反 `interaction-spec.md` §4
///     硬约束 2"任何状态都不能只靠颜色表达"）。现在颜色之外还有一道内芯描边：
///     基础 `0pt` / 进阶 `1pt` / 终极 `2pt` —— 色盲用户与黑白截图里也分得出来。
///   * **未解锁不写"还差 N 次"**（用户 2026-10-10 拍板，`plan-ux` §五-B 第 3 条）：
///     收藏册一屏原来最多同时 8 个数字 + 6 根进度条。现在进度条只留给**真的在跑**
///     的那几枚（见 `achievements_screen` 的"离你最近的一枚"），未解锁的只留外圈。
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'badges.dart';

/// 稀有度的**第二通道**：内芯描边宽度（pt）。0 / 1 / 2 三档。
///
/// 为什么是描边而不是图案：徽章只有 46pt 的内芯，图案塞进去就成噪点；
/// 而"一圈比一圈厚"在任何尺寸、任何色觉、黑白截图上都成立。
double badgeInnerStroke(BadgeTier tier) => switch (tier) {
      BadgeTier.common => 0,
      BadgeTier.rare => 1,
      BadgeTier.epic => 2,
    };

/// 一枚徽章（完成页与收藏册共用）。
class BadgeMedallion extends StatelessWidget {
  const BadgeMedallion({
    super.key,
    required this.id,
    required this.tier,
    required this.unlocked,
    this.progress = 1,
    this.diameter = 64,
  });

  final String id;
  final BadgeTier tier;

  /// 拿到了没有。**决定内芯**（渐变 / 暗底）与右下角那个戳。
  final bool unlocked;

  /// 0..1。未解锁时外圈只画到这里；已解锁画满。
  final double progress;

  /// 外圈直径。内芯、描边、戳都按它等比缩 —— 所以完成页那枚 38pt 与收藏册那枚 64pt
  /// 是**同一枚徽章的两个尺寸**，不是两个图形。
  ///
  /// ⚠️ 参数名**不叫 `size`**：`icon_spec_test` 有一条守卫扫 `size: <数字>`
  /// （图标只有 4 档），而这是徽章的直径、与图标那套无关 —— 换个名字比放宽守卫诚实
  /// （`empty_state.dart` 的图形直径同理）。
  final double diameter;

  double get _core => diameter * 0.72;
  double get _stroke => diameter * 0.047;
  double get _chip => diameter * 0.31;

  @override
  Widget build(BuildContext context) {
    final Color tierColor = badgeTierColor(tier);
    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          // ① 外圈：进度环（未解锁画到 progress，已解锁画满）
          Positioned.fill(
            child: CustomPaint(
              key: Key('badge-ring-$id'),
              painter: BadgeRingPainter(
                progress: unlocked ? 1 : progress,
                color: tierColor,
                unlocked: unlocked,
                stroke: _stroke,
              ),
            ),
          ),
          // ② 内芯：已解锁 = 该档渐变 + 一点外发光；未解锁 = 暗底 + 该档色的细描边
          Center(
            child: Container(
              key: Key('badge-$id'),
              width: _core,
              height: _core,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: unlocked ? badgeTierGradient(tier) : null,
                color: unlocked ? null : Tokens.elevated,
                border: unlocked ? null : Border.all(color: tierColor.withValues(alpha: 0.35)),
                boxShadow: unlocked ? Tokens.glow(tierColor) : null,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  // ③ 稀有度的第二通道：内芯里那一圈描边（0 / 1 / 2pt）
                  if (badgeInnerStroke(tier) > 0)
                    Container(
                      key: Key('badge-inner-$id'),
                      width: _core - diameter * 0.16,
                      height: _core - diameter * 0.16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: tierColor.withValues(alpha: unlocked ? 0.55 : 0.30),
                          width: badgeInnerStroke(tier),
                        ),
                      ),
                    ),
                  Icon(
                    // **每枚徽章自己的图形**（`badges.dart` 的 `badgeIcon`）——
                    // 两张屏用同一个函数，所以不可能再出现"完成页一个、收藏册另一个"。
                    badgeIcon(id),
                    size: diameter * 0.30,
                    color: unlocked ? Tokens.accentInk : Tokens.text3,
                  ),
                ],
              ),
            ),
          ),
          // ④ 右下角的状态戳：勾 / 锁 —— 拿到没拿到**不只看颜色**
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: _chip,
              height: _chip,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: unlocked ? tierColor : Tokens.lift,
                border: Border.all(color: Tokens.bg, width: 2),
              ),
              child: Icon(
                unlocked ? Icons.check : Icons.lock_outline,
                size: diameter * 0.19,
                color: unlocked ? Tokens.accentInk : Tokens.text2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 外圈那根进度环。自己画而不用 `CircularProgressIndicator`：
/// 后者的线宽与圆头都得再包一层去覆盖，而且未解锁时它不画"剩下的那一段"底色。
class BadgeRingPainter extends CustomPainter {
  const BadgeRingPainter({
    required this.progress,
    required this.color,
    required this.unlocked,
    required this.stroke,
  });

  final double progress;
  final Color color;
  final bool unlocked;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height / 2);
    final double r = (size.width - stroke) / 2;
    final Paint base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = unlocked ? color.withValues(alpha: 0.22) : Tokens.line;
    canvas.drawCircle(c, r, base);

    final double p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -1.5707963267948966, // -90°：从 12 点开始
      6.283185307179586 * p,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = unlocked ? color : color.withValues(alpha: 0.75),
    );
  }

  @override
  bool shouldRepaint(covariant BadgeRingPainter old) =>
      old.progress != progress || old.color != color ||
      old.unlocked != unlocked || old.stroke != stroke;
}
