/// 练了么 · **训练主屏重排的证据图**（2026-10-10）
///
/// 对应 `docs/plan-ux-2026-10-10.md` P0-3：主按钮回到屏幕下 1/3、休息改成主按钮上方
/// 一条带百分比的细进度、上半屏那块死区换成「上次 / 历史最佳」、两个 x/y 分开、
/// 「改重量」变成看得见的入口。
///
/// 这个脚本只做一件事：**把那几样拍下来**，而且是按**用户真实路径**走的 ——
/// 训练屏上第一次练某个动作时**没有历史**（对照带整条不出现，这是有意的），
/// 所以要先真的练完一场，再开第二场，那条带子才会长出「上次」与「历史最佳」。
///
/// ⚠️ 训练屏**没有平台视图**（底栏那两块真的 `UITabBar` / `UISegmentedControl`
/// 在训练中是整屏被盖住的），所以 `takeScreenshot` 拍得到它 —— 与
/// `native_controls_evidence_test.dart` 那两个必须用设备级截图的东西不一样。
///
/// 跑法：
///   SHOT_DIR=../docs/images/workout-2026-10-10 flutter drive \
///     --driver=test_driver/screenshot_driver.dart \
///     --target=integration_test/workout_screen_evidence_test.dart -d <设备 id>
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianleme/main.dart' as app;

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('训练主屏重排：证据图', (WidgetTester tester) async {
    Future<void> settle(int ms) async {
      // ⚠️ 不能用 pumpAndSettle：训练屏的休息倒计时每秒都在动，永远不会静止
      await tester.pump(const Duration(milliseconds: 120));
      for (int i = 0; i < ms ~/ 120; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    Future<void> capture(String name) async {
      await binding.takeScreenshot(name).timeout(const Duration(seconds: 8));
      debugPrint('LIANLEME-WORKOUT-SHOT $name');
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

    /// 从首页开一场训练、记 [sets] 组、再退出来（返回 = 结束这次训练）。
    Future<void> trainOnce(int sets) async {
      await tester.tap(find.byKey(const Key('start-workout')));
      await settle(2200);
      for (int i = 0; i < sets; i++) {
        await tester.tap(find.byKey(const Key('big-log-button')));
        await settle(1400);
      }
    }

    Future<void> leaveWorkout() async {
      await tester.tap(find.byKey(const Key('back-button')));
      await settle(1500);
      // 用了杠铃 → 会弹一次「杠铃归位了吗」（用户真实路径上的一步）
      if (find.byKey(const Key('unload-plates-ok')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('unload-plates-ok')));
        await settle(700);
      }
      await settle(2000);
      if (find.text('完成').evaluate().isNotEmpty) {
        await tester.tap(find.text('完成'));
        await settle(1600);
      }
    }

    // ① 第一场：**没有历史**的那一屏（对照带整条不出现、大按钮贴底）
    await trainOnce(1);
    await capture('workout-01-first-time');
    await tester.tap(find.byKey(const Key('big-log-button')));
    await settle(1500);
    await capture('workout-02-resting');
    await tester.tap(find.byKey(const Key('big-log-button')));
    await settle(1500);
    await capture('workout-03-three-sets');
    await leaveWorkout();

    // ② 第二场：这下有历史了 —— 「上次 / 历史最佳」那条对照带才长出来
    await settle(1200);
    await trainOnce(1);
    await capture('workout-04-with-history');
    await tester.tap(find.byKey(const Key('big-log-button')));
    await settle(1500);
    await capture('workout-05-with-history-resting');

    debugPrint('LIANLEME-WORKOUT-DONE');
  });
}
