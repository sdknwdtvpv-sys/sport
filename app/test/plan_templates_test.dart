/// 练了么 · **内置计划模板** 与「把建议存成计划」（2026-10-01）
///
/// 这两件事是同一个功能的两面：**给"不知道怎么搭计划"的人一个起点**。
///   * 内置模板：`plan_templates.dart` 里 5 套，从空态就能一键建出计划；
///   * 建议存成计划：把今天摇出来的那套存下来，明天不用重新摇。
///
/// 这个文件钉三件事：
///   1. **模板本身是合法的**：每个 `exerciseId` 在种子库里真的存在、
///      组数/次数区间合理、每套 3–4 个动作（太长没人用）；
///   2. **落库正确**：`createFromPlan` 建出来的计划，动作顺序与处方与模板逐项一致，
///      而且 `source` 记得住"它从哪来"（builtin / suggested）—— 没有这个字段，
///      "新手到底用不用模板"就只能靠猜；
///   3. **界面真的能给到**：空态（最需要模板的人）也要看得见模板行。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/routine_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/routine/plan_templates.dart';
import 'package:lianleme/features/routine/routine_screen.dart';

void main() {
  late AppDatabase db;
  late ExerciseRepository exercises;
  late RoutineRepository routines;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    exercises = ExerciseRepository(db);
    routines = RoutineRepository(db);
    await exercises.importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
  });

  tearDown(() => db.close());

  group('内置模板本身', () {
    test('每套 3–4 个动作（计划太长没人用）', () {
      expect(kPlanTemplates.length, greaterThanOrEqualTo(3),
          reason: '至少覆盖"全身 / 分化 / 时间紧"这几种最常见的落法');
      for (final PlanTemplate t in kPlanTemplates) {
        expect(t.items.length, inInclusiveRange(3, 4), reason: '${t.name} 的动作数');
        expect(t.name.trim(), isNotEmpty);
        expect(t.note.trim(), isNotEmpty, reason: '${t.name} 缺少"它适合谁"那一句');
      }
    });

    test('模板 id 不重复（界面 key 与测试都用它）', () {
      final Set<String> ids = kPlanTemplates.map((PlanTemplate t) => t.id).toSet();
      expect(ids.length, kPlanTemplates.length);
    });

    test('动作都在动作库里，组数与次数区间都合理', () async {
      for (final PlanTemplate t in kPlanTemplates) {
        for (final PlanTemplateItem it in t.items) {
          final ExerciseData? e = await exercises.byId(it.exerciseId);
          expect(e, isNotNull,
              reason: '${t.name} 里的 ${it.exerciseId} 在动作库里找不到 —— 模板要跟着种子改');
          expect(it.sets, inInclusiveRange(1, 5), reason: '${e!.name} 的组数');
          expect(it.repsLow, greaterThan(0), reason: '${e.name} 的次数下限');
          expect(it.repsHigh, greaterThanOrEqualTo(it.repsLow),
              reason: '${e.name} 的次数区间反了');
          // 按时长动作的"次数"其实是秒：30 秒起步才说得通（8 秒的平板支撑是记错了）
          if (e.trackType == 'time') {
            expect(it.repsLow, greaterThanOrEqualTo(15),
                reason: '${e.name} 是按时长动作，这里应当写秒数（≥15 秒）');
          }
        }
      }
    });
  });

  group('从模板/建议建计划', () {
    test('从模板建：动作顺序、处方、source 都逐项对上', () async {
      final PlanTemplate t = kPlanTemplates.first;
      final RoutineData r = await routines.createFromPlan(
        t.name,
        <({String exerciseId, PlanTarget plan})>[
          for (final PlanTemplateItem it in t.items)
            (exerciseId: it.exerciseId, plan: planTargetOf(it)),
        ],
        source: 'builtin',
      );

      expect(r.name, t.name);
      expect(r.source, 'builtin', reason: '要记得住"它从模板来"');

      final List<RoutineItemData> items = await routines.items(r.id);
      expect(items.length, t.items.length);
      for (int i = 0; i < items.length; i++) {
        expect(items[i].exerciseId, t.items[i].exerciseId, reason: '第 ${i + 1} 个动作的顺序');
        expect(items[i].position, i, reason: 'position 按传进来的顺序落');
        expect(items[i].targetSets, t.items[i].sets);
        expect(items[i].targetRepsLow, t.items[i].repsLow);
        expect(items[i].targetRepsHigh, t.items[i].repsHigh);
      }
    });

    test('从建议建：source 记成 suggested（两者共用同一条建库路径）', () async {
      final RoutineData r = await routines.createFromPlan(
        '胸 · 建议',
        <({String exerciseId, PlanTarget plan})>[
          (
            exerciseId: 'ex_bb_bench_press',
            plan: const PlanTarget(targetSets: 4, targetRepsLow: 8, targetRepsHigh: 12),
          ),
        ],
        source: 'suggested',
      );
      expect(r.source, 'suggested');
      final List<RoutineItemData> items = await routines.items(r.id);
      expect(items.single.exerciseId, 'ex_bb_bench_press');
      expect(items.single.targetSets, 4);
    });

    test('自建仍然是 user（默认值不能让老路径变了）', () async {
      final RoutineData r = await routines.create('我的计划');
      expect(r.source, 'user');
    });
  });

  group('界面：模板要给得到', () {
    Future<void> pumpList(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: RoutineListScreen(repository: routines, exercises: exercises),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('一份计划都没有时，空态里也要看得到模板（最需要它的人在这里）',
        (WidgetTester tester) async {
      await pumpList(tester);

      for (final PlanTemplate t in kPlanTemplates) {
        expect(find.byKey(Key('template-${t.id}')), findsOneWidget,
            reason: '空态里应当能看到「${t.name}」');
      }
    });

    testWidgets('点一个模板 → 真的建出计划（不是只摆一行字）',
        (WidgetTester tester) async {
      await pumpList(tester);

      final PlanTemplate t = kPlanTemplates.first;
      await tester.tap(find.byKey(Key('template-${t.id}')));
      await tester.pumpAndSettle();

      final List<RoutineData> rows = await routines.routines();
      expect(rows.length, 1, reason: '点一下就该建出一份计划');
      expect(rows.single.name, t.name);
      expect(rows.single.source, 'builtin');
      expect((await routines.items(rows.single.id)).length, t.items.length);
    });
  });
}
