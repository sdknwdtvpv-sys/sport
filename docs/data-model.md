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
  equipment         TEXT NOT NULL,              -- barbell/dumbbell/machine/cable/bodyweight/band/kettlebell
  category          TEXT NOT NULL DEFAULT 'strength',
                                                -- strength/warmup/stretch，见下方「category 词表」
  track_type        TEXT NOT NULL DEFAULT 'weight_reps',
                                                -- 怎么记这个动作，见下方「track_type 词表」
  default_rest_sec  INTEGER NOT NULL DEFAULT 90,
  default_weight_kg REAL,                       -- 首次使用时的起始建议
  default_target_distance_m REAL,               -- 距离处方：每组多少米（distance_time 专用）
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

### category 词表

`category` **决定这个动作会不会进「今天练什么」的推荐** —— 不只是个标签：

| 值 | 含义 | 会进「今天练什么」吗 | 记法 |
|---|---|---|---|
| `strength` | 力量动作（缺省，318 个） | 会 | 看 `track_type` |
| `warmup` | 热身（11 个） | **不会** | 按秒（`time`），无重量 |
| `cardio` | 有氧（4 个） | **不会** | 按秒（`time`），无重量 |
| `stretch` | 拉伸（9 个） | **不会** | 按秒（`time`），无重量 |

**有氧只有"按秒记"的那批进得来**（跳绳、椭圆机、爬楼机、战绳）。跑步机 / 划船机 /
动感单车 / 游泳 / 快走 / 徒步这一批在上游是 `distance_duration`（距离 + 时长），
而**引擎只有 `distance_time` 的词表、没有它的规则** —— 把它们按"×N 秒"记等于丢掉距离与配速，
是假数据（`seed/build.mjs` 见到 `distance_time` 直接报错，就是为了不让这种数据进库）。
要有氧记录得先做那个功能：`set_record` 加距离列、输入 UI、配速、
以及引擎对它的推进规则。**同一块石头下面还压着一个力量动作**：农夫行走（`Farmer Carry`）——
它是哑铃负重行走，上游也是 `distance_duration`，同样卡在距离上。

**为什么要有这个字段**（2026-09-29）：热身与拉伸一开始是**被整类排除在动作库外**的，
理由是"混进来会被当成某个部位的动作推荐"—— 理由对，解法错：代价是"练完拉一下"也记不了，
用户想记一次拉伸，得自己新建一个自定义动作。正确的解法是给它们一个类别，
让**推荐规则**按类别过滤（`TodayPlanner` 只从 `strength` 里挑，`planToday` 与 `reroll` 两处都要挡），
而不是让库里没有它们。

三处配套的硬约束（`seed/build.mjs` 会在违反时报错）：

1. `warmup` / `stretch` 必须 `track_type = time` —— 它们没有"次数"这回事
2. `warmup` / `stretch` 的 `weight_increment` 必须是 0、`default_weight_kg` 必须是 null ——
   否则引擎会走"加重"那条路，给「站姿股四头肌拉伸」建议加 2.5 kg
3. `category` 是**必填**，不给缺省 —— 这个字段决定"会不会被推荐"，静默缺省等于埋雷

### track_type 词表

`track_type` 决定**数字的含义**，不只决定界面怎么显示：

| 值 | 含义 | `reps` 这一列装的是 | 引擎的推进方式 |
|---|---|---|---|
| `weight_reps` | 负重次数（缺省） | 次数 | 双重渐进：先加次数，达标后加重 |
| `reps_only` | 自重次数 | 次数 | 只能加次数（到上限后建议加负重） |
| `time` | **按时长**（平板支撑、侧平板） | **秒** | 按秒推进（+5 秒）；到上限建议加负重 |
| `weight_time` | 负重时长（负重平板支撑） | **秒** | 保持重量加秒数；到时长上限直接加重 |
| `distance_time` | 距离 + 时长（有氧：跑/走/骑行/划船…） | 距离 + 秒 | ⚠️ **只保留词表，引擎还不支持** —— 见下方 |
| `assisted_reps` | 辅助自重（辅助引体/双杠） | 次数 | **达标 → 减助力**（方向与负重相反），见下方 |

**两个必须知道的约定：**

1. **`reps` 这一列对 `time` / `weight_time` 装的是秒数**，不是次数。
   这是有意的取舍：另开一列要动 schema（v4 迁移）+ 查询 + CSV + 全部统计，
   而它们真正需要的只是一个"怎么读这个数"的开关。**读这个数之前先看 `track_type`** ——
   判断只走 `isTimeTrack()`（`app/lib/domain/models.dart`）一处，别各处自己写 `== 'time'`。
2. **上游动作库的 `exerciseType` 是同一件事的更细版本**：它的
   `duration` → 我们的 `time`、`bodyweight_reps` → `reps_only`，
   另外还有我们暂时没有的 `distance_duration`（有氧）与 `assisted_bodyweight`（辅助自重）。
   映射与重叠度见 `【9月28日竞品分析】/参考包-健康教练Skill/本地补充/动作库对比.md`。

**`assisted_reps`：方向已实现对**（2026-09-29）。辅助自重的"重量"是**助力**，
越练越强 = 助力越少，所以推进方向与负重**相反**：

| 情况 | 引擎给的下一组 |
|---|---|
| 全部达标（≥ 区间上限） | **减轻**助力一个步长（如 30 → 25 kg） |
| 次数没到顶 | 助力不变，先加次数（双重渐进的前半段，与负重动作同一逻辑） |
| 组数没做满 / 有组掉到下限以下 | **保持**助力（既不减也不加） |
| 助力减到 ≤ 0 | 给 0，提示"可以试试不用辅助了" |

**为什么"掉组时加助力"也是错的**：那会让人更轻松，看起来像"修复"，实际是把进度往回推。
真的做不动就保持，靠次数与组数找回来。
`seed/build.mjs` 现在**强制** `assisted_reps` 的 `weight_increment > 0` ——
助力不记的话引擎会把它当自重动作，"减助力"那条分支永远走不到。
界面也必须说清这个数是什么：大按钮与已完成组念「助力 30 kg × 8」。

**仍然只保留词表、引擎没用上的值**：`distance_time`（有氧的配速/距离/时长推进规则还没设计）。
现在库里有 9 个有氧动作用它（**能记**距离与时长），但引擎对它们**不给推进建议** ——
没有用户的有氧目标（减脂/耐力/间歇），"这次多跑 5%"是假精确。
距离类动作现在**进得了**「今天练什么」了（见下方「距离处方」）——
2026-09-29 补上了 `default_target_distance_m`，处方能表达"3 组 × 20 米"。

**次肌群词表 2026-09-29 扩到 24 值**（原 21 值 + `chest` / `upper_back` / `grip`）：
上游拿它们当次肌群用（`chest` 6 个动作、`upper_back` 5 个、`grip` 3 个 —— 硬拉与悬垂的握力），
我们原来只有 `lats`/`traps` 装不下"上背"这个整体，也没有"握力"和"大肌群出现在次要位置"的位置。
同步改了 `app/lib/core/labels.dart`（中文标签）与 `seed/parts/00-header.json`（词表声明）。

**同样在这一轮，次肌群按上游补全**：51 个动作 / 59 个标签，**纯增量**
（只加不减 —— 我们自己更细的标签如 `front_delts` 一律保留）。
补全来自上游 `secondaryMuscles`，且只取我们**已有**的标签。

**器械词表 2026-09-29 扩到 7 值**（原 5 值 + `band` / `kettlebell`）：
上游有 19 个弹力带动作、2 个壶铃动作。原来的 5 值里没有它们的位置，
硬塞进 `dumbbell` 就是**直接写错数据**（壶铃摆荡的起始重量、步长都和哑铃不是一回事）。
步长：弹力带 0（靠阻力档位，不走配重片）、壶铃 4 kg。

**唯一一个「上游在用、我们决定不扩」的标签**：`cardio`（6 个动作）。
它不是肌肉，是供能系统的标签 —— 我们的次肌群词表是给肌群热力图与恢复建议用的，
塞进去会让热力图多出一块不存在的"肌肉"。结论留档在 `seed/upstream-confirmed.json`。

**与上游的映射**：`docs/exercise-mapping.md`（由 `tool/map-upstream.mjs` 从
`seed/upstream-workout-guide.json` 生成）。上游 `exerciseType` 的五值与我们的对应关系：

| 上游 `exerciseType` | 我们 | 条数（上游 302 条里） |
|---|---|---|
| `weight_reps` | `weight_reps` | 136 |
| `bodyweight_reps` | `reps_only` | 114 |
| `duration` | `time` | 39 |
| `distance_duration` | `distance_time` | 10 |
| `assisted_bodyweight` | `assisted_reps` | 3 |

**主肌群归类 vs 上游（2026-09-29 已全部拍板，`docs/exercise-mapping.md` §5.2 现在是 0 项待决策）**：

改主肌群会改变"今天练什么"的部位轮转（轮转按 `muscle_group` 走），所以是产品决策，逐条给理由：

| 动作 | 原 | 现 | 为什么 |
|---|---|---|---|
| `ex_deadlift` | back | legs | 传统硬拉是**腿**主导（髋伸），背只是等长维持。按 back 归会把它排进"背日" |
| `ex_sumo_deadlift` | back | legs | 同上，相扑硬拉股四头参与更多 |
| `ex_back_extension` | core | back | 山羊挺身练的是**竖脊肌**（下背），不是腹肌 |
| `ex_chin_up` | back | back（不改） | 上游按屈肘归 Biceps；引体是背的动作，肱二头只是协同 |
| `ex_weighted_dip` | chest | chest（不改） | 上游按伸肘归 Triceps；双杠臂屈伸躯干前倾时主推胸 |

**结论留档在 `seed/upstream-confirmed.json`**（`primary_muscle_kept`），
`tool/map-upstream.mjs` 消费它：如果哪天上游改了 `primaryMuscle`、或我们又改了归类，
这一条会重新出现在"待决策"表里 —— 留档的结论不是免检通行证。

### 两个显示单位：训练重量（kg/lb）与体重（kg/斤）

**为什么是两个设置**（2026-09-29，用户提出"体重钉死在千克和斤之间切换"）：

| 场景 | 取值 | 存在哪 |
|---|---|---|
| 训练重量（杠铃、哑铃、容量、PR） | `kg` / `lb` | `user_profile.unit_pref` |
| 体重（S12 录入、S8 卡片） | `kg` / `jin`（斤） | `user_profile.body_weight_unit` |

* 中国用户称体重说**斤**（1 斤 = 500 g），而杠铃重量说 kg —— 一个开关管两件事就会打架：
  把训练切到磅的人，不该连体重也变成磅（"我 188.5 磅"没人这么说）
* 斤**不是**训练重量的选项，lb 也**不是**体重的选项 —— 两个枚举各管一段，
  所以它们在 `core/units.dart` 里是**两个类型**（`WeightUnit` / `BodyWeightUnit`），
  使用点不需要判断"这个单位在这个场景下合不合法"
* **存储仍然是 kg**（与全局同一条规矩），转换是精确的：1 kg = 2 斤，来回倒不掉精度

### 有氧记录（`distance_m` + `distance_time`）

**为什么存米不存公里**：与"重量一律存 kg"同一条规矩 —— **存储不跟显示单位走**。
5.25 公里的浮点表示会随显示单位变（英里 3.26），而米是整数友好的最小单位，
算配速（秒/公里）时也不用再乘一次 1000。显示层负责念「5.00 公里」还是「800 米」。

`distance_m` 的三种取值含义**必须分清**：

| 值 | 含义 |
|---|---|
| `255` | 记了 255 米 |
| `NULL` | 这个动作不记距离（或 v4 及更早的老记录、format 1 的老备份没这个字段） |
| `0` | 记了，而且是"没动" —— 目前**不会写入**（距离为 0 时大按钮置灰） |

配套的三条规则：

1. **`distance_time` 动作的 `reps` 是秒** —— 沿用 `time` 那一列的约定，不另开一列
2. **容量恒为 0**：`weight_kg × reps` 对一次跑步没有量纲意义（20kg × 1800 是两个量纲相乘）。
   有氧要看的是**里程与配速**，见 `WorkoutSummary.distanceLabel / paceLabel`
3. **引擎对 `distance_time` 不给推进建议**（返回 null）。这是产品决策：
   没有用户的有氧目标（减脂/耐力/间歇），"这次多跑 5%"是假精确；
   更要紧的是不能让它掉进"加次数"分支 —— 那会对一次跑步说"每组次数补到 10 次"

### 距离处方（`default_target_distance_m`，2026-09-29 补齐）

**处方现在有三种形态**，由动作的 `track_type` 决定：

| track_type | 处方 |
|---|---|
| `weight_reps` / `reps_only` / `assisted_reps` | 3 组 × 8–10 次 |
| `time` / `weight_time` | 3 组 × 30–45 秒 |
| **`distance_time`** | **N 组 × 每组多少米**（有氧 1 组、力量类 3 组） |

* 米数写在种子里（`exercise.default_target_distance_m`），**不在代码里推导** ——
  5 公里跑与 20 米农夫行走差两个数量级，任何默认值都是编数据；`seed/build.mjs` 会强制它存在
* 秒数（`target_reps_low/high`）留 0：配速因人而异，距离处方只说"多少米"，
  时长由用户在训练屏自己设（有历史时默认沿用上次）
* 于是**力量类的距离动作（农夫行走）能进「今天练什么」了**；
  有氧仍然不进 —— 它靠 `category = cardio` 挡着，与距离处方无关
* 训练屏会显示「目标 3 组 × 20 米」（那一行本来留给引擎建议，但引擎对距离动作不给建议）

> 曾经有个 `ExerciseRepository.search(plannable: true)` 把距离类动作挡在推荐之外
> （因为当时处方开不出距离）。**已删除** —— 留着反而危险：以后有人加距离动作时
> 会照着旧注释把自己挡在推荐外。

### 迁移历史

| 版本 | 改动 | 需要注意的地方 |
|---|---|---|
| v2 | 新增 `body_metric` | 只加表 |
| v3 | 新增 `routine` / `routine_item` | 只加表 |
| v4 | `exercise` 新增 `category`（DEFAULT `'strength'`；词表 strength/warmup/cardio/stretch） | **第一次给已有表加列** —— 老库升级后 318 个动作全部落成 `strength`（它们本来就是力量动作，这正是要的结果），不需要数据搬迁 |
| v8 | `exercise` 新增 `default_target_distance_m` | 距离处方。老库里它恒为 null —— 老库本来就没有距离动作（v1.4.0 才补进来），null 是准确的历史 |
| v6 | `user_profile` 新增 `body_weight_unit` | 第三次加列。老档案里缺省 `'kg'` —— 在"体重单位"这个概念出现之前，体重显示的确实是 kg（`unit_pref`），所以缺省值就是当时的真实行为 |
| v5 | `set_record` 新增 `distance_m` | 第二次加列。老库里的组记录距离恒为 **null**（"没记过距离"），**不是 0**（0 表示"真的没动"）—— 这是加列迁移最容易被搞错的地方，有专门的迁移测试守着 |

迁移测试在 `app/test/migration_test.dart`，fixture 在老库形状的 `app/test/legacy_db.dart`。
⚠️ **fixture 必须用当年的 DDL 手写**：拿当前 schema 建完再改的话，
`ALTER TABLE ADD COLUMN` 会因为列已存在而失败（看起来像迁移坏了），
或者更糟 —— 有人把 fixture 悄悄改成新 schema，测试永远绿。
`migration_test.dart` 里有一条专门守这个。

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
  reps            INTEGER,                -- 次数；time/distance_time 动作装的是**秒**
  distance_m      REAL,                   -- 距离（米）。只有 distance_time 动作写它，见下
  rpe             REAL,                   -- 预留，MVP 不采集
  rest_sec_actual INTEGER,                -- 本组结束到下一组开始的真实间隔
  is_pr           INTEGER NOT NULL DEFAULT 0,
  volume          REAL,                   -- weight_kg * reps；距离动作恒为 0（量纲不同）
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
  unit_pref          TEXT DEFAULT 'kg',       -- 训练重量的显示单位：kg / lb
  body_weight_unit   TEXT DEFAULT 'kg',       -- 体重的显示单位：kg / jin（1 斤 = 500 g）
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
