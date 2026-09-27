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

    test('自重动作的重量为 null 也能往返', () async {
      await store.saveSet(_set(id: 's1', workoutId: 'w1', exerciseId: 'pullup', setIndex: 1, reps: 8, atMs: 1000, weightKg: null));

      final sets = await store.setsFor('w1');
      expect(sets.single.weightKg, isNull);
      expect(sets.single.volume, 0, reason: '自重动作容量记 0');
    });
  });
}

void main() {
  runContractTests(InMemoryHarness());
  runContractTests(DriftHarness());
}
