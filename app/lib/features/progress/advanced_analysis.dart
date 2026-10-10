/// 练了么 · **进阶分析**的数据层（Ultra 权益 7；2026-10-10 起做成真功能）
///
/// 方案：`docs/plan-membership-2026-10-10.md` §二 权益 7「分动作趋势、周/月/季对比」。
/// 与 `progress_data.dart` / `all_data.dart` 同一个约定：**全是纯函数**，没有 IO、
/// 没有 Flutter 依赖 —— 于是"周期怎么切、跨月跨年怎么算、只有一组数据时怎么显示"
/// 这些最容易错的地方可以被完整测到（`app/test/advanced_analysis_test.dart`）。
///
/// ⚠️ **它只新增视角，不改动任何已有数字**：进步页那四张卡、容量趋势、PR 墙、
/// 「全部数据」里的三种趋势都保持免费且算法不动。Ultra 卖的是"看得更远"，
/// 不是"把原来能看的遮起来"（红线 2，见方案 §一）。
library;

import '../../domain/models.dart';
import '../../domain/progression.dart';

/// 周期档位。**只有三档**（与「全部数据」的分段控件同一个语言）：
/// 周 / 月 / 季。年那一档留给已有的容量趋势，不在这里重复。
enum AnalysisRange { week, month, quarter }

extension AnalysisRangeLabel on AnalysisRange {
  String get label {
    switch (this) {
      case AnalysisRange.week:
        return '周';
      case AnalysisRange.month:
        return '月';
      case AnalysisRange.quarter:
        return '季';
    }
  }

  /// 这个档位下的分桶跨度（周 = 7 天；月与季按自然月/季走，见 [bucketStart]）
  int get days {
    switch (this) {
      case AnalysisRange.week:
        return 7;
      case AnalysisRange.month:
        return 30;
      case AnalysisRange.quarter:
        return 90;
    }
  }
}

/// 一个周期里的汇总。
///
/// 口径与进步页那四张卡一致（容量 = Σ `SetRecord.volume`；距离动作恒为 0，
/// 那是 `SetRecord.volume` 自己的规矩，这里不另立一套）。
class PeriodStats {
  const PeriodStats({
    required this.from,
    required this.to,
    required this.sets,
    required this.volumeKg,
    required this.reps,
    this.bestWeightKg,
    this.best1Rm,
    this.sessions = 0,
  });

  /// 周期起点（含）
  final DateTime from;

  /// 周期终点（**不含**）—— 半开区间，跨月跨年都不会重复计数
  final DateTime to;

  final int sets;
  final double volumeKg;
  final int reps;

  /// 这个周期里最重的一组（自重动作没有重量 → null）
  final double? bestWeightKg;

  /// 这个周期里最好的估算 1RM（Epley；次数 > 12 时为 null，见 `estimate1RM`）
  final double? best1Rm;

  /// 有记录的天数（"练了几次"）
  final int sessions;

  bool get isEmpty => sets == 0;

  static PeriodStats empty(DateTime from, DateTime to) =>
      PeriodStats(from: from, to: to, sets: 0, volumeKg: 0, reps: 0);
}

/// 相邻两个周期的对比结果（**"这周比上周"就靠它**）
class PeriodDelta {
  const PeriodDelta({required this.current, required this.previous});

  final PeriodStats current;
  final PeriodStats previous;

  double get volumeKgDelta => current.volumeKg - previous.volumeKg;
  int get setsDelta => current.sets - previous.sets;
  int get repsDelta => current.reps - previous.reps;

  /// 容量变化率。**上一周期为 0 时返回 null**（不是 0%、也不是 100%）——
  /// "从 0 到 300" 的百分比在数学上没有意义，编一个数只会让用户看到假趋势。
  double? get volumeChangePct =>
      previous.volumeKg <= 0 ? null : volumeKgDelta / previous.volumeKg;

  bool get isNewPain => current.best1Rm != null &&
      previous.best1Rm != null &&
      current.best1Rm! > previous.best1Rm!;
}

/// 趋势上的一个点（一个桶）
class TrendPoint {
  const TrendPoint({
    required this.bucketStart,
    required this.volumeKg,
    required this.sets,
    this.topWeightKg,
  });

  final DateTime bucketStart;
  final double volumeKg;
  final int sets;

  /// 这个桶里最重的一组（自重动作 null）
  final double? topWeightKg;
}

/// **一个动作的进阶趋势**（这一屏的主角）
class ExerciseTrend {
  const ExerciseTrend({
    required this.exerciseId,
    required this.range,
    required this.points,
    required this.latest,
    required this.previous,
    this.firstTopWeightKg,
    this.latestTopWeightKg,
  });

  final String exerciseId;
  final AnalysisRange range;

  /// 按时间升序的桶（**空桶也在里面**：断掉的周要如实显示为 0，
  /// 而不是把两个不相邻的点连成一条"看起来一直在涨"的线）
  final List<TrendPoint> points;

  /// 最近的周期与它的上一个周期（对比用）
  final PeriodStats latest;
  final PeriodStats previous;

  /// "起步时"（最早 30 天内）与"最近 30 天"各自最重的一组，用来算从头到现在的变化
  final double? firstTopWeightKg;
  final double? latestTopWeightKg;

  /// 起步 → 现在的最佳重量变化率。任一端为空时返回 null（编不出来就说编不出来）
  double? get topWeightChangePct {
    final double? a = firstTopWeightKg;
    final double? b = latestTopWeightKg;
    if (a == null || b == null || a <= 0) return null;
    return (b - a) / a;
  }

  bool get hasHistory => points.any((TrendPoint p) => p.sets > 0);
}

/// 把某一天归到它所在的桶起点。
///
/// * **周**：周一（ISO 口径）。用 `weekday` 反推，不引入任何"I 周从周日开始"的歧义；
/// * **月**：当月 1 号零点；
/// * **季**：当季第一个月的 1 号零点。
DateTime bucketStart(DateTime day, AnalysisRange range) {
  final DateTime d = DateTime(day.year, day.month, day.day);
  switch (range) {
    case AnalysisRange.week:
      return d.subtract(Duration(days: d.weekday - DateTime.monday));
    case AnalysisRange.month:
      return DateTime(d.year, d.month);
    case AnalysisRange.quarter:
      return DateTime(d.year, ((d.month - 1) ~/ 3) * 3 + 1);
  }
}

/// 桶起点的**下一个**桶起点（周 +7 天；月/季按自然月/季推进）
DateTime nextBucket(DateTime start, AnalysisRange range) {
  switch (range) {
    case AnalysisRange.week:
      return start.add(const Duration(days: 7));
    case AnalysisRange.month:
      return DateTime(start.year, start.month + 1);
    case AnalysisRange.quarter:
      return DateTime(start.year, start.month + 3);
  }
}

/// 某个时间区间里的汇总（半开区间 `[from, to)`）
PeriodStats statsIn(List<SetRecord> sets, {required DateTime from, required DateTime to}) {
  final int fromMs = from.millisecondsSinceEpoch;
  final int toMs = to.millisecondsSinceEpoch;
  double volume = 0;
  int reps = 0;
  int count = 0;
  double? bestWeight;
  double? best1Rm;
  final Set<String> days = <String>{};

  for (final SetRecord s in sets) {
    if (s.completedAtMs < fromMs || s.completedAtMs >= toMs) continue;
    count++;
    reps += s.reps;
    volume += s.volume;
    final double? w = s.weightKg;
    if (w != null && w > 0 && (bestWeight == null || w > bestWeight)) bestWeight = w;
    final double? r = estimate1RM(s.weightKg, s.reps);
    if (r != null && (best1Rm == null || r > best1Rm)) best1Rm = r;
    final DateTime at = DateTime.fromMillisecondsSinceEpoch(s.completedAtMs);
    days.add('${at.year}-${at.month}-${at.day}');
  }
  return PeriodStats(
    from: from,
    to: to,
    sets: count,
    volumeKg: volume,
    reps: reps,
    bestWeightKg: bestWeight,
    best1Rm: best1Rm,
    sessions: days.length,
  );
}

/// **最近一个完整周期的对比**：`[now 所在桶, 现在)` 对 `[上一个桶, 这个桶)`。
///
/// 为什么拿"当前周期"跟"上一个完整周期"比（而不是两个完整周期比）：
/// 用户点进来就是想看"我这周怎么样" —— 拿上周跟再上周比虽然更"公平"，
/// 但那回答不了他此刻的问题。口径写在界面上（"本周 vs 上周"）。
PeriodDelta compareLatestPeriods(
  List<SetRecord> sets, {
  required AnalysisRange range,
  required DateTime now,
}) {
  final DateTime curStart = bucketStart(now, range);
  final DateTime prevStart = previousBucketStart(curStart, range);
  return PeriodDelta(
    current: statsIn(sets, from: curStart, to: nextBucket(curStart, range)),
    previous: statsIn(sets, from: prevStart, to: curStart),
  );
}

/// 桶起点的**上一个**桶起点（月与季按自然月/季往回退，不是减 30/90 天 ——
/// 否则 3 月 31 日退一个月会掉到 3 月 3 日，季度也会错位）
DateTime previousBucketStart(DateTime start, AnalysisRange range) {
  switch (range) {
    case AnalysisRange.week:
      return start.subtract(const Duration(days: 7));
    case AnalysisRange.month:
      return DateTime(start.year, start.month - 1);
    case AnalysisRange.quarter:
      return DateTime(start.year, start.month - 3);
  }
}

/// 一个动作的趋势：从它**第一次出现**的那个桶一直画到现在。
///
/// `buckets` 是"最多往回看多少个桶"（周 12 / 月 12 / 季 8 之类，由界面给）——
/// 上限是必要的：一个练了两年的动作，按周画会有 104 个点，图上什么都看不出来。
ExerciseTrend exerciseTrend(
  List<SetRecord> allSets, {
  required String exerciseId,
  required AnalysisRange range,
  required DateTime now,
  int buckets = 12,
}) {
  final List<SetRecord> mine =
      allSets.where((SetRecord s) => s.exerciseId == exerciseId).toList()
        ..sort((SetRecord a, SetRecord b) => a.completedAtMs.compareTo(b.completedAtMs));

  final DateTime curStart = bucketStart(now, range);
  final DateTime lastStart = curStart;
  // 往回数 buckets-1 个桶，得到窗口起点
  DateTime firstStart = lastStart;
  for (int i = 1; i < buckets; i++) {
    firstStart = previousBucketStart(firstStart, range);
  }

  final List<TrendPoint> points = <TrendPoint>[];
  DateTime cursor = firstStart;
  while (!cursor.isAfter(lastStart)) {
    final DateTime next = nextBucket(cursor, range);
    final PeriodStats st = statsIn(mine, from: cursor, to: next);
    points.add(TrendPoint(
      bucketStart: cursor,
      volumeKg: st.volumeKg,
      sets: st.sets,
      topWeightKg: st.bestWeightKg,
    ));
    cursor = next;
  }

  final PeriodStats latest = statsIn(mine, from: curStart, to: nextBucket(curStart, range));
  final PeriodStats previous = statsIn(mine, from: previousBucketStart(curStart, range), to: curStart);

  // "起步时的重量" = **最早那 30 天里**最重的一组。
  // ⚠️ 不是"历史最大一组"——那个数算不出"从起步到现在涨了多少"
  // （历史最大往往就是最近那一次，两端相等 → 永远显示 0% 变化，看起来像没进步）。
  double? firstTop;
  if (mine.isNotEmpty) {
    final DateTime firstAt =
        DateTime.fromMillisecondsSinceEpoch(mine.first.completedAtMs);
    final DateTime firstUntil = firstAt.add(const Duration(days: 30));
    for (final SetRecord s in mine) {
      final DateTime at = DateTime.fromMillisecondsSinceEpoch(s.completedAtMs);
      if (at.isAfter(firstUntil)) break; // mine 已按时间升序
      final double? w = s.weightKg;
      if (w == null || w <= 0) continue;
      if (firstTop == null || w > firstTop) firstTop = w;
    }
  }
  double? lastTop;
  // "最近一次的重量"取最近 30 天里最重的一组（不是"最后一次那一组"：
  // 最后一次可能是个热身组，拿它跟历史最佳比会让用户以为自己在退步）
  final DateTime recentFrom = now.subtract(const Duration(days: 30));
  for (final SetRecord s in mine) {
    final DateTime at = DateTime.fromMillisecondsSinceEpoch(s.completedAtMs);
    if (at.isBefore(recentFrom)) continue;
    final double? w = s.weightKg;
    if (w == null || w <= 0) continue;
    if (lastTop == null || w > lastTop) lastTop = w;
  }

  return ExerciseTrend(
    exerciseId: exerciseId,
    range: range,
    points: points,
    latest: latest,
    previous: previous,
    firstTopWeightKg: firstTop,
    latestTopWeightKg: lastTop,
  );
}

/// 挑出"值得放进进阶分析列表"的动作：**按最近 90 天的组数从多到少**，最多 [limit] 个。
///
/// 为什么按组数而不是按名称/最近一次：用户想看的几乎一定是"我练得最多的那几个"，
/// 而按字母序排会让卧推排在引体向上后面、按最近一次排会让"今天刚加的新动作"霸榜。
List<String> topExercisesBySets(
  List<SetRecord> sets, {
  required DateTime now,
  int limit = 8,
  int windowDays = 90,
}) {
  final DateTime from = now.subtract(Duration(days: windowDays));
  final Map<String, int> counts = <String, int>{};
  for (final SetRecord s in sets) {
    final DateTime at = DateTime.fromMillisecondsSinceEpoch(s.completedAtMs);
    if (at.isBefore(from)) continue;
    counts[s.exerciseId] = (counts[s.exerciseId] ?? 0) + 1;
  }
  final List<String> ids = counts.keys.toList()
    ..sort((String a, String b) {
      final int byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b); // 同数按 id 定序，保证结果稳定
    });
  return ids.take(limit).toList(growable: false);
}
