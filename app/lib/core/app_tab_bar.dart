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
            // ⚠️ 正中那一格**留空**：它由浮在底栏之上的那颗凸起圆顶替
            // （见下面的 `_centerAction`）。留一格空的，是为了**五格仍然等宽** ——
            // 直接少一格会让"计划/我的"整体左移，一眼就不齐。
            if (i == _centerIndex)
              const Expanded(child: SizedBox.shrink())
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

    if (!floating) return _withCenterAction(bar, floating: false);

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
    return _withCenterAction(
      GlassSegmented(
      key: const Key('glass-tab-bar'),
      count: tabs.length,
      index: current,
      radius: radius,
      style: GlassStyle.regular,
      // 胶囊往里缩 5pt：这条缝就是"凸起来的那块"与底托的分界
      pillInset: 5,
      dragIndex: dragIndex,
      // 字与图标交给原生画（玻璃**里面**）：Flutter 那份在玻璃背后，会被折射出第二份虚影。
      // ⚠️ 正中那一格（`_centerIndex`）**故意传空串**：它由 Flutter 画成一颗凸起的圆
      // （见 `_centerAction`）—— 原生的 SF Symbol 与文字若照画，圆里会叠出一份虚影。
      labels: <String>[
        for (int i = 0; i < tabs.length; i++) i == _centerIndex ? '' : tabs[i].label,
      ],
      icons: const <String>[
        'chart.line.uptrend.xyaxis',
        'chart.bar.fill',
        '',
        'calendar',
        'person',
      ],
      selectedColor: _hexOf(Tokens.accent),
      unselectedColor: _hexOf(Tokens.text3),
      labelFontSize: 11,
      iconSize: 22,
      // 按住不放、横向拖到别格再松手 = 换 tab（`changes` 幂等，与点击那条路不冲突）
      onDragSelect: onChanged,
      child: bar,
      ),
      floating: true,
    );
  }

  /// 底栏之上那颗**凸起的圆**（正中那一格，2026-10-07 v1.60.0）。
  ///
  /// 为什么是"浮在上面"而不是"画在格子里"：底栏只有 58pt 高，一格还要放图标 + 文字；
  /// 要让中间那颗"看起来是**动作**而不是格子"，就得**顶出底栏的上沿**。
  /// 于是它不进 `Row`，而是 `Stack` 里的一层 —— 五格仍然等宽（正中那格留空），
  /// 圆浮在正中那一格的上方。
  ///
  /// 两端都套这一层（Android 通栏 / iOS 玻璃胶囊），**只有玻璃的底子不同** ——
  /// 用户的原话里没有"只在 iOS 上区别展示"这层意思。
  Widget _withCenterAction(Widget content, {required bool floating}) => Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          content,
          Positioned(
            top: -10,
            left: 0,
            right: 0,
            child: Center(
              child: Semantics(
                button: true,
                label: tabs[_centerIndex].label,
                child: Tooltip(
                  message: tabs[_centerIndex].label,
                  child: GestureDetector(
                    // ⚠️ key 与另外四格**同一套命名**（`tab-<label>`）：正中那格就是
                    // 「训练」那一格，只是长得不一样。这样所有"点某个 tab"的测试与
                    // 截图脚本（`Key('tab-我')` 那种）都不用改。
                    key: Key('tab-${tabs[_centerIndex].label}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(_centerIndex),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // ⚠️ 这一格**必须有字**（「训练」）：底栏少了它，五个 tab 里就有一个
                        // 光看图标的格子 —— 而且 `widget_test` 那条"5 个 Tab"的断言
                        // 找的就是这五个字（它当场抓到了我第一版"中间不写字"的做法）。
                        Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Tokens.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Tokens.bg, width: 3),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Tokens.accent.withValues(alpha: 0.35),
                            blurRadius: 14,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                          child: Icon(
                            tabs[_centerIndex].icon,
                            size: 22,
                            // 深墨字压在强调色上（与主按钮同一套：`Tokens.bg` 当"墨"用）
                            color: Tokens.bg,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tabs[_centerIndex].label,
                          key: const Key('tab-center-label'),
                          style: TextStyle(
                            color: current == _centerIndex ? Tokens.accent : Tokens.text3,
                            fontSize: 11,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
}
