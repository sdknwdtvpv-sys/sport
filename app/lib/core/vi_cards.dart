/// 练了么 · **卡片与统计块**（新 VI 的共用件）
///
/// 为什么要有这一层：新 VI 里几乎每一屏都是"卡片 + 大数字"，如果让每个页面各写一份，
/// 三十个页面就会有三十份卡片样式，改一次配色要改三十处 —— 这个仓库已经吃过一次同类的亏
/// （胶囊选项曾经是三份拷贝，同一个 bug 复制了三份，见 `core/pills.dart`）。
///
/// ⚠️ 与 `docs/interaction-spec.md` §5 的组件规格一一对应；改这里之前先改规格。
library;

import 'package:flutter/material.dart';

import 'glass_segmented.dart';
import 'native_hex.dart';
import 'native_segmented.dart';
import 'glass_surface.dart';
import 'theme.dart';

/// 卡片：`surface` 底 + **白 6% 描边** + `rCard` 圆角。
///
/// 描边用半透明白而不是实心灰，是界面稿的做法：叠在任何一层背景上都自动对
/// （实心灰在换底色时要逐个重算 —— 这个坑 2026-10-05 换色时刚踩过）。
class ViCard extends StatelessWidget {
  const ViCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Tokens.s5),
    this.glow = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// 右上角那团暖光（界面稿里每张卡都有一点）。默认关：一屏里最多点亮一张。
  final bool glow;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
        border: Border.all(color: Tokens.line),
      ),
      child: glow
          ? Stack(
              children: <Widget>[
                // 角落的暖光：一块圆形渐变，不参与布局（Positioned.fill 里自己定位）
                Positioned(
                  right: -40,
                  top: -40,
                  child: IgnorePointer(
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: <Color>[
                            Tokens.accent.withValues(alpha: 0.18),
                            Tokens.accent.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                child,
              ],
            )
          : child,
    );
    if (onTap == null) return box;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: box,
    );
  }
}

/// 统计块：**一个大数字 + 一行标签**（可选一行涨跌）。
///
/// 数字走 [Tokens.display]（Oswald）—— 中文标签自动回落系统字体，混排正是界面稿的做法。
/// `value` 允许带单位（例：`12.4 t`），它会**整串**用展示字体：数字与拉丁字母都归 Oswald，
/// 中文单位（例：`次`）回落系统字体，不影响读。
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.delta,
    this.deltaUp,
    this.deltaKey,
    this.valueSize = 28,
    this.valueKey,
  });

  final String label;
  final String value;

  /// 挂在**数值那行**上的 Key（测试要按它读数字，例：`progress-week-volume`）。
  final Key? valueKey;

  /// 涨跌文案（例：`+18%`）。为空就不占位。
  final String? delta;

  /// 挂在**涨跌那一行**上的 Key（周期对比的测试按它读那句话，
  /// 例：`progress-delta-volume`）。`delta` 为空时它自然不出现。
  final Key? deltaKey;

  /// 涨跌的方向：true 向上（绿）、false 向下（红）、null 中性（灰）。
  final bool? deltaUp;

  final double valueSize;

  @override
  Widget build(BuildContext context) {
    final bool? up = deltaUp;
    final Color deltaColor = up == null
        ? Tokens.text3
        : (up ? Tokens.success : Tokens.danger);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(color: Tokens.text2, fontSize: Tokens.fsCap, height: Tokens.lhSnug),
        ),
        const SizedBox(height: Tokens.s2),
        Text(value,
            key: valueKey,
            style: Tokens.display(valueSize, weight: 700, letterSpacing: Tokens.lsTight)),
        if (delta != null) ...<Widget>[
          const SizedBox(height: Tokens.s1),
          Text(
            delta!,
            key: deltaKey,
            style: TextStyle(color: deltaColor, fontSize: Tokens.fsMicro, height: Tokens.lhSnug),
          ),
        ],
      ],
    );
  }
}

/// 分段选择（**周 / 月 / 年**）：界面稿里每个图表右上角都是它。
///
/// 与 `choicePill` 的区别：那个是"多选一"的胶囊行，这个是**贴着图表的一小块**。
///
/// ## iOS 26：底托一块玻璃 + 选中一块玻璃，两块"溶"在一起
/// 见 `core/glass_segmented.dart`。融合的前提是**条目等宽**，所以 iOS 上改成等分
/// （用户 2026-10-06 拍板："融在一起的这个我觉得挺好的 要做并且全局所有涉及到
/// 类似于切换 tab 的都做"）。**非 iOS 一个像素都不动**（仍然是按内容收缩的实心胶囊）。
///
/// ⚠️ 等宽要有个宽度，`itemWidth` 就是它 —— 默认 56 够装三个汉字（最长的标签是
/// "肌肉量"）。宽度必须是**定值**：原生侧按 `frame.width / count` 切格子，
/// 给它一个"内容撑开"的宽度就等于把几何交给两次布局去对齐，迟早错位。
class ViSegmented extends StatelessWidget {
  const ViSegmented({
    super.key,
    required this.labels,
    required this.current,
    required this.onChanged,
    this.itemWidth = 56,
    this.itemKey,
  });

  final List<String> labels;
  final int current;
  final ValueChanged<int> onChanged;

  /// iOS 上每格的宽度（等宽）。非 iOS 不生效。
  final double itemWidth;

  /// 每一格的 `Key`（**只有非 iOS 那一支用得上** —— iOS 的格子在 UIKit 里，没有 key）。
  ///
  /// 默认 `Key('seg-<标签>')`。单位那种"标签是给人看的、key 是给测试用的"地方要自己给：
  /// 体重的三个单位标签是 `kg / lb / 斤`，而测试找的是 `body-unit-jin`（wire 值）。
  final Key Function(int index)? itemKey;

  /// 分段控件的高度（两支都用）：iOS 上就是原生控件的框高，圆角 = 高度 / 2。
  static const double _glassHeight = 32;

  @override
  Widget build(BuildContext context) {
    // **iOS：苹果原生的 `UISegmentedControl`**（2026-10-09，用户看完底栏之后问的
    // 「其他的切换选项能不能也做成这个效果呢，比如说像周 月 年的那个调整」）。
    // 这一支覆盖了 5 处调用点（周/月/年、按动作看/按时间看、计划三视图、
    // 身体数据页的指标切换、分享卡预览）。
    //
    // ⚠️ 与旧那条玻璃支路的差别不只是"更像苹果"：**触摸归原生了** ——
    // Flutter 的测试点不到它（合成事件进不了 UIKit），要驱动它得走业务入口
    // （底栏那件事已经踩过一次，见 `main.dart` 的 `debugSwitchTab`）。
    if (GlassSurface.isSupportedPlatform) {
      return NativeSegmented(
        width: itemWidth * labels.length,
        height: _glassHeight,
        spec: NativeSegmentedSpec(
          labels: labels,
          selectedIndex: current,
          // 选中胶囊 = **强调色**（用户 2026-10-10 拍板：「橙色」）。
          // 底色是橙的，字就必须是 `accentInk` —— 橙底 + 白字只有 3.08:1，
          // 小字不合规（`docs/interaction-spec.md` 那条对比度规则）。
          selectedColor: hexOfColor(Tokens.accentInk),
          unselectedColor: hexOfColor(Tokens.text2),
          selectedTint: hexOfColor(Tokens.accent),
          fontSize: Tokens.fsMicro,
        ),
        onChanged: onChanged,
      );
    }

    // 非 iOS（Android / 桌面 / widget 测试）：老样子 —— 实心胶囊行，按内容收缩。
    //
    // ⚠️ iOS 那条玻璃支路（`GlassSegmentedRow`）**已经不用了**：2026-10-09 起
    // 这一组件在 iOS 上走上面的原生 `UISegmentedControl`。所以这里不再传
    // `labels` / `selectedColor` 那些"交给原生画字"的参数 —— 那些参数只有玻璃支路要。
    // （想看以前长什么样：`git show v1.66.0:app/lib/core/vi_cards.dart`）
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Tokens.elevated,
        borderRadius: BorderRadius.circular(Tokens.rPill),
      ),
      child: GlassSegmentedRow(
        count: labels.length,
        index: current,
        itemWidth: itemWidth,
        height: _glassHeight,
        itemBuilder: _item,
      ),
    );
  }

  Widget _item(int i, bool glass) {
    final bool on = i == current;
    final Text label = Text(
      labels[i],
      style: TextStyle(
        // ⚠️ 这一支只在**非 iOS** 上跑（选中 = 实心 accent 胶囊 + 深墨字），
        // 所以这里不再有"玻璃上要用最亮的字"那种分叉
        color: on ? Tokens.accentInk : Tokens.text2,
        fontSize: Tokens.fsMicro,
        height: Tokens.lhTight,
        fontWeight: on ? Tokens.fwBold : Tokens.fwStrong,
      ),
    );

    return GestureDetector(
      key: itemKey?.call(i) ?? Key('seg-${labels[i]}'),
      behavior: HitTestBehavior.deferToChild,
      onTap: () => onChanged(i),
      child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.s3, vertical: 5),
              decoration: BoxDecoration(
                color: on ? Tokens.accent : null,
                borderRadius: BorderRadius.circular(Tokens.rPill),
              ),
              child: label,
            ),
    );
  }
}

/// 细进度条（打卡进度、周目标那种）。**必须夹到 0..1**：调用方算错比例时
/// 宁可画满，也不要画到框外面去。
class ViProgressBar extends StatelessWidget {
  const ViProgressBar({
    super.key,
    required this.value,
    this.height = 6,
    this.color = Tokens.accent,
  });

  final double value;
  final double height;

  /// 进度条的填充色。**默认是主色**，只有"四条收集线并排"那种场合才传别的色
  /// （A1 的线奖励，2026-10-06）—— 一屏里出现两条不同颜色的进度条而没有任何理由，
  /// 读起来就是"这两个不是一回事"，所以别随手传。
  final Color color;

  @override
  Widget build(BuildContext context) {
    final double v = value.isNaN ? 0 : value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Stack(
        children: <Widget>[
          // 进度槽 = 「抬起来的材料」（T1-2）。它只在卡片里用，不能在弹层里（对 sheet 只有 1.10:1）
          Container(height: height, color: Tokens.lift),
          FractionallySizedBox(
            widthFactor: v,
            child: Container(height: height, color: color),
          ),
        ],
      ),
    );
  }
}
