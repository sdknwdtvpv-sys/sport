# 上游动作库映射（待人工复核）

> **这不是结论，是一张给人过的候选表。** 工具只给候选与相似度；
> `Romanian Deadlift` 与 `Deadlift` 名字极近但是两个动作 —— 自动接受这类猜测
> 等于往动作库里灌错数据，而动作库是产品资产。
>
> 由 `node tool/map-upstream.mjs` 生成，输入是 `seed/upstream-workout-guide.json`
> （上游 `bryllim/workout-guide` @ `aac59922` 的元数据快照，MIT，不含插画）。

## 总览

| 项 | 数量 |
|---|---|
| 我们的动作 | 165 |
| 上游动作 | 302 |
| **英文名精确命中** | **85**（52%） |
| 未命中：疑似只是命名不同（相似度 ≥ 0.5） | 54 |
| 未命中：疑似真的没有对应（< 0.5） | 26 |
| 上游有、我们没有 | 217 |

## 一、已命中、但类型标错的动作（可直接改，有上游依据）

（没有 —— 种子的 `track_type` 与上游一致）

## 二、未命中：候选映射（相似度 ≥ 0.5，**待人工确认**）

| 我们的 id | 中文名 | 英文名 | 最相近的上游动作 | 相似度 | 上游类型 | 上游器械 |
|---|---|---|---|---|---|---|
| `ex_machine_chest_press` | 器械推胸 | Chest Press Machine | Machine Chest Press | 1.00 | `weight_reps` | Machine |
| `ex_bb_decline_bench_press` | 下斜杠铃卧推 | Decline Barbell Bench Press | Decline Bench Press | 0.75 | `weight_reps` | Barbell |
| `ex_bb_incline_bench_press` | 上斜杠铃卧推 | Incline Barbell Bench Press | Incline Bench Press | 0.75 | `weight_reps` | Barbell |
| `ex_db_shoulder_press` | 哑铃推举 | Dumbbell Shoulder Press | Dumbbell Seated Shoulder Press | 0.75 | `weight_reps` | Dumbbell |
| `ex_hanging_side_leg_raise` | 悬垂侧举腿 | Hanging Side Leg Raise | Hanging Leg Raise | 0.75 | `bodyweight_reps` | Bodyweight |
| `ex_machine_hip_thrust` | 器械臀推 | Machine Hip Thrust | Smith Machine Hip Thrust | 0.75 | `weight_reps` | Machine |
| `ex_machine_incline_press` | 上斜器械推胸 | Incline Chest Press Machine | Machine Chest Press | 0.75 | `weight_reps` | Machine |
| `ex_overhead_db_extension` | 哑铃颈后臂屈伸 | Overhead Dumbbell Extension | Dumbbell Overhead Tricep Extension | 0.75 | `weight_reps` | Dumbbell |
| `ex_smith_lateral_raise` | 史密斯侧平举 | Smith Machine Lateral Raise | Machine Lateral Raise | 0.75 | `weight_reps` | Machine |
| `ex_smith_shoulder_press` | 史密斯推举 | Smith Machine Shoulder Press | Machine Shoulder Press | 0.75 | `weight_reps` | Machine |
| `ex_bb_bench_press` | 杠铃卧推 | Barbell Bench Press | Bench Press | 0.67 | `weight_reps` | Barbell |
| `ex_bb_front_raise` | 杠铃前平举 | Barbell Front Raise | Front Raise | 0.67 | `weight_reps` | Dumbbell |
| `ex_cable_hammer_curl` | 绳索锤式弯举 | Cable Hammer Curl | Cable Curl | 0.67 | `weight_reps` | Cable |
| `ex_cable_reverse_curl` | 绳索反握弯举 | Cable Reverse Curl | Cable Curl | 0.67 | `weight_reps` | Cable |
| `ex_db_curl` | 哑铃弯举 | Dumbbell Curl | Incline Dumbbell Curl | 0.67 | `weight_reps` | Dumbbell |
| `ex_db_front_raise` | 哑铃前平举 | Dumbbell Front Raise | Front Raise | 0.67 | `weight_reps` | Dumbbell |
| `ex_db_incline_fly` | 上斜哑铃飞鸟 | Incline Dumbbell Fly | Dumbbell Fly | 0.67 | `weight_reps` | Dumbbell |
| `ex_db_lateral_raise` | 哑铃侧平举 | Dumbbell Lateral Raise | Lateral Raise | 0.67 | `weight_reps` | Dumbbell |
| `ex_hip_abduction` | 髋外展 | Hip Abduction | Hip Abduction Machine | 0.67 | `weight_reps` | Machine |
| `ex_hip_adduction` | 髋内收 | Hip Adduction | Hip Adduction Machine | 0.67 | `weight_reps` | Machine |
| `ex_hip_thrust` | 臀推 | Barbell Hip Thrust | Hip Thrust | 0.67 | `weight_reps` | Barbell |
| `ex_incline_hammer_curl` | 斜托锤式弯举 | Incline Hammer Curl | Hammer Curl | 0.67 | `weight_reps` | Dumbbell |
| `ex_machine_pec_deck` | 蝴蝶机夹胸 | Pec Deck Fly | Pec Deck | 0.67 | `weight_reps` | Machine |
| `ex_machine_row` | 器械划船 | Seated Row Machine | Machine Row | 0.67 | `weight_reps` | Machine |
| `ex_reverse_bb_curl` | 反握杠铃弯举 | Reverse Barbell Curl | Reverse Curl | 0.67 | `weight_reps` | Barbell |
| `ex_reverse_wrist_curl` | 反向腕弯举 | Reverse Wrist Curl | Reverse Curl | 0.67 | `weight_reps` | Barbell |
| `ex_single_leg_extension` | 单腿腿屈伸 | Single-Leg Extension | Leg Extension | 0.67 | `weight_reps` | Machine |
| `ex_single_leg_press` | 单腿腿举 | Single-Leg Press | Leg Press | 0.67 | `weight_reps` | Machine |
| `ex_sit_up` | 仰卧起坐 | Sit-up | Decline Sit-Up | 0.67 | `bodyweight_reps` | Bench |
| `ex_weighted_glute_bridge` | 负重臀桥 | Weighted Glute Bridge | Glute Bridge | 0.67 | `bodyweight_reps` | Bodyweight |
| `ex_close_grip_smith` | 窄握史密斯卧推 | Close-Grip Smith Press | Close-Grip Bench Press | 0.60 | `weight_reps` | Barbell |
| `ex_db_close_grip_press` | 窄距哑铃卧推 | Close-Grip Dumbbell Press | Close-Grip Bench Press | 0.60 | `weight_reps` | Barbell |
| `ex_reverse_grip_pulldown` | 反握高位下拉 | Reverse-Grip Lat Pulldown | Close-Grip Lat Pulldown | 0.60 | `weight_reps` | Cable |
| `ex_single_arm_cable_front` | 单臂绳索前平举 | Single-Arm Cable Front Raise | Cable Front Raise | 0.60 | `weight_reps` | Cable |
| `ex_single_arm_cable_lateral` | 单臂绳索侧平举 | Single-Arm Cable Lateral Raise | Cable Lateral Raise | 0.60 | `weight_reps` | Cable |
| `ex_single_arm_db_press` | 单臂哑铃推举 | One-Arm Dumbbell Press | One-Arm Dumbbell Row | 0.60 | `weight_reps` | Dumbbell |
| `ex_single_arm_machine_row` | 单臂器械划船 | Single-Arm Machine Row | Single-Arm Cable Row | 0.60 | `weight_reps` | Cable |
| `ex_smith_incline_press` | 史密斯上斜卧推 | Smith Machine Incline Press | Smith Machine Bench Press | 0.60 | `weight_reps` | Machine |
| `ex_two_arm_db_row` | 双臂哑铃划船 | Two-Arm Dumbbell Row | One-Arm Dumbbell Row | 0.60 | `weight_reps` | Dumbbell |
| `ex_wide_t_bar_row` | 宽握T杠划船 | Wide-Grip T-Bar Row | T-Bar Row | 0.60 | `weight_reps` | Machine |
| `ex_bent_over_cable_fly` | 俯身绳索飞鸟 | Bent-Over Cable Fly | Cable Fly | 0.50 | `weight_reps` | Cable |
| `ex_box_squat` | 箱式深蹲 | Box Squat | Single-Leg Box Squat | 0.50 | `bodyweight_reps` | Box |
| `ex_cable_side_bend` | 绳索侧屈 | Cable Side Bend | Dumbbell Side Bend | 0.50 | `weight_reps` | Dumbbell |
| `ex_db_alternating_curl` | 哑铃交替弯举 | Alternating Dumbbell Curl | Incline Dumbbell Curl | 0.50 | `weight_reps` | Dumbbell |
| `ex_lean_away_lateral` | 斜托侧平举 | Lean-Away Lateral Raise | Lateral Raise | 0.50 | `weight_reps` | Dumbbell |
| `ex_machine_crunch` | 器械卷腹 | Machine Crunch | Crunch | 0.50 | `bodyweight_reps` | Bodyweight |
| `ex_overhead_cable_extension` | 绳索过顶臂屈伸 | Overhead Cable Extension | Overhead Tricep Extension | 0.50 | `weight_reps` | Cable |
| `ex_pause_squat` | 暂停深蹲 | Pause Squat | Squat | 0.50 | `weight_reps` | Barbell |
| `ex_reverse_grip_bb_row` | 反握杠铃划船 | Reverse-Grip Barbell Row | Barbell Row | 0.50 | `weight_reps` | Barbell |
| `ex_side_crunch` | 侧卷腹 | Side Crunch | Crunch | 0.50 | `bodyweight_reps` | Bodyweight |
| `ex_single_arm_overhead_cable` | 单臂绳索过顶臂屈伸 | Single-Arm Overhead Cable Extension | Single-Arm Cable Row | 0.50 | `weight_reps` | Cable |
| `ex_single_arm_pulldown` | 单臂高位下拉 | Single-Arm Lat Pulldown | Lat Pulldown | 0.50 | `weight_reps` | Cable |
| `ex_smith_calf_raise` | 史密斯提踵 | Smith Machine Calf Raise | Calf Raise | 0.50 | `bodyweight_reps` | Bodyweight |
| `ex_weighted_plank` | 负重平板支撑 | Weighted Plank | Plank | 0.50 | `duration` | Bodyweight |

## 三、未命中且相似度低（< 0.5）—— 很可能上游真没有

这些动作**我们自己维护**：上游没有对应，也就没有类型/器械/肌群可借。

| 我们的 id | 中文名 | 英文名 | 最近的候选（若有） | 相似度 |
|---|---|---|---|---|
| `ex_bb_curl` | 杠铃弯举 | Barbell Curl | Barbell Row | 0.33 |
| `ex_bb_floor_press` | 地板卧推 | Barbell Floor Press | Arnold Press | 0.25 |
| `ex_bb_lunge` | 杠铃箭步蹲 | Barbell Lunge | Barbell Row | 0.33 |
| `ex_bb_squat` | 杠铃深蹲 | Barbell Back Squat | Squat | 0.33 |
| `ex_bent_over_db_fly` | 俯身哑铃飞鸟 | Bent-Over Reverse Fly | Dumbbell Bent Over Row | 0.33 |
| `ex_cable_crossover` | 绳索夹胸 | Cable Crossover | Cable Crunch | 0.33 |
| `ex_cable_high_fly` | 高位绳索夹胸 | High Cable Crossover | Cable Crunch | 0.25 |
| `ex_cable_low_fly` | 低位绳索夹胸 | Low Cable Crossover | Cable Crunch | 0.25 |
| `ex_cable_pushdown` | 绳索下压 | Cable Triceps Pushdown | Cable Crunch | 0.25 |
| `ex_db_pullover` | 哑铃仰卧屈臂上拉 | Dumbbell Pullover | Dumbbell Fly | 0.33 |
| `ex_db_swissball_press` | 瑞士球哑铃卧推 | Swiss Ball Dumbbell Press | Decline Dumbbell Press | 0.40 |
| `ex_farmer_walk` | 农夫行走 | Farmer's Walk | Crab Walk | 0.25 |
| `ex_heel_touch` | 仰卧交替触踝 | Heel Touch | Heel Tap | 0.33 |
| `ex_machine_curl` | 器械弯举 | Machine Curl | Bicep Curl | 0.33 |
| `ex_machine_single_chest_press` | 单臂器械推胸 | Single-Arm Chest Press | Machine Chest Press | 0.40 |
| `ex_machine_triceps_extension` | 器械臂屈伸 | Machine Triceps Extension | Back Extension | 0.25 |
| `ex_reverse_grip_pushdown` | 反握下压 | Reverse-Grip Pushdown | Reverse Crunch | 0.25 |
| `ex_seated_bb_press` | 坐姿杠铃推举 | Seated Barbell Press | Dumbbell Seated Shoulder Press | 0.40 |
| `ex_single_arm_pushdown` | 单臂绳索下压 | Single-Arm Pushdown | Single-Arm Cable Row | 0.40 |
| `ex_single_leg_rdl` | 单腿罗马尼亚硬拉 | Single-Leg RDL | Single-Leg Box Squat | 0.40 |
| `ex_static_lunge` | 静态分腿蹲 | Static Lunge | Curtsy Lunge | 0.33 |
| `ex_stiff_leg_deadlift` | 直腿硬拉 | Stiff-Leg Deadlift | Single-Leg Romanian Deadlift | 0.40 |
| `ex_straight_bar_pushdown` | 直杆下压 | Straight-Bar Pushdown | Tricep Pushdown | 0.25 |
| `ex_triceps_kickback` | 哑铃俯身臂屈伸 | Triceps Kickback | Banded Kickback | 0.33 |
| `ex_wide_cable_row` | 宽握坐姿划船 | Wide-Grip Cable Row | Seated Cable Row | 0.40 |
| `ex_zottman_curl` | 佐特曼弯举 | Zottman Curl | Bicep Curl | 0.33 |

## 四、上游有、我们没有（可选补库）

| 上游类型 | 数量 | 例 |
|---|---|---|
| `bodyweight_reps` | 90 | Dip, Neutral-Grip Pull-up, Nordic Hamstring Curl, Glute-Focused Back Extension, Reverse Hyperextension, Jump Squat |
| `weight_reps` | 79 | Bench Press, Incline Bench Press, Decline Bench Press, Machine Chest Press, Pec Deck, Cable Fly |
| `duration` | 36 | Stair Climber, Wall Sit, Cable Pallof Hold, Elliptical, Jump Rope, Battle Ropes |
| `distance_duration` | 10 | Running, Walking, Cycling, Rowing, Farmer Carry, Swimming |
| `assisted_bodyweight` | 2 | Assisted Dip, Assisted Chin-up |

其中 **14 个是拉伸动作**（上游 `isStretch: true`）—— 我们种子里一个都没有：

> Cat-Cow Stretch, Arm Circles, World's Greatest Stretch, Leg Swings, Torso Twists, Doorway Chest Stretch, Child's Pose, Kneeling Hip Flexor Stretch, Hamstring Stretch, Standing Quad Stretch, Seated Forward Fold, Cross-Body Shoulder Stretch, Wall Calf Stretch, Butterfly Stretch

---

## 五、复核完之后怎么用

1. **第一节**可以直接改种子（有上游依据，不需要人判断）：改 `seed/parts/*.json` 的 `track_type`。
2. **第二节**逐行确认 → 确认后可以借上游的 `exerciseType` / `equipment` / `primaryMuscle` 补我们缺的字段；
   不确认就留在表里，别猜。
3. **第三节**说明这些动作得自己维护（上游帮不上）。
4. **第四节**是"要不要补库"的产品决策：有氧与拉伸目前是整块空白。
