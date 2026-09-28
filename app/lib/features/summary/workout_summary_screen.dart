/// 练了么 · S7 训练结束总结
///
/// 对应 `docs/screens.md` S7。训练闭环的收尾。
///
/// **一处有意的范围裁剪**：规格里的「生成分享卡图片」在本版**没有实现**。
/// 那需要 RepaintBoundary.toImage() 加相册写入插件与平台通道，
/// 是我在受限环境里无法验证的东西 —— 做出来只会是"看起来完成了但没人跑过"的代码。
/// 数据部分（三项大数 + 破纪录）先做扎实，分享卡列在 ROADMAP 的后续增量里。
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/units.dart';
import 'share_card_exporter.dart';
import 'share_card_preview_screen.dart';
import 'workout_summary.dart';

class WorkoutSummaryScreen extends StatefulWidget {
  const WorkoutSummaryScreen({
    super.key,
    required this.service,
    required this.workoutId,
    this.unit = WeightUnit.kg,
    this.exporter = const PluginShareCardExporter(),
  });

  final SummaryService service;
  final String workoutId;

  /// 显示单位。**只影响显示**：服务算出来的量与 PR 判定始终是 kg。
  final WeightUnit unit;

  /// 分享卡的交付实现。测试里换成假的（插件调用在 widget 测试里跑不了）。
  final ShareCardExporter exporter;

  @override
  State<WorkoutSummaryScreen> createState() => _WorkoutSummaryScreenState();
}

class _WorkoutSummaryScreenState extends State<WorkoutSummaryScreen> {
  WorkoutSummary? _summary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final WorkoutSummary? s =
        await widget.service.build(widget.workoutId, unit: widget.unit);
    if (!mounted) return;
    setState(() {
      _summary = s;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _body(),
      ),
    );
  }

  Widget _body() {
    final WorkoutSummary? s = _summary;
    if (s == null) {
      return Column(
        children: <Widget>[
          const Expanded(
            child: Center(
              child: Text(
                '这次没有记录到任何一组。',
                style: TextStyle(color: Tokens.text3, fontSize: 15),
              ),
            ),
          ),
          _doneButton(),
        ],
      );
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s6, Tokens.s5, Tokens.s4),
            children: <Widget>[
              const Text(
                '训练完成',
                style: TextStyle(
                  color: Tokens.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: Tokens.s5),
              _stats(s),
              if (s.hasPr) ...<Widget>[
                const SizedBox(height: Tokens.s5),
                _prBlock(s),
              ],
            ],
          ),
        ),
        _shareButton(s),
        _doneButton(),
      ],
    );
  }

  /// 一行三个大数：容量 / 时长 / 组数
  Widget _stats(WorkoutSummary s) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Tokens.s5, horizontal: Tokens.s4),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
        border: Border.all(color: Tokens.line),
      ),
      child: Row(
        children: <Widget>[
          _stat('容量', s.volumeLabel, const Key('summary-volume')),
          _divider(),
          _stat('时长', s.durationLabel, const Key('summary-duration')),
          _divider(),
          _stat('组数', '${s.totalSets}', const Key('summary-sets')),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Key key) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            value,
            key: key,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Tokens.text,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Tokens.text3, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 32, color: Tokens.line);

  Widget _prBlock(WorkoutSummary s) {
    return Container(
      padding: const EdgeInsets.all(Tokens.s5),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
        border: Border.all(color: Tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // 破纪录用专属色，且**不只靠颜色**表达 —— 有文字
              const Text('★',
                  style: TextStyle(color: Tokens.pr, fontSize: 16, height: 1.2)),
              const SizedBox(width: Tokens.s2),
              Text(
                s.prs.length == 1 ? '破纪录' : '破了 ${s.prs.length} 项纪录',
                style: const TextStyle(
                  color: Tokens.pr,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.s3),
          for (final SetPr pr in s.prs)
            Padding(
              key: Key('summary-pr-${pr.exerciseId}'),
              padding: const EdgeInsets.only(bottom: Tokens.s2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      pr.exerciseName,
                      style: const TextStyle(
                        color: Tokens.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  Text(
                    pr.detail,
                    style: const TextStyle(color: Tokens.text2, fontSize: 13),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 分享训练卡。**只在真的有记录时才出现** —— 一次都没练的总结页
  /// 没有可分享的东西，给个按钮只会误导。
  Widget _shareButton(WorkoutSummary s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, 0),
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: OutlinedButton.icon(
          key: const Key('summary-share'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Tokens.text,
            side: const BorderSide(color: Tokens.lineStrong),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Tokens.rPill),
            ),
          ),
          icon: const Icon(Icons.ios_share, size: 18),
          label: const Text('分享训练卡',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ShareCardPreviewScreen(
                summary: s,
                exporter: widget.exporter,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _doneButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, Tokens.s5),
      child: SizedBox(
        height: Tokens.hPrimary,
        width: double.infinity,
        child: FilledButton(
          key: const Key('summary-done'),
          style: FilledButton.styleFrom(
            backgroundColor: Tokens.volt,
            foregroundColor: Tokens.voltInk,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Tokens.rPill),
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '完成',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
