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

import 'package:flutter/material.dart';
import 'package:lianleme/core/theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// 扫 `app/lib` 下的 Dart 源码（**跳过 `core/theme.dart`** —— 它是令牌的定义处，
/// 那些"不许在别处出现"的东西本来就要写在它里面），返回命中 [pattern] 的行。
List<String> _hits(RegExp pattern) {
  final List<String> out = <String>[];
  for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    if (e.path.replaceAll('\\', '/').endsWith('core/theme.dart')) continue;
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

  test('★ `theme.dart` 之外不许出现 `Color(0x`（色值只有一个真源）', () {
    final List<String> bad = <String>[];
    for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (e.path.replaceAll('\\', '/').endsWith('core/theme.dart')) continue;
      final List<String> lines = e.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('Color(0x')) {
          bad.add('${e.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(bad, isEmpty,
        reason: '新色值要先进 theme.dart（否则它一定会漂）：\n${bad.join('\n')}');
  });

  test('★ `theme.dart` 之外不许出现 `BoxShadow(`（辉光只有一处实现）', () {
    final List<String> bad = _hits(RegExp(r'BoxShadow\('));
    expect(bad, isEmpty,
        reason: '改用 Tokens.glow(...) —— 原来三处各写一份，同一个"发光"有三种半径：\n${bad.join('\n')}');
  });

  test('★ 语义色只许出现在白名单文件里（越界当场红）', () {
    // ⚠️ **这张白名单是按现状写的**（批次 0/1 不夹带语义色越界的清理，那是批次 3）。
    // 所以它现在的价值是"拦住新增的越界"，而不是"证明现在没有越界"。
    // 每条后面标了"待收窄"的就是已知越界，批次 3 要清。
    // ⚠️ **这张白名单是按现状写的**（批次 0/1 不夹带语义色越界的清理，那是批次 3）。
    // 所以它现在的价值是"拦住**新增**的越界"，而不是"证明现在没有越界" ——
    // 每条标了 `待收窄` 的就是**已知越界**，批次 3 要清（都记进了 `docs/plan-vi-2026-10-10.md`）。
    const Map<String, List<String>> whitelist = <String, List<String>>{
      'Tokens.danger': <String>[
        // —— 合法：删除 / 不可逆 ——
        'lib/features/profile/data_tools_screen.dart',   // 删除全部数据
        'lib/features/account/account_screen.dart',      // 注销账号
        'lib/features/backup/cloud_backup_screen.dart',  // 关闭云备份（不可逆）
        'lib/main.dart',                                 // 丢弃这半截训练
        'lib/features/profile/trash_screen.dart',
        // —— 待收窄（批次 3）——
        'lib/core/vi_cards.dart',                        // `StatTile` 的"跌"：那是**方向色**，不是删除色
        'lib/features/progress/badges.dart',             // 「探索发现」那一档的**分类配色**（纯借用）
        'lib/features/profile/privacy_policy_screen.dart', // 法律条款的**强调**
        'lib/features/profile/collection_list_screen.dart', // 同上（个人信息清单）
      ],
      'Tokens.pr': <String>[
        // —— 合法：破纪录 ——
        'lib/features/workout/workout_screen.dart',       // 训练屏的"历史最佳"
        'lib/features/progress/progress_screen.dart',      // PR 墙
        'lib/features/summary/share_card.dart',            // 分享卡上的纪录
        'lib/features/summary/workout_summary_screen.dart', // 完成页的破纪录块
        // —— 待收窄（批次 3）——
        'lib/features/progress/badges.dart',               // 传说档的徽章色（借用）
        'lib/features/notifications/notification_visuals.dart', // 通知图标的"纪录"类（借用）
        'lib/features/backup/cloud_backup_screen.dart',    // 云备份的"同步完成"（借用）
      ],
    };
    final List<String> bad = <String>[];
    for (final MapEntry<String, List<String>> e in whitelist.entries) {
      for (final String hit in _hits(RegExp('${e.key}\\b'))) {
        final String path = hit.split(':').first;
        if (!e.value.contains(path)) bad.add('${e.key} 越界 → $hit');
      }
    }
    expect(bad, isEmpty, reason: '语义色越界：\n${bad.join('\n')}');
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

  // ── 转圈圈的颜色（VI 计划 §批次 4 的"保留"那一条，2026-10-10）────────────────
  //
  // ⚠️ 计划里写着"21 处 `CircularProgressIndicator` 里至少 3 处没传色，在暖黑底上会取
  // Material 默认的紫/青 —— 这是一个真 bug，值得单独一条 S 级任务"。
  // **实测这条不成立**：`buildAppTheme()` 的 `ColorScheme` 把 `primary` 覆盖成了 `Tokens.accent`，
  // 而 `CircularProgressIndicator` 的默认色正是 `progressIndicatorTheme.color ?? colorScheme.primary`
  // —— 21 处里只有 2 处显式传色（都是 accent），其余全是橙的。
  // 结论写在这里 + 两条断言钉住**机制**：谁把 `primary` 改掉，这一条就会红。
  testWidgets('转圈圈的颜色来自 colorScheme.primary（= accent），不是 Material 默认色',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(body: Center(child: CircularProgressIndicator())),
    ));
    final ThemeData theme =
        Theme.of(tester.element(find.byType(CircularProgressIndicator)));
    expect(theme.colorScheme.primary, Tokens.accent,
        reason: '21 处转圈圈里只有 2 处显式传色，其余全靠这一条 —— primary 一变，它们全变紫');
    expect(theme.progressIndicatorTheme.color ?? theme.colorScheme.primary,
        Tokens.accent);
  });

  test('转圈圈要么不传色，要么传 accent（不许有自己的颜色）', () {
    // ⚠️ **要看的是它自己那对括号里写的东西**，不是"接下来几行"：
    // 第一版按"往后 4 行"扫，把隔壁 `Icon(..., color: Tokens.text3)` 当成了转圈圈的颜色
    // （`body_metric_screen.dart:447` 的转圈圈本身压根没传色）—— 测试当场把这误报抓了出来。
    String argsOf(String src, int open) {
      int depth = 0;
      for (int i = open; i < src.length; i++) {
        if (src[i] == '(') depth++;
        if (src[i] == ')') {
          depth--;
          if (depth == 0) return src.substring(open, i + 1);
        }
      }
      return src.substring(open);
    }

    final List<String> bad = <String>[];
    for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String src = e.readAsStringSync();
      for (final RegExpMatch m in RegExp(r'CircularProgressIndicator\(').allMatches(src)) {
        final String args = argsOf(src, m.end - 1);
        final RegExpMatch? c = RegExp(r'color:\s*([^,)]+)').firstMatch(args);
        if (c != null && !c.group(1)!.contains('Tokens.accent')) {
          final int line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          bad.add('${e.path}:$line: ${c.group(1)!.trim()}');
        }
      }
    }
    expect(bad, isEmpty, reason: '转圈圈只许用 accent（或干脆不传，走主题）：\n${bad.join('\n')}');
  });
}
