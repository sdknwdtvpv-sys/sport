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
  TextColumn get trackType => text().withDefault(const Constant('weight_reps'))();
  IntColumn get defaultRestSec => integer().withDefault(const Constant(90))();
  RealColumn get defaultWeightKg => real().nullable()();
  RealColumn get weightIncrement => real().withDefault(const Constant(2.5))();
  BoolColumn get isBuiltin => boolean().withDefault(const Constant(false))();
  IntColumn get popularity => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

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

  /// kg | lb。显示单位；**存储与引擎始终是 kg**（见 core/units.dart）
  TextColumn get unitPref => text().withDefault(const Constant('kg'))();
  IntColumn get defaultRestSec => integer().withDefault(const Constant(90))();

  /// double | linear | off
  TextColumn get progressionMode => text().withDefault(const Constant('double'))();

  /// 「帮助改进产品」开关。关掉后除崩溃外一律不上报（见 analytics-sdk.md §10）。
  BoolColumn get analyticsEnabled => boolean().withDefault(const Constant(true))();
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

@DriftDatabase(tables: <Type>[
  Exercise,
  Workout,
  WorkoutItem,
  SetRecord,
  UserProfile,
  AnalyticsOutbox,
  BodyMetric,
  Routine,
  RoutineItem,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// v2：新增 `body_metric`（S12 身体数据）。
  /// v3：新增 `routine` / `routine_item`（S11 计划模板）。
  ///
  /// **老版本的库已经装在用户手机上了**，所以每次加表都必须有 onUpgrade ——
  /// 只加表不改 onUpgrade 的话，老用户的 App 一开就崩。
  @override
  int get schemaVersion => 3;

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
        },
      );
}

/// App 用的工厂。测试请自行传 `NativeDatabase.memory()`，不要走这里。
AppDatabase openAppDatabase() => AppDatabase(driftDatabase(name: 'lianleme'));
