/// 练了么 · 训练中主屏（S4）+ 修改弹层（S5）
///
/// 对应 `docs/interaction-spec.md` §5–§8。
///
/// 一个刻意的实现选择：修改弹层用 Stack 内的自绘层，而不是 `showModalBottomSheet`。
/// 理由是规格里那条硬要求——「长按不误记」必须有 widget 测试守着，
/// 自绘层可以在同一棵 widget 树里直接断言，不需要处理路由与动画时序。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/units.dart';
import '../../data/db.dart' show ExerciseData;
import '../../data/local_store.dart';
import '../../domain/models.dart';
import '../exercise/exercise_detail_screen.dart';
import 'workout_controller.dart';
import 'screen_awake.dart';
import 'workout_session.dart';

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({
    super.key,
    required this.session,
    this.catalog = const <ExerciseData>[],
    this.store,
    this.screenAwake = const MethodChannelScreenAwake(),
    this.onSwapExercise,
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
  String get _planDoneKey => '${c.exercise.id}@${c.plannedSets}';

  @override
  void initState() {
    super.initState();
    // 只听会话：它会转发内部每个控制器的通知，切动作也是它通知
    widget.session.addListener(_onChange);
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
      final bool again = await showDialog<bool>(
            context: context,
            builder: (BuildContext ctx) => AlertDialog(
              backgroundColor: Tokens.surface,
              title: const Text('计划组数做完了',
                  style: TextStyle(color: Tokens.text)),
              content: Text(
                last
                    ? '这是最后一个动作。加一组接着练，或者收工。'
                    : '加一组接着练，或者去下一个：${widget.session.nextName ?? '下一个动作'}。',
                key: const Key('plan-done-note'),
                style: const TextStyle(color: Tokens.text2, height: 1.6),
              ),
              actions: <Widget>[
                TextButton(
                  key: const Key('plan-done-more'),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('再加一组', style: TextStyle(color: Tokens.accent)),
                ),
                TextButton(
                  key: const Key('plan-done-next'),
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(last ? '结束训练' : '下一个',
                      style: const TextStyle(color: Tokens.accent)),
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
              child: Column(
                children: <Widget>[
                  _header(),
                  Expanded(child: _middle()),
                  _doneList(),
                  _restBar(),
                  _switcher(),
                  _hintBar(),
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
      if (c.exercise.id == exerciseId) { unit = c.unit; break; }
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

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, 0),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              key: const Key('back-button'),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.chevron_left, color: Tokens.text2),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Text(
              c.exercise.name.isEmpty ? c.exercise.id : c.exercise.name,
              style: const TextStyle(
                color: Tokens.text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // 换动作（v1.53）：健身房最高频的意外就是"器械被占"。
          // 放在标题右边、与详情入口并排 —— 只在一个不显眼的角落藏一个入口，
          // 等于没有（这一屏上每一个入口都必须是"一眼看到"）。
          if (widget.onSwapExercise != null)
            SizedBox(
              width: 36,
              height: 36,
              child: IconButton(
                key: const Key('swap-exercise'),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.swap_horiz, color: Tokens.text2, size: 20),
                onPressed: () => unawaited(widget.onSwapExercise!()),
              ),
            ),
          // 动作详情入口。**必须看得见**：练到一半想确认"这个动作怎么做"的人
          // 不会去猜哪里能点。没有动作库行时（老调用方/测试）不显示。
          if (_dataFor(c.exercise.id) != null)
            SizedBox(
              width: 36,
              height: 36,
              child: IconButton(
                key: const Key('exercise-info'),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.info_outline, color: Tokens.text2, size: 20),
                onPressed: () => _openDetail(c.exercise.id),
              ),
            ),
          if (c.isOffline)
            Container(
              key: const Key('offline-chip'),
              margin: const EdgeInsets.only(right: Tokens.s2),
              padding: const EdgeInsets.symmetric(horizontal: Tokens.s2, vertical: 3),
              decoration: BoxDecoration(
                color: Tokens.elevated,
                borderRadius: BorderRadius.circular(Tokens.rPill),
              ),
              child: const Text('离线',
                  style: TextStyle(color: Tokens.text3, fontSize: 11, height: 1.2)),
            ),
          Text(
            '第 ${c.setNumber} 组 / 共 ${c.plannedSets} 组',
            key: const Key('set-count'),
            style: const TextStyle(color: Tokens.text3, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ---------- 中部：上次数据 + 大按钮 ----------

  Widget _middle() {
    final s = c.suggestion;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.s5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (s != null)
            Text(
              s.reasonText,
              key: const Key('suggestion-reason'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Tokens.text3, fontSize: 15, height: 1.4),
            ),
          // 距离动作**没有引擎建议**（有氧不给推进建议，见 engine/progression.mjs 第 0.5 步），
          // 所以那一行由**处方**来占：告诉用户今天的目标是什么。
          // 不写这一行的话，这块屏幕上会少掉"今天该练多少"这个信息。
          if (s == null && c.targetDistanceM != null)
            Text(
              '目标 ${c.plannedSets} 组 × ${formatDistanceKm(c.targetDistanceM!)}'
              '（可长按改成你实际练的）',
              key: const Key('plan-target'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Tokens.text3, fontSize: 15, height: 1.4),
            ),
          // 「上次练了多少」（v1.53）：站在器械前最想知道的数字，而原先它只藏在
          // 建议页那条证据链里 —— 训练屏上根本没有。有历史才出现，没有就不编。
          if (c.lastTimeLabelText != null)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.s2),
              child: Text(
                c.lastTimeLabelText!,
                key: const Key('last-time'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Tokens.text3, fontSize: 13, height: 1.3),
              ),
            ),
          const SizedBox(height: Tokens.s4),
          Text(
            // 热身状态是"粘住"的（见 WorkoutController._warmup），
            // 所以标题必须换掉 —— 否则用户看到"第 1 组"却记进去一条热身，
            // 完全不知道发生了什么。
            c.warmup
                ? '热身组'
                : c.holding
                    ? '第 ${c.setNumber} 组 · 计时中'
                    : '第 ${c.setNumber} 组',
            key: const Key('set-number'),
            style: TextStyle(
              color: c.warmup ? Tokens.accent : Tokens.text,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: Tokens.s3),
          GestureDetector(
            key: const Key('big-log-button'),
            behavior: HitTestBehavior.opaque,
            onTap: c.onBigButtonTap,
            onLongPress: c.onLongPress,
            child: Container(
              height: Tokens.hPrimary,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // 距离动作还没设距离时**视觉上也不给点**（控制器里同样挡了一道）：
                // 一次误触会写进"0 公里"的假记录。按钮变灰 + 下面那行提示，
                // 是这块屏幕上唯一"按钮不是主角"的例外。
                color: c.canLog ? Tokens.accent : Tokens.elevated,
                borderRadius: BorderRadius.circular(Tokens.rPill),
              ),
              // ⚠️ `FittedBox`（v1.53）：系统字号调到 1.5× 时，"45 kg × 10" 在
              // 30pt 字号下会把这一行撑爆（实测溢出 163px）。缩放兜底而不是换行 ——
              // 大按钮上的字必须**一眼读完**，两行反而是灾难。
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      c.primaryButtonLabel,
                      key: const Key('button-label'),
                    style: TextStyle(
                      color: c.canLog ? Tokens.accentInk : Tokens.text3,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                    const SizedBox(width: Tokens.s2),
                    Text('✓',
                        style: TextStyle(
                            color: c.canLog ? Tokens.accentInk : Tokens.text3,
                            fontSize: 24,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 已完成组 ----------

  Widget _doneList() {
    final sets = c.loggedSets;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s5, Tokens.s5, 0),
      child: Column(
        key: const Key('done-list'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 撤销的**入口要看得见**（v1.53）。原先"长按任意一行撤销"只写在代码里，
          // 屏幕上没有任何地方提过 —— 误触的人根本不知道有后悔药
          // （真机上问过一次：记错一组之后第一反应是"这下完了"）。
          // 只在真的记过组时出现，空列表上摆一句"长按可撤销"是废话。
          if (sets.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s2),
              child: Text(
                '已完成 ${sets.length} 组 · 长按某一行可撤销',
                key: const Key('done-list-hint'),
                style: const TextStyle(color: Tokens.text3, fontSize: 11, height: 1.2),
              ),
            ),
          for (final r in sets)
            // 长按任意一行撤销这一组（误触的后悔药）。
            // **刻意不用右滑**：整屏已经在响应横向拖拽切动作，而
            // interaction-spec §7 明令禁止训练中做左滑删除这类精细手势 ——
            // 长按是这块屏幕上唯一不打架、也不要求精细操作的入口。
            GestureDetector(
              key: Key('done-set-${r.id}'),
              behavior: HitTestBehavior.opaque,
              onLongPress: () => c.undoSet(r.id),
              child: Padding(
                padding: const EdgeInsets.only(bottom: Tokens.s2),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 16,
                      child: Text('${r.setIndex}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: Tokens.text3, fontSize: 13)),
                    ),
                    const SizedBox(width: Tokens.s3),
                    Text(
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
                        color: r.setType == SetType.warmup
                            ? Tokens.text3
                            : Tokens.text2,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    // RPE 记了就必须显示 —— 只写库不显示就成了用户看不见的隐藏数据
                    if (r.rpe != null) ...<Widget>[
                      const SizedBox(width: Tokens.s2),
                      Text('RPE ${r.rpe!.toInt()}',
                          style: const TextStyle(
                              color: Tokens.text3, fontSize: 12)),
                    ],
                    if (r.setType == SetType.warmup) ...<Widget>[
                      const SizedBox(width: Tokens.s2),
                      const Text('热身',
                          style: TextStyle(color: Tokens.text3, fontSize: 12)),
                    ],
                    const SizedBox(width: Tokens.s2),
                    const Text('✓',
                        style: TextStyle(
                            color: Tokens.accent,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------- 休息条 ----------

  Widget _restBar() {
    return Container(
      key: const Key('rest-bar'),
      margin: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s3, Tokens.s5, Tokens.s3),
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: Tokens.s5),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
        border: Border.all(color: Tokens.line),
      ),
      child: Row(
        children: <Widget>[
          // ⚠️ 左边这组在**大字号**下会被挤（实测 1.5× 溢出 101px）：
          // 它整体 `FittedBox` 缩到放得下，右边三个控件保持原尺寸 ——
          // 那些是手指要点的地方，不许跟着缩（缩了就点不中）。
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: <Widget>[
                  // ⚠️ 这里曾经写过「休息 · 按你的节奏」（提示"这次是按你实际节奏算的"）。
                  // 10.8 清单第 9 条，用户原话：「**【休息 按你的节奏】这几个字有什么存在的
                  // 必要吗**? 或者能不能集成到设置里的休息时间里」—— 说得对：训练屏上那几个字
                  // 既占地方、又是在解释我们内部的算法。**自适应行为照旧保留**，
                  // 解释挪到「设置 → 休息时长」那一行的副标题里（用户自己提的那个去处）。
                  const Text('休息',
                      style: TextStyle(color: Tokens.text3, fontSize: 13)),
                  const SizedBox(width: Tokens.s3),
                  Text(
                    _restText(),
                    key: const Key('rest-time'),
                    style: TextStyle(
                      color: c.restDone ? Tokens.accent : Tokens.text,
                      fontSize: c.restDone ? 17 : 20,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // −15 / +15（2026-10-05，v1.53）：健身房现场"今天想多歇半分钟"几乎必然发生。
          // 只在**真的在休息**时出现 —— 休息已经结束时这两个按钮按了没有任何作用，
          // 摆着就是骗人（`adjustRest` 里也挡了一道）。
          if (c.restRunning) ...<Widget>[
            _restAdjust(key: 'rest-minus', label: '−15', onTap: () => c.adjustRest(-15)),
            _restAdjust(key: 'rest-plus', label: '+15', onTap: () => c.adjustRest(15)),
            const SizedBox(width: Tokens.s1),
          ],
          _restAdjust(key: 'skip-rest', label: '跳过', onTap: c.skipRest),
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
          height: 44,
          constraints: const BoxConstraints(minWidth: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s2),
          child: Text(label,
              style: const TextStyle(
                  color: Tokens.text2, fontSize: 14, fontWeight: FontWeight.w600)),
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
        border: Border(top: BorderSide(color: Tokens.line)),
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
          Text(
            '${s.index + 1} / ${s.length}',
            key: const Key('exercise-position'),
            style: const TextStyle(color: Tokens.text3, fontSize: 13),
          ),
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
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _hintBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s5, 0, Tokens.s5, Tokens.s4),
      child: Text(
        c.hint ??
            (c.holding
                // 计时中：告诉用户"现在这一下会记下多少"，以及"什么时候会震"
                ? '计时中 · 点大按钮记下这一组（到 ${c.reps} 秒震一下）'
                : c.isDistance
                // 距离动作先说"怎么设距离" —— 首次进来它是 0，按钮是灰的
                ? '长按按钮设距离与时长 · 设好之后点一下记一组'
                : '点大按钮记录一组 · 长按可以改重量'),
        key: const Key('workout-hint'),
        textAlign: TextAlign.center,
        style: const TextStyle(color: Tokens.text3, fontSize: 11, height: 1.3),
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
            child: Container(color: const Color(0x9E000000)),
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
                borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.rSheet)),
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
                      value: trimNumber(round1(toDisplayWeight(c.weightKg, c.unit))),
                      unit: c.unit.wire,
                      step: trimNumber(c.weightStep),
                      keyMinus: 'step-weight-down',
                      keyPlus: 'step-weight-up',
                      onMinus: () => c.onStepper(deltaWeight: -c.weightStep),
                      onPlus: () => c.onStepper(deltaWeight: c.weightStep),
                    ),
                  if (c.isDistance && !c.isBodyweight) const SizedBox(height: Tokens.s5),
                  if (c.isDistance)
                    _stepperRow(
                      value: trimNumber(round1(c.distanceM)),
                      unit: '米',
                      step: '${c.distanceStepM.toInt()}',
                      keyMinus: 'step-distance-down',
                      keyPlus: 'step-distance-up',
                      onMinus: () => c.onStepper(deltaDistanceM: -c.distanceStepM),
                      onPlus: () => c.onStepper(deltaDistanceM: c.distanceStepM),
                    ),
                  if (!c.isDistance)
                    _stepperRow(
                      // 步进值按显示单位展示；底层量与步长仍是 kg
                      // （lb 原生步进会让重量脱离杠铃片网格，见 core/units.dart）
                      value: c.isBodyweight
                          ? '自重'
                          : trimNumber(round1(toDisplayWeight(c.weightKg, c.unit))),
                      // 辅助自重的单位里必须带"助力"：这个数越大越轻松
                      unit: c.isBodyweight
                          ? ''
                          : (c.isAssisted ? '${c.unit.wire} 助力' : c.unit.wire),
                      step: trimNumber(c.weightStep),
                      keyMinus: 'step-weight-down',
                      keyPlus: 'step-weight-up',
                      onMinus: () => c.onStepper(deltaWeight: -c.weightStep),
                      onPlus: () => c.onStepper(deltaWeight: c.weightStep),
                    ),
                  const SizedBox(height: Tokens.s5),
                  _stepperRow(
                    // 距离动作把秒念成 30:00（1800 秒没人这么念），其余照旧
                    value: c.isDistance
                        ? formatDurationHms(c.reps)
                        : '${c.reps}',
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
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
                        foregroundColor: c.warmup ? Tokens.accent : Tokens.text3,
                        padding: const EdgeInsets.symmetric(
                          horizontal: Tokens.s3,
                          vertical: Tokens.s2,
                        ),
                      ),
                      child: Text(
                        c.warmup ? '✓ 下一组记为热身' : '热身组',
                        style: const TextStyle(fontSize: 14),
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
                            style: TextStyle(color: Tokens.text3, fontSize: 13)),
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
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
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
            border: Border.all(color: active ? Tokens.accent : Tokens.lineStrong),
            borderRadius: BorderRadius.circular(Tokens.rPill),
          ),
          child: Text(
            '${value.toInt()}',
            style: TextStyle(
              color: active ? Tokens.accentInk : Tokens.text3,
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
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
  }) {
    return Row(
      children: <Widget>[
        Text(value, style: Tokens.display(36, weight: 700, letterSpacing: -0.5)),
        if (unit.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: Tokens.s1),
            child: Text(unit,
                style: const TextStyle(
                    color: Tokens.text3, fontSize: 17, fontWeight: FontWeight.w600)),
          ),
        const Spacer(),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.rCard)),
          padding: EdgeInsets.zero,
        ),
        onPressed: onPressed,
        child: Text(label,
            style: const TextStyle(
                color: Tokens.text, fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
