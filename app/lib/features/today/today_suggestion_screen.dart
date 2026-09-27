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

import '../../core/labels.dart';
import '../../core/theme.dart';
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
  const TodaySuggestionScreen({super.key, required this.planner});

  final TodayPlanner planner;

  @override
  State<TodaySuggestionScreen> createState() => _TodaySuggestionScreenState();
}

class _TodaySuggestionScreenState extends State<TodaySuggestionScreen> {
  List<PlannedExercise> _plan = const <PlannedExercise>[];
  String _group = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final String group = await widget.planner.nextMuscleGroup();
    final List<PlannedExercise> plan =
        await widget.planner.planToday(muscleGroup: group);
    if (!mounted) return;
    setState(() {
      _group = group;
      _plan = plan;
      _loading = false;
    });
  }

  Future<void> _reroll() async {
    setState(() => _loading = true);
    final List<PlannedExercise> plan =
        await widget.planner.reroll(current: _plan);
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _loading = false;
    });
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
              _group.isEmpty ? '今天练什么' : '今天练 ${muscleLabel(_group)}',
              key: const Key('today-title'),
              style: const TextStyle(
                color: Tokens.text,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
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
            style: TextStyle(color: Tokens.text3, fontSize: 15, height: 1.5),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s4),
      children: <Widget>[
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
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: Tokens.s3),
              Text(
                p.loadLabel,
                style: const TextStyle(
                  color: Tokens.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
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
                color: Tokens.volt,
                fontSize: 13,
                height: 1.4,
              ),
            ),
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
                backgroundColor: Tokens.volt,
                foregroundColor: Tokens.voltInk,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Tokens.rPill),
                ),
              ),
              onPressed: _plan.isEmpty ? null : _start,
              child: const Text(
                '开始训练',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
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
                      style: TextStyle(color: Tokens.text2, fontSize: 15)),
                ),
              ),
              Expanded(
                child: TextButton(
                  key: const Key('pick-myself'),
                  onPressed: _pickMyself,
                  child: const Text('我自己选',
                      style: TextStyle(color: Tokens.text2, fontSize: 15)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
