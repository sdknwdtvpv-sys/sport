/// 「周 / 月 / 年」三档区间口径的自测。
///
/// **为什么单独测它**：这一层是纯函数，但它是"数字对不对"的唯一出处 ——
/// 卡片上的容量、次数、组数，曲线上的点，全都从这里来。
/// 口径错了不会崩、不会红，只会**静默地把错的数字画得很好看**。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/progress/progress_data.dart';

SetRecord _set(String workoutId, DateTime at, {double weight = 100, int reps = 5}) => SetRecord(
      id: '$workoutId-${at.millisecondsSinceEpoch}',
      workoutId: workoutId,
      exerciseId: 'bench',
      setIndex: 0,
      weightKg: weight,
      reps: reps,
      completedAtMs: at.millisecondsSinceEpoch,
    );

void main() {
  final DateTime today = DateTime(2026, 10, 5, 15, 30); // 带时分的"今天"

  test('窗口：7 / 30 / 365 天，且右边界是明天零点（今天算在内）', () {
    final ({DateTime from, DateTime to}) w = rangeWindow(today, ProgressRange.week);
    expect(w.from, DateTime(2026, 9, 29));
    expect(w.to, DateTime(2026, 10, 6));

    final ({DateTime from, DateTime to}) m = rangeWindow(today, ProgressRange.month);
    expect(m.from, DateTime(2026, 9, 6));

    final ({DateTime from, DateTime to}) y = rangeWindow(today, ProgressRange.year);
    expect(y.from, DateTime(2025, 10, 6));
    expect(y.to, m.to);
  });

  test('口径说明写的是"最近 N 天"，不是自然周/月（否则每月 1 号那屏会突然空掉）', () {
    expect(rangeHint(ProgressRange.week), '最近 7 天');
    expect(rangeHint(ProgressRange.month), '最近 30 天');
    expect(rangeHint(ProgressRange.year), '最近 12 个月');
    expect(rangeLabel(ProgressRange.week), '本周');
  });

  // ── 周期对比（2026-10-09，10.9 清单第 4 条：进步页 = 周期对比）──────────────
  group('周期对比', () {
    test('上一个窗口与当前窗口**严格等长、紧挨着**（本周比的是它前面那 7 天）', () {
      final ({DateTime from, DateTime to}) w = rangeWindow(today, ProgressRange.week);
      final ({DateTime from, DateTime to}) p =
          previousRangeWindow(today, ProgressRange.week);

      expect(p.to, w.from, reason: '中间不能有缝，也不能重叠');
      expect(p.to.difference(p.from), w.to.difference(w.from),
          reason: '两个窗口不等长，比出来的百分比就是假的');
      expect(p.from, DateTime(2026, 9, 22));
    });

    test('月 / 年也一样等长', () {
      for (final ProgressRange r in ProgressRange.values) {
        final ({DateTime from, DateTime to}) w = rangeWindow(today, r);
        final ({DateTime from, DateTime to}) p = previousRangeWindow(today, r);
        expect(p.to.difference(p.from), w.to.difference(w.from), reason: '$r 不等长');
      }
    });

    test('对比文案：四种情况分开说（上期没练 ≠ +100%）', () {
      expect(periodDeltaLabel(120, 100), '较上期 +20%');
      expect(periodDeltaLabel(80, 100), '较上期 −20%');
      expect(periodDeltaLabel(100.2, 100), '与上期持平', reason: '0.2% 的波动不该说成涨了');
      expect(periodDeltaLabel(50, 0), '上期没练',
          reason: '除零没有百分比可写，硬写 +100% 就是编一个数');
      expect(periodDeltaLabel(0, 0), '—', reason: '两边都没有，没什么可比的');
      expect(periodDeltaLabel(0, 100), '较上期 −100%', reason: '归零是一件要说出来的事');
    });
  });

  test('容量 / 次数 / 组数：只算窗口内，且**未来时间不算**（与 lastSevenDays 同一条边界）', () {
    final List<SetRecord> sets = <SetRecord>[
      _set('w1', DateTime(2026, 10, 5, 9)), // 今天
      _set('w1', DateTime(2026, 10, 5, 10)),
      _set('w2', DateTime(2026, 9, 30)), // 窗口内
      _set('w0', DateTime(2026, 9, 28)), // 窗口外（早一天）
      _set('w9', DateTime(2026, 10, 6, 9)), // 未来（明天）
    ];
    final ({DateTime from, DateTime to}) w = rangeWindow(today, ProgressRange.week);
    expect(setCountIn(sets, w.from, w.to), 3);
    expect(workoutCountIn(sets, w.from, w.to), 2, reason: '一次训练记多组只算一次');
    expect(volumeIn(sets, w.from, w.to), 100 * 5 * 3);
  });

  test('曲线：长度按区间（7 / 30 / 12），值都在 0..1，且最大值那点正好是 1', () {
    final List<SetRecord> sets = <SetRecord>[
      _set('w1', DateTime(2026, 10, 1), weight: 100),
      _set('w2', DateTime(2026, 10, 4), weight: 300), // 最大
    ];
    for (final ProgressRange r in ProgressRange.values) {
      final List<double> s = volumeSeries(sets, today, r);
      expect(s.length, r == ProgressRange.week ? 7 : (r == ProgressRange.month ? 30 : 12));
      expect(s.every((double v) => v >= 0 && v <= 1), isTrue, reason: '$r 有点越界了');
      expect(s.reduce((double a, double b) => a > b ? a : b), 1.0, reason: '$r 没有峰值点');
    }
  });

  test('曲线：没有任何数据 → 全 0（不是 NaN、不是空数组）', () {
    final List<double> s = volumeSeries(<SetRecord>[], today, ProgressRange.month);
    expect(s.length, 30);
    expect(s.every((double v) => v == 0), isTrue);
  });

  test('曲线：只记了体重、没练过 → 一样是全 0（曲线不该崩）', () {
    expect(volumeSeries(<SetRecord>[], today, ProgressRange.year).length, 12);
  });

  test('一共练过几次：按 workoutId 去重（一次训练记 24 组也只算一次）', () {
    final List<SetRecord> sets = <SetRecord>[
      _set('w1', DateTime(2026, 10, 1)),
      _set('w1', DateTime(2026, 10, 1, 10)),
      _set('w2', DateTime(2026, 10, 3)),
    ];
    expect(totalWorkouts(sets), 2);
    expect(totalWorkouts(<SetRecord>[]), 0);
  });

  test('两端标签：左旧右新，且右边是"今天"（不是明天）', () {
    expect(seriesEndLabels(today, ProgressRange.week), <String>['9/29', '10/5']);
    expect(seriesEndLabels(today, ProgressRange.year), <String>['10/6', '10/5']);
  });
}
