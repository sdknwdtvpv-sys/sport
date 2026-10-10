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


import 'glass_surface.dart';
import 'native_tab_bar.dart';
import 'theme.dart';


class AppTabBar extends StatelessWidget {
  const AppTabBar({
    super.key,
    required this.current,
    required this.onChanged,
  });

  final int current;
  final ValueChanged<int> onChanged;

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

  /// 正中那格的**图标大小**（2026-10-09，10.9 清单第 2b 条）。
  ///
  /// 用户原话：「底栏中间那个图标太割裂」—— 左右四个是线性图标，中间是
  /// "实心强调色圆 + 深墨图标"，两套视觉语言。现在那**颗圆整个去掉**，
  /// 中间与其余四个同一个画法，只靠两件事区分：
  ///   * **大一号**（26 vs 22）；
  ///   * 一点强调色（正中那格永远用强调色，不必等选中）。
  /// 两颗数都留在这一处，两端（Flutter 画 / 原生画）取同一个值。
  static const double centerIconSize = 26;

  /// 其余四格的图标大小（与 [centerIconSize] 一起构成"只差一号"）。
  static const double iconsize = 22;

  /// **每屏的滚动内容底部要留出的空间**（否则最后一项会被压在玻璃下面）。
  ///
  /// 只在**浮动**（iOS）时非零：Android 那条底栏仍然贴在内容下面，不需要留。
  /// ⚠️ 用 `GlassSurface.isSupportedPlatform` 判断 —— 与"哪一端浮动"是同一条判据，
  /// 两处各写一个条件迟早会漂（那就会出现"Android 上底部空出一大块"这种怪事）。
  static double reservedSpaceFor(BuildContext context) =>
      GlassSurface.isSupportedPlatform ? height + floatMargin + 8 : 0;

  /// **顺序**：`进步 / 开练 / 我`（2026-10-10，回 3 个 tab）。
  ///
  /// ⚠️ **2026-10-10 从 5 个收回 3 个**（用户 10.10 的设计评审 + `docs/plan-ux-2026-10-10.md`
  /// §一/§五-A）：`PRODUCT.md` §4 一直写着「**3 个 Tab，上限**」，而这两年长成了五个 ——
  /// 其中「数据」**就是**「进步」页里「全部数据 ›」推开的同一屏（靠 `asTab` 分叉），
  /// 「计划」在首页也有入口，而且「数据」的默认落地几乎是一张空页（真机实拍：
  /// 一行"选一个动作" + 一句"这个动作还没有记录"）。
  ///
  /// * **进步 / 我** 不变；
  /// * 中间那格从「训练」改名「**开练**」（动词）—— 它是"我要开始练"的入口，
  ///   不是叫"训练"的分类；首页那颗大按钮叫「开始训练」。
  /// * 用户 10.7 那条「训练放在最中间」的意图**继续成立**（仍然居中 + 强调色）。
  ///
  /// ⚠️ **下标语义**：`main.dart` 的 `_bodyFor` 与初始 tab（1）必须与这一份
  /// **逐条对齐**，错一条就是"点开练进了进步"。两处都有注释互相指着。
  static const List<({IconData icon, String label})> tabs =
      <({IconData icon, String label})>[
    (icon: Icons.show_chart, label: '进步'),
    (icon: Icons.fitness_center, label: '开练'),
    (icon: Icons.person_outline, label: '我'),
  ];

  /// 正中那一格（Flutter 那一支会把它画得大一号 + 强调色）。
  static const int _centerIndex = 1;

  /// 三个 Tab 的 SF Symbol（**只有 iOS 的原生底栏用**）。
  ///
  /// 为什么用 SF Symbol 而不是 Material 图标：那是系统底栏的语汇，
  /// VoiceOver、选中态的字重变化、可选的字形都与系统一致（v1.61 起就这么做了）。
  static const List<String> _sfSymbols = <String>[
    'chart.line.uptrend.xyaxis',
    'dumbbell.fill',
    'person',
  ];

  /// 正中那一格（**完全在栏内**）：一个**大一号的强调色图标** + 文字。
  ///
  /// 用户原话（真机反馈第二遍）：「只在**中间的图标**做点文章就行」；
  /// 2026-10-09（10.9 清单第 2b 条）又补了一句：「中间那个图标太割裂」——
  /// 于是那颗实心圆**整个去掉**（见 [centerIconSize] 的注释）。
  /// 文字与另外四格同一个字号、同一个位置（五格仍然等宽）。
  Widget _centerCell(int i) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            tabs[i].icon,
            key: const Key('tab-center-icon'),
            size: centerIconSize,
            color: Tokens.accent,
          ),
          const SizedBox(height: 3),
          Text(
            tabs[i].label,
            key: const Key('tab-center-label'),
            style: TextStyle(
              // ⚠️ 未选中用 text2（不是 text3）：tab 标签是「我在哪一屏」的唯一线索，
                        // 属于**功能性标签**（VI 计划 T0-3 的豁免规则）。
                        color: i == current ? Tokens.accent : Tokens.text2,
              fontSize: Tokens.fsMicro,
              height: Tokens.lhTight,
            ),
          ),
        ],
      );

  /// **苹果原生的 `UITabBar`**（2026-10-09，用户：「我想要苹果原生的 uitabbar」）。
  ///
  /// iOS 上底栏从"自己画一块 `UIGlassEffect`"换成系统那个真的 `UITabBar` ——
  /// 外观走 `UITabBarAppearance`、触摸/无障碍/长按自定义都由系统负责。
  /// 代价如实写在这里（细节见 `core/native_tab_bar.dart` 的文件头）：
  ///   * 五格**一视同仁** —— 原生的 `UITabBarItem` 没有"某一格更大"，
  ///     所以 v1.66.0 第 2b 条那颗"正中放大 + 强调色"在 iOS 上没有了；
  ///   * **离散选中**：原来"手指拖页面时胶囊跟手滑"（`dragIndex`）没有对应 API
  ///     —— 那个参数已经删掉了，页面照样能拖（Flutter 的 `PageView`），底栏松手后跳过去；
  ///   * 它只是 `UITabBar`、不是 `UITabBarController`，所以 iOS 26 那套"浮动胶囊 +
  ///     滚动自动收起"还拿不到（那要换整个外壳，见 `native_tab_bar.dart` §1）。
  Widget _nativeBar() => NativeTabBar(
        height: height,
        spec: nativeTabBarSpec(
          labels: <String>[for (final ({IconData icon, String label}) t in tabs) t.label],
          icons: _sfSymbols,
          selectedIndex: current,
        ),
        // ⚠️ 选中由**原生**回给这里，然后交给外壳（`onChanged`）——
        // 不要在本地自己改 `current`：真源在外壳的 `_tab`。
        onSelected: onChanged,
      );

  @override
  Widget build(BuildContext context) {
    // **iOS：苹果原生的 `UITabBar`**（2026-10-09 用户点名要的）。
    // Android 走下面那一支 Flutter 画法：通栏、贴底、保留 1px 顶边线 ——
    // **一个像素都不动**（这一条从 v1.61 起就没变过）。
    //
    // ⚠️ iOS 那一支换掉之后，这一支里**所有** iOS 分支（浮动、玻璃、跟手胶囊、
    // 正中那颗强调圆）都成了死代码 —— 一并删掉，别留着让人以为还在用。
    // 想看"以前 iOS 长什么样"：`git show v1.66.0:app/lib/core/app_tab_bar.dart`
    // 与 `docs/images/glass-probe-segment-variants.png`。
    if (GlassSurface.isSupportedPlatform) return _nativeBar();

    return Container(
      key: const Key('tab-bar'),
      height: height,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Tokens.line)),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < tabs.length; i++)
            // 正中那一格由 Flutter 画（`_centerCell`），五格仍然等宽 ——
            // 少一格会让"计划/我的"整体左移，一眼就不齐。
            if (i == _centerIndex)
              Expanded(
                child: GestureDetector(
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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        tabs[i].icon,
                        size: iconsize,
                        // ⚠️ 未选中用 text2（不是 text3）：tab 标签是「我在哪一屏」的唯一线索，
                        // 属于**功能性标签**（VI 计划 T0-3 的豁免规则）。
                        color: i == current ? Tokens.accent : Tokens.text2,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tabs[i].label,
                        style: TextStyle(
                          // ⚠️ 未选中用 text2（不是 text3）：tab 标签是「我在哪一屏」的唯一线索，
                        // 属于**功能性标签**（VI 计划 T0-3 的豁免规则）。
                        color: i == current ? Tokens.accent : Tokens.text2,
                          fontSize: Tokens.fsMicro,
                          height: Tokens.lhTight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
