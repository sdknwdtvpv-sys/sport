/// 练了么 · 「上次练了多少」那一行（v1.53）
///
/// **一处实现、两处用**：今日建议页的证据链（`TodayPlanner.historyLabel`）与训练屏上
/// 新加的那一行（用户在器械前最想知道的数字）。抽出来的理由和别的共享件一样 ——
/// 两处各写一遍，迟早会出现"同一个动作在两张屏上念得不一样"。
///
/// 三条规矩：
///   * **没有历史就返回 null**，界面那一行整个不出现 —— 不编一个"上次"出来；
///   * 距离动作念**距离 + 时长**（念"自重 × 3000"是胡说）；
///   * 字面量与建议页完全一致（`上次 3 组 · 45 kg × 10 次`），用户在两张屏上看到的是同一句话。
library;

import '../core/units.dart';
import '../domain/models.dart';

/// 把上一次的训练折成一句人话。null = 没练过（或那次一组都没完成）。
///
/// [trackType] 决定用哪一套单位与说法：距离动作念里程 + 时长，
/// 计时动作念秒，其余念次数。
String? lastTimeLabel(
  LastSession? last, {
  required WeightUnit unit,
  String? trackType,
}) {
  if (last == null || last.completedSets == 0) return null;
  final String track = trackType ?? '';

  if (isDistanceTrack(track)) {
    // 距离动作：优先"最后一组"（"今天还跑那么多"），没有就用最远那组。
    final double? meters = last.lastDistanceM ?? last.maxDistanceM;
    if (meters == null || meters <= 0) return null;
    final int seconds = last.reps.isEmpty ? 0 : last.reps.last;
    final String time = seconds > 0 ? ' · ${formatDurationHms(seconds)}' : '';
    return '上次 ${last.completedSets} 组 · ${formatDistanceKm(meters)}$time';
  }

  final String weight = last.weightKg == null ? '自重' : formatWeight(last.weightKg, unit);
  final String unitText = isTimeTrack(track) ? '秒' : '次';
  // 各组次数一样时说"× 10 次"，不一样时说"最少 8 次" —— 后者才是**事实**：
  // 5/8/8 那三组写成"最少 8 次"不会骗人，写成"× 8 次"会。
  final String reps = last.reps.toSet().length == 1
      ? '${last.minReps} $unitText'
      : '最少 ${last.minReps} $unitText';
  return '上次 ${last.completedSets} 组 · $weight × $reps';
}

/// 大字那一行：`45 kg × 10`（自重念 `自重 × 12`，按时长念 `45 秒`，距离念里程）。
///
/// 2026-10-10：训练屏把它拆成两行之后新增 —— 原来只有
/// [lastTimeLabel] 那一句连成一串的话，塞不进"上次 / 历史最佳"那条对照带的左半边。
String? lastSetMainLabel(
  LastSession? last, {
  required WeightUnit unit,
  String? trackType,
}) {
  if (last == null || last.completedSets == 0) return null;
  final String track = trackType ?? '';
  if (isDistanceTrack(track)) {
    final double? meters = last.lastDistanceM ?? last.maxDistanceM;
    if (meters == null || meters <= 0) return null;
    return formatDistanceKm(meters);
  }
  final int reps = last.reps.isEmpty ? 0 : last.minReps;
  if (isTimeTrack(track)) return '$reps 秒';
  final String w = last.weightKg == null ? '自重' : formatWeight(last.weightKg, unit);
  return '$w × $reps';
}

/// 小字那一行：`3 组 · 7 天前`。没有历史返回 null（界面那一行不出现）。
String? lastSetSubLabel(LastSession? last) {
  if (last == null || last.completedSets == 0) return null;
  return '${last.completedSets} 组 · ${daysAgoLabel(last.daysAgo)}';
}

/// `0 → 今天` / `1 → 昨天` / `n → n 天前` / `n → n 个月前`。
///
/// ⚠️ 与「进步」页 PR 墙那套分档**同一口径**（那边是"最近一次破纪录"的分档）——
/// 同一件事在两张屏上念得不一样，用户就会以为是两件事。
String daysAgoLabel(int days) {
  if (days <= 0) return '今天';
  if (days == 1) return '昨天';
  if (days < 30) return '$days 天前';
  if (days < 365) return '${days ~/ 30} 个月前';
  return '${days ~/ 365} 年前';
}
