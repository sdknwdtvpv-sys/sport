/// 练了么 · 训练会话状态机
///
/// 对应 `docs/interaction-spec.md` §6 的状态机与 §7 的手势规范。
///
/// 两条容易做错、且都有测试守着的规则：
///   1. **训练中不重算建议。** 建议是"本次训练的处方"，在训练开始时算一次就固定；
///      如果每组后重算，会立刻变成「上次只完成 1 组，先把组数补满」这种荒谬提示。
///      重算只发生在下一次训练开始时。
///   2. **组数达标后不禁用按钮。** 计划是建议不是牢笼，禁止加组会让用户退回备忘录。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../analytics/analytics.dart';
import '../../data/local_store.dart';
import '../../data/sync_queue.dart';
import '../../core/last_time.dart';
import '../../core/units.dart';
import 'haptics.dart';
import 'rest_activity.dart';
import 'rest_cue.dart';
import '../../domain/models.dart';
import '../../domain/progression.dart';
import '../../domain/tap_meter.dart';

/// 单动作训练时的默认 id。多动作场景由调用方传入同一个 id。
const String kLocalWorkoutId = 'w_local_1';

class WorkoutController extends ChangeNotifier {
  WorkoutController({
    required this.exercise,
    required this.plan,
    required this.analytics,
    required this.store,
    required this.syncQueue,
    this.restActivity = const NoopRestActivity(),
    /// 触觉反馈（记一组 / 休息结束）。默认无操作 —— 只有生产那条路接真的那个。
    this.haptics = const NoopHaptics(),
    /// 休息结束的**体外提示**（Android 本地通知）。iOS 侧实现成空操作
    /// （那边有 Live Activity），所以默认 noop 不会让任何平台少东西。
    this.restCue = const NoopRestCue(),
    /// 同一次训练里的多个动作**共享同一个 workoutId**，
    /// 这样记录会挂在一条 workout 下，而不是被拆成多次训练。
    String workoutId = kLocalWorkoutId,
    LastSession? lastSession,
    List<ManualOverride> overrides = const <ManualOverride>[],
    UserProfile profile = const UserProfile(),
    /// 恢复训练时的"休息到什么时候"（绝对毫秒时间戳，2026-10-01）。
    /// 传了就按"现在还剩多少"接着倒数 —— **被杀掉的那几分钟也该算进休息**，
    /// 而不是回来重新从 90 秒开始。
    int? restEndsAtMs,
    /// 恢复训练时：**这个动作在这次训练里已经记过的组**（2026-10-04）。
    ///
    /// 为什么必须传（这是一条真机上抓到的 P0，静默丢数据）：
    /// 恢复时控制器是**新建**的，`_setSeq` 从 0 开始 —— 于是界面显示「第 1 组」、
    /// 已完成列表是空的；用户再记一组就会按 `s_<workoutId>_<exerciseId>_1` 写库，
    /// **把杀进程前那一组覆盖掉**（总数不变，所以从界面上看不出来）。
    ///
    /// 为什么不把"已经记到第几组"存进 `ActiveSession` 的 JSON：
    /// 组本来就逐条落库了，**数据库才是真源** —— 存一个计数器等于把同一件事
    /// 写两遍，迟早会漂。调用方拿 `store.setsFor(workoutId)` 过滤一下传进来即可。
    List<SetRecord> alreadyLogged = const <SetRecord>[],
    /// 恢复时沿用**原来那次训练的开始时刻**。不传的话这次训练的行会被改成
    /// "恢复的那一刻"（`saveWorkout` 每次记组都会写一遍），总结页的时长就只剩后半段。
    int? startedAtMs,
    int Function()? clock,
  })  : _lastSession = lastSession,
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    workout = Workout(id: workoutId, startedAtMs: startedAtMs ?? _clock());
    // 把已记的组读回来：**界面、组序、计划进度三处一起对上**，缺一处就会重演那个 P0。
    if (alreadyLogged.isNotEmpty) {
      workout.sets.addAll(alreadyLogged);
      _setSeq = alreadyLogged
          .map((SetRecord s) => s.setIndex)
          .reduce((int a, int b) => a > b ? a : b);
      _normalSets =
          alreadyLogged.where((SetRecord s) => s.setType == SetType.normal).length;
    }
    _suggestion = suggestNext(
      exercise: exercise,
      plan: plan,
      lastSession: lastSession,
      profile: profile,
      overrides: overrides,
    );
    _weightKg = _suggestion?.weightKg ?? 0;
    _reps = _suggestion?.reps ?? plan.targetRepsLow;
    // 有氧的默认值来自上一次训练（没有建议可依）。lastSession 可能是上一轮的
    // 老数据（distances 为 null）—— 那时保持 0，让用户自己设。
    //
    // 取**最远的一组**而不是最后一组：热身/放松那两组距离短，
    // 拿它们当默认值会把"今天还跑 5 公里"变成"今天跑 1 公里"。
    // 默认距离：**先看上次**（"今天还跑那么多"），没历史就用**距离处方**（种子给的每组米数）。
    // 处方之前，首次练距离动作只能从 0 开始、逼着用户自己设 —— 现在它有起点。
    _distanceM = lastSession?.maxDistanceM ?? plan.targetDistanceM ?? 0;
    if (exercise.isDistance) {
      // 时长同样来自上次。**不能用 plan.targetRepsLow（8）** ——
      // 那是"8 次"的处方，落到有氧上就成了"8 秒"，一条 5 公里跑记成 8 秒。
      // 这个 bug 是 cardio_test 里"reps 是秒"那条断言抓出来的。
      final List<int>? lastReps = lastSession?.reps;
      _reps = (lastReps == null || lastReps.isEmpty) ? 0 : lastReps.last;
    }
    // 只影响界面怎么念数字；引擎与存储始终是 kg（见 core/units.dart）
    unit = profile.unit;
    // 用户设了就用他的；没设就跟随动作自带的值（种子差异很大：核心 45s、深蹲 180s）
    plannedRestSec = profile.restOverrideSec ?? exercise.defaultRestSec;
    // 从一次被中断的训练回来：把休息接着数完（不做"重新开始"那件更糟的事）
    if (restEndsAtMs != null && restEndsAtMs > _clock()) {
      _beginRest(((restEndsAtMs - _clock()) / 1000).ceil(),
          endsAtMs: restEndsAtMs, announce: false, totalSec: plannedRestSec);
    }
    // **ensure 而不是 begin**：端到端口径要求把"用户点开始训练 → 选动作"
    // 这些点击算进第一组，而它们发生在控制器被构造之前。
    // 用 begin 会在这里清零，第一组又变回"只算大按钮那一下"。
    analytics.ensureSetInteraction();
  }

  final ExerciseSpec exercise;
  final PlanTarget plan;
  final Analytics analytics;
  final LocalStore store;
  final SyncQueue syncQueue;

  /// 组间休息的 Live Activity（iOS 锁屏/灵动岛）。**生产环境必须传真的那个**
  /// （见 `main.dart`）—— 默认是 noop，因为另外 20 多个构造点都在测试里。
  final RestActivityBridge restActivity;

  /// 触觉反馈。与 [restActivity] 一样**失败是静默的**：震动没响不该影响记录训练。
  final Haptics haptics;

  /// 休息结束的体外提示（Android 通知）。同样静默失败。
  final RestCue restCue;
  final int Function() _clock;

  /// 显示单位。存储与引擎始终是 kg，这个字段只用于格式化。
  late final WeightUnit unit;

  /// 本次训练实际使用的休息时长（秒）。**算一次就固定** ——
  /// 用户在训练中途去改设置也不该让倒计时突然变长变短。
  late final int plannedRestSec;

  late final Workout workout;

  /// 上一次这个动作练成什么样。**留着给界面念那一行**（v1.53）——
  /// 构造时它只是引擎的输入，用完就丢的话训练屏就没法告诉用户"上次练了多少"。
  final LastSession? _lastSession;

  /// 「上次 3 组 · 45 kg × 10 次」这一行（没有历史就是 null，界面不出现这一行）。
  String? get lastTimeLabelText =>
      lastTimeLabel(_lastSession, unit: unit, trackType: exercise.trackType);

  /// 上一次这个动作的原始数据。**2026-10-10 从私有改成公开** ——
  /// 训练屏那条「上次 / 历史最佳」对照带要把它拆成**两行**念
  /// （大字 `45 kg × 10`、小字 `3 组 · 7 天前`），一句话那版塞不进那块版面。
  LastSession? get lastSession => _lastSession;
  Suggestion? _suggestion;

  /// 建议的稳定标识：**采纳率要靠它把"展示"与"采纳/手改"串成一条链**。
  ///
  /// 一次训练里同一个动作只算一条建议（引擎在同一次训练内不会改口：
  /// 加重/减重都发生在**下次**训练，见 `progression.dart`），
  /// 所以 `workoutId + exerciseId` 足以唯一标识。
  String? get suggestionId => _suggestion == null
      ? null
      : 'sg_${workout.id}_${exercise.id}';

  /// 打开步进弹层时的原值 —— 用来判断用户**到底改没改**（`set_edited`）。
  double? _sheetFromWeight;
  int? _sheetFromReps;

  double _weightKg = 0;
  int _reps = 0;

  /// 下一组要记的**距离（米）**。只对 `distance_time` 动作有意义（跑步机/划船机/跳绳/农夫行走）。
  ///
  /// 默认取**上次的距离** —— 有氧没有推进建议（引擎对 distance_time 返回 null），
  /// 所以"上次跑多少"就是最好的默认值：今天还跑那么多，一次点击落一组。
  /// 没有历史时是 0，这时大按钮**不可点**（见 canLog），提示用户长按设距离 ——
  /// 理由与这一整轮的主题一致：**宁可不记，也不写一条 0 公里的假记录**。
  double _distanceM = 0;

  /// **正式组**数。计划进度与「第 N 组」都由它算。
  int _normalSets = 0;

  /// **这一场里，同一个动作逐组之间实际歇了多久**（秒，2026-10-08，10.8 清单第 2 条）。
  ///
  /// 用户原话："根据过往训练中的休息时长动态调整后面同一个动作的休息时间"。
  /// 现在收的是**本场**的数据（跨场的数据没地方存 —— 库里从来没记过"实际休息"，
  /// 只有埋点里那两个事件名）。第一条组没有"上一次"，所以它不参与。
  final List<int> _observedRestsSec = <int>[];

  /// 上一组**写下**的时刻（毫秒）。相邻两组的差就是"实际休息"。
  int? _lastLoggedAtMs;

  /// **全部组**数（含热身）。只用来生成不重复的 `setIndex` 与记录 id。
  ///
  /// 必须和 `_normalSets` 分开：热身组要占一个组序（否则两条热身会撞 id，
  /// 后一条把前一条覆盖 —— 这个坑在 id 用局部计数器时踩过一次），
  /// 但它不能计入计划进度（否则两组热身就把"共 3 组"顶掉了）。
  int _setSeq = 0;

  /// 下一组是否记为热身组。
  ///
  /// **默认关闭，且做成"粘住"的** —— 规格要求它"弱化样式、渐进式暴露、不主动教"，
  /// 所以不能每次记完就自动弹回（连做两组热身时那样很烦）。
  /// 代价是用户可能忘了它开着，因此 S4 上必须有**可见标记**。
  bool _warmup = false;

  /// 下一组要记的 RPE（自觉用力程度）。**null = 不记**，这是默认值。
  ///
  /// 和热身一样做成"粘住"的：练的人往往连续几组 RPE 相同，每组都要重设很烦。
  /// 但不参与任何引擎判定（进度、渐进建议、破纪录都不看它），
  /// 且会在**已完成组列表**里显示出来 —— 否则就成了用户看不见的隐藏数据。
  double? _rpe;
  int _restRemaining = 0;
  bool _restRunning = false;

  /// 休息结束的**绝对**时间戳。存绝对值而不是"剩余秒数"，
  /// 是为了让"App 被杀掉 5 分钟"在这件事上等于"休息已经过去 5 分钟"。
  int? _restEndsAtMs;
  bool _sheetOpen = false;
  bool _disposed = false;
  String? _hint;
  Timer? _restTimer;

  /// 计时动作的**做组计时器**（v1.53）：开始时刻（绝对毫秒）+ 每跳一次的刷新计时器。
  ///
  /// 为什么用绝对时刻而不是"每秒加一"：与组间休息同一条理由 ——
  /// App 被系统挂起时 Dart 定时器不走，靠累加会把被挂起的那段白送掉。
  int? _holdStartedAtMs;
  bool _holdAnnounced = false;
  Timer? _holdTimer;

  Suggestion? get suggestion => _suggestion;
  double get weightKg => _weightKg;
  int get reps => _reps;
  double get distanceM => _distanceM;

  /// 这个动作记不记距离。
  bool get isDistance => exercise.isDistance;

  /// "重量"是不是**助力**（辅助引体/双杠）。
  bool get isAssisted => exercise.isAssisted;

  /// 距离处方（每组多少米）。null = 这个动作不吃距离处方。
  double? get targetDistanceM => plan.targetDistanceM;

  /// 大按钮能不能点。
  ///
  /// 对距离动作：**距离或时长有一个是 0 就不给点** —— 一次误触会写进
  /// "0 公里 / 0 秒"或"5 公里 / 0 秒"这样的半截记录，那是这一整轮在防的那种假数据
  /// （有氧不给建议、不按次数推、老库不加 0 距离，同一个道理）。
  /// 代价是首次记有氧要设两个值 —— 两个值各一次步进，而假记录会跟着用户一辈子。
  /// 其余动作恒为 true：力量动作的默认值来自引擎建议，点一下就是一组。
  bool get canLog => !isDistance || (_distanceM > 0 && _reps > 0);
  /// **下一组该歇多久**（2026-10-08，10.8 清单第 2 条）。
  ///
  /// 本场已经歇过 **≥ 2 次**时，取**实际休息的中位数**（5 秒取整），
  /// 并夹在动作自带值的 **0.5× ～ 2×** 之间 —— 上下界是为了不让某一次
  /// "接了个电话"把后面全带跑。看上去这一条会改设置，其实**不会**：
  /// 它只影响**这一场**接下来的默认值（动作自带值与用户覆盖值一个字节都不动）。
  int get nextRestSec {
    if (_observedRestsSec.length < 2) return plannedRestSec;
    final List<int> sorted = <int>[..._observedRestsSec]..sort();
    final int median = sorted[sorted.length ~/ 2];
    final int rounded = (median / 5).round() * 5;
    final int lo = (plannedRestSec * 0.5).round().clamp(5, 3600);
    final int hi = (plannedRestSec * 2).clamp(lo, 3600);
    return rounded.clamp(lo, hi);
  }

  /// 这一次休息是不是**跟着你的节奏**来的 —— 界面据此说一句实话（"按你的节奏"）。
  bool get restIsAdaptive =>
      _observedRestsSec.length >= 2 && nextRestSec != plannedRestSec;

  /// 本场实际休息的采样次数（测试与埋点诊断用；界面不显示这个数）。
  int get observedRestCount => _observedRestsSec.length;

  int get restRemainingSec => _restRemaining;

  /// **这一轮休息开始时有多长**（秒）。训练屏那条细进度按它算比例；
  /// 0 = 这次训练还没休息过。⚠️ 从中断处恢复时传的是 `plannedRestSec`
  /// （那时已经不知道原来那一轮的总长），界面把比例 clamp 到 0..1。
  int _restTotalSec = 0;
  int get restTotalSec => _restTotalSec;
  bool get restRunning => _restRunning;

  /// 正在休息时给出"休息到几点"（绝对毫秒）—— 会话恢复要用它。
  /// 不在休息中就是 null（下一个版本要拿这个值去写"未结束的会话"）。
  int? get restEndsAtMs => _restRunning ? _restEndsAtMs : null;
  bool get restDone => !_restRunning && _restRemaining == 0 && _normalSets > 0;
  bool get sheetOpen => _sheetOpen;
  bool get isOffline => syncQueue.offline;
  bool get isBodyweight => exercise.isBodyweight;
  /// 已经记下的**正式组**数（热身不算）。界面用它判"做满计划组数没有"
  /// （10.8 清单第 3 条：做满之后底部换成「再加一组 / 下一个动作」两个按钮）。
  int get normalSets => _normalSets;

  int get setNumber => _normalSets + 1;
  int get plannedSets => plan.targetSets;
  String? get hint => _hint;
  List<SetRecord> get loggedSets => List<SetRecord>.unmodifiable(workout.sets);

  /// 下一组是不是热身组。UI **必须**据此给出可见提示 ——
  /// 状态是"粘住"的，用户看不到就会把正式组白白记成热身。
  bool get warmup => _warmup;

  /// 已记录的热身组数（计划进度不含它）。
  int get warmupSets =>
      workout.sets.where((SetRecord s) => s.setType == SetType.warmup).length;

  /// 下一组要记的 RPE；null = 不记（默认）。
  double? get rpe => _rpe;

  /// 「次数」这一行对按时长/距离动作来说其实是**秒**。
  String get repsUnit => exercise.isTime ? '秒' : '次';

  /// 次数（或秒数）的步长。
  ///
  /// * 次数动作：±1 次
  /// * 时长动作（平板支撑）：±5 秒 —— ±1 秒没有意义
  /// * **距离动作（有氧）：±60 秒（1 分钟）** —— 跑步 30 分钟要点 1800 次 ±1 秒，
  ///   那不叫步进
  int get repsStep {
    if (isDistance) return 60;
    return exercise.isTime ? kTimeStepSec : 1;
  }

  /// 重量步进幅度：**用动作自己的步长**，不再写死 ±2.5。
  /// 种子里的步长有 2 / 5 / 2.5 / 0 四种（哑铃 2、器械 5…），写死会让用户改不动重量。
  ///
  /// 2026-10-09（10.9 清单第 8a 条「加重量的选项能否自定义」）：用户还能**当场改**它 ——
  /// 改了之后先落在这个覆盖值上（这一趟训练立刻按新步进加减），由界面负责写库
  /// （[setWeightStep] 只管内存，它不认识仓库 —— 与这个类一贯的边界一致）。
  double get weightStep => _weightStepOverride ??
      (exercise.weightIncrement > 0 ? exercise.weightIncrement : 2.5);

  double? _weightStepOverride;

  /// 用户在训练屏里把步进改成了 [kg]（kg，> 0）。界面同时负责持久化到那个动作上。
  void setWeightStep(double kg) {
    if (kg <= 0 || kg == _weightStepOverride) return;
    _weightStepOverride = kg;
    notifyListeners();
  }

  /// 距离步进幅度：100 米。跑步机上最小刻度就是 0.1 km，
  /// 而再细（10 米）在长距离上要点太多次。
  double get distanceStepM => 100;

  /// 大按钮上显示的文案 —— 就是即将写入的值。
  /// 这是全产品唯一不可妥协的指标：点击即写入，1 次点击 = 1 组。
  String get primaryButtonLabel {
    // 计时中：大按钮上就是那个在走的数字 —— 用户抬眼要能读到"我撑了多久"。
    // 记下来的值就是它（见 onBigButtonTap）。
    if (holding) {
      final int sec = holdElapsedSec;
      final String mm = (sec ~/ 60).toString();
      final String ss = (sec % 60).toString().padLeft(2, '0');
      return '$mm:$ss';
    }
    // 距离动作：念「5.00 公里 · 30:00」——重量与次数都说不通（跑步机没有重量，
    // "1800 次"更是胡说）。距离 + 时长才是这个动作实际做了什么。
    if (isDistance) {
      return '${formatDistanceKm(_distanceM)} · ${formatDurationHms(_reps)}';
    }
    // 辅助自重：那个数字是**助力**。只说「30 kg × 8」会被读成"举起了 30 kg"，
    // 而它恰恰相反 —— 助力越大越轻松。引擎的方向已经反过来（达标 → 减助力），
    // 界面上也必须说清楚这个数是什么。
    final w = isAssisted
        ? '助力 ${formatWeight(_weightKg, unit)}'
        : isBodyweight
            ? '自重'
            : formatWeight(_weightKg, unit);
    return exercise.isTime ? '$w × $_reps 秒' : '$w × $_reps';
  }

  // ---------- 手势入口（UI 只调用这四个） ----------

  /// 点按大按钮：记一组。
  ///
  /// 计时中（计时动作）时这一下同时**收下计时的结果**：把已计秒数当成这一组的次数，
  /// 然后走完全一样的记组路径 —— 所以"一次点击 = 一组"这条不变。
  void onBigButtonTap() {
    analytics.countTap(TapKind.bigButton);
    if (holding) {
      final int elapsed = holdElapsedSec;
      _holdTimer?.cancel();
      _holdTimer = null;
      _holdStartedAtMs = null;
      _holdAnnounced = false;
      // 最少 1 秒：一条"0 秒"的记录是假数据（与距离动作"0 公里不记"同一条纪律）
      _reps = elapsed < 1 ? 1 : elapsed;
    }
    _logSet();
  }

  /// 长按大按钮 500ms：打开修改弹层。**不记录任何一组。**
  void onLongPress() {
    analytics.countTap(TapKind.longPress);
    // 计时中被长按 = 我按错了，先收起计时器（否则弹层关掉之后它还在悄悄倒数）
    if (holding) cancelHold();
    // 记下打开弹层前的值：只有真的改了才算一次"编辑"（见 onSheetConfirm）
    _sheetFromWeight = _weightKg;
    _sheetFromReps = _reps;
    _sheetOpen = true;
    // 文案审计（2026-10-04）：这里原本会弹一句「步进调整，不需要键盘」——
    // 那是**解释我们的交互设计**，而步进按钮就摆在弹层里，用户一眼就懂了。删。
    _hint = null;
    _notify();
  }

  /// 弹层里每按一次步进按钮。
  void onStepper({double deltaWeight = 0, int deltaReps = 0, double deltaDistanceM = 0}) {
    analytics.countTap(TapKind.stepper);
    if (deltaWeight != 0) {
      final next = _weightKg + deltaWeight;
      _weightKg = next < 0 ? 0 : (next * 10).round() / 10;
    }
    if (deltaDistanceM != 0) {
      final next = _distanceM + deltaDistanceM;
      // 下限为 0，**不是**一个步进：距离可以是 0（还没跑），
      // 而次数不能掉到 0（"0 次"没有意义）。这是两种输入的区别。
      _distanceM = next < 0 ? 0 : (next * 10).round() / 10;
    }
    if (deltaReps != 0) {
      final next = _reps + deltaReps;
      // 下限就是一次步进：次数不会掉到 0，秒数也不会掉到 5 秒以下
      _reps = next < repsStep ? repsStep : next;
    }
    _notify();
  }

  /// 弹层「确定」：关闭弹层，把修改应用到后续的组。
  void onSheetConfirm() {
    analytics.countTap(TapKind.sheetConfirm);
    _sheetOpen = false;
    _hint = null;

    // `set_edited`：**只记真的改了的那一项**。
    // "打开弹层又原样关掉"不是编辑 —— 把它算进去会让"编辑成本"这个指标虚高，
    // 而那个指标正是用来判断"建议是不是不该被改"的。
    final double? fromW = _sheetFromWeight;
    final int? fromR = _sheetFromReps;
    if (fromW != null && fromW != _weightKg) {
      analytics.track('set_edited', <String, Object?>{
        'field': 'weight',
        'from': fromW,
        'to': _weightKg,
        'suggestion_id': suggestionId,
      });
    }
    if (fromR != null && fromR != _reps) {
      analytics.track('set_edited', <String, Object?>{
        'field': 'reps',
        'from': fromR,
        'to': _reps,
        'suggestion_id': suggestionId,
      });
    }
    _sheetFromWeight = null;
    _sheetFromReps = null;
    _notify();
  }

  /// 切换「下一组记为热身」。热身组不计入计划进度，也不进引擎的渐进判定
  /// （`lastSessionFor` / `recentExerciseIds` / `allSets` 都排除它，有契约测试守着）。
  void toggleWarmup() {
    _warmup = !_warmup;
    _hint = _warmup ? '下一组记为热身，不计入计划组数' : null;
    _notify();
  }

  /// 设置 RPE。传 null 表示不记（再点一次已选中的值即清除）。
  ///
  /// 规格要求它"弱化样式存在、不主动教"，所以这里既不校验范围也不拦截 ——
  /// 界面只给 6–10 这几个常用档，传进来的值原样记录。
  void setRpe(double? value) {
    _rpe = value;
    _notify();
  }

  /// 撤销误触记下的那一组（长按"已完成"里的任意一行）。
  ///
  /// 这是规格里"误触多记一组"的后悔药（`docs/interaction-spec.md` §7、`PRODUCT.md` §5）。
  ///
  /// **刻意不用右滑**：训练屏整屏已经在响应横向拖拽（切动作，S6），
  /// 而 §7 又明令禁止训练中做"左滑删除"这类需要在组间 60 秒里精细操作的手势。
  /// 长按是这块屏幕上唯一既不与别的手势打架、也不要求精细动作的入口。
  ///
  /// 撤销后大按钮上的值**不动** —— 它就是这一组刚记下的值，
  /// 于是"手抖点快了"可以直接再点一下补回来（规格要求的"恢复上一组建议值"）。
  Future<void> undoSet(String id) async {
    final int i = workout.sets.indexWhere((SetRecord s) => s.id == id);
    if (i < 0) return;
    final SetRecord r = workout.sets.removeAt(i);
    // 计划进度要退回：正式组才算进度（热身组本来就不计入）
    if (r.setType == SetType.normal && _normalSets > 0) _normalSets--;
    _hint = '已撤销第 ${r.setIndex} 组';
    _notify();

    // 本地优先：软删除留痕，训练中绝不发网络请求（真正出站交给同步队列）
    await store.deleteSet(r.id);
    syncQueue.enqueue('set_deleted', <String, Object?>{
      'id': r.id,
      'workout_id': r.workoutId,
    });
    analytics.track('set_undone', <String, Object?>{
      'set_index': r.setIndex,
      'method': 'longpress',
      // 误触率要看"记完多久才发现" —— 这也解释了撤销该多容易被找到
      'seconds_after_log': ((_clock() - r.completedAtMs) / 1000).round(),
    });
  }

  void skipRest() {
    _stopRest();
    _restRemaining = 0;
    restActivity.end(); // 用户跳过了休息 → 锁屏上那条不该还挂着倒计时
    unawaited(restCue.cancel()); // 体外那条提示同理：人已经在看屏幕了
    analytics.track('rest_skipped', <String, Object?>{
      'exercise_id': exercise.id,
      'planned_sec': plannedRestSec,
    });
    _notify();
  }

  /// 休息条上的 −15 / +15 秒（2026-10-05，v1.53）。
  ///
  /// 为什么要有它：健身房现场「今天想多歇半分钟」几乎必然发生，而原先只有「跳过」——
  /// 想多歇的人只能自己数秒，等于没有这个功能。
  ///
  /// 三条口径：
  ///   * 改的是**结束时刻**（`_restEndsAtMs`），不是"剩余秒数"。全项目只有这一份真相，
  ///     锁屏/灵动岛那串倒计时也按它走 —— 所以紧接着要**重播一次** Live Activity，
  ///     否则会出现"手机上 +15 了、锁屏上还是原来那个点"。
  ///   * **不在休息中时什么也不做**（按钮本来也不出现）；减到已经过去时，
  ///     由计时器那一跳去收尾，这里**不另写一条结束分支** ——
  ///     否则「休息完成」那条埋点在两条路径上会各报一次或漏报一次。
  ///   * **不计入 `tap_count`**：那条护栏量的是"为得到下一组多付出了几次操作"，
  ///     而调整休息不产生任何记录；计进去只会把这条指标算脏。
  void adjustRest(int deltaSec) {
    final int? endsAt = _restEndsAtMs;
    if (!_restRunning || endsAt == null) return;
    _restEndsAtMs = endsAt + deltaSec * 1000;
    final int left = ((_restEndsAtMs! - _clock()) / 1000).ceil();
    _restRemaining = left < 0 ? 0 : left;
    _startRestActivity();
    _notify();
  }

  /// 这个动作能不能"计时做组"（v1.53）。
  ///
  /// 只有**按时长记的动作**（平板支撑、农夫行走的时长那部分不算、`time` 轨迹）才有意义：
  /// 力量动作的"一组"是一串重复，秒数说不上；距离动作有自己的距离+时长口径。
  bool get canTimeSet => exercise.isTime && !isDistance;

  /// 计时中（大按钮那一下会**记下已计的秒数**）。
  bool get holding => _holdStartedAtMs != null;

  /// 已经计了多少秒（不在计时中就 0）。
  int get holdElapsedSec {
    final int? from = _holdStartedAtMs;
    if (from == null) return 0;
    final int ms = _clock() - from;
    return ms <= 0 ? 0 : (ms / 1000).round();
  }

  /// 开始计时。**不记组** —— 记组仍然是用户在合适的时候点一下大按钮。
  ///
  /// 为什么不做成"再点一下大按钮就停"之外的东西：`1 次点击 = 1 组` 是这条产品线
  /// 最不能动的一条，所以计时只是**给出这一组的值**，不改变"点一下 = 记一组"。
  void startHold() {
    if (!canTimeSet || holding) return;
    // 计一次 `stepper`（**诚实地算进 tap_count**）：它和"手动调次数"是同一件事 ——
    // 给出这一组的值。计时动作因此是"两次点击一组"（开始计时 + 点一下记下），
    // 这是这个动作真实的操作代价，藏起来只会让那条护栏看起来比实际好。
    analytics.countTap(TapKind.stepper);
    // 开计时前先把弹层收掉：否则用户会对着一个盖住屏幕的弹层数秒
    _sheetOpen = false;
    _holdStartedAtMs = _clock();
    _holdAnnounced = false;
    // 与休息同一条口径：**从开始时刻重算**，不累加
    _holdTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (_disposed) {
        t.cancel();
        return;
      }
      final int elapsed = holdElapsedSec;
      // 撑到今天的秒数就震两下（用户常常闭着眼数，这是唯一能"到点"的提示）。
      // 只震一次：之后继续撑是他自己的选择，不该每秒震一下。
      if (!_holdAnnounced && elapsed >= _reps) {
        _holdAnnounced = true;
        unawaited(haptics.targetReached());
      }
      _notify();
    });
    _notify();
  }

  /// 取消计时（不记组）。长按大按钮会走这条路 —— 长按在训练屏上的语义始终是"改"。
  void cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdStartedAtMs = null;
    _holdAnnounced = false;
    _notify();
  }

  void setOffline(bool value) {
    syncQueue.offline = value;
    _notify();  }

  Future<SyncOutcome> flushSync() => syncQueue.flush();

  // ---------- 内部 ----------

  void _logSet() {
    final reading = analytics.flushTap();
    final bool isWarmup = _warmup;
    // 组序与记录 id 用**全部组**计数：热身也要占一个序号，
    // 否则两条热身都是 _setSeq=1，id 撞主键、后一条覆盖前一条。
    _setSeq++;
    // 计划进度只用**正式组**计数。
    if (!isWarmup) _normalSets++;

    // 距离动作而距离还是 0：不写。见 canLog 的说明 ——
    // 一条"0 公里 / 0 秒"的记录是假数据，宁可这一下不算。
    if (!canLog) {
      _hint = '长按按钮设置距离与时长（两个都要有，才能记一组）';
      _notify();
      return;
    }

    final record = SetRecord(
      // 确定性 id，包含 workout + 动作 + 组序 —— 三者确定唯一一条记录。
      //
      // 之前写的是 's_${workout.sets.length + 1}'：那是**每个控制器各自计数**的，
      // 所以同一次训练里两个动作都会生成 's_1'，后者把前者覆盖掉 —— 直接丢数据。
      // set_record.id 是全局主键，id 就不能按局部计数器生成。
      // 确定性还有个好处：同一组重复写入是幂等的。
      id: 's_${workout.id}_${exercise.id}_$_setSeq',
      workoutId: workout.id,
      exerciseId: exercise.id,
      setIndex: _setSeq,
      reps: _reps,
      weightKg: isBodyweight ? null : _weightKg,
      // 距离只给 distance_time 的动作写上；其余动作传 null（"不记距离"）
      distanceM: isDistance ? _distanceM : null,
      completedAtMs: _clock(),
      setType: isWarmup ? SetType.warmup : SetType.normal,
      rpe: _rpe,
    );
    workout.sets.add(record);

    // 本地优先：先落本地库、再进队列。训练中绝不发网络请求。
    unawaited(store.saveSet(record));
    // 训练行本身也必须落库（totalSets / totalVolume 随之更新）。
    // 之前只写了 set_record，导致重启后 loadWorkout 找不到这次训练。
    unawaited(store.saveWorkout(workout));
    syncQueue.enqueue('set_record', <String, Object?>{
      'id': record.id,
      'workout_id': record.workoutId,
      'exercise_id': record.exerciseId,
      'set_index': record.setIndex,
      'weight_kg': record.weightKg,
      'reps': record.reps,
      // 距离（米）。服务端现在是"有就收"，没这个字段就是没记
      'distance_m': record.distanceM,
      'set_type': record.setType.wire,
      'completed_at': record.completedAtMs,
      'rpe': record.rpe,
    });

    // ── 建议采纳链：展示 → 采纳 / 手改 ────────────────────────────────
    //
    // 口径（写进 docs/analytics.md §2.2 的注）：**在这条组记录被记下的这一刻
    // 记一次"展示"**，紧接着按"记的值 == 建议的值"分流成采纳或手改。
    //
    // 为什么不在按钮渲染时记"展示"：那会把"用户看了但没记"也算进分母，
    // 而分母里混进"根本没打算练这一组"的人，采纳率就没法看了。
    // 这样三者严格同源：shown == accepted + modified，比率必然落在 [0,1]。
    //
    // 热身组不算：建议针对的是正式组，热身是"先来两组轻的"，不是对建议的表态。
    if (_suggestion != null && record.setType == SetType.normal) {
      final Suggestion sg = _suggestion!;
      analytics.track('suggestion_shown', <String, Object?>{
        'suggestion_id': suggestionId,
        'exercise_id': exercise.id,
        'reason_code': sg.reasonCode.name,
        'suggested_weight_kg': sg.weightKg,
        'suggested_reps': sg.reps,
      });

      final bool sameWeight = sg.weightKg == record.weightKg ||
          (sg.weightKg == null && record.weightKg == null);
      final bool sameReps = sg.reps == record.reps;
      final bool sameDistance = !isDistance ||
          (plan.targetDistanceM == null || record.distanceM == plan.targetDistanceM);

      if (sameWeight && sameReps && sameDistance) {
        analytics.track('suggestion_accepted', <String, Object?>{
          'suggestion_id': suggestionId,
          'reason_code': sg.reasonCode.name,
        });
      } else {
        final double? dw = (sg.weightKg == null || record.weightKg == null)
            ? null
            : record.weightKg! - sg.weightKg!;
        analytics.track('suggestion_modified', <String, Object?>{
          'suggestion_id': suggestionId,
          'reason_code': sg.reasonCode.name,
          'delta_weight_kg': dw,
          'delta_reps': record.reps - sg.reps,
          // 方向取"重量优先"，没有重量（自重/时长）就看次数 ——
          // 这是"往难了改还是往轻了改"，正是引擎失效点的定位信息
          'direction': (dw ?? (record.reps - sg.reps).toDouble()) >= 0
              ? 'up'
              : 'down',
        });
      }
    }

    analytics.track('set_logged', <String, Object?>{
      'workout_id': workout.id,
      'exercise_id': exercise.id,
      'set_index': record.setIndex,
      'weight_kg': record.weightKg,
      'reps': record.reps,
      'distance_m': record.distanceM,
      'set_type': record.setType.wire,
      'rpe': record.rpe,
      'tap_count': reading.count,
      'tap_kinds': reading.kinds.map((k) => k.wire).toList(),
      'entry': reading.kinds.isEmpty ? 'unknown' : reading.kinds.first.wire,
      'is_offline': syncQueue.offline,
    });

    // 这一组**真的写进去了**才震一下。上面那条 `if (!canLog) return;` 的分支
    // 刻意不震：一次没记上的震动比不震更糟（用户以为记上了）。
    unawaited(haptics.setLogged());

    // 组数达标后不禁用，只提示。计划是建议不是牢笼。
    if (_normalSets >= plan.targetSets) {
      // ⚠️ 2026-10-08（10.8 清单第 3 条）：这句话下面现在会长出**两个按钮**
      // （「再加一组」/「下一个动作」），所以这里不再用一整句解释 ——
      // 文案与按钮都由界面给，控制器只留一句短提示（测试与锁屏也还在用它）。
      _hint = '已达到计划组数';
    }

    // 实际休息：相邻两组的间隔（10.8 清单第 2 条）。只收"像休息"的间隔 ——
    // 0 秒（同一秒连点两下）与超过 30 分钟（多半是中途去干别的了）都不算。
    final int nowMs = _clock();
    final int? prevMs = _lastLoggedAtMs;
    if (prevMs != null) {
      final int gapSec = ((nowMs - prevMs) / 1000).round();
      if (gapSec > 0 && gapSec <= 30 * 60) _observedRestsSec.add(gapSec);
    }
    _lastLoggedAtMs = nowMs;

    _startRest();
    analytics.beginSetInteraction(); // 开启下一组的交互周期
    _notify();
  }

  void _startRest() {
    final int sec = nextRestSec;
    _beginRest(sec, endsAtMs: _clock() + sec * 1000, announce: true);
  }

  /// 开始（或**接着**）倒数。
  ///
  /// [announce] 区分两种来源：用户刚记完一组（要上报 `rest_started`），
  /// 与"从被中断的训练回来"（那是同一次休息的下半段，再报一次就把口径搞脏了）。
  /// 把这次休息广播出去（Live Activity）。**失败是静默的** —— 见 `rest_activity.dart`。
  void _startRestActivity() {
    final int? endsAt = _restEndsAtMs;
    if (endsAt == null) return;
    restActivity.start(RestActivityInfo(
      exerciseName: exercise.name,
      // 与大按钮同一行字：锁屏上写的"下一组练什么"必须与点下去要写的值一致
      nextLabel: primaryButtonLabel,
      setIndex: setNumber,
      totalSets: plannedSets,
      endAtMs: endsAt,
    ));
  }

  void _beginRest(
    int remainingSec, {
    required int endsAtMs,
    required bool announce,
    int? totalSec,
  }) {
    _stopRest();
    _restTotalSec = totalSec ?? remainingSec;
    _restRemaining = remainingSec;
    _restEndsAtMs = endsAtMs;
    _restRunning = true;
    if (announce) {
      analytics.track('rest_started', <String, Object?>{
        'exercise_id': exercise.id,
        'planned_sec': plannedRestSec,
        'auto': true,
      });
    }
    // Live Activity：把"休息到几点结束"广播给系统，锁屏上那串数字由它自己走。
    _startRestActivity();
    _restTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_disposed) {
        t.cancel();
        return;
      }
      // ⚠️ **不靠每秒减一**（2026-10-04 修）：App 被系统挂起时（锁屏、切后台、
      // 系统省电）Dart 的定时器**不会走**，回到前台后再从旧数字接着减，
      // 就把"被挂起的那段"白送了 —— 而锁屏上系统走的倒计时是准的，
      // 两个界面会当场对不上（"手机上还剩 40 秒，锁屏上已经 0:10"）。
      // 所以每一跳都**从结束时刻重算**：真源仍然是 `_restEndsAtMs`。
      final int? endsAt = _restEndsAtMs;
      final int left = endsAt == null ? 0 : ((endsAt - _clock()) / 1000).ceil();
      if (left <= 0) {
        _restRemaining = 0;
        _restRunning = false;
        _restEndsAtMs = null;
        t.cancel();
        analytics.track('rest_completed', <String, Object?>{
          'exercise_id': exercise.id,
          'planned_sec': plannedRestSec,
        });
        restActivity.end(); // 锁屏上那条也要撤下
        // 这一下通常不看屏幕（手机扣在器械上/在包里）—— 靠震动把人叫回来
        unawaited(haptics.restFinished());
        // Android：锁屏上没有任何东西（iOS 有 Live Activity），发一条本地通知 ——
        // 这是"手机在包里也知道该下一组了"的唯一办法。
        unawaited(restCue.show(title: '休息结束', body: '下一组：$primaryButtonLabel'));
      } else {
        _restRemaining = left;
      }
      _notify();
    });
  }

  void _stopRest() {
    _restTimer?.cancel();
    _restTimer = null;
    _restRunning = false;
    _restEndsAtMs = null;
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopRest();
    _holdTimer?.cancel();
    _holdTimer = null;
    // 退出训练屏 = 这次休息不再有意义：锁屏上那条必须撤掉，
    // 否则用户放下手机之后会看到一条永远数不完的"组间休息"。
    restActivity.end();
    unawaited(restCue.cancel());
    super.dispose();
  }
}
