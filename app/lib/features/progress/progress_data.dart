/// 练了么 · S8「进步」的数据
///
/// 全是纯函数：给一堆记录 + 一个「今天」，算出最近 7 天的容量曲线与各动作的历史最佳。
/// 没有 IO、没有 Flutter 依赖 —— 所以日期边界这种事能被完整测到。
///
/// 范围说明：`docs/screens.md` 的 S8 有三块（容量曲线 / PR 墙 / 体重）。
/// 这里只做前两块。**体重没做**：它需要 `body_metric` 表和录入界面（S12），
/// 属于另一块工作，不该塞进这一屏顺手做。
library;

import '../../core/labels.dart';
import '../../core/units.dart';
import '../../domain/models.dart';
import '../../domain/progression.dart';

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
    this.unit = WeightUnit.kg,
    this.isTime = false,
    this.oneRm,
  });

  /// 按时长动作（平板支撑）：这个数字是**秒**不是次数。
  final bool isTime;

  final String exerciseId;
  final String name;

  /// 自重动作为 null —— 那时比的是次数
  final double? weightKg;

  /// 创造这个最佳时做的次数
  final int reps;

  bool get isBodyweight => weightKg == null;

  /// **预估 1RM**（2026-10-04 加进 PR 墙）。
  ///
  /// 全榜取**所有组里估算值最大**的那一条 —— 它常常不是"最重那一组"
  /// （80 kg × 3 估出来比 82.5 kg × 1 高）。null = 这条动作算不出 1RM：
  /// 自重 / 按时长 / 或者次数超过 12（`estimate1RM` 在高次数下不可信，会误导）。
  final double? oneRm;

  /// 排序与展示用的单一数值：有重量比重量，自重比次数
  double get value => isBodyweight ? reps.toDouble() : (weightKg ?? 0);

  /// 显示单位。存储始终是 kg，这里只影响怎么念数字。
  final WeightUnit unit;

  /// 如「80 kg」「176.4 lb」「15 次」「45 秒」
  String get label =>
      isBodyweight ? '$reps ${isTime ? '秒' : '次'}' : formatWeight(weightKg, unit);
}

class ProgressData {
  const ProgressData({
    required this.week,
    required this.prs,
    required this.weekWorkouts,
    this.unit = WeightUnit.kg,
    this.weekSetsByMuscle = const <({String muscleGroup, int sets})>[],
  });

  /// 最近 7 天（含今天），没练的那天是 0
  final List<DailyVolume> week;

  /// 练过的动作的历史最佳，按数值降序
  final List<ExercisePr> prs;

  /// 这 7 天练了几次
  final int weekWorkouts;

  final WeightUnit unit;

  /// 本周**每个部位**练了几组（2026-10-04 加，进步页那一行）。
  ///
  /// 顺序固定（胸背腿肩臂核心），**没练的部位也在里面**（sets = 0）——
  /// "这周腿 0 组"恰恰是最该被看见的一句话。
  final List<({String muscleGroup, int sets})> weekSetsByMuscle;

  bool get isEmpty => prs.isEmpty;

  /// 本周总容量
  double get weekVolume =>
      week.fold<double>(0, (double a, DailyVolume d) => a + d.volumeKg);

  String get weekVolumeLabel {
    // 交给 core/units.dart 统一格式化（此前这里、TrainingStats、WorkoutSummary
    // 各写了一份千分位）
    return formatVolume(weekVolume, unit);
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
  WeightUnit unit = WeightUnit.kg,
  /// 按时长动作的 id 集合 —— 它们的最佳值念「秒」。缺省空集，行为不变。
  Set<String> timeExerciseIds = const <String>{},
  /// 记距离的动作 id 集合 —— **整条跳过**。
  ///
  /// 它们没有"力量最佳"可言：距离动作的 weightKg 是 null、reps 是秒，
  /// 按自重那条路比次数会得出"最佳 1800 次"。有氧的成绩是里程与配速，
  /// 是另一套呈现（见 WorkoutSummary.distanceLabel）。
  Set<String> distanceExerciseIds = const <String>{},
}) {
  final Map<String, List<SetRecord>> byExercise = <String, List<SetRecord>>{};
  for (final SetRecord s in sets) {
    byExercise.putIfAbsent(s.exerciseId, () => <SetRecord>[]).add(s);
  }

  final List<ExercisePr> out = <ExercisePr>[];
  byExercise.forEach((String id, List<SetRecord> list) {
    if (distanceExerciseIds.contains(id)) return; // 有氧不进力量最佳榜
    final String name = exerciseNames[id] ?? id;
    final bool bodyweight = list.every((SetRecord s) => s.weightKg == null);

    if (bodyweight) {
      SetRecord best = list.first;
      for (final SetRecord s in list) {
        if (s.reps > best.reps) best = s;
      }
      out.add(ExercisePr(
        exerciseId: id,
        name: name,
        reps: best.reps,
        unit: unit,
        isTime: timeExerciseIds.contains(id),
      ));
    } else {
      SetRecord best = list.first;
      double? best1Rm;
      for (final SetRecord s in list) {
        if ((s.weightKg ?? 0) > (best.weightKg ?? 0)) best = s;
        // 1RM 要**逐组估**再取最大：它常常不是"最重那一组"
        // （80 kg × 3 估出来比 82.5 kg × 1 高）。与 all_data.dart 同一口径。
        final double? e = estimate1RM(s.weightKg, s.reps);
        if (e != null && (best1Rm == null || e > best1Rm)) best1Rm = e;
      }
      out.add(ExercisePr(
        exerciseId: id,
        name: name,
        reps: best.reps,
        weightKg: best.weightKg,
        unit: unit,
        oneRm: best1Rm,
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

/// **本周每个部位练了几组**（2026-10-04 加，进步页那一行）。
///
/// **为什么要有它**：循证区间是「每块肌肉每周 **12–20 组**」——
/// Baz-Valle 2022 系统综述+元分析的结论（中等 12–20 与高容量 >20 在股四头肌 p=0.19、
/// 肱二头肌 p=0.59 上**没有差异**）；下限门槛「> 9 组/周」见 Schoenfeld 2017 元分析。
/// 而这个数用户**看不见** —— 目标看不见就等于不存在。
///
/// 顺序固定用 `kPrimaryMuscleGroups`（胸背腿肩臂核心），**没练的部位也在表里**（0 组）。
///
/// ⚠️ **只按主肌群算**：卧推的组只记进"胸"，尽管它同时喂了三头与前束。
/// 复合动作的间接量我们没有折算 —— 已知的简化，写在 `docs/feature-backlog.md`。
List<({String muscleGroup, int sets})> weeklySetsByMuscle({
  required List<SetRecord> sets,
  required Map<String, String> muscleOf,
  required DateTime today,
}) {
  final DateTime first = startOfDay(today).subtract(const Duration(days: 6));
  final DateTime end = startOfDay(today).add(const Duration(days: 1));
  final Map<String, int> count = <String, int>{
    for (final String g in kPrimaryMuscleGroups) g: 0,
  };
  for (final SetRecord s in sets) {
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(s.completedAtMs);
    // 上界与 lastSevenDays/weekWorkoutCount 同一个口径：未来时间的记录不算
    if (t.isBefore(first) || !t.isBefore(end)) continue;
    final String? g = muscleOf[s.exerciseId];
    if (g == null || !count.containsKey(g)) continue;
    count[g] = count[g]! + 1;
  }
  return <({String muscleGroup, int sets})>[
    for (final String g in kPrimaryMuscleGroups) (muscleGroup: g, sets: count[g]!),
  ];
}

/// 一次算好界面要用的全部数据
ProgressData buildProgress({
  required List<SetRecord> sets,
  required Map<String, String> exerciseNames,
  required DateTime today,
  WeightUnit unit = WeightUnit.kg,
  /// 按时长动作的 id 集合（它们的最佳值念「秒」）。缺省空集，行为不变。
  Set<String> timeExerciseIds = const <String>{},
  /// 记距离的动作 id 集合（有氧、农夫行走）—— 不进力量最佳榜。
  Set<String> distanceExerciseIds = const <String>{},
  /// 动作 id → 主肌群。传了就一并算出"本周每部位组数"；缺省空表（老调用行为不变）。
  Map<String, String> muscleOf = const <String, String>{},
}) =>
    ProgressData(
      week: lastSevenDays(sets, today),
      prs: personalBests(
        sets: sets,
        exerciseNames: exerciseNames,
        unit: unit,
        timeExerciseIds: timeExerciseIds,
        distanceExerciseIds: distanceExerciseIds,
      ),
      weekWorkouts: weekWorkoutCount(sets, today),
      unit: unit,
      weekSetsByMuscle: muscleOf.isEmpty
          ? const <({String muscleGroup, int sets})>[]
          : weeklySetsByMuscle(
              sets: sets, muscleOf: muscleOf, today: today),
    );
