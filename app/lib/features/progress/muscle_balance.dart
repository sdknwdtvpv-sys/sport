/// 练了么 · **部位平衡提示**（第二部分第 5 条，2026-10-06 用户拍板）
///
/// 首页一行：「这周胸 3 次、腿 0 次」。
///
/// 为什么值得占首页一行：练了么不做计划也能用，于是**最真实的风险不是"练得少"，
/// 而是"只练爱练的那几个部位"**（卧推/弯举练到飞起，腿和背一次不碰）。
/// 这一句是产品里唯一会指出这件事的地方 —— 它必须**只陈述事实**，
/// 不喊口号、不打分、不推送。
///
/// 口径（三条，都有理由）：
///   * **只数本周**（周一起算，与每周挑战、周报、计划屏同一个"一周"的定义）；
///   * 只数**六大主部位**（胸 / 背 / 腿 / 肩 / 手臂 / 核心）——
///     辅助肌群（肱三头、臀中肌…）会把同一组算进好几个部位，那就成了一笔糊涂账；
///   * 一条记录算它**主部位**的一次（`SetRecord.exerciseId` → 动作表的主部位）。
///
/// ⚠️ 部位表**由调用方传进来**（`exerciseId → muscleGroup`）：与 `badges.dart` 同一条规矩 ——
/// 纯函数不查库，测试就能直接打它，界面那边只负责把表查出来。
library;

import '../../core/labels.dart';
import '../../domain/models.dart';
import 'weekly_challenge.dart';

/// 六大主部位（顺序固定：这个顺序会被写进那一行文案）。
const List<String> kMainMuscleGroups = <String>[
  'chest',
  'back',
  'legs',
  'shoulders',
  'arms',
  'core',
];

/// 本周各主部位练了几次。**没练过的部位是 0，不是"不存在"** ——
/// 那一行文案要的正是"某个部位 0 次"。
Map<String, int> weeklyMuscleCounts({
  required List<SetRecord> sets,
  required Map<String, String> muscleOf,
  required DateTime day,
}) {
  final ({DateTime start, DateTime end}) w = weekBounds(day);
  final Map<String, int> out = <String, int>{
    for (final String g in kMainMuscleGroups) g: 0,
  };
  for (final SetRecord s in sets) {
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(s.completedAtMs);
    if (t.isBefore(w.start) || !t.isBefore(w.end)) continue;
    final String? g = muscleOf[s.exerciseId];
    if (g == null || !out.containsKey(g)) continue; // 辅助肌群 / 未知动作：不参与这行话
    out[g] = out[g]! + 1;
  }
  return out;
}

/// 本周练到的那几个动作 → 它们的主部位。
///
/// **只查本周练过的动作**（一次训练几个动作，一周最多几十次查询）——
/// 不要为了一行提示去把动作库全表读一遍。
Future<Map<String, String>> muscleMapForWeek({
  required List<SetRecord> sets,
  required Future<String?> Function(String exerciseId) muscleOfId,
  required DateTime day,
}) async {
  final ({DateTime start, DateTime end}) w = weekBounds(day);
  final Set<String> ids = <String>{};
  for (final SetRecord s in sets) {
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(s.completedAtMs);
    if (t.isBefore(w.start) || !t.isBefore(w.end)) continue;
    ids.add(s.exerciseId);
  }
  final Map<String, String> out = <String, String>{};
  for (final String id in ids) {
    final String? g = await muscleOfId(id);
    if (g != null) out[id] = g;
  }
  return out;
}

/// 首页那一行。**没有值得说的事就返回 null**（那一行不出现）。
///
/// 什么算"值得说"：
///   * **有部位一次没练**（这是最要紧的那种不平衡）；
///   * 或者某部位**明显偏多**（≥ 3 次，且是练得最多的那个）。
///
/// 反过来，若本周练得又少又匀（比如胸 1、背 1），那**没什么可说的** ——
/// 硬凑一句"你的部位很均衡"只会变成噪音，而首页每一行都该有它的理由。
({String text, String? worst, String? most})? muscleBalanceHint({
  required List<SetRecord> sets,
  required Map<String, String> muscleOf,
  required DateTime day,
}) {
  final Map<String, int> counts = weeklyMuscleCounts(
      sets: sets, muscleOf: muscleOf, day: day);
  final int total = counts.values.fold(0, (int a, int b) => a + b);
  if (total == 0) return null; // 本周一次都没练：那该说的是"练一次"，不是"部位不均"

  // 练得最多的（并列时按 kMainMuscleGroups 的固定顺序取第一个 —— 不许随 Map 顺序抖）
  String most = kMainMuscleGroups.first;
  for (final String g in kMainMuscleGroups) {
    if (counts[g]! > counts[most]!) most = g;
  }
  final List<String> zero = <String>[
    for (final String g in kMainMuscleGroups)
      if (counts[g] == 0) g,
  ];

  if (zero.isNotEmpty) {
    // 先说"最多"，再说"一次没练" —— 顺序不能反：先肯定已有的，再指出缺口
    final String head = counts[most]! >= 2
        ? '这周${muscleLabel(most)} ${counts[most]} 次'
        : '这周练了 $total 组';
    final String tail = zero.length == 1
        ? '${muscleLabel(zero.first)}还是 0 次'
        : '${zero.map(muscleLabel).join('、')}还是 0 次';
    return (text: '$head、$tail', worst: zero.first, most: most);
  }

  if (counts[most]! >= 3) {
    return (
      text: '这周${muscleLabel(most)} ${counts[most]} 次，'
          '其他部位也练到了',
      worst: null,
      most: most,
    );
  }
  return null; // 练得不多但很匀 —— 没什么可说的
}
