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
import 'package:lianleme/core/units.dart';
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/analytics_meta_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
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

  test('v5 的库升到 v6：档案里的其它设置原样保留，体重单位落成 kg', () async {
    // v6 给 user_profile 加一列。风险与 v5 同类：不是崩，是**把别人的设置抹掉**。
    late List<String> colsBefore;
    final AppDatabase legacy = AppDatabase(
      NativeDatabase.memory(setup: (dynamic raw) {
        legacySetup(raw, version: 5);
        raw.execute(legacySeedProfileSql);
        colsBefore = raw
            .select("SELECT name FROM pragma_table_info('user_profile')")
            .map<String>((row) => row['name'] as String)
            .toList();
      }),
    );

    final ProfileRepository profile = ProfileRepository(legacy);
    // 打开即触发 onUpgrade
    expect(await profile.unit(), WeightUnit.lb,
        reason: '老库里设的是磅，升级不能把它改回 kg —— 那是"把别人的设置抹掉"');
    expect(await profile.bodyWeightUnit(), BodyWeightUnit.kg,
        reason: '缺省 kg：在"体重单位"这个概念出现之前，体重显示的确实是 kg');
    // ⚠️ 90 秒是一个**真实偏好**，不是"跟随动作"（那个有自己的哨兵值）。
    // 第一版这里写成 isNull，被测试自己纠正了 —— 顺手也说明加列的迁移没有动它。
    expect(await profile.restOverrideSec(), 90, reason: '加列不该动到别的设置');
    expect(colsBefore, isNot(contains('body_weight_unit')),
        reason: 'fixture 不该有这一列，否则这条测试是空转');

    final after = await legacy
        .customSelect("SELECT name FROM pragma_table_info('user_profile')")
        .get();
    expect(after.map((r) => r.read<String>('name')), contains('body_weight_unit'));

    await legacy.close();
  });

  test('v6 的库升到 v7：新表建出来了，而且老数据一条没动', () async {
    // v7 加的是**埋点的记账表**（设备 ID / 会话 / 首启时间）。
    // 它和用户数据无关，但升级路径同样要走通 —— 老库升上来时这张表必须是空的，
    // 首次启动才生成设备 ID（升级用户从这一版起算"首次 app_open"）。
    final AppDatabase legacy = AppDatabase(
      NativeDatabase.memory(setup: (dynamic raw) {
        legacySetup(raw, version: 6);
        raw.execute(legacySeedExerciseSql);
        raw.execute(legacySeedSetSql);
      }),
    );

    final AnalyticsMetaRepository meta = AnalyticsMetaRepository(legacy);

    expect(await meta.isFirstOpen(), isTrue,
        reason: '升级用户没有历史设备 ID —— 从这一版起算首次（诚实的近似）');
    final AnalyticsMetaData row = await meta.ensure();
    expect(row.deviceId, hasLength(32));
    // 老数据不受影响
    final DriftLocalStore store = DriftLocalStore(legacy);
    expect(await store.setsFor('w_legacy'), hasLength(1));

    await legacy.close();
  });

  test('v7 的库升到 v8：exercise 多一列距离处方，老数据原样', () async {
    late List<String> colsBefore;
    final AppDatabase legacy = AppDatabase(
      NativeDatabase.memory(setup: (dynamic raw) {
        legacySetup(raw, version: 7);
        raw.execute(legacySeedExerciseSql);
        colsBefore = raw
            .select("SELECT name FROM pragma_table_info('exercise')")
            .map<String>((row) => row['name'] as String)
            .toList();
      }),
    );

    final ExerciseRepository repo = ExerciseRepository(legacy);
    final ExerciseData? kept = await repo.byId('ex_legacy_bench');
    expect(kept, isNotNull);
    expect(kept!.category, 'strength');
    expect(kept.defaultTargetDistanceM, isNull,
        reason: '老库里没有距离动作，null 是准确的历史');
    expect(colsBefore, isNot(contains('default_target_distance_m')),
        reason: 'fixture 不该有这一列，否则这条测试是空转');

    final after = await legacy
        .customSelect("SELECT name FROM pragma_table_info('exercise')")
        .get();
    expect(after.map((r) => r.read<String>('name')),
        contains('default_target_distance_m'));

    await legacy.close();
  });

  test('v8 的库升到 v9：exercise 多一列动作说明，老数据原样', () async {
    late List<String> colsBefore;
    final AppDatabase legacy = AppDatabase(
      NativeDatabase.memory(setup: (dynamic raw) {
        legacySetup(raw, version: 8);
        raw.execute(legacySeedExerciseSql);
        colsBefore = raw
            .select("SELECT name FROM pragma_table_info('exercise')")
            .map<String>((row) => row['name'] as String)
            .toList();
      }),
    );

    final ExerciseData? kept =
        await ExerciseRepository(legacy).byId('ex_legacy_bench');
    expect(kept, isNotNull);
    expect(kept!.instructions, isNull,
        reason: '老库里没有说明 —— null 是准确的历史，不是"忘了写"');
    expect(colsBefore, isNot(contains('instructions')),
        reason: 'fixture 不该有这一列，否则这条测试是空转');

    final after = await legacy
        .customSelect("SELECT name FROM pragma_table_info('exercise')")
        .get();
    expect(after.map((r) => r.read<String>('name')), contains('instructions'));

    await legacy.close();
  });

  test('v9 的库升到 v10：多出 backup_account 表，而且**是空的**', () async {
    late List<String> tablesBefore;
    final AppDatabase legacy = AppDatabase(
      NativeDatabase.memory(setup: (dynamic raw) {
        legacySetup(raw, version: 9);
        raw.execute(legacySeedExerciseSql);
        tablesBefore = raw
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map<String>((row) => row['name'] as String)
            .toList();
      }),
    );

    // `setup` 是**第一次真正查库时**才跑的（drift 是懒的），所以要先戳一下，
    // 否则 `tablesBefore` 还是一个没初始化的 late 变量。
    await legacy.customSelect('SELECT 1').get();

    // 老库升级上来必须是"没开过云备份"，而不是"开过但恢复码是空的"——
    // 后者会让界面显示成一团糟的已开启状态。所以查的是**没有那一行**。
    expect(tablesBefore, isNot(contains('backup_account')),
        reason: 'fixture 不该有这张表，否则这条测试是空转');
    expect(await ProfileRepository(legacy).cloudAccount(), isNull);

    final after = await legacy
        .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
        .get();
    expect(after.map((r) => r.read<String>('name')), contains('backup_account'));

    // 升级之后这张表要能真的用起来（只是存在还不够）
    await ProfileRepository(legacy)
        .setCloudAccount('ABCDEFGHJKMNPQRSTVWXYZ01234', nowMs: 1000);
    final BackupAccountData? row = await ProfileRepository(legacy).cloudAccount();
    expect(row!.recoveryCode, 'ABCDEFGHJKMNPQRSTVWXYZ01234');
    expect(row.lastUploadAtMs, isNull);

    await legacy.close();
  });

  test('v10 的库升到 v11：多出隐私同意那一列，**老库是 null**（所以要再问一次）',
      () async {
    final AppDatabase legacy = AppDatabase(
      NativeDatabase.memory(setup: (dynamic raw) {
        legacySetup(raw, version: 10);
        raw.execute(legacySeedExerciseSql);
      }),
    );
    await legacy.customSelect('SELECT 1').get(); // 触发迁移

    // 升级后这张表要能真的用起来，而且**默认是"没同意过"**
    expect(await ProfileRepository(legacy).privacyConsentAtMs(), isNull,
        reason: '老用户当年装的那个版本里，应用内根本没有隐私政策可读 —— '
            '所以升级后该重新问一次，而不是替他们默认同意');

    await ProfileRepository(legacy).setPrivacyConsent(nowMs: 1234);
    expect(await ProfileRepository(legacy).privacyConsentAtMs(), 1234);

    final cols = await legacy
        .customSelect("SELECT name FROM pragma_table_info('user_profile')")
        .get();
    expect(cols.map((r) => r.read<String>('name')), contains('privacy_consent_at_ms'));

    await legacy.close();
  });

  test('**其它设置不能把同意状态抹掉**（可空列在 insertOnConflictUpdate 里会被写成 null）',
      () async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    await ProfileRepository(db).setPrivacyConsent(nowMs: 111);
    // 换单位、开关渐进建议、改休息时长 —— 每个 setter 都会整行写入
    await ProfileRepository(db).setUnit(WeightUnit.lb);
    await ProfileRepository(db).setProgressionMode(ProgressionMode.linear);
    await ProfileRepository(db).setRestOverrideSec(120);
    await ProfileRepository(db).setAnalyticsEnabled(false);

    expect(await ProfileRepository(db).privacyConsentAtMs(), 111,
        reason: '少带一次这个字段，用户点一下别的开关就会再被问一遍隐私政策');
    await db.close();
  });

  test('v11 的库升到 v12：多出"拒绝时刻"那一列，老库是 null', () async {
    final AppDatabase legacy = AppDatabase(
      NativeDatabase.memory(setup: (dynamic raw) {
        legacySetup(raw, version: 11);
        raw.execute(legacySeedExerciseSql);
      }),
    );
    await legacy.customSelect('SELECT 1').get();

    expect(await ProfileRepository(legacy).privacyDeclinedAtMs(), isNull);
    await ProfileRepository(legacy).setPrivacyDeclined(nowMs: 777);
    expect(await ProfileRepository(legacy).privacyDeclinedAtMs(), 777);
    // 拒绝**不能**把同意那一列也写脏
    expect(await ProfileRepository(legacy).privacyConsentAtMs(), isNull);

    final cols = await legacy
        .customSelect("SELECT name FROM pragma_table_info('user_profile')")
        .get();
    expect(cols.map((r) => r.read<String>('name')), contains('privacy_declined_at_ms'));

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
