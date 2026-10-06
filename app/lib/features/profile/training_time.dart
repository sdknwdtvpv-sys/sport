/// 练了么 · **固定训练时段建议**（第二部分第 6 条，2026-10-06 用户拍板）
///
/// 一句话：**历史上某时段练得最多 → 一句"要不要定在 19:30"**。
///
/// 为什么值得说一次：习惯养成研究里最稳的一条是"**固定时间 + 固定线索**"
/// （同一时间、同一地点做同一件事），而提醒功能本身只是工具 —— 没有"该定几点"的
/// 建议，用户要么不设，要么设一个自己根本不会练的点（提醒响在健身房之外，两次就被关掉）。
///
/// ⚠️ 这一句**只在"确实有一个明显集中的时段"时才说**：
///   * 至少 [kMinSessionsForSuggestion] 次训练（样本太少时的高频时段是噪音）；
///   * 那个时段要占**一半以上**（练得东一处西一处的人，不该被建议"定死一个点"）。
///
/// 与 `reminder.dart` 的关系：这个函数只产出**建议**（一个下拉里能选到的时刻）——
/// 提醒本身仍然要用户自己点开关（不新增权限、不偷偷设闹钟）。
library;

import '../../domain/models.dart';

/// 至少练过几次才给建议。
const int kMinSessionsForSuggestion = 6;

/// 时段按**整点**归并（19:05 与 19:50 算同一个"19 点档"）。
///
/// 为什么不用"精确到分钟"：真实用户的开始时间每天都在漂（19:10 / 19:40 / 20:05），
/// 精确归并会让每一个时刻都只有一两次，永远凑不出"明显集中"。
/// 归到整点之后，"晚上 7 点档练了 9 次"才是用户看得懂也有用的结论。
///
/// 返回 `(hour, count)`；**建议不出一个整点**时返回 null。
({int hour, int count})? dominantWorkoutHour(
  List<SetRecord> sets, {
  int minSessions = kMinSessionsForSuggestion,
}) {
  if (sets.isEmpty) return null;
  // 一场训练取**那场最早一组**的小时 —— 练到 21 点结束不代表"你习惯 21 点开始"。
  // ⚠️ 按"最早那一组的 ms"取，不能比 `t.hour` 的大小：19:50 与 20:10 是跨了整点的
  // 同一场，比小时会得出"20 点档"（那是错的开始时间）。
  final Map<String, int> startMs = <String, int>{};
  for (final SetRecord s in sets) {
    final int? prev = startMs[s.workoutId];
    if (prev == null || s.completedAtMs < prev) startMs[s.workoutId] = s.completedAtMs;
  }
  final Map<String, int> hourOf = <String, int>{
    for (final MapEntry<String, int> e in startMs.entries)
      e.key: DateTime.fromMillisecondsSinceEpoch(e.value).hour,
  };
  final Set<String> workouts = startMs.keys.toSet();
  if (workouts.length < minSessions) return null;
  final Map<int, int> byHour = <int, int>{};
  for (final String w in workouts) {
    final int? h = hourOf[w];
    if (h == null) continue;
    byHour[h] = (byHour[h] ?? 0) + 1;
  }
  int bestHour = -1;
  int best = 0;
  // 稳定顺序：小时从早到晚，平手时取早的那个（同一个人不会有两次不同的建议）
  for (int h = 0; h < 24; h++) {
    final int n = byHour[h] ?? 0;
    if (n > best) {
      best = n;
      bestHour = h;
    }
  }
  if (bestHour < 0) return null;
  if (best * 2 < workouts.length) return null; // 不到一半 → 说明没有固定时段
  return (hour: bestHour, count: best);
}

/// 那一句建议。**不值得说就返回 null**（提醒那一块该保持安静）。
///
/// 文案三件事：**事实**（你在 19 点档练得最多）、**数字**（9 次）、**去路**（要不要定在 19:00）。
/// ⚠️ 刻意不写"坚持就是胜利"这类话 —— 这一条是**工具性建议**，不是鼓励。
String? trainingTimeSuggestion(
  List<SetRecord> sets, {
  int minSessions = kMinSessionsForSuggestion,
}) {
  final ({int hour, int count})? d =
      dominantWorkoutHour(sets, minSessions: minSessions);
  if (d == null) return null;
  return '你多数在 ${d.hour}:00 前后开始练（${d.count} 次）—— '
      '要不要把提醒定在这个点？';
}

/// 建议里那个时刻转成"一天里的第几分钟"（`ReminderSettings.minutesOfDay` 用的就是它）。
///
/// 单独一个函数是为了**不在这里改任何设置**：调用方拿到这个数之后，
/// 仍然要用户自己点（点了才写库）。
int suggestedReminderMinutes(int hour) => hour * 60;
