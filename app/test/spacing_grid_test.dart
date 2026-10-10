/// 练了么 · **4pt 栅格与卡片内边距**（VI 计划 T1-9）
///
/// **4pt 栅格的全部价值在于"任何两个元素之间的距离都能被 4 整除"**：
/// 一旦允许 7pt 与 6pt 存在，下一个人就会写 5pt 与 3pt，栅格就不再是栅格。
/// 这一条之前全仓有 **18 处**非 4 倍数的 `SizedBox`（含休息进度条与它标签之间那个 7pt）。
///
/// 同时钉住"卡片/屏幕的内边距只有一个值"（`Tokens.s5`）：
///   * `ViCard` 的默认内边距是 s5（改一处、全站的卡跟着走）；
///   * 手搓的卡片（`Container` + `surface` + `rCard`）也必须是 s5 ——
///     否则 ListTile 主题给的行内边距（T1-8 的 s5）与卡内文字就差 4pt，同一个毛病只是低了一层；
///   * 唯一例外是**输入框的 `contentPadding`**（`fields.dart` 与个别 `TextField`）：
///     那是"框里的字离框边多远"，与卡片内边距不是同一件事，规则按 `contentPadding` 区分。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 计划里点名的那些"非 4 倍数"（`10`、`14`、`18` 也算：它们不是间距该用的档位）。
const List<String> kBadGrid = <String>['2', '3', '5', '6', '7', '10', '14', '18'];

/// 一行里有没有非标的 `SizedBox` 间距。
bool hasOffGridSizedBox(String line) {
  final int i = line.indexOf('//');
  final String code = i < 0 ? line : line.substring(0, i);
  final RegExpMatch? m =
      RegExp(r'SizedBox\((?:width|height): ([0-9]+)').firstMatch(code);
  if (m == null) return false;
  return kBadGrid.contains(m.group(1));
}

/// 一行里有没有"不是输入框内边距"的 `EdgeInsets.all(Tokens.s4)`。
bool hasOffGridCardPadding(String line) {
  final int i = line.indexOf('//');
  final String code = i < 0 ? line : line.substring(0, i);
  if (!code.contains('EdgeInsets.all(Tokens.s4)')) return false;
  return !code.contains('contentPadding');
}

List<String> scan(bool Function(String line) test) {
  final List<String> out = <String>[];
  for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final List<String> lines = e.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      if (test(lines[i])) out.add('${e.path}:${i + 1}: ${lines[i].trim()}');
    }
  }
  return out;
}

void main() {
  test('间距只有 4 的倍数：非标 SizedBox 一处都不许有（判据 1）', () {
    final List<String> bad = scan(hasOffGridSizedBox);
    expect(bad, isEmpty,
        reason: '这些间距不是 4 的倍数（2→4 / 3→4 / 6→8 / 7→8）：\n${bad.join('\n')}');
  });

  test('卡片与屏幕的内边距只有一个值 s5（判据 2 收紧版）', () {
    final List<String> bad = scan(hasOffGridCardPadding);
    expect(bad, isEmpty,
        reason: '卡片内边距只许 `Tokens.s5`（输入框的 `contentPadding` 例外）：\n${bad.join('\n')}');
    // `fromLTRB` 那种写法也一起钉：整屏级与卡片级都只许 s5 起头
    final List<String> ltrb = <String>[];
    for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final List<String> lines = e.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final int c = lines[i].indexOf('//');
        final String code = c < 0 ? lines[i] : lines[i].substring(0, c);
        if (RegExp(r'fromLTRB\(Tokens\.(s3|s4|s6)').hasMatch(code)) {
          ltrb.add('${e.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(ltrb, isEmpty, reason: '整屏/卡片边距只许从 `Tokens.s5` 起：\n${ltrb.join('\n')}');
  });

  test('反向自检：扫描器真的抓得住', () {
    expect(hasOffGridSizedBox('const SizedBox(height: 7),'), isTrue);
    expect(hasOffGridSizedBox('const SizedBox(width: 6),'), isTrue);
    expect(hasOffGridSizedBox('const SizedBox(height: 10),'), isTrue);
    expect(hasOffGridSizedBox('const SizedBox(height: 8),'), isFalse);
    expect(hasOffGridSizedBox('const SizedBox(width: 56),'), isFalse,
        reason: '56 是**元素宽**（日期那一格），不是间距');
    expect(hasOffGridSizedBox('const SizedBox(height: 90),'), isFalse,
        reason: '90 是趋势卡的高度，不是间距');
    expect(hasOffGridSizedBox('// 原来是 SizedBox(height: 7)'), isFalse);

    expect(hasOffGridCardPadding('padding: const EdgeInsets.all(Tokens.s4),'), isTrue);
    expect(hasOffGridCardPadding('contentPadding: const EdgeInsets.all(Tokens.s4),'), isFalse,
        reason: '输入框的 contentPadding 是另一件事');
    expect(hasOffGridCardPadding('padding: const EdgeInsets.all(Tokens.s5),'), isFalse);
  });
}
