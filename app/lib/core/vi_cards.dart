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
import 'glass_surface.dart';
import 'theme.dart';

/// `Color` → `#RRGGBB`（原生按这个解析）
String _hexOf(Color c) {
  final int v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// 卡片：`surface` 底 + **白 6% 描边** + `rCard` 圆角。
///
/// 描边用半透明白而不是实心灰，是界面稿的做法：叠在任何一层背景上都自动对
/// （实心灰在换底色时要逐个重算 —— 这个坑 2026-10-05 换色时刚踩过）。
class ViCard extends StatelessWidget {
  const ViCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Tokens.s4),
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
    this.valueSize = 28,
    this.valueKey,
  });

  final String label;
  final String value;

  /// 挂在**数值那行**上的 Key（测试要按它读数字，例：`progress-week-volume`）。
  final Key? valueKey;

  /// 涨跌文案（例：`+18%`）。为空就不占位。
  final String? delta;

  /// 涨跌的方向：true 向上（绿）、false 向下（红）、null 中性（灰）。
  final bool? deltaUp;

  final double valueSize;

  @override
  Widget build(BuildContext context) {
    final bool? up = deltaUp;
    final Color deltaColor = up == null
        ? Tokens.text3
        : (up ? const Color(0xFF5FD08A) : Tokens.danger);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(color: Tokens.text2, fontSize: 13, height: 1.3),
        ),
        const SizedBox(height: Tokens.s2),
        Text(value,
            key: valueKey,
            style: Tokens.display(valueSize, weight: 700, letterSpacing: -0.5)),
        if (delta != null) ...<Widget>[
          const SizedBox(height: Tokens.s1),
          Text(
            delta!,
            style: TextStyle(color: deltaColor, fontSize: 12, height: 1.3),
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
  });

  final List<String> labels;
  final int current;
  final ValueChanged<int> onChanged;

  /// iOS 上每格的宽度（等宽）。非 iOS 不生效。
  final double itemWidth;

  /// iOS 上分段控件的高度：胶囊圆角 = 高度 / 2。
  static const double _glassHeight = 32;

  @override
  Widget build(BuildContext context) {
    final bool glass = GlassSurface.isSupportedPlatform;
    final Widget row = GlassSegmentedRow(
      count: labels.length,
      index: current,
      itemWidth: itemWidth,
      height: _glassHeight,
      itemBuilder: _item,
      // 字交给原生画（玻璃里面）：Flutter 那份在玻璃背后会被折射出第二份虚影
      labels: labels,
      selectedColor: _hexOf(Tokens.text),
      unselectedColor: _hexOf(Tokens.text2),
      labelFontSize: 12,
    );

    if (!glass) {
      // 老样子：实心胶囊行，按内容收缩（Android 一个像素都不动）
      return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Tokens.elevated,
          borderRadius: BorderRadius.circular(Tokens.rPill),
        ),
        child: row,
      );
    }

    return row;
  }

  Widget _item(int i, bool glass) {
    final bool on = i == current;
    // 选中项的字色：非 iOS 是"实心 accent 胶囊上的深墨"；玻璃上没有实心底，
    // 玻璃自己就是那块亮色，字反过来要用最亮的 —— 否则深字压在浅玻璃上会糊。
    final Text label = Text(
      labels[i],
      style: TextStyle(
        color: on ? (glass ? Tokens.text : Tokens.accentInk) : Tokens.text2,
        fontSize: 12,
        height: 1.2,
        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
      ),
    );

    return GestureDetector(
      key: Key('seg-${labels[i]}'),
      // 玻璃那支：整格都要能点（否则只有字上那几像素是热区）
      behavior: glass ? HitTestBehavior.opaque : HitTestBehavior.deferToChild,
      onTap: () => onChanged(i),
      child: glass
          ? Center(child: label)
          : Container(
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
          Container(height: height, color: Tokens.elevated),
          FractionallySizedBox(
            widthFactor: v,
            child: Container(height: height, color: color),
          ),
        ],
      ),
    );
  }
}
