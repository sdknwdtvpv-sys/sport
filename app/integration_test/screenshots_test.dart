/// 练了么 · 用**真实 App** 渲染出可用截图
///
/// **为什么需要它**：软著说明书与商店列表都要界面截图，而这两处都要求
/// "必须来自真实 App，不能拿 `prototype/index.html` 充数"。真机上截图本来做不到 ——
/// MIUI 禁掉了 `adb shell input`（`INJECT_EVENTS`），点不动屏幕。
///
/// 但 integration_test 的点击是**在 App 进程内模拟的**，不走 adb 注入那条路 ——
/// 于是它绕开了这个限制，而且拿到的是真实字体、真实布局、真实设备分辨率。
/// （widget 测试截不了：那边用的是测试字体，汉字会全渲染成方框。）
///
/// 跑法（在 `app/` 下）：
///     flutter drive --driver=test_driver/screenshot_driver.dart \
///                   --target=integration_test/screenshots_test.dart
/// 产物落在 `../store-assets/screenshots/`（**入库**，是交付物）。
///
/// 三条刻意的写法：
///   * **不用 `pumpAndSettle`** —— App 里有常驻的休息计时器，settle 会一直等不到静止。
///     改成推进固定时长（[settle]）。
///   * **每一步各包一层 try** —— 一步崩了不该让前面截好的图白截；日志写清哪步没成。
///   * **surface 只转一次** —— `convertFlutterSurfaceToImage()` 每张都调会抛异常
///     （第一版就这么写，从第二张开始全失败）。
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

  testWidgets('真实 App 截图', (WidgetTester tester) async {
    /// 推进 [ms] 毫秒而不是等"稳定"：App 里有个每秒走的休息计时器，
    /// `pumpAndSettle` 会一直等不到静止而超时。
    Future<void> settle([int ms = 1200]) async {
      final DateTime end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    bool surfaceReady = false;

    Future<void> capture(String name) async {
      if (Platform.isAndroid && !surfaceReady) {
        await binding.convertFlutterSurfaceToImage();
        surfaceReady = true;
        await settle(400);
      }
      await binding.takeScreenshot(name);
      shot.add(name);
      debugPrint('LIANLEME-SHOT $name');
    }

    Future<void> step(String name, Future<void> Function() body) async {
      try {
        await body();
      } catch (e) {
        failed.add('$name: $e');
        debugPrint('LIANLEME-SHOT-FAIL $name — $e');
        // 失败时顺手截一张现场图：不然只知道"没找到那个 key"，
        // 不知道当时到底停在哪一屏。（第一次跑就吃了这个亏：9 步连败，无从查起。）
        try {
          await binding.takeScreenshot('zz-fail-$name');
        } catch (_) {}
      }
    }

    /// 点 App 自己的返回键。**不要用 `Navigator.pop()` 硬弹** ——
    /// 第一版就是这么写的，弹完并没有回到首页（栈里还有选动作那层），
    /// 于是后面 9 步全部找不到目标。用户怎么回来，测试就怎么回来。
    Future<void> tapBack(Key key) async {
      await tester.tap(find.byKey(key));
    }

    app.main();
    // 冷启动要做：建库 / 导入 351 个动作 / 读设置。给足时间。
    await settle(6000);

    await step('01-home', () async {
      expect(find.byKey(const Key('start-workout')), findsOneWidget,
          reason: '首页没起来，后面都别谈了');
      await capture('01-home');
    });

    await step('02-suggestion', () async {
      await tester.tap(find.byKey(const Key('see-plan')));
      await settle(1800);
      await capture('02-suggestion');
    });

    await step('03-routine', () async {
      await tester.tap(find.byKey(const Key('use-routine')));
      await settle(1500);
      await capture('03-routine');
    });

    await step('03b-back', () async {
      // 计划页没有单独的返回键（它是从建议卡推上来的），这里只能程序化返回
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await settle(1200);
    });

    await step('04-picker', () async {
      await tester.tap(find.byKey(const Key('pick-myself')));
      await settle(1500);
      await capture('04-picker');
    });

    await step('04b-back-home', () async {
      await tapBack(const Key('picker-back')); // 选动作 → 建议卡
      await settle(1000);
      await tapBack(const Key('today-back')); // 建议卡 → 首页（不带结果 = 不练了）
      await settle(1600);
    });

    await step('05-workout', () async {
      await tester.tap(find.byKey(const Key('start-workout')));
      await settle(2500);
      await capture('05-workout');
    });

    await step('06-workout-logged', () async {
      // 记两组：大按钮连点。第一下之后按钮位置不变，所以能连点。
      await tester.tap(find.byKey(const Key('big-log-button')));
      await settle(1600);
      await tester.tap(find.byKey(const Key('big-log-button')));
      await settle(1600);
      await capture('06-workout-logged');
    });

    await step('07-summary', () async {
      // 返回 = 结束这次训练 → 主壳接着弹总结屏
      await tester.tap(find.byKey(const Key('back-button')));
      await settle(3000);
      await capture('07-summary');
    });

    await step('07b-close-summary', () async {
      await tester.tap(find.text('完成'));
      await settle(1500);
    });

    await step('08-progress', () async {
      await tester.tap(find.byKey(const Key('tab-进步')));
      await settle(2000);
      await capture('08-progress');
    });

    await step('09-all-data', () async {
      await tester.tap(find.byKey(const Key('open-all-data')));
      await settle(1800);
      await capture('09-all-data');
    });

    await step('09b-back', () async {
      await tester.tap(find.byKey(const Key('all-data-back')));
      await settle(1200);
    });

    await step('10-profile', () async {
      await tester.tap(find.byKey(const Key('tab-我')));
      await settle(1800);
      await capture('10-profile');
    });

    await step('11-body-metric', () async {
      await tester.tap(find.byKey(const Key('open-body-metric')));
      await settle(1500);
      await capture('11-body-metric');
    });

    debugPrint('LIANLEME-SHOT-SUMMARY 成功 ${shot.length} 张（${shot.join(',')}）'
        ' · 失败 ${failed.length} 步 ${failed.isEmpty ? '' : ':: ${failed.join(' | ')}'}');
  });
}
