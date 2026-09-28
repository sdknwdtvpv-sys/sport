/// 练了么 · S11 计划模板仓库测试
///
/// 「简化版只有动作 + 组数 + 次数区间」是规格明确划的范围，
/// 所以这里也守住：能改的只有这三项。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/routine_repository.dart';
import 'package:lianleme/domain/models.dart';

void main() {
  late AppDatabase db;
  late RoutineRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = RoutineRepository(db);
  });

  tearDown(() => db.close());

  group('计划本身', () {
    test('新建之后出现在列表里', () async {
      final RoutineData r = await repo.create('推日', nowMs: 1000);

      expect(r.name, '推日');
      expect(r.source, 'user', reason: '自建的就是 user');
      expect(r.isActive, isFalse);
      expect((await repo.routines()).map((RoutineData x) => x.id), <String>[r.id]);
    });

    test('名称去掉首尾空白（不然列表里会莫名其妙缩进）', () async {
      final RoutineData r = await repo.create('  推日  ', nowMs: 1000);
      expect(r.name, '推日');
    });

    test('改名', () async {
      final RoutineData r = await repo.create('推日', nowMs: 1000);
      await repo.rename(r.id, '胸三头', nowMs: 2000);

      expect((await repo.byId(r.id))!.name, '胸三头');
    });

    test('删除是软删除：列表里没有了，但行还在', () async {
      final RoutineData r = await repo.create('推日', nowMs: 1000);
      await repo.delete(r.id, nowMs: 2000);

      expect(await repo.routines(), isEmpty);
      expect(await repo.byId(r.id), isNull);
      // 行还在（软删除），所以「恢复」将来是可能的
      expect(await (db.select(db.routine)).get(), hasLength(1));
    });

    test('列表按最近改过排序', () async {
      final RoutineData a = await repo.create('A', nowMs: 1000);
      final RoutineData b = await repo.create('B', nowMs: 2000);
      expect((await repo.routines()).first.id, b.id);

      await repo.rename(a.id, 'A2', nowMs: 3000);
      expect((await repo.routines()).first.id, a.id, reason: 'A 刚改过，排到前面');
    });
  });

  group('计划里的项', () {
    test('按 position 升序', () async {
      final RoutineData r = await repo.create('推日', nowMs: 1000);
      await repo.addItem(r.id, 'ex_bb_bench_press', nowMs: 1001);
      await repo.addItem(r.id, 'ex_bb_incline_bench_press', nowMs: 1002);
      await repo.addItem(r.id, 'ex_cable_fly', nowMs: 1003);

      expect(
        (await repo.items(r.id)).map((RoutineItemData i) => i.exerciseId).toList(),
        <String>['ex_bb_bench_press', 'ex_bb_incline_bench_press', 'ex_cable_fly'],
      );
    });

    test('同一个动作可以加两次（有人练两组不同强度的卧推）', () async {
      final RoutineData r = await repo.create('推日', nowMs: 1000);
      await repo.addItem(r.id, 'ex_bb_bench_press', targetSets: 3, nowMs: 1001);
      await repo.addItem(r.id, 'ex_bb_bench_press', targetSets: 1, nowMs: 1002);

      expect(await repo.items(r.id), hasLength(2));
    });

    test('新的项用默认处方 3 组 8–10 次', () async {
      final RoutineData r = await repo.create('推日', nowMs: 1000);
      final RoutineItemData item =
          await repo.addItem(r.id, 'ex_bb_bench_press', nowMs: 1001);

      expect(item.targetSets, 3);
      expect(item.targetRepsLow, 8);
      expect(item.targetRepsHigh, 10);
      expect(item.targetWeightKg, isNull, reason: 'NULL = 交给规则引擎建议');
    });

    test('改组数 / 次数区间（简化版能改的就这三项）', () async {
      final RoutineData r = await repo.create('推日', nowMs: 1000);
      final RoutineItemData item =
          await repo.addItem(r.id, 'ex_bb_bench_press', nowMs: 1001);

      await repo.updateItem(item.id, targetSets: 5, targetRepsLow: 3,
          targetRepsHigh: 5, nowMs: 2000);

      final RoutineItemData after = (await repo.items(r.id)).single;
      expect(after.targetSets, 5);
      expect(after.targetRepsLow, 3);
      expect(after.targetRepsHigh, 5);
    });

    test('只传一个字段时，别的字段不受影响', () async {
      final RoutineData r = await repo.create('推日', nowMs: 1000);
      final RoutineItemData item = await repo.addItem(r.id, 'ex_bb_bench_press',
          targetSets: 4, targetRepsLow: 6, targetRepsHigh: 8, nowMs: 1001);

      await repo.updateItem(item.id, targetSets: 5, nowMs: 2000);

      final RoutineItemData after = (await repo.items(r.id)).single;
      expect(after.targetSets, 5);
      expect(after.targetRepsLow, 6, reason: '没传的字段不该被重置');
      expect(after.targetRepsHigh, 8);
    });

    test('删项是软删除，且列表里不再出现', () async {
      final RoutineData r = await repo.create('推日', nowMs: 1000);
      final RoutineItemData item =
          await repo.addItem(r.id, 'ex_bb_bench_press', nowMs: 1001);

      await repo.removeItem(item.id, nowMs: 2000);

      expect(await repo.items(r.id), isEmpty);
      expect(await (db.select(db.routineItem)).get(), hasLength(1));
    });

    test('改动项会顺带更新计划的 updatedAt（列表排序要它）', () async {
      final RoutineData r = await repo.create('推日', nowMs: 1000);
      final RoutineData other = await repo.create('拉日', nowMs: 2000);
      expect((await repo.routines()).first.id, other.id);

      final RoutineItemData item =
          await repo.addItem(r.id, 'ex_bb_bench_press', nowMs: 3000);

      expect((await repo.routines()).first.id, r.id,
          reason: '加了动作的计划应该排到前面');
      expect((await repo.byId(r.id))!.updatedAt, 3000);
      expect(item.routineId, r.id);
    });

    test('删掉一个计划不会影响另一个计划的项', () async {
      final RoutineData a = await repo.create('A', nowMs: 1000);
      final RoutineData b = await repo.create('B', nowMs: 1000);
      await repo.addItem(a.id, 'ex_bb_bench_press', nowMs: 1001);
      await repo.addItem(b.id, 'ex_bb_squat', nowMs: 1001);

      await repo.delete(a.id, nowMs: 2000);

      expect(await repo.items(a.id), hasLength(1), reason: '项还在，只是父计划被删了');
      expect((await repo.items(b.id)).single.exerciseId, 'ex_bb_squat');
    });
  });

  group('数据库迁移', () {
    test('用 v3 代码打开一个 v2 的库：不崩，且新表可用', () async {
      // 模拟老库：user_version = 2，且没有 routine / routine_item
      final AppDatabase legacy = AppDatabase(
        NativeDatabase.memory(setup: (dynamic raw) {
          raw.execute('PRAGMA user_version = 2');
        }),
      );

      final RoutineRepository r = RoutineRepository(legacy);
      expect(await r.routines(), isEmpty, reason: '升级后新表存在且为空');

      final RoutineData created = await r.create('推日', nowMs: 1000);
      await r.addItem(created.id, 'ex_bb_bench_press', nowMs: 1001);
      expect(await r.items(created.id), hasLength(1));

      await legacy.close();
    });
  });

  group('合规：计划也是用户数据', () {
    test('「删除全部数据」会一并清掉计划与项', () async {
      final DriftLocalStore store = DriftLocalStore(db);
      final RoutineData r = await repo.create('推日', nowMs: 1000);
      await repo.addItem(r.id, 'ex_bb_bench_press', nowMs: 1001);

      await store.deleteAllUserData();

      expect(await repo.routines(), isEmpty);
      expect(await repo.items(r.id), isEmpty);
    });
  });

  group('交接给引擎的形状', () {
    test('计划项能转成 PlanTarget（组数 + 次数区间）', () async {
      final RoutineData r = await repo.create('推日', nowMs: 1000);
      await repo.addItem(r.id, 'ex_bb_bench_press',
          targetSets: 5, targetRepsLow: 3, targetRepsHigh: 5, nowMs: 1001);

      final RoutineItemData item = (await repo.items(r.id)).single;
      final PlanTarget plan = PlanTarget(
        targetSets: item.targetSets,
        targetRepsLow: item.targetRepsLow,
        targetRepsHigh: item.targetRepsHigh,
      );

      expect(plan.targetSets, 5);
      expect(plan.targetRepsLow, 3);
      expect(plan.targetRepsHigh, 5);
      expect(plan.targetWeightKg, isNull, reason: '重量交给规则引擎');
    });
  });
}
