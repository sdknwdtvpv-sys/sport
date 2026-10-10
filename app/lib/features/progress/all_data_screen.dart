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

import '../../billing/debug_grant.dart';
import '../../billing/ultra_visibility.dart';
import '../../core/glass_overlay.dart';
import '../../core/icon_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/sparkline.dart';
import '../../core/empty_state.dart';
import '../../core/theme.dart';
import '../../core/app_tab_bar.dart';
import '../../core/units.dart';
import '../../core/vi_cards.dart';
import '../../data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import '../../data/entitlement_repository.dart';
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
    this.asTab = false,
    required this.store,
    required this.repository,
    this.unit = WeightUnit.kg,
    this.now,
    this.entitlements,
    this.onOpenUltra,
    this.showUltra = kUltraReleased,
  });

  final LocalStore store;

  /// **它是不是被当成一级 tab 在用**（2026-10-09 加）。
  ///
  /// 同一个屏有两种角色，而它们对"页头"的要求正好相反：
  ///   * **二级页**（从「进步」点进来）：整屏盖住了外壳顶栏，所以它**必须**自己画
  ///     「‹ 全部数据」那一行 —— 不然没有返回入口；
  ///   * **一级 tab**（v1.45.0 起「数据」这一栏就是它）：外壳顶栏已经写着「数据」，
  ///     再画一遍就是**同一个标题出现两次**，而且那个 `‹` 在一级页里点下去是
  ///     "退回上一个 tab"，语义根本不对（用户 10.9 清单第 3 条抓的就是这个）。
  /// 所以由调用方明说角色，别让这一页去猜。
  final bool asTab;
  final ExerciseRepository repository;
  final WeightUnit unit;

  /// 测试注入固定"今天"
  final DateTime? now;

  /// 会员权益仓储（可选）。不传 = 当作**免费用户** —— 于是"批量整理"那一栏
  /// 显示为「整理（Ultra）」，点下去是去会员页（`onOpenUltra`），不会真的改数据。
  final EntitlementRepository? entitlements;

  /// 「整理（Ultra）」点下去的去处。不传 = 那一栏点了没反应（宁可不显示，也不谎报）
  final VoidCallback? onOpenUltra;

  /// 这一版上不上会员（默认 `kUltraReleased`，首版 `false`）。
  /// 关着的时候「整理」那一栏**不渲染**，长按某一行也**不进多选态** ——
  /// 批量整理是 Ultra 权益，而首版买不到（见 `ultra_visibility.dart`）。
  final bool showUltra;

  @override
  State<AllDataScreen> createState() => _AllDataScreenState();
}

class _AllDataScreenState extends State<AllDataScreen> {
  _Mode _mode = _Mode.byExercise;
  bool _loading = true;

  ExerciseData? _exercise;
  ExerciseStats? _stats;
  List<SetRecord> _records = const <SetRecord>[];

  /// **批量整理**（Ultra 权益 8，2026-10-10）：多选态与已选集合。
  /// 退出多选、或任何一次批量动作之后都要清空 —— 留着会让"下一次点"带着上一次的选择。
  bool _selecting = false;
  final Set<String> _selected = <String>{};
  bool _ultra = false;

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

    // ⚠️ 权益要在 setState **之前**读完（回调是同步的，里面不能 await）
    final bool ultra = widget.entitlements == null
        ? false
        : (await widget.entitlements!.access(_today.millisecondsSinceEpoch)).ultra;
    if (!mounted) return;
    setState(() {
      _ultra = debugUltraGranted || ultra;
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
        // 弹层底：比卡片再抬一档（T1-2 的 sheet）
                backgroundColor: Tokens.sheet,
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
            // 一级 tab 里不画页头（顶栏已经有「数据」了）—— 那个标题与返回箭头
            // 只对"二级页"角色有意义，见 asTab 的注释。
            if (!widget.asTab) _header(),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else ...<Widget>[
              _modeBar(),
              Expanded(
                child: _mode == _Mode.byExercise ? _byExercise() : _byTime(),
              ),
              if (_selecting) _selectionBar(),
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
                fontSize: Tokens.fsHeadline,
                fontWeight: Tokens.fwBold,
              ),
            ),
          ),
          // ⚠️ 两个动作按钮放进 `Flexible` + `Wrap`：大字号下（1.5×/2.0×）
          // 「整理（Ultra）」+「导出 CSV」会把这一行顶出屏幕 —— `large_font_sweep_test`
          // 当场抓到（全部数据页 1.5×/2.0× 溢出）。`Wrap` 让它们在放不下时**换行**，
          // 而不是把标题挤没、或溢出到屏幕外。
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
          // 「整理」= 批量整理历史（Ultra 权益 8）。**免费用户也看得见**，
          // 但写着「（Ultra）」并指向会员页 —— 把入口藏起来，用户根本不知道有这种东西；
          // 摆出来、说清解锁的是什么，才是"卖省心"而不是制造信息差（与进步页同一套口径）。
          // 只在「按动作看」里出现：记录列表只存在于那个维度，而"进多选态却无行可选"
          // 比"没有这个按钮"更让人摸不着头脑
          if (widget.showUltra && !_selecting && _mode == _Mode.byExercise)
            TextButton(
              key: const Key('all-data-organize'),
              style: TextButton.styleFrom(
                foregroundColor: _ultra ? Tokens.accent : Tokens.text2,
              ),
              onPressed: _ultra ? _enterSelecting : widget.onOpenUltra,
              child: Text(
                _ultra ? '整理' : '整理（Ultra）',
                style: const TextStyle(fontSize: Tokens.fsSub),
              ),
            ),
          TextButton(
            key: const Key('all-data-export'),
            style: TextButton.styleFrom(foregroundColor: Tokens.accent),
            onPressed: _export,
            child: const Text('导出 CSV', style: TextStyle(fontSize: Tokens.fsSub)),
          ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 维度切换：**明面上的分段控件**（2026-10-06 从右上角「更多」菜单改回来）。
  ///
  /// 2026-10-01 曾经把它收进「更多」菜单，理由是"新手在这里只是被问了一个他答不上来的
  /// 问题"。改回来的原因：iOS 26 的分段控件把两个选项**并排摆着、一眼读完**，
  /// 而藏在菜单里意味着**每次换维度都要多点一次** —— 对老手是天天付的税。
  /// 代价（新手多一次选择）用一个自解释的标签抵掉：「按动作看 / 按时间看」。
  /// 这条反转记在 `docs/competitor-xunji-pro-v7.md`（那里原来写着"收一个维度做对了"）。
  Widget _modeBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, 0),
      child: Row(
        children: <Widget>[
          ViSegmented(
            key: const Key('all-data-mode'),
            // 四个汉字的标签，格子要比默认宽一点（否则要紧贴边框）
            itemWidth: 80,
            labels: const <String>['按动作看', '按时间看'],
            current: _mode.index,
            onChanged: (int i) => setState(() => _mode = _Mode.values[i]),
          ),
          // 一级 tab 没有页头了，「导出 CSV」搬到这里 —— 它原来的位置就是和标题同一行
          if (widget.asTab) ...<Widget>[
            const Spacer(),
            TextButton(
              key: const Key('all-data-export'),
              style: TextButton.styleFrom(foregroundColor: Tokens.accent),
              onPressed: _export,
              child: const Text('导出 CSV', style: TextStyle(fontSize: Tokens.fsSub)),
            ),
          ],
        ],
      ),
    );
  }

  // ---------- 按动作 ----------

  Widget _byExercise() {
    final ExerciseStats? s = _stats;
    return ListView(
            padding: EdgeInsets.fromLTRB(
          Tokens.s5,
          Tokens.s4,
          Tokens.s5,
          Tokens.s6 + AppTabBar.reservedSpaceFor(context)),
      children: <Widget>[
        GestureDetector(
          key: const Key('all-data-pick-exercise'),
          onTap: _pickExercise,
          behavior: HitTestBehavior.opaque,
          // ⚠️ 2026-10-10：原来是一只**大圆角实心方块**（一屏里就它最大）。
          // 用户：「数据这一页全是大方块儿 实在是太丑了」—— 换成一条**设置项那样的行**：
          // 上下细线夹着，左边"选一个动作"、右边一个展开箭头，高度只有原来一半。
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: Tokens.s3),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Tokens.hair),
                bottom: BorderSide(color: Tokens.hair),
              ),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    s == null ? '选一个动作' : s.name,
                    key: const Key('all-data-exercise-name'),
                    style: const TextStyle(
                      color: Tokens.text,
                      fontSize: Tokens.fsBody,
                      fontWeight: Tokens.fwStrong,
                    ),
                  ),
                ),
                const Icon(Icons.unfold_more, color: Tokens.text3, size: IconSpec.m),
              ],
            ),
          ),
        ),
        if (s == null || s.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Tokens.s5),
            child: EmptyState(
              key: const Key('empty-all-data'),
              art: EmptyArt.ringSearch,
              title: '这个动作还没有记录。',
              body: '练过一次再来，或者换一个动作看看。',
              action: '换一个动作',
              onAction: _pickExercise,
            ),
          )
        else ...<Widget>[
          _sectionTitle('历史最佳'),
          // ⚠️ **按"这个动作到底在比什么"决定显示哪几行**（2026-10-01 真机走查改的）。
          // 以前不管什么动作都摆这五行，于是自重动作（引体向上）看到的是
          // 「最大重量 — / 1RM — / 总容量 —」三行废话，下面还叠了两条恒为零的平线。
          // 现在：有重量的比容量与 1RM；自重/按时长的比次数（或秒数）与总组数。
          _card(<Widget>[
            if (s.tracksWeight) ...<Widget>[
              _statRow('最大重量', formatWeight(s.bestWeightKg, widget.unit),
                  const Key('all-data-best-weight')),
              _statRow('最佳估算 1RM',
                  s.best1RM == null ? '—' : formatWeight(s.best1RM, widget.unit),
                  const Key('all-data-best-1rm')),
            ],
            // 按时长动作这里念「秒」—— 平板支撑的"最多次数"是个说不通的标签
            _statRow(
              s.isTime ? '最长时长' : '最多次数',
              '${s.bestReps} ${s.isTime ? '秒' : '次'}',
              const Key('all-data-best-reps'),
            ),
            if (s.tracksWeight)
              _statRow('总容量', formatVolume(s.totalVolumeKg, widget.unit, zeroText: '—'),
                  const Key('all-data-total-volume')),
            _statRow('总组数', '${s.setCount} 组', const Key('all-data-set-count')),
          ]),
          if (s.tracksWeight) ...<Widget>[
            _sectionTitle('容量趋势（最近 30 天）'),
            _trendCard(s.volumeTrend, const Key('all-data-volume-trend')),
            _sectionTitle('1RM 趋势（最近 30 天）'),
            _trendCard(s.oneRmTrend, const Key('all-data-1rm-trend')),
          ] else ...<Widget>[
            // 自重 / 按时长动作：容量与 1RM 恒为 0，画出来只是贴着底的平线。
            // 它们真正会变的是次数（按时长动作是秒数），所以只画这一条。
            _sectionTitle(
                s.isTime ? '时长趋势（最近 30 天）' : '次数趋势（最近 30 天）'),
            _trendCard(s.repsTrend, const Key('all-data-reps-trend')),
            Padding(
              padding: const EdgeInsets.only(top: Tokens.s2),
              child: Text(
                s.isTime
                    ? '按时长动作不比容量 —— 它比的是每组坚持了多久。'
                    : '自重动作不比容量与 1RM —— 它比的是次数。',
                style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro),
              ),
            ),
          ],
          _sectionTitle('全部记录'),
          _card(<Widget>[
            for (final SetRecord r in _records.take(30)) _recordRow(r),
            if (_records.length > 30)
              Padding(
                padding: const EdgeInsets.only(top: Tokens.s2),
                child: Text(
                  '只显示最近 30 条，共 ${_records.length} 条。完整数据用「导出 CSV」。',
                  style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro),
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
      padding: const EdgeInsets.all(Tokens.s5),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
      ),
      child: Sparkline(key: key, values: values),
    );
  }

  // ---------- 批量整理（Ultra 权益 8）----------

  void _enterSelecting({String? withId}) {
    // 首版不上会员：这一版连"点进去看预览"都不给（按钮都没渲染），
    // 长按也走同一条闸门 —— 免得出现"看不见按钮却进了多选态"的鬼状态
    if (!widget.showUltra) return;
    if (!_ultra) {
      // 免费用户点长按：把他带到会员页，而不是"点了没反应"或偷偷允许
      widget.onOpenUltra?.call();
      return;
    }
    setState(() {
      _selecting = true;
      if (withId != null) _selected.add(withId);
    });
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  void _cancelSelecting() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  /// 批量移到回收站。**先确认**：这是"改用户历史"的动作，而它是可恢复的
  /// （回收站在「数据与备份」里），所以确认文案要写清"可以恢复"——
  /// 否则用户会以为点错了就没了，于是不敢用这个功能。
  Future<void> _moveSelectedToTrash() async {
    final int n = _selected.length;
    if (n == 0) return;
    final bool? yes = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: Tokens.surface,
        title: Text('把这 $n 组移到回收站？'),
        content: const Text('它们会从统计里消失，但可以随时在「数据与备份 → 回收站」里恢复。',
            style: TextStyle(color: Tokens.text2, height: Tokens.lhNormal)),
        actions: <Widget>[
          TextButton(
            key: const Key('organize-trash-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('organize-trash-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('移到回收站'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final int done = await widget.store.deleteSets(_selected.toList());
    if (!mounted) return;
    _cancelSelecting();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已移到回收站 $done 组'),
      backgroundColor: Tokens.elevated,
    ));
  }

  /// 批量改动作：复用选动作页（它与"给这次训练挑动作"是同一套）。
  Future<void> _reassignSelected() async {
    if (_selected.isEmpty) return;
    final ExerciseData? picked = await Navigator.of(context).push<ExerciseData>(
      MaterialPageRoute<ExerciseData>(
        builder: (_) => ExercisePickerScreen(repository: widget.repository),
      ),
    );
    if (picked == null || !mounted) return;
    final int done = await widget.store.reassignSets(_selected.toList(), picked.id);
    if (!mounted) return;
    _cancelSelecting();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已把 $done 组改成「${picked.name}」'),
      backgroundColor: Tokens.elevated,
    ));
  }

  /// 多选态下的底部操作条
  Widget _selectionBar() => Container(
        key: const Key('all-data-selection-bar'),
        padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s3, Tokens.s5, Tokens.s3),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Tokens.line)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '已选 ${_selected.length} 组',
                style: const TextStyle(color: Tokens.text2, fontSize: Tokens.fsSub),
              ),
            ),
            TextButton(
              key: const Key('organize-cancel'),
              style: TextButton.styleFrom(foregroundColor: Tokens.text3),
              onPressed: _cancelSelecting,
              child: const Text('取消'),
            ),
            TextButton(
              key: const Key('organize-reassign'),
              style: TextButton.styleFrom(
                foregroundColor: _selected.isEmpty ? Tokens.text3 : Tokens.text2,
              ),
              onPressed: _selected.isEmpty ? null : _reassignSelected,
              child: const Text('改动作'),
            ),
            TextButton(
              key: const Key('organize-trash'),
              style: TextButton.styleFrom(
                foregroundColor: _selected.isEmpty ? Tokens.text3 : Tokens.danger,
              ),
              onPressed: _selected.isEmpty ? null : _moveSelectedToTrash,
              child: const Text('移到回收站'),
            ),
          ],
        ),
      );

  Widget _recordRow(SetRecord r) {
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(r.completedAtMs);
    final String day = formatDateAxis(d);
    final bool chosen = _selected.contains(r.id);
    // 多选态：整行可点、左边一枚勾；**只有 Ultra 能进这个态**（`_enterSelecting` 守着）
    // 非多选态：长按也能进来（比"先去右上角点整理"少一步，而长按在这个 App 里
    // 已经是"对某一行做更多事"的通用手势 —— 训练屏长按一行是撤销）。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _selecting ? () => _toggle(r.id) : null,
      onLongPress: _selecting ? null : () => _enterSelecting(withId: r.id),
      child: Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s2),
      child: Row(
        children: <Widget>[
          if (_selecting) ...<Widget>[
            Icon(
              chosen ? Icons.check_circle : Icons.circle_outlined,
              key: Key('all-data-pick-${r.id}'),
              color: chosen ? Tokens.success : Tokens.text3,
              size: IconSpec.m,
            ),
            const SizedBox(width: Tokens.s2),
          ],
          SizedBox(
            width: 48,
            child: Text(day,
                style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap)),
          ),
          // ⚠️ **中间那格要能缩**（2026-10-10 大字号扫描抓到：1.5× 下这一行 402pt > 331pt）：
          // 「65 kg × 10」在大字号下很宽，而右边的容量数字是**结论**、左边的日期是**定位**，
          // 真要挤的时候该让中间这一格先让步（省略号而不是把右边顶出去）。
          Expanded(
            child: Text(
              // 有氧/农夫行走念「5.00 公里 · 30:00」—— 容量那一格对它们是 0，
              // 光看"自重 × 1800"看不出这是跑还是走。
              r.hasDistance
                  ? '${formatDistanceKm(r.distanceM!)} · ${formatDurationHms(r.reps)}'
                  : r.weightKg == null
                      ? '自重 × ${r.reps}'
                      : '${formatWeight(r.weightKg, widget.unit)} × ${r.reps}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Tokens.text2, fontSize: Tokens.fsSub, fontWeight: Tokens.fwStrong),
            ),
          ),
          const SizedBox(width: Tokens.s2),
          Text(
            formatVolume(r.volume, widget.unit, zeroText: '—'),
            style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap),
          ),
        ],
      ),
      ),
    );
  }

  // ---------- 按时间 ----------

  Widget _byTime() {
    final PeriodReport? w = _week;
    final PeriodReport? m = _month;
    return ListView(
            padding: EdgeInsets.fromLTRB(
          Tokens.s5,
          Tokens.s4,
          Tokens.s5,
          Tokens.s6 + AppTabBar.reservedSpaceFor(context)),
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
                        style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap)),
                  ),
                  Text(
                    formatVolume(mv.volumeKg, widget.unit, zeroText: '—'),
                    style: const TextStyle(
                        color: Tokens.text2, fontSize: Tokens.fsSub, fontWeight: Tokens.fwStrong),
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
            style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsSub)),
      );
    }
    return Container(
      key: key,
      padding: const EdgeInsets.all(Tokens.s5),
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
          // 标签是"这行是什么"，值是**数据** —— 大字号下要挤时让标签先省略
          // （2026-10-10 扫描：2.0× 下这一行 434pt > 331pt）
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap)),
          ),
          const SizedBox(width: Tokens.s2),
          Text(
            value,
            key: key,
            style: Tokens.display(16, weight: 600),
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
            fontSize: Tokens.fsCap,
            fontWeight: Tokens.fwStrong,
            letterSpacing: Tokens.lsWide,
          ),
        ),
      );

  /// 一组"标签 - 数值"行。
  ///
  /// ⚠️ 2026-10-10：原来是一只**圆角实心方块**（`surface` 底 + `rCard` 圆角）。
  /// 用户说这一屏「全是大方块儿」—— 一屏三四只同款方块确实是这个观感。
  /// 现在只留**上下两条细线**（分节靠它们），行与行之间的留白由 `_statRow` 自己带。
  /// 与「进步」页同一条规矩：**只有图表还配卡片底**（`_trendCard` 没动）。
  Widget _card(List<Widget> children) => Container(
        width: double.infinity,
        // T1-8：这条带子里的行与 `ListTile` 的行走**同一个内边距**（`Tokens.s5`，
        // 见 `theme.dart` 的 `listTileTheme.contentPadding`）——
        // 在此之前 ListTile 行是 16 + 卡片 0，这条带子是 0，两个"记录列表"
        // 的文字不在同一列（差 16pt）。带子仍然只有上下两条 hair 线（分节靠它们）。
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s5, vertical: Tokens.s3),
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Tokens.hair),
            bottom: BorderSide(color: Tokens.hair),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}
