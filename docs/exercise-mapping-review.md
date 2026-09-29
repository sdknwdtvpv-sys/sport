# 上游动作库映射 —— 人工复核结论（第 2、3 节）

> 输入：[exercise-mapping.md](file:///workspace/.uploads/8d537c76-acf1-491c-8529-3cd558573e0c_exercise-mapping.md)
> 范围：仅复核第 2 节（待人工确认）与第 3 节（相似度 < 0.5）。
> 判定标准：动作模式相同 + 上游器械列与我们英文名所含器械一致 + 无 single-arm / incline / reverse-grip / pause / weighted 等限定差异。

## 一、第 2 节：上游与我们一致，可直接确认

下列动作的上游候选就是同一个动作，仅命名/词序不同，可放心勾选确认并借上游 `exerciseType` / `equipment` / `primaryMuscle` 补齐字段。

| 我们的 id | 我们的英文名 | 上游动作 | 上游器械 | 相似度 |
|---|---|---|---|---|
| `ex_machine_chest_press` | Chest Press Machine | Machine Chest Press | Machine | 1.00 |
| `ex_bb_decline_bench_press` | Decline Barbell Bench Press | Decline Bench Press | Barbell | 0.75 |
| `ex_bb_incline_bench_press` | Incline Barbell Bench Press | Incline Bench Press | Barbell | 0.75 |
| `ex_overhead_db_extension` | Overhead Dumbbell Extension | Dumbbell Overhead Tricep Extension | Dumbbell | 0.75 |
| `ex_bb_bench_press` | Barbell Bench Press | Bench Press | Barbell | 0.67 |
| `ex_db_front_raise` | Dumbbell Front Raise | Front Raise | Dumbbell | 0.67 |
| `ex_db_lateral_raise` | Dumbbell Lateral Raise | Lateral Raise | Dumbbell | 0.67 |
| `ex_hip_abduction` | Hip Abduction | Hip Abduction Machine | Machine | 0.67 |
| `ex_hip_adduction` | Hip Adduction | Hip Adduction Machine | Machine | 0.67 |
| `ex_hip_thrust` | Barbell Hip Thrust | Hip Thrust | Barbell | 0.67 |
| `ex_machine_pec_deck` | Pec Deck Fly | Pec Deck | Machine | 0.67 |
| `ex_machine_row` | Seated Row Machine | Machine Row | Machine | 0.67 |
| `ex_reverse_bb_curl` | Reverse Barbell Curl | Reverse Curl | Barbell | 0.67 |
| `ex_overhead_cable_extension` | Overhead Cable Extension | Overhead Tricep Extension | Cable | 0.50 |

### 1 个边界项，需先查姿势字段

| 我们的 id | 我们的英文名 | 上游动作 | 上游器械 | 相似度 | 怀疑点 |
|---|---|---|---|---|---|
| `ex_db_shoulder_press` | Dumbbell Shoulder Press | Dumbbell Seated Shoulder Press | Dumbbell | 0.75 | 上游多 "Seated"。若我们种子默认坐姿 → 同动作；站姿 → 不同 |

### 易漏项提示

`ex_bb_front_raise`（杠铃前平举）虽然也指向 `Front Raise`，但上游器械列是 **Dumbbell**，与我们 Barbell 不同，**不**算一致。

## 二、第 2 节剩余项：命名相近但动作不同，不建议确认

这些行相似度高，但存在器械 / 单臂 / 角度 / 反握等差异，属于表头警告的"Romanian Deadlift 与 Deadlift"类型：

- `ex_machine_hip_thrust`（Machine Hip Thrust）vs Smith Machine Hip Thrust —— 器械不同（Machine vs Smith）
- `ex_machine_incline_press` vs Machine Chest Press —— 角度不同（上斜 vs 平）
- `ex_smith_lateral_raise` / `ex_smith_shoulder_press` —— 史密斯 vs 普通器械
- `ex_hanging_side_leg_raise` —— 侧举腿 vs 直腿举腿
- 全部 `ex_single_arm_*` / `ex_close_grip_*` / `ex_reverse_grip_*` / `ex_pause_squat` / `ex_weighted_*` —— 存在限定词差异
- `ex_db_curl` / `ex_db_incline_fly` / `ex_incline_hammer_curl` —— 上斜/器械变体不同
- `ex_cable_hammer_curl` / `ex_cable_reverse_curl` —— 锤式/反握 与普通 Cable Curl 不同
- `ex_reverse_wrist_curl` —— 腕弯举 与普通弯举不同
- `ex_sit_up` —— 仰卧起坐 vs Decline Sit-Up，角度不同
- `ex_box_squat` / `ex_cable_side_bend` / `ex_machine_crunch` / `ex_side_crunch` / `ex_smith_calf_raise` / `ex_weighted_plank` / `ex_lean_away_lateral` / `ex_db_alternating_curl` / `ex_bent_over_cable_fly` —— 器械或姿态不同

## 三、第 3 节：基本无一致上游

按文档定性，第 3 节均为"上游真没有、需自行维护"。逐行核对候选也确实不是同一动作（如 `Barbell Curl`↔`Barbell Row`、`Cable Crossover`↔`Cable Crunch`、`One-Arm Press`↔`One-Arm Row` 等）。

### 仅 2 项值得再看一次上游源数据

第 3 节表无"上游器械"列，无法交叉验证，下列两项需查 `seed/upstream-workout-guide.json`：

| 我们的 id | 我们的英文名 | 候选 | 相似度 | 怀疑点 |
|---|---|---|---|---|
| `ex_bb_squat` | Barbell Back Squat | Squat | 0.33 | 若上游 `Squat` 默认即杠铃背蹲，则其实是同一个；分低是字符串差异所致 |
| `ex_straight_bar_pushdown` | Straight-Bar Pushdown | Tricep Pushdown | 0.25 | 两者都可能是直杆三头下压，命名侧重不同 |

## 四、下一步

1. **第一节**（上游已命中且类型标错）：原文档说明本节为空，无需动作。
2. **第二节一、二**：上面"一致"清单可直接确认并补字段；"边界项"先查 `ex_db_shoulder_press` 的姿势字段再定。
3. **第二节三**：剩余项不建议自动确认，保留在表里。
4. **第三节**：除两项需查上游源数据外，其余按"自行维护"处理。
