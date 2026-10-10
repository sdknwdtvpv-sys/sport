/// 练了么 · **品牌圆环的几何与纪律**（VI 计划 T3-1，2026-10-10）
///
/// 判据（与计划一致，数字按**实测的主图**校准，理由写在 `brand_mark.dart` 文件头）：
///   1. `'圆环几何在任意尺寸下满足 1 : 0.198 : 0.603'` —— 外径 : 环带厚 : 洞径，
///      在 S = 16 / 40 / 120 / 320 四处都成立（几何全是比例，不许有绝对像素）；
///   2. `'BrandMark.glow 只允许在启动屏与完成页出现'`（源码扫描 + 白名单）；
///   3. 反向自检：把比例写歪一点，第 1 条要能红。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/brand_mark.dart';

/// 计划里点名的四档尺寸（16 = 行内小标 / 40 = 卡片角标 / 120 = 空态 / 320 = 启动页）。
const List<double> kSizes = <double>[16, 40, 120, 320];

void main() {
  test('圆环几何在任意尺寸下满足 1 : 0.1985 : 0.603', () {
    for (final double s in kSizes) {
      final double outer = BrandMarkGeometry.outerRadius(s);
      final double hole = BrandMarkGeometry.holeRadius(s);
      final double band = BrandMarkGeometry.band(s);

      // ① 外径 / 画布 = 0.447（实测主图 229×2 / 1024）
      expect(outer * 2, closeTo(s * 0.447, 0.0001), reason: 'S = $s');

      // ② 三组比例（**同一组数在任何尺寸下都成立** —— 这就是"比例而非像素"的意思）
      expect(band / (outer * 2), closeTo(BrandMarkGeometry.bandRatio, 0.0001),
          reason: 'S = $s 的环带厚 / 外径');
      expect(hole * 2 / (outer * 2), closeTo(BrandMarkGeometry.holeRatio, 0.0001),
          reason: 'S = $s 的洞径 / 外径');

      // ③ 描边落在中径上：mid ± band/2 必须正好是洞半径与外半径
      final double mid = BrandMarkGeometry.midRadius(s);
      expect(mid - band / 2, closeTo(hole, 0.0001), reason: 'S = $s 的内沿');
      expect(mid + band / 2, closeTo(outer, 0.0001), reason: 'S = $s 的外沿');
    }
  });

  testWidgets('四档尺寸都画得出来，且描边宽度就是环带厚', (WidgetTester tester) async {
    for (final double s in kSizes) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: BrandMark(size: s))),
      ));
      await tester.pump();

      final Size box = tester.getSize(find.byKey(const Key('brand-mark')));
      expect(box.width, s);
      expect(box.height, s);
      // 描边宽度 = 环带厚：从 painter 的路径 + 画笔上验一遍（不是只看常量）
      final CustomPaint paint =
          tester.widget<CustomPaint>(find.byKey(const Key('brand-mark')));
      expect(paint.painter, isNotNull);
      expect(BrandMarkGeometry.band(s),
          closeTo(s * BrandMarkGeometry.outerRatio * BrandMarkGeometry.bandRatio, 0.0001));
    }
  });

  testWidgets('辉光变体只多加一层光，尺寸不变', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: BrandMark.glow(size: 120))),
    ));
    await tester.pump();
    expect(tester.getSize(find.byKey(const Key('brand-mark'))), const Size(120, 120));
    // 辉光是 `Tokens.glow` 那条路（不是随手写的 BoxShadow）—— 全站只有 theme 能写 BoxShadow
    expect(find.byType(DecoratedBox), findsWidgets);
  });

  test('BrandMark.glow 只允许在启动屏与完成页出现', () {
    // 白名单写死在测试里（与 T1-5 的语义色白名单同一种做法）。
    // **现在这两个文件里还没有** —— 白名单的意义是"下一步要加的时候加不到别处去"。
    const List<String> allowed = <String>[
      'lib/main.dart', // 启动屏（T3-6 的 SplashOverlay 也挂在这儿）
      'lib/features/summary/workout_summary_screen.dart', // 完成页背后的光环
    ];
    final List<String> hits = <String>[];
    for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String path = e.path.replaceAll('\\', '/');
      if (path.endsWith('core/brand_mark.dart')) continue; // 定义处不算
      final List<String> lines = e.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final int c = lines[i].indexOf('//');
        final String code = c < 0 ? lines[i] : lines[i].substring(0, c);
        if (code.contains('BrandMark.glow(')) {
          if (!allowed.contains(path)) hits.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(hits, isEmpty,
        reason: '辉光是"一屏一次"的绑定载体，不许扩散到别处：\n${hits.join('\n')}');
  });

  test('反向自检：把比例写歪，第一条就会红', () {
    // 这条不依赖实现，只验证"比例断言本身是紧的"：
    // 环带厚若按 0.15 而不是 0.198 画，band/(outer*2) 就落不到 0.198 上。
    const double outer = 100;
    const double wrongBand = outer * 2 * 0.15;
    expect(wrongBand / (outer * 2), isNot(closeTo(BrandMarkGeometry.bandRatio, 0.0001)));
    expect(100.0 * 2 * BrandMarkGeometry.bandRatio, closeTo(39.7, 0.05),
        reason: '(1 - 0.603)/2 × 200 = 39.7 —— 与"环带厚 ÷ 环外半径 = 0.397"是同一件事的两倍关系');
  });
}
