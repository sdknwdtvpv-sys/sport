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
import '../../analytics/analytics.dart';
import '../../data/local_store.dart';
import 'custom_exercise_screen.dart';
import 'exercise_detail_screen.dart';

class ExercisePickerScreen extends StatefulWidget {
  const ExercisePickerScreen({
    super.key,
    required this.repository,
    this.store,
    this.unit = WeightUnit.kg,
    this.analytics,
  });

  final ExerciseRepository repository;

  /// 埋点。**可选**：不传就什么也不上报（测试与"单独打开这个页面"的场景）。
  final Analytics? analytics;

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

  /// 用户置顶的动作（**按他自己排的顺序**）。2026-10-04。
  ///
  /// 为什么要有它：分区（最近做过 / 常用 / 全部）都是**系统猜的**——
  /// 而"我就是要练这几个"只有用户自己知道。这是唯一一处用户能直接表态的地方。
  List<ExerciseData> _pinned = const <ExerciseData>[];
  bool _loading = true;
  String? _muscleGroup;

  /// 器械筛选。**居家 / 女性人群进来的第一道门** ——
  /// 只有一对哑铃的人不该被推荐杠铃卧推。
  String? _equipment;

  /// 类别筛选（热身 / 拉伸 / null=全部）。
  ///
  /// 2026-09-29 加了热身与拉伸这两个类别之后，得让用户**找得到它们** ——
  /// 这类动作的使用时机和力量动作不一样（练前 / 练后），
  /// 混在 500 条「全部动作」里排到最后等于没有。所以给它一行自己的 chip。
  String? _category;

  /// 浏览态 = 没搜索、没筛部位、没筛器械、没筛类别。只有这个状态下才分区
  /// （分区是"我还不知道要练什么"时的陈列；筛过之后用户已经知道要找什么了）。
  bool get _browsing =>
      _query.text.trim().isEmpty &&
      _muscleGroup == null &&
      _equipment == null &&
      _category == null;

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
      equipment: _equipment,
      category: _category,
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

    // 置顶**只在浏览态取**，与「最近做过」同一个理由：搜索/筛选是"我已经知道要找什么"，
    // 那时顶部分区只是噪音。而 _togglePin 之后也要能立刻反映出来，所以读的是一份状态。
    List<ExerciseData> pinned = const <ExerciseData>[];
    if (browsing && store != null) {
      final List<String> ids = await store.pinnedExerciseIds();
      final List<ExerciseData> loaded = <ExerciseData>[];
      for (final String id in ids) {
        final ExerciseData? e = await widget.repository.byId(id);
        // 置顶的动作被删了（自定义动作可以删）→ 静默跳过，不显示一个点不动的行
        if (e != null) loaded.add(e);
      }
      pinned = loaded;
    }

    if (!mounted) return;
    setState(() {
      _rows = rows;
      _recent = recent;
      _pinned = pinned;
      _loading = false;
    });
  }

  /// 选中一个动作返回。**同时上报它是从哪条路进来的**（`add_method`）。
  ///
  /// 为什么要问"从哪进来的"：选动作页有三个分区（最近做过 / 常用 / 全部动作）
  /// 外加搜索与新建。用户的入口分布直接说明"推荐有没有用"——
  /// 如果人人都从「全部动作」里翻，那「常用」就是白排的。
  ///
  /// 注：doc 里的枚举原本只有 suggest/search/recent/custom，这里多了 `all`
  /// （「全部动作」那一区）—— 硬把它归到 suggest 会让这个字段说谎，
  /// `docs/analytics.md` 已同步。
  /// 置顶 / 取消置顶。**刻意不发埋点**：这是一次罕见的偏好动作（不是漏斗里的一步），
  /// 而且"要发就得多一个新事件 → 同步中英政策 + 隐私事实表 + 两张商店表单"。
  /// 与回收站那次同一个判断（见 `trash_screen.dart` 的注释）。
  Future<void> _togglePin(ExerciseData e) async {
    final LocalStore? store = widget.store;
    if (store == null) return;
    final List<String> ids = <String>[
      for (final ExerciseData p in _pinned) p.id,
    ];
    if (ids.contains(e.id)) {
      ids.remove(e.id);
    } else {
      ids.add(e.id); // 新钉的放最后：先钉的先看见，不会因为再钉一个就跳位
    }
    await store.setPinnedExerciseIds(ids);
    await _load();
  }

  void _pick(ExerciseData e, {String method = 'all'}) {
    widget.analytics?.track('exercise_added', <String, Object?>{
      'exercise_id': e.id,
      'add_method': method,
    });
    Navigator.of(context).pop(e);
  }

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
                      foregroundColor: Tokens.accent,
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
                    for (final String k in kPrimaryMuscleGroups)
                      _chip(muscleLabel(k), _muscleGroup == k, () {
                        _muscleGroup = k;
                        _load();
                      }, key: 'muscle-$k'),
                  ],
                ),
              ),
            ),
            // 器械这一行：给"家里只有哑铃 / 只有自重"的人一条能走通的路。
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, 0),
              child: SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: <Widget>[
                    _chip('全部器械', _equipment == null, () {
                      _equipment = null;
                      _load();
                    }, key: 'equip-all'),
                    for (final MapEntry<String, String> e
                        in kEquipmentLabels.entries)
                      _chip(e.value, _equipment == e.key, () {
                        _equipment = e.key;
                        _load();
                      }, key: 'equip-${e.key}'),
                  ],
                ),
              ),
            ),
            // 类别这一行：热身与拉伸是**另外的使用时机**（练前 / 练后），
            // 不给入口的话它们就是 500 条列表的最后几条 —— 等于没有。
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, 0),
              child: SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: <Widget>[
                    _chip('全部类型', _category == null, () {
                      _category = null;
                      _load();
                    }, key: 'cat-all'),
                    // strength 不单独给 chip：它是这个 App 的默认语境，
                    // 「全部类型」减去热身与拉伸就是它。
                    for (final String c in const <String>['warmup', 'cardio', 'stretch'])
                      _chip(categoryLabel(c), _category == c, () {
                        _category = c;
                        _load();
                      }, key: 'cat-$c'),
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
    // 平铺列表 = 搜索结果的形态（`_load` 里一旦有关键词就走这条路）
    return ListView.separated(
      key: const Key('picker-list'),
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s6),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const Divider(color: Tokens.line, height: 1),
      itemBuilder: (BuildContext context, int i) =>
          _tile(_rows[i], method: 'search'),
    );
  }

  /// 浏览态分区：**最近做过 / 常用 / 全部动作**。
  ///
  /// 分区的意义就是规格那条「从打开到选中 ≤ 5 秒，不滚动」：
  /// 把最可能被选的动作顶到首屏，而不是让人在 318 个动作里翻。
  Widget _browseList() {
    final Set<String> recentIds =
        _recent.map((ExerciseData e) => e.id).toSet();
    // 置顶排在最前，且**从其它区里去掉** —— 同一个动作在首屏出现两次
    // 只会让人多滚一次（这条规矩在「常用」那儿已经写过一次了）。
    final Set<String> pinnedIds = _pinned.map((ExerciseData e) => e.id).toSet();
    // ⚠️ 「最近做过」也要去掉置顶的 —— 2026-10-04 在**真机上**才发现漏了这一处：
    // 只过滤了「常用 / 全部」，于是刚练过、又被置顶的那个动作**在同一屏出现两次**
    // （置顶区一次、最近做过一次）。测试当时没盖住，因为夹具里"最近做过"是空的、
    // 置顶的是另一个动作 —— 真机上两者恰好是同一个。
    final List<ExerciseData> recentShown = _recent
        .where((ExerciseData e) => !pinnedIds.contains(e.id))
        .toList();
    // 「常用」按 popularity 排序（repository.search 已保证），去掉已在「最近做过」
    // 里出现过的 —— 同一个动作在首屏出现两次只会让人多滚一次。
    final List<ExerciseData> popular = _rows
        .where((ExerciseData e) =>
            !recentIds.contains(e.id) && !pinnedIds.contains(e.id))
        .take(8)
        .toList();
    final Set<String> popularIds = popular.map((ExerciseData e) => e.id).toSet();
    final List<ExerciseData> rest = _rows
        .where((ExerciseData e) =>
            !pinnedIds.contains(e.id) &&
            !recentIds.contains(e.id) &&
            !popularIds.contains(e.id))
        .toList();

    final List<Widget> children = <Widget>[];
    if (_pinned.isNotEmpty) {
      children.add(_sectionHeader('置顶'));
      children.addAll(_pinned.map((ExerciseData e) => _tile(e, method: 'pinned')));
    }
    if (recentShown.isNotEmpty) {
      children.add(_sectionHeader('最近做过'));
      children.addAll(recentShown.map((ExerciseData e) => _tile(e, method: 'recent')));
    }
    if (popular.isNotEmpty) {
      children.add(_sectionHeader('常用'));
      children.addAll(popular.map((ExerciseData e) => _tile(e, method: 'suggest')));
    }
    if (rest.isNotEmpty) {
      children.add(_sectionHeader('全部动作'));
      children.addAll(rest.map((ExerciseData e) => _tile(e, method: 'all')));
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

  void _openDetail(ExerciseData e) {
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => ExerciseDetailScreen(
        exercise: e,
        store: widget.store,
        unit: widget.unit,
      ),
    ));
  }

  Widget _tile(ExerciseData e, {String method = 'all'}) {
    final bool bodyweight = e.weightIncrement == 0;
    final bool pinned = _pinned.any((ExerciseData p) => p.id == e.id);
    return ListTile(
      key: Key('exercise-${e.id}'),
      contentPadding: EdgeInsets.zero,
      onTap: () => _pick(e, method: method),
      // 长按看详情：这一行的副标题已经带了说明要点，长按才是"我要看全的"
      // （与「长按已完成的那一组可以撤销」是同一套手势语言）。
      onLongPress: () => _openDetail(e),
      title: Text(
        e.name,
        style: const TextStyle(
          color: Tokens.text,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      // 说明**接在副标题后面**（不另起一行）：351 个动作里只有一部分写了说明，
      // 另起一行会让"有没有说明"变成两行/一行的不齐；接在后面则一行放得下要点。
      subtitle: Text(
        <String>[
          e.category == 'strength'
              ? muscleLabel(e.muscleGroup)
              : '${categoryLabel(e.category)} · ${muscleLabel(e.muscleGroup)}',
          equipmentLabel(e.equipment),
          if (e.instructions != null && e.instructions!.isNotEmpty)
            e.instructions!,
        ].join(' · '),
        style: const TextStyle(color: Tokens.text3, fontSize: 13),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 置顶开关：**看得见的图标**，不是一个藏在长按里的动作
          // （长按已经是"看详情"了，而这一行要能被一眼看懂）。
          if (widget.store != null)
            IconButton(
              key: Key('pin-${e.id}'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              tooltip: pinned ? '取消置顶' : '置顶',
              icon: Icon(
                pinned ? Icons.push_pin : Icons.push_pin_outlined,
                size: 18,
                color: pinned ? Tokens.accent : Tokens.text3,
              ),
              onPressed: () => _togglePin(e),
            ),
          Text(
            bodyweight ? '自重' : formatWeight(e.defaultWeightKg, widget.unit),
            style: const TextStyle(
              color: Tokens.text2,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap, {String? key}) {
    return Padding(
      padding: const EdgeInsets.only(right: Tokens.s2),
      child: GestureDetector(
        key: key == null ? null : Key(key),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
          decoration: BoxDecoration(
            color: active ? Tokens.accent : Tokens.surface,
            borderRadius: BorderRadius.circular(Tokens.rPill),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Tokens.accentInk : Tokens.text2,
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
