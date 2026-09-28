/// 练了么 · S6 动作切换（会话层 + 底部条 + 左右滑动）
///
/// 这一项原本是**假的**：底部那条「‹ 上一个动作　动作 1 / 1　下一个动作 ›」
/// 是 `const Row` 里三个纯 Text，点什么都没反应；而且没有任何滑动手势。
/// 假的可点按元件比没有更糟（项目在 Tab 栏上踩过一次），所以这里既测
/// "真的能切"，也测"每个动作的进度互相独立"。
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
import 'package:lianleme/features/workout/workout_session.dart';

const PlanTarget _plan = PlanTarget(
  targetSets: 3,
  targetRepsLow: 8,
  targetRepsHigh: 10,
);

WorkoutController _controller(String id, String name, {double weight = 40}) =>
    WorkoutController(
      exercise: ExerciseSpec(id: id, name: name, weightIncrement: 2.5, defaultWeightKg: weight),
      plan: _plan,
      analytics: RecordingAnalytics(),
      store: InMemoryLocalStore(),
      syncQueue: InMemorySyncQueue(),
    );

/// 三个动作的会话：卧推 / 深蹲 / 硬拉
class _Harness {
  _Harness()
      : bench = _controller('bench', '杠铃卧推'),
        squat = _controller('squat', '杠铃深蹲', weight: 60),
        dead = _controller('dead', '硬拉', weight: 80) {
    session = WorkoutSession(<WorkoutController>[bench, squat, dead]);
  }

  final WorkoutController bench;
  final WorkoutController squat;
  final WorkoutController dead;
  late final WorkoutSession session;

  void dispose() {
    session.dispose();
    bench.dispose();
    squat.dispose();
    dead.dispose();
  }
}

Future<void> _pump(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: WorkoutScreen(session: h.session),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('会话本身', () {
    test('next / previous 在边界处不动', () {
      final _Harness h = _Harness();
      expect(h.session.index, 0);
      expect(h.session.canGoPrevious, isFalse);

      h.session.previous(); // 已经在第一个
      expect(h.session.index, 0);

      h.session.next();
      h.session.next();
      expect(h.session.index, 2);
      expect(h.session.canGoNext, isFalse);

      h.session.next(); // 已经在最后一个
      expect(h.session.index, 2);
      h.dispose();
    });

    test('current 跟着 index 走', () {
      final _Harness h = _Harness();
      expect(h.session.current.exercise.name, '杠铃卧推');
      h.session.next();
      expect(h.session.current.exercise.name, '杠铃深蹲');
      h.dispose();
    });

    test('相邻动作名：首尾处返回 null（界面据此禁用按钮）', () {
      final _Harness h = _Harness();
      expect(h.session.previousName, isNull, reason: '第一个没有前一个');
      expect(h.session.nextName, '杠铃深蹲');

      h.session.next();
      expect(h.session.previousName, '杠铃卧推');
      h.dispose();
    });

    test('hasMultiple 只在多于一个动作时为真', () {
      final WorkoutController only = _controller('only', '只有它');
      final WorkoutSession s = WorkoutSession.single(only);
      expect(s.hasMultiple, isFalse);
      s.dispose();
      only.dispose();
    });

    test('转发内部控制器的通知（否则记一组界面不刷新）', () {
      final _Harness h = _Harness();
      int notified = 0;
      h.session.addListener(() => notified++);

      h.bench.onBigButtonTap();
      expect(notified, greaterThan(0), reason: '会话要把控制器的通知转出去');
      h.dispose();
    });

    test('dispose 之后不再转发（避免泄漏）', () {
      final _Harness h = _Harness();
      final WorkoutController bench = h.bench;
      h.session.dispose();
      // 会话已 dispose，但仍然持有控制器；这条只确认不抛异常
      expect(() => bench.onBigButtonTap(), returnsNormally);
      h.bench.dispose();
      h.squat.dispose();
      h.dead.dispose();
    });

    test('切换动作计一次点击，并且计在切换后的那个动作上', () {
      // 同一个会话里的控制器**共用一个埋点** —— 这正是 main.dart 的真实做法
      // （所有控制器都拿 `_analytics`）。
      final RecordingAnalytics analytics = RecordingAnalytics();
      WorkoutController make(String id, String name, double weight) =>
          WorkoutController(
            workoutId: 'w_shared',
            exercise: ExerciseSpec(
                id: id, name: name, weightIncrement: 2.5, defaultWeightKg: weight),
            plan: _plan,
            analytics: analytics,
            store: InMemoryLocalStore(),
            syncQueue: InMemorySyncQueue(),
          );
      final WorkoutController a = make('bench', '杠铃卧推', 40);
      final WorkoutController b = make('squat', '杠铃深蹲', 60);
      final WorkoutSession s = WorkoutSession(<WorkoutController>[a, b]);

      s.next(); // 切到 B：一次操作
      b.onBigButtonTap(); // 第 1 组

      final Map<String, Object?> props = analytics.propsOf('set_logged').single;
      expect(props['tap_count'], 2,
          reason: '切动作 1 次 + 大按钮 1 次；只算大按钮会把它记成 1，等于假装用户没切');
      expect(props['tap_kinds'], <String>['exercise_switch', 'big_button']);

      s.dispose();
      a.dispose();
      b.dispose();
    });
  });

  group('底部切换条', () {
    testWidgets('显示位置与相邻动作名', (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h);

      expect(tester.widget<Text>(find.byKey(const Key('exercise-position'))).data, '1 / 3');
      expect(find.textContaining('杠铃深蹲'), findsWidgets, reason: '右侧显示下一个是谁');

      h.session.next();
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('exercise-position'))).data, '2 / 3');
      expect(find.textContaining('杠铃卧推'), findsWidgets, reason: '左侧显示上一个是谁');

      h.dispose();
    });

    testWidgets('点右侧真的能切到下一个（不再是死的装饰）',
        (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h);

      await tester.tap(find.byKey(const Key('next-exercise')));
      await tester.pumpAndSettle();

      expect(h.session.index, 1);
      // 大按钮上的值也换成了新动作的
      expect(find.textContaining('60 kg'), findsWidgets);

      h.dispose();
    });

    testWidgets('点左侧回到上一个', (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h);
      h.session.next();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('prev-exercise')));
      await tester.pumpAndSettle();

      expect(h.session.index, 0);
      h.dispose();
    });

    testWidgets('只有一个动作时整条不显示（那行 1/1 没有信息量）',
        (WidgetTester tester) async {
      final WorkoutController only = _controller('only', '只有它');
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: WorkoutScreen(session: WorkoutSession.single(only)),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('exercise-position')), findsNothing);
      only.dispose();
    });
  });

  group('左右滑动', () {
    // ⚠️ 用 `flingFrom` 显式坐标，而不是 `fling(finder, ...)`。
    // 后者会取目标 widget 的中心作为起点，而滑动区的中心正好落在大按钮上 ——
    // 于是框架报"该坐标命中不到指定 widget"的警告。更要紧的是：
    // **警告会让"不该切"的测试变成假通过**（手势根本没落地，当然也不切）。
    const Offset kNeutral = Offset(60, 40); // 顶部标题栏一带，不在大按钮上

    testWidgets('向左滑 → 下一个动作', (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h);

      await tester.flingFrom(kNeutral, const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();

      expect(h.session.index, 1);
      h.dispose();
    });

    testWidgets('向右滑 → 上一个动作', (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h);
      h.session.next();
      await tester.pumpAndSettle();

      await tester.flingFrom(kNeutral, const Offset(300, 0), 1000);
      await tester.pumpAndSettle();

      expect(h.session.index, 0);
      h.dispose();
    });

    testWidgets('从大按钮上开始滑也能切（大按钮是满宽的，用户多半从那儿滑）',
        (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h);

      final Offset onButton =
          tester.getCenter(find.byKey(const Key('big-log-button')));
      await tester.flingFrom(onButton, const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();

      expect(h.session.index, 1, reason: '横向拖拽应当胜过点击，切到下一个');
      h.dispose();
    });

    testWidgets('轻轻一蹭不切动作（避免手抖就跳走）', (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h);

      await tester.flingFrom(kNeutral, const Offset(-60, 0), 80); // 速度远低于阈值
      await tester.pumpAndSettle();

      expect(h.session.index, 0, reason: '低速滑动不该切换');
      h.dispose();
    });

    testWidgets('弹层开着时不切动作（那是在改重量，不是在换动作）',
        (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h);

      await tester.longPress(find.byKey(const Key('big-log-button')));
      await tester.pumpAndSettle();
      expect(h.bench.sheetOpen, isTrue);

      await tester.flingFrom(kNeutral, const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();

      expect(h.session.index, 0, reason: '弹层开着不该被滑走');
      h.dispose();
    });
  });

  group('每个动作的记录互相独立', () {
    testWidgets('在 A 记一组，切到 B 后按钮与组数都不受 A 影响',
        (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h);

      await tester.tap(find.byKey(const Key('big-log-button')));
      await tester.pump();
      expect(h.bench.loggedSets, hasLength(1));

      h.session.next();
      await tester.pumpAndSettle();

      expect(h.squat.loggedSets, isEmpty, reason: 'B 还没练过');
      expect(
        tester.widget<Text>(find.byKey(const Key('set-number'))).data,
        '第 1 组',
        reason: 'B 的进度要从头开始，不能被 A 顶掉',
      );

      h.dispose();
    });

    testWidgets('切回 A，它的进度还在', (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h);

      await tester.tap(find.byKey(const Key('big-log-button')));
      await tester.pump();

      h.session.next();
      await tester.pumpAndSettle();
      h.session.previous();
      await tester.pumpAndSettle();

      expect(h.bench.loggedSets, hasLength(1));
      expect(
        tester.widget<Text>(find.byKey(const Key('set-number'))).data,
        '第 2 组',
      );

      h.dispose();
    });

    testWidgets('多个动作的记录挂在同一次训练下（共用 workoutId）',
        (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h);

      await tester.tap(find.byKey(const Key('big-log-button')));
      await tester.pump();
      h.session.next();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('big-log-button')));
      await tester.pump();

      expect(h.bench.workout.id, h.squat.workout.id, reason: '必须是同一次训练');
      expect(h.session.totalSetsSoFar, 2);

      h.dispose();
    });
  });
}
