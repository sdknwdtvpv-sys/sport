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
import 'workout_controller.dart';

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key, required this.controller});

  /// 由调用方持有并负责 dispose —— 这样测试可以在页面销毁后继续断言控制器状态。
  final WorkoutController controller;

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  WorkoutController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    super.dispose();
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
            Column(
              children: <Widget>[
                _header(),
                Expanded(child: _middle()),
                _doneList(),
                _restBar(),
                _switcher(),
                _hintBar(),
              ],
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
            '第 ${c.setNumber} 组',
            key: const Key('set-number'),
            style: const TextStyle(
              color: Tokens.text,
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
                        : '${r.weightKg}kg × ${r.reps}',
                    style: const TextStyle(
                        color: Tokens.text2, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
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

  Widget _switcher() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: Tokens.s3),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Tokens.line)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text('‹ 上一个动作', style: TextStyle(color: Tokens.text2, fontSize: 15)),
          Text('动作 1 / 1', style: TextStyle(color: Tokens.text3, fontSize: 13)),
          Text('下一个动作 ›', style: TextStyle(color: Tokens.text2, fontSize: 15)),
        ],
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
                    value: c.isBodyweight ? '自重' : '${c.weightKg}',
                    unit: c.isBodyweight ? '' : 'kg',
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
