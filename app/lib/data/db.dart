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

/// 动作库。种子数据见 `seed/exercises.sql`（165 条，已用 sqlite3 实测导入）。
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

@DriftDatabase(tables: <Type>[Exercise, Workout, WorkoutItem, SetRecord])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

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
        },
      );
}

/// App 用的工厂。测试请自行传 `NativeDatabase.memory()`，不要走这里。
AppDatabase openAppDatabase() => AppDatabase(driftDatabase(name: 'lianleme'));
