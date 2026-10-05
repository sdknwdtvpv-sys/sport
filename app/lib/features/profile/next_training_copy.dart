/// 练了么 · 「训练结束」那条提醒的**文案**（2026-10-05，纯函数、可测）
///
/// 为什么单独一个文件：这句话要在**总结页排程时**算出来并塞进通知里
/// （`docs/feature-backlog.md` §〇 第 6 条的施工清单）。文案与"什么时候排"分开 ——
/// 平台侧只负责到点响，怎么说人话在这一层，于是它能被普通单测钉住。
///
/// 三条口径：
///   * **没有下次部位就别编**（用户还没练过、或轮转算不出）→ 返回 null，调用方不排这条；
///   * **不催**：措辞是"明天该练背了"，不是"你今天还没练"——后者是训练提醒那条的活，
///     两条通知各管一件事，文案不许混；
///   * 只带**一个**动作提示词（"点开直接开始"），不写具体动作清单 ——
///     排程时算出来的清单到明天可能已经过期（用户明天可能改了计划）。
library;

import '../../core/labels.dart';

/// 训练结束时那条提醒的标题与正文。null = 这次不排（见上面第 1 条）。
(String title, String body)? nextTrainingReminderCopy(String? nextMuscleKey) {
  if (nextMuscleKey == null || nextMuscleKey.isEmpty) return null;
  final String muscle = muscleLabel(nextMuscleKey);
  if (muscle.isEmpty) return null;
  return ('明天该练$muscle了', '点开直接开始 · 已经按你的习惯排好');
}
