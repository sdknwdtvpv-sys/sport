/// 练了么 · 动作详情的**入口**测试
///
/// 详情页本身在 `exercise_detail_test.dart` 里测过了。这里只回答一件事：
/// **用户在两个该找到它的地方，能不能找到它。**
/// 功能做出来但没入口，等于没做 —— 而"没入口"没有任何断言会红，所以单独守。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/analytics.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart'
    hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/sync_queue.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/exercise/exercise_detail_screen.dart';
import 'package:lianleme/features/exercise/exercise_picker_screen.dart';
import 'package:lianleme/features/workout/workout_controller.dart';
import 'package:lianleme/features/workout/workout_screen.dart';
import 'package:lianleme/features/workout/workout_session.dart';

/// 与控制器用的 `ExerciseSpec` 对应的**完整动作库行**
/// （控制器手里只有瘦身过的 spec，详情页要的是这一份）
ExerciseData fullRow({
  String id = 'ex_squat',
  String name = '深蹲',
  String? instructions = '下蹲到髋低于膝，背全程中立。',
  String trackType = 'weight_reps',
}) =>
    ExerciseData(
      id: id,
      name: name,
      aliases: '["蹲"]',
      muscleGroup: 'legs',
      subTags: '[]',
      secondaryMuscles: '["glutes"]',
      equipment: 'barbell',
      category: 'strength',
      trackType: trackType,
      defaultRestSec: 120,
      instructions: instructions,
      weightIncrement: 2.5,
      isBuiltin: true,
      popularity: 90,
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  group('训练屏入口', () {
    const ExerciseSpec spec = ExerciseSpec(
      id: 'ex_squat',
      name: '深蹲',
      weightIncrement: 2.5,
      defaultWeightKg: 40,
      defaultRestSec: 120,
    );
    const PlanTarget plan = PlanTarget(
      targetSets: 3,
      targetRepsLow: 8,
      targetRepsHigh: 10,
    );

    late WorkoutController controller;
    late InMemoryLocalStore store;

    setUp(() {
      store = InMemoryLocalStore();
      controller = WorkoutController(
        exercise: spec,
        plan: plan,
        analytics: RecordingAnalytics(),
        store: store,
        syncQueue: InMemorySyncQueue(),
        clock: () => 1000,
      );
    });

    tearDown(() => controller.dispose());

    Future<void> pumpWorkout(WidgetTester tester, {bool withCatalog = true}) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: WorkoutScreen(
          session: WorkoutSession.single(controller),
          catalog:
              withCatalog ? <ExerciseData>[fullRow()] : const <ExerciseData>[],
          store: store,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('训练屏有看得见的详情入口，点开就是动作详情', (WidgetTester tester) async {
      await pumpWorkout(tester);
      expect(find.byKey(const Key('exercise-info')), findsOneWidget);

      await tester.tap(find.byKey(const Key('exercise-info')));
      await tester.pumpAndSettle();

      expect(find.byType(ExerciseDetailScreen), findsOneWidget);
      expect(find.textContaining('下蹲到髋低于膝'), findsOneWidget);
    });

    testWidgets('★ 第一组之前那块空白里摆着「动作要领」，并能点开完整说明', (WidgetTester tester) async {
      // 用户的反馈：「初始第一组的时候上边儿也太空了」（2026-10-11）。
      // 要领用的是**我们自己动作库里的 `instructions`**（351 个动作全有，中位 28 字）——
      // 零版权风险、零新增体积，且那句话本身就是"最容易错的点"。
      await pumpWorkout(tester);
      expect(find.byKey(const Key('howto-block')), findsOneWidget);
      expect(find.text('动作要领'), findsOneWidget);
      expect(find.textContaining('下蹲到髋低于膝'), findsOneWidget);

      await tester.tap(find.byKey(const Key('howto-open-detail')));
      await tester.pumpAndSettle();
      expect(find.byType(ExerciseDetailScreen), findsOneWidget);
    });

    testWidgets('★ 没有说明的动作：**什么都不摆**（不画一个空标题）', (WidgetTester tester) async {
      // 用户自建的动作很可能没有 instructions —— 那时摆一个空的「动作要领」比不摆更糟
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: WorkoutScreen(
          session: WorkoutSession.single(controller),
          catalog: <ExerciseData>[fullRow(instructions: null)],
          store: store,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('howto-block')), findsNothing);
      // 大按钮照常在 = 这个可选块没有影响训练本身
      expect(find.byKey(const Key('big-log-button')), findsOneWidget);
    });

    testWidgets('没带动作库时不显示入口，但训练屏照常能用', (WidgetTester tester) async {
      await pumpWorkout(tester, withCatalog: false);
      expect(find.byKey(const Key('exercise-info')), findsNothing);
      expect(find.byKey(const Key('howto-block')), findsNothing,
          reason: '没有动作库就没有说明可摆 —— 别画一个空块');
      // 大按钮还在 = 这个可选入口没有影响训练本身
      expect(find.byKey(const Key('big-log-button')), findsOneWidget);
    });
  });

  group('选动作页入口', () {
    late AppDatabase db;
    late ExerciseRepository repo;
    late DriftLocalStore store;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = ExerciseRepository(db);
      store = DriftLocalStore(db);
      await repo.importSeed(
        loadJson: () => File('assets/exercises.json').readAsString(),
      );
    });

    tearDown(() => db.close());

    testWidgets('长按一行打开详情；点一下仍然是"选中"',
        (WidgetTester tester) async {
      ExerciseData? picked;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Builder(builder: (BuildContext ctx) {
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  picked = await Navigator.of(ctx).push<ExerciseData>(
                    MaterialPageRoute<ExerciseData>(
                      builder: (_) => ExercisePickerScreen(
                        repository: repo,
                        store: store,
                      ),
                    ),
                  );
                },
                child: const Text('打开选动作'),
              ),
            ),
          );
        }),
      ));
      await tester.tap(find.text('打开选动作'));
      await tester.pumpAndSettle();

      // 用搜索把它筛出来：浏览态是懒构建的 ListView（没滚到的行根本不存在），
      // 而"滚到它"依赖首屏内容，脆。搜索后的平铺列表一定包含这一行。
      await tester.enterText(
          find.byKey(const Key('exercise-search')), '高脚杯深蹲');
      await tester.pumpAndSettle();
      final Finder row = find.byKey(const Key('exercise-ex_goblet_squat'));
      expect(row, findsOneWidget, reason: '搜索后这一行必须可见，否则后面测的不是入口');

      // 长按 → 详情（而不是选中）
      await tester.longPress(row);
      await tester.pumpAndSettle();
      expect(find.byType(ExerciseDetailScreen), findsOneWidget);
      expect(find.textContaining('哑铃抱在胸前'), findsOneWidget);
      expect(picked, isNull, reason: '长按不该顺手把动作选了');

      // 返回之后点一下 → 还是原来的选中行为
      await tester.tap(find.byKey(const Key('detail-back')));
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(picked?.id, 'ex_goblet_squat');
    });
  });
}
