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

/// `Color` → `#RRGGBB`（原生按这个解析；不写死十六进制，免得与调色板漂）
String _hexOf(Color c) {
  final int v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}


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
  /// 底栏高度（2026-10-08 从 58 加到 **68**）。
  ///
  /// 用户原话（真机反馈第二遍）：「Tab 栏中间那个玻璃效果还是有问题，**直接把 Tab 栏
  /// 变宽一点，所有的内容都包进来吧，不要让中间突出去一截了**，只在中间的图标做点文章就行」。
  /// 所以这一版把"正中那颗凸起"整个收进底栏里：栏加高 10pt（正中那格的强调圆 + 图标 +
  /// 文字全都落在栏内）、左右留白 12 → 8（"变宽一点"）、正中只在**图标**上做文章。
  static const double height = 68;

  /// 圆角＝高度的一半 → 胶囊。iOS 26 原生的 tab bar 就是这个形状。
  static const double radius = height / 2;

  /// 左右与离底的留白（浮起来之后，屏幕边缘能看到内容在它两侧继续）。
  static const double floatMargin = 8;

  /// 正中那颗圆的直径（只垫在**图标**下面，**完全在栏内** —— 不再有"突出去一截"）。
  /// 直径 36：40 那颗在 iOS 的胶囊里会**贴着上沿**（胶囊上沿离栏顶还有 5pt 的内缩），
  /// 看着像被切了一刀 —— 36 给两端都留出 2pt 以上的呼吸。两端同一个数。
  static const double centerCircleSize = 36;

  /// **每屏的滚动内容底部要留出的空间**（否则最后一项会被压在玻璃下面）。
  ///
  /// 只在**浮动**（iOS）时非零：Android 那条底栏仍然贴在内容下面，不需要留。
  /// ⚠️ 用 `GlassSurface.isSupportedPlatform` 判断 —— 与"哪一端浮动"是同一条判据，
  /// 两处各写一个条件迟早会漂（那就会出现"Android 上底部空出一大块"这种怪事）。
  static double reservedSpaceFor(BuildContext context) =>
      GlassSurface.isSupportedPlatform ? height + floatMargin + 8 : 0;

  /// **顺序**：`进步 / 数据 / 训练 / 计划 / 我的`（2026-10-07，v1.60.0）。
  ///
  /// 用户 10.7 清单第 2 条：「下面导航栏五个，**训练放在最中间**，并且最好跟其他四个
  /// 做区别展示」。所以「训练」从最左挪到正中，并做成一颗**凸起的圆**（见
  /// [_centerIndex] 与 `_centerAction`）—— 它本来就是"这个 App 的主按钮"。
  ///
  /// ⚠️ **下标语义跟着变了**：`main.dart` 的 `_bodyFor` 与初始 tab（2）必须与这一份
  /// **逐条对齐**，错一条就是"点训练进了数据"。两处都有注释互相指着。
  static const List<({IconData icon, String label})> tabs =
      <({IconData icon, String label})>[
    (icon: Icons.show_chart, label: '进步'),
    (icon: Icons.bar_chart, label: '数据'),
    (icon: Icons.fitness_center, label: '训练'),
    (icon: Icons.event_note, label: '计划'),
    (icon: Icons.person_outline, label: '我的'),
  ];

  /// 凸起的那一格（正中）。它的图标由 Flutter 画在一颗圆里，**不画文字标签**
  /// （Apple 那套"中间是动作、不是格子"的做法：有了文字反而像第二个 tab）。
  static const int _centerIndex = 2;

  /// 正中那一格（**完全在栏内**）：强调色实心圆垫在图标下 + 深墨图标 + 文字。
  ///
  /// 用户原话（真机反馈第二遍）：「只在**中间的图标**做点文章就行」——
  /// 区别只在这颗圆；文字与另外四格同一个字号、同一个位置（五格仍然等宽）。
  Widget _centerCell(int i) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            key: const Key('tab-center-icon'),
            width: centerCircleSize,
            height: centerCircleSize,
            decoration: const BoxDecoration(
              color: Tokens.accent,
              shape: BoxShape.circle,
            ),
            child: Icon(tabs[i].icon, size: 20, color: Tokens.bg),
          ),
          const SizedBox(height: 3),
          Text(
            tabs[i].label,
            key: const Key('tab-center-label'),
            style: TextStyle(
              color: i == current ? Tokens.accent : Tokens.text3,
              fontSize: 11,
              height: 1.2,
            ),
          ),
        ],
      );

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
            // ⚠️ 正中那一格**不画图标与文字**（它们由 `_centerAction` 或原生那层画），
            // 但**两种平台都要占满一格** —— 五格等宽全靠它：少一格会让"计划/我的"
            // 整体左移，一眼就不齐。
            if (i == _centerIndex)
              Expanded(
                child: floating
                    // iOS：圆与图标由**原生**画在玻璃之上（见 `emphasisIndex`），
                    // 但**点击仍然由 Flutter 这一层接**（`UiKitView` 的
                    // `gestureRecognizers` 是空集合，所以触摸穿透到 Flutter）。
                    // 所以这里要留一个**透明但可点**的热区，key 与另外四格同一套命名 ——
                    // 少了它，iOS 上"点正中那颗训练"就点不动，按 key 找它的测试也会红。
                    ? GestureDetector(
                        key: Key('tab-${tabs[i].label}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(i),
                        child: const SizedBox.expand(),
                      )
                    // Android：整个格子由 Flutter 画在栏内（见 `_centerCell`）
                    : GestureDetector(
                        key: Key('tab-${tabs[i].label}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(i),
                        child: _centerCell(i),
                      ),
              )
            else
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

    // Android（通栏、没有玻璃）：正中那格由 **Flutter** 画，但**完全画在栏内**
    // （那颗强调圆垫在图标下，与 iOS 原生那颗同一个意图）—— 不再"顶出上沿"。
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
      // 字与图标交给原生画（玻璃**里面**）：Flutter 那份在玻璃背后，会被折射出第二份虚影。
      // ⚠️ 2026-10-08（v1.61.0）改：正中那一格**不再传空串** ——
      // 它的圆也交给原生画（`emphasisIndex`），理由是同一个：
      // Flutter 画的圆会落在玻璃**背后**，被折射成一层发灰的虚影
      // （用户 10.8 清单第 1 条「tab 栏的训练 玻璃效果 bug」就是这么来的）。
      labels: <String>[for (final ({IconData icon, String label}) t in tabs) t.label],
      icons: const <String>[
        'chart.line.uptrend.xyaxis',
        'chart.bar.fill',
        'dumbbell.fill',
        'calendar',
        'person',
      ],
      // 正中那颗：原生在这一层（玻璃**之上**）画一颗实心强调圆 + 深墨图标。
      // ⚠️ iOS 上它**不凸出**平台视图的边界（平台视图是一张按 bounds 裁好的纹理）——
      // 所以 iOS 是"实心强调圆"、Android 是"凸出上沿 10pt 的圆"：
      // 同一个意图，各自贴合本端材质（差异记在 `docs/screens.md`）。
      emphasisIndex: _centerIndex,
      emphasisColor: _hexOf(Tokens.accent),
      emphasisIconColor: _hexOf(Tokens.bg),
      selectedColor: _hexOf(Tokens.accent),
      unselectedColor: _hexOf(Tokens.text3),
      labelFontSize: 11,
      iconSize: 22,
      // 按住不放、横向拖到别格再松手 = 换 tab（`changes` 幂等，与点击那条路不冲突）
      onDragSelect: onChanged,
      child: bar,
    );
  }

}
