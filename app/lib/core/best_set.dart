/// 练了么 · 某个动作的「**历史最佳**」（2026-10-10，训练屏那条对照带的右半边）
///
/// **为什么要有它**：用户 10.10 的设计评审里我最想改的一处 —— 训练屏上半屏近 40%
/// 是纯黑死区，而"默认胜过输入"这条产品原则最该被看见的两个数字（**上次**与**最佳**）
/// 一个藏在角落、一个根本没出现过。「上次」那半边早就有（`core/last_time.dart`），
/// 这个文件补的是右半边。
///
/// 口径**与「进步」页 PR 墙完全一致**（`features/progress/progress_data.dart` 的
/// `personalBests`）—— 同一个动作在两张屏上算出不同的"最佳"是绝不允许的：
///   * 有重量：比**最重那一组**，1RM 另算 —— **逐组估再取最大**，它常常不是最重那组
///     （80 kg × 3 估出来比 82.5 kg × 1 高，见 `progression.dart` 的 `estimate1RM`）；
///   * 自重 / 按时长：比**最多次数**（按时长那些"次"其实是秒，界面负责换单位）；
///   * **有氧（记距离）整个不进来** —— 它的成绩是里程与配速，按自重那条路比会得出
///     "最佳 1800 次"这种胡话（v1.66.0 已经在 PR 墙上挡过一次，这里同一条规矩）。
///
/// 没有历史就返回 `null`，界面不编一个"最佳"出来。
library;

import '../domain/models.dart';
import '../domain/progression.dart' show estimate1RM;
import 'units.dart';

/// 一个动作的历史最佳（`null` = 没有历史 / 不该有最佳）。
class BestSet {
  const BestSet({
    this.weightKg,
    this.reps,
    this.oneRm,
    required this.isBodyweight,
    required this.totalSets,
  });

  /// 最重那一组的重量（kg）。自重动作恒为 null。
  final double? weightKg;

  /// 那一组的次数（按时长动作是秒）。
  final int? reps;

  /// 全部历史里**逐组**估出来的最大 1RM。算不出来（自重/次数过高）就是 null。
  final double? oneRm;

  /// 这个动作是不是"没有重量"的那一类（自重 / 按时长）。
  final bool isBodyweight;

  /// 历史一共练过几组（这句会印在副标题里："共 12 组"）。
  final int totalSets;
}

/// 从某个动作的**全部历史组**里挑出最佳。空集合 / 有氧动作返回 `null`。
BestSet? bestSetOf(Iterable<SetRecord> sets, {String? trackType}) {
  // 有氧不进来（口径见文件头）
  if (isDistanceTrack(trackType ?? '')) return null;
  // 热身组不算成绩 —— 但库里本来就只存了 normal（`LocalStore.setsForExercise` 过滤了），
  // 这里再挡一道是给测试里的替身用的：它们常常不区分。
  final List<SetRecord> list = <SetRecord>[
    for (final SetRecord s in sets)
      if (s.setType == SetType.normal) s,
  ];
  if (list.isEmpty) return null;

  final bool bodyweight =
      list.every((SetRecord s) => s.weightKg == null || s.weightKg! <= 0);

  if (bodyweight) {
    SetRecord best = list.first;
    for (final SetRecord s in list) {
      if (s.reps > best.reps) best = s;
    }
    return BestSet(
      reps: best.reps,
      isBodyweight: true,
      totalSets: list.length,
    );
  }

  SetRecord best = list.first;
  double? best1Rm;
  for (final SetRecord s in list) {
    if ((s.weightKg ?? 0) > (best.weightKg ?? 0)) best = s;
    final double? e = estimate1RM(s.weightKg, s.reps);
    if (e != null && (best1Rm == null || e > best1Rm)) best1Rm = e;
  }
  return BestSet(
    weightKg: best.weightKg,
    reps: best.reps,
    oneRm: best1Rm,
    isBodyweight: false,
    totalSets: list.length,
  );
}

/// 大字那一行：`45 kg × 8` / `自重 × 12`（按时长动作的次数念"秒"）。
String bestSetMainLabel(BestSet b, {required WeightUnit unit, String? trackType}) {
  final String reps = '${b.reps ?? 0}${isTimeTrack(trackType ?? '') ? ' 秒' : ''}';
  if (b.isBodyweight || b.weightKg == null) return '自重 × $reps';
  return '${formatWeight(b.weightKg, unit)} × $reps';
}

/// 小字那一行：有 1RM 就念 1RM，否则念历史组数。**两组都不编**：
/// 都算不出来时返回 null，界面那一行不出现。
String? bestSetSubLabel(BestSet b, {required WeightUnit unit}) {
  if (b.oneRm != null) return '1RM 预估 ${formatWeight(b.oneRm, unit)}';
  return null;
}
