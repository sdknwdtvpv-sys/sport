/// 练了么 · 弹层（对话框 / 底部弹层）的玻璃背景
/// （2026-10-09，10.9 清单第 2a 条）
///
/// 用户拍板的范围：**顶栏 + 底栏 + 浮层**做玻璃，列表里的卡片保持不透明
/// （理由写在 `docs/plan-ux-2026-10-09.md` §零：卡片里是小字与图表，
/// 健身房里是暗光 + 汗手，玻璃底会把可读性做坏）。
///
/// ## 为什么要有这个文件，而不是每处自己包一层
///
/// 弹层在本仓库里有 **20 多处**（`showDialog` / `showModalBottomSheet`）。
/// 如果每处自己写 `GlassSurface(...)`，一定会出现：有的包了有的没包、
/// 有的圆角不一样、有一天有人加了个新弹层又忘了 —— 而"有的弹层是玻璃、
/// 有的不是"比"全都不是"更难看。所以这里给两个**统一入口**，
/// 全仓库的弹层都从它们开：
///
///   * [showAppDialog] —— 顶替 `showDialog`
///   * [showAppSheet]  —— 顶替 `showModalBottomSheet`
///
/// ## 关键的一步：把弹层自己的底色**变透明**
///
/// 玻璃必须能透过去。Material 的 `AlertDialog` / `BottomSheet` 默认自带
/// 不透明底色（`Tokens.surface`），包一层玻璃只会得到"玻璃上盖了一块实心板"。
/// 所以 [showAppDialog] 用 `Theme` 把 `dialogTheme.backgroundColor` 改成透明
/// （弹层内部的 Material 于是成了空壳），玻璃才露得出来 —— 这一步在**外面**
/// 做得到，正是它值得做成公共入口的原因。
///
/// ## 非 iOS 一个像素都不动
///
/// 判据只有一条：`GlassSurface.isSupportedPlatform`。非 iOS 时这两个函数
/// 与原来的 `showDialog` / `showModalBottomSheet` **逐参数等价** ——
/// Android 上连多一层 `Theme` 都不会套。
library;

import 'package:flutter/material.dart';

import 'glass_surface.dart';
import 'theme.dart';

/// 玻璃弹层的圆角。与 `dialogTheme` 的默认形状对得上（M3 是 28）。
const double kGlassDialogRadius = 28;

/// 底部弹层的圆角（只有上方两个角）。与各处原来那个 `RoundedRectangleBorder` 一致。
const double kGlassSheetRadius = Tokens.rCard;

/// 顶替 `showDialog`：iOS 上整块弹层是玻璃，其余平台与原来逐参数等价。
///
/// ⚠️ 弹层内部**不要再写 `backgroundColor: Tokens.surface`**（少数地方为了
/// "非 iOS 兜底"留着也行 —— 那会盖住玻璃；要留就留，但别指望玻璃露出来）。
/// 这是唯一一条使用纪律，写在这里免得下次有人一边包玻璃一边填底色。
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  String? barrierLabel,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) {
  if (!GlassSurface.isSupportedPlatform) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
      builder: builder,
    );
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    builder: (BuildContext ctx) {
      final ThemeData base = Theme.of(ctx);
      return Theme(
        // 弹层自己的底色**变透明**（否则玻璃被它盖住）+ 去掉阴影
        // （阴影画在透明底上会变成一圈脏边；玻璃自己的高光就是分隔）。
        data: base.copyWith(
          dialogTheme: base.dialogTheme.copyWith(
            backgroundColor: Colors.transparent,
            elevation: 0,
            shadowColor: Colors.transparent,
          ),
          bottomSheetTheme: base.bottomSheetTheme.copyWith(
            backgroundColor: Colors.transparent,
            elevation: 0,
            modalBackgroundColor: Colors.transparent,
          ),
        ),
        child: GlassSurface(
          radius: kGlassDialogRadius,
          style: GlassStyle.regular,
          // 弹层背后是**被压暗的页面**（`barrierColor`），有内容可折射 ——
          // 这正是玻璃最好看的那种场合（见 `glass_surface.dart` 文件头那条前提）。
          tint: '#10101480',
          child: builder(ctx),
        ),
      );
    },
  );
}

/// 顶替 `showModalBottomSheet`：iOS 上底部弹层是玻璃。
///
/// 其余平台**逐参数等价**于原来的调用（含 `backgroundColor`、`shape`、
/// `isScrollControlled`、`enableDrag`）—— Android 一个像素都不动。
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool enableDrag = true,
  bool isDismissible = true,
  bool useSafeArea = false,
  bool useRootNavigator = false,
  RouteSettings? routeSettings,
  Color? backgroundColor,
  ShapeBorder? shape,
}) {
  if (!GlassSurface.isSupportedPlatform) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      isScrollControlled: isScrollControlled,
      enableDrag: enableDrag,
      isDismissible: isDismissible,
      useSafeArea: useSafeArea,
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
      backgroundColor: backgroundColor,
      shape: shape,
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    // 玻璃自己就是那张"底"：底色透明，圆角用它自己的
    backgroundColor: Colors.transparent,
    isScrollControlled: isScrollControlled,
    enableDrag: enableDrag,
    isDismissible: isDismissible,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    // ⚠️ 形状交给玻璃（见 `GlassSurface.radius`），但**上面两个圆角必须留**：
    // 底部弹层的玻璃是一块按 bounds 裁的纹理，方形的话会顶到屏幕左右两个角。
    shape: shape ??
        const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(kGlassSheetRadius)),
        ),
    builder: (BuildContext ctx) => GlassSurface(
      radius: kGlassSheetRadius,
      style: GlassStyle.regular,
      tint: '#10101480',
      child: builder(ctx),
    ),
  );
}
