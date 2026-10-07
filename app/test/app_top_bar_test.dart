/// 练了么 · **外壳顶栏**与**底栏正中那颗**（2026-10-07，v1.60.0）
///
/// 两条用户原话各自的判据：
///   * 「小铃铛放在右上角，**注意下布局协调性**」+「所有的设置相关的能不能集成到右上角，
///     一个小齿轮图标」→ 顶栏（`AppTopBar`，见 `widget_test.dart` 那条端到端）；
///   * 「下面导航栏五个，**训练放在最中间**，并且最好跟其他四个**做区别展示**」→ 底栏。
///
/// 这个文件钉的是**几何与顺序**（"看起来对不对"这件事只有尺寸与下标能验）：
/// 正中那颗必须真的**顶出底栏上沿**，五个格必须仍然等宽，tab 顺序必须与
/// `main.dart` 的 `_bodyFor` 对得上 —— 错一条就是"点训练进了数据"。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/app_tab_bar.dart';
import 'package:lianleme/core/app_top_bar.dart';
import 'package:lianleme/core/theme.dart';

void main() {
  test('★ tab 顺序：训练在**正中**（下标 2），其余四个各就各位',
      () {
    expect(AppTabBar.tabs.map((({IconData icon, String label}) t) => t.label),
        <String>['进步', '数据', '训练', '计划', '我的']);
  });

  testWidgets('★ 正中那颗**凸出底栏上沿**，而且五格仍然等宽', (WidgetTester tester) async {
    int tapped = -1;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: AppTabBar(current: 2, onChanged: (int i) => tapped = i),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final double barTop = tester.getTopLeft(find.byKey(const Key('tab-bar'))).dy;
    final Finder center = find.byKey(const Key('tab-训练'));
    expect(center, findsOneWidget, reason: '正中那格仍然叫 tab-训练（key 与另外四格同一套）');

    // 凸出：它的上沿必须**高于**底栏的上沿（这就是"做区别展示"的形状）
    expect(tester.getTopLeft(center).dy, lessThan(barTop),
        reason: '正中那颗要顶出底栏上沿；平齐的话它看起来只是第二个格子');

    // 五格仍然等宽：四枚普通格子的宽度一致，且都约为底栏宽度的 1/5
    final double barWidth = tester.getSize(find.byKey(const Key('tab-bar'))).width;
    final double slot = tester.getSize(find.byKey(const Key('tab-进步'))).width;
    for (final String label in <String>['数据', '计划', '我的']) {
      expect(tester.getSize(find.byKey(Key('tab-$label'))).width,
          moreOrLessEquals(slot, epsilon: 0.5));
    }
    expect(slot, moreOrLessEquals(barWidth / 5, epsilon: 0.5),
        reason: '留空正中那一格就是为了让五格等宽 —— 少一格会让右边两格整体左移');

    // 点它 = 切到正中那一格
    await tester.tap(center);
    await tester.pumpAndSettle();
    expect(tapped, 2, reason: '正中那颗就是「训练」（下标 2）');
  });

  testWidgets('顶栏：标题 + 副标题 + 两枚 40×40 的动作（同一基线）',
      (WidgetTester tester) async {
    bool settings = false;
    bool notifications = false;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: AppTopBar(
          title: '今天',
          subtitle: '10 月 7 日 · 周三',
          unread: 0,
          onOpenSettings: () => settings = true,
          onOpenNotifications: () => notifications = true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('今天'), findsOneWidget);
    expect(find.byKey(const Key('top-bar-subtitle')), findsOneWidget);
    // **没有未读就一个点都不许有**（永远亮着的点等于没有点）
    expect(find.byKey(const Key('notifications-unread-dot')), findsNothing);

    // 两枚动作同规格、垂直居中对齐 —— "布局协调性"就是这两条
    final Size gear = tester.getSize(find.byKey(const Key('top-bar-settings')));
    final Size bell = tester.getSize(find.byKey(const Key('open-notifications')));
    expect(gear, const Size(AppTopBar.actionSize, AppTopBar.actionSize));
    expect(bell, gear, reason: '两枚动作必须同规格');
    expect(tester.getCenter(find.byKey(const Key('top-bar-settings'))).dy,
        moreOrLessEquals(tester.getCenter(find.byKey(const Key('open-notifications'))).dy,
            epsilon: 0.5),
        reason: '同一基线 —— 这是原来那版"标题 34pt + 日期 13pt + 40×40 触区"最难看的地方');

    // 都在标题**右边**（"放在右上角"）
    expect(tester.getCenter(find.byKey(const Key('top-bar-settings'))).dx,
        greaterThan(tester.getCenter(find.byKey(const Key('top-bar-title'))).dx));

    await tester.tap(find.byKey(const Key('top-bar-settings')));
    await tester.tap(find.byKey(const Key('open-notifications')));
    expect(settings, isTrue);
    expect(notifications, isTrue);
  });

  testWidgets('顶栏：有未读才有那个点', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: AppTopBar(
          title: '今天',
          unread: 3,
          onOpenNotifications: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notifications-unread-dot')), findsOneWidget);
    // 没给 onOpenSettings 时齿轮**不出现**（测试与"不接设置的调用点"保持干净）
    expect(find.byKey(const Key('top-bar-settings')), findsNothing);
  });
}
