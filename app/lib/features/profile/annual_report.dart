/// 练了么 · 训练年报的聚合口径（Ultra 权益 9，纯函数）
///
/// 给定"这一年"的组记录 + 动作信息，算出年报卡要的数字。**没有 IO、没有 Flutter 依赖**
/// —— 跨年边界、闰年、空数据、只有热身组、只有有氧这些边界才能一条一条测干净。
///
/// 四条口径（都写在这里，别在界面里另算一遍）：
///
///   1. **只算正式组**：热身/拉伸（`SetType.warmup`）不算训练量，也不算 PR
///      —— 它们不是"练成什么样"的记录。列表里传进来的可能混着热身，这里自己再挡一道。
///   2. **归年按本机时区**：`completedAtMs` 用本地时间取年/月/日；12 月 31 日 23:59 与
///      1 月 1 日 00:01 分属两年，不做任何"平均分摊"。
///   3. **出勤周数 = 有训练的那几个"周一起始周"的个数**（周跨年时按发生的那一年各算一次；
///      这是"这一年里练了几周"的口径，不假装是 ISO 周号）。
///   4. **不编数字**：没有数据 → `hasData=false`；只有有氧 → 容量 0 但里程照实；
///      只有热身 → 等同于没有数据。界面按这些字段决定显示"空态"还是数字。
library;

import '../../core/units.dart';
import '../../domain/models.dart';

/// 一条"年度最佳"（每个动作只取一条）。
class AnnualPr {
  const AnnualPr({
    required this.exerciseId,
    required this.exerciseName,
    required this.reps,
    required this.completedAtMs,
    required this.isTime,
    this.weightKg,
    this.score = 0,
  });

  final String exerciseId;
  final String exerciseName;
  final int reps;
  final int completedAtMs;

  /// 按时长动作（平板支撑）：`reps` 其实是**秒**。
  final bool isTime;

  /// 自重/有氧为 null。
  final double? weightKg;

  /// 排序用的分数（负重 = 估算 1RM；自重 = 次数；按时长 = 秒）。
  /// **只用于"哪几条排前 3"，不展示**。
  final double score;

  bool get isBodyweight => weightKg == null;
}

/// 一年训练的报告（输入一整年的组记录，输出卡上的数字）。
class AnnualReport {
  const AnnualReport({
    required this.year,
    required this.unit,
    required this.workoutCount,
    required this.setCount,
    required this.totalVolumeKg,
    required this.distanceM,
    required this.trainingDays,
    required this.attendanceWeeks,
    required this.monthsWithData,
    required this.bestPrs,
    required this.muscleVolumeKg,
  });

  final int year;
  final WeightUnit unit;

  final int workoutCount;
  final int setCount;

  /// 总容量（自重/有氧记 0 —— 与 `SetRecord.volume` 同一口径）。
  final double totalVolumeKg;

  /// 有氧/负重行走的总里程（米）。没有距离组时为 0。
  final double distanceM;

  final int trainingDays;
  final int attendanceWeeks;

  /// 有数据的月份数（1..12）。半年数据 = 6，不会推算剩下半年。
  final int monthsWithData;

  final List<AnnualPr> bestPrs;

  /// 主部位（原始 key：chest/back/...；未知动作为 unspecified）→ 容量（kg）。
  final Map<String, double> muscleVolumeKg;

  bool get hasData => setCount > 0;

  bool get hasVolume => totalVolumeKg > 0;

  bool get hasDistance => distanceM > 0;

  /// 只有半年数据时界面用来写"覆盖 N/12 个月"；满 12 个月返回 null（不必说）。
  int? get partialMonths => monthsWithData >= 12 ? null : monthsWithData;

  String get volumeLabel => formatVolume(totalVolumeKg, unit);

  String get distanceLabel {
    final double km = distanceM / 1000;
    return km >= 10 ? '${km.toStringAsFixed(1)} km' : '${km.toStringAsFixed(2)} km';
  }
}

/// 把一组记录聚合成某一年的年报。
///
/// [exerciseNames] 动作 id → 中文名（查不到就用 id，不编）。
/// [muscleGroups] 动作 id → 主部位 key（chest/back/legs/shoulders/arms/core）。
/// [timeExercises] 按时长记录的动作 id 集合（平板支撑等）。
AnnualReport buildAnnualReport({
  required List<SetRecord> sets,
  required int year,
  required Map<String, String> exerciseNames,
  required Map<String, String> muscleGroups,
  required Set<String> timeExercises,
  WeightUnit unit = WeightUnit.kg,
}) {
  // 只算这一年的正式组；热身/拉伸不算（即使调用方没过滤）。
  final List<SetRecord> inYear = sets.where((SetRecord s) {
    if (s.setType != SetType.normal) return false;
    return DateTime.fromMillisecondsSinceEpoch(s.completedAtMs).year == year;
  }).toList(growable: false);

  final Set<String> workoutIds = <String>{};
  final Set<String> days = <String>{};
  final Set<String> weeks = <String>{};
  final Set<int> months = <int>{};
  final Map<String, List<SetRecord>> byExercise = <String, List<SetRecord>>{};
  final Map<String, double> muscleVolume = <String, double>{};
  double volume = 0;
  double distanceM = 0;

  for (final SetRecord s in inYear) {
    workoutIds.add(s.workoutId);
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(s.completedAtMs);
    days.add(_dateKey(t));
    // 周一起始：weekday 1=周一 … 7=周日。
    weeks.add(_dateKey(DateTime(t.year, t.month, t.day).subtract(Duration(days: t.weekday - 1))));
    months.add(t.month);
    volume += s.volume;
    if (s.distanceM != null) distanceM += s.distanceM!;
    byExercise.putIfAbsent(s.exerciseId, () => <SetRecord>[]).add(s);
    if (s.volume > 0) {
      final String group = muscleGroups[s.exerciseId] ?? 'unspecified';
      muscleVolume[group] = (muscleVolume[group] ?? 0) + s.volume;
    }
  }

  final List<AnnualPr> prs = <AnnualPr>[];
  byExercise.forEach((String exerciseId, List<SetRecord> list) {
    final AnnualPr? pr = _bestOf(exerciseId, list, exerciseNames, timeExercises);
    if (pr != null) prs.add(pr);
  });
  // 只展示"年度最佳"前几条；排序口径只用于排序，不展示。
  prs.sort((AnnualPr a, AnnualPr b) {
    final int byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return b.completedAtMs.compareTo(a.completedAtMs);
  });

  return AnnualReport(
    year: year,
    unit: unit,
    workoutCount: workoutIds.length,
    setCount: inYear.length,
    totalVolumeKg: volume,
    distanceM: distanceM,
    trainingDays: days.length,
    attendanceWeeks: weeks.length,
    monthsWithData: months.length,
    bestPrs: List<AnnualPr>.unmodifiable(prs.take(5)),
    muscleVolumeKg: Map<String, double>.unmodifiable(muscleVolume),
  );
}

AnnualPr? _bestOf(
  String exerciseId,
  List<SetRecord> list,
  Map<String, String> names,
  Set<String> timeExercises,
) {
  // 有氧/距离动作的"成绩"是里程与配速，不是 PR —— 与总结页的
  // `_detectPr` 同一条口径：不拿"1800 秒"当纪录。
  if (list.any((SetRecord s) => s.hasDistance)) return null;
  final String name = names[exerciseId] ?? exerciseId;
  final bool isTime = timeExercises.contains(exerciseId);
  final bool bodyweight = list.every((SetRecord s) => s.weightKg == null);

  SetRecord best = list.first;
  double scoreOf(SetRecord s) {
    if (isTime) return s.reps.toDouble();
    if (bodyweight) return s.reps.toDouble();
    final double w = s.weightKg ?? 0;
    // 与「历史最好」同一思路：重量 + 次数都影响；这里用 重量×次数 的近似排序，
    // 不引入 1RM 公式（那是呈现层的口径，年报只需要"谁是这一年最好的一组"）。
    return w * 1000 + s.reps;
  }

  double bestScore = scoreOf(best);
  for (final SetRecord s in list.skip(1)) {
    final double v = scoreOf(s);
    if (v > bestScore) {
      best = s;
      bestScore = v;
    }
  }
  return AnnualPr(
    exerciseId: exerciseId,
    exerciseName: name,
    reps: best.reps,
    completedAtMs: best.completedAtMs,
    isTime: isTime,
    weightKg: bodyweight ? null : best.weightKg,
    score: bestScore,
  );
}

String _two(int n) => n.toString().padLeft(2, '0');

String _dateKey(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)}';
