# 练了么 · 数据模型

## active_session_row（v15，2026-10-01）

**未结束的训练会话**，只会有**一行**（`id = 'local'`）。

| 列 | 说明 |
|---|---|
| `id` | 固定 `local`：本机同时只会有一个未结束的训练 |
| `workout_id` | 这次训练挂在哪个 workout 上（组记录本来就按它落库） |
| `payload` | JSON：`{workout_id, index, rest_ends_at, started_at, source, entries:[{exercise_id, sets, reps_low, reps_high}]}` |
| `updated_at` | 最后写入时间 |

**为什么单独一张表、而不是塞进 `user_profile`**：它是**运行时状态**、每次记一组都会重写；
混进偏好表会让"改设置"和"记一组"互相覆盖（那张表的每个 setter 都要把整行带回去）。

**为什么 `rest_ends_at` 存绝对时间戳**：App 被杀掉 5 分钟之后回来，
休息**应该已经过去 5 分钟**（而不是"重新从 90 秒开始倒数"）——
存绝对时刻，这件事天然成立。

**生命周期**：开始训练时写入 → 训练中按"指纹变化"（第几个动作 / 组数 / 休息结束时刻）更新 →
训练结束（路由返回）或用户"删除全部数据"时清掉。
App 被杀掉时它就留在库里，下次冷启动首页据此显示「继续上次的训练」。

## pinned_exercise（v16，2026-10-04）

| 列 | 类型 | 说明 |
|---|---|---|
| `exercise_id` | TEXT PK | 被置顶的动作 |
| `position` | INTEGER | **用户排的顺序**（0 起）—— 顺序显式存，不靠插入时间 |
| `created_at` | INTEGER | 什么时候钉的（只作记录，不参与排序） |

**为什么单独一张表、而不是 `user_profile` 的一列**：它是一份**有顺序的集合**
（用户钉 3–5 个动作），而 `user_profile` 全是标量偏好 —— 与 `active_session_row`
同一类判断（那张表是因为"运行时状态、每次记一组都重写"）。
**为什么顺序显式存**：这个顺序用户看得见（选择器的「置顶」分区），
不该由两次点击相差几毫秒来决定。
**取消置顶 = 删行**（不是软删）：这张表里没有"历史"可言，留着反而会让
"同一动作出现在置顶区两次"这种状态成为可能。

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
  instructions      TEXT,                       -- 动作说明（怎么做 + 最常见的一个错），null = 还没写
  sub_tags          TEXT DEFAULT '[]',          -- 细分标签（JSON 数组）：上胸/中缝/后束…，见下方那节
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
  "app": "lianleme", "format": 3, "exported_at": 1790612345678, "unit": "kg",
  "exercise_names": { "ex_bb_bench_press": "杠铃卧推" },
  "pinned_exercises": [ "ex_bb_squat", "ex_bb_bench_press" ],
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
5. **`exercise_names` 是给导入用的**（2026-09-30 起）：记录之间的关联永远是 id，
   但导入时若本机缺这个 id 对应的动作，就用映射里那个名字**按原 id 补建**一条自定义动作
   （`isBuiltin: false`，分组/器械记「未分类」）—— 这样"换手机导回来"看到的还是同一批动作名，
   而不是 `ex_xxxxxxxx`。补建是**幂等**的（同一份导两次不会建两个），映射里没有的动作
   照旧退化成显示 id。

6. **`pinned_exercises` 是 v3 加的（2026-10-04），而且"没有这个键" ≠ "空列表"**：
   v1/v2 的备份根本没提置顶 → 解析成 `null` → **导入时不碰本机的置顶**；
   v3 里写了 `[]` 才是"我一个都没置顶"。把这两件事混起来的后果是：
   用户拿一份老备份恢复，收藏被**静默清空**（`backup_scope_test.dart` 有一条专门钉它）。
   同一次扩张的边界：**只加了置顶**。
   ⚠️ **2026-10-05 又扩了一次（format v4）：身体数据进备份**（身高 + 逐日的体重/体脂率/
   腰围/肌肉量/备注；只在仍持有那道单独同意时带上）。**计划模板 / 其它设置仍然不进备份。**

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

**重量填的是一个还是两个？**（2026-10-08 用户问出来的，界面上以前一个字都没写）

| 器械 | 你填的数 | 证据 |
|---|---|---|
| **杠铃** | **总重（含杠铃杆）** | `杠铃卧推` 的起始建议是 **40 kg**（= 20 kg 杆 + 两侧各 10 kg），不是"每边 40" |
| **哑铃 / 壶铃** | **单只** | `哑铃卧推` 的起始建议是 **12 kg/只** |
| 器械 / 绳索 / 自重 | 没有这个歧义 | —— |

**容量算法**：`Σ 重量 × 次数`（`SetRecord.volume`，见 `app/lib/domain/models.dart`），
用的就是**你填的那个数** —— 所以杠铃是"总重 × 次数"，哑铃是"**单只** × 次数"。
⚠️ **哑铃那一半是已知口径**：两只一起举的真实负荷是两倍，容量因此偏小；
改它属于**数据口径变更**（会动到历史 PR、周报、趋势图），要单独拍板 ——
账记在 `docs/plan-ux-2026-10-08.md` §二。界面上的口径由 `core/labels.dart` 的
`weightBasisLabel()` 统一给（动作库那一行 + 动作详情各印一句），**不许各写各的**。

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

### 动作说明：内容债的**可见形式**（`instructions`，2026-09-29）

动作库 351 个动作，而 App 里长期只有**名字** —— 对「垫脚高脚杯深蹲」这种名字，
新人看不出是在干什么。这一列补的就是这个，但它**一次写不完**，所以配套的是三件事：

| 事 | 在哪 |
|---|---|
| 字段与校验 | `exercise.instructions`（≤ 80 字，写了就不能空、不能带首尾空白） |
| **覆盖率的数字** | `node tool/content-report.mjs`（全部覆盖率 + 推荐位覆盖率 + 待写队列按常用度排） |
| **一条硬承诺** | **每个动作都必须有说明**（全库）—— 有测试守着：新加动作不写说明就红 |

当前的取舍如实写在这里：**推荐位 48/48、全库 351/351 = 100%**。
2026-09-30 从高常用度往下铺了六版（15.4% → 47.9% → 64.4% → 86.6% → 100%），
现在它是**不变量而不是覆盖率**：动作数可以涨，涨进来的新动作必须带说明。
`tool/content-report.mjs` 保留下来是给"以后要不要加动作"用的，不再是一条欠账。

内容由人撰写（`seed/parts/` 下的 `01-chest-back.json` / `02-legs-shoulders.json` / `03-arms-core.json`，与 `seed/upstream-zh-names.json`），
**不由脚本推导** —— 动作要点写错的代价比不写大得多。

### 细分标签（`sub_tags`，v28 / 2026-10-09）

**问题**：主部位只有 6 个（chest / back / legs / shoulders / arms / core），
而用户嘴里说的是「**今天练上胸**」—— 选择器按部位筛只能筛到"胸"，35 个胸部动作一起铺出来。

**做法**：给力量动作打**细分标签**，参与搜索与筛选。

| 主部位 | 词表 |
|---|---|
| `chest` | 上胸 / 下胸 / 中缝 |
| `back` | 背阔 / 上背 / 下背 / 斜方 |
| `shoulders` | 前束 / 中束 / 后束 |
| `arms` | 肱二头 / 肱三头 / 前臂 |
| `legs` | 股四头 / 腘绳 / 臀 / 小腿 / 内收 |
| `core` | 上腹 / 下腹 / 侧腹 |

三条规矩（都在 `seed/build.mjs` 里校验，写错直接构建失败）：

1. **标签必须属于它自己的主部位** —— "上胸"出现在背部动作上，筛出来的东西是错的，
   比没有标签更糟；
2. **只给 `category = strength` 的动作打** —— 热身/拉伸谈"上胸"没有意义；
3. **允许为空** —— 标签是内容债，**宁可没有也不要猜**。当前 **230/318 个力量动作有标签**
   （构建时打印这个数）。没有标签的动作照旧只能在"部位"那一层被筛到。

⚠️ **词表有两份，而且必须一致**：种子校验那份在 `seed/build.mjs` 的 `SUB_TAGS`，
客户端画 chip 那份在 `app/lib/core/labels.dart` 的 `kSubTagsByMuscle`。
两边不一致的后果是"chip 点下去筛不到任何动作，而门禁全绿"—— 所以 `seed/build.mjs`
会拿 Dart 那份做**交叉检查**（缺一个标签就报错；这条检查自己也被反向验证过：
把 Dart 里某个标签改坏一个字，种子构建当场红）。

存储是 **JSON 数组文本**（与 `aliases` / `secondary_muscles` 同一性质：一串短词、
只整体读写、从不按它 join）。搜索用 `LIKE '%"上胸"%'`（带引号，避免"胸"命中"上胸"之外的词）。

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

**当前 `schemaVersion = 30`**（真源是 `app/lib/data/db.dart`；文档里这个数字由
`tool/check-doc-facts.mjs` 每次对着代码核，写旧了会判红 —— 包括这种 `schemaVersion = 20`
的写法，2026-10-05 之前它只认 `schema v20`，而本文档恰好用的是前者，于是**只有这份文档
逃过了检查**：规则补上 `=` 之后当场抓到它写着 15）。

| 版本 | 改动 | 需要注意的地方 |
|---|---|---|
| v1 | 初始 schema（动作库 / 训练 / 训练项 / 组记录 / 档案 / 埋点 outbox） | 老库的起点 |
| v2 | 新增 `body_metric`（身体数据 S12） | 只加表 |
| v3 | 新增 `routine` / `routine_item`（计划模板 S11） | 只加表 |
| v4 | `exercise` 新增 `category`（DEFAULT `'strength'`；词表 strength/warmup/cardio/stretch） | **第一次给已有表加列** —— 老库升级后 318 个动作全部落成 `strength`（它们本来就是力量动作，这正是要的结果），不需要数据搬迁 |
| v5 | `set_record` 新增 `distance_m` | 老库里的组记录距离恒为 **null**（"没记过距离"），**不是 0**（0 表示"真的没动"）—— 加列迁移最容易被搞错的地方，有专门的迁移测试守着 |
| v6 | `user_profile` 新增 `body_weight_unit`（体重的显示单位） | 老档案缺省 `'kg'` —— 在"体重单位"这个概念出现之前，体重显示的确实是 kg，所以缺省值就是当时的真实行为 |
| v7 | 新增 `analytics_meta`（埋点的本机记账） | 只加表。老库升上来是空的 —— 首次启动会生成设备 ID 并记下首启时间，**升级用户的"首次 app_open"从这一版算起**（这正是要的） |
| v8 | `exercise` 新增 `default_target_distance_m`（距离处方） | 老库恒为 null —— 老库本来就没有距离动作（v1.4.0 才补进来），null 是准确的历史 |
| v9 | `exercise` 新增 `instructions`（动作说明） | 老库恒为 null（那时 App 里没有这个字段）—— 覆盖率工具会如实算进去，不假装有 |
| v10 | 新增 `backup_account`（云备份账号 / 恢复码） | 只加表。老库升上来是空的 —— 那正是要的：**云备份默认关闭**，没有那行代表"这台机器还没开过" |
| v11 | `user_profile` 新增 `privacy_consent_at_ms`（政策同意时刻） | 老库为 **null = 还没同意过** —— 于是老用户也会看到一次同意弹窗。**这是有意的**：他们当年装的那版里根本没有应用内政策可读 |
| v12 | `user_profile` 新增 `privacy_declined_at_ms`（拒绝时刻） | 拒绝 ≠ 同意：老库为 null 表示"没拒绝过"。用户在弹窗里选"不同意"照样能进 App 用离线功能，而我们记得他拒绝过 |
| v13 | **统计开关的默认值从"开"改成"关"**（`UPDATE user_profile SET analytics_enabled = 0`） | 列默认值只影响以后新插入的行，**老库里那几个 `true` 必须显式翻过来** —— 否则"默认同意"这个毛病会跟着老用户一直活下去。（写这一刀时还没有真实用户，所以没有覆盖任何人的选择） |
| v14 | `user_profile` 新增 `body_metric_consent_at_ms`（体重的**单独同意**） | PIPL 第 29 条：敏感个人信息要单独征得同意。老库为 null —— 老用户下次进「身体数据」会看到那道说明（对的：他们当初同意的是政策，不是"处理敏感个人信息"这件事本身） |
| v15 | 新增 `active_session_row`（**未结束的训练会话**） | 2026-10-01：训练中断后能回来接着练（见本文上面那节）。只加表；「删除全部数据」会把它一起清掉（有"表清单守门"测试盯着） |
| v16 | 新增 `pinned_exercise`（动作置顶 / 收藏） | 只加表。老库升上来是空的 —— **准确的历史**：这个功能出现之前用户一个动作都没置顶过 |
| v17 | 新增 `reminder_setting`（训练提醒） | 只加表。老库升上来是空的 —— 那正是要的：**提醒默认关闭**，没有那行代表"这台机器还没开过提醒" |
| v18 | `analytics_meta` 新增 `legacy_purged_at`（"旧数据已清"的时刻） | **第二次给既有表加列**，两条教训见 `db.dart` 里那段注释：迁移必须排在**链尾**（那张表是 v7 才建的），判据是"这一列现在有没有"而不是版本号。老库为 null = 还没清过 |
| v19 | 新增 `app_notification`（站内消息 / 通知中心） | 只加表。⚠️ 那条**部分唯一索引**（`idx_notification_ref`）在迁移里也要建一遍 —— 老库升级走的是迁移这条路，`onCreate` 只管新库 |
| v20 | 身体数据扩展：`body_metric` 新增 `waist_cm` / `muscle_mass_kg`，`user_profile` 新增 `height_cm` | **第三次给既有表加列**（v18 之后）。老库这三列都是 **null = 没记过**（不是 0）—— 腰围 0 cm 是个有意义的值，不能拿来当"没填"。同样排在链尾、同样按"这一列有没有"判断（新库 `onCreate` 已经带着这三列，无条件 `addColumn` 会 `duplicate column name`） |
| v21 | 新增 `streak_protection`（连续保护 / 补签，第二部分第 2 条） | 只加表。老库升上来是空的 —— **准确的历史**：这个功能出现之前谁也没补签过（也就是说，他们的连续天数从来没被补签撑过）。⚠️ 这是**唯一一张「关于历史」的用户声明**（其余一切都是训练记录的推导结果）——所以它只能新开一张表，绝不能去改 `set_record`/`workout`：**记录就是事实**。删表清单（`test/delete_all_test.dart` 的表清单守门）里它是**删** |
| v22 | 新增 `auth_session`（登录会话，账号体系 P1-3） | 只加表。老库升上来是空的 —— **准确的历史**：升级之前这台设备没有登录过任何账号。⚠️ 里面存着账号密钥（16 字节）与**还有效的会话令牌**，所以「删除全部数据」**必须清它**（`drift_local_store.deleteAllUserData` + `delete_all_test.dart` 的表清单与种子两处都接上了）|
| **v30** | 新增 `entitlement` / `billing_event`（**会员（Ultra）权益与计费流水**，2026-10-10 会员 M1） | 只加表、排在链尾。老库升上来两张都是空的 —— **准确的历史**：在这之前这台设备没有任何权益记录；而"没有记录"正是 `resolveUltraAccess(null, now) == none`（免费用户），所以**升级不会凭空给谁发权益**（`migration_test.dart` 的 v29→v30 那条就是钉这个的：断言的重点是"空"）。⚠️ 两处取舍写在案：① `entitlement` 是**本机缓存**（离线也能用），真相永远在商店收据上，判定逻辑全在纯函数 `app/lib/billing/entitlement.dart`（九态状态机），表里只存字段；② 「删除全部数据」**会连它一起清**（它记的是"这个人是谁、买过什么"，与 `backup_account` / `auth_session` 同类）——代价是付费用户删完数据会暂时变回免费，直到点一次「恢复购买」 |
| v29 | `user_profile` +`training_scenario`（**在哪儿练**：健身房 / 家里 / 徒手，2026-10-09 第二份 docx 第 4 条） | **加列**。老库升上来是 **null = 没选过** → 按**健身房**（全部器械）算 —— 那正是这一版之前的行为，所以老用户一个字都没变。⚠️ 词表与"每个场景允许哪些器械"的唯一出处是 `app/lib/features/today/training_scenario.dart`（纯函数 + 单测）：健身房=全部、家里=哑铃/壶铃/弹力带/自重、徒手=只有自重。它只影响**今天练什么**的挑动作（`planToday` / `reroll` → `search(equipmentIn:)`），**不改计划模板**（那要一套新内容） |
| v28 | `exercise` +`sub_tags`（细分标签：上胸 / 中缝 / 后束…，10.9 清单第 7 条） | **加列**。老库升上来是 `[]` = 没标过 —— 那是准确的历史：在这之前动作库里没有这个粒度。⚠️ 而动作库**下次启动会按种子重新导入**（`importSeed` 按 id upsert），标签随之到位；用户自建的动作永远是 `[]`（我们不为他猜"这动作练的是上胸"）。词表与种子校验在 `seed/build.mjs`，客户端那一份在 `core/labels.dart`，两处不一致会让构建失败（交叉检查） |
| v27 | 新增 `day_plan_item` / `day_plan_day`（**今天的安排**落库，10.9 清单第 6 条） | 只加表。老库升上来是空的 = "这一天还没排过" → 下次打开照旧按分化现算一份并落库。⚠️ 两张表是一件事的两半：`item` 存"练哪几个"（date + position + 动作 + 处方），`day` 存"这一天排过了" —— 因为用户可以把动作**全删光**，而"我删光了"必须存得住（只看有没有行的话，那批动作下次又冒出来，他会以为删除按钮是坏的） |
| v26 | `user_profile` +`default_weight_increment`（用户自己设的默认加重步进，10.9 清单第 8a 条） | **加列**。老库升上来是 **null = 没设过** → 各动作仍用自己的步长（现状不变）。⚠️ 它只影响**以后新建的自定义动作**（与"铺到所有动作"那个动作分开：铺开写的是 `exercise.weight_increment`）—— 语义写在 `ProfileRepository.setDefaultWeightIncrement` 的注释里 |
| v25 | `user_profile` +`health_consent_at_ms`（**从系统健康库读取体成分**的单独同意时刻） | **加列**。老库升上来是 **null = 从没同意过 = 一次都没读过** —— 那正是准确的历史。⚠️ 它与 `body_metric_consent_at_ms` **不是同一件事**：那一列同意的是"把体重记在本机"，这一列同意的是"去读系统健康库里别人写进去的记录"（可能是体脂秤 App，也可能是医院那份）。PIPL 第 29 条要对处理目的逐项单独同意，拿一个勾盖两件事、撤回时就会连带撤回另一件 —— 所以各自一列、各自一道门、各自一条撤回路径（`ProfileRepository.setHealthConsent` / `clearHealthConsent`，互不干扰由 `app/test/health_sync_test.dart` 钉着）|
| v24 | `user_profile` +`nickname`（昵称，10.7 清单第 7 条） | **加列**。老库升上来是 **null = 没设过**（界面如实写"还没设昵称"，不编默认名）。⚠️ 三条边界：① **纯本地** —— 不进云备份的合并键、不上报、没有分享名片；② **不是身份** —— 身份由账号 ID 承担（`account_id` 前 8 位，没登录就不显示）；③ 写入**不走 `insertOnConflictUpdate`** —— 实测那条路不会把已存在的值清成 NULL（设过"李松"再传 null，库里还是"李松"），所以"清空昵称"单独走一条精确 `update`（`ProfileRepository.setNickname`，有测试钉着） |
| v23 | `user_profile.analytics_enabled` 的**列默认值** `0 → 1`（「帮助改进产品」默认开，2026-10-07 用户拍板） | ⚠️ **这是唯一一次"只改默认值"的迁移，而且它有意什么都不做**。三件事要连着读：① 这个默认值只在建表或缺省插入时起作用，而 drift 的 Dart 数据类把这一列当必填、每次写都显式传值 —— 老库根本用不到它；② **不搬数据**：存量机器那一位原样不动（他们当年在同意屏与政策里看到的是"默认关闭"，静默翻转等于对着旧承诺收集数据）；③ 于是语义是"**新装 = 开，存量 = 它自己那一行**"，由 `migration_test.dart` 的 v22→v23 用例钉住。判据链的另一半在 `docs/privacy-facts.json` 的 `analyticsOptIn`（事实源 ↔ `db.dart` 默认值 ↔ 中英政策正文，`privacy-audit` 每次三方对账）|

迁移测试在 `app/test/migration_test.dart`，fixture 在老库形状的 `app/test/legacy_db.dart`。
⚠️ **fixture 必须用当年的 DDL 手写**：拿当前 schema 建完再改的话，
`ALTER TABLE ADD COLUMN` 会因为列已存在而失败（看起来像迁移坏了），
或者更糟 —— 有人把 fixture 悄悄改成新 schema，测试永远绿。
`migration_test.dart` 里有一条专门守这个。

**已知限制（记在这儿，不藏着）**：`weight_time` 动作的"容量"仍是 `重量 × 秒数`，
量纲上说不通（负重平板 5kg × 30 秒 = 150）。目前只有 1 个这样的动作，
且自重时长动作的容量本来就是 0。要修就得让 `set_record` 知道自己是不是时长动作
（加列或联表），留给真正需要"容量"统计的那次改动。


### 连续打卡保护（`streak_protection`，v21 / 2026-10-06）

**这个 App 里唯一一件「用户写下来的、关于历史」的声明。** 其余的一切（徽章、连续天数、
段位、周报、经验）都是从训练记录**推导**出来的 —— 改历史 / 导入备份 / 换设备之后
它们自己就对。补签是例外，所以它被刻意关在这张表里，**一行一天**：

| 列 | 类型 | 说明 |
|---|---|---|
| `date` | TEXT **PK** | 被保护的那一天（本地日，`YYYY-MM-DD`）。用字符串是为了排障时能人肉读出来 |
| `created_at_ms` | INTEGER | **补签这个动作**发生的时刻（不是被补的那一天 —— 界面上它们是两件事） |

口径（判据全是纯函数，见 `features/progress/streak_protection.dart`）：

* **每周一次**：额度**由已补的那一天反推**（周一那天所在的周），不另存计数 ——
  存计数就会和这张表本身不一致；
* **代价 = 本周至少练过 1 次**：白送的保护没有意义，而且这条让用户"先练一次再补"
  （顺序是对的：先动起来，再谈保护）；
* **补签不涨连续天数，只防断**：被补的那天**撑住链、也计 1 天**，所以界面上
  **必须**同时写出「其中 N 天是补签」（`streakLabelWithProtection`）——
  不写就等于在告诉用户"这些天我天天都练了"；
* 判据第 3 条是「**昨天与前天里恰好断了一天**」，而**今天不参与**
  （"今天还没练"从来不算断，与 `streak.dart` 同一条纪律）。

⚠️ 它**不碰任何训练记录**：补签不是"那天我练了"，而是"我知道那天断了，
我选择不让这条链断在这里"。

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
  id             TEXT PRIMARY KEY,
  user_id        TEXT,
  date           TEXT NOT NULL,        -- YYYY-MM-DD，一天一条
  weight_kg      REAL,
  body_fat_pct   REAL,
  waist_cm       REAL,                 -- 腰围（v20 加）；null = 没记过，不是 0
  muscle_mass_kg REAL,                 -- 骨骼肌量（v20 加）；同样 null = 没记过
  note           TEXT,
  updated_at     INTEGER NOT NULL,
  deleted_at     INTEGER
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

-- 用户画像：规则引擎的输入（2026-10-05 逐列对齐 db.dart，之前这份 DDL 停在 v6 的形状）
CREATE TABLE user_profile (
  user_id                 TEXT PRIMARY KEY,
  goal                    TEXT,      -- hypertrophy | strength | fat_loss
  weekly_frequency        INTEGER,   -- 每周几天，用于部位轮转
  unit_pref               TEXT DEFAULT 'kg',    -- **训练重量**的显示单位：kg / lb
  body_weight_unit        TEXT DEFAULT 'kg',    -- **体重**的显示单位：kg / jin（1 斤 = 500 g）
  default_rest_sec        INTEGER DEFAULT 90,
  progression_mode        TEXT DEFAULT 'double', -- double | linear | off（用户可关闭建议）
  height_cm               REAL,                 -- 身高（v20 加）；只用来算 BMI，null = 没填过
  nickname                TEXT,                 -- 昵称（v24 加）；纯本地，null = 没设过
  analytics_enabled       INTEGER DEFAULT 1,    -- 「帮助改进产品」开关，**默认开**（v13 改成关、v23 又改回开）
  privacy_consent_at_ms   INTEGER,              -- 政策同意的时刻（v11 加）；null = 还没同意过
  privacy_declined_at_ms  INTEGER,              -- 明确拒绝过的时刻（v12 加）；拒绝 ≠ 同意
  body_metric_consent_at_ms INTEGER,            -- 身体数据的**单独同意**（v14 加）；null = 还没问过
  health_consent_at_ms    INTEGER,              -- **从系统健康库读取**的单独同意（v25 加）；null = 从没同意过（= 一次都没读过）
  created_at              INTEGER NOT NULL,
  updated_at              INTEGER NOT NULL
);
```

> 这张表里有两列是"**不能混**"的：`analytics_enabled`（使用统计开关，随时可关、关掉
> 功能不受影响）和 `privacy_consent_at_ms`（法律意义上的同意）。另有
> `body_metric_consent_at_ms` 专门记**敏感个人信息**的单独同意（PIPL 第 29 条）——
> 三者是三个东西，撤回同意的那条路（`clearBodyMetricConsent`）只清第三个。

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
