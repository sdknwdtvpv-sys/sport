/// 练了么 · 周期化计划 v1 页面（Ultra 权益 10）
///
/// 口径唯一出处：`docs/plan-periodization-2026-11-06.md`。这一屏只做四件事：
/// 建计划（4/6/8 周 × 3/4 练）、看本周课表、从某一天开练、导入/导出 JSON。
/// **加重/完成判定一行都不在这里** —— 在 `domain/periodization.dart` 的纯函数里。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/glass_overlay.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import '../../data/period_plan_repository.dart';
import '../../domain/models.dart';
import '../../domain/periodization.dart';
import '../today/today_planner.dart';

class PeriodizationScreen extends StatefulWidget {
  const PeriodizationScreen({
    super.key,
    required this.plans,
    required this.planner,
    required this.exercises,
    required this.store,
    this.unit = WeightUnit.kg,
    this.now,
  });

  final PeriodPlanRepository plans;
  final TodayPlanner planner;
  final ExerciseRepository exercises;
  final LocalStore store;
  final WeightUnit unit;
  final DateTime Function()? now;

  @override
  State<PeriodizationScreen> createState() => _PeriodizationScreenState();
}

class _PeriodizationScreenState extends State<PeriodizationScreen> {
  PeriodPlanSnapshot? _plan;
  Map<String, String> _names = const <String, String>{};
  bool _loading = true;
  bool _busy = false;
  int _weeks = 4;
  int _days = 3;

  DateTime get _today => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<ExerciseData> rows = await widget.exercises.search(limit: 1000);
    PeriodPlanSnapshot? plan = await widget.plans.activePlan();
    if (plan != null && plan.status == PeriodPlanStatus.active) {
      plan = await widget.plans.refreshProgress(plan, await widget.store.allSets());
    }
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _names = <String, String>{for (final ExerciseData r in rows) r.id: r.name};
      _loading = false;
    });
  }

  /// 建计划：第 1 周模板从 `TodayPlanner` 快照（上肢/下肢交替），后续周由纯函数展开。
  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final List<PeriodSessionSpec> base = <PeriodSessionSpec>[];
      for (int day = 1; day <= _days; day += 1) {
        final TrainingDay trainingDay = day.isOdd ? TrainingDay.upper : TrainingDay.lower;
        final List<PlannedExercise> picked = await widget.planner.planToday(
          day: trainingDay,
          count: 6,
          unit: widget.unit,
        );
        for (int i = 0; i < picked.length; i += 1) {
          final PlannedExercise p = picked[i];
          final Suggestion? s = p.suggestion;
          final double? weight = (s != null && !s.isBodyweight)
              ? s.weightKg
              : (s == null ? p.exercise.defaultWeightKg : null);
          base.add(PeriodSessionSpec(
            week: 1,
            day: day,
            position: i,
            exerciseId: p.exercise.id,
            targetSets: p.plan.targetSets,
            repsLow: p.plan.targetRepsLow,
            repsHigh: p.plan.targetRepsHigh,
            targetWeightKg: weight,
          ));
        }
      }
      if (base.isEmpty) {
        _toast('动作库还没准备好，稍后再试');
        return;
      }
      await widget.plans.createPlan(
        name: '$_weeks 周计划 · 每周 $_days 练',
        weeks: _weeks,
        daysPerWeek: _days,
        startDate: DateTime(_today.year, _today.month, _today.day),
        baseSessions: base,
      );
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startDay(int day) async {
    final PeriodPlanSnapshot? plan = _plan;
    if (plan == null || _busy) return;
    final List<PeriodSessionSpec> sessions = plan
        .sessionsOfWeek(plan.currentWeek)
        .where((PeriodSessionSpec s) => s.day == day)
        .toList(growable: false);
    if (sessions.isEmpty) return;
    setState(() => _busy = true);
    try {
      final List<PlannedExercise> planned = await widget.planner.planFromRoutine(
        entries: <RoutineEntry>[
          for (final PeriodSessionSpec s in sessions)
            RoutineEntry(
              exerciseId: s.exerciseId,
              plan: PlanTarget(
                targetSets: s.targetSets,
                targetRepsLow: s.repsLow,
                targetRepsHigh: s.repsHigh,
                targetWeightKg: s.targetWeightKg,
              ),
            ),
        ],
        unit: widget.unit,
      );
      if (!mounted) return;
      Navigator.of(context).pop<List<PlannedExercise>>(planned);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final PeriodPlanSnapshot? plan = _plan;
    if (plan == null) return;
    await Clipboard.setData(ClipboardData(text: encodePeriodPlanJson(plan)));
    _toast('已复制计划 JSON 到剪贴板');
  }

  Future<void> _import() async {
    final TextEditingController input = TextEditingController();
    final String? text = await showAppDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: Tokens.elevated,
        title: const Text('导入计划 JSON', style: TextStyle(color: Tokens.text)),
        content: TextField(
          key: const Key('period-import-field'),
          controller: input,
          maxLines: 6,
          style: const TextStyle(color: Tokens.text),
          decoration: const InputDecoration(hintText: '把导出的 JSON 粘进来'),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('period-import-cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消', style: TextStyle(color: Tokens.text2)),
          ),
          TextButton(
            key: const Key('period-import-ok'),
            onPressed: () => Navigator.of(ctx).pop(input.text),
            child: const Text('导入', style: TextStyle(color: Tokens.accentText)),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    final PeriodPlanParseResult parsed = parsePeriodPlanJson(text);
    if (!parsed.ok) {
      _toast(parsed.error ?? '计划文件读不出来');
      return;
    }
    await widget.plans.importPlan(parsed.plan!);
    await _load();
    _toast('已导入「${parsed.plan!.name}」');
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Tokens.elevated),
    );
  }

  @override
  Widget build(BuildContext context) {
    final PeriodPlanSnapshot? plan = _plan;
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, 0),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton(
                      key: const Key('period-back'),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.chevron_left, color: Tokens.text2),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  const Expanded(
                    child: Text('周期计划',
                        style: TextStyle(
                            color: Tokens.text,
                            fontSize: Tokens.fsHeadline,
                            fontWeight: Tokens.fwBold)),
                  ),
                  if (_busy)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Tokens.accent),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s8),
                children: <Widget>[
                  if (_loading)
                    const Center(
                        child: Padding(
                            padding: EdgeInsets.all(Tokens.s5),
                            child: CircularProgressIndicator()))
                  else if (plan == null)
                    ..._createView()
                  else
                    ..._planView(plan),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _createView() => <Widget>[
        _card(<Widget>[
          const Text('还没有周期计划',
              style: TextStyle(color: Tokens.text, fontSize: Tokens.fsSub, fontWeight: Tokens.fwBold)),
          const SizedBox(height: Tokens.s2),
          const Text(
            '选一个周期长度和每周练几天。计划会按周自动加重（有重量的动作 +2.5%，'
            '每第 4 周 deload -10%）；自重/按时长动作不编重量。',
            style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap, height: Tokens.lhNormal),
          ),
          const SizedBox(height: Tokens.s4),
          _choiceRow('周期', <int>[4, 6, 8], _weeks, (int v) => setState(() => _weeks = v), 'period-weeks'),
          const SizedBox(height: Tokens.s3),
          _choiceRow('每周练', <int>[3, 4], _days, (int v) => setState(() => _days = v), 'period-days'),
          const SizedBox(height: Tokens.s4),
          FilledButton(
            key: const Key('period-create'),
            onPressed: _busy ? null : _create,
            style: FilledButton.styleFrom(
              backgroundColor: Tokens.accent,
              foregroundColor: Tokens.accentInk,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.rPill)),
            ),
            child: const Text('创建计划'),
          ),
          const SizedBox(height: Tokens.s3),
          TextButton(
            key: const Key('period-import'),
            onPressed: _busy ? null : _import,
            child: const Text('导入计划 JSON', style: TextStyle(color: Tokens.accentText)),
          ),
        ]),
      ];

  Widget _choiceRow(String label, List<int> values, int current, ValueChanged<int> onPick, String keyPrefix) =>
      Row(
        children: <Widget>[
          SizedBox(
            width: 56,
            child: Text(label, style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap)),
          ),
          for (final int v in values)
            Padding(
              padding: const EdgeInsets.only(right: Tokens.s2),
              child: ChoiceChip(
                key: Key('$keyPrefix-$v'),
                label: Text('$v',
                    style: TextStyle(color: v == current ? Tokens.accentInk : Tokens.text2)),
                selected: v == current,
                onSelected: (_) => onPick(v),
              ),
            ),
        ],
      );

  List<Widget> _planView(PeriodPlanSnapshot plan) {
    final bool active = plan.status == PeriodPlanStatus.active;
    final List<PeriodSessionSpec> week = plan.sessionsOfWeek(plan.currentWeek);
    final Map<int, List<PeriodSessionSpec>> byDay = <int, List<PeriodSessionSpec>>{};
    for (final PeriodSessionSpec s in week) {
      byDay.putIfAbsent(s.day, () => <PeriodSessionSpec>[]).add(s);
    }
    final bool deload = isDeloadWeek(plan.currentWeek);
    return <Widget>[
      _card(<Widget>[
        Text(plan.name,
            key: const Key('period-name'),
            style: const TextStyle(color: Tokens.text, fontSize: Tokens.fsSub, fontWeight: Tokens.fwBold)),
        const SizedBox(height: Tokens.s2),
        Text(
          '第 ${plan.currentWeek}/${plan.weeks} 周'
          '${deload ? ' · deload（-10%）' : ''}'
          ' · ${active ? '进行中' : (plan.status == PeriodPlanStatus.completed ? '已完成' : '已归档')}',
          key: const Key('period-status'),
          style: const TextStyle(color: Tokens.text2, fontSize: Tokens.fsCap, height: Tokens.lhNormal),
        ),
        const SizedBox(height: Tokens.s3),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                key: const Key('period-export'),
                onPressed: _export,
                child: const Text('导出 JSON'),
              ),
            ),
            const SizedBox(width: Tokens.s3),
            Expanded(
              child: OutlinedButton(
                key: const Key('period-new'),
                onPressed: _busy ? null : _create,
                child: const Text('换一份计划'),
              ),
            ),
          ],
        ),
      ]),
      const SizedBox(height: Tokens.s4),
      if (week.isEmpty)
        _card(<Widget>[
          const Text('这一周没有课表',
              style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsSub)),
        ])
      else
        for (final MapEntry<int, List<PeriodSessionSpec>> e in byDay.entries) ...<Widget>[
          _card(<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('第 ${e.key} 天 · ${e.key.isOdd ? '上肢' : '下肢'}',
                      style: const TextStyle(
                          color: Tokens.text, fontSize: Tokens.fsSub, fontWeight: Tokens.fwBold)),
                ),
                TextButton(
                  key: Key('period-start-${e.key}'),
                  onPressed: _busy ? null : () => _startDay(e.key),
                  child: const Text('从这一天开练', style: TextStyle(color: Tokens.accentText)),
                ),
              ],
            ),
            const SizedBox(height: Tokens.s2),
            for (final PeriodSessionSpec s in e.value)
              Padding(
                padding: const EdgeInsets.only(bottom: Tokens.s1),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(_names[s.exerciseId] ?? s.exerciseId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Tokens.text2, fontSize: Tokens.fsSub)),
                    ),
                    Text(_targetLabel(s),
                        style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap)),
                  ],
                ),
              ),
          ]),
          const SizedBox(height: Tokens.s3),
        ],
    ];
  }

  String _targetLabel(PeriodSessionSpec s) {
    final String reps = s.repsLow == s.repsHigh ? '${s.repsLow}' : '${s.repsLow}–${s.repsHigh}';
    final String weight = s.targetWeightKg == null
        ? '自重'
        : formatWeight(s.targetWeightKg, widget.unit);
    return '${s.targetSets} 组 × $reps · $weight';
  }

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(Tokens.s5),
        decoration: BoxDecoration(
          color: Tokens.surface,
          borderRadius: BorderRadius.circular(Tokens.rCard),
          border: Border.all(color: Tokens.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}
