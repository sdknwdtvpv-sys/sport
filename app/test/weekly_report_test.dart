/// 周报 / 月报（第二部分第 1 条）的判据自测。
///
/// 周报最容易出的两种错，都会让用户觉得"这 App 在瞎写"：
///   1. **算错周**：把"最近 7 天"当成"上周"（今天写的数明天就对不上）；
///   2. **天天顶在首页**（回顾变成广告），或者**没练也推一张卡**（"你上周练了 0 次"）。
/// 两条都钉在这里，而且是纯函数级的 —— 不必去改系统时钟。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/progress/weekly_report.dart';

SetRecord _set({
  required String workout,
  required DateTime at,
  String exercise = 'ex_bb_bench_press',
  int reps = 8,
  double? weight = 60,
  double? distanceM,
}) =>
    SetRecord(
      id: '$workout-${at.millisecondsSinceEpoch}-$exercise',
      workoutId: workout,
      exerciseId: exercise,
      setIndex: 0,
      reps: reps,
      weightKg: weight,
      distanceM: distanceM,
      completedAtMs: at.millisecondsSinceEpoch,
    );

void main() {
  // 2026-10-05 是周一 → "上周" = 9/28（周一）～ 10/4（周日）
  final DateTime monday = DateTime(2026, 10, 5, 9);

  group('算哪一周', () {
    test('★ 周一看到的"上周"是**上一个完整周**（9/28 ~ 10/4），不是最近 7 天', () {
      final WeeklyReport r = weeklyReportFor(<SetRecord>[], monday);
      expect(r.start, DateTime(2026, 9, 28));
      expect(r.end, DateTime(2026, 10, 5));
      expect(r.rangeLabel, '9 月 28 日 – 10 月 4 日',
          reason: '结束日要显示成**周日**（end 是下周一 00:00，直接写会差一天）');
    });

    test('周二看到的还是同一周（周一没看、周二看，数不能变）', () {
      final List<SetRecord> sets = <SetRecord>[
        _set(workout: 'w1', at: DateTime(2026, 9, 30, 19)),
        _set(workout: 'w2', at: DateTime(2026, 10, 2, 19)),
      ];
      final WeeklyReport a = weeklyReportFor(sets, DateTime(2026, 10, 5, 9));
      final WeeklyReport b = weeklyReportFor(sets, DateTime(2026, 10, 6, 22));
      expect(b.start, a.start);
      expect(b.sessions, a.sessions);
      expect(b.rangeLabel, a.rangeLabel);
    });

    test('★ 本周的记录**不算进上周**（否则周报每天都在变）', () {
      final List<SetRecord> sets = <SetRecord>[
        _set(workout: 'last', at: DateTime(2026, 10, 1, 19)),
        _set(workout: 'this', at: DateTime(2026, 10, 5, 19)), // 本周一
      ];
      final WeeklyReport r = weeklyReportFor(sets, monday);
      expect(r.sessions, 1, reason: '本周一那次不属于"上周"');
    });
  });

  group('数字与人话', () {
    test('次数 / 天数 / 组数 / 容量 / 时长都算得对', () {
      final List<SetRecord> sets = <SetRecord>[
        // 同一天两场（一天两练），每场两组
        _set(workout: 'w1', at: DateTime(2026, 9, 29, 9), weight: 60, reps: 10),
        _set(workout: 'w1', at: DateTime(2026, 9, 29, 9, 30), weight: 60, reps: 10),
        _set(workout: 'w2', at: DateTime(2026, 9, 29, 20), weight: 100, reps: 5),
        // 另一天一场
        _set(workout: 'w3', at: DateTime(2026, 10, 1, 19), weight: 60, reps: 10),
        _set(workout: 'w3', at: DateTime(2026, 10, 1, 19, 30), weight: 60, reps: 10),
      ];
      final WeeklyReport r = weeklyReportFor(sets, monday);
      expect(r.sessions, 3, reason: '三场训练（按 workoutId 去重）');
      expect(r.activeDays, 2, reason: '练了两天');
      expect(r.totalSets, 5);
      expect(r.volumeKg, 600 + 600 + 500 + 600 + 600);
      expect(r.exerciseCount, 1, reason: '这五组都是同一个动作');
      expect(r.durationMin, 60,
          reason: '每场按最后一组减第一组算：w1 那场 30 分钟、w2 那场 0 分钟、w3 那场 60 分钟');
      expect(r.bestDayVolumeKg, 600 + 600 + 500, reason: '9/29 那天最猛');
    });

    test('★ 破纪录只跟"这一周之前"比：同一周练两次，第二次不算破纪录', () {
      final List<SetRecord> sets = <SetRecord>[
        // 更早的历史：60 kg
        _set(workout: 'old', at: DateTime(2026, 9, 1, 19), weight: 60),
        // 这一周：先 70（破了 60）、再 75（**不是**破纪录 —— 它只比本周的 70 高）
        _set(workout: 'w1', at: DateTime(2026, 9, 29, 19), weight: 70),
        _set(workout: 'w2', at: DateTime(2026, 10, 1, 19), weight: 75),
      ];
      final WeeklyReport r = weeklyReportFor(sets, monday);
      expect(r.prs.length, 1, reason: '同一周内的先后不算破纪录（那是热身）');
      expect(r.prs.first.detail, contains('75'),
          reason: '报的是这一周的最好成绩（75 kg），与它比的是上周之前的 60 kg');
    });

    test('历史没有那个动作 → 第一次练不算"破纪录"（没有可比的东西）', () {
      final WeeklyReport r = weeklyReportFor(<SetRecord>[
        _set(workout: 'w1', at: DateTime(2026, 9, 29, 19), exercise: 'ex_new', weight: 80),
      ], monday);
      expect(r.prs, isEmpty);
    });

    test('新徽章数 = 这一周之前的徽章与现在的差（同一份记录上算两次，不落库）', () {
      final List<SetRecord> sets = <SetRecord>[
        _set(workout: 'w1', at: DateTime(2026, 9, 29, 19)),
      ];
      final WeeklyReport r = weeklyReportFor(sets, monday);
      expect(r.badgesUnlocked, greaterThan(0), reason: '练过一次至少解锁「首训」');
    });

    test('headline 与 statsLine：数字都在，而且**没练就如实说**', () {
      final WeeklyReport r = weeklyReportFor(<SetRecord>[
        _set(workout: 'w1', at: DateTime(2026, 9, 29, 19), weight: 60, reps: 10),
      ], monday);
      // 只有一次训练、一天、又是第一次拿徽章 → headline 走「新徽章」那一支
      // （分支顺序是刻意的：对只练了一次的人，说「拿到 N 枚新徽章」比「练了 1 次」更像回事）
      expect(r.headline, contains('新徽章'));
      expect(r.statsLine, contains('1 次训练'));
      expect(r.statsLine, contains('吨'));
      expect(r.shareable, isTrue);

      final WeeklyReport empty = weeklyReportFor(<SetRecord>[], monday);
      expect(empty.isEmpty, isTrue);
      expect(empty.headline, contains('没练'));
      expect(empty.shareable, isFalse, reason: '没练过的一周不值得做成卡');
    });
  });

  group('什么时候给看（shouldShowWeeklyReport）', () {
    final List<SetRecord> lastWeek = <SetRecord>[
      _set(workout: 'w1', at: DateTime(2026, 9, 30, 19)),
    ];

    test('★ 只在周一 / 周二出现，周三到周日都不给（回顾不许变成广告）', () {
      expect(shouldShowWeeklyReport(lastWeek, DateTime(2026, 10, 5, 9)), isTrue,
          reason: '周一');
      expect(shouldShowWeeklyReport(lastWeek, DateTime(2026, 10, 6, 9)), isTrue,
          reason: '周二');
      for (int d = 7; d <= 11; d++) {
        expect(shouldShowWeeklyReport(lastWeek, DateTime(2026, 10, d, 9)), isFalse,
            reason: '周三~周日（10/$d）不该再推周报');
      }
    });

    test('★ 上周一次都没练 → 周一也不给看（不推"你上周练了 0 次"）', () {
      expect(shouldShowWeeklyReport(<SetRecord>[], DateTime(2026, 10, 5, 9)), isFalse);
    });

    test('上周练过、但记录都在更早 → 依然不给看（只认上一个完整周）', () {
      final List<SetRecord> old = <SetRecord>[
        _set(workout: 'w1', at: DateTime(2026, 9, 1, 19)),
      ];
      expect(shouldShowWeeklyReport(old, DateTime(2026, 10, 5, 9)), isFalse);
    });
  });

  test('weekOrdinal：同一年里的第几周，跨年不会变成 0 或负数', () {
    expect(weekOrdinal(DateTime(2026, 1, 5)), 2, reason: '2026-01-01 是那年的第一个周四 → 1/5 属第 2 周');
    expect(weekOrdinal(DateTime(2026, 12, 28)), greaterThan(50));
    expect(weekOrdinal(DateTime(2027, 1, 4)), greaterThanOrEqualTo(1));
  });
}
