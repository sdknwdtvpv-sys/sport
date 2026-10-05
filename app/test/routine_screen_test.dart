/// 练了么 · S11 计划模板界面测试
///
/// 仓库层的语义在 `routine_repository_test.dart` 里测过了。
/// 这里测"建一个计划到开始训练"这条完整路径走得通。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/routine_repository.dart';
import 'package:lianleme/features/routine/routine_screen.dart';

void main() {
  late AppDatabase db;
  late RoutineRepository routines;
  late ExerciseRepository exercises;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    routines = RoutineRepository(db);
    exercises = ExerciseRepository(db);
    await exercises.importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
  });

  tearDown(() => db.close());

  Future<void> pumpList(WidgetTester tester,
      {List<RoutineStart>? popped, LocalStore? store}) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Builder(
        builder: (BuildContext ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final RoutineStart? s =
                    await Navigator.of(ctx).push<RoutineStart>(
                  MaterialPageRoute<RoutineStart>(
                    builder: (_) => RoutineListScreen(
                      repository: routines,
                      exercises: exercises,
                      store: store,
                    ),
                  ),
                );
                if (s != null) popped?.add(s);
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('还没有计划时给出下一步，而不是一片空白',
      (WidgetTester tester) async {
    await pumpList(tester);

    expect(find.textContaining('还没有计划'), findsOneWidget);
    expect(find.byKey(const Key('routine-create')), findsOneWidget);
  });

  testWidgets('「新建」建出计划并直接进编辑页', (WidgetTester tester) async {
    await pumpList(tester);

    await tester.tap(find.byKey(const Key('routine-create')));
    await tester.pumpAndSettle();

    expect(find.text('编辑计划'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('routine-name'))).controller!.text,
      '新计划',
    );
    expect(find.textContaining('还没有动作'), findsOneWidget);
  });

  testWidgets('加动作 → 列表里出现它，且默认 3 组 8–10 次',
      (WidgetTester tester) async {
    final RoutineData r = await routines.create('推日', nowMs: 1000);
    final RoutineItemData item =
        await routines.addItem(r.id, 'ex_bb_bench_press', nowMs: 1001);

    await pumpList(tester);
    await tester.tap(find.byKey(Key('routine-open-${r.id}')));
    await tester.pumpAndSettle();

    expect(find.text('杠铃卧推'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(Key('routine-item-label-${item.id}'))).data,
      '3 组 · 8–10 次',
    );
  });

  testWidgets('★ 从计划编辑页进选择器时，置顶/最近做过分区也在（顺手补的一处不一致）',
      (WidgetTester tester) async {
    // 由来：选择器有三条入口，而「计划 → 加动作」那条**没传 store** ——
    // 于是同一个页面从训练流程进来有"置顶/最近做过"、从计划进来没有。
    final LocalStore store = DriftLocalStore(db);
    await store.setPinnedExerciseIds(<String>['ex_bb_squat']);
    final RoutineData r = await routines.create('推日', nowMs: 1000);

    await pumpList(tester, store: store);
    await tester.tap(find.byKey(Key('routine-open-${r.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routine-add-exercise')));
    await tester.pumpAndSettle();

    expect(find.text('置顶'), findsOneWidget,
        reason: '这条路径也必须看得到置顶区（同一个页面不该因入口不同而两样）');
    expect(find.byKey(const Key('pin-ex_bb_squat')), findsOneWidget,
        reason: '星标要在 —— 否则这条路上用户根本订不了动作');
  });

  testWidgets('点一项可以改组数与次数区间（简化版能改的就这两样）',
      (WidgetTester tester) async {
    final RoutineData r = await routines.create('推日', nowMs: 1000);
    final RoutineItemData item =
        await routines.addItem(r.id, 'ex_bb_bench_press', nowMs: 1001);

    await pumpList(tester);
    await tester.tap(find.byKey(Key('routine-open-${r.id}')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('routine-item-${item.id}')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('set-5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reps-3-5')));
    await tester.pumpAndSettle();
    // 弹层内容在小屏上可能要滚一下才够得到「确定」
    await tester.ensureVisible(find.byKey(const Key('routine-item-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routine-item-save')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(Key('routine-item-label-${item.id}'))).data,
      '5 组 · 3–5 次',
    );
    // 落库了才算数
    final RoutineItemData after = (await routines.items(r.id)).single;
    expect(after.targetSets, 5);
    expect(after.targetRepsLow, 3);
    expect(after.targetRepsHigh, 5);
  });

  testWidgets('删项', (WidgetTester tester) async {
    final RoutineData r = await routines.create('推日', nowMs: 1000);
    final RoutineItemData item =
        await routines.addItem(r.id, 'ex_bb_bench_press', nowMs: 1001);

    await pumpList(tester);
    await tester.tap(find.byKey(Key('routine-open-${r.id}')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('routine-item-remove-${item.id}')));
    await tester.pumpAndSettle();

    expect(find.textContaining('还没有动作'), findsOneWidget);
    expect(await routines.items(r.id), isEmpty);
  });

  testWidgets('空计划点「开始训练」会提示，而不是走进一个空会话',
      (WidgetTester tester) async {
    final RoutineData r = await routines.create('空计划', nowMs: 1000);

    await pumpList(tester);
    await tester.tap(find.byKey(Key('routine-open-${r.id}')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('routine-start')));
    await tester.pumpAndSettle();

    expect(find.text('先加几个动作'), findsOneWidget);
  });

  testWidgets('有动作时点「开始训练」会把计划交回给调用方',
      (WidgetTester tester) async {
    final List<RoutineStart> popped = <RoutineStart>[];
    final RoutineData r = await routines.create('推日', nowMs: 1000);
    await routines.addItem(r.id, 'ex_bb_bench_press', nowMs: 1001);
    await routines.addItem(r.id, 'ex_bb_squat', targetSets: 5, nowMs: 1002);

    await pumpList(tester, popped: popped);
    await tester.tap(find.byKey(Key('routine-open-${r.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routine-start')));
    await tester.pumpAndSettle();

    expect(popped, hasLength(1));
    expect(popped.single.routine.name, '推日');
    expect(popped.single.items, hasLength(2));
    expect(popped.single.items[1].targetSets, 5,
        reason: '逐项的处方要原样带走，不能被默认值顶掉');
  });

  testWidgets('列表页的「开始」也能直接开训', (WidgetTester tester) async {
    final List<RoutineStart> popped = <RoutineStart>[];
    final RoutineData r = await routines.create('推日', nowMs: 1000);
    await routines.addItem(r.id, 'ex_bb_bench_press', nowMs: 1001);

    await pumpList(tester, popped: popped);
    await tester.tap(find.byKey(Key('routine-start-${r.id}')));
    await tester.pumpAndSettle();

    expect(popped, hasLength(1));
    expect(popped.single.items, hasLength(1));
  });

  testWidgets('列表页显示每个计划有几个动作', (WidgetTester tester) async {
    final RoutineData a = await routines.create('推日', nowMs: 1000);
    await routines.create('拉日', nowMs: 2000);
    await routines.addItem(a.id, 'ex_bb_bench_press', nowMs: 3000);

    await pumpList(tester);

    expect(find.text('1 个动作'), findsOneWidget);
    // ⚠️ 2026-10-01：列表页顶部多了「从模板开始」那一栏（5 行），
    // 「还没有动作」被挤到视口之外 —— ListView 懒构建，不滚过去就不存在。
    await tester.dragUntilVisible(find.text('还没有动作'), find.byType(ListView),
        const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.text('还没有动作'), findsOneWidget, reason: '拉日还是空的');
  });
}
