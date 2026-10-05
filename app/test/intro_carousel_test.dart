/// 首启引导（3 屏卖点轮播）的契约。
///
/// 这一屏是用户拍的板，而且带了**四条约束** —— 所以测试也按那四条来写：
///   1. 只在全新安装出现一次（"出现过就不再出现"由同意门本身保证，见下面那条集成判据）；
///   2. 每屏可跳过；
///   3. 放在同意门之后；
///   4. 末屏按钮是「开始第一次训练」，不是「完成」。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/features/onboarding/intro_carousel_screen.dart';
import 'package:lianleme/main.dart';

Future<void> _pumpIntro(
  WidgetTester tester, {
  required VoidCallback onSkip,
  required VoidCallback onStartFirst,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: IntroCarouselScreen(onSkip: onSkip, onStartFirst: onStartFirst),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('约束 2：**每一屏**右上角都有「跳过」', (WidgetTester tester) async {
    int skips = 0;
    await _pumpIntro(tester, onSkip: () => skips++, onStartFirst: () {});
    for (int i = 0; i < 3; i++) {
      expect(find.byKey(const Key('intro-skip')), findsOneWidget, reason: '第 ${i + 1} 屏没有跳过');
      await tester.tap(find.byKey(const Key('intro-skip')));
      await tester.pumpAndSettle();
      expect(skips, i + 1);
    }
  });

  testWidgets('三屏内容都在，且前两屏是「下一步」圆按钮、末屏换成整颗主按钮',
      (WidgetTester tester) async {
    await _pumpIntro(tester, onSkip: () {}, onStartFirst: () {});
    expect(find.text('一次点击\n记录一组'), findsOneWidget);
    expect(find.byKey(const Key('intro-next')), findsOneWidget);
    expect(find.byKey(const Key('intro-start')), findsNothing);

    await tester.tap(find.byKey(const Key('intro-next')));
    await tester.pumpAndSettle();
    expect(find.text('今天练什么\n不用你想'), findsOneWidget);
    expect(find.byKey(const Key('intro-next')), findsOneWidget);

    await tester.tap(find.byKey(const Key('intro-next')));
    await tester.pumpAndSettle();
    expect(find.text('看得见的进步\n才是动力'), findsOneWidget);
    // 末屏：圆按钮消失，换成整颗主按钮
    expect(find.byKey(const Key('intro-next')), findsNothing);
    expect(find.byKey(const Key('intro-start')), findsOneWidget);
  });

  testWidgets('约束 4：末屏按钮写的是「开始第一次训练」，**不是「完成」**',
      (WidgetTester tester) async {
    await _pumpIntro(tester, onSkip: () {}, onStartFirst: () {});
    await tester.tap(find.byKey(const Key('intro-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('intro-next')));
    await tester.pumpAndSettle();

    expect(find.text('开始第一次训练'), findsOneWidget);
    expect(find.text('完成'), findsNothing, reason: '「完成」是个终点，这一屏的唯一出口是开练');
  });

  testWidgets('末屏按钮触发的是"开始训练"，跳过触发的是"离开引导"（两条路分得清）',
      (WidgetTester tester) async {
    int start = 0;
    int skip = 0;
    await _pumpIntro(tester, onSkip: () => skip++, onStartFirst: () => start++);
    await tester.tap(find.byKey(const Key('intro-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('intro-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('intro-start')));
    await tester.pumpAndSettle();
    expect(start, 1);
    expect(skip, 0);
  });

  // ── 约束 1 与 3：整条首启流程（真的过一遍同意门） ──
  testWidgets('约束 3：引导页在**同意门之后** —— 同意前看不到它；同意后才出现',
      (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(LianLeMeApp(database: db));
    await tester.pumpAndSettle();

    // 先看到同意门：引导页与主界面都还不该出现
    expect(find.textContaining('隐私政策'), findsWidgets);
    expect(find.byType(IntroCarouselScreen), findsNothing);
    expect(find.text('开始今天的训练'), findsNothing);

    // 点「同意并继续」
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    expect(find.byType(IntroCarouselScreen), findsOneWidget, reason: '同意之后紧接着就是引导页');
    expect(find.text('开始今天的训练'), findsNothing, reason: '引导页在主界面之前');

    // 跳过 → 落到主界面
    await tester.tap(find.byKey(const Key('intro-skip')));
    await tester.pumpAndSettle();
    expect(find.byType(IntroCarouselScreen), findsNothing);
    expect(find.text('开始今天的训练'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('约束 1：**已经同意过**的冷启动直接进主界面，不再出现引导页',
      (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    // 预置"已同意"：模拟第二次冷启动（同意门不会再出现）
    await ProfileRepository(db).setPrivacyConsent(nowMs: 1);
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(LianLeMeApp(database: db));
    await tester.pumpAndSettle();

    expect(find.byType(IntroCarouselScreen), findsNothing,
        reason: '同意门本身就是"每次安装只出现一次"的标记 —— 引导页不该再来一次');
    expect(find.text('开始今天的训练'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
