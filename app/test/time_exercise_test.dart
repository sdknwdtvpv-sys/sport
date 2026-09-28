/// 练了么 · 按时长的动作（平板支撑 / 侧平板）
///
/// **修的是什么**：165 个动作的 `track_type` 全是 `weight_reps`，而这个字段
/// 在库里躺着**没有任何代码读它** —— 于是平板支撑被开成「3 组 × 8–10 次」，
/// 引擎按次数继续往上加，还会说出「自重已完成 30 次，建议加负重」。
/// 用户一眼就能看出这个 App 不懂健身，比少一个功能更伤。
///
/// 现在：种子标出时间类动作 → `ExerciseSpec.trackType` → 引擎走加秒数分支 →
/// 界面上说「秒」而不是「次」，步进是 ±5 秒。
///
/// 引擎本身的行为由 `engine/vectors.json` 的 7 条时长向量守着（JS 与 Dart 共用），
/// 这里测的是**从动作库一路走到界面**这条线。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/analytics.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/sync_queue.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/domain/progression.dart';
import 'package:lianleme/features/workout/workout_controller.dart';
import 'package:lianleme/features/workout/workout_screen.dart';
import 'package:lianleme/features/workout/workout_session.dart';

/// 与 seed 里的 ex_plank 一致（注意 track_type 是 time）。
const ExerciseSpec _plank = ExerciseSpec(
  id: 'ex_plank',
  name: '平板支撑',
  weightIncrement: 0,
  defaultWeightKg: null,
  defaultRestSec: 60,
  trackType: 'time',
);

/// 与 seed 里的 ex_weighted_plank 一致。
const ExerciseSpec _weightedPlank = ExerciseSpec(
  id: 'ex_weighted_plank',
  name: '负重平板支撑',
  weightIncrement: 2.5,
  defaultWeightKg: 5,
  defaultRestSec: 60,
  trackType: 'weight_time',
);

/// 按时长动作的处方：数字是**秒**。
const PlanTarget _planTime = PlanTarget(
  targetSets: 3,
  targetRepsLow: 30,
  targetRepsHigh: 45,
);

class _Harness {
  _Harness({ExerciseSpec spec = _plank, LastSession? lastSession}) {
    controller = WorkoutController(
      exercise: spec,
      plan: _planTime,
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

/// 必须显式销毁：Timer.periodic 会留下 pending timer，testWidgets 直接判失败。
Future<void> _teardown(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  h.controller.dispose();
}

void main() {
  group('引擎：按时长动作走加秒数分支', () {
    test('零历史 → 给 30 秒，文案说的是"秒数"不是"次数"', () {
      final Suggestion? s = suggestNext(
        exercise: _plank,
        plan: _planTime,
        lastSession: null,
      );

      expect(s!.reps, 30);
      expect(s.weightKg, isNull);
      expect(s.reasonCode, ReasonCode.firstTime);
      expect(s.reasonText, contains('秒数'));
      expect(s.reasonText, isNot(contains('次数')));
    });

    test('有历史且没做满 → 先补组数（不吹秒数）', () {
      final Suggestion? s = suggestNext(
        exercise: _plank,
        plan: _planTime,
        lastSession: const LastSession(weightKg: null, reps: <int>[30, 30], daysAgo: 2),
      );

      expect(s!.reasonCode, ReasonCode.hold);
      expect(s.reasonText, contains('先把组数补满'));
    });

    test('做满了 → 按秒推进 +5（不是 +1 次）', () {
      final Suggestion? s = suggestNext(
        exercise: _plank,
        plan: _planTime,
        lastSession: const LastSession(weightKg: null, reps: <int>[35, 32, 30], daysAgo: 2),
      );

      expect(s!.reasonCode, ReasonCode.addRep);
      expect(s.reps, 35, reason: '30 + 5 秒');
      expect(s.reasonText, contains('30 → 35 秒'));
      expect(s.reasonText, isNot(contains('次')));
    });

    test('到时长上限 → 自重动作建议加负重，不再无限加秒', () {
      final Suggestion? s = suggestNext(
        exercise: _plank,
        plan: _planTime,
        lastSession: const LastSession(weightKg: null, reps: <int>[60, 62, 60], daysAgo: 2),
      );

      expect(s!.reasonCode, ReasonCode.addRep);
      expect(s.reps, 60, reason: '上限 = 45 + 15 秒');
      expect(s.reasonText, contains('建议加负重'));
    });

    test('负重时长（负重平板）保留重量，到上限直接加重', () {
      final Suggestion? s = suggestNext(
        exercise: _weightedPlank,
        plan: _planTime,
        lastSession: const LastSession(weightKg: 5, reps: <int>[60, 60, 60], daysAgo: 2),
      );

      expect(s!.reasonCode, ReasonCode.linearProgress);
      expect(s.weightKg, 7.5, reason: '5 + 2.5：它有重量，不是自重');
      expect(s.reps, 30, reason: '加重后回到区间下限');
    });

    test('21 天回归保护优先于时长推进（顺序不能变）', () {
      final Suggestion? s = suggestNext(
        exercise: _plank,
        plan: _planTime,
        lastSession: const LastSession(weightKg: null, reps: <int>[40, 40, 40], daysAgo: 25),
      );

      expect(s!.reasonCode, ReasonCode.deload);
      expect(s.reasonText, contains('25 天'));
    });
  });

  group('界面：说「秒」不说「次」', () {
    testWidgets('大按钮上就是"自重 × 30 秒"', (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h);

      expect(find.text('自重 × 30 秒'), findsOneWidget);
      expect(find.textContaining('× 30'), findsOneWidget);

      await _teardown(tester, h);
    });

    testWidgets('弹层里的步进是 ±5 秒，且按钮上的字与真实步长一致',
        (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h);

      await tester.longPress(find.byKey(const Key('big-log-button')));
      await tester.pump();

      expect(find.text('秒'), findsOneWidget, reason: '次数那一行的单位应当是"秒"');
      expect(find.text('−5'), findsOneWidget);
      expect(find.text('+5'), findsOneWidget);

      await tester.tap(find.byKey(const Key('step-reps-up')));
      await tester.pump();
      expect(h.controller.reps, 35);

      await _teardown(tester, h);
    });

    testWidgets('秒数不会被步进到 5 以下（次数不会到 0）', (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h);

      for (int i = 0; i < 20; i++) {
        h.controller.onStepper(deltaReps: -h.controller.repsStep);
      }
      await tester.pump();

      expect(h.controller.reps, 5, reason: '下限就是一次步进');

      await _teardown(tester, h);
    });

    testWidgets('记完一组后，已完成那行也带"秒"', (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h);

      await tester.tap(find.byKey(const Key('big-log-button')));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(const Key('done-list')),
          matching: find.textContaining('秒'),
        ),
        findsOneWidget,
        reason: '不加"秒"会被读成"自重 × 30 次"',
      );

      await _teardown(tester, h);
    });

    testWidgets('重量步进用动作自己的步长，不再是写死的 ±2.5',
        (WidgetTester tester) async {
      // 器械的种子步长是 5
      final _Harness h = _Harness(
        spec: const ExerciseSpec(
          id: 'ex_machine_chest_press',
          name: '器械推胸',
          weightIncrement: 5,
          defaultWeightKg: 30,
          defaultRestSec: 90,
        ),
      );
      await _pump(tester, h);

      await tester.longPress(find.byKey(const Key('big-log-button')));
      await tester.pump();

      expect(find.text('−5'), findsOneWidget);
      expect(find.text('+5'), findsOneWidget);

      await _teardown(tester, h);
    });
  });
}
