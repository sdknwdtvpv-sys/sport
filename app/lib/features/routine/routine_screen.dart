/// 练了么 · S11 计划模板（列表 + 编辑）
///
/// 规格（`docs/screens.md` S11）：**简化版：只有动作 + 组数 + 次数区间；不做周期化**。
/// 所以这里刻意**不问重量、不问休息**：重量交给规则引擎建议
/// （`routine_item.target_weight_kg` 留 NULL 就是这个意思），
/// 休息沿用动作自带的值（或用户在 S10 设的偏好）。
///
/// 不自建一套动作选择：添加动作复用 S3 的动作选择器 ——
/// 那里已经有搜索、别名、最近做过与部位筛选。
library;

import 'package:flutter/material.dart';
import '../../domain/models.dart' show PlanTarget;

import 'plan_templates.dart';

import '../../core/pills.dart';
import '../../core/fields.dart';
import '../../core/theme.dart';
import '../../core/glass_overlay.dart';
import '../../core/units.dart';
import '../../data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import '../../data/routine_repository.dart';
import '../exercise/exercise_picker_screen.dart';

/// 用户点了「开始训练」时返回的东西。
class RoutineStart {
  const RoutineStart({required this.routine, required this.items});

  final RoutineData routine;
  final List<RoutineItemData> items;
}

/// 次数区间的预设档。**不做全键盘** —— 与项目其它地方的取向一致。
const List<({int low, int high})> kRepRanges = <({int low, int high})>[
  (low: 3, high: 5),
  (low: 5, high: 8),
  (low: 8, high: 10),
  (low: 10, high: 12),
  (low: 12, high: 15),
  (low: 15, high: 20),
];

const List<int> kSetChoices = <int>[1, 2, 3, 4, 5, 6];

// ---------------------------------------------------------------- 列表

class RoutineListScreen extends StatefulWidget {
  const RoutineListScreen({
    super.key,
    required this.repository,
    required this.exercises,
    this.unit = WeightUnit.kg,
    this.store,
    this.embedded = false,
  });

  final RoutineRepository repository;
  final ExerciseRepository exercises;
  final WeightUnit unit;

  /// 本地库：只用来把它传给选择器（置顶 / 最近做过两个分区）。可选。
  final LocalStore? store;

  /// **嵌进别的页面**（2026-10-05，训练计划 Tab 的「模板库」那一栏）。
  ///
  /// 传了它就不返回自己的 Scaffold 与标题行，只给内容 —— 否则会出现两个返回箭头、
  /// 两行标题（动作库那次已经吃过一遍同样的亏）。独立打开这条路一点没变。
  final bool embedded;

  @override
  State<RoutineListScreen> createState() => _RoutineListScreenState();
}

class _RoutineListScreenState extends State<RoutineListScreen> {
  List<RoutineData> _routines = const <RoutineData>[];
  Map<String, int> _counts = const <String, int>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<RoutineData> rows = await widget.repository.routines();
    final Map<String, int> counts = <String, int>{};
    for (final RoutineData r in rows) {
      counts[r.id] = (await widget.repository.items(r.id)).length;
    }
    if (!mounted) return;
    setState(() {
      _routines = rows;
      _counts = counts;
      _loading = false;
    });
  }

  /// 从**内置模板**建一份计划（2026-10-01）。
  ///
  /// 建出来的是一份**普通计划**（可改可删），只是 `source` 记着 `builtin` ——
  /// 这样以后能回答"新手到底用不用模板"，而不是靠猜。
  Future<void> _createFromTemplate(PlanTemplate t) async {
    final RoutineData r = await widget.repository.createFromPlan(
      t.name,
      <({String exerciseId, PlanTarget plan})>[
        for (final PlanTemplateItem it in t.items)
          (exerciseId: it.exerciseId, plan: planTargetOf(it)),
      ],
      source: 'builtin',
    );
    if (!mounted) return;
    await _edit(r.id);
    await _load();
  }

  Future<void> _create() async {
    final RoutineData r = await widget.repository.create('新计划');
    if (!mounted) return;
    await _edit(r.id);
    await _load();
  }

  /// 打开编辑页。
  ///
  /// ⚠️ 路由的结果类型必须是 `RoutineStart` —— 最初写的是 `<void>`，
  /// 于是用户在编辑页点「开始训练」时，那个结果被路由直接丢掉，
  /// 表现是"点了没反应"。（测试抓出来的。）
  Future<void> _edit(String routineId) async {
    final RoutineStart? start = await Navigator.of(context).push<RoutineStart>(
      MaterialPageRoute<RoutineStart>(
        builder: (_) => RoutineEditScreen(
          routineId: routineId,
          repository: widget.repository,
          exercises: widget.exercises,
          unit: widget.unit,
          store: widget.store,
        ),
      ),
    );
    if (start == null || !mounted) return;
    // 转发给列表页的调用方（S2）—— 只有它能真的开训
    Navigator.of(context).pop(start);
  }

  /// 开始训练：把这份计划交回给调用方（S2），由它走既有的开训路径。
  Future<void> _start(RoutineData r) async {
    final List<RoutineItemData> items = await widget.repository.items(r.id);
    if (!mounted) return;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('这个计划还没加动作'),
          // 弹层底：比卡片再抬一档（T1-2 的 sheet）
                backgroundColor: Tokens.sheet,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(Tokens.s5, 0, Tokens.s5, 80),
        ),
      );
      return;
    }
    Navigator.of(context).pop(RoutineStart(routine: r, items: items));
  }

  @override
  Widget build(BuildContext context) {
    // 嵌入模式：只要内容（壳与标题由嵌它的那一页负责）
    if (widget.embedded) {
      return Column(
        children: <Widget>[
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: Tokens.s5),
              child: TextButton(
                key: const Key('routine-create'),
                style: TextButton.styleFrom(foregroundColor: Tokens.accent),
                onPressed: _create,
                child: const Text('＋ 新建', style: TextStyle(fontSize: 14)),
              ),
            ),
          ),
          Expanded(child: _listBody()),
        ],
      );
    }
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, 0),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton(
                      key: const Key('routine-back'),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.chevron_left, color: Tokens.text2),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  const Expanded(
                    child: Text('我的计划',
                        style: TextStyle(
                            color: Tokens.text, fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    key: const Key('routine-create'),
                    style: TextButton.styleFrom(foregroundColor: Tokens.accent),
                    onPressed: _create,
                    child: const Text('＋ 新建', style: TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ),
            Expanded(child: _listBody()),
          ],
        ),
      ),
    );
  }

  /// 计划列表本体（独立打开与嵌进 Tab 都用它，只有一份实现）。
  Widget _listBody() => _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _routines.isEmpty
                      ? ListView(
                          // ⚠️ 空态**也得看得到模板**：2026-10-01 之前这里只有一句话，
                          // 而"没有计划"的人恰恰是最需要模板的人（空态被当成死胡同了）。
                          padding: const EdgeInsets.fromLTRB(
                              Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s6),
                          children: <Widget>[
                            const Padding(
                              padding: EdgeInsets.only(bottom: Tokens.s4),
                              child: Text(
                                '还没有计划。\n先用下面任意一套模板，'
                                '下次打开就直接照着练 —— 不用每次重新挑动作。',
                                style: TextStyle(color: Tokens.text3, fontSize: 15, height: 1.6),
                              ),
                            ),
                            const Text('从模板开始',
                                style: TextStyle(color: Tokens.text3, fontSize: 13)),
                            const SizedBox(height: Tokens.s2),
                            for (final PlanTemplate t in kPlanTemplates)
                              _templateRow(t),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(
                              Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s6),
                          children: <Widget>[
                            // 「从模板开始」放在最上面：不知道自己该练什么的人，
                            // 第一眼该看到的是这个，而不是"＋ 新建"。
                            const Text('从模板开始',
                                style: TextStyle(color: Tokens.text3, fontSize: 13)),
                            const SizedBox(height: Tokens.s2),
                            for (final PlanTemplate t in kPlanTemplates)
                              _templateRow(t),
                            const SizedBox(height: Tokens.s5),
                            const Text('我的计划',
                                style: TextStyle(color: Tokens.text3, fontSize: 13)),
                            const SizedBox(height: Tokens.s2),
                            for (final RoutineData r in _routines) _row(r),
                          ],
                        );

  /// 模板那一行：名字 + 一句说明 + 几个动作。
  Widget _templateRow(PlanTemplate t) {
    // ⚠️ 背景色必须交给 Material，不能放在中间的 DecoratedBox 上 ——
    // ListTile 的水波纹画在最近的 Material 祖先上，隔着带背景色的容器会把它盖住，
    // debug 下直接抛断言（`profile_widgets.dart` 里记过同一条）。
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s2),
      child: Material(
        color: Tokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.rCard),
          side: const BorderSide(color: Tokens.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
        key: Key('template-${t.id}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
        onTap: () => _createFromTemplate(t),
        // 名字 + **一眼标签**（2026-10-04）：标签是"要不要器械 / 什么时候用"的
        // 一行答案，坐在名字旁边才叫"一眼选中"（放到副标题里就得读第二行）。
        // 用 `Wrap` 而不是 `Row`：名字是一块**不可拆**的内容，标签放不下就整排换行。
        // 第一版用的 Row + Flexible，结果是名字被挤到折行（"上下肢 A · 下 / 肢"）——
        // 在真机截图里一眼就看出来了。
        title: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Tokens.s2,
          runSpacing: 2,
          children: <Widget>[
            Text(t.name,
                style: const TextStyle(color: Tokens.text, fontSize: 15)),
            for (int i = 0; i < t.tags.length; i++)
              Container(
                  key: Key('template-tag-${t.id}-$i'),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Tokens.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(Tokens.rPill),
                  ),
                  child: Text(
                    t.tags[i],
                    style: const TextStyle(
                        color: Tokens.accent, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
          ],
        ),
        subtitle: Text('${t.note} · ${t.items.length} 个动作',
            style: const TextStyle(color: Tokens.text3, fontSize: 13, height: 1.4)),
          trailing: const Icon(Icons.add_circle_outline, color: Tokens.accent, size: 20),
        ),
      ),
    );
  }

  Widget _row(RoutineData r) {
    final int n = _counts[r.id] ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: Tokens.s3),
      padding: const EdgeInsets.all(Tokens.s4),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              key: Key('routine-open-${r.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                await _edit(r.id);
                await _load();
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(r.name,
                      style: const TextStyle(
                          color: Tokens.text, fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: Tokens.s1),
                  Text(n == 0 ? '还没有动作' : '$n 个动作',
                      style: const TextStyle(color: Tokens.text3, fontSize: 13)),
                ],
              ),
            ),
          ),
          TextButton(
            key: Key('routine-start-${r.id}'),
            style: TextButton.styleFrom(foregroundColor: Tokens.accent),
            onPressed: () => _start(r),
            child: const Text('开始'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 编辑

class RoutineEditScreen extends StatefulWidget {
  const RoutineEditScreen({
    super.key,
    required this.routineId,
    required this.repository,
    required this.exercises,
    this.unit = WeightUnit.kg,
    this.store,
  });

  final String routineId;
  final RoutineRepository repository;
  final ExerciseRepository exercises;
  final WeightUnit unit;

  /// 本地库：传给选择器（置顶 / 最近做过）。可选。
  final LocalStore? store;

  @override
  State<RoutineEditScreen> createState() => _RoutineEditScreenState();
}

class _RoutineEditScreenState extends State<RoutineEditScreen> {
  final TextEditingController _name = TextEditingController();
  List<RoutineItemData> _items = const <RoutineItemData>[];
  final Map<String, ExerciseData> _byId = <String, ExerciseData>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final RoutineData? r = await widget.repository.byId(widget.routineId);
    final List<RoutineItemData> items =
        await widget.repository.items(widget.routineId);
    final Map<String, ExerciseData> names = <String, ExerciseData>{};
    for (final RoutineItemData i in items) {
      final ExerciseData? e = await widget.exercises.byId(i.exerciseId);
      if (e != null) names[i.exerciseId] = e;
    }
    if (!mounted) return;
    setState(() {
      _name.text = r?.name ?? '';
      _items = items;
      _byId
        ..clear()
        ..addAll(names);
      _loading = false;
    });
  }

  /// 改名即存。计划模板没有"保存"概念 —— 每一改都是真的。
  Future<void> _saveName(String v) async {
    if (v.trim().isEmpty) return;
    await widget.repository.rename(widget.routineId, v);
  }

  Future<void> _addExercise() async {
    final ExerciseData? picked = await Navigator.of(context).push<ExerciseData>(
      MaterialPageRoute<ExerciseData>(
        builder: (_) => ExercisePickerScreen(
          repository: widget.exercises,
          unit: widget.unit,
          store: widget.store,
        ),
      ),
    );
    if (picked == null) return;
    await widget.repository.addItem(widget.routineId, picked.id);
    await _load();
  }

  Future<void> _editItem(RoutineItemData item) async {
    final ({int sets, int low, int high})? next = await showAppSheet<
        ({int sets, int low, int high})>(
      context: context,
      // 弹层底：比卡片再抬一档（T1-2 的 sheet）
                backgroundColor: Tokens.sheet,
      // 默认的弹层高度上限约半屏，装不下两排 chips + 按钮时
      // 保存按钮会被裁掉（测试里点不到）。放开高度并让它自己滚。
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.rSheet)),
      ),
      builder: (_) => _ItemEditor(item: item),
    );
    if (next == null) return;
    await widget.repository.updateItem(
      item.id,
      targetSets: next.sets,
      targetRepsLow: next.low,
      targetRepsHigh: next.high,
    );
    await _load();
  }

  Future<void> _removeItem(RoutineItemData item) async {
    await widget.repository.removeItem(item.id);
    await _load();
  }

  Future<void> _start() async {
    final RoutineData? r = await widget.repository.byId(widget.routineId);
    final List<RoutineItemData> items =
        await widget.repository.items(widget.routineId);
    if (!mounted) return;
    if (r == null || items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('先加几个动作'),
          // 弹层底：比卡片再抬一档（T1-2 的 sheet）
                backgroundColor: Tokens.sheet,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(Tokens.s5, 0, Tokens.s5, 80),
        ),
      );
      return;
    }
    Navigator.of(context).pop(RoutineStart(routine: r, items: items));
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
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton(
                      key: const Key('routine-edit-back'),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.chevron_left, color: Tokens.text2),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  const Expanded(
                    child: Text('编辑计划',
                        style: TextStyle(
                            color: Tokens.text, fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else ...<Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s5, 0),
                child: TextField(
                  key: const Key('routine-name'),
                  controller: _name,
                  style: const TextStyle(
                      color: Tokens.text, fontSize: 20, fontWeight: FontWeight.w700),
                  decoration: appFieldDecoration(
                    hint: '计划名称，如「推日」',
                    fontSize: 20,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: Tokens.s4, vertical: Tokens.s4),
                  ),
                  onSubmitted: _saveName,
                  onTapOutside: (_) => _saveName(_name.text),
                ),
              ),
              Expanded(
                child: ListView(
                  padding:
                      const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s6),
                  children: <Widget>[
                    if (_items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: Tokens.s5),
                        child: Text(
                          '还没有动作。加几个，下次直接照着练。',
                          style: TextStyle(color: Tokens.text3, fontSize: 15, height: 1.5),
                        ),
                      ),
                    for (final RoutineItemData i in _items) _itemRow(i),
                    const SizedBox(height: Tokens.s3),
                    OutlinedButton.icon(
                      key: const Key('routine-add-exercise'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Tokens.text,
                        side: const BorderSide(color: Tokens.lineStrong),
                        minimumSize: const Size(0, 52),
                      ),
                      onPressed: _addExercise,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('添加动作'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Tokens.s5, 0, Tokens.s5, Tokens.s4),
                child: SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: FilledButton(
                    key: const Key('routine-start'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Tokens.accent,
                      foregroundColor: Tokens.accentInk,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Tokens.rPill),
                      ),
                    ),
                    onPressed: _start,
                    child: const Text('开始训练',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _itemRow(RoutineItemData i) {
    final ExerciseData? e = _byId[i.exerciseId];
    return Container(
      margin: const EdgeInsets.only(bottom: Tokens.s2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              key: Key('routine-item-${i.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _editItem(i),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(e?.name ?? i.exerciseId,
                      style: const TextStyle(
                          color: Tokens.text, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: Tokens.s1),
                  Text('${i.targetSets} 组 · ${i.targetRepsLow}–${i.targetRepsHigh} 次',
                      key: Key('routine-item-label-${i.id}'),
                      style: const TextStyle(color: Tokens.text3, fontSize: 13)),
                ],
              ),
            ),
          ),
          IconButton(
            key: Key('routine-item-remove-${i.id}'),
            icon: const Icon(Icons.close, color: Tokens.text3, size: 20),
            onPressed: () => _removeItem(i),
          ),
        ],
      ),
    );
  }
}

/// 组数 + 次数区间的小编辑层。**只有这两样** —— 简化版的全部范围。
class _ItemEditor extends StatefulWidget {
  const _ItemEditor({required this.item});

  final RoutineItemData item;

  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late int _sets = widget.item.targetSets;
  late int _low = widget.item.targetRepsLow;
  late int _high = widget.item.targetRepsHigh;

  @override
  Widget build(BuildContext context) {
    // 紧凑排版：两排 chips + 按钮要能在一屏里放下。
    // 之前用 s5/s2 的间距时，800×600 下按钮落到了 y=614 —— 超出屏幕，
    // 用户得先滚一下才能点到「确定」。
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('组数',
              style: TextStyle(
                  color: Tokens.text3, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: Tokens.s1),
          Wrap(
            spacing: Tokens.s2,
            children: <Widget>[
              for (final int s in kSetChoices)
                _chip('set-$s', '$s', _sets == s, () => setState(() => _sets = s)),
            ],
          ),
          const SizedBox(height: Tokens.s4),
          const Text('次数区间',
              style: TextStyle(
                  color: Tokens.text3, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: Tokens.s1),
          Wrap(
            spacing: Tokens.s1,
            runSpacing: Tokens.s1,
            children: <Widget>[
              for (final ({int low, int high}) r in kRepRanges)
                _chip('reps-${r.low}-${r.high}', '${r.low}–${r.high}',
                    _low == r.low && _high == r.high,
                    () => setState(() {
                          _low = r.low;
                          _high = r.high;
                        })),
            ],
          ),
          const SizedBox(height: Tokens.s4),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              key: const Key('routine-item-save'),
              style: FilledButton.styleFrom(
                backgroundColor: Tokens.accent,
                foregroundColor: Tokens.accentInk,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Tokens.rPill),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(
                (sets: _sets, low: _low, high: _high),
              ),
              child: const Text('确定',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String key, String label, bool active, VoidCallback onTap) {
    // ⚠️ 别再手写一遍 `Container(alignment: ...)`：它会被 `Wrap` 的有界宽度撑成通栏
    // （组数/次数各占一整行）。共用件见 `core/pills.dart`。
    return choicePill(label: label, active: active, onTap: onTap, key: Key(key));
  }
}
