/// 练了么 · 「今天的安排」：落库 + 长按拖动/替换/删除
/// （2026-10-09，10.9 清单第 6 条）
///
/// 用户原话：「今天的安排」要能长按拖动调整顺序 / 删除 / 替换动作。
/// 而这件事的前提是**那份安排得先存得下来** —— 它原来是每次冷启动现算的
/// （`TodayPlanner.planToday`），改了没地方存，而且同一天里再打开可能换一批动作。
///
/// 所以这个文件分三层：
///   1. **仓库**：存了什么、读回来什么、空清单也存得住（"我删光了"必须算数）；
///   2. **编辑器**：拖动真的换了顺序、替换换了动作但**不动组数次数**、删除就没了；
///   3. **整个 App**：库里那份说了算（第一天生成、第二天重排）。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout, kPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/data/day_plan_repository.dart';
// db.dart（drift）与 models.dart 都定义了 SetRecord / Workout，预先 hide。
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/today/day_plan_editor.dart';
import 'package:lianleme/features/today/today_planner.dart';
import 'package:lianleme/main.dart';

RoutineEntry _entry(String id, {int sets = 3}) => RoutineEntry(
      exerciseId: id,
      plan: PlanTarget(targetSets: sets, targetRepsLow: 8, targetRepsHigh: 12),
    );

void main() {
  late AppDatabase db;
  late String seedJson;
  final String today = dayPlanKey(DateTime(2026, 10, 9));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    seedJson = await File('assets/exercises.json').readAsString();
  });

  tearDown(() => db.close());

  group('仓库：存得住、读得回、空清单也算数', () {
    test('没排过 → hasPlan false、load 空', () async {
      final DayPlanRepository repo = DayPlanRepository(db);
      expect(await repo.hasPlan(today), isFalse);
      expect(await repo.load(today), isEmpty);
    });

    test('存两个动作，读回来**顺序一模一样**', () async {
      final DayPlanRepository repo = DayPlanRepository(db);
      await repo.save(today, <RoutineEntry>[
        _entry('ex_bb_squat', sets: 5),
        _entry('ex_bb_bench_press'),
      ], nowMs: 1000);

      expect(await repo.hasPlan(today), isTrue);
      final List<RoutineEntry> back = await repo.load(today);
      expect(back.map((RoutineEntry e) => e.exerciseId),
          <String>['ex_bb_squat', 'ex_bb_bench_press']);
      expect(back.first.plan.targetSets, 5, reason: '处方也要原样回来');
    });

    test('再存一次是覆盖（不是追加) —— 拖动之后重排就靠它', () async {
      final DayPlanRepository repo = DayPlanRepository(db);
      await repo.save(today, <RoutineEntry>[_entry('a'), _entry('b')], nowMs: 1000);
      await repo.save(today, <RoutineEntry>[_entry('b'), _entry('a')], nowMs: 2000);

      expect((await repo.load(today)).map((RoutineEntry e) => e.exerciseId),
          <String>['b', 'a']);
    });

    test('★ 空清单也存得住（用户把今天的动作全删了）', () async {
      final DayPlanRepository repo = DayPlanRepository(db);
      await repo.save(today, <RoutineEntry>[_entry('a')], nowMs: 1000);
      await repo.save(today, const <RoutineEntry>[], nowMs: 2000);

      expect(await repo.load(today), isEmpty);
      expect(await repo.hasPlan(today), isTrue,
          reason: '"我删光了"必须算数 —— 否则下次冷启动那批动作又冒出来，'
              '用户会以为删除按钮是坏的');
    });

    test('别的日子互不影响', () async {
      final DayPlanRepository repo = DayPlanRepository(db);
      await repo.save('2026-10-09', <RoutineEntry>[_entry('a')], nowMs: 1000);
      expect(await repo.hasPlan('2026-10-10'), isFalse);
      expect(await repo.load('2026-10-10'), isEmpty);
    });

    test('清理老日子：只留最近 N 天（这张表每天都会长几行）', () async {
      final DayPlanRepository repo = DayPlanRepository(db);
      await repo.save('2026-01-01', <RoutineEntry>[_entry('old')], nowMs: 1000);
      await repo.save('2026-10-08', <RoutineEntry>[_entry('yesterday')], nowMs: 1000);
      await repo.save('2026-10-09', <RoutineEntry>[_entry('today')], nowMs: 1000);

      await repo.pruneBefore('2026-10-09', keepDays: 30);

      expect(await repo.hasPlan('2026-01-01'), isFalse, reason: '半年前那份没人要了');
      expect(await repo.hasPlan('2026-10-08'), isTrue, reason: '最近 30 天留着');
      expect(await repo.hasPlan('2026-10-09'), isTrue, reason: '当天永远不动');
    });

    test('日期键是**本地日**（YYYY-MM-DD），不是带时分的 ISO 串', () {
      expect(dayPlanKey(DateTime(2026, 10, 9, 23, 59)), '2026-10-09');
      expect(dayPlanKey(DateTime(2026, 1, 5)), '2026-01-05');
    });
  });

  group('编辑器：拖动 / 替换 / 删除', () {
    late ExerciseRepository exercises;
    late DriftLocalStore store;
    late TodayPlanner planner;
    late List<PlannedExercise> plan;

    setUp(() async {
      exercises = ExerciseRepository(db);
      store = DriftLocalStore(db);
      planner = TodayPlanner(repository: exercises, store: store);
      await exercises.importSeed(loadJson: () => File('assets/exercises.json').readAsString());
      plan = await planner.planFromRoutine(
        entries: <RoutineEntry>[
          _entry('ex_bb_bench_press'),
          _entry('ex_bb_squat'),
          _entry('ex_deadlift'),
        ],
      );
      expect(plan.length, 3, reason: '前置：三个动作都在库里');
    });

    /// 弹层「完成」之后拿到的那份清单（没点完成就是 null）。
    List<PlannedExercise>? edited;

    /// 打开编辑器。⚠️ **不返回结果** —— 结果是用户点「完成」之后才有的，
    /// 落在这个 group 的 `edited` 里。
    Future<void> openEditor(WidgetTester tester) async {
      edited = null;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open-editor'),
                onPressed: () async {
                  edited = await showDayPlanEditor(
                    ctx,
                    plan: plan,
                    planner: planner,
                    repository: exercises,
                    store: store,
                    unit: WeightUnit.kg,
                  );
                },
                child: const Text('编辑'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('open-editor')));
      await tester.pumpAndSettle();
    }

    testWidgets('打开时列出全部动作，并写着"长按可以拖动"',
        (WidgetTester tester) async {
      await openEditor(tester);
      expect(find.byKey(const Key('plan-editor')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('plan-edit-ex_bb_bench_press')),
          findsOneWidget);
      expect(find.textContaining('长按一行可以拖动排序'), findsOneWidget);
      // 只改"练哪几个"，不改组数次数 —— 这句话要摆在明处
      expect(find.textContaining('组数次数不动'), findsOneWidget);
    });

    testWidgets('★ 长按拖动真的换顺序，并且一直换到"完成"的结果里',
        (WidgetTester tester) async {
      await openEditor(tester);

      // 长按第一个（延迟拖动把手）→ 拖到最后一行**下面**（拖到中间只会换一格）。
      // ⚠️ 手势要按 Flutter 自己测 `ReorderableListView` 的那套节奏来：
      // 每一步之间 `pump(kPressTimeout)`。全程 `pump()`（零时长）时，
      // 拖动列表**一次回调都不会收到** —— 这一条就是这么试出来的。
      final Finder last =
          find.byKey(const ValueKey<String>('plan-edit-ex_deadlift'));
      // ⚠️ 起点取**动作名那个 Text 的中心**，不取整行的中心：
      // 整行盒子里有拖动手柄、名字、两个按钮，而"长按哪里"必须是**看得见的那块内容**
      // （Flutter 自己测 ReorderableListView 也是从 item 的文字上开始按的）
      final TestGesture drag =
          await tester.startGesture(tester.getCenter(find.text('杠铃卧推')));
      await tester.pump(kLongPressTimeout + kPressTimeout);
      await drag.moveTo(tester.getCenter(last) + const Offset(0, 40));
      await tester.pump(kPressTimeout);
      await drag.moveBy(const Offset(0, 40));
      await tester.pump(kPressTimeout);
      await drag.up();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('plan-edit-done')));
      await tester.pumpAndSettle();

      expect(edited, isNotNull, reason: '点了完成就该拿到新清单');
      expect(edited!.map((PlannedExercise e) => e.exercise.id).toList(),
          <String>['ex_bb_squat', 'ex_deadlift', 'ex_bb_bench_press'],
          reason: '第一个动作被拖到最后 —— 顺序就是用户拖出来的那一个');
    });

    testWidgets('删掉一个 → 完成之后清单里就没有它了',
        (WidgetTester tester) async {
      await openEditor(tester);
      await tester.tap(find.byKey(const Key('plan-edit-delete-ex_bb_squat')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('plan-edit-ex_bb_squat')), findsNothing);

      await tester.tap(find.byKey(const Key('plan-edit-done')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plan-editor')), findsNothing, reason: '完成要关掉弹层');
    });

    testWidgets('全删光 → 弹层如实说"都删光了"，并指出「换一批」那条出路',
        (WidgetTester tester) async {
      await openEditor(tester);
      for (final String id in <String>['ex_bb_bench_press', 'ex_bb_squat', 'ex_deadlift']) {
        await tester.tap(find.byKey(Key('plan-edit-delete-$id')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('plan-edit-empty')), findsOneWidget);
    });

    testWidgets('★ 替换：换成同部位的另一个动作，**组数次数沿用原来那一格**',
        (WidgetTester tester) async {
      await openEditor(tester);
      await tester.tap(find.byKey(const Key('plan-edit-replace-ex_bb_bench_press')));
      await tester.pumpAndSettle();

      // 打开的是动作选择器（同一个页面，训练里"换动作"也是它）
      expect(find.byKey(const Key('exercise-search')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('exercise-search')), '上斜');
      await tester.pumpAndSettle();
      // 按 key 点那一行（按文字点容易落到别的 Text 上）
      await tester.tap(find.byKey(const Key('exercise-ex_bb_incline_bench_press')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('plan-edit-ex_bb_incline_bench_press')),
          findsOneWidget, reason: '新动作应当顶掉原来那一格');
      expect(find.byKey(const ValueKey<String>('plan-edit-ex_bb_bench_press')), findsNothing);
      // 完成之后带回来的那份里，这一格就是新动作
      await tester.tap(find.byKey(const Key('plan-edit-done')));
      await tester.pumpAndSettle();
      expect(edited!.map((PlannedExercise e) => e.exercise.id).toList(),
          <String>['ex_bb_incline_bench_press', 'ex_bb_squat', 'ex_deadlift']);
      expect(edited!.first.plan.targetSets, 3, reason: '组数沿用原来那一格');
    });
  });

  // ── 整个 App：库里那份说了算 ─────────────────────────────────────────────
  group('整个 App', () {
    Future<void> pumpApp(WidgetTester tester) async {
      await ProfileRepository(db).setPrivacyConsent(nowMs: 1);
      await tester.pumpWidget(LianLeMeApp(
        database: db,
        seedLoader: () async => seedJson,
      ));
      await tester.pumpAndSettle();
    }

    Future<void> teardown(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }

    testWidgets('第一次打开：算一份并**落库**（下次不再换一批）',
        (WidgetTester tester) async {
      final String key = dayPlanKey(DateTime.now());
      await pumpApp(tester);

      final List<RoutineEntry> saved = await DayPlanRepository(db).load(key);
      expect(saved, isNotEmpty, reason: '首页显示的那份必须存下来，否则"改了没法存"');
      // 首页那块至少有 1 行 —— 而且它显示的就是库里那一份（同一次生成的）
      expect(find.byKey(const Key('today-plan-row-0')), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('库里有今天那一份时**以它为准**（哪怕只有一个动作）',
        (WidgetTester tester) async {
      final String key = dayPlanKey(DateTime.now());
      await DayPlanRepository(db).save(key, <RoutineEntry>[_entry('ex_bb_squat')], nowMs: 1000);

      await pumpApp(tester);

      // 首页那块只该有 1 行（现算的话会是 4–6 个动作）
      expect(find.byKey(const Key('today-plan-row-0')), findsOneWidget);
      expect(find.byKey(const Key('today-plan-row-1')), findsNothing,
          reason: '库里只有一个动作，就只显示一个 —— 现算会把它撑成 4–6 行');

      await teardown(tester);
    });

    testWidgets('库里的空清单也说了算（用户删光了，不许又冒出来）',
        (WidgetTester tester) async {
      final String key = dayPlanKey(DateTime.now());
      await DayPlanRepository(db).save(key, const <RoutineEntry>[], nowMs: 1000);

      await pumpApp(tester);

      expect(find.text('今天还没有排动作'), findsOneWidget);
      expect(find.byKey(const Key('today-plan-row-0')), findsNothing);

      await teardown(tester);
    });

    testWidgets('★ 长按首页那一行 → 弹出编辑器；删一个再完成 → 库里跟着变',
        (WidgetTester tester) async {
      final String key = dayPlanKey(DateTime.now());
      await DayPlanRepository(db).save(key, <RoutineEntry>[
        _entry('ex_bb_bench_press'),
        _entry('ex_bb_squat'),
      ], nowMs: 1000);

      await pumpApp(tester);
      expect(find.byKey(const Key('today-plan-hint')), findsOneWidget,
          reason: '"能长按"这件事必须被看见');

      await tester.longPress(find.byKey(const Key('today-plan-row-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plan-editor')), findsOneWidget);

      await tester.tap(find.byKey(const Key('plan-edit-delete-ex_bb_bench_press')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plan-edit-done')));
      await tester.pumpAndSettle();

      final List<RoutineEntry> saved = await DayPlanRepository(db).load(key);
      expect(saved.map((RoutineEntry e) => e.exerciseId), <String>['ex_bb_squat'],
          reason: '弹层里删掉的必须写回库 —— 否则下次冷启动它又回来了');

      await teardown(tester);
    });
  });
}
