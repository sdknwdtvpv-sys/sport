/// 徽章**长相**的回归护栏（2026-10-05 重绘时新增）。
///
/// `badges_test.dart` 管判据、`achievements_test.dart` 管这一屏的对外契约，
/// 都不该管徽章长什么样。但"每枚徽章长得不一样"这件事**没有测试就一定会退化回去**：
/// 加一枚新徽章忘了配图形、或者谁图省事又换回一排一样的方块，页面上都不会报错，
/// 只会悄悄变回原来那副占位符的样子 —— 这次要修的正是它。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/progress/achievements_screen.dart';
import 'package:lianleme/features/progress/badges.dart';

void main() {
  final List<BadgeStatus> all = badgeStatuses(const <SetRecord>[]);

  test('每一枚徽章都有自己的图形：id → 图标，互不相同', () {
    final List<IconData> icons =
        all.map((BadgeStatus b) => badgeIcon(b.id)).toList();
    expect(icons.toSet().length, all.length,
        reason: '有徽章共用了同一个图形 —— 那就又回到"所有徽章长得一模一样"了');
  });

  test('现有这些徽章全部**显式**配过图形，没有一枚落在兜底上', () {
    // ⚠️ 兜底**按一个不存在的 id 取**，不许写死成某个图标常量。
    // 踩过的坑：兜底原来是 `Icons.military_tech`，后来"一年不断"把那个图形拿去做真图形了
    // —— 于是这条测试既抓不到漏配（漏配与真配同形）、又会误报。按未知 id 取就不会再犯。
    final IconData fallback = badgeIcon('__no_such_badge_id__');
    for (final BadgeStatus b in all) {
      expect(badgeIcon(b.id), isNot(fallback), reason: '${b.name}（${b.id}）没配图形');
    }
  });

  test('渐变没有偷偷加色：深的那端和亮的那端是同一个色相，只是更暗', () {
    for (final BadgeTier t in BadgeTier.values) {
      final LinearGradient g = badgeTierGradient(t);
      final Color bright = g.colors.first;
      final Color deep = g.colors.last;
      expect(bright, badgeTierColor(t), reason: '${badgeTierLabel(t)}的亮端必须就是它那一档的颜色');
      expect(deep, isNot(bright), reason: '两端一样就不是渐变了');
      final HSLColor a = HSLColor.fromColor(bright);
      final HSLColor b = HSLColor.fromColor(deep);
      expect(b.hue, closeTo(a.hue, 1),
          reason: '深端是压暗出来的，不许是另一个色相（否则页面就多了一个颜色）');
      expect(b.lightness, lessThan(a.lightness));
    }
  });

  testWidgets('每一格画的是它自己的图形（不是一排勾、也不是一排锁）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(home: AchievementsScreen(sets: const <SetRecord>[])));
    await tester.pumpAndSettle();
    // 2026-10-06 起每个分区默认只摊两行 —— 要逐枚看图形就得先全部展开
    for (final BadgeCategory c in BadgeCategory.values) {
      final Finder toggle = find.byKey(Key('badge-section-toggle-${c.name}'));
      if (toggle.evaluate().isEmpty) continue;
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
    }

    for (final BadgeStatus b in all) {
      expect(
        find.descendant(
          of: find.byKey(Key('badge-${b.id}')),
          matching: find.byIcon(badgeIcon(b.id)),
        ),
        findsOneWidget,
        reason: '${b.name} 那一格画的不是它自己的图形',
      );
    }
  });

  group('A2 离你最近的一枚 / A5 段位（2026-10-06 拍板）', () {
    BadgeStatus mk(String id, int cur, int tgt, {bool unlocked = false, BadgeTier tier = BadgeTier.common}) =>
        BadgeStatus(
          id: id,
          name: id,
          how: '',
          tier: tier,
          category: BadgeCategory.milestone,
          current: cur,
          target: tgt,
          unlocked: unlocked,
        );

    test('★ 按**剩余比例**排，不按绝对差值（否则"还差 94536 kg"会被当成最近）', () {
      final BadgeStatus? n = nearestBadge(<BadgeStatus>[
        mk('hundred_ton', 5464, 100000),   // 差 94536，比例 5.5%
        mk('week_streak', 5, 7),           // 差 2，比例 71%
      ]);
      expect(n!.id, 'week_streak');
    });

    test('已解锁的不参与；全拿到了就如实返回 null（不许挑一枚充数）', () {
      expect(nearestBadge(<BadgeStatus>[mk('a', 7, 7, unlocked: true)]), isNull);
      final BadgeStatus? n = nearestBadge(<BadgeStatus>[
        mk('a', 7, 7, unlocked: true),
        mk('b', 1, 10),
      ]);
      expect(n!.id, 'b');
    });

    test('同进度先推**低档位**那枚（更容易拿到，更该今天去拿）', () {
      final BadgeStatus? n = nearestBadge(<BadgeStatus>[
        mk('epic_one', 1, 2, tier: BadgeTier.epic),
        mk('common_one', 1, 2, tier: BadgeTier.common),
      ]);
      expect(n!.id, 'common_one');
    });

    test('段位门槛是升序且从 0 开始；段位/下一段算得对', () {
      for (int i = 1; i < kRanks.length; i++) {
        expect(kRanks[i].need, greaterThan(kRanks[i - 1].need));
      }
      expect(kRanks.first.need, 0);
      expect(rankFor(0).name, '青铜');
      expect(rankFor(2).name, '青铜');
      expect(rankFor(3).name, '白银');
      expect(nextRank(3)!.name, '黄金');
      expect(nextRank(3)!.remaining, 5);
      // 门槛与"徽章总数"要对得上：顶级段位不该低于最难的几枚徽章的量级
      expect(kRanks.last.need, greaterThan(50));
      // 到顶之后**不许编**下一个目标
      expect(nextRank(kRanks.last.need + 10), isNull);
    });
  });
}
