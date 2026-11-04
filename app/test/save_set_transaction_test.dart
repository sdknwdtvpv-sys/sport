/// 练了么 · `saveSet()` 的原子性（v1.68.2）
///
/// **为什么单独一个文件**：`saveSet()` 一次"记一组"会派生两行 ——
/// `workout_item`（这次训练里的这个动作）与 `set_record`（这一组本身）。
/// 它们现在在**同一个事务**里写；分开写时第二条失败会留下一个"没有任何组的
/// workout_item"，而那会让「最近做过」与备份里"练过哪些训练"多出一次**并不存在**的训练。
///
/// 这条测试用一个**故意失败**的 SQLite 触发器让第二条写炸掉，然后查库：
/// 事务生效 → `workout_item` 一行都没有；没有事务（旧实现）→ 它会留在库里。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart' hide SetRecord;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/domain/models.dart';

void main() {
  late AppDatabase db;
  late DriftLocalStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLocalStore(db);
  });

  tearDown(() => db.close());

  Future<int> countOf(String table) async {
    final row = await db
        .customSelect('SELECT count(*) AS n FROM "$table"')
        .getSingle();
    return row.read<int>('n');
  }

  SetRecord set() => SetRecord(
        id: 's_atomic_1',
        workoutId: 'w_atomic',
        exerciseId: 'ex_bb_bench_press',
        setIndex: 1,
        reps: 8,
        weightKg: 60,
        completedAtMs: 1000,
      );

  test('★ 第二条写失败时，第一条（workout_item）也一起回滚，不留半条记录', () async {
    // 先建库（第一次查询触发 onCreate）。
    expect(await countOf('workout_item'), 0);

    // 让 set_record 的插入**必然失败**：这是"第二刀"失败的替身。
    await db.customStatement(
      'CREATE TRIGGER fail_set_insert BEFORE INSERT ON set_record '
      "BEGIN SELECT RAISE(ABORT, 'boom'); END",
    );

    await expectLater(store.saveSet(set()), throwsA(anything),
        reason: '触发器让第二刀失败，异常必须原样抛出去（不能静默吞掉）');

    expect(await countOf('workout_item'), 0,
        reason: '旧实现（两条写不在同一事务）会在这里留下 1 行孤儿 workout_item');
    expect(await countOf('set_record'), 0);
  });

  test('去掉失败原因之后，同一次保存两行都能落地（事务没有把连接弄坏）', () async {
    await db.customStatement('DROP TRIGGER IF EXISTS fail_set_insert');
    await db.customStatement(
      'CREATE TRIGGER fail_set_insert BEFORE INSERT ON set_record '
      "BEGIN SELECT RAISE(ABORT, 'boom'); END",
    );
    await expectLater(store.saveSet(set()), throwsA(anything));
    await db.customStatement('DROP TRIGGER fail_set_insert');

    await store.saveSet(set());
    expect(await countOf('workout_item'), 1);
    expect(await countOf('set_record'), 1);
    expect((await store.allSets()).single.id, 's_atomic_1');
  });
}
