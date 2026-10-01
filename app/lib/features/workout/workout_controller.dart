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
import '../../core/units.dart';
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
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    workout = Workout(id: workoutId, startedAtMs: _clock());
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
          endsAtMs: restEndsAtMs, announce: false);
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
  final int Function() _clock;

  /// 显示单位。存储与引擎始终是 kg，这个字段只用于格式化。
  late final WeightUnit unit;

  /// 本次训练实际使用的休息时长（秒）。**算一次就固定** ——
  /// 用户在训练中途去改设置也不该让倒计时突然变长变短。
  late final int plannedRestSec;

  late final Workout workout;
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
  int get restRemainingSec => _restRemaining;
  bool get restRunning => _restRunning;

  /// 正在休息时给出"休息到几点"（绝对毫秒）—— 会话恢复要用它。
  /// 不在休息中就是 null（下一个版本要拿这个值去写"未结束的会话"）。
  int? get restEndsAtMs => _restRunning ? _restEndsAtMs : null;
  bool get restDone => !_restRunning && _restRemaining == 0 && _normalSets > 0;
  bool get sheetOpen => _sheetOpen;
  bool get isOffline => syncQueue.offline;
  bool get isBodyweight => exercise.isBodyweight;
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
  double get weightStep =>
      exercise.weightIncrement > 0 ? exercise.weightIncrement : 2.5;

  /// 距离步进幅度：100 米。跑步机上最小刻度就是 0.1 km，
  /// 而再细（10 米）在长距离上要点太多次。
  double get distanceStepM => 100;

  /// 大按钮上显示的文案 —— 就是即将写入的值。
  /// 这是全产品唯一不可妥协的指标：点击即写入，1 次点击 = 1 组。
  String get primaryButtonLabel {
    // 距离动作：念「5.00 公里 · 30:00」——重量与次数都说不通（跑步机没有重量，
    // "1800 次"更是胡说）。距离 + 时长才是这个动作实际做了什么。
    if (isDistance) {
      return '${formatDistanceKm(_distanceM)} · ${formatDurationHms(_reps)}';
    }
    // 辅助自重：那个数字是**助力**。只说「30 kg × 8」会被读成"举起了 30kg"，
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
  void onBigButtonTap() {
    analytics.countTap(TapKind.bigButton);
    _logSet();
  }

  /// 长按大按钮 500ms：打开修改弹层。**不记录任何一组。**
  void onLongPress() {
    analytics.countTap(TapKind.longPress);
    // 记下打开弹层前的值：只有真的改了才算一次"编辑"（见 onSheetConfirm）
    _sheetFromWeight = _weightKg;
    _sheetFromReps = _reps;
    _sheetOpen = true;
    _hint = '步进调整，不需要键盘';
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
    analytics.track('rest_skipped', <String, Object?>{
      'exercise_id': exercise.id,
      'planned_sec': plannedRestSec,
    });
    _notify();
  }

  void setOffline(bool value) {
    syncQueue.offline = value;
    _notify();
  }

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

    // 组数达标后不禁用，只提示。计划是建议不是牢笼。
    if (_normalSets >= plan.targetSets) {
      _hint = '已达到计划组数，再点会继续记录（不加限制）';
    }

    _startRest();
    analytics.beginSetInteraction(); // 开启下一组的交互周期
    _notify();
  }

  void _startRest() => _beginRest(plannedRestSec,
      endsAtMs: _clock() + plannedRestSec * 1000, announce: true);

  /// 开始（或**接着**）倒数。
  ///
  /// [announce] 区分两种来源：用户刚记完一组（要上报 `rest_started`），
  /// 与"从被中断的训练回来"（那是同一次休息的下半段，再报一次就把口径搞脏了）。
  void _beginRest(int remainingSec, {required int endsAtMs, required bool announce}) {
    _stopRest();
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
    _restTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_disposed) {
        t.cancel();
        return;
      }
      if (_restRemaining <= 1) {
        _restRemaining = 0;
        _restRunning = false;
        _restEndsAtMs = null;
        t.cancel();
        analytics.track('rest_completed', <String, Object?>{
          'exercise_id': exercise.id,
          'planned_sec': plannedRestSec,
        });
      } else {
        _restRemaining--;
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
    super.dispose();
  }
}
