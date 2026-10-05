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
    Future<void> pumpSummary(WidgetTester tester, String workoutId,
        {List<ExerciseData> stretches = const <ExerciseData>[]}) async {
      await tester.pumpWidget(MaterialApp(
        home: WorkoutSummaryScreen(
          service: service,
          workoutId: workoutId,
          stretches: stretches,
        ),
      ));
      await tester.pumpAndSettle();
    }

    /// 造一个"练完该拉一下"的候选（拉伸动作在库里是 category=stretch）
    ExerciseData stretch(String id, String name, String how) => ExerciseData(
          id: id,
          name: name,
          aliases: '[]',
          muscleGroup: 'chest',
          secondaryMuscles: '[]',
          equipment: 'bodyweight',
          category: 'stretch',
          trackType: 'time',
          defaultRestSec: 30,
          instructions: how,
          weightIncrement: 0,
          isBuiltin: true,
          popularity: 20,
          createdAt: 0,
          updatedAt: 0,
        );

    testWidgets('★ 系统大字号 1.5× 也不溢出（总结页是练完第一眼看到的那屏）',
        (WidgetTester tester) async {
      // 三个大数（容量/时长/组数）横排 + 分享卡按钮，是这一屏最容易挤爆的地方。
      tester.view.physicalSize = const Size(1233, 2742);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await logSets('w_big_text', 'ex_bb_bench_press',
          <_S>[_S(8, 60), _S(8, 60), _S(8, 60)],
          startedAt: 0, from: 1000);
      await pumpSummary(tester, 'w_big_text');

      // 溢出会让测试直接失败；这里再钉住三个大数与主按钮都还在
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('summary-volume')), findsOneWidget);
      expect(find.byKey(const Key('summary-duration')), findsOneWidget);
      expect(find.byKey(const Key('summary-sets')), findsOneWidget);
    });

    testWidgets('显示容量 / 时长 / 组数三个大数', (WidgetTester tester) async {
      await logSets('w1', 'ex_bb_bench_press',
          <_S>[_S(8, 60), _S(8, 60), _S(8, 60)],
          startedAt: 0, from: 1000);
      await pumpSummary(tester, 'w1');

      expect(find.byKey(const Key('summary-volume')), findsOneWidget);
      expect(find.byKey(const Key('summary-duration')), findsOneWidget);
      expect(find.byKey(const Key('summary-sets')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('summary-sets'))).data, '3');
      expect(find.text('训练完成！'), findsOneWidget);
      // 2026-10-05 新 VI：完成标记是**绿色实心圆 + 白勾**，且用的是语义色 success
      expect(find.byKey(const Key('summary-done-title')), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.check_rounded)).color,
        const Color(0xFF06231A),
        reason: '勾的颜色变了就是换皮肤时被顺手改掉了',
      );
    });

    testWidgets('三个大数在同一水平线上：中间那格再长也不许换行把标签顶下去',
        (WidgetTester tester) async {
      // 这一条来自 2026-10-01 的真机走查：练了 2 组、时长不到 1 分钟时，
      // 中格的值是「不到 1 分钟」—— 它换行成两行，把「时长」这个标签
      // 压到比左右两格低一截，三格看起来就是歪的。
      await logSets('w1', 'ex_bb_bench_press', <_S>[_S(8, 60)],
          startedAt: 0, from: 20000);
      await pumpSummary(tester, 'w1');

      expect(
        tester.widget<Text>(find.byKey(const Key('summary-duration'))).data,
        contains('不到'),
        reason: '前置：这一格的值就是那句会长到换行的人话',
      );

      // 值必须是单行（长就整体缩，不换行）
      for (final String key in <String>['summary-volume', 'summary-duration', 'summary-sets']) {
        final Text t = tester.widget<Text>(find.byKey(Key(key)));
        expect(t.maxLines, 1, reason: '$key 的大数必须单行');
      }

      // 三个标签的纵向中心必须一致 —— 这才是"对齐"的可观测判据
      final double y1 = tester.getCenter(find.text('容量')).dy;
      final double y2 = tester.getCenter(find.text('时长')).dy;
      final double y3 = tester.getCenter(find.text('组数')).dy;
      expect(y2, closeTo(y1, 0.5), reason: '「时长」标签被换行顶下去了');
      expect(y3, closeTo(y1, 0.5));
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
      expect(find.text('训练完成！'), findsOneWidget);

      await tester.tap(find.byKey(const Key('summary-done')));
      await tester.pumpAndSettle();
      expect(find.text('训练完成！'), findsNothing);
    });

    testWidgets('练完给拉伸建议：有动作就显示，带做法', (WidgetTester tester) async {
      await logSets('w1', 'ex_bb_bench_press',
          <_S>[_S(8, 60), _S(8, 60), _S(8, 60)], startedAt: 0, from: 1000);
      await pumpSummary(tester, 'w1', stretches: <ExerciseData>[
        stretch('ex_doorway_chest_stretch', '门框胸部拉伸', '小臂贴在门框上、身体往前送。'),
      ]);
      expect(find.byKey(const Key('summary-stretch')), findsOneWidget);
      expect(find.text('练完拉伸一下'), findsOneWidget);
      expect(find.text('门框胸部拉伸'), findsOneWidget);
      expect(find.textContaining('小臂贴在门框上'), findsOneWidget);
    });

    testWidgets('没有拉伸建议时整块不出现（不占一块空地方）',
        (WidgetTester tester) async {
      await logSets('w1', 'ex_bb_bench_press',
          <_S>[_S(8, 60), _S(8, 60), _S(8, 60)], startedAt: 0, from: 1000);
      await pumpSummary(tester, 'w1');
      expect(find.byKey(const Key('summary-stretch')), findsNothing);
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

  // ─── 一句话笔记（2026-10-04）────────────────────────────────────────────
  // 列 `workout.note` 从第一天起就在、`progress_screen` 也一直在显示它，
  // 但**没有任何写入路径** —— 是个只读的死字段。训记的「训记备忘录」就是它。
  group('一句话笔记', () {
    test('写进去、读得出来、空字符串等于清掉', () async {
      await logSets('w1', 'ex_bb_bench_press', <_S>[_S(60, 8)]);
      expect((await service.build('w1'))!.note, isNull, reason: '本来没写');

      await service.setNote('w1', '状态一般，肩膀有点紧');
      expect((await service.build('w1'))!.note, '状态一般，肩膀有点紧');

      await service.setNote('w1', '   ');
      expect((await service.build('w1'))!.note, isNull,
          reason: '清空之后不该留一个空白字符串（界面会显示一行空的）');
    });

    test('★ 笔记不会被后续的 saveWorkout 抹掉（整行 upsert 的陷阱）', () async {
      // saveWorkout 是**整行 upsert**：以前它压根不带 note 这一列，
      // 于是任何一次保存都会把用户写的那句话覆盖成 NULL。
      // 这条就是钉那个陷阱 —— 写笔记之后再存一次 workout，笔记必须还在。
      await logSets('w1', 'ex_bb_bench_press', <_S>[_S(60, 8)]);
      await service.setNote('w1', '今天加了 2.5kg');

      final Workout? w = await store.loadWorkout('w1');
      await store.saveWorkout(w!); // 再存一遍（真实场景：又记了一组）

      expect((await store.loadWorkout('w1'))!.note, '今天加了 2.5kg');
      expect((await service.build('w1'))!.note, '今天加了 2.5kg');
    });

    test('写不存在的训练不炸', () async {
      await service.setNote('没这个 id', '随便写点');
      expect(await store.loadWorkout('没这个 id'), isNull);
    });
  });
}
