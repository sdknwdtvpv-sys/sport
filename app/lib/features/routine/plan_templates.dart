/// 练了么 · **内置计划模板**（S11 的"给不知道怎么搭计划的人一个起点"）
///
/// **为什么要有它**（2026-10-01）：`routine.source` 从第一天起就留着
/// `builtin / suggested` 两个取值没人用（见 `routine_repository.dart` 的老注释），
/// 于是"计划模板"这条线一直只有**用户自己一条一条建**这一种路径。
/// 而北极星是「首次打开 → 完成第一次训练」——**让新手自己搭一份计划，是最贵的门槛**。
///
/// 三条口径：
///   * **模板只是起点，不是课程**：用模板建出来的是**普通计划**（可改可删，`source='builtin'`
///     只用来记"它从哪来"），不是一份跟着走 12 周的东西；
///   * **动作与处方都写死在这里、并且有测试对着种子核**（id 必须真的存在、组数/次数区间必须合理）——
///     写错一个 id 的后果是"点进去少一个动作"，而没人会去数；
///   * **覆盖面优先于精巧**：5 套模板覆盖"全身 / 上下肢 / 推拉腿 / 30 分钟"这几种最常见的落法，
///     每套 3–4 个动作 —— 计划太长反而没人用。
library;

import '../../domain/models.dart';

/// 一套内置模板：名字 + 一句人话说明 + 动作清单。
class PlanTemplate {
  const PlanTemplate({
    required this.id,
    required this.name,
    required this.note,
    required this.items,
  });

  /// 稳定 id（测试与界面 key 都用它）
  final String id;

  final String name;

  /// 一句话说明（界面上副标题那一行，也是"它适合谁"的答案）
  final String note;

  final List<PlanTemplateItem> items;
}

/// 模板里的一个动作：练哪个 + 什么处方。
class PlanTemplateItem {
  const PlanTemplateItem({
    required this.exerciseId,
    required this.sets,
    required this.repsLow,
    required this.repsHigh,
  });

  final String exerciseId;
  final int sets;
  final int repsLow;

  /// 次数上限；**按时长动作装的是秒**（与 `PlanTarget` 同一口径）
  final int repsHigh;
}

/// 五套内置模板。顺序就是界面上的顺序：从最容易上手到最分化。
const List<PlanTemplate> kPlanTemplates = <PlanTemplate>[
  PlanTemplate(
    id: 'full_body_starter',
    name: '全身入门',
    note: '第一次进健身房就用这套：三个大动作，每个 3 组',
    items: <PlanTemplateItem>[
      PlanTemplateItem(exerciseId: 'ex_bb_squat', sets: 3, repsLow: 5, repsHigh: 8),
      PlanTemplateItem(exerciseId: 'ex_bb_bench_press', sets: 3, repsLow: 8, repsHigh: 12),
      PlanTemplateItem(exerciseId: 'ex_bb_row', sets: 3, repsLow: 8, repsHigh: 12),
    ],
  ),
  PlanTemplate(
    id: 'upper_lower_lower',
    name: '上下肢 A · 下肢',
    note: '能一周练两次以上时用：腿 + 核心，深蹲打头',
    items: <PlanTemplateItem>[
      PlanTemplateItem(exerciseId: 'ex_bb_squat', sets: 4, repsLow: 5, repsHigh: 8),
      PlanTemplateItem(exerciseId: 'ex_rdl', sets: 3, repsLow: 8, repsHigh: 12),
      PlanTemplateItem(exerciseId: 'ex_bb_lunge', sets: 3, repsLow: 8, repsHigh: 12),
      PlanTemplateItem(exerciseId: 'ex_plank', sets: 3, repsLow: 30, repsHigh: 45),
    ],
  ),
  PlanTemplate(
    id: 'push_day',
    name: '推日',
    note: '分化训练的第一天：胸 / 肩 / 三头',
    items: <PlanTemplateItem>[
      PlanTemplateItem(exerciseId: 'ex_bb_bench_press', sets: 4, repsLow: 5, repsHigh: 8),
      PlanTemplateItem(exerciseId: 'ex_bb_incline_bench_press', sets: 3, repsLow: 8, repsHigh: 12),
      PlanTemplateItem(exerciseId: 'ex_db_shoulder_press', sets: 3, repsLow: 8, repsHigh: 12),
      PlanTemplateItem(exerciseId: 'ex_push_up', sets: 3, repsLow: 8, repsHigh: 15),
    ],
  ),
  PlanTemplate(
    id: 'pull_day',
    name: '拉日',
    note: '分化训练的第二天：背 / 二头',
    items: <PlanTemplateItem>[
      PlanTemplateItem(exerciseId: 'ex_deadlift', sets: 3, repsLow: 5, repsHigh: 5),
      PlanTemplateItem(exerciseId: 'ex_pull_up', sets: 3, repsLow: 5, repsHigh: 10),
      PlanTemplateItem(exerciseId: 'ex_seated_cable_row', sets: 3, repsLow: 8, repsHigh: 12),
      PlanTemplateItem(exerciseId: 'ex_db_curl', sets: 3, repsLow: 10, repsHigh: 15),
    ],
  ),
  PlanTemplate(
    id: 'quick_30',
    name: '30 分钟全身',
    note: '时间紧的时候用：一对哑铃 + 俯卧撑，20 分钟能走完',
    items: <PlanTemplateItem>[
      PlanTemplateItem(exerciseId: 'ex_goblet_squat', sets: 3, repsLow: 10, repsHigh: 15),
      PlanTemplateItem(exerciseId: 'ex_db_bench_press', sets: 3, repsLow: 8, repsHigh: 12),
      PlanTemplateItem(exerciseId: 'ex_lat_pulldown', sets: 3, repsLow: 8, repsHigh: 12),
      PlanTemplateItem(exerciseId: 'ex_push_up', sets: 3, repsLow: 8, repsHigh: 15),
    ],
  ),
];

/// 把一个模板项变成引擎/落库用的处方。
///
/// 为什么不让模板直接写 `PlanTarget`：模板只关心"几组、多少次"，
/// 重量与距离是**练的时候**由引擎按历史给的（写死重量等于替用户决定）。
PlanTarget planTargetOf(PlanTemplateItem item) => PlanTarget(
      targetSets: item.sets,
      targetRepsLow: item.repsLow,
      targetRepsHigh: item.repsHigh,
    );
