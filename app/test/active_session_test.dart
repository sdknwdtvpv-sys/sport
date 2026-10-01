/// 练了么 · 「训练中断不丢状态」与「5 分钟轻量活动」（2026-10-01）
///
/// 两件事都是**产品决定**，所以各有自己的测试文件（而不是塞进已有的测试里）：
///
/// 1. **中断不丢状态**：接个电话、切到微信、系统把 App 杀掉 —— 回来要能接着练。
///    组记录本来就落库（那样不丢），这里钉的是**运行时状态**：
///    练到第几个动作、休息还剩多久。休息记的是**绝对时间戳**，
///    所以"被杀掉 30 秒"等于"休息已经过去 30 秒"，而不是"回来重新从 90 秒开始"。
/// 2. **5 分钟轻量活动**：习惯养成的敌人是"全有或全无"。
///    它必须满足三条：动作都是按时长的、每个只 1 组、**不进容量与 PR**。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/analytics.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/sync_queue.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/today/today_screen.dart';
import 'package:lianleme/features/workout/workout_controller.dart';

ActiveSession _session({int index = 0, int? restEndsAtMs}) => ActiveSession(
      workoutId: 'w1',
      entries: const <ActiveEntry>[
        ActiveEntry(
            exerciseId: 'ex_bb_bench_press',
            plan: PlanTarget(targetSets: 3, targetRepsLow: 8, targetRepsHigh: 12)),
        ActiveEntry(
            exerciseId: 'ex_bb_squat',
            plan: PlanTarget(targetSets: 5, targetRepsLow: 5, targetRepsHigh: 5)),
      ],
      index: index,
      restEndsAtMs: restEndsAtMs,
      startedAtMs: 1000,
      source: 'suggestion',
    );

void main() {
  group('未结束的训练会话：存 / 读 / 清（两个实现同一组断言）', () {
    for (final ({String name, LocalStore Function() make}) impl
        in <({String name, LocalStore Function() make})>[
      (name: 'InMemoryLocalStore', make: () => InMemoryLocalStore()),
      (
        name: 'DriftLocalStore',
        make: () {
          final AppDatabase db = AppDatabase(NativeDatabase.memory());
          addTearDown(db.close);
          return DriftLocalStore(db);
        }
      ),
    ]) {
      test('${impl.name}：存进去能原样读出来，清掉就没了', () async {
        final LocalStore store = impl.make();
        expect(await store.activeSession(), isNull, reason: '一开始不该有未结束的会话');

        final ActiveSession s = _session(index: 1, restEndsAtMs: 123456);
        await store.saveActiveSession(s);

        final ActiveSession? back = await store.activeSession();
        expect(back, isNotNull);
        expect(back!.workoutId, 'w1');
        expect(back.index, 1);
        expect(back.restEndsAtMs, 123456, reason: '休息结束时刻要原样带回来');
        expect(back.source, 'suggestion', reason: '恢复时按原路重新上报，漏斗口径不变');
        expect(back.entries.length, 2);
        expect(back.entries[1].exerciseId, 'ex_bb_squat');
        expect(back.entries[1].plan.targetSets, 5, reason: '每个动作的处方要跟着回来');

        await store.clearActiveSession();
        expect(await store.activeSession(), isNull);
      });

      test('${impl.name}：写第二次是覆盖，不是堆积（只允许一行）', () async {
        final LocalStore store = impl.make();
        await store.saveActiveSession(_session(index: 0));
        await store.saveActiveSession(_session(index: 1));
        final ActiveSession? back = await store.activeSession();
        expect(back!.index, 1);
      });

      test('${impl.name}：删除全部数据会把未结束的会话也清掉', () async {
        final LocalStore store = impl.make();
        await store.saveActiveSession(_session());
        await store.deleteAllUserData();
        expect(await store.activeSession(), isNull,
            reason: '删光之后首页不该还问你要不要继续上次的训练 —— 那次训练已经没了');
      });
    }
  });

  group('休息接着数：靠的是绝对时间戳', () {
    test('被杀掉 30 秒后回来，还剩 60 秒（不是重新从 90 秒开始）', () async {
      int now = 1000000;
      final WorkoutController c = WorkoutController(
        exercise: const ExerciseSpec(
          id: 'ex_bb_bench_press',
          name: '杠铃卧推',
          trackType: 'weight_reps',
          defaultRestSec: 90,
          weightIncrement: 2.5,
        ),
        plan: const PlanTarget(targetSets: 3, targetRepsLow: 8, targetRepsHigh: 12),
        analytics: NoopAnalytics(),
        store: InMemoryLocalStore(),
        syncQueue: InMemorySyncQueue(),
        clock: () => now,
        // 90 秒的休息，已经过去了 30 秒
        restEndsAtMs: 1000000 + 60000,
      );

      expect(c.restRunning, isTrue, reason: '回来时应该在休息中');
      expect(c.restRemainingSec, 60, reason: '剩 60 秒 —— 那 30 秒不该被抹掉');
      expect(c.restEndsAtMs, 1000000 + 60000, reason: '绝对时刻原样保留');

      // 再走 60 秒 → 休息自然结束
      for (int i = 0; i < 60; i++) {
        now += 1000;
        await Future<void>.delayed(Duration.zero);
      }
      c.dispose();
    });

    test('休息结束时刻已经过去 → 不进入休息状态', () async {
      final WorkoutController c = WorkoutController(
        exercise: const ExerciseSpec(
          id: 'ex_bb_bench_press',
          name: '杠铃卧推',
          trackType: 'weight_reps',
          defaultRestSec: 90,
          weightIncrement: 2.5,
        ),
        plan: const PlanTarget(targetSets: 3, targetRepsLow: 8, targetRepsHigh: 12),
        analytics: NoopAnalytics(),
        store: InMemoryLocalStore(),
        syncQueue: InMemorySyncQueue(),
        clock: () => 2000000,
        restEndsAtMs: 1500000, // 早过去了
      );
      expect(c.restRunning, isFalse);
      expect(c.restEndsAtMs, isNull);
      c.dispose();
    });
  });

  group('首页：未结束的训练会先摆出来', () {
    Future<void> pump(WidgetTester tester, {VoidCallback? onResume}) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: TodayScreen(
            onStart: () {},
            onResume: onResume,
            resumeLabel: '上次练到第 2/3 个动作',
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('有未结束的训练 → 显示「继续」条，且写着练到哪了', (WidgetTester tester) async {
      await pump(tester, onResume: () {});
      expect(find.byKey(const Key('resume-session')), findsOneWidget);
      expect(find.textContaining('上次的训练还没结束'), findsOneWidget);
      expect(find.text('上次练到第 2/3 个动作'), findsOneWidget);
    });

    testWidgets('没有未结束的训练 → 不显示（不做"永远挂着的空入口"）',
        (WidgetTester tester) async {
      await pump(tester);
      expect(find.byKey(const Key('resume-session')), findsNothing);
    });
  });

  group('5 分钟轻量活动', () {
    testWidgets('首页有那条出口，而且它排在主按钮之下（不抢主路径）',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: TodayScreen(onStart: () {}, onLightWorkout: () {}),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('light-workout')), findsOneWidget);
      expect(find.textContaining('今天不想练'), findsOneWidget);

      // 主按钮在它上面：一遍过（"点一下就开始记录"这条不能被这条活动挤下去）
      final double primary = tester.getCenter(find.text('开始今天的训练')).dy;
      final double light = tester.getCenter(find.byKey(const Key('light-workout'))).dy;
      expect(light, greaterThan(primary), reason: '轻量出口必须在主按钮下面');
    });

    test('清单里的动作在动作库里真的存在，而且都是按时长的（不会进容量/PR）', () async {
      final AppDatabase db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final ExerciseRepository repo = ExerciseRepository(db);
      await repo.importSeed(loadJson: () async => _seedJson());

      for (final String id in kLightActivityIds) {
        final ExerciseData? e = await repo.byId(id);
        expect(e, isNotNull, reason: '$id 在动作库里找不到 —— 清单要跟着种子改');
        expect(e!.trackType, 'time',
            reason: '$id 不是按时长动作：它会带上"重量 × 次数"的容量，污染总容量与 PR');
        expect(e.category == 'cardio', isFalse,
            reason: '$id 是有氧：有氧有自己的呈现（里程/配速），不该混进"5 分钟活动"');
      }
    });
  });
}

String _seedJson() => '''
{"exercises": [
  {"id":"ex_arm_circles","name":"绕臂","muscle_group":"shoulders","equipment":"bodyweight",
   "category":"warmup","track_type":"time","default_rest_sec":30,"weight_increment":0},
  {"id":"ex_cat_cow_stretch","name":"猫牛式","muscle_group":"core","equipment":"bodyweight",
   "category":"warmup","track_type":"time","default_rest_sec":30,"weight_increment":0},
  {"id":"ex_plank","name":"平板支撑","muscle_group":"core","equipment":"bodyweight",
   "category":"strength","track_type":"time","default_rest_sec":60,"weight_increment":0},
  {"id":"ex_childs_pose","name":"婴儿式","muscle_group":"back","equipment":"bodyweight",
   "category":"stretch","track_type":"time","default_rest_sec":30,"weight_increment":0}
]}
''';
