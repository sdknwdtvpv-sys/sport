/// 练了么 · S9「全部数据」的数据
///
/// 全是纯函数：给一堆记录 + 一个「今天」，算出按动作 / 按时间的统计。
/// 没有 IO、没有 Flutter 依赖，所以日期边界能被完整测到。
///
/// 规格（`docs/screens.md` S9）：
///   * 按动作维度：容量趋势 / 1RM 趋势 / 历史最佳 / 全部记录
///   * 按时间维度：周报 / 月报
///   * 导出 CSV
library;

import '../../core/sparkline.dart';
import '../../domain/models.dart';
import '../../domain/progression.dart';
import 'progress_data.dart';

/// 某个动作的全部统计。
class ExerciseStats {
  const ExerciseStats({
    required this.exerciseId,
    required this.name,
    required this.setCount,
    required this.totalVolumeKg,
    required this.bestWeightKg,
    required this.best1RM,
    required this.bestReps,
    this.isTime = false,
    required this.lastTrainedAtMs,
    required this.volumeByDay,
    required this.oneRmByDay,
  });

  final String exerciseId;
  final String name;
  final int setCount;
  final double totalVolumeKg;

  /// 历史最大重量。自重动作恒为 null —— 那时比的是次数。
  final double? bestWeightKg;

  /// 最佳估算 1RM。自重动作、或次数超出可信区间时为 null
  /// （见 `progression.dart` 的 `estimate1RM`：宁可不说，也不给假数字）。
  final double? best1RM;

  /// 历史最多次数。自重动作比这个。
  final int bestReps;

  /// 按时长动作（平板支撑）：`bestReps` 其实是**秒**。界面据此改标签与单位。
  final bool isTime;

  final int? lastTrainedAtMs;

  /// 窗口内每天的容量（没练的天是 0）
  final List<DailyVolume> volumeByDay;

  /// 窗口内每天的最大估算 1RM（没值的日子是 0）
  final List<double> oneRmByDay;

  bool get isBodyweight => bestWeightKg == null;
  bool get isEmpty => setCount == 0;

  /// 容量趋势（0..1），交给 `Sparkline` 画
  List<double> get volumeTrend =>
      normalize(volumeByDay.map((DailyVolume d) => d.volumeKg).toList());

  /// 1RM 趋势（0..1）。
  ///
  /// 单独一条是因为**容量与 1RM 会背离**：练得更多（容量涨）不一定更强
  /// （1RM 原地踏步），这正是力量训练者最想看到的区别。
  List<double> get oneRmTrend => normalize(oneRmByDay);
}

/// 按动作汇总。[sets] 传该动作的全部记录（跨训练）。
ExerciseStats buildExerciseStats({
  required String exerciseId,
  required String name,
  required List<SetRecord> sets,
  required DateTime today,
  int days = 30,
  /// 按时长动作：`bestReps` 是秒。缺省 false，行为不变。
  bool isTime = false,
}) {
  final List<SetRecord> normal =
      sets.where((SetRecord s) => s.setType == SetType.normal).toList();

  double volume = 0;
  double? bestWeight;
  double? best1RM;
  int bestReps = 0;
  int? lastAt;

  for (final SetRecord s in normal) {
    volume += s.volume;
    final double? w = s.weightKg;
    if (w != null && (bestWeight == null || w > bestWeight)) bestWeight = w;
    if (s.reps > bestReps) bestReps = s.reps;
    final double? e = estimate1RM(w, s.reps);
    if (e != null && (best1RM == null || e > best1RM)) best1RM = e;
    if (lastAt == null || s.completedAtMs > lastAt) lastAt = s.completedAtMs;
  }

  final List<DateTime> window = _dayWindow(today, days);
  final Map<String, double> volumeMap = <String, double>{};
  final Map<String, double> oneRmMap = <String, double>{};
  for (final SetRecord s in normal) {
    final String key = _dayKeyOf(s.completedAtMs);
    volumeMap[key] = (volumeMap[key] ?? 0) + s.volume;
    final double? e = estimate1RM(s.weightKg, s.reps);
    if (e != null) {
      final double prev = oneRmMap[key] ?? 0;
      if (e > prev) oneRmMap[key] = e;
    }
  }

  return ExerciseStats(
    exerciseId: exerciseId,
    name: name,
    setCount: normal.length,
    totalVolumeKg: volume,
    bestWeightKg: bestWeight,
    best1RM: best1RM,
    bestReps: bestReps,
    isTime: isTime,
    lastTrainedAtMs: lastAt,
    volumeByDay: <DailyVolume>[
      for (final DateTime d in window)
        DailyVolume(day: d, volumeKg: volumeMap[_keyOf(d)] ?? 0),
    ],
    oneRmByDay: <double>[
      for (final DateTime d in window) oneRmMap[_keyOf(d)] ?? 0,
    ],
  );
}

/// 最近 [days] 天（含今天），从旧到新。
List<DateTime> _dayWindow(DateTime today, int days) {
  final DateTime end = startOfDay(today);
  return <DateTime>[
    for (int i = days - 1; i >= 0; i--)
      DateTime(end.year, end.month, end.day - i),
  ];
}

String _keyOf(DateTime d) => startOfDay(d).toIso8601String();

String _dayKeyOf(int ms) =>
    _keyOf(DateTime.fromMillisecondsSinceEpoch(ms));

/// 一段时间内的汇总（周报 / 月报共用）。
class PeriodReport {
  const PeriodReport({
    required this.start,
    required this.end,
    required this.workoutCount,
    required this.setCount,
    required this.volumeKg,
    required this.activeDays,
  });

  /// 含首含尾
  final DateTime start;
  final DateTime end;

  final int workoutCount;
  final int setCount;
  final double volumeKg;

  /// 这段时间里有几天真的练了
  final int activeDays;

  bool get isEmpty => setCount == 0;
}

PeriodReport buildPeriodReport({
  required List<SetRecord> sets,
  required DateTime start,
  required DateTime end,
}) {
  final DateTime from = startOfDay(start);
  final DateTime to = startOfDay(end);
  final int fromMs = from.millisecondsSinceEpoch;
  // 含尾：上界取次日零点
  final int toMs = DateTime(to.year, to.month, to.day + 1).millisecondsSinceEpoch;

  final Set<String> workouts = <String>{};
  final Set<String> days = <String>{};
  int count = 0;
  double volume = 0;

  for (final SetRecord s in sets) {
    if (s.setType != SetType.normal) continue;
    if (s.completedAtMs < fromMs || s.completedAtMs >= toMs) continue;
    count++;
    volume += s.volume;
    workouts.add(s.workoutId);
    days.add(_dayKeyOf(s.completedAtMs));
  }

  return PeriodReport(
    start: from,
    end: to,
    workoutCount: workouts.length,
    setCount: count,
    volumeKg: volume,
    activeDays: days.length,
  );
}

/// 本周（**周一**起，中文习惯）。
PeriodReport buildWeekReport({
  required List<SetRecord> sets,
  required DateTime today,
}) {
  final DateTime d = startOfDay(today);
  final DateTime monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
  return buildPeriodReport(sets: sets, start: monday, end: d);
}

/// 本月。
PeriodReport buildMonthReport({
  required List<SetRecord> sets,
  required DateTime today,
}) {
  final DateTime d = startOfDay(today);
  return buildPeriodReport(
    sets: sets,
    start: DateTime(d.year, d.month, 1),
    end: d,
  );
}

class MonthVolume {
  const MonthVolume({required this.label, required this.volumeKg});

  /// 如「2026-09」
  final String label;
  final double volumeKg;
}

/// 最近 [months] 个月的容量，从旧到新。
List<MonthVolume> recentMonthVolumes({
  required List<SetRecord> sets,
  required DateTime today,
  int months = 6,
}) {
  final DateTime d = startOfDay(today);
  return <MonthVolume>[
    for (int i = months - 1; i >= 0; i--)
      () {
        // 用"月初"来减月份，避免月末（如 3 月 31 日减一个月）溢出
        final DateTime m = DateTime(d.year, d.month - i, 1);
        final DateTime last = DateTime(m.year, m.month + 1, 0);
        final PeriodReport r = buildPeriodReport(sets: sets, start: m, end: last);
        final String mm = m.month.toString().padLeft(2, '0');
        return MonthVolume(label: '${m.year}-$mm', volumeKg: r.volumeKg);
      }(),
  ];
}
