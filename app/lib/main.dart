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
import 'core/labels.dart';
import 'core/theme.dart';
import 'core/units.dart';
// db.dart（drift 表）与 models.dart（领域模型）都定义了 Workout / SetRecord，
// 同时裸 import 两个库时，一用到同名类就 ambiguity_import。这里预先 hide 掉。
import 'data/analytics_meta_repository.dart';
import 'data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import 'data/body_metric_repository.dart';
import 'data/drift_local_store.dart';
import 'data/exercise_repository.dart';
import 'data/local_store.dart';
import 'data/profile_repository.dart';
import 'data/reminder_repository.dart';
import 'data/routine_repository.dart';
import 'data/sync_queue.dart';
import 'domain/models.dart';
import 'domain/tap_meter.dart';
import 'features/exercise/exercise_picker_screen.dart';
import 'features/today/today_planner.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/onboarding/privacy_consent_screen.dart';
import 'features/today/today_screen.dart';
import 'features/today/today_suggestion_screen.dart';
import 'features/summary/workout_summary.dart';
import 'features/profile/profile_screen.dart';
import 'features/progress/progress_data.dart';
import 'features/progress/progress_screen.dart';
import 'features/profile/reminder.dart';
import 'features/profile/reminder_bridge.dart';
import 'features/profile/reminder_service.dart';
import 'features/summary/workout_summary_screen.dart';
import 'features/workout/rest_activity.dart';
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
  );
  ReminderSettings _reminder = ReminderSettings.off;

  /// 「下次提醒：…」那一行。**它是这一版真机反馈的直接产物**：
  /// 用户设了 17:58、当时就是 17:58，而规则把它顺延到明天 ——
  /// 界面上没有任何反馈，于是看起来就是"设了闹钟不响"。
  String? _reminderHint;
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

  /// 有没有同意过隐私政策。**null = 还没从库里读出来**（读出来之前什么都不做）。
  ///
  /// 这一屏是法律要求：国内商店要求"首次运行时以弹窗等明显方式提示用户阅读隐私政策
  /// 并征得同意"，且**同意之前不得收集任何个人信息**。所以它不只是 UI ——
  /// `_initAnalytics()` 也被挪到同意之后（见下面 initState 的注释）。
  bool? _consented;

  /// 用户**明确拒绝过**（拒绝后不弹第二次；且**永远不启动埋点**）。
  bool _declined = false;

  /// 显示单位。启动时从 user_profile 读一次，用户在 S10 改了之后整棵树重建。
  /// **只影响显示**：存储、引擎、埋点始终是 kg（见 core/units.dart）。
  WeightUnit _unit = WeightUnit.kg;

  /// 体重的显示单位（千克 / 斤）。**与训练重量分开** —— 见 units.dart 的说明。
  BodyWeightUnit _bodyUnit = BodyWeightUnit.kg;

  /// 休息时长偏好。**null = 跟随动作自带的值**，这是默认。
  int? _restOverrideSec;

  /// 冷启动时刻，用来给事件算 `ms_since_launch`（"从打开到记下第一组用了多久"）。
  final int _launchedAtMs = DateTime.now().millisecondsSinceEpoch;

  int _clock() => DateTime.now().millisecondsSinceEpoch;

  /// 训练目标。**null = 还没走过 S13 的引导** —— S1 据此决定要不要显示入口。
  String? _goalWire;

  /// 最近 7 天练了几次 —— 空态那行字要用。
  /// 之前这个值从没被算过，所以练完回来空态还写着「还没有训练记录」。
  int _weekSessions = 0;

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
    });
    // 刻意**不**调用 `_initAnalytics()` —— 拒绝之后一条事件都不该产生
  }

  Future<void> _onPrivacyAgreed() async {
    await _profile.setPrivacyConsent();
    if (!mounted) return;
    setState(() => _consented = true);
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
    final String? goal = await _profile.goalWire();
    // 训练提醒的设置也在这里读一次（设置页要显示它）。
    // 注意**不在这里请求权限** —— 那是用户主动打开开关时才做的事。
    final ReminderSettings reminder = await _reminderRepo.load();
    if (!mounted) return;
    setState(() {
      _unit = u;
      _bodyUnit = b;
      _restOverrideSec = rest;
      _goalWire = goal;
      _reminder = reminder;
      _reminderHint = _hintFor(const <SetRecord>[]);
    });
  }

  Future<void> _initAnalytics() async {
    // ⚠️ **先问用户的选择，再做任何记录**（2026-09-30，审计 A 的后半段）。
    // 库里那一列的默认值改成"关"了，但这个对象在内存里的默认值未必跟着变 ——
    // 而"开关显示关着、实际上还在收集"是所有失败方式里最坏的一种。
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
    setState(() {
      _weekSessions = weekWorkoutCount(sets, DateTime.now());
      _reminderHint = _hintFor(sets);
    });
    await _loadTodayPlan();
    // 训练提醒也在这里同步：这个函数是"开 App / 练完回来"的公共出口，
    // 而提醒的正确状态正好取决于**刚刚是不是练过了**（练过就顺延到明天）。
    await _syncReminder();
  }

  /// 「下次提醒：…」。传 sets 是为了知道**今天练过没有** ——
  /// 练过就会顺延到明天，而那正是用户最需要被告知的一件事。
  String? _hintFor(List<SetRecord> sets) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    return reminderHint(
      settings: _reminder,
      trainedToday: hasTrainedOn(
        sets: sets,
        day: DateTime.fromMillisecondsSinceEpoch(now),
      ),
      nowMs: now,
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
    // setState 是同步闭包，取数据必须在它外面（await 不能写在里面）
    final List<SetRecord> sets = await _store.allSets();
    if (mounted) {
      setState(() {
        _reminder = next;
        _reminderHint = _hintFor(sets);
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
          await _planner.planToday(day: day, unit: _unit);
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

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutScreen(
          session: session,
          // 完整动作库行：控制器只有瘦身过的 ExerciseSpec，而详情页要说明/部位/器械
          catalog: <ExerciseData>[
            for (final SessionEntry e in entries) e.exercise,
          ],
          store: _store,
        ),
      ),
    );

    session.removeListener(onSessionChanged);
    // 训练结束了（正常结束或用户自己退出）—— 未结束的会话到此为止。
    // 不清的话，下次冷启动会把用户送回一个早就结束的训练。
    await _store.clearActiveSession();

    session.dispose();
    for (final WorkoutController c in controllers) {
      c.dispose();
    }
    _flusher.resume();
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
      plan = await _planner.planToday(day: _todayDay, unit: _unit);
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
          );
      case 1:
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
          );
      default:
        return ProfileScreen(
          store: _store,
          repository: _repo,
          profile: _profile,
          analytics: _analytics,
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

