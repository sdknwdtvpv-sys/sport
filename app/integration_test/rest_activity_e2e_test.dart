/// 练了么 · 组间休息 Live Activity 的**端到端**测试（只在 iOS 上断言）
///
/// 为什么必须有这一条：Dart 侧的桩测试只能证明"我调了那个通道"，
/// 证明不了"系统里真的开出了一条 Live Activity" —— 而后者才是这个功能存在的全部意义。
/// 中间隔着 MethodChannel、ActivityKit、以及一个**必须打包进 .appex 的扩展**，
/// 任何一环错了，桩测试照样全绿。
///
/// 跑法（模拟器 UDID 见 `docs/dev-environment.md`）：
///     flutter test integration_test/rest_activity_e2e_test.dart -d <模拟器 UDID>
///
/// ⚠️ **它验不了什么**：锁屏上那行字长什么样（排版/字体/间距）。
/// 这台机器上没有 `Simulator.app`（没法锁屏），所以**视觉验收仍然是缺的** ——
/// 见 `docs/plan-scene-and-return.md` 的状态一栏。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianleme/features/workout/rest_activity.dart';
import 'package:lianleme/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannelRestActivity bridge = MethodChannelRestActivity();

  /// 只在 iOS 上断言：Android 上没有这个通道，`activeCount` 恒 0。
  final bool supported = Platform.isIOS;

  testWidgets('记一组 → 系统里真的开出一条 Live Activity；跳过休息 → 撤下',
      (WidgetTester tester) async {
    // 跑**真实 App 和真实库**（与其它 e2e 一致）：这条要验的是"平台侧真的开出了
    // Live Activity"，用内存库替身反而离真相更远。
    app.main();
    // 冷启动要建库 / 导入 351 个动作；干净安装还会先弹一道隐私政策同意门
    // （不点它主界面一个像素都不渲染）。两者都需要等，所以循环等到首页真的出现。
    for (int i = 0; i < 40; i++) {
      if (find.byKey(const Key('start-workout')).evaluate().isNotEmpty) break;
      if (find.byKey(const Key('consent-agree')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('consent-agree')));
      }
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.byKey(const Key('start-workout')), findsOneWidget,
        reason: '首页没起来，后面的断言都在测空气');

    // 首页 → 大按钮直开练（用今天的第一条建议）。
    // 进训练屏要算建议 / 建会话，别用固定等待：等它真的出现。
    await tester.tap(find.byKey(const Key('start-workout')));
    for (int i = 0; i < 30; i++) {
      if (find.byKey(const Key('big-log-button')).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.byKey(const Key('big-log-button')), findsOneWidget,
        reason: '没进训练屏 —— 后面"记一组"的断言都是空的');

    expect(await bridge.activeCount(), 0, reason: '前置：还没记组，不该有 Live Activity');

    // 记一组 —— 组间休息随之开始
    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump(const Duration(seconds: 2));

    if (supported) {
      expect(await bridge.activeCount(), 1,
          reason: '记完一组之后，系统里必须有且只有一条（重复 request 会在锁屏上叠起来）');
    }

    // 跳过休息 → 那条必须被撤下
    await tester.tap(find.byKey(const Key('skip-rest')));
    await tester.pump(const Duration(seconds: 2));

    expect(await bridge.activeCount(), 0,
        reason: '用户跳过了休息，锁屏上不该还挂着一条倒计时');
  });
}
