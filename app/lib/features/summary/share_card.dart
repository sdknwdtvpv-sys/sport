/// 练了么 · S7 分享卡（生成部分）
///
/// **刻意不引入任何依赖。** 卡片就是一棵普通的 widget 树，用 Flutter 自带的
/// `RepaintBoundary.toImage()` 抓成 PNG —— 项目 pubspec 里写着「依赖保持最小」，
/// 而"把界面变成图片"这件事根本不需要插件。
///
/// 本文件只负责**生成**。把图片交给系统（存相册 / 拉起分享面板）是另一件事，
/// 需要插件或平台通道，见 `docs/tech-decisions.md` 与本文件末尾的说明。
///
/// 固定尺寸是刻意的：不同机型、不同字号下导出的图必须一致，
/// 否则同一份训练在不同手机上分享出来长得不一样。
library;

import '../../core/icon_spec.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/theme.dart';
import 'workout_summary.dart';

/// 卡片逻辑尺寸。3:4 左右，适合朋友圈/微博这类竖版场景。
const double kShareCardWidth = 360;
const double kShareCardHeight = 460;

/// 导出倍数。3 倍 → 1080 × 1380，够社交平台用且不至于太大。
const double kShareCardPixelRatio = 3;

/// 两种版式（2026-10-05，新 VI 的 `vi/share-card.html` 里就给了两款）：
///   * [standard]：训练明细 —— 容量 / 组数 / 时长 + 前三个动作。想说"我今天练了什么"用它；
///   * [streak]：打卡 —— Day N + 连续天数 + 今日容量。想说"我坚持了多久"用它。
enum ShareCardVariant { standard, streak }

/// 分享卡：一张自包含的、固定尺寸的图。
class ShareCard extends StatelessWidget {
  const ShareCard({
    super.key,
    required this.summary,
    this.variant = ShareCardVariant.standard,
    this.streak = 0,
    this.ordinal,
  });

  final WorkoutSummary summary;

  final ShareCardVariant variant;

  /// 连续打卡天数（打卡版要）。**算出来的**，见 `features/progress/streak.dart`。
  final int streak;

  /// 这是第几次训练（打卡版的 "Day N"）。未知时传 null，那一行就不显示 ——
  /// 宁可少一行，也不编一个数出来。
  final int? ordinal;

  @override
  Widget build(BuildContext context) {
    if (variant == ShareCardVariant.streak) return _streakCard(context);
    return SizedBox(
      width: kShareCardWidth,
      height: kShareCardHeight,
      child: Container(
        key: const Key('share-card'),
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
                const Text(
                  '练了么',
                  style: TextStyle(
                    color: Tokens.accent,
                    fontSize: Tokens.fsSub,
                    fontWeight: Tokens.fwBold,
                    letterSpacing: Tokens.lsWide,
                  ),
                ),
                const Spacer(),
                Text(
                  formatCardDate(summary.startedAtMs),
                  style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro),
                ),
              ],
            ),
            const SizedBox(height: Tokens.s5),
            const Text(
              '训练完成',
              style: TextStyle(
                color: Tokens.text,
                fontSize: Tokens.fsTitle,
                fontWeight: Tokens.fwBold,
                letterSpacing: Tokens.lsTight,
              ),
            ),
            const SizedBox(height: Tokens.s5),
            _stat('容量', summary.volumeLabel),
            const SizedBox(height: Tokens.s3),
            _stat('时长', summary.durationLabel),
            const SizedBox(height: Tokens.s3),
            _stat('组数', '${summary.totalSets} 组'),
            const Spacer(),
            if (summary.hasPr) ...<Widget>[
              const Text(
                '这次破了纪录',
                style: TextStyle(
                  color: Tokens.pr,
                  fontSize: Tokens.fsCap,
                  fontWeight: Tokens.fwBold,
                ),
              ),
              const SizedBox(height: Tokens.s2),
              // 卡片只放得下前两条 —— 塞满会让人看不清重点
              for (final SetPr pr in summary.prs.take(2))
                Padding(
                  padding: const EdgeInsets.only(bottom: Tokens.s1),
                  child: Text(
                    '${pr.exerciseName} ${pr.detail}',
                    style: const TextStyle(color: Tokens.text2, fontSize: Tokens.fsCap),
                  ),
                ),
              if (summary.prs.length > 2)
                Text(
                  '还有 ${summary.prs.length - 2} 项',
                  style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro),
                ),
              const SizedBox(height: Tokens.s4),
            ],
            Text(
              '${summary.exerciseCount} 个动作 · ${summary.totalSets} 组',
              style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro),
            ),
          ],
        ),
      ),
    );
  }

  /// 打卡版（新 VI 的第二款版式）。
  ///
  /// 与标准版的区别是**它在说什么**：标准版回答"今天练了什么"，
  /// 这一版回答"我坚持了多久"—— 所以主角是 Day N 与连续天数，容量退成配角。
  Widget _streakCard(BuildContext context) => SizedBox(
        width: kShareCardWidth,
        height: kShareCardHeight,
        child: Container(
          key: const Key('share-card-streak'),
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
                  const Text('练了么',
                      style: TextStyle(
                          color: Tokens.accent,
                          fontSize: Tokens.fsSub,
                          fontWeight: Tokens.fwBold,
                          letterSpacing: Tokens.lsWide)),
                  const Spacer(),
                  Text(formatCardDate(summary.startedAtMs),
                      style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
                ],
              ),
              const Spacer(),
              if (ordinal != null)
                Text('DAY $ordinal',
                    key: const Key('share-card-day'),
                    style: Tokens.display(44, weight: 700, letterSpacing: Tokens.lsTight)),
              const SizedBox(height: Tokens.s2),
              Row(
                children: <Widget>[
                  const Icon(Icons.local_fire_department, color: Tokens.accent, size: IconSpec.m),
                  const SizedBox(width: Tokens.s2),
                  Text('连续打卡 $streak 天',
                      key: const Key('share-card-streak-text'),
                      style: const TextStyle(
                          color: Tokens.text, fontSize: Tokens.fsBody, fontWeight: Tokens.fwBold)),
                ],
              ),
              const Spacer(),
              Text(summary.volumeLabel,
                  style: Tokens.display(36, weight: 700, letterSpacing: Tokens.lsTight)),
              const SizedBox(height: Tokens.s1),
              Text('今日总容量 · ${summary.exerciseCount} 个动作 · ${summary.totalSets} 组',
                  style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
              const Spacer(),
              Row(
                children: <Widget>[
                  Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                        color: Tokens.accent, shape: BoxShape.circle),
                    child: const Center(
                      child: Text('练',
                          style: TextStyle(
                              color: Tokens.accentInk,
                              fontSize: Tokens.fsCap,
                              fontWeight: Tokens.fwBold)),
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  const Text('分享自练了么',
                      style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _stat(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        SizedBox(
          width: 48,
          child: Text(label,
              style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap)),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Tokens.text,
            fontSize: Tokens.fsNum,
            fontWeight: Tokens.fwBold,
            letterSpacing: Tokens.lsSnug,
          ),
        ),
      ],
    );
  }
}

/// 「2026 年 9 月 28 日」。
///
/// 手写而不用 `intl`：只为这一处格式化引入一个本地化依赖不划算，
/// 而且这个格式是固定的，不需要按语言变化。
String formatCardDate(int ms) {
  final DateTime d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year} 年 ${d.month} 月 ${d.day} 日';
}

/// 把 [boundaryKey] 上的 `RepaintBoundary` 抓成 PNG 字节。
///
/// ⚠️ 必须在**这一帧已经画完之后**调用（例如按钮回调里，
/// 或 `WidgetsBinding.instance.addPostFrameCallback` 之后）。
/// 布局还没发生就抓，会得到一张空白图 —— 而且不会报错。
Future<Uint8List> captureCardPng(
  GlobalKey boundaryKey, {
  double pixelRatio = kShareCardPixelRatio,
}) async {
  final RenderObject? obj = boundaryKey.currentContext?.findRenderObject();
  if (obj is! RenderRepaintBoundary) {
    throw StateError('captureCardPng：该 key 上没有挂 RepaintBoundary');
  }
  final ui.Image image = await obj.toImage(pixelRatio: pixelRatio);
  try {
    final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('captureCardPng：PNG 编码返回空');
    }
    return data.buffer.asUint8List();
  } finally {
    // 不 dispose 会漏 native 内存；一张 1080×1380 的位图不小
    image.dispose();
  }
}

/// 交付方式（**尚未实现**）：
///
/// 生成 PNG 之后要把它交出去，有两条路，各有代价：
///
/// 1. **引入插件**（如 `share_plus` 走系统分享面板，或 `gal` 直接存相册）
///    —— 与 pubspec 里「依赖保持最小」的原则冲突，需要一次明确的例外决定。
///    走系统分享面板**不需要任何新权限**，因此隐私政策里
///    「只申请 INTERNET 一项权限」那句话仍然成立。
/// 2. **自己写平台通道**（Android `Intent.ACTION_SEND` + FileProvider，iOS
///    `UIActivityViewController`）—— 不违反依赖原则，但要加原生代码，
///    且 **iOS 那一半在当前机器上无法验证**（没有完整 Xcode）。
