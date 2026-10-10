/// 练了么 · **字阶的纪律**（VI 计划 T1-1）
///
/// **为什么要有它**：全仓曾经 **468 处 `fontSize:` 落在 21 个不同字号上**（规格只定义 7 级），
/// 行高 10 个字面量、字重 5 种、字距 8 种 —— 而 `theme.dart` 里有色值、间距、圆角，
/// **唯独没有字号**。所以"换 VI 只换掉了皮"：色值改一处全站生效，字号要改 178 处。
///
/// 这一组把三件事钉死：
///   1. `lib` 里（除 `theme.dart`）**不许再出现字号/行高/字重/字距的字面量**；
///   2. 字号**只许是那 10 级**，而且**每一级都真的有人在用**（没有死档）；
///   3. 扫描器本身要能被反向验证（喂一段假源码必须红）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 10 级字阶（与 `Tokens.fs*` 一一对应）。**加第 11 级要同时改这里**，否则测试会红。
const List<String> scale = <String>[
  'fsHero', // 30 训练屏大按钮上的值 / 引导页大标题
  'fsTitle', // 28 页面标题
  'fsNumL', // 24 大数字
  'fsNum', // 22 中等数字与标题
  'fsHeadline', // 20 卡片标题 / 输入框 / 分段控件
  'fsBody', // 17 正文
  'fsBodyS', // 16 次级正文
  'fsSub', // 15 说明文字
  'fsCap', // 13 小标签 / Tab / 胶囊
  'fsMicro', // 12 最小说明 / hint
];

/// 一行里有没有"排版字面量"（**先去掉行注释** —— 这个仓库的习惯是把旧写法留在注释里）。
bool hasTypeLiteral(String line) {
  final int i = line.indexOf('//');
  final String code = i < 0 ? line : line.substring(0, i);
  return RegExp(r'fontSize: [0-9]').hasMatch(code) ||
      RegExp(r'height: 1\.[0-9]').hasMatch(code) ||
      RegExp(r'letterSpacing: -?[0-9]').hasMatch(code) ||
      RegExp(r'FontWeight\.w[0-9]').hasMatch(code);
}

/// 一行里用了哪几级字号（`Tokens.fsXxx`）。
List<String> scaleNamesIn(String line) =>
    RegExp(r'Tokens\.(fs[A-Za-z]+)')
        .allMatches(line)
        .map((RegExpMatch m) => m.group(1)!)
        .toList();

List<String> _scan(bool Function(String line) test,
    {bool skipTheme = true, List<String>? collect}) {
  final List<String> out = <String>[];
  for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final String path = e.path.replaceAll('\\', '/');
    if (skipTheme && path.endsWith('core/theme.dart')) continue;
    final List<String> lines = e.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      if (test(lines[i])) out.add('$path:${i + 1}: ${lines[i].trim()}');
      if (collect != null) collect.addAll(scaleNamesIn(lines[i]));
    }
  }
  return out;
}

void main() {
  test('★ 全站字号只用令牌里的 10 级（不许再写字面量）', () {
    final List<String> bad = _scan(hasTypeLiteral);
    expect(bad, isEmpty,
        reason: '这些地方还在自己写字号/行高/字重/字距，改用 `Tokens.fs*/lh*/fw*/ls*`：\n${bad.join('\n')}');
  });

  test('★ 10 级**每一级都有人在用**（没有死档，也没有第 11 级）', () {
    final List<String> used = <String>[];
    _scan((String _) => false, collect: used);
    final Set<String> distinct = used.toSet();
    expect(distinct.difference(scale.toSet()), isEmpty,
        reason: '用了字阶表之外的档位：${distinct.difference(scale.toSet())}');
    for (final String name in scale) {
      expect(distinct.contains(name), isTrue,
          reason: '`Tokens.$name` 一次都没被用 —— 没有使用点的令牌就是漂移的入口');
    }
    expect(distinct.length, scale.length);
  });

  test('★ 反向自检：扫描器真的抓得住字面量', () {
    expect(hasTypeLiteral('style: TextStyle(fontSize: 13, height: 1.4),'), isTrue);
    expect(hasTypeLiteral('fontWeight: FontWeight.w500,'), isTrue);
    expect(hasTypeLiteral('letterSpacing: -0.5,'), isTrue);
    // 注释里的旧写法不算（这个仓库的注释习惯就是留着旧值）
    expect(hasTypeLiteral('// 原来是 fontSize: 13 与 height: 1.4'), isFalse);
    // 令牌写法不算
    expect(hasTypeLiteral('style: TextStyle(fontSize: Tokens.fsCap, height: Tokens.lhSnug),'), isFalse);
  });

  test('★ `theme.dart` 里的 10 级就是这 10 个名字', () {
    final String theme = File('lib/core/theme.dart').readAsStringSync();
    for (final String name in scale) {
      expect(theme.contains('double $name ='), isTrue,
          reason: '`theme.dart` 里少了 `$name`');
    }
  });
}
