/// 练了么 · S13 首次引导测试（非阻塞版）
///
/// 这一版的要点是**它不挡路**：入口只在 S1 空态里作为可选链接出现，
/// 而且引导以"开始训练"收尾而不是以"设置完成"收尾。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/data/routine_repository.dart';
import 'package:lianleme/features/onboarding/onboarding.dart';
import 'package:lianleme/features/onboarding/onboarding_screen.dart';
import 'package:lianleme/features/today/today_planner.dart';
import 'package:lianleme/features/today/today_screen.dart';

void main() {
  group('规则', () {
    test('目标 → 处方：力量是少次数大重量，减脂是多次数', () {
      final PlanTarget strength = planForGoal(TrainingGoal.strength);
      final PlanTarget hypertrophy = planForGoal(TrainingGoal.hypertrophy);
      final PlanTarget fatLoss = planForGoal(TrainingGoal.fatLoss);

      expect(strength.targetRepsHigh, lessThan(hypertrophy.targetRepsLow),
          reason: '力量的次数区间应该整体更低');
      expect(fatLoss.targetRepsLow, greaterThanOrEqualTo(12));
      expect(strength.targetSets, greaterThanOrEqualTo(4), reason: '力量组数更多');
    });

    test('一周练得越少，一次安排的动作越多', () {
      expect(exercisesPerSession(2), greaterThan(exercisesPerSession(4)));
      expect(exercisesPerSession(4), greaterThan(exercisesPerSession(6)));
      expect(exercisesPerSession(2), exercisesPerSession(3));
    });

    test('wire 值与 data-model.md 里的注释一致', () {
      expect(TrainingGoal.hypertrophy.wire, 'hypertrophy');
      expect(TrainingGoal.strength.wire, 'strength');
      expect(TrainingGoal.fatLoss.wire, 'fat_loss');
      expect(TrainingGoal.fromWire('fat_loss'), TrainingGoal.fatLoss);
      expect(TrainingGoal.fromWire('nonsense'), isNull);
      expect(TrainingGoal.fromWire(null), isNull);
    });

    test('天数说明会告诉用户这个数字被拿去做什么了', () {
      expect(daysHint(3), contains('6 个动作'));
      expect(daysHint(5), contains('4 个动作'));
    });
  });

  group('流程', () {
    late AppDatabase db;
    late DriftLocalStore store;
    late ExerciseRepository exercises;
    late ProfileRepository profile;
    late RoutineRepository routines;
    late TodayPlanner planner;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      store = DriftLocalStore(db);
      exercises = ExerciseRepository(db);
      profile = ProfileRepository(db);
      routines = RoutineRepository(db);
      planner = TodayPlanner(repository: exercises, store: store);
      await exercises.importSeed(
        loadJson: () => File('assets/exercises.json').readAsString(),
      );
    });

    tearDown(() => db.close());

    /// 把引导推成一个路由，好接住它的返回值
    Future<List<OnboardingResult?>> pump(WidgetTester tester) async {
      final List<OnboardingResult?> out = <OnboardingResult?>[];
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  out.add(await Navigator.of(ctx).push<OnboardingResult>(
                    MaterialPageRoute<OnboardingResult>(
                      builder: (_) => OnboardingScreen(
                        planner: planner,
                        profile: profile,
                        routines: routines,
                        exercises: exercises,
                      ),
                    ),
                  ));
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      return out;
    }

    testWidgets('第 1 步：没选目标之前「下一步」是禁用的',
        (WidgetTester tester) async {
      await pump(tester);

      expect(find.text('你的目标是？'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('onboarding-next-1'))).onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('goal-strength')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('onboarding-next-1'))).onPressed,
        isNotNull,
      );
    });

    testWidgets('第 2 步：选完天数才能看计划', (WidgetTester tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('goal-strength')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding-next-1')));
      await tester.pumpAndSettle();

      expect(find.text('一周练几天？'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('onboarding-next-2'))).onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('days-3')));
      await tester.pumpAndSettle();
      expect(find.textContaining('6 个动作'), findsOneWidget,
          reason: '天数要立刻解释它决定了什么');
    });

    testWidgets('第 3 步：生成计划，处方来自目标而不是默认值',
        (WidgetTester tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('goal-strength')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding-next-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('days-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding-next-2')));
      await tester.pumpAndSettle();

      expect(find.text('这是你的第一份计划'), findsOneWidget);
      // 力量的处方是 5 组 × 3–5 次
      expect(find.textContaining('5 组 × 3–5 次'), findsOneWidget);
    });

    testWidgets('「就用这个，开始练」：落库 + 返回 startNow，计划写进 S11 的模板',
        (WidgetTester tester) async {
      final List<OnboardingResult?> out = await pump(tester);
      await tester.tap(find.byKey(const Key('goal-hypertrophy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding-next-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('days-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding-next-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding-start-now')));
      await tester.pumpAndSettle();

      expect(out.single, isNotNull);
      expect(out.single!.startNow, isTrue);
      expect(out.single!.plan, hasLength(6), reason: '一周 3 天 → 6 个动作');

      // 目标与频率落库
      expect(await profile.goalWire(), 'hypertrophy');
      expect(await profile.weeklyFrequency(), 3);

      // 计划写进了 S11 的模板，且处方跟着目标走
      final List<RoutineData> rs = await routines.routines();
      expect(rs, hasLength(1));
      expect(rs.single.name, contains('增肌'));
      final List<RoutineItemData> items = await routines.items(rs.single.id);
      expect(items, hasLength(6));
      expect(items.first.targetSets, 4);
      expect(items.first.targetRepsLow, 8);
      expect(items.first.targetRepsHigh, 12);
    });

    testWidgets('「先这样，回头再练」：一样落库，但 startNow 是 false',
        (WidgetTester tester) async {
      final List<OnboardingResult?> out = await pump(tester);
      await tester.tap(find.byKey(const Key('goal-maintain')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding-next-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('days-4')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding-next-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding-just-save')));
      await tester.pumpAndSettle();

      expect(out.single!.startNow, isFalse);
      expect(await profile.goalWire(), 'maintain');
      expect((await routines.routines()), hasLength(1));
    });

    testWidgets('「跳过」：什么都不写，也不留痕（下次还能再来）',
        (WidgetTester tester) async {
      final List<OnboardingResult?> out = await pump(tester);

      await tester.tap(find.byKey(const Key('onboarding-skip')));
      await tester.pumpAndSettle();

      expect(out.single, isNull);
      expect(await profile.goalWire(), isNull, reason: '跳过不该写目标');
      expect(await profile.weeklyFrequency(), isNull);
      expect(await routines.routines(), isEmpty, reason: '跳过不该建计划');
    });

    testWidgets('写引导结果不会把别的设置抹掉', (WidgetTester tester) async {
      // 先设好别的设置
      await profile.setUnit(WeightUnit.lb, nowMs: 1000);
      await profile.setAnalyticsEnabled(false, nowMs: 1000);
      await profile.setRestOverrideSec(60, nowMs: 1000);

      await pump(tester);
      await tester.tap(find.byKey(const Key('goal-strength')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding-next-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('days-5')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding-next-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding-just-save')));
      await tester.pumpAndSettle();

      expect(await profile.unit(), WeightUnit.lb);
      expect(await profile.analyticsEnabled(), isFalse);
      expect(await profile.restOverrideSec(), 60);
    });
  });

  group('S1 的入口是可选、非阻塞的', () {
    testWidgets('没传 onPlanHelp 时不显示（已定过计划的人不需要它）',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TodayScreen(onStart: () {})),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('plan-help')), findsNothing);
      // 主按钮该在还在：点一下就能开始训练
      expect(find.byKey(const Key('start-workout')), findsOneWidget);
    });

    testWidgets('传了才显示，且不会挤掉主按钮', (WidgetTester tester) async {
      int helped = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TodayScreen(onStart: () {}, onPlanHelp: () => helped++),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('start-workout')), findsOneWidget);
      await tester.tap(find.byKey(const Key('plan-help')));
      await tester.pumpAndSettle();
      expect(helped, 1);
    });
  });
}
