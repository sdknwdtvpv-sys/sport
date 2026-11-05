/// 练了么 · 按动作拆分 CSV（Ultra 权益 9）
///
/// 判据：**列与「导出全部记录」完全一致**（不自创字段）、按动作→时间排序、
/// 逗号/引号正确转义、单位跟随显示单位。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/profile/training_stats.dart';

SetRecord _set({
  required String id,
  required String exerciseId,
  required int atMs,
  int reps = 8,
  double? weightKg,
  double? distanceM,
  int setIndex = 1,
}) =>
    SetRecord(
      id: id,
      workoutId: 'w_${id}',
      exerciseId: exerciseId,
      setIndex: setIndex,
      reps: reps,
      completedAtMs: atMs,
      weightKg: weightKg,
      distanceM: distanceM,
    );

void main() {
  final Map<String, String> names = <String, String>{
    'squat': '深蹲',
    'bench': '卧推, "大重量"',
    'run': '跑步',
  };

  test('表头与「导出全部记录」逐字一致（不自创字段）', () {
    final List<SetRecord> sets = <SetRecord>[
      _set(id: 'a', exerciseId: 'bench', atMs: DateTime(2026, 2, 1).millisecondsSinceEpoch, weightKg: 80, reps: 5),
    ];
    final String all = buildSetsCsv(sets: sets, exerciseNames: names);
    final String per = buildPerExerciseCsv(sets: sets, exerciseNames: names);
    expect(per.split('\n').first, all.split('\n').first);
  });

  test('按动作 → 时间 → 组序排序（每个动作一条时间序列）', () {
    final List<SetRecord> sets = <SetRecord>[
      _set(id: '1', exerciseId: 'squat', atMs: DateTime(2026, 3, 2, 10).millisecondsSinceEpoch, weightKg: 100, reps: 5, setIndex: 2),
      _set(id: '2', exerciseId: 'bench', atMs: DateTime(2026, 1, 2, 10).millisecondsSinceEpoch, weightKg: 80, reps: 5),
      _set(id: '3', exerciseId: 'squat', atMs: DateTime(2026, 3, 1, 10).millisecondsSinceEpoch, weightKg: 90, reps: 5, setIndex: 1),
      _set(id: '4', exerciseId: 'bench', atMs: DateTime(2026, 1, 1, 10).millisecondsSinceEpoch, weightKg: 70, reps: 8),
    ];
    final List<String> rows = buildPerExerciseCsv(sets: sets, exerciseNames: names)
        .split('\n')
        .where((String l) => l.isNotEmpty)
        .skip(1)
        .toList();
    // compareTo 按 Unicode：卧推（卧 U+5367）< 深蹲（深 U+6DF1）
    expect(rows[0], contains('2026-01-01 10:00'));
    expect(rows[0], contains('卧推'));
    expect(rows[1], contains('2026-01-02 10:00'));
    expect(rows[2], contains('2026-03-01 10:00'));
    expect(rows[2], contains('深蹲'));
    expect(rows[3], contains('2026-03-02 10:00'));
  });

  test('逗号与引号正确转义（动作名不会把表格搞散）', () {
    final List<SetRecord> sets = <SetRecord>[
      _set(id: 'a', exerciseId: 'bench', atMs: DateTime(2026, 2, 1).millisecondsSinceEpoch, weightKg: 80, reps: 5),
    ];
    final String csv = buildPerExerciseCsv(sets: sets, exerciseNames: names);
    expect(csv, contains('"卧推, ""大重量"""'));
  });

  test('单位跟随显示单位（lb 时重量/容量列换算，其余列不变）', () {
    final List<SetRecord> sets = <SetRecord>[
      _set(id: 'a', exerciseId: 'squat', atMs: DateTime(2026, 2, 1).millisecondsSinceEpoch, weightKg: 100, reps: 5),
    ];
    final String kg = buildPerExerciseCsv(sets: sets, exerciseNames: names);
    final String lb = buildPerExerciseCsv(sets: sets, exerciseNames: names, unit: WeightUnit.lb);
    expect(lb.split('\n').first, contains('重量lb,次数,容量lb'));
    expect(kg.split('\n').first, contains('重量kg,次数,容量kg'));
    expect(lb, isNot(equals(kg)));
    // 行数一致、列数一致
    expect(lb.split('\n').length, kg.split('\n').length);
    for (final String line in lb.split('\n').where((String l) => l.isNotEmpty)) {
      expect(line.split(',').length, kg.split('\n').first.split(',').length);
    }
  });

  test('有距离的组：距离列保留、容量为 0（与全量 CSV 同口径）', () {
    final List<SetRecord> sets = <SetRecord>[
      _set(id: 'r', exerciseId: 'run', atMs: DateTime(2026, 2, 1).millisecondsSinceEpoch, reps: 1800, distanceM: 5000),
    ];
    final String csv = buildPerExerciseCsv(sets: sets, exerciseNames: names);
    expect(csv, contains(',"5.00"'));
  });

  test('空列表：只有表头（不编造任何行）', () {
    final String csv = buildPerExerciseCsv(sets: const <SetRecord>[], exerciseNames: names);
    expect(csv.trim().split('\n').length, 1);
  });
}
