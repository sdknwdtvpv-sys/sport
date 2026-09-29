/// 练了么 · 有氧记录（距离 + 时长）
///
/// **这一版解决什么**：在这之前，一次 5 公里跑**根本记不了** ——
/// 动作库里没有跑步机（上游有，被"引擎还没有 distance_time 规则"挡在库外），
/// 就算手动建一个自定义动作，也只能记"次数"或"秒数"，距离无处可放。
///
/// 三件事一起做才成立：
///   1. **存储**：`set_record.distance_m`（数据库 v5）。存米不存公里 ——
///      与"重量一律 kg"同一条规矩：存储不跟显示单位走
///   2. **引擎**：对 `distance_time` **不给推进建议**（返回 null）。
///      这是产品决策：没有用户的有氧目标，"这次多跑 5%"是假精确。
///      更要紧的是**不能掉进次数分支** —— 那会对一次跑步说"每组次数补到 10 次"
///   3. **界面**：训练屏念「5.00 公里 · 30:00」，长按能设距离与时长；
///      距离为 0 时大按钮置灰（不写"0 公里"的假记录）
///
/// 引擎单步行为由 `engine/vectors.json` 的 2 条 distance_time 向量守着（JS/Dart 共用），
/// 这里测的是**从动作库走到界面、再落到存储**这条线。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/analytics.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/sync_queue.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/domain/progression.dart';
import 'package:lianleme/features/workout/workout_controller.dart';
import 'package:lianleme/features/workout/workout_screen.dart';
import 'package:lianleme/features/workout/workout_session.dart';

/// 与 seed 里的 ex_treadmill_incline_walk 一致：跑步机爬坡走，按距离记。
const ExerciseSpec _treadmill = ExerciseSpec(
  id: 'ex_treadmill_incline_walk',
  name: '跑步机爬坡走',
  weightIncrement: 0,
  defaultWeightKg: null,
  defaultRestSec: 60,
  trackType: 'distance_time',
);

/// 与 seed 里的 ex_farmer_walk 一致：农夫行走 —— **有重量**的距离动作。
const ExerciseSpec _farmerWalk = ExerciseSpec(
  id: 'ex_farmer_walk',
  name: '农夫行走',
  weightIncrement: 2,
  defaultWeightKg: 20,
  defaultRestSec: 120,
  trackType: 'distance_time',
);

/// 与 seed 里的 ex_bb_bench_press 一致，用来对照"普通动作不受影响"。
const ExerciseSpec _bench = ExerciseSpec(
  id: 'ex_bb_bench_press',
  name: '杠铃卧推',
  weightIncrement: 2.5,
  defaultWeightKg: 40,
  defaultRestSec: 120,
);

const PlanTarget _planReps = PlanTarget(
  targetSets: 3,
  targetRepsLow: 8,
  targetRepsHigh: 10,
);

class _Harness {
  _Harness({ExerciseSpec spec = _treadmill, LastSession? lastSession}) {
    controller = WorkoutController(
      exercise: spec,
      plan: _planReps,
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
}

Future<void> _pump(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: WorkoutScreen(session: WorkoutSession.single(h.controller)),
  ));
}

Future<void> _teardown(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  h.controller.dispose();
}

void main() {
  group('引擎：有氧不给推进建议', () {
    test('有历史的跑步 → 返回 null（一个字都不说）', () {
      final Suggestion? s = suggestNext(
        exercise: _treadmill,
        plan: _planReps,
        lastSession: const LastSession(
          weightKg: null,
          reps: <int>[1800, 1800, 1800],
          distances: <double?>[5000, 5000, 5000],
          daysAgo: 2,
        ),
      );

      expect(s, isNull);
    });

    test('零历史的有氧也不给建议 —— 不能走"第一次先从这个重量开始"', () {
      expect(
        suggestNext(exercise: _treadmill, plan: _planReps, lastSession: null),
        isNull,
      );
    });

    test('⚠️ 这条最重要：**绝不能掉进次数分支**', () {
      // 不挡的话 distance_time 不是 time，会走到最后那条"加次数"分支，
      // 于是引擎对一次 5 公里跑说"每组次数补到 10 次"。这不是不精确，是说错话。
      final Suggestion? s = suggestNext(
        exercise: _treadmill,
        plan: _planReps,
        lastSession: const LastSession(
          weightKg: null,
          reps: <int>[1800, 1800, 1800],
          daysAgo: 2,
        ),
      );

      expect(s, isNull, reason: '有建议就说明它掉进了数值分支');
    });

    test('有重量的距离动作（农夫行走）同样不给建议', () {
      expect(
        suggestNext(
          exercise: _farmerWalk,
          plan: _planReps,
          lastSession: const LastSession(
            weightKg: 20,
            reps: <int>[60, 60, 60],
            distances: <double?>[20, 20, 20],
            daysAgo: 3,
          ),
        ),
        isNull,
      );
    });
  });

  group('控制器：默认值、门禁与写库', () {
    test('没有历史 → 距离是 0，大按钮**不给点**（不写 0 公里的假记录）', () {
      final _Harness h = _Harness();
      expect(h.controller.distanceM, 0);
      expect(h.controller.canLog, isFalse);

      h.controller.onBigButtonTap();
      expect(h.controller.loggedSets, isEmpty, reason: '没设距离就不该落库');
      expect(h.controller.hint, contains('距离'));
      h.controller.dispose();
    });

    test('有历史 → 默认沿用上次的距离（"今天还跑那么多"，一次点击一组）', () {
      final _Harness h = _Harness(
        lastSession: const LastSession(
          weightKg: null,
          reps: <int>[1800, 1740],
          distances: <double?>[5000, 4800],
          daysAgo: 2,
        ),
      );

      expect(h.controller.distanceM, 5000,
          reason: '取上次**最远**的一组 —— 热身/放松那两组会把默认值拖低');
      expect(h.controller.canLog, isTrue);
      h.controller.dispose();
    });

    test('点一下 → 距离与秒数都落进 SetRecord', () {
      final _Harness h = _Harness(
        lastSession: const LastSession(
          weightKg: null,
          reps: <int>[1800],
          distances: <double?>[5000],
          daysAgo: 2,
        ),
      );

      h.controller.onBigButtonTap();

      final SetRecord r = h.controller.loggedSets.single;
      expect(r.distanceM, 5000);
      expect(r.reps, 1800, reason: '有氧的 reps 是秒');
      expect(r.weightKg, isNull);
      expect(r.volume, 0, reason: '距离动作的容量记 0 —— 不该拿秒数当次数乘');
      h.controller.dispose();
    });

    test('步进：距离 ±100 米、时长 ±60 秒（不是 ±5 秒）', () {
      final _Harness h = _Harness();
      expect(h.controller.distanceStepM, 100);
      expect(h.controller.repsStep, 60, reason: '跑步 30 分钟要点 1800 次 ±1 秒不叫步进');

      h.controller.onStepper(deltaDistanceM: 500);
      h.controller.onStepper(deltaReps: 1800);
      expect(h.controller.distanceM, 500);
      expect(h.controller.reps, 1800);

      // 距离可以回到 0（"还没跑"）；它不像次数那样有"至少一次"的下限
      h.controller.onStepper(deltaDistanceM: -900);
      expect(h.controller.distanceM, 0);
      expect(h.controller.canLog, isFalse);
      h.controller.dispose();
    });

    test('普通动作不受影响：默认来自建议、一直可点、不写距离', () {
      final _Harness h = _Harness(spec: _bench);
      expect(h.controller.canLog, isTrue);
      expect(h.controller.repsStep, 1);

      h.controller.onBigButtonTap();
      final SetRecord r = h.controller.loggedSets.single;
      expect(r.distanceM, isNull);
      expect(r.weightKg, 40);
      expect(r.volume, 40 * 8);
      h.controller.dispose();
    });

    test('同步队列与埋点都带上距离（否则服务端与报表看不到）', () {
      final _Harness h = _Harness(
        lastSession: const LastSession(
          weightKg: null,
          reps: <int>[1800],
          distances: <double?>[5000],
          daysAgo: 2,
        ),
      );
      h.controller.onBigButtonTap();

      expect(h.syncQueue.items.single.payload['distance_m'], 5000);
      final AnalyticsEvent logged = h.analytics.events
          .lastWhere((AnalyticsEvent e) => e.name == 'set_logged');
      expect(logged.props['distance_m'], 5000);
      h.controller.dispose();
    });
  });

  group('距离处方：首次练也有起点', () {
    test('没有历史时，默认距离来自**处方**（不是 0）', () {
      const PlanTarget plan = PlanTarget(
        targetSets: 3,
        targetRepsLow: 0,
        targetRepsHigh: 0,
        targetDistanceM: 20,
      );
      final WorkoutController c = WorkoutController(
        exercise: _farmerWalk,
        plan: plan,
        analytics: RecordingAnalytics(),
        store: InMemoryLocalStore(),
        syncQueue: InMemorySyncQueue(),
        clock: () => 1000,
      );

      expect(c.distanceM, 20, reason: '处方给的每组米数就是起点');
      expect(c.targetDistanceM, 20);
      c.dispose();
    });

    test('有历史时**上次优先**（今天还练那么多），处方只当没有历史时的兜底', () {
      const PlanTarget plan = PlanTarget(
        targetSets: 3,
        targetRepsLow: 0,
        targetRepsHigh: 0,
        targetDistanceM: 20,
      );
      final WorkoutController c = WorkoutController(
        exercise: _farmerWalk,
        plan: plan,
        analytics: RecordingAnalytics(),
        store: InMemoryLocalStore(),
        syncQueue: InMemorySyncQueue(),
        lastSession: const LastSession(
          weightKg: 20,
          reps: <int>[60, 60],
          distances: <double?>[24.5, 26],
          daysAgo: 2,
        ),
        clock: () => 1000,
      );

      expect(c.distanceM, 26, reason: '上次最远的一组；处方不该盖掉真实历史');
      c.dispose();
    });
  });

  group('训练屏：念公里与时长，不念"自重 × 1800"', () {
    testWidgets('大按钮上写「5.00 公里 · 30:00」', (WidgetTester tester) async {
      final _Harness h = _Harness(
        lastSession: const LastSession(
          weightKg: null,
          reps: <int>[1800],
          distances: <double?>[5000],
          daysAgo: 2,
        ),
      );
      await _pump(tester, h);

      expect(find.text('5.00 公里 · 30:00'), findsOneWidget);
      await _teardown(tester, h);
    });

    testWidgets('距离为 0 → 按钮文案是「0 米 · 00:00」且提示怎么设',
        (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h);

      // 只看按钮上那一个 Text —— 休息计时器也写着「00:00」，
      // 用 textContaining 会同时命中它（第一次写这条就是这么红的）
      final Text label =
          tester.widget<Text>(find.byKey(const Key('button-label')));
      expect(label.data, '0 米 · 00:00',
          reason: '时长也不该凭空给个 8 秒（那是"8 次"的处方落到了有氧上）');
      expect(
        tester.widget<Text>(find.byKey(const Key('workout-hint'))).data,
        contains('长按'),
      );
      await _teardown(tester, h);
    });

    testWidgets('长按弹层里有距离行（±100 米），没有重量行', (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h);

      expect(find.byKey(const Key('step-weight-up')), findsNothing,
          reason: '跑步机没有重量这一项');
      await tester.longPress(find.byKey(const Key('big-log-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('step-distance-up')), findsOneWidget);
      await tester.tap(find.byKey(const Key('step-distance-up')));
      await tester.pumpAndSettle();
      expect(find.text('100'), findsWidgets);
      await _teardown(tester, h);
    });

    testWidgets('农夫行走（有重量）→ 弹层里重量与距离**都有**',
        (WidgetTester tester) async {
      final _Harness h = _Harness(spec: _farmerWalk);
      await _pump(tester, h);

      await tester.longPress(find.byKey(const Key('big-log-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('step-weight-up')), findsOneWidget);
      expect(find.byKey(const Key('step-distance-up')), findsOneWidget);
      await _teardown(tester, h);
    });

    testWidgets('记完之后已完成组那一行念「5.00 公里 · 30:00」',
        (WidgetTester tester) async {
      final _Harness h = _Harness(
        lastSession: const LastSession(
          weightKg: null,
          reps: <int>[1800],
          distances: <double?>[5000],
          daysAgo: 2,
        ),
      );
      await _pump(tester, h);

      await tester.tap(find.byKey(const Key('big-log-button')));
      await tester.pumpAndSettle();

      expect(find.text('5.00 公里 · 30:00'), findsWidgets);
      await _teardown(tester, h);
    });
  });

  group('单位格式', () {
    test('1 公里以上说公里（两位小数），以下说米', () {
      expect(formatDistanceKm(5000), '5.00 公里');
      expect(formatDistanceKm(1000), '1.00 公里');
      expect(formatDistanceKm(800), '800 米');
      expect(formatDistanceKm(0), '0 米');
    });

    test('秒数念成 mm:ss / h:mm:ss', () {
      expect(formatDurationHms(1800), '30:00');
      expect(formatDurationHms(65), '01:05');
      expect(formatDurationHms(3900), '1:05:00');
    });

    test('配速：5 公里 30 分钟 = 6\'00"/公里', () {
      expect(formatPace(5000, 1800), '6\'00"/公里');
      expect(formatPace(0, 1800), isNull, reason: '距离为 0 时配速没有定义');
      expect(formatPace(5000, 0), isNull);
    });
  });
}
