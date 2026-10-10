/// 练了么 · **休息进度条的方向**（VI 计划 T0-1，2026-10-10）
///
/// **为什么单独一条测试**：这一行是"组间 60 秒"里**唯一的时间线索**，而它原来是错的 ——
/// 条的 `value` 写的是 `1 - 剩余/总`（**条在长**），右边那行字写的是「还剩 41%」（数字在减）。
/// 同一行里两个方向相反的信号，用户扫一眼得到的是"快到了"还是"刚开始"完全靠猜。
///
/// 判据（与计划里的可跑判据一致）：
///   1. 剩余一半时条宽 ≈ 半宽，且百分比文案同向；
///   2. 剩得少时条**必须更短**（不是更长）；
///   3. 休息结束时条清空。
///
/// ⚠️ 休息倒计时按**墙上时钟**算（`restEndsAtMs - clock()`），所以"让时间过去"必须
/// 同时推进假钟与 `tester.pump` —— 这条与 `workout_flow_test.dart` 的 harness 同源。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/analytics.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/sync_queue.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/workout/workout_controller.dart';
import 'package:lianleme/features/workout/workout_screen.dart';
import 'package:lianleme/features/workout/workout_session.dart';

const ExerciseSpec _bench = ExerciseSpec(
  id: 'ex_bb_bench_press',
  name: '杠铃卧推',
  weightIncrement: 2.5,
  defaultWeightKg: 40,
  // 60 秒：判据里的"剩一半 = 30 秒"就是这么来的
  defaultRestSec: 60,
);

const PlanTarget _plan = PlanTarget(
  targetSets: 3,
  targetRepsLow: 8,
  targetRepsHigh: 10,
);

class _Harness {
  _Harness() {
    controller = WorkoutController(
      exercise: _bench,
      plan: _plan,
      analytics: RecordingAnalytics(),
      store: InMemoryLocalStore(),
      syncQueue: InMemorySyncQueue(),
      clock: () => _t,
    );
  }

  late final WorkoutController controller;
  int _t = 1000000;

  /// 把假钟往前推 [ms]（与 `tester.pump` 配对用）。
  void advance(int ms) => _t += ms;

  void dispose() => controller.dispose();
}

void main() {
  testWidgets('★ 休息进度条随剩余时间变短，方向与百分比一致', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await tester.pumpWidget(MaterialApp(
      home: WorkoutScreen(session: WorkoutSession.single(h.controller)),
    ));
    await tester.pump();

    // 记一组 → 休息自动开始（60 秒）
    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();
    expect(find.byKey(const Key('rest-bar')), findsOneWidget, reason: '记一组后该开始休息');

    double bar() => tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .value!;
    String pct() =>
        tester.widget<Text>(find.textContaining('还剩')).data!;

    expect(bar(), closeTo(1.0, 0.02), reason: '刚休息 → 还剩 100%');
    expect(pct(), '还剩 100%');

    // 时间过去一半
    h.advance(30000);
    await tester.pump(const Duration(seconds: 30));
    expect(bar(), closeTo(0.5, 0.03), reason: '剩一半 → 条也该是一半');
    expect(pct(), '还剩 50%');

    // 再过 10 秒（剩 20 秒）
    h.advance(10000);
    await tester.pump(const Duration(seconds: 10));
    final double at20 = bar();
    expect(at20, lessThan(0.5), reason: '剩得少 → 条必须更短（原来这里是反的：条在长）');
    expect(pct(), '还剩 33%');

    // 走到结束
    h.advance(20000);
    await tester.pump(const Duration(seconds: 20));
    expect(bar(), 0, reason: '休息结束时条清空');

    h.dispose();
  });

  test('源码里不许再出现反向写法（与门禁里的 grep 判据同源）', () {
    // 判据与 `docs/plan-vi-2026-10-10.md` T0-1 的第 2 条一致：
    // `grep -n "1 - restRemainingSec" app/lib/.../workout_screen.dart` → 0 命中。
    final String src =
        File('lib/features/workout/workout_screen.dart').readAsStringSync();
    expect(src.contains('1 - restRemainingSec'), isFalse,
        reason: '条的方向必须是"还剩占比"，不是"已过占比"');
    expect(src.contains('c.restRemainingSec / total'), isTrue,
        reason: '正解就写在那一行上 —— 找不到说明这段被重写了，回来核对方向');
  });
}
