/// 练了么 · **进阶分析**（Ultra 权益 7）的判据
///
/// 这一份测的全是**最容易错、错了还很难看出来**的地方：
///   * 桶怎么切（周一算起点、月与季按自然月/季推进 —— 不是减 30/90 天）；
///   * 半开区间 `[from, to)`：跨月/跨年不能重复计数，也不能漏掉最后一天；
///   * **只有一组数据 / 上一周期为空**时怎么显示（不许编百分比、不许编趋势）；
///   * 空桶要留在序列里（断掉的周如实显示 0，而不是把两个不相邻的点连成一条上涨的线）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/progress/advanced_analysis.dart';

SetRecord _set({
  String exerciseId = 'bench',
  int reps = 10,
  double? weightKg = 60,
  required DateTime at,
  String id = 's',
}) =>
    SetRecord(
      id: '$id-${at.millisecondsSinceEpoch}-$reps',
      workoutId: 'w',
      exerciseId: exerciseId,
      setIndex: 1,
      reps: reps,
      weightKg: weightKg,
      completedAtMs: at.millisecondsSinceEpoch,
    );

void main() {
  group('桶怎么切（跨月跨年最容易错的地方）', () {
    test('周：一律归到**周一**（周日也算上一周，不搞"周日起始"那套）', () {
      // 2026-10-10 是周六
      expect(bucketStart(DateTime(2026, 10, 10), AnalysisRange.week),
          DateTime(2026, 10, 5));
      // 2026-10-11 是周日 —— ISO 口径下它属于 10-05 那一周
      expect(bucketStart(DateTime(2026, 10, 11), AnalysisRange.week),
          DateTime(2026, 10, 5));
      expect(bucketStart(DateTime(2026, 10, 12), AnalysisRange.week),
          DateTime(2026, 10, 12), reason: '周一当天是新一周的起点');
    });

    test('周跨月：10-01（周四）属于 09-28 那一周', () {
      expect(bucketStart(DateTime(2026, 10, 1), AnalysisRange.week),
          DateTime(2026, 9, 28));
    });

    test('月与季：按**自然**月/季推进，不是减 30 / 90 天', () {
      expect(bucketStart(DateTime(2026, 10, 10), AnalysisRange.month),
          DateTime(2026, 10));
      expect(bucketStart(DateTime(2026, 10, 10), AnalysisRange.quarter),
          DateTime(2026, 10), reason: 'Q4 = 10 月起');
      expect(bucketStart(DateTime(2026, 3, 31), AnalysisRange.month),
          DateTime(2026, 3));
      expect(previousBucketStart(DateTime(2026, 3), AnalysisRange.month),
          DateTime(2026, 2), reason: '3 月往回退一个月是 2 月，不是 3 月 3 日');
      expect(previousBucketStart(DateTime(2026, 1), AnalysisRange.month),
          DateTime(2025, 12), reason: '跨年');
      expect(previousBucketStart(DateTime(2026, 1, 5), AnalysisRange.quarter),
          DateTime(2025, 10), reason: 'Q1 往回退一季是上一年 Q4');
      expect(nextBucket(DateTime(2026, 12), AnalysisRange.month), DateTime(2027, 1));
    });
  });

  group('区间是半开 [from, to)：不重复、不漏', () {
    test('边界上的那一组只算进一个周期', () {
      // 10-05 00:00 正好是周一那一桶的起点
      final List<SetRecord> sets = <SetRecord>[
        _set(at: DateTime(2026, 10, 5), id: 'a'),
        _set(at: DateTime(2026, 10, 11, 23, 59), id: 'b'),
        _set(at: DateTime(2026, 10, 12), id: 'c'), // 下一周
      ];
      final PeriodStats thisWeek = statsIn(sets,
          from: DateTime(2026, 10, 5), to: DateTime(2026, 10, 12));
      expect(thisWeek.sets, 2);
      expect(thisWeek.volumeKg, 1200);
      expect(thisWeek.sessions, 2, reason: '两天各一组');
      final PeriodStats lastWeek = statsIn(sets,
          from: DateTime(2026, 9, 28), to: DateTime(2026, 10, 5));
      expect(lastWeek.sets, 0);
    });

    test('容量 = 重量 × 次数；距离动作的容量恒为 0（`SetRecord.volume` 的规矩）', () {
      final List<SetRecord> sets = <SetRecord>[
        _set(at: DateTime(2026, 10, 6), reps: 10, weightKg: 60),
        _set(at: DateTime(2026, 10, 6), reps: 20, weightKg: null), // 自重
        // 有距离的组（有氧）：容量恒为 0 —— 拿"重量 × 秒数"当容量没有量纲意义
        SetRecord(
          id: 'run',
          workoutId: 'w',
          exerciseId: 'run',
          setIndex: 1,
          reps: 1800,
          distanceM: 5000,
          completedAtMs: DateTime(2026, 10, 6).millisecondsSinceEpoch,
        ),
      ];
      final PeriodStats st = statsIn(sets,
          from: DateTime(2026, 10, 5), to: DateTime(2026, 10, 12));
      expect(st.sets, 3);
      expect(st.volumeKg, 600, reason: '自重与有氧都不进容量');
      expect(st.bestWeightKg, 60);
    });

    test('最佳 1RM 只认 ≤12 次（Epley 在高次数下会误导）', () {
      final List<SetRecord> sets = <SetRecord>[
        _set(at: DateTime(2026, 10, 6), reps: 5, weightKg: 100),
        _set(at: DateTime(2026, 10, 6), reps: 20, weightKg: 200), // 次数过高 → 不算 1RM
      ];
      final PeriodStats st = statsIn(sets,
          from: DateTime(2026, 10, 5), to: DateTime(2026, 10, 12));
      expect(st.bestWeightKg, 200, reason: '最重一组仍然认它');
      // `estimate1RM` 自己会四舍五入到两位小数（116.67），所以容差要跟着它
      expect(st.best1Rm, closeTo(100 * (1 + 5 / 30), 0.01));
    });
  });

  group('周期对比：**不许编数**', () {
    test('上一周期为 0 时，变化率是 null（不是 0%、也不是 100%）', () {
      final List<SetRecord> sets = <SetRecord>[
        _set(at: DateTime(2026, 10, 6), reps: 10, weightKg: 60),
      ];
      final PeriodDelta d = compareLatestPeriods(sets,
          range: AnalysisRange.week, now: DateTime(2026, 10, 8));
      expect(d.current.volumeKg, 600);
      expect(d.previous.volumeKg, 0);
      expect(d.volumeChangePct, isNull, reason: '"从 0 到 600" 没有百分比可言');
      expect(d.volumeKgDelta, 600);
    });

    test('两个周期都有数据时，变化率就是两者之比', () {
      final List<SetRecord> sets = <SetRecord>[
        _set(at: DateTime(2026, 9, 30), reps: 10, weightKg: 50, id: 'prev'), // 上周
        _set(at: DateTime(2026, 10, 6), reps: 10, weightKg: 60, id: 'cur'), // 本周
      ];
      final PeriodDelta d = compareLatestPeriods(sets,
          range: AnalysisRange.week, now: DateTime(2026, 10, 8));
      expect(d.previous.volumeKg, 500);
      expect(d.current.volumeKg, 600);
      expect(d.volumeChangePct, closeTo(0.2, 1e-9));
    });

    test('1RM 破纪录的判定：只有两边都有估算值时才可能为真', () {
      final PeriodDelta none = PeriodDelta(
        current: PeriodStats.empty(DateTime(2026, 10, 5), DateTime(2026, 10, 12)),
        previous: PeriodStats.empty(DateTime(2026, 9, 28), DateTime(2026, 10, 5)),
      );
      expect(none.isNewPain, isFalse);
    });
  });

  group('单动作趋势', () {
    test('窗口里**每个桶都在**（断掉的周显示 0，不把两端连成一条假上涨的线）', () {
      final List<SetRecord> sets = <SetRecord>[
        _set(at: DateTime(2026, 9, 7), reps: 10, weightKg: 60), // 5 周前
        _set(at: DateTime(2026, 10, 6), reps: 10, weightKg: 70), // 本周
      ];
      final ExerciseTrend t = exerciseTrend(sets,
          exerciseId: 'bench', range: AnalysisRange.week, now: DateTime(2026, 10, 8), buckets: 6);
      expect(t.points.length, 6, reason: '窗口有 6 个桶，空桶也要在');
      // 窗口是「从本周往回数 6 个桶」→ 08-31 起；09-07 那组落在第 2 个桶里
      expect(t.points.first.volumeKg, 0, reason: '08-31 那一周没练');
      expect(t.points[1].volumeKg, 600);
      expect(t.points.last.volumeKg, 700);
      expect(t.points.where((TrendPoint p) => p.sets == 0).length, 4,
          reason: '中间那 4 周没练 —— 它们必须如实是 0');
      expect(t.hasHistory, isTrue);
    });

    test('从没练过这个动作 → 一串空桶，hasHistory 为假（界面据此说"还没有记录"）', () {
      final ExerciseTrend t = exerciseTrend(<SetRecord>[],
          exerciseId: 'bench', range: AnalysisRange.month, now: DateTime(2026, 10, 8), buckets: 3);
      expect(t.points.length, 3);
      expect(t.hasHistory, isFalse);
      expect(t.topWeightChangePct, isNull);
    });

    test('起步 → 现在的重量变化：看的是"起步那 30 天 vs 最近 30 天"，不是历史最大', () {
      final List<SetRecord> sets = <SetRecord>[
        _set(at: DateTime(2026, 9, 1), reps: 8, weightKg: 50),
        _set(at: DateTime(2026, 10, 6), reps: 8, weightKg: 65),
      ];
      final ExerciseTrend t = exerciseTrend(sets,
          exerciseId: 'bench', range: AnalysisRange.week, now: DateTime(2026, 10, 8), buckets: 8);
      expect(t.firstTopWeightKg, 50, reason: '最早那 30 天里最重的一组是 50 kg');
      expect(t.latestTopWeightKg, 65);
      expect(t.topWeightChangePct, closeTo(0.3, 1e-9));
    });

    test('"最近一次的重量"取近 30 天最重的一组（热身组不许拉低结论）', () {
      final List<SetRecord> sets = <SetRecord>[
        _set(at: DateTime(2026, 9, 1), reps: 5, weightKg: 100),
        _set(at: DateTime(2026, 10, 7), reps: 12, weightKg: 40, id: 'warm'), // 最近但很轻
        _set(at: DateTime(2026, 10, 5), reps: 5, weightKg: 95),
      ];
      final ExerciseTrend t = exerciseTrend(sets,
          exerciseId: 'bench', range: AnalysisRange.week, now: DateTime(2026, 10, 8), buckets: 8);
      expect(t.latestTopWeightKg, 95, reason: '不该被 40kg 那组热身拉低');
    });

    test('只统计**这个动作**的组（别的动作不许混进来）', () {
      final List<SetRecord> sets = <SetRecord>[
        _set(at: DateTime(2026, 10, 6), reps: 10, weightKg: 60, exerciseId: 'bench'),
        _set(at: DateTime(2026, 10, 6), reps: 10, weightKg: 100, exerciseId: 'squat'),
      ];
      final ExerciseTrend t = exerciseTrend(sets,
          exerciseId: 'bench', range: AnalysisRange.week, now: DateTime(2026, 10, 8), buckets: 2);
      expect(t.latest.sets, 1);
      expect(t.latest.bestWeightKg, 60);
    });
  });

  group('挑哪些动作进列表', () {
    test('按最近 90 天的组数从多到少，同数按 id 定序（结果必须稳定）', () {
      final List<SetRecord> sets = <SetRecord>[
        for (int i = 0; i < 5; i++)
          _set(at: DateTime(2026, 10, 6), exerciseId: 'squat', id: 'sq$i'),
        for (int i = 0; i < 9; i++)
          _set(at: DateTime(2026, 10, 6), exerciseId: 'bench', id: 'be$i'),
        _set(at: DateTime(2026, 10, 6), exerciseId: 'row', id: 'ro'),
        // 90 天以前的记录不算
        for (int i = 0; i < 30; i++)
          _set(at: DateTime(2026, 1, 1), exerciseId: 'old', id: 'ol$i'),
      ];
      final List<String> ids = topExercisesBySets(sets, now: DateTime(2026, 10, 8), limit: 8);
      expect(ids, <String>['bench', 'squat', 'row'],
          reason: '按组数排；90 天前的"old"不进列表');
    });

    test('没有记录时是空列表（界面据此说"先练几次"）', () {
      expect(topExercisesBySets(<SetRecord>[], now: DateTime(2026, 10, 8)), isEmpty);
    });
  });
}
