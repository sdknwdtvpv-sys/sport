# 练了么 · 数据模型

## 全局约定

1. **主键 = 客户端生成的 UUID**。离线优先的前提：不依赖服务端分配 ID，不产生冲突。
2. **每张业务表带 `updated_at` + `deleted_at`**。软删除，同步冲突用 last-write-wins 解决。
3. **重量统一存 kg（REAL）**，展示层换算。绝不把单位存进数据库。
4. **`set_record` 近似 append-only**。改一组生成新记录或只更新值，但永不物理删除 —— 训练数据是资产，可回溯高于存储成本。
5. 时间统一存 UTC 毫秒时间戳（INTEGER），展示层按本地时区渲染。

---

## 表结构

### 动作库

```sql
CREATE TABLE exercise (
  id                TEXT PRIMARY KEY,
  name              TEXT NOT NULL,              -- 卧推
  name_en           TEXT,                       -- Barbell Bench Press
  aliases           TEXT,                       -- JSON 数组，搜索用："平板卧推","bp"
  muscle_group      TEXT NOT NULL,              -- chest/back/legs/shoulders/arms/core
  secondary_muscles TEXT,                       -- JSON 数组
  equipment         TEXT NOT NULL,              -- barbell/dumbbell/machine/bodyweight/cable
  track_type        TEXT NOT NULL DEFAULT 'weight_reps',
                                                -- weight_reps/reps_only/time/weight_time（MVP 只用第一种）
  default_rest_sec  INTEGER NOT NULL DEFAULT 90,
  default_weight_kg REAL,                       -- 首次使用时的起始建议
  weight_increment  REAL NOT NULL DEFAULT 2.5,  -- 规则引擎加重步长
  is_builtin        INTEGER NOT NULL DEFAULT 0,
  popularity        INTEGER NOT NULL DEFAULT 0, -- 用于"常用动作"排序
  created_at        INTEGER NOT NULL,
  updated_at        INTEGER NOT NULL,
  deleted_at        INTEGER
);
CREATE INDEX idx_exercise_name     ON exercise(name);
CREATE INDEX idx_exercise_muscle   ON exercise(muscle_group, popularity DESC);
```

### 计划模板

```sql
CREATE TABLE routine (
  id         TEXT PRIMARY KEY,
  user_id    TEXT,
  name       TEXT NOT NULL,          -- 推日 / 胸三头
  note       TEXT,
  source     TEXT NOT NULL,          -- builtin | user | suggested
  is_active  INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);

CREATE TABLE routine_item (
  id                TEXT PRIMARY KEY,
  routine_id        TEXT NOT NULL REFERENCES routine(id),
  exercise_id       TEXT NOT NULL REFERENCES exercise(id),
  position          INTEGER NOT NULL,
  target_sets       INTEGER NOT NULL DEFAULT 3,
  target_reps_low   INTEGER NOT NULL DEFAULT 8,   -- 次数区间，双重渐进需要
  target_reps_high  INTEGER NOT NULL DEFAULT 10,
  target_weight_kg  REAL,                          -- NULL = 交给规则引擎建议
  rest_sec          INTEGER NOT NULL DEFAULT 90,
  updated_at        INTEGER NOT NULL,
  deleted_at        INTEGER
);
```

### 训练记录（核心）

```sql
CREATE TABLE workout (
  id            TEXT PRIMARY KEY,
  user_id       TEXT,
  routine_id    TEXT REFERENCES routine(id),   -- 可空：自由训练
  status        TEXT NOT NULL,                 -- in_progress | finished
  started_at    INTEGER NOT NULL,
  ended_at      INTEGER,
  duration_sec  INTEGER,
  total_volume  REAL,                          -- 冗余字段，结束时物化
  total_sets    INTEGER,
  note          TEXT,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  deleted_at    INTEGER
);
CREATE INDEX idx_workout_user_time ON workout(user_id, started_at DESC);

CREATE TABLE workout_item (
  id          TEXT PRIMARY KEY,
  workout_id  TEXT NOT NULL REFERENCES workout(id),
  exercise_id TEXT NOT NULL REFERENCES exercise(id),
  position    INTEGER NOT NULL,
  note        TEXT,
  updated_at  INTEGER NOT NULL,
  deleted_at  INTEGER
);

CREATE TABLE set_record (
  id              TEXT PRIMARY KEY,
  workout_id      TEXT NOT NULL REFERENCES workout(id),
  workout_item_id TEXT NOT NULL REFERENCES workout_item(id),
  exercise_id     TEXT NOT NULL,          -- 冗余，避免算"上次同动作"时三表 JOIN
  set_index       INTEGER NOT NULL,       -- 第几组，从 1 开始
  set_type        TEXT NOT NULL DEFAULT 'normal',  -- normal | warmup（MVP 只有这两种）
  weight_kg       REAL,
  reps            INTEGER,
  rpe             REAL,                   -- 预留，MVP 不采集
  rest_sec_actual INTEGER,                -- 本组结束到下一组开始的真实间隔
  is_pr           INTEGER NOT NULL DEFAULT 0,
  volume          REAL,                   -- weight_kg * reps，写入时算好
  completed_at    INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL,
  deleted_at      INTEGER
);
CREATE INDEX idx_set_item     ON set_record(workout_item_id, set_index);
CREATE INDEX idx_set_exercise ON set_record(exercise_id, completed_at DESC);  -- 规则引擎的关键索引
```

### 身体数据与 PR

```sql
CREATE TABLE body_metric (
  id           TEXT PRIMARY KEY,
  user_id      TEXT,
  date         TEXT NOT NULL,          -- YYYY-MM-DD，一天一条
  weight_kg    REAL,
  body_fat_pct REAL,
  note         TEXT,
  updated_at   INTEGER NOT NULL,
  deleted_at   INTEGER
);

CREATE TABLE personal_record (
  id            TEXT PRIMARY KEY,
  user_id       TEXT,
  exercise_id   TEXT NOT NULL,
  pr_type       TEXT NOT NULL,         -- est_1rm | max_weight | max_reps | max_volume
  value         REAL NOT NULL,
  set_record_id TEXT REFERENCES set_record(id),
  achieved_at   INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  deleted_at    INTEGER
);
```

### 规则引擎的两张表（决定 AI 楔子能否被验证）

```sql
-- 建议日志：没有这张表，"建议采纳率 ≥ 60%" 就无法度量
CREATE TABLE suggestion_log (
  id                    TEXT PRIMARY KEY,
  workout_id            TEXT NOT NULL,
  exercise_id           TEXT NOT NULL,
  set_index             INTEGER,
  suggested_weight_kg   REAL,
  suggested_reps        INTEGER,
  reason_code           TEXT NOT NULL,   -- linear_progress | hold | add_rep | first_time | deload
  reason_text           TEXT NOT NULL,   -- 直接展示给用户的解释
  accepted              INTEGER,         -- 1 采纳 / 0 手改 / NULL 未响应
  final_weight_kg       REAL,            -- 用户实际记录的
  final_reps            INTEGER,
  created_at            INTEGER NOT NULL
);
CREATE INDEX idx_suggestion_exercise ON suggestion_log(exercise_id, created_at DESC);

-- 用户画像：规则引擎的输入
CREATE TABLE user_profile (
  user_id            TEXT PRIMARY KEY,
  goal               TEXT,      -- hypertrophy | strength | fat_loss
  weekly_frequency   INTEGER,   -- 每周几天，用于部位轮转
  unit_pref          TEXT DEFAULT 'kg',
  default_rest_sec   INTEGER DEFAULT 90,
  progression_mode   TEXT DEFAULT 'double',  -- double | linear | off（用户可关闭建议）
  created_at         INTEGER NOT NULL,
  updated_at         INTEGER NOT NULL
);
```

### 离线同步

```sql
CREATE TABLE sync_outbox (
  id          TEXT PRIMARY KEY,
  entity      TEXT NOT NULL,      -- workout / set_record / ...
  entity_id   TEXT NOT NULL,
  op          TEXT NOT NULL,      -- upsert | delete
  payload     TEXT,               -- JSON 快照
  retry_count INTEGER NOT NULL DEFAULT 0,
  last_error  TEXT,
  created_at  INTEGER NOT NULL
);
```

**同步策略**：写本地 → 入 outbox → 后台按序推送 → 服务端按 `updated_at` 做 last-write-wins。训练过程中**永不阻塞 UI**。冲突面积极小（单人单设备为主），不值得上 CRDT。

---

## 关键查询

```sql
-- 1) 某个动作的"上次表现"（规则引擎的输入，走 idx_set_exercise）
SELECT s.weight_kg, s.reps, s.set_index, s.workout_id
FROM set_record s
WHERE s.exercise_id = ? AND s.set_type = 'normal' AND s.deleted_at IS NULL
ORDER BY s.completed_at DESC
LIMIT 10;

-- 2) 本次训练容量（实时）
SELECT SUM(volume) FROM set_record
WHERE workout_id = ? AND deleted_at IS NULL;

-- 3) 本周容量趋势
SELECT date(completed_at/1000,'unixepoch','localtime') AS d, SUM(volume)
FROM set_record WHERE completed_at >= ?
GROUP BY d ORDER BY d;

-- 4) 建议采纳率（北极星之一）
SELECT AVG(accepted) FROM suggestion_log WHERE accepted IS NOT NULL;
```

---

## 派生指标

- **容量**：`volume = weight_kg × reps`（热身组 set_type='warmup' 不计入）
- **估算 1RM**：Epley 公式 `weight × (1 + reps / 30)`。仅在 `reps ≤ 12` 时计算，否则不显示 —— 高次数下的估算误差会误导用户
- **PR 判定**：每组完成时，比对 `personal_record`，破纪录则打 `is_pr=1` 并写入新记录

---

## 规则引擎（伪代码）

```js
function suggestNext(exercise, lastSession, plan, profile) {
  if (profile.progression_mode === 'off') return null;
  if (!lastSession) {
    return {
      weight: exercise.default_weight_kg ?? plan.target_weight_kg,
      reps: plan.target_reps_low,
      code: 'first_time',
      text: '第一次练这个动作，先从这个重量开始',
    };
  }

  const allSetsDone = lastSession.completedSets >= plan.target_sets;
  const minReps     = Math.min(...lastSession.reps);

  // 1) 全部达标 → 加重
  if (allSetsDone && minReps >= plan.target_reps_high) {
    const delta = exercise.weight_increment;
    return {
      weight: lastSession.weight + delta, reps: plan.target_reps_low,
      code: 'linear_progress',
      text: `上次 ${lastSession.completedSets} 组全部达标，线性加重 +${delta}kg`,
    };
  }

  // 2) 掉组 → 保持（不加重，也不降重，先看是不是偶发）
  if (minReps < plan.target_reps_low) {
    return {
      weight: lastSession.weight, reps: plan.target_reps_low,
      code: 'hold',
      text: `上次有组掉到 ${minReps} 次，先保持重量`,
    };
  }

  // 3) 中间态 → 加次数不加重量（双重渐进）
  return {
    weight: lastSession.weight, reps: minReps + 1,
    code: 'add_rep',
    text: `上次差一点达标，先把每组次数补到 ${minReps + 1}`,
  };
}
```

**设计红线**：
- 每个建议**必须**带 `reason_text`，且能在 UI 上一行放下。解释不了的建议不许出现。
- 用户连续手改 3 次同一动作 → 该动作后续默认沿用用户的手改值，不再建议。
- 建议**永远可一键采纳、随时手改**，不做不可撤销的自动化。
