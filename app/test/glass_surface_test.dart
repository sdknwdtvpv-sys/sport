/// 练了么 · iOS 液态玻璃那层壳（`GlassSurface`）
///
/// **这一组守什么**：它只有一条真正的分界线 —— **iOS 才画玻璃，其它平台原样放行**。
/// 这条线断了会有两种症状，而且都很坏：
///   * 该放行时没放行 → **Android 的界面被悄悄改了**（用户 2026-10-06 拍板的条件就是
///     "Android 一个像素都不动"）；
///   * 该画时没画 → iOS 上什么都不出现，而**没有任何报错**（platform view 的创建参数
///     与原生读取的名字对不上时就是这个下场，`UiKitView` 不校验）。
/// 所以这里把"非 iOS 原样返回""iOS 传了哪些参数"两条都钉住。
///
/// ⚠️ `debugDefaultTargetPlatformOverride` **必须在每个用例体里改回 null**：测试框架会在
/// 用例体结束时校验"foundation 的调试变量有没有被留下"，放 `tearDown` 里已经太晚
/// （会报 "The value of a foundation debug variable was changed by the test"）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/glass_surface.dart';

Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  testWidgets('★ 非 iOS：原样返回 child —— 一个 UIKitView、一层 backdrop 都不许出现',
      (WidgetTester tester) async {
    for (final TargetPlatform p in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    ]) {
      debugDefaultTargetPlatformOverride = p;
      await pump(
        tester,
        const GlassSurface(
          backdrop: Text('垫层', textDirection: TextDirection.ltr),
          child: Text('内容', textDirection: TextDirection.ltr),
        ),
      );
      expect(find.text('内容'), findsOneWidget, reason: '$p 上内容必须照旧渲染');
      expect(find.byType(UiKitView), findsNothing, reason: '$p 上不该有平台视图');
      expect(find.text('垫层'), findsNothing,
          reason: '$p 上玻璃不存在，垫的那层也不该画（画了等于凭空多出一块颜色）');
    }
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('★ iOS：走 UiKitView，且创建参数逐项对（原生按这些名字取值）',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pump(
      tester,
      const GlassSurface(
        style: GlassStyle.clear,
        tint: '#FF5C2620',
        radius: 32,
        interactive: true,
        backdrop: Text('垫层', textDirection: TextDirection.ltr),
        child: Text('内容', textDirection: TextDirection.ltr),
      ),
    );

    final UiKitView view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(view.viewType, 'lianleme/glass',
        reason: '与 GlassBridge.swift 里的 viewType 必须逐字一致');
    final Map<Object?, Object?> args = view.creationParams! as Map<Object?, Object?>;
    expect(args['style'], 'clear');
    expect(args['radius'], 32);
    expect(args['interactive'], true);
    expect(args['tint'], '#FF5C2620');
    // 内容仍然画在玻璃上面（图标/文字是 Flutter 画的），垫层在它背后
    expect(find.text('内容'), findsOneWidget);
    expect(find.text('垫层'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS：backdrop 真的垫在玻璃背后（它有东西可折射才不是灰板）',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pump(
      tester,
      const GlassSurface(
        backdrop: Text('垫层', textDirection: TextDirection.ltr),
        child: Text('内容', textDirection: TextDirection.ltr),
      ),
    );
    expect(find.text('垫层'), findsOneWidget);
    expect(find.text('内容'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS：不传 tint 时就不带这个键（别传 null 让原生去猜）',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pump(
      tester,
      const GlassSurface(child: SizedBox.shrink()),
    );
    final UiKitView view = tester.widget<UiKitView>(find.byType(UiKitView));
    final Map<Object?, Object?> args = view.creationParams! as Map<Object?, Object?>;
    expect(args.containsKey('tint'), isFalse);
    // 默认值也是有意的：默认 `.clear` —— 我们的 VI 是暗底，`.regular` 在暗底上发灰
    expect(args['style'], 'clear');
    expect(args['interactive'], false);
    expect(args['radius'], 0);
    debugDefaultTargetPlatformOverride = null;
  });
}
