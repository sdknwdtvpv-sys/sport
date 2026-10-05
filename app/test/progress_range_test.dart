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

  test('两端标签：左旧右新，且右边是"今天"（不是明天）', () {
    expect(seriesEndLabels(today, ProgressRange.week), <String>['9/29', '10/5']);
    expect(seriesEndLabels(today, ProgressRange.year), <String>['10/6', '10/5']);
  });
}
