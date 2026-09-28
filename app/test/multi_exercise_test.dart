/// 练了么 · 多动作共享同一次训练
///
/// 这是"一次训练 = 一个 workoutId"的回归测试。
/// 如果哪天有人把 workoutId 改回每个控制器各自一份，一次训练就会被拆成多次 —— 这里会红。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/analytics.dart';
// db.dart（drift 表）与 models.dart（领域模型）都定义了 Workout / SetRecord，
// 使用时必须 hide 掉表类，否则 ambiguity_import。
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/sync_queue.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/workout/workout_controller.dart';

const PlanTarget _plan = PlanTarget(
  targetSets: 3,
  targetRepsLow: 8,
  targetRepsHigh: 10,
);

/// 控制器对本地库的写入是 fire-and-forget（不阻塞 UI），
/// 所以测试要等它落盘，不能直接断言。
Future<void> _waitForSets(LocalStore store, String workoutId, int n) async {
  for (int i = 0; i < 100; i++) {
    if ((await store.setsFor(workoutId)).length >= n) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('等待 $n 条记录落盘超时');
}

void main() {
  late AppDatabase db;
  late DriftLocalStore store;
  late ExerciseRepository repo;
  late InMemorySyncQueue queue;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLocalStore(db);
    repo = ExerciseRepository(db);
    queue = InMemorySyncQueue();
    await repo.importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
  });

  tearDown(() => db.close());

  /// 用**真实种子数据**构造控制器，而不是硬编一份 spec ——
  /// 否则测试通过也只证明了假数据能跑。
  Future<WorkoutController> controllerFor(
    String workoutId,
    String exerciseId,
    int clockBase,
  ) async {
    final List<ExerciseData> rows = await repo.search(limit: 200);
    final ExerciseData row =
        rows.firstWhere((ExerciseData r) => r.id == exerciseId);
    return WorkoutController(
      workoutId: workoutId,
      exercise: repo.specOf(row),
      plan: _plan,
      // 每个控制器一份独立埋点，避免互相影响断言。
      // 真实 App 里所有控制器**共用同一个** `OutboxAnalytics`（main.dart 的 `_analytics`），
      // 这也是端到端 tap_count 的前提：构造函数用 `ensure()` 而不是 `begin()`，
      // 所以后构造的控制器不会把前面攒下的导航/切换点击清零。
      analytics: RecordingAnalytics(),
      store: store,
      syncQueue: queue,
      clock: () => clockBase++,
    );
  }

  test('两个动作共享 workoutId 时，记录挂在同一次训练下', () async {
    const String session = 'w_session_1';
    final WorkoutController bench =
        await controllerFor(session, 'ex_bb_bench_press', 1000);
    final WorkoutController squat =
        await controllerFor(session, 'ex_bb_squat', 2000);

    bench.onBigButtonTap(); // 每个动作各记一组
    squat.onBigButtonTap();

    await _waitForSets(store, session, 2);

    final List<SetRecord> sets = await store.setsFor(session);
    expect(sets.length, 2, reason: '两个动作的记录必须落在同一次训练下');
    expect(
      sets.map((SetRecord s) => s.exerciseId).toSet(),
      <String>{'ex_bb_bench_press', 'ex_bb_squat'},
    );
    expect(sets.map((SetRecord s) => s.setIndex).toList(), <int>[1, 1],
        reason: '每个动作的组序各自从 1 开始');

    bench.dispose();
    squat.dispose();
  });

  test('训练行本身也落库了（重启后 loadWorkout 才找得到）', () async {
    const String session = 'w_session_2';
    final WorkoutController bench =
        await controllerFor(session, 'ex_bb_bench_press', 1000);
    bench.onBigButtonTap();
    bench.onBigButtonTap();

    await _waitForSets(store, session, 2);

    final Workout? loaded = await store.loadWorkout(session);
    expect(loaded, isNotNull,
        reason: '只写 set_record 不写 workout 行，这里就会是 null');
    expect(loaded!.sets.length, 2);
    expect(loaded.totalSets, 2);
    // 杠铃卧推种子值：40kg 起始 × 8 次（计划区间下限）× 2 组
    expect(loaded.totalVolume, 40 * 8 * 2);

    bench.dispose();
  });

  test('不同 workoutId 的训练互不干扰', () async {
    final WorkoutController a =
        await controllerFor('w_a', 'ex_bb_bench_press', 1000);
    final WorkoutController b =
        await controllerFor('w_b', 'ex_bb_bench_press', 2000);

    a.onBigButtonTap();
    b.onBigButtonTap();

    await _waitForSets(store, 'w_a', 1);
    await _waitForSets(store, 'w_b', 1);

    expect((await store.setsFor('w_a')).length, 1);
    expect((await store.setsFor('w_b')).length, 1);

    a.dispose();
    b.dispose();
  });

  test('同一次训练内，历史仍按动作隔离', () async {
    const String session = 'w_session_3';
    final WorkoutController bench =
        await controllerFor(session, 'ex_bb_bench_press', 1000);
    bench.onBigButtonTap();
    await _waitForSets(store, session, 1);

    final LastSession? benchHistory =
        await store.lastSessionFor('ex_bb_bench_press');
    final LastSession? squatHistory = await store.lastSessionFor('ex_bb_squat');

    expect(benchHistory, isNotNull);
    expect(benchHistory!.reps, <int>[8]);
    expect(squatHistory, isNull, reason: '没练过的动作不该有历史');

    bench.dispose();
  });
}
