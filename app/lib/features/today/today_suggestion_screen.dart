/// 练了么 · S2 今日建议卡
///
/// 对应 `docs/screens.md` S2。这是"降低门槛"的主要卖点：
/// **用户连计划都不用搭，打开就知道今天练什么、每个动作该上多少重量。**
///
/// 页面本身不含任何规则 —— 轮转与建议全在 `today_planner.dart` 里，
/// 有 13 项测试锁着。这里只负责把结果画出来并返回用户的选择。
///
/// 与 `docs/screens.md` 的一处偏离：规格里「换一批」在标题栏和底部各有一个入口，
/// 这里只保留底部一个 —— 同一个动作出现两次是极简产品最该避免的冗余。
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/units.dart';
import '../../data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import '../../domain/models.dart';
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import '../../data/routine_repository.dart';
import '../routine/routine_screen.dart';
import 'today_planner.dart';

/// 用户在这一屏做出的选择，回传给调用方（main.dart）决定接下来怎么练。
enum TodayChoice {
  /// 按建议练
  startPlanned,

  /// 我要自己挑
  pickMyself,
}

class TodayResult {
  const TodayResult(this.choice, [this.plan = const <PlannedExercise>[]]);

  final TodayChoice choice;
  final List<PlannedExercise> plan;
}

class TodaySuggestionScreen extends StatefulWidget {
  const TodaySuggestionScreen({
    super.key,
    required this.planner,
    this.unit = WeightUnit.kg,
    this.routines,
    this.exercises,
    this.store,
  });

  final TodayPlanner planner;

  /// 本地库。**传下去只为一件事**：计划编辑器里的「加动作」也会开选择器，
  /// 而选择器的「置顶 / 最近做过」两个分区要靠它 —— 不传的话同一个页面
  /// 从训练流程进来有、从计划进来没有（2026-10-04 顺手补的一处不一致）。
  final LocalStore? store;

  /// 计划模板（S11）。**两者都给才显示「我的计划」入口** ——
  /// 缺一个就宁可不显示，也不放一个点不动的按钮。
  final RoutineRepository? routines;
  final ExerciseRepository? exercises;

  /// 显示单位（建议卡上那行「62.5 kg × 8」）
  final WeightUnit unit;

  @override
  State<TodaySuggestionScreen> createState() => _TodaySuggestionScreenState();
}

class _TodaySuggestionScreenState extends State<TodaySuggestionScreen> {
  List<PlannedExercise> _plan = const <PlannedExercise>[];
  TrainingDay? _day;
  bool _loading = true;

  /// 今日热身（练之前先做 1–2 个）。**默认不塞进计划** ——
  /// 要不要热身是用户的选择，但"选得到"必须是我们的事：
  /// 库里 11 个热身动作在这条流程里以前一个都见不到。
  List<ExerciseData> _warmups = const <ExerciseData>[];
  bool _warmupAdded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 2026-10-04：轮转从"6 部位"改成"上下肢交替"，所以这里先取**训练日**，
    // 再按这一天的构图（上肢 胸3+背2+肩1 / 下肢 腿4+核心2）生成计划。
    final TrainingDay day = await widget.planner.nextTrainingDay();
    final List<PlannedExercise> plan =
        await widget.planner.planToday(day: day, unit: widget.unit);
    // 热身按**这一天第一个部位**选（上肢→胸、下肢→腿），与计划的开头一致
    final String head =
        plan.isEmpty ? (kDayComposition[day]!.first.group) : plan.first.exercise.muscleGroup;
    final List<ExerciseData> warmups =
        await widget.planner.warmupFor(muscleGroup: head);
    if (!mounted) return;
    setState(() {
      _day = day;
      _plan = plan;
      _warmups = warmups;
      _warmupAdded = false;
      _loading = false;
    });
  }

  /// 把热身加进今天：插在**最前面**（热身先做），每组 1 组。
  ///
  /// 加进去之后它就成了计划的一部分 —— 点「开始训练」时这些动作会一起带进训练屏。
  void _addWarmups() {
    if (_warmups.isEmpty || _warmupAdded) return;
    setState(() {
      _plan = <PlannedExercise>[
        for (final ExerciseData w in _warmups)
          PlannedExercise(exercise: w, plan: defaultPlanFor(w), unit: widget.unit),
        ..._plan,
      ];
      _warmupAdded = true;
    });
  }

  Future<void> _reroll() async {
    setState(() => _loading = true);
    final List<PlannedExercise> plan =
        await widget.planner.reroll(current: _plan, unit: widget.unit);
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _loading = false;
    });
  }

  /// 用计划模板开训（S11）。
  ///
  /// 复用「按建议练」那条路径 —— 返回的 TodayResult 形状完全一样，
  /// 只是 plan 的来源从"轮转建议"换成了"用户自己的计划"。
  /// 把**今天的建议**存成一份计划（2026-10-01）。
  ///
  /// 为什么值得做：建议卡回答的是"今天练什么"，计划回答的是"以后照着练" ——
  /// 用户摇出一套顺眼的组合，原先只能今天用一次，明天还得重新摇。
  /// 存下来之后它出现在「我的计划」里，`source='suggested'` 记住它是从建议来的。
  Future<void> _saveAsRoutine() async {
    final RoutineRepository? repo = widget.routines;
    if (repo == null || _plan.isEmpty) return;
    final List<({String exerciseId, PlanTarget plan})> items =
        <({String exerciseId, PlanTarget plan})>[
      // 热身也一起存：它在界面上已经"加进今天"了，存计划时丢掉会让人困惑
      if (_warmupAdded)
        for (final ExerciseData w in _warmups)
          (
            exerciseId: w.id,
            plan: const PlanTarget(targetSets: 1, targetRepsLow: 30, targetRepsHigh: 45),
          ),
      for (final PlannedExercise p in _plan)
        (exerciseId: p.exercise.id, plan: p.plan),
    ];
    final RoutineData r = await repo.createFromPlan(
      '${_day == null ? '今日建议' : _day!.label} · 建议',
      items,
      source: 'suggested',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已存成计划「${r.name}」，下次在「我的计划」里直接用'),
        // 弹层底：比卡片再抬一档（T1-2 的 sheet）
                backgroundColor: Tokens.sheet,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(Tokens.s5, 0, Tokens.s5, 80),
      ),
    );
  }

  Future<void> _useRoutine() async {
    final RoutineStart? start = await Navigator.of(context).push<RoutineStart>(
      MaterialPageRoute<RoutineStart>(
        builder: (_) => RoutineListScreen(
          repository: widget.routines!,
          exercises: widget.exercises!,
          unit: widget.unit,
          store: widget.store,
        ),
      ),
    );
    if (start == null || !mounted) return;

    final List<PlannedExercise> plan = await widget.planner.planFromRoutine(
      entries: <RoutineEntry>[
        for (final RoutineItemData i in start.items)
          RoutineEntry(
            exerciseId: i.exerciseId,
            plan: PlanTarget(
              targetSets: i.targetSets,
              targetRepsLow: i.targetRepsLow,
              targetRepsHigh: i.targetRepsHigh,
            ),
          ),
      ],
      unit: widget.unit,
    );
    if (!mounted) return;
    if (plan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这份计划里的动作都不在动作库里了')),
      );
      return;
    }
    Navigator.of(context).pop(TodayResult(TodayChoice.startPlanned, plan));
  }

  void _start() =>
      Navigator.of(context).pop(TodayResult(TodayChoice.startPlanned, _plan));

  void _pickMyself() =>
      Navigator.of(context).pop(const TodayResult(TodayChoice.pickMyself));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _header(),
            Expanded(child: _body()),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, 0),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              key: const Key('today-back'),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.chevron_left, color: Tokens.text2),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Text(
              _day == null ? '今天练什么' : '今天练 ${_day!.label}',
              key: const Key('today-title'),
              style: const TextStyle(
                color: Tokens.text,
                fontSize: Tokens.fsTitle,
                fontWeight: Tokens.fwBold,
                letterSpacing: Tokens.lsTight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_plan.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: Tokens.s5),
          child: Text(
            '动作库还没准备好。\n可以点「我自己选」先练一个。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsSub, height: Tokens.lhNormal),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s4),
      children: <Widget>[
        if (_warmups.isNotEmpty) ...<Widget>[
          _warmupCard(),
          const SizedBox(height: Tokens.s3),
        ],
        Container(
          decoration: BoxDecoration(
            color: Tokens.surface,
            borderRadius: BorderRadius.circular(Tokens.rCard),
            border: Border.all(color: Tokens.line),
          ),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < _plan.length; i++)
                _row(_plan[i], isLast: i == _plan.length - 1),
            ],
          ),
        ),
      ],
    );
  }

  /// 「练之前先热身」卡。
  ///
  /// 刻意**不自动加进计划**：自动塞两个动作进今天的计划，会让"点一下开始练"
  /// 这件事变复杂（也多两条不想做的人要删的记录）。做成一张卡，谁想热谁加。
  Widget _warmupCard() {
    return Container(
      key: const Key('warmup-card'),
      padding: const EdgeInsets.all(Tokens.s5),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
        border: Border.all(color: Tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  '练之前先热身',
                  style: TextStyle(
                    color: Tokens.text,
                    fontSize: Tokens.fsBodyS,
                    fontWeight: Tokens.fwBold,
                  ),
                ),
              ),
              Text(
                _warmupAdded ? '已加进今天' : '1 组 · 30 秒',
                style: TextStyle(
                  color: _warmupAdded ? Tokens.accent : Tokens.text3,
                  fontSize: Tokens.fsCap,
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.s3),
          for (final ExerciseData w in _warmups)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          w.name,
                          style: const TextStyle(
                            color: Tokens.text,
                            fontSize: Tokens.fsSub,
                            fontWeight: Tokens.fwStrong,
                          ),
                        ),
                        if (w.instructions != null && w.instructions!.isNotEmpty)
                          Text(
                            w.instructions!,
                            style: const TextStyle(
                              color: Tokens.text3,
                              fontSize: Tokens.fsCap,
                              height: Tokens.lhSnug,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (!_warmupAdded)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('add-warmup'),
                onPressed: _addWarmups,
                child: const Text('加进今天'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(PlannedExercise p, {required bool isLast}) {
    return Container(
      key: Key('suggestion-${p.exercise.id}'),
      padding: const EdgeInsets.all(Tokens.s5),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Tokens.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  p.exercise.name,
                  style: const TextStyle(
                    color: Tokens.text,
                    fontSize: Tokens.fsBody,
                    fontWeight: Tokens.fwStrong,
                  ),
                ),
              ),
              const SizedBox(width: Tokens.s3),
              Text(
                p.loadLabel,
                style: const TextStyle(
                  color: Tokens.text,
                  fontSize: Tokens.fsBody,
                  fontWeight: Tokens.fwBold,
                ),
              ),
            ],
          ),
          if (p.suggestion != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              // 红线：解释不了的建议不许出现
              p.suggestion!.reasonText,
              style: const TextStyle(
                color: Tokens.accent,
                fontSize: Tokens.fsCap,
                height: Tokens.lhSnug,
              ),
            ),
            // 证据链：把引擎据以判断的**事实**摆出来。
            // 「上次 3 组 · 60 kg × 10 次 → 今天 62.5 kg」这条链能被用户看见，
            // 建议才不是黑箱；而看得见的事实也就可以被反驳（"这不是我上次记的"）。
            if (p.historyLabel != null) ...<Widget>[
              const SizedBox(height: 3),
              Text(
                p.historyLabel!,
                key: Key('history-${p.exercise.id}'),
                style: const TextStyle(
                  color: Tokens.text3,
                  fontSize: Tokens.fsMicro,
                  height: Tokens.lhSnug,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, Tokens.s5),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: Tokens.hPrimary,
            width: double.infinity,
            child: FilledButton(
              key: const Key('start-session'),
              style: FilledButton.styleFrom(
                backgroundColor: Tokens.accent,
                foregroundColor: Tokens.accentInk,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Tokens.rPill),
                ),
              ),
              onPressed: _plan.isEmpty ? null : _start,
              child: const Text(
                '开始训练',
                style: TextStyle(fontSize: Tokens.fsHeadline, fontWeight: Tokens.fwBold),
              ),
            ),
          ),
          const SizedBox(height: Tokens.s2),
          Row(
            children: <Widget>[
              Expanded(
                child: TextButton(
                  key: const Key('reroll'),
                  onPressed: _loading ? null : _reroll,
                  child: const Text('换一批',
                      style: TextStyle(color: Tokens.text2, fontSize: Tokens.fsSub)),
                ),
              ),
              Expanded(
                child: TextButton(
                  key: const Key('pick-myself'),
                  onPressed: _pickMyself,
                  child: const Text('我自己选',
                      style: TextStyle(color: Tokens.text2, fontSize: Tokens.fsSub)),
                ),
              ),
              if (widget.routines != null && widget.exercises != null)
                Expanded(
                  child: TextButton(
                    key: const Key('use-routine'),
                    onPressed: _useRoutine,
                    child: const Text('我的计划',
                        style: TextStyle(color: Tokens.text2, fontSize: Tokens.fsSub)),
                  ),
                ),
            ],
          ),
          // 「存成我的计划」单独一行：三个次要入口已经排满，再挤进去就是四个等宽按钮
          // （每一个都点到让人怀疑自己点错了）。
          if (widget.routines != null && _plan.isNotEmpty)
            TextButton(
              key: const Key('save-as-routine'),
              onPressed: _loading ? null : _saveAsRoutine,
              child: const Text('存成我的计划 ›',
                  style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap)),
            ),
        ],
      ),
    );
  }
}
