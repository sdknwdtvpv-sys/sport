/// 练了么 · 数据库迁移（老库升级）
///
/// **为什么值得单独一个文件**：迁移是这个仓库里唯一"错了老用户一开就崩"的东西，
/// 而它跑在**别人手机上已经存在的数据**上 —— 开发机上永远复现不出来。
///
/// v4（2026-09-29）是**第一次给已有表加列**（`exercise.category`）：
/// 前三版都只是加表。所以这一版把 fixture 也换成了真实的老库形状（见 `legacy_db.dart`），
/// 并补上"老数据在升级后还在、而且落成 strength"这条断言 ——
/// 加列迁移真正会出错的地方不是"崩不崩"，是**静默丢数据**。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/domain/models.dart';

import 'legacy_db.dart';

void main() {
  test('v1 的库用当前代码打开：不崩、新表可用、老动作还在且是 strength', () async {
    final AppDatabase legacy = AppDatabase(
      NativeDatabase.memory(setup: (dynamic raw) {
        legacySetup(raw, version: 1);
        raw.execute(legacySeedExerciseSql);
      }),
    );

    // 打开即触发 onUpgrade（v1 → v2 → v3 → v4）
    final ExerciseRepository repo = ExerciseRepository(legacy);

    final ExerciseData? kept = await repo.byId('ex_legacy_bench');
    expect(kept, isNotNull, reason: '升级不能把老数据弄丢');
    expect(kept!.name, '老库卧推');
    expect(kept.category, 'strength',
        reason: '老库里的动作全是力量动作 —— 加列的 DEFAULT 必须是它，'
            '否则「今天练什么」会在老用户手机上一夜之间空掉');

    // 新列真的可用：能按类别查
    expect((await repo.search(category: 'strength', limit: 10)).length, 1);
    expect(await repo.search(category: 'stretch', limit: 10), isEmpty);

    await legacy.close();
  });

  test('v2 的库升上来同样不崩，且 routine 表可用', () async {
    final AppDatabase legacy = AppDatabase(
      NativeDatabase.memory(setup: (dynamic raw) {
        legacySetup(raw, version: 2);
        raw.execute(legacySeedExerciseSql);
      }),
    );

    expect((await ExerciseRepository(legacy).byId('ex_legacy_bench'))!.category,
        'strength');
    // v3 引入的 routine 表由迁移建出来
    await legacy.customStatement(
        'INSERT INTO routine (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)',
        <Object?>['r1', '推日', 1, 1]);
    final rows = await legacy.customSelect('SELECT COUNT(*) c FROM routine').get();
    expect(rows.first.read<int>('c'), 1);

    await legacy.close();
  });

  test('v4 的库升到 v5：老组记录原样还在，距离是 null 而不是 0', () async {
    // 训练数据是资产。v5 给 set_record 加 distance_m 时，最怕的不是崩，
    // 是**老组记录被当成 0 公里**（那是"真的没动"，不是"当年没这个字段"）。
    late List<String> colsBefore;
    final AppDatabase legacy = AppDatabase(
      NativeDatabase.memory(setup: (dynamic raw) {
        legacySetup(raw, version: 4);
        raw.execute(legacySeedSetSql);
        colsBefore = raw
            .select("SELECT name FROM pragma_table_info('set_record')")
            .map<String>((row) => row['name'] as String)
            .toList();
      }),
    );

    final DriftLocalStore store = DriftLocalStore(legacy);
    final List<SetRecord> sets = await store.setsFor('w_legacy');

    expect(sets, hasLength(1), reason: '加列不能弄丢组记录');
    expect(sets.first.reps, 8);
    expect(sets.first.weightKg, 60.0);
    expect(sets.first.volume, 480.0, reason: '物化的容量也不该被动');
    expect(sets.first.distanceM, isNull,
        reason: '老记录没记过距离 —— null（没这个字段）不等于 0（真的没动）');
    expect(colsBefore, isNot(contains('distance_m')),
        reason: 'fixture 不该有 distance_m，否则这条测试是空转');

    final after = await legacy
        .customSelect("SELECT name FROM pragma_table_info('set_record')")
        .get();
    expect(after.map((r) => r.read<String>('name')), contains('distance_m'));

    await legacy.close();
  });

  test('老库里**没有** category 列 —— fixture 本身也要守着', () async {
    // 这一条是防"有人把 fixture 改成当前 schema 的样子"从而让上面两条变成空转。
    // 迁移测试最隐蔽的失败方式就是：fixture 悄悄跟上了新 schema，测试永远绿。
    //
    // ⚠️ 列必须在 **setup 回调里**读：一旦用 AppDatabase 打开，onUpgrade 就跑完了，
    // 那时再查 pragma 看到的是**迁移后**的形状 —— 第一次写这条测试就是这么写错的。
    late List<String> colsBefore;
    final AppDatabase legacy = AppDatabase(
      NativeDatabase.memory(setup: (dynamic raw) {
        legacySetup(raw, version: 1);
        colsBefore = raw
            .select("SELECT name FROM pragma_table_info('exercise')")
            .map<String>((row) => row['name'] as String)
            .toList();
      }),
    );

    // 先让 drift 打开库 —— setup（建老表、抓形状）与 onUpgrade 都在这一步跑。
    // 抓到的 colsBefore 是**迁移前**的形状（它是 setup 里读的），所以这里对顺序无碍。
    await ExerciseRepository(legacy).byId('ex_nobody');

    expect(colsBefore, contains('muscle_group'));
    expect(colsBefore, isNot(contains('category')),
        reason: '老库不该有 category —— 有的话上面两条迁移测试就是空转');
    final after = await legacy
        .customSelect("SELECT name FROM pragma_table_info('exercise')")
        .get();
    expect(after.map((r) => r.read<String>('name')), contains('category'));

    await legacy.close();
  });
}
