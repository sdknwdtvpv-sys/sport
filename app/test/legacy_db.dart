/// 练了么 · 迁移测试用的「老版本的库」
///
/// **这个文件存在的理由**：迁移测试要验的是"**旧形状**的库能不能被新代码打开"。
/// 所以旧库必须用**当年那份 DDL** 建出来，不能拿当前 schema 建完再改 ——
/// 那样建出来的库已经含着新列，`ALTER TABLE ADD COLUMN` 会以
/// "duplicate column name" 失败，看起来像迁移坏了，其实是 fixture 假了。
///
/// **踩过的坑（2026-09-29）**：原来这两个 fixture 是
/// `NativeDatabase.memory(setup: (raw) => raw.execute('PRAGMA user_version = N'))`
/// —— 一个**空库**顶着老版本号。在"迁移只加表"的年代够用（老库缺表本来就不真实，
/// 但没人碰过）。v4 第一次**给已有表加列**（`exercise.category`），
/// 它当场报 `no such table: exercise`：真实的老库里这张表当然存在。
/// 所以 fixture 换成了"手工写的老版 exercise 表"。
///
/// 什么时候要改这个文件：**只有当你想改历史**（比如声称 v1 就有 category）时才改。
/// 加新版本时应该新增一个 `legacyV5Schema` 之类的常量，而不是改老的。
library;

/// `exercise` 表的**按版本形状**：v1–v3 没有 `category`（v4 加的），
/// v1–v7 没有 `default_target_distance_m`（v8 加的），v1–v8 没有 `instructions`（v9 加的）。
///
/// ⚠️ **必须是"那个版本当时的样子"**，否则测的就不是迁移：
/// 这一条踩过 —— 最初这里只有一份 v1 形状的 DDL，于是造"v7 的库"时
/// `exercise` 里根本没有 `category` 列（v7 的迁移不会再加它，因为 `from < 4` 为假），
/// drift 读那一行时直接 `Null check operator used on a null value`。
/// 那不是迁移坏了，是 fixture 假了。所以这里按版本拼：
/// **加新版本时给对应分支添列，而不是改老分支**。
String legacyExerciseDdl(int version) => '''
CREATE TABLE IF NOT EXISTS exercise (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  name_en TEXT NULL,
  aliases TEXT NOT NULL DEFAULT '[]',
  muscle_group TEXT NOT NULL,
  secondary_muscles TEXT NOT NULL DEFAULT '[]',
  equipment TEXT NOT NULL,
  track_type TEXT NOT NULL DEFAULT 'weight_reps',
  default_rest_sec INTEGER NOT NULL DEFAULT 90,
  default_weight_kg REAL NULL,
  weight_increment REAL NOT NULL DEFAULT 2.5,
  is_builtin INTEGER NOT NULL DEFAULT 0 CHECK (is_builtin IN (0, 1)),
  popularity INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER NULL${version >= 4 ? ",\n  category TEXT NOT NULL DEFAULT 'strength'" : ''}${version >= 8 ? ",\n  default_target_distance_m REAL NULL" : ''}${version >= 9 ? ",\n  instructions TEXT NULL" : ''}
)
''';

/// v1 的 `workout`（训练行）。
const String legacyWorkoutDdl = '''
CREATE TABLE IF NOT EXISTS workout (
  id TEXT NOT NULL PRIMARY KEY,
  user_id TEXT NULL,
  routine_id TEXT NULL,
  status TEXT NOT NULL DEFAULT 'in_progress',
  started_at INTEGER NOT NULL,
  ended_at INTEGER NULL,
  duration_sec INTEGER NULL,
  total_volume REAL NULL,
  total_sets INTEGER NULL,
  note TEXT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER NULL
)
''';

/// v1 的 `workout_item`。
const String legacyWorkoutItemDdl = '''
CREATE TABLE IF NOT EXISTS workout_item (
  id TEXT NOT NULL PRIMARY KEY,
  workout_id TEXT NOT NULL,
  exercise_id TEXT NOT NULL,
  position INTEGER NOT NULL DEFAULT 0,
  note TEXT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER NULL
)
''';

/// v1～v4 的 `set_record`：与当前 db.dart 一致，**只少 `distance_m` 一列**。
///
/// v5 第一次给这张表加列，所以 fixture 必须有它 —— 而且必须有**当年那份 DDL**
/// （没有 distance_m），否则那条迁移要么报 no such table，要么"列已存在"。
const String legacySetRecordDdl = '''
CREATE TABLE IF NOT EXISTS set_record (
  id TEXT NOT NULL PRIMARY KEY,
  workout_id TEXT NOT NULL,
  workout_item_id TEXT NOT NULL,
  exercise_id TEXT NOT NULL,
  set_index INTEGER NOT NULL,
  set_type TEXT NOT NULL DEFAULT 'normal',
  weight_kg REAL NULL,
  reps INTEGER NULL,
  rpe REAL NULL,
  rest_sec_actual INTEGER NULL,
  is_pr INTEGER NOT NULL DEFAULT 0 CHECK (is_pr IN (0, 1)),
  volume REAL NULL,
  completed_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER NULL
)
''';

/// v1～v5 的 `user_profile`：与当前 db.dart 一致，**只少 `body_weight_unit` 一列**。
///
/// v6 第一次给这张表加列，所以 fixture 必须有它。
const String legacyUserProfileDdl = '''
CREATE TABLE IF NOT EXISTS user_profile (
  user_id TEXT NOT NULL PRIMARY KEY,
  goal TEXT NULL,
  weekly_frequency INTEGER NULL,
  unit_pref TEXT NOT NULL DEFAULT 'kg',
  default_rest_sec INTEGER NOT NULL DEFAULT 90,
  progression_mode TEXT NOT NULL DEFAULT 'double',
  analytics_enabled INTEGER NOT NULL DEFAULT 1 CHECK (analytics_enabled IN (0, 1)),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''';

/// v2 的 `body_metric`（v2 引入的那张表）。
const String legacyBodyMetricDdl = '''
CREATE TABLE IF NOT EXISTS body_metric (
  id TEXT NOT NULL PRIMARY KEY,
  date TEXT NOT NULL,
  weight_kg REAL NULL,
  body_fat_pct REAL NULL,
  note TEXT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER NULL
)
''';

/// 给 `NativeDatabase.memory` 用的 setup：建出该版本**真实存在**的表 + 写上版本号。
///
/// 只建与迁移相关的表（`exercise` 必须建、其余按版本），
/// 因为这几个测试要验的是"升级不崩"，不是"整份 v1 schema 逐列一致"。
void legacySetup(dynamic raw, {required int version}) {
  raw.execute(legacyExerciseDdl(version));
  raw.execute(legacyWorkoutDdl);
  raw.execute(legacyWorkoutItemDdl);
  raw.execute(legacySetRecordDdl);
  raw.execute(legacyUserProfileDdl);
  if (version >= 2) raw.execute(legacyBodyMetricDdl);
  raw.execute('PRAGMA user_version = $version');
}

/// 往老库里塞一组训练记录 —— 用来验"加列迁移不会碰既有行"。
///
/// 训练数据是资产：v5 给 `set_record` 加 `distance_m` 时，老组记录必须原样还在，
/// 而且距离是 **null**（没记过距离），不是 0（0 表示"真的没动"）。
const String legacySeedSetSql = '''
INSERT INTO set_record
  (id, workout_id, workout_item_id, exercise_id, set_index, set_type, weight_kg,
   reps, rpe, is_pr, volume, completed_at, updated_at, deleted_at)
VALUES
  ('s_legacy_1', 'w_legacy', 'wi_legacy', 'ex_legacy_bench', 1, 'normal', 60.0,
   8, NULL, 0, 480.0, 1000, 1000, NULL)
''';

/// **v1–v6 都没有 `analytics_meta`** —— v7 才建的（埋点的本机身份）。
/// 不用写 DDL：fixture 里不该有它，迁移负责创建。migration_test 里有一条守这个。
///
/// 往老库里塞一行用户档案 —— 用来验 v6 给 user_profile 加列时不动已有设置。
const String legacySeedProfileSql = '''
INSERT INTO user_profile
  (user_id, goal, weekly_frequency, unit_pref, default_rest_sec,
   progression_mode, analytics_enabled, created_at, updated_at)
VALUES
  ('local', 'hypertrophy', 5, 'lb', 90, 'double', 1, 1000, 1000)
''';

/// 往老库里塞一个动作 —— 用来验"升级之后老数据还在，而且被落成 strength"。
const String legacySeedExerciseSql = '''
INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment,
   track_type, default_rest_sec, default_weight_kg, weight_increment,
   is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_legacy_bench', '老库卧推', 'Legacy Bench Press', '[]', 'chest', '[]',
   'barbell', 'weight_reps', 120, 40.0, 2.5, 1, 90, 1000, 1000, NULL)
''';
