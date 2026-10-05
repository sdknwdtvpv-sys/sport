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

    /// ⚠️ **必须带超时**。踩过两次：失败分支里那次"现场截图"没有超时，
    /// 结果 11 步都跑完了、`takeScreenshot` 却再也不返回 —— 整个 run 卡死，
    /// driver 侧一张图都写不出来（截图字节是等 run 结束才回传的）。
    /// 少一张现场图无所谓，把全部截图赔进去才是灾难。
    /// 截图前必须先把 Flutter 的 surface 转成图片（Android 上只做一次）。
    ///
    /// ⚠️ 这一步原先只在**成功路径**（`capture`）里做，于是"第一步就失败"时
    /// 那张现场图必定抛 `Call convertFlutterSurfaceToImage() before taking a screenshot`
    /// —— 而那正是最需要看图的时候（2026-10-05 重跑时 15 步全红、一张诊断图都没有）。
    Future<void> ensureSurface() async {
      if (Platform.isAndroid && !surfaceReady) {
        await binding.convertFlutterSurfaceToImage();
        surfaceReady = true;
        await settle(400);
      }
    }

    Future<void> shotWithTimeout(String name) async {
      try {
        await ensureSurface();
        await binding.takeScreenshot(name).timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('LIANLEME-SHOT-TIMEOUT $name — $e');
      }
    }

    Future<void> capture(String name) async {
      await ensureSurface();
      await shotWithTimeout(name);
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
        await shotWithTimeout('zz-fail-$name');
      }
    }

    /// 滚到某个 key 可见。
    ///
    /// ⚠️ 必须指名"整页那个滚动体"（`body-scroll`）：身体数据页从 v1.52 起
    /// **有两个 ListView**（整页纵向 + 日期那排横向 chips），
    /// `find.byType(ListView)` 会同时命中两个，`dragUntilVisible` 当场抛
    /// `Found 2 widgets`。这也是 v1.52 补页内 key 的原因。
    Future<void> scrollTo(WidgetTester tester, Key key,
        {int step = 220}) async {
      await tester.dragUntilVisible(
        find.byKey(key),
        find.byKey(const Key('body-scroll')),
        Offset(0, -step.toDouble()),
      );
      await settle(500);
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

    // 首次启动多了一道**隐私政策同意门**（法律要求）：干净安装的包里主界面在同意之前
    // 一个像素都不渲染。截图与流程都必须先过这道门 —— 而这一步（在真机上真的点一下）
    // 本身就是"那道门能用"的证据。
    if (find.byKey(const Key('consent-agree')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('consent-agree')));
      await settle(2500);
      debugPrint('LIANLEME-SHOT privacy-consent-agreed');
    }

    // v1.49 起：同意之后还有**三屏卖点轮播**（只在首次启动出现 —— 同意门本身就是那个标记）。
    // 截图脚本必须走这一步：不处理它，后面每一步都找不到控件。
    // ⚠️ 2026-10-05 重跑这套图时**就是这么 15 步全红的** —— v1.48–v1.52 做完之后从没重拍过，
    // 脚本与 App 之间差了这一个新屏。教训：新屏上线后要**立刻**重跑一次这套脚本，
    // 否则"截图脚本还能跑通"这件事本身没有任何守卫。
    if (find.byKey(const Key('intro-skip')).evaluate().isNotEmpty) {
      await settle(1500);
      debugPrint('LIANLEME-SHOT intro-carousel-present');
      await tester.tap(find.byKey(const Key('intro-skip')));
      await settle(1800);
    }

    await step('01-home', () async {
      expect(find.byKey(const Key('start-workout')), findsOneWidget,
          reason: '首页没起来，后面都别谈了');
      await capture('01-home');
    });

    await step('02-suggestion', () async {
      await tester.tap(find.byKey(const Key('open-plan')));
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
      // 只需一次返回：从建议卡点「我自己选」是把建议卡**弹掉**再推选动作页的，
      // 所以选动作页返回 = 直接回首页。（原来还补点了一次 today-back，
      // 结果那一下必然落空 —— 现场图与 01-home 逐字节相同，正好证明了当时已在首页。）
      await tapBack(const Key('picker-back'));
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
      await tester.tap(find.byKey(const Key('tab-我的')));
      await settle(1800);
      await capture('10-profile');
    });

    await step('10b-data-tools', () async {
      // 2026-10-01 重排：身体数据 / 导出 / 导入 / 删除都收进了「我 → 数据与备份」。
      // 顺手把这一页也留一张 —— 它是"我"那一族里第二个二级页。
      await tester.dragUntilVisible(
        find.byKey(const Key('open-data-tools')),
        find.byType(ListView),
        const Offset(0, -220),
      );
      await settle(600);
      await tester.tap(find.byKey(const Key('open-data-tools')));
      await settle(1200);
      await capture('10b-data-tools');
    });

    await step('11-body-metric', () async {
      // 已经在「数据与备份」页里了：身体数据是这一页的第一行
      // （ListView 懒构建这条规律仍然成立，所以还是先滚过去再点）
      await tester.dragUntilVisible(
        find.byKey(const Key('open-body-metric')),
        find.byType(ListView),
        const Offset(0, -220),
      );
      await settle(800);
      await tester.tap(find.byKey(const Key('open-body-metric')));
      await settle(1500);

      // v1.31.0 起，这一页前面多了一道**敏感信息单独同意**的门。不处理它，
      // 截到的是对话框 —— 而正确做法不是"绕过"，是按用户真实路径点过去，
      // 顺手把这道门本身也留一张证（软著说明书要讲清"体重单独同意"这件事）。
      //
      // 这条分支是硬找出来的：v1.31.0 之前的图 11-body-metric 里是表单，
      // 而那之后新装的 App 根本到不了表单 —— 图比 App 旧了一个版本。
      final bool consentGate =
          find.byKey(const Key('body-consent-agree')).evaluate().isNotEmpty;
      debugPrint('LIANLEME-SHOT body-consent-gate=$consentGate');
      if (consentGate) {
        await capture('11a-body-consent');
        await tester.tap(find.byKey(const Key('body-consent-agree')));
        await settle(1800);
      }

      // v1.52：这一页多了腰围 / 肌肉量 / 身高，摘要卡会算 BMI，趋势卡要**两次以上**记录。
      // 所以这里顺手把真实录入路径走两遍（今天 + 昨天）—— 截到的才是"有数据的样子"，
      // 而不是一张空表单（空表单证明不了 BMI 与趋势真的能用）。
      Future<void> fillAndSave(String date, String weight, String waist,
          String muscle, String height) async {
        if (date.isNotEmpty) {
          await tester.tap(find.byKey(Key('body-day-$date')));
          await settle(700);
        }
        await tester.enterText(find.byKey(const Key('body-weight')), weight);
        await settle(400);
        await scrollTo(tester, const Key('body-waist'));
        await tester.enterText(find.byKey(const Key('body-waist')), waist);
        await settle(300);
        await tester.enterText(find.byKey(const Key('body-muscle')), muscle);
        await settle(300);
        await tester.enterText(find.byKey(const Key('body-height')), height);
        await settle(300);
        await scrollTo(tester, const Key('body-save'));
        await tester.tap(find.byKey(const Key('body-save')));
        await settle(1500);
      }

      String day(DateTime d) => '${d.year}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      final String today = day(DateTime.now());
      final String y = day(DateTime.now().subtract(const Duration(days: 1)));

      await step('11c-body-fill-two-days', () async {
        // ⚠️ 两次**都要点日期 chip**：页面选中的那天不会自己跳回今天，
        // 第二次不点的话两次都写进昨天那一条 —— 只有一条记录，
        // 趋势卡就（正确地）不出现。第一版就是这么写的，图里少了趋势。
        await fillAndSave(y, '73.2', '82.5', '34.2', '176');
        await fillAndSave(today, '72.4', '82', '34.6', '176');
        // 存完滚回顶部：图里要同时有摘要卡（含 BMI）与趋势卡
        await tester.drag(find.byKey(const Key('body-scroll')), const Offset(0, 2400));
        await settle(800);
      });
      // SnackBar（"已记录 …的身体数据"）会浮在表单上方，等它自己走掉再拍
      await settle(4200);
      await capture('11-body-metric');

      await step('11b-body-revoke', () async {
        // 撤回同意（PIPL 第 15 条）的入口在这一页最下面，滚到底才可见 ——
        // 单独留一张，作为"这个入口真的在、而且没渲染坏"的证
        // （`**` 那类漏字只有截图看得见，单测看的是 key）。
        await scrollTo(tester, const Key('body-revoke'));
        await capture('11b-body-revoke');
      });
    });

    debugPrint('LIANLEME-SHOT-SUMMARY 成功 ${shot.length} 张（${shot.join(',')}）'
        ' · 失败 ${failed.length} 步 ${failed.isEmpty ? '' : ':: ${failed.join(' | ')}'}');
  });
}
