/// 练了么 · 身体数据的**趋势**（v1.52）
///
/// 为什么单独一个文件：这一层是**纯计算**（哪几天记过、按时间排、怎么归一化成 0..1），
/// 与"画在哪儿"无关 —— 抽出来才能用普通单测盯住，而不是靠截图看。
/// 页面只负责把它交给 `core/vi_area_chart.dart`（与「进步」页那张容量图**同一个**组件，
/// 不抄第二份）。
///
/// 三条刻意的取舍：
///  1. **只取"记过"的那些天**：`null` 是"没记过"，不是 0 —— 把没记过的日子当成 0
///     画进曲线，会造出一条"体重掉到 0"的假趋势（体重的 0 kg 是个荒谬值，
///     而腰围 0 cm 同样荒谬）。
///  2. **按日期升序**：曲线从左到右必须是时间顺序。调用方给的是倒序（仓库按日期降序取），
///     所以在这一层排序，而不是指望每个调用方都记得 `reversed`。
///  3. **少于两个点就不画**：一个点连不成线，画出来只会是一条假的平线 ——
///     宁可说"记两次以上才画得出趋势"。
library;

import '../../data/db.dart';

/// 能画趋势的三个指标。体脂率暂时不在里面：它比体重更容易被单次测量误差左右，
/// 画成曲线会让人过度解读（要加就先想清楚这件事）。
enum BodyTrendMetric { weight, waist, muscle }

extension BodyTrendMetricX on BodyTrendMetric {
  /// 切换器上的名字（也是测试里认的那个词）。
  String get label => switch (this) {
        BodyTrendMetric.weight => '体重',
        BodyTrendMetric.waist => '腰围',
        BodyTrendMetric.muscle => '肌肉量',
      };

  /// 数值单位。腰围是 cm，另两个是 kg —— 单位和数字一起念，否则"掉了 2"会被误读。
  String get unit => switch (this) {
        BodyTrendMetric.weight => 'kg',
        BodyTrendMetric.waist => 'cm',
        BodyTrendMetric.muscle => 'kg',
      };

  /// 从一条记录里取这个指标的值。没记过就是 null。
  double? valueOf(BodyMetricData row) => switch (this) {
        BodyTrendMetric.weight => row.weightKg,
        BodyTrendMetric.waist => row.waistCm,
        BodyTrendMetric.muscle => row.muscleMassKg,
      };
}

/// 趋势算好之后的样子：选中的指标 + 按时间升序的采样点。
class BodyTrend {
  const BodyTrend({required this.metric, required this.samples});

  final BodyTrendMetric metric;

  /// `(日期, 数值)`，日期升序，且**每一天都真有这个值**。
  final List<(String date, double value)> samples;

  List<double> get values =>
      <double>[for (final (String _, double v) in samples) v];

  /// 两个点以上才画得出线。
  bool get plottable => samples.length >= 2;

  /// 首尾之差（最后一次 − 第一次）。少于两个点返回 null —— 不是 0。
  double? get delta => plottable ? samples.last.$2 - samples.first.$2 : null;

  String get firstDate => samples.isEmpty ? '' : samples.first.$1;
  String get lastDate => samples.isEmpty ? '' : samples.last.$1;
}

/// 把一批记录折成某个指标的趋势。`rows` 的顺序不重要（这一层会按日期排）。
BodyTrend bodyTrend(List<BodyMetricData> rows, BodyTrendMetric metric) {
  final List<BodyMetricData> sorted = <BodyMetricData>[...rows]
    ..sort((BodyMetricData a, BodyMetricData b) => a.date.compareTo(b.date));
  final List<(String, double)> samples = <(String, double)>[
    for (final BodyMetricData r in sorted)
      if (metric.valueOf(r) != null) (r.date, metric.valueOf(r)!),
  ];
  return BodyTrend(metric: metric, samples: samples);
}

/// 哪些指标**画得出**趋势（两个点以上），顺序固定为 体重 / 腰围 / 肌肉量。
///
/// 切换器只列这里面的：列一个点了没反应的指标，等于给用户一个假的入口。
List<BodyTrendMetric> trendMetrics(List<BodyMetricData> rows) => <BodyTrendMetric>[
      for (final BodyTrendMetric m in BodyTrendMetric.values)
        if (bodyTrend(rows, m).plottable) m,
    ];

/// 把一串数值压到 0..1（面积图要的比例）。
///
/// 全部相等时给 0.5：一条**平**线画在中间，读起来正是"这段时间没变"。
/// 若压成 0 或 1，那条平线会贴着底或顶，看起来像"一直在最低点/最高点"。
List<double> trendPoints(List<double> values) {
  if (values.isEmpty) return const <double>[];
  final double lo = values.reduce((double a, double b) => a < b ? a : b);
  final double hi = values.reduce((double a, double b) => a > b ? a : b);
  if (hi == lo) return <double>[for (final double _ in values) 0.5];
  return <double>[for (final double v in values) (v - lo) / (hi - lo)];
}

/// 首尾差的人话：带正负号和单位。0 写"没变"（"+0.0 kg"读起来像有什么事发生）。
String trendDeltaText(BodyTrendMetric metric, double delta) {
  if (delta.abs() < 0.05) return '没变';
  final String sign = delta > 0 ? '+' : '-';
  return '$sign${delta.abs().toStringAsFixed(1)} ${metric.unit}';
}

/// `2026-09-28` → `09-28`：横轴标签位置很窄，年份是废话（曲线最多 30 条记录）。
String shortDate(String yyyyMmDd) =>
    yyyyMmDd.length >= 10 ? yyyyMmDd.substring(5) : yyyyMmDd;
