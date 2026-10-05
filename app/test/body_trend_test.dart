/// 练了么 · 身体数据**趋势**的纯计算（v1.52）
///
/// 这一层不碰界面，所以能用普通单测把判断钉死。四条最容易做错的地方：
///   1. 把 `null`（没记过）当成 0 画进曲线 —— 会造出"体重掉到 0"的假趋势；
///   2. 拿倒序的记录当时间顺序 —— 曲线会左右颠倒；
///   3. 只有一个点时也画一条线 —— 那是编出来的趋势；
///   4. 全部相等时把点压到 0 或 1 —— 平线贴着底/顶，读起来像"一直在最低点"。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/features/body/body_trend.dart';

BodyMetricData row(
  String date, {
  double? weight,
  double? waist,
  double? muscle,
}) =>
    BodyMetricData(
      id: 'bm_$date',
      date: date,
      weightKg: weight,
      waistCm: waist,
      muscleMassKg: muscle,
      updatedAt: 0,
    );

void main() {
  group('取值：只取"记过"的那些天', () {
    test('null 不是 0 —— 没记过的日子不进曲线', () {
      final BodyTrend t = bodyTrend(<BodyMetricData>[
        row('2026-09-01', weight: 72),
        row('2026-09-02,', waist: 80), // 这天没记体重
        row('2026-09-03', weight: 71),
      ], BodyTrendMetric.weight);

      expect(t.values, <double>[72, 71], reason: '中间那天没记体重，不能被当成 0');
      expect(t.samples.length, 2);
    });

    test('按日期升序 —— 传进来是倒序也画成正的时间轴', () {
      final BodyTrend t = bodyTrend(<BodyMetricData>[
        row('2026-09-03', weight: 71),
        row('2026-09-01', weight: 73),
        row('2026-09-02', weight: 72),
      ], BodyTrendMetric.weight);

      expect(t.values, <double>[73, 72, 71]);
      expect(t.firstDate, '2026-09-01', reason: '左端是最早那天');
      expect(t.lastDate, '2026-09-03');
    });

    test('三个指标各取各的列（腰围是 cm，别拿体重的数）', () {
      final List<BodyMetricData> rows = <BodyMetricData>[
        row('2026-09-01', weight: 72, waist: 81, muscle: 34),
        row('2026-09-02', weight: 71.5, waist: 80.5, muscle: 34.2),
      ];
      expect(bodyTrend(rows, BodyTrendMetric.weight).values, <double>[72, 71.5]);
      expect(bodyTrend(rows, BodyTrendMetric.waist).values, <double>[81, 80.5]);
      expect(bodyTrend(rows, BodyTrendMetric.muscle).values, <double>[34, 34.2]);
      expect(BodyTrendMetric.waist.unit, 'cm');
      expect(BodyTrendMetric.muscle.unit, 'kg');
    });
  });

  group('能不能画：少于两个点就不画', () {
    test('只有一天 → 画不出（而且不算"没变"）', () {
      final BodyTrend t = bodyTrend(<BodyMetricData>[
        row('2026-09-01', weight: 72),
      ], BodyTrendMetric.weight);

      expect(t.plottable, isFalse);
      expect(t.delta, isNull, reason: '一个点的"变化"是 null，不是 0');
    });

    test('两天才画得出，且切换器只列画得出的指标', () {
      final List<BodyMetricData> rows = <BodyMetricData>[
        row('2026-09-01', weight: 72, waist: 81),
        row('2026-09-02', weight: 71),
      ];
      expect(trendMetrics(rows), <BodyTrendMetric>[BodyTrendMetric.weight],
          reason: '腰围只记了一次，列出来等于给个点了没反应的入口');
    });

    test('一条记录都没有 → 一个指标都不列', () {
      expect(trendMetrics(const <BodyMetricData>[]), isEmpty);
    });
  });

  group('归一化与实际变化', () {
    test('最小映射到 0、最大映射到 1', () {
      expect(trendPoints(<double>[72, 71, 73]), <double>[0.5, 0.0, 1.0]);
    });

    test('全部相等 → 一条平线画在中间（不是贴底）', () {
      expect(trendPoints(<double>[70, 70, 70]), <double>[0.5, 0.5, 0.5]);
    });

    test('空数组不炸（"还没有数据"是常态）', () {
      expect(trendPoints(const <double>[]), isEmpty);
    });

    test('首尾差带正负号和单位；0 附近说"没变"', () {
      expect(trendDeltaText(BodyTrendMetric.weight, -1.2), '-1.2 kg');
      expect(trendDeltaText(BodyTrendMetric.waist, 2), '+2.0 cm');
      expect(trendDeltaText(BodyTrendMetric.weight, 0.01), '没变',
          reason: '"+0.0 kg"读起来像有什么事发生');
    });

    test('delta 是最后一次减第一次（不是反过来）', () {
      final BodyTrend t = bodyTrend(<BodyMetricData>[
        row('2026-09-01', weight: 73),
        row('2026-09-02', weight: 71.5),
      ], BodyTrendMetric.weight);
      expect(t.delta, closeTo(-1.5, 1e-9), reason: '掉秤应该是负数');
    });

    test('横轴标签去掉年份（位置很窄，年份是废话）', () {
      expect(shortDate('2026-09-28'), '09-28');
      expect(shortDate('坏数据'), '坏数据', reason: '长度不对就原样返回，不崩');
    });
  });
}
