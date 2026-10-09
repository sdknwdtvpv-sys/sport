/// 练了么 · **首页改版的证据图**（2026-10-10）
///
/// 对应 `docs/plan-ux-2026-10-10.md` 的 P0-1（激励收敛）+ P1-4/P1-5（入口收敛）：
///   * 删掉「打卡」大卡 + 「本周挑战」那一行 → 收成**一行事实**（连续 N 天 · 本周已练 M 次）；
///   * 删掉主按钮下那句「不知道怎么练？帮我定个计划 ›」（那个向导搬进了「计划」页）；
///   * 四个同权重工具磁贴 → **一只卡里的三格**（动作库 / 记录体重 / 5 分钟活动），
///     「成就」收进「我」。
///
/// 跑法：
///   SHOT_DIR=../docs/images/home-2026-10-10 flutter drive \
///     --driver=test_driver/screenshot_driver.dart \
///     --target=integration_test/home_evidence_test.dart -d <设备 id>
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianleme/main.dart' as app;

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('首页：激励收成一行 + 三个快捷入口', (WidgetTester tester) async {
    Future<void> settle(int ms) async {
      await tester.pump(const Duration(milliseconds: 120));
      for (int i = 0; i < ms ~/ 120; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    Future<void> capture(String name) async {
      await binding.takeScreenshot(name).timeout(const Duration(seconds: 8));
      debugPrint('LIANLEME-HOME-SHOT $name');
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
    await settle(800);
    await capture('home-01-first-launch');

    // 「计划」页：向导的新家（只在还没定过计划时出现）
    await switchTabToPlan(tester);
    await settle(1600);
    await capture('home-02-plan-page');

    debugPrint('LIANLEME-HOME-DONE');
  });
}

/// 切到「计划」那一格。⚠️ iOS 上底栏是**平台视图**（真的 `UITabBar`），
/// `tester.tap(Key('tab-计划'))` 不存在 —— 只能走外壳交出来的那个钩子
/// （这条坑在 `docs/screens.md` 的 S0 里记着）。
Future<void> switchTabToPlan(WidgetTester tester) async {
  final Finder tab = find.byKey(const Key('tab-计划'));
  if (tab.evaluate().isNotEmpty) {
    await tester.tap(tab);
    return;
  }
  app.debugSwitchTab?.call(3);
}
