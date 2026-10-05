/// 练了么 · **v1.53 那批健身房细节的证据图**（不是商店素材，是验证证据）
///
/// 与 `v152_evidence_test.dart` 同一个套路：产物进 `docs/images/`，不参与商店截图清单。
/// 这一趟要走"用户真的会用"的路径，因为这几处改动都是**只有真跑一遍才看得出对不对**的：
/// 换动作按钮在不在、休息条上那两个 ±15 是不是真能点、换完动作之后重量有没有跟着换、
/// 以及"上次练了多少"那行是不是在**第二次**训练里才出现。
///
/// 跑法（在 `app/` 下，模拟器 `emulator-5554`）：
///     SHOT_DIR=../docs/images flutter drive \
///       --driver=test_driver/screenshot_driver.dart \
///       --target=integration_test/v153_evidence_test.dart -d emulator-5554
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

  testWidgets('v1.53 健身房细节证据图', (WidgetTester tester) async {
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

    // 首启两道门：政策同意 → 卖点轮播
    if (find.byKey(const Key('consent-agree')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('consent-agree')));
      await settle(2500);
    }
    if (find.byKey(const Key('intro-skip')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('intro-skip')));
      await settle(1800);
    }

    // ★ 常亮：这一屏在的时候，宿主机的 `dumpsys window` 里应当能看到 KEEP_SCREEN_ON
    //   （那一半由 `docs/plan-gym-polish.md` 的验证记录负责，Dart 侧测不了）。
    await step('workout', () async {
      await tester.tap(find.byKey(const Key('start-workout')));
      await settle(2500);
      expect(find.byKey(const Key('big-log-button')), findsOneWidget);
      // 换动作入口必须一眼看得到
      expect(find.byKey(const Key('swap-exercise')), findsOneWidget);
      await capture('v153-01-workout');
    });

    // 记一组 → 休息开始 → 休息条上的 ±15 出现
    await step('rest-controls', () async {
      await tester.tap(find.byKey(const Key('big-log-button')));
      await settle(1500);
      expect(find.byKey(const Key('rest-minus')), findsOneWidget);
      expect(find.byKey(const Key('rest-plus')), findsOneWidget);
      final String before =
          tester.widget<Text>(find.byKey(const Key('rest-time'))).data!;
      await tester.tap(find.byKey(const Key('rest-plus')));
      await settle(1200);
      final String after =
          tester.widget<Text>(find.byKey(const Key('rest-time'))).data!;
      expect(after, isNot(before), reason: '+15 之后秒数必须真的变了');
      await capture('v153-02-rest-plus15');
    });

    // 换动作：按当前部位预筛的选择器 → 选一个 → 头部动作名跟着换
    await step('swap', () async {
      await tester.tap(find.byKey(const Key('swap-exercise')));
      await settle(2000);
      await capture('v153-03-swap-picker');
      // ⚠️ 别用前缀匹配找行：搜索框的 key 是 `exercise-search`，也在 `exercise-` 里，
      //    第一次跑就点到了搜索框（键盘弹起来，看着像"点了没反应"）。直接点那个动作。
      //    选一个**同部位但不同**的动作（当前是杠铃卧推 → 换成上斜哑铃卧推）。
      final Finder row = find.byKey(const Key('exercise-ex_db_incline_press'));
      expect(row, findsOneWidget, reason: '同部位预筛之后应当能看到这个动作');
      await tester.tap(row);
      await settle(2500);
      expect(find.byKey(const Key('big-log-button')), findsOneWidget,
          reason: '换完还要回到训练屏');
      await capture('v153-04-after-swap');
    });

    // 结束这次训练 → 回首页 → 再开一次：**这时才有"上次练了多少"那一行**
    await step('last-time', () async {
      await tester.tap(find.byKey(const Key('back-button')));
      await settle(3000);
      // 总结页（有「完成」就点掉）
      if (find.text('完成').evaluate().isNotEmpty) {
        await tester.tap(find.text('完成'));
        await settle(2000);
      }
      await capture('v153-05-summary');
      if (find.byKey(const Key('start-workout')).evaluate().isEmpty) {
        // 可能还停在总结页，再点一次完成
        if (find.text('完成').evaluate().isNotEmpty) {
          await tester.tap(find.text('完成'));
          await settle(2000);
        }
      }
      await tester.tap(find.byKey(const Key('start-workout')));
      await settle(2500);
      // ⚠️ 这里**不断言**那一行一定在：首页推荐到哪个动作由轮转决定，
      //    推荐到一个没练过的动作时那一行本来就不该出现（不编）。
      //    "有历史就显示、没历史就不显示"的确定性证据在单测里：
      //    `last_time_test`（8 条）与 `workout_flow_test` 的两条 widget 测试。
      final int shown = find.byKey(const Key('last-time')).evaluate().length;
      debugPrint('LIANLEME-EVIDENCE last-time-shown=$shown'
          ' (0 = 这次推荐的动作还没有历史，属正常)');
      await capture('v153-06-last-time');
    });

    debugPrint('LIANLEME-EVIDENCE-SUMMARY 成功 ${shot.length} 张（${shot.join(',')}）'
        ' · 失败 ${failed.length} 步 ${failed.isEmpty ? '' : ':: ${failed.join(' | ')}'}');
  });
}
