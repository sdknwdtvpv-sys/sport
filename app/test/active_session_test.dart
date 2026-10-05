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

/// 一条"杀进程前已经记下"的组。id 与 `WorkoutController::_logSet` 的规则一致 ——
/// 所以"恢复后从 1 重新数"在库里表现为**覆盖**（总数不变），这正是那个 P0 的样子。
SetRecord _logged(
  String workoutId,
  String exerciseId,
  int setIndex, {
  int atMs = 1000,
  SetType type = SetType.normal,
}) =>
    SetRecord(
      id: 's_${workoutId}_${exerciseId}_$setIndex',
      workoutId: workoutId,
      exerciseId: exerciseId,
      setIndex: setIndex,
      reps: 8,
      weightKg: 40,
      completedAtMs: atMs + setIndex * 1000,
      setType: type,
    );

/// 一个杠铃卧推的控制器。`alreadyLogged` 就是这次修复的入口。
WorkoutController _controller({
  required LocalStore store,
  List<SetRecord> alreadyLogged = const <SetRecord>[],
  int? startedAtMs,
  int Function()? clock,
}) =>
    WorkoutController(
      exercise: const ExerciseSpec(
        id: 'ex_bb_bench_press',
        name: '杠铃卧推',
        trackType: 'weight_reps',
        defaultRestSec: 90,
        weightIncrement: 2.5,
      ),
      plan: const PlanTarget(targetSets: 3, targetRepsLow: 8, targetRepsHigh: 12),
      analytics: NoopAnalytics(),
      store: store,
      syncQueue: InMemorySyncQueue(),
      workoutId: 'w1',
      clock: clock,
      alreadyLogged: alreadyLogged,
      startedAtMs: startedAtMs,
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

      // ⚠️ **位置也是行为**：2026-10-01 真机走查抓到过一次不一致 ——
      // 文档与注释写着"摆在主按钮之前"，而实际渲染在主按钮**下面**。
      // 现在把它钉住：接着练是此刻该做的那件事，所以它排在主按钮上面。
      final double resume = tester.getCenter(find.byKey(const Key('resume-session'))).dy;
      final double primary = tester.getCenter(find.text('开始今天的训练')).dy;
      expect(resume, lessThan(primary),
          reason: '「继续上次的训练」必须在主按钮**之前**（不能在下面）');
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

  // ─────────────────────────────────────────────────────────────────────────
  // ★ 2026-10-04 真机走查抓到的 P0：恢复后记一组会**覆盖**已记的那一组。
  //
  // 复现（Redmi `flourite` / v1.37.0，`adb shell input` 注入）：记 2 组 → 杀进程 →
  // 点「继续」→ 训练屏显示 **第 1 组、已完成列表为空**（而休息时间接着数）→
  // 再记一组 → 界面变「第 2 组」，而「我」页统计**仍是 2 组 / 640 kg**
  // —— 新那组按 `set_seq = 1` 写库，把原来第 1 组覆盖了。
  //
  // 根因：恢复时控制器是新建的，`_setSeq` 从 0 开始。修法：调用方把
  // `store.setsFor(workoutId)` 传进 `alreadyLogged`（数据库是真源，不另存计数器）。
  group('★ 恢复后接着记：不许覆盖已记的组（真机 P0 的回归）', () {
    test('把已记的组读回来：第几组 / 已完成列表 / 开始时刻 都对', () async {
      final WorkoutController c = _controller(
        store: InMemoryLocalStore(),
        alreadyLogged: <SetRecord>[
          _logged('w1', 'ex_bb_bench_press', 1),
          _logged('w1', 'ex_bb_bench_press', 2),
        ],
        startedAtMs: 4242,
      );

      expect(c.loggedSets.length, 2, reason: '已完成列表要显示杀进程前记的那两组');
      expect(c.setNumber, 3, reason: '接着数的应当是第 3 组，不是第 1 组');
      expect(c.workout.startedAtMs, 4242,
          reason: '开始时刻要沿用原来那次训练（否则总结页的时长只剩后半段）');
    });

    test('★ 真机那条复现：恢复前 2 组 → 恢复后记一组 = 库里 3 组，原第 1 组还在', () async {
      final LocalStore store = InMemoryLocalStore();
      // 杀进程前：记了 2 组（id 是确定性的，所以"覆盖"在这里会表现为"还是 2 组"）
      await store.saveSet(_logged('w1', 'ex_bb_bench_press', 1, atMs: 5000));
      await store.saveSet(_logged('w1', 'ex_bb_bench_press', 2, atMs: 6000));
      await store.saveActiveSession(_session());
      expect((await store.setsFor('w1')).length, 2);

      // 恢复 —— `main.dart::_resumeSession` 做的就是这两步
      final WorkoutController c = _controller(
        store: store,
        alreadyLogged: await store.setsFor('w1'),
      );
      c.onBigButtonTap();
      await Future<void>.delayed(Duration.zero); // 让 unawaited 的落库跑完

      final List<SetRecord> after = await store.setsFor('w1');
      expect(after.length, 3,
          reason: '**修复前这里一直是 2** —— 真机上"总数没变"就是这么来的');
      expect(after.map((SetRecord s) => s.id).toSet().length, 3, reason: '三条不同的组，谁都没被覆盖');
      expect(after.map((SetRecord s) => s.setIndex).toList(), <int>[1, 2, 3]);
      expect(after.first.id, 's_w1_ex_bb_bench_press_1', reason: '原来那组必须还在');
    });

    test('热身组占过的序号也不会被重用（_setSeq 取的是最大值）', () async {
      final WorkoutController c = _controller(
        store: InMemoryLocalStore(),
        alreadyLogged: <SetRecord>[
          _logged('w1', 'ex_bb_bench_press', 1, type: SetType.warmup),
          _logged('w1', 'ex_bb_bench_press', 2),
        ],
      );

      expect(c.setNumber, 2, reason: '只有一组正式组 → 接着的是第 2 组');
      c.onBigButtonTap();
      await Future<void>.delayed(Duration.zero);
      expect(c.loggedSets.last.id, 's_w1_ex_bb_bench_press_3',
          reason: '热身占了 1、正式组占了 2 → 新一组必须是 3');
    });

    test('全新训练（没传 alreadyLogged）行为一点没变', () {
      final WorkoutController c = _controller(store: InMemoryLocalStore());
      expect(c.setNumber, 1);
      expect(c.loggedSets, isEmpty);
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
