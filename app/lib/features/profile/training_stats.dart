/// 练了么 · 训练统计与数据导出
///
/// 全是纯函数：给定一组记录，算出统计数字或 CSV 文本。
/// 没有 IO、没有 Flutter 依赖，所以能被完整测试。
///
/// 「数据必须能一键全量导出」是产品原则之一（见 PRODUCT.md §10 风险对策）——
/// 工具类用户最怕数据被锁在里面。
library;

import '../../core/units.dart';
import '../../domain/models.dart';

class TrainingStats {
  const TrainingStats({
    required this.workoutCount,
    required this.setCount,
    required this.totalVolumeKg,
    this.unit = WeightUnit.kg,
  });

  /// 从全部正式组算出来
  factory TrainingStats.fromSets(
    List<SetRecord> sets, {
    WeightUnit unit = WeightUnit.kg,
  }) {
    final Set<String> workouts = <String>{};
    double volume = 0;
    for (final SetRecord s in sets) {
      workouts.add(s.workoutId);
      volume += s.volume;
    }
    return TrainingStats(
      workoutCount: workouts.length,
      setCount: sets.length,
      totalVolumeKg: volume,
      unit: unit,
    );
  }

  /// 练过多少次
  final int workoutCount;

  /// 总共多少组
  final int setCount;

  /// 总容量（自重动作记 0）
  final double totalVolumeKg;

  final WeightUnit unit;

  String get volumeLabel => formatVolume(totalVolumeKg, unit);

  bool get isEmpty => setCount == 0;
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 本地时间，形如 2026-09-27 19:03
String formatLocalTime(int ms) {
  final DateTime t = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${t.year}-${_two(t.month)}-${_two(t.day)} '
      '${_two(t.hour)}:${_two(t.minute)}';
}

/// CSV 字段转义：一律加引号，内部的引号翻倍。
/// 动作名里出现逗号或引号时不会把表格搞散。
String _csvField(String v) => '"${v.replaceAll('"', '""')}"';

/// 导出用的 CSV 文本。
///
/// [exerciseNames] 是 id → 名称；查不到的用 id 兜底，不会丢行。
///
/// 重量列跟随 [unit]：界面上显示 lb、导出却是 kg 的话，用户会以为导错了。
/// 表头也随之写清楚是哪个单位。
String _csvHeader(WeightUnit unit) {
  // 「距离km」列：有氧与农夫行走靠它才带得走数据。
  // 那一行的「次数」列其实是**秒**（沿用 time 的约定），报表里不改表头 ——
  // 改了就要动已存在的表的解析，代价大于收益；说明写在 docs/data-model.md 与这里。
  return '日期,动作,重量${unit.wire},次数,容量${unit.wire},组序,距离km';
}

/// CSV 的一行（**表头与列序只在这里定义一次**，两种导出共用）。
String _csvRow(SetRecord s, Map<String, String> exerciseNames, WeightUnit unit) {
  final String name = exerciseNames[s.exerciseId] ?? s.exerciseId;
  return <String>[
    _csvField(formatLocalTime(s.completedAtMs)),
    _csvField(name),
    _csvField(s.weightKg == null
        ? ''
        : trimNumber(round1(toDisplayWeight(s.weightKg!, unit)))),
    _csvField('${s.reps}'),
    _csvField(trimNumber(round1(toDisplayWeight(s.volume, unit)))),
    _csvField('${s.setIndex}'),
    _csvField(s.distanceM == null || s.distanceM == 0
        ? ''
        : (s.distanceM! / 1000).toStringAsFixed(2)),
  ].join(',');
}

String buildSetsCsv({
  required List<SetRecord> sets,
  required Map<String, String> exerciseNames,
  WeightUnit unit = WeightUnit.kg,
}) {
  final StringBuffer b = StringBuffer();
  b.writeln(_csvHeader(unit));
  for (final SetRecord s in sets) {
    b.writeln(_csvRow(s, exerciseNames, unit));
  }
  return b.toString();
}

/// **按动作拆分**的 CSV（Ultra 权益 9）：列与 [buildSetsCsv] 完全一致（不自创字段），
/// 只是行按"动作 → 时间 → 组序"排好，于是每个动作是一条连续的时间序列。
///
/// 为什么不拆成多个文件：用户点一次导出拿到一个可粘进表格的文本；
/// 一个动作一个小文件会把"导出"变成"收一堆文件"。要拆开的话在表格里按「动作」列筛即可。
String buildPerExerciseCsv({
  required List<SetRecord> sets,
  required Map<String, String> exerciseNames,
  WeightUnit unit = WeightUnit.kg,
}) {
  final List<SetRecord> sorted = List<SetRecord>.of(sets)
    ..sort((SetRecord a, SetRecord b) {
      final int byExercise = (exerciseNames[a.exerciseId] ?? a.exerciseId)
          .compareTo(exerciseNames[b.exerciseId] ?? b.exerciseId);
      if (byExercise != 0) return byExercise;
      final int byTime = a.completedAtMs.compareTo(b.completedAtMs);
      if (byTime != 0) return byTime;
      return a.setIndex.compareTo(b.setIndex);
    });
  final StringBuffer b = StringBuffer();
  b.writeln(_csvHeader(unit));
  for (final SetRecord s in sorted) {
    b.writeln(_csvRow(s, exerciseNames, unit));
  }
  return b.toString();
}
