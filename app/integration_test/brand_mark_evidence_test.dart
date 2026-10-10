/// 练了么 · **品牌圆环四档尺寸的证据图**（VI 计划 T3-1）
///
/// T3-1 建的是"品牌只有一枚圆环，而它在这个 App 里一次都没被画出来"这件事的解：
/// 一个 `CustomPaint` 组件（几何全是比例，没有绝对像素）。
/// 这条证据要回答两个问题：
///   ① **四档尺寸下形状一样**（16 / 40 / 120 / 320 + 辉光变体），
///   ② 图上量出来的环，仍然是主图的那组比例（外径 0.447 / 环带 0.1985 / 洞 0.603）。
/// 第 ② 条由主机上的 `tool/brandmark-probe.py` 在图上量（不是靠眼睛）。
///
/// 跑法：
///   flutter drive --driver=test_driver/screenshot_driver.dart \
///     --target=integration_test/brand_mark_evidence_test.dart -d <设备 id>
///   SHOT_DIR=../docs/images/plan-vi-2026-10-10/raw
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianleme/core/brand_mark.dart';
import 'package:lianleme/core/theme.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('品牌圆环：16 / 40 / 120 / 320 四档 + 辉光', (WidgetTester tester) async {
    await binding.convertFlutterSurfaceToImage();

    /// 一档尺寸一小块：**标签在上、环在下**（横着排 320 那一档会把 440pt 的屏撑爆 ——
    /// 第一版就是这么溢出的，黄色警示条直接进了证据图）。
    Widget block(double size, {bool glow = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: Tokens.s3),
          child: Column(
            children: <Widget>[
              Text(
                '${size.round()} · 外径 '
                '${(size * BrandMarkGeometry.outerRatio).round()} · 环带 '
                '${(size * BrandMarkGeometry.outerRatio * BrandMarkGeometry.bandRatio).toStringAsFixed(1)}',
                key: Key('label-${size.round()}'),
                style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro),
              ),
              const SizedBox(height: Tokens.s2),
              glow ? BrandMark.glow(size: size) : BrandMark(size: size),
            ],
          ),
        );

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: Tokens.bg,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Tokens.s5),
            children: <Widget>[
              const Text('BrandMark · 四档尺寸',
                  style: TextStyle(
                      color: Tokens.text,
                      fontSize: Tokens.fsHeadline,
                      fontWeight: Tokens.fwBold)),
              const SizedBox(height: Tokens.s2),
              const Text('几何全部是比例：16 与 320 是同一枚环',
                  style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap)),
              const SizedBox(height: Tokens.s4),
              block(16),
              block(40),
              block(120),
              block(320),
              const SizedBox(height: Tokens.s4),
              const Text('辉光变体（只许出现在启动屏与完成页）',
                  style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap)),
              block(120, glow: true),
            ],
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('label-320')), findsOneWidget);
    await binding.takeScreenshot('m3-brandmark-4-sizes')
        .timeout(const Duration(seconds: 15));
    debugPrint('LIANLEME-BRANDMArk-SHOT m3-brandmark-4-sizes');
  });
}
