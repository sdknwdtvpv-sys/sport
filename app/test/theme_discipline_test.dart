/// 练了么 · **设计令牌的纪律**（VI 计划 T0-4 / 后续批次在这条线上继续加）
///
/// **为什么要有它**：`theme.dart` 里的令牌本身不会用错 —— 错的是**用法**：
/// 拿页面级的最弱线去描卡片边、拿卡片描边去做输入框边界……这些都不会报错、
/// 也不会崩，只会让层级慢慢糊掉。所以纪律必须是**机械的**。
///
/// 这个文件是**源码扫描**（不是 widget 测试）：判据都以"某个表达式在 `app/lib`
/// 里出现几次"的形式写死，与 `docs/plan-vi-2026-10-10.md` 里的 grep 判据同源。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 扫 `app/lib` 下的全部 Dart 源码，返回命中 [pattern] 的行（`路径:行号: 内容`）。
List<String> _hits(RegExp pattern) {
  final List<String> out = <String>[];
  for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final List<String> lines = e.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      if (pattern.hasMatch(lines[i])) out.add('${e.path}:${i + 1}: ${lines[i].trim()}');
    }
  }
  return out;
}

void main() {
  test('★ `hair` 只做上下分隔，不许用来描一整圈边（`Border.all`）', () {
    // hair 是最弱一级（对 bg 1.30:1），描卡片边会让卡片"没有边"——
    // 那正是 T0-4 要修的毛病，别用新令牌把它带回来。
    final List<String> bad = _hits(RegExp(r'Border\.all\([^)]*Tokens\.hair'));
    expect(bad, isEmpty, reason: 'hair 不是描边色：\n${bad.join('\n')}');
  });

  test('★ 半透明线全部下线（半透明只有一档可见度，做不出层级）', () {
    final List<String> bad = _hits(RegExp(r'0x0FFFFFFF|0x14FFFFFF'));
    expect(bad, isEmpty,
        reason: '这些是旧的 line / lineStrong 字面量，现在有三级实色：\n${bad.join('\n')}');
  });

  test('★ 三级线各自只出现在该出现的层上', () {
    // 这条是"文档里写下来的规矩"的机械版：
    //   hair       → 页面级长分隔（bg 上）
    //   line       → 卡片描边 / 卡片内行分隔
    //   lineStrong → 功能性边界（输入框、胶囊、分段控件外壳）
    // 眼下能机械判定的只有"hair 不许上 elevated/sheet"（它是给 bg 用的最弱线）。
    final List<String> bad = <String>[];
    for (final FileSystemEntity e in Directory('lib/core').listSync()) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String src = e.readAsStringSync();
      // `hair` 出现在同一个表达式里搭配 elevated/sheet 的写法 → 可疑
      if (RegExp(r'Tokens\.hair[^;]*Tokens\.(elevated|sheet)').hasMatch(src)) {
        bad.add(e.path);
      }
    }
    expect(bad, isEmpty, reason: 'hair 是给 bg 用的最弱线：\n${bad.join('\n')}');
  });
}
