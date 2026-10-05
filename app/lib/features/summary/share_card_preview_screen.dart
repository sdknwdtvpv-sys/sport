/// 练了么 · 分享卡预览 + 交付
///
/// 为什么不直接从 S7 抓图：S7 是**可滚动的页面**，还带着导航与「完成」按钮，
/// 抓出来的不会是一张卡片。这里把 [ShareCard] 单独渲染成一个固定尺寸的预览，
/// 顺便让用户**先看到将会分享出去的那张图** —— 分享之前看不到内容是很糟的体验。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/vi_cards.dart';
import '../../analytics/analytics.dart';
import 'share_card.dart';
import 'share_card_exporter.dart';
import 'workout_summary.dart';

class ShareCardPreviewScreen extends StatefulWidget {
  const ShareCardPreviewScreen({
    super.key,
    required this.summary,
    this.exporter = const PluginShareCardExporter(),
    this.capture = captureCardPng,
    this.analytics,
    this.streak = 0,
    this.ordinal,
  });

  final WorkoutSummary summary;

  /// 连续打卡天数与"第几次训练" —— 打卡版要用。
  /// **streak <= 1 时不给这个选项**：只有一天的人看到"连续打卡 1 天"不会想分享，
  /// 摆一个没人会选的版式反而是噪音。
  final int streak;
  final int? ordinal;

  /// 测试里换成假的 —— 插件调用本身在 widget 测试里跑不了
  final ShareCardExporter exporter;

  /// 抓图函数。默认是真身（`RepaintBoundary.toImage()`）。
  ///
  /// 做成可注入是为了**可测**：`toImage()` 是真实的引擎异步，
  /// 在 widget 测试的假时钟下不会完成（`share_card_test.dart` 里为此踩过坑，
  /// 挂死了 10 分钟）。抓图本身在那个文件里已经验证过了，这里只需要验证
  /// "抓到之后交给了谁、传了什么"。
  final Future<Uint8List> Function(GlobalKey key) capture;

  /// 埋点（可选）。上报 `share_card_created` —— 一期唯一的社交形态，
  /// 有没有人真的把卡发出去，只能靠这个事件回答。
  final Analytics? analytics;

  @override
  State<ShareCardPreviewScreen> createState() => _ShareCardPreviewScreenState();
}

class _ShareCardPreviewScreenState extends State<ShareCardPreviewScreen> {
  final GlobalKey _boundaryKey = GlobalKey();

  /// 当前版式（2026-10-05，新 VI 给了两款）。
  ShareCardVariant _variant = ShareCardVariant.standard;
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
      // `'$e'` 会把 `PlatformException(...)` 之类印给用户看 —— 兜底一句人话，细节进日志。
      debugPrint('分享卡导出失败：$e');
      _toast('没成功，请稍后再试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() => _export((Uint8List png) async {
        // channel 用 'share'：系统分享面板**不会告诉我们用户发给了谁**，
        // 所以不假装知道是微信还是别的（doc 里写的 wechat 只能等接了微信 SDK 再说）。
        widget.analytics?.track('share_card_created', <String, Object?>{'channel': 'share'});
        await widget.exporter.shareToSystem(png, fileName: _fileName);
      });

  Future<void> _save() async {
    // **申请权限之前先说清目的**：系统那个"允许写入媒体"的弹框不会解释我们要干什么，
    // 而规矩要求"申请可收集个人信息的权限时同步告知目的"（191 号文二.3）。
    // Android 10+ 走 MediaStore 免权限，`galleryNeedsPermission()` 会返回 false ——
    // 那种情况下不该白问用户一次。
    if (await widget.exporter.galleryNeedsPermission()) {
      if (!mounted) return;
      final bool? go = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          backgroundColor: Tokens.elevated,
          title: const Text('存到相册要一次授权', style: TextStyle(color: Tokens.text)),
          content: const Text(
            '接下来系统会问你是否允许「写入相册」。\n\n'
            '我们只是把这张训练卡写进去 —— 从不读取你的任何照片。',
            key: Key('gallery-rationale'),
            style: TextStyle(color: Tokens.text2, height: 1.6),
          ),
          actions: <Widget>[
            TextButton(
              key: const Key('gallery-rationale-cancel'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('先不用', style: TextStyle(color: Tokens.text2)),
            ),
            TextButton(
              key: const Key('gallery-rationale-ok'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('继续', style: TextStyle(color: Tokens.accent)),
            ),
          ],
        ),
      );
      if (go != true) return;
    }

    await _export((Uint8List png) async {
      widget.analytics?.track('share_card_created', <String, Object?>{'channel': 'save'});
      final bool ok = await widget.exporter.saveToGallery(png, fileName: _fileName);
      _toast(ok ? '已存进相册' : '没有相册权限，没存成');
    });
  }

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
                  // 第二款版式：**只有真的连续练过 2 天以上才给** ——
                  // "连续打卡 1 天"没人会分享（见 widget.streak 的注释）。
                  if (widget.streak >= 2)
                    ViSegmented(
                      labels: const <String>['明细', '打卡'],
                      current: _variant.index,
                      onChanged: (int i) => setState(
                          () => _variant = ShareCardVariant.values[i]),
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
                    child: ShareCard(
                      summary: widget.summary,
                      variant: _variant,
                      streak: widget.streak,
                      ordinal: widget.ordinal,
                    ),
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
                          backgroundColor: Tokens.accent,
                          foregroundColor: Tokens.accentInk,
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
