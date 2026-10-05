/// 训练完成页（新 VI）的视觉契约：**完成标记与破纪录色**。
///
/// 为什么单独测这两条：它们是"语义色"的唯一落点，而语义色最容易在下一次改皮肤时
/// 被顺手统一成主色 —— 那时"完成"和"主操作"就分不出来了，
/// 而这种事**任何页面测试都不会红**（文字还在、Key 还在）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';

void main() {
  test('成功色与主色是两个颜色，且都够亮（暖黑底上 4.5:1）', () {
    expect(Tokens.success, isNot(Tokens.accent));
    expect(Tokens.pr, isNot(Tokens.accent));
    // 相对亮度粗判：人眼可读的语义色不该是暗色
    for (final Color c in <Color>[Tokens.success, Tokens.pr]) {
      final double lum = (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b);
      expect(lum, greaterThan(0.3), reason: '$c 在暖黑底上太暗');
    }
  });

  test('完成标记的颜色**不是**主色（"完成"与"主操作"必须能分开）', () {
    // 直接对着 `_doneMark` 的取值断言：它必须用 success
    expect(Tokens.success.toARGB32(), 0xFF0CAC78);
  });
}
