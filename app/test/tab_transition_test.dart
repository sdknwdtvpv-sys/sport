/// 练了么 · **底栏切换的过渡**（VI 计划 T2-5，2026-10-10）
///
/// **为什么要有它**：`main.dart` 的 `_selectTab` 里曾经有一句
/// `if (!GlassSurface.isSupportedPlatform) return;` —— 位置在 `animateToPage` **之前**，
/// 于是 **Android 上点底栏是"瞬切"，iOS 上是 300ms 缓动滑动**。
/// 同一台产品，两台设备的 Tab 切换是两种手感，而规格书里从来没定义过 Tab 切换的动效。
///
/// 判据：
///   1. 两条平台都真的在**动**（动画中途 `PageController.page` 落在起点与终点之间，
///      而不是一步到位）—— 这就是"删掉那句早返回"的可跑证据；
///   2. **时长不随距离变**：`Motion.pageTransition`（300ms）是**一档**，
///      跨 1 格与跨 2 格在同一时刻的归一化进度相同
///      （T1-4 的裁决：原来那个 `260 + 90 × 距离` 的算式已经删了）；
///   3. `_selectTab` 里不许再出现平台判断（源码扫描，反向自检）。
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/motion.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/main.dart';

Future<void> _pumpShell(WidgetTester tester) async {
  // ⚠️ **必须先"同意过隐私政策"**：否则外壳先停在同意门那一屏，
  // `PageView` 根本不在树上（`_page()` 会直接抛）。
  final AppDatabase db = AppDatabase(NativeDatabase.memory());
  await ProfileRepository(db).setPrivacyConsent(nowMs: 1);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: HomeShell(
      database: db,
      seedLoader: () => File('assets/exercises.json').readAsString(),
    ),
  ));
  // 首帧 + 初始化（库、种子、偏好）—— 不用 pumpAndSettle：
  // 外壳里有常驻动画（玻璃/指示器），settle 会等不到静止。
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 当前 `PageView` 的页码（1 = 「开练」，0 = 「进步」，2 = 「我」）。
double _page(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!.page!.toDouble();

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  // ⚠️ 平台用 `variant` 指定，**不要**自己写 `debugDefaultTargetPlatformOverride`：
  // 测试框架会在用例结束时检查"foundation 的调试变量有没有被改过"，
  // 手动改而忘了在用例内复位，报的是 `The value of a foundation debug variable was changed by the test`。
  testWidgets('Android：点底栏真的在动（不再瞬切）', (WidgetTester tester) async {
    await _pumpShell(tester);
    expect(_page(tester), closeTo(1.0, 0.01), reason: '初始落在「开练」');

    await tester.tap(find.byKey(const Key('tab-我')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150)); // 300ms 的一半
    final double mid = _page(tester);
    expect(mid, greaterThan(1.0),
        reason: 'Android 上一按就到 2.0 就是"瞬切"—— 那句平台早返回又回来了');
    expect(mid, lessThan(2.0));

    await tester.pumpAndSettle();
    expect(_page(tester), closeTo(2.0, 0.01));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('iOS：同一段动画（两条平台的手感一致）', (WidgetTester tester) async {
    await _pumpShell(tester);

    // ⚠️ iOS 上底栏是**苹果原生 `UITabBar`**（一块平台视图），Flutter 侧没有 `tab-*` 那些 key,
    // `tester.tap` 也点不到它（合成事件进不了 UIKit）—— 所以走外壳交出来的那个入口
    // （语义一致：都是"用户点了那一格"，真机上的原生回调也走它）。
    debugSwitchTab?.call(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final double mid = _page(tester);
    expect(mid, lessThan(1.0));
    expect(mid, greaterThan(0.0));

    await tester.pumpAndSettle();
    expect(_page(tester), closeTo(0.0, 0.01));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('时长不随距离变：跨 1 格与跨 2 格在同一时刻的归一化进度相同',
      (WidgetTester tester) async {

    // ① 跨 1 格（1 → 2）
    await _pumpShell(tester);
    await tester.tap(find.byKey(const Key('tab-我')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final double oneStep = (_page(tester) - 1.0) / 1.0;
    await tester.pumpAndSettle();

    // ② 先回到 0，再跨 2 格（0 → 2）
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await _pumpShell(tester);
    await tester.tap(find.byKey(const Key('tab-进步')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab-我')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final double twoSteps = (_page(tester) - 0.0) / 2.0;

    // 150 / 300 = 0.5 在 `Motion.standard` 上的位置 —— 两段必须都落在它上面
    final double expected = Motion.standard.transform(0.5);
    expect(oneStep, closeTo(expected, 0.06), reason: '跨 1 格：$oneStep vs $expected');
    expect(twoSteps, closeTo(expected, 0.06), reason: '跨 2 格：$twoSteps vs $expected');
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  test('反向自检：`_selectTab` 里不许再有平台判断', () {
    final String src = File('lib/main.dart').readAsStringSync();
    final RegExpMatch? m =
        RegExp(r'void _selectTab\(int i\) \{([\s\S]*?)\n  \}').firstMatch(src);
    expect(m, isNotNull, reason: '找不到 `_selectTab` —— 改名了就把这条测试一起改');
    // **先去掉注释**：这一条的注释里正好引用了那句被禁掉的代码
    // （"注释里留着旧写法"是这个仓库的习惯，所以扫描器一律先剥注释）。
    final String body = m!
        .group(1)!
        .split('\n')
        .map((String l) {
          final int i = l.indexOf('//');
          return i < 0 ? l : l.substring(0, i);
        })
        .join('\n');
    expect(body.contains('isSupportedPlatform'), isFalse,
        reason: '**Android 瞬切的根因就是这一句**（它在 animateToPage 之前提前返回）');
    expect(body.contains('Motion.pageTransition'), isTrue,
        reason: '时长要走令牌（T1-4 的裁决：300ms 一档，不再按距离算）');
  });
}
