/// 练了么 · S7 训练结束总结（逻辑 + 界面）
///
/// 破纪录的判定是最容易做错的地方，两条例外都有测试守着：
///   1. **第一次练某个动作不算破纪录** —— 没有历史可比
///   2. **判定必须排除本次训练** —— 否则每次练完都是"新纪录"
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/summary/workout_summary.dart';
import 'package:lianleme/features/summary/workout_summary_screen.dart';

/// 一组：次数 + 可选重量
class _S {
  const _S(this.reps, [this.weight]);
  final int reps;
  final double? weight;
}

void main() {
  late AppDatabase db;
  late DriftLocalStore store;
  late ExerciseRepository repo;
  late SummaryService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLocalStore(db);
    repo = ExerciseRepository(db);
    service = SummaryService(store: store, repository: repo);
    await repo.importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
  });

  tearDown(() => db.close());

  /// 记一次训练。会先建 workout 行 —— loadWorkout 找不到行就会返回 null。
  Future<void> logSets(
    String workoutId,
    String exerciseId,
    List<_S> sets, {
    int from = 1000,
    int? startedAt,
  }) async {
    await store.saveWorkout(
      Workout(id: workoutId, startedAtMs: startedAt ?? from),
    );
    for (int i = 0; i < sets.length; i++) {
      await store.saveSet(SetRecord(
        id: '$workoutId|$exerciseId|$i',
        workoutId: workoutId,
        exerciseId: exerciseId,
        setIndex: i + 1,
        reps: sets[i].reps,
        weightKg: sets[i].weight,
        completedAtMs: from + i * 1000,
      ));
    }
  }

  group('总结数据', () {
    test('一组都没练 → 返回 null', () async {
      await store.saveWorkout(Workout(id: 'w_empty', startedAtMs: 1000));
      expect(await service.build('w_empty'), isNull);
    });

    test('查不到这次训练 → 返回 null', () async {
      expect(await service.build('w_nope'), isNull);
    });

    test('容量 / 组数 / 动作数都对', () async {
      await logSets('w1', 'ex_bb_bench_press',
          <_S>[_S(8, 60), _S(8, 60), _S(8, 60)]);
      await logSets('w1', 'ex_bb_squat', <_S>[_S(10, 80)], from: 10000);

      final WorkoutSummary s = (await service.build('w1'))!;
      expect(s.totalSets, 4);
      expect(s.totalVolumeKg, 60 * 8 * 3 + 80 * 10);
      expect(s.exerciseCount, 2);
    });

    test('时长由结束时间算出来', () async {
      await logSets('w1', 'ex_bb_bench_press', <_S>[_S(8, 60)],
          startedAt: 0, from: 1000);

      // 42 分钟后结束
      final WorkoutSummary s =
          (await service.build('w1', nowMs: 42 * 60 * 1000))!;
      expect(s.duration, const Duration(minutes: 42));
      expect(s.durationLabel, '42 分钟');
    });

    test('结束时间会落库（重开也算得出时长）', () async {
      await logSets('w1', 'ex_bb_bench_press', <_S>[_S(8, 60)],
          startedAt: 0, from: 1000);
      await service.build('w1', nowMs: 600000);

      final Workout? w = await store.loadWorkout('w1');
      expect(w!.isFinished, isTrue);
      expect(w.endedAtMs, 600000);
      expect(w.duration, const Duration(minutes: 10));
    });

    test('自重动作的容量显示为「自重」而不是 0 kg', () async {
      await logSets('w1', 'ex_pull_up', <_S>[_S(8), _S(8)]);

      final WorkoutSummary s = (await service.build('w1'))!;
      expect(s.totalVolumeKg, 0);
      expect(s.volumeLabel, '自重');
    });
  });

  group('破纪录判定', () {
    test('第一次练这个动作 → 不算破纪录', () async {
      await logSets('w1', 'ex_bb_bench_press', <_S>[_S(8, 60), _S(8, 60)]);

      final WorkoutSummary s = (await service.build('w1'))!;
      expect(s.hasPr, isFalse, reason: '没有历史可比，第一次不该叫破纪录');
    });

    test('重量超过历史最佳 → 破纪录', () async {
      await logSets('w_old', 'ex_bb_bench_press', <_S>[_S(8, 60), _S(8, 60)],
          from: 1000);
      await logSets('w_new', 'ex_bb_bench_press', <_S>[_S(8, 65)],
          from: 100000);

      final WorkoutSummary s = (await service.build('w_new'))!;
      expect(s.hasPr, isTrue);
      expect(s.prs.single.exerciseName, '杠铃卧推');
      expect(s.prs.single.weightKg, 65);
      expect(s.prs.single.previousBest, 60);
      expect(s.prs.single.detail, '65 kg（上次最好 60 kg）');
    });

    test('重量没超过历史最佳 → 不破纪录（含持平）', () async {
      await logSets('w_old', 'ex_bb_bench_press', <_S>[_S(8, 60)], from: 1000);
      await logSets('w_same', 'ex_bb_bench_press', <_S>[_S(8, 60)], from: 100000);

      expect((await service.build('w_same'))!.hasPr, isFalse);
    });

    test('判定排除本次训练 —— 否则每组都是新纪录', () async {
      // 本次第一组就 70kg，随后还有一组同样 70kg；历史最佳只有 60kg
      await logSets('w_old', 'ex_bb_bench_press', <_S>[_S(8, 60)], from: 1000);
      await logSets('w_new', 'ex_bb_bench_press',
          <_S>[_S(8, 70), _S(8, 70), _S(8, 70)], from: 100000);

      final WorkoutSummary s = (await service.build('w_new'))!;
      expect(s.prs.length, 1, reason: '一个动作只出一条纪录，而不是每组一条');
      expect(s.prs.single.previousBest, 60, reason: '历史最佳不能把本次的 70 算进去');
    });

    test('自重动作比次数，不比公斤', () async {
      await logSets('w_old', 'ex_pull_up', <_S>[_S(8), _S(8)], from: 1000);
      await logSets('w_new', 'ex_pull_up', <_S>[_S(12), _S(10)], from: 100000);

      final WorkoutSummary s = (await service.build('w_new'))!;
      expect(s.hasPr, isTrue);
      expect(s.prs.single.isBodyweight, isTrue);
      expect(s.prs.single.reps, 12);
      expect(s.prs.single.previousBest, 8);
      expect(s.prs.single.detail, '12 次（上次最好 8 次）');
    });

    test('自重动作次数没超过 → 不破纪录', () async {
      await logSets('w_old', 'ex_pull_up', <_S>[_S(12), _S(12)], from: 1000);
      await logSets('w_new', 'ex_pull_up', <_S>[_S(10), _S(11)], from: 100000);

      expect((await service.build('w_new'))!.hasPr, isFalse);
    });

    test('多个动作各判各的', () async {
      await logSets('w_old', 'ex_bb_bench_press', <_S>[_S(8, 60)], from: 1000);
      await logSets('w_old', 'ex_bb_squat', <_S>[_S(8, 100)], from: 2000);
      // 卧推破纪录（65 > 60），深蹲没有（90 < 100）
      await logSets('w_new', 'ex_bb_bench_press', <_S>[_S(8, 65)], from: 100000);
      await logSets('w_new', 'ex_bb_squat', <_S>[_S(8, 90)], from: 200000);

      final WorkoutSummary s = (await service.build('w_new'))!;
      expect(s.prs.length, 1);
      expect(s.prs.single.exerciseId, 'ex_bb_bench_press');
    });
  });

  group('界面', () {
    Future<void> pumpSummary(WidgetTester tester, String workoutId) async {
      await tester.pumpWidget(MaterialApp(
        home: WorkoutSummaryScreen(service: service, workoutId: workoutId),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('显示容量 / 时长 / 组数三个大数', (WidgetTester tester) async {
      await logSets('w1', 'ex_bb_bench_press',
          <_S>[_S(8, 60), _S(8, 60), _S(8, 60)],
          startedAt: 0, from: 1000);
      await pumpSummary(tester, 'w1');

      expect(find.byKey(const Key('summary-volume')), findsOneWidget);
      expect(find.byKey(const Key('summary-duration')), findsOneWidget);
      expect(find.byKey(const Key('summary-sets')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('summary-sets'))).data, '3');
      expect(find.text('训练完成'), findsOneWidget);
    });

    testWidgets('有破纪录时显示纪录区块，且不只靠颜色表达',
        (WidgetTester tester) async {
      await logSets('w_old', 'ex_bb_bench_press', <_S>[_S(8, 60)], from: 1000);
      await logSets('w_new', 'ex_bb_bench_press', <_S>[_S(8, 65)], from: 100000);
      await pumpSummary(tester, 'w_new');

      expect(find.text('破纪录'), findsOneWidget);
      expect(find.byKey(const Key('summary-pr-ex_bb_bench_press')), findsOneWidget);
      expect(find.text('65 kg（上次最好 60 kg）'), findsOneWidget);
      expect(find.text('★'), findsOneWidget, reason: '色盲用户也要能看出来');
    });

    testWidgets('没破纪录时不显示纪录区块', (WidgetTester tester) async {
      await logSets('w1', 'ex_bb_bench_press', <_S>[_S(8, 60)]); // 首练
      await pumpSummary(tester, 'w1');

      expect(find.textContaining('破纪录'), findsNothing);
      expect(find.text('★'), findsNothing);
    });

    testWidgets('一组都没练时给出明确说明，而不是空白', (WidgetTester tester) async {
      await store.saveWorkout(Workout(id: 'w_empty', startedAtMs: 1000));
      await pumpSummary(tester, 'w_empty');

      expect(find.textContaining('没有记录到任何一组'), findsOneWidget);
    });

    testWidgets('点「完成」返回', (WidgetTester tester) async {
      await logSets('w1', 'ex_bb_bench_press', <_S>[_S(8, 60)]);

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        WorkoutSummaryScreen(service: service, workoutId: 'w1'),
                  ),
                ),
                child: const Text('看总结'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('看总结'));
      await tester.pumpAndSettle();
      expect(find.text('训练完成'), findsOneWidget);

      await tester.tap(find.byKey(const Key('summary-done')));
      await tester.pumpAndSettle();
      expect(find.text('训练完成'), findsNothing);
    });
  });

  group('有氧：里程与配速，且不冒充力量纪录', () {
    // 这一组守的是"假数据"那条线：距离动作的 reps 是**秒**、weight 是 null，
    // 按原来的"自重比次数"逻辑，一次 5 公里跑会得到一条"1800 次新纪录"。
    test('里程聚合进来，且**不加进容量**（两个量纲）', () async {
      final Workout w = Workout(id: 'w_run', startedAtMs: 1000)
        ..sets.addAll(<SetRecord>[
          SetRecord(
            id: 's1', workoutId: 'w_run', exerciseId: 'ex_treadmill_incline_walk',
            setIndex: 1, reps: 1800, distanceM: 5000, completedAtMs: 1000,
          ),
          SetRecord(
            id: 's2', workoutId: 'w_run', exerciseId: 'ex_treadmill_incline_walk',
            setIndex: 2, reps: 600, distanceM: 1500, completedAtMs: 2000,
          ),
        ]);
      await store.saveWorkout(w);
      for (final SetRecord r in w.sets) {
        await store.saveSet(r);
      }

      final WorkoutSummary s = (await service.build('w_run', nowMs: 3000))!;

      expect(s.distanceM, 6500);
      expect(s.hasDistance, isTrue);
      expect(s.distanceLabel, '6.50 公里');
      expect(s.totalVolumeKg, 0, reason: '有氧不产生容量，也不许它污染容量的数字');
      expect(s.cardiovascularLabels, <String>['跑步机爬坡走']);
    });

    test('距离动作**不判**力量纪录（否则会出"1800 次新纪录"）', () async {
      // 先造一次历史，再练一次更"多"，看它会不会被判成破纪录
      final Workout old = Workout(id: 'w_old', startedAtMs: 0)
        ..sets.add(SetRecord(
          id: 's_old', workoutId: 'w_old', exerciseId: 'ex_treadmill_incline_walk',
          setIndex: 1, reps: 1200, distanceM: 3000, completedAtMs: 10,
        ));
      await store.saveWorkout(old);
      for (final SetRecord r in old.sets) {
        await store.saveSet(r);
      }

      final Workout now = Workout(id: 'w_now', startedAtMs: 5000)
        ..sets.add(SetRecord(
          id: 's_now', workoutId: 'w_now', exerciseId: 'ex_treadmill_incline_walk',
          setIndex: 1, reps: 1800, distanceM: 5000, completedAtMs: 5000,
        ));
      await store.saveWorkout(now);
      for (final SetRecord r in now.sets) {
        await store.saveSet(r);
      }

      final WorkoutSummary s = (await service.build('w_now', nowMs: 9000))!;

      expect(s.prs, isEmpty, reason: '"1800 次"是秒数，不是纪录');
      expect(s.hasPr, isFalse);
      expect(s.distanceM, 5000, reason: '里程本身照常统计');
    });

    test('混合训练：力量纪录照旧，有氧另外报里程', () async {
      final Workout w = Workout(id: 'w_mix', startedAtMs: 1000)
        ..sets.addAll(<SetRecord>[
          SetRecord(
            id: 's_bench', workoutId: 'w_mix', exerciseId: 'ex_bb_bench_press',
            setIndex: 1, reps: 8, weightKg: 62.5, completedAtMs: 1000,
          ),
          SetRecord(
            id: 's_run', workoutId: 'w_mix', exerciseId: 'ex_treadmill_incline_walk',
            setIndex: 2, reps: 1200, distanceM: 4000, completedAtMs: 2000,
          ),
        ]);
      await store.saveWorkout(w);
      for (final SetRecord r in w.sets) {
        await store.saveSet(r);
      }
      // 卧推的历史，让"这次 62.5 破纪录"成立
      final Workout hist = Workout(id: 'w_hist', startedAtMs: 0)
        ..sets.add(SetRecord(
          id: 's_h', workoutId: 'w_hist', exerciseId: 'ex_bb_bench_press',
          setIndex: 1, reps: 8, weightKg: 60, completedAtMs: 10,
        ));
      await store.saveWorkout(hist);
      for (final SetRecord r in hist.sets) {
        await store.saveSet(r);
      }

      final WorkoutSummary s = (await service.build('w_mix', nowMs: 9000))!;

      expect(s.prs.map((SetPr p) => p.exerciseId), <String>['ex_bb_bench_press']);
      expect(s.distanceM, 4000);
    });
  });
}
