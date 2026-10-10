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

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/brand_mark.dart';
import 'package:lianleme/core/theme.dart';
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
  // 第二款版式（打卡版，2026-10-05 新 VI）
  _streakGroup();
  // 品牌层（T3-3）
  _brandGroup();
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

// ─────────────────────────────────────────────────────────────────────────────
// 第二款版式（打卡版，2026-10-05 新 VI）
// ─────────────────────────────────────────────────────────────────────────────

void _streakGroup() {
  testWidgets('标准版与打卡版是两张不同的卡，Key 也不一样（抓图抓的是当前那张）',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ShareCard(summary: _summary(), variant: ShareCardVariant.standard),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('share-card')), findsOneWidget);
    expect(find.byKey(const Key('share-card-streak')), findsNothing);

    await tester.pumpWidget(MaterialApp(
      home: ShareCard(
        summary: _summary(),
        variant: ShareCardVariant.streak,
        streak: 23,
        ordinal: 42,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('share-card-streak')), findsOneWidget);
    expect(find.byKey(const Key('share-card')), findsNothing);
    expect(find.text('DAY 42'), findsOneWidget);
    expect(find.text('连续打卡 23 天'), findsOneWidget);
  });

  testWidgets('打卡版不知道"第几次训练"时**不编一个数**：那一行直接不显示',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ShareCard(
        summary: _summary(),
        variant: ShareCardVariant.streak,
        streak: 3,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('share-card-streak')), findsOneWidget);
    expect(find.byKey(const Key('share-card-day')), findsNothing);
    expect(find.textContaining('DAY'), findsNothing);
    // 打卡天数照样在
    expect(find.text('连续打卡 3 天'), findsOneWidget);
  });

  testWidgets('打卡版仍然带日期与"分享自练了么"（社交形态的那两件不能少）',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ShareCard(
        summary: _summary(),
        variant: ShareCardVariant.streak,
        streak: 9,
        ordinal: 9,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('分享自练了么'), findsOneWidget);
    expect(find.text(formatCardDate(_summary().startedAtMs)), findsOneWidget);
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 品牌层（VI 计划 T3-3，2026-10-10）
// ─────────────────────────────────────────────────────────────────────────────

/// WCAG 的相对亮度分量（sRGB 先线性化）。
double _lin(int c) {
  final double v = c / 255;
  return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(int r, int g, int b) =>
    0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b);

double _contrast(double a, double b) {
  final double hi = math.max(a, b), lo = math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

void _brandGroup() {
  testWidgets('卡头是 BrandMark 而不是文字', (WidgetTester tester) async {
    await _pumpCard(tester, _summary());

    expect(
      find.descendant(
          of: find.byKey(const Key('share-card')), matching: find.byType(BrandMark)),
      findsWidgets,
      reason: '卡头要有品牌环 —— 这一条之前只有一行 15pt 的橙字',
    );

    final Text wordmark =
        tester.widget<Text>(find.byKey(const Key('share-card-wordmark')));
    expect(wordmark.data, '练了么');
    expect(wordmark.style!.fontSize, greaterThanOrEqualTo(16),
        reason: '字标 < 16pt 在 200pt 宽的缩略图里读不出来');
    expect(wordmark.style!.letterSpacing, 6);
    expect(Tokens.lsWordmark, 6, reason: '那个 6pt 必须是令牌（`Tokens.lsWordmark`）');

    // 底部那个"橙圆里写一个「练」"必须没了：全 App 唯一的"字母标"不该是汉字
    expect(find.text('练'), findsNothing);
  });

  testWidgets('卡面 360 × 520、导出 1080 × 1560（两个版式同一规格）',
      (WidgetTester tester) async {
    expect(kShareCardWidth, 360);
    expect(kShareCardHeight, 520, reason: 'T3-3 把卡面从 460 提到 520（品牌那一层变厚了）');
    expect(kShareCardWidth * kShareCardPixelRatio, 1080);
    expect(kShareCardHeight * kShareCardPixelRatio, 1560);

    await _pumpCard(tester, _summary());
    expect(tester.getSize(find.byKey(const Key('share-card'))), const Size(360, 520));

    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: ShareCard(
          summary: _summary(),
          variant: ShareCardVariant.streak,
          streak: 23,
          ordinal: 41,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('share-card-streak'))),
        const Size(360, 520));
  });

  testWidgets('缩略图可读性：压到 200pt 宽以后，字标仍然认得出',
      (WidgetTester tester) async {
    final GlobalKey key = await _pumpCard(tester, _summary());

    final Rect cardBox = tester.getRect(find.byKey(const Key('share-card')));
    final Rect wordBox = tester.getRect(find.byKey(const Key('share-card-wordmark')));
    const double to200 = 200 / kShareCardWidth; // 0.556

    // ① 几何：200pt 宽下字标有多高
    expect(wordBox.height * to200, greaterThanOrEqualTo(8),
        reason: '200pt 宽下字标只有 ${(wordBox.height * to200).toStringAsFixed(1)}px');

    // ② 像素：按 200pt 宽真渲染一次，扫字标那一块（对比度 + 实际占了几行像素）
    final _Pixels p = await _capturePixels(tester, key, pixelRatio: to200);
    final int x0 = ((wordBox.left - cardBox.left) * to200).round();
    final int y0 = ((wordBox.top - cardBox.top) * to200).round();
    final int x1 = ((wordBox.right - cardBox.left) * to200).round();
    final int y1 = ((wordBox.bottom - cardBox.top) * to200).round();

    final int bgI = p.at((x1 + 4).clamp(0, p.width - 1), ((y0 + y1) ~/ 2));
    final double bgLum = _luminance(p.rgba[bgI], p.rgba[bgI + 1], p.rgba[bgI + 2]);

    double bestLum = 0;
    int glyphRows = 0;
    for (int y = y0; y < y1; y++) {
      bool row = false;
      for (int x = x0; x < x1; x++) {
        final int i = p.at(x, y);
        final double l = _luminance(p.rgba[i], p.rgba[i + 1], p.rgba[i + 2]);
        if (l > bestLum) bestLum = l;
        if (l > bgLum * 4) row = true;
      }
      if (row) glyphRows++;
    }

    final double ratio = _contrast(bestLum, bgLum);
    expect(ratio, greaterThanOrEqualTo(4.5),
        reason: '字标对底色的对比度只有 ${ratio.toStringAsFixed(2)}:1（要 ≥ 4.5）');
    expect(glyphRows, greaterThanOrEqualTo(8),
        reason: '字标在 200pt 宽下只占 $glyphRows 行像素（要 ≥ 8）—— 缩略图里读不出来');
  });
}

typedef _Pixels = ({Uint8List rgba, int width, int height});

extension on _Pixels {
  int at(int x, int y) => (y * width + x) * 4;
}

/// 抓某个 key 上的位图**原始像素**（不是 PNG）—— 缩略图可读性只能从像素上看。
Future<_Pixels> _capturePixels(WidgetTester tester, GlobalKey key,
    {double pixelRatio = 1}) async {
  final RenderRepaintBoundary b =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final _Pixels? out = await tester.runAsync(() async {
    final ui.Image img = await b.toImage(pixelRatio: pixelRatio);
    final ByteData data =
        (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final _Pixels p = (
      rgba: data.buffer.asUint8List(),
      width: img.width,
      height: img.height
    );
    img.dispose();
    return p;
  });
  return out!;
}
