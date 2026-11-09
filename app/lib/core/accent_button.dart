/// 练了么 · **主按钮**（v2.2.0，唯一一处 `accentButton` 渐变 + `ctaGlow`）
///
/// 为什么要有它：审计 O3 说 `Tokens.accentButton` 定义了 0 处使用，五个主操作
/// 全是平涂大橙块 —— 这是最重的"模板感"。把渐变、1px 高光/暗边、按压缩放
/// 收在一个组件里，页面不再各写一份，也不会有人再手写阴影。
library;

import 'package:flutter/material.dart';

import 'motion.dart';
import 'reduced_motion.dart';
import 'theme.dart';

class AccentButton extends StatefulWidget {
  const AccentButton({
    super.key,
    required this.label,
    this.onPressed,
    this.onLongPress,
    this.height = Tokens.hPrimary,
    this.labelSize = Tokens.fsHero,
    this.icon = true,
    this.labelKey,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final double height;
  final double labelSize;

  /// 末尾那颗 ✓（首页「开始训练」也用它，表示"这一下会写进去"）。
  final bool icon;

  /// 接 `button-label` 之类既有测试 key 的位置。
  final Key? labelKey;

  final String? semanticLabel;

  @override
  State<AccentButton> createState() => _AccentButtonState();
}

class _AccentButtonState extends State<AccentButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onPressed != null;
    final Widget body = Container(
      height: widget.height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: enabled ? Tokens.accentButton : null,
        color: enabled ? null : Tokens.surfaceHi,
        borderRadius: BorderRadius.circular(Tokens.rPill),
        boxShadow: enabled ? Tokens.ctaGlow : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Tokens.rPill),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Container(
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Text(
                        widget.label,
                        key: widget.labelKey,
                        style: TextStyle(
                          color: enabled ? Tokens.accentInk : Tokens.text3,
                          fontSize: widget.labelSize,
                          fontWeight: Tokens.fwBold,
                          letterSpacing: Tokens.lsTight,
                          fontFeatures: Tokens.tabular,
                        ),
                      ),
                      if (widget.icon) ...<Widget>[
                        const SizedBox(width: Tokens.s2),
                        Text('✓',
                            style: TextStyle(
                                color: enabled ? Tokens.accentInk : Tokens.text3,
                                fontSize: Tokens.fsNumL,
                                fontWeight: Tokens.fwBold)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // 1px 暖白高光 / 底部暗边（BoxShadow 不能 inset，用两条线表达）
            if (enabled) ...<Widget>[
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Container(height: 1, color: Tokens.ctaHighlightLine),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(height: 1, color: Tokens.ctaBottomLine),
              ),
            ],
          ],
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        onLongPress: widget.onLongPress,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: reducedMotion(context) ? Duration.zero : Motion.instant,
          curve: Motion.press,
          child: body,
        ),
      ),
    );
  }
}
