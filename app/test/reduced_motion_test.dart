/// 练了么 · **减弱动态效果**（VI 计划 T1-4）
///
/// `interaction-spec.md` §12 挂着一条「`prefers-reduced-motion` 下无动效残留」，
/// 而全仓 `disableAnimations` 曾经 **0 命中** —— 那条验收从来没有对象。
/// 这一组把开关钉住：**读的是 `MediaQuery.disableAnimationsOf`，短路的是 `Motion.forContext`**。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/motion.dart';
import 'package:lianleme/core/reduced_motion.dart';

Future<void> _pump(WidgetTester tester, {required bool reduce, required Widget child}) =>
    tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: child,
      ),
    ));

void main() {
  testWidgets('★ `disableAnimations` 为真时所有 Motion 时长归零', (WidgetTester tester) async {
    late BuildContext ctx;
    await _pump(
      tester,
      reduce: true,
      child: Builder(builder: (BuildContext c) {
        ctx = c;
        return const SizedBox.shrink();
      }),
    );
    await tester.pump();

    expect(reducedMotion(ctx), isTrue);
    // 每一档都归零 —— 降级拿走的是"运动"，不是"信息"
    // （元素**直接出现在终态**，而不是消失）
    for (final Duration d in <Duration>[
      Motion.instant,
      Motion.fast,
      Motion.base,
      Motion.slow,
      Motion.celebrate,
      Motion.restTick,
      Motion.pageTransition,
    ]) {
      expect(Motion.forContext(ctx, d), Duration.zero,
          reason: '$d 在减弱动态效果下必须归零');
    }
  });

  testWidgets('没要求减弱时，时长原样通过', (WidgetTester tester) async {
    late BuildContext ctx;
    await _pump(
      tester,
      reduce: false,
      child: Builder(builder: (BuildContext c) {
        ctx = c;
        return const SizedBox.shrink();
      }),
    );
    await tester.pump();

    expect(reducedMotion(ctx), isFalse);
    expect(Motion.forContext(ctx, Motion.base), Motion.base);
    expect(Motion.forContext(ctx, Motion.pageTransition), Motion.pageTransition);
  });

  testWidgets('纯函数入口 `reducedOr` 与开关同口径', (WidgetTester tester) async {
    expect(reducedOr(true, Motion.base), Duration.zero);
    expect(reducedOr(false, Motion.base), Motion.base);
  });
}
