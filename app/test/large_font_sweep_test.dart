/// 练了么 · **大字号全屏扫描**（VI 计划 §7 E 组"`xxxLarge` 下不许溢出"的整屏版）
///
/// **为什么要有它**：计划里那条判据只盯了"主按钮的高度"，而 2026-10-10 收尾时
/// 我在 **2.0×** 下抓到训练屏真溢出 17px ——「本次 · N 组」+「长按某一行可撤销」
/// 那一行合计 388pt > 屏宽 371pt。**一件事只有被整屏扫过，才知道它到底通不通**：
/// 零散地测某一屏某一处，正是这类缺陷活下来的方式。
///
/// 覆盖范围：能便宜地构造出来的**主要屏**（见 [kScreens]）。
/// ⚠️ 没覆盖的（需要更重的依赖，如实记在下面，不当成通过）：
/// 身体数据页（要 `BodyMetricRepository` + 健康桥）、数据与备份（要 profile/backup/账号）、
/// 通知详情、分享卡预览（要导出器）、引导页（要 consent 流程）。
///
/// 判据：每一屏 × {1.5×, 2.0×} 下 `pump` 之后
/// **不许有 `RenderFlex overflowed`（`tester.takeException()` 必须为 null）**。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/analytics.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart' hide SetRecord, Workout, Exercise, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/notification_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/data/routine_repository.dart';
import 'package:lianleme/data/sync_queue.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/exercise/exercise_picker_screen.dart';
import 'package:lianleme/features/notifications/notification_center_screen.dart';
import 'package:lianleme/features/profile/settings_home_screen.dart';
import 'package:lianleme/features/progress/achievements_screen.dart';
import 'package:lianleme/features/progress/all_data_screen.dart';
import 'package:lianleme/features/progress/progress_screen.dart';
import 'package:lianleme/features/routine/plan_screen.dart';
import 'package:lianleme/features/summary/workout_summary.dart';
import 'package:lianleme/features/summary/workout_summary_screen.dart';
import 'package:lianleme/features/today/today_screen.dart';
import 'package:lianleme/features/workout/workout_controller.dart';
import 'package:lianleme/features/workout/workout_screen.dart';
import 'package:lianleme/features/workout/workout_session.dart';

/// 常见安卓机的逻辑尺寸（411×914）—— 比测试默认的 800×600 窄得多，
/// 而"溢出"几乎都是**窄屏 + 大字号**一起才出现。
const Size kPhone = Size(411, 914);
const double kPhoneDpr = 3.0;

/// 一次训练记录（总结页/全部数据页要有东西可显示才谈得上"展示态溢出"）。
List<SetRecord> _sets() => <SetRecord>[
      for (int i = 0; i < 3; i++)
        SetRecord(
          id: 's$i',
          workoutId: 'w1',
          exerciseId: 'ex_bb_bench_press',
          setIndex: i + 1,
          reps: 10,
          weightKg: 65,
          completedAtMs: DateTime(2026, 10, 10, 19).millisecondsSinceEpoch + i * 60000,
        ),
    ];

void main() {
  /// 训练屏那个控制器要留个引用：点完大按钮会起**休息倒计时**（periodic Timer），
  /// 不掐掉测试结束时会报 "Pending timers"。
  WorkoutController? workoutController;

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

  /// 一屏怎么造。`label` 只用于报错信息。
  final Map<String, Future<Widget> Function()> screens =
      <String, Future<Widget> Function()>{
    '首页': () async => TodayScreen(onStart: () {}, onOpenLibrary: () {}),
    '进步页': () async => ProgressScreen(
          store: store,
          repository: repo,
          onOpenToday: () {},
          now: DateTime(2026, 10, 10),
        ),
    '全部数据页': () async => AllDataScreen(
          store: store,
          repository: repo,
          now: DateTime(2026, 10, 10),
        ),
    '动作库': () async => ExercisePickerScreen(repository: repo),
    '通知中心': () async => NotificationCenterScreen(repository: NotificationRepository(db)),
    '计划页': () async => PlanScreen(
          repository: RoutineRepository(db),
          exercises: repo,
          store: store,
          onBack: () {},
          now: DateTime(2026, 10, 10),
        ),
    '成就册': () async => AchievementsScreen(sets: _sets()),
    '设置页': () async => SettingsHomeScreen(
          store: store,
          repository: repo,
          profile: ProfileRepository(db),
        ),
    '总结页': () async {
      for (final SetRecord r in _sets()) {
        await store.saveSet(r);
      }
      await store.saveWorkout(Workout(id: 'w1', startedAtMs: 0));
      return WorkoutSummaryScreen(
        service: SummaryService(store: store, repository: repo),
        workoutId: 'w1',
      );
    },
    '训练屏（记过一组）': () async {
      final WorkoutController c = WorkoutController(
        exercise: const ExerciseSpec(
          id: 'ex_bb_bench_press',
          name: '杠铃卧推',
          weightIncrement: 2.5,
          defaultWeightKg: 40,
          defaultRestSec: 60,
        ),
        plan: const PlanTarget(targetSets: 3, targetRepsLow: 8, targetRepsHigh: 10),
        analytics: RecordingAnalytics(),
        store: InMemoryLocalStore(),
        syncQueue: InMemorySyncQueue(),
        clock: () => 1000000,
      );
      workoutController = c;
      final Widget screen = WorkoutScreen(session: WorkoutSession.single(c));
      // 记一组（休息条 + 已完成行都出现）—— 那正是溢出被藏起来的地方
      // 调用方会在 pump 之后点一次大按钮（见下面的 `tapBigButton`）。
      return screen;
    },
  };

  for (final double scale in <double>[1.5, 2.0]) {
    for (final MapEntry<String, Future<Widget> Function()> e in screens.entries) {
      testWidgets('${e.key}：${scale}× 下不溢出', (WidgetTester tester) async {
        tester.view.physicalSize = kPhone * kPhoneDpr;
        tester.view.devicePixelRatio = kPhoneDpr;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final Widget home = await e.value();
        await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: home));
        // 推进固定时长而不是 pumpAndSettle：这些屏里有不确定进度的转圈圈/常驻计时器
        for (int i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 120));
        }
        final Object? first = tester.takeException();

        // 训练屏：再点一次大按钮，把"接上休息条 + 已完成行"那个状态也过一遍
        if (e.key.startsWith('训练屏') &&
            find.byKey(const Key('big-log-button')).evaluate().isNotEmpty) {
          await tester.tap(find.byKey(const Key('big-log-button')));
          for (int i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 120));
          }
        }
        final Object? second = tester.takeException();
        // 溢出时报出**是哪一行**：渲染错误里的 element 是 DEFUNCT（拿不到 widget 名），
        // 所以自己扫一遍横向 RenderFlex —— 子宽度之和 > 自身宽度的那一个就是它。
        final List<String> overflowing = <String>[];
        for (final Element el in tester.allElements) {
          final RenderObject? ro = el.renderObject;
          if (ro is! RenderFlex || ro.direction != Axis.horizontal) continue;
          double sum = 0;
          RenderBox? child = ro.firstChild;
          while (child != null) {
            sum += child.size.width;
            child = ro.childAfter(child);
          }
          if (sum > ro.size.width + 0.5) {
            overflowing.add('${ro.size.width} ← 子 $sum ｜ '
                '${el.debugGetCreatorChain(6).replaceAll('\n', ' ')}');
          }
        }
        // 掐掉休息倒计时（否则 "Pending timers"）
        workoutController?.skipRest();
        workoutController?.dispose();
        workoutController = null;

        expect(first ?? second, isNull,
            reason: '${e.key} 在 ${scale}× 下溢出了 —— 大字号是 40+ 用户会开的档位，'
                '而溢出意味着**有内容被裁掉**（不是"看着挤"）。'
                '${overflowing.isEmpty ? '' : '溢出的行：${overflowing.join(' ／ ')}'}');
      });
    }
  }
}
