/// 练了么 · LocalStore 契约测试
///
/// **同一组断言同时跑在两个实现上**（内存版与 drift 版）。
/// 这样两个实现就不会偷偷分叉 —— 内存版跑得快、用于 widget 测试，
/// drift 版是真身在真机上用的，两者行为必须一致。
///
/// 这份文件也是"接线 drift 时 UI 与控制器一行都不用改"这句话的证明：
/// 换实现只影响这里的一个工厂。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// db.dart（drift 表）与 models.dart（领域模型）都定义了 Workout / SetRecord。
// 只 import 前者里的 AppDatabase，把同名表类 hide 掉，避免使用时名字歧义。
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/domain/models.dart';

/// 一个实现的装配与拆卸
abstract class StoreHarness {
  String get label;
  LocalStore create();
  Future<void> dispose();
}

class InMemoryHarness implements StoreHarness {
  @override
  String get label => 'InMemoryLocalStore';

  @override
  LocalStore create() => InMemoryLocalStore();

  @override
  Future<void> dispose() async {}
}

class DriftHarness implements StoreHarness {
  late AppDatabase db;

  @override
  String get label => 'DriftLocalStore';

  @override
  LocalStore create() {
    db = AppDatabase(NativeDatabase.memory());
    return DriftLocalStore(db);
  }

  @override
  Future<void> dispose() => db.close();
}

SetRecord _set({
  required String id,
  required String workoutId,
  required String exerciseId,
  required int setIndex,
  required int reps,
  required int atMs,
  double? weightKg = 60,
  SetType setType = SetType.normal,
  double? rpe,
}) =>
    SetRecord(
      id: id,
      workoutId: workoutId,
      exerciseId: exerciseId,
      setIndex: setIndex,
      reps: reps,
      completedAtMs: atMs,
      weightKg: weightKg,
      setType: setType,
      rpe: rpe,
    );

void runContractTests(StoreHarness harness) {
  group(harness.label, () {
    late LocalStore store;

    setUp(() => store = harness.create());
    tearDown(() => harness.dispose());

    test('保存的组能按 workout 读回来，并按组序排列', () async {
      await store.saveSet(_set(id: 's2', workoutId: 'w1', exerciseId: 'bench', setIndex: 2, reps: 8, atMs: 2000));
      await store.saveSet(_set(id: 's1', workoutId: 'w1', exerciseId: 'bench', setIndex: 1, reps: 10, atMs: 1000));

      final sets = await store.setsFor('w1');
      expect(sets.map((SetRecord s) => s.id).toList(), <String>['s1', 's2']);
      expect(sets.first.reps, 10);
      expect(sets.first.weightKg, 60);
    });

    test('不同 workout 的组互不串台', () async {
      await store.saveSet(_set(id: 'a', workoutId: 'w1', exerciseId: 'bench', setIndex: 1, reps: 8, atMs: 1000));
      await store.saveSet(_set(id: 'b', workoutId: 'w2', exerciseId: 'bench', setIndex: 1, reps: 8, atMs: 2000));

      expect((await store.setsFor('w1')).length, 1);
      expect((await store.setsFor('w2')).length, 1);
    });

    test('删除后不再出现在查询结果里', () async {
      await store.saveSet(_set(id: 's1', workoutId: 'w1', exerciseId: 'bench', setIndex: 1, reps: 8, atMs: 1000));
      await store.deleteSet('s1');

      expect(await store.setsFor('w1'), isEmpty);
    });

    test('同一组重复保存是幂等的（不产生重复行）', () async {
      final r = _set(id: 's1', workoutId: 'w1', exerciseId: 'bench', setIndex: 1, reps: 8, atMs: 1000);
      await store.saveSet(r);
      await store.saveSet(r);

      expect((await store.setsFor('w1')).length, 1);
    });

    test('训练能往返保存与读取，且组记录一并带回', () async {
      await store.saveWorkout(Workout(id: 'w1', startedAtMs: 1000));
      await store.saveSet(_set(id: 's1', workoutId: 'w1', exerciseId: 'bench', setIndex: 1, reps: 8, atMs: 1000));
      await store.saveSet(_set(id: 's2', workoutId: 'w1', exerciseId: 'bench', setIndex: 2, reps: 8, atMs: 2000));

      final loaded = await store.loadWorkout('w1');
      expect(loaded, isNotNull);
      expect(loaded!.totalSets, 2);
      expect(loaded.sets.length, 2);
      expect(loaded.totalVolume, 60 * 8 * 2);
    });

    test('读取不存在的训练返回 null', () async {
      expect(await store.loadWorkout('nope'), isNull);
    });

    test('没有历史时 lastSessionFor 返回 null', () async {
      expect(await store.lastSessionFor('bench'), isNull);
    });

    test('lastSessionFor 返回上次训练的全部正式组', () async {
      await store.saveSet(_set(id: 's1', workoutId: 'w1', exerciseId: 'bench', setIndex: 1, reps: 10, atMs: 1000));
      await store.saveSet(_set(id: 's2', workoutId: 'w1', exerciseId: 'bench', setIndex: 2, reps: 9, atMs: 2000));
      await store.saveSet(_set(id: 's3', workoutId: 'w1', exerciseId: 'bench', setIndex: 3, reps: 8, atMs: 3000, weightKg: 62.5));

      final last = await store.lastSessionFor('bench');
      expect(last, isNotNull);
      expect(last!.reps, <int>[10, 9, 8]);
      expect(last.completedSets, 3);
      expect(last.minReps, 8);
      expect(last.weightKg, 62.5, reason: '取该次训练最后一组的重量');
    });

    test('lastSessionFor 只取最近一次训练，不混入更早的', () async {
      // 更早的一次训练
      await store.saveSet(_set(id: 'old1', workoutId: 'w1', exerciseId: 'bench', setIndex: 1, reps: 5, atMs: 1000));
      await store.saveSet(_set(id: 'old2', workoutId: 'w1', exerciseId: 'bench', setIndex: 2, reps: 5, atMs: 1500));
      // 最近的一次训练
      await store.saveSet(_set(id: 'new1', workoutId: 'w2', exerciseId: 'bench', setIndex: 1, reps: 10, atMs: 5000));
      await store.saveSet(_set(id: 'new2', workoutId: 'w2', exerciseId: 'bench', setIndex: 2, reps: 10, atMs: 6000));
      await store.saveSet(_set(id: 'new3', workoutId: 'w2', exerciseId: 'bench', setIndex: 3, reps: 10, atMs: 7000));

      final last = await store.lastSessionFor('bench');
      expect(last!.reps, <int>[10, 10, 10], reason: '不能把 w1 的 2 组算进来');
      expect(last.completedSets, 3);
    });

    test('lastSessionFor 排除热身组', () async {
      await store.saveSet(_set(id: 'wu', workoutId: 'w1', exerciseId: 'bench', setIndex: 1, reps: 15, atMs: 1000, setType: SetType.warmup));
      await store.saveSet(_set(id: 's1', workoutId: 'w1', exerciseId: 'bench', setIndex: 2, reps: 8, atMs: 2000));
      await store.saveSet(_set(id: 's2', workoutId: 'w1', exerciseId: 'bench', setIndex: 3, reps: 8, atMs: 3000));

      final last = await store.lastSessionFor('bench');
      expect(last!.completedSets, 2, reason: '热身组不能计入引擎的判定');
      expect(last.reps, <int>[8, 8]);
    });

    test('lastSessionFor 不统计已删除的组', () async {
      await store.saveSet(_set(id: 's1', workoutId: 'w1', exerciseId: 'bench', setIndex: 1, reps: 8, atMs: 1000));
      await store.saveSet(_set(id: 's2', workoutId: 'w1', exerciseId: 'bench', setIndex: 2, reps: 8, atMs: 2000));
      await store.deleteSet('s2');

      final last = await store.lastSessionFor('bench');
      expect(last!.completedSets, 1);
    });

    test('不同动作的历史互不干扰', () async {
      await store.saveSet(_set(id: 'b1', workoutId: 'w1', exerciseId: 'bench', setIndex: 1, reps: 8, atMs: 1000));
      await store.saveSet(_set(id: 'r1', workoutId: 'w1', exerciseId: 'row', setIndex: 1, reps: 12, atMs: 2000));

      expect((await store.lastSessionFor('bench'))!.reps, <int>[8]);
      expect((await store.lastSessionFor('row'))!.reps, <int>[12]);
    });

    test('daysAgo 是真实天数 —— 引擎的"21 天回归保护"全靠它', () async {
      // 两个实现曾经都漏了这个字段，daysAgo 恒为默认值 0，
      // 于是 progression.dart 的 kStaleDays 分支永远进不去 ——
      // 写在 PRODUCT.md §6 的一条承诺从来没生效过。
      final int now = DateTime.now().millisecondsSinceEpoch;
      await store.saveSet(_set(
        id: 's1',
        workoutId: 'w1',
        exerciseId: 'bench',
        setIndex: 1,
        reps: 8,
        atMs: now - 5 * Duration.millisecondsPerDay,
      ));

      final last = await store.lastSessionFor('bench');
      expect(last!.daysAgo, 5,
          reason: '恒为 0 时"三周没练该减量"永远不会触发');
    });

    test('daysAgo 跨过 21 天门槛（回归保护的另一半）', () async {
      final int now = DateTime.now().millisecondsSinceEpoch;
      await store.saveSet(_set(
        id: 's1',
        workoutId: 'w1',
        exerciseId: 'bench',
        setIndex: 1,
        reps: 8,
        atMs: now - 22 * Duration.millisecondsPerDay,
      ));

      expect((await store.lastSessionFor('bench'))!.daysAgo, greaterThanOrEqualTo(21));
    });

    test('excludeWorkoutId 排除本次训练 —— 同一次里再进同一动作时不把刚才的组当"上次"',
        () async {
      await store.saveSet(_set(id: 'p1', workoutId: 'w_prev', exerciseId: 'bench', setIndex: 1, reps: 8, atMs: 1000, weightKg: 60));
      await store.saveSet(_set(id: 'n1', workoutId: 'w_now', exerciseId: 'bench', setIndex: 1, reps: 12, atMs: 2000, weightKg: 80));

      final withNow = await store.lastSessionFor('bench');
      expect(withNow!.weightKg, 80, reason: '不排除时最近一次就是本次');

      final excluded = await store.lastSessionFor('bench', excludeWorkoutId: 'w_now');
      expect(excluded!.weightKg, 60, reason: '排除本次后回落到上一次训练');
      expect(excluded.reps, <int>[8]);
    });

    test('excludeWorkoutId 把唯一一次训练排除掉时返回 null', () async {
      await store.saveSet(_set(id: 'n1', workoutId: 'w_now', exerciseId: 'bench', setIndex: 1, reps: 12, atMs: 2000));

      expect(await store.lastSessionFor('bench', excludeWorkoutId: 'w_now'), isNull);
    });

    test('allSets：返回全部正式组，跨训练、按时间升序', () async {
      await store.saveSet(_set(id: 'b', workoutId: 'w2', exerciseId: 'row', setIndex: 1, reps: 10, atMs: 5000));
      await store.saveSet(_set(id: 'a', workoutId: 'w1', exerciseId: 'bench', setIndex: 1, reps: 8, atMs: 1000));
      await store.saveSet(_set(id: 'c', workoutId: 'w1', exerciseId: 'bench', setIndex: 2, reps: 8, atMs: 3000));
      await store.saveSet(_set(id: 'wu', workoutId: 'w1', exerciseId: 'bench', setIndex: 9, reps: 15, atMs: 500, setType: SetType.warmup));

      final sets = await store.allSets();
      expect(sets.map((SetRecord s) => s.id).toList(), <String>['a', 'c', 'b'],
          reason: '按时间升序，且不含热身组');
    });

    test('allSets：软删除的不算', () async {
      await store.saveSet(_set(id: 'a', workoutId: 'w1', exerciseId: 'bench', setIndex: 1, reps: 8, atMs: 1000));
      await store.saveSet(_set(id: 'b', workoutId: 'w1', exerciseId: 'bench', setIndex: 2, reps: 8, atMs: 2000));
      await store.deleteSet('a');

      expect((await store.allSets()).map((SetRecord s) => s.id).toList(), <String>['b']);
    });

    test('setsForExercise：返回该动作跨训练的全部正式组', () async {
      await store.saveSet(_set(id: 'a1', workoutId: 'w1', exerciseId: 'bench', setIndex: 1, reps: 8, atMs: 1000));
      await store.saveSet(_set(id: 'a2', workoutId: 'w2', exerciseId: 'bench', setIndex: 1, reps: 10, atMs: 5000));
      await store.saveSet(_set(id: 'b1', workoutId: 'w1', exerciseId: 'row', setIndex: 1, reps: 12, atMs: 2000));
      await store.saveSet(_set(id: 'wu', workoutId: 'w1', exerciseId: 'bench', setIndex: 9, reps: 15, atMs: 500, setType: SetType.warmup));

      final sets = await store.setsForExercise('bench');
      expect(sets.map((SetRecord s) => s.id).toList(), <String>['a1', 'a2'],
          reason: '只含正式组，按时间升序，且不含别的动作');
    });

    test('setsForExercise：excludeWorkoutId 能排除本次训练', () async {
      await store.saveSet(_set(id: 'old', workoutId: 'w_old', exerciseId: 'bench', setIndex: 1, reps: 8, atMs: 1000, weightKg: 60));
      await store.saveSet(_set(id: 'now', workoutId: 'w_now', exerciseId: 'bench', setIndex: 1, reps: 8, atMs: 5000, weightKg: 65));

      final history = await store.setsForExercise('bench', excludeWorkoutId: 'w_now');
      expect(history.map((SetRecord s) => s.id).toList(), <String>['old'],
          reason: '判定破纪录必须排除本次，否则每次都是纪录');
    });

    test('setsForExercise：没练过时是空', () async {
      expect(await store.setsForExercise('nope'), isEmpty);
    });

    test('recentExerciseIds：没练过时是空', () async {
      expect(await store.recentExerciseIds(), isEmpty);
    });

    test('recentExerciseIds：只取最近一次训练的动作，去重且保持顺序', () async {
      // 更早的一次训练：不该出现
      await store.saveSet(_set(id: 'o1', workoutId: 'w1', exerciseId: 'squat', setIndex: 1, reps: 8, atMs: 1000));
      // 最近的一次：bench → row → bench（去重后应是 bench, row）
      await store.saveSet(_set(id: 'n1', workoutId: 'w2', exerciseId: 'bench', setIndex: 1, reps: 8, atMs: 5000));
      await store.saveSet(_set(id: 'n2', workoutId: 'w2', exerciseId: 'row', setIndex: 1, reps: 10, atMs: 6000));
      await store.saveSet(_set(id: 'n3', workoutId: 'w2', exerciseId: 'bench', setIndex: 2, reps: 8, atMs: 7000));

      expect(await store.recentExerciseIds(), <String>['bench', 'row']);
    });

    test('recentExerciseIds：热身组不算（没练正式组就是没练）', () async {
      await store.saveSet(_set(id: 'wu', workoutId: 'w1', exerciseId: 'bench', setIndex: 1, reps: 15, atMs: 1000, setType: SetType.warmup));

      expect(await store.recentExerciseIds(), isEmpty);
    });

    test('动作置顶：默认空，写入后按**给定顺序**读回（不是按插入时间）', () async {
      expect(await store.pinnedExerciseIds(), isEmpty);

      // 有意按"看起来不自然"的顺序写：这样"按 position 排"与"按插入时间排"
      // 会给出不同答案，测试才真的在守顺序这件事。
      await store.setPinnedExerciseIds(<String>['bench', 'squat', 'row']);

      expect(await store.pinnedExerciseIds(), <String>['bench', 'squat', 'row']);
    });

    test('动作置顶：再写一次是**整体替换**（不是追加）', () async {
      await store.setPinnedExerciseIds(<String>['bench', 'squat']);
      await store.setPinnedExerciseIds(<String>['row']);

      expect(await store.pinnedExerciseIds(), <String>['row']);
    });

    test('动作置顶：可以清空', () async {
      await store.setPinnedExerciseIds(<String>['bench']);
      await store.setPinnedExerciseIds(const <String>[]);

      expect(await store.pinnedExerciseIds(), isEmpty);
    });

    test('自重动作的重量为 null 也能往返', () async {
      await store.saveSet(_set(id: 's1', workoutId: 'w1', exerciseId: 'pullup', setIndex: 1, reps: 8, atMs: 1000, weightKg: null));

      final sets = await store.setsFor('w1');
      expect(sets.single.weightKg, isNull);
      expect(sets.single.volume, 0, reason: '自重动作容量记 0');
    });

    test('RPE 能往返：默认 null，有值时原样存回、不被别的字段挤掉', () async {
      await store.saveSet(_set(
          id: 'noRpe', workoutId: 'w1', exerciseId: 'bench', setIndex: 1, reps: 8, atMs: 1000));
      await store.saveSet(_set(
          id: 'withRpe', workoutId: 'w1', exerciseId: 'bench', setIndex: 2, reps: 8, atMs: 2000, rpe: 8));

      final List<SetRecord> sets = await store.setsFor('w1');
      expect(sets.firstWhere((SetRecord s) => s.id == 'noRpe').rpe, isNull,
          reason: '没记就是 null，不能变成 0');
      expect(sets.firstWhere((SetRecord s) => s.id == 'withRpe').rpe, 8);
    });

    test('删除全部数据：训练、组记录、各类历史查询全部清空', () async {
      await store.saveSet(_set(id: 's1', workoutId: 'w1', exerciseId: 'bench', setIndex: 1, reps: 8, atMs: 1000));
      await store.saveWorkout(Workout(id: 'w1', startedAtMs: 1000));
      await store.setPinnedExerciseIds(<String>['bench']);
      expect(await store.setsFor('w1'), hasLength(1), reason: '前置：确实有数据');

      await store.deleteAllUserData();

      expect(await store.setsFor('w1'), isEmpty);
      expect(await store.allSets(), isEmpty, reason: '「我」页的统计与 CSV 导出来自这里');
      expect(await store.loadWorkout('w1'), isNull);
      expect(await store.lastSessionFor('bench'), isNull, reason: '不能让"上次 xx kg"还活在库里');
      expect(await store.recentExerciseIds(), isEmpty);
      // 置顶也是用户数据 —— 「删除全部数据」之后他的收藏必须真的没了
      expect(await store.pinnedExerciseIds(), isEmpty);
    });

    // ─── 回收站（2026-10-04）────────────────────────────────────────────
    // 软删除从第一天起就存在，但**从来没有任何地方读它** —— 长按撤销之后那组永远没了。
    // 这一组两个实现都要过（契约测试的意义就在这儿）。
    test('★ 回收站：撤销掉的组进回收站，恢复之后回到训练里', () async {
      await store.saveSet(_set(id: 's1', workoutId: 'w1', exerciseId: 'bench', setIndex: 1, reps: 8, atMs: 1000));
      await store.saveSet(_set(id: 's2', workoutId: 'w1', exerciseId: 'bench', setIndex: 2, reps: 8, atMs: 2000));

      await store.deleteSet('s1');
      expect(await store.setsFor('w1'), hasLength(1), reason: '删除后不在这条训练里');
      expect(await store.allSets(), hasLength(1), reason: '统计里也不该有它');

      final List<DeletedSet> bin = await store.deletedSets();
      expect(bin, hasLength(1), reason: '它应当躺在回收站里 —— 这正是以前缺的那一环');
      expect(bin.single.set.id, 's1');
      expect(bin.single.set.exerciseId, 'bench', reason: '回收站要能说清"哪一组"');
      expect(bin.single.deletedAtMs, greaterThan(0));

      await store.restoreSet('s1');
      expect(await store.deletedSets(), isEmpty, reason: '恢复之后就不该还在回收站');
      expect((await store.setsFor('w1')).map((SetRecord s) => s.id).toSet(),
          <String>{'s1', 's2'});
      expect(await store.allSets(), hasLength(2), reason: '容量/PR 会重新把它算上');
    });

    test('回收站按"最近删的在前"，且恢复不存在的 id 不炸', () async {
      await store.saveSet(_set(id: 'a', workoutId: 'w1', exerciseId: 'bench', setIndex: 1, reps: 8, atMs: 1000));
      await store.saveSet(_set(id: 'b', workoutId: 'w1', exerciseId: 'bench', setIndex: 2, reps: 8, atMs: 2000));
      await store.deleteSet('a');
      await store.deleteSet('b');

      final List<DeletedSet> bin = await store.deletedSets();
      // ⚠️ **不断言顺序**：两次删除落在同一毫秒里时，谁先谁后是未定义的
      // （两个实现都用 `now()` 当删除时刻，而毫秒级并列在真实使用里也不是事 ——
      // 人手删两次至少隔几秒）。第一版写了 `['b','a']`，两个实现一起红。
      // 真正要守的是"两条都在回收站里"。
      expect(bin.map((DeletedSet d) => d.set.id).toSet(), <String>{'a', 'b'});

      await store.restoreSet('根本没这个 id'); // 不该抛
      expect(await store.deletedSets(), hasLength(2));
    });

    test('★ 批量整理：一次删多组（Ultra 权益 8）', () async {
      await store.saveSet(_set(id: 'a', workoutId: 'w1', exerciseId: 'bench', setIndex: 1, reps: 8, atMs: 1000));
      await store.saveSet(_set(id: 'b', workoutId: 'w1', exerciseId: 'bench', setIndex: 2, reps: 8, atMs: 2000));
      await store.saveSet(_set(id: 'c', workoutId: 'w1', exerciseId: 'bench', setIndex: 3, reps: 8, atMs: 3000));

      final int n = await store.deleteSets(<String>['a', 'b']);
      expect(n, 2, reason: '要如实回条数 —— 界面那句"已移到回收站 2 组"就是它');
      expect((await store.allSets()).map((SetRecord r) => r.id).toList(), <String>['c']);
      expect((await store.deletedSets()).map((DeletedSet d) => d.set.id).toSet(),
          <String>{'a', 'b'});
      // 空列表是安全的空操作（界面在没选任何组时也会调到它）
      expect(await store.deleteSets(<String>[]), 0);
      // 重复删同一批：第二次什么也不删（幂等，不抛）
      expect(await store.deleteSets(<String>['a', 'b']), 0);
    });

    test('★ 批量整理：一次改多组的动作，且**不碰回收站里的那些**', () async {
      await store.saveSet(_set(id: 'a', workoutId: 'w1', exerciseId: 'bench', setIndex: 1, reps: 8, atMs: 1000));
      await store.saveSet(_set(id: 'b', workoutId: 'w1', exerciseId: 'bench', setIndex: 2, reps: 8, atMs: 2000));
      await store.saveSet(_set(id: 'c', workoutId: 'w1', exerciseId: 'bench', setIndex: 3, reps: 8, atMs: 3000));
      await store.deleteSet('c');

      final int n = await store.reassignSets(<String>['a', 'b', 'c'], 'squat');
      expect(n, 2, reason: '回收站里的 c 不该被改 —— 用户改的是"现在看得到的这批"');
      final List<SetRecord> live = await store.allSets();
      expect(live.every((SetRecord r) => r.exerciseId == 'squat'), isTrue);
      expect(live.map((SetRecord r) => r.id).toSet(), <String>{'a', 'b'});
      // 改成同一个动作是幂等的
      expect(await store.reassignSets(<String>['a'], 'squat'), 1);
    });

    test('删除全部数据之后仍能继续正常记录（不是把库弄坏了）', () async {
      await store.saveSet(_set(id: 'old', workoutId: 'w1', exerciseId: 'bench', setIndex: 1, reps: 8, atMs: 1000));

      await store.deleteAllUserData();
      await store.saveSet(_set(id: 'new', workoutId: 'w2', exerciseId: 'squat', setIndex: 1, reps: 5, atMs: 9000));

      expect(await store.allSets(), hasLength(1));
      expect((await store.setsFor('w2')).single.id, 'new');
      expect(await store.setsFor('w1'), isEmpty, reason: '删掉的旧训练不会复活');
    });
  });
}

void main() {
  runContractTests(InMemoryHarness());
  runContractTests(DriftHarness());
}
