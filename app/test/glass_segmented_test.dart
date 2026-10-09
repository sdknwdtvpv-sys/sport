/// 练了么 · iOS 液态玻璃的第二件事：**底托 + 选中胶囊"溶"在一起**（`GlassSegmented`）
///
/// 与 `glass_surface_test.dart` 守同一条分界线（**iOS 才走原生，其它平台原样放行**），
/// 但它多守一条**几何契约**，而这条契约断了是静默的：
///
/// > 「融合」由原生在 `UIGlassContainerEffect` 里做，格子是按 `frame.width / count` 切的
/// > （`GlassBridge.swift` 的 `pillFrame`）—— **条目必须等宽**。
///
/// Dart 这边要是哪天又改回"按内容收缩"，原生那一侧不会报错，只会让选中的胶囊
/// 和它上面那几个字**慢慢错开**（越靠右偏得越多）。所以这里把"每格一样宽"钉住。
///
/// ⚠️ `debugDefaultTargetPlatformOverride` 必须在**每个用例体里**改回 null（原因见
/// `glass_surface_test.dart` 顶部）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/app_tab_bar.dart';
import 'package:lianleme/core/glass_segmented.dart';
import 'package:lianleme/core/glass_surface.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/core/vi_cards.dart';

Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: Center(child: child)),
  ));
}

void main() {
  testWidgets('★ 非 iOS：一个平台视图都不建（Android 仍然按内容收缩的实心胶囊）',
      (WidgetTester tester) async {
    for (final TargetPlatform p in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.macOS,
    ]) {
      debugDefaultTargetPlatformOverride = p;
      int picked = -1;
      await pump(
        tester,
        ViSegmented(
          labels: const <String>['周', '月', '年'],
          current: 0,
          onChanged: (int i) => picked = i,
        ),
      );
      expect(find.byType(UiKitView), findsNothing, reason: '$p 上不该有平台视图');
      await tester.tap(find.byKey(const Key('seg-月')));
      expect(picked, 1, reason: '$p 上的点击行为不能变');
      // 老样子：选中项是"实心 accent 胶囊 + 深墨字"
      final Text first = tester.widget<Text>(find.text('周'));
      expect(first.style!.color, Tokens.accentInk);
    }
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('★ iOS：走原生容器视图，创建参数逐项对（原生按这些名字取值）',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pump(
      tester,
      ViSegmented(
        labels: const <String>['周', '月', '年'],
        current: 1,
        onChanged: (int _) {},
      ),
    );

    final UiKitView view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(view.viewType, 'lianleme/glass_segmented',
        reason: '与 GlassBridge.swift 里的 viewType 必须逐字一致');
    final Map<Object?, Object?> args = view.creationParams! as Map<Object?, Object?>;
    expect(args['count'], 3);
    expect(args['index'], 1);
    expect(args['style'], 'regular');
    expect(args['radius'], 16, reason: '高度 32 的胶囊 → 圆角是它的一半');
    // 选中胶囊：往里缩 5pt（这就是"凸起那块"与底托之间的缝）+ 一点白
    expect(args['pillInset'], 5);
    // 默认**不染色 = 全透明**（用户 2026-10-06："能不能做成全透明的"）：
    // 一个键都不带，原生那边就一点都不染
    expect(args.containsKey('pillTint'), isFalse,
        reason: '没给就是不染 —— 别传 null 让原生去猜');
    // ⚠️ 胶囊默认 `.clear`：两块 `.regular` 叠着是双重磨砂 → 鼓起来那颗会变成奶白疙瘩
    // （真机原话"通透度太差了 完全不是透明的"）
    expect(args['pillStyle'], 'clear');
    expect(args['style'], 'regular', reason: '底托仍然是磨砂的 regular');
    // 按下去鼓 14pt：太小就没有那个"Q弹"的幅度（真机原话"太小了 要超出边界"）
    expect(args['pressBulge'], 14);
    // ② 的重影 bug：字**由原生画**（`labels` 发过去），Flutter 那份不画 ——
    // 否则玻璃会把背后的字折射出第二份（用户备忘条第 2 条）
    expect(args['labels'], <String>['周', '月', '年'],
        reason: '分段控件的字也要交给原生画（否则玻璃会把它折射出第二份）');
    expect(args['selectedColor'], isNotNull);
    expect(args['unselectedColor'], isNotNull);
    expect(args['labelFontSize'], 12);
    // ⚠️ 不许再有"融合距离"这个参数：容器会把两块玻璃抹平成一块
    // （真机上就是"切 tab 完全感觉不到玻璃"，证据 glass-probe-segment-variants.png）
    expect(args.containsKey('spacing'), isFalse);
    // 标签仍然是 Flutter 画的（在玻璃上面），原生只负责那两块玻璃
    expect(find.text('月'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('★ iOS：条目**等宽**（原生按 width/count 切格子，不等宽就会越往右越偏）',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pump(
      tester,
      ViSegmented(
        labels: const <String>['周', '月', '年'],
        current: 0,
        onChanged: (int _) {},
      ),
    );

    final List<double> widths = <double>[
      for (final String l in <String>['周', '月', '年'])
        tester.getSize(find.byKey(Key('seg-$l'))).width,
    ];
    expect(widths, <double>[56, 56, 56], reason: '每格都要是 itemWidth，一个字和三个字一样');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS：玻璃上面那层照样收点击（整格都是热区，不是只有字那几像素）',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    int picked = -1;
    await pump(
      tester,
      ViSegmented(
        labels: const <String>['周', '月', '年'],
        current: 0,
        onChanged: (int i) => picked = i,
      ),
    );
    await tester.tap(find.byKey(const Key('seg-年')));
    expect(picked, 2);
    // 选中项在玻璃上：字色用最亮的那个（深墨压在浅玻璃上会糊）；
    // 没选中的是次要色
    expect(tester.widget<Text>(find.text('周')).style!.color, Tokens.text);
    expect(tester.widget<Text>(find.text('年')).style!.color, Tokens.text2);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('★ 通用的一行多选（单位那种）：非 iOS 原样、iOS 等宽进玻璃',
      (WidgetTester tester) async {
    final List<bool> seen = <bool>[];

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pump(
      tester,
      GlassSegmentedRow(
        count: 3,
        index: 1,
        itemBuilder: (int i, bool glass) {
          seen.add(glass);
          return Text('格$i', textDirection: TextDirection.ltr);
        },
      ),
    );
    expect(seen, <bool>[false, false, false], reason: '非 iOS 不许进玻璃');
    expect(find.byType(UiKitView), findsNothing);

    seen.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pump(
      tester,
      GlassSegmentedRow(
        count: 3,
        index: 1,
        itemBuilder: (int i, bool glass) {
          seen.add(glass);
          return Text('格$i', textDirection: TextDirection.ltr);
        },
      ),
    );
    expect(seen, <bool>[true, true, true], reason: 'iOS 每一格都在等宽格子里');
    for (int i = 0; i < 3; i++) {
      expect(tester.getSize(find.text('格$i')).height, lessThanOrEqualTo(32),
          reason: '格子是定高的，内容不许把它撑开');
    }
    final UiKitView view = tester.widget<UiKitView>(find.byType(UiKitView));
    final Map<Object?, Object?> args = view.creationParams! as Map<Object?, Object?>;
    expect(args['count'], 3);
    expect(args['index'], 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('★ 底栏：iOS 走"底托 + 独立选中胶囊"，五格就是 count=5、圆角=高度的一半',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // 手指拖页面时喂进来的"小数页号"（外壳的 PageController 持有它）
    final ValueNotifier<double> drag = ValueNotifier<double>(-1);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppTabBar(current: 2, onChanged: (int _) {}, dragIndex: drag),
      ),
    ));

    final GlassSegmented seg =
        tester.widget<GlassSegmented>(find.byType(GlassSegmented));
    expect(seg.count, AppTabBar.tabs.length);
    expect(seg.count, 5);
    expect(seg.index, 2);
    expect(seg.radius, AppTabBar.height / 2, reason: '胶囊 = 高度的一半');
    expect(seg.style, GlassStyle.regular);
    expect(seg.pillInset, 5, reason: '底栏的选中胶囊也要缩进去一点才看得出是凸的一块');
    expect(seg.pillTint, isNull, reason: '底栏那颗默认全透明（靠着图标颜色与边缘高光读形状）');
    expect(seg.pillStyle, GlassStyle.clear, reason: '鼓起来那颗必须透得过去');
    expect(seg.pressBulge, 14, reason: '按下去的幅度 —— 小了就没有 Q 弹的手感');
    // ★ 底栏的字与图标必须**交给原生画**（否则会在玻璃上出现折射重影），
    // 且图标是 SF Symbol 那一组
    expect(seg.labels, isNotNull);
    expect(seg.labels!.length, 5);
    expect(seg.icons, isNotNull);
    expect(seg.icons!.length, 5);
    // ⚠️ 2026-10-07（v1.60.0）：图标顺序跟着 tab 顺序变了（「训练」挪到正中）。
    // ⚠️ **2026-10-08（v1.61.0）又改了正中那一格的画法**：v1.60.0 我把它交给
    // Flutter 画（传空串），结果那颗圆落在**玻璃背后**、被折射成一层发灰的虚影 ——
    // 用户 10.8 清单第 1 条「tab 栏的训练 玻璃效果 bug」说的就是它。
    // 现在正中也交给原生画（`emphasisIndex`），圆与另外四格的字在**同一层**（玻璃之上）。
    expect(seg.icons, contains('chart.line.uptrend.xyaxis'));
    expect(seg.icons![2], 'dumbbell.fill', reason: '正中那格也要原生画图标');
    expect(seg.labels![2], '训练', reason: '正中那格也要原生画文字（否则底栏少一个词）');
    expect(seg.emphasisIndex, 2, reason: '正中被点亮的那一格 = 训练（下标 2）');
    // ⚠️ 2026-10-09（10.9 清单第 2b 条）：**不再传 `emphasisColor`** ——
    // 传了原生会插一颗实心圆，而那正是用户说"太割裂"的东西。
    // 现在正中只靠"大一号 + 强调色"，两个数都要真的传下去。
    expect(seg.emphasisColor, isNull, reason: '不许再画实心圆');
    expect(seg.emphasisIconSize, AppTabBar.centerIconSize,
        reason: '正中那颗要更大一号 —— 这是去掉圆之后仅剩的区分手段');
    expect(seg.emphasisIconColor, isNotNull, reason: '一点强调色：正中那颗永远用强调色');
    // 拖动信号必须**一路传到玻璃组件**（外壳 → AppTabBar → GlassSegmented）：
    // 断了的话页面照样能拖，但底下那颗玻璃会跳格 —— 看起来就是"不跟手"。
    expect(seg.dragIndex, same(drag), reason: '那条"跟手"的线就靠它');
    // 五个格子仍然各是各的热区（原生的胶囊只是"画"在下面）
    for (final String label in <String>['训练', '进步', '数据', '计划', '我的']) {
      expect(find.byKey(Key('tab-$label')), findsOneWidget);
    }
    // ⚠️ 尺寸也要有：玻璃那层外面是个 Stack，而 Stack 的尺寸靠**非定位子项**决定 ——
    // 若哪天把内容也包成 `Positioned.fill`，Stack 会算不出自己的大小（真机上直接抛断言，
    // 而"能找到 key"的断言照样全绿）。这条是 2026-10-06 真机 integration test 抓到的。
    final Size bar = tester.getSize(find.byKey(const Key('glass-tab-bar')));
    expect(bar.height, AppTabBar.height);
    expect(bar.width, greaterThan(0));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('★ iOS：按住横向拖到别格再松手 = 换 tab；原地点击不算拖动',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final List<int> dragged = <int>[];
    await pump(
      tester,
      GlassSegmented(
        count: 3,
        index: 0,
        radius: 16,
        onDragSelect: dragged.add,
        child: const SizedBox(width: 168, height: 32),
      ),
    );

    // ⚠️ 坐标要**相对这个组件**：`_host` 把它居中，直接用 (10,10) 会落在组件外面
    final Offset origin = tester.getTopLeft(find.byType(GlassSegmented));

    // 原地按一下再松手：**不是**拖动（普通点击走上面那层 Flutter 自己的 tap）
    TestGesture g = await tester.startGesture(origin + const Offset(10, 10));
    await g.up();
    expect(dragged, isEmpty, reason: '同一格上按下松手 = 点击，不该走拖动那条路');

    // 从第 0 格拖到第 2 格再松手 → 回调 2
    g = await tester.startGesture(origin + const Offset(10, 10));
    await g.moveTo(origin + const Offset(150, 10));
    await g.up();
    expect(dragged, <int>[2]);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('★ 底栏：非 iOS 不许出现玻璃、也不许浮动（Android 一个像素都不动）',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AppTabBar(current: 0, onChanged: (int _) {})),
    ));

    expect(find.byType(GlassSegmented), findsNothing);
    expect(find.byType(UiKitView), findsNothing);
    // 贴着内容的那条底栏仍然留着 1px 顶边线（iOS 那支靠玻璃自己的边缘高光分隔）
    final Container bar =
        tester.widget<Container>(find.byKey(const Key('tab-bar')));
    final BoxDecoration d = bar.decoration! as BoxDecoration;
    expect(d.border, isNotNull);
    expect(AppTabBar.reservedSpaceFor(tester.element(find.byType(AppTabBar))), 0,
        reason: '不浮动就不用给内容留位置');
    debugDefaultTargetPlatformOverride = null;
  });
}
