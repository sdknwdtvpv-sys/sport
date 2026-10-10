/// 练了么 · 「删除全部数据」到底删了什么（逐表核对）
///
/// **为什么单独一组**：这是**删除权**（PIPL 第 47 条 / 各商店合规要求）最容易被咬的地方，
/// 而它的失败方式很隐蔽 —— **新加一张表却忘了接进 `deleteAllUserData`**：
/// 用户点了"删除全部数据"，那张表里的东西还在。界面上一切正常，没有任何测试会红。
/// 2026-09-30 就是这么发现身体数据那张表的。所以这里做两件事：
///   1. **逐表**核对：删除后除了动作库（产品资产，刻意保留）之外，一张表都不许有行；
///   2. **表清单守门**：库里出现新表就要来改这里的清单 —— 逼人想清楚"这张删不删"。
///
/// 另外钉住"删除之后回落到什么默认值"。代码注释里曾写着「回落到…「帮助改进产品」**开**」，
/// 而 v1.28.0 起那个默认值是**关** —— 注释说谎比没有注释更坏，所以这里用断言把事实钉死。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/outbox.dart';
import 'package:lianleme/backup/login_session.dart';
import 'package:lianleme/data/auth_session_repository.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/data/analytics_meta_repository.dart';
import 'package:lianleme/data/body_metric_repository.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/day_plan_repository.dart';
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/streak_protection_repository.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/data/reminder_repository.dart';
import 'package:lianleme/features/profile/reminder.dart';
import 'package:lianleme/data/routine_repository.dart';
import 'package:lianleme/domain/models.dart';
// RoutineEntry 是 planner 那边的形状（今天的安排存的就是它）
import 'package:lianleme/features/today/today_planner.dart' show RoutineEntry;

/// 逐表行数（键是数据库里的真表名）
Future<Map<String, int>> rowCounts(AppDatabase db) async {
  final Map<String, int> out = <String, int>{};
  for (final t in db.allTables) {
    out[t.actualTableName] = (await db.select(t).get()).length;
  }
  return out;
}

void main() {
  late AppDatabase db;
  late DriftLocalStore store;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLocalStore(db);
    await ExerciseRepository(db).importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
  });

  tearDown(() => db.close());

  /// 往**每一张**用户数据表里塞一行
  Future<void> seedEveryUserTable() async {
    // 直接用真表名与真列名插（companion 的必填项会随生成代码变，SQL 不会）：
    // 这里只是要"这张表里有行"，不是在建业务对象。
    await db.customStatement(
      "INSERT INTO workout (id, status, started_at, ended_at, created_at, updated_at) "
      "VALUES ('w1', 'finished', 900, 1100, 900, 1100)",
    );
    await db.customStatement(
      "INSERT INTO workout_item (id, workout_id, exercise_id, position, updated_at) "
      "VALUES ('wi1', 'w1', 'ex_bb_bench_press', 0, 1000)",
    );
    await store.saveSet(SetRecord(
      id: 's1',
      workoutId: 'w1',
      exerciseId: 'ex_bb_bench_press',
      setIndex: 1,
      reps: 8,
      completedAtMs: 1000,
      weightKg: 60,
      setType: SetType.normal,
    ));
    final ProfileRepository profile = ProfileRepository(db);
    await profile.setUnit(WeightUnit.lb, nowMs: 1000);
    await profile.setAnalyticsEnabled(true, nowMs: 1000);
    await profile.setRestOverrideSec(120, nowMs: 1000);
    await profile.setPrivacyConsent(nowMs: 1000);
    await profile.setCloudAccount('ABCDE-FGHJK-LMNPQ-RSTUV-WXYZ2-34567', nowMs: 1000);
    await AnalyticsOutboxStore(db).enqueue(
      name: 'set_logged',
      props: <String, Object?>{'x': 1},
      priority: 0,
      nowMs: 1000,
    );
    await AnalyticsMetaRepository(db).ensure();
    await BodyMetricRepository(db).save(date: '2026-09-28', weightKg: 72.5, nowMs: 1000);
    final RoutineData r = await RoutineRepository(db).create('推日', nowMs: 1000);
    await RoutineRepository(db).addItem(r.id, 'ex_bb_bench_press', nowMs: 1000);
    // v16：动作置顶（用户钉住的那些动作）。走公开 API，不写裸 SQL。
    await store.setPinnedExerciseIds(<String>['ex_bb_bench_press']);
    // v17：训练提醒的设置（开关 + 时间）
    await ReminderRepository(db).save(
      const ReminderSettings(enabled: true, minutesOfDay: 20 * 60),
      nowMs: 1000,
    );
    // v21：连续保护（补签）—— 走公开 API，不写裸 SQL。
    // ⚠️ 它是这一批唯一新增的表，也是**唯一一件"关于历史"的用户声明**：
    // 留着它，"删除全部数据"之后连续天数就还是被补签撑着的（自相矛盾的界面）。
    await StreakProtectionRepository(db).protect('2026-10-05', nowMs: 1000);
    // v27：今天的安排（10.9 清单第 6 条）—— 走公开 API，不写裸 SQL。
    await DayPlanRepository(db).save(
      dayPlanKey(DateTime(2026, 10, 9)),
      <RoutineEntry>[
        RoutineEntry(
          exerciseId: 'ex_bb_bench_press',
          plan: const PlanTarget(targetSets: 3, targetRepsLow: 8, targetRepsHigh: 12),
        ),
      ],
      nowMs: 1000,
    );
    // v22：登录会话（账号体系）。这一行**非有不可** —— 表清单守门只强制你"表态"，
    // 真正证明"删掉了"的是下面逐表核行数那一条；而一张从没被塞过行的表
    // 是 0 → 0，删没删都看不出来。
    await AuthSessionRepository(db).write(StoredSession(
      token: 'lm1_${'0' * 64}',
      email: 'seed@example.com',
      accountId: 'a' * 64,
      accountKey: Uint8List.fromList(List<int>.generate(16, (int i) => i)),
      saltHex: 'b' * 64,
      kdf: '{"alg":"argon2id"}',
      loginAtMs: 1000,
    ));
  }

  test('逐表核对：删除后除动作库外，一张表都不许有行', () async {
    await seedEveryUserTable();
    final Map<String, int> before = await rowCounts(db);
    expect(before['set_record'], 1, reason: '前置：先确认真的塞进去了');
    expect(before['exercise'], greaterThan(0), reason: '前置：动作库有货');

    await store.deleteAllUserData();

    final Map<String, int> after = await rowCounts(db);
    final List<String> leftovers = <String>[
      for (final MapEntry<String, int> e in after.entries)
        if (e.key != 'exercise' && e.value != 0) '${e.key}=${e.value}',
    ];
    expect(leftovers, isEmpty,
        reason: '这些表在"删除全部数据"之后还有行：${leftovers.join('、')} —— '
            '大概率是新增的表没接进 deleteAllUserData（删除权问题，不是功能瑕疵）');
    expect(after['exercise'], before['exercise'],
        reason: '动作库是产品资产、不是用户数据，必须留下 —— 删了用户就没法记录任何动作');
  });

  test('表清单守门：库里出现了新表就要来改这份清单', () async {
    final Set<String> actual =
        db.allTables.map((t) => t.actualTableName).toSet();
    // 这份清单是"人工表态"：每张表要么在 deleteAllUserData 里被删，要么写明为什么留。
    const Set<String> known = <String>{
      'exercise', // 产品资产，刻意保留（注意：这些表名是**单数**）
      'workout',
      'workout_item',
      'set_record',
      'user_profile',
      'analytics_outbox',
      'analytics_meta',
      'body_metric',
      'routine',
      'routine_item',
      'backup_account',
    'auth_session',
      // v15（2026-10-01）：未结束的训练会话。**删** —— 它也是用户状态，
      // 留着会让"删光之后首页还问你要不要继续上次的训练"。
      'active_session_row',
      // v16（2026-10-04）：动作置顶。**删** —— 那是用户自己钉的收藏，
      // 属于"删除全部数据"的范围（留着会让选择器在他删光之后还摆着置顶区）。
      'pinned_exercise',
      // v17（2026-10-04）：训练提醒的设置。**删** —— 那是用户自己选的开关与时间，
      // "删除全部数据"之后不该还留着一条他看不见的提醒。
      'reminder_setting',
      // v19（2026-10-05）：站内消息（通知中心）。**删** —— 那些消息全是他自己的训练
      // 攒出来的（徽章解锁/提醒/备份结果）；留着会让"删光之后"通知中心还摆着旧消息。
      'app_notification',
      // v21（2026-10-06）：连续保护（补签）。**删** —— 那是用户自己做的决定
      // （"这一天不能让链断"），属于他的数据；留着会让删光之后连续天数还是被补签撑着的。
      'streak_protection',
      // v27（2026-10-09）：今天的安排（用户拖动/替换/删除过的那一份）。**删** ——
      // 那是用户自己的编辑结果；留着会让"删光之后"首页还摆着今天练哪几个。
      'day_plan_item',
      'day_plan_day',
      // v30（2026-10-10）：会员权益与计费流水。**删** —— 它们记的是"这个人是谁、
      // 买过什么"，与 `backup_account` / `auth_session` 同类。
      // ⚠️ 代价（有意接受，也已写在 `drift_local_store.deleteAllUserData` 那里）：
      // 付费用户删完数据会暂时变成免费用户，直到点一次「恢复购买」。
      'entitlement',
      'billing_event',
    };
    expect(actual, equals(known),
        reason: '库里的表和这份清单对不上 —— 新增/改名一张表就要来改这里，'
            '并同时确认 deleteAllUserData 里对它的处理（删掉？还是写明为什么留）');
  });

  test('删除之后回落到哪些默认值（注释曾经写错过，这里用断言钉死）', () async {
    await seedEveryUserTable();
    await store.deleteAllUserData();

    final ProfileRepository profile = ProfileRepository(db);
    // 2026-10-07（v23）起匿名统计默认**开** —— 删完数据后回落到的就是这个默认值
    // （v1.28.0～v1.58.0 之间它是"关"，那是审计 A 的后半段；这一版是用户知情拍板翻回来的）
    expect(await profile.analyticsEnabled(), isTrue,
        reason: '删完全部数据后开关要回落到默认值，而现在的默认值是"开"');
    expect(await profile.unit(), WeightUnit.kg, reason: '单位回落默认 kg');
    expect(await profile.progressionMode(), ProgressionMode.doubleProgression,
        reason: '渐进建议回落默认');
    expect(await profile.restOverrideSec(), isNull, reason: '休息时长回落"跟随动作"');
    expect(await profile.cloudAccount(), isNull,
        reason: '本机的恢复码也要删（那是打开云端数据的钥匙）');
    expect(await profile.privacyConsentAtMs(), isNull,
        reason: '连"同意过"的记录也一起删 —— 下次冷启动会重新征求意见'
            '（这是有意的：用户说的是"删除全部数据"）');
  });

  test('删除是硬删除，不是打标记', () async {
    await seedEveryUserTable();
    await store.deleteAllUserData();

    final int rows =
        (await db.customSelect('SELECT COUNT(*) AS c FROM set_record').getSingle())
            .read<int>('c');
    expect(rows, 0);

    // `workout_items` 表**确实有** `deleted_at` 这类软删列（历史设计），
    // 所以这里要专门确认：删除全部数据之后它是**没有行**，而不是被打了标记。
    final int items =
        (await db.customSelect('SELECT COUNT(*) AS c FROM workout_item').getSingle())
            .read<int>('c');
    expect(items, 0, reason: '软删列不是借口 —— 用户要的是真的删掉');
  });

  test('重复删除是幂等的（空库上再删一次不能炸）', () async {
    await seedEveryUserTable();
    await store.deleteAllUserData();
    await store.deleteAllUserData();

    final Map<String, int> after = await rowCounts(db);
    expect(after['set_record'], 0);
    expect(after['user_profile'], 0);
    expect(after['backup_account'], 0);
  });

  test('本机凭据删掉了；**服务端**那份的删除是 UI 层的事（这里不越界断言）', () async {
    await seedEveryUserTable();
    expect(await ProfileRepository(db).cloudAccount(), isNotNull, reason: '前置');

    await store.deleteAllUserData();

    // ⚠️ 这里**不能**断言"云端也删了" —— 数据层根本不该去联网。
    // 那件事在 features/profile/profile_screen.dart 的 _deleteAll()：
    // 先问「同时删除云端备份并注销」，先删云端、失败则整个中止。
    // 它的覆盖在 profile_test.dart 与集成测试里，不在这里重复。
    expect(await ProfileRepository(db).cloudAccount(), isNull);
  });
}
