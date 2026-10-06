/// 练了么 · S8「进步」
///
/// 对应 `docs/screens.md` S8。只有三块内容（规格里就是这么定的）：
/// 本周容量曲线、PR 墙、体重。
///
/// **体重没做** —— 需要 `body_metric` 表与录入界面（S12），是另一块工作。
/// 与其放一个空的「体重 —」，不如先不放；等有了再加回来。
///
/// 曲线是自己画的（`CustomPainter`），不引图表库：
/// 七个点、一条折线，为它加一个依赖不值得。
library;

import 'package:flutter/material.dart';

// db.dart（drift 表）与 models.dart（领域模型）都定义了 Workout / SetRecord，预先 hide。
import '../../core/labels.dart';
import '../../analytics/analytics.dart';
import '../../core/theme.dart';
import '../../core/app_tab_bar.dart';
import '../../core/vi_area_chart.dart';
import '../../core/vi_cards.dart';
import '../../core/units.dart';
import '../../data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import '../../data/profile_repository.dart';
import '../../data/body_metric_repository.dart';
import '../../domain/models.dart';
import '../body/body_metric_screen.dart';
import 'all_data_screen.dart';
import 'progress_data.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({
    super.key,
    required this.store,
    required this.repository,
    this.bodyMetrics,
    this.profile,
    this.onBodyUnitChanged,
    this.analytics,
    this.unit = WeightUnit.kg,
    this.bodyUnit = BodyWeightUnit.kg,
    this.now,
  });

  final LocalStore store;

  /// 埋点（可选）：身体数据页从这里拿去上报 `body_metric_logged`
  final Analytics? analytics;
  final ExerciseRepository repository;

  /// 体重（S12）。**可选**：不传就没有体重卡片 ——
  /// 「等有了再加回来」的那块，加回来了。
  final BodyMetricRepository? bodyMetrics;

  /// **训练重量**的显示单位。只影响显示：容量与 PR 的判定始终按 kg 算。
  final WeightUnit unit;

  /// **体重**的显示单位（千克 / 斤）的初始值。与 [unit] 分开 ——
  /// 把训练切到 lb 的人，体重也不该跟着变磅（中国用户称体重说斤）。
  ///
  /// 它可以在**身体数据页里实时切**，所以这页要能收到变化（[onBodyUnitChanged]）
  /// 并把这个偏好落库（[profile]）。
  final BodyWeightUnit bodyUnit;

  /// 用户偏好仓库 —— 身体数据页里切单位时要落库。
  final ProfileRepository? profile;

  /// 体重单位在身体数据页被切了之后通知上层（本页那张卡片要立刻跟着变）。
  final ValueChanged<BodyWeightUnit>? onBodyUnitChanged;

  /// 测试注入固定时间用；生产为 null，取当前时间
  final DateTime? now;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  ProgressData? _data;
  BodyMetricData? _latestWeight;
  bool _loading = true;

  /// 原始组数据。卡片的三个数字与曲线都按**区间**现算 ——
  /// 所以这里要留着它（`ProgressData` 里只有"最近 7 天"那一份）。
  List<SetRecord> _sets = const <SetRecord>[];

  /// 「周 / 月 / 年」当前选中项（2026-10-05，新 VI）。
  ProgressRange _range = ProgressRange.week;

  DateTime get _today => widget.now ?? DateTime.now();

  /// 体重单位：初值来自构造参数，身体数据页里切了之后本地也跟着变
  /// （否则回来那张卡片还按旧单位念）。
  late BodyWeightUnit _bodyUnit = widget.bodyUnit;

  /// 上层换了体重单位就跟着换。
  ///
  /// 少这一条会出一个很具体的 bug：用户在身体数据页把单位切成「斤」→
  /// 上层 setState 传下新的 `bodyUnit` → **State 被复用**（同类型同位置），
  /// 于是本地 `_bodyUnit` 还是旧值，回来那张卡片仍按千克念 ——
  /// "切了但数字没变"。测试把这条抓出来了。
  @override
  void didUpdateWidget(ProgressScreen old) {
    super.didUpdateWidget(old);
    if (old.bodyUnit != widget.bodyUnit) {
      setState(() => _bodyUnit = widget.bodyUnit);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<SetRecord> sets = await widget.store.allSets();
    final List<ExerciseData> rows = await widget.repository.search(limit: 500);
    final Map<String, String> names = <String, String>{
      for (final ExerciseData r in rows) r.id: r.name,
    };
    // 按时长动作（平板支撑类）的最佳值念「秒」不念「次」
    final Set<String> timeIds = <String>{
      for (final ExerciseData r in rows)
        if (isTimeTrack(r.trackType)) r.id,
    };
    // 记距离的动作（有氧、农夫行走）**不进力量最佳榜**：
    // 它们的 reps 是秒，按"自重比次数"会得出"最佳 1800 次"这种假纪录。
    final Set<String> distanceIds = <String>{
      for (final ExerciseData r in rows)
        if (isDistanceTrack(r.trackType)) r.id,
    };
    final BodyMetricData? weight = await widget.bodyMetrics?.latest();
    if (!mounted) return;
    setState(() {
      _sets = sets;
      _data = buildProgress(
        sets: sets,
        exerciseNames: names,
        today: widget.now ?? DateTime.now(),
        unit: widget.unit,
        timeExerciseIds: timeIds,
        distanceExerciseIds: distanceIds,
        // 本周每部位组数（2026-10-04）：顺手把 id → 主肌群也建好
        muscleOf: <String, String>{
          for (final ExerciseData r in rows) r.id: r.muscleGroup,
        },
      );
      _latestWeight = weight;
      _loading = false;
    });
  }

  /// 体重卡片。S8 原本有三块，这块当时因为"没有 body_metric 表"而没做，
  /// 注释里写的是「等有了再加回来」。
  Widget _weightCard() {
    final BodyMetricData? w = _latestWeight;
    return Container(
      padding: const EdgeInsets.all(Tokens.s4),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: w == null
                ? const Text(
                    '还没记录过体重',
                    style: TextStyle(color: Tokens.text3, fontSize: 15),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        // 走**唯一**的重量格式化入口 —— 这里以前硬写着 `kg` + 自己 _trim，
                        // 于是单位是 lb 的用户会在「进步」看到「85.5 kg」、
                        // 在「身体数据」看到「188.5 lb」：同一个体重，两个单位两块屏。
                        formatBodyWeight(w.weightKg, _bodyUnit),
                        key: const Key('progress-weight'),
                        style: Tokens.display(24, weight: 700, letterSpacing: -0.3),
                      ),
                      const SizedBox(height: Tokens.s1),
                      Text(
                        <String>[
                          w.date,
                          if (w.note != null && w.note!.isNotEmpty) w.note!,
                        ].join(' · '),
                        style: const TextStyle(color: Tokens.text3, fontSize: 13),
                      ),
                    ],
                  ),
          ),
          TextButton(
            key: const Key('progress-weight-edit'),
            style: TextButton.styleFrom(foregroundColor: Tokens.accent),
            onPressed: _openBodyMetric,
            child: Text(w == null ? '记录' : '更新'),
          ),
        ],
      ),
    );
  }

  Future<void> _openAllData() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AllDataScreen(
          store: widget.store,
          repository: widget.repository,
          unit: widget.unit,
          now: widget.now,
        ),
      ),
    );
  }

  Future<void> _openBodyMetric() async {
    final BodyMetricRepository? repo = widget.bodyMetrics;
    if (repo == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BodyMetricScreen(
          repository: repo,
          unit: widget.bodyUnit,
          profile: widget.profile,
          onUnitChanged: (BodyWeightUnit u) {
            if (!mounted) return;
            setState(() => _bodyUnit = u);
            widget.onBodyUnitChanged?.call(u);
          },
          // 记完回来要刷新，否则卡片还显示旧体重
          onSaved: _load,
          analytics: widget.analytics,
        ),
      ),
    );
    await _load();
  }


  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final ProgressData d = _data!;

    return ListView(
      padding: EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s5,
          Tokens.s5 + AppTabBar.reservedSpaceFor(context)),
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                '进步',
                style: TextStyle(
                  color: Tokens.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            // S9 的入口。二级页：这一屏回答"最近怎么样"，
            // 那一屏回答"某个动作/某段时间到底怎么样"。
            TextButton(
              key: const Key('open-all-data'),
              style: TextButton.styleFrom(foregroundColor: Tokens.accent),
              onPressed: _openAllData,
              child: const Text('全部数据 ›', style: TextStyle(fontSize: 14)),
            ),
          ],
        ),
        const SizedBox(height: Tokens.s5),
        // 空态**不再提前 return** —— 否则"只记了体重、还没练过"的人
        // 看不到自己刚记的体重。体重和训练是两件独立的事。
        if (d.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: Tokens.s5),
            child: Text(
              '还没有训练记录。\n练完第一次，这里就会长出曲线和纪录。',
              style: TextStyle(color: Tokens.text3, fontSize: 15, height: 1.6),
            ),
          )
        else ...<Widget>[
          _statsBlock(),          // 四张统计卡（按区间现算）
          const SizedBox(height: Tokens.s3),
          _trendCard(),           // 容量趋势（周 / 月 / 年）
          const SizedBox(height: Tokens.s5),
          // 本周每部位组数（2026-10-04）：**并进 S8、不新开屏**。
          // 它回答的是"我这周练均衡了吗"—— 这一屏原来只有容量/PR/体重三块，
          // 而容量是"总量"，看不出哪块肌肉被漏掉了。
          if (d.weekSetsByMuscle.isNotEmpty) _muscleCard(d),
          const SizedBox(height: Tokens.s5),
          _sectionTitle('PR 墙'),
          _prCard(d),
        ],
        // 没有体重仓库就连标题都不显示 —— 否则会渲染一个
        // 「还没记录过体重」+ 点不动的「记录」按钮（测试抓出来的）
        if (widget.bodyMetrics != null) ...<Widget>[
          const SizedBox(height: Tokens.s5),
          _sectionTitle('体重'),
          _weightCard(),
        ],
      ],
    );
  }

  /// 本周每部位组数（2026-10-04）。
  ///
  /// **一行一个部位，横向铺开**，并标出与循证区间的关系：
  /// 区间是「每块肌肉每周 12–20 组」（Baz-Valle 2022），所以
  ///   * 0 组 → 灰字（这周没练）
  ///   * 1–11 组 → 常规色（还没到区间）
  ///   * 12–20 组 → **accent 高亮**（在区间里）
  ///   * > 20 组 → 也高亮（超过 20 组研究上没更多收益，但不该说人家错了）
  ///
  /// ⚠️ 只按主肌群算（卧推只记进"胸"）—— 所以显示的数字**低估**协同肌群的量，
  /// 这是已知简化，不在这里假装精确。
  Widget _muscleCard(ProgressData d) {
    return Container(
      key: const Key('progress-muscles'),
      padding: const EdgeInsets.all(Tokens.s5),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
        border: Border.all(color: Tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('本周各部位组数',
              style: TextStyle(color: Tokens.text3, fontSize: 13)),
          const SizedBox(height: Tokens.s3),
          Wrap(
            spacing: Tokens.s3,
            runSpacing: Tokens.s3,
            children: <Widget>[
              for (final ({String muscleGroup, int sets}) m in d.weekSetsByMuscle)
                _muscleChip(m.muscleGroup, m.sets),
            ],
          ),
          const SizedBox(height: Tokens.s3),
          const Text('循证区间：每块肌肉每周 12–20 组',
              style: TextStyle(color: Tokens.text3, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _muscleChip(String group, int sets) {
    final bool inRange = sets >= 12;
    return SizedBox(
      width: 72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(muscleLabel(group),
              style: const TextStyle(color: Tokens.text2, fontSize: 13)),
          const SizedBox(height: 2),
          Text(
            '$sets 组',
            key: Key('muscle-$group'),
            style: TextStyle(
              color: sets == 0
                  ? Tokens.text3
                  : (inRange ? Tokens.accent : Tokens.text),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// 四张统计卡（2026-10-05，新 VI）：区间容量 / 训练次数 / 总组数 / 个人纪录。
  ///
  /// 前三张**跟着区间走**（周 / 月 / 年），第四张是全时段的历史纪录数 ——
  /// 所以它的标签上写明了「全部」，不改口径也不含糊。
  Widget _statsBlock() {
    final ({DateTime from, DateTime to}) w = rangeWindow(_today, _range);
    final double volume = volumeIn(_sets, w.from, w.to);
    final int workouts = workoutCountIn(_sets, w.from, w.to);
    final int sets = setCountIn(_sets, w.from, w.to);
    final int prs = _data?.prs.length ?? 0;
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: ViCard(
                child: StatTile(
                  label: '${rangeLabel(_range)}容量',
                  value: formatVolume(volume, widget.unit),
                  valueKey: const Key('progress-week-volume'),
                  delta: rangeHint(_range),
                ),
              ),
            ),
            const SizedBox(width: Tokens.s3),
            Expanded(
              child: ViCard(
                child: StatTile(
                  label: '训练次数',
                  value: '$workouts 次',
                  delta: rangeHint(_range),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Tokens.s3),
        Row(
          children: <Widget>[
            Expanded(
              child: ViCard(
                child: StatTile(
                  label: '总组数',
                  value: '$sets 组',
                  delta: rangeHint(_range),
                ),
              ),
            ),
            const SizedBox(width: Tokens.s3),
            Expanded(
              child: ViCard(
                child: StatTile(
                  label: '个人纪录',
                  value: '$prs 项',
                  delta: '全部历史',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 容量趋势（周 / 月 / 年）。曲线是零依赖自绘的 `ViAreaChart`。
  Widget _trendCard() {
    final List<double> series = volumeSeries(_sets, _today, _range);
    final List<String> ends = seriesEndLabels(_today, _range);
    return ViCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text('训练容量趋势',
                    style: TextStyle(color: Tokens.text, fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              ViSegmented(
                labels: const <String>['周', '月', '年'],
                current: _range.index,
                onChanged: (int i) => setState(() => _range = ProgressRange.values[i]),
              ),
            ],
          ),
          const SizedBox(height: Tokens.s3),
          ViAreaChart(
            key: const Key('progress-sparkline'),
            points: series,
            height: 120,
          ),
          const SizedBox(height: Tokens.s2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(ends.first, style: const TextStyle(color: Tokens.text3, fontSize: 11)),
              Text(rangeHint(_range), style: const TextStyle(color: Tokens.text3, fontSize: 11)),
              Text(ends.last, style: const TextStyle(color: Tokens.text3, fontSize: 11)),
            ],
          ),
          // 这个区间一条记录都没有就说清楚 —— 曲线画成一条平线时，
          // 人分不清"没练"和"练了但没重量"，而这两件事完全不同。
          if (series.every((double v) => v == 0))
            Padding(
              padding: const EdgeInsets.only(top: Tokens.s2),
              child: Text(
                '${rangeHint(_range)}还没练',
                style: const TextStyle(color: Tokens.text3, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }


  Widget _prCard(ProgressData d) {
    return Container(
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
        border: Border.all(color: Tokens.line),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < d.prs.length; i++)
            Container(
              key: Key('pr-${d.prs[i].exerciseId}'),
              padding: const EdgeInsets.symmetric(
                  horizontal: Tokens.s4, vertical: Tokens.s4),
              decoration: BoxDecoration(
                border: i == d.prs.length - 1
                    ? null
                    : const Border(bottom: BorderSide(color: Tokens.line)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          d.prs[i].name,
                          style: const TextStyle(color: Tokens.text, fontSize: 15),
                        ),
                        // 预估 1RM（2026-10-04）。**只在算得出来时显示** ——
                        // 自重 / 按时长 / 次数超过 12 的动作没有可信的 1RM
                        // （`estimate1RM` 在这些情况下返回 null，界面不留空行）。
                        if (d.prs[i].oneRm != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '预估 1RM ${formatWeight(d.prs[i].oneRm!, d.unit)}',
                              key: Key('pr-1rm-${d.prs[i].exerciseId}'),
                              style: const TextStyle(
                                  color: Tokens.text3, fontSize: 12),
                            ),
                          ),
                        // 距上次破纪录多少天（第二部分第 4 条，2026-10-06）。
                        // "68 kg"是上周刚破的还是半年前破的，是完全不同的两件事：
                        // 前者说明还在涨，后者说明该换计划了。**从没破过就不显示这一行**
                        // （显示"0 天前"会是假话）。
                        if (lastPrLabel(d.daysSinceLastPr, d.prs[i].exerciseId) != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              lastPrLabel(d.daysSinceLastPr, d.prs[i].exerciseId)!,
                              key: Key('pr-age-${d.prs[i].exerciseId}'),
                              style: const TextStyle(
                                  color: Tokens.text3, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    d.prs[i].label,
                    style: const TextStyle(
                      color: Tokens.pr,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(left: Tokens.s1, bottom: Tokens.s2),
        child: Text(t, style: const TextStyle(color: Tokens.text3, fontSize: 13)),
      );

}
