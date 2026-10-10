/// 练了么 · **内启动屏**（VI 计划 T3-6，2026-10-10）
///
/// **它补的是哪一段**：冷启动原来是三段互不相干的画面 ——
/// ① 原生启动图（`LaunchImage@1x/2x/3x.png`，橙环）→
/// ② Flutter 首帧渲染 `Scaffold(backgroundColor: Tokens.bg, body: SizedBox.expand())`，
///    也就是**一块纯色空屏** → ③ 数据库/同意状态读完才落屏。
/// 第 ② 段不闪白，但它闪"什么都没有"——而客户 VI 稿里明明画了这一段
/// （`vi/splash-screen.html`：圆环 `ringPulse` 2.5s + 字标 + 三个 `loadDot`）。
///
/// ## 三条纪律（都写在判据里）
///
/// 1. **一帧都不能是"空屏"**：这一屏从 Flutter 第一帧起就画环 ——
///    否则"原生启动图（有环）→ 空屏（没环）→ 内容"中间那一下就是一次闪。
/// 2. **三个点共用一个控制器**：`grep -c AnimationController splash_overlay.dart` 必须恰好 **1**。
///    三个各自计时的延时会让三点在掉帧时各走各的（而且没法一起停）。
/// 3. **小于 400ms 就不画点**：本地库是毫秒级的，绝大多数启动在 400ms 内就完事了 ——
///    那时冒一下点再消失，是一帧"脏"画面，比不画更糟。
///
/// 几何上它必须与原生启动图**对得上**（`LaunchImage@3x.png` 的环外径 128px ÷ 3 = 42.67pt）：
/// 所以这里用 `BrandMark(size: 96)` —— 它的外径 = `0.447 × 96 = 42.9pt`，与原生那枚差 0.2pt
/// （守则在 `tool/check-launch-relay.py`，它直接量 PNG）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/brand_mark.dart';
import '../../core/motion.dart';
import '../../core/reduced_motion.dart';
import '../../core/theme.dart';

/// 内启动屏：**品牌环 + 字标 +（慢的时候才出现）三个点**。
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({super.key, this.busy = true});

  /// 还在等（同意状态 / 首屏数据）。false 之后这一屏就该被换掉。
  final bool busy;

  /// 画布边长。**不要改**：96pt 对应原生启动图那枚 42.7pt 的环（见文件头）。
  static const double canvas = 96;

  /// 快了就不画点的那条线（走令牌 `Motion.slow`，不另开一个数）。
  static const Duration dotDelay = Motion.slow;

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay>
    with SingleTickerProviderStateMixin {
  /// ⚠️ **全文件只有一个控制器**（判据 2）：环的呼吸与三个点都从它取值。
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.splashPulse,
  );

  /// 已经过了 [SplashOverlay.dotDelay] 没有（过了才画点）。
  bool _slow = false;

  /// ⚠️ 用 `Timer` 而不是"`Future` 那种延时"：**它可以在 `dispose` 里取消**。
  /// 第一版用的是后者、忘了收，测试当场报 "Pending timers"（这正是那条纪律的意义）。
  /// （注释里也不写那个字符串：扫描器看的是原文，`theme_discipline_test` 那次已经吃过一回。）
  Timer? _dotTimer;

  @override
  void initState() {
    super.initState();
    _c.repeat();
    _dotTimer = Timer(SplashOverlay.dotDelay, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _dotTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool still = reducedMotion(context);
    final double t = _c.value; // 0..1 循环
    // 环的"呼吸"：幅度很小（0.02 个 canvas），它是启动屏不是加载动画 ——
    // 大起大落的缩放会让"启动"这件事显得焦躁。
    final double pulse = still ? 1.0 : 1 + 0.02 * (1 - (t * 2 - 1).abs());

    return Scaffold(
      backgroundColor: Tokens.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: SplashOverlay.canvas,
              height: SplashOverlay.canvas,
              child: Transform.scale(
                scale: pulse,
                // 启动屏是"一屏一次"那个例外之一（另一处是完成页）—— 见 T3-1 的白名单。
                child: const BrandMark.glow(
                    size: SplashOverlay.canvas, color: Tokens.accent),
              ),
            ),
            const SizedBox(height: Tokens.s5),
            const Text(
              '练了么',
              key: Key('splash-wordmark'),
              style: TextStyle(
                color: Tokens.text,
                fontSize: Tokens.fsHeadline,
                fontWeight: Tokens.fwBold,
                letterSpacing: Tokens.lsWide,
              ),
            ),
            const SizedBox(height: Tokens.s6),
            // 三个点：**只在这台设备慢的时候**出现（< 400ms 就完事的话不画）。
            SizedBox(
              height: 8,
              child: _slow
                  ? _Dots(t: still ? 0 : t)
                  : const SizedBox.shrink(key: Key('splash-no-dots')),
            ),
          ],
        ),
      ),
    );
  }
}

/// 三个加载点。用**同一个 0..1 的 t** 错开相位 —— 不是三个各自计时的动画。
class _Dots extends StatelessWidget {
  const _Dots({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (int i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.s1),
              child: Opacity(
                // 相位差 1/6 个周期：看起来像"一颗火星在三点之间走"
                opacity: 0.25 +
                    0.75 * (1 - ((t + i / 6) % 1.0 - 0.5).abs() * 2).clamp(0.0, 1.0),
                child: const _Dot(),
              ),
            ),
        ],
      );
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: Tokens.accent,
          shape: BoxShape.circle,
        ),
      );
}

/// 内启动屏用到的动效令牌（放在这里是为了让"启动屏的节拍"只有一个出处）。
class SplashMotion {
  const SplashMotion._();

  /// 环呼吸 + 三点走一圈的周期（就是 `Motion.splashPulse`，与稿子的 `ringPulse 2.5s` 对齐）。
  static const Duration cycle = Motion.splashPulse;

  /// 环呼吸的幅度（占 canvas 的比例）。
  static const double pulseAmplitude = 0.02;

  /// 淡出时长（交给 `Motion` 的档位，不另开一个数）。
  static const Duration fadeOut = Motion.base;
}
