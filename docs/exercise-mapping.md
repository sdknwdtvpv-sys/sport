# 上游动作库映射（活文档）

> **这不是结论，是一张给人过的候选表。** 工具只给候选与相似度；
> `Romanian Deadlift` 与 `Deadlift` 名字极近但是两个动作 —— 自动接受这类猜测
> 等于往动作库里灌错数据，而动作库是产品资产。
>
> **人工复核的结论已经落进 `seed/upstream-confirmed.json`**（复核过程见
> `docs/exercise-mapping-review.md`），本文件由它驱动：已确认的移出待办、否掉的连理由留档。
>
> 由 `node tool/map-upstream.mjs` 生成。上游快照 = `bryllim/workout-guide` @ `aac59922`（MIT，**不含插画**）。

## 总览

| 项 | 数量 |
|---|---|
| 我们的动作 | 165 |
| 上游动作 | 302 |
| **有上游对应**（精确命中 85 + 人工确认 17） | **102** |
| 已复核：确认一致 | 17 |
| 已复核：命名相近但动作不同 | 39 |
| 待人工复核的候选（相似度 ≥ 0.5） | 0 |
| 未命中且相似度 < 0.5（自行维护） | 26 |
| 上游有、我们没有 | 200 |

## 一、有上游对应、但类型标错的动作（当前为空 ✅）

没有 —— 种子的 `track_type` 与上游逐条一致。（这条曾经有 26 处，2026-09-29 修完。）

## 二、已复核确认（17 个）：上游同一个动作，字段可借

| 我们的 id | 我们的英文名 | 上游动作 | 上游器械 | 相似度 | 按上游补了什么 |
|---|---|---|---|---|---|
| `ex_bb_bench_press` | Barbell Bench Press | Bench Press | Barbell | 0.67 | （已一致，无需补） |
| `ex_bb_decline_bench_press` | Decline Barbell Bench Press | Decline Bench Press | Barbell | 0.75 | （已一致，无需补） |
| `ex_bb_incline_bench_press` | Incline Barbell Bench Press | Incline Bench Press | Barbell | 0.75 | （已一致，无需补） |
| `ex_bb_squat` | Barbell Back Squat | Squat | Barbell | 0.33 | （已一致，无需补） |
| `ex_db_front_raise` | Dumbbell Front Raise | Front Raise | Dumbbell | 0.67 | （已一致，无需补） |
| `ex_db_lateral_raise` | Dumbbell Lateral Raise | Lateral Raise | Dumbbell | 0.67 | （已一致，无需补） |
| `ex_db_shoulder_press` | Dumbbell Shoulder Press | Dumbbell Seated Shoulder Press | Dumbbell | 0.75 | （已一致，无需补） |
| `ex_hip_abduction` | Hip Abduction | Hip Abduction Machine | Machine | 0.67 | （已一致，无需补） |
| `ex_hip_adduction` | Hip Adduction | Hip Adduction Machine | Machine | 0.67 | （已一致，无需补） |
| `ex_hip_thrust` | Barbell Hip Thrust | Hip Thrust | Barbell | 0.67 | （已一致，无需补） |
| `ex_machine_chest_press` | Chest Press Machine | Machine Chest Press | Machine | 1.00 | （已一致，无需补） |
| `ex_machine_pec_deck` | Pec Deck Fly | Pec Deck | Machine | 0.67 | （已一致，无需补） |
| `ex_machine_row` | Seated Row Machine | Machine Row | Machine | 0.67 | （已一致，无需补） |
| `ex_overhead_cable_extension` | Overhead Cable Extension | Overhead Tricep Extension | Cable | 0.50 | （已一致，无需补） |
| `ex_overhead_db_extension` | Overhead Dumbbell Extension | Dumbbell Overhead Tricep Extension | Dumbbell | 0.75 | （已一致，无需补） |
| `ex_reverse_bb_curl` | Reverse Barbell Curl | Reverse Curl | Barbell | 0.67 | （已一致，无需补） |
| `ex_straight_bar_pushdown` | Straight-Bar Pushdown | Tricep Pushdown | Cable | 0.25 | （已一致，无需补） |

> **绝大多数「已一致」是有意义的结论，不是空转**：它们的 `track_type` 与 `equipment`
> 本来就对 —— 类型词表能表达的维度，在第 26 处修正时已经全部对齐。

## 三、已复核：命名相近但动作不同（39 个，不再重新纠结）

| 我们的 id | 我们的英文名 | 曾被误指的上游动作 | 为什么不是同一个 |
|---|---|---|---|
| `ex_bb_front_raise` | Barbell Front Raise | Front Raise | 上游器械是 Dumbbell，我们是 Barbell |
| `ex_bent_over_cable_fly` | Bent-Over Cable Fly | Cable Fly | 器械或姿态不同 |
| `ex_box_squat` | Box Squat | Squat | 器械或姿态不同 |
| `ex_cable_hammer_curl` | Cable Hammer Curl | Hammer Curl | 锤式与普通 Cable Curl 不同 |
| `ex_cable_reverse_curl` | Cable Reverse Curl | Cable Curl | 反握与普通 Cable Curl 不同 |
| `ex_cable_side_bend` | Cable Side Bend | Dumbbell Side Bend | 器械或姿态不同 |
| `ex_close_grip_smith` | Close-Grip Smith Press | Close-Grip Bench Press | 存在 close-grip 限定差异 |
| `ex_db_alternating_curl` | Alternating Dumbbell Curl | Incline Dumbbell Curl | 器械或姿态不同 |
| `ex_db_close_grip_press` | Close-Grip Dumbbell Press | Close-Grip Bench Press | 剩余项：命名相近但动作不同（复核第二节） |
| `ex_db_curl` | Dumbbell Curl | Incline Dumbbell Curl | 上斜/器械变体不同 |
| `ex_db_incline_fly` | Incline Dumbbell Fly | Dumbbell Fly | 上斜/器械变体不同 |
| `ex_hanging_side_leg_raise` | Hanging Side Leg Raise | Hanging Leg Raise | 侧举腿 vs 直腿举腿 |
| `ex_incline_hammer_curl` | Incline Hammer Curl | Hammer Curl | 上斜/器械变体不同 |
| `ex_lean_away_lateral` | Lean-Away Lateral Raise | Lateral Raise | 器械或姿态不同 |
| `ex_machine_crunch` | Machine Crunch | Crunch | 器械或姿态不同 |
| `ex_machine_hip_thrust` | Machine Hip Thrust | Smith Machine Hip Thrust | 器械不同（Machine vs Smith Machine） |
| `ex_machine_incline_press` | Incline Chest Press Machine | Machine Chest Press | 角度不同（上斜 vs 平） |
| `ex_pause_squat` | Pause Squat | Squat | 存在 pause 限定差异 |
| `ex_reverse_grip_bb_row` | Reverse-Grip Barbell Row | Barbell Row | 存在 reverse-grip 限定差异 |
| `ex_reverse_grip_pulldown` | Reverse-Grip Lat Pulldown | Close-Grip Lat Pulldown | 存在 reverse-grip 限定差异 |
| `ex_reverse_wrist_curl` | Reverse Wrist Curl | Reverse Curl | 腕弯举与普通弯举不同 |
| `ex_side_crunch` | Side Crunch | Crunch | 器械或姿态不同 |
| `ex_single_arm_cable_front` | Single-Arm Cable Front Raise | Cable Front Raise | 存在 single-arm 限定差异 |
| `ex_single_arm_cable_lateral` | Single-Arm Cable Lateral Raise | Cable Lateral Raise | 存在 single-arm 限定差异 |
| `ex_single_arm_db_press` | One-Arm Dumbbell Press | One-Arm Dumbbell Row | 存在 single-arm 限定差异 |
| `ex_single_arm_machine_row` | Single-Arm Machine Row | Single-Arm Cable Row | 存在 single-arm 限定差异 |
| `ex_single_arm_overhead_cable` | Single-Arm Overhead Cable Extension | Single-Arm Cable Row | 存在 single-arm 限定差异 |
| `ex_single_arm_pulldown` | Single-Arm Lat Pulldown | Lat Pulldown | 存在 single-arm 限定差异 |
| `ex_single_leg_extension` | Single-Leg Extension | Leg Extension | 剩余项：命名相近但动作不同（复核第二节） |
| `ex_single_leg_press` | Single-Leg Press | Leg Press | 剩余项：命名相近但动作不同（复核第二节） |
| `ex_sit_up` | Sit-up | Decline Sit-Up | 角度不同（vs Decline Sit-Up） |
| `ex_smith_calf_raise` | Smith Machine Calf Raise | Calf Raise | 器械或姿态不同 |
| `ex_smith_incline_press` | Smith Machine Incline Press | Smith Machine Bench Press | 剩余项：命名相近但动作不同（复核第二节） |
| `ex_smith_lateral_raise` | Smith Machine Lateral Raise | Machine Lateral Raise | 史密斯 vs 普通器械 |
| `ex_smith_shoulder_press` | Smith Machine Shoulder Press | Machine Shoulder Press | 史密斯 vs 普通器械 |
| `ex_two_arm_db_row` | Two-Arm Dumbbell Row | One-Arm Dumbbell Row | 剩余项：命名相近但动作不同（复核第二节） |
| `ex_weighted_glute_bridge` | Weighted Glute Bridge | Glute Bridge | 存在 weighted 限定差异 |
| `ex_weighted_plank` | Weighted Plank | Plank | 器械或姿态不同 |
| `ex_wide_t_bar_row` | Wide-Grip T-Bar Row | T-Bar Row | 剩余项：命名相近但动作不同（复核第二节） |

## 四、待人工复核的候选：**已清空 ✅**

相似度 ≥ 0.5 的候选已全部被复核过（确认或否掉）。

## 五、仍需决策的两件事（工具算出来的，等人拍板）

### 5.1 上游提到、我们词表里没有的次肌群标签（3 个标签）

这些标签上游在用、我们的 21 值词表里没有。**补它们要先决定扩不扩词表** ——
扩了以后 `docs/data-model.md` 与 `app/lib/core/labels.dart` 都要跟着改。

| 上游标签 | 涉及我们的动作数 | 例 |
|---|---|---|
| `chest` | 6 | `ex_weighted_dip` `ex_handstand_push_up` `ex_cable_front_raise` `ex_close_grip_bench` |
| `upper_back` | 5 | `ex_cable_lateral_raise` `ex_machine_lateral_raise` `ex_reverse_pec_deck` `ex_upright_row` |
| `grip` | 3 | `ex_deadlift` `ex_hanging_leg_raise` `ex_hanging_knee_raise` |

### 5.2 主肌群归类与上游不一致（5 个）

**改这些会改变"今天练什么"的部位轮转**（部位轮转按 `muscle_group` 走），所以是产品决策：

| 我们的 id | 我们 | 上游 primaryMuscle | 按映射会归到 |
|---|---|---|---|
| `ex_back_extension` | core | Lower Back | back |
| `ex_chin_up` | back | Biceps | arms |
| `ex_deadlift` | back | Posterior Chain | legs |
| `ex_sumo_deadlift` | back | Posterior Chain | legs |
| `ex_weighted_dip` | chest | Triceps | arms |

## 六、次肌群对齐情况（还差 0 个动作 / 0 个标签）

这是一份**实时差异**：上游 `secondaryMuscles` 列出、而我们没有的标签 ——
只统计"我们词表里已经有、只是没打在这个动作上"的那部分（需要新词表的见 5.1）。

**当前为 0：已对齐。** 上游列出的次肌群，要么我们本来就有，要么是词表缺值（5.1）。

> 2026-09-29 这一轮补了 51 个动作 / 59 个标签（**纯增量**，我们更细的标签如
> `front_delts` 一律保留），过程记在 `CHANGELOG.md`。之后每改种子都重新算一次，
> 有差异就会出现在下表里。

## 七、上游有、我们没有（可选补库）

| 上游类型 | 数量 | 例 |
|---|---|---|
| `bodyweight_reps` | 90 | Dip, Neutral-Grip Pull-up, Nordic Hamstring Curl, Glute-Focused Back Extension, Reverse Hyperextension, Jump Squat |
| `weight_reps` | 62 | Cable Fly, Weighted Push-up, Rear Delt Fly, Dumbbell Bent Over Row, Step-Up, Leg Curl |
| `duration` | 36 | Stair Climber, Wall Sit, Cable Pallof Hold, Elliptical, Jump Rope, Battle Ropes |
| `distance_duration` | 10 | Running, Walking, Cycling, Rowing, Farmer Carry, Swimming |
| `assisted_bodyweight` | 2 | Assisted Dip, Assisted Chin-up |

其中 **14 个是拉伸动作**（上游 `isStretch: true`）—— 我们种子里一个都没有：

> Cat-Cow Stretch, Arm Circles, World's Greatest Stretch, Leg Swings, Torso Twists, Doorway Chest Stretch, Child's Pose, Kneeling Hip Flexor Stretch, Hamstring Stretch, Standing Quad Stretch, Seated Forward Fold, Cross-Body Shoulder Stretch, Wall Calf Stretch, Butterfly Stretch

---

## 八、改完之后怎么跑

```bash
node tool/map-upstream.mjs            # 改了种子或复核结论之后重新生成本文
node tool/map-upstream.mjs --check    # verify.sh 第 1 层会跑：过期就红
```

复核结论写在 `seed/upstream-confirmed.json`：确认项进 `confirmed`，否掉项进 `rejected`（带理由）。
写错 id 或上游名会**直接报错退出**，不会静静什么都不发生。
