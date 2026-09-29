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
                                                -- 怎么记这个动作，见下方「track_type 词表」
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

### 备份文件格式

用户数据的**完整可导回**表示（JSON），由 `app/lib/features/profile/backup.dart` 实现。
与「导出全部记录」那份 CSV **不是一回事** —— 后者是给人看的报表，丢了 id/热身/RPE/秒级时间，
重量还跟显示单位走，导回来是另一批数据。

```json
{
  "app": "lianleme", "format": 1, "exported_at": 1790612345678, "unit": "kg",
  "exercise_names": { "ex_bb_bench_press": "杠铃卧推" },
  "workouts": [
    { "id": "w_...", "started_at": 0, "ended_at": 0,
      "sets": [ { "id": "s_...", "exercise_id": "ex_bb_bench_press", "set_index": 1,
                  "reps": 8, "weight_kg": 60, "set_type": "normal", "rpe": 8,
                  "completed_at": 0 } ] }
  ]
}
```

约定：

1. **重量一律 kg**。备份是数据交换格式，不跟显示单位走 —— 否则一份 lb 备份
   导进 kg 手机就会静默变成另一组数字。
2. **`format` 是版本号**，加字段时靠它判断兼容；`app` 用来在用户粘错东西时给一句人话。
3. **导入幂等**：id 是确定性的（`s_{workout}_{exercise}_{组序}`），同一份粘两次不会翻倍。
4. **坏行跳过并计数**，不整份作废 —— "42 条进来、2 条没认出来"远好过"一份作废"，
   后者会让用户在数据最危险的时候失去唯一的恢复手段。
5. `exercise_names` **只是给人看的**；关联永远是 id（动作可能被改名或删除）。

### track_type 词表

`track_type` 决定**数字的含义**，不只决定界面怎么显示：

| 值 | 含义 | `reps` 这一列装的是 | 引擎的推进方式 |
|---|---|---|---|
| `weight_reps` | 负重次数（缺省） | 次数 | 双重渐进：先加次数，达标后加重 |
| `reps_only` | 自重次数 | 次数 | 只能加次数（到上限后建议加负重） |
| `time` | **按时长**（平板支撑、侧平板） | **秒** | 按秒推进（+5 秒）；到上限建议加负重 |
| `weight_time` | 负重时长（负重平板支撑） | **秒** | 保持重量加秒数；到时长上限直接加重 |
| `distance_time` | 距离 + 时长（有氧：跑/走/骑行/划船…） | 距离 + 秒 | ⚠️ **只保留词表，引擎还不支持** —— 见下方 |
| `assisted_reps` | 辅助自重（辅助引体/双杠） | 次数 | ⚠️ **方向还没实现对** —— 见下方 |

**两个必须知道的约定：**

1. **`reps` 这一列对 `time` / `weight_time` 装的是秒数**，不是次数。
   这是有意的取舍：另开一列要动 schema（v4 迁移）+ 查询 + CSV + 全部统计，
   而它们真正需要的只是一个"怎么读这个数"的开关。**读这个数之前先看 `track_type`** ——
   判断只走 `isTimeTrack()`（`app/lib/domain/models.dart`）一处，别各处自己写 `== 'time'`。
2. **上游动作库的 `exerciseType` 是同一件事的更细版本**：它的
   `duration` → 我们的 `time`、`bodyweight_reps` → `reps_only`，
   另外还有我们暂时没有的 `distance_duration`（有氧）与 `assisted_bodyweight`（辅助自重）。
   映射与重叠度见 `【9月28日竞品分析】/参考包-健康教练Skill/本地补充/动作库对比.md`。

**两个「词表有了、引擎还没跟上」的值（记在这儿，不藏着）**：

- **`distance_time`**：有氧动作的推进规则（配速 / 距离 / 时长）还没设计。
  种子里目前**一个都没有**，而且 `seed/build.mjs` 会在出现时报错 ——
  与其让引擎按"加次数"去推进跑步，不如让它进不来。要加有氧就得先补引擎。
- **`assisted_reps`**：辅助引体的"重量"是**助力**，所以加重 = 加助力 = 更轻松，
  方向是反的。引擎目前按负重推进，`seed/build.mjs` 会为它发一条**警告**（不阻断）。
  要做对得加一条"减少助力"的推进分支，那是产品决策，不是字段问题。

**次肌群已按上游补全（2026-09-29）**：51 个动作 / 59 个标签，**纯增量**
（只加不减 —— 我们自己更细的标签如 `front_delts` 一律保留）。
补全来自上游 `secondaryMuscles`，且只取我们**已有**的标签。

**次肌群词表还差 3 个值**（`docs/exercise-mapping.md` §5.1，**待决策**）：
上游用 `chest`（作为次肌群，6 个动作）、`upper_back`（5 个）、`grip`（3 个，硬拉与悬垂动作），
我们的 21 值词表里没有。补它们要先决定扩不扩词表 —— 扩了 `labels.dart` 与本文都要跟着改。

**与上游的映射**：`docs/exercise-mapping.md`（由 `tool/map-upstream.mjs` 从
`seed/upstream-workout-guide.json` 生成）。上游 `exerciseType` 的五值与我们的对应关系：

| 上游 `exerciseType` | 我们 | 条数（上游 302 条里） |
|---|---|---|
| `weight_reps` | `weight_reps` | 136 |
| `bodyweight_reps` | `reps_only` | 114 |
| `duration` | `time` | 39 |
| `distance_duration` | `distance_time` | 10 |
| `assisted_bodyweight` | `assisted_reps` | 3 |

**主肌群归类与上游不一致 5 处**（`docs/exercise-mapping.md` §5.2，**待决策**）：
`ex_deadlift` / `ex_sumo_deadlift`（我们 back，上游 Posterior Chain）、`ex_chin_up`（back vs Biceps）、
`ex_weighted_dip`（chest vs Triceps）、`ex_back_extension`（core vs Lower Back）。
**改这些会改变"今天练什么"的部位轮转**（轮转按 `muscle_group` 走），所以不是数据问题而是产品决策。

**已知限制（记在这儿，不藏着）**：`weight_time` 动作的"容量"仍是 `重量 × 秒数`，
量纲上说不通（负重平板 5kg × 30 秒 = 150）。目前只有 1 个这样的动作，
且自重时长动作的容量本来就是 0。要修就得让 `set_record` 知道自己是不是时长动作
（加列或联表），留给真正需要"容量"统计的那次改动。


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

CREATE INDEX idx_routine_item_routine ON routine_item(routine_id, position);

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

-- S8「进步」要按日期倒序取最近若干条
CREATE INDEX idx_body_metric_date ON body_metric(date DESC);

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
