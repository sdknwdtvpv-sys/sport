/// 练了么 · 「在哪儿练」（2026-10-09 第二份 docx 第 4 条）
///
/// 用户原话：「计划里面，有些不在健身房练的。能否前置选择下在什么场景练，
/// 然后匹配对应的动作和计划」。
///
/// 这一条守三件事：
///   1. **场景 → 器械**那张表（纯函数，边界在这里）；
///   2. **筛选真的生效**（"家里"不许排出杠铃/器械动作）；
///   3. **没选过 = 健身房**（老库升上来与这一版之前逐条一致 —— 不许悄悄改老用户）。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/core/units.dart';
// db.dart（drift）与 models.dart 都定义了 SetRecord / Workout，预先 hide。
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/data/routine_repository.dart';
import 'package:lianleme/features/routine/plan_screen.dart';
import 'package:lianleme/features/today/today_planner.dart';
import 'package:lianleme/features/today/training_scenario.dart';

void main() {
  group('场景 → 器械（纯表）', () {
    test('没选过 = 健身房（老库升上来与这一版之前逐条一致）', () {
      expect(TrainingScenario.fromWire(null), TrainingScenario.gym);
      expect(TrainingScenario.fromWire(''), TrainingScenario.gym);
      expect(TrainingScenario.fromWire('不认识的值'), TrainingScenario.gym);
      expect(TrainingScenario.fromWire('home'), TrainingScenario.home);
      expect(TrainingScenario.fromWire('bodyweight'), TrainingScenario.bodyweight);
    });

    test('健身房 = 全部器械；家里不含杠铃/器械/绳索；徒手只有自重', () {
      expect(TrainingScenario.gym.equipment, contains('barbell'));
      expect(TrainingScenario.gym.equipment, contains('machine'));

      expect(TrainingScenario.home.equipment, contains('dumbbell'));
      expect(TrainingScenario.home.equipment, contains('bodyweight'));
      for (final String banned in <String>['barbell', 'machine', 'cable']) {
        expect(TrainingScenario.home.equipment, isNot(contains(banned)),
            reason: '家里不该有 $banned —— 那是最常见的"排了我做不了的动作"');
      }

      expect(TrainingScenario.bodyweight.equipment, <String>{'bodyweight'});
    });
  });

  group('筛选真的生效（planner + 仓库）', () {
    late AppDatabase db;
    late ExerciseRepository repo;
    late DriftLocalStore store;
    late TodayPlanner planner;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = ExerciseRepository(db);
      store = DriftLocalStore(db);
      planner = TodayPlanner(repository: repo, store: store);
      await repo.importSeed(
          loadJson: () => File('assets/exercises.json').readAsString());
    });

    tearDown(() => db.close());

    test('徒手场景：排出来的动作**全是自重**', () async {
      final List<PlannedExercise> plan = await planner.planToday(
        day: TrainingDay.upper,
        equipment: TrainingScenario.bodyweight.equipment,
      );

      expect(plan, isNotEmpty, reason: '徒手也该排得出上肢日');
      for (final PlannedExercise p in plan) {
        expect(p.exercise.equipment, 'bodyweight',
            reason: '${p.exercise.name} 不是自重动作，徒手场景不该出现它');
      }
    });

    test('家里场景：不含杠铃 / 器械 / 绳索', () async {
      final List<PlannedExercise> plan = await planner.planToday(
        day: TrainingDay.lower,
        equipment: TrainingScenario.home.equipment,
      );

      expect(plan, isNotEmpty);
      for (final PlannedExercise p in plan) {
        expect(TrainingScenario.home.equipment, contains(p.exercise.equipment),
            reason: '${p.exercise.name}（${p.exercise.equipment}）不该出现在家里');
      }
    });

    test('换一批也守场景（否则"家里"换两下又换出器械动作）', () async {
      final List<PlannedExercise> first = await planner.planToday(
        day: TrainingDay.upper,
        equipment: TrainingScenario.bodyweight.equipment,
      );
      final List<PlannedExercise> next = await planner.reroll(
        current: first,
        equipment: TrainingScenario.bodyweight.equipment,
      );

      for (final PlannedExercise p in next) {
        expect(p.exercise.equipment, 'bodyweight', reason: p.exercise.name);
      }
    });

    test('仓库层：equipmentIn 一组器械都算，观里那一条仍然只管一个', () async {
      final List<ExerciseData> rows = await repo.search(
        muscleGroup: 'chest',
        equipmentIn: TrainingScenario.home.equipment,
        limit: 200,
      );

      expect(rows, isNotEmpty);
      for (final ExerciseData e in rows) {
        expect(TrainingScenario.home.equipment, contains(e.equipment));
      }
    });
  });

  group('落库与界面', () {
    late AppDatabase db;
    late ProfileRepository profile;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      profile = ProfileRepository(db);
    });

    tearDown(() => db.close());

    test('没选过是 null；选了读得回来；也能清回 null（按健身房算）', () async {
      expect(await profile.trainingScenario(), isNull);

      await profile.setTrainingScenario('home', nowMs: 1);
      expect(await profile.trainingScenario(), 'home');

      await profile.setTrainingScenario(null, nowMs: 2);
      expect(await profile.trainingScenario(), isNull,
          reason: 'null 是"没选过"这个有意义的值（drift 的 nullToAbsent 坑）');
    });

    test('别的设置不会被这次写入抹掉', () async {
      await profile.setUnit(WeightUnit.lb, nowMs: 1);
      await profile.setAnalyticsEnabled(true, nowMs: 1);
      await profile.setTrainingScenario('bodyweight', nowMs: 2);

      expect(await profile.unit(), WeightUnit.lb);
      expect(await profile.analyticsEnabled(), isTrue);
      expect(await profile.trainingScenario(), 'bodyweight');
    });

    testWidgets('计划页顶部：三个场景都在，当前那个高亮点了会回调',
        (WidgetTester tester) async {
      TrainingScenario? picked;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: PlanScreen(
            repository: RoutineRepository(db),
            exercises: ExerciseRepository(db),
            store: DriftLocalStore(db),
            scenario: TrainingScenario.gym,
            onScenarioChanged: (TrainingScenario s) => picked = s,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scenario-gym')), findsOneWidget);
      expect(find.byKey(const Key('scenario-home')), findsOneWidget);
      expect(find.byKey(const Key('scenario-bodyweight')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('scenario-hint'))).data,
          TrainingScenario.gym.hint);

      await tester.tap(find.byKey(const Key('scenario-home')));
      await tester.pumpAndSettle();
      expect(picked, TrainingScenario.home);
    });
  });
}
