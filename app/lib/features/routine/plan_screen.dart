/// 练了么 · **训练计划**（2026-10-05，v1.51；新 VI 的 `vi/training-plan.html`）
///
/// 三个视图，用一个分段控件切：
///   * **本周** —— 周一…周日七格（每格今天练了几组），下面是**今天的安排**
///     （与首页**同一份**：由外壳传进来，不让这一页现算 —— 显示了 A 却练 B 比不显示更糟）；
///   * **模板库** —— 直接嵌 `RoutineListScreen`（**同一份实现**，不抄第二遍；
///     它就是原来的「我的计划」那一屏，独立打开那条路一点没变）；
///   * **历史** —— 按周聚合：本周/上周/更早各多少练、多少容量，以及每次训练的一行。
///
/// ⚠️ 这一屏**不写任何数据**：它只读（组记录 + 外壳给的今天计划）。
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/app_tab_bar.dart';
import '../../core/units.dart';
import '../../core/vi_cards.dart';
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import '../../data/routine_repository.dart';
import '../../domain/models.dart' show SetRecord;
import '../progress/progress_data.dart';
import '../routine/routine_screen.dart';
import '../today/today_planner.dart';

/// 三个视图的枚举（界面上的那排 chip 就是它）。
enum PlanView { week, templates, history }

class PlanScreen extends StatefulWidget {
  const PlanScreen({
    super.key,
    required this.repository,
    required this.exercises,
    required this.store,
    this.unit = WeightUnit.kg,
    this.todayPlan = const <PlannedExercise>[],
    this.todayLabel,
    this.onResume,
    this.now,
  });

  final RoutineRepository repository;
  final ExerciseRepository exercises;
  final LocalStore store;
  final WeightUnit unit;

  /// **今天的安排** —— 与首页同一份（外壳持有）。
  final List<PlannedExercise> todayPlan;

  /// 「上肢 / 下肢」那一行。
  final String? todayLabel;

  /// 上次没练完 → 「继续训练」。
  final VoidCallback? onResume;

  /// 可注入的"今天"，测试用。
  final DateTime? now;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  PlanView _view = PlanView.week;
  List<SetRecord> _sets = const <SetRecord>[];
  bool _loading = true;

  DateTime get _today => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<SetRecord> sets = await widget.store.allSets();
    if (!mounted) return;
    setState(() {
      _sets = sets;
      _loading = false;
    });
  }

  /// 本周的七天（**周一起**，与 `all_data.dart` 的口径一致）。
  List<DateTime> get _weekDays {
    final DateTime t = _today;
    final DateTime monday = DateTime(t.year, t.month, t.day)
        .subtract(Duration(days: t.weekday - DateTime.monday));
    return <DateTime>[for (int i = 0; i < 7; i++) monday.add(Duration(days: i))];
  }

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s5, 0),
            child: Row(
              children: <Widget>[
                // ⚠️ 这里原来写着「训练计划」—— 与顶栏的「计划」是同一个标题
                // （用户 10.9 清单第 3 条）。一级页不再自报名字，把那行文字删掉，
                // 只留右边的视图切换。
                const Spacer(),
                ViSegmented(
                  labels: const <String>['本周', '模板库', '历史'],
                  current: _view.index,
                  onChanged: (int i) => setState(() => _view = PlanView.values[i]),
                ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.s3),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : switch (_view) {
                    PlanView.week => _weekView(),
                    PlanView.templates => RoutineListScreen(
                        repository: widget.repository,
                        exercises: widget.exercises,
                        unit: widget.unit,
                        store: widget.store,
                        embedded: true,
                      ),
                    PlanView.history => _historyView(),
                  },
          ),
        ],
      );

  // ─────────────────────────────────────────────── 本周

  Widget _weekView() {
    final List<DateTime> days = _weekDays;
    final DateTime today = _today;
    const List<String> names = <String>['一', '二', '三', '四', '五', '六', '日'];

    return ListView(
      padding: EdgeInsets.fromLTRB(Tokens.s5, 0, Tokens.s5,
          Tokens.s5 + AppTabBar.reservedSpaceFor(context)),
      children: <Widget>[
        ViCard(
          child: Row(
            children: <Widget>[
              for (int i = 0; i < days.length; i++)
                Expanded(
                  child: _dayCell(
                    day: days[i],
                    label: names[i],
                    isToday: days[i].year == today.year &&
                        days[i].month == today.month &&
                        days[i].day == today.day,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Tokens.s4),
        if (widget.onResume != null) ...<Widget>[
          ViCard(
            key: const Key('plan-resume'),
            onTap: widget.onResume,
            child: const Row(
              children: <Widget>[
                Icon(Icons.play_circle_outline, color: Tokens.accent, size: 20),
                SizedBox(width: Tokens.s3),
                Expanded(
                  child: Text('上次的训练还没结束 —— 接着练',
                      style: TextStyle(color: Tokens.text, fontSize: 14)),
                ),
                Icon(Icons.chevron_right, color: Tokens.text3, size: 20),
              ],
            ),
          ),
          const SizedBox(height: Tokens.s4),
        ],
        const Text('今天的安排',
            style: TextStyle(color: Tokens.text, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: Tokens.s2),
        if (widget.todayPlan.isEmpty)
          const Text('今天还没有排动作 —— 回首页点「开始今天的训练」会自动生成。',
              style: TextStyle(color: Tokens.text3, fontSize: 13, height: 1.5))
        else
          ViCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (widget.todayLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Tokens.s2),
                    child: Text(widget.todayLabel!,
                        style: const TextStyle(color: Tokens.accent, fontSize: 13)),
                  ),
                for (final PlannedExercise p in widget.todayPlan)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(p.exercise.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Tokens.text2, fontSize: 14)),
                        ),
                        Text(p.loadLabel,
                            style: const TextStyle(color: Tokens.text3, fontSize: 13)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// 周历的一格：星期 + 日期 + 那天练了几组。
  ///
  /// **只显示"事实"**：练了就是几组，没练就是一条短横 —— 不画"计划中的训练"，
  /// 因为 App 里并没有"未来的计划"这个数据（计划的只有今天）。
  Widget _dayCell({required DateTime day, required String label, required bool isToday}) {
    int sets = 0;
    for (final SetRecord s in _sets) {
      final DateTime t = DateTime.fromMillisecondsSinceEpoch(s.completedAtMs);
      if (t.year == day.year && t.month == day.month && t.day == day.day) sets++;
    }
    return Column(
      key: Key('week-${day.month}-${day.day}'),
      children: <Widget>[
        Text('周$label',
            style: TextStyle(
                color: isToday ? Tokens.accent : Tokens.text3, fontSize: 11)),
        const SizedBox(height: 4),
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: isToday ? Tokens.accent : Colors.transparent,
            shape: BoxShape.circle,
            border: isToday ? null : Border.all(color: Tokens.line),
          ),
          child: Center(
            child: Text('${day.day}',
                style: TextStyle(
                  color: isToday ? Tokens.accentInk : Tokens.text2,
                  fontSize: 13,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                )),
          ),
        ),
        const SizedBox(height: 4),
        Text(sets > 0 ? '$sets 组' : '—',
            style: TextStyle(color: sets > 0 ? Tokens.text2 : Tokens.text3, fontSize: 10)),
      ],
    );
  }

  // ─────────────────────────────────────────────── 历史

  Widget _historyView() {
    final DateTime now = _today;
    final List<({String workoutId, DateTime day, int exercises, int sets, double volume})> all =
        recentWorkouts(_sets, limit: 1000);

    /// 分成三桶：本周 / 上周 / 更早。**桶的边界按"周一起"算**，与上面那个周历同一个口径。
    final DateTime monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - DateTime.monday));
    final DateTime lastMonday = monday.subtract(const Duration(days: 7));

    final List<({String title, List<({String workoutId, DateTime day, int exercises, int sets, double volume})> rows})>
        groups = <({String title, List<({String workoutId, DateTime day, int exercises, int sets, double volume})> rows})>[];
    for (final (String, bool Function(DateTime)) g in <(String, bool Function(DateTime))>[
      ('本周', (DateTime d) => !d.isBefore(monday)),
      ('上周', (DateTime d) => !d.isBefore(lastMonday) && d.isBefore(monday)),
      ('更早', (DateTime d) => d.isBefore(lastMonday)),
    ]) {
      final List<({String workoutId, DateTime day, int exercises, int sets, double volume})> rows =
          all.where((({String workoutId, DateTime day, int exercises, int sets, double volume}) r) => g.$2(r.day)).toList();
      if (rows.isNotEmpty) groups.add((title: g.$1, rows: rows));
    }

    if (groups.isEmpty) {
      return const Center(
        child: Text('还没有练过。\n练完第一次，这里会按周记下你练了几次、多少容量。',
            key: Key('plan-history-empty'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Tokens.text3, fontSize: 14, height: 1.6)),
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(Tokens.s5, 0, Tokens.s5,
          Tokens.s5 + AppTabBar.reservedSpaceFor(context)),
      children: <Widget>[
        for (final ({String title, List<({String workoutId, DateTime day, int exercises, int sets, double volume})> rows}) g in groups) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.s2),
            child: Text(
              '${g.title} · ${g.rows.length} 次 · '
              '${formatVolume(g.rows.fold<double>(0, (double a, ({String workoutId, DateTime day, int exercises, int sets, double volume}) r) => a + r.volume), widget.unit)}',
              key: Key('history-${g.title}'),
              style: const TextStyle(color: Tokens.text2, fontSize: 13),
            ),
          ),
          for (final ({String workoutId, DateTime day, int exercises, int sets, double volume}) r in g.rows)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s2),
              child: ViCard(
                key: Key('history-row-${r.workoutId}'),
                padding: const EdgeInsets.symmetric(horizontal: Tokens.s4, vertical: Tokens.s3),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text('${r.day.month} 月 ${r.day.day} 日',
                          style: const TextStyle(color: Tokens.text, fontSize: 14)),
                    ),
                    Text('${r.exercises} 个动作 · ${r.sets} 组 · ${formatVolume(r.volume, widget.unit)}',
                        style: const TextStyle(color: Tokens.text3, fontSize: 12)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: Tokens.s4),
        ],
      ],
    );
  }
}
