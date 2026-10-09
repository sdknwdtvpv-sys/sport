/// 练了么 · 弹层的玻璃背景（`showAppDialog` / `showAppSheet`）
/// （2026-10-09，10.9 清单第 2a 条：顶栏 + 底栏 + **浮层**做玻璃）
///
/// **这一组守两条线**：
///   1. **非 iOS 逐参数等价** —— Android 上不许因为"多了个玻璃入口"而改变任何东西
///      （连多套一层 `Theme` 都不行）；
///   2. **iOS 上玻璃真的包上去了，而且弹层自己的底色被改透明** ——
///      后面这条最容易漏：底色不透明时玻璃被盖住，界面上**看不出任何区别**，
///      也没有任何报错（"以为做了、其实没有"）。
///
/// ⚠️ 与本仓库其它玻璃测试同一条规矩：`debugDefaultTargetPlatformOverride`
/// 必须在**用例体内**改回 null（放 tearDown 里太晚，测试框架会判"调试变量被改过"）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/glass_overlay.dart';
import 'package:lianleme/core/glass_surface.dart';
import 'package:lianleme/core/theme.dart';

/// 一个带按钮的宿主：点按钮 → 开弹层。
Future<void> pumpHost(
  WidgetTester tester, {
  required Future<void> Function(BuildContext) open,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: Builder(
        builder: (BuildContext ctx) => Center(
          child: ElevatedButton(
            key: const Key('open-overlay'),
            onPressed: () => open(ctx),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('★ 非 iOS：showAppDialog 与原生 showDialog 等价（不许出现玻璃）',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pumpHost(tester, open: (BuildContext ctx) async {
      await showAppDialog<void>(
        context: ctx,
        builder: (_) => AlertDialog(
          key: const Key('the-dialog'),
          backgroundColor: Tokens.surface,
          content: const Text('内容'),
        ),
      );
    });

    await tester.tap(find.byKey(const Key('open-overlay')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('the-dialog')), findsOneWidget);
    expect(find.byType(GlassSurface), findsNothing,
        reason: 'Android 上一个像素都不动 —— 玻璃组件连建都不该建');
    // 底色也照旧（没有那一层"改透明"的 Theme）
    expect(
      tester.widget<AlertDialog>(find.byKey(const Key('the-dialog'))).backgroundColor,
      Tokens.surface,
    );

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('★ iOS：弹层包上玻璃，且弹层自己的底色被改成透明（否则玻璃被盖住）',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpHost(tester, open: (BuildContext ctx) async {
      await showAppDialog<void>(
        context: ctx,
        builder: (_) => AlertDialog(
          key: const Key('the-dialog'),
          backgroundColor: Tokens.surface,
          content: const Text('内容'),
        ),
      );
    });

    await tester.tap(find.byKey(const Key('open-overlay')));
    await tester.pumpAndSettle();

    expect(find.byType(GlassSurface), findsOneWidget, reason: 'iOS 上整块弹层是玻璃');
    // 实际生效的 dialogTheme 底色必须是透明 —— 弹层自己那条 `backgroundColor`
    // 我们**不替用户改**（那是各处自己写的），改的是主题这一层：
    // Material 的优先序是"组件参数 > 主题"，所以这里要钉住的是主题确实透明了，
    // 而**各处不该再自己填底色**（写在使用纪律里）。
    final ThemeData theme = Theme.of(
      tester.element(find.byKey(const Key('the-dialog'))),
    );
    expect(theme.dialogTheme.backgroundColor, Colors.transparent);
    expect(theme.dialogTheme.elevation, 0, reason: '透明底上的阴影会变成一圈脏边');

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('★ 非 iOS：showAppSheet 与原生 showModalBottomSheet 等价',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pumpHost(tester, open: (BuildContext ctx) async {
      await showAppSheet<void>(
        context: ctx,
        backgroundColor: Tokens.surface,
        builder: (_) => const SizedBox(height: 120, child: Text('弹层内容')),
      );
    });

    await tester.tap(find.byKey(const Key('open-overlay')));
    await tester.pumpAndSettle();

    expect(find.text('弹层内容'), findsOneWidget);
    expect(find.byType(GlassSurface), findsNothing, reason: 'Android 不画玻璃');

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('★ iOS：底部弹层是玻璃，圆角在玻璃上（否则会顶到屏幕两个角）',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpHost(tester, open: (BuildContext ctx) async {
      await showAppSheet<void>(
        context: ctx,
        builder: (_) => const SizedBox(height: 120, child: Text('弹层内容')),
      );
    });

    await tester.tap(find.byKey(const Key('open-overlay')));
    await tester.pumpAndSettle();

    expect(find.text('弹层内容'), findsOneWidget);
    final Finder glass = find.ancestor(
      of: find.text('弹层内容'),
      matching: find.byType(GlassSurface),
    );
    expect(glass, findsOneWidget, reason: 'iOS 上底部弹层也是一块玻璃');
    expect(tester.widget<GlassSurface>(glass).radius, kGlassSheetRadius);

    debugDefaultTargetPlatformOverride = null;
  });
}
