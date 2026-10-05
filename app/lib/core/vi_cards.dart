/// 练了么 · **卡片与统计块**（新 VI 的共用件）
///
/// 为什么要有这一层：新 VI 里几乎每一屏都是"卡片 + 大数字"，如果让每个页面各写一份，
/// 三十个页面就会有三十份卡片样式，改一次配色要改三十处 —— 这个仓库已经吃过一次同类的亏
/// （胶囊选项曾经是三份拷贝，同一个 bug 复制了三份，见 `core/pills.dart`）。
///
/// ⚠️ 与 `docs/interaction-spec.md` §5 的组件规格一一对应；改这里之前先改规格。
library;

import 'package:flutter/material.dart';

import 'theme.dart';

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
  });

  final String label;
  final String value;

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
        Text(value, style: Tokens.display(valueSize, weight: 700, letterSpacing: -0.5)),
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
/// 与 `choicePill` 的区别：那个是"多选一"的胶囊行，这个是**贴着图表的一小块**，
/// 所以更小、更密，且**必须按内容收缩**（同样的坑：带 alignment 的 Container 会撑满）。
class ViSegmented extends StatelessWidget {
  const ViSegmented({
    super.key,
    required this.labels,
    required this.current,
    required this.onChanged,
  });

  final List<String> labels;
  final int current;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Tokens.elevated,
          borderRadius: BorderRadius.circular(Tokens.rPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < labels.length; i++)
              GestureDetector(
                key: Key('seg-${labels[i]}'),
                onTap: () => onChanged(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: Tokens.s3, vertical: 5),
                  decoration: BoxDecoration(
                    color: i == current ? Tokens.accent : null,
                    borderRadius: BorderRadius.circular(Tokens.rPill),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: i == current ? Tokens.accentInk : Tokens.text2,
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// 细进度条（打卡进度、周目标那种）。**必须夹到 0..1**：调用方算错比例时
/// 宁可画满，也不要画到框外面去。
class ViProgressBar extends StatelessWidget {
  const ViProgressBar({super.key, required this.value, this.height = 6});

  final double value;
  final double height;

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
            child: Container(height: height, color: Tokens.accent),
          ),
        ],
      ),
    );
  }
}
