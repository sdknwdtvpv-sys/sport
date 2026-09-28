/// 练了么 · S9「全部数据」（二级页）
///
/// 规格（`docs/screens.md` S9）：
///   * 按动作维度：容量趋势 / 1RM 趋势 / 历史最佳 / 全部记录
///   * 按时间维度：周报 / 月报
///   * 导出 CSV
///
/// 入口挂在 S8「进步」上。这里只做展示与聚合 —— 规则全在 `all_data.dart`
/// （纯函数、可测），这一层不自己算任何东西。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/sparkline.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import '../../domain/models.dart';
import '../exercise/exercise_picker_screen.dart';
import '../profile/training_stats.dart';
import 'all_data.dart';

enum _Mode { byExercise, byTime }

class AllDataScreen extends StatefulWidget {
  const AllDataScreen({
    super.key,
    required this.store,
    required this.repository,
    this.unit = WeightUnit.kg,
    this.now,
  });

  final LocalStore store;
  final ExerciseRepository repository;
  final WeightUnit unit;

  /// 测试注入固定"今天"
  final DateTime? now;

  @override
  State<AllDataScreen> createState() => _AllDataScreenState();
}

class _AllDataScreenState extends State<AllDataScreen> {
  _Mode _mode = _Mode.byExercise;
  bool _loading = true;

  ExerciseData? _exercise;
  ExerciseStats? _stats;
  List<SetRecord> _records = const <SetRecord>[];

  PeriodReport? _week;
  PeriodReport? _month;
  List<MonthVolume> _months = const <MonthVolume>[];

  DateTime get _today => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<SetRecord> all = await widget.store.allSets();

    // 默认选最近练过的那个动作 —— 打开就有点东西看，而不是一个空选择器
    ExerciseData? exercise = _exercise;
    if (exercise == null) {
      final List<String> recent = await widget.store.recentExerciseIds();
      if (recent.isNotEmpty) exercise = await widget.repository.byId(recent.first);
    }

    ExerciseStats? stats;
    List<SetRecord> records = const <SetRecord>[];
    if (exercise != null) {
      records = await widget.store.setsForExercise(exercise.id);
      // 最近的排前面：用户多数想知道"最近怎么样"
      final List<SetRecord> sorted = List<SetRecord>.of(records)
        ..sort((SetRecord a, SetRecord b) =>
            b.completedAtMs.compareTo(a.completedAtMs));
      records = sorted;
      stats = buildExerciseStats(
        exerciseId: exercise.id,
        name: exercise.name,
        sets: records,
        today: _today,
        isTime: isTimeTrack(exercise.trackType),
      );
    }

    if (!mounted) return;
    setState(() {
      _exercise = exercise;
      _stats = stats;
      _records = records;
      _week = buildWeekReport(sets: all, today: _today);
      _month = buildMonthReport(sets: all, today: _today);
      _months = recentMonthVolumes(sets: all, today: _today);
      _loading = false;
    });
  }

  Future<void> _pickExercise() async {
    final ExerciseData? picked = await Navigator.of(context).push<ExerciseData>(
      MaterialPageRoute<ExerciseData>(
        builder: (_) => ExercisePickerScreen(
          repository: widget.repository,
          store: widget.store,
          unit: widget.unit,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _exercise = picked);
    await _load();
  }

  /// 导出全部记录。和 S10 的导出走同一段代码，单位也跟着走 ——
  /// 界面上显示 lb、导出却是 kg 的话，用户会以为导错了。
  Future<void> _export() async {
    final List<SetRecord> sets = await widget.store.allSets();
    final List<ExerciseData> rows = await widget.repository.search(limit: 500);
    final Map<String, String> names = <String, String>{
      for (final ExerciseData r in rows) r.id: r.name,
    };
    final String csv =
        buildSetsCsv(sets: sets, exerciseNames: names, unit: widget.unit);
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 ${sets.length} 条记录到剪贴板'),
        backgroundColor: Tokens.elevated,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(Tokens.s5, 0, Tokens.s5, 80),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _header(),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else ...<Widget>[
              _modeChips(),
              Expanded(
                child: _mode == _Mode.byExercise ? _byExercise() : _byTime(),
              ),
            ],
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
              key: const Key('all-data-back'),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.chevron_left, color: Tokens.text2),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: Tokens.s3),
          const Expanded(
            child: Text(
              '全部数据',
              style: TextStyle(
                color: Tokens.text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            key: const Key('all-data-export'),
            style: TextButton.styleFrom(foregroundColor: Tokens.volt),
            onPressed: _export,
            child: const Text('导出 CSV', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _modeChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s3, Tokens.s5, 0),
      child: Row(
        children: <Widget>[
          _chip('all-data-mode-exercise', '按动作', _mode == _Mode.byExercise,
              () => setState(() => _mode = _Mode.byExercise)),
          const SizedBox(width: Tokens.s2),
          _chip('all-data-mode-time', '按时间', _mode == _Mode.byTime,
              () => setState(() => _mode = _Mode.byTime)),
        ],
      ),
    );
  }

  Widget _chip(String key, String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      key: Key(key),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
        height: 36,
        decoration: BoxDecoration(
          color: active ? Tokens.volt : Tokens.surface,
          borderRadius: BorderRadius.circular(Tokens.rPill),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Tokens.voltInk : Tokens.text2,
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  // ---------- 按动作 ----------

  Widget _byExercise() {
    final ExerciseStats? s = _stats;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s6),
      children: <Widget>[
        GestureDetector(
          key: const Key('all-data-pick-exercise'),
          onTap: _pickExercise,
          child: Container(
            padding: const EdgeInsets.all(Tokens.s4),
            decoration: BoxDecoration(
              color: Tokens.surface,
              borderRadius: BorderRadius.circular(Tokens.rCard),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    s == null ? '选一个动作' : s.name,
                    key: const Key('all-data-exercise-name'),
                    style: const TextStyle(
                      color: Tokens.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.unfold_more, color: Tokens.text3, size: 20),
              ],
            ),
          ),
        ),
        if (s == null || s.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: Tokens.s5),
            child: Text(
              '这个动作还没有记录。练过一次再来，这里就会长出曲线。',
              style: TextStyle(color: Tokens.text3, fontSize: 15, height: 1.5),
            ),
          )
        else ...<Widget>[
          _sectionTitle('历史最佳'),
          _card(<Widget>[
            _statRow('最大重量',
                s.isBodyweight ? '—' : formatWeight(s.bestWeightKg, widget.unit),
                const Key('all-data-best-weight')),
            _statRow('最佳估算 1RM',
                s.best1RM == null ? '—' : formatWeight(s.best1RM, widget.unit),
                const Key('all-data-best-1rm')),
            // 按时长动作这里念「秒」—— 平板支撑的"最多次数"是个说不通的标签
            _statRow(
              s.isTime ? '最长时长' : '最多次数',
              '${s.bestReps} ${s.isTime ? '秒' : '次'}',
              const Key('all-data-best-reps'),
            ),
            _statRow('总容量', formatVolume(s.totalVolumeKg, widget.unit, zeroText: '—'),
                const Key('all-data-total-volume')),
            _statRow('总组数', '${s.setCount} 组', const Key('all-data-set-count')),
          ]),
          _sectionTitle('容量趋势（最近 30 天）'),
          _trendCard(s.volumeTrend, const Key('all-data-volume-trend')),
          _sectionTitle('1RM 趋势（最近 30 天）'),
          _trendCard(s.oneRmTrend, const Key('all-data-1rm-trend')),
          if (s.isBodyweight)
            const Padding(
              padding: EdgeInsets.only(top: Tokens.s2),
              child: Text(
                '自重动作没有 1RM —— 它比的是次数。',
                style: TextStyle(color: Tokens.text3, fontSize: 12),
              ),
            ),
          _sectionTitle('全部记录'),
          _card(<Widget>[
            for (final SetRecord r in _records.take(30)) _recordRow(r),
            if (_records.length > 30)
              Padding(
                padding: const EdgeInsets.only(top: Tokens.s2),
                child: Text(
                  '只显示最近 30 条，共 ${_records.length} 条。完整数据用「导出 CSV」。',
                  style: const TextStyle(color: Tokens.text3, fontSize: 12),
                ),
              ),
          ]),
        ],
      ],
    );
  }

  Widget _trendCard(List<double> values, Key key) {
    return Container(
      height: 90,
      padding: const EdgeInsets.all(Tokens.s4),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
      ),
      child: Sparkline(key: key, values: values),
    );
  }

  Widget _recordRow(SetRecord r) {
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(r.completedAtMs);
    final String day = '${d.month}/${d.day}';
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 56,
            child: Text(day,
                style: const TextStyle(color: Tokens.text3, fontSize: 13)),
          ),
          Text(
            r.weightKg == null
                ? '自重 × ${r.reps}'
                : '${formatWeight(r.weightKg, widget.unit)} × ${r.reps}',
            style: const TextStyle(
                color: Tokens.text2, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            formatVolume(r.volume, widget.unit, zeroText: '—'),
            style: const TextStyle(color: Tokens.text3, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ---------- 按时间 ----------

  Widget _byTime() {
    final PeriodReport? w = _week;
    final PeriodReport? m = _month;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s6),
      children: <Widget>[
        if (w != null) ...<Widget>[
          _sectionTitle('本周'),
          _periodCard(w, const Key('all-data-week')),
        ],
        if (m != null) ...<Widget>[
          _sectionTitle('本月'),
          _periodCard(m, const Key('all-data-month')),
        ],
        _sectionTitle('最近 6 个月容量'),
        _card(<Widget>[
          for (final MonthVolume mv in _months)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s2),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 76,
                    child: Text(mv.label,
                        style: const TextStyle(color: Tokens.text3, fontSize: 13)),
                  ),
                  Text(
                    formatVolume(mv.volumeKg, widget.unit, zeroText: '—'),
                    style: const TextStyle(
                        color: Tokens.text2, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ]),
        _sectionTitle('月趋势'),
        _trendCard(
          normalize(_months.map((MonthVolume m) => m.volumeKg).toList()),
          const Key('all-data-month-trend'),
        ),
      ],
    );
  }

  Widget _periodCard(PeriodReport r, Key key) {
    if (r.isEmpty) {
      return Padding(
        key: key,
        padding: const EdgeInsets.symmetric(vertical: Tokens.s2),
        child: const Text('这段时间还没有记录',
            style: TextStyle(color: Tokens.text3, fontSize: 15)),
      );
    }
    return Container(
      key: key,
      padding: const EdgeInsets.all(Tokens.s4),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
      ),
      child: Column(
        children: <Widget>[
          _statRow('训练次数', '${r.workoutCount} 次', null),
          _statRow('总组数', '${r.setCount} 组', null),
          _statRow('总容量',
              formatVolume(r.volumeKg, widget.unit, zeroText: '—'), null),
          _statRow('练了几天', '${r.activeDays} 天', null),
        ],
      ),
    );
  }

  // ---------- 小部件 ----------

  Widget _statRow(String label, String value, Key? key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label,
              style: const TextStyle(color: Tokens.text3, fontSize: 13)),
          Text(
            value,
            key: key,
            style: const TextStyle(
                color: Tokens.text, fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, Tokens.s5, 0, Tokens.s2),
        child: Text(
          t,
          style: const TextStyle(
            color: Tokens.text3,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      );

  Widget _card(List<Widget> children) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Tokens.s4),
        decoration: BoxDecoration(
          color: Tokens.surface,
          borderRadius: BorderRadius.circular(Tokens.rCard),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}
