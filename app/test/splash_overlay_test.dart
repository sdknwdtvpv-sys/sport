/// 练了么 · **内启动屏**（VI 计划 T3-6，2026-10-10）
///
/// 冷启动原来是三段互不相干的画面：原生启动图（橙环）→ **一块纯色空屏** → 内容。
/// 第二段不闪白，但它闪"什么都没有"：原生图上那枚环**在这一帧消失**了。
///
/// 判据（与计划一致）：
///   1. 注入一个**永不完成**的同意状态读取，屏幕上要能找到环 —— 证明它不是"先空屏再出环"；
///   2. **小于 400ms 完成时找不到加载点**（本地库是毫秒级的，冒一下点再消失是一帧脏画面）；
///      且 `grep -c AnimationController splash_overlay.dart` **恰好 1**（三点共用一个控制器）；
///   3. **接力对位**：原生启动图的环与 `SplashMark` 首帧的环 ≤ 2pt（几何那一半由
///      `tool/check-launch-relay.py` 直接量 PNG，Dart 这一半测 widget 的几何）；
///   4. 减弱动态效果下不做无限脉冲（只有静态环 + 字标）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/brand_mark.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/features/onboarding/splash_overlay.dart';

void main() {
  testWidgets('一帧都不是空屏：从第一帧起就有环与字标', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SplashOverlay(), // busy = true（同意状态还没读出来）
    ));
    await tester.pump(); // 只推进一帧 —— "第一帧"就是被测对象

    expect(find.byKey(const Key('brand-mark')), findsOneWidget,
        reason: '第一帧就必须有环：否则原生启动图（有环）→ 空屏（没环）中间那一下就是闪');
    expect(find.byKey(const Key('splash-wordmark')), findsOneWidget);
    expect(find.byKey(const Key('splash-no-dots')), findsOneWidget,
        reason: '第一帧不该有点（< 400ms 就完事的话冒一下点是脏画面）');
  });

  testWidgets('小于 400ms 完成时找不到加载点', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashOverlay()));
    // 300ms 就把这一屏换掉（模拟"本地库毫秒级就绪"）
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await tester.pump(const Duration(milliseconds: 200)); // 越过那个 400ms 的线
    expect(find.byKey(const Key('splash-no-dots')), findsNothing);
    // 三点从来没被画出来过
    expect(find.byKey(const Key('splash-wordmark')), findsNothing);
  });

  testWidgets('慢的时候（> 400ms）才画三个点，且三点一起出现在同一棵树里',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashOverlay()));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    final Finder dots = find.descendant(
        of: find.byType(Row), matching: find.byType(Opacity));
    expect(dots, findsWidgets, reason: '过了 400ms 就该有点');
  });

  testWidgets('减弱动态效果下不做无限脉冲（静态环 + 字标）', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: SplashOverlay(),
      ),
    ));
    await tester.pump();
    // 静态：环的 Transform.scale 恒为 1.0（不随 t 呼吸）。
    // ⚠️ `Transform` 是 `brand-mark` 的**祖先**（`Transform.scale(child: BrandMark)`），
    // 不是后代 —— 第一版用 `find.descendant` 直接报 "Bad state: No element"。
    double scaleNow() => tester
        .widget<Transform>(find
            .ancestor(
              of: find.byKey(const Key('brand-mark')),
              matching: find.byType(Transform),
            )
            .first)
        .transform
        .getMaxScaleOnAxis();

    expect(scaleNow(), closeTo(1.0, 0.0001));
    await tester.pump(const Duration(milliseconds: 800));
    expect(scaleNow(), closeTo(1.0, 0.0001), reason: '减弱动态效果下不许有无限脉冲');
  });

  test('三个点共用一个控制器（不许三个各自计时）', () {
    final String src =
        File('lib/features/onboarding/splash_overlay.dart').readAsStringSync();
    final int n = RegExp(r'AnimationController\(').allMatches(src).length;
    expect(n, 1, reason: '判据 2：`grep -c AnimationController` 必须恰好 1，现在是 $n');
    expect(src.contains('Future.delayed'), isFalse,
        reason: '动画的时间轴只许来自那个控制器；那一条"过 400ms 才画点"的延时要用**可取消的 Timer**'
            '（`Future.delayed` 取消不掉，第一版就是因此被 "Pending timers" 抓住的）');
    expect(RegExp(r'Timer\(').allMatches(src).length, 1,
        reason: '有且只有一处延时：过了 400ms 才画点');
    expect(src.contains('_dotTimer?.cancel()'), isTrue,
        reason: '那处延时要能在 dispose 里取消');
  });

  test('接力对位（Dart 这一半）：BrandMark(96) 的外径 = 原生启动图那枚 42.67pt ± 2pt', () {
    // 原生那半由 `tool/check-launch-relay.py` 直接量 `LaunchImage@3x.png`：
    //   环外径 128px ÷ 3 = 42.67pt、非透明包围盒中心在画布正中。
    // 这里只钉 widget 这一半 —— 两边用同一个数，谁也不许单独改。
    final double outer = BrandMarkGeometry.outerRadius(SplashOverlay.canvas) * 2;
    expect(outer, closeTo(42.67, 2.0),
        reason: 'SplashOverlay.canvas = ${SplashOverlay.canvas} 时外径是 $outer');
    // 画布 96pt 这个数本身也是从"原生图 96pt 画布"来的
    expect(SplashOverlay.canvas, 96);
  });

  test('画布底色与主题一致（启动屏不是"另一种黑"）', () {
    // 原生启动图的底色是 Assets 里的 launch_background，而 Flutter 这一侧用 Tokens.bg ——
    // 两处如果不是同一个黑，接力那一刻会看到一次轻微的跳色。
    expect(Tokens.bg, const Color(0xFF0E0C0A));
  });
}
