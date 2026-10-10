/// 练了么 · **休息倒计时只重建那一条**（VI 计划 T2-1，2026-10-10）
///
/// **为什么这一条值得单独一个文件**：它修的是一个**看不见**的性能风险 ——
/// `WorkoutController` 每秒 `notifyListeners()`，而训练屏是
/// `session.addListener(_onChange)` → `setState(() {})`，**整屏重建**。
/// 于是"组间 60 秒"= 整屏每秒重建一次、持续 60 次；而 iOS 上同一屏还活着一个
/// `UITabBar` 平台视图（`glass_surface.dart` 文件头写着"活着的期间 Flutter 的栅格化
/// 不再与 Dart 并行（**整屏代价**）"）。**这是这个 App 最大的性能风险，而它以前没有被测过。**
///
/// 修法：秒级 tick 只写 `restTick`（一个 `ValueNotifier<int>`），
/// 训练屏把那条 ~26pt 的休息带包在 `ValueListenableBuilder` 里听它。
/// 判据（与计划一致）：**休息期间每秒 pump，只有休息带的重建计数增加，整屏计数不变。**
///
/// ⚠️ 计数来自 `workout_screen.dart` 里两个 `assert` 包住的全局量
/// （release 里不存在，与 `debugSwitchTab` 同一种做法）。
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

  void advance(int ms) => _t += ms;
  void dispose() => controller.dispose();
}

void main() {
  testWidgets('★ 休息每秒只重建那条带子，整屏一次都不重建', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await tester.pumpWidget(MaterialApp(
      home: WorkoutScreen(session: WorkoutSession.single(h.controller)),
    ));
    await tester.pump();

    // 记一组 → 休息自动开始（60 秒）
    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();
    expect(find.byKey(const Key('rest-bar')), findsOneWidget, reason: '记一组后该开始休息');

    final int screenBefore = debugWorkoutScreenBuilds;
    final int stripBefore = debugRestStripBuilds;

    // 5 秒：每秒一跳
    for (int i = 0; i < 5; i++) {
      h.advance(1000);
      await tester.pump(const Duration(seconds: 1));
    }

    expect(debugWorkoutScreenBuilds, screenBefore,
        reason: '整屏每秒重建一次正是 T2-1 要修的那个性能风险 —— '
            '计数从 $screenBefore 变成了 $debugWorkoutScreenBuilds');
    expect(debugRestStripBuilds - stripBefore, greaterThanOrEqualTo(5),
        reason: '那 5 秒必须落在休息带上（带子没重建 = 数字根本没动）');
    // 带子上的数字真的在走（重建是有意义的，不是白重建）
    expect(find.text('00:55'), findsOneWidget);
    expect(find.text('还剩 92%'), findsOneWidget, reason: '55 / 60 = 91.7% → 四舍五入 92%');

    h.dispose();
  });

  testWidgets('休息归零仍然是结构性变化：那一帧整屏重建一次、写「休息结束」',
      (WidgetTester tester) async {
    final _Harness h = _Harness();
    await tester.pumpWidget(MaterialApp(
      home: WorkoutScreen(session: WorkoutSession.single(h.controller)),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    final int screenBefore = debugWorkoutScreenBuilds;
    h.advance(60000);
    await tester.pump(const Duration(seconds: 60));
    await tester.pump();

    expect(find.text('休息结束'), findsOneWidget);
    expect(debugWorkoutScreenBuilds, greaterThan(screenBefore),
        reason: '归零要换颜色与文案（success），这一次必须走整屏重建');

    h.dispose();
  });

  test('反向自检：计时器那一跳不许再 notifyListeners（否则整屏又每秒重建）', () {
    final String src =
        File('lib/features/workout/workout_controller.dart').readAsStringSync();
    expect(src.contains('restTick.value = left'), isTrue,
        reason: '窄通道的那一行没了 —— 秒级 tick 又回到整屏重建');
    expect(
        RegExp(r'_restRemaining = left;\s*\n\s*_notify\(\);').hasMatch(src), isFalse,
        reason: '`_restRemaining = left;` 后面直接跟着 `_notify();` —— 那是 T2-1 之前的写法');
  });
}
