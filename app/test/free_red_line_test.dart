/// 练了么 · **免费红线与付费入口位置**的机械守卫（M1）
///
/// 判据来自 `docs/plan-membership-2026-10-10.md` §一（四条红线）与 §九 判据 5：
///
///   1. **记录训练永远免费** → 付费入口**不许**出现在开练那条路径上
///      （首页 → 训练屏 → 总结页 → 分享卡）。这不是审美问题：付费墙挡在
///      "完成第一次训练"前面，等于杀掉北极星（≥55%）。
///   2. **导出自己的数据永远免费** → 今天那两个入口（CSV 报表、JSON 备份）
///      与权益**一点关系都没有**：它们连 billing 都不许 import。
///   3. **付费入口只许出现在被明确允许的几个地方**（白名单）——
///      这是把"我打算放哪儿"变成一条能跑的判断，而不是每次翻代码。
///
/// ⚠️ 这份白名单会在 M1c（锁点接线）时**有意变长**：进步页的进阶分析预览态、
/// 「全部数据」的批量整理、云备份的多版本、以及"导出进阶"那一处都会加提示。
/// 那时要来这里加一行 —— **加之前先想一遍：这一处是不是在开练路径上？**
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 允许出现 `PaywallScreen` 的文件（**只许在这些地方**）
const Set<String> kPaywallAllowedFiles = <String>{
  'lib/billing/paywall_screen.dart', // 它自己
  'lib/features/profile/settings_home_screen.dart', // 设置页那一行入口（主动进来）
  // 2026-10-10 加：进步页的「进阶分析」卡要一个 `onOpenUltra` 回调，
  // 而**组装那条路由**的地方是 `main.dart`（屏自己不 import 会员页 ——
  // 这正是白名单要有它的原因：耦合点在装配层，不在屏里）。
  'lib/main.dart',
};

/// 开练那条路径上的文件：**一个字都不许出现付费入口**
const List<String> kTrainingPathFiles = <String>[
  'lib/features/today/today_screen.dart',
  'lib/features/workout/workout_screen.dart',
  'lib/features/workout/workout_controller.dart',
  'lib/features/summary/workout_summary_screen.dart',
  'lib/features/summary/share_card.dart',
  'lib/features/summary/share_card_preview_screen.dart',
];

/// 永远免费的两个导出入口所在文件：**不许 import billing**
const List<String> kAlwaysFreeFiles = <String>[
  'lib/features/profile/data_tools_screen.dart',
  'lib/features/profile/training_stats.dart',
];

Iterable<File> _dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((File f) => f.path.endsWith('.dart'));

void main() {
  test('★ 付费入口只出现在白名单里（其余地方一律不许引用 PaywallScreen）', () {
    final List<String> offenders = <String>[];
    for (final File f in _dartFiles('lib')) {
      final String text = f.readAsStringSync();
      if (!text.contains('PaywallScreen')) continue;
      final String rel = f.path.replaceFirst(RegExp(r'^\./'), '');
      if (!kPaywallAllowedFiles.contains(rel)) offenders.add(rel);
    }
    expect(offenders, isEmpty,
        reason: '这些文件里出现了付费墙入口，但不在白名单里。'
            '要么撤掉它，要么来 `kPaywallAllowedFiles` 里加一行（并想清楚：它在开练路径上吗？）');
  });

  test('★ 开练那条路径上一个付费字样都没有（首页 / 训练屏 / 总结页 / 分享卡）', () {
    final List<String> offenders = <String>[];
    for (final String rel in kTrainingPathFiles) {
      final File f = File(rel);
      if (!f.existsSync()) {
        offenders.add('$rel（文件不在了 —— 这里要跟着改，别让它静静失效）');
        continue;
      }
      final String text = f.readAsStringSync();
      for (final String needle in <String>['Ultra', 'PaywallScreen', 'paywall', 'open-ultra']) {
        if (text.contains(needle)) offenders.add('$rel 含「$needle」');
      }
    }
    expect(offenders, isEmpty,
        reason: '付费入口跑到开练路径上了 —— 那条路径的完成率是北极星，不能用来卖东西');
  });

  test('★ 导出自己的数据与权益无关（那两个入口所在文件不许 import billing）', () {
    final List<String> offenders = <String>[];
    for (final String rel in kAlwaysFreeFiles) {
      final File f = File(rel);
      if (!f.existsSync()) {
        offenders.add('$rel（文件不在了 —— 这里要跟着改）');
        continue;
      }
      final String text = f.readAsStringSync();
      // 只查 import 行：注释里提到 billing（解释"进阶导出将来会锁"）是允许的
      for (final String line in text.split('\n')) {
        final String t = line.trim();
        if (t.startsWith('//') || t.startsWith('///')) continue;
        if (t.startsWith('import ') && t.contains('billing/')) {
          offenders.add('$rel：$t');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: '「导出自己的数据」是红线（合规 + 信任），它不该与权益有任何耦合。'
            '将来要锁的是**进阶形态**（年报卡 / 按条拆分），那要另建入口，不是改这两个');
  });

  test('白名单本身不许悄悄失效（每个文件都得真的存在）', () {
    for (final String rel in <String>[...kPaywallAllowedFiles, ...kAlwaysFreeFiles]) {
      expect(File(rel).existsSync(), isTrue, reason: '$rel 不在了 —— 白名单要跟着更新');
    }
  });
}
