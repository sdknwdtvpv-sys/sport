/// 练了么 · **年度报告卡**（Ultra 权益 9）
///
/// 复用分享卡那套"普通 widget 树 + RepaintBoundary 抓图"的管线：
/// 固定逻辑尺寸、不跟随系统字号（与 `ShareCard` 同一条理由 —— 导出的图必须在
/// 任何手机上长得一样）；颜色/字号/间距全部来自 `Tokens`。
///
/// 空数据/半年数据**如实显示**：没有数字就写"这一年还没有训练记录"，
/// 不拿 0 冒充"练了 0 次"以外的任何东西。
library;

import 'package:flutter/material.dart';

import '../../core/brand_mark.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../summary/share_card.dart' show kShareCardMark;
import 'annual_report.dart';

/// 年报卡逻辑尺寸：竖版 3:4.7，比训练分享卡再高一点（内容多：数字 + PR + 部位分布）。
const double kAnnualCardWidth = 360;
const double kAnnualCardHeight = 640;

/// 3 倍 → 1080 × 1920，社交平台够用。
const double kAnnualCardPixelRatio = 3;

class AnnualReportCard extends StatelessWidget {
  const AnnualReportCard({super.key, required this.report});

  final AnnualReport report;

  @override
  Widget build(BuildContext context) {
    // 与训练分享卡同一理由：导出成图片的产物不跟随系统字号。
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: SizedBox(
        width: kAnnualCardWidth,
        height: kAnnualCardHeight,
        child: Container(
          key: const Key('annual-report-card'),
          padding: const EdgeInsets.all(Tokens.s6),
          decoration: BoxDecoration(
            color: Tokens.bg,
            borderRadius: BorderRadius.circular(Tokens.rCard),
            border: Border.all(color: Tokens.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const BrandMark(size: kShareCardMark),
                  const SizedBox(width: Tokens.s2),
                  const Text('练了么',
                      style: TextStyle(
                          color: Tokens.text,
                          fontSize: Tokens.fsCap,
                          fontWeight: Tokens.fwBold,
                          letterSpacing: Tokens.lsTight)),
                  const Spacer(),
                  Text('${report.year} 年度报告', key: const Key('annual-year-label'),
                      style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
                ],
              ),
              const SizedBox(height: Tokens.s5),
              if (!report.hasData)
                Expanded(child: _empty())
              else ...<Widget>[
                if (report.hasVolume) ...<Widget>[
                  const Text('总容量',
                      style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap)),
                  const SizedBox(height: Tokens.s1),
                  Text(report.volumeLabel,
                      key: const Key('annual-volume'),
                      style: Tokens.display(40, weight: 700, letterSpacing: Tokens.lsTight)),
                ] else
                  const Text('自重/有氧训练（容量不适用）',
                      key: Key('annual-no-volume'),
                      style: TextStyle(color: Tokens.text2, fontSize: Tokens.fsSub)),
                if (report.hasDistance) ...<Widget>[
                  const SizedBox(height: Tokens.s1),
                  Text('有氧里程 ${report.distanceLabel}',
                      key: const Key('annual-distance'),
                      style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap)),
                ],
                const SizedBox(height: Tokens.s5),
                _statGrid(),
                if (report.partialMonths != null) ...<Widget>[
                  const SizedBox(height: Tokens.s3),
                  Text('覆盖 ${report.partialMonths}/12 个月，不推算全年',
                      key: const Key('annual-partial'),
                      style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
                ],
                const SizedBox(height: Tokens.s5),
                if (report.bestPrs.isNotEmpty) ...<Widget>[
                  const Text('年度最佳',
                      style: TextStyle(
                          color: Tokens.text2,
                          fontSize: Tokens.fsCap,
                          fontWeight: Tokens.fwBold)),
                  const SizedBox(height: Tokens.s2),
                  for (final AnnualPr pr in report.bestPrs.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: Tokens.s1),
                      child: Text('${pr.exerciseName} · ${_prDetail(pr)}',
                          style: const TextStyle(color: Tokens.text2, fontSize: Tokens.fsMicro)),
                    ),
                  const SizedBox(height: Tokens.s3),
                ],
                if (report.muscleVolumeKg.isNotEmpty) ...<Widget>[
                  const Text('部位分布（按容量）',
                      style: TextStyle(
                          color: Tokens.text2,
                          fontSize: Tokens.fsCap,
                          fontWeight: Tokens.fwBold)),
                  const SizedBox(height: Tokens.s2),
                  _muscleBars(),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('这一年还没有训练记录',
                key: Key('annual-empty'),
                style: TextStyle(color: Tokens.text2, fontSize: Tokens.fsSub)),
            const SizedBox(height: Tokens.s2),
            const Text('没有数据就不编数字 —— 练过之后再回来看看。',
                style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap, height: Tokens.lhNormal)),
          ],
        ),
      );

  Widget _statGrid() => Row(
        children: <Widget>[
          Expanded(child: _stat('训练次数', '${report.workoutCount} 次', 'annual-workouts')),
          const SizedBox(width: Tokens.s4),
          Expanded(child: _stat('总组数', '${report.setCount} 组', 'annual-sets')),
          const SizedBox(width: Tokens.s4),
          Expanded(child: _stat('训练天数', '${report.trainingDays} 天', 'annual-days')),
          const SizedBox(width: Tokens.s4),
          Expanded(child: _stat('出勤周数', '${report.attendanceWeeks} 周', 'annual-weeks')),
        ],
      );

  Widget _stat(String label, String value, String key) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
          const SizedBox(height: Tokens.s1),
          Text(value,
              key: Key(key),
              style: const TextStyle(
                  color: Tokens.text, fontSize: Tokens.fsBody, fontWeight: Tokens.fwBold)),
        ],
      );

  Widget _muscleBars() {
    final double maxV = report.muscleVolumeKg.values.reduce((double a, double b) => a > b ? a : b);
    final List<MapEntry<String, double>> rows = report.muscleVolumeKg.entries.toList()
      ..sort((MapEntry<String, double> a, MapEntry<String, double> b) => b.value.compareTo(a.value));
    return Column(
      children: <Widget>[
        for (final MapEntry<String, double> e in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.s1),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 34,
                  child: Text(kMuscleLabels[e.key] ?? e.key,
                      style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
                ),
                Expanded(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: maxV <= 0 ? 0 : (e.value / maxV).clamp(0.02, 1.0),
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: Tokens.accent,
                        borderRadius: BorderRadius.circular(Tokens.rPill),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _prDetail(AnnualPr pr) {
    if (pr.isTime) return '${pr.reps} 秒';
    if (pr.isBodyweight) return '${pr.reps} 次';
    final String w = pr.weightKg == null ? '' : '${pr.weightKg!.toStringAsFixed(pr.weightKg! % 1 == 0 ? 0 : 1)} kg × ';
    return '$w${pr.reps} 次';
  }
}
