/// 练了么 · **启动接力**的证据图（VI 计划 T3-6）
///
/// 冷启动那一刻屏幕上有两枚"同一枚品牌环"：先是原生的 `LaunchImage@3x.png`（UIKit 画的），
/// 再是 Flutter 第一帧的 `SplashOverlay`。这张证据图把两者并排放：
///   * 左：原生启动图（从仓库里那张 PNG 直接读，不是重画）；
///   * 右：`SplashOverlay` 在模拟器上的实拍。
///
/// 数字上的对位由 `tool/check-launch-relay.py` 每次门禁核（外径 / 环心 alpha / 圆心偏移），
/// 这张图是给人看的第二道。
///
/// 跑法：
///   SHOT_DIR=../docs/images/plan-vi-2026-10-10/raw flutter drive \
///     --driver=test_driver/screenshot_driver.dart \
///     --target=integration_test/splash_evidence_test.dart -d <设备 id>
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianleme/features/onboarding/splash_overlay.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('内启动屏（与原生启动图接力）', (WidgetTester tester) async {
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpWidget(const MaterialApp(home: SplashOverlay()));
    // 让它呼吸两个周期再拍（拍的是"启动中"的样子，不是第一帧）
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.byKey(const Key('brand-mark')), findsOneWidget);
    await binding.takeScreenshot('m3-splash-inapp')
        .timeout(const Duration(seconds: 15));
    debugPrint('LIANLEME-SPLASH-SHOT m3-splash-inapp');
  });
}
