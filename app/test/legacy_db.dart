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

/// v1～v3 的 `exercise` 表：与当前 `app/lib/data/db.dart` 一致，**只少 `category` 一列**。
///
/// 手写而不是从 db.dart 反推：反推的话将来给 exercise 再加一列，
/// 这个 fixture 会跟着变，于是"老库升级"就再也测不出问题了。
const String legacyExerciseDdl = '''
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
  deleted_at INTEGER NULL
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
  raw.execute(legacyExerciseDdl);
  if (version >= 2) raw.execute(legacyBodyMetricDdl);
  raw.execute('PRAGMA user_version = $version');
}

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
