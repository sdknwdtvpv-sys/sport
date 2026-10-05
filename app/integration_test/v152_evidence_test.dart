/// 练了么 · **v1.52 那批新屏的证据图**（不是商店素材，是验证证据）
///
/// 为什么要单独一个脚本：商店那三套图（`integration_test/screenshots_test.dart`）
/// 的清单是**显式**的（`tool/check-screenshots.mjs` 里逐张列着，加一张要同时改三套图与
/// 四份文档），而 v1.49–v1.51 上线的三个屏（引导页轮播 / 通知中心 / 计划三视图）
/// 当时没有留证据图 —— 于是"三个新屏真的长这样"这件事只有代码，没有图。
///
/// 这一个脚本只做证据：产物进 `docs/images/`（那一目录不参与商店截图核对），
/// 命名统一 `v152-*`，每一张对应排期表里的一条里程碑。
///
/// 跑法（在 `app/` 下，模拟器 `emulator-5554`）：
///     SHOT_DIR=../docs/images flutter drive \
///       --driver=test_driver/screenshot_driver.dart \
///       --target=integration_test/v152_evidence_test.dart -d emulator-5554
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianleme/main.dart' as app;

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final List<String> shot = <String>[];
  final List<String> failed = <String>[];

  testWidgets('v1.49–v1.52 新屏证据图', (WidgetTester tester) async {
    /// 推进固定时长（不用 `pumpAndSettle`：App 里有常驻的休息计时器，永远静止不了）。
    Future<void> settle([int ms = 1200]) async {
      final DateTime end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    bool surfaceReady = false;

    Future<void> ensureSurface() async {
      if (Platform.isAndroid && !surfaceReady) {
        await binding.convertFlutterSurfaceToImage();
        surfaceReady = true;
        await settle(400);
      }
    }

    Future<void> capture(String name) async {
      try {
        await ensureSurface();
        await binding.takeScreenshot(name).timeout(const Duration(seconds: 8));
        shot.add(name);
        debugPrint('LIANLEME-EVIDENCE $name');
      } catch (e) {
        failed.add('$name: $e');
        debugPrint('LIANLEME-EVIDENCE-FAIL $name — $e');
      }
    }

    Future<void> step(String name, Future<void> Function() body) async {
      try {
        await body();
      } catch (e) {
        failed.add('$name: $e');
        debugPrint('LIANLEME-EVIDENCE-STEP-FAIL $name — $e');
      }
    }

    app.main();
    await settle(7000);

    // 首次启动那道政策同意门
    if (find.byKey(const Key('consent-agree')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('consent-agree')));
      await settle(2500);
    }

    // ── v1.49 引导页卖点轮播（同意门之后、主界面之前，只在首次启动出现）──────
    await step('intro', () async {
      expect(find.byKey(const Key('intro-skip')), findsOneWidget,
          reason: '首次启动应当能看到引导页（每屏右上角都有「跳过」）');
      await capture('v152-01-intro-1');
      for (int i = 2; i <= 3; i++) {
        await tester.tap(find.byKey(const Key('intro-next')));
        await settle(1400);
        await capture('v152-0$i-intro-$i');
      }
      // 用「跳过」离开：末屏那个按钮是"开始第一次训练"（会真的开一场训练，
      // 后面几屏就会被训练屏挡住）。这一步顺手也是"跳过真的能出去"的证据。
      await tester.tap(find.byKey(const Key('intro-skip')));
      await settle(1800);
      expect(find.byKey(const Key('start-workout')), findsOneWidget,
          reason: '跳过后应当直接到主界面');
    });

    // ── v1.50 通知中心（首页右上角铃铛）────────────────────────────────────
    await step('notifications', () async {
      await tester.tap(find.byKey(const Key('open-notifications')));
      await settle(1600);
      await capture('v152-04-notification-center');
      await tester.tap(find.byKey(const Key('notifications-back')));
      await settle(1400);
    });

    // ── v1.51 计划屏的三个视图 ────────────────────────────────────────────
    await step('plan-week', () async {
      await tester.tap(find.byKey(const Key('tab-计划')));
      await settle(1800);
      await capture('v152-05-plan-week');
    });
    await step('plan-history', () async {
      await tester.tap(find.text('历史'));
      await settle(1500);
      await capture('v152-06-plan-history');
    });
    await step('plan-library', () async {
      await tester.tap(find.text('模板库'));
      await settle(1500);
      await capture('v152-07-plan-library');
    });

    debugPrint('LIANLEME-EVIDENCE-SUMMARY 成功 ${shot.length} 张（${shot.join(',')}）'
        ' · 失败 ${failed.length} 步 ${failed.isEmpty ? '' : ':: ${failed.join(' | ')}'}');
  });
}
