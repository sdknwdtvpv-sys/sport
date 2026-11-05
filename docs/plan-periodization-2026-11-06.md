# 周期化计划 v1（Ultra 权益 10）· 设计与判据

> 状态：**2026-11-06 设计与 v1 实现同批落地**（用户点名「周期化计划 v1」）。
> 施工落点：`app/lib/domain/periodization.dart`（纯函数）、`app/lib/data/period_plan_repository.dart`、
> `app/lib/features/plan/periodization_screen.dart`；本文件是**口径的唯一出处**，代码与本文件不一致时以本文件为准。
>
> **边界**：不做 AI 动态调整、不做服务端同步、不改既有免费「我的计划（模板）」行为、
> 不新增权限/埋点事件。`kUltraReleased == false` 期间**免费用户零新增付费入口**。

---

## 一、v1 的范围（做成什么、不做什么）

**做**：

* 内置模板创建：**4 / 6 / 8 周** × **每周 3 / 4 练**；
* 每周课表（每天哪些动作、几组、几次/几秒、目标重量）；
* 从课表某一天直接开练（复用现有训练屏/渐进建议引擎）；
* 按周自动加重、第 4 周 deload、跨周推进；
* 周期完成后归档；中途换计划（新建 = 旧计划归档，不删数据）；
* 计划 JSON 导入/导出（版本化、拒绝未知字段、坏文件给可读原因）。

**不做**（v1 明确）：AI 动态调整、服务端同步、按 1RM 百分比编程、多计划并行、
自动换动作（器械被占仍走训练屏既有路径）、周期化计划的"我的计划"式逐项编辑（v1 只读模板结果，
训练时仍可像今天一样改动作/重量）。

---

## 二、模板与日程

| 模板 | 周数 | 每周练 | 说明 |
|---|---|---|---|
| 4 周入门 | 4 | 3 | 上肢/下肢交替（上、下、上） |
| 6 周标准 | 6 | 3 | 同上 |
| 8 周进阶 | 8 | 4 | 上肢/下肢/上肢/下肢 |

> 上面是**推荐预设**；创建时也允许任意 `4/6/8 × 3/4` 组合（如 6 周 × 4 练）。
> 计划名称默认 `W 周计划 · 每周 D 练`，创建后可导入/换一份。

* **第 1 周（day 1..N）的日程**：从 `TodayPlanner.planToday(day: …)` 快照生成
  （上肢日用 `TrainingDay.upper`、下肢日 `lower`，交替）；不按用户历史动态变，
  保证同一份计划每周同一天动作一致，才谈得上"按周加重"。
* **每周几练**由模板决定，**不按日历硬绑**：课表有 N 天，用户哪天真练由他自己决定；
  周完成判定只看"这一周内是否完成了足够的训练"（见 §四）。
* **训练日 label**：`第 W 周 · 第 D 天 · 上肢/下肢`；day 从 1 开始。

## 三、加重与 deload（纯函数口径）

设某动作第 `w` 周目标重量为 `targetWeightKg`（null = 自重/按时长，**不加重**）。

1. **普通周**（`w+1` 不是 deload 周）：
   * 有重量（`targetWeightKg != null && > 0`）：
     `increment = max(2.5, roundToStep(targetWeightKg × 2.5%, 2.5))`（kg，四舍五入到 2.5 kg 步进），
     新目标 = `targetWeightKg + increment`；
     * 例：60 kg → 2.5% = 1.5 → 取 2.5 → 62.5 kg；100 kg → 2.5 → 102.5 kg；200 kg → 5 → 205 kg。
   * **自重/按时长**（null）：保持 null；组数/次数区间不变 —— **不编重量**。
2. **deload 周**：`week % 4 == 0`（4/8 周计划的第 4/8 周，6 周计划的第 4 周）：
   * 有重量：目标 = `roundToStep(targetWeightKg × 0.9, 2.5)`（-10%，向 2.5 kg 步进取整）；
   * 自重/按时长：不变；
   * 组数不变（v1 不额外减组 —— 减组会与"这周也要完成课表"的判定打架）。
3. deload **之后一周**：从 deload 前的重量继续 `+increment`（不是从 deload 的 90% 往上爬）：
   即纯函数按"上一非 deload 周目标"推进，deload 只是那一周的显示/执行值。
4. **一次性代际**：v1 只按"周"推进，不按"实际完成重量"动态回退（那属于 v2/AI）。
   用户若某周自己加重了，计划里的目标不会自动跟随（训练屏仍按用户实际记录给建议）。

## 四、周完成判定（进入下一周的唯一条件）

* **周窗**：以 `startDate`（本地日，`YYYY-MM-DD`）为第 1 周第 1 天；
  第 `w` 周 = `[startDate + 7*(w-1), startDate + 7*w)`（左闭右开，本地日期）。
* **计划项命中**：一项（某天某动作）在本周内**至少有一条正式组**（`set_type='normal'`）即算完成。
* **周完成阈值**：本周计划项的**完成比例 ≥ 80%**（向上取整项数：`ceil(总数 × 0.8)`）。
  * 例：3 练 × 6 动作 = 18 项 → 至少 15 项；4 练 × 6 = 24 → 至少 20 项。
* 达标 → 自动 `currentWeek += 1`（若已是最后一周 → 计划状态变 `completed` 并归档说明）。
* **没练满**：**不自动推进**，`currentWeek` 停在原周；首页/计划页显示"本周还差 N 项"。
  v1 不提供"跳过本周"按钮（避免"点一下就跳过"变成默认操作）；
  用户可以继续练完，或新建一份计划（旧计划归档）。**没有"惩罚"、不删数据**。
* 跨年、闰年、缺周：全部按本地日期与 7 天窗计算；`DateTime` 加法不引入时区/夏令时假设
  （中国无 DST；跨年只是年份+1，周窗连续）。

## 五、数据模型（schema v32）

两张新表（只加表、不动任何既有列/行）：

```sql
period_plan(
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  weeks INTEGER NOT NULL,           -- 4/6/8
  days_per_week INTEGER NOT NULL,   -- 3/4
  start_date TEXT NOT NULL,         -- 本地日 YYYY-MM-DD（第 1 周第 1 天）
  current_week INTEGER NOT NULL,    -- 1..weeks
  status TEXT NOT NULL,             -- active / completed / archived
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
period_plan_session(
  id TEXT PRIMARY KEY,              -- planId/w/week/day/position 的稳定串
  plan_id TEXT NOT NULL,
  week INTEGER NOT NULL,            -- 1..weeks
  day INTEGER NOT NULL,             -- 1..daysPerWeek
  position INTEGER NOT NULL,
  exercise_id TEXT NOT NULL,
  target_sets INTEGER NOT NULL,
  reps_low INTEGER NOT NULL,
  reps_high INTEGER NOT NULL,
  target_weight_kg REAL NULL,       -- null = 自重/按时长，不加重
  updated_at INTEGER NOT NULL
);
CREATE INDEX idx_period_plan_status ON period_plan(status, updated_at DESC);
CREATE INDEX idx_period_plan_session ON period_plan_session(plan_id, week, day, position);
```

* v31 → v32 **只加这两张表**（`m.createTable`）；老库升上来是空的 = "还没建过周期计划"。
* 迁移不对既有行/列做任何事；重复打开幂等（drift 的 user_version + `CREATE TABLE IF NOT EXISTS` 语义）。
* 「删除全部数据」要把这两张表一起清（加到 `deleteAllUserData` 的表清单与 `delete_all_test`）。

## 六、交互流程

1. 计划页（`PlanScreen`）「本周」页新增入口卡 **「周期计划（Ultra）」**：
   * **仅本机权益 active 时渲染**；无权益/过期整组不出现（`kUltraReleased=false` 时零新增付费入口）。
2. 周期计划页：
   * 无计划：三/四个模板按钮（4/6/8 周 × 3/4 练按模板固定组合展示）+「导入 JSON」；
   * 有计划：标题（名称 · 第 W/总周 · 状态）、本周课表（第 1..N 天，每天动作 + 组数×次数 + 目标重量）、
     「从这一天开练」（把该天动作交给既有训练屏/建议引擎）；
     底部「导出 JSON」「换一份计划」（新建 = 旧计划归档）。
3. 周完成：打开计划页/首页时由仓库检查本周完成度；达标自动进下一周（只前进、不后退）。
4. 导入/导出 JSON：文件结构见 §七；导出复制到剪贴板（与现有 CSV/备份同交付方式），
   导入粘贴文本（v1 不接文件选择器 —— 不新增权限）。

## 七、计划 JSON 格式（v1）

```json
{
  "version": 1,
  "plan": {
    "name": "4 周入门",
    "weeks": 4,
    "days_per_week": 3,
    "start_date": "2026-11-09",
    "current_week": 1,
    "status": "active",
    "sessions": [
      {"week":1,"day":1,"position":0,"exercise_id":"ex_bb_bench_press",
       "target_sets":3,"reps_low":8,"reps_high":10,"target_weight_kg":60.0}
    ]
  }
}
```

**校验（纯函数，坏文件给可读原因，不抛原始异常）**：

* `version` 必须是 1；其他值 →「这份计划来自更新版本（vX），当前版本读不了」。
* **未知字段一律拒绝**（任意层级）：`拒绝未知字段：plan.foo`（防止"以为导入了、其实丢了字段"）。
* `weeks ∈ {4,6,8}`、`days_per_week ∈ {3,4}`、`current_week ∈ [1,weeks]`、`start_date` 为 `YYYY-MM-DD`；
* sessions 非空、每个 `week ∈ [1,weeks]`、`day ∈ [1,days_per_week]`、`position >= 0`、
  `target_sets ∈ [1,10]`、`0 < reps_low <= reps_high <= 600`、`target_weight_kg` 若给必须 > 0；
* 同一 `(week, day, position)` 不得重复；缺字段 →「缺少字段：plan.name」。
* 导入 = 新建一份计划并归档当前 active 计划（**旧计划不删**）；`id` 由本地重新生成。

## 八、判据（本批测试逐条对应）

1. 纯函数：普通周 +2.5%（2.5kg 步进）、deload -10%（第 4/8 周）、自重/按时长不变、
   deload 后从 deload 前重量继续、跨年周窗、周完成阈值 80%（含向上取整）、没练满不推进。
2. 迁移 v31→v32：老库打开不崩、两张新表存在且为空、重复打开幂等（文件库）。
3. JSON roundtrip 完全一致；未知字段/版本不符/坏日期/重复 position/缺字段都给**可读中文原因**。
4. 权益 gate：无权益/过期 → 入口不渲染；有权益 → 可进；`ultra_release_gate_test` 仍绿。
5. 大字号：周期计划页在 2.0× 下不溢出（列表可滚 + 固定元素用 Tokens）。
6. 空态：没有 active 计划时显示模板选择，不显示假课表；`currentWeek` 不越过总周数。
