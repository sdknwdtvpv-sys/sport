/// 练了么 · 辅助自重（辅助引体 / 辅助双杠臂屈伸）
///
/// **修的是什么**：辅助动作的"重量"是**助力** —— 越练越强 = 助力越少。
/// 而引擎一直把它当负重推：达标 → `+5kg`，也就是**给你更多助力**。
/// 用户看到的是"越练越轻松"，系统却以为在进步。这是最伤可信度的那类错：
/// 它不但方向反了，还会一直反下去。
///
/// 现在：达标 → **减**助力（−5kg）；掉组/组数不足 → 保持；助力减到 0 → 提示可以不用辅助了。
/// 引擎行为由 `engine/vectors.json` 的 6 条 assisted 向量守着（JS/Dart 共用），
/// 这里测的是**从动作库一路走到界面**这条线：界面必须说清那个数字是"助力"。
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

/// 与 seed 里的 ex_assisted_pull_up 一致：起始助力 30kg，助力步长 5kg。
const ExerciseSpec _assistedPullUp = ExerciseSpec(
  id: 'ex_assisted_pull_up',
  name: '辅助引体向上',
  weightIncrement: 5,
  defaultWeightKg: 30,
  defaultRestSec: 120,
  trackType: 'assisted_reps',
);

const PlanTarget _plan = PlanTarget(
  targetSets: 3,
  targetRepsLow: 8,
  targetRepsHigh: 10,
);

class _Harness {
  _Harness({LastSession? lastSession}) {
    controller = WorkoutController(
      exercise: _assistedPullUp,
      plan: _plan,
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
  group('引擎：助力只减不增', () {
    test('全部达标 → 减轻助力（30 → 25），文案说"减轻助力"', () {
      final Suggestion? s = suggestNext(
        exercise: _assistedPullUp,
        plan: _plan,
        lastSession: const LastSession(
          weightKg: 30,
          reps: <int>[10, 10, 10],
          daysAgo: 2,
        ),
      );

      expect(s!.weightKg, 25, reason: '越练越强 = 助力越少');
      expect(s.reasonCode, ReasonCode.linearProgress);
      expect(s.reasonText, contains('减轻助力'));
    });

    test('掉组 → 保持助力（**不许**加助力：那不是修复，是让人更轻松）', () {
      final Suggestion? s = suggestNext(
        exercise: _assistedPullUp,
        plan: _plan,
        lastSession: const LastSession(
          weightKg: 30,
          reps: <int>[10, 6, 5],
          daysAgo: 2,
        ),
      );

      expect(s!.weightKg, 30);
      expect(s.reasonCode, ReasonCode.hold);
      expect(s.reasonText, contains('保持助力'));
    });

    test('助力已到最低 → 提示不用辅助了，且不减到负数', () {
      final Suggestion? s = suggestNext(
        exercise: _assistedPullUp,
        plan: _plan,
        lastSession: const LastSession(
          weightKg: 5,
          reps: <int>[10, 10, 10],
          daysAgo: 2,
        ),
      );

      expect(s!.weightKg, 0);
      expect(s.reasonText, contains('不用辅助'));
    });

    test('零历史 → 从起始**助力**开始（文案不说"重量"）', () {
      final Suggestion? s =
          suggestNext(exercise: _assistedPullUp, plan: _plan, lastSession: null);

      expect(s!.weightKg, 30);
      expect(s.reasonText, contains('助力'));
    });
  });

  group('界面：那个数字必须叫"助力"', () {
    testWidgets('大按钮写「助力 30 kg × 8」——不是「30 kg × 8」',
        (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h);

      final Text label =
          tester.widget<Text>(find.byKey(const Key('button-label')));
      expect(label.data, '助力 30 kg × 8',
          reason: '只说「30 kg × 8」会被读成"举起了 30kg"，而它恰恰相反');
      await _teardown(tester, h);
    });

    testWidgets('弹层里的单位带"助力"（否则用户不知道该往哪边调）',
        (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h);

      await tester.longPress(find.byKey(const Key('big-log-button')));
      await tester.pumpAndSettle();

      expect(find.text('kg 助力'), findsOneWidget);
      await _teardown(tester, h);
    });

    testWidgets('记完那一行也念「助力 30 kg × 8」',
        (WidgetTester tester) async {
      final _Harness h = _Harness();
      await _pump(tester, h);

      await tester.tap(find.byKey(const Key('big-log-button')));
      await tester.pumpAndSettle();

      expect(find.text('助力 30 kg × 8'), findsWidgets);
      await _teardown(tester, h);
    });
  });
}
