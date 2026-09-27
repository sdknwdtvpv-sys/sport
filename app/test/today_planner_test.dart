/// 练了么 ·「今天练什么」测试
///
/// 这是产品第二个楔子的核心逻辑：让用户连计划都不用搭。
/// 规则全部可解释，所以全部可断言 —— 不涉及任何不可预测的东西。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/today/today_planner.dart';

void main() {
  late AppDatabase db;
  late DriftLocalStore store;
  late ExerciseRepository repo;
  late TodayPlanner planner;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLocalStore(db);
    repo = ExerciseRepository(db);
    planner = TodayPlanner(repository: repo, store: store);
    await repo.importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
  });

  tearDown(() => db.close());

  /// 记一次训练：同一个 workoutId 下若干个正式组
  Future<void> train(
    String workoutId,
    String exerciseId, {
    List<int> reps = const <int>[10, 10, 10],
    double weight = 60,
    int at = 1000,
  }) async {
    for (int i = 0; i < reps.length; i++) {
      await store.saveSet(SetRecord(
        id: '${workoutId}_${exerciseId}_${i + 1}',
        workoutId: workoutId,
        exerciseId: exerciseId,
        setIndex: i + 1,
        reps: reps[i],
        weightKg: weight,
        completedAtMs: at + i,
      ));
    }
  }

  group('部位轮转', () {
    test('从没练过 → 从轮转的第一个部位（胸）开始', () async {
      expect(await planner.nextMuscleGroup(), 'chest');
    });

    test('练过胸 → 下次轮到背', () async {
      await train('w1', 'ex_bb_bench_press');
      expect(await planner.nextMuscleGroup(), 'back');
    });

    test('练过胸 + 背 → 下次轮到腿', () async {
      await train('w1', 'ex_bb_bench_press');
      await train('w1', 'ex_bb_row', at: 2000);
      expect(await planner.nextMuscleGroup(), 'legs');
    });

    test('六个部位都练过 → 回到第一个', () async {
      await train('w1', 'ex_bb_bench_press'); // chest
      await train('w1', 'ex_bb_row', at: 2000); // back
      await train('w1', 'ex_bb_squat', at: 3000); // legs
      await train('w1', 'ex_bb_ohp', at: 4000); // shoulders
      await train('w1', 'ex_bb_curl', at: 5000); // arms
      await train('w1', 'ex_crunch', at: 6000); // core

      expect(await planner.nextMuscleGroup(), 'chest');
    });

    test('只看最近一次训练：更早练过的不影响轮转', () async {
      await train('w_old', 'ex_bb_squat', at: 1000); // 上次：腿
      await train('w_new', 'ex_bb_row', at: 9000); // 最近：背

      // 最近只练了背 → 轮转里胸没练 → 该练胸
      expect(await planner.nextMuscleGroup(), 'chest');
    });
  });

  group('今日建议', () {
    test('推荐 3 个动作，每个都带建议和一行理由（首练）', () async {
      final List<PlannedExercise> plan = await planner.planToday();

      expect(plan.length, 3);
      for (final PlannedExercise p in plan) {
        expect(p.exercise.muscleGroup, 'chest');
        expect(p.suggestion, isNotNull);
        expect(p.suggestion!.reasonText, isNotEmpty,
            reason: '红线：解释不了的建议不许出现');
        expect(p.suggestion!.reasonCode, ReasonCode.firstTime);
      }
    });

    test('有历史时建议会推进：3 组达标 → 加重', () async {
      await train('w_old', 'ex_bb_bench_press',
          reps: <int>[10, 10, 10], weight: 60, at: 1000);

      final List<PlannedExercise> plan =
          await planner.planToday(muscleGroup: 'chest');
      final PlannedExercise bench = plan
          .firstWhere((PlannedExercise p) => p.exercise.id == 'ex_bb_bench_press');

      expect(bench.suggestion!.reasonCode, ReasonCode.linearProgress);
      expect(bench.suggestion!.weightKg, 62.5);
      expect(bench.suggestion!.reasonText, contains('+2.5kg'));
      expect(bench.loadLabel, '62.5kg × 8');
    });

    test('掉组时保持重量（历史真的进了引擎）', () async {
      await train('w_old', 'ex_bb_bench_press',
          reps: <int>[10, 6, 5], weight: 60, at: 1000);

      final List<PlannedExercise> plan =
          await planner.planToday(muscleGroup: 'chest');
      final PlannedExercise bench = plan
          .firstWhere((PlannedExercise p) => p.exercise.id == 'ex_bb_bench_press');

      expect(bench.suggestion!.reasonCode, ReasonCode.hold);
      expect(bench.suggestion!.weightKg, 60);
    });

    test('自重动作的展示是「自重 × n」', () async {
      final List<PlannedExercise> plan =
          await planner.planToday(muscleGroup: 'back', count: 60);
      final Iterable<PlannedExercise> pull =
          plan.where((PlannedExercise p) => p.exercise.id == 'ex_pull_up');

      expect(pull, isNotEmpty, reason: '背部位应该有引体向上');
      expect(pull.first.suggestion!.isBodyweight, isTrue);
      expect(pull.first.loadLabel, startsWith('自重 × '));
    });

    test('count 生效', () async {
      expect((await planner.planToday(count: 5)).length, 5);
    });

    test('指定部位时不走轮转', () async {
      await train('w1', 'ex_bb_bench_press'); // 练过胸，轮转本该给背
      final List<PlannedExercise> plan =
          await planner.planToday(muscleGroup: 'shoulders');

      expect(plan.every((PlannedExercise p) => p.exercise.muscleGroup == 'shoulders'),
          isTrue);
    });
  });

  group('换一批', () {
    test('换掉动作，不复用已推荐过的', () async {
      final List<PlannedExercise> first = await planner.planToday();
      final List<PlannedExercise> again =
          await planner.reroll(current: first);

      final Set<String> a =
          first.map((PlannedExercise p) => p.exercise.id).toSet();
      final Set<String> b =
          again.map((PlannedExercise p) => p.exercise.id).toSet();

      expect(b.intersection(a), isEmpty);
      expect(again.length, first.length);
      expect(again.every((PlannedExercise p) => p.suggestion != null), isTrue);
    });

    test('同一部位动作不够换时保持原样，不会返回空', () async {
      // core 的动作少，要一大批就换不出等量的
      final List<PlannedExercise> first =
          await planner.planToday(muscleGroup: 'core', count: 60);
      final List<PlannedExercise> again =
          await planner.reroll(current: first, count: 60);

      expect(again, isNotEmpty);
    });
  });
}
