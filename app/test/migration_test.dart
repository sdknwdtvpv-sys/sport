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
import 'package:lianleme/data/body_metric_repository.dart';
import 'package:lianleme/data/notification_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/data/reminder_repository.dart';
import 'package:lianleme/features/profile/reminder.dart';
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

  test('v12 的库升到 v13：老库里的 analytics_enabled=1 被翻成 0（默认改关）', () async {
    final AppDatabase legacy = AppDatabase(
      NativeDatabase.memory(setup: (dynamic raw) {
        legacySetup(raw, version: 12);
        raw.execute(legacySeedProfileSql); // fixture 里 analytics_enabled = 1
        raw.execute(legacySeedExerciseSql);
      }),
    );
    // 打开即触发 onUpgrade
    final bool after = await ProfileRepository(legacy).analyticsEnabled();
    expect(after, isFalse,
        reason: '列默认值只影响新插入的行；老库里的 true 必须由 v13 的迁移显式翻过来，'
            '否则"默认同意"这个毛病会跟着老用户一直活下去');

    // 迁移不能顺手把别的设置也抹了
    final cols = await legacy
        .customSelect('SELECT unit_pref, progression_mode FROM user_profile')
        .get();
    expect(cols.first.read<String>('unit_pref'), 'lb');
    expect(cols.first.read<String>('progression_mode'), 'double');

    await legacy.close();
  });

  test('v14 的库升到 v16：多出「未结束的会话」与「动作置顶」两张表，而且**是空的**',
      () async {
    // 这两次迁移（v15 / v16）都是"只加表、不动既有列"，所以一条测试一起盖掉：
    // fixture 停在 v14，打开时 onUpgrade 连着跑两步。
    late List<String> tablesBefore;
    final AppDatabase legacy = AppDatabase(
      NativeDatabase.memory(setup: (dynamic raw) {
        legacySetup(raw, version: 14);
        raw.execute(legacySeedExerciseSql);
        tablesBefore = raw
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map<String>((row) => row['name'] as String)
            .toList();
      }),
    );
    // `setup` 是第一次真正查库时才跑的（drift 是懒的）
    await legacy.customSelect('SELECT 1').get();

    for (final String t in <String>['active_session_row', 'pinned_exercise']) {
      expect(tablesBefore, isNot(contains(t)),
          reason: 'fixture 里不该有 $t，否则这条测试是空转（最隐蔽的失败方式）');
    }

    // 两张表都要**真的能用**，不只是"存在"
    final DriftLocalStore store = DriftLocalStore(legacy);
    expect(await store.activeSession(), isNull, reason: '老库升上来不该有"未结束的训练"');
    expect(await store.pinnedExerciseIds(), isEmpty,
        reason: '老库升上来是"一个都没置顶"—— 这个功能出现之前没人置顶过');

    await store.setPinnedExerciseIds(<String>['ex_legacy_bench', 'ex_bb_squat']);
    expect(await store.pinnedExerciseIds(), <String>['ex_legacy_bench', 'ex_bb_squat'],
        reason: '顺序要按 position 存回来（用户看得见的顺序不该由毫秒决定）');

    await legacy.close();
  });

  test('v16 的库升到 v17：多出「训练提醒」那张表，而且是空的（默认关）',
      () async {
    // v17 同样是"只加表、不动既有列"。
    late List<String> tablesBefore;
    final AppDatabase legacy = AppDatabase(
      NativeDatabase.memory(setup: (dynamic raw) {
        legacySetup(raw, version: 16);
        raw.execute(legacySeedExerciseSql);
        tablesBefore = raw
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map<String>((row) => row['name'] as String)
            .toList();
      }),
    );
    await legacy.customSelect('SELECT 1').get();
    expect(tablesBefore, isNot(contains('reminder_setting')),
        reason: 'fixture 里不该有这张表，否则这条测试是空转');

    final ReminderRepository repo = ReminderRepository(legacy);
    // 老库升上来 = "从没设置过" = 默认值（关、20:00）
    final ReminderSettings settings = await repo.load();
    expect(settings.enabled, isFalse, reason: '提醒必须默认关（不主动要通知权限）');
    expect(settings.label, '20:00');

    // 而且这张表要真的能用
    await repo.save(const ReminderSettings(enabled: true, minutesOfDay: 7 * 60 + 30),
        nowMs: 1000);
    final ReminderSettings again = await repo.load();
    expect(again.enabled, isTrue);
    expect(again.label, '07:30');

    await legacy.close();
  });

  test('v19 的库升到 v20：body_metric 多出腰围/肌肉量、user_profile 多出身高，老数据原样',
      () async {
    // v20 是**第二次"动既有表"**（第一次是 v18 给 analytics_meta 加列）。
    // 所以这条测试守的是同一类坑：新库走 `onCreate` 时这两张表**已经带着新列**建好了，
    // 迁移里若无条件 addColumn 就会 `duplicate column name`；反过来 fixture 里是"旧形状"，
    // 不 add 又查不到列。判据必须是"这一列现在有没有"。
    late List<String> colsBefore;
    final AppDatabase legacy = AppDatabase(
      NativeDatabase.memory(setup: (dynamic raw) {
        legacySetup(raw, version: 19);
        raw.execute(legacySeedExerciseSql);
        // ⚠️ `body_metric` 从 v2 起就**没有** `created_at` 这一列（只有 updated_at）。
        // 第一版 fixture 里我凭空写了个 `created_at NOT NULL`，于是这条测试以
        // `NOT NULL constraint failed` 失败 —— 那是**测试自己假了**，不是迁移的问题。
        // 教训：fixture 的 DDL 必须和 `docs/data-model.md` / `db.dart` 逐列对齐。
        raw.execute("INSERT INTO body_metric (id, date, weight_kg, note, updated_at) "
            "VALUES ('bm_old', '2026-10-01', 72.5, '旧记录', 1000)");
        colsBefore = raw
            .select("PRAGMA table_info('body_metric')")
            .map<String>((row) => row['name'] as String)
            .toList();
      }),
    );
    await legacy.customSelect('SELECT 1').get();
    expect(colsBefore, isNot(contains('waist_cm')),
        reason: 'fixture 里不该有新列，否则这条测试是空转');

    final BodyMetricRepository repo = BodyMetricRepository(legacy);
    // 老记录原样还在，新列是 null（"没记过"，不是 0）
    final BodyMetricData old = (await repo.forDate('2026-10-01'))!;
    expect(old.weightKg, 72.5);
    expect(old.note, '旧记录');
    expect(old.waistCm, isNull);
    expect(old.muscleMassKg, isNull);

    // 新列能写能读
    await repo.save(date: '2026-10-02', weightKg: 72, waistCm: 81.5, muscleMassKg: 34);
    final BodyMetricData fresh = (await repo.forDate('2026-10-02'))!;
    expect(fresh.waistCm, 81.5);
    expect(fresh.muscleMassKg, 34);

    // 身高那一列同样加上了，而且老库是 null（"没填过"）
    final ProfileRepository profile = ProfileRepository(legacy);
    expect(await profile.heightCm(), isNull);
    await profile.setHeightCm(176);
    expect(await profile.heightCm(), 176);

    await legacy.close();
  });

  test('v18 的库升到 v19：多出「站内消息」那张表，而且是空的（老库没有任何消息）',
      () async {
    // v19 又是"只加表、不动既有列"（v18 那条是例外）。
    // ⚠️ 但这一版**多了一件事**：去重靠一条 partial unique index，
    // `onCreate` 只在**新库**上跑，老库升级走的是迁移那条路 —— 所以这里要验的是
    // **"索引也建出来了"**，否则去重在老用户身上形同虚设（表建了、索引没建）。
    late List<String> tablesBefore;
    final AppDatabase legacy = AppDatabase(
      NativeDatabase.memory(setup: (dynamic raw) {
        legacySetup(raw, version: 18);
        raw.execute(legacySeedExerciseSql);
        tablesBefore = raw
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map<String>((row) => row['name'] as String)
            .toList();
      }),
    );
    await legacy.customSelect('SELECT 1').get();
    expect(tablesBefore, isNot(contains('app_notification')),
        reason: 'fixture 里不该有这张表，否则这条测试是空转');

    final NotificationRepository repo = NotificationRepository(legacy);
    expect(await repo.list(), isEmpty, reason: '老库升上来 = 一条消息都没有（准确的历史）');

    // 表能用，而且**去重索引真的在**
    expect(
      await repo.add(
          kind: NotificationKind.achievement, title: '解锁「首训」', body: 'x', refKey: 'first_workout'),
      isTrue,
    );
    expect(
      await repo.add(
          kind: NotificationKind.achievement, title: '解锁「首训」', body: 'x', refKey: 'first_workout'),
      isFalse,
      reason: '重复的那条要被唯一索引挡掉 —— 索引没建出来的话这里会返回 true',
    );
    expect((await repo.list()).length, 1);

    await legacy.close();
  });

  test('v17 的库升到 v18：埋点那一行多出「已清过积压」这一位，而且老库是 null', () async {
    // v18 是第一个**动既有表**的迁移（前几版都是加表）。它踩过两个坑，这条测试守第二个：
    // fixture 里 v17 的 `analytics_meta` 必须是**当时的形状**（没有 legacy_purged_at），
    // 否则 addColumn 会因为"列已存在"而红，或者因为"表不存在"而红 —— 两种都是 fixture 假了。
    late List<String> colsBefore;
    final AppDatabase legacy = AppDatabase(
      NativeDatabase.memory(setup: (dynamic raw) {
        legacySetup(raw, version: 17);
        colsBefore = raw
            .select("PRAGMA table_info('analytics_meta')")
            .map<String>((row) => row['name'] as String)
            .toList();
      }),
    );
    await legacy.customSelect('SELECT 1').get();
    expect(colsBefore, contains('device_id'), reason: 'v17 的库当然有这张表');
    expect(colsBefore, isNot(contains('legacy_purged_at')),
        reason: 'fixture 里不该有新列，否则这条测试是空转');

    final AnalyticsMetaRepository meta = AnalyticsMetaRepository(legacy);
    // 老库升上来 = "从没清过" → null（**不是 0**：0 会被读成"1970 年清过"）
    expect(await meta.legacyPurgedAt(), isNull,
        reason: '升级后这一位必须是 null —— 意味着"还没清过"');
    // 而且新代码能用它：记下之后读得回来
    await meta.markLegacyPurged(4242);
    expect(await meta.legacyPurgedAt(), 4242);
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

  test('v22 的库升到 v23：**存量那一行不许被翻转**（只有新装才是默认开）', () async {
    // v23 是**唯一一次"只改列默认值"的迁移**，而且它**有意什么都不做**。
    // 这条测试守的就是那个"什么都不做"——三种机器各验一遍：
    //   ① 存量机器写着 0（当年在同意屏与政策里被告知的是"默认关闭"）→ 升级后**仍然是 0**。
    //      把它静默翻成 1 就是对着旧承诺收集数据 —— 2026-10-07 拍板时专门交代过（
    //      `docs/plan-ux-2026-10-07.md` §三·9）。
    //   ② 存量机器写着 1（用户自己开的）→ 同样一格都不动。
    //   ③ **没有那一行**的新装机器 → 读到的才是新默认值（开）。这一条才是这一版真正要改的东西。
    Future<({int? stored, bool read})> upgrade(int? seed) async {
      final AppDatabase legacy = AppDatabase(
        NativeDatabase.memory(setup: (dynamic raw) {
          legacySetup(raw, version: 22);
          if (seed != null) {
            raw.execute('INSERT INTO user_profile '
                '(user_id, goal, weekly_frequency, unit_pref, default_rest_sec, '
                'progression_mode, analytics_enabled, created_at, updated_at) '
                "VALUES ('local', 'hypertrophy', 5, 'kg', 90, 'double', $seed, 1000, 1000)");
          }
        }),
      );
      // 打开即触发 onUpgrade（v22 → v23）
      final bool read = await ProfileRepository(legacy).analyticsEnabled();
      // 直接读库里那一格 —— 不只信读出来的布尔（"没被搬动"必须有原始证据）
      // 类型由 `.get()` 推出来（`QueryRow` 不必写出来 —— 写出来还得额外 import）
      final rows = await legacy
          .customSelect('SELECT analytics_enabled AS v FROM user_profile')
          .get();
      final int? stored = rows.isEmpty ? null : rows.first.read<int>('v');
      await legacy.close();
      return (stored: stored, read: read);
    }

    final ({int? stored, bool read}) off = await upgrade(0);
    expect(off.stored, 0, reason: '存量机器写着 0 → 升级后一格都不许动');
    expect(off.read, isFalse,
        reason: '读到的是它自己那一行（关），不是新默认值 —— 静默翻转是我们明确不做的事');

    final ({int? stored, bool read}) on = await upgrade(1);
    expect(on.stored, 1, reason: '用户自己开过的，当然也不动');
    expect(on.read, isTrue);

    final ({int? stored, bool read}) fresh = await upgrade(null);
    expect(fresh.stored, isNull, reason: '新装机器在第一次写设置之前根本没有那一行');
    expect(fresh.read, isTrue,
        reason: '没有那一行 → 读到的就是这一版改的默认值（开）');
  });

  test('v24 的库升到 v25：多出"从系统健康库读取"那道同意列，老库是 null（所以要再问一次）',
      () async {
    // 这一列与"身体数据那道单独同意"**不是同一件事**：它同意的是"去读系统健康库里
    // 别人写进去的记录"。老库升上来必须是 null —— 那正是准确的历史：
    // 这个功能出现之前，这台设备没有读过任何健康库里的东西。
    // 于是老用户第一次点「从系统健康同步」时会被单独问一次。
    final AppDatabase legacy = AppDatabase(
      NativeDatabase.memory(setup: (dynamic raw) {
        legacySetup(raw, version: 24);
        raw.execute(legacySeedProfileSql); // 里面 unit_pref = 'lb'
      }),
    );
    expect(await ProfileRepository(legacy).healthConsentAtMs(), isNull,
        reason: '老库没读过健康库，这一列必须是 null，不能替他默认同意');

    await ProfileRepository(legacy).setHealthConsent(nowMs: 777);
    expect(await ProfileRepository(legacy).healthConsentAtMs(), 777);
    expect(await ProfileRepository(legacy).unit(), WeightUnit.lb,
        reason: '迁移与写入都不能把已有的设置抹掉');

    final cols = await legacy
        .customSelect("SELECT name FROM pragma_table_info('user_profile')")
        .get();
    expect(cols.map((r) => r.read<String>('name')),
        contains('health_consent_at_ms'));

    await legacy.close();
  });

  test('老库里**没有** health_consent_at_ms —— fixture 本身也要守着', () async {
    // 防"有人把 fixture 改成当前 schema"，那样上面那条迁移测试就变成空转。
    late List<String> colsBefore;
    final AppDatabase legacy = AppDatabase(
      NativeDatabase.memory(setup: (dynamic raw) {
        legacySetup(raw, version: 24);
        colsBefore = raw
            .select("SELECT name FROM pragma_table_info('user_profile')")
            .map<String>((row) => row['name'] as String)
            .toList();
      }),
    );
    await ProfileRepository(legacy).healthConsentAtMs(); // 打开库（setup 是懒执行的）
    expect(colsBefore, isNot(contains('health_consent_at_ms')),
        reason: 'v24 的老库不该有这一列，否则上面那条迁移测试是空转');
    await legacy.close();
  });

  test('v29 的库升到 v30：多出「会员权益」与「计费流水」两张表，而且**都是空的**', () async {
    // v30（2026-10-10，会员 M1）= 只加表、不动既有列。
    // 断言的重点不是"建出来了"，而是**"空"** —— 空 = 升级不会凭空给谁发权益，
    // 而"没有记录"正是 `resolveUltraAccess(null, now)` 的 `none`（免费用户）。
    // 这一条同时守住反向的错误：假如迁移里手滑写了 INSERT（例如给老用户送一个月），
    // 老用户会一夜之间变成 Ultra —— 那是这个仓库里最不该发生的事。
    final AppDatabase legacy = AppDatabase(
      NativeDatabase.memory(setup: (dynamic raw) {
        legacySetup(raw, version: 29);
      }),
    );
    // 打开即触发 onUpgrade（v29 → v30）
    final List<QueryRow> tables = await legacy
        .customSelect("SELECT name FROM sqlite_master WHERE type='table' "
            "AND name IN ('entitlement', 'billing_event') ORDER BY name")
        .get();
    expect(tables.map((QueryRow r) => r.read<String>('name')).toList(),
        <String>['billing_event', 'entitlement'],
        reason: '两张表都要建出来（少一张，软件包里的仓储一读就崩）');

    final int entitlements =
        (await legacy.customSelect('SELECT count(*) AS n FROM entitlement').getSingle())
            .read<int>('n');
    final int events =
        (await legacy.customSelect('SELECT count(*) AS n FROM billing_event').getSingle())
            .read<int>('n');
    expect(entitlements, 0, reason: '老库升级上来**不许凭空有权益**');
    expect(events, 0);

    await legacy.close();
  });
}
