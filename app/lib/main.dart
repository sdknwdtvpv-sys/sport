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
import 'core/units.dart';
// db.dart（drift 表）与 models.dart（领域模型）都定义了 Workout / SetRecord，
// 同时裸 import 两个库时，一用到同名类就 ambiguity_import。这里预先 hide 掉。
import 'data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import 'data/body_metric_repository.dart';
import 'data/drift_local_store.dart';
import 'data/exercise_repository.dart';
import 'data/local_store.dart';
import 'data/profile_repository.dart';
import 'data/routine_repository.dart';
import 'data/sync_queue.dart';
import 'domain/models.dart';
import 'domain/tap_meter.dart';
import 'features/exercise/exercise_picker_screen.dart';
import 'features/today/today_planner.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/today/today_screen.dart';
import 'features/today/today_suggestion_screen.dart';
import 'features/summary/workout_summary.dart';
import 'features/profile/profile_screen.dart';
import 'features/progress/progress_data.dart';
import 'features/progress/progress_screen.dart';
import 'features/summary/workout_summary_screen.dart';
import 'features/workout/workout_controller.dart';
import 'features/workout/workout_screen.dart';
import 'features/workout/workout_session.dart';

void main() {
  runApp(const LianLeMeApp());
}

class LianLeMeApp extends StatelessWidget {
  const LianLeMeApp({super.key, this.database, this.seedLoader});

  /// 测试注入内存库；生产传 null，由 [HomeShell] 打开真实库。
  /// 不注入的话 widget 测试会去碰 path_provider —— 那里没有平台通道。
  final AppDatabase? database;

  /// 动作库种子的加载器。生产传 null（走 `rootBundle` 读 asset）。
  ///
  /// **测试必须能把它换掉** —— 和上面那条同一个理由，但更隐蔽：
  /// `testWidgets` 跑在 fake-async 里，而 `rootBundle.loadString` 要经平台通道，
  /// 于是 `await importSeed()` 会**永远挂住**（连 `Future.timeout` 都救不了：
  /// 假时钟不推进，定时器根本不会触发）。
  /// 所以在此之前，这个仓库里**没有任何测试驱动过完整的开练流程** ——
  /// 全部自己注入 `loadJson`（见 `today_planner_test.dart` / `multi_exercise_test.dart`）。
  final Future<String> Function()? seedLoader;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '练了么',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: HomeShell(database: database, seedLoader: seedLoader),
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
  const HomeShell({super.key, this.database, this.seedLoader});

  final AppDatabase? database;
  final Future<String> Function()? seedLoader;

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
  late final BodyMetricRepository _bodyMetrics = BodyMetricRepository(_db);
  late final RoutineRepository _routines = RoutineRepository(_db);
  late final TodayPlanner _planner =
      TodayPlanner(repository: _repo, store: _store);
  late final SummaryService _summaryService =
      SummaryService(store: _store, repository: _repo);
  late final ProfileRepository _profile = ProfileRepository(_db);

  /// 当前 Tab。三个封顶（见 docs/screens.md）。
  int _tab = 0;

  /// 显示单位。启动时从 user_profile 读一次，用户在 S10 改了之后整棵树重建。
  /// **只影响显示**：存储、引擎、埋点始终是 kg（见 core/units.dart）。
  WeightUnit _unit = WeightUnit.kg;

  /// 体重的显示单位（千克 / 斤）。**与训练重量分开** —— 见 units.dart 的说明。
  BodyWeightUnit _bodyUnit = BodyWeightUnit.kg;

  /// 休息时长偏好。**null = 跟随动作自带的值**，这是默认。
  int? _restOverrideSec;

  /// 训练目标。**null = 还没走过 S13 的引导** —— S1 据此决定要不要显示入口。
  String? _goalWire;

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
    unawaited(_loadUnit());
    unawaited(_initAnalytics());
    unawaited(_importSeedQuietly());
  }

  /// 冷启动就把动作库刷一遍。
  ///
  /// **这个调用是补上的，2026-09-29 在真机上抓到的**：在此之前 `importSeed` 只在
  /// 「开始训练」与「看看今天练什么」两个按钮里调 —— 而 `exercise_repository.dart`
  /// 的注释写的是"每次冷启动都可以安全地调一次 `importSeed()`"。
  /// 后果：v1.2.0 升到 v1.4.0 之后，真机上的 `exercise` 表还是老的 **165** 条，
  /// 新补的 186 个动作（热身/拉伸/有氧/跑步机…）**要等用户真的点开始训练才会出现**；
  /// 而「计划 → 加动作 → 选择器」这条路根本不经过那两个按钮，永远看到老库。
  ///
  /// 为什么 `unawaited`：这是冷启动路径，不能为一个内容刷新卡住首屏。
  /// 两个按钮里的 `await` 保留着 —— 那条路必须保证"进训练屏时库是最新的"。
  Future<void> _importSeedQuietly() async {
    try {
      await _repo.importSeed(loadJson: widget.seedLoader);
    } catch (e) {
      // 刷新失败不该挡住启动：库里已有上一份，用户照常能练。
      // 但要留痕 —— 否则"新动作没出现"会变成一个查不下去的问题。
      _analytics.track('seed_import_failed', <String, Object?>{'error': '$e'});
    }
  }

  Future<void> _loadUnit() async {
    final WeightUnit u = await _profile.unit();
    final BodyWeightUnit b = await _profile.bodyWeightUnit();
    final int? rest = await _profile.restOverrideSec();
    final String? goal = await _profile.goalWire();
    if (!mounted) return;
    setState(() {
      _unit = u;
      _bodyUnit = b;
      _restOverrideSec = rest;
      _goalWire = goal;
    });
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

  /// 开一段训练会话：**一次把这一趟要练的动作都建好**，
  /// 于是训练屏底部可以在它们之间切换（S6），而不是每个动作重新进一次页面。
  /// 全程共用同一个 workoutId，所以多动作挂在同一次训练下。
  Future<void> _trainSession(String workoutId, List<SessionEntry> entries) async {
    if (entries.isEmpty) return;

    // 红线：训练进行中不发任何网络请求。
    // 健身房常年弱网，任何请求都可能跟"记一组"抢资源。
    _flusher.suspend();

    final List<WorkoutController> controllers = <WorkoutController>[];
    for (final SessionEntry entry in entries) {
      controllers.add(WorkoutController(
        workoutId: workoutId,
        exercise: _repo.specOf(entry.exercise),
        // 处方逐项带上：计划模板里每个动作的组数/次数区间是分开的
        plan: entry.plan,
        analytics: _analytics,
        store: _store,
        syncQueue: _syncQueue,
        // **上一次这个动作练成什么样 —— 渐进建议的输入，必须传。**
        //
        // 不传的后果（曾经就是这样）：引擎永远命中 progression.dart 的
        // "零历史"分支 → 大按钮上恒是动作库默认重量（卧推 40kg）、
        // 理由恒是"第一次练这个动作"；而两秒前建议卡上写的是按历史算出来的
        // 数字 —— 同一个用户在两张屏上看到两个数。
        //
        // excludeWorkoutId 排除本次训练：同一次训练里再次进入同一个动作时，
        // 不能把"两秒前刚记的组"当成"上次"。
        lastSession: await _store.lastSessionFor(
          entry.exercise.id,
          excludeWorkoutId: workoutId,
        ),
        // 控制器靠 profile 决定大按钮上怎么念数字、以及休息多久
        profile: UserProfile(unit: _unit, restOverrideSec: _restOverrideSec),
      ));
    }
    final WorkoutSession session = WorkoutSession(controllers);

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => WorkoutScreen(session: session)),
    );

    session.dispose();
    for (final WorkoutController c in controllers) {
      c.dispose();
    }
    _flusher.resume();
  }

  /// 只练一个动作。「我自己选」那条流程每次只加一个。
  Future<void> _trainOne(String workoutId, ExerciseData exercise) =>
      _trainSession(workoutId, <SessionEntry>[
        SessionEntry(exercise: exercise, plan: defaultPlanFor(exercise)),
      ]);

  /// S13：可选的「帮我定个计划」。**不在启动路径上** ——
  /// 只有用户主动点 S1 上那个链接才会进。
  ///
  /// 引导以"开始训练"收尾：计划已经落库（S11 的计划模板），
  /// 用户点「就用这个，开始练」时直接进训练会话。
  Future<void> _openFirstPlan() async {
    final OnboardingResult? r = await Navigator.of(context).push<OnboardingResult>(
      MaterialPageRoute<OnboardingResult>(
        builder: (_) => OnboardingScreen(
          planner: _planner,
          profile: _profile,
          routines: _routines,
          exercises: _repo,
          unit: _unit,
        ),
      ),
    );
    if (r == null || !mounted) return;

    // 入口该收起来了
    final String? goal = await _profile.goalWire();
    if (mounted) setState(() => _goalWire = goal);

    if (!r.startNow) {
      await _refreshWeekSessions();
      return;
    }
    final String workoutId = 'w_${DateTime.now().millisecondsSinceEpoch}';
    // 引导最后那下「就用这个，开始练」也是导航点击，且此时控制器还没被构造。
    // 引导中间选目标/频率的那几步**不计** —— 那是搭计划，不是记这一组。
    _analytics.beginSetInteraction();
    _analytics.countTap(TapKind.nav);
    await _trainSession(
      workoutId,
      r.plan
          .map((PlannedExercise p) =>
              SessionEntry(exercise: p.exercise, plan: p.plan))
          .toList(),
    );
    await _showSummary(workoutId);
    await _refreshWeekSessions();
  }

  /// S1 的大按钮：**一跳直接开练**。
  ///
  /// 原来的路径是「今日页 → 建议卡 → 大按钮」= 端到端 3 次点击才记下第一组，
  /// 而 `PRODUCT.md` §1 的红线是"超过 3 次点击判负"—— 刚好压线；
  /// 竞品 Everlift 的公开数字是"3 组从约 21 次降到 8 次"（≈2.7 次/组）。
  /// 现在：首页这一下直接进训练屏 → 第一组 **2 次**，同一动作的第 2 组起 **1 次**。
  ///
  /// 建议卡没有被砍掉，只是移到「看看今天练什么 ›」后面（见 [_openSuggestion]）。
  Future<void> _startNow() async {
    // 端到端口径：这一下就是这条记录的第一步（周期必须在这里开）
    _analytics.beginSetInteraction();
    _analytics.countTap(TapKind.nav);

    await _repo.importSeed(loadJson: widget.seedLoader);
    if (!mounted) return;

    final String group = await _planner.nextMuscleGroup();
    final List<PlannedExercise> plan =
        await _planner.planToday(muscleGroup: group, unit: _unit);
    if (!mounted) return;

    // 动作库没准备好（或这个部位一个动作都没有）→ 退回建议卡：
    // 它会给出"动作库还没准备好，可以点我自己选"的说明，
    // 而不是把一个空白训练屏推给用户。
    if (plan.isEmpty) {
      await _openSuggestion();
      return;
    }

    final String workoutId = 'w_${DateTime.now().millisecondsSinceEpoch}';
    await _trainSession(
      workoutId,
      plan
          .map((PlannedExercise p) =>
              SessionEntry(exercise: p.exercise, plan: p.plan))
          .toList(),
    );
    await _showSummary(workoutId);
    await _refreshWeekSessions(); // 练完回来，次数要变
  }

  /// 「看看今天练什么 ›」：原来的建议卡路径（换一批 / 我的计划 / 我自己选）。
  Future<void> _openSuggestion() async {
    // 端到端 tap_count：用户按「开始训练」这一下就是这条记录的第一步。
    // 周期必须**在这里**开 —— 控制器要等建议卡/选动作走完才被构造，
    // 那时候再 begin() 会把这几下点击清零，又变回"只算大按钮"的窄口径。
    _analytics.beginSetInteraction();
    _analytics.countTap(TapKind.nav);

    // 幂等，所以每次开始训练都调一次，保证种子一定在库里
    await _repo.importSeed(loadJson: widget.seedLoader);
    if (!mounted) return;

    final String workoutId = 'w_${DateTime.now().millisecondsSinceEpoch}';

    // 第一屏先给建议：用户连计划都不用搭
    final TodayResult? result = await Navigator.of(context).push<TodayResult>(
      MaterialPageRoute<TodayResult>(
        builder: (_) => TodaySuggestionScreen(
            planner: _planner,
            unit: _unit,
            routines: _routines,
            exercises: _repo,
          ),
      ),
    );
    if (result == null || !mounted) return; // 从建议卡返回 = 不练了

    if (result.choice == TodayChoice.startPlanned) {
      // 建议卡上「就用这个，开始练」也是为得到第一组付出的一次操作
      _analytics.countTap(TapKind.nav);
      // 一次把建议里的动作全开出来，底部条与左右滑动在它们之间切换（S6）
      await _trainSession(
        workoutId,
        result.plan
            .map((PlannedExercise p) =>
                SessionEntry(exercise: p.exercise, plan: p.plan))
            .toList(),
      );
      await _showSummary(workoutId);
      await _refreshWeekSessions(); // 练完回来，次数要变
      return;
    }

    // 「我自己选」：沿用"选一个 → 练 → 回来再选"的循环
    // 选这条路本身也是一次点击（它决定了接下来要记什么）
    _analytics.countTap(TapKind.nav);
    while (mounted) {
      final ExerciseData? picked = await Navigator.of(context).push<ExerciseData>(
        MaterialPageRoute<ExerciseData>(
          builder: (_) => ExercisePickerScreen(
            repository: _repo,
            store: _store,
            unit: _unit,
          ),
        ),
      );
      if (picked == null || !mounted) break;
      // 从动作库挑一个动作 = 一次选动作点击
      _analytics.countTap(TapKind.exercisePick);
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
          unit: _unit,
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
        return TodayScreen(
            // 大按钮一跳直开练；想先看看的人走下面那个入口
            onStart: _startNow,
            onSeePlan: _openSuggestion,
            lastWeekSessions: _weekSessions,
            // 还没定过计划才显示入口
            onPlanHelp: _goalWire == null ? _openFirstPlan : null,
          );
      case 1:
        return ProgressScreen(
            store: _store,
            repository: _repo,
            bodyMetrics: _bodyMetrics,
            profile: _profile,
            unit: _unit,
            bodyUnit: _bodyUnit,
            // 身体数据页里切了体重单位 → 整棵树按新单位重建
            onBodyUnitChanged: (BodyWeightUnit u) {
              setState(() => _bodyUnit = u);
            },
          );
      default:
        return ProfileScreen(
          store: _store,
          repository: _repo,
          profile: _profile,
          analytics: _analytics,
          bodyMetrics: _bodyMetrics,
          unit: _unit,
          // 用户改了单位：存库 + 整棵树重建，别的地方立刻也跟着变
          onUnitChanged: (WeightUnit u) {
            setState(() => _unit = u);
          },
          bodyUnit: _bodyUnit,
          onBodyUnitChanged: (BodyWeightUnit u) {
            setState(() => _bodyUnit = u);
          },
          restOverrideSec: _restOverrideSec,
          onRestOverrideChanged: (int? sec) {
            setState(() => _restOverrideSec = sec);
          },
          // 删光 / 导入之后，首页那行"我上周练了 N 次"要跟着变
          onDataChanged: () => unawaited(_refreshWeekSessions()),
        );
    }
  }
}

