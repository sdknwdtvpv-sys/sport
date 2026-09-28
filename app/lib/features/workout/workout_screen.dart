/// 练了么 · 训练中主屏（S4）+ 修改弹层（S5）
///
/// 对应 `docs/interaction-spec.md` §5–§8。
///
/// 一个刻意的实现选择：修改弹层用 Stack 内的自绘层，而不是 `showModalBottomSheet`。
/// 理由是规格里那条硬要求——「长按不误记」必须有 widget 测试守着，
/// 自绘层可以在同一棵 widget 树里直接断言，不需要处理路由与动画时序。
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/units.dart';
import '../../domain/models.dart';
import 'workout_controller.dart';
import 'workout_session.dart';

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key, required this.session});

  /// 一次训练里的全部动作（S6）。单个动作就用 `WorkoutSession.single(c)`。
  ///
  /// **会话与它内部的控制器都由调用方持有并负责 dispose** ——
  /// 这样测试可以在页面销毁后继续断言控制器状态。
  final WorkoutSession session;

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  /// 当前动作。切动作时这个 getter 会指向另一个控制器 ——
  /// 所以下面所有 `c.xxx` 都自动跟着走，不需要各自处理切换。
  WorkoutController get c => widget.session.current;

  @override
  void initState() {
    super.initState();
    // 只听会话：它会转发内部每个控制器的通知，切动作也是它通知
    widget.session.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onChange);
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
          const SizedBox(height: Tokens.s4),
          Text(
            // 热身状态是"粘住"的（见 WorkoutController._warmup），
            // 所以标题必须换掉 —— 否则用户看到"第 1 组"却记进去一条热身，
            // 完全不知道发生了什么。
            c.warmup ? '热身组' : '第 ${c.setNumber} 组',
            key: const Key('set-number'),
            style: TextStyle(
              color: c.warmup ? Tokens.volt : Tokens.text,
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
                color: Tokens.volt,
                borderRadius: BorderRadius.circular(Tokens.rPill),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    c.primaryButtonLabel,
                    key: const Key('button-label'),
                    style: const TextStyle(
                      color: Tokens.voltInk,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: Tokens.s2),
                  const Text('✓',
                      style: TextStyle(
                          color: Tokens.voltInk, fontSize: 24, fontWeight: FontWeight.w700)),
                ],
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
          for (final r in sets)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s2),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 16,
                    child: Text('${r.setIndex}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: Tokens.text3, fontSize: 13)),
                  ),
                  const SizedBox(width: Tokens.s3),
                  Text(
                    r.weightKg == null
                        ? '自重 × ${r.reps}'
                        : '${formatWeight(r.weightKg, c.unit)} × ${r.reps}',
                    style: TextStyle(
                      // 热身组用次级色：和正式组混在一起分不出来，用户就不知道
                      // 哪些算进了计划进度
                      color: r.setType == SetType.warmup ? Tokens.text3 : Tokens.text2,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // RPE 记了就必须显示 —— 只写库不显示就成了用户看不见的隐藏数据
                  if (r.rpe != null) ...<Widget>[
                    const SizedBox(width: Tokens.s2),
                    Text('RPE ${r.rpe!.toInt()}',
                        style: const TextStyle(color: Tokens.text3, fontSize: 12)),
                  ],
                  if (r.setType == SetType.warmup) ...<Widget>[
                    const SizedBox(width: Tokens.s2),
                    const Text('热身',
                        style: TextStyle(color: Tokens.text3, fontSize: 12)),
                  ],
                  const SizedBox(width: Tokens.s2),
                  const Text('✓',
                      style: TextStyle(
                          color: Tokens.volt, fontSize: 15, fontWeight: FontWeight.w700)),
                ],
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
          const Text('休息', style: TextStyle(color: Tokens.text3, fontSize: 13)),
          const SizedBox(width: Tokens.s3),
          Text(
            _restText(),
            key: const Key('rest-time'),
            style: TextStyle(
              color: c.restDone ? Tokens.volt : Tokens.text,
              fontSize: c.restDone ? 17 : 20,
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          TextButton(
            key: const Key('skip-rest'),
            onPressed: c.skipRest,
            child: const Text('跳过', style: TextStyle(color: Tokens.text2, fontSize: 13)),
          ),
        ],
      ),
    );
  }

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
        c.hint ?? '点大按钮记录一组 · 长按可以改重量',
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
                  _stepperRow(
                    // 步进值按显示单位展示；底层量与步长仍是 kg
                    // （lb 原生步进会让重量脱离杠铃片网格，见 core/units.dart）
                    value: c.isBodyweight
                        ? '自重'
                        : trimNumber(round1(toDisplayWeight(c.weightKg, c.unit))),
                    unit: c.isBodyweight ? '' : c.unit.wire,
                    keyMinus: 'step-weight-down',
                    keyPlus: 'step-weight-up',
                    onMinus: () => c.onStepper(deltaWeight: -2.5),
                    onPlus: () => c.onStepper(deltaWeight: 2.5),
                  ),
                  const SizedBox(height: Tokens.s5),
                  _stepperRow(
                    value: '${c.reps}',
                    unit: '次',
                    keyMinus: 'step-reps-down',
                    keyPlus: 'step-reps-up',
                    onMinus: () => c.onStepper(deltaReps: -1),
                    onPlus: () => c.onStepper(deltaReps: 1),
                  ),
                  const SizedBox(height: Tokens.s5),
                  // 热身组：规格要求「弱化样式存在、不主动教」，所以做成一个
                  // 普通文字按钮而不是显眼开关 —— 主按钮才是这一屏唯一的主角。
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const Key('sheet-warmup'),
                      onPressed: c.toggleWarmup,
                      style: TextButton.styleFrom(
                        foregroundColor: c.warmup ? Tokens.volt : Tokens.text3,
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
                        backgroundColor: Tokens.volt,
                        foregroundColor: Tokens.voltInk,
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
            color: active ? Tokens.volt : Colors.transparent,
            border: Border.all(color: active ? Tokens.volt : Tokens.lineStrong),
            borderRadius: BorderRadius.circular(Tokens.rPill),
          ),
          child: Text(
            '${value.toInt()}',
            style: TextStyle(
              color: active ? Tokens.voltInk : Tokens.text3,
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
    required String keyMinus,
    required String keyPlus,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    return Row(
      children: <Widget>[
        Text(value,
            style: const TextStyle(
                color: Tokens.text,
                fontSize: 36,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5)),
        if (unit.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: Tokens.s1),
            child: Text(unit,
                style: const TextStyle(
                    color: Tokens.text3, fontSize: 17, fontWeight: FontWeight.w600)),
          ),
        const Spacer(),
        _stepButton(keyMinus, '−2.5', onMinus),
        const SizedBox(width: Tokens.s2),
        _stepButton(keyPlus, '+2.5', onPlus),
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
