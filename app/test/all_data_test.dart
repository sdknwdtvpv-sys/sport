/// 练了么 · S9「全部数据」的纯函数测试
///
/// 日期窗口与"含首含尾"最容易做错，所以边界单独测。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/progress/all_data.dart';

/// 固定"今天"，否则测试会在月初/月末飘。
/// 2026-09-28 是**周一**，周报的边界正好能测到。
final DateTime kToday = DateTime(2026, 9, 28, 10);

SetRecord _set({
  required String id,
  String workoutId = 'w1',
  String exerciseId = 'bench',
  int setIndex = 1,
  int reps = 8,
  double? weightKg = 60,
  DateTime? at,
  SetType setType = SetType.normal,
}) =>
    SetRecord(
      id: id,
      workoutId: workoutId,
      exerciseId: exerciseId,
      setIndex: setIndex,
      reps: reps,
      completedAtMs: (at ?? DateTime(2026, 9, 28, 9)).millisecondsSinceEpoch,
      weightKg: weightKg,
      setType: setType,
    );

void main() {
  group('按动作：历史最佳', () {
    test('最大重量 / 最多次数 / 总容量', () {
      final ExerciseStats s = buildExerciseStats(
        exerciseId: 'bench',
        name: '杠铃卧推',
        today: kToday,
        sets: <SetRecord>[
          _set(id: 'a', reps: 8, weightKg: 60), // 480
          _set(id: 'b', reps: 5, weightKg: 80, setIndex: 2), // 400
          _set(id: 'c', reps: 12, weightKg: 50, setIndex: 3), // 600
        ],
      );

      expect(s.setCount, 3);
      expect(s.totalVolumeKg, 480 + 400 + 600);
      expect(s.bestWeightKg, 80);
      expect(s.bestReps, 12);
      expect(s.isEmpty, isFalse);
    });

    test('最佳 1RM 用估算值，而不是最大重量', () {
      final ExerciseStats s = buildExerciseStats(
        exerciseId: 'bench',
        name: '杠铃卧推',
        today: kToday,
        sets: <SetRecord>[
          _set(id: 'a', reps: 5, weightKg: 80), // 80 × (1+5/30) = 93.33
          _set(id: 'b', reps: 10, weightKg: 60, setIndex: 2), // 60 × 1.333 = 80
        ],
      );
      // 80kg×5 比 60kg×10 更强，尽管后者容量更大
      expect(s.best1RM, closeTo(93.33, 0.01));
    });

    test('自重动作：重量为 null，比次数', () {
      final ExerciseStats s = buildExerciseStats(
        exerciseId: 'pullup',
        name: '引体向上',
        today: kToday,
        sets: <SetRecord>[
          _set(id: 'a', exerciseId: 'pullup', reps: 12, weightKg: null),
        ],
      );
      expect(s.isBodyweight, isTrue);
      expect(s.bestWeightKg, isNull);
      expect(s.best1RM, isNull, reason: '没有重量就算不出 1RM');
      expect(s.bestReps, 12);
    });

    test('热身组不计入任何统计', () {
      final ExerciseStats s = buildExerciseStats(
        exerciseId: 'bench',
        name: '杠铃卧推',
        today: kToday,
        sets: <SetRecord>[
          _set(id: 'wu', reps: 15, weightKg: 100, setType: SetType.warmup),
          _set(id: 'a', reps: 8, weightKg: 60, setIndex: 2),
        ],
      );
      expect(s.setCount, 1);
      expect(s.bestWeightKg, 60, reason: '热身的 100kg 不算历史最佳');
    });

    test('没有任何记录时是空的，且曲线不会除以 0', () {
      final ExerciseStats s = buildExerciseStats(
        exerciseId: 'bench',
        name: '杠铃卧推',
        today: kToday,
        sets: const <SetRecord>[],
      );
      expect(s.isEmpty, isTrue);
      expect(s.volumeTrend.every((double v) => v == 0), isTrue);
      expect(s.oneRmTrend.every((double v) => v == 0), isTrue);
    });
  });

  group('按动作：趋势', () {
    test('容量趋势的长度 = 窗口天数，最后一天是今天', () {
      final ExerciseStats s = buildExerciseStats(
        exerciseId: 'bench',
        name: '杠铃卧推',
        today: kToday,
        days: 7,
        sets: <SetRecord>[_set(id: 'a', at: kToday)],
      );
      expect(s.volumeByDay, hasLength(7));
      expect(s.volumeByDay.last.day, DateTime(2026, 9, 28));
      expect(s.volumeByDay.first.day, DateTime(2026, 9, 22));
    });

    test('容量与 1RM 可以背离：容量涨但 1RM 不涨', () {
      final ExerciseStats s = buildExerciseStats(
        exerciseId: 'bench',
        name: '杠铃卧推',
        today: kToday,
        days: 7,
        sets: <SetRecord>[
          // 昨天：80kg × 5（1RM ≈ 93.3，容量 400）
          _set(id: 'a', reps: 5, weightKg: 80, at: DateTime(2026, 9, 27, 9)),
          // 今天：60kg × 10，15 组（容量大得多，但 1RM 更低）
          for (int i = 0; i < 15; i++)
            _set(
              id: 'b$i',
              reps: 10,
              weightKg: 60,
              setIndex: i + 1,
              at: DateTime(2026, 9, 28, 9),
            ),
        ],
      );

      final int yesterday = s.volumeByDay.length - 2;
      final int todayIdx = s.volumeByDay.length - 1;
      expect(s.volumeByDay[todayIdx].volumeKg,
          greaterThan(s.volumeByDay[yesterday].volumeKg),
          reason: '今天的容量更大');
      expect(s.oneRmByDay[todayIdx], lessThan(s.oneRmByDay[yesterday]),
          reason: '但 1RM 更低 —— 这正是两条曲线要分开画的原因');
    });
  });

  group('按时间：周报 / 月报', () {
    test('周报从**周一**起（中文习惯），不含上周日', () {
      // 2026-09-28 是周一，所以本周只有 09-28 这一天
      final PeriodReport r = buildWeekReport(
        sets: <SetRecord>[
          _set(id: 'sun', at: DateTime(2026, 9, 27, 9)), // 上周日
          _set(id: 'mon', at: DateTime(2026, 9, 28, 9)), // 本周一
        ],
        today: kToday,
      );
      expect(r.start, DateTime(2026, 9, 28));
      expect(r.setCount, 1, reason: '上周日不该算进本周');
      expect(r.activeDays, 1);
    });

    test('月报含首含尾，月末那天的记录算进去', () {
      final PeriodReport r = buildMonthReport(
        sets: <SetRecord>[
          _set(id: 'first', at: DateTime(2026, 9, 1, 8)),
          _set(id: 'last', at: DateTime(2026, 9, 30, 23)),
        ],
        today: DateTime(2026, 9, 30, 23),
      );
      expect(r.setCount, 2, reason: '月末 23:00 的记录必须算进本月');
    });

    test('训练次数按 workoutId 去重，不是按组数', () {
      final PeriodReport r = buildMonthReport(
        sets: <SetRecord>[
          _set(id: 'a', workoutId: 'w1'),
          _set(id: 'b', workoutId: 'w1', setIndex: 2),
          _set(id: 'c', workoutId: 'w2'),
        ],
        today: kToday,
      );
      expect(r.workoutCount, 2);
      expect(r.setCount, 3);
    });

    test('练了几天（activeDays）与训练次数不是一回事', () {
      final PeriodReport r = buildMonthReport(
        sets: <SetRecord>[
          _set(id: 'a', workoutId: 'w1', at: DateTime(2026, 9, 28, 8)),
          _set(id: 'b', workoutId: 'w2', at: DateTime(2026, 9, 28, 20)),
        ],
        today: kToday,
      );
      expect(r.workoutCount, 2);
      expect(r.activeDays, 1, reason: '同一天练了两次');
    });

    test('热身组不计入周报 / 月报', () {
      final PeriodReport r = buildMonthReport(
        sets: <SetRecord>[
          _set(id: 'wu', setType: SetType.warmup),
        ],
        today: kToday,
      );
      expect(r.isEmpty, isTrue);
    });
  });

  group('月趋势', () {
    test('最近 6 个月，从旧到新', () {
      final List<MonthVolume> ms = recentMonthVolumes(
        sets: <SetRecord>[_set(id: 'a', at: DateTime(2026, 9, 10))],
        today: kToday,
        months: 6,
      );
      expect(
        ms.map((MonthVolume m) => m.label).toList(),
        <String>['2026-04', '2026-05', '2026-06', '2026-07', '2026-08', '2026-09'],
      );
      expect(ms.last.volumeKg, 480);
    });

    test('跨年边界也对（1 月往前推是去年 12 月）', () {
      final List<MonthVolume> ms = recentMonthVolumes(
        sets: const <SetRecord>[],
        today: DateTime(2026, 2, 15),
        months: 3,
      );
      expect(
        ms.map((MonthVolume m) => m.label).toList(),
        <String>['2025-12', '2026-01', '2026-02'],
      );
    });

    test('月末不会因为减月份而溢出（3 月 31 日往前推不能跳到 3 月）', () {
      final List<MonthVolume> ms = recentMonthVolumes(
        sets: const <SetRecord>[],
        today: DateTime(2026, 3, 31),
        months: 2,
      );
      expect(
        ms.map((MonthVolume m) => m.label).toList(),
        <String>['2026-02', '2026-03'],
      );
    });
  });
}
