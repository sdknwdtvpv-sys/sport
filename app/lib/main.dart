/// 练了么 · 应用入口
///
/// 当前阶段刻意使用内存实现（InMemoryLocalStore / RecordingAnalytics）：
/// 目标是把"契约可执行 + CI 能跑"这件事做扎实，而不是假装功能完整。
/// 接 drift 时替换 `_store` 的构造即可，UI 与控制器一行不用改。
library;

import 'package:flutter/material.dart';

import 'dart:async';

import 'analytics/flusher.dart';
import 'analytics/outbox.dart';
import 'analytics/outbox_analytics.dart';
import 'analytics/transport.dart';
import 'core/app_tab_bar.dart';
import 'core/theme.dart';
// db.dart（drift 表）与 models.dart（领域模型）都定义了 Workout / SetRecord，
// 同时裸 import 两个库时，一用到同名类就 ambiguity_import。这里预先 hide 掉。
import 'data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'data/drift_local_store.dart';
import 'data/exercise_repository.dart';
import 'data/local_store.dart';
import 'data/profile_repository.dart';
import 'data/sync_queue.dart';
import 'domain/models.dart';
import 'features/exercise/exercise_picker_screen.dart';
import 'features/today/today_planner.dart';
import 'features/today/today_screen.dart';
import 'features/today/today_suggestion_screen.dart';
import 'features/summary/workout_summary.dart';
import 'features/profile/profile_screen.dart';
import 'features/progress/progress_data.dart';
import 'features/progress/progress_screen.dart';
import 'features/summary/workout_summary_screen.dart';
import 'features/workout/workout_controller.dart';
import 'features/workout/workout_screen.dart';

void main() {
  runApp(const LianLeMeApp());
}

class LianLeMeApp extends StatelessWidget {
  const LianLeMeApp({super.key, this.database});

  /// 测试注入内存库；生产传 null，由 [HomeShell] 打开真实库。
  /// 不注入的话 widget 测试会去碰 path_provider —— 那里没有平台通道。
  final AppDatabase? database;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '练了么',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: HomeShell(database: database),
    );
  }
}

/// 还没有后端时的传输实现：什么都不做，永远返回失败。
///
/// 事件会被留在本地 outbox（不丢），等真地址接上再一起送出去。
/// 之所以不直接不发：那样 outbox 会一直空着，"到底有没有记下来"就无从验证。
class _NullTransport implements AnalyticsTransport {
  @override
  Future<bool> send(List<AnalyticsEventPayload> batch) async => false;
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.database});

  final AppDatabase? database;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final SyncQueue _syncQueue = InMemorySyncQueue();

  /// 持久化：drift（SQLite）。数据活过重启 —— 见 ROADMAP 阶段 1。
  /// 换回内存实现只需把下面两行改成 `InMemoryLocalStore()`。
  late final AppDatabase _db = widget.database ?? openAppDatabase();
  late final AnalyticsOutboxStore _outbox = AnalyticsOutboxStore(_db);
  late final OutboxAnalytics _analytics = OutboxAnalytics(outbox: _outbox);
  late final AnalyticsFlusher _flusher =
      AnalyticsFlusher(db: _db, transport: _buildTransport(), outbox: _outbox);
  Timer? _flushTimer;
  Timer? _coldStartTimer;
  late final LocalStore _store = DriftLocalStore(_db);
  late final ExerciseRepository _repo = ExerciseRepository(_db);
  late final TodayPlanner _planner =
      TodayPlanner(repository: _repo, store: _store);
  late final SummaryService _summaryService =
      SummaryService(store: _store, repository: _repo);
  late final ProfileRepository _profile = ProfileRepository(_db);

  /// 当前 Tab。三个封顶（见 docs/screens.md）。
  int _tab = 0;

  /// 最近 7 天练了几次 —— 空态那行字要用。
  /// 之前这个值从没被算过，所以练完回来空态还写着「还没有训练记录」。
  int _weekSessions = 0;

  /// 上报地址。还没有后端，所以返回一个「什么都不做但永远失败」的传输实现 ——
  /// 事件会留在本地 outbox 里，等真地址接上再一起送出去（不会丢）。
  AnalyticsTransport _buildTransport() => _NullTransport();

  @override
  void initState() {
    super.initState();
    _refreshWeekSessions();
    unawaited(_initAnalytics());
  }

  Future<void> _initAnalytics() async {
    await _flusher.onColdStart(); // 放行上次 parked 的事件
    // 冷启动 5 秒后试一次（analytics-sdk.md §5 的五个触发时机之一）
    _coldStartTimer =
        Timer(const Duration(seconds: 5), () => unawaited(_flusher.flushOnce()));
    // 前台每 60 秒试一次；训练中 flushOnce 自己会跳过
    _flushTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_flusher.flushOnce()),
    );
  }

  Future<void> _refreshWeekSessions() async {
    final List<SetRecord> sets = await _store.allSets();
    if (!mounted) return;
    setState(() => _weekSessions = weekWorkoutCount(sets, DateTime.now()));
  }

  @override
  void dispose() {
    // 两个定时器都要取消：不然 widget 测试会因 pending timer 直接判失败
    _coldStartTimer?.cancel();
    _flushTimer?.cancel();
    // 外部注入的库由注入方负责关闭，我们只关自己打开的
    if (widget.database == null) _db.close();
    super.dispose();
  }

  /// 练一个动作：开训练屏，用户返回后收工。
  /// **全程共用同一个 workoutId**，所以多动作挂在同一次训练下。
  Future<void> _trainOne(String workoutId, ExerciseData exercise) async {
    // 红线：训练进行中不发任何网络请求。
    // 健身房常年弱网，任何请求都可能跟"记一组"抢资源。
    _flusher.suspend();
    final controller = WorkoutController(
      workoutId: workoutId,
      exercise: _repo.specOf(exercise),
      plan: kDefaultPlan,
      analytics: _analytics,
      store: _store,
      syncQueue: _syncQueue,
    );
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => WorkoutScreen(controller: controller)),
    );
    controller.dispose();
    _flusher.resume();
  }

  Future<void> _startSession() async {
    // 幂等，所以每次开始训练都调一次，保证种子一定在库里
    await _repo.importSeed();
    if (!mounted) return;

    final String workoutId = 'w_${DateTime.now().millisecondsSinceEpoch}';

    // 第一屏先给建议：用户连计划都不用搭
    final TodayResult? result = await Navigator.of(context).push<TodayResult>(
      MaterialPageRoute<TodayResult>(
        builder: (_) => TodaySuggestionScreen(planner: _planner),
      ),
    );
    if (result == null || !mounted) return; // 从建议卡返回 = 不练了

    if (result.choice == TodayChoice.startPlanned) {
      for (final PlannedExercise p in result.plan) {
        if (!mounted) break;
        await _trainOne(workoutId, p.exercise);
      }
      await _showSummary(workoutId);
      await _refreshWeekSessions(); // 练完回来，次数要变
      return;
    }

    // 「我自己选」：沿用"选一个 → 练 → 回来再选"的循环
    while (mounted) {
      final ExerciseData? picked = await Navigator.of(context).push<ExerciseData>(
        MaterialPageRoute<ExerciseData>(
          builder: (_) => ExercisePickerScreen(repository: _repo),
        ),
      );
      if (picked == null || !mounted) break;
      await _trainOne(workoutId, picked);
    }
    await _showSummary(workoutId);
    await _refreshWeekSessions();
  }

  /// 训练结束总结。一组都没练就直接回空态 —— 没什么可总结的。
  Future<void> _showSummary(String workoutId) async {
    // 训练结束是五个上报时机之一，这时最该送一次
    unawaited(_flusher.flushOnce());

    final Workout? w = await _store.loadWorkout(workoutId);
    if (w == null || w.sets.isEmpty || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutSummaryScreen(
          service: _summaryService,
          workoutId: workoutId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(child: _bodyFor(_tab)),
            AppTabBar(
              current: _tab,
              onChanged: (int i) => setState(() => _tab = i),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bodyFor(int tab) {
    switch (tab) {
      case 0:
        return TodayScreen(onStart: _startSession, lastWeekSessions: _weekSessions);
      case 1:
        return ProgressScreen(store: _store, repository: _repo);
      default:
        return ProfileScreen(
          store: _store,
          repository: _repo,
          profile: _profile,
          analytics: _analytics,
        );
    }
  }
}

