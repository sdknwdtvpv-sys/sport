/// 练了么 · **徽章册收敛**（VI 计划 T3-4，2026-10-10）
///
/// 用户 2026-10-10 拍板（`plan-ux-2026-10-10.md` §五-B 第 3 条）：
/// **未解锁的勋章不写「还差 N 次」** —— 而代码里最多同时 69 条，一屏 8 个数字 + 6 根进度条。
///
/// 另外两条一起收：
///   * 完成页与收藏册**用同一个渲染器**（原来完成页按类别给 4 个图标之一、
///     收藏册按 id 给 73 枚 —— 同一枚徽章两张屏两个图形）；
///   * 三档稀有度除了颜色**还有第二通道**（内芯描边 0 / 1 / 2pt）——
///     `interaction-spec.md` §4 硬约束 2 写着"任何状态都不能只靠颜色表达"。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/progress/badge_medallion.dart';
import 'package:lianleme/features/progress/badges.dart';

/// 造一场"能解锁首训与单次 5 吨"的训练（够触发几枚已解锁 + 一堆未解锁）。
List<SetRecord> _sets() => <SetRecord>[
      SetRecord(
        id: 's1',
        workoutId: 'w1',
        exerciseId: 'ex_bb_bench_press',
        setIndex: 1,
        reps: 10,
        weightKg: 100,
        completedAtMs: DateTime(2026, 9, 1, 7, 30).millisecondsSinceEpoch,
      ),
    ];

void main() {
  testWidgets('未解锁徽章不显示任何第二行', (WidgetTester tester) async {
    final List<SetRecord> sets = _sets();
    final List<BadgeStatus> all = badgeStatuses(sets);
    final BadgeStatus locked =
        all.firstWhere((BadgeStatus b) => !b.unlocked && !b.hidden);
    final BadgeStatus unlocked = all.firstWhere((BadgeStatus b) => b.unlocked);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Column(
          children: <Widget>[
            for (final BadgeStatus b in <BadgeStatus>[unlocked, locked])
              BadgeMedallion(
                key: Key('tile-${b.id}'),
                id: b.id,
                tier: b.tier,
                unlocked: b.unlocked,
                progress: b.progress,
              ),
            // 收藏册里那一行第二行文字只在"已解锁 or 隐藏"时出现 —— 这里直接钉住那条规则
            if (unlocked.unlocked) Text(unlocked.how, key: const Key('meta-unlocked')),
            if (locked.unlocked || locked.hidden)
              const Text('不该出现', key: Key('meta-locked')),
          ],
        ),
      ),
    ));
    await tester.pump();

    expect(find.byKey(const Key('meta-unlocked')), findsOneWidget);
    expect(find.byKey(const Key('meta-locked')), findsNothing,
        reason: '未解锁的徽章不许有第二行（用户 10-10 拍板：删掉「还差 N」）');
    // 外圈那根进度环还在 —— "还差多少"由它说，不靠文字
    expect(find.byKey(Key('badge-ring-${locked.id}')), findsOneWidget);
  });

  testWidgets('完成页与收藏册用同一个渲染器，参数完全相等', (WidgetTester tester) async {
    final BadgeStatus b = badgeStatuses(_sets()).first;
    // 两处都构造同一个组件、同一个 id：38pt（完成页）与 64pt（收藏册）
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Column(
          children: <Widget>[
            BadgeMedallion(
                key: const Key('summary-size'),
                id: b.id,
                tier: b.tier,
                unlocked: true,
                diameter: 38),
            BadgeMedallion(
                key: const Key('shelf-size'),
                id: b.id,
                tier: b.tier,
                unlocked: true,
                diameter: 64),
          ],
        ),
      ),
    ));
    await tester.pump();

    final BadgeMedallion a =
        tester.widget<BadgeMedallion>(find.byKey(const Key('summary-size')));
    final BadgeMedallion c =
        tester.widget<BadgeMedallion>(find.byKey(const Key('shelf-size')));
    expect(a.id, c.id);
    expect(a.tier, c.tier, reason: '同一个 id 的稀有度两处必须一致');
    expect(a.unlocked, c.unlocked);
    // 图形来自 `badgeIcon(id)`（同一个函数），尺寸只是等比缩放
    expect(find.byKey(Key('badge-${b.id}')), findsNWidgets(2));
  });

  test('三档稀有度有颜色以外的第二通道（内芯描边 0 / 1 / 2pt）', () {
    expect(badgeInnerStroke(BadgeTier.common), 0);
    expect(badgeInnerStroke(BadgeTier.rare), 1);
    expect(badgeInnerStroke(BadgeTier.epic), 2);
    // 单调：越稀有越厚（不是三个随手写的数）
    expect(badgeInnerStroke(BadgeTier.rare),
        greaterThan(badgeInnerStroke(BadgeTier.common)));
    expect(badgeInnerStroke(BadgeTier.epic),
        greaterThan(badgeInnerStroke(BadgeTier.rare)));
  });

  testWidgets('内芯描边真的画出来了（终极那档有、基础那档没有）',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Column(
          children: <Widget>[
            BadgeMedallion(id: 'hundred_kg', tier: BadgeTier.common, unlocked: false),
            BadgeMedallion(id: 'ten_ton', tier: BadgeTier.epic, unlocked: false),
          ],
        ),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const Key('badge-inner-hundred_kg')), findsNothing,
        reason: '基础档 0pt：不画那一圈');
    final Container inner = tester
        .widget<Container>(find.byKey(const Key('badge-inner-ten_ton')));
    final BoxDecoration deco = inner.decoration! as BoxDecoration;
    expect(deco.border!.top.width, 2, reason: '终极档 2pt');
  });

  test('源码：完成页与收藏册都不再自己画徽章', () {
    // 收藏册不许再有本地的 ring painter / 内芯 Container（都搬进 badge_medallion.dart 了）
    final String shelf =
        File('lib/features/progress/achievements_screen.dart').readAsStringSync();
    expect(shelf.contains('BadgeMedallion('), isTrue);
    expect(shelf.contains('_BadgeRingPainter'), isFalse,
        reason: '收藏册里那份 painter 应该只在 badge_medallion.dart');
    // 完成页不许再按类别给图标（那是"两张屏两个图形"的根源）
    final String summary =
        File('lib/features/summary/workout_summary_screen.dart').readAsStringSync();
    expect(summary.contains('BadgeMedallion('), isTrue);
    expect(summary.contains('_badgeIcon'), isFalse,
        reason: '完成页那个"按类别给图标"的函数必须删掉');
    // 判据 1 的 grep 同源：全仓不许再拼「还差 ${badge.target …」
    expect(summary.contains('还差 \${badge.target'), isFalse);
  });
}
