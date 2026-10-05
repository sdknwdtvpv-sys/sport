/// 练了么 · 训练屏的"体外"两件事（v1.53）：**屏幕常亮**与**休息结束的提示**
///
/// 真机上"屏幕到底熄没熄""锁屏上有没有那条通知"没法自动断言，但**什么时候开、什么时候关**
/// 是逻辑，必须钉住 —— 这一组测试就是钉它。两件都走"接口 + 替身"，理由与
/// `RestActivityBridge` 一样：失败必须静默，且不能挡住记组。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/analytics.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/sync_queue.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/workout/rest_cue.dart';
import 'package:lianleme/features/workout/screen_awake.dart';
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

class _FakeScreenAwake implements ScreenAwake {
  final List<bool> calls = <bool>[];

  @override
  Future<void> keepOn() async => calls.add(true);

  @override
  Future<void> release() async => calls.add(false);
}

class _FakeRestCue implements RestCue {
  final List<(String, String)> shown = <(String, String)>[];
  int cancelled = 0;

  @override
  Future<void> show({required String title, required String body}) async =>
      shown.add((title, body));

  @override
  Future<void> cancel() async => cancelled += 1;
}

class _Harness {
  _Harness() {
    controller = WorkoutController(
      exercise: _bench,
      plan: _plan,
      analytics: analytics,
      store: store,
      syncQueue: syncQueue,
      restCue: restCue,
      clock: () => _t,
    );
  }

  final RecordingAnalytics analytics = RecordingAnalytics();
  final InMemoryLocalStore store = InMemoryLocalStore();
  final InMemorySyncQueue syncQueue = InMemorySyncQueue();
  final _FakeRestCue restCue = _FakeRestCue();
  final _FakeScreenAwake screenAwake = _FakeScreenAwake();
  late final WorkoutController controller;

  int _t = 900000;

  void advance(int ms) => _t += ms;
}

void main() {
  testWidgets('进训练屏开常亮、离开关掉（不常驻、不全局）', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: WorkoutScreen(
        session: WorkoutSession.single(h.controller),
        screenAwake: h.screenAwake,
      ),
    ));
    await tester.pump();

    expect(h.screenAwake.calls, <bool>[true], reason: '进训练屏就该亮着');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(h.screenAwake.calls, <bool>[true, false],
        reason: '离开训练屏必须还回去 —— 全局常亮是费电的');
    h.controller.dispose();
  });

  test('休息**中**不发提示（只有走到 0 才发）', () {
    final _Harness h = _Harness();
    h.controller.onBigButtonTap();

    h.advance(30 * 1000); // 才歇了一半

    expect(h.restCue.shown, isEmpty,
        reason: '休息中途发通知等于每隔几秒打扰一次');
    h.controller.dispose();
  });

  test('离开训练屏（dispose）→ 撤掉那条体外提示', () {
    final _Harness h = _Harness();
    h.controller.onBigButtonTap();

    h.controller.dispose();

    expect(h.restCue.cancelled, 1,
        reason: '人都退出训练了，锁屏上还挂着"休息结束"就是噪音');
  });

  test('跳过休息 → 撤掉那条体外提示（人已经在看屏幕了）', () {
    final _Harness h = _Harness();
    h.controller.onBigButtonTap();

    h.controller.skipRest();

    expect(h.restCue.cancelled, 1);
    h.controller.dispose();
  });

  testWidgets('休息走到 0：**同时**发提示（体外）与震动（近身）', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: WorkoutScreen(
        session: WorkoutSession.single(h.controller),
        screenAwake: h.screenAwake,
      ),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();
    h.advance(61 * 1000);
    await tester.pump(const Duration(seconds: 1));

    expect(h.controller.restRunning, isFalse, reason: '休息该结束了');
    expect(h.restCue.shown.length, 1, reason: 'Android 上锁屏什么都没有，靠这条通知');
    expect(h.restCue.shown.single.$1, '休息结束');
    expect(h.restCue.shown.single.$2, contains('下一组'));

    await tester.pumpWidget(const SizedBox.shrink());
    h.controller.dispose();
  });
}
