/// 练了么 · 动作选择页（S3）
///
/// 对应 `docs/screens.md` S3。目标：从打开到选中一个动作 ≤ 5 秒，不滚动。
/// 搜索同时匹配名称与别名（"bp" → 杠铃卧推，"rdl" → 罗马尼亚硬拉）。
///
/// 浏览态（没搜索、没筛部位）按规格分三区：**最近做过 / 常用 / 全部**，
/// 前两区把"打开就要选的那个动作"顶到首屏，不用滚动。
/// 一旦开始搜索或筛部位，就退回平铺列表 —— 那时用户已经知道自己在找什么。
library;

import 'package:flutter/material.dart';

import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../data/db.dart';
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import 'custom_exercise_screen.dart';

class ExercisePickerScreen extends StatefulWidget {
  const ExercisePickerScreen({
    super.key,
    required this.repository,
    this.store,
    this.unit = WeightUnit.kg,
  });

  final ExerciseRepository repository;

  /// 用来取「最近做过」。可选是为了不破坏只关心搜索的既有测试，
  /// 但**生产环境必须传** —— 不传就没有最近做过分区。
  final LocalStore? store;

  /// 显示单位。列表右侧的起始重量要跟着变。
  final WeightUnit unit;

  @override
  State<ExercisePickerScreen> createState() => _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends State<ExercisePickerScreen> {
  final TextEditingController _query = TextEditingController();
  List<ExerciseData> _rows = const <ExerciseData>[];
  List<ExerciseData> _recent = const <ExerciseData>[];
  bool _loading = true;
  String? _muscleGroup;

  /// 浏览态 = 没搜索、没筛部位。只有这个状态下才分区。
  bool get _browsing => _query.text.trim().isEmpty && _muscleGroup == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final bool browsing = _browsing;
    final List<ExerciseData> rows = await widget.repository.search(
      query: _query.text,
      muscleGroup: _muscleGroup,
      // 浏览态要把「全部」也铺出来，所以多要一些；搜索态 60 条足够
      limit: browsing ? 500 : 60,
    );

    // 「最近做过」：store 早就有这个能力（S2 的部位轮转一直在用），
    // 但选择页以前完全没用上 —— 而这正是"打开就能选中"的关键。
    List<ExerciseData> recent = const <ExerciseData>[];
    final LocalStore? store = widget.store;
    if (browsing && store != null) {
      final List<String> ids = await store.recentExerciseIds();
      final List<ExerciseData> loaded = <ExerciseData>[];
      for (final String id in ids) {
        final ExerciseData? e = await widget.repository.byId(id);
        if (e != null) loaded.add(e);
      }
      recent = loaded;
    }

    if (!mounted) return;
    setState(() {
      _rows = rows;
      _recent = recent;
      _loading = false;
    });
  }

  void _pick(ExerciseData e) => Navigator.of(context).pop(e);

  /// 新建自定义动作（规格 S3 的「右上角」入口）。
  ///
  /// 建完**直接把新动作作为选择结果返回** —— 用户刚给它起了名字，
  /// 再让他回列表里找一遍是最烦的。
  Future<void> _newCustom() async {
    final ExerciseData? created = await Navigator.of(context).push<ExerciseData>(
      MaterialPageRoute<ExerciseData>(
        builder: (_) => CustomExerciseScreen(
          repository: widget.repository,
          unit: widget.unit,
        ),
      ),
    );
    if (created == null || !mounted) return;
    _pick(created);
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
                      key: const Key('picker-back'),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.chevron_left, color: Tokens.text2),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  const Expanded(
                    child: Text(
                      '选动作',
                      style: TextStyle(
                        color: Tokens.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${_rows.length} 个',
                    style: const TextStyle(color: Tokens.text3, fontSize: 13),
                  ),
                  const SizedBox(width: Tokens.s2),
                  // 规格 S3 的「右上角新建自定义动作」入口
                  TextButton(
                    key: const Key('picker-new-custom'),
                    onPressed: _newCustom,
                    style: TextButton.styleFrom(
                      foregroundColor: Tokens.volt,
                      padding: const EdgeInsets.symmetric(horizontal: Tokens.s3),
                      minimumSize: const Size(0, 36),
                    ),
                    child: const Text('＋ 新建', style: TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s5, 0),
              child: TextField(
                key: const Key('exercise-search'),
                controller: _query,
                onChanged: (_) => _load(),
                style: const TextStyle(color: Tokens.text, fontSize: 17),
                decoration: InputDecoration(
                  hintText: '搜索动作或别名，如 bp / rdl',
                  hintStyle: const TextStyle(color: Tokens.text3, fontSize: 17),
                  filled: true,
                  fillColor: Tokens.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Tokens.s5,
                    vertical: Tokens.s4,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Tokens.rPill),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s3, Tokens.s5, 0),
              child: SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: <Widget>[
                    _chip('全部', _muscleGroup == null, () {
                      _muscleGroup = null;
                      _load();
                    }),
                    for (final MapEntry<String, String> e in kMuscleLabels.entries)
                      _chip(e.value, _muscleGroup == e.key, () {
                        _muscleGroup = e.key;
                        _load();
                      }),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                      ? _emptyState()
                      : _browsing
                          ? _browseList()
                          : _flatList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() => const Center(
        child: Text(
          '没找到这个动作。\n换个词试试，或者点右上角「＋ 新建」自建一个。',
          textAlign: TextAlign.center,
          style: TextStyle(color: Tokens.text3, fontSize: 15, height: 1.5),
        ),
      );

  /// 搜索 / 筛部位时的平铺列表 —— 这时用户已经知道自己在找什么。
  Widget _flatList() {
    return ListView.separated(
      key: const Key('picker-list'),
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s6),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const Divider(color: Tokens.line, height: 1),
      itemBuilder: (BuildContext context, int i) => _tile(_rows[i]),
    );
  }

  /// 浏览态分区：**最近做过 / 常用 / 全部动作**。
  ///
  /// 分区的意义就是规格那条「从打开到选中 ≤ 5 秒，不滚动」：
  /// 把最可能被选的动作顶到首屏，而不是让人在 165 个动作里翻。
  Widget _browseList() {
    final Set<String> recentIds =
        _recent.map((ExerciseData e) => e.id).toSet();
    // 「常用」按 popularity 排序（repository.search 已保证），去掉已在「最近做过」
    // 里出现过的 —— 同一个动作在首屏出现两次只会让人多滚一次。
    final List<ExerciseData> popular = _rows
        .where((ExerciseData e) => !recentIds.contains(e.id))
        .take(8)
        .toList();
    final Set<String> popularIds = popular.map((ExerciseData e) => e.id).toSet();
    final List<ExerciseData> rest = _rows
        .where((ExerciseData e) =>
            !recentIds.contains(e.id) && !popularIds.contains(e.id))
        .toList();

    final List<Widget> children = <Widget>[];
    if (_recent.isNotEmpty) {
      children.add(_sectionHeader('最近做过'));
      children.addAll(_recent.map(_tile));
    }
    if (popular.isNotEmpty) {
      children.add(_sectionHeader('常用'));
      children.addAll(popular.map(_tile));
    }
    if (rest.isNotEmpty) {
      children.add(_sectionHeader('全部动作'));
      children.addAll(rest.map(_tile));
    }

    return ListView(
      key: const Key('picker-list'),
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, Tokens.s6),
      children: children,
    );
  }

  Widget _sectionHeader(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(0, Tokens.s4, 0, Tokens.s1),
        child: Text(
          label,
          style: const TextStyle(
            color: Tokens.text3,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      );

  Widget _tile(ExerciseData e) {
    final bool bodyweight = e.weightIncrement == 0;
    return ListTile(
      key: Key('exercise-${e.id}'),
      contentPadding: EdgeInsets.zero,
      onTap: () => _pick(e),
      title: Text(
        e.name,
        style: const TextStyle(
          color: Tokens.text,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        <String>[
          muscleLabel(e.muscleGroup),
          equipmentLabel(e.equipment),
        ].join(' · '),
        style: const TextStyle(color: Tokens.text3, fontSize: 13),
      ),
      trailing: Text(
        bodyweight ? '自重' : formatWeight(e.defaultWeightKg, widget.unit),
        style: const TextStyle(
          color: Tokens.text2,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: Tokens.s2),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
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
      ),
    );
  }
}
