/// 练了么 · **图标规格的纪律**（VI 计划 T1-3）
///
/// **为什么要有它**：改这一条之前全仓 **112 个字形、12 个尺寸值**，
/// 而"同一个动作在两屏用两个隐喻"这种事**不会报错、不会崩**，只会让图标失去表达能力。
/// 所以两条都要机械守着：
///   1. **尺寸只有 4 档**（`IconSpec.s/m/l/xl`），`lib` 里不许再出现 `size: <数字>`；
///   2. **语义映射表**：每条**两台配对**都要有、名字唯一、`iconOf` 认得出；
///      底栏那三条 SF Symbol 必须与表里的 `progress/today/profile` 一致（顺序也要）。
library;

import 'dart:io';

import 'package:flutter/material.dart' show IconData;
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/app_tab_bar.dart';
import 'package:lianleme/core/icon_spec.dart';

void main() {
  test('★ 图标尺寸只有 4 档（`lib` 里不许出现 `size: <数字>`）', () {
    final List<String> bad = <String>[];
    for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String path = e.path.replaceAll('\\', '/');
      if (path.endsWith('core/icon_spec.dart')) continue; // 定义处
      final List<String> lines = e.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final int c = lines[i].indexOf('//');
        final String code = c < 0 ? lines[i] : lines[i].substring(0, c);
        if (RegExp(r'size: [0-9]').hasMatch(code)) {
          bad.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(bad, isEmpty,
        reason: '改用 `IconSpec.s/m/l/xl`（只有 4 档）：\n${bad.join('\n')}');
    // 而且那 4 档就是这 4 个值
    expect(IconSpec.values, <double>[16, 20, 24, 40]);
  });

  test('★ 语义映射表：每条两台配对、名字唯一、都能取到', () {
    expect(kIconSemantics.length, greaterThanOrEqualTo(13),
        reason: '方案要求至少 13 组 —— 少了说明有语义没收敛');
    final Set<String> names = <String>{};
    for (final IconSemantic s in kIconSemantics) {
      expect(s.name.trim(), isNotEmpty);
      expect(names.add(s.name), isTrue, reason: '名字重复：${s.name}');
      expect(s.sf.trim(), isNotEmpty, reason: '${s.name} 少了 SF Symbol');
      // 取得到（取不到会抛 —— 名字漂了当场红）
      expect(iconOf(s.name), isNotNull);
      expect(sfSymbolOf(s.name), s.sf);
    }
    // 派生出来的两条列表长度**天然相等**（只有一份表，没有第二份可漂）
    expect(kSfSymbols.length, kIconSemantics.length);
    expect(kMaterialIcons.length, kIconSemantics.length);
  });

  test('★ 取一个没登记的名字要当场炸（不许静默给默认图标）', () {
    expect(() => iconOf('不存在的语义'), throwsArgumentError);
    expect(() => sfSymbolOf('不存在的语义'), throwsArgumentError);
  });

  test('★ 底栏那三个 SF Symbol 与语义表一致（顺序也要）', () {
    // 长度不同会崩、语义错位没人发现 —— 这条把两边钉在一起。
    final List<String> fromTable = <String>[
      sfSymbolOf('progress'),
      sfSymbolOf('today'),
      sfSymbolOf('profile'),
    ];
    expect(AppTabBar.tabs.map((({IconData icon, String label}) t) => t.label),
        <String>['进步', '开练', '我']);
    // 表里的 Material 侧也要与底栏用的那三个一致
    expect(AppTabBar.tabs.map((({IconData icon, String label}) t) => t.icon).toList(),
        <IconData>[iconOf('progress'), iconOf('today'), iconOf('profile')]);
    expect(fromTable, <String>['chart.line.uptrend.xyaxis', 'dumbbell.fill', 'person']);
  });

  test('★ 图标族只留一套（`_rounded` / `_sharp` / `_two_tone` → 0）', () {
    final List<String> bad = <String>[];
    for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final List<String> lines = e.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        if (RegExp(r'Icons\.[a-z_0-9]*(_rounded|_sharp|_two_tone)').hasMatch(lines[i])) {
          bad.add('${e.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(bad, isEmpty,
        reason: '三套族混用会让"同一个动作"看起来像两个动作：\n${bad.join('\n')}');
  });
}
