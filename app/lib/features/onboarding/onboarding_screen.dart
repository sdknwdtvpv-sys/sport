/// 练了么 · S13 首次引导（**非阻塞版**）
///
/// 三步：目标 → 每周几天 → 第一份计划。**全程可跳过**，
/// 而且它根本不在启动路径上 —— 入口是 S1 空态里的一个可选链接。
///
/// 最后一步的主按钮是「就用这个，开始练」：引导**以开始训练收尾**，
/// 这样它就不是"又一个挡在训练前面的流程"，而是"帮你更快开始"。
/// 次按钮「先这样」只把计划存下来。
library;

import 'package:flutter/material.dart';

import '../../analytics/analytics.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import '../../data/exercise_repository.dart';
import '../../data/profile_repository.dart';
import '../../data/routine_repository.dart';
import '../../domain/models.dart';
import '../today/today_planner.dart';
import 'onboarding.dart';

/// 引导结束时的产出。计划已经落库（存成一份 S11 的计划模板）。
class OnboardingResult {
  const OnboardingResult({required this.plan, required this.startNow});

  final List<PlannedExercise> plan;

  /// 用户点的是「就用这个，开始练」还是「先这样」
  final bool startNow;
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.planner,
    required this.profile,
    required this.routines,
    required this.exercises,
    this.unit = WeightUnit.kg,
    this.analytics,
  });

  final TodayPlanner planner;
  final ProfileRepository profile;
  final RoutineRepository routines;
  final ExerciseRepository exercises;
  final WeightUnit unit;

  /// 埋点（可选）。上报 `onboarding_step` —— 用来验证"≤3 步且可跳过"这条规格：
  /// 现在是 3 步，但没人知道用户在第几步走了、跳过了哪一步。
  final Analytics? analytics;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  TrainingGoal? _goal;
  int? _days;
  List<PlannedExercise> _plan = const <PlannedExercise>[];
  bool _loading = false;

  PlanTarget get _target => planForGoal(_goal ?? TrainingGoal.maintain);

  Future<void> _preview() async {
    setState(() => _loading = true);
    final int n = exercisesPerSession(_days ?? 3);
    final List<PlannedExercise> base =
        await widget.planner.planToday(count: n, unit: widget.unit);
    if (!mounted) return;
    setState(() {
      // 用目标对应的处方替换掉默认处方 —— 否则"增肌"和"力量"生成出来一模一样
      _plan = <PlannedExercise>[
        for (final PlannedExercise p in base)
          PlannedExercise(
            exercise: p.exercise,
            plan: _target,
            suggestion: p.suggestion,
            unit: widget.unit,
          ),
      ];
      _loading = false;
      _step = 2;
    });
  }

  /// 离开某一步时上报（[skipped] = 是点「跳过」走的）。
  ///
  /// `_step` 在 State 上，所以这个方法也必须在这里 —— 放 widget 类里会拿不到它
  /// （这轮我已经在 WorkoutScreen 上犯过一次同样的错）。
  void _leaveStep({required bool skipped}) {
    widget.analytics?.track('onboarding_step', <String, Object?>{
      'step_index': _step,
      'skipped': skipped,
    });
  }

  /// 落库：目标 + 频率写进档案，计划写进 S11 的计划模板。
  Future<void> _commit({required bool startNow}) async {
    final TrainingGoal goal = _goal ?? TrainingGoal.maintain;
    final int days = _days ?? 3;

    await widget.profile.setOnboarding(
      goalWire: goal.wire,
      weeklyFrequency: days,
    );

    final RoutineData routine = await widget.routines.create(planNameFor(goal));
    for (final PlannedExercise p in _plan) {
      await widget.routines.addItem(
        routine.id,
        p.exercise.id,
        targetSets: p.plan.targetSets,
        targetRepsLow: p.plan.targetRepsLow,
        targetRepsHigh: p.plan.targetRepsHigh,
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop(
      OnboardingResult(plan: _plan, startNow: startNow),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, 0),
              child: Row(
                children: <Widget>[
                  // 返回：第 2/3 步回上一步；第 1 步就是"算了，回首页"。
                  // 2026-10-01 真机走查发现：这个全屏页原先**只有「跳过」**，
                  // 用户想退回去只能点它 —— 而"跳过"意味着放弃整个向导，不是"返回"。
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton(
                      key: const Key('onboarding-back'),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.chevron_left, color: Tokens.text2),
                      onPressed: () {
                        if (_step == 0) {
                          _leaveStep(skipped: true);
                          Navigator.of(context).pop();
                          return;
                        }
                        setState(() => _step -= 1);
                      },
                    ),
                  ),
                  // 标题**不带人称**：首页那个入口是用户口气（「帮我定个计划」），
                  // 页面标题再写「帮你定个计划」就变成两种人称打架（2026-10-01 真机走查）。
                  // 中性的「定个计划」两边都顺，也不用改那句已经定稿的入口文案。
                  const Expanded(
                    child: Text('定个计划',
                        style: TextStyle(
                            color: Tokens.text, fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    key: const Key('onboarding-skip'),
                    style: TextButton.styleFrom(foregroundColor: Tokens.text3),
                    // 跳过 = 什么都不写，也不留痕（不记"已完成"）。
                    // 但要上报**在哪一步跳的** —— "可跳过"这条规格的验证全靠它。
                    onPressed: () {
                      _leaveStep(skipped: true);
                      Navigator.of(context).pop();
                    },
                    child: const Text('跳过', style: TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ),
            _progress(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _progress() => Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s3, Tokens.s5, 0),
        child: Row(
          children: <Widget>[
            for (int i = 0; i < 3; i++) ...<Widget>[
              Expanded(
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: i <= _step ? Tokens.volt : Tokens.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (i < 2) const SizedBox(width: Tokens.s1),
            ],
          ],
        ),
      );

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return switch (_step) {
      0 => _goalStep(),
      1 => _daysStep(),
      _ => _planStep(),
    };
  }

  // ---------- 第 1 步：目标 ----------

  Widget _goalStep() => _step1Frame(
        title: '你的目标是？',
        subtitle: '只影响建议的组数与次数，随时能改。',
        children: <Widget>[
          for (final TrainingGoal g in TrainingGoal.values)
            _bigChoice(
              key: 'goal-${g.wire}',
              label: g.label,
              detail: _goalDetail(g),
              active: _goal == g,
              onTap: () => setState(() => _goal = g),
            ),
          const SizedBox(height: Tokens.s5),
          _nextButton(
            key: 'onboarding-next-1',
            enabled: _goal != null,
            onTap: () {
              _leaveStep(skipped: false);
              setState(() => _step = 1);
            },
          ),
        ],
      );

  String _goalDetail(TrainingGoal g) {
    final PlanTarget t = planForGoal(g);
    return '${t.targetSets} 组 × ${t.targetRepsLow}–${t.targetRepsHigh} 次';
  }

  // ---------- 第 2 步：每周几天 ----------

  Widget _daysStep() => _step1Frame(
        title: '一周练几天？',
        subtitle: '决定每次安排几个动作 —— 练得少，每次就多覆盖几个部位。',
        children: <Widget>[
          Wrap(
            spacing: Tokens.s2,
            runSpacing: Tokens.s2,
            children: <Widget>[
              for (final int d in kDaysChoices)
                GestureDetector(
                  key: Key('days-$d'),
                  onTap: () => setState(() => _days = d),
                  child: Container(
                    alignment: Alignment.center,
                    width: 64,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _days == d ? Tokens.volt : Tokens.surface,
                      borderRadius: BorderRadius.circular(Tokens.rCard),
                    ),
                    child: Text('$d 天',
                        style: TextStyle(
                          color: _days == d ? Tokens.voltInk : Tokens.text2,
                          fontSize: 16,
                          fontWeight: _days == d ? FontWeight.w700 : FontWeight.w400,
                        )),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Tokens.s4),
          Text(
            _days == null ? '选一个' : daysHint(_days!),
            style: const TextStyle(color: Tokens.text3, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: Tokens.s5),
          _nextButton(
            key: 'onboarding-next-2',
            label: '看看我的计划',
            enabled: _days != null,
            onTap: () {
              _leaveStep(skipped: false);
              _preview();
            },
          ),
        ],
      );

  // ---------- 第 3 步：第一份计划 ----------

  Widget _planStep() => Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s4),
              children: <Widget>[
                const Text('这是你的第一份计划',
                    style: TextStyle(
                        color: Tokens.text, fontSize: 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: Tokens.s2),
                Text(
                  '${_goal?.label ?? ''} · 一周 ${_days ?? 3} 天 · '
                  '${_target.targetSets} 组 × ${_target.targetRepsLow}–${_target.targetRepsHigh} 次',
                  style: const TextStyle(color: Tokens.text3, fontSize: 13),
                ),
                const SizedBox(height: Tokens.s4),
                for (final PlannedExercise p in _plan)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Tokens.s2),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(p.exercise.name,
                              style: const TextStyle(
                                  color: Tokens.text, fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Text(
                          p.suggestion?.isBodyweight ?? true
                              ? '自重'
                              : formatWeight(p.suggestion?.weightKg, widget.unit),
                          style: const TextStyle(
                              color: Tokens.text2, fontSize: 15,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: Tokens.s4),
                const Text(
                  '计划已经存下来了。之后可以在「今天练什么」里开始，'
                  '也能在「我的计划」里逐项改。',
                  style: TextStyle(color: Tokens.text3, fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Tokens.s5, 0, Tokens.s5, Tokens.s4),
            child: Column(
              children: <Widget>[
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: FilledButton(
                    key: const Key('onboarding-start-now'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Tokens.volt,
                      foregroundColor: Tokens.voltInk,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Tokens.rPill),
                      ),
                    ),
                    // 引导以"开始训练"收尾，而不是以"设置完成"收尾
                    onPressed: _plan.isEmpty
                        ? null
                        : () => _commit(startNow: true),
                    child: const Text('就用这个，开始练',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                ),
                TextButton(
                  key: const Key('onboarding-just-save'),
                  onPressed: _plan.isEmpty
                      ? null
                      : () => _commit(startNow: false),
                  child: const Text('先这样，回头再练',
                      style: TextStyle(color: Tokens.text2, fontSize: 14)),
                ),
              ],
            ),
          ),
        ],
      );

  // ---------- 小部件 ----------

  Widget _step1Frame({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) =>
      ListView(
        padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s6),
        children: <Widget>[
          Text(title,
              style: const TextStyle(
                  color: Tokens.text, fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: Tokens.s2),
          Text(subtitle,
              style: const TextStyle(color: Tokens.text3, fontSize: 13, height: 1.5)),
          const SizedBox(height: Tokens.s5),
          ...children,
        ],
      );

  Widget _bigChoice({
    required String key,
    required String label,
    required String detail,
    required bool active,
    required VoidCallback onTap,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: Tokens.s2),
        child: GestureDetector(
          key: Key(key),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(Tokens.s4),
            decoration: BoxDecoration(
              color: active ? Tokens.volt : Tokens.surface,
              borderRadius: BorderRadius.circular(Tokens.rCard),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                        color: active ? Tokens.voltInk : Tokens.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      )),
                ),
                Text(detail,
                    style: TextStyle(
                      color: active ? Tokens.voltInk : Tokens.text3,
                      fontSize: 13,
                    )),
              ],
            ),
          ),
        ),
      );

  Widget _nextButton({
    required String key,
    required bool enabled,
    required VoidCallback onTap,
    String label = '下一步',
  }) =>
      SizedBox(
        width: double.infinity,
        height: 64,
        child: FilledButton(
          key: Key(key),
          style: FilledButton.styleFrom(
            backgroundColor: enabled ? Tokens.volt : Tokens.line,
            foregroundColor: enabled ? Tokens.voltInk : Tokens.text3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Tokens.rPill),
            ),
          ),
          onPressed: enabled ? onTap : null,
          child: Text(label,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ),
      );
}
