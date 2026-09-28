/// 练了么 · S7 分享卡生成测试
///
/// 这里能验证的是**图片生成**：抓出来的确实是合法 PNG、尺寸是约定的倍数、
/// 破纪录块该出现时才出现。
///
/// **交出去那一步（存相册 / 分享面板）不在本文件覆盖范围内** —— 那需要真机，
/// 见 `share_card.dart` 末尾关于交付方式的说明。
///
/// ⚠️ **所有涉及 `toImage()` / `toByteData()` 的调用都必须包在 `tester.runAsync()` 里。**
/// 它们是真实的引擎异步（要走光栅化线程），而 `testWidgets` 用的是假时钟 ——
/// 直接 await 会**永远挂住**，不报错、不超时，只是安静地卡到测试框架把它杀掉。
/// 第一次写这个文件时就这么挂了 10 分钟。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/features/summary/share_card.dart';
import 'package:lianleme/features/summary/workout_summary.dart';

/// PNG 文件头。能被图片查看器认出来，才说明不是一段坏字节。
const List<int> _pngMagic = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

WorkoutSummary _summary({List<SetPr> prs = const <SetPr>[]}) => WorkoutSummary(
      workoutId: 'w1',
      totalSets: 12,
      totalVolumeKg: 5400,
      duration: const Duration(minutes: 52),
      exerciseCount: 4,
      prs: prs,
      startedAtMs: DateTime(2026, 9, 28, 19, 30).millisecondsSinceEpoch,
    );

typedef _Captured = ({Uint8List png, int width, int height});

/// 抓图并解码出真实像素尺寸。整个流程放进 `runAsync`（见文件头说明）。
Future<_Captured> _capture(
  WidgetTester tester,
  GlobalKey key, {
  double pixelRatio = kShareCardPixelRatio,
}) async {
  final _Captured? out = await tester.runAsync(() async {
    final Uint8List png = await captureCardPng(key, pixelRatio: pixelRatio);
    final ui.Codec codec = await ui.instantiateImageCodec(png);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final int w = frame.image.width;
    final int h = frame.image.height;
    frame.image.dispose();
    codec.dispose();
    return (png: png, width: w, height: h);
  });
  return out!;
}

Future<GlobalKey> _pumpCard(WidgetTester tester, WorkoutSummary s) async {
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    home: Center(
      child: RepaintBoundary(key: key, child: ShareCard(summary: s)),
    ),
  ));
  await tester.pumpAndSettle();
  return key;
}

void main() {
  testWidgets('分享卡能抓成合法 PNG', (WidgetTester tester) async {
    final GlobalKey key = await _pumpCard(tester, _summary());

    final _Captured c = await _capture(tester, key);

    expect(c.png.sublist(0, 8), _pngMagic, reason: '必须是真正的 PNG');
    expect(c.png.length, greaterThan(2000), reason: '不该是空白图');
  });

  testWidgets('导出尺寸 = 卡片逻辑尺寸 × 倍率（不同机型导出一致）',
      (WidgetTester tester) async {
    final GlobalKey key = await _pumpCard(tester, _summary());

    final _Captured c = await _capture(tester, key);

    expect(c.width, (kShareCardWidth * kShareCardPixelRatio).round());
    expect(c.height, (kShareCardHeight * kShareCardPixelRatio).round());
    expect(c.width, 1080, reason: '3 倍正好是社交平台舒服的宽度');
  });

  testWidgets('倍率可调（测试里用低倍率更快，产线上用高倍率更清晰）',
      (WidgetTester tester) async {
    final GlobalKey key = await _pumpCard(tester, _summary());

    final _Captured c = await _capture(tester, key, pixelRatio: 1);

    expect(c.width, kShareCardWidth.round());
    expect(c.height, kShareCardHeight.round());
  });

  testWidgets('没有破纪录时不显示「这次破了纪录」', (WidgetTester tester) async {
    await _pumpCard(tester, _summary());

    expect(find.text('这次破了纪录'), findsNothing);
  });

  testWidgets('有破纪录时显示，且最多只放两条（塞满会看不清重点）',
      (WidgetTester tester) async {
    final List<SetPr> prs = <SetPr>[
      const SetPr(
          exerciseId: 'a',
          exerciseName: '杠铃卧推',
          reps: 5,
          previousBest: 100,
          weightKg: 105),
      const SetPr(
          exerciseId: 'b',
          exerciseName: '杠铃深蹲',
          reps: 5,
          previousBest: 120,
          weightKg: 125),
      const SetPr(
          exerciseId: 'c', exerciseName: '引体向上', reps: 12, previousBest: 10),
    ];

    await _pumpCard(tester, _summary(prs: prs));

    expect(find.text('这次破了纪录'), findsOneWidget);
    expect(find.textContaining('杠铃卧推'), findsOneWidget);
    expect(find.textContaining('杠铃深蹲'), findsOneWidget);
    expect(find.textContaining('引体向上'), findsNothing, reason: '第三条不放进卡片');
    expect(find.text('还有 1 项'), findsOneWidget, reason: '但要让用户知道还有');
  });

  testWidgets('卡片上有日期（没有日期的"训练完成"没有纪念意义）',
      (WidgetTester tester) async {
    await _pumpCard(tester, _summary());

    expect(find.text('2026 年 9 月 28 日'), findsOneWidget);
  });

  test('日期格式固定，不随语言变化', () {
    final int ms = DateTime(2026, 9, 28).millisecondsSinceEpoch;
    expect(formatCardDate(ms), '2026 年 9 月 28 日');
  });

  testWidgets('key 上没挂 RepaintBoundary 时报错，而不是默默给张空白图',
      (WidgetTester tester) async {
    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Center(
        // 刻意不加 RepaintBoundary
        child: Container(key: key, width: 10, height: 10),
      ),
    ));
    await tester.pumpAndSettle();

    final Object? err = await tester.runAsync<Object?>(() async {
      try {
        await captureCardPng(key);
        return null;
      } catch (e) {
        return e;
      }
    });
    expect(err, isA<StateError>());
  });
}
