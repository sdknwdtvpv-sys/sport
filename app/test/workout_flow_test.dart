/// 练了么 · 训练主屏 widget 测试
///
/// 这是 `docs/interaction-spec.md` §12「设计验收清单」的自动化版本。
/// 覆盖三条最容易在迭代中被改坏的规则：
///   1. 1 次点击 = 1 组（tap_count 中位数必须为 1）
///   2. 长按不误记
///   3. 离线可用、且训练中不发网络请求
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/analytics.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/sync_queue.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/workout/workout_controller.dart';
import 'package:lianleme/features/workout/workout_screen.dart';

/// 与 seed/exercises.json 的 ex_bb_bench_press 保持一致。
const ExerciseSpec _bench = ExerciseSpec(
  id: 'ex_bb_bench_press',
  name: '杠铃卧推',
  weightIncrement: 2.5,
  defaultWeightKg: 40,
  defaultRestSec: 120,
);

const PlanTarget _plan3x8to10 = PlanTarget(
  targetSets: 3,
  targetRepsLow: 8,
  targetRepsHigh: 10,
);

class _Harness {
  _Harness({LastSession? lastSession}) {
    controller = WorkoutController(
      exercise: _bench,
      plan: _plan3x8to10,
      analytics: analytics,
      store: store,
      syncQueue: syncQueue,
      lastSession: lastSession,
      clock: () => _t++,
    );
  }

  final RecordingAnalytics analytics = RecordingAnalytics();
  final InMemoryLocalStore store = InMemoryLocalStore();
  final InMemorySyncQueue syncQueue = InMemorySyncQueue();
  late final WorkoutController controller;

  int _t = 1000;

  List<Map<String, Object?>> get setEvents => analytics.propsOf('set_logged');
}

Future<void> _pump(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(), home: WorkoutScreen(controller: h.controller)),
  );
}

/// 必须显式销毁页面并 dispose 控制器，否则 Timer.periodic 会留下 pending timer，
/// testWidgets 会直接判失败。这是 widget 测试里最常见的假失败来源。
Future<void> _teardown(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  h.controller.dispose();
}

void main() {
  testWidgets('点大按钮 = 记录 1 组，tap_count = 1', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    expect(find.text('40kg × 8'), findsOneWidget, reason: '按钮上就是要写入的值');

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    expect(h.controller.loggedSets.length, 1);
    expect(h.setEvents.length, 1);
    expect(h.setEvents.single['tap_count'], 1);
    expect(h.setEvents.single['tap_kinds'], <String>['big_button']);
    expect(h.setEvents.single['weight_kg'], 40);

    await _teardown(tester, h);
  });

  testWidgets('连点两次 = 两条记录，各自 tap_count = 1', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    expect(h.controller.loggedSets.length, 2);
    expect(
      h.setEvents.map((Map<String, Object?> p) => p['tap_count']).toList(),
      <int>[1, 1],
      reason: '两次点击必须是两个独立周期，不能被合并计数',
    );

    await _teardown(tester, h);
  });

  testWidgets('长按不误记：弹出修改层，且不产生任何记录', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    await tester.longPress(find.byKey(const Key('big-log-button')));
    await tester.pump();

    expect(h.controller.loggedSets, isEmpty, reason: '长按绝不能顺手记一组');
    expect(h.analytics.countOf('set_logged'), 0);
    expect(find.byKey(const Key('sheet')), findsOneWidget);
    expect(h.controller.sheetOpen, isTrue);

    await _teardown(tester, h);
  });

  testWidgets('长按 → 改重量 → 确定 → 记录：tap_count = 4，且新重量生效',
      (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    await tester.longPress(find.byKey(const Key('big-log-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('step-weight-up'))); // 40 → 42.5
    await tester.pump();
    await tester.tap(find.byKey(const Key('sheet-confirm')));
    await tester.pump();
    expect(find.byKey(const Key('sheet')), findsNothing);

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    expect(h.setEvents.single['tap_count'], 4);
    expect(h.setEvents.single['weight_kg'], 42.5);
    expect(h.controller.loggedSets.single.weightKg, 42.5);

    await _teardown(tester, h);
  });

  testWidgets('离线可用：记录照常成功、进同步队列、界面不报错', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    h.controller.setOffline(true);
    await tester.pump();
    expect(find.byKey(const Key('offline-chip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    expect(h.controller.loggedSets.length, 1, reason: '离线必须能完整记录');
    expect(h.syncQueue.pending, 1, reason: '写入进队列，等联网后补报');
    expect(h.setEvents.single['is_offline'], isTrue);
    expect(find.textContaining('失败'), findsNothing, reason: '离线不允许弹错误 UI');

    // 恢复网络后补报成功，队列清空
    h.controller.setOffline(false);
    await tester.pump();
    final SyncOutcome outcome = await h.controller.flushSync();
    expect(outcome, SyncOutcome.ok);
    expect(h.syncQueue.pending, 0);

    await _teardown(tester, h);
  });

  testWidgets('达到计划组数后不禁用按钮，只提示', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    for (int i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('big-log-button')));
      await tester.pump();
    }
    expect(h.controller.loggedSets.length, 3);

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    expect(h.controller.loggedSets.length, 4, reason: '计划是建议不是牢笼，禁止加组会逼用户回备忘录');
    expect(
      tester.widget<Text>(find.byKey(const Key('workout-hint'))).data,
      contains('已达到计划组数'),
    );

    await _teardown(tester, h);
  });

  testWidgets('训练中不重算建议（建议是本次训练的处方）', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    final String? before =
        tester.widget<Text>(find.byKey(const Key('suggestion-reason'))).data;

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    final String? after =
        tester.widget<Text>(find.byKey(const Key('suggestion-reason'))).data;

    expect(after, before,
        reason: '每组后重算会让提示立刻变成「上次只完成 1 组，先把组数补满」这种荒谬文案');

    await _teardown(tester, h);
  });

  testWidgets('记录后自动开始休息计时，跳过可结束', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();
    expect(h.controller.restRunning, isTrue);
    expect(h.controller.restRemainingSec, 120);

    await tester.pump(const Duration(seconds: 1));
    expect(h.controller.restRemainingSec, 119, reason: '倒计时必须真的走');

    await tester.tap(find.byKey(const Key('skip-rest')));
    await tester.pump();
    expect(h.controller.restRunning, isFalse);
    expect(find.text('休息结束'), findsOneWidget);
    expect(h.analytics.countOf('rest_skipped'), 1);

    await _teardown(tester, h);
  });

  testWidgets('记录会落到本地库（本地优先），并写入同步队列', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    final List<SetRecord> stored = await h.store.setsFor(h.controller.workout.id);
    expect(stored.length, 1);
    expect(h.controller.workout.totalSets, 1);
    expect(h.controller.workout.totalVolume, 320); // 40kg × 8

    await _teardown(tester, h);
  });
}
