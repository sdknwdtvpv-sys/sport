/// 训练计划（三视图）的契约。
///
/// 这一屏最容易出的问题是**两处口径打架**：周历的"本周"与历史的"本周"要同一条边界
/// （都用周一起算），而且"今天的安排"必须与首页**同一份** —— 显示了 A 却练 B
/// 比不显示更糟。所以测试按这两条来钉。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/routine_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/routine/plan_screen.dart';
import 'package:lianleme/features/routine/routine_screen.dart';

String _seedJson() => '''
{"exercises": [
  {"id":"ex_bb_bench_press","name":"杠铃卧推","muscle_group":"chest","equipment":"barbell",
   "category":"strength","track_type":"weight_reps","default_rest_sec":120,"weight_increment":2.5},
  {"id":"ex_squat","name":"杠铃深蹲","muscle_group":"legs","equipment":"barbell",
   "category":"strength","track_type":"weight_reps","default_rest_sec":150,"weight_increment":5}
]}
''';

SetRecord _set(String workout, DateTime at, {double weight = 60, int reps = 8}) => SetRecord(
      id: '$workout-${at.millisecondsSinceEpoch}',
      workoutId: workout,
      exerciseId: 'ex_bb_bench_press',
      setIndex: 0,
      weightKg: weight,
      reps: reps,
      completedAtMs: at.millisecondsSinceEpoch,
    );

/// 2026-10-05 是**周一** —— 用它当"今天"，周历的边界一眼能算。
final DateTime kToday = DateTime(2026, 10, 5, 20);

Future<DriftLocalStore> _pump(
  WidgetTester tester, {
  List<SetRecord> sets = const <SetRecord>[],
  bool resume = false,
}) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final AppDatabase db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final DriftLocalStore store = DriftLocalStore(db);
  for (final SetRecord s in sets) {
    await store.saveSet(s);
  }
  final ExerciseRepository repo = ExerciseRepository(db);
  await repo.importSeed(loadJson: () async => _seedJson());

  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: PlanScreen(
        repository: RoutineRepository(db),
        exercises: repo,
        store: store,
        unit: WeightUnit.kg,
        now: kToday,
        onResume: resume ? () {} : null,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets('默认是「本周」：七天都在，今天是高亮的那个', (WidgetTester tester) async {
    await _pump(tester);
    for (int d = 5; d <= 11; d++) {
      expect(find.byKey(Key('week-10-$d')), findsOneWidget, reason: '10/$d 那一格不见了');
    }
    expect(find.text('周' '一'), findsOneWidget);
    expect(find.text('周' '日'), findsOneWidget);
  });

  testWidgets('周历显示的是**事实**：哪天练了几组，没练就是短横', (WidgetTester tester) async {
    await _pump(tester, sets: <SetRecord>[
      _set('w1', DateTime(2026, 10, 5, 9)),
      _set('w1', DateTime(2026, 10, 5, 9, 30)),
      _set('w2', DateTime(2026, 10, 7, 9)),
    ]);
    // 今天（10/5）两格：周历里显示 "2 组"；10/7 显示 "1 组"
    expect(find.text('2 组'), findsOneWidget);
    expect(find.text('1 组'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(5), reason: '另外五天没练');
  });

  testWidgets('切到「模板库」：嵌的是同一个 RoutineListScreen，而且只有一行标题',
      (WidgetTester tester) async {
    await _pump(tester);
    expect(find.byType(RoutineListScreen), findsNothing);
    await tester.tap(find.byKey(const Key('seg-模板库')));
    await tester.pumpAndSettle();
    expect(find.byType(RoutineListScreen), findsOneWidget);
    // 嵌入模式不该再印自己的返回箭头与标题（两个箭头会让人以为要退两层）
    expect(find.byKey(const Key('routine-back')), findsNothing);
    expect(find.text('训练计划'), findsOneWidget, reason: '标题只有外层这一个');
  });

  testWidgets('切到「历史」：按周分桶，本周/上周的数字对得上', (WidgetTester tester) async {
    await _pump(tester, sets: <SetRecord>[
      // 本周（10/5 周一之后）
      _set('w1', DateTime(2026, 10, 5, 9)),
      _set('w2', DateTime(2026, 10, 7, 9)),
      // 上周（9/28–10/4）
      _set('w3', DateTime(2026, 9, 30, 9)),
    ]);
    await tester.tap(find.byKey(const Key('seg-历史')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('history-本周')), findsOneWidget);
    expect(find.byKey(const Key('history-上周')), findsOneWidget);
    expect(find.textContaining('本周 · 2 次'), findsOneWidget);
    expect(find.textContaining('上周 · 1 次'), findsOneWidget);
    expect(find.byKey(const Key('history-row-w3')), findsOneWidget);
  });

  testWidgets('没练过 → 历史视图给一句人话（不是一块空白）', (WidgetTester tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('seg-历史')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan-history-empty')), findsOneWidget);
  });

  testWidgets('有没结束的训练时，本周视图给「接着练」；没有就不给', (WidgetTester tester) async {
    await _pump(tester, resume: true);
    expect(find.byKey(const Key('plan-resume')), findsOneWidget);
  });
}
