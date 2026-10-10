/// 练了么 · **千分位与日期三档的唯一入口**（VI 计划 T1-7）
///
/// **为什么要有它**：数字与日期的写法曾经是"每个界面自己拼"的 ——
///   1. 千分位：`12,400` 与 `5400` 并存（同一个数值两种读法）；
///   2. 数字与单位：`2.5kg`（紧贴）与 `100 kg`（空格）并存；
///   3. 日期：`10 月 8 日` / `10月8日` / `10/8` / `10 / 8` 混着写。
///
/// 三件事都收在一处（`units.dart`），这个测试负责**钉住入口**：
///   * 三档日期各自的**字面形状**（空格、补零）；
///   * `sortable` 档的**字典序即时间序**（补零的真正理由）；
///   * 一条**机械扫描**：`lib` 里除了 `units.dart`，不许再有别的拼日期的实现。
///
/// 扫描器本身也要能被反向验证（喂一段假源码必须红）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/units.dart';

/// "自己拼日期"的判定：一行里**同时**出现
///   1. 取 `.year` / `.month` / `.day` 的插值（`${d.month}`），且
///   2. `月` / `日` / `/` 这三个"日期分隔符"里的任意一个。
///
/// 为什么要两条一起：只按 `month` 找会打到 `Key('week-${day.month}-${day.day}')`
/// 这种**标识**（它不给人看，也没有分隔符）；只按 `月` 找会打到正文里
/// "每月一次"这种普通文字。
bool buildsDateByHand(String line) {
  final int i = line.indexOf('//');
  final String code = i < 0 ? line : line.substring(0, i);
  if (!RegExp(r'\$\{[^}]*\.(year|month|day)\b').hasMatch(code)) return false;
  return code.contains('月') || code.contains('日') || code.contains('/');
}

/// `lib` 里所有自己拼日期的行（除 [skip] 之外）。
List<String> scanHandBuiltDates({String skip = 'core/units.dart'}) {
  final List<String> out = <String>[];
  for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final String path = e.path.replaceAll('\\', '/');
    if (path.endsWith(skip)) continue;
    final List<String> lines = e.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      if (buildsDateByHand(lines[i])) out.add('$path:${i + 1}: ${lines[i].trim()}');
    }
  }
  return out;
}

void main() {
  test('千分位与日期三档都由 units.dart 产出', () {
    // 千分位：五位数一眼能读（`12,400` 与 `5400` 并存的那种不一致收在这里）
    expect(withThousands(5400), '5,400');
    expect(withThousands(12400), '12,400');
    expect(withThousands(999), '999');
    expect(withThousands(1000000), '1,000,000');
    expect(withThousands(-5400), '-5,400');
    expect(formatVolume(5400, WeightUnit.kg), '5,400 kg');

    // 日期三档
    final DateTime d = DateTime(2026, 10, 8);
    expect(formatDateHuman(d), '10 月 8 日');
    // 带年份的那一种只给"离开 App 也要能读懂"的地方（分享卡导出图）
    expect(formatDateHuman(d, withYear: true), '2026 年 10 月 8 日');
    expect(formatDateAxis(d), '10/8');
    expect(formatDateSortable(d), '2026-10-08');

    // 补零：`sortable` 档是为了**排序**才补的，个位数月份/日期最容易漏
    final DateTime jan = DateTime(2026, 1, 5);
    expect(formatDateHuman(jan), '1 月 5 日'); // 人读的档**不补零**（1 月，不是 01 月）
    expect(formatDateAxis(jan), '1/5');
    expect(formatDateSortable(jan), '2026-01-05');

    // 字典序即时间序 —— 不补零就会把 10 月排到 2 月前面
    final List<String> keys = <String>[
      formatDateSortable(DateTime(2026, 10, 8)),
      formatDateSortable(DateTime(2026, 2, 1)),
      formatDateSortable(DateTime(2025, 12, 31)),
    ]..sort();
    expect(keys, <String>['2025-12-31', '2026-02-01', '2026-10-08']);
  });

  test('数字与单位之间恒一个半角空格（判据 2）', () {
    final List<String> hits = <String>[];
    for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final List<String> lines = e.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        // 注释也算：这条规矩是**文档级**的（`grep -rnE "[0-9]kg"` 就是判据原样）
        if (RegExp(r'[0-9]kg').hasMatch(lines[i])) {
          hits.add('${e.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(hits, isEmpty, reason: '数字与单位要隔一个空格：\n${hits.join('\n')}');

    // 三个格式化函数都带那个空格
    expect(formatWeight(60, WeightUnit.kg), '60 kg');
    expect(formatVolume(5400, WeightUnit.kg), '5,400 kg');
    expect(formatBodyWeight(85.5, BodyWeightUnit.kg), '85.5 kg');
  });

  test('lib 里没有第二处自己拼日期的实现（判据 3 的机械扫描）', () {
    final List<String> hits = scanHandBuiltDates();
    expect(hits, isEmpty,
        reason: '这些地方还在自己拼日期，改用 `formatDateHuman/Axis/Sortable`：\n${hits.join('\n')}');
  });

  test('反向自检：扫描器真的抓得住自己拼的日期', () {
    expect(buildsDateByHand("    return '\${d.month}/\${d.day}';"), isTrue);
    expect(buildsDateByHand("    _ => '\${missed.month} 月 \${missed.day} 日',"), isTrue);
    expect(buildsDateByHand("  return '\${day.month}月\${day.day}日';"), isTrue);
    // 标识（不给人看、没有分隔符）不算
    expect(buildsDateByHand("      key: Key('week-\${day.month}-\${day.day}'),"), isFalse);
    expect(buildsDateByHand("    final String key = formatDateSortable(d);"), isFalse);
    // 注释里的旧写法不算
    expect(buildsDateByHand("      // 原来是 '  \${d.month}/\${d.day}'"), isFalse);
    // 走入口的写法不算
    expect(buildsDateByHand('    return formatDateAxis(d);'), isFalse);
    expect(buildsDateByHand('    return \'\${formatDateHuman(t)} \${two(t.hour)} 删的\';'), isFalse);
  });
}
