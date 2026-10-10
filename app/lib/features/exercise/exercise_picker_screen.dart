/// 练了么 · 动作选择页（S3）
///
/// 对应 `docs/screens.md` S3。目标：从打开到选中一个动作 ≤ 5 秒，不滚动。
/// 搜索同时匹配名称与别名（"bp" → 杠铃卧推，"rdl" → 罗马尼亚硬拉）。
///
/// 浏览态（没搜索、没筛部位）按规格分三区：**最近做过 / 常用 / 全部**，
/// 前两区把"打开就要选的那个动作"顶到首屏，不用滚动。
/// 一旦开始搜索或筛部位，就退回平铺列表 —— 那时用户已经知道自己在找什么。
library;

import '../../core/icon_spec.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/labels.dart';
import '../../core/fields.dart';
import '../../core/empty_state.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../data/db.dart';
import '../../data/exercise_repository.dart';
import '../../analytics/analytics.dart';
import '../../data/local_store.dart';
import '../../domain/models.dart' as domain;
import 'custom_exercise_screen.dart';
import 'exercise_detail_screen.dart';

class ExercisePickerScreen extends StatefulWidget {
  const ExercisePickerScreen({
    super.key,
    required this.repository,
    this.store,
    this.unit = WeightUnit.kg,
    this.analytics,
    this.onBrowse,
    this.initialMuscle,
  });

  final ExerciseRepository repository;

  /// 埋点。**可选**：不传就什么也不上报（测试与"单独打开这个页面"的场景）。
  final Analytics? analytics;

  /// 用来取「最近做过」。可选是为了不破坏只关心搜索的既有测试，
  /// 但**生产环境必须传** —— 不传就没有最近做过分区。
  final LocalStore? store;

  /// 显示单位。列表右侧的起始重量要跟着变。
  final WeightUnit unit;

  /// **浏览态**（2026-10-05，动作库页用）：点了动作**不"选中并返回"**，而是交给这个回调。
  ///
  /// 为什么必须区分：这个页面原本只有一种用法（在训练里选动作 → `pop(e)` 把结果带回去）。
  /// 动作库是**看**动作的地方 —— 传了它，点击就改成"打开这个动作的详情"；
  /// 不传，行为与以前一模一样（训练里选动作那条路一点没变）。
  final ValueChanged<ExerciseData>? onBrowse;

  /// **训练中换动作**（2026-10-05，v1.53）：进来就先把部位筛好。
  ///
  /// 为什么：器械被占时用户要的是"换一个**同部位**的动作"，
  /// 而不是从 351 个动作里重新找一遍 —— 那 20 秒正是训练被打断的时候。
  /// 传 null（默认）则与以前一模一样（不预筛）。
  final String? initialMuscle;

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

  /// **每个动作上一次练成什么样**（2026-10-10）。
  ///
  /// 为什么加：这一行右边原来印的是**种子默认重量**（`e.defaultWeightKg`，还带
  /// "总重（含杠铃杆）"这种口径说明）—— 那会被读成"我举过 40 kg"，其实它只是
  /// "第一次练就从这儿开始"的默认值。用户 10.10 评审点名了这一条。
  /// 有历史就念历史（`上次 45 kg × 10`），没有历史才退回默认值。
  ///
  /// 实现：**一次 `allSets()` 建一张表**，不是每行查一次库（这一屏最多 500 行）。
  Map<String, domain.SetRecord> _lastByExercise = const <String, domain.SetRecord>{};
  bool _loading = true;
  late String? _muscleGroup = widget.initialMuscle;

  /// 器械筛选。**居家 / 女性人群进来的第一道门** ——
  /// 只有一对哑铃的人不该被推荐杠铃卧推。
  String? _equipment;

  /// 类别筛选（热身 / 拉伸 / null=全部）。
  ///
  /// 2026-09-29 加了热身与拉伸这两个类别之后，得让用户**找得到它们** ——
  /// 这类动作的使用时机和力量动作不一样（练前 / 练后），
  /// 混在 500 条「全部动作」里排到最后等于没有。所以给它一行自己的 chip。
  String? _category;

  /// **细分标签**筛选（上胸 / 中缝 / 后束…，10.9 清单第 7 条）。
  ///
  /// 只在**选了某个主部位**时才有意义（"上胸"挂在胸下面）——所以那一行 chip 也是
  /// 选了部位才出现。换部位时它会跟着清掉（否则会出现"腿 + 上胸"这种筛不出东西的组合）。
  String? _subTag;

  /// 浏览态 = 没搜索、没筛部位、没筛器械、没筛类别。只有这个状态下才分区
  /// （分区是"我还不知道要练什么"时的陈列；筛过之后用户已经知道要找什么了）。
  bool get _browsing =>
      _query.text.trim().isEmpty &&
      _muscleGroup == null &&
      _equipment == null &&
      _category == null &&
      _subTag == null;

  @override
  void initState() {
    super.initState();
    _load();
    unawaited(_loadLastSets());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// 建"每个动作最近一组"的表（一次查询，见字段注释）。
  Future<void> _loadLastSets() async {
    final LocalStore? store = widget.store;
    if (store == null) return;
    try {
      final List<domain.SetRecord> sets = await store.allSets();
      final Map<String, domain.SetRecord> map = <String, domain.SetRecord>{};
      for (final domain.SetRecord r in sets) {
        final domain.SetRecord? prev = map[r.exerciseId];
        if (prev == null || r.completedAtMs > prev.completedAtMs) {
          map[r.exerciseId] = r;
        }
      }
      if (mounted) setState(() => _lastByExercise = map);
    } catch (_) {
      // 读不出来就当没有历史 —— 右边退回默认重量，其余一切照旧
    }
  }

  Future<void> _load() async {
    final bool browsing = _browsing;
    final List<ExerciseData> rows = await widget.repository.search(
      query: _query.text,
      muscleGroup: _muscleGroup,
      equipment: _equipment,
      category: _category,
      subTag: _subTag,
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
    // 浏览态：**不报 `exercise_added`**（那件事没发生），也不 pop —— 交给回调打开详情
    final ValueChanged<ExerciseData>? browse = widget.onBrowse;
    if (browse != null) {
      browse(e);
      return;
    }
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
                    // 浏览态里**不画返回键**：外层（动作库）自己有一个，
                    // 两个返回箭头并排会让人以为"要退两层"
                    child: widget.onBrowse != null
                        ? const SizedBox(width: 36)
                        : IconButton(
                            key: const Key('picker-back'),
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.chevron_left, color: Tokens.text2),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  // 浏览态（动作库）**不印这一行标题**：外层已经写着「动作库」了，
                  // 两行标题叠在一起读起来像"套了两层壳"（真机截图里一眼看到的问题）。
                  // 数量与「＋新建」照旧留着 —— 那两个是有用的信息/入口。
                  if (widget.onBrowse == null)
                    const Expanded(
                      child: Text(
                        '选动作',
                        style: TextStyle(
                          color: Tokens.text,
                          fontSize: Tokens.fsHeadline,
                          fontWeight: Tokens.fwBold,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  Text(
                    widget.onBrowse == null ? '${_rows.length} 个' : '共 ${_rows.length} 个动作',
                    style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap),
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
                    child: const Text('＋ 新建', style: TextStyle(fontSize: Tokens.fsSub)),
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
                style: const TextStyle(color: Tokens.text, fontSize: Tokens.fsBody),
                // ⚠️ 2026-10-10（VI 计划 T0-2）：这一格原来**没有边框**，
                // 底对页面只有 1.10:1 —— 暗光健身房里看不出这里能打字。
                // 现在走共用外观：`field` 底 + `lineStrong` 边界（3.18:1）。
                decoration: appFieldDecoration(
                  hint: '搜索动作或别名，如 bp / rdl',
                  fontSize: Tokens.fsBody,
                  radius: Tokens.rPill,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Tokens.s5,
                    vertical: Tokens.s4,
                  ),
                ),
              ),
            ),
            _filterRow('部位', <Widget>[
                    // ⚠️ 2026-10-10：未筛选时这一格是**中性色**，不再是强调橙 ——
                    // 原来四行里的"全部××"全是橙色选中态，一屏四处强调色，
                    // 把主操作都没了的地方（`interaction-spec` §4：一屏 accent ≤ 1）。
                    _chip('全部', _muscleGroup == null, () {
                      _muscleGroup = null;
                      // 部位清掉了，挂在它下面的细分标签也必须跟着清
                      _subTag = null;
                      _load();
                    }, neutralWhenActive: true),
                    for (final String k in kPrimaryMuscleGroups)
                      _chip(muscleLabel(k), _muscleGroup == k, () {
                        _muscleGroup = k;
                        _subTag = null;
                        _load();
                      }, key: 'muscle-$k'),
            ]),
            // **细分标签这一行**（2026-10-09，10.9 清单第 7 条）：选了部位才出现 ——
            // 用户点「胸」之后最想问的下一句就是"上胸还是中缝"。
            // 不选部位时这一行不存在（6 个部位的标签混在一起会长到看不懂）。
            if (_muscleGroup != null && subTagsFor(_muscleGroup!).isNotEmpty)
              _filterRow('细分', <Widget>[
                      _chip('全部', _subTag == null, () {
                        _subTag = null;
                        _load();
                      }, key: 'subtag-all'),
                      for (final String t in subTagsFor(_muscleGroup!))
                        _chip(t, _subTag == t, () {
                          _subTag = t;
                          _load();
                        }, key: 'subtag-$t'),
              ]),
            // 器械这一行：给"家里只有哑铃 / 只有自重"的人一条能走通的路。
            _filterRow('器械', <Widget>[
                    _chip('全部', _equipment == null, () {
                      _equipment = null;
                      _load();
                    }, key: 'equip-all', neutralWhenActive: true),
                    for (final MapEntry<String, String> e
                        in kEquipmentLabels.entries)
                      _chip(e.value, _equipment == e.key, () {
                        _equipment = e.key;
                        _load();
                      }, key: 'equip-${e.key}'),
            ]),
            // 类别这一行：热身与拉伸是**另外的使用时机**（练前 / 练后），
            // 不给入口的话它们就是 500 条列表的最后几条 —— 等于没有。
            _filterRow('类型', <Widget>[
                    _chip('全部', _category == null, () {
                      _category = null;
                      _load();
                    }, key: 'cat-all', neutralWhenActive: true),
                    // strength 不单独给 chip：它是这个 App 的默认语境，
                    // 「全部类型」减去热身与拉伸就是它。
                    for (final String c in const <String>['warmup', 'cardio', 'stretch'])
                      _chip(categoryLabel(c), _category == c, () {
                        _category = c;
                        _load();
                      }, key: 'cat-$c'),
            ]),
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

  /// 搜不到时的空态（T3-2）：原来只有两行灰字，**没有下一步** ——
  /// 而"搜不到"这件事的下一步非常明确：把关键词清掉再找一次。
  Widget _emptyState() => Center(
        child: EmptyState(
          key: const Key('empty-picker'),
          art: EmptyArt.ringSearch,
          title: '没找到这个动作。',
          body: '换个词试试，或者点右上角「＋ 新建」自建一个。',
          action: '清空关键词',
          onAction: () {
            // 清掉关键词就是"回到浏览态"（`_browsing` 那个 getter 会跟着变）
            _query.clear();
            setState(() {});
            _load();
          },
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
      // 同一份数据、两种叫法（2026-10-05）：选动作时叫「常用」（用户关心的是
      // "我常练的在哪"），动作库（浏览态）里叫「热门」—— 与 VI 稿 `vi/complete-library.html`
      // 那一屏的说法对齐。**排序口径是同一个**：种子里人工定的 `popularity`（内置固定排序，
      // 不引服务端、也不看别人的数据）。
      children.add(_sectionHeader(widget.onBrowse != null ? '热门' : '常用'));
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
            fontSize: Tokens.fsCap,
            fontWeight: Tokens.fwStrong,
            letterSpacing: Tokens.lsWide,
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
          fontSize: Tokens.fsBody,
          fontWeight: Tokens.fwStrong,
        ),
      ),
      // ⚠️ **2026-10-10：副标题压成一行**（用户 10.10 评审："每行 3 行描述扫不动"）。
      // 原来把 `instructions`（一句话动作要点）也接在这里，于是一行长到三行 ——
      // 351 条列表里全是字，扫不动。现在这里只留**分类信息**（部位 · 细分 · 器械），
      // 动作要点在**长按进的那一页**（`_openDetail`）里完整可读。
      subtitle: Text(
        <String>[
          e.category == 'strength'
              ? muscleLabel(e.muscleGroup)
              : '${categoryLabel(e.category)} · ${muscleLabel(e.muscleGroup)}',
          // 细分标签**接在部位后面**（"胸 · 上胸"）：搜「上胸」时得看得见
          // 它为什么被搜出来，否则那是一条无法解释的结果
          ...decodeSubTags(e.subTags),
          equipmentLabel(e.equipment),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        // 每行的「部位 · 器械」是选之前要读的东西 → text2（VI 计划 T0-3）
        style: const TextStyle(color: Tokens.text2, fontSize: Tokens.fsCap),
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
                size: IconSpec.m,
                color: pinned ? Tokens.accent : Tokens.text3,
              ),
              onPressed: () => _togglePin(e),
            ),
          // ⚠️ **2026-10-10：有历史就念历史**（"上次 45 kg × 10"）。
          // 原来这里印的是**种子默认重量**（还带"总重（含杠铃杆）"的口径说明）——
          // 那会被读成"我举过 40 kg"，其实它只是"第一次练从这儿开始"的默认值。
          // 没历史时才退回默认值 + 口径（那时它确实是"你会从这儿开始"）。
          if (_lastLabelFor(e) != null)
            Text(
              _lastLabelFor(e)!,
              key: Key('last-${e.id}'),
              style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap),
            )
          else ...<Widget>[
            Text(
              bodyweight ? '自重' : formatWeight(e.defaultWeightKg, widget.unit),
              style: const TextStyle(
                color: Tokens.text2,
                fontSize: Tokens.fsSub,
                fontWeight: Tokens.fwStrong,
              ),
            ),
            // 口径（10.8 清单第 6 条）：杠铃填总重（含杆）、哑铃填单只 ——
            // 用户就是在这一屏问"这一个还是两个"的，所以答案要印在**数字旁边**。
            // 器械/绳索/自重没有这个歧义，`weightBasisLabel` 返回空串、这里不占位。
            if (!bodyweight && weightBasisLabel(e.equipment).isNotEmpty) ...<Widget>[
              const SizedBox(width: 4),
              Text(
                weightBasisLabel(e.equipment),
                key: Key('basis-${e.id}'),
                style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// 一行筛选：**左边一个小标签**（部位 / 器械 / 类型 / 细分）+ 横向滚动的胶囊。
  ///
  /// ⚠️ 2026-10-10：标签是**新加的**。原来四行胶囊一个标签都没有，只能靠第一格
  /// "全部器械""全部类型"这种名字去猜这行是什么 —— 用户 10.10 评审点名了这条。
  Widget _filterRow(String label, List<Widget> chips) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, 0),
      child: SizedBox(
        height: 36,
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 30,
              child: Text(label,
                  key: Key('filter-label-$label'),
                  // 行标签是功能性标签（「这行筛的是什么」）→ text2（VI 计划 T0-3）
                  style: const TextStyle(color: Tokens.text2, fontSize: Tokens.fsMicro)),
            ),
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: chips,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 「上次 45 kg × 10」/「上次 5.00 公里」/「上次 自重 × 12」。没有历史返回 null。
  ///
  /// 与训练屏那条对照带**同一个口径**（`core/best_set.dart` 的兄弟函数）：
  /// 距离动作念里程、自重动作念"自重 × N"，不拿 0 kg 编一个数字。
  String? _lastLabelFor(ExerciseData e) {
    final domain.SetRecord? r = _lastByExercise[e.id];
    if (r == null) return null;
    final bool isTime = e.trackType == 'time';
    final String main;
    if (r.distanceM != null && r.distanceM! > 0) {
      main = formatDistanceKm(r.distanceM!);
    } else if (r.weightKg == null || r.weightKg! <= 0) {
      main = '自重 × ${r.reps}${isTime ? ' 秒' : ''}';
    } else {
      main = '${formatWeight(r.weightKg, widget.unit)} × ${r.reps}'
          '${isTime ? ' 秒' : ''}';
    }
    return '上次 $main';
  }

  Widget _chip(String label, bool active, VoidCallback onTap,
      {String? key, bool neutralWhenActive = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: Tokens.s2),
      child: GestureDetector(
        key: key == null ? null : Key(key),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
          decoration: BoxDecoration(
            // 「全部」在**什么都没筛**的时候用中性色：它是"默认"，不是一个选择
            // （详见 `neutralWhenActive` 的调用点）
            color: active && !neutralWhenActive ? Tokens.accent : Tokens.surface,
            borderRadius: BorderRadius.circular(Tokens.rPill),
            border: active && neutralWhenActive
                ? Border.all(color: Tokens.lineStrong)
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active && !neutralWhenActive ? Tokens.accentInk : Tokens.text2,
              fontSize: Tokens.fsCap,
              fontWeight: active && !neutralWhenActive
                  ? Tokens.fwBold
                  : Tokens.fwBody,
            ),
          ),
        ),
      ),
    );
  }
}
