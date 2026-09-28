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
String buildSetsCsv({
  required List<SetRecord> sets,
  required Map<String, String> exerciseNames,
  WeightUnit unit = WeightUnit.kg,
}) {
  final String u = unit.wire;
  final StringBuffer b = StringBuffer();
  b.writeln('日期,动作,重量$u,次数,容量$u,组序');
  for (final SetRecord s in sets) {
    final String name = exerciseNames[s.exerciseId] ?? s.exerciseId;
    b.writeln(<String>[
      _csvField(formatLocalTime(s.completedAtMs)),
      _csvField(name),
      _csvField(s.weightKg == null
          ? ''
          : trimNumber(round1(toDisplayWeight(s.weightKg!, unit)))),
      _csvField('${s.reps}'),
      _csvField(trimNumber(round1(toDisplayWeight(s.volume, unit)))),
      _csvField('${s.setIndex}'),
    ].join(','));
  }
  return b.toString();
}
