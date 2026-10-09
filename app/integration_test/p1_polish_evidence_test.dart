/// 练了么 · **P1 扫尾的证据图**（2026-10-10）
///
/// 拍三张：
///   ① **选动作页**：四行筛选都有行标签、「全部」未筛选时是中性色、每行只有一行副标题、
///      右边念的是「上次 …」而不是种子默认重量；
///   ② **「我」**：训练统计收成**一条细线带**（与「进步」页同一个语言）+ 齿轮在这一格；
///   ③ **「进步」**：顶栏**没有齿轮**（齿轮只在「我」那一格）。
///
/// ⚠️ 为了让「上次 …」真的出现，脚本先**练一场**（记两组杠铃卧推）再进选动作页 ——
/// 干净安装的库里没有历史，右边就只会是种子默认重量。
///
/// 跑法：
///   SHOT_DIR=../docs/images/p1-2026-10-10 flutter drive \
///     --driver=test_driver/screenshot_driver.dart \
///     --target=integration_test/p1_polish_evidence_test.dart -d <设备 id>
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianleme/main.dart' as app;

import 'evidence_sets.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P1 扫尾：选动作页 / 我 / 进步', (WidgetTester tester) async {
    Future<void> settle(int ms) async {
      await tester.pump(const Duration(milliseconds: 120));
      for (int i = 0; i < ms ~/ 120; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    Future<void> capture(String name) async {
      await binding.takeScreenshot(name).timeout(const Duration(seconds: 8));
      debugPrint('LIANLEME-P1-SHOT $name');
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

    // ① 先练一场（这样"上次"才有东西可念）
    await tester.tap(find.byKey(const Key('start-workout')));
    await settle(2200);
    for (int i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('big-log-button')));
      await settle(1400);
    }
    await tester.tap(find.byKey(const Key('back-button')));
    await settle(1500);
    if (find.byKey(const Key('unload-plates-ok')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('unload-plates-ok')));
      await settle(700);
    }
    await settle(2000);
    if (find.text('完成').evaluate().isNotEmpty) {
      await tester.tap(find.text('完成'));
      await settle(1800);
    }

    // ② 选动作页：从首页那张卡 → 建议卡 → 「我自己选」
    await tester.tap(find.byKey(const Key('open-plan')));
    await settle(1800);
    if (find.byKey(const Key('pick-myself')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('pick-myself')));
      await settle(2000);
    }
    await capture('p1-01-picker');

    // ⚠️ 选动作页是**推上来的路由**，它盖着外壳 —— 不先退出来，切 tab 只会改**背后**
    // 那棵树，截图仍然是选动作页（第一版就是这么拍出两张一模一样的图）。
    if (find.byKey(const Key('picker-back')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('picker-back')));
      await settle(1500);
    }
    // 建议卡也要退出来才回得到外壳
    for (int i = 0; i < 2; i++) {
      final Finder back = find.byKey(const Key('today-back'));
      if (back.evaluate().isEmpty) break;
      await tester.tap(back);
      await settle(1200);
    }

    // ③ 「我」：统计细线带 + 齿轮在这一格
    await switchTab(tester, 2, '我');
    await settle(1800);
    await capture('p1-02-profile');

    // ④ 「进步」：顶栏没有齿轮
    await switchTab(tester, 0, '进步');
    await settle(1800);
    await capture('p1-03-progress-no-gear');

    debugPrint('LIANLEME-P1-DONE');
  });
}
