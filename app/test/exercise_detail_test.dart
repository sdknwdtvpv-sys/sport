/// 练了么 · 动作详情页测试
///
/// 分两层：
///   * **纯逻辑**（按天归并、两个 JSON 列的读取）—— 日期边界与坏数据在这里测全
///   * **界面** —— 只测"有没有把该说的话摆出来"，尤其两条诚实性：
///     没写说明时不留空、没 store 时不假装有历史
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/data/db.dart'
    hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_data_ext.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/exercise/exercise_detail_screen.dart';
import 'package:lianleme/features/progress/all_data.dart';

void main() {
  // ─────────────────────────────────────── 纯逻辑

  group('按天归并（详情页的"最近几次"）', () {
    SetRecord set({
      required String id,
      required DateTime at,
      int reps = 8,
      double? weightKg = 60,
      int setIndex = 1,
      SetType type = SetType.normal,
    }) =>
        SetRecord(
          id: id,
          workoutId: 'w_${id}',
          exerciseId: 'ex_x',
          setIndex: setIndex,
          reps: reps,
          completedAtMs: at.millisecondsSinceEpoch,
          weightKg: weightKg,
          setType: type,
        );

    test('同一天的多组并成一条，最近的排在前面', () {
      final List<ExerciseDayEntry> days = groupSetsByDay(<SetRecord>[
        set(id: 'a', at: DateTime(2026, 9, 28, 9)),
        set(id: 'b', at: DateTime(2026, 9, 28, 9, 5), setIndex: 2),
        set(id: 'c', at: DateTime(2026, 9, 26, 9)),
      ]);
      expect(days.length, 2);
      expect(days[0].date, '2026-09-28');
      expect(days[0].setCount, 2);
      expect(days[1].date, '2026-09-26');
    });

    test('按天归并时按组序排好（不是按写入顺序）', () {
      final List<ExerciseDayEntry> days = groupSetsByDay(<SetRecord>[
        set(id: 'c', at: DateTime(2026, 9, 28, 9, 20), setIndex: 3),
        set(id: 'a', at: DateTime(2026, 9, 28, 9), setIndex: 1),
        set(id: 'b', at: DateTime(2026, 9, 28, 9, 10), setIndex: 2),
      ]);
      expect(days.single.sets.map((SetRecord s) => s.id).toList(),
          <String>['a', 'b', 'c']);
    });

    test('热身组不算进"练成什么样"（它是准备动作，不是训练量）', () {
      final List<ExerciseDayEntry> days = groupSetsByDay(<SetRecord>[
        set(id: 'w', at: DateTime(2026, 9, 28, 9), type: SetType.warmup),
        set(id: 'n', at: DateTime(2026, 9, 28, 9, 10)),
      ]);
      expect(days.single.setCount, 1);
      expect(days.single.sets.single.id, 'n');
    });

    test('只有热身组的那一天整条不出现（不留一个空壳）', () {
      final List<ExerciseDayEntry> days = groupSetsByDay(<SetRecord>[
        set(id: 'w', at: DateTime(2026, 9, 28, 9), type: SetType.warmup),
      ]);
      expect(days, isEmpty);
    });

    test('limit 只取最近几天', () {
      final List<ExerciseDayEntry> days = groupSetsByDay(<SetRecord>[
        for (int d = 20; d < 30; d++) set(id: 's$d', at: DateTime(2026, 9, d, 9)),
      ], limit: 3);
      expect(days.length, 3);
      expect(days.map((ExerciseDayEntry e) => e.date).toList(),
          <String>['2026-09-29', '2026-09-28', '2026-09-27']);
    });

    test('跨天用本地时间切（23:59 与次日 00:01 是两天）', () {
      final List<ExerciseDayEntry> days = groupSetsByDay(<SetRecord>[
        set(id: 'a', at: DateTime(2026, 9, 28, 23, 59)),
        set(id: 'b', at: DateTime(2026, 9, 29, 0, 1)),
      ]);
      expect(days.map((ExerciseDayEntry e) => e.date).toList(),
          <String>['2026-09-29', '2026-09-28']);
    });
  });

  group('挑"历史最好"的那一组', () {
    SetRecord set(String id,
            {double? kg, int reps = 8, int setIndex = 1,
            SetType type = SetType.normal}) =>
        SetRecord(
          id: id,
          workoutId: 'w',
          exerciseId: 'ex_x',
          setIndex: setIndex,
          reps: reps,
          completedAtMs: DateTime(2026, 9, 28, 9).millisecondsSinceEpoch,
          weightKg: kg,
          setType: type,
        );

    test('负重：比 1RM，而不是"最重那组的重量 + 最多次数那组的次数"', () {
      // 40kg×8 与 24kg×10：1RM 都是约 49.3 vs 32，所以最好的是 40kg 那组
      final SetRecord? best = bestSetOf(<SetRecord>[
        set('a', kg: 40, reps: 8),
        set('b', kg: 24, reps: 10),
      ]);
      expect(best!.id, 'a');
      expect(best.weightKg, 40);
      expect(best.reps, 8, reason: '必须是这一组自己的次数');
    });

    test('同样重量比次数：60kg×10 强于 60kg×8', () {
      final SetRecord? best = bestSetOf(<SetRecord>[
        set('a', kg: 60, reps: 8),
        set('b', kg: 60, reps: 10),
      ]);
      expect(best!.id, 'b');
    });

    test('自重动作比次数', () {
      final SetRecord? best = bestSetOf(<SetRecord>[
        set('a', reps: 8),
        set('b', reps: 12),
      ]);
      expect(best!.id, 'b');
      expect(best.reps, 12);
    });

    test('按时长动作比秒数（isTime=true）', () {
      final SetRecord? best = bestSetOf(<SetRecord>[
        set('a', reps: 30),
        set('b', reps: 45),
      ], isTime: true);
      expect(best!.reps, 45);
    });

    test('热身组不参选；全是热身组时返回 null', () {
      final SetRecord? best = bestSetOf(<SetRecord>[
        set('w', kg: 100, reps: 5, type: SetType.warmup),
        set('n', kg: 60, reps: 8),
      ]);
      expect(best!.id, 'n');
      expect(bestSetOf(<SetRecord>[
        set('w', kg: 100, type: SetType.warmup),
      ]), isNull);
    });
  });

  group('两个 JSON 文本列的读取', () {
    ExerciseData row({String aliases = '[]', String secondary = '[]'}) =>
        ExerciseData(
          id: 'ex_x',
          name: '扣篮',
          aliases: aliases,
          muscleGroup: 'chest',
          secondaryMuscles: secondary,
          equipment: 'barbell',
          category: 'strength',
          trackType: 'weight_reps',
          defaultRestSec: 90,
          weightIncrement: 1,
          isBuiltin: true,
          popularity: 50,
          createdAt: 0,
          updatedAt: 0,
        );

    test('正常 JSON 数组解析成列表', () {
      final ExerciseData e =
          row(aliases: '["bp","卧推"]', secondary: '["lats","biceps"]');
      expect(e.aliasList, <String>['bp', '卧推']);
      expect(e.secondaryMuscleList, <String>['lats', 'biceps']);
    });

    test('空数组与空串都是空列表（不是 [""]）', () {
      expect(row().aliasList, isEmpty);
      expect(row(aliases: '').aliasList, isEmpty);
      expect(row(aliases: '   ').aliasList, isEmpty);
    });

    test('坏 JSON 当作空，绝不抛（详情页不能因为一个标签打不开）', () {
      expect(row(aliases: 'bp, 卧推').aliasList, isEmpty);
      expect(row(aliases: '{').aliasList, isEmpty);
      expect(row(aliases: '{"a":1}').aliasList, isEmpty);
    });

    test('数组里混了非字符串 / 空白项时过滤掉，而不是崩', () {
      expect(row(aliases: '["bp", 1, null, "  ", "卧推"]').aliasList,
          <String>['bp', '卧推']);
    });
  });

  // ─────────────────────────────────────── 界面

  group('界面', () {
    late AppDatabase db;
    late DriftLocalStore store;
    late ExerciseRepository repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      store = DriftLocalStore(db);
      repo = ExerciseRepository(db);
      await repo.importSeed(
        loadJson: () => File('assets/exercises.json').readAsString(),
      );
    });

    tearDown(() => db.close());

    Future<ExerciseData> pick(String id) async {
      final ExerciseData? e = await repo.byId(id);
      return e!;
    }

    Future<void> pump(WidgetTester tester, ExerciseData e, {bool withStore = true}) async {
      await tester.pumpWidget(MaterialApp(
        home: ExerciseDetailScreen(
          exercise: e,
          store: withStore ? store : null,
          today: DateTime(2026, 9, 28, 10),
          unit: WeightUnit.kg,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('动作说明完整显示出来（这是点进来的主要目的）', (WidgetTester tester) async {
      final ExerciseData e = await pick('ex_goblet_squat');
      await pump(tester, e);
      expect(find.byKey(const Key('detail-instructions')), findsOneWidget);
      expect(find.textContaining('哑铃抱在胸前'), findsOneWidget);
    });

    testWidgets('没写过说明时如实说，而不是留一个空框', (WidgetTester tester) async {
      // 造一个没有说明的动作（自定义动作就是这种）
      final ExerciseData e = ExerciseData(
        id: 'ex_custom_1',
        name: '我自己加的动作',
        aliases: '[]',
        muscleGroup: 'chest',
        secondaryMuscles: '[]',
        equipment: 'dumbbell',
        category: 'strength',
        trackType: 'weight_reps',
        defaultRestSec: 90,
        weightIncrement: 2.5,
        isBuiltin: false,
        popularity: 0,
        createdAt: 0,
        updatedAt: 0,
      );
      await pump(tester, e, withStore: false);
      expect(find.byKey(const Key('detail-instructions-missing')), findsOneWidget);
      expect(find.byKey(const Key('detail-instructions')), findsNothing);
    });

    testWidgets('没给 store 时不显示历史区，也不假装"还没练过"', (WidgetTester tester) async {
      final ExerciseData e = await pick('ex_goblet_squat');
      await pump(tester, e, withStore: false);
      expect(find.text('我以前练成什么样'), findsNothing);
      expect(find.byKey(const Key('detail-no-history')), findsNothing);
    });

    testWidgets('没练过的动作：明说还没练过（而不是一排 0）', (WidgetTester tester) async {
      final ExerciseData e = await pick('ex_goblet_squat');
      await pump(tester, e);
      expect(find.byKey(const Key('detail-no-history')), findsOneWidget);
      expect(find.textContaining('这个动作你还没练过'), findsOneWidget);
    });

    testWidgets('练过之后：显示历史最好、总组数与"最近几次"', (WidgetTester tester) async {
      Future<void> save(String id, DateTime at, {int reps = 8, double kg = 40}) =>
          store.saveSet(SetRecord(
            id: id,
            workoutId: 'w_$id',
            exerciseId: 'ex_goblet_squat',
            setIndex: 1,
            reps: reps,
            completedAtMs: at.millisecondsSinceEpoch,
            weightKg: kg,
          ));

      await save('a', DateTime(2026, 9, 26, 9), reps: 8, kg: 40);
      await save('b', DateTime(2026, 9, 28, 9), reps: 10, kg: 24);
      await save('c', DateTime(2026, 9, 28, 9, 5), reps: 9, kg: 24);

      final ExerciseData e = await pick('ex_goblet_squat');
      await pump(tester, e);

      expect(find.text('我以前练成什么样'), findsOneWidget);
      expect(find.byKey(const Key('detail-best')), findsOneWidget);
      // 历史最好 = 最大重量那一组（40kg × 8），不是最近那次
      expect(find.text('40 kg × 8'), findsOneWidget);
      expect(find.text('3 组'), findsOneWidget);
      // 最近两次：9/28 两组、9/26 一组
      expect(find.byKey(const Key('detail-day-2026-09-28')), findsOneWidget);
      expect(find.byKey(const Key('detail-day-2026-09-26')), findsOneWidget);
      expect(find.textContaining('2 组 · 24 kg × 10 · 9'), findsOneWidget);
    });

    /// ⚠️ 自重与按时长**必须分成两条测试**：同一个测试里二次 pumpWidget 会复用
    /// 同一个 State（同类型、无 key），`initState` 不会再跑，历史仍是上一个动作的
    /// —— 第一版就是这么误报"45 秒找不到"的。
    Future<void> saveOne(String id, String exId, {int reps = 8, double? kg}) =>
        store.saveSet(SetRecord(
          id: id,
          workoutId: 'w_$id',
          exerciseId: exId,
          setIndex: 1,
          reps: reps,
          completedAtMs: DateTime(2026, 9, 28, 9).millisecondsSinceEpoch,
          weightKg: kg,
        ));

    testWidgets('自重动作的"历史最好"比次数（不说"0 kg"）', (WidgetTester tester) async {
      await saveOne('p1', 'ex_pull_up', reps: 8);
      await pump(tester, await pick('ex_pull_up'));
      expect(find.text('8 次'), findsOneWidget);
      expect(find.textContaining('0 kg'), findsNothing);
    });

    testWidgets('按时长动作的"历史最好"比秒数（不说"0 kg"）', (WidgetTester tester) async {
      await saveOne('t1', 'ex_plank', reps: 45);
      await pump(tester, await pick('ex_plank'));
      expect(find.text('45 秒'), findsOneWidget);
    });
  });
}
