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
import 'package:lianleme/core/units.dart';
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

  /// 记一次训练：同一个 workoutId 下若干个正式组。
  ///
  /// `at` 只用来定**相对先后**（同一批数据里越大越新）；绝对时间锚在「现在」上。
  ///
  /// 为什么必须锚在现在：`LastSession.daysAgo` 现在是**真实天数**了。
  /// 以前这里写 `completedAtMs: 1000`（= 1970 年），那时 daysAgo 恒为 0 所以看不出问题；
  /// 接上真实天数后，每条历史都变成"两万天没练"，直接命中**回归保护**分支，
  /// 把「达标加重」「掉组保持」这些要测的分支全挡在外面。
  Future<void> train(
    String workoutId,
    String exerciseId, {
    List<int> reps = const <int>[10, 10, 10],
    /// 传 null 明确表示"自重"（按时长/自重动作必须这样，否则会被当成负重组）
    double? weight = 60,
    int at = 1000,
    int daysAgo = 1,
  }) async {
    final int base = DateTime.now().millisecondsSinceEpoch -
        daysAgo * Duration.millisecondsPerDay;
    for (int i = 0; i < reps.length; i++) {
      await store.saveSet(SetRecord(
        id: '${workoutId}_${exerciseId}_${i + 1}',
        workoutId: workoutId,
        exerciseId: exerciseId,
        setIndex: i + 1,
        reps: reps[i],
        weightKg: weight,
        completedAtMs: base + at + i,
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
      expect(bench.loadLabel, '62.5 kg × 8');
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

  group('证据链：建议卡要能看见「上次」', () {
    test('有历史时给出上次的事实（组数 · 重量 × 次数）', () async {
      await train('w_old', 'ex_bb_bench_press',
          reps: <int>[10, 10, 10], weight: 60);

      final List<PlannedExercise> plan =
          await planner.planToday(muscleGroup: 'chest');
      final PlannedExercise bench = plan
          .firstWhere((PlannedExercise p) => p.exercise.id == 'ex_bb_bench_press');

      expect(bench.historyLabel, '上次 3 组 · 60 kg × 10 次');
      expect(bench.suggestion!.reasonCode, ReasonCode.linearProgress);
    });

    test('组间次数不一致时只报最少的那组（引擎就是按它判断的）', () async {
      await train('w_old', 'ex_bb_bench_press', reps: <int>[10, 6, 5], weight: 60);

      final List<PlannedExercise> plan =
          await planner.planToday(muscleGroup: 'chest');
      final PlannedExercise bench = plan
          .firstWhere((PlannedExercise p) => p.exercise.id == 'ex_bb_bench_press');

      expect(bench.historyLabel, '上次 3 组 · 60 kg × 最少 5 次',
          reason: '报最大值会让用户觉得"我明明做到 10 次，凭什么不给我加重量"');
      expect(bench.suggestion!.reasonCode, ReasonCode.hold);
    });

    test('没历史时没有那一行（第一次练这个动作，理由文案已经说了）', () async {
      final List<PlannedExercise> plan =
          await planner.planToday(muscleGroup: 'chest');
      final PlannedExercise bench = plan
          .firstWhere((PlannedExercise p) => p.exercise.id == 'ex_bb_bench_press');

      expect(bench.lastSession, isNull);
      expect(bench.historyLabel, isNull);
    });

    test('单位是 lb 时，证据链也跟着换算', () async {
      await train('w_old', 'ex_bb_bench_press',
          reps: <int>[10, 10, 10], weight: 60);

      final List<PlannedExercise> plan = await planner.planToday(
          muscleGroup: 'chest', unit: WeightUnit.lb);
      final PlannedExercise bench = plan
          .firstWhere((PlannedExercise p) => p.exercise.id == 'ex_bb_bench_press');

      expect(bench.historyLabel, contains('lb'));
      expect(bench.historyLabel, isNot(contains('60 kg')));
    });

    test('「换一批」也要带单位 —— 以前这里漏了 unit，一换就变回 kg', () async {
      final List<PlannedExercise> first = await planner.planToday(
          muscleGroup: 'chest', unit: WeightUnit.lb);
      final List<PlannedExercise> again =
          await planner.reroll(current: first, unit: WeightUnit.lb);

      expect(again, isNotEmpty);
      for (final PlannedExercise p in again) {
        expect(p.unit, WeightUnit.lb,
            reason: '同一屏上两种单位是明显的 bug');
      }
    });
  });

  group('按时长动作（track_type 真的被读到了）', () {
    test('平板支撑的处方是 3 组 × 30–45 秒，不是 8–10 次', () async {
      final List<PlannedExercise> plan =
          await planner.planToday(muscleGroup: 'core', count: 60);
      final PlannedExercise plank =
          plan.firstWhere((PlannedExercise p) => p.exercise.id == 'ex_plank');

      expect(plank.exercise.trackType, 'time');
      expect(plank.plan.targetRepsLow, 30, reason: '数字的含义是"秒"');
      expect(plank.plan.targetRepsHigh, 45);
      expect(plank.loadLabel, '自重 × 30 秒');
      expect(plank.suggestion!.reasonText, contains('秒数'));
      expect(plank.suggestion!.reasonText, isNot(contains('次数')));
    });

    test('侧平板同属按时长；负重平板是 weight_time 且保留重量', () async {
      final List<PlannedExercise> plan =
          await planner.planToday(muscleGroup: 'core', count: 60);
      final PlannedExercise side =
          plan.firstWhere((PlannedExercise p) => p.exercise.id == 'ex_side_plank');
      final PlannedExercise wp =
          plan.firstWhere((PlannedExercise p) => p.exercise.id == 'ex_weighted_plank');

      expect(side.exercise.trackType, 'time');
      expect(side.plan.targetRepsHigh, 45);
      expect(wp.exercise.trackType, 'weight_time');
      expect(wp.plan.targetRepsHigh, 45);
      expect(wp.loadLabel, contains('kg'), reason: '它有重量，不是自重');
    });

    test('有历史时，证据链那一行也念「秒」', () async {
      await train('w_old', 'ex_plank', reps: <int>[40, 40, 40], weight: null);

      final List<PlannedExercise> plan =
          await planner.planToday(muscleGroup: 'core', count: 60);
      final PlannedExercise plank =
          plan.firstWhere((PlannedExercise p) => p.exercise.id == 'ex_plank');

      expect(plank.historyLabel, '上次 3 组 · 自重 × 40 秒');
      expect(plank.suggestion!.reasonText, contains('40 → 45 秒'));
    });

    test('非时长动作的处方不受影响（负重与自重次数都是 3 组 × 8–10 次）', () async {
      final List<PlannedExercise> plan =
          await planner.planToday(muscleGroup: 'chest', count: 60);
      for (final PlannedExercise p in plan) {
        // ⚠️ 这条测试原本断言"chest 里全都是 weight_reps" —— 那是在断言**字段值**，
        // 而不是它想守的东西。2026-09-29 按上游把俯卧撑类如实标成 reps_only
        // （自重次数）之后它就红了，于是改成断言本意：**不是时长动作，处方不变**。
        expect(isTimeTrack(p.exercise.trackType), isFalse,
            reason: '${p.exercise.id} 不该被当成按时长动作');
        expect(p.plan.targetRepsHigh, 10, reason: '还是 3 组 × 8–10 次');
      }
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
