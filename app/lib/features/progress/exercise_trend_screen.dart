/// 练了么 · **单动作趋势页**（Ultra 权益 7「进阶分析」的主体）
///
/// 方案：`docs/plan-membership-2026-10-10.md` §二 权益 7。它回答的问题只有一个：
/// **「我这个动作，最近是涨还是在原地？」** —— 而这恰好是免费版回答不了的
/// （免费版的容量趋势是"全部动作合起来"，把某个动作的停滞藏在总量里）。
///
/// 界面四块，从上到下：
///   1. 周期切换（周 / 月 / 季）—— 与「全部数据」的分段控件同一个语言；
///   2. 容量趋势（`ViAreaChart`：与进步页那张同一个画笔，只是数据换成这一个动作的）；
///   3. **这一周期 vs 上一周期**的四行数字（组数 / 容量 / 最重 / 估算 1RM）；
///   4. 「起步 vs 现在」一行 —— 只有两端都有数据时才说话，没有就说"数据还不够"。
///
/// ⚠️ 三条"不许编"的规矩（`advanced_analysis.dart` 的纯函数已经保证，界面照做）：
///   * 上一周期没有数据 → **不显示百分比**（"从 0 到 600" 没有百分比可言）；
///   * 起步或现在缺一端 → 那一行写"数据还不够"，不写 0%；
///   * 断掉的周期在图上**如实是 0**，不把两端连成一条看起来一直在涨的线。
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/units.dart';
import '../../core/vi_area_chart.dart';
import '../../core/vi_cards.dart';
import '../../domain/models.dart';
import '../../features/profile/profile_widgets.dart';
import 'advanced_analysis.dart';

class ExerciseTrendScreen extends StatefulWidget {
  const ExerciseTrendScreen({
    super.key,
    required this.sets,
    required this.exerciseId,
    required this.exerciseName,
    this.unit = WeightUnit.kg,
    this.now,
    this.initialRange = AnalysisRange.week,
  });

  /// 这个动作的全部记录（调用方已经滤过；这里不再查库 —— 与进步页共用同一份内存数据）
  final List<SetRecord> sets;
  final String exerciseId;
  final String exerciseName;
  final WeightUnit unit;
  final DateTime Function()? now;
  final AnalysisRange initialRange;

  @override
  State<ExerciseTrendScreen> createState() => _ExerciseTrendScreenState();
}

class _ExerciseTrendScreenState extends State<ExerciseTrendScreen> {
  late AnalysisRange _range = widget.initialRange;

  DateTime get _now => (widget.now ?? DateTime.now)();

  /// 往回看多少个桶：周 12（约 3 个月）/ 月 12（一年）/ 季 8（两年）
  int get _buckets {
    switch (_range) {
      case AnalysisRange.week:
        return 12;
      case AnalysisRange.month:
        return 12;
      case AnalysisRange.quarter:
        return 8;
    }
  }

  ExerciseTrend get _trend => exerciseTrend(
        widget.sets,
        exerciseId: widget.exerciseId,
        range: _range,
        now: _now,
        buckets: _buckets,
      );

  @override
  Widget build(BuildContext context) {
    final ExerciseTrend t = _trend;
    return ProfileSubPage(
      title: widget.exerciseName,
      children: <Widget>[
        // 周期切换：三档（周 / 月 / 季）——与「全部数据」的分段控件同一个语言
        SizedBox(
          height: 36,
          child: Row(
            children: <Widget>[
              for (final AnalysisRange r in AnalysisRange.values) ...<Widget>[
                _rangeChip(r),
                if (r != AnalysisRange.values.last) const SizedBox(width: Tokens.s2),
              ],
            ],
          ),
        ),
        const SizedBox(height: Tokens.s5),

        if (!t.hasHistory)
          const Padding(
            padding: EdgeInsets.only(top: Tokens.s2),
            child: Text(
              '这个动作还没有记录。练几次之后，这里会画出它的趋势。',
              key: Key('trend-empty'),
              style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsSub, height: Tokens.lhNormal),
            ),
          )
        else ...<Widget>[
          // ── 容量趋势（同一个画笔，数据换成这一个动作的）──────────────
          ViCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '每${_range.label}容量',
                  style: const TextStyle(color: Tokens.text2, fontSize: Tokens.fsCap),
                ),
                const SizedBox(height: Tokens.s3),
                ViAreaChart(
                  points: t.points.map((TrendPoint p) => p.volumeKg).toList(),
                  height: 120,
                  labels: <String>[
                    _bucketLabel(t.points.first.bucketStart),
                    _bucketLabel(t.points.last.bucketStart),
                  ],
                ),
                const SizedBox(height: Tokens.s2),
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        _bucketLabel(t.points.first.bucketStart),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro),
                      ),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        _bucketLabel(t.points.last.bucketStart),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.s5),

          // ── 这一周期 vs 上一周期 ─────────────────────────────────────
          _sectionTitle('这一${_range.label} vs 上一${_range.label}'),
          settingsCard(<Widget>[
            _deltaRow('组数', '${t.latest.sets}', t.latest.sets - t.previous.sets),
            const Divider(height: 1, color: Tokens.line),
            _deltaRow('容量', formatVolume(t.latest.volumeKg, widget.unit, zeroText: '0 kg'), null,
                sub: _volumeDeltaText(t)),
            const Divider(height: 1, color: Tokens.line),
            _weightRow(t),
            const Divider(height: 1, color: Tokens.line),
            _oneRmRow(t),
          ]),
          const SizedBox(height: Tokens.s5),

          // ── 起步 vs 现在 ────────────────────────────────────────────
          _sectionTitle('起步 vs 现在'),
          ViCard(
            key: const Key('trend-since-start'),
            child: Text(
              t.topWeightChangePct == null
                  ? '数据还不够：这个动作需要一个"起步阶段"和一个"最近 30 天"的记录，才谈得上从头到现在的变化。'
                  : '起步那 30 天最重 ${_kg(t.firstTopWeightKg!)}，最近 30 天最重 ${_kg(t.latestTopWeightKg!)}'
                      '（${_pct(t.topWeightChangePct!)}）。',
              style: const TextStyle(color: Tokens.text2, fontSize: Tokens.fsSub, height: Tokens.lhNormal),
            ),
          ),
        ],
      ],
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: Tokens.s2, left: Tokens.s1),
        child: Text(t,
            style: const TextStyle(
                color: Tokens.text3, fontSize: Tokens.fsCap, fontWeight: Tokens.fwStrong)),
      );

  Widget _rangeChip(AnalysisRange r) {
    final bool on = r == _range;
    return GestureDetector(
      key: Key('trend-range-${r.name}'),
      onTap: () => setState(() => _range = r),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? Tokens.lift : Colors.transparent,
          borderRadius: BorderRadius.circular(Tokens.rPill),
          border: Border.all(color: on ? Tokens.lineStrong : Tokens.line),
        ),
        child: Text(
          r.label,
          style: TextStyle(
            color: on ? Tokens.text : Tokens.text2,
            fontSize: Tokens.fsCap,
            fontWeight: on ? Tokens.fwStrong : Tokens.fwBody,
          ),
        ),
      ),
    );
  }

  /// 一行数字：左边标签、右边数值，下面可挂一句对比小字（"上周期 500 kg · ↓ 20%"）。
  ///
  /// `delta` 与 `sub` 二选一：`delta` 用于"组数"那种可以直接说增减的量，
  /// `sub` 用于"容量 / 最重 / 1RM"——它们的对比要带上上一周期的值才有意义。
  Widget _deltaRow(String label, String value, int? delta, {String? sub}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s5, vertical: Tokens.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(label,
                      style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsSub)),
                ),
                if (delta != null && delta != 0)
                  Padding(
                    padding: const EdgeInsets.only(right: Tokens.s2),
                    child: Text(
                      '${delta > 0 ? '↑' : '↓'} ${delta.abs()}',
                      style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap),
                    ),
                  ),
                Text(
                  value,
                  key: Key('trend-$label'),
                  style: const TextStyle(
                    color: Tokens.text,
                    fontSize: Tokens.fsBodyS,
                    fontWeight: Tokens.fwStrong,
                    fontFeatures: Tokens.tabular,
                  ),
                ),
              ],
            ),
            if (sub != null && sub.isNotEmpty) ...<Widget>[
              const SizedBox(height: Tokens.s1),
              Text(sub,
                  style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
            ],
          ],
        ),
      );

  Widget _weightRow(ExerciseTrend t) {
    final double? cur = t.latest.bestWeightKg;
    final double? prev = t.previous.bestWeightKg;
    return _deltaRow('最重一组', cur == null ? '—' : _kg(cur), null,
        sub: prev == null || cur == null ? null : '上${_range.label} ${_kg(prev)}');
  }

  Widget _oneRmRow(ExerciseTrend t) {
    final double? cur = t.latest.best1Rm;
    final double? prev = t.previous.best1Rm;
    return _deltaRow('估算 1RM', cur == null ? '—' : _kg(cur), null,
        sub: prev == null || cur == null ? null : '上${_range.label} ${_kg(prev)}');
  }

  /// 容量的对比文案。**上一周期没有数据时不写百分比** ——
  /// "从 0 到 600" 的百分比是编出来的，而用户会当真。
  String _volumeDeltaText(ExerciseTrend t) {
    if (t.previous.volumeKg <= 0) {
      return t.latest.volumeKg > 0 ? '上${_range.label}没有记录' : '';
    }
    final double pct = (t.latest.volumeKg - t.previous.volumeKg) / t.previous.volumeKg;
    return '上${_range.label} ${_kg(t.previous.volumeKg)} · ${_pct(pct)}';
  }

  String _kg(double v) => formatVolume(v, widget.unit, zeroText: '0 kg');

  /// 变化率的写法。⚠️ **四舍五入到 0 时写"持平"，不写"↑ 0%"**：
  /// 后者读起来像"涨了"，而它表达的是"没变"（也是被测试逼出来的：
  /// 一个"起步与现在都是 60 kg"的动作，界面上出现过「↑ 0%」）。
  String _pct(double v) {
    final int p = (v.abs() * 100).round();
    if (p == 0) return '持平';
    return '${v >= 0 ? '↑' : '↓'} $p%';
  }

  String _bucketLabel(DateTime d) {
    switch (_range) {
      case AnalysisRange.week:
        return formatDateAxis(d);
      case AnalysisRange.month:
        // 周期标签不是"某一天"，所以走 `units.dart` 新加的那两档
        // （自己拼的话，`units_format_test` 判据 3 的扫描会当场抓出来）
        return formatMonthLabel(d);
      case AnalysisRange.quarter:
        return formatQuarterLabel(d);
    }
  }
}
