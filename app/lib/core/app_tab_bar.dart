/// 练了么 · 底部 Tab 栏
///
/// **五个**（训练 / 进步 / 数据 / 计划 / 我的）—— 2026-10-05 按新 VI 从"三个封顶"改过来，
/// 见 `docs/screens.md` 与 `docs/plan-vi-migration.md`。
///
/// 图标用的是 Material 的线框图标（VI 那套自绘的 Tab 图标体系还没做）——
/// **这是个已知的过渡状态**，写在这里免得下一个人以为"已经对上了"。
/// 之前这个组件只是个装饰性的静态元件，现在由外壳持有状态、真的能切换 ——
/// 假的可点按元件比没有更糟。
library;

import 'package:flutter/material.dart';

import 'package:flutter/foundation.dart';

import 'glass_segmented.dart';
import 'glass_surface.dart';
import 'theme.dart';

class AppTabBar extends StatelessWidget {
  const AppTabBar({
    super.key,
    required this.current,
    required this.onChanged,
    this.dragIndex,
  });

  final int current;
  final ValueChanged<int> onChanged;

  /// 手指左右拖页面时的**连续位置**（小数页号）；`null` = 没人在拖。
  /// 传进玻璃里，那颗胶囊就**跟着手指滑**而不是跳格（见 `GlassSegmented.dragIndex`）。
  final ValueListenable<double>? dragIndex;

  /// 胶囊高度（2026-10-06 从通栏 56 改成浮动胶囊 58 —— 苹果 iOS 26 的底栏是浮起来的一块）。
  static const double height = 58;

  /// 圆角＝高度的一半 → 胶囊。iOS 26 原生的 tab bar 就是这个形状。
  static const double radius = height / 2;

  /// 左右与离底的留白（浮起来之后，屏幕边缘能看到内容在它两侧继续）。
  static const double floatMargin = 12;

  /// **每屏的滚动内容底部要留出的空间**（否则最后一项会被压在玻璃下面）。
  ///
  /// 只在**浮动**（iOS）时非零：Android 那条底栏仍然贴在内容下面，不需要留。
  /// ⚠️ 用 `GlassSurface.isSupportedPlatform` 判断 —— 与"哪一端浮动"是同一条判据，
  /// 两处各写一个条件迟早会漂（那就会出现"Android 上底部空出一大块"这种怪事）。
  static double reservedSpaceFor(BuildContext context) =>
      GlassSurface.isSupportedPlatform ? height + floatMargin + 8 : 0;

  static const List<({IconData icon, String label})> tabs =
      <({IconData icon, String label})>[
    (icon: Icons.fitness_center, label: '训练'),
    (icon: Icons.show_chart, label: '进步'),
    (icon: Icons.bar_chart, label: '数据'),
    (icon: Icons.event_note, label: '计划'),
    (icon: Icons.person_outline, label: '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    // **只给 iOS 浮动 + 玻璃**（2026-10-06 用户拍板：A 路线、仅 iOS）。
    // Android 走 else 那一支：通栏、贴底、保留 1px 顶边线 —— 与以前**一个像素都不差**。
    final bool floating = GlassSurface.isSupportedPlatform;

    final Widget bar = Container(
      key: const Key('tab-bar'),
      height: height,
      decoration: BoxDecoration(
        // iOS：胶囊、无线（玻璃自己的边缘高光就是分隔）；Android：保持原样
        borderRadius: floating ? BorderRadius.circular(radius) : null,
        border: floating ? null : const Border(top: BorderSide(color: Tokens.line)),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < tabs.length; i++)
            Expanded(
              child: InkWell(
                key: Key('tab-${tabs[i].label}'),
                onTap: () => onChanged(i),
                // iOS：**不要 Material 的水波纹/高亮** —— 那里的按压反馈是
                // "那块玻璃鼓起来、亮一档"（原生的手感，见 `GlassSegmented`）。
                // 一层涟漪盖在玻璃上，既不是苹果的样子，也会把玻璃的形变糊掉。
                // Android 保持原样（水波纹是那边的语言）。
                splashFactory: floating ? NoSplash.splashFactory : null,
                highlightColor: floating ? Colors.transparent : null,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      tabs[i].icon,
                      size: 22,
                      color: i == current ? Tokens.accent : Tokens.text3,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tabs[i].label,
                      style: TextStyle(
                        color: i == current ? Tokens.accent : Tokens.text3,
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    if (!floating) return bar;

    // ⚠️ 这里不再垫 backdrop（2026-10-06 改）：外壳已把**内容铺满、底栏浮在它上面**
    // （`main.dart` 的 Stack），滚动时真实内容从玻璃后面经过 —— 这才是那个观感的来源。
    //
    // 用 **`GlassSegmented` 而不是 `GlassSurface`**：底栏要的是
    // **"底托 + 选中那一格的胶囊"两块玻璃**（用户 2026-10-06 拍板要这个）。
    // 底栏的 5 格本来就是 `Expanded`（等分），正好符合"条目必须等宽"这个前提。
    //
    // ⚠️ 这两块是**各自独立**的玻璃，**故意不进 `UIGlassContainerEffect`**：
    // 那个容器会把叠在一起的两块抹平成一块 —— 真机上就变成了"切 tab 完全没有玻璃的感觉"
    // （2026-10-06 你的原话）。逐行对比见 `docs/images/glass-probe-segment-variants.png`。
    //
    // 材质：底托 `.regular`；选中胶囊同样 `.regular` + **一点白（12%）**，
    // 因为玻璃底托本身就比屏幕亮，选中那块要再亮一档才读得出来（苹果也是这么做的）。
    return GlassSegmented(
      key: const Key('glass-tab-bar'),
      count: tabs.length,
      index: current,
      radius: radius,
      style: GlassStyle.regular,
      // 胶囊往里缩 5pt：这条缝就是"凸起来的那块"与底托的分界
      pillInset: 5,
      dragIndex: dragIndex,
      // 按住不放、横向拖到别格再松手 = 换 tab（`changes` 幂等，与点击那条路不冲突）
      onDragSelect: onChanged,
      child: bar,
    );
  }
}
