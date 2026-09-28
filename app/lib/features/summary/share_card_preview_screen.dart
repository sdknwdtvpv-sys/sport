/// 练了么 · 分享卡预览 + 交付
///
/// 为什么不直接从 S7 抓图：S7 是**可滚动的页面**，还带着导航与「完成」按钮，
/// 抓出来的不会是一张卡片。这里把 [ShareCard] 单独渲染成一个固定尺寸的预览，
/// 顺便让用户**先看到将会分享出去的那张图** —— 分享之前看不到内容是很糟的体验。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'share_card.dart';
import 'share_card_exporter.dart';
import 'workout_summary.dart';

class ShareCardPreviewScreen extends StatefulWidget {
  const ShareCardPreviewScreen({
    super.key,
    required this.summary,
    this.exporter = const PluginShareCardExporter(),
    this.capture = captureCardPng,
  });

  final WorkoutSummary summary;

  /// 测试里换成假的 —— 插件调用本身在 widget 测试里跑不了
  final ShareCardExporter exporter;

  /// 抓图函数。默认是真身（`RepaintBoundary.toImage()`）。
  ///
  /// 做成可注入是为了**可测**：`toImage()` 是真实的引擎异步，
  /// 在 widget 测试的假时钟下不会完成（`share_card_test.dart` 里为此踩过坑，
  /// 挂死了 10 分钟）。抓图本身在那个文件里已经验证过了，这里只需要验证
  /// "抓到之后交给了谁、传了什么"。
  final Future<Uint8List> Function(GlobalKey key) capture;

  @override
  State<ShareCardPreviewScreen> createState() => _ShareCardPreviewScreenState();
}

class _ShareCardPreviewScreenState extends State<ShareCardPreviewScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _busy = false;

  /// 导出用的文件名：带上日期，用户在相册/文件里能认出来。
  String get _fileName {
    final DateTime d =
        DateTime.fromMillisecondsSinceEpoch(widget.summary.startedAtMs);
    final String mm = d.month.toString().padLeft(2, '0');
    final String dd = d.day.toString().padLeft(2, '0');
    return 'lianleme_${d.year}$mm$dd';
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: Tokens.elevated,
        // 浮动到按钮上方：默认贴底会盖住「分享 / 存相册」
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(Tokens.s5, 0, Tokens.s5, 80),
      ),
    );
  }

  /// 抓图并交给 [action]。
  ///
  /// 全程不抛出去：分享/存储失败不该让整个训练总结页崩掉 ——
  /// 用户刚练完，最不该看到的就是崩溃。
  Future<void> _export(Future<void> Function(Uint8List png) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final Uint8List png = await widget.capture(_boundaryKey);
      await action(png);
    } catch (e) {
      _toast('没成功：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() => _export((Uint8List png) async {
        await widget.exporter.shareToSystem(png, fileName: _fileName);
      });

  Future<void> _save() => _export((Uint8List png) async {
        final bool ok =
            await widget.exporter.saveToGallery(png, fileName: _fileName);
        _toast(ok ? '已存进相册' : '没有相册权限，没存成');
      });

  @override
  Widget build(BuildContext context) {
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
                      key: const Key('share-preview-back'),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.chevron_left, color: Tokens.text2),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  const Expanded(
                    child: Text(
                      '分享训练卡',
                      style: TextStyle(
                        color: Tokens.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(Tokens.s5),
                  // RepaintBoundary 就是被抓的那一层。它必须真的完成绘制，
                  // 所以这里用正常的可见布局（Offstage 会跳过绘制，抓出来是空的）。
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    child: ShareCard(summary: widget.summary),
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
                        key: const Key('share-card-save'),
                        onPressed: _busy ? null : _save,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Tokens.text,
                          side: const BorderSide(color: Tokens.lineStrong),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Tokens.rPill),
                          ),
                        ),
                        child: const Text('存相册',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: FilledButton(
                        key: const Key('share-card-share'),
                        onPressed: _busy ? null : _share,
                        style: FilledButton.styleFrom(
                          backgroundColor: Tokens.volt,
                          foregroundColor: Tokens.voltInk,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Tokens.rPill),
                          ),
                        ),
                        child: const Text('分享',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
