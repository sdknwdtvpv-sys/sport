/// 练了么 · 应用入口
///
/// 当前阶段刻意使用内存实现（InMemoryLocalStore / RecordingAnalytics）：
/// 目标是把"契约可执行 + CI 能跑"这件事做扎实，而不是假装功能完整。
/// 接 drift 时替换 `_store` 的构造即可，UI 与控制器一行不用改。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';

import 'analytics/analytics_context.dart';
import 'analytics/flusher.dart';
import 'analytics/outbox.dart';
import 'analytics/outbox_analytics.dart';
import 'analytics/transport.dart';
import 'core/app_tab_bar.dart';
import 'core/app_top_bar.dart';
import 'core/glass_surface.dart';
import 'core/labels.dart';
import 'core/theme.dart';
import 'core/units.dart';
// db.dart（drift 表）与 models.dart（领域模型）都定义了 Workout / SetRecord，
// 同时裸 import 两个库时，一用到同名类就 ambiguity_import。这里预先 hide 掉。
import 'data/analytics_meta_repository.dart';
import 'data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
// ⚠️ 两个文件都定义了 `dayKey`：身体数据那个是给 `body_metric.date` 用的，
// 补签那个是给 `streak_protection.date` 用的（写法一样、语义不同）。
// 这里要的是补签那个 —— 所以把身体数据那个 hide 掉（它的使用者在本文件里
// 都有自己的入口，不经过 main.dart 的这个名字）。
import 'data/body_metric_repository.dart' hide dayKey;
import 'data/drift_local_store.dart';
import 'data/exercise_data_ext.dart';
import 'data/exercise_repository.dart';
import 'data/local_store.dart';
import 'data/notification_repository.dart';
import 'data/profile_repository.dart';
import 'data/reminder_repository.dart';
import 'data/routine_repository.dart';
import 'data/sync_queue.dart';
import 'domain/models.dart';
import 'domain/tap_meter.dart';
import 'features/exercise/exercise_library_screen.dart';
import 'features/exercise/exercise_picker_screen.dart';
import 'features/today/today_planner.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/onboarding/intro_carousel_screen.dart';
import 'features/onboarding/privacy_consent_screen.dart';
import 'features/today/today_screen.dart';
import 'features/today/today_suggestion_screen.dart';
import 'features/summary/workout_summary.dart';
import 'features/routine/plan_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/profile/settings_home_screen.dart';
import 'features/body/body_metric_screen.dart';
import 'features/notifications/notification_center_screen.dart';
import 'features/notifications/notification_rules.dart';
import 'features/progress/achievements_screen.dart';
import 'features/progress/streak.dart';
import 'features/progress/all_data_screen.dart';
import 'features/progress/progress_data.dart';
import 'features/progress/progress_screen.dart';
import 'features/progress/weekly_report.dart';
import 'features/progress/weekly_challenge.dart';
import 'features/progress/muscle_balance.dart';
import 'features/progress/comeback.dart';
import 'features/progress/streak_protection.dart';
import 'data/streak_protection_repository.dart';
import 'features/summary/share_card_preview_screen.dart';
import 'features/profile/reminder.dart';
import 'features/profile/reminder_bridge.dart';
import 'features/profile/reminder_service.dart';
import 'features/summary/workout_summary_screen.dart';
import 'features/workout/haptics.dart';
import 'features/workout/rest_activity.dart';
import 'features/workout/rest_cue.dart';
import 'features/workout/workout_controller.dart';
import 'features/workout/workout_screen.dart';
import 'features/workout/workout_session.dart';

void main() {
  _registerFontLicense();
  runApp(const LianLeMeApp());
}

/// 把展示字体（Oswald，OFL-1.1）的许可原文登记进 Flutter 自带的许可页。
///
/// 为什么必须有这一段：政策与商店规则都要求"开源许可在应用内可查"（我 → 隐私与关于 → 开源许可
/// 走的就是 `showLicensePage`），而**字体许可不会自动出现** —— Flutter 只登记各插件包自带的
/// LICENSE。字体文件是我们自己放进 `app/fonts/` 的，许可也得自己登记，否则那一页会缺一条。
void _registerFontLicense() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      <String>['Oswald'],
      await rootBundle.loadString('fonts/OFL-Oswald.txt'),
    );
  });
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
      // 界面语言**写死中文**：这一版只有中文文案（政策、清单、软著都是中文），
      // 跟着系统语言走只会让"英文系统 + 中文界面"这种组合里，Material 自带的
      // 页面（许可页、选择器）变成半中半英。
      // 这些 delegate 只提供**系统组件的文案与格式**，不改变我们自己的任何字符串。
      locale: const Locale('zh', 'CN'),
      supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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
  late final AnalyticsMetaRepository _analyticsMeta =
      AnalyticsMetaRepository(_db);
  late final OutboxAnalytics _analytics = OutboxAnalytics(
    outbox: _outbox,
    context: DeviceAnalyticsContext(
      repository: _analyticsMeta,
      platform: () => Platform.isIOS ? 'ios' : 'android',
    ),
    // 事件发生时的离线状态：公共字段 is_offline 的真源
    offline: () => _syncQueue.offline,
  );
  late final AnalyticsFlusher _flusher = AnalyticsFlusher(
    db: _db,
    transport: _buildTransport(),
    outbox: _outbox,
    // 关掉之后**连队列里的也不发**（见 FlushOutcome.disabled 的注释）
    enabled: () => _analytics.enabled,
  );
  Timer? _flushTimer;
  Timer? _coldStartTimer;
  late final LocalStore _store = DriftLocalStore(_db);

  /// 训练提醒（本地通知）。三件东西：设置、平台桥、以及"把两者捏在一起"的服务。
  late final ReminderRepository _reminderRepo = ReminderRepository(_db);
  static const ReminderBridge _reminderBridge = MethodChannelReminder();
  late final ReminderService _reminderService = ReminderService(
    repository: _reminderRepo,
    bridge: _reminderBridge,
    store: _store,
    // 「下一次练哪个部位」—— 训练结束那条预告的输入（没有训练历史时它是 null，
    // 于是那句预告不排，退回通用的"今天还没练"）。问 planner，不在这里现算。
    nextMuscle: () => _planner.nextMuscleGroupKey(),
  );
  ReminderSettings _reminder = ReminderSettings.off;

  /// 「下次提醒：…」那一行。**它是这一版真机反馈的直接产物**：
  /// 用户设了 17:58、当时就是 17:58，而规则把它顺延到明天 ——
  /// 界面上没有任何反馈，于是看起来就是"设了闹钟不响"。
  String? _reminderHint;
  late final ExerciseRepository _repo = ExerciseRepository(_db);
  late final BodyMetricRepository _bodyMetrics = BodyMetricRepository(_db);
  late final RoutineRepository _routines = RoutineRepository(_db);

  /// 站内消息（通知中心）。2026-10-05，v1.50。
  late final NotificationRepository _notifications = NotificationRepository(_db);

  /// 连续保护（补签）的仓库（第二部分第 2 条）。表定义与理由见 `data/db.dart`。
  late final StreakProtectionRepository _streakProtection =
      StreakProtectionRepository(_db);
  late final TodayPlanner _planner =
      TodayPlanner(repository: _repo, store: _store);
  late final SummaryService _summaryService =
      SummaryService(store: _store, repository: _repo);
  late final ProfileRepository _profile = ProfileRepository(_db);

  /// 当前 Tab。五个（训练 / 进步 / 数据 / 计划 / 我的，见 docs/screens.md）。
  /// 当前 tab。**2026-10-07（v1.60.0）起「训练」在正中**（用户 10.7 清单第 2 条），
  /// 所以首页那个下标从 0 变成了 2 —— `_bodyFor` 的映射也跟着改了。
  int _tab = 2;

  /// iOS 的外壳用 `PageView`（**可以左右拖着换 tab**）+ 这个控制器。
  /// Android 不用它（那边仍然是"直接换一屏"，见 `build` 里那条平台判据）。
  /// ⚠️ `initialPage` **必须与 `_tab` 的初值一致**（现在都是 2 = 「训练」）。
  /// 不一致的后果很隐蔽：安卓那条路读 `_tab`（对），iOS 那条路读 PageView（错），
  /// 于是"iOS 冷启动落在进步页、安卓落在训练页"—— 而且两边的底栏高亮都是对的。
  final PageController _pages = PageController(initialPage: 2);

  /// 手指拖到哪儿了（小数页号）—— 底栏那颗玻璃**跟着手指滑**就是靠它喂。
  /// `-1` = 没人在拖（胶囊停在整格上）。
  final ValueNotifier<double> _glassDrag = ValueNotifier<double>(-1);

  /// 正在跑"点 tab 换页"的动画。**这段时间里不喂拖动位置** ——
  /// 那趟动画由原生弹簧自己走（见 `GlassSegmented`），两边同时驱动会打架、看起来是抖。
  bool _tapPaging = false;

  void _onPageScrolled() {
    if (_tapPaging || !_pages.hasClients) return;
    final double? p = _pages.page;
    if (p == null) return;
    _glassDrag.value = p;
  }

  /// 点底栏换 tab：图标颜色**立刻**变（不然要等动画跑完，手感会钝），
  /// 页面滑过去，玻璃由原生弹簧接管。
  void _selectTab(int i) {
    if (i == _tab) return;
    final int from = _tab;
    setState(() => _tab = i);
    if (!GlassSurface.isSupportedPlatform) return;
    _tapPaging = true;
    // 远的 tab 给长一点的时间（不然四页在 300ms 里一闪而过）
    _pages
        .animateToPage(i,
            duration: Duration(milliseconds: 260 + 90 * (i - from).abs()),
            curve: Curves.easeOutCubic)
        .whenComplete(() {
      _tapPaging = false;
      _glassDrag.value = -1;
    });
  }

  /// 有没有同意过隐私政策。**null = 还没从库里读出来**（读出来之前什么都不做）。
  ///
  /// 这一屏是法律要求：国内商店要求"首次运行时以弹窗等明显方式提示用户阅读隐私政策
  /// 并征得同意"，且**同意之前不得收集任何个人信息**。所以它不只是 UI ——
  /// `_initAnalytics()` 也被挪到同意之后（见下面 initState 的注释）。
  bool? _consented;

  /// 用户**明确拒绝过**（拒绝后不弹第二次；且**永远不启动埋点**）。
  bool _declined = false;

  /// 本次启动里**刚过完同意门** —— 首启引导（3 屏卖点轮播）就挂在它上面。
  ///
  /// ⚠️ 为什么不需要新增"看过没"的落库标记：同意门本身就是"每次安装只出现一次"的那个标记。
  /// 用户同意过之后冷启动不会再走到同意门，因此也**不会再走到引导页** ——
  /// 少一个字段就少一处会漂的真相（见引导页文件头那四条约束）。
  bool _introPending = false;

  /// 显示单位。启动时从 user_profile 读一次，用户在 S10 改了之后整棵树重建。
  /// **只影响显示**：存储、引擎、埋点始终是 kg（见 core/units.dart）。
  WeightUnit _unit = WeightUnit.kg;

  /// 体重的显示单位（千克 / 斤）。**与训练重量分开** —— 见 units.dart 的说明。
  BodyWeightUnit _bodyUnit = BodyWeightUnit.kg;

  /// 休息时长偏好。**null = 跟随动作自带的值**，这是默认。
  int? _restOverrideSec;

  /// 用户定过的加重步进（kg，10.9 清单第 8a 条）。null = 没设过。
  double? _defaultStepKg;

  /// 冷启动时刻，用来给事件算 `ms_since_launch`（"从打开到记下第一组用了多久"）。
  final int _launchedAtMs = DateTime.now().millisecondsSinceEpoch;

  int _clock() => DateTime.now().millisecondsSinceEpoch;

  /// 训练目标。**null = 还没走过 S13 的引导** —— S1 据此决定要不要显示入口。
  String? _goalWire;

  /// 最近 7 天练了几次 —— 空态那行字要用。
  /// 之前这个值从没被算过，所以练完回来空态还写着「还没有训练记录」。
  int _weekSessions = 0;

  /// 连续打卡天数与最近几次训练（2026-10-05，新 VI 首页）。
  /// 两个都是**算出来的**（见 features/progress/streak.dart）。
  int _streak = 0;

  /// 一共练过多少次 —— 分享卡打卡版的 "Day N"。
  int _totalWorkouts = 0;

  /// 未读消息数（首页铃铛上那个点）。
  int _unreadNotifications = 0;
  List<({String workoutId, DateTime day, int exercises, int sets, double volume})> _recent =
      const <({String workoutId, DateTime day, int exercises, int sets, double volume})>[];

  /// **全部组记录**（最近一次刷新时读到的，2026-10-06 加）。
  ///
  /// 为什么留在壳层：首页那块周报要算"上周"的完整统计（容量 / 组数 / 破纪录 / 新徽章），
  /// 而 [_recent] 只够画"最近训练"那三行。`_refreshHome()` 本来就把 `allSets()` 读出来了
  /// （徽章消息、提醒、周次数都用它），就手存一份 —— 免得首页为了周报再查一次全表。
  ///
  /// ⚠️ 它**不是状态源**：任何写入路径都会 `_refreshHome()`，所以它只会是"刚读过的那一份"。
  /// 只读它、不直接改它。
  List<SetRecord> _allSets = const <SetRecord>[];

  /// 首页那一行**部位平衡**（第二部分第 5 条）。null = 不显示。
  /// 判据与文案在 `muscle_balance.dart`（纯函数）；这里只负责把动作表查出来。
  String? _muscleBalance;

  /// 首页那一句**回归激励**（第二部分第 9 条）。null = 不显示。
  String? _comebackNudge;

  /// 当前这条链里有几天是补签（0 = 没有）。与 `_streak` 一起算、一起用。
  int _protectedInStreak = 0;

  /// 现在能不能补签（null = 不给）。
  StreakProtectionOffer? _protectionOffer;

  /// 被补签保护过的日子（`YYYY-MM-DD`）。**「我」页的连续天数也要它** ——
  /// 与首页共用同一份读库结果，不各读一遍。
  Set<String> _protectedDays = const <String>{};

  /// **今天的安排**（首页中间那一块，2026-10-04 加）。
  ///
  /// 它与大按钮开练的**是同一份**（[_startNow] 直接用 `_todayPlan`）——
  /// 首页显示了计划却不按它开练，比不显示更糟。
  List<PlannedExercise> _todayPlan = const <PlannedExercise>[];
  TrainingDay? _todayDay;

  /// 未结束的训练会话（冷启动时读一次）。非 null 就说明上次没练完 ——
  /// 首页会显示「继续上次的训练」（2026-10-01）。
  ActiveSession? _activeSession;

  /// 上报地址。还没有后端，所以返回一个「什么都不做但永远失败」的传输实现 ——
  /// 事件会留在本地 outbox 里，等真地址接上再一起送出去（不会丢）。
  /// 上报地址：**编译期可配**，不改代码就能接上真后端。
  ///
  ///   flutter build apk --release \
  ///     --dart-define=LIANLEME_ANALYTICS_URL=https://example.com/v1/events
  ///
  /// 不配就回落 [_NullTransport]：事件照常落本地 outbox（P0 永不丢），只是不发。
  /// **这个默认值是安全的那一个** —— 没配地址却"假装上报了"才是危险的。
  AnalyticsTransport _buildTransport() {
    final String raw = const String.fromEnvironment('LIANLEME_ANALYTICS_URL');
    if (raw.isEmpty) return _NullTransport();
    final Uri? uri = Uri.tryParse(raw);
    final bool usable = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    if (!usable) {
      // 配了但配错：**不发**，而且要让它在开发期看得见。
      // 静默回落到 Null 会让人以为"接了但没数据"，那种问题查起来最费时间。
      debugPrint('LIANLEME_ANALYTICS_URL 不是可用的 http(s) 地址：$raw —— 上报已禁用');
      return _NullTransport();
    }
    return HttpAnalyticsTransport(endpoint: uri);
  }

  @override
  void initState() {
    // 手指拖页面时，每帧把"当前停在第几页"（小数）推给底栏那颗玻璃
    _pages.addListener(_onPageScrolled);
    super.initState();
    _refreshHome();
    unawaited(_loadUnit());
    unawaited(_loadConsentThenStart());
  }

  /// 先问"同意过吗"，再决定起不起埋点。
  ///
  /// ⚠️ **顺序是这个功能的关键**：埋点（哪怕默认包没有上报地址、事件只落本地队列）
  /// 也是"收集"，而规则明确要求**同意之前不收集**。所以 `_initAnalytics()` 和
  /// 种子导入都挪到同意之后 —— 第一版若照原样放在 initState 里，
  /// 就等于"还没问就先开始记了"，那正是这一屏要避免的事。
  Future<void> _loadConsentThenStart() async {
    bool consented = false;
    bool declined = false;
    try {
      consented = await _profile.privacyConsentAtMs() != null;
      declined = await _profile.privacyDeclinedAtMs() != null;
    } catch (_) {
      // 读不出来时**当作没同意**：宁可多问一次，也不要在没同意的情况下开始收集
      consented = false;
    }
    if (!mounted) return;
    setState(() {
      _consented = consented;
      _declined = declined;
    });

    if (consented) {
      unawaited(_initAnalytics());
      unawaited(_importSeedQuietly());
    }
  }

  /// 用户选择"不同意"：**照样让他用 App**，但我们不收集任何东西。
  ///
  /// 这是 191 号文第四条 2 项的直接要求（不得因用户不同意收集非必要信息而拒绝提供业务功能）。
  /// 本地记录本来就不需要联网与权限，所以"不同意的代价"只是没有匿名统计。
  Future<void> _onPrivacyDeclined() async {
    await _profile.setPrivacyDeclined();
    if (!mounted) return;
    setState(() {
      _declined = true;
      _consented = false;
      // 拒绝收集也照样能用 App（191 号文那条），所以引导页同样给他看 ——
      // 它讲的是"这 App 怎么用"，不是"请同意收集"。
      _introPending = true;
    });
    // 刻意**不**调用 `_initAnalytics()` —— 拒绝之后一条事件都不该产生
  }

  Future<void> _onPrivacyAgreed() async {
    await _profile.setPrivacyConsent();
    if (!mounted) return;
    setState(() {
      _consented = true;
      _introPending = true; // 首次进来的三屏卖点（约束 3：在同意门之后）
    });
    // 同意之后才开始：埋点 + 第一次种子导入
    unawaited(_initAnalytics());
    unawaited(_importSeedQuietly());
  }

  /// `app_open`（`docs/analytics.md` §2.1 / §1.1）。
  ///
  /// **这是北极星的分母**：没有它，"首次 24h 内完成一次训练的比例"根本算不出来。
  /// 在此之前客户端从未发过这个事件 —— 上报管线是通的，但漏斗的起点是空的。
  ///
  /// `is_first_open` 必须在**记下首启时间之前**读，顺序颠倒的话它永远是 false。
  Future<void> _trackAppOpen() async {
    bool first = false;
    try {
      first = await _analyticsMeta.isFirstOpen();
    } catch (_) {
      // 读不到就当作"不是第一次" —— 宁可分母少一台设备，也不重复计一次新设备
    }
    _analytics.track('app_open', <String, Object?>{
      'is_first_open': first,
      'ms_since_launch': _clock() - _launchedAtMs,
      'entry': 'cold_start',
    });
    try {
      await _analyticsMeta.markFirstOpen();
    } catch (_) {
      // 记不上就下次再记（首启判定会退化成"每次都是第一次"，但事件不丢）
    }
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
      // 库刷完之后才算得出"今天的安排"（它是从动作库里挑的）——
      // 首页中间那一块就靠这一步拿到内容。
      await _loadTodayPlan();
    } catch (e) {
      // 刷新失败不该挡住启动：库里已有上一份，用户照常能练。
      // 但要留痕 —— 否则"新动作没出现"会变成一个查不下去的问题。
      //
      // ⚠️ 只发**错误类型**，不发整条消息：政策里 `error` 那一栏写的就是「错误类型，不含内容」，
      // 而整条消息可能带文件路径之类的设备细节（`'$e'` 连类名一起发出去）。
      // 这条纪律由 `tool/check-user-text.mjs` 那条"不许把整个异常插进字符串"的规则一起守着。
      _analytics.track('seed_import_failed',
          <String, Object?>{'error': e.runtimeType.toString()});
    }
  }

  Future<void> _loadUnit() async {
    await _loadActiveSession();
    final WeightUnit u = await _profile.unit();
    final BodyWeightUnit b = await _profile.bodyWeightUnit();
    final int? rest = await _profile.restOverrideSec();
    final double? step = await _profile.defaultWeightIncrement();
    final String? goal = await _profile.goalWire();
    // 训练提醒的设置也在这里读一次（设置页要显示它）。
    // 注意**不在这里请求权限** —— 那是用户主动打开开关时才做的事。
    final ReminderSettings reminder = await _reminderRepo.load();
    // 提示行用**刚读出来那份**设置算（此刻还没落进 `_reminder` 字段）
    final String? hint = await _hintFor(const <SetRecord>[], settings: reminder);
    if (!mounted) return;
    setState(() {
      _unit = u;
      _bodyUnit = b;
      _restOverrideSec = rest;
      _defaultStepKg = step;
      _goalWire = goal;
      _reminder = reminder;
      _reminderHint = hint;
    });
  }

  Future<void> _initAnalytics() async {
    // ⚠️ **先问用户的选择，再做任何记录**（2026-09-30，审计 A 的后半段）。
    // 库里那一列的默认值 2026-10-07 起是"开"（用户拍板），但这个对象在内存里的
    // 默认值未必跟着变 —— 而"开关显示开着、实际却没记"或反过来，都是最坏的失败方式。
    // 另外：这个方法**只在 `_onPrivacyAgreed` 里调** —— 首启同意门之前它根本没被启用，
    // 所以"同意之前一条事件都不许入队"是结构上成立的，不是碰巧。
    // 所以这一步在 `_trackAppOpen()` 与任何 flush 之前，顺序就是它的意义。
    _analytics.setEnabled(await _profile.analyticsEnabled());
    await _purgeLegacyOutboxOnce(); // ★ B 方案：配了地址的包，第一次冷启动先丢掉历史积压
    await _flusher.onColdStart(); // 放行上次 parked 的事件
    await _trackAppOpen();
    // 冷启动 5 秒后试一次（analytics-sdk.md §5 的五个触发时机之一）
    _coldStartTimer =
        Timer(const Duration(seconds: 5), () => unawaited(_flusher.flushOnce()));
    // 前台每 60 秒试一次；训练中 flushOnce 自己会跳过
    _flushTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_flusher.flushOnce()),
    );
  }

  /// **接入上报的第一次冷启动：丢掉历史积压**（`docs/analytics.md` §10 的 B 方案，2026-10-04 拍板）。
  ///
  /// 为什么：没配地址的包**不丢事件、只一直攒**（上限 10000 条）。那些事件产生时，
  /// 用户用的是"不对外发送"的包 —— 我们从没告诉过他会被发出去。接上地址的那天补传，
  /// 等于事后改主意，而政策 §3.2 也没覆盖这条。所以**谁记的谁发**：
  /// 第一次在"真的有地址"的包里冷启动时，先清空队列、再记下"清过了"。
  ///
  /// 三条边界（都由测试钉着）：
  ///   * **没配地址就什么都不做** —— 那些包继续攒（行为与以前完全一样）；
  ///   * **只清一次**（`legacyPurgedAt` 落库）；第二次冷启动不会再删任何东西；
  ///   * 清空发生在 `onColdStart()` **之前** —— 否则 parked 的事件会先被放行发出去。
  Future<void> _purgeLegacyOutboxOnce() async {
    if (_buildTransport() is _NullTransport) return;
    if (await _analyticsMeta.legacyPurgedAt() != null) return;
    final int dropped = await _outbox.clearAll();
    await _analyticsMeta.markLegacyPurged(DateTime.now().millisecondsSinceEpoch);
    debugPrint('埋点：已按"谁记的谁发"丢掉接入前的历史积压 $dropped 条（只做一次）');
  }

  /// 首页那两样随"库里的记录"变的东西：**上周练了几次** + **今天的安排**。
  ///
  /// 2026-10-04 合并（原来只刷前一个）：每个"练完回来"的地方都调它，
  /// 而练完回来**今天的安排也变了**（上下肢交替）—— 两件事必须一起刷，
  /// 否则首页会显示着上一次的分化、大按钮却开练另一次。
  Future<void> _refreshHome() async {
    final List<SetRecord> sets = await _store.allSets();
    if (!mounted) return;
    // 四条消息生成规则**都在这里跑**（冷启动与"练完回来"都经过这个出口）：
    // 徽章解锁 / 每周挑战完成 / 错过的训练提醒 —— 都是本地算的，且各自带去重键，
    // 重复调用安全。
    // ⚠️ 云备份那条不在这里：它由云备份那一屏在上传有结果时调（那才是它发生的时刻）。
    await syncAchievementMessages(repo: _notifications, sets: sets);
    await maybeWeeklyChallengeDone(repo: _notifications, sets: sets);
    await maybeRemindMissed(repo: _notifications, settings: _reminder, sets: sets);
    final int unread = await _notifications.unreadCount();
    final String? hint = await _hintFor(sets);
    // 首页那两行（第二部分第 5 / 9 条）。部位表只为**本周练过的动作**查
    // （一次训练几个动作，不是全表读一遍），见 `muscle_balance.dart` 的说明。
    final DateTime now = DateTime.now();
    final Map<String, String> muscleOf = await muscleMapForWeek(
      sets: sets,
      muscleOfId: (String id) async => (await _repo.byId(id))?.muscleGroup,
      day: now,
    );
    final ({String text, String? worst, String? most})? balance =
        muscleBalanceHint(sets: sets, muscleOf: muscleOf, day: now);
    final String? comeback = comebackCopy(sets, now);
    final Set<String> protected = await _streakProtection.protectedDays();
    final StreakProtectionOffer? offer =
        protectionOffer(sets, protected, now);
    if (!mounted) return;
    setState(() {
      _weekSessions = weekWorkoutCount(sets, DateTime.now());
      // 连续天数**认补签**（被保护的那天撑住链、也计 1 天）——
      // 与 `streak.dart` 的口径只差这一处，纯函数在 `streak_protection.dart`。
      _streak = streakWithProtection(sets, protected, now);
      _protectedInStreak = protectedDaysInStreak(sets, protected, now);
      _totalWorkouts = totalWorkouts(sets);
      _recent = recentWorkouts(sets);
      _allSets = sets; // 首页周报要算"上周"的完整统计，见字段注释
      _muscleBalance = balance?.text;
      _comebackNudge = comeback;
      _protectionOffer = offer;
      _protectedDays = protected;
      _reminderHint = hint;
      _unreadNotifications = unread;
    });
    await _loadTodayPlan();
    // 训练提醒也在这里同步：这个函数是"开 App / 练完回来"的公共出口，
    // 而提醒的正确状态正好取决于**刚刚是不是练过了**（练过就顺延到明天）。
    await _syncReminder();
  }

  /// 「下次提醒：…」。传 sets 是为了知道**今天练过没有** ——
  /// 练过就会顺延到明天（或者今晚换成训练结束那条预告），
  /// 而那正是用户最需要被告知的一件事。
  ///
  /// [settings] 不传就用字段上那份设置。为什么留这个口子：两处调它的时候
  /// **新的设置还没有落进 `_reminder`**（`_loadUnit` 刚读出来、`_setReminder` 刚保存），
  /// 用字段算出来的提示行会是上一份设置的结果 —— 那正是"界面与系统里排着的那条不一致"。
  Future<String?> _hintFor(List<SetRecord> sets, {ReminderSettings? settings}) async {
    final ReminderSettings now = settings ?? _reminder;
    final int at = DateTime.now().millisecondsSinceEpoch;
    final bool trainedToday = hasTrainedOn(
      sets: sets,
      day: DateTime.fromMillisecondsSinceEpoch(at),
    );
    return reminderHint(
      settings: now,
      trainedToday: trainedToday,
      nowMs: at,
      // 与 `ReminderService.sync()` 问的是同一个问题 —— 界面上的这一行必须
      // 与系统里**真的排着的那条**一致，否则它就是一句会撒谎的话。
      nextMuscleKey: trainedToday ? await _planner.nextMuscleGroupKey() : null,
    );
  }

  /// 把系统里排着的提醒同步成"当前设置 + 今天的事实"该有的样子。
  /// 失败静默（`ReminderService` 里每一层都不抛）—— 排不上提醒不该影响记录训练。
  Future<void> _syncReminder() async {
    await _reminderService.sync();
  }

  /// 用户改了提醒设置（S10）。**打开时才向系统要通知权限**（不在启动时要）。
  Future<bool> _setReminder(ReminderSettings next) async {
    if (next.enabled) {
      final bool allowed =
          await _reminderBridge.isAllowed() || await _reminderBridge.requestPermission();
      if (!allowed) return false;
    }
    await _reminderRepo.save(next);
    // setState 是同步闭包，取数据必须在它外面（await 不能写在里面）；
    // 提示行也用**刚保存的这份**算，别用字段上那份旧的（见 [_hintFor]）。
    final List<SetRecord> sets = await _store.allSets();
    final String? hint = await _hintFor(sets, settings: next);
    if (mounted) {
      setState(() {
        _reminder = next;
        _reminderHint = hint;
      });
    }
    await _syncReminder();
    return true;
  }

  /// 今天的安排（首页中间那一块）。
  ///
  /// ⚠️ **它与大按钮开练的是同一份计划**（`_todayPlan` 被 [_startNow] 直接用）——
  /// 首页显示了计划却不按它开练，比不显示更糟（"我看到的和我要练的不是一回事"）。
  Future<void> _loadTodayPlan() async {
    try {
      final TrainingDay day = await _planner.nextTrainingDay();
      final List<PlannedExercise> plan =
          await _planner.planToday(
              day: day,
              unit: _unit,
              // 10.8 清单第 8 条（用户选 A）：每周 ≤3 天 → 每个动作 4 组，≥4 天 → 3 组
              weeklyFrequency: await _profile.weeklyFrequency());
      if (!mounted) return;
      setState(() {
        _todayDay = day;
        _todayPlan = plan;
      });
    } catch (_) {
      // 首页那块只是**预览**，主路径是大按钮 —— 它出问题不该让首屏崩掉。
      // 开练时 [_startNow] 还会自己再算一次，所以"预览空了"不等于"练不了"。
    }
  }

  /// 「换一批」：在同一天的分化里换动作（换完仍然是首页显示的那一份）。
  Future<void> _rerollTodayPlan() async {
    if (_todayPlan.isEmpty) {
      await _loadTodayPlan();
      return;
    }
    try {
      final List<PlannedExercise> next = await _planner.reroll(
        current: _todayPlan,
        unit: _unit,
      );
      if (!mounted) return;
      setState(() => _todayPlan = next);
    } catch (_) {
      // 同上：换不动就保持原来那份，不弹错
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    _glassDrag.dispose();
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
  Future<void> _trainSession(
    String workoutId,
    List<SessionEntry> entries, {
    required String source,
    int initialIndex = 0,
    /// 恢复时"休息到什么时候"（绝对毫秒）。只对 [initialIndex] 那个动作生效。
    int? restEndsAtMs,
    /// 恢复时：**这次训练里已经记过的组**（整条训练，含热身）。
    ///
    /// 不传的后果（2026-10-04 真机走查抓到的 P0）：恢复后界面显示「第 1 组」、
    /// 已完成列表是空的，用户再记一组就按 `set_seq = 1` 写库、**覆盖掉原来那一组**
    /// （总数不变，所以看不出来）。调用方用 `store.setsFor(workoutId)` 取。
    List<SetRecord> alreadyLogged = const <SetRecord>[],
    /// 恢复时沿用原训练的开始时刻（否则总结页的时长只剩后半段）。
    int? startedAtMs,
  }) async {
    if (entries.isEmpty) return;

    // 漏斗第 2 环。source 回答"用户是从哪条路开始练的"——
    // 首页大按钮压到 1 跳之后，这一环的转化率是那一版改动的直接检验。
    _analytics.track('workout_started', <String, Object?>{
      'source': source,
      'exercise_count': entries.length,
      'ms_since_launch': _clock() - _launchedAtMs,
    });

    // 红线：训练进行中不发任何网络请求。
    // 健身房常年弱网，任何请求都可能跟"记一组"抢资源。
    _flusher.suspend();

    final List<WorkoutController> controllers = <WorkoutController>[];
    for (int i = 0; i < entries.length; i++) {
      final SessionEntry entry = entries[i];
      controllers.add(WorkoutController(
        workoutId: workoutId,
        exercise: _repo.specOf(entry.exercise),
        // 处方逐项带上：计划模板里每个动作的组数/次数区间是分开的
        plan: entry.plan,
        analytics: _analytics,
        store: _store,
        syncQueue: _syncQueue,
        // 组间休息的 Live Activity（iOS 锁屏/灵动岛）。**生产在这里接上真的那个** ——
        // 默认值是 noop，所以漏传不会报错，只会"锁屏上什么都没有"。
        restActivity: const MethodChannelRestActivity(),
        // 记一组 / 休息结束的触觉反馈（v1.53）。**生产在这里接上真的那个** ——
        // 默认是 NoopHaptics，漏传不会报错，只会"记了组没震"。
        haptics: const SystemHaptics(),
        // 休息结束的体外提示（Android 通知；iOS 侧是空操作，那边有 Live Activity）。
        // 同样"漏传不报错、只是锁屏上没有东西"。
        restCue: const MethodChannelRestCue(),
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
        // 从被中断的训练回来时，**只有当前那个动作**接着倒数休息；
        // 别的动作本来就没在休息，传了反而会凭空起一个倒计时。
        restEndsAtMs: i == initialIndex ? restEndsAtMs : null,
        // 恢复时把**这个动作已经记过的组**还给它（2026-10-04 修 P0）：
        // 少了这一步，恢复后记一组会覆盖掉杀进程前那一组。
        alreadyLogged: <SetRecord>[
          for (final SetRecord s in alreadyLogged)
            if (s.exerciseId == entry.exercise.id) s,
        ],
        startedAtMs: startedAtMs,
      ));
    }
    final WorkoutSession session =
        WorkoutSession(controllers, initialIndex: initialIndex);

    // ── 未结束的会话：训练期间一直写，结束（路由回来）就清（2026-10-01）──
    //
    // 为什么要有它：组记录本来就是逐条落库的，但"练到第几个动作、休息还剩多久"
    // 原先只在内存里 —— 接个电话、切到微信、系统把 App 杀掉，回来就回到了首页，
    // 那次训练像没发生过。现在这一步把这份**运行时状态**也存下来。
    //
    // ⚠️ 只在"指纹"变化时才写：休息倒计时每秒都会通知一次，
    // 每秒写一次库是没必要的（而且是在健身房、可能的低端机上）。
    String fingerprint = '';
    Future<void> persistSession() async {
      final String now = '${session.index}|'
          '${session.current.workout.sets.length}|'
          '${session.current.restEndsAtMs ?? 0}';
      if (now == fingerprint) return;
      fingerprint = now;
      await _store.saveActiveSession(ActiveSession(
        workoutId: workoutId,
        entries: <ActiveEntry>[
          for (final SessionEntry e in entries)
            ActiveEntry(exerciseId: e.exercise.id, plan: e.plan),
        ],
        index: session.index,
        restEndsAtMs: session.current.restEndsAtMs,
        startedAtMs: _clock(),
        source: source,
      ));
    }

    void onSessionChanged() {
      // 不 await：这是"顺手记一下状态"，不能拖慢记一组的交互
      unawaited(persistSession());
    }

    session.addListener(onSessionChanged);
    await persistSession(); // 开始训练这件事本身就该被记住

    /// **器械被占了 → 换一个动作**（2026-10-05，v1.53）。
    ///
    /// 健身房最高频的意外就是深蹲架被占：原来的做法是退出训练、重新选动作、
    /// 重量次数还得重填 —— 它直接伤「单次 ≥ 12 组」这条护栏。
    ///
    /// 换的时候要守住四件事：
    ///   1. **同部位预筛**（器械被占时要的是"换个练同一块的"，不是重新逛 351 个动作）；
    ///   2. **新动作的默认值来自它自己的历史/处方**（不是沿用上一个动作的重量 ——
    ///      腿举 100 kg 挪到箭步蹲上会直接把人练伤）；
    ///   3. **已经记过的组一条不动**（组本来就逐条落库了；换动作只换"接下来练什么"）；
    ///   4. **崩溃恢复后换过的动作也在** —— 所以 `entries` 要就地改，
    ///      `ActiveSession` 存的就是它（不改的话，杀进程回来会看到早就换掉的那个动作）。
    Future<void> swapCurrentExercise() async {
      final WorkoutController old = session.current;
      final ExerciseData? picked = await Navigator.of(context).push<ExerciseData>(
        MaterialPageRoute<ExerciseData>(
          builder: (BuildContext ctx) => ExercisePickerScreen(
            repository: _repo,
            store: _store,
            unit: _unit,
            analytics: _analytics,
            // 同部位预筛：只在动作库行里有部位时才传
            initialMuscle: entries[session.index].exercise.muscleGroup,
          ),
        ),
      );
      if (picked == null || !mounted) return;
      if (picked.id == old.exercise.id) return; // 选了同一个 = 什么都没发生

      // ★ 协同性提示（2026-10-08，10.8 清单第 5 条）：手动换进来的动作若与
      // "今天这一场已经在练的肌群"**完全没交集**（只看主肌群），先问一声。
      // 非阻断：用户点「仍然换」就照换 —— 提示只是把"你可能没注意"这件事说出来。
      final String? warning = muscleSynergyWarning(
        pickedId: picked.id,
        pickedMuscle: picked.muscleGroup,
        session: <({String id, String muscle, List<String> secondary})>[
          for (final SessionEntry e in entries)
            (
              id: e.exercise.id,
              muscle: e.exercise.muscleGroup,
              secondary: e.exercise.secondaryMuscleList,
            ),
        ],
        muscleNames: kMuscleLabels,
      );
      if (warning != null) {
        if (!mounted) return;
        final bool go = await showDialog<bool>(
              context: context,
              builder: (BuildContext ctx) => AlertDialog(
                backgroundColor: Tokens.surface,
                title: const Text('这个动作和今天不太搭',
                    style: TextStyle(color: Tokens.text)),
                content: Text(
                  '$warning\n\n计划是建议，不是牢笼 —— 想换就换。',
                  key: const Key('synergy-note'),
                  style: const TextStyle(color: Tokens.text2, height: 1.6),
                ),
                actions: <Widget>[
                  TextButton(
                    key: const Key('synergy-cancel'),
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('算了', style: TextStyle(color: Tokens.text2)),
                  ),
                  TextButton(
                    key: const Key('synergy-continue'),
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('仍然换', style: TextStyle(color: Tokens.accent)),
                  ),
                ],
              ),
            ) ??
            false;
        if (!go) return;
      }

      // 新动作的"上次"要**排除本次训练**：否则会把这次刚记的组当成上次
      final WorkoutController next = WorkoutController(
        workoutId: workoutId,
        exercise: _repo.specOf(picked),
        // 处方形状沿用这一格原来的（同样的组数/次数）——
        // 用户要的是"换个动作继续练"，不是"重新定计划"
        plan: entries[session.index].plan,
        analytics: _analytics,
        store: _store,
        syncQueue: _syncQueue,
        restActivity: const MethodChannelRestActivity(),
        haptics: const SystemHaptics(),
        restCue: const MethodChannelRestCue(),
        lastSession: await _store.lastSessionFor(picked.id, excludeWorkoutId: workoutId),
        profile: UserProfile(unit: _unit, restOverrideSec: _restOverrideSec),
        // 这个动作在这次训练里**已经记过的组**（换了再换回来时不丢）
        alreadyLogged: <SetRecord>[
          for (final SetRecord r in await _store.setsFor(workoutId))
            if (r.exerciseId == picked.id) r,
        ],
      );

      // ① 会话换掉当前那一格；② entries 就地改（崩溃恢复要用）；
      // ③ 旧控制器收掉（它可能还在休息倒计时 —— 那条倒计时跟着它一起结束）
      session.replaceCurrent(next);
      entries[session.index] = SessionEntry(exercise: picked, plan: entries[session.index].plan);
      old.dispose();
      // 换动作对用户是一次额外操作 —— 与"点底部条切动作"同一个意图，计一次
      next.analytics.countTap(TapKind.exerciseSwitch);
      unawaited(persistSession());
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutScreen(
          session: session,
          // 完整动作库行：控制器只有瘦身过的 ExerciseSpec，而详情页要说明/部位/器械
          catalog: <ExerciseData>[
            for (final SessionEntry e in entries) e.exercise,
          ],
          store: _store,
          onSwapExercise: swapCurrentExercise,
          // 改加重步进（10.9 清单第 8a 条）：写在**这个动作自己**身上 ——
          // 下次进来还是它，别的动作不受影响（要一次铺到所有动作，去设置页那个开关）。
          onWeightStepChanged: (String exerciseId, double kg) =>
              _repo.setWeightIncrement(exerciseId, kg),
          // 「所有动作都改」：铺到整个动作库 + 记成"你设的默认值"（设置页以后要显示它）。
          // ⚠️ 自重动作在里面被跳过（`weight_increment == 0` 是"没有重量"的标记）。
          onWeightStepAll: (double kg) async {
            await _repo.setAllWeightIncrements(kg);
            await _profile.setDefaultWeightIncrement(kg);
          },
        ),
      ),
    );

    session.removeListener(onSessionChanged);

    // ★ 器械复位提醒（10.8 清单第 6 条）。用户原话：
    //   「做完当天计划中，**带杠铃片器械**的训练之后，弹窗提醒使用完器械一定要记得
    //   卸片，主动复位。」
    // ⚠️ 三个判据都写在这里：① 只在**真的用了杠铃**时才提醒（器械/绳索/自重不提醒 ——
    // 那些本来就没有片子可卸）；② 一次训练只弹一次（就在退出训练屏这一刻）；
    // ③ 用户自己中途退出也会弹 —— 他同样把杠铃留在架子上了。
    if (mounted && entries.any((SessionEntry e) => e.exercise.equipment == 'barbell')) {
      await _remindUnloadPlates();
    }

    // 训练结束了（正常结束或用户自己退出）—— 未结束的会话到此为止。
    // 不清的话，下次冷启动会把用户送回一个早就结束的训练。
    await _store.clearActiveSession();

    session.dispose();
    // ⚠️ 用 `session.allControllers` 而不是上面那个局部 `controllers` 列表：
    // 训练中"换动作"（v1.53）会把当前那一格换成**新造**的控制器，
    // 局部列表里还留着旧的 —— 照它 dispose 会漏掉换进来的那个（计时器/监听泄漏），
    // 而那个旧的已经由换动作那条路自己收掉了（重复 dispose 在 debug 下会断言失败）。
    for (final WorkoutController c in session.allControllers) {
      c.dispose();
    }
    _flusher.resume();

    // **训练结束 → 把提醒重新同步一次**（`docs/feature-backlog.md` 第 6 条）。
    //
    // 为什么在这个出口、而不是各个调用点：每一段训练（首页大按钮 / 计划 / 轻量活动 /
    // 崩溃后恢复）都从这里回来，而"练完了"这件事对提醒的影响是同一件 ——
    // 从前只有走 `_refreshHome()` 的那几条路会同步，恢复后再练那条不会。
    //
    // 此刻这一趟的组**已经逐条落库**了（组是记一组写一条），所以 sync() 看到的
    // 就是"今天练过了"这个事实；说不说得出来"下次练哪儿"由 planner 回答，
    // 综合判断在 `composeReminder`（纯函数、有测试）。
    //
    // ⚠️ **绝不能 await**（2026-10-05 写这一行时踩到的）：`sync()` 最后要走平台通道
    // （排/撤系统通知），而**平台通道没有回复时那个 Future 永远不会完成** ——
    // 在 widget 测试里当场就是"总结页再也出不来"（`home_entry_test` 的漏斗那条红），
    // 在真机上就是"点了返回，界面卡在训练屏"。提醒是"顺手做的事"，
    // 排不上/排得慢都绝不该挡住总结页 —— 与 `persistSession()` 同一条纪律。
    unawaited(_syncReminder());
  }

  /// 继续上次没结束的训练（2026-10-01）。
  ///
  /// 冷启动时首页会显示入口：有未结束的会话才有（`_activeSession`）。
  /// 重建的方式与开新训练完全一样（同一批动作、同样的处方），只是**落在原来那个动作上、
  /// 接着把休息数完** —— 恢复不该是另一条代码路径，否则它迟早与正常流程长歪。
  Future<void> _resumeSession() async {
    final ActiveSession? a = await _store.activeSession();
    if (a == null) return;
    final List<SessionEntry> entries = <SessionEntry>[];
    for (final ActiveEntry e in a.entries) {
      final ExerciseData? row = await _repo.byId(e.exerciseId);
      if (row != null) entries.add(SessionEntry(exercise: row, plan: e.plan));
    }
    if (entries.isEmpty) {
      // 动作库对不上了（比如种子换过）—— 会话没意义，清掉，别让入口一直挂着
      await _store.clearActiveSession();
      if (mounted) setState(() => _activeSession = null);
      return;
    }
    await _trainSession(
      a.workoutId,
      entries,
      source: a.source,
      initialIndex: a.index.clamp(0, entries.length - 1),
      restEndsAtMs: a.restEndsAtMs,
      // ★ 这次训练已经记过的组（含热身）—— **从库里读，不从 JSON 里的计数器读**：
      //   组本来就逐条落库了，数据库是真源。少了这一步就是 2026-10-04 那个 P0：
      //   恢复后界面从"第 1 组"重新数，再记一组会覆盖掉原来那一组。
      alreadyLogged: await _store.setsFor(a.workoutId),
      // 开始时刻也要沿用：否则这次训练的行会被写成"恢复的那一刻"，
      // 总结页的时长只剩后半段。
      startedAtMs: a.startedAtMs,
    );
    if (mounted) await _loadActiveSession();
  }

  /// 「今天不想练」的 5 分钟活动（2026-10-01）。
  ///
  /// 为什么有它：习惯养成的敌人是"全有或全无"——今天没力气做正式训练，
  /// 不等于该断掉。这条路径给 **4 个按时长的活动**（绕臂 / 猫牛式 / 平板支撑 / 婴儿式），
  /// 每个 **1 组 30–45 秒**，几分钟走完，**也算一次训练**。
  ///
  /// 三个刻意的选择：
  ///   * 全是 `time` 动作 → 它们没有"重量 × 次数"的容量，**不会污染容量与 PR**；
  ///   * 用**热身处方**（1 组）而不是正式处方（3 组）——它是活动，不是训练量；
  ///   * `source: light` 单独上报，将来能回答"这条路径有没有人用"。
  Future<void> _startLight() async {
    final List<SessionEntry> entries = <SessionEntry>[];
    for (final String id in kLightActivityIds) {
      final ExerciseData? e = await _repo.byId(id);
      if (e == null) continue; // 种子换过名字也不至于崩
      entries.add(SessionEntry(exercise: e, plan: kDefaultWarmupPlan));
    }
    if (entries.isEmpty) return;
    await _trainSession(
      'w_${_clock()}_light',
      entries,
      source: 'light',
    );
  }

  /// 只练一个动作。「我自己选」那条流程每次只加一个。
  Future<void> _trainOne(String workoutId, ExerciseData exercise) =>
      _trainSession(
        workoutId,
        <SessionEntry>[
          SessionEntry(exercise: exercise, plan: defaultPlanFor(exercise)),
        ],
        source: 'picker',
      );

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
          analytics: _analytics,
        ),
      ),
    );
    if (r == null || !mounted) return;

    // 入口该收起来了
    final String? goal = await _profile.goalWire();
    if (mounted) setState(() => _goalWire = goal);

    if (!r.startNow) {
      await _refreshHome();
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
      source: 'onboarding',
    );
    await _showSummary(workoutId);
    await _refreshHome();
  }

  /// S1 的大按钮：**一跳直接开练**。
  ///
  /// 原来的路径是「今日页 → 建议卡 → 大按钮」= 端到端 3 次点击才记下第一组，
  /// 而 `PRODUCT.md` §1 的红线是"超过 3 次点击判负"—— 刚好压线；
  /// 竞品 Everlift 的公开数字是"3 组从约 21 次降到 8 次"（≈2.7 次/组）。
  /// 现在：首页这一下直接进训练屏 → 第一组 **2 次**，同一动作的第 2 组起 **1 次**。
  ///
  /// 建议卡没有被砍掉，只是挪到「今天的安排」卡后面 —— **点那张卡进建议卡**（见 [_openSuggestion]）。
  Future<void> _startNow() async {
    // 端到端口径：这一下就是这条记录的第一步（周期必须在这里开）
    _analytics.beginSetInteraction();
    _analytics.countTap(TapKind.nav);

    await _repo.importSeed(loadJson: widget.seedLoader);
    if (!mounted) return;

    // **用首页显示的那一份**（2026-10-04）：首页中间现在摆着"今天的安排"，
    // 大按钮必须按它开练 —— 否则用户看到的是清单 A、练的是清单 B。
    // 预览为空（还没算出来 / 算的时候出过错）才现算一次。
    List<PlannedExercise> plan = _todayPlan;
    if (plan.isEmpty) {
      _todayDay = await _planner.nextTrainingDay();
      plan = await _planner.planToday(
          day: _todayDay,
          unit: _unit,
          weeklyFrequency: await _profile.weeklyFrequency());
      if (!mounted) return;
    }

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
      // 首页大按钮：1 跳直开练那条路
      source: 'home_button',
    );
    await _showSummary(workoutId);
    await _refreshHome(); // 练完回来，次数要变
  }

  /// 建议卡路径（换一批 / 我的计划 / 我自己选）—— 由首页「今天的安排」**卡本身**进入。
  ///
  /// 2026-10-04：原先这里还有一行「看看今天练什么 ›」，删掉了（卡已经把"今天练什么"
  /// 回答了，同一件事不留两个入口），见 `today_screen.dart` 里 `onSeePlan` 的说明。
  /// 快速入口：动作库（2026-10-05 v1.48）。
  ///
  /// ⚠️ 这里以前接的是「全部数据」—— 那是 v1.46 里写明的**过渡状态**
  /// （真正的动作库还没做）。现在换成真的动作库页，偏差收掉。
  Future<void> _openLibrary() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExerciseLibraryScreen(
          repository: _repo,
          store: _store,
          unit: _unit,
        ),
      ),
    );
  }

  /// 打开消息通知（首页右上角铃铛）。回来时刷新未读数 ——
  /// 用户在里面点了「全部已读」，首页那个点要跟着消失（否则他会以为没生效）。
  /// **练完带杠铃片的动作之后**：提醒卸片与复位（10.8 清单第 6 条）。
  ///
  /// 为什么值得弹一次：这条提醒**在健身房里是刚需**（不卸片是安全事故，也是礼仪），
  /// 而 App 是那个"知道你今天用了杠铃"的唯一角色。文案只讲事实与动作，不说教。
  Future<void> _remindUnloadPlates() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: Tokens.surface,
        title: const Text('杠铃归位了吗', style: TextStyle(color: Tokens.text)),
        content: const Text(
          '今天用了杠铃 —— 走之前记得卸片、把杠铃放回架子上。'
          '下一个人可能会直接用，留着片子既危险也不礼貌。',
          key: Key('unload-plates-note'),
          style: TextStyle(color: Tokens.text2, height: 1.6),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('unload-plates-ok'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('已归位', style: TextStyle(color: Tokens.accent)),
          ),
        ],
      ),
    );
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationCenterScreen(repository: _notifications),
      ),
    );
    if (!mounted) return;
    final int unread = await _notifications.unreadCount();
    if (!mounted) return;
    setState(() => _unreadNotifications = unread);
  }

  /// 快速入口：我的成就。**组记录已经在手上**（`_recent` 那次加载拿过），
  /// 但成就要的是全量，所以这里重新读一次并交给那一屏 —— 不与「我」页共用状态，
  /// 免得两处的"已解锁"在返回后不同步。
  /// **补签保护那一天**（第二部分第 2 条）。
  ///
  /// 三件事，顺序不能变：先写库（`streak_protection` 表里加一行"这一天被保护了"）、
  /// 再刷新首页（连续天数立刻变长、那一行"其中 N 天是补签"也立刻出现）、
  /// 最后弹一句**如实**的说明 —— 用户点的是一个会改变"连续多少天"的动作，
  /// 它值得一句确认。
  ///
  /// ⚠️ 这里**不动任何训练记录**：补签不是"那天我练了"，而是"我知道那天断了，
  /// 我选择不让这条链断在这里"。记录就是事实，这一点在所有功能里都一样。
  Future<void> _protectStreak() async {
    final StreakProtectionOffer? offer = _protectionOffer;
    if (offer == null) return;
    await _streakProtection.protect(dayKey(offer.day));
    await _refreshHome();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已保护 ${offer.day.month} 月 ${offer.day.day} 日这一处断点 —— 每周一次。'),
    ));
  }

  /// **周报 → 分享卡预览**（第二部分第 1 条）。
  ///
  /// 复用现有那套分享卡（同一棵 `ShareCard`、同一个抓图与交付路径）：
  /// 用户已经把那张卡当成"练了么的卡"了，为周报再画一套长相不同的卡没有收益，
  /// 而两条抓图/存相册的路径却要各自维护。
  Future<void> _openWeeklyReport() async {
    final WeeklyReport r = weeklyReportFor(_allSets, DateTime.now());
    if (r.isEmpty) return; // 没练过的一周不值得做成卡（按钮本来就只在练过时出现）
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ShareCardPreviewScreen(
          summary: WorkoutSummary(
            workoutId: 'week-${r.start.millisecondsSinceEpoch}',
            totalSets: r.totalSets,
            totalVolumeKg: r.volumeKg,
            duration: r.durationMin > 0 ? Duration(minutes: r.durationMin) : null,
            exerciseCount: r.exerciseCount,
            prs: const <SetPr>[],
            startedAtMs: r.start.millisecondsSinceEpoch,
            distanceM: r.distanceM,
            distanceSets: r.distanceM > 0 ? 1 : 0,
          ),
          streak: r.activeDays,
          ordinal: weekOrdinal(DateTime.now()),
          analytics: _analytics,
        ),
      ),
    );
  }

  Future<void> _openAchievements() async {
    final List<SetRecord> sets = await _store.allSets();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AchievementsScreen(sets: sets),
      ),
    );
  }

  /// 快速入口：记录体重（与「进步」页那张体重卡是同一个页面）。
  Future<void> _openBodyMetric() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BodyMetricScreen(
          repository: _bodyMetrics,
          unit: _bodyUnit,
          analytics: _analytics,
          profile: _profile,
          onSaved: () => unawaited(_refreshHome()),
        ),
      ),
    );
  }

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
            store: _store,
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
        source: 'suggestion',
      );
      await _showSummary(workoutId);
      await _refreshHome(); // 练完回来，次数要变
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
            analytics: _analytics,
          ),
        ),
      );
      if (picked == null || !mounted) break;
      // 从动作库挑一个动作 = 一次选动作点击
      _analytics.countTap(TapKind.exercisePick);
      await _trainOne(workoutId, picked);
    }
    await _showSummary(workoutId);
    await _refreshHome();
  }

  /// 读一次"有没有未结束的训练"（首页那个入口用它）。
  Future<void> _loadActiveSession() async {
    final ActiveSession? a = await _store.activeSession();
    if (!mounted) return;
    setState(() => _activeSession = a);
  }

  /// 训练结束总结。一组都没练就直接回空态 —— 没什么可总结的。
  /// 练完该拉伸哪儿：按这次练得最多的那个部位给 1–2 个拉伸动作。
  ///
  /// 练得最多 = 组数最多的部位（不是"第一个动作的部位"）：
  /// 一次胸+三头里三头只做两组、胸做了九组，该拉的是胸。
  Future<({List<ExerciseData> stretches, String? topMuscle})> _stretchesFor(
      Workout w) async {
    final List<({String muscleGroup, String category})> trained =
        <({String muscleGroup, String category})>[];
    for (final SetRecord r in w.sets) {
      if (r.setType != SetType.normal) continue;
      final ExerciseData? e = await _repo.byId(r.exerciseId);
      if (e == null) continue;
      trained.add((muscleGroup: e.muscleGroup, category: e.category));
    }
    // 挑选口径（跳过热身/拉伸、取组数最多）在 today_planner 里，是纯函数、有测试
    final String? top = topMuscleGroupForStretch(trained);
    if (top == null) {
      return (stretches: const <ExerciseData>[], topMuscle: null);
    }
    // 顺带把"今天练得最多的是哪个部位"带出去 —— 「下一次」那一行要用它做对比，
    // 再查一遍库没必要（这个函数本来就把部位算出来了）。
    return (stretches: await _planner.stretchFor(muscleGroup: top), topMuscle: top);
  }

  Future<void> _showSummary(String workoutId) async {
    // 训练结束是五个上报时机之一，这时最该送一次
    unawaited(_flusher.flushOnce());

    final Workout? w = await _store.loadWorkout(workoutId);
    if (w == null || w.sets.isEmpty || !mounted) return;

    // 漏斗第 4 环 + **北极星的分子**。属性按 docs/analytics.md §2.2：
    // duration_sec / total_sets / total_volume_kg / exercise_count。
    // 验收清单里有一条 sanity check：set_logged 条数要和 total_sets 对得上 ——
    // total_sets 只数正式组（热身不算），set_logged 那边也一样（热身组照记，
    // 但对比时用正式组），这条一致性由 analytics_test 里的端到端用例守着。
    final Set<String> exercised = <String>{
      for (final SetRecord r in w.sets) r.exerciseId,
    };
    _analytics.track('workout_finished', <String, Object?>{
      'duration_sec': w.duration?.inSeconds,
      'total_sets': w.totalSets,
      'total_volume_kg': w.totalVolume.round(),
      'exercise_count': exercised.length,
      'ms_since_launch': _clock() - _launchedAtMs,
    });
    // 拉伸建议在这里先算好：builder 不是 async 函数，await 放不进去
    final ({List<ExerciseData> stretches, String? topMuscle}) stretchInfo =
        await _stretchesFor(w);
    final List<ExerciseData> stretches = stretchInfo.stretches;

    // 「下一次」那一行（2026-10-01）：刚练完是用户唯一愿意想下一次的时刻。
    // 轮转用的是 planner 的同一套规则（它已经算上了今天这次训练），
    // 所以这里说出来的"下次轮到谁"与首页/建议卡的口径一致 —— 不会两处说两样话。
    //
    // 2026-10-04：轮转从"6 部位"改成"上下肢交替"，所以这里说的是**训练日**
    // （"下次轮到 下肢"），不再是单个部位。
    String? nextLine;
    final String? todayTop = stretchInfo.topMuscle;
    final TrainingDay nextDay = await _planner.nextTrainingDay();
    if (_todayDay == null || nextDay != _todayDay) {
      nextLine = todayTop == null
          ? '下次轮到 ${nextDay.label}'
          : '下次轮到 ${nextDay.label}（今天练的是 ${kMuscleLabels[todayTop] ?? todayTop}）';
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutSummaryScreen(
          service: _summaryService,
          workoutId: workoutId,
          unit: _unit,
          stretches: stretches,
          nextLine: nextLine,
          analytics: _analytics,
          streak: _streak,
          // "第几次训练"用**练完之后**的总数（这次刚记完，已经在库里了）
          ordinal: _totalWorkouts,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 还没读出同意状态：先给一块同色底（不闪、也不提前渲染任何内容）
    if (_consented == null) {
      return const Scaffold(backgroundColor: Tokens.bg, body: SizedBox.expand());
    }
    // 没同意过：整屏征求同意 —— 主界面**一个像素都不渲染**
    if (_consented == false && !_declined) {
      return PrivacyConsentScreen(
        onAgree: _onPrivacyAgreed,
        onDecline: _onPrivacyDeclined,
      );
    }
    // 首启引导：**在同意门之后**、主界面之前（约束 3）。
    // 跳过 → 直接进主界面；末屏按钮 → 开始第一次训练（约束 4）。
    if (_introPending) {
      return IntroCarouselScreen(
        onSkip: () => setState(() => _introPending = false),
        onStartFirst: () {
          setState(() => _introPending = false);
          unawaited(_startNow());
        },
      );
    }
    // 外壳有两种排布，**判据只有一条**（`GlassSurface.isSupportedPlatform`）：
    //   * **iOS**：内容铺满整屏，底栏作为**浮动胶囊浮在它上面** —— 滚动时真实内容从玻璃
    //     后面经过，那正是 iOS 26 那个观感的来源（用户 2026-10-06 拍板要的就是这个）；
    //   * **Android**：底栏仍然贴在内容的**下面**（通栏、贴底）—— **一个像素都不改**。
    // 两种排布下各屏都要留出底栏的位置，那份空间由 `AppTabBar.reservedSpaceFor(context)`
    // 回答（Android 上它是 0）。
    final Widget tabBar = AppTabBar(
      current: _tab,
      onChanged: _selectTab,
      dragIndex: GlassSurface.isSupportedPlatform ? _glassDrag : null,
    );
    // **统一顶栏**（2026-10-07，v1.60.0；用户 10.7 清单第 1、6 条）：
    // 左标题 + 右上角 [齿轮][铃铛]，五个 tab 共用一条 —— 之前是五屏各画各的标题，
    // 于是铃铛只活在首页、设置只活在「我」页，而它们本来都是**全局**的东西。
    final Widget topBar = AppTopBar(
      title: _topBarTitle,
      subtitle: _topBarSubtitle,
      unread: _unreadNotifications,
      onOpenSettings: _openSettings,
      onOpenNotifications: _openNotifications,
    );
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // 统一顶栏（v1.60.0）：左标题 + 右上角 [齿轮][铃铛]，五个 tab 共用
            topBar,
            Expanded(
              child: !GlassSurface.isSupportedPlatform
                  // Android：底栏仍然贴在内容**下面**（通栏、贴底）。
                  ? Column(
                      children: <Widget>[
                        Expanded(child: _bodyFor(_tab)),
                        tabBar,
                      ],
                    )
                  // iOS：内容铺满整屏、底栏浮在它上面；**可以左右拖着换 tab**
                  // （用户 2026-10-06 要的"丝滑 + 左右拖动的感觉"）。
                  // 拖动时每帧把小数页号喂给底栏那颗玻璃 → 它跟着手指滑；
                  // 松手后 `onPageChanged` 落到整页，玻璃再交回"整格"轨道（原生 setIndex）。
                  : Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: PageView(
                            controller: _pages,
                            onPageChanged: (int i) {
                              if (i != _tab) setState(() => _tab = i);
                              _glassDrag.value = -1;
                            },
                            children: <Widget>[
                              for (int i = 0; i < AppTabBar.tabs.length; i++)
                                _bodyFor(i),
                            ],
                          ),
                        ),
                        Positioned(
                          left: AppTabBar.floatMargin,
                          right: AppTabBar.floatMargin,
                          bottom: AppTabBar.floatMargin,
                          child: tabBar,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶栏标题：就是当前 tab 的名字；**「训练」那一屏写"今天"**
  /// （那一屏回答的是"今天练什么"，tab 名字叫训练，进了门就是今天）。
  String get _topBarTitle => switch (_tab) {
        0 => '进步',
        1 => '数据',
        2 => '今天',
        3 => '计划',
        _ => '我的',
      };

  /// 顶栏副标题：只有「今天」那一屏给日期（原来它挤在首页标题旁边，
  /// 与 34pt 大字、40×40 铃铛三种高度混在一行 —— 那正是用户说的"布局不协调"）。
  String? get _topBarSubtitle {
    if (_tab != 2) return null;
    const List<String> weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
    final DateTime now = DateTime.now();
    return '${now.month} 月 ${now.day} 日 · 周${weekdays[now.weekday - 1]}';
  }

  /// 齿轮 → 「设置」那一屏（三组设置从「我」页搬过去了）。
  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsHomeScreen(
        store: _store,
        repository: _repo,
        profile: _profile,
        analytics: _analytics,
        bodyMetrics: _bodyMetrics,
        unit: _unit,
        bodyUnit: _bodyUnit,
        onUnitChanged: (WeightUnit u) => setState(() => _unit = u),
        onBodyUnitChanged: (BodyWeightUnit u) => setState(() => _bodyUnit = u),
        defaultStepKg: _defaultStepKg,
        onStepChanged: (double kg) => setState(() => _defaultStepKg = kg),
        restOverrideSec: _restOverrideSec,
        onRestOverrideChanged: (int? sec) => setState(() => _restOverrideSec = sec),
        loadEvents: _outbox.peekAll,
        onDataChanged: () => unawaited(_refreshHome()),
        cloudBackupAvailable: null,
        cloud: null,
        // 会话交给这一屏按需读（`ProfileRepository.authSessionStore()`），
        // 与「我」页同一个来源 —— 不在这里多存一份状态
        sets: _allSets,
        reminder: _reminder,
        reminderHint: _reminderHint,
        onReminderChanged: _setReminder,
      ),
    ));
    if (mounted) await _refreshHome();
  }

  /// 按 **tab 下标** 取那一屏。⚠️ 2026-10-07（v1.60.0）起顺序是
  /// `进步 / 数据 / 训练 / 计划 / 我的`（「训练」在正中，用户 10.7 清单第 2 条），
  /// 所以这里的映射与 `AppTabBar.tabs` **必须逐条对齐** —— 两处错位就是"点训练进了数据"。
  Widget _bodyFor(int tab) {
    switch (tab) {      case 0:
        return ProgressScreen(
            store: _store,
            repository: _repo,
            bodyMetrics: _bodyMetrics,
            profile: _profile,
            analytics: _analytics,
            unit: _unit,
            bodyUnit: _bodyUnit,
            // 身体数据页里切了体重单位 → 整棵树按新单位重建
            onBodyUnitChanged: (BodyWeightUnit u) {
              setState(() => _bodyUnit = u);
            },
          );      case 1:
        // 「数据」= 原来的「全部数据」二级页（v1.45.0 起提到一级）。
        // VI 里这一页还要重做（四张统计卡 + 容量趋势面积图），那属于 v1.46.0 的组件层。
        return AllDataScreen(
          store: _store,
          repository: _repo,
          unit: _unit,
          // 一级 tab 角色：外壳顶栏已经写着「数据」，这一页**不要再画自己的标题与返回箭头**
          // （用户 10.9 清单第 3 条：截图里「数据」下面又出现一行「‹ 全部数据」）。
          asTab: true,
        );      case 2:
        return TodayScreen(
            // 大按钮一跳直开练；想先看看的人走下面那个入口
            onStart: _startNow,
            onSeePlan: _openSuggestion,
            lastWeekSessions: _weekSessions,
            // 还没定过计划才显示入口
            onPlanHelp: _goalWire == null ? _openFirstPlan : null,
            // 「今天不想练」的轻量出口：4 个按时长的活动，1 组就走完
            onLightWorkout: _startLight,
            // 上次没练完 → 先把这条摆在最上面（"接着练"是此刻唯一该做的事）
            onResume: _activeSession == null ? null : _resumeSession,
            resumeLabel: _activeSession == null
                ? null
                : '上次练到第 ${(_activeSession!.index + 1).clamp(1, _activeSession!.length)}'
                    '/${_activeSession!.length} 个动作',
            // 首页中间那一块：今天的安排（2026-10-04 替掉原来那个 Spacer）
            todayPlan: _todayPlan,
            todayLabel: _todayDay?.label,
            onReroll: _todayPlan.isEmpty ? null : _rerollTodayPlan,
            // 新 VI 的首页三块（2026-10-05）：打卡 / 快速入口 / 最近训练
            streak: _streak,
            streakCopy: streakCopy(_streak),
            recent: _recent,
            // 同一个屏幕上**只能有一种单位**：上面「今天的安排」用 `_unit`，
            // 「最近训练」那三行也必须用它（10.8 清单第 7 条：单位不一致）
            unit: _unit,
            onOpenLibrary: _openLibrary,
            onLogWeight: _openBodyMetric,
            onOpenAchievements: _openAchievements,
            // 铃铛与未读点**搬去外壳顶栏**了（v1.60.0）：通知中心是全局的，
            // 不该只在首页点得到。`_openNotifications` 现在挂在顶栏上。
            // 周报（第二部分第 1 条）：**只在周一 / 周二 + 上周练过**才给看。
            // 判据是纯函数（`shouldShowWeeklyReport`），所以"周三不给看"这件事有测试钉着。
            weeklyReport: shouldShowWeeklyReport(_allSets, DateTime.now())
                ? weeklyReportFor(_allSets, DateTime.now())
                : null,
            onOpenWeeklyReport: _openWeeklyReport,
            muscleBalance: _muscleBalance,
            comebackNudge: _comebackNudge,
            protectedInStreak: _protectedInStreak,
            protectionOffer: _protectionOffer,
            // 首页那一行本周挑战（A3 的第二处落点）：与成就页共用同一份纯函数，
            // "什么时候不显示"也写在那里面（做完了 / 只剩今天都不显示）。
            weeklyChallengeLine:
                weeklyChallengeLine(weeklyChallenge(_allSets, DateTime.now())),
            onProtectStreak:
                _protectionOffer == null ? null : _protectStreak,
          );      case 3:
        // 「计划」= 原来的计划模板列表（v1.45.0 起提到一级）。
        // VI 里它还要加周历与历史两个视图，同样属于 v1.46.0。
        // 2026-10-05（v1.51）：这一栏从"只有模板列表"变成**三个视图**
        // （本周 / 模板库 / 历史）—— 模板库那一栏嵌的就是原来这一屏。
        return PlanScreen(
          repository: _routines,
          exercises: _repo,
          store: _store,
          unit: _unit,
          todayPlan: _todayPlan,
          todayLabel: _todayDay?.label,
          onResume: _activeSession == null ? null : _resumeSession,
        );      default:
        return ProfileScreen(
          store: _store,
          repository: _repo,
          profile: _profile,
          analytics: _analytics,
          // 连续打卡保护（第二部分第 2 条）：**必须与首页同一份** ——
          // 两边各算一遍就会出现"首页说连续 12 天、这里说 0 天"的矛盾。
          protectedDays: _protectedDays,
          // 「隐私与关于 → 导出统计事件」用：本机攒下的事件（含发不出去的那些）。
          // 这是**唯一**能把 tap_count 从设备上取回来的路径 —— 见
          // `analytics_export.dart` 的文件头与 `docs/analytics.md` §3。
          loadEvents: _outbox.peekAll,
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
          reminder: _reminder,
          reminderHint: _reminderHint,
          onReminderChanged: _setReminder,
          // 删光 / 导入之后，首页那行"我上周练了 N 次"要跟着变
          onDataChanged: () => unawaited(_refreshHome()),
        );
    }
  }
}

