/// 练了么 · 首页「今天的安排」+ 上下肢分化（2026-10-04）
///
/// 这一批改的是**北极星靶心那一屏**，两条投诉都来自真机：
///   1. 标题与按钮之间**空了一大块**（原来是一个 `Spacer()`），首屏很难看；
///   2. 默认只给 **3 个动作 = 9 组**，而 `PRODUCT.md` §9 的护栏是「单次 ≥ 12 组」
///      —— 默认计划**数学上就到不了**。证据与算账见 `TrainingDay` 的注释。
///
/// 所以这里守三条不变量：
///   * 首页中间那块**有内容**（不是空白），并且是**今天要练的那一份**；
///   * **大按钮开练的动作 = 首页列出来的那些**（显示了 A 却练 B 比不显示更糟）；
///   * 矮屏**不溢出**（加了卡片之后 Flutter 报过 RenderFlex overflowed by 72px）。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/domain/models.dart' show PlanTarget;
import 'package:lianleme/features/today/today_planner.dart';
import 'package:lianleme/features/progress/streak_protection.dart';
import 'package:lianleme/features/progress/weekly_report.dart';
import 'package:lianleme/features/today/today_screen.dart';
import 'package:lianleme/main.dart';

void main() {
  late AppDatabase db;
  late String seedJson;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    seedJson = await File('assets/exercises.json').readAsString();
  });
  tearDown(() => db.close());

  Future<void> pumpApp(WidgetTester tester) async {
    await ProfileRepository(db).setPrivacyConsent(nowMs: 1);
    await tester.pumpWidget(LianLeMeApp(
      database: db,
      seedLoader: () async => seedJson,
    ));
    await tester.pumpAndSettle();
  }

  /// 卡片里所有文字（表头 + 每个动作名 + 建议值 + "换一批"）
  List<String> cardTexts(WidgetTester tester) => tester
      .widgetList<Text>(find.descendant(
        of: find.byKey(const Key('today-plan')),
        matching: find.byType(Text),
      ))
      .map((Text t) => t.data ?? '')
      .where((String s) => s.isNotEmpty)
      .toList();

  /// 卡片里列了几个动作 —— **按结构数**（每行一个 key），
  /// 不猜"文字里有没有 kg"：自重动作念「自重 × 8」，按 kg 数会漏掉它们。
  int rowCount(WidgetTester tester) => tester
      .widgetList(find.byWidgetPredicate((Widget w) {
        final Key? k = w.key;
        return k is ValueKey<String> && k.value.startsWith('today-plan-row-');
      }))
      .length;

  /// 必须销毁页面：外壳里有两个埋点定时器，不销毁 testWidgets 会因 pending timer 判失败
  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  group('首页「今天的安排」', () {
    testWidgets('中间那块不再是空白：有表头、有动作、有建议值',
        (WidgetTester tester) async {
      await pumpApp(tester);

      expect(find.byKey(const Key('today-plan')), findsOneWidget,
          reason: '首页中间现在该摆今天的安排（以前是一个 Spacer）');

      final List<String> texts = cardTexts(tester);
      expect(texts, contains('今天练 上肢'),
          reason: '从没练过 → 上肢；2026-10-04 起不再是"今天练 胸"');
      expect(texts, contains('换一批'));
      // 上肢日第一个动作是常用度最高的胸部动作
      expect(texts, contains('杠铃卧推'));
      // 第一次练这个动作 → 建议值就是动作库起始重量（40kg × 8）
      expect(texts.any((String s) => s.contains('40 kg × 8')), isTrue,
          reason: '每行要带引擎算好的建议值，不能只给个名字：$texts');

      await teardown(tester);
    });

    testWidgets('★ 第一次只列 4 个动作（12 组，压在「单次 ≥ 12 组」护栏上）',
        (WidgetTester tester) async {
      await pumpApp(tester);

      final int rows = rowCount(tester);
      expect(rows, kFirstSessionExercises);
      expect(rows * 3, 12, reason: '3 组/动作 → 正好 12 组');

      await teardown(tester);
    });

    testWidgets('★ 大按钮开练的，就是首页列出来的那一个动作',
        (WidgetTester tester) async {
      await pumpApp(tester);

      final List<String> texts = cardTexts(tester);
      expect(texts, contains('杠铃卧推'));

      await tester.tap(find.byKey(const Key('start-workout')));
      await tester.pumpAndSettle();

      // 训练屏顶部那个动作名 —— 首页列的是杠铃卧推，那进去就该是它
      expect(find.text('杠铃卧推'), findsWidgets,
          reason: '首页显示的计划与真正开练的必须是同一份（显示了 A 却练 B 更糟）');
      expect(find.byKey(const Key('big-log-button')), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('「换一批」换掉首页那张卡里的动作', (WidgetTester tester) async {
      await pumpApp(tester);

      final List<String> before = cardTexts(tester);
      final int rowsBefore = rowCount(tester);
      await tester.tap(find.byKey(const Key('today-reroll')));
      await tester.pumpAndSettle();
      final List<String> after = cardTexts(tester);

      expect(after, isNot(equals(before)), reason: '「换一批」得真的换掉');
      expect(rowCount(tester), rowsBefore, reason: '换一批不该让计划缩水');

      await teardown(tester);
    });

    testWidgets('★ 卡片整块可点：点它进建议卡（「我自己选 / 我的计划」在那儿）',
        (WidgetTester tester) async {
      await pumpApp(tester);

      // 那一行「看看今天练什么 ›」已经删掉（2026-10-04）—— 入口合并进卡片，
      // 所以这条测试要同时钉住"新入口在"与"旧的那一行不在了"。
      expect(find.byKey(const Key('see-plan')), findsNothing,
          reason: '同一件事不留两个入口');
      expect(find.byKey(const Key('open-plan')), findsOneWidget);

      await tester.tap(find.byKey(const Key('open-plan')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('today-title')), findsOneWidget,
          reason: '点卡片该落到建议卡');
      expect(find.byKey(const Key('pick-myself')), findsOneWidget,
          reason: '「我自己选」只在建议卡里 —— 所以这个入口不能真删');
      expect(find.byKey(const Key('big-log-button')), findsNothing,
          reason: '点卡片只是"看看"，不是开练（开练永远是大按钮）');

      await teardown(tester);
    });

    testWidgets('计划还没算出来时，卡片照常在（入口不会因此消失）',
        (WidgetTester tester) async {
      // 只有 `todayPlan` 空、`onSeePlan` 非空 —— 这是"首页预览算失败"的样子。
      // 真源在 main.dart：`_loadTodayPlan()` 的 catch 是**吞掉异常**的，
      // 于是"预览空了"是可能发生的；如果这时卡片不显示，
      // 「我自己选 / 我的计划」就变得够不着了。
      bool opened = false;
      await tester.pumpWidget(MaterialApp(
        home: TodayScreen(
          onStart: () {},
          onSeePlan: () => opened = true,
          lastWeekSessions: 0,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('today-plan')), findsOneWidget);
      expect(find.text('今天还没有排动作'), findsOneWidget);

      // 2026-10-05：主按钮进了卡片（新 VI），而 `tester.tap` 点的是**中心**——
      // 现在中心是那颗按钮。所以要**点卡片的非按钮区域**（标题那行），
      // 并且顺手钉死一件事：**点按钮不能顺带把建议卡也打开**（两个目标是分开的）。
      await tester.tap(find.text('今天还没有排动作'));
      await tester.pumpAndSettle();
      expect(opened, isTrue);

      opened = false;
      await tester.tap(find.byKey(const Key('start-workout')));
      await tester.pumpAndSettle();
      expect(opened, isFalse, reason: '点主按钮不该同时打开建议卡');

      await teardown(tester);
    });

    testWidgets('卡片不可点时**不摆那个 ›**（点不动的箭头比没有更糟）',
        (WidgetTester tester) async {
      // 老调用方不传 onSeePlan，但**有**计划要显示（测试里的常见形状）。
      final ExerciseData ex = ExerciseData(
        id: 'ex_bench',
        name: '杠铃卧推',
        aliases: '[]',
        muscleGroup: 'chest',
        secondaryMuscles: '[]',
        equipment: 'barbell',
        category: 'strength',
        trackType: 'weight_reps',
        defaultRestSec: 90,
        weightIncrement: 2.5,
        isBuiltin: true,
        popularity: 100,
        createdAt: 0,
        updatedAt: 0,
      );
      await tester.pumpWidget(MaterialApp(
        home: TodayScreen(
          onStart: () {},
          lastWeekSessions: 0,
          todayPlan: <PlannedExercise>[
            PlannedExercise(
                exercise: ex,
                plan: const PlanTarget(
                    targetSets: 3, targetRepsLow: 8, targetRepsHigh: 10)),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('today-plan')), findsOneWidget);
      expect(find.byKey(const Key('open-plan')), findsNothing,
          reason: '没有 onOpen 就不该可点');
      expect(find.text('点这里看看怎么练 ›'), findsNothing);

      await teardown(tester);
    });

    testWidgets('★ 矮屏不溢出（加了卡片之后报过 overflowed 72px）',
        (WidgetTester tester) async {
      // 600 高 ≈ 很多手机横过来 / 大字体下的可用高度。
      // Flutter 在 RenderFlex 溢出时会直接让测试失败，所以这条不用额外断言什么 ——
      // 能跑完就是没溢出。
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpApp(tester);

      expect(find.byKey(const Key('today-plan')), findsOneWidget);
      expect(find.byKey(const Key('start-workout')), findsOneWidget,
          reason: '再挤也要看得见主按钮');
      expect(tester.takeException(), isNull);

      await teardown(tester);
    });

    testWidgets('★ 系统大字号 1.5× 也不溢出（40+ 用户会把字号调大）',
        (WidgetTester tester) async {
      // 为什么单独一条：全项目原先**没有任何一处**处理 textScaler，
      // 而首页是卡片叠卡片、最容易挤爆的一屏。
      // 设备按 411×914 逻辑像素（常见安卓机）+ 1.5 倍字体。
      tester.view.physicalSize = const Size(1233, 2742);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      // 1.3× 与 1.5× 都跑一遍：1.3 是"调大一点"的常见档，1.5 是系统里最大的一档
      for (final double scale in <double>[1.3, 1.5]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await pumpApp(tester);

        // Flutter 在 RenderFlex 溢出时会直接让测试失败，能跑完就是没溢出
        expect(tester.takeException(), isNull, reason: '${scale}× 时首页溢出了');
        expect(find.byKey(const Key('start-workout')), findsOneWidget,
            reason: '${scale}× 时也要看得见主按钮');
        expect(find.byKey(const Key('open-notifications')), findsOneWidget,
            reason: '${scale}× 时铃铛不能被挤掉 —— 那是通知中心唯一的入口');
      }

      await teardown(tester);
    });
  });

  _weeklyReportUiTests();

  testWidgets('★ 补签保护（第二部分第 2 条）：有得补时卡片里出现那一行 + 按钮，点了回调出去',
      (WidgetTester tester) async {
    int protectedCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: TodayScreen(
        onStart: () {},
        streak: 3,
        protectedInStreak: 1,
        protectionOffer: StreakProtectionOffer(
          day: DateTime(2026, 10, 7),
          label: '昨天（10 月 7 日）没练，补签一次就能接上 —— 每周一次。',
        ),
        onProtectStreak: () => protectedCount++,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('protection-offer')), findsOneWidget);
    expect(find.textContaining('每周一次'), findsOneWidget);
    await tester.tap(find.byKey(const Key('protect-streak')));
    await tester.pumpAndSettle();
    expect(protectedCount, 1);
  });

  testWidgets('★ 连续天数里含补签 → **必须写出来**（不写就是假话）',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TodayScreen(onStart: () {}, streak: 12, protectedInStreak: 2),
    ));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('streak-label'))).data,
      '已连续打卡 12 天（其中 2 天是补签）',
    );

    // 没有补签时不多说那半句
    await tester.pumpWidget(MaterialApp(
      home: TodayScreen(onStart: () {}, streak: 12),
    ));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('streak-label'))).data,
      '已连续打卡 12 天',
    );
  });

  testWidgets('没得补时：那一行与按钮都不出现（不许多说一个字）',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TodayScreen(onStart: () {}, streak: 5),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('protection-offer')), findsNothing);
    expect(find.byKey(const Key('protect-streak')), findsNothing);
  });

  testWidgets('★ 本周挑战那一行（第二部分第 3 条）：传了就画，没传就不出现',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TodayScreen(
        onStart: () {},
        weeklyChallengeLine: '本周挑战：本周练 3 次 · 1 / 3次（还剩 5 天）',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('weekly-challenge-line')), findsOneWidget);
    expect(find.textContaining('本周挑战'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(home: TodayScreen(onStart: () {})));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('weekly-challenge-line')), findsNothing,
        reason: '没传就不该出现（判据在 weekly_challenge.dart 的纯函数里）');
  });
}

// ── 周报（第二部分第 1 条，2026-10-06）──────────────────────────────
//
// 判据（该不该显示）在 `weekly_report_test.dart` 里是纯函数级的；这里只钉**界面契约**：
// 传进来就画、没传就不画、点「做成一张卡」会回调出去。

void _weeklyReportUiTests() {
  final WeeklyReport report = WeeklyReport(
    start: DateTime(2026, 9, 28),
    end: DateTime(2026, 10, 5),
    sessions: 4,
    activeDays: 4,
    totalSets: 60,
    volumeKg: 24000,
    durationMin: 180,
    exerciseCount: 8,
    distanceM: 5000,
    prs: const <({String name, String detail})>[
      (name: '杠铃卧推', detail: '70 kg（上次最好 65 kg）'),
    ],
    badgesUnlocked: 2,
    bestDayVolumeKg: 9000,
  );

  testWidgets('周报传进来就画：范围 / 一句人话 / 数字行 / 额外收获都在',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TodayScreen(onStart: () {}, weeklyReport: report),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('weekly-report')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('weekly-report-range'))).data,
        '9 月 28 日 – 10 月 4 日');
    expect(tester.widget<Text>(find.byKey(const Key('weekly-report-headline'))).data,
        report.headline);
    expect(tester.widget<Text>(find.byKey(const Key('weekly-report-stats'))).data,
        contains('4 次训练'));
    expect(find.textContaining('刷新 1 项纪录'), findsOneWidget);
  });

  testWidgets('★ 没传周报（周三到周日、或上周没练）→ 那一块**完全不出现**',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: TodayScreen(onStart: () {})));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('weekly-report')), findsNothing,
        reason: '回顾不许天天顶在首页');
  });

  testWidgets('★ 点「做成一张卡」把动作交回外壳（这一屏不自己推页面）',
      (WidgetTester tester) async {
    int opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: TodayScreen(onStart: () {}, weeklyReport: report, onOpenWeeklyReport: () => opened++),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('weekly-report-share')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('weekly-report-share')));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('★ 部位平衡传进来就画那一行；没传就不出现（首页不许多说一句）',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TodayScreen(onStart: () {}, muscleBalance: '这周胸 3 次、腿还是 0 次'),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('muscle-balance')), findsOneWidget);
    expect(find.text('这周胸 3 次、腿还是 0 次'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(home: TodayScreen(onStart: () {})));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('muscle-balance')), findsNothing);
  });

  testWidgets('★ 回归激励：断 7 天以上才出现，且那条轻量入口跟着上来',
      (WidgetTester tester) async {
    int light = 0;
    await tester.pumpWidget(MaterialApp(
      home: TodayScreen(
        onStart: () {},
        onLightWorkout: () => light++,
        comebackNudge: '已经 9 天没练了 —— 先做 5 分钟活动，也算一次。',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('comeback-nudge')), findsOneWidget);
    expect(find.textContaining('9 天没练'), findsOneWidget);
    await tester.tap(find.byKey(const Key('comeback-light')));
    await tester.pumpAndSettle();
    expect(light, 1, reason: '卡里那颗按钮要真的能进 5 分钟活动');

    await tester.pumpWidget(MaterialApp(home: TodayScreen(onStart: () {})));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('comeback-nudge')), findsNothing);
  });
}

