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

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/app_tab_bar.dart';
import 'package:lianleme/core/glass_segmented.dart';
import 'package:lianleme/core/native_hex.dart';
import 'package:lianleme/core/native_segmented.dart';
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

  testWidgets('★ iOS：走**苹果原生的 UISegmentedControl**（2026-10-09 起，不再自己画玻璃）',
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

    // 用户看完底栏换成真 UITabBar 之后问：「其他的切换选项能不能也做成这个效果呢，
    // 比如说像周 月 年的那个调整」—— 这一条就是那时换的。
    // 判据与底栏那条同源：**不许再有自己画的玻璃**，平台视图的参数要对得上
    // （原生按这些名字取值，写错了界面上就是一条空白、而且不报错）。
    expect(find.byKey(const Key('native-segmented')), findsOneWidget);
    final UiKitView view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(view.viewType, 'lianleme/native_segmented',
        reason: '与 NativeSegmentedBridge.swift 里的 viewType 必须逐字一致');
    final Map<Object?, Object?> args = view.creationParams! as Map<Object?, Object?>;
    expect(args['labels'], <String>['周', '月', '年']);
    expect(args['selectedIndex'], 1);
    expect(args['fontSize'], 12);
    // 颜色走 `#RRGGBB`（原生按这个解析）。
    // 2026-10-10 用户拍板：「**橙色**」—— 所以选中胶囊的底是 accent，
    // 而**橙底上的字必须是 accentInk**（橙底 + 白字只有 3.08:1，小字不合规）。
    // 用 `hexOfColor(Tokens.*)` 而不是写死的 `#FF5C26`：钉住的是"传的就是这两颗令牌"，
    // 令牌改名/改色时这条跟着走（写死字符串的话改色要手工同步，而它是会悄悄漂移的那种）。
    expect(args['selectedTint'], hexOfColor(Tokens.accent), reason: '选中胶囊 = 强调色');
    expect(args['selectedColor'], hexOfColor(Tokens.accentInk),
        reason: '橙底上的字用 accentInk —— 不许是近白的 Tokens.text');
    expect(args['selectedColor'], isNot(hexOfColor(Tokens.text)),
        reason: '橙底 + 近白字 = 3.08:1，不合规');
    expect((args['unselectedColor']! as String).startsWith('#'), isTrue);
    // ⚠️ 宽度由 Dart 定（`itemWidth × 段数`）：原生关了"按内容撑开"，
    // 否则同一行里的别的元素会跟着跳
    expect(tester.getSize(find.byKey(const Key('native-segmented'))).width, 56 * 3);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('★ iOS：宽度是 itemWidth × 段数（等宽由我们定，原生不许按内容撑开）',
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

    // ⚠️ 原来这条量的是三格各自的宽度（`seg-周/月/年` 那三个 key）。
    // 换成原生 `UISegmentedControl` 之后**格子在 UIKit 里**，Flutter 这边没有它们的 key ——
    // 能钉的是"我们给了它多宽"，以及"原生那一侧关了按内容撑开"
    // （`apportionsSegmentWidthsByContent = false`，见 Swift 那份注释）。
    final Size size = tester.getSize(find.byKey(const Key('native-segmented')));
    expect(size.width, 56 * 3, reason: '每格 itemWidth，一个字和三个字一样宽');
    expect(size.height, 32);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('★ iOS：触摸归**原生**（Flutter 不再拦点击，也不再自己画字）',
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

    // ⚠️ 这条**反过来钉**了旧行为：以前 iOS 上那块玻璃是"触摸穿透"的，
    // 所以 Flutter 得在上面盖透明热区、字也得由 Flutter 画（玻璃会折射第二份）。
    // 现在换成真控件：它自己接触摸（`EagerGestureRecognizer`），
    // 字由 UIKit 画 —— **Flutter 这边一个 `Text` 都不该有**。
    expect(find.text('周'), findsNothing,
        reason: '字交给 UIKit 画（否则会与系统控件里的字叠成两份）');
    expect(find.byKey(const Key('seg-周')), findsNothing,
        reason: 'Flutter 侧不再有热区（点击由原生控件收）');
    // 平台视图的识别器必须是**认领手势**的那一种，否则系统控件一个点击都收不到
    final UiKitView view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(view.gestureRecognizers, isNotNull);
    expect(view.gestureRecognizers!.length, 1);
    // `gestureRecognizers` 装的是 **Factory**（不是识别器本身）——
    // 造一个出来看类型，这才是原生真正会拿到的那个
    // ⚠️ `Factory` 是一个**类**（`foundation/basic_types.dart`），不是函数类型 ——
    // 要造识别器得读它的 `.constructor` 字段（写成 `first()` 会被解析成"调用 first"）。
    final Object rec = view.gestureRecognizers!.first.constructor();
    expect(rec.runtimeType.toString(), contains('EagerGestureRecognizer'));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('★ iOS：段数/文字变了必须整块重建（只挪选中位会留下上一套标签）',
      (WidgetTester tester) async {
    // 这条守的是「身体数据」页 TrendMetric 那条真事：撤销授权后可选指标
    // 从 4 个变 3 个 —— 段数变了，而选中位可能还是 0。
    //
    // ⚠️ 决策本身是纯函数（`nativeSegmentedUpdate`）。为什么不在 widget 里点：
    // `_channel` 要等原生 `onPlatformViewCreated` 才建起来，widget 测试没有原生
    // 那一侧，`invokeMethod` 会被静默丢掉 —— 那样这条测试永远绿，等于没写。
    expect(
      nativeSegmentedUpdate(
        oldLabels: const <String>['体重', '体脂率', '腰围', '骨骼肌'],
        oldIndex: 0,
        newLabels: const <String>['体重', '体脂率', '骨骼肌'],
        newIndex: 0,
      ),
      'setSpec',
      reason: '段数变了：`setSelected` 改不了标题',
    );
    expect(
      nativeSegmentedUpdate(
        oldLabels: const <String>['周', '月', '年'],
        oldIndex: 0,
        newLabels: const <String>['周', '月', '年'],
        newIndex: 2,
      ),
      'setSelected',
      reason: '段没变，只是选中位变了',
    );
    expect(
      nativeSegmentedUpdate(
        oldLabels: const <String>['周', '月', '年'],
        oldIndex: 1,
        newLabels: const <String>['周', '月', '年'],
        newIndex: 1,
      ),
      isNull,
      reason: '什么都没变就别打扰原生（每次 rebuild 都发一遍会打断选中动画）',
    );
    // 逐字比，顺序也算 —— 原生的格是按顺序插的
    expect(sameLabels(const <String>['周', '月'], const <String>['月', '周']), isFalse);
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

  testWidgets('★ 底栏：iOS 走**苹果原生的 UITabBar**（2026-10-09 起，不再自己画玻璃）',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppTabBar(current: 2, onChanged: (int _) {}),
      ),
    ));

    // ⚠️ 这条用例原来钉的是"底栏走 GlassSegmented（底托 + 独立选中胶囊）"——
    // 2026-10-09 用户点名要「苹果原生的 uitabbar」，底栏换成真的 `UITabBar`
    // （`NativeTabBar` → 平台视图 `lianleme/native_tab_bar`）。
    // 所以判据也换了：**不许再有 GlassSegmented**，而平台视图的创建参数要对得上
    // （原生按这些名字取值，写错了界面上就是一条空底栏、而且不报错 ——
    // 与 `GlassSegmented` 那几条同一个道理）。
    expect(find.byType(GlassSegmented), findsNothing,
        reason: '底栏不再自己画玻璃了（那颗"正中放大 + 强调色"也随之没有了）');

    final UiKitView view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(view.viewType, 'lianleme/native_tab_bar');
    final Map<Object?, Object?> args = view.creationParams! as Map<Object?, Object?>;
    expect((args['labels']! as List<Object?>).length, AppTabBar.tabs.length);
    expect((args['icons']! as List<Object?>).length, AppTabBar.tabs.length);
    expect(args['selectedIndex'], 2, reason: '当前那一格 = 训练（下标 2）');
    // 颜色走 `#RRGGBB`（原生按这个解析），两端同一套 Tokens
    expect(args['selectedColor'], isA<String>());
    expect((args['selectedColor']! as String).startsWith('#'), isTrue);
    expect(args['unselectedColor'], isA<String>());

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

  test('★ 全仓扫一遍：分段控件只许走 `ViSegmented`（2026-10-10 漏过两处的教训）', () {
    // 用户那天说「**选中胶囊还有没改的，你再查一下**」—— 一查真有：
    // 「身体数据」页的体重单位（kg/lb/斤）与「设置 → 显示」的重量单位（kg/lb）
    // 当时还在直接用 `GlassSegmentedRow`（iOS 上就是旧的玻璃胶囊），
    // 所以那两处没跟着换成橙色的原生控件。
    //
    // 这条把"靠人眼找"换成"机械扫"：**除了 `ViSegmented` 自己那一支，
    // lib/ 下不许再有人直接建玻璃分段行** —— 否则它就是下一个漏网的选中胶囊。
    // 扫的是**去掉行注释之后**的代码（注释里提到这个名字是正常的，我在好几处都写了）。
    final List<String> offenders = <String>[];
    for (final FileSystemEntity e
        in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String path = e.path;
      // 这两个文件是"实现本身"，不算调用点
      if (path.endsWith('core/vi_cards.dart')) continue;
      if (path.endsWith('core/glass_segmented.dart')) continue;
      final String code = e
          .readAsLinesSync()
          .map((String l) {
            final int i = l.indexOf('//');
            return i < 0 ? l : l.substring(0, i);
          })
          .join('\n');
      if (code.contains('GlassSegmentedRow(') || code.contains('GlassSegmented(')) {
        offenders.add(path);
      }
    }
    expect(offenders, isEmpty,
        reason: '这些地方还在自己建玻璃分段控件，应该改用 `ViSegmented`：$offenders');
  });
}
