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

import 'package:flutter/foundation.dart';
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

  testWidgets('★ 正中那格**完全在栏内**：只有图标垫一颗强调圆，五格仍等宽',
      (WidgetTester tester) async {
    // 2026-10-08 第二遍（用户真机反馈）：「Tab 栏中间那个玻璃效果还是有问题，
    // 直接把 Tab 栏变宽一点，所有的内容都包进来吧，**不要让中间突出去一截了**，
    // 只在中间的图标做点文章就行」。
    // 所以判据也跟着反过来：正中那格的**整块**必须落在底栏的矩形内（不再有 top: -10）。
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

    final Rect bar = tester.getRect(find.byKey(const Key('tab-bar')));
    final Finder center = find.byKey(const Key('tab-训练'));
    expect(center, findsOneWidget, reason: '正中那格仍叫 tab-训练（key 与另外四格同一套）');

    // ① 整格都在栏内 —— 上沿不许高过底栏上沿（这条就是"不要突出去"）
    final Rect centerRect = tester.getRect(center);
    expect(centerRect.top, greaterThanOrEqualTo(bar.top - 0.01),
        reason: '正中那格不许顶出底栏上沿（上一版是 top: -10，用户要求收进来）');
    expect(centerRect.bottom, lessThanOrEqualTo(bar.bottom + 0.01));

    // ② 区别只做在**图标**上：一个**大一号的强调色图标**，而且它也在栏内。
    //
    // ⚠️ 2026-10-09（10.9 清单第 2b 条）：这里原来钉的是"一颗实心强调圆"——
    // 用户看完真机说"中间那个图标太割裂"（左右四个是线性图标，中间是实心圆 + 深色图标，
    // 两套视觉语言），所以圆整个去掉了。现在钉的是"同一种图标、只差大小与颜色"，
    // 而且**不许再出现圆形底**（下面那条 ancestor 断言就是干这个的）。
    final Finder centerIcon = find.byKey(const Key('tab-center-icon'));
    expect(centerIcon, findsOneWidget, reason: '正中那颗图标必须有（它仍是唯一的区别）');
    expect(tester.getSize(centerIcon).height, AppTabBar.centerIconSize);
    expect(AppTabBar.centerIconSize, greaterThan(AppTabBar.iconsize),
        reason: '只靠大小与颜色区分 —— 那就必须真的比别的格子大一号');
    expect(tester.getRect(centerIcon).top, greaterThanOrEqualTo(bar.top - 0.01),
        reason: '图标也要在栏内 —— 这才是"所有内容都包进来"');
    expect(
      find.descendant(
        of: find.byKey(const Key('tab-训练')),
        matching: find.byType(Container),
      ),
      findsNothing,
      reason: '正中那格不许再有"圆底"那种容器（10.9 清单第 2b 条：太割裂）',
    );
    // 文字照旧（底栏不许少一个词）
    expect(find.byKey(const Key('tab-center-label')), findsOneWidget);
    expect(find.text('训练'), findsOneWidget);

    // ③ 五格仍然等宽（留空/换画法都不许改变等分）
    final double slot = tester.getSize(find.byKey(const Key('tab-进步'))).width;
    for (final String label in <String>['数据', '计划', '我的']) {
      expect(tester.getSize(find.byKey(Key('tab-$label'))).width,
          moreOrLessEquals(slot, epsilon: 0.5));
    }
    expect(slot, moreOrLessEquals(bar.width / 5, epsilon: 0.5));

    // ④ 点它 = 切到正中那一格
    await tester.tap(center);
    await tester.pumpAndSettle();
    expect(tapped, 2, reason: '正中那颗就是「训练」（下标 2）');
  });

  test('★ 底栏高度：装得下正中那颗（大一号的）图标 + 文字（68pt，不再是 58）', () {
    // 高度是"内容包得住"这条要求的量化形式：图标 + 3（间隙）+ ~13（文字）+ 上下留白。
    // 2026-10-09 起正中是一颗 26pt 的图标（不再是 36pt 的圆），所以这条比以前宽松 ——
    // 但**高度不回退**：真机上 68 的手感是量过的，而且内容与栏沿之间要留呼吸。
    expect(AppTabBar.height, greaterThanOrEqualTo(64));
    expect(AppTabBar.centerIconSize, lessThanOrEqualTo(AppTabBar.height - 20));
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

  // ── 顶栏**不许**再包玻璃（v1.66.0 上线后被用户回退）────────────────────────
  //
  // 用户原话（2026-10-09 第二份 docx 第 5 条）：「看最上面 玻璃质感完全 bug了 回退吧」——
  // 真机上标题与页面内容互相叠影。这条组的作用就是**把它钉住**：
  // 顶栏两种平台都只是一个普通的 `Padding`，不许出现 `glass-top-bar`、
  // 也不许再有"给浮动顶栏让位"那种 API（`reservedSpaceFor` 已经删掉了 ——
  // 留着它，下次有人会以为顶栏还是浮的）。
  group('顶栏：回退到无玻璃、不浮动', () {
    testWidgets('iOS：顶栏没有玻璃、也不浮动（回归：用户回退过的那一条）',
        (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: AppTopBar(title: '今天')),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('glass-top-bar')), findsNothing,
          reason: '顶栏那块玻璃被用户回退了 —— 真机上会叠影');
      expect(find.byKey(const Key('app-top-bar')), findsOneWidget,
          reason: '顶栏本身当然还在（回退的是它的玻璃，不是它）');

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('非 iOS：同样没有玻璃（两端同一条判据：都没有）',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: AppTopBar(title: '今天')),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('glass-top-bar')), findsNothing);
      expect(find.byKey(const Key('app-top-bar')), findsOneWidget);
    });
  });
}
