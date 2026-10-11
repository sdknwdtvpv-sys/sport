/// 练了么 · **RepDB 动作插图的真机证据图**
///
/// **为什么不能靠 `adb shell input`**：MIUI 禁掉了注入事件（`INJECT_EVENTS`），
/// 点不动屏幕。integration_test 的点击是**在 App 进程内模拟的**，绕开这条限制，
/// 拿到的是真实字体、真实布局、真实设备分辨率（与 `screenshots_test.dart` 同一个理由）。
///
/// 跑法（在 `app/` 下，指名设备）：
///     SHOT_DIR=../docs/images/repdb-art-device \
///     flutter drive -d 75caf509 \
///       --driver=test_driver/screenshot_driver.dart \
///       --target=integration_test/repdb_art_shot_test.dart
///
/// 产物（入库，是"真机看过"的证据）：
///   `docs/images/repdb-art-device/01-detail-peak.png`（默认：顶峰）
///   `docs/images/repdb-art-device/02-detail-start.png`（点「看起始姿势」后）
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianleme/main.dart' as app;

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RepDB 插图：动作详情页两张证据图', (WidgetTester tester) async {
    /// 推进固定时长而不是 `pumpAndSettle`：App 里有常驻计时器，settle 等不到静止。
    Future<void> settle([int ms = 1200]) async {
      final DateTime end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    bool surfaceReady = false;
    Future<void> capture(String name) async {
      if (androidNeedsSurface && !surfaceReady) {
        await binding.convertFlutterSurfaceToImage();
        surfaceReady = true;
        await settle(400);
      }
      await binding.takeScreenshot(name).timeout(const Duration(seconds: 10));
      debugPrint('LIANLEME-SHOT $name');
    }

    app.main();
    await settle(7000);

    // 同意门（干净安装才会出现）
    if (find.byKey(const Key('consent-agree')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('consent-agree')));
      await settle(2500);
    }
    // 引导轮播（首启动才有）
    if (find.byKey(const Key('intro-skip')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('intro-skip')));
      await settle(2500);
    }
    // 上次训练没结束的恢复弹层会挡住入口
    final Finder discard = find.text('丢弃');
    if (discard.evaluate().isNotEmpty) {
      await tester.tap(discard.first);
      await settle(1500);
    }

    // 首页 →「开始今天的训练」→「自己挑」→ 选动作页
    // ⚠️ 这三步与 `screenshots_test.dart` 用同一套 key（那边已在真机上跑通过）
    await tester.tap(find.byKey(const Key('start-workout')));
    await settle(2000);
    await tester.tap(find.byKey(const Key('pick-myself')));
    await settle(2500);

    // 搜到杠铃卧推（用英文名搜，避开中文输入法）
    await tester.enterText(find.byKey(const Key('exercise-search')), 'Barbell Bench Press');
    await settle(2000);
    final Finder row =
        find.byKey(const Key('exercise-ex_bb_bench_press')).first;
    expect(row, findsOneWidget, reason: '搜索后必须有这一行');

    // 长按 → 详情（与真实手势一致）
    await tester.longPress(row);
    await settle(3000);

    await capture('01-detail-peak');

    // 点「看起始姿势」→ 换图
    final Finder toggle = find.byKey(const Key('detail-art-toggle'));
    if (toggle.evaluate().isNotEmpty) {
      await tester.tap(toggle);
      await settle(2000);
      await capture('02-detail-start');
    } else {
      debugPrint('LIANLEME-SHOT 没有姿势切换入口（这个动作只有一张图？）');
    }
  });
}

/// Android 上要把 Flutter surface 转成图片才能截；iOS 不需要。
/// 用常量而不是 `Platform.isAndroid`：这个文件只跑真机，但导入 dart:io 会让
/// web 编译目标出问题（仓库里没有 web 目标，仍然是多余的风险）。
const bool androidNeedsSurface = true;
