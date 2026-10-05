/// 成就页的界面契约：**已解锁几枚**要对得上，未解锁的**要说清还差多少**。
///
/// 为什么单独测这一屏：徽章最容易做成"发着玩的贴纸"——
/// 数字对不上、锁着的看不见进度，页面上都**不会报错**，只会让人失去兴趣。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/progress/achievements_screen.dart';
import 'package:lianleme/features/progress/badges.dart';

SetRecord _set(String workout, DateTime at, {double weight = 60}) => SetRecord(
      id: '$workout-${at.millisecondsSinceEpoch}',
      workoutId: workout,
      exerciseId: 'bench',
      setIndex: 0,
      weightKg: weight,
      reps: 8,
      completedAtMs: at.millisecondsSinceEpoch,
    );

/// 把测试表面放大到"整页一次画得下"。
///
/// 为什么不逐段滚：这一屏是 ListView（懒构建），滚动断言在**已经滚到底**之后
/// `scrollUntilVisible` 会抛 `Bad state: No element`（试过，就是上面那条）。
/// 与其跟滚动较劲，不如把视口放大到能装下整页 —— 这样每条断言都在测**内容**，
/// 而不是在测"滚动的实现细节"。
Future<void> _pump(WidgetTester tester, List<SetRecord> sets) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: AchievementsScreen(sets: sets)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('顶部那行"已解锁 N / M"与数据层算出来的一致', (WidgetTester tester) async {
    final List<SetRecord> sets = <SetRecord>[
      _set('w1', DateTime(2026, 10, 5, 9)),
    ];
    await _pump(tester, sets);
    final ({int unlocked, int total}) tally = badgeTally(badgeStatuses(sets));
    expect(tally.unlocked, greaterThan(0), reason: '练过一次至少解锁"首训"');
    expect(
      tester.widget<Text>(find.byKey(const Key('achievements-tally'))).data,
      '已解锁 ${tally.unlocked} / ${tally.total} 枚徽章',
    );
  });

  testWidgets('未解锁的徽章**照样显示**，并写出"还差多少"（藏起来就没有激励作用）',
      (WidgetTester tester) async {
    await _pump(tester, <SetRecord>[]);
    final List<BadgeStatus> all = badgeStatuses(<SetRecord>[]);
    // 视口放大过（见 `_pump`），所以整页都在树里 —— 逐枚断言
    for (final BadgeStatus b in all) {
      expect(find.byKey(Key('badge-${b.id}')), findsOneWidget, reason: '${b.name} 不见了');
    }
    expect(find.textContaining('还差'), findsWidgets);
  });

  testWidgets('已解锁与未解锁**不只靠颜色区分**：勾 vs 锁（色盲用户读到的信息一样）',
      (WidgetTester tester) async {
    final List<SetRecord> sets = <SetRecord>[
      _set('w1', DateTime(2026, 10, 5, 9)),
    ];
    await _pump(tester, sets);
    expect(find.byIcon(Icons.check_rounded), findsWidgets, reason: '已解锁要有勾');
    expect(find.byIcon(Icons.lock_outline), findsWidgets, reason: '未解锁要有锁');
  });

  testWidgets('四个分类的分区标题都在（连续打卡 / 力量突破 / 探索发现 / 里程碑）',
      (WidgetTester tester) async {
    await _pump(tester, <SetRecord>[]);
    for (final BadgeCategory c in BadgeCategory.values) {
      expect(find.text(badgeCategoryLabel(c)), findsOneWidget);
    }
  });

  testWidgets('三档稀有度用的是三个不同的颜色，且"普通"不是紫色（挡一次改错）',
      (WidgetTester tester) async {
    expect(badgeTierColor(BadgeTier.common), Tokens.accent);
    expect(badgeTierColor(BadgeTier.rare), Tokens.tierRare);
    expect(badgeTierColor(BadgeTier.epic), Tokens.pr);
    expect(<Color>{badgeTierColor(BadgeTier.common), badgeTierColor(BadgeTier.rare),
        badgeTierColor(BadgeTier.epic)}.length, 3);
  });

  test('分组不会漏徽章：每个分类里的数量加起来 == 全部', () {
    final List<BadgeStatus> all = badgeStatuses(<SetRecord>[]);
    final Map<BadgeCategory, List<BadgeStatus>> groups = badgeGroups(all);
    expect(groups.values.expand((List<BadgeStatus> x) => x).length, all.length);
  });
}
