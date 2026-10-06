/// 练了么 · **开关**（`GlassSwitch` / `AppSwitchTile`）
///
/// 守两件事：
///   1. **分界线**：iOS 走原生 `UISwitch`（`lianleme/switch` 这个平台视图），
///      非 iOS 仍然是 Material `Switch`（Android 一个像素都不动）；
///   2. **值的方向**：Dart 说值、原生报操作 —— 值变化时要把 `setValue` 发过去，
///      用户拨动时要回调回来（这两个方向任一断了，开关就会"自己跳回去"）。
///
/// 为什么要有这组：用户 2026-10-06 的备忘条第 3 条就是"开关没有苹果的原生玻璃效果"，
/// 换实现时最容易的错是**只换了壳、忘了值**。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/glass_switch.dart';

Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: child))));
}

void main() {
  testWidgets('★ 非 iOS：不许出现平台视图，仍然是 Material 开关', (WidgetTester tester) async {
    for (final TargetPlatform p in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.macOS,
    ]) {
      debugDefaultTargetPlatformOverride = p;
      await pump(tester, GlassSwitch(value: true, onChanged: (bool _) {}));
      expect(find.byType(UiKitView), findsNothing, reason: '$p 上不该有平台视图');
      expect(find.byType(Switch), findsOneWidget);
      final Switch sw = tester.widget<Switch>(find.byType(Switch));
      expect(sw.value, isTrue, reason: '值要如实透给 Material 开关');
    }
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('★ iOS：走原生开关，viewType 与创建参数逐项对', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pump(tester, GlassSwitch(value: true, onChanged: (bool _) {}));

    final UiKitView view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(view.viewType, 'lianleme/switch',
        reason: '与 GlassBridge.swift 里的 switchViewType 必须逐字一致');
    final Map<Object?, Object?> args = view.creationParams! as Map<Object?, Object?>;
    expect(args['value'], true);
    expect(args['onColor'], isNotNull, reason: '开关的"打开"颜色跟随主题主色');
    debugDefaultTargetPlatformOverride = null;
  });

  // ⚠️ 「值变化时发 setValue」这条**在 widget 测试里测不到**：平台视图不会被真的创建，
  // `onPlatformViewCreated` 不触发 → 通道是 null。那条链路的真实证据是模拟器实拍
  // （`docs/images/memo-20261006-2-unit-switch.png`：开关跟着 Dart 的状态亮/灭），
  // 以及原生侧的回声保护（`applyingFromDart`，见 GlassBridge.swift）。

  testWidgets('★ 一行开关（AppSwitchTile）：点整行也能切换，key 留在这一行上',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    bool? got;
    await pump(
      tester,
      AppSwitchTile(
        key: const Key('demo-switch'),
        value: false,
        onChanged: (bool v) => got = v,
        title: const Text('根据历史提示重量'),
      ),
    );
    expect(find.byKey(const Key('demo-switch')), findsOneWidget,
        reason: '测试与用户都按这个 key 找它，别把 key 挪到内层去');
    await tester.tap(find.byKey(const Key('demo-switch')));
    expect(got, isTrue, reason: '点整行 = 打开（不是只有那几个像素的开关才能点）');
    debugDefaultTargetPlatformOverride = null;
  });
}
