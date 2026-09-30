/// 练了么 · S2 今日建议卡 widget 测试
///
/// 规则本身在 `today_planner_test.dart` 里测（13 条）。
/// 这里只测"页面有没有把结果显示对、有没有把用户的选择传对"。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/routine_repository.dart';
import 'package:lianleme/features/today/today_planner.dart';
import 'package:lianleme/features/today/today_suggestion_screen.dart';

void main() {
  late AppDatabase db;
  late ExerciseRepository repo;
  late TodayPlanner planner;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = ExerciseRepository(db);
    planner = TodayPlanner(repository: repo, store: DriftLocalStore(db));
    await repo.importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
  });

  tearDown(() => db.close());

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: TodaySuggestionScreen(planner: planner)),
    );
    await tester.pumpAndSettle();
  }

  /// 把卡片推到一个路由里，以便拿到它的返回值
  Future<TodayResult?> pushCardAndGetResult(
    WidgetTester tester,
    Future<void> Function(WidgetTester t) interaction,
  ) async {
    TodayResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(ctx).push<TodayResult>(
                    MaterialPageRoute<TodayResult>(
                      builder: (_) => TodaySuggestionScreen(planner: planner),
                    ),
                  );
                },
                child: const Text('进入'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('进入'));
    await tester.pumpAndSettle();
    await interaction(tester);
    return result;
  }

  testWidgets('显示"今天练 胸"和 3 条建议', (WidgetTester tester) async {
    await pumpCard(tester);

    expect(find.byKey(const Key('today-title')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('today-title'))).data,
      '今天练 胸',
      reason: '没练过任何动作时，轮转从胸开始',
    );

    // 三条建议，每条都有动作名和加载值
    // 首选动作是杠铃卧推，首练用的是动作库起始重量 40kg × 8
    expect(find.byKey(const Key('suggestion-ex_bb_bench_press')), findsOneWidget);
    expect(find.text('40 kg × 8'), findsOneWidget);
  });

  testWidgets('每条建议都带一行理由（红线：解释不了的建议不许出现）',
      (WidgetTester tester) async {
    await pumpCard(tester);

    expect(find.textContaining('第一次练这个动作'), findsWidgets);
  });

  testWidgets('「换一批」换掉动作', (WidgetTester tester) async {
    await pumpCard(tester);

    expect(find.byKey(const Key('suggestion-ex_bb_bench_press')), findsOneWidget,
        reason: '第一批里应该有杠铃卧推');

    await tester.tap(find.byKey(const Key('reroll')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('suggestion-ex_bb_bench_press')), findsNothing,
        reason: '换一批之后不该还有杠铃卧推');
  });

  testWidgets('点「开始训练」返回 startPlanned 和计划', (WidgetTester tester) async {
    final TodayResult? result =
        await pushCardAndGetResult(tester, (WidgetTester t) async {
      await t.tap(find.byKey(const Key('start-session')));
      await t.pumpAndSettle();
    });

    expect(result, isNotNull);
    expect(result!.choice, TodayChoice.startPlanned);
    expect(result.plan.length, 3);
    expect(result.plan.every((PlannedExercise p) => p.exercise.muscleGroup == 'chest'),
        isTrue);
  });

  testWidgets('点「我自己选」返回 pickMyself，不带计划', (WidgetTester tester) async {
    final TodayResult? result =
        await pushCardAndGetResult(tester, (WidgetTester t) async {
      await t.tap(find.byKey(const Key('pick-myself')));
      await t.pumpAndSettle();
    });

    expect(result, isNotNull);
    expect(result!.choice, TodayChoice.pickMyself);
    expect(result.plan, isEmpty);
  });

  testWidgets('从建议卡返回 = 不练了（结果为 null）', (WidgetTester tester) async {
    final TodayResult? result =
        await pushCardAndGetResult(tester, (WidgetTester t) async {
      await t.tap(find.byKey(const Key('today-back')));
      await t.pumpAndSettle();
    });

    expect(result, isNull);
  });

  // ---------- S11：用计划模板开训 ----------

  group('我的计划', () {
    late RoutineRepository routines;

    setUp(() {
      routines = RoutineRepository(db);
    });

    Future<TodayResult?> pumpWithRoutines(WidgetTester tester) async {
      TodayResult? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(ctx).push<TodayResult>(
                    MaterialPageRoute<TodayResult>(
                      builder: (_) => TodaySuggestionScreen(
                        planner: planner,
                        routines: routines,
                        exercises: repo,
                      ),
                    ),
                  );
                },
                child: const Text('开始'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('没给计划仓库时不显示「我的计划」（不放点不动的按钮）',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: TodaySuggestionScreen(planner: planner),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('use-routine')), findsNothing);
    });

    testWidgets('给了就显示入口', (WidgetTester tester) async {
      await pumpWithRoutines(tester);

      expect(find.byKey(const Key('use-routine')), findsOneWidget);
    });

    testWidgets('选一份计划 → 返回 startPlanned，且处方来自计划而不是默认值',
        (WidgetTester tester) async {
      final RoutineData r = await routines.create('推日', nowMs: 1000);
      await routines.addItem(r.id, 'ex_bb_bench_press',
          targetSets: 5, targetRepsLow: 3, targetRepsHigh: 5, nowMs: 1001);

      TodayResult? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(ctx).push<TodayResult>(
                    MaterialPageRoute<TodayResult>(
                      builder: (_) => TodaySuggestionScreen(
                        planner: planner,
                        routines: routines,
                        exercises: repo,
                      ),
                    ),
                  );
                },
                child: const Text('开始'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('use-routine')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('routine-start-${r.id}')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.choice, TodayChoice.startPlanned);
      expect(result!.plan, hasLength(1));
      expect(result!.plan.single.exercise.id, 'ex_bb_bench_press');
      // 关键：处方必须是计划里那份，不能被 kDefaultPlan 顶掉
      expect(result!.plan.single.plan.targetSets, 5);
      expect(result!.plan.single.plan.targetRepsLow, 3);
      expect(result!.plan.single.plan.targetRepsHigh, 5);
    });
  });

  group('今日热身卡', () {
    testWidgets('建议卡上会出现热身（库里 11 个热身以前在这条流程里见不到）',
        (WidgetTester tester) async {
      await pumpCard(tester);
      expect(find.byKey(const Key('warmup-card')), findsOneWidget);
      expect(find.text('练之前先热身'), findsOneWidget);
      expect(find.byKey(const Key('add-warmup')), findsOneWidget);
    });

    testWidgets('热身默认**不进**计划：不点就一条都不多',
        (WidgetTester tester) async {
      await pumpCard(tester);
      final int before = tester
          .widgetList(find.byWidgetPredicate((Widget w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('suggestion-')))
          .length;
      // 热身卡自己带着 add-warmup 按钮，但它没有被自动加进计划列表
      expect(find.byKey(const Key('add-warmup')), findsOneWidget);
      expect(before, greaterThan(0));
    });

    testWidgets('点「加进今天」之后：热身进入计划，而且带 1 组处方',
        (WidgetTester tester) async {
      await pumpCard(tester);
      // 先记下当前计划里的动作数
      final int before = tester
          .widgetList(find.byWidgetPredicate((Widget w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('suggestion-')))
          .length;

      await tester.tap(find.byKey(const Key('add-warmup')));
      await tester.pumpAndSettle();

      final int after = tester
          .widgetList(find.byWidgetPredicate((Widget w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('suggestion-')))
          .length;
      expect(after, greaterThan(before), reason: '热身必须真的进了计划');
      expect(find.text('已加进今天'), findsOneWidget);
      // 加过之后按钮消失（不能重复加）
      expect(find.byKey(const Key('add-warmup')), findsNothing);
    });

    testWidgets('加进今天的热身会跟着「开始训练」一起被带进训练会话',
        (WidgetTester tester) async {
      TodayResult? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (BuildContext ctx) {
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await Navigator.of(ctx).push<TodayResult>(
                    MaterialPageRoute<TodayResult>(
                      builder: (_) => TodaySuggestionScreen(planner: planner),
                    ),
                  );
                },
                child: const Text('打开建议卡'),
              ),
            ),
          );
        }),
      ));
      await tester.tap(find.text('打开建议卡'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-warmup')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('start-session')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.plan.length, greaterThan(3),
          reason: '计划里除了 3 个正式动作，还该多出热身');
      expect(
        result!.plan.any((PlannedExercise p) => p.exercise.category == 'warmup'),
        isTrue,
        reason: '热身必须真的进了这次会话',
      );
      expect(
        result!.plan
            .where((PlannedExercise p) => p.exercise.category == 'warmup')
            .every((PlannedExercise p) => p.plan.targetSets == 1),
        isTrue,
        reason: '热身是 1 组，不是 3 组',
      );
    });
  });

    testWidgets('加进今天的热身行念处方，不是破折号', (WidgetTester tester) async {
      await pumpCard(tester);
      await tester.tap(find.byKey(const Key('add-warmup')));
      await tester.pumpAndSettle();

      // 破折号曾经出现在这里（真机走查发现）：热身没有渐进建议，
      // 而 loadLabel 在没有建议时直接返回 '—'，等于这一行不告诉用户做多久。
      expect(find.text('—'), findsNothing,
          reason: '热身行必须念出处方（1 组 · 30–45 秒）');
      expect(find.textContaining('1 组 · 30–45 秒'), findsWidgets);
    });
}