/// 练了么 · 年报聚合纯函数（Ultra 权益 9）
///
/// 边界：跨年、闰年、空数据、只有热身组、只有有氧/自重、部位分布、PR 口径。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/profile/annual_report.dart';

SetRecord _set({
  required String id,
  required String workoutId,
  required String exerciseId,
  required int atMs,
  int reps = 8,
  double? weightKg,
  double? distanceM,
  SetType setType = SetType.normal,
  int setIndex = 1,
}) =>
    SetRecord(
      id: id,
      workoutId: workoutId,
      exerciseId: exerciseId,
      setIndex: setIndex,
      reps: reps,
      completedAtMs: atMs,
      weightKg: weightKg,
      distanceM: distanceM,
      setType: setType,
    );

void main() {
  final Map<String, String> names = <String, String>{
    'bench': '卧推',
    'pull': '引体向上',
    'plank': '平板支撑',
    'run': '跑步',
  };
  final Map<String, String> muscles = <String, String>{
    'bench': 'chest',
    'pull': 'back',
    'plank': 'core',
    'run': 'legs',
  };
  final Set<String> timeExercises = <String>{'plank'};

  AnnualReport build(List<SetRecord> sets, int year) => buildAnnualReport(
        sets: sets,
        year: year,
        exerciseNames: names,
        muscleGroups: muscles,
        timeExercises: timeExercises,
      );

  test('空数据：hasData=false，所有数字为 0（不编）', () {
    final AnnualReport r = build(const <SetRecord>[], 2026);
    expect(r.hasData, isFalse);
    expect(r.workoutCount, 0);
    expect(r.setCount, 0);
    expect(r.trainingDays, 0);
    expect(r.attendanceWeeks, 0);
    expect(r.monthsWithData, 0);
    expect(r.totalVolumeKg, 0);
    expect(r.hasDistance, isFalse);
    expect(r.bestPrs, isEmpty);
    expect(r.muscleVolumeKg, isEmpty);
  });

  test('只有热身组：等同空数据（热身不是训练量）', () {
    final AnnualReport r = build(<SetRecord>[
      _set(
        id: 'w1',
        workoutId: 'wo1',
        exerciseId: 'bench',
        atMs: DateTime(2026, 3, 1, 10).millisecondsSinceEpoch,
        weightKg: 20,
        setType: SetType.warmup,
      ),
    ], 2026);
    expect(r.hasData, isFalse);
    expect(r.setCount, 0);
    expect(r.muscleVolumeKg, isEmpty);
  });

  test('只有有氧：次数/天数照实，容量 0、无 PR、有里程', () {
    final AnnualReport r = build(<SetRecord>[
      _set(
        id: 'c1',
        workoutId: 'wo1',
        exerciseId: 'run',
        atMs: DateTime(2026, 5, 1, 8).millisecondsSinceEpoch,
        reps: 1800,
        distanceM: 5000,
      ),
    ], 2026);
    expect(r.hasData, isTrue);
    expect(r.setCount, 1);
    expect(r.workoutCount, 1);
    expect(r.totalVolumeKg, 0);
    expect(r.hasVolume, isFalse);
    expect(r.distanceM, 5000);
    expect(r.hasDistance, isTrue);
    expect(r.bestPrs, isEmpty, reason: '有氧的成绩是里程/配速，不是 PR');
    expect(r.muscleVolumeKg, isEmpty);
  });

  test('跨年边界：12-31 与 1-1 分属两年，不平均分摊', () {
    final List<SetRecord> sets = <SetRecord>[
      _set(id: 'a', workoutId: 'w2025', exerciseId: 'bench',
          atMs: DateTime(2025, 12, 31, 23, 59).millisecondsSinceEpoch, weightKg: 100),
      _set(id: 'b', workoutId: 'w2026', exerciseId: 'bench',
          atMs: DateTime(2026, 1, 1, 0, 1).millisecondsSinceEpoch, weightKg: 80),
    ];
    expect(build(sets, 2025).setCount, 1);
    expect(build(sets, 2025).workoutCount, 1);
    expect(build(sets, 2026).setCount, 1);
    expect(build(sets, 2026).workoutCount, 1);
    expect(build(sets, 2026).totalVolumeKg, 80 * 8);
  });

  test('闰年 2 月 29 日算进当年；不存在的日期不会被凭空造出来', () {
    final SetRecord leap = _set(id: 'leap', workoutId: 'w1', exerciseId: 'bench',
        atMs: DateTime(2024, 2, 29, 12).millisecondsSinceEpoch, weightKg: 60);
    expect(build(<SetRecord>[leap], 2024).setCount, 1);
    expect(build(<SetRecord>[leap], 2024).monthsWithData, 1);
    expect(build(<SetRecord>[leap], 2023).setCount, 0);
  });

  test('训练天数 / 出勤周数 / 覆盖月份：同一天多组只算一天、周一跨年按发生年算', () {
    final List<SetRecord> sets = <SetRecord>[
      // 2026-01-01（周四）与 2026-01-05（周一）—— 两周
      _set(id: 'a', workoutId: 'wo1', exerciseId: 'bench',
          atMs: DateTime(2026, 1, 1, 10).millisecondsSinceEpoch, weightKg: 80),
      _set(id: 'b', workoutId: 'wo1', exerciseId: 'bench',
          atMs: DateTime(2026, 1, 1, 10, 30).millisecondsSinceEpoch, weightKg: 80),
      _set(id: 'c', workoutId: 'wo2', exerciseId: 'bench',
          atMs: DateTime(2026, 1, 5, 10).millisecondsSinceEpoch, weightKg: 80),
      // 2025-12-31（周三）属于 2025-12-29 那一周；2026 年里不出现 12-31，所以不混进来
      _set(id: 'd', workoutId: 'wo3', exerciseId: 'bench',
          atMs: DateTime(2025, 12, 31, 10).millisecondsSinceEpoch, weightKg: 80),
    ];
    final AnnualReport r = build(sets, 2026);
    expect(r.workoutCount, 2);
    expect(r.setCount, 3);
    expect(r.trainingDays, 2);
    expect(r.attendanceWeeks, 2);
    expect(r.monthsWithData, 1);
    expect(r.partialMonths, 1);
  });

  test('全年 12 个月时不再写"覆盖 N/12"（partialMonths=null）', () {
    final List<SetRecord> sets = <SetRecord>[
      for (int m = 1; m <= 12; m += 1)
        _set(id: 'm$m', workoutId: 'w$m', exerciseId: 'bench',
            atMs: DateTime(2026, m, 1, 10).millisecondsSinceEpoch, weightKg: 50),
    ];
    final AnnualReport r = build(sets, 2026);
    expect(r.monthsWithData, 12);
    expect(r.partialMonths, isNull);
  });

  test('PR 口径：负重比重量、自重比次数、按时长比秒数（有氧不算 PR）', () {
    final AnnualReport r = build(<SetRecord>[
      _set(id: 'b1', workoutId: 'w1', exerciseId: 'bench',
          atMs: DateTime(2026, 2, 1).millisecondsSinceEpoch, weightKg: 100, reps: 5),
      _set(id: 'b2', workoutId: 'w1', exerciseId: 'bench',
          atMs: DateTime(2026, 3, 1).millisecondsSinceEpoch, weightKg: 90, reps: 10),
      _set(id: 'p1', workoutId: 'w2', exerciseId: 'pull',
          atMs: DateTime(2026, 2, 2).millisecondsSinceEpoch, reps: 10),
      _set(id: 'p2', workoutId: 'w2', exerciseId: 'pull',
          atMs: DateTime(2026, 3, 2).millisecondsSinceEpoch, reps: 12),
      _set(id: 't1', workoutId: 'w3', exerciseId: 'plank',
          atMs: DateTime(2026, 2, 3).millisecondsSinceEpoch, reps: 45),
      _set(id: 't2', workoutId: 'w3', exerciseId: 'plank',
          atMs: DateTime(2026, 3, 3).millisecondsSinceEpoch, reps: 60),
    ], 2026);
    final Map<String, AnnualPr> byId = <String, AnnualPr>{
      for (final AnnualPr p in r.bestPrs) p.exerciseId: p,
    };
    expect(byId['bench']?.weightKg, 100);
    expect(byId['bench']?.reps, 5);
    expect(byId['pull']?.weightKg, isNull);
    expect(byId['pull']?.reps, 12);
    expect(byId['pull']?.isBodyweight, isTrue);
    expect(byId['plank']?.isTime, isTrue);
    expect(byId['plank']?.reps, 60);
    expect(r.bestPrs.length, 3);
  });

  test('部位分布按容量；未知动作归 unspecified；自重/有氧不产生容量', () {
    final AnnualReport r = build(<SetRecord>[
      _set(id: '1', workoutId: 'w1', exerciseId: 'bench',
          atMs: DateTime(2026, 2, 1).millisecondsSinceEpoch, weightKg: 100, reps: 5),
      _set(id: '2', workoutId: 'w1', exerciseId: 'pull',
          atMs: DateTime(2026, 2, 1).millisecondsSinceEpoch, reps: 10),
      _set(id: '3', workoutId: 'w2', exerciseId: 'unknown_ex',
          atMs: DateTime(2026, 2, 2).millisecondsSinceEpoch, weightKg: 10, reps: 10),
    ], 2026);
    expect(r.muscleVolumeKg['chest'], 500);
    expect(r.muscleVolumeKg.containsKey('back'), isFalse, reason: '自重没有容量，不该出现 0 行');
    expect(r.muscleVolumeKg['unspecified'], 100);
  });

  test('渲染幂等：同一输入算两次结果完全一致', () {
    final List<SetRecord> sets = <SetRecord>[
      _set(id: 'a', workoutId: 'w1', exerciseId: 'bench',
          atMs: DateTime(2026, 2, 1).millisecondsSinceEpoch, weightKg: 100, reps: 5),
      _set(id: 'b', workoutId: 'w2', exerciseId: 'pull',
          atMs: DateTime(2026, 3, 1).millisecondsSinceEpoch, reps: 12),
    ];
    final AnnualReport a = build(sets, 2026);
    final AnnualReport b = build(sets, 2026);
    expect(a.workoutCount, b.workoutCount);
    expect(a.setCount, b.setCount);
    expect(a.totalVolumeKg, b.totalVolumeKg);
    expect(a.trainingDays, b.trainingDays);
    expect(a.attendanceWeeks, b.attendanceWeeks);
    expect(a.bestPrs.map((AnnualPr p) => '${p.exerciseId}:${p.reps}:${p.weightKg}').join(','),
        b.bestPrs.map((AnnualPr p) => '${p.exerciseId}:${p.reps}:${p.weightKg}').join(','));
    expect(a.muscleVolumeKg.toString(), b.muscleVolumeKg.toString());
    expect(a.unit, WeightUnit.kg);
  });
}
