/// 练了么 · drift 表结构（SQLite）
///
/// **本文件是 `docs/data-model.md` 的可执行版本。** 字段、索引、`updated_at` / `deleted_at`
/// 都照那份 DDL 一一对应，不自行发挥。表名与列名走 drift 默认的 snake_case 转换，
/// 结果与文档完全一致（`WorkoutItem` → `workout_item`，`nameEn` → `name_en`）。
///
/// 范围说明：本阶段只落地**跑通持久化所必需**的 4 张表。
/// 其余 7 张（routine / routine_item / body_metric / personal_record /
/// suggestion_log / user_profile / 以及 sync_outbox）等各自功能落地时再加——
/// 一次定义全部表只会增加我无法验证的表面积。
library;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'db.g.dart';

/// 动作库。种子数据见 `seed/exercises.sql`（318 条，已用 sqlite3 实测导入）。
class Exercise extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get nameEn => text().nullable()();
  TextColumn get aliases => text().withDefault(const Constant('[]'))();
  TextColumn get muscleGroup => text()();
  TextColumn get secondaryMuscles => text().withDefault(const Constant('[]'))();
  TextColumn get equipment => text()();

  /// strength | warmup | stretch —— **决定它会不会进「今天练什么」的推荐**。
  ///
  /// 热身与拉伸是动作库的正常成员（能被搜到、能被选、能被记成一组），
  /// 但它们不该当"今天练哪个部位"的答案。2026-09-29 之前它们根本不在库里 ——
  /// 当时的做法是整类排除，那就连"练完拉一下"都记不了。类别比排除诚实。
  ///
  /// 缺省 'strength'：老库（v3）升上来时没有任何一行是热身/拉伸，缺省值就是正确答案。
  TextColumn get category => text().withDefault(const Constant('strength'))();

  TextColumn get trackType => text().withDefault(const Constant('weight_reps'))();
  IntColumn get defaultRestSec => integer().withDefault(const Constant(90))();
  RealColumn get defaultWeightKg => real().nullable()();

  /// **动作说明**（一两句话说清"怎么做 + 最常见的一个错"）。null = 还没写。
  ///
  /// 2026-09-29 加。动作库有 351 个动作而 App 里只有**名字** —— 对"垫脚高脚杯深蹲"这种
  /// 名字，新人看不出是在干什么。这一列是内容债的**可见形式**：有就是有，没有就是 null，
  /// `tool/content-report.mjs` 会把覆盖率与待写队列打出来。
  ///
  /// 只写"要点"，不写长文：选择器的一行放得下（≤ 80 字），也不至于让人在健身房读论文。
  TextColumn get instructions => text().nullable()();

  /// **距离处方：每组多少米**（`distance_time` 动作专用，其余恒 null）。
  ///
  /// 2026-09-29 加。之前距离类动作"能记但不被推荐"，因为处方只有"多少次 / 多少秒"
  /// 两种形态，开不出"走 20 米"。有了这一列，「今天练什么」才敢推荐农夫行走，
  /// 训练屏也才有默认距离可用（首次练时拿它当起点）。
  ///
  /// 为什么写在种子里而不是代码里推导：5 公里跑与 20 米农夫行走差两个数量级，
  /// 任何"默认 3000 米"都是编数据。见 `seed/upstream-zh-names.json` 的约定。
  RealColumn get defaultTargetDistanceM => real().nullable()();
  RealColumn get weightIncrement => real().withDefault(const Constant(2.5))();
  BoolColumn get isBuiltin => boolean().withDefault(const Constant(false))();
  IntColumn get popularity => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 埋点的本机身份与会话（`docs/analytics.md` §2.1 的公共字段靠它）。
///
/// **为什么不塞进 `user_profile`**：那张表的每一列都是"用户能看见、能改的设置"，
/// 而且它的写入路径有一堆"必须把其它列原样带回去"的坑（见 ProfileRepository 的注释）。
/// 设备 ID / 会话 ID 是**埋点的记账**，不是用户设置 —— 放一起只会让两边都更容易写错。
///
/// 只有一行（`id = 'local'`）。
class AnalyticsMeta extends Table {
  TextColumn get id => text()();

  /// 设备匿名 ID。随机生成、与任何账号信息无关（`docs/analytics.md` §6）。
  TextColumn get deviceId => text()();

  /// 当前会话 ID。30 分钟无事件即换新会话。
  TextColumn get sessionId => text()();

  /// 上一条事件的时间。判断会话是否过期用它，不是用"App 启动时间"。
  IntColumn get sessionLastAt => integer()();

  /// 首次冷启动的时间。null = 还没开过 → `app_open.is_first_open = true`。
  /// **北极星的分母完全靠它**（"首次 app_open 起 24 小时内"），所以必须落库。
  IntColumn get firstOpenAt => integer().nullable()();

  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 一次训练。
class Workout extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get routineId => text().nullable()();

  /// in_progress | finished
  /// （领域模型 `Workout` 目前还没有 status 字段，见 saveWorkout 的说明）
  TextColumn get status => text().withDefault(const Constant('in_progress'))();
  IntColumn get startedAt => integer()();
  IntColumn get endedAt => integer().nullable()();
  IntColumn get durationSec => integer().nullable()();
  RealColumn get totalVolume => real().nullable()();
  IntColumn get totalSets => integer().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 训练中的一个动作。同一次训练里的多组记录挂在这个 id 下。
class WorkoutItem extends Table {
  TextColumn get id => text()();
  TextColumn get workoutId => text()();
  TextColumn get exerciseId => text()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 一组记录。近似 append-only —— 训练数据是资产，可回溯高于存储成本。
class SetRecord extends Table {
  TextColumn get id => text()();
  TextColumn get workoutId => text()();
  TextColumn get workoutItemId => text()();

  /// 冗余字段：避免算"上次同动作"时做三表 JOIN（引擎的热路径）
  TextColumn get exerciseId => text()();
  IntColumn get setIndex => integer()();

  /// normal | warmup
  TextColumn get setType => text().withDefault(const Constant('normal'))();
  RealColumn get weightKg => real().nullable()();
  IntColumn get reps => integer().nullable()();

  /// **距离（米）**。只有 `track_type = distance_time` 的动作会写它
  /// （跑步机、划船机、跳绳、农夫行走…）；其余动作恒为 null。
  ///
  /// 为什么存米而不是公里：与"重量一律存 kg"同一条规矩 ——
  /// **存储不跟显示单位走**。5.25 公里的浮点表示会随显示单位变（英里 3.26），
  /// 而米是整数友好的最小单位，算配速（秒/公里）时也不用再乘一次 1000。
  RealColumn get distanceM => real().nullable()();

  RealColumn get rpe => real().nullable()();
  IntColumn get restSecActual => integer().nullable()();
  BoolColumn get isPr => boolean().withDefault(const Constant(false))();
  RealColumn get volume => real().nullable()();
  IntColumn get completedAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 用户档案。单行（本地只有一个用户），存设置项。
///
/// 只有 `progression_mode` 现在真的被用到（S10「我」的渐进建议开关）；
/// 其余列照 `docs/data-model.md` 先建好，等对应功能落地时再用。
class UserProfile extends Table {
  TextColumn get userId => text()();
  TextColumn get goal => text().nullable()();
  IntColumn get weeklyFrequency => integer().nullable()();

  /// kg | lb。**训练重量**的显示单位；存储与引擎始终是 kg（见 core/units.dart）
  TextColumn get unitPref => text().withDefault(const Constant('kg'))();

  /// kg | jin。**体重**的显示单位，与训练重量分开。
  ///
  /// 2026-09-29 用户提出："体重钉死在千克和斤之间切换"。
  /// 中国用户称体重说斤（1 斤 = 500 g），而杠铃重量说 kg —— 一个开关管两件事
  /// 就会打架（把训练切到 lb 的人，体重也不该跟着变磅）。存储同样是 kg。
  TextColumn get bodyWeightUnit => text().withDefault(const Constant('kg'))();
  IntColumn get defaultRestSec => integer().withDefault(const Constant(90))();

  /// double | linear | off
  TextColumn get progressionMode => text().withDefault(const Constant('double'))();

  /// 「帮助改进产品」开关。关掉后除崩溃外一律不上报（见 analytics-sdk.md §10）。
  BoolColumn get analyticsEnabled => boolean().withDefault(const Constant(true))();

  /// **首次启动征求隐私政策同意的时刻**。null = 还没同意过（要弹窗）。
  ///
  /// 为什么必须落库：国内商店要求"首次运行时通过弹窗等明显方式提示用户阅读隐私政策
  /// 并征得同意"（小米的隐私合规指引，规则来源国信办秘字〔2019〕191 号）。
  /// 记不住的话每次冷启动都弹 —— 那比不弹更糟。
  ///
  /// 为什么不复用 `analytics_enabled`：那是**使用统计**的开关（可以随时关掉、
  /// 关掉后功能完全不受影响），而这一条是**法律意义上的同意**，两件事不能混。
  IntColumn get privacyConsentAtMs => integer().nullable()();

  /// **用户明确拒绝过**的时刻。null = 没拒绝过（也没同意过）。
  ///
  /// 为什么单独记一列：拒绝之后不能让每次冷启动都再弹一遍（那是骚扰），
  /// 但也不能把"拒绝"写成"同意"（那是撒谎）。两列各自为真，门只看这两个都是 null。
  IntColumn get privacyDeclinedAtMs => integer().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{userId};
}

/// 埋点 outbox。字段照 `docs/analytics-sdk.md` §4 的 DDL。
///
/// 与训练数据分开：埋点丢了不影响用户，训练数据丢一条都不行。
/// 所以两者是两条独立的通道、两套重试策略。
class AnalyticsOutbox extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get payload => text()();
  IntColumn get priority => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 身体数据（S12）。字段照 `docs/data-model.md` 的 `body_metric` DDL。
///
/// **一天一条**：用 `date`（YYYY-MM-DD 字符串）做业务上的唯一键。
/// 刻意**不加数据库唯一索引** —— 软删除之后用户还要能重新录入同一天，
/// 唯一索引会让那次插入直接炸。唯一性在仓库层判断。
class BodyMetric extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get date => text()();

  /// 体重。允许单独记体脂而不记体重，所以这一列可空。
  RealColumn get weightKg => real().nullable()();
  RealColumn get bodyFatPct => real().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 计划模板（S11）。字段照 `docs/data-model.md` 的 `routine` DDL。
///
/// `source` 区分内置 / 用户自建 / 建议生成 —— 现在只写 `user`，
/// 另两种留给后续（内置模板与"把建议存成计划"）。
class Routine extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get note => text().nullable()();
  TextColumn get source => text().withDefault(const Constant('user'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 计划里的一项。**简化版只有动作 + 组数 + 次数区间**（规格 S11 明确说的）。
///
/// `targetWeightKg` 与 `restSec` 照 DDL 建好但**这一版不暴露编辑入口** ——
/// 前者交给规则引擎建议（NULL 就是这个意思），后者沿用动作自带的休息时长。
class RoutineItem extends Table {
  TextColumn get id => text()();
  TextColumn get routineId => text()();
  TextColumn get exerciseId => text()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  IntColumn get targetSets => integer().withDefault(const Constant(3))();
  IntColumn get targetRepsLow => integer().withDefault(const Constant(8))();
  IntColumn get targetRepsHigh => integer().withDefault(const Constant(10))();
  RealColumn get targetWeightKg => real().nullable()();
  IntColumn get restSec => integer().withDefault(const Constant(90))();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 云备份账号（**最多一行**）。
///
/// 恢复码就是账号密钥，所以这张表存的是**打开云端备份的唯一凭据**。
/// 三条设计决定：
///
///   * **和 `user_profile` 一样按 `user_id` 做主键**（现在恒为 `local`）——
///     多用户是以后的事，但先把位置留出来，免得将来再加一次表重建。
///   * **存规范形态（27 位、无连字符）**，不存给人看的那版分组写法。
///     展示时再分组 —— 两处都存就会出现"哪份是真的"这种问题。
///   * **它会被「删除全部数据」一起清掉**（见 `drift_local_store.deleteAllUserData`）。
///     ⚠️ 但那只清了本机 —— **云上那份要另外删**，否则恢复码一丢，用户的数据
///     就永远留在一台他控制不了的服务器上了。
class BackupAccount extends Table {
  TextColumn get userId => text()();
  TextColumn get recoveryCode => text()();

  /// 开启云备份的时间
  IntColumn get enabledAtMs => integer()();

  /// 最后一次成功上传的时间与密文字节数（界面上显示"上次备份于…"）
  IntColumn get lastUploadAtMs => integer().nullable()();
  IntColumn get lastUploadBytes => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{userId};
}

@DriftDatabase(tables: <Type>[
  Exercise,
  Workout,
  WorkoutItem,
  SetRecord,
  UserProfile,
  AnalyticsOutbox,
  AnalyticsMeta,
  BodyMetric,
  Routine,
  RoutineItem,
  BackupAccount,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// v2：新增 `body_metric`（S12 身体数据）。
  /// v3：新增 `routine` / `routine_item`（S11 计划模板）。
  /// v4：`exercise` 新增 `category`（热身/拉伸进库，但不进推荐）—— **第一次给已有表加列**。
  /// v5：`set_record` 新增 `distance_m`（有氧记录：跑步机/划船机/跳绳/农夫行走）。
  /// v6：`user_profile` 新增 `body_weight_unit`（体重的显示单位：千克 / 斤）。
  /// v7：新增 `analytics_meta`（设备 ID / 会话 ID / 首次启动时间 —— 埋点公共字段）。
  /// v8：`exercise` 新增 `default_target_distance_m`（距离处方：每组多少米）。
  /// v9：`exercise` 新增 `instructions`（动作说明：怎么做 + 最常见的错）。
  /// v10：新增 `backup_account`（云备份账号：恢复码 + 上次备份时间）。
  /// v11：`user_profile` 新增 `privacy_consent_at_ms`（首次启动的隐私政策同意时刻）。
  /// v12：`user_profile` 新增 `privacy_declined_at_ms`（**拒绝过**的时刻）。
  ///
  /// **老版本的库已经装在用户手机上了**，所以每次加表/加列都必须有 onUpgrade ——
  /// 只改表定义不改 onUpgrade 的话，老用户的 App 一开就崩。
  @override
  int get schemaVersion => 12;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          // 索引直接照 docs/data-model.md 建，保证与文档一致。
          // drift 没有在表定义里声明索引的稳定 API，用 customStatement 更可控。
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_set_exercise '
            'ON set_record (exercise_id, completed_at DESC)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_set_workout_item '
            'ON set_record (workout_item_id, set_index)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_workout_user_time '
            'ON workout (user_id, started_at DESC)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_body_metric_date '
            'ON body_metric (date DESC)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_routine_item_routine '
            'ON routine_item (routine_id, position)',
          );
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // v1 → v2：只多了一张表，没有改动任何既有列，所以不需要数据搬迁。
          if (from < 2) {
            await m.createTable(bodyMetric);
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_body_metric_date '
              'ON body_metric (date DESC)',
            );
          }
          // v2 → v3：只多两张表，没有改动任何既有列
          if (from < 3) {
            await m.createTable(routine);
            await m.createTable(routineItem);
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_routine_item_routine '
              'ON routine_item (routine_id, position)',
            );
          }
          // v3 → v4：**加列**，不是加表。加列时是 NOT NULL + DEFAULT 'strength'，
          // 所以老库里的 318 个动作全部落成 strength —— 这正是我们要的：
          // 它们本来就都是力量动作。**不需要数据搬迁**（也不需要清表重建）。
          if (from < 4) {
            await m.addColumn(exercise, exercise.category);
          }
          // v4 → v5：又是一次加列，这次是 `set_record`。老库里的组记录全是力量组，
          // 距离一律 null —— 这正是"没记过距离"的诚实表示（不是 0，0 公里是一次真的没动）。
          // ⚠️ 训练数据是资产：加列不能碰任何既有行，也不该重建表。
          if (from < 5) {
            await m.addColumn(setRecord, setRecord.distanceM);
          }
          // v5 → v6：给 `user_profile` 加一列。老库里的档案只有一行（本机用户），
          // 缺省 'kg' 就是正确答案 —— 在"体重单位"这个概念出现之前，
          // 体重显示的确实是 kg（`unit_pref`）。**不需要数据搬迁。**
          if (from < 6) {
            await m.addColumn(userProfile, userProfile.bodyWeightUnit);
          }
          // v6 → v7：加一张新表（只放埋点的记账），没有改动任何既有列。
          // 老库升上来时这张表是空的，首次启动会生成设备 ID 并把首启时间记下 ——
          // 那正是我们要的：升级用户的"首次 app_open"从这一版算起。
          if (from < 7) {
            await m.createTable(analyticsMeta);
          }
          // v7 → v8：给 `exercise` 再加一列（距离处方）。老库里它恒为 null ——
          // 老库本来就没有距离动作（v1.4.0 才补进来），null 是准确的历史。
          if (from < 8) {
            await m.addColumn(exercise, exercise.defaultTargetDistanceM);
          }
          // v8 → v9：动作说明。老库里恒为 null（那时 App 里根本没有这个字段）——
          // 覆盖率工具会把"还没写的"如实算进去，不假装有。
          if (from < 9) {
            await m.addColumn(exercise, exercise.instructions);
          }
          // v9 → v10：加一张新表（只放云备份账号）。老库升上来时这张表是空的 ——
          // 那正是我们要的：**云备份默认关闭**，没有那行就代表"这台机器还没开过"。
          if (from < 10) {
            await m.createTable(backupAccount);
          }
          // v10 → v11：给 `user_profile` 加一列（隐私政策同意时刻）。老库升上来时它是
          // **null = 还没同意过** —— 于是老用户也会看到一次同意弹窗。
          // 这是有意的：他们当年装的那个版本里，应用内根本没有隐私政策可读。
          if (from < 11) {
            await m.addColumn(userProfile, userProfile.privacyConsentAtMs);
          }
          // v11 → v12：再加一列（拒绝时刻）。老库升上来两列都是 null → 会问一次；
          // 用户在这一次里选"不同意"就能进 App 用离线功能，而我们记得他拒绝过。
          if (from < 12) {
            await m.addColumn(userProfile, userProfile.privacyDeclinedAtMs);
          }
        },
      );
}

/// App 用的工厂。测试请自行传 `NativeDatabase.memory()`，不要走这里。
AppDatabase openAppDatabase() => AppDatabase(driftDatabase(name: 'lianleme'));
