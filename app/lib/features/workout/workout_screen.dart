/// 练了么 · 训练中主屏（S4）+ 修改弹层（S5）
///
/// 对应 `docs/interaction-spec.md` §5–§8。
///
/// 一个刻意的实现选择：修改弹层用 Stack 内的自绘层，而不是 `showModalBottomSheet`。
/// 理由是规格里那条硬要求——「长按不误记」必须有 widget 测试守着，
/// 自绘层可以在同一棵 widget 树里直接断言，不需要处理路由与动画时序。
library;

import '../../core/icon_spec.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/best_set.dart';
import '../../core/last_time.dart';
import '../../core/theme.dart';
import '../../core/glass_overlay.dart';
import '../../core/motion.dart';
import '../../core/accent_button.dart';
import '../../core/reduced_motion.dart';
import '../../core/units.dart';
import '../../core/weight_step_dialog.dart';
import '../../data/db.dart' show ExerciseData;
import '../../data/local_store.dart';
import '../../domain/models.dart';
import '../exercise/exercise_detail_screen.dart';
import 'workout_controller.dart';
import 'screen_awake.dart';
import 'workout_session.dart';

/// **只为测试存在的两个计数**（VI 计划 T2-1 的判据 1）。
///
/// 这一条修的是"组间休息每秒**整屏重建**一次"这个**看不见**的性能风险 ——
/// 而"看不见"就意味着改坏了也没人立刻发现。有了这两个数，
/// `rest_local_rebuild_test.dart` 就能断言"每秒只有休息带重建、整屏一次都不重建"。
///
/// 用 `assert` 包住递增 → release 里这两行不存在（与 `debugSwitchTab` 同一种做法）。
int debugWorkoutScreenBuilds = 0;
int debugRestStripBuilds = 0;

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({
    super.key,
    required this.session,
    this.catalog = const <ExerciseData>[],
    this.store,
    this.screenAwake = const MethodChannelScreenAwake(),
    this.onSwapExercise,
    this.onWeightStepChanged,
    this.onWeightStepAll,
  });

  /// 一次训练里的全部动作（S6）。单个动作就用 `WorkoutSession.single(c)`。
  ///
  /// **会话与它内部的控制器都由调用方持有并负责 dispose** ——
  /// 这样测试可以在页面销毁后继续断言控制器状态。
  final WorkoutSession session;

  /// 训练屏期间**别让屏幕熄掉**（v1.53）。默认走平台通道；
  /// 测试传一个记账的替身 —— "进训练屏开、走的时候关"是逻辑，必须能断言。
  final ScreenAwake screenAwake;

  /// **器械被占了 → 换一个动作**（v1.53）。
  ///
  /// 为什么由调用方实现：换动作要"按当前部位预筛的选择器 + 新动作的上次记录 + 落库"，
  /// 那三样东西都在外壳（`main.dart`）手里，训练屏只有一份瘦身的控制器。
  /// 不传就没有这个入口（测试与"单独打开这一屏"的场景）。
  final Future<void> Function()? onSwapExercise;

  /// 本次训练涉及的动作（**完整动作库行**）。
  ///
  /// 控制器手里只有瘦身过的 `ExerciseSpec`（够算渐进建议，但没有动作说明、
  /// 部位、器械），而动作详情页要的就是那些。所以由调用方把完整行带进来 ——
  /// 不传也不影响训练，只是详情入口不显示。
  final List<ExerciseData> catalog;

  /// 详情页要看历史；不传就只显示"怎么做"（测试与无库场景）
  final LocalStore? store;

  /// **用户把某个动作的加重步进改了**（2026-10-09，10.9 清单第 8a 条）。
  ///
  /// 为什么由调用方实现（与 [onSwapExercise] 同一个理由）：写库要用 `ExerciseRepository`，
  /// 而训练屏只拿得到瘦身过的控制器；外壳手里才有仓库。
  /// 不传就没有"改步进"这个入口（测试与"单独打开这一屏"的场景）。
  final Future<void> Function(String exerciseId, double kg)?
      onWeightStepChanged;

  /// **把步进铺到所有动作**（同一条清单里的那个"所有动作都改"）。
  /// 与 [onWeightStepChanged] 一样由外壳实现：它要动整个动作库，还要把值记成"你设的默认"。
  final Future<void> Function(double kg)? onWeightStepAll;

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  /// 当前动作。切动作时这个 getter 会指向另一个控制器 ——
  /// 所以下面所有 `c.xxx` 都自动跟着走，不需要各自处理切换。
  WorkoutController get c => widget.session.current;

  /// 已经为哪个"动作 + 计划组数"弹过"做满计划了"那个选择（10.8 清单第 7 条）。
  ///
  /// 为什么要记：`_onChange` 会因为**任何**状态变化被叫到（记组、休息倒数、切动作…），
  /// 不记的话那一次弹窗会被反复弹出来。key 用 `exerciseId@plannedSets` ——
  /// 换了动作或组数变了就是另一次选择，该重新问。
  final Set<String> _askedPlanDone = <String>{};

  /// 大按钮现在是不是被按着（T2-2 的按压缩放）。手指滑出去要弹回来，所以三个回调都改它。
  bool _guideOpen = false;
  String get _planDoneKey => '${c.exercise.id}@${c.plannedSets}';

  @override
  void initState() {
    super.initState();
    // 只听会话：它会转发内部每个控制器的通知，切动作也是它通知
    widget.session.addListener(_onChange);
    unawaited(_loadBest()); // 当前动作的「历史最佳」（对照带右半边）
    // 训练期间**别让屏幕熄掉**（v1.53）：手机架在器械上时，
    // 屏幕一黑就意味着"每记一组先解一次锁"。离开这一屏就还回去（不全局常亮）。
    // 失败是静默的 —— 少一个常亮绝不能让训练屏记不了组。
    unawaited(widget.screenAwake.keepOn());
  }

  @override
  void dispose() {
    widget.session.removeListener(_onChange);
    unawaited(widget.screenAwake.release());
    super.dispose();
  }

  /// 左右滑动切换动作（规格 S6）。要求一定速度，避免手一抖就跳走。
  void _onHorizontalDragEnd(DragEndDetails d) {
    // 弹层开着时不切：那是在改重量，不是在换动作
    if (c.sheetOpen) return;
    final double v = d.velocity.pixelsPerSecond.dx;
    if (v.abs() < 200) return;
    if (v < 0) {
      widget.session.next();
    } else {
      widget.session.previous();
    }
  }

  void _onChange() {
    // 切了动作就重读「历史最佳」（同一个动作只读一次，见 _loadBest）
    if (_bestLoadedFor != c.exercise.id) {
      _best = null;
      unawaited(_loadBest());
    }
    if (mounted) setState(() {});
    _maybeAskPlanDone();
  }

  /// 做满计划组数的那一刻，弹一次「再加一组 / 下一个动作」（10.8 清单第 7 条）。
  ///
  /// 用户原话：「这个界面重新设计：**加一组和下一组应该是弹窗的形式更好一些吧**？
  /// 在下面太鸡肋了」（上一版我按他上一轮的"给两条明确的路"做成了底部两颗按钮）。
  ///
  /// ⚠️ 三个纪律：
  ///   1. **只在"刚好做满"的那一次弹** —— 弹窗是用来做选择的，不是常驻的路标；
  ///   2. 每个「动作 + 计划组数」只弹一次（`_askedPlanDone`）—— 否则记一组弹一次；
  ///   3. 弹窗里两个按钮就是**动作**（再加一组 = 立刻记一组）与**去路**（下一个/结束），
  ///      点遮罩关掉 = 什么都不做（用户可以继续按大按钮）。
  void _maybeAskPlanDone() {
    if (!mounted) return;
    if (c.normalSets < c.plannedSets) return;
    if (c.holding || c.sheetOpen) return; // 正在计时/改重量时不打扰
    if (_askedPlanDone.contains(_planDoneKey)) return;
    _askedPlanDone.add(_planDoneKey);
    final bool last = !widget.session.canGoNext;
    // 记完这一组正好在 setState/build 的尾巴上 —— 推到下一帧再弹，避免"build 期间弹窗"
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final bool again = await showAppDialog<bool>(
            context: context,
            builder: (BuildContext ctx) => AlertDialog(
              backgroundColor: Tokens.surface,
              title:
                  const Text('计划组数做完了', style: TextStyle(color: Tokens.text)),
              content: Text(
                last
                    ? '这是最后一个动作。加一组接着练，或者收工。'
                    : '加一组接着练，或者去下一个：${widget.session.nextName ?? '下一个动作'}。',
                key: const Key('plan-done-note'),
                style: const TextStyle(
                    color: Tokens.text2, height: Tokens.lhNormal),
              ),
              actions: <Widget>[
                TextButton(
                  key: const Key('plan-done-more'),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('再加一组',
                      style: TextStyle(color: Tokens.accentText)),
                ),
                TextButton(
                  key: const Key('plan-done-next'),
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(last ? '结束训练' : '下一个',
                      style: const TextStyle(color: Tokens.accentText)),
                ),
              ],
            ),
          ) ??
          false;
      if (!mounted) return;
      if (again) {
        c.onBigButtonTap(); // 立刻再记一组（与点大按钮同一个动作）
      } else if (last) {
        Navigator.of(context).maybePop();
      } else {
        widget.session.next();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // **只为测试存在的计数**（VI 计划 T2-1 判据 1）：`assert` 包住 → release 里不存在。
    assert(() {
      debugWorkoutScreenBuilds++;
      return true;
    }());
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            // 左右滑动切换动作（规格 S6）。挂在整块内容上：
            // 大按钮的点击/长按仍在手势竞技场里胜出，只有横向拖拽才切动作。
            GestureDetector(
              key: const Key('workout-swipe-area'),
              behavior: HitTestBehavior.opaque,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              // ⚠️ **2026-10-10 重排**（`docs/plan-ux-2026-10-10.md` P0-3）。
              // 原来的顺序是「中部（建议 + 上次 + 第 N 组 + 大按钮）→ 已完成 → 休息条 →
              // 切换条 → 提示」，于是**主按钮落在屏幕中部**，而 spec §5 那条硬约束写的是
              // "主操作位于屏幕下 1/3"；上半屏还有近 40% 纯黑死区，
              // 而"上次 / 最佳"这两个最值钱的数字一个在角落、一个根本没出现过。
              // 现在：对照带在最上面、本次那几行**撑满中间**、大按钮贴着底部。
              child: Column(
                children: <Widget>[
                  _header(),
                  Expanded(child: _setsArea()),
                  _bigArea(),
                  _switcher(),
                ],
              ),
            ),
            if (c.sheetOpen) _sheetOverlay(),
          ],
        ),
      ),
    );
  }

  /// 当前动作的完整行（找不到就返回 null）
  ExerciseData? _dataFor(String exerciseId) {
    for (final ExerciseData e in widget.catalog) {
      if (e.id == exerciseId) return e;
    }
    return null;
  }

  void _openDetail(String exerciseId) {
    final ExerciseData? e = _dataFor(exerciseId);
    if (e == null) return;
    // 单位取自**这个动作自己的控制器**：会话里每个动作都带了当时的单位设置，
    // 而 WorkoutScreen 本身不持有单位（它只持有会话）。
    WeightUnit unit = WeightUnit.kg;
    for (final WorkoutController c in widget.session.controllers) {
      if (c.exercise.id == exerciseId) {
        unit = c.unit;
        break;
      }
    }
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => ExerciseDetailScreen(
        exercise: e,
        store: widget.store,
        unit: unit,
      ),
    ));
  }

  // ---------- 顶部 ----------

  /// 4 段进度点：当前动作/总动作。训练屏顶部唯一的"我在第几个动作"的图形信号。
  // ignore: unused_element
  Widget _progressDots() {
    final int total = widget.session.length;
    final int index = widget.session.index;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, 0),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < total; i += 1)
            Expanded(
              child: Container(
                height: 3,
                margin: EdgeInsets.only(right: i == total - 1 ? 0 : Tokens.s1),
                decoration: BoxDecoration(
                  color: i <= index ? Tokens.accentText : Tokens.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s6, Tokens.s2, Tokens.s6, 0),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              key: const Key('back-button'),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.chevron_left, color: Tokens.text2),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          const SizedBox(width: Tokens.s2),
          Expanded(
            child: Text(
              c.exercise.name.isEmpty ? c.exercise.id : c.exercise.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Tokens.text,
                fontSize: Tokens.fsHeadline,
                fontWeight: Tokens.fwBold,
              ),
            ),
          ),
          if (c.isOffline)
            Container(
              key: const Key('offline-chip'),
              margin: const EdgeInsets.only(right: Tokens.s2),
              padding: const EdgeInsets.symmetric(horizontal: Tokens.s2, vertical: 2),
              decoration: BoxDecoration(
                color: Tokens.surfaceHi,
                borderRadius: BorderRadius.circular(Tokens.rPill),
              ),
              child: const Text('离线',
                  style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
            ),
          if (widget.session.hasMultiple) ...<Widget>[
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '动作 ${widget.session.index + 1} / ${widget.session.length}',
                  key: const Key('exercise-position'),
                  style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro),
                ),
              ),
            ),
            const SizedBox(width: Tokens.s2),
          ],
          // 一个 `⋯` 收掉换动作 / 说明 / 改重量（v2.3.0）；不再占三个 36pt 触区。
          PopupMenuButton<String>(
            key: const Key('workout-more'),
            tooltip: '更多',
            color: Tokens.elevated,
            icon: const Icon(Icons.more_horiz, color: Tokens.text2, size: IconSpec.m),
            onSelected: (String v) {
              switch (v) {
                case 'swap':
                  if (widget.onSwapExercise != null) unawaited(widget.onSwapExercise!());
                case 'info':
                  _openDetail(c.exercise.id);
                case 'weight':
                  c.onLongPress();
              }
            },
            itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(value: 'swap', child: Text('换动作')),
              const PopupMenuItem<String>(value: 'info', child: Text('动作说明')),
              const PopupMenuItem<String>(value: 'weight', child: Text('改重量')),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- 上次 / 历史最佳（2026-10-10 新增） ----------

  /// 当前动作的**历史最佳**。null = 没有历史（或还没读回来）。
  BestSet? _best;

  /// 已经为哪个动作读过（切动作才重读；同一个动作在一次训练里只读一次）。
  String? _bestLoadedFor;

  /// 为**当前动作**读一次历史。
  ///
  /// ⚠️ 排除**本次**训练：这条带子回答的是"我今天要打的那个纪录是多少"，
  /// 把刚才那几组算进去，"最佳"会在训练中途自己往上跳。
  Future<void> _loadBest() async {
    final LocalStore? store = widget.store;
    if (store == null) return;
    final String id = c.exercise.id;
    if (_bestLoadedFor == id) return;
    _bestLoadedFor = id;
    try {
      final List<SetRecord> rows =
          await store.setsForExercise(id, excludeWorkoutId: c.workout.id);
      final BestSet? b = bestSetOf(rows, trackType: c.exercise.trackType);
      if (!mounted || _bestLoadedFor != id) return;
      setState(() => _best = b);
    } catch (_) {
      // 读不出来就当没有历史 —— 少一条对照带，绝不能让训练屏记不了组
    }
  }

  /// 「上次 / 历史最佳」那条带（上下细线夹着，与「进步」页的数字带同一种语言）。
  ///
  /// 两样都没有（首次练这个动作）就整条不出现 —— 上半屏留给"本次"那几行。
  // ignore: unused_element
  Widget _compareBand() {
    final String? lastMain = lastSetMainLabel(c.lastSession,
        unit: c.unit, trackType: c.exercise.trackType);
    final String? lastSub = lastSetSubLabel(c.lastSession);
    final BestSet? best = _best;
    final String targetReps = '${c.plan.targetRepsLow}'
        '${c.plan.targetRepsHigh == c.plan.targetRepsLow ? '' : '–${c.plan.targetRepsHigh}'}';
    final String target = '${c.plannedSets} × $targetReps'
        '${c.exercise.isTime ? ' 秒' : ''}';
    final String targetSub = c.plan.targetWeightKg == null
        ? (c.isBodyweight ? '自重' : '')
        : formatWeight(c.plan.targetWeightKg, c.unit);
    final bool hasLast = lastMain != null;
    final bool hasBest = best != null;
    // 首练：没有过去、没有纪录 → 只摆一行"今天的目标"，不渲染两格破折号（O6）。
    if (!hasLast && !hasBest) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s3, Tokens.s5, 0),
        child: Container(
          key: const Key('compare-band'),
          padding: const EdgeInsets.symmetric(vertical: Tokens.s4),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Tokens.hair), bottom: BorderSide(color: Tokens.hair)),
          ),
          child: Row(
            children: <Widget>[
              const Text('今天的目标',
                  style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
              const SizedBox(width: Tokens.s3),
              Expanded(
                child: Text(
                  targetSub.isEmpty ? target : '$target · $targetSub',
                  key: const Key('today-target'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Tokens.text,
                      fontSize: Tokens.fsBody,
                      fontWeight: Tokens.fwBold),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s3, Tokens.s5, 0),
      child: Container(
        key: const Key('compare-band'),
        padding: const EdgeInsets.symmetric(vertical: Tokens.s4),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Tokens.hair), bottom: BorderSide(color: Tokens.hair)),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (hasLast)
                Expanded(
                  child: _compareCell(
                    '上次',
                    lastMain,
                    lastSub,
                    Tokens.text,
                    valueKey: const Key('last-time'),
                    subKey: const Key('last-time-sub'),
                  ),
                ),
              if (hasLast) const SizedBox(width: Tokens.s3),
              if (hasBest)
                Expanded(
                  child: _compareCell(
                    '最佳',
                    bestSetMainLabel(best, unit: c.unit, trackType: c.exercise.trackType),
                    bestSetSubLabel(best, unit: c.unit),
                    Tokens.pr,
                    valueKey: const Key('best-time'),
                    subKey: const Key('best-time-sub'),
                  ),
                ),
              if (hasBest) const SizedBox(width: Tokens.s3),
              Expanded(
                child: _compareCell(
                  '目标',
                  target,
                  targetSub.isEmpty ? null : targetSub,
                  Tokens.text,
                  valueKey: const Key('today-target'),
                  subKey: const Key('today-target-sub'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compareCell(
    String label,
    String value,
    String? sub,
    Color valueColor, {
    Key? valueKey,
    Key? subKey,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label,
            style:
                const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
        const SizedBox(height: 4),
        Text(
          value,
          key: valueKey,
          style: TextStyle(
            color: valueColor,
            fontSize: Tokens.fsBody,
            fontWeight: Tokens.fwBold,
            letterSpacing: Tokens.lsSnug,
          ),
        ),
        if (sub != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(sub,
              key: subKey,
              style: const TextStyle(
                  color: Tokens.text3, fontSize: Tokens.fsMicro)),
        ],
      ],
    );
  }

  // ---------- 本次（撑满中间那块曾经的空黑） ----------

  Widget _setsArea() {
    final List<SetRecord> sets = c.loggedSets;
    final int planned = c.plannedSets;
    final int rows = sets.length > planned ? sets.length : planned;
    final bool showLast = c.lastSession != null;
    final String? lastLabel = c.lastSession == null
        ? null
        : '${c.lastSession!.weightKg == null ? '自重' : formatWeight(c.lastSession!.weightKg!, c.unit)}'
            ' × ${c.lastSession!.reps.isEmpty ? '—' : c.lastSession!.reps.last}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s6, Tokens.s7, Tokens.s6, 0),
      child: Column(
        key: const Key('done-list'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text('本次',
                  style:
                      TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
              const SizedBox(width: Tokens.s2),
              Text(
                c.warmup ? '热身组' : '第 ${c.setNumber} 组',
                key: const Key('set-number'),
                style: TextStyle(
                    color: c.warmup ? Tokens.accentText : Tokens.text3,
                    fontSize: Tokens.fsMicro),
              ),
              const Spacer(),
              Text('${sets.length} / $planned 组',
                  key: const Key('set-count'),
                  style: const TextStyle(
                      color: Tokens.text2,
                      fontSize: Tokens.fsCap,
                      fontFeatures: Tokens.tabular)),
            ],
          ),
          const SizedBox(height: Tokens.s2),
          // ⚠️ v2.0.1 真机：这张卡原来是 `Expanded` 撑满剩余高度，于是 4 行组表下面
          // 留了一大片空卡底（动作要领孤零零吊在中间，像"加载失败"）。改成**卡随内容收口**：
          // 组表 + 要领排完就结束卡片，剩下的呼吸空间留给下面「第 N 组 / 记录键」。
          // `Flexible` 是关键：内容超过可用高度时（2.0× 字号 / 5 组 + 展开要领）卡内 ListView
          // 自己滚，而不是让外层 Column 溢出 —— 否则 `rest_zero_frame_test` 会当场红。
          Flexible(
            child: Container(
              decoration: BoxDecoration(
                color: Tokens.surface,
                borderRadius: BorderRadius.circular(Tokens.rCard),
                border: Border.all(color: Tokens.line),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Tokens.s3, vertical: Tokens.s2),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Tokens.line)),
                    ),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                            width: 24,
                            child: Text('组',
                                style: TextStyle(
                                    color: Tokens.text3,
                                    fontSize: Tokens.fsMicro))),
                        Expanded(
                            child: Text('重量',
                                style: TextStyle(
                                    color: Tokens.text3,
                                    fontSize: Tokens.fsMicro))),
                        SizedBox(
                            width: 44,
                            child: Text('次数',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    color: Tokens.text3,
                                    fontSize: Tokens.fsMicro))),
                        if (c.lastSession != null)
                          SizedBox(
                              width: 76,
                              child: Text('上次',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      color: Tokens.text3,
                                      fontSize: Tokens.fsMicro))),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '目标 ${c.plannedSets}×${c.plan.targetRepsLow}'
                              '${c.plan.targetRepsHigh == c.plan.targetRepsLow ? '' : '–${c.plan.targetRepsHigh}'}',
                              key: const Key('table-target'),
                              style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro),
                            ),
                          ),
                        ),
                        SizedBox(width: 24),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      // 卡随内容长高；内容超过可用高度时自己滚（不在卡里留空白）。
                      shrinkWrap: true,
                      physics: const ClampingScrollPhysics(),
                      padding: EdgeInsets.zero,
                      children: <Widget>[
                        for (int i = 0; i < rows; i += 1)
                          _setRow(
                            index: i,
                            logged: i < sets.length ? sets[i] : null,
                            current: i == sets.length,
                            planned: planned,
                            lastLabel: lastLabel,
                            showLast: showLast,
                          ),
                        _howToCard(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 组表一行：已完成（✓）/ 当前（橙左条 + 浅橙底）/ 待做（42% 透明）。
  Widget _setRow({
    required int index,
    required SetRecord? logged,
    required bool current,
    required int planned,
    required String? lastLabel,
    required bool showLast,
  }) {
    final bool done = logged != null;
    final bool pending = !done && !current;
    final String weight = done
        ? (logged.weightKg == null
            ? '自重'
            : formatWeight(logged.weightKg!, c.unit))
        : (c.isBodyweight ? '自重' : formatWeight(c.weightKg, c.unit));
    final String reps = done
        ? (logged.hasDistance
            ? formatDurationHms(logged.reps)
            : '${logged.reps}${c.exercise.isTime ? ' 秒' : ''}')
        : '${c.reps}${c.exercise.isTime ? ' 秒' : ''}';
    Widget body = Container(
      key: done ? Key('done-set-${logged.id}') : Key('set-row-$index'),
      padding: const EdgeInsets.symmetric(
          horizontal: Tokens.s3, vertical: Tokens.s4),
      decoration: BoxDecoration(
        color: current ? Tokens.accentLo.withValues(alpha: 0.12) : null,
        border: Border(
          left: BorderSide(
              color: current ? Tokens.accentLo : Colors.transparent, width: 3),
          bottom: index == planned - 1
              ? BorderSide.none
              : const BorderSide(color: Tokens.line),
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 24,
            child: Text('${index + 1}',
                style: TextStyle(
                    color: done ? Tokens.text3 : Tokens.text2,
                    fontSize: Tokens.fsCap,
                    fontFeatures: Tokens.tabular)),
          ),
          Expanded(
            child: Text(weight,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: done ? Tokens.text : Tokens.text2,
                    fontSize: Tokens.fsSub,
                    fontWeight: Tokens.fwStrong,
                    fontFeatures: Tokens.tabular)),
          ),
          SizedBox(
            width: 44,
            child: Text(reps,
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: done ? Tokens.text : Tokens.text2,
                    fontSize: Tokens.fsSub,
                    fontFeatures: Tokens.tabular)),
          ),
          if (showLast)
            SizedBox(
              width: 76,
              child: Text(lastLabel ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      color: Tokens.text3, fontSize: Tokens.fsMicro)),
            ),
          SizedBox(
            width: 24,
            child: done
                ? const Icon(Icons.check,
                    color: Tokens.success, size: IconSpec.s)
                : current
                    ? Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Tokens.accent, width: 2),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
          ),
        ],
      ),
    );
    if (pending) body = Opacity(opacity: 0.42, child: body);
    if (!done) return body;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => c.undoSet(logged.id),
      child: _popIn(key: 'done-row-fade-${logged.id}', child: body),
    );
  }

  Widget _howToCard() {
    final String? text = _dataFor(c.exercise.id)?.instructions?.trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    final String firstLine = text.split('\n').first;
    return Padding(
      padding: const EdgeInsets.only(top: Tokens.s4, bottom: Tokens.s2),
      child: Column(
        key: const Key('howto-block'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          GestureDetector(
            key: const Key('howto-toggle'),
            onTap: () => setState(() => _guideOpen = !_guideOpen),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: <Widget>[
                const Text('动作要领',
                    style: TextStyle(
                        color: Tokens.text3, fontSize: Tokens.fsMicro)),
                const SizedBox(width: Tokens.s3),
                Expanded(
                  child: Text(_guideOpen ? '收起' : firstLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Tokens.text2, fontSize: Tokens.fsMicro)),
                ),
                Icon(_guideOpen ? Icons.expand_less : Icons.expand_more,
                    color: Tokens.text3, size: IconSpec.s),
              ],
            ),
          ),
          if (_guideOpen) ...<Widget>[
            const SizedBox(height: Tokens.s2),
            Text(text,
                style: const TextStyle(
                    color: Tokens.text2,
                    fontSize: Tokens.fsSub,
                    height: Tokens.lhLoose)),
            const SizedBox(height: Tokens.s2),
            GestureDetector(
              key: const Key('howto-open-detail'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _openDetail(c.exercise.id),
              child: const Text('完整说明 ›',
                  style: TextStyle(
                      color: Tokens.accentText, fontSize: Tokens.fsCap)),
            ),
          ],
        ],
      ),
    );
  }

  /// 一行"已完成的组"。  /// 一行"已完成的组"。长按撤销（误触的后悔药）。
  ///
  /// ⚠️ **2026-10-10（VI 计划 T2-2）**：新行要有**入场**（规格 §8 写的是"pop 入场 280ms"，
  /// 而它一直只写在纸上）。实现是这一行自己的 `TweenAnimationBuilder`，**不是 `AnimatedList`**：
  /// 健身房里连点两下是常态，`AnimatedList` 的队列会让第二行**迟到**（排队播动画）——
  /// 而行迟到在这件事上等于"我点的那一下没成功"，用户会再点一次（那就是两组）。
  ///
  /// 时长用 `Motion.base`（260ms，令牌里离 280 最近的一档 —— T1-4 的裁决是"时长只许来自令牌"）。
  /// 减弱动态效果下直接给终值（不用等）。
  // ignore: unused_element
  Widget _doneRow(SetRecord r) {
    return GestureDetector(
      key: Key('done-set-${r.id}'),
      behavior: HitTestBehavior.opaque,
      onLongPress: () => c.undoSet(r.id),
      child: _popIn(key: 'done-row-fade-${r.id}', child: _doneRowBody(r)),
    );
  }

  /// 新行入场：**透明 0 → 1 且略微放大 0.96 → 1**（"长出来"而不是"闪出来"）。
  Widget _popIn({required String key, required Widget child}) {
    if (reducedMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      key: Key(key),
      duration: Motion.base,
      // ⚠️ 用 `Motion.standard` 而**不是** `Motion.arrival`：后者是**过冲**曲线
      // （峰值 1.0978，T1-4 里专门钉过这个数），喂给 `Opacity` 会直接断言失败 ——
      // 透明度没有"超过 1"这回事。想做过冲就用 `Transform.scale` 单独加，
      // 不许让它经过透明度（这条是测试当场抓出来的）。
      curve: Motion.standard,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (BuildContext context, double t, Widget? inner) => Opacity(
        key: Key('$key-opacity'),
        opacity: t,
        child: Transform.scale(scale: 0.96 + 0.04 * t, child: inner),
      ),
      child: child,
    );
  }

  Widget _doneRowBody(SetRecord r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 16,
            child: Text('${r.setIndex}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: Tokens.text3, fontSize: Tokens.fsCap)),
          ),
          const SizedBox(width: Tokens.s3),
          // ⚠️ **这一格必须是 `Expanded`**（2026-10-10 在 2.0× 系统字号下抓到的）：
          // 它原来是裸 `Text`，而"助力 30 kg × 8 秒"这种组合在 2.0× 下会把这一行撑爆
          // （实测溢出 17px）。主数字要能缩，右侧那几个标记（RPE / 热身 / ✓）先保。
          Expanded(
            child: Text(
              // 距离动作念「5.00 公里 · 30:00」—— 既没有"自重 × 1800"，
              // 也没有把秒读成次。
              r.hasDistance
                  ? '${formatDistanceKm(r.distanceM!)} · '
                      '${formatDurationHms(r.reps)}'
                  // 按时长动作那个数字是秒，不加"秒"会被读成"自重 × 30 次"
                  : r.weightKg == null
                      ? '自重 × ${r.reps}${c.exercise.isTime ? ' 秒' : ''}'
                      : '${c.isAssisted ? '助力 ' : ''}'
                          '${formatWeight(r.weightKg, c.unit)} × ${r.reps}'
                          '${c.exercise.isTime ? ' 秒' : ''}',
              style: TextStyle(
                // 热身组用次级色：和正式组混在一起分不出来，用户就不知道
                // 哪些算进了计划进度
                color:
                    r.setType == SetType.warmup ? Tokens.text3 : Tokens.text2,
                fontSize: Tokens.fsSub,
                fontWeight: Tokens.fwStrong,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // RPE 记了就必须显示 —— 只写库不显示就成了用户看不见的隐藏数据
          if (r.rpe != null) ...<Widget>[
            const SizedBox(width: Tokens.s2),
            Text('RPE ${r.rpe!.toInt()}',
                style: const TextStyle(
                    color: Tokens.text3, fontSize: Tokens.fsMicro)),
          ],
          if (r.setType == SetType.warmup) ...<Widget>[
            const SizedBox(width: Tokens.s2),
            const Text('热身',
                style:
                    TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
          ],
          const SizedBox(width: Tokens.s2),
          const Text('✓',
              style: TextStyle(
                  color: Tokens.accentText,
                  fontSize: Tokens.fsSub,
                  fontWeight: Tokens.fwBold)),
        ],
      ),
    );
  }

  // ---------- 大按钮区（屏幕下 1/3） ----------

  Widget _bigArea() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s6, Tokens.s3, Tokens.s6, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _restStrip(),
          AccentButton(
            key: const Key('big-log-button'),
            label: c.primaryButtonLabel,
            labelKey: const Key('button-label'),
            height: Tokens.hPrimary,
            onPressed: c.canLog ? c.onBigButtonTap : null,
            onLongPress: c.onLongPress,
          ),
        ],
      ),
    );
  }

  /// 「改重量」+ 那行提示（2026-10-10）。
  ///
  /// **为什么加这个入口**：长按大按钮改重量是隐形的 —— 界面上只有一行 11pt 小字提过它。
  /// 现在它是一个看得见的胶囊（点它 = 长按那一下，走同一个 `onLongPress`），
  /// 提示语因此不再需要写"长按可以改重量"。
  // ignore: unused_element
  Widget _editRow() {
    return GestureDetector(
      key: const Key('edit-weight'),
      onTap: c.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s3, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Tokens.rPill),
          border: Border.all(color: Tokens.lineStrong),
        ),
        child: const Text('改重量',
            style: TextStyle(color: Tokens.text2, fontSize: Tokens.fsCap)),
      ),
    );
  }

  // ---------- 休息：大按钮上方一条细进度（2026-10-10） ----------

  /// 休息中（或刚结束）时，大按钮上方出现一条**细进度**。
  ///
  /// 原来它是一只 56pt 高的方盒子，里面一个 `01:59` —— 看不出"还剩多少比例"，
  /// 而且它挤在大按钮下面、和"已完成 / 上下一个"抢同一块地方（主按钮于是被顶到了屏幕中部）。
  /// 现在：数字 + 百分比 + 一条 3pt 的进度条，整条只有 ~26pt 高，直接贴在大按钮上方。
  ///
  /// 不休息时**整条不出现** —— 不摆一个 `00:00` 在那里占位置。
  ///
  /// ⚠️ **2026-10-10（VI 计划 T2-1）**：里面的数字与进度条包在 `ValueListenableBuilder`
  /// 里听 [WorkoutController.restTick] —— 秒级 tick 只重画这一条，
  /// 不再走 `_onChange → setState`（那会整屏重建，而 iOS 上同屏还有 `UITabBar` 平台视图）。
  /// 休息**开始 / 结束**仍是结构性变化，由父级重建。
  Widget _restStrip() {
    if (!c.restRunning && !c.restDone) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: c.restTick,
      builder: (BuildContext context, int tick, Widget? _) => _restStripBody(),
    );
  }

  Widget _restStripBody() {
    assert(() {
      debugRestStripBuilds++;
      return true;
    }());
    final int total = c.restTotalSec > 0 ? c.restTotalSec : c.plannedRestSec;
    // ⚠️ **条的方向 = 「还剩多少」**（2026-10-10 修，VI 计划 T0-1）。
    // 原来这里是 `1 - 剩余/总`（条在**长**），而右边那行字写的是「还剩 41%」（数字在**减**）——
    // 同一行里两个方向相反的信号，而这一行是"组间 60 秒"里唯一的时间线索。
    // 现在两者同向：**条越短 = 剩得越少**（`rest_progress_direction_test.dart` 钉着）。
    final double left = c.restDone || total <= 0
        ? 0
        : (c.restRemainingSec / total).clamp(0.0, 1.0);
    final int leftPct = (left * 100).round();
    return Padding(
      key: const Key('rest-bar'),
      padding: const EdgeInsets.only(bottom: Tokens.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // 大字号下这一组会被挤（v1.53 实测 1.5× 溢出 101px）：整体缩到放得下，
              // 右边那几个控件保持原尺寸 —— 那些是手指要点的地方，不许跟着缩。
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: <Widget>[
                      const Text('休息',
                          style: TextStyle(
                              color: Tokens.text3, fontSize: Tokens.fsCap)),
                      const SizedBox(width: Tokens.s3),
                      Text(
                        _restText(),
                        key: const Key('rest-time'),
                        style: TextStyle(
                          // 三档颜色：剩余 ≤ 3 秒转 accent（与那一下最轻的预告触觉**同一刻**发生，
                          // 视觉与触觉同时到 —— VI 计划 T2-4）；归零转 accent 且字号收小；
                          // 其余时间是普通的 text。**不闪、不跳字号**。
                          color: c.restDone
                              ? Tokens.accent
                              : (c.restRunning && c.restRemainingSec <= 3
                                  ? Tokens.accent
                                  : Tokens.text),
                          fontSize: c.restDone ? 17 : 20,
                          fontWeight: Tokens.fwBold,
                          fontFeatures: Tokens.tabular,
                        ),
                      ),
                      if (!c.restDone) ...<Widget>[
                        const SizedBox(width: Tokens.s2),
                        Text('还剩 $leftPct%',
                            style: const TextStyle(
                                color: Tokens.text3, fontSize: Tokens.fsMicro)),
                      ],
                    ],
                  ),
                ),
              ),
              // −15 / +15 只在**真的在休息**时出现 —— 休息已经结束时按了没用，
              // 摆着就是骗人（`adjustRest` 里也挡了一道）。
              if (c.restRunning) ...<Widget>[
                _restAdjust(
                    key: 'rest-minus',
                    label: '−15',
                    onTap: () => c.adjustRest(-15)),
                _restAdjust(
                    key: 'rest-plus',
                    label: '+15',
                    onTap: () => c.adjustRest(15)),
                const SizedBox(width: Tokens.s1),
              ],
              _restAdjust(key: 'skip-rest', label: '跳过', onTap: c.skipRest),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: left,
              minHeight: 3,
              backgroundColor: Tokens.lineStrong,
              valueColor: AlwaysStoppedAnimation<Color>(
                  c.restDone ? Tokens.success : Tokens.accent),
            ),
          ),
        ],
      ),
    );
  }

  /// 休息条上的一个小按钮。做成**方形热区**（44×36 起）——
  /// 训练中手指是汗的、手机可能架在器械上，太小的目标点不中。
  Widget _restAdjust({
    required String key,
    required String label,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        key: Key(key),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 36,
          constraints: const BoxConstraints(minWidth: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s2),
          child: Text(label,
              style: const TextStyle(
                  color: Tokens.text2,
                  fontSize: Tokens.fsSub,
                  fontWeight: Tokens.fwStrong)),
        ),
      );

  String _restText() {
    if (c.restDone) return '休息结束';
    final m = (c.restRemainingSec ~/ 60).toString().padLeft(2, '0');
    final s = (c.restRemainingSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ---------- 动作切换 ----------

  /// 底部切换条（S6）。**每个元素都是真的能点的** ——
  /// 之前这里是三个纯 Text，是死的装饰。
  Widget _switcher() {
    final WorkoutSession s = widget.session;
    // 只有一个动作时不显示：那行「1 / 1」没有信息量，还会让人以为能滑
    if (!s.hasMultiple) return const SizedBox.shrink();

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: Tokens.s3),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Tokens.hair)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          _switchSide(
            key: 'prev-exercise',
            name: s.previousName,
            leading: true,
            onTap: s.previous,
          ),
          // 中间那个「1 / 3」**搬到了顶栏**（`exercise-position` 的 key 跟着走）——
          // 屏幕上原来有两个含义不同的 x/y 隔了大半屏，是真会读错的。
          _switchSide(
            key: 'next-exercise',
            name: s.nextName,
            leading: false,
            onTap: s.next,
          ),
        ],
      ),
    );
  }

  /// 一侧的切换按钮。名字太长时省略，不挤掉中间的「2 / 3」。
  Widget _switchSide({
    required String key,
    required String? name,
    required bool leading,
    required VoidCallback onTap,
  }) {
    final bool enabled = name != null;
    final String label = leading ? '‹ ${name ?? '上一个'}' : '${name ?? '下一个'} ›';
    return GestureDetector(
      key: Key(key),
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 110,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: leading ? TextAlign.left : TextAlign.right,
          style: TextStyle(
            color: enabled ? Tokens.text2 : Tokens.text3,
            fontSize: Tokens.fsSub,
          ),
        ),
      ),
    );
  }

  // ---------- 修改弹层（S5） ----------

  Widget _sheetOverlay() {
    return Positioned.fill(
      child: Stack(
        children: <Widget>[
          GestureDetector(
            key: const Key('sheet-scrim'),
            onTap: c.onSheetConfirm,
            child: Container(color: Tokens.scrim),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              key: const Key('sheet'),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                  Tokens.s5, Tokens.s3, Tokens.s5, Tokens.s6),
              decoration: const BoxDecoration(
                color: Tokens.elevated,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(Tokens.rSheet)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Tokens.lineStrong,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: Tokens.s5),
                  // 距离动作（跑步机/划船机/跳绳/农夫行走）：**重量这一行没有意义** ——
                  // 跑步机上没有"自重"，农夫行走的重量也确实要记，所以分两种：
                  //   · 有重量的距离动作（农夫行走，weight_increment > 0）→ 重量 + 距离 + 时长
                  //   · 没有重量的（跑步机等）→ 距离 + 时长，不显示重量行
                  if (c.isDistance && !c.isBodyweight)
                    _stepperRow(
                      value: trimNumber(
                          round1(toDisplayWeight(c.weightKg, c.unit))),
                      unit: c.unit.wire,
                      // ⚠️ 步进按显示单位念，但**不许舍成一位小数**：
                      // 用户输进去的 1.25 要原样写在这个按钮上（`formatStep`）
                      step: formatStep(c.weightStep, c.unit),
                      keyMinus: 'step-weight-down',
                      keyPlus: 'step-weight-up',
                      // 步进可点改（10.9 清单第 8a 条）：有些健身房的片子只有 5 kg 一档，
                      // 而步进本来是种子数据里写死的。
                      onEditStep: widget.onWeightStepChanged == null
                          ? null
                          : () => _pickWeightStep(c),
                      onMinus: () => c.onStepper(deltaWeight: -c.weightStep),
                      onPlus: () => c.onStepper(deltaWeight: c.weightStep),
                    ),
                  if (c.isDistance && !c.isBodyweight)
                    const SizedBox(height: Tokens.s5),
                  if (c.isDistance)
                    _stepperRow(
                      value: trimNumber(round1(c.distanceM)),
                      unit: '米',
                      step: '${c.distanceStepM.toInt()}',
                      keyMinus: 'step-distance-down',
                      keyPlus: 'step-distance-up',
                      onMinus: () =>
                          c.onStepper(deltaDistanceM: -c.distanceStepM),
                      onPlus: () =>
                          c.onStepper(deltaDistanceM: c.distanceStepM),
                    ),
                  if (!c.isDistance)
                    _stepperRow(
                      // 步进值按显示单位展示；底层量与步长仍是 kg
                      // （lb 原生步进会让重量脱离杠铃片网格，见 core/units.dart）
                      value: c.isBodyweight
                          ? '自重'
                          : trimNumber(
                              round1(toDisplayWeight(c.weightKg, c.unit))),
                      // 辅助自重的单位里必须带"助力"：这个数越大越轻松
                      unit: c.isBodyweight
                          ? ''
                          : (c.isAssisted ? '${c.unit.wire} 助力' : c.unit.wire),
                      // ⚠️ 步进按显示单位念，但**不许舍成一位小数**：
                      // 用户输进去的 1.25 要原样写在这个按钮上（`formatStep`）
                      step: formatStep(c.weightStep, c.unit),
                      keyMinus: 'step-weight-down',
                      keyPlus: 'step-weight-up',
                      // 步进可点改（10.9 清单第 8a 条）：有些健身房的片子只有 5 kg 一档，
                      // 而步进本来是种子数据里写死的。
                      onEditStep: widget.onWeightStepChanged == null
                          ? null
                          : () => _pickWeightStep(c),
                      onMinus: () => c.onStepper(deltaWeight: -c.weightStep),
                      onPlus: () => c.onStepper(deltaWeight: c.weightStep),
                    ),
                  const SizedBox(height: Tokens.s5),
                  _stepperRow(
                    // 距离动作把秒念成 30:00（1800 秒没人这么念），其余照旧
                    value:
                        c.isDistance ? formatDurationHms(c.reps) : '${c.reps}',
                    // 按时长动作这里是**秒**，步进也变成 ±5 秒；
                    // 距离动作是 ±60 秒（1 分钟）
                    unit: c.isDistance ? '' : c.repsUnit,
                    step: '${c.repsStep}',
                    keyMinus: 'step-reps-down',
                    keyPlus: 'step-reps-up',
                    onMinus: () => c.onStepper(deltaReps: -c.repsStep),
                    onPlus: () => c.onStepper(deltaReps: c.repsStep),
                  ),
                  // 计时动作给一个"开始计时"（v1.53）：平板支撑这类动作，
                  // 手动选一个秒数等于让用户在垫子上自己看表 —— 那正是这个 App 该替他做的事。
                  // 它只**给出这一组的值**，记组仍然是点一下大按钮（红线：1 次点击 = 1 组）。
                  if (c.canTimeSet) ...<Widget>[
                    const SizedBox(height: Tokens.s4),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        key: const Key('sheet-timer-start'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Tokens.text,
                          side: const BorderSide(color: Tokens.lineStrong),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Tokens.rPill),
                          ),
                        ),
                        onPressed: c.startHold,
                        child: const Text('开始计时',
                            style: TextStyle(
                                fontSize: Tokens.fsBodyS,
                                fontWeight: Tokens.fwStrong)),
                      ),
                    ),
                  ],
                  const SizedBox(height: Tokens.s5),
                  // 热身组：规格要求「弱化样式存在、不主动教」，所以做成一个
                  // 普通文字按钮而不是显眼开关 —— 主按钮才是这一屏唯一的主角。
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const Key('sheet-warmup'),
                      onPressed: c.toggleWarmup,
                      style: TextButton.styleFrom(
                        foregroundColor:
                            c.warmup ? Tokens.accent : Tokens.text3,
                        padding: const EdgeInsets.symmetric(
                          horizontal: Tokens.s3,
                          vertical: Tokens.s2,
                        ),
                      ),
                      child: Text(
                        c.warmup ? '✓ 下一组记为热身' : '热身组',
                        style: const TextStyle(fontSize: Tokens.fsSub),
                      ),
                    ),
                  ),
                  const SizedBox(height: Tokens.s2),
                  // RPE：同样按规格弱化 —— 一行小档位，不占位置也不教。
                  // 点一个值即选中，**再点同一个值即清除**，省掉一个"清除"按钮。
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: <Widget>[
                        const Text('RPE',
                            style: TextStyle(
                                color: Tokens.text3, fontSize: Tokens.fsCap)),
                        const SizedBox(width: Tokens.s3),
                        for (final double v in _rpeChoices) _rpeChip(v),
                      ],
                    ),
                  ),
                  const SizedBox(height: Tokens.s3),
                  SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: FilledButton(
                      key: const Key('sheet-confirm'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Tokens.accent,
                        foregroundColor: Tokens.accentInk,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Tokens.rPill),
                        ),
                      ),
                      onPressed: c.onSheetConfirm,
                      child: const Text('确定',
                          style: TextStyle(
                              fontSize: Tokens.fsHeadline,
                              fontWeight: Tokens.fwBold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// RPE 只给常用档位，不做全键盘，也不做 1–10 全量选择（规格：弱化、不主动教）。
  static const List<double> _rpeChoices = <double>[6, 7, 8, 9, 10];

  Widget _rpeChip(double value) {
    final bool active = c.rpe == value;
    return Padding(
      padding: const EdgeInsets.only(right: Tokens.s1),
      child: InkWell(
        key: Key('rpe-${value.toInt()}'),
        borderRadius: BorderRadius.circular(Tokens.rPill),
        // 再点一次已选中的值 = 清除，不需要额外的"清除"按钮
        onTap: () => c.setRpe(active ? null : value),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Tokens.s3, vertical: Tokens.s2),
          decoration: BoxDecoration(
            color: active ? Tokens.accent : Colors.transparent,
            border:
                Border.all(color: active ? Tokens.accent : Tokens.lineStrong),
            borderRadius: BorderRadius.circular(Tokens.rPill),
          ),
          child: Text(
            '${value.toInt()}',
            style: TextStyle(
              // RPE 是功能控件（要读要选）→ text2（VI 计划 T0-3）
              color: active ? Tokens.accentInk : Tokens.text2,
              fontSize: Tokens.fsCap,
              fontWeight: active ? Tokens.fwBold : Tokens.fwStrong,
            ),
          ),
        ),
      ),
    );
  }

  /// 改加重步进（10.9 清单第 8a 条「加重量的选项能不能自定义」）。
  ///
  /// 对话框本身在 `core/weight_step_dialog.dart`：设置里的「加重步进」走的是**同一个**
  /// （两处要问的东西一模一样，两份实现迟早长歪）。
  /// 这一处多给一个"只改这个动作"（训练中当场要能只动手上这一个）。
  ///
  /// 写库**不在这里**：训练屏只有瘦身过的控制器，仓库在外壳手里（两个回调）。
  Future<void> _pickWeightStep(WorkoutController c) async {
    final WeightStepPick? pick = await pickWeightStep(
      context,
      unit: c.unit,
      current: c.weightStep,
      exerciseName: c.exercise.name,
    );
    if (pick == null || pick.kg <= 0) return; // 关掉弹层 / 空值 = 没改
    // ① 内存：这一趟训练立刻按新步进加减（不用退出重进）
    c.setWeightStep(pick.kg);
    // ② 库：由外壳写
    if (pick.all) {
      await widget.onWeightStepAll?.call(pick.kg);
    } else {
      await widget.onWeightStepChanged?.call(c.exercise.id, pick.kg);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(pick.all
            ? '所有动作的加重步进都改成 ±${formatWeight(pick.kg, c.unit)}'
            : '加重步进改成 ±${formatWeight(pick.kg, c.unit)}'),
      ),
    );
  }

  Widget _stepperRow({
    required String value,
    required String unit,

    /// 这一步的幅度，直接印在按钮上。
    ///
    /// 以前两个按钮上的字是**硬编码的 ±2.5** —— 于是次数那一行明明在 ±1，
    /// 按钮却写着 ±2.5（一处用户一眼能看出不对、而且会怪自己看错的地方）。
    required String step,
    required String keyMinus,
    required String keyPlus,
    required VoidCallback onMinus,
    required VoidCallback onPlus,

    /// 传了就把中间的步进做成**可点**的（点开改步进）。只有重量那一行传。
    VoidCallback? onEditStep,
  }) {
    return Row(
      children: <Widget>[
        Text(value,
            style:
                Tokens.display(36, weight: 700, letterSpacing: Tokens.lsTight)),
        if (unit.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: Tokens.s1),
            child: Text(unit,
                style: const TextStyle(
                    color: Tokens.text3,
                    fontSize: Tokens.fsBody,
                    fontWeight: Tokens.fwStrong)),
          ),
        const Spacer(),
        if (onEditStep != null) ...<Widget>[
          // 「步进」这一小枚就是入口 —— 它自己就写着当前幅度（±2.5），点开能改
          GestureDetector(
            key: const Key('step-weight-edit'),
            onTap: onEditStep,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Tokens.s3, vertical: 6),
              decoration: BoxDecoration(
                color: Tokens.surface,
                borderRadius: BorderRadius.circular(Tokens.rPill),
                border: Border.all(color: Tokens.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('±$step',
                      style: const TextStyle(
                          color: Tokens.text2,
                          fontSize: Tokens.fsCap,
                          fontWeight: Tokens.fwStrong)),
                  const SizedBox(width: 4),
                  const Icon(Icons.tune, size: IconSpec.s, color: Tokens.text3),
                ],
              ),
            ),
          ),
          const SizedBox(width: Tokens.s2),
        ],
        _stepButton(keyMinus, '−$step', onMinus),
        const SizedBox(width: Tokens.s2),
        _stepButton(keyPlus, '+$step', onPlus),
      ],
    );
  }

  Widget _stepButton(String key, String label, VoidCallback onPressed) {
    return SizedBox(
      width: 64,
      height: 56,
      child: OutlinedButton(
        key: Key(key),
        style: OutlinedButton.styleFrom(
          backgroundColor: Tokens.surface,
          side: const BorderSide(color: Tokens.lineStrong),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Tokens.rCard)),
          padding: EdgeInsets.zero,
        ),
        onPressed: onPressed,
        child: Text(label,
            style: const TextStyle(
                color: Tokens.text,
                fontSize: Tokens.fsSub,
                fontWeight: Tokens.fwStrong)),
      ),
    );
  }
}
