/// 练了么 · 年度报告预览 + 交付（Ultra 权益 9）
///
/// 与分享卡预览同一条管线：把 [AnnualReportCard] 渲染成固定尺寸，抓成 PNG，
/// 再交给系统分享/存相册。**不新增埋点事件**（`share_card_created` 的语义是训练卡，
/// 这里不借用；任务里明确说不新增事件）。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/glass_overlay.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../domain/models.dart';
import '../summary/share_card.dart' show captureCardPng;
import '../summary/share_card_exporter.dart' show PluginShareCardExporter, ShareCardExporter;
import 'annual_report.dart';
import 'annual_report_card.dart';

class AnnualReportScreen extends StatefulWidget {
  const AnnualReportScreen({
    super.key,
    required this.sets,
    required this.exerciseNames,
    required this.muscleGroups,
    required this.timeExercises,
    this.unit = WeightUnit.kg,
    this.initialYear,
    this.now,
    this.exporter = const PluginShareCardExporter(),
    this.capture = captureCardPng,
  });

  final List<SetRecord> sets;
  final Map<String, String> exerciseNames;
  final Map<String, String> muscleGroups;
  final Set<String> timeExercises;
  final WeightUnit unit;
  final int? initialYear;
  final DateTime Function()? now;
  final ShareCardExporter exporter;
  final Future<Uint8List> Function(GlobalKey key) capture;

  @override
  State<AnnualReportScreen> createState() => _AnnualReportScreenState();
}

class _AnnualReportScreenState extends State<AnnualReportScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  late int _year;
  bool _busy = false;

  int get _nowYear => (widget.now?.call() ?? DateTime.now()).year;

  @override
  void initState() {
    super.initState();
    _year = widget.initialYear ?? _nowYear;
  }

  AnnualReport get _report => buildAnnualReport(
        sets: widget.sets,
        year: _year,
        exerciseNames: widget.exerciseNames,
        muscleGroups: widget.muscleGroups,
        timeExercises: widget.timeExercises,
        unit: widget.unit,
      );

  String get _fileName => 'lianleme_annual_$_year';

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: Tokens.elevated,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(Tokens.s5, 0, Tokens.s5, 80),
      ),
    );
  }

  Future<void> _export(Future<void> Function(Uint8List png) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final Uint8List png = await widget.capture(_boundaryKey);
      await action(png);
    } catch (e) {
      debugPrint('年报卡导出失败：$e');
      _toast('没成功，请稍后再试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() => _export((Uint8List png) async {
        await widget.exporter.shareToSystem(png, fileName: _fileName);
      });

  Future<void> _save() async {
    // 与分享卡同一套：申请相册权限前先说清目的（191 号文二.3）。
    if (await widget.exporter.galleryNeedsPermission()) {
      if (!mounted) return;
      final bool? go = await showAppDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          backgroundColor: Tokens.elevated,
          title: const Text('存到相册要一次授权', style: TextStyle(color: Tokens.text)),
          content: const Text(
            '接下来系统会问你是否允许「写入相册」。\n\n'
            '我们只是把这张年度报告写进去 —— 从不读取你的任何照片。',
            key: Key('annual-gallery-rationale'),
            style: TextStyle(color: Tokens.text2, height: Tokens.lhNormal),
          ),
          actions: <Widget>[
            TextButton(
              key: const Key('annual-gallery-cancel'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('先不用', style: TextStyle(color: Tokens.text2)),
            ),
            TextButton(
              key: const Key('annual-gallery-ok'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('继续', style: TextStyle(color: Tokens.accentText)),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    await _export((Uint8List png) async {
      final bool ok = await widget.exporter.saveToGallery(png, fileName: _fileName);
      _toast(ok ? '已存进相册' : '没有相册权限，没存成');
    });
  }

  @override
  Widget build(BuildContext context) {
    final AnnualReport report = _report;
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, 0),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton(
                      key: const Key('annual-back'),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.chevron_left, color: Tokens.text2),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  const Expanded(
                    child: Text('年度报告',
                        style: TextStyle(
                            color: Tokens.text,
                            fontSize: Tokens.fsHeadline,
                            fontWeight: Tokens.fwBold)),
                  ),
                  IconButton(
                    key: const Key('annual-year-prev'),
                    icon: const Icon(Icons.chevron_left, color: Tokens.text2),
                    onPressed: () => setState(() => _year -= 1),
                  ),
                  Text('$_year',
                      key: const Key('annual-year'),
                      style: const TextStyle(color: Tokens.text, fontSize: Tokens.fsSub)),
                  IconButton(
                    key: const Key('annual-year-next'),
                    icon: const Icon(Icons.chevron_right, color: Tokens.text2),
                    // 不让人翻到未来（未来没有数据，翻过去只会看到空态，像坏了）
                    onPressed: _year >= _nowYear ? null : () => setState(() => _year += 1),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(Tokens.s5),
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    child: AnnualReportCard(report: report),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.s5, 0, Tokens.s5, Tokens.s4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: OutlinedButton(
                        key: const Key('annual-save'),
                        onPressed: _busy || !report.hasData ? null : _save,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Tokens.text,
                          side: const BorderSide(color: Tokens.lineStrong),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Tokens.rPill),
                          ),
                        ),
                        child: const Text('存相册',
                            style: TextStyle(fontSize: Tokens.fsBodyS, fontWeight: Tokens.fwStrong)),
                      ),
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: FilledButton(
                        key: const Key('annual-share'),
                        onPressed: _busy || !report.hasData ? null : _share,
                        style: FilledButton.styleFrom(
                          backgroundColor: Tokens.accent,
                          foregroundColor: Tokens.accentInk,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Tokens.rPill),
                          ),
                        ),
                        child: const Text('分享',
                            style: TextStyle(fontSize: Tokens.fsBodyS, fontWeight: Tokens.fwBold)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
