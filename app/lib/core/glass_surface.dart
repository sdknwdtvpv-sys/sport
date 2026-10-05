/// 练了么 · iOS 26 的「液态玻璃」表面（`UIGlassEffect`，真材质）
///
/// ## 一条边界：**只做 iOS，Android 一个像素都不动**
///
/// 非 iOS（含 Android、以及跑在 macOS 上的 widget 测试）**原样返回 [child]** ——
/// 不模糊、不加边框、不加内边距。所以"接上它"对 Android 是**零影响**，
/// 这也是当初选这条路的条件之一（用户 2026-10-06 拍板：A 路线、仅 iOS）。
///
/// iOS 上的分档（由原生那侧决定，Dart 这边不需要知道系统版本）：
///   * **iOS 26+** → `UIGlassEffect` 真材质；
///   * **iOS 26 以下** → **退回** `UIBlurEffect(.systemUltraThinMaterial)`（是"退回"，不是等价物）。
///
/// ## ⚠️ 用它的前提：**玻璃必须背后有东西可折射**
///
/// 2026-10-06 的 spike 实测（证据 `docs/images/glass-spike-1-flat-vs-content.png`）：
/// 同一块 `.regular`，背后是纯炭黑时**变成一块浅灰板**（比屏幕上所有东西都亮、抢视线），
/// 背后有彩色内容时才是 Apple 那个样子。所以：
///   1. 默认 `style: GlassStyle.clear`（`.clear` 在暗底上读得出是玻璃，`.regular` 会发灰）；
///   2. 背后确实没内容时，用 [backdrop] **自己垫一层**（内容/纹理/极淡辉光）；
///   3. **纯色空屏上别用** —— 那种地方宁可不放玻璃。
///
/// ## 代价（必须写下来，不然会有人问"为什么这里卡"）
///
/// 它是一个**平台视图**：活着的期间 Flutter 的栅格化不再与 Dart 并行（整屏代价），
/// 而且画在它上面的 Flutter 内容（图标、文字）会多出一层 overlay surface。
/// 所以：**一屏一两处**，别放进列表行里。真机 release 的帧率必须实测
/// （`docs/feature-backlog.md` §〇「⑦」里记着这一条还没验）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 玻璃的两种材质。默认 [clear] —— 我们的 VI 是暗底，`.regular` 在暗底上会发灰。
enum GlassStyle {
  /// `.regular`：Apple 默认的玻璃（**要背后有内容**才好看；纯色暗底上会变灰板）
  regular('regular'),

  /// `.clear`：更透的一档，暗底 + 一点 tint 最好看（我们的默认）
  clear('clear');

  const GlassStyle(this.wire);
  final String wire;
}

/// 一块 iOS 26 的液态玻璃。[child] 画在玻璃**上面**（图标/文字照旧是 Flutter 画的）。
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.style = GlassStyle.clear,
    this.tint,
    this.radius = 0,
    this.interactive = false,
    this.backdrop,
  });

  final Widget child;

  final GlassStyle style;

  /// 淡淡的染色（`#RRGGBB` 或 `#RRGGBBAA`）。暗底上给一点暖色会像"烟熏玻璃"。
  final String? tint;

  /// 圆角。0 = 通栏（底栏那种），32 左右 = 胶囊。
  final double radius;

  /// 交给系统的"可按压"行为（会跟着手指做形变）。底栏这种不需要。
  final bool interactive;

  /// 玻璃**背后**垫的那一层（只有 iOS 会画它；非 iOS 连它也不画 —— 因为那时
  /// 玻璃不存在，垫的东西就没有意义，画了反而多出一块颜色）。
  ///
  /// 为什么要有这个参数：我们的底栏下面是 Scaffold 的纯炭黑背景，**没有东西可折射**，
  /// 玻璃会变成灰板。所以由调用方决定"垫什么"（例如底栏上方那一点点辉光）。
  final Widget? backdrop;

  /// ⚠️ 用 `defaultTargetPlatform` 而不是 `Platform.isIOS`：前者**测试里能改**
  /// （`debugDefaultTargetPlatformOverride`），后者不能 —— 否则"iOS 分支长什么样"
  /// 就永远只有真机能验，而这一层恰恰是最容易写错创建参数的地方。
  static bool get isSupportedPlatform => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    if (!isSupportedPlatform) return child;
    return Stack(
      children: <Widget>[
        if (backdrop != null) Positioned.fill(child: backdrop!),
        Positioned.fill(
          child: UiKitView(
            viewType: 'lianleme/glass',
            // ⚠️ 参数名要与 GlassBridge.swift 里的读取**逐字一致**（没有编译期约束，
            // 写错了只会静默退回默认值 —— 那是最难查的一种"没生效"）。
            creationParams: <String, Object?>{
              'style': style.wire,
              'radius': radius,
              'interactive': interactive,
              if (tint != null) 'tint': tint,
            },
            creationParamsCodec: const StandardMessageCodec(),
            // 玻璃本身不吃手势（图标/文字在它上面，那些才要点）
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          ),
        ),
        child,
      ],
    );
  }
}
