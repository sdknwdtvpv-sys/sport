/// 练了么 · **原生控件那一版的证据图**（2026-10-09）
///
/// 用户：「我想要苹果原生的 uitabbar」→「其他的切换选项能不能也做成这个效果呢，
/// 比如说像周 月 年的那个调整」。这一版把：
///   * 底栏 → 苹果原生 `UITabBar`（`NativeTabBarBridge.swift`）；
///   * 周/月/年这类分段切换器 → 苹果原生 `UISegmentedControl`（`NativeSegmentedBridge.swift`）。
///
/// 这个脚本只做一件事：**把这两样东西拍下来**（进步页的三段切换器、数据页的三段切换器）。
/// ⚠️ 它顺带证明了 `debugSwitchTab` 这条钩子是通的 —— iOS 上底栏是平台视图，
/// `tester.tap(Key('tab-进步'))` 根本不存在，只能走外壳交出来的入口。
///
/// 跑法（模拟器或真机都行）：
///   flutter drive --driver=test_driver/screenshot_driver.dart \
///     --target=integration_test/native_controls_evidence_test.dart -d <设备 id>
/// ⚠️ 产物走 `SHOT_DIR`（默认 `../store-assets/screenshots`），
/// 这里刻意用**另一个目录**，免得把商店那套图覆盖掉。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianleme/main.dart' as app;

import 'evidence_sets.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('原生控件证据：底栏 + 分段切换器', (WidgetTester tester) async {
    Future<void> settle(int ms) async {
      // ⚠️ 不能用 pumpAndSettle：底栏那个平台视图一直在动（玻璃），它永远不会静止
      await tester.pump(const Duration(milliseconds: 120));
      for (int i = 0; i < ms ~/ 120; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    Future<void> capture(String name) async {
      // ⚠️ surface 只转一次（每个用例里）；转换之后 takeScreenshot 才拿得到内容。
      // 平台视图（原生底栏/分段控件）**不会**进这张图 —— 这是 Flutter 的已知限制，
      // 所以"原生控件长什么样"要看**设备级截图**：
      //   iOS：`xcrun devicectl device capture screenshot` / `simctl io screenshot`
      //   Android：`adb exec-out screencap -p`
      // 这里拍的是"页面到了哪一步"，用来证明这条路走得通。
      await binding.takeScreenshot(name).timeout(const Duration(seconds: 8));
      debugPrint('LIANLEME-NATIVE-SHOT $name');
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

    // ① 「进步」页：**周 / 月 / 年** 那个三段切换器就在这儿
    await switchTab(tester, 0, '进步');
    await settle(2000);
    await capture('native-01-progress-segmented');

    // ② 「数据」页：按动作看 / 按时间看
    await switchTab(tester, 1, '数据');
    await settle(2000);
    await capture('native-02-all-data-segmented');

    // ③ 「计划」页：本周 / 模板库 / 历史
    await switchTab(tester, 3, '计划');
    await settle(2000);
    await capture('native-03-plan-segmented');

    debugPrint('LIANLEME-NATIVE-DONE');
  });
}
