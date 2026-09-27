/// 练了么 · S8「进步」的数据
///
/// 全是纯函数：给一堆记录 + 一个「今天」，算出最近 7 天的容量曲线与各动作的历史最佳。
/// 没有 IO、没有 Flutter 依赖 —— 所以日期边界这种事能被完整测到。
///
/// 范围说明：`docs/screens.md` 的 S8 有三块（容量曲线 / PR 墙 / 体重）。
/// 这里只做前两块。**体重没做**：它需要 `body_metric` 表和录入界面（S12），
/// 属于另一块工作，不该塞进这一屏顺手做。
library;

import '../../domain/models.dart';

class DailyVolume {
  const DailyVolume({required this.day, required this.volumeKg});

  /// 当天零点（本地时间）
  final DateTime day;
  final double volumeKg;

  bool get isEmpty => volumeKg <= 0;
}

class ExercisePr {
  const ExercisePr({
    required this.exerciseId,
    required this.name,
    required this.reps,
    this.weightKg,
  });

  final String exerciseId;
  final String name;

  /// 自重动作为 null —— 那时比的是次数
  final double? weightKg;

  /// 创造这个最佳时做的次数
  final int reps;

  bool get isBodyweight => weightKg == null;

  /// 排序与展示用的单一数值：有重量比重量，自重比次数
  double get value => isBodyweight ? reps.toDouble() : (weightKg ?? 0);

  /// 如「80kg」「15 次」
  String get label {
    if (isBodyweight) return '$reps 次';
    final double w = weightKg ?? 0;
    return '${w == w.roundToDouble() ? w.toInt() : w}kg';
  }
}

class ProgressData {
  const ProgressData({required this.week, required this.prs, required this.weekWorkouts});

  /// 最近 7 天（含今天），没练的那天是 0
  final List<DailyVolume> week;

  /// 练过的动作的历史最佳，按数值降序
  final List<ExercisePr> prs;

  /// 这 7 天练了几次
  final int weekWorkouts;

  bool get isEmpty => prs.isEmpty;

  /// 本周总容量
  double get weekVolume =>
      week.fold<double>(0, (double a, DailyVolume d) => a + d.volumeKg);

  String get weekVolumeLabel {
    if (weekVolume <= 0) return '—';
    final String s = weekVolume.round().toString();
    final StringBuffer b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '$b kg';
  }

  /// 曲线用的点（0..1），全 0 时返回全 0 —— 由界面决定怎么画
  List<double> get sparkline {
    final double maxV = week.fold<double>(0, (double a, DailyVolume d) => a > d.volumeKg ? a : d.volumeKg);
    if (maxV <= 0) return List<double>.filled(week.length, 0);
    return week.map((DailyVolume d) => d.volumeKg / maxV).toList();
  }
}

/// 本地时间的「当天零点」
DateTime startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);

/// 最近 7 天（含 [today] 当天）的每日容量
List<DailyVolume> lastSevenDays(List<SetRecord> sets, DateTime today) {
  final DateTime first = startOfDay(today).subtract(const Duration(days: 6));
  final List<DailyVolume> out = <DailyVolume>[];
  for (int i = 0; i < 7; i++) {
    final DateTime day = first.add(Duration(days: i));
    final DateTime next = day.add(const Duration(days: 1));
    double v = 0;
    for (final SetRecord s in sets) {
      final DateTime t = DateTime.fromMillisecondsSinceEpoch(s.completedAtMs);
      if (!t.isBefore(day) && t.isBefore(next)) v += s.volume;
    }
    out.add(DailyVolume(day: day, volumeKg: v));
  }
  return out;
}

/// 这 7 天里有几次训练
int weekWorkoutCount(List<SetRecord> sets, DateTime today) {
  final DateTime first = startOfDay(today).subtract(const Duration(days: 6));
  // 上界和 lastSevenDays 保持一致：未来时间的记录两边都不算，
  // 否则同一个窗口在两处会有两种口径（时钟偏移时尤其明显）。
  final DateTime end = startOfDay(today).add(const Duration(days: 1));
  final Set<String> ids = <String>{};
  for (final SetRecord s in sets) {
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(s.completedAtMs);
    if (!t.isBefore(first) && t.isBefore(end)) ids.add(s.workoutId);
  }
  return ids.length;
}

/// 练过的动作各自的历史最佳。
/// 有重量比重量，自重比次数 —— 引体向上的「最佳」不可能是公斤数。
List<ExercisePr> personalBests({
  required List<SetRecord> sets,
  required Map<String, String> exerciseNames,
}) {
  final Map<String, List<SetRecord>> byExercise = <String, List<SetRecord>>{};
  for (final SetRecord s in sets) {
    byExercise.putIfAbsent(s.exerciseId, () => <SetRecord>[]).add(s);
  }

  final List<ExercisePr> out = <ExercisePr>[];
  byExercise.forEach((String id, List<SetRecord> list) {
    final String name = exerciseNames[id] ?? id;
    final bool bodyweight = list.every((SetRecord s) => s.weightKg == null);

    if (bodyweight) {
      SetRecord best = list.first;
      for (final SetRecord s in list) {
        if (s.reps > best.reps) best = s;
      }
      out.add(ExercisePr(exerciseId: id, name: name, reps: best.reps));
    } else {
      SetRecord best = list.first;
      for (final SetRecord s in list) {
        if ((s.weightKg ?? 0) > (best.weightKg ?? 0)) best = s;
      }
      out.add(ExercisePr(
        exerciseId: id,
        name: name,
        reps: best.reps,
        weightKg: best.weightKg,
      ));
    }
  });

  // 重的在前；同值按名字排，保证顺序稳定（否则每次重建都会跳）
  out.sort((ExercisePr a, ExercisePr b) {
    final int c = b.value.compareTo(a.value);
    return c != 0 ? c : a.name.compareTo(b.name);
  });
  return out;
}

/// 一次算好界面要用的全部数据
ProgressData buildProgress({
  required List<SetRecord> sets,
  required Map<String, String> exerciseNames,
  required DateTime today,
}) =>
    ProgressData(
      week: lastSevenDays(sets, today),
      prs: personalBests(sets: sets, exerciseNames: exerciseNames),
      weekWorkouts: weekWorkoutCount(sets, today),
    );
