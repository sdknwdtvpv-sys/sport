/// 练了么 · S13 首次引导的规则
///
/// **这一版是"非阻塞"的**：不拦启动、不影响 S1 的「点一下就能进 S3」。
/// 入口是 S1 空态里的一个可选链接「帮我定个计划」—— 见 `docs/screens.md`。
///
/// 起因是规格自己矛盾：S13 表要求「≤ 3 步：目标 → 每周几天 → 生成第一份计划」，
/// 而同一份文档的 S1 写着「无引导页……点一下就能进 S3」，
/// 总判据又是「它能否让"第一次训练"更快发生？不能的，一期都不做」。
/// 把引导做成"可选、且以开始训练收尾"，两边就都成立了。
///
/// 这里的映射规则是**经验值**，不是什么精确科学 —— 生成出来只是起点，
/// 用户可以在 S11 的计划模板里逐项改。
library;

import '../../domain/models.dart';

/// 训练目标。wire 值与 `docs/data-model.md` 的 `user_profile.goal` 一致。
enum TrainingGoal {
  hypertrophy('hypertrophy', '增肌'),
  strength('strength', '力量'),
  fatLoss('fat_loss', '减脂'),
  maintain('maintain', '保持');

  const TrainingGoal(this.wire, this.label);

  final String wire;
  final String label;

  static TrainingGoal? fromWire(String? w) {
    for (final TrainingGoal g in TrainingGoal.values) {
      if (g.wire == w) return g;
    }
    return null;
  }
}

/// 目标 → 处方（组数 + 次数区间）。
///
/// 经验值：增肌走中等重量多次数，力量走大重量少次数，
/// 减脂走轻重量高次数（组间休息短），保持走中庸。
PlanTarget planForGoal(TrainingGoal goal) => switch (goal) {
      TrainingGoal.hypertrophy => const PlanTarget(
          targetSets: 4, targetRepsLow: 8, targetRepsHigh: 12),
      TrainingGoal.strength => const PlanTarget(
          targetSets: 5, targetRepsLow: 3, targetRepsHigh: 5),
      TrainingGoal.fatLoss => const PlanTarget(
          targetSets: 3, targetRepsLow: 12, targetRepsHigh: 15),
      TrainingGoal.maintain => const PlanTarget(
          targetSets: 3, targetRepsLow: 8, targetRepsHigh: 10),
    };

/// 一周练几天 → 一次练几个动作。
///
/// 逻辑：**一周练得越少，每次要覆盖的部位越多**。
/// 一周 2 天还只练 3 个动作，剩下的部位整周都轮不到。
int exercisesPerSession(int daysPerWeek) {
  if (daysPerWeek <= 3) return 6;
  if (daysPerWeek == 4) return 5;
  return 4;
}

/// 一周可选的训练天数。上限 6：留一天休息比练满 7 天更可持续。
const List<int> kDaysChoices = <int>[2, 3, 4, 5, 6];

/// 生成的第一份计划叫什么名字。
String planNameFor(TrainingGoal goal) => '我的${goal.label}计划';

/// 频率的说明文字，让用户知道这个数字被拿去做什么了。
String daysHint(int daysPerWeek) {
  final int n = exercisesPerSession(daysPerWeek);
  return '一周 $daysPerWeek 天 → 每次安排 $n 个动作，尽量覆盖不同部位';
}
