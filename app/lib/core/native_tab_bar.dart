/// 练了么 · **苹果原生 `UITabBar`** 的 Dart 侧（2026-10-09）
///
/// 用户原话：「我想要苹果原生的 uitabbar」。原话之前他发来一份
/// `StellarTabBar.swift`（SwiftUI，靠 `UITabBarAppearance` + `.toolbarBackground` 生效）——
/// 那是**另一个项目的 SwiftUI App**：我们的 App 是 Flutter，iOS 侧一个 `UITabBar`、
/// 一个 SwiftUI 视图都没有，所以那份文件**拖进来也不会有一个像素的变化**
/// （它改的是我们并不存在的 `UITabBar`）。
///
/// 能落地的是**它的做法**：用一个真的 `UITabBar`（`ios/Runner/NativeTabBarBridge.swift`），
/// 外观走 `UITabBarAppearance`。这一层就是那个控件的 Dart 门面。
///
/// ## 三条边界（与 Swift 那份注释同源，改之前先读）
///
/// 1. **它只是一个 `UITabBar`，不是 `UITabBarController`** —— iOS 26 的"浮动胶囊 +
///    滚动自动收起"长在后者身上，那要把外壳换成 UIKit 且每 tab 一个 FlutterView，
///    与本 App"一个引擎、一份外壳状态"冲突。这一版拿到的是**系统控件本体与它的外观**。
/// 2. **五格一视同仁**：原生的 `UITabBarItem` 没有"某一格更大"这回事 ——
///    v1.66.0 第 2b 条那颗"正中放大 + 强调色"在原生控件里表达不出来。
/// 3. **选中是离散的**：`dragIndex`（手指拖动时胶囊跟手滑）没有对应 API，页面照样能拖，
///    但底栏是松手后跳过去。
///
/// ## 触摸：iOS 上**不许再盖透明热区**
///
/// 原来那块玻璃是"触摸穿透"的（Dart 在上面盖五块透明热区）。真 `UITabBar` 自己接触摸，
/// 盖上去就会把点击吃掉。所以 iOS 这支**只画平台视图**，选中变化由原生通道回给 Dart。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass_surface.dart' show GlassSurface;
import 'native_hex.dart';
import 'theme.dart';

/// 原生底栏要的全部参数（与 `NativeTabBarBridge.swift` 读的键名一一对应）。
@immutable
class NativeTabBarSpec {
  const NativeTabBarSpec({
    required this.labels,
    required this.icons,
    required this.selectedIndex,
    required this.selectedColor,
    required this.unselectedColor,
    this.hairline,
  });

  final List<String> labels;
  final List<String> icons;
  final int selectedIndex;

  /// `#RRGGBB` / `#RRGGBBAA`（原生按这个解析，与 `GlassBridge` 同一套写法）
  final String selectedColor;
  final String unselectedColor;

  /// 顶部分割线（不传 = 系统的默认）
  final String? hairline;

  Map<String, Object?> toMap() => <String, Object?>{
        'labels': labels,
        'icons': icons,
        'selectedIndex': selectedIndex,
        'selectedColor': selectedColor,
        'unselectedColor': unselectedColor,
        if (hairline != null) 'hairline': hairline,
      };
}

/// 一块**真的 `UITabBar`**。
///
/// 非 iOS（Android / 桌面 / widget 测试）**不渲染任何东西** —— 那条分支由调用方
/// （`AppTabBar`）自己用 Flutter 画，与"Android 一个像素都不动"是同一条纪律。
class NativeTabBar extends StatefulWidget {
  const NativeTabBar({
    super.key,
    required this.spec,
    this.onSelected,
    this.height = 49,
  });

  final NativeTabBarSpec spec;

  /// 用户点了某一格（原生回调，0 起）
  final ValueChanged<int>? onSelected;

  /// 平台视图的高度。⚠️ 真源在**原生那边**（`UITabBar` 自己的高度），
  /// 这里给的是 Flutter 布局用的值：与 `AppTabBar.height` 保持一致，
  /// 否则内容底部留白会与实际底栏差一截。
  final double height;

  @override
  State<NativeTabBar> createState() => _NativeTabBarState();
}

class _NativeTabBarState extends State<NativeTabBar> {
  MethodChannel? _channel;

  void _onPlatformViewCreated(int id) {
    _channel = MethodChannel('lianleme/native_tab_bar/$id');
    _channel!.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onTabSelected') {
        final Object? args = call.arguments;
        final Object? raw = args is Map ? args['index'] : null;
        if (raw is num) widget.onSelected?.call(raw.toInt());
      }
    });
  }

  @override
  void didUpdateWidget(NativeTabBar old) {
    super.didUpdateWidget(old);
    // 选中变了（从 Dart 那边切的 tab）→ 告诉原生，别让两边显示不一致
    if (old.spec.selectedIndex != widget.spec.selectedIndex) {
      _channel?.invokeMethod<void>('setSelected', <String, Object?>{
        'index': widget.spec.selectedIndex,
      });
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!GlassSurface.isSupportedPlatform) return const SizedBox.shrink();
    return SizedBox(
      height: widget.height,
      child: UiKitView(
        key: const Key('native-tab-bar'),
        viewType: 'lianleme/native_tab_bar',
        layoutDirection: TextDirection.ltr,
        creationParams: widget.spec.toMap(),
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
        // ⚠️ **`EagerGestureRecognizer`：这块区域的手势全交给原生** ——
        // 真 `UITabBar` 是一块**自己接触摸**的 UIKit 控件，它得拿到点击才能点选、
        // 才有系统的手感与无障碍。
        //
        // ⚠️ 这一条与**原来那块玻璃正好相反**：那边传的是**空集合**（Flutter 认领手势，
        // 于是触摸穿透到 Flutter 层，由盖在上面的透明热区接点击，见 v1.66.0 的
        // `app_tab_bar.dart`）。现在反过来了 —— 空集合会让系统控件**一个点击都收不到**。
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
        },
      ),
    );
  }
}

/// 底栏那五个 tab 的颜色（与 `AppTabBar` 里 Flutter 那一支**同源**，
/// 免得两支各写一套颜色、改一处忘一处）。
NativeTabBarSpec nativeTabBarSpec({
  required List<String> labels,
  required List<String> icons,
  required int selectedIndex,
}) =>
    NativeTabBarSpec(
      labels: labels,
      icons: icons,
      selectedIndex: selectedIndex,
      selectedColor: hexOfColor(Tokens.accent),
      // 未选中 = text2：tab 标签是功能性标签（VI 计划 T0-3）
      unselectedColor: hexOfColor(Tokens.text2),
      hairline: hexOfColor(Tokens.line),
    );
