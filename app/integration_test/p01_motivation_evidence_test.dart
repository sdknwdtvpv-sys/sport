/// 练了么 · **P0-1 证据图：一条进度 + 一本收藏册**（2026-10-10）
///
/// 拍三张：
///   ① **训练完成页**：`✦ 新解锁 N 枚` 那一条（**只在真的解锁了才出现** ——
///      干净安装的第一次训练一定会解锁「首训」，所以这一趟跑得出来）；
///   ② **「我」**：只剩一条进度条（等级）+ 一行事实（连续 / 本周），
///      「成就」那一行写着 `已解锁 N / M 枚`；
///   ③ **成就页**：段位那一行（2026-10-10 从「我」搬进来的）与收藏册。
///
/// 跑法：
///   SHOT_DIR=../docs/images/p01-motivation-2026-10-10 flutter drive \
///     --driver=test_driver/screenshot_driver.dart \
///     --target=integration_test/p01_motivation_evidence_test.dart -d <设备 id>
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianleme/main.dart' as app;

import 'evidence_sets.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P0-1 证据：完成页新解锁条 + 「我」一条进度 + 成就页段位',
      (WidgetTester tester) async {
    Future<void> settle(int ms) async {
      await tester.pump(const Duration(milliseconds: 120));
      for (int i = 0; i < ms ~/ 120; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    Future<void> capture(String name) async {
      await binding.takeScreenshot(name).timeout(const Duration(seconds: 8));
      debugPrint('LIANLEME-P01-SHOT $name');
    }

    app.main();
    await settle(6000);

    if (find.byKey(const Key('consent-agree')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('consent-agree')));
      await settle(2500);
    }
    if (find.byKey(const Key('intro-skip')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('intro-skip')));
      await settle(1500);
    }

    await binding.convertFlutterSurfaceToImage();

    // 练一场（干净安装的第一次 → 一定会解锁「首训」）
    await tester.tap(find.byKey(const Key('start-workout')));
    await settle(2200);
    for (int i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('big-log-button')));
      await settle(1400);
    }

    // 返回 = 结束这次训练；用了杠铃会弹一次「杠铃归位了吗」
    await tester.tap(find.byKey(const Key('back-button')));
    await settle(1500);
    if (find.byKey(const Key('unload-plates-ok')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('unload-plates-ok')));
      await settle(700);
    }
    await settle(2200);
    await capture('p01-01-summary-unlock');

    // 关掉完成页 → 「我」
    if (find.text('完成').evaluate().isNotEmpty) {
      await tester.tap(find.text('完成'));
      await settle(1800);
    }
    await switchTab(tester, 2, '我');
    await settle(2000);
    await capture('p01-02-profile');

    // 成就页（段位那一行 + 收藏册）
    final Finder open = find.byKey(const Key('open-achievements'));
    if (open.evaluate().isNotEmpty) {
      await tester.ensureVisible(open);
      await settle(400);
      await tester.tap(open);
      await settle(2000);
      await capture('p01-03-achievements');
    }

    debugPrint('LIANLEME-P01-DONE');
  });
}
