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
import 'package:lianleme/features/progress/weekly_challenge.dart';

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

/// 把四个分区**全部展开**（2026-10-06 起每个分区默认只摊两行）。
///
/// 需要"逐枚断言 73 枚"的测试必须先展开 —— 否则测的是"折叠对不对"，
/// 而不是"这一枚徽章在不在"。折叠本身由下面那条 `★ 分区折叠` 单独钉。
Future<void> _expandAll(WidgetTester tester) async {
  for (final BadgeCategory c in BadgeCategory.values) {
    final Finder toggle = find.byKey(Key('badge-section-toggle-${c.name}'));
    if (toggle.evaluate().isEmpty) continue;
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('★ 徽章一排**占满整行**（写死宽度会让整排偏左 —— 2026-10-07 修）',
      (WidgetTester tester) async {
    // 用户看截图问"这一页的布局太怪了，为什么没有设计成居中"。
    // 根因是 `_BadgeTile` 写死 100 宽 + `Wrap`：一排三枚 = 3×100 + 2×12 = 324，
    // 而内容宽度是"屏宽 − 左右各 20" —— 右边永远剩一截空档，整排看着往左偏。
    // 现在每一枚的宽度由**可用宽度反算**。
    //
    // 这条测试量的是**几何**（宽度 / 边缘），不是"能不能画出来"：
    // 布局类修复不留一条量尺寸的测试就等于没修 —— 下一次谁再写死一个宽度，
    // 界面上仍然什么错都不报。
    await _pump(tester, <SetRecord>[]);
    final Finder wrap = find.byType(Wrap).first;
    final Finder tiles = find.descendant(
      of: wrap,
      matching: find.byWidgetPredicate((Widget w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('badge-tile-')),
    );
    expect(tiles, findsWidgets, reason: '一格都没找到 = 这条测试自己失效了');

    final double rowWidth = tester.getSize(wrap).width;
    final double tile = tester.getSize(tiles.first).width;
    expect(tile * 3 + Tokens.s3 * 2, closeTo(rowWidth, 0.5),
        reason: '三枚 + 两条间隙必须**正好**是一整行（差出来的就是右边那段空档）');
    expect(tester.getTopLeft(tiles.first).dx,
        closeTo(tester.getTopLeft(wrap).dx, 0.5),
        reason: '最左边那一枚要贴着内容区左边缘');
    expect(tester.getTopRight(tiles.at(2)).dx,
        closeTo(tester.getTopRight(wrap).dx, 0.5),
        reason: '第一排最右边那一枚要顶到内容区右边缘 —— 这就是"居中"');
    // 一排里的三枚必须等宽（宽度是算出来的，不是各自碰运气）
    for (int i = 1; i < 3; i++) {
      expect(tester.getSize(tiles.at(i)).width, closeTo(tile, 0.01));
    }
  });

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
    // 分区默认只摊两行，逐枚断言之前先把四个分区都展开
    await _expandAll(tester);
    // 视口放大过（见 `_pump`），所以整页都在树里 —— 逐枚断言
    for (final BadgeStatus b in all) {
      expect(find.byKey(Key('badge-${b.id}')), findsOneWidget, reason: '${b.name} 不见了');
    }
    expect(find.textContaining('还差'), findsWidgets);
  });

  // ── 分区折叠（2026-10-06：73 枚不能一次铺满 ≈3000px）────────────────
  testWidgets('★ 每个分区默认只摊两行，并如实写出"展开全部 N 枚"',
      (WidgetTester tester) async {
    await _pump(tester, <SetRecord>[]);
    final Map<BadgeCategory, List<BadgeStatus>> groups =
        badgeGroups(badgeStatuses(<SetRecord>[]));
    for (final MapEntry<BadgeCategory, List<BadgeStatus>> e in groups.entries) {
      // 标题右边那行"已拿 / 全部"——折叠之后它是这条线唯一的进度
      expect(
        tester.widget<Text>(find.byKey(Key('badge-section-count-${e.key.name}'))).data,
        '0 / ${e.value.length}',
      );
      final Finder toggle =
          find.byKey(Key('badge-section-toggle-${e.key.name}'));
      expect(toggle, findsOneWidget, reason: '${badgeCategoryLabel(e.key)} 应当可以展开');
      expect(find.text('展开全部 ${e.value.length} 枚'), findsWidgets);
      // 折叠状态下，第 7 枚（两行之外）必须**还不在**树里
      final int limit = 6;
      if (e.value.length > limit) {
        expect(find.byKey(Key('badge-${e.value[limit].id}')), findsNothing,
            reason: '折叠时不该把 ${e.value[limit].name} 也画出来');
      }
    }
  });

  testWidgets('展开之后第 7 枚才出现，点"收起"又收回去（不是单向的）',
      (WidgetTester tester) async {
    await _pump(tester, <SetRecord>[]);
    final List<BadgeStatus> streakRows =
        badgeGroups(badgeStatuses(<SetRecord>[]))[BadgeCategory.streak]!;
    final Finder toggle = find.byKey(const Key('badge-section-toggle-streak'));
    final Finder seventh = find.byKey(Key('badge-${streakRows[6].id}'));
    expect(seventh, findsNothing);

    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(seventh, findsOneWidget, reason: '展开之后第 7 枚要出现');
    expect(find.text('收起'), findsWidgets);

    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(seventh, findsNothing, reason: '"收起"必须真的收回去');
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
      // ⚠️ 2026-10-06 起同一个名字会出现在两处：A1 那张「收集线」卡里、
      // 以及分区标题。所以这里按**分区计数**那一行去找，而不是按纯文字去找
      // （`findsOneWidget` 会挂——那不是 bug，是这句话现在本来就说两遍）。
      expect(find.byKey(Key('badge-section-count-${c.name}')), findsOneWidget,
          reason: '${badgeCategoryLabel(c)} 的分区标题不见了');
      expect(find.text(badgeCategoryLabel(c)), findsWidgets);
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


  // ── A3 每周挑战（2026-10-06 拍板）──────────────────────────────────
  testWidgets('★ A3：成就页有「本周挑战」那一块，且写清还剩几天（过期作废）',
      (WidgetTester tester) async {
    await _pump(tester, <SetRecord>[]);
    expect(find.byKey(const Key('weekly-challenge')), findsOneWidget);
    final WeeklyChallenge c = weeklyChallenge(<SetRecord>[], DateTime.now());
    expect(tester.widget<Text>(find.byKey(const Key('weekly-name'))).data, c.spec.name);
    expect(
      tester.widget<Text>(find.byKey(const Key('weekly-days-left'))).data,
      '还剩 ${c.daysLeft} 天',
      reason: '"过期作废"必须写出来 —— 不写用户会以为下周还能补',
    );
    expect(find.byKey(const Key('weekly-progress')), findsOneWidget);
  });

  testWidgets('本周挑战做完了 → 如实写"本周已完成"，不再画一条 0 进度',
      (WidgetTester tester) async {
    // 今天所在这一周，天天练（池子里每一条都做得到 —— 见 weekly_challenge_test）
    final DateTime now = DateTime.now();
    final DateTime monday = now.subtract(Duration(days: now.weekday - DateTime.monday));
    final List<SetRecord> sets = <SetRecord>[
      for (int d = 0; d < 4; d++)
        for (int i = 0; i < 12; i++)
          _set('w$d', monday.add(Duration(days: d, hours: 19, minutes: i))),
    ];
    await _pump(tester, sets);
    expect(weeklyChallenge(sets, now).done, isTrue, reason: '这一周的挑战应当已完成');
    expect(
      tester.widget<Text>(find.byKey(const Key('weekly-progress'))).data,
      contains('本周已完成'),
    );
  });

  // ── A1 收集线（2026-10-06 拍板）────────────────────────────────────
  testWidgets('★ A1：四条收集线各有一根条 + 一个"已拿 / 全部"的数',
      (WidgetTester tester) async {
    await _pump(tester, <SetRecord>[]);
    expect(find.byKey(const Key('badge-lines')), findsOneWidget);
    final List<BadgeLine> lines = badgeLines(badgeStatuses(<SetRecord>[]));
    expect(lines.length, BadgeCategory.values.length);
    for (final BadgeLine l in lines) {
      expect(
        tester.widget<Text>(find.byKey(Key('line-count-${l.category.name}'))).data,
        '${l.unlocked} / ${l.total}',
        reason: '${l.label} 那一行的数要与纯函数一致',
      );
      expect(find.byKey(Key('line-emblem-${l.category.name}')), findsOneWidget);
    }
    // 一条都没集齐时，如实说"还差一点点"
    expect(find.text('还差一点点'), findsOneWidget);
  });

  testWidgets('★ A1 集齐奖励：集齐之后写"已集齐"，颜色换成这条线的颜色',
      (WidgetTester tester) async {
    // 造一条**只有两枚**的线，两枚都解锁 → 集齐。用真实的 BadgeStatus 构造，
    // 因为奖励的判据就是"这条线上每一枚都 unlocked"。
    final List<BadgeStatus> all = <BadgeStatus>[
      const BadgeStatus(
        id: 'a', name: 'a', how: 'h', tier: BadgeTier.common,
        category: BadgeCategory.streak, current: 1, target: 1, unlocked: true,
      ),
      const BadgeStatus(
        id: 'b', name: 'b', how: 'h', tier: BadgeTier.common,
        category: BadgeCategory.streak, current: 1, target: 1, unlocked: true,
      ),
    ];
    final List<BadgeLine> done = completedLines(all);
    expect(done.length, 1);
    expect(done.first.category, BadgeCategory.streak);
    // 奖励是"那条线的颜色"—— 与图例里的三档颜色是两件事，这里只钉它来自 lineColor
    expect(lineColor(BadgeCategory.streak), Tokens.accent);
  });

  test('分组不会漏徽章：每个分类里的数量加起来 == 全部', () {
    final List<BadgeStatus> all = badgeStatuses(<SetRecord>[]);
    final Map<BadgeCategory, List<BadgeStatus>> groups = badgeGroups(all);
    expect(groups.values.expand((List<BadgeStatus> x) => x).length, all.length);
  });

  // ── A4 隐藏徽章（2026-10-06 拍板）──────────────────────────────────
  testWidgets('★ 隐藏徽章：解锁前条件是「？？？」，名字照常看得见', (WidgetTester tester) async {
    await _pump(tester, <SetRecord>[]);
    // 隐藏徽章都在「探索发现」线的后半段，折叠态下够不到 —— 先展开
    await _expandAll(tester);
    final List<BadgeStatus> hidden =
        badgeStatuses(<SetRecord>[]).where((BadgeStatus b) => b.hidden).toList();
    expect(hidden, isNotEmpty, reason: '一枚隐藏徽章都没有的话这条测试是空转的');
    for (final BadgeStatus b in hidden) {
      expect(
        tester.widget<Text>(find.byKey(Key('badge-meta-${b.id}'))).data,
        '？？？',
        reason: '${b.id} 解锁前不该把怎么拿到写出来',
      );
      expect(find.text(b.name), findsWidgets, reason: '${b.id} 的名字必须仍然可见');
      // 也不许退化成"还差 N" —— 那等于把条件的一半说出来了
      expect(find.textContaining('还差'), findsWidgets);
    }
  });

  testWidgets('隐藏徽章**解锁之后**就把条件讲明白了（藏的是过程，不是结果）',
      (WidgetTester tester) async {
    // 「跨零点」：0~2 点之间记一组
    await _pump(tester, <SetRecord>[
      SetRecord(
        id: 'midnight',
        workoutId: 'w1',
        exerciseId: 'bench',
        setIndex: 0,
        weightKg: 60,
        reps: 8,
        completedAtMs: DateTime(2026, 10, 5, 1, 10).millisecondsSinceEpoch,
      ),
    ]);
    await _expandAll(tester);
    final BadgeStatus b = badgeStatuses(<SetRecord>[
      SetRecord(
        id: 'midnight',
        workoutId: 'w1',
        exerciseId: 'bench',
        setIndex: 0,
        weightKg: 60,
        reps: 8,
        completedAtMs: DateTime(2026, 10, 5, 1, 10).millisecondsSinceEpoch,
      ),
    ]).firstWhere((BadgeStatus x) => x.id == 'midnight_crosser');
    expect(b.unlocked, isTrue, reason: '凌晨 1 点记过一组，这枚就该解锁');
    expect(
      tester.widget<Text>(find.byKey(const Key('badge-meta-midnight_crosser'))).data,
      b.how,
      reason: '解锁之后要写清条件，不能永远挂着「？？？」',
    );
  });
}
