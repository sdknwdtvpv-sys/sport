/// v3.0.0 盲审 must-fix 回归（task-22）
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/features/today/today_screen.dart';

void main() {
  test('★ 总结页不再有 success 彩色发光盘（must-fix 2）', () {
    final String src = File('lib/features/summary/workout_summary_screen.dart').readAsStringSync();
    expect(src.contains('glow(Tokens.success'), isFalse,
        reason: '锁定项：不做彩色氛围光；success 只留小勾');
    expect(src.contains("'训练完成'"), isTrue);
  });

  test('★ 设置只从「我」进：主 Tab 顶栏不再按旧 _tab==2 显示齿轮', () {
    final String src = File('lib/main.dart').readAsStringSync();
    expect(src.contains('showSettings: _tab == 2'), isFalse);
    expect(src.contains('showSettings: false'), isTrue);
  });

  testWidgets('★ 今天：时间用「未定时间」，卡与按钮左缘对齐（must-fix 3）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TodayScreen(onStart: () {})),
    ));
    await tester.pumpAndSettle();

    expect(find.text('未定时间'), findsOneWidget,
        reason: '不能用渲染时钟冒充日程时间');
    final Rect card = tester.getRect(find.byKey(const Key('today-plan')));
    final Rect button = tester.getRect(find.byKey(const Key('start-workout')));
    expect(card.left, closeTo(button.left, 0.5));
    expect(card.right, closeTo(button.right, 0.5));
  });
}
