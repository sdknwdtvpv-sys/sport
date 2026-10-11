/// 练了么 · 动作详情
///
/// **它回答三个问题**（用户练到一半掏出手机时真正想问的）：
///   1. 这个动作怎么做？（完整动作说明 + 目标肌群）
///   2. 练的是哪儿、用什么器械？（部位 / 器械 / 类别）
///   3. 我以前练成什么样？（最近几次 + 历史最好）
///
/// 详情页是**只读**的：改重量、改组数、选动作各有各的入口，
/// 这里只负责看清楚。进来的人多半正在深蹲架旁边，所以信息密度比美观重要。
///
/// [store] 可空：没有它就不显示历史（测试与无库场景）。
/// 这也是仓库里一贯的注入风格 —— 依赖可选，缺了降级而不是崩。
library;

import 'package:flutter/material.dart';

import '../../core/icon_spec.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../data/db.dart' show ExerciseData;
import '../../data/exercise_data_ext.dart';
import '../../data/local_store.dart';
import '../../data/repdb_art.dart' show ExerciseArt, RepdbArt, RepdbArtCatalog;
import '../../domain/models.dart';
import '../progress/all_data.dart';
import '../../core/labels.dart';

class ExerciseDetailScreen extends StatefulWidget {
  const ExerciseDetailScreen({
    super.key,
    required this.exercise,
    this.store,
    this.today,
    this.unit = WeightUnit.kg,
  });

  final ExerciseData exercise;

  /// 有它才显示"最近几次 / 历史最好"
  final LocalStore? store;

  /// 可注入的"今天"，测试用
  final DateTime? today;

  final WeightUnit unit;

  @override
  State<ExerciseDetailScreen> createState() => _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends State<ExerciseDetailScreen> {
  ExerciseStats? _stats;
  SetRecord? _best;
  List<ExerciseDayEntry> _recent = const <ExerciseDayEntry>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _loadArt();
  }

  /// 插图清单是**异步**读出来的（asset → JSON），而这一屏不等它：
  /// 文字说明才是用户点进来的原因。读到了就 `setState` 一次补上图。
  ///
  /// 已经有缓存时（第二次进详情页）走同步路径，不闪。
  Future<void> _loadArt() async {
    if (RepdbArt.cached != null) return;
    final RepdbArtCatalog catalog = await RepdbArt.catalog();
    if (!mounted || catalog.count == 0) return;
    setState(() {});
  }

  Future<void> _load() async {
    final LocalStore? store = widget.store;
    if (store == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final List<SetRecord> sets =
          await store.setsForExercise(widget.exercise.id);
      if (!mounted) return;
      setState(() {
        _stats = buildExerciseStats(
          exerciseId: widget.exercise.id,
          name: widget.exercise.name,
          sets: sets,
          today: widget.today ?? DateTime.now(),
          isTime: isTimeTrack(widget.exercise.trackType),
        );
        // "历史最好"要挑**真实存在的那一组**：stats 里的 bestWeight 与 bestReps
        // 是各自取最大，拼起来会出现没有一组做到过的组合（见 bestSetOf 的注释）。
        _best = bestSetOf(
          sets,
          isTime: isTimeTrack(widget.exercise.trackType),
        );
        _recent = groupSetsByDay(sets, limit: 3);
        _loading = false;
      });
    } catch (_) {
      // 历史读不出来不该挡住"这个动作怎么做"——那才是他点进来的原因
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ExerciseData e = widget.exercise;
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s3, Tokens.s5, Tokens.s8),
          children: <Widget>[
            _header(e),
            const SizedBox(height: Tokens.s5),
            // 插图（有就画，没有就什么都不画 —— 见 data/repdb_art.dart 的"缺失就降级"）
            if (RepdbArt.of(e.id) != null) ...<Widget>[
              _ArtCard(art: RepdbArt.of(e.id)!),
              const SizedBox(height: Tokens.s4),
            ],
            if (e.instructions != null && e.instructions!.trim().isNotEmpty)
              _howTo(e.instructions!.trim())
            else
              _howToMissing(),
            const SizedBox(height: Tokens.s6),
            _facts(e),
            const SizedBox(height: Tokens.s6),
            _history(),
          ],
        ),
      ),
    );
  }

  // ---------- 顶部 ----------

  Widget _header(ExerciseData e) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 36,
          height: 36,
          child: IconButton(
            key: const Key('detail-back'),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.chevron_left, color: Tokens.text2),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        const SizedBox(width: Tokens.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                e.name,
                style: const TextStyle(
                  color: Tokens.text,
                  fontSize: Tokens.fsNum,
                  fontWeight: Tokens.fwBold,
                ),
              ),
              if (e.nameEn != null && e.nameEn!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    e.nameEn!,
                    style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap),
                  ),
                ),
              // 别名：搜得到但看不到，等于没写。这里显式列出来。
              if (e.aliasList.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '也叫：${e.aliasList.join(' / ')}',
                    style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- 怎么做 ----------

  Widget _howTo(String text) {
    return Container(
      padding: const EdgeInsets.all(Tokens.s5),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
        border: Border.all(color: Tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '怎么做',
            style: TextStyle(
              color: Tokens.accent,
              fontSize: Tokens.fsCap,
              fontWeight: Tokens.fwBold,
            ),
          ),
          const SizedBox(height: Tokens.s2),
          Text(
            text,
            key: const Key('detail-instructions'),
            style: const TextStyle(color: Tokens.text, fontSize: Tokens.fsBodyS, height: Tokens.lhNormal),
          ),
        ],
      ),
    );
  }

  /// 说明缺失时**如实说**，不留空行也不编一句通用话术。
  /// （当前 351 个动作全都有说明，所以这条是兜底：将来加了动作没写说明会走到这里。）
  Widget _howToMissing() {
    return Container(
      padding: const EdgeInsets.all(Tokens.s5),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
        border: Border.all(color: Tokens.line),
      ),
      child: const Text(
        '这个动作还没有写说明 —— 你可以先按自己的做法练，'
        '或换个更熟的动作。',
        key: Key('detail-instructions-missing'),
        style: TextStyle(color: Tokens.text2, fontSize: Tokens.fsSub, height: Tokens.lhNormal),
      ),
    );
  }

  // ---------- 事实 ----------

  Widget _facts(ExerciseData e) {

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          '基本事实',
          style: TextStyle(
            color: Tokens.text2,
            fontSize: Tokens.fsCap,
            fontWeight: Tokens.fwBold,
          ),
        ),
        const SizedBox(height: Tokens.s3),
        Wrap(
          spacing: Tokens.s2,
          runSpacing: Tokens.s2,
          children: <Widget>[
            _chip(categoryLabel(e.category)),
            _chip(muscleLabel(e.muscleGroup)),
            _chip(equipmentLabel(e.equipment)),
            if (e.secondaryMuscleList.isNotEmpty)
              _chip('辅助：${e.secondaryMuscleList.map(muscleLabel).join('、')}'),
          ],
        ),
        // 重量口径（10.8 清单第 6 条）：这一句是**答案**，不是解释性废话 ——
        // 用户原话是"杠铃动作的重量是一个的还是两个的？计算容量的时候怎么算？"。
        // 只对"有歧义"的器械显示（器械/绳索/自重没有单边还是总重这个问题）。
        if (weightBasisLabel(e.equipment).isNotEmpty) ...<Widget>[
          const SizedBox(height: Tokens.s3),
          Text(
            '重量填${weightBasisLabel(e.equipment)} · ${volumeBasisLabel(e.equipment)}',
            key: const Key('detail-weight-basis'),
            style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap, height: Tokens.lhNormal),
          ),
        ],
      ],
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Tokens.elevated,
        borderRadius: BorderRadius.circular(Tokens.rPill),
        border: Border.all(color: Tokens.line),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Tokens.text2, fontSize: Tokens.fsCap),
      ),
    );
  }

  // ---------- 历史 ----------

  Widget _history() {
    final LocalStore? store = widget.store;
    if (store == null) {
      return const SizedBox.shrink();
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Tokens.s4),
        child: Text('正在看你的历史…',
            style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsSub)),
      );
    }
    final ExerciseStats? s = _stats;
    if (s == null || s.setCount == 0) {
      return Container(
        padding: const EdgeInsets.all(Tokens.s5),
        decoration: BoxDecoration(
          color: Tokens.surface,
          borderRadius: BorderRadius.circular(Tokens.rCard),
          border: Border.all(color: Tokens.line),
        ),
        child: const Text(
          '这个动作你还没练过。',
          key: Key('detail-no-history'),
          style: TextStyle(color: Tokens.text2, fontSize: Tokens.fsSub),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          '我以前练成什么样',
          style: TextStyle(
            color: Tokens.text2,
            fontSize: Tokens.fsCap,
            fontWeight: Tokens.fwBold,
          ),
        ),
        const SizedBox(height: Tokens.s3),
        _bestRow(s, _best),
        const SizedBox(height: Tokens.s4),
        for (final ExerciseDayEntry day in _recent) _dayRow(day, s.isTime),
      ],
    );
  }

  Widget _bestRow(ExerciseStats s, SetRecord? best) {
    // 按时长动作的"最好"是秒数；自重动作比次数；负重比"重量 × 次数"**同一组**。
    final String bestText;
    if (best == null) {
      bestText = '—';
    } else if (s.isTime) {
      bestText = '${best.reps} 秒';
    } else if (best.weightKg == null) {
      bestText = '${best.reps} 次';
    } else {
      bestText = '${formatWeight(best.weightKg, widget.unit)} × ${best.reps}';
    }
    return Container(
      padding: const EdgeInsets.all(Tokens.s5),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
        border: Border.all(color: Tokens.line),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _stat('历史最好', bestText, const Key('detail-best')),
          ),
          Expanded(
            child: _stat('总组数', '${s.setCount} 组', const Key('detail-sets')),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Key key) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
        const SizedBox(height: 4),
        Text(
          value,
          key: key,
          style: const TextStyle(
            color: Tokens.text,
            fontSize: Tokens.fsBody,
            fontWeight: Tokens.fwBold,
          ),
        ),
      ],
    );
  }

  /// 一天一行：`9/29 · 3 组 · 40 kg × 8 · 8 · 8`
  Widget _dayRow(ExerciseDayEntry day, bool isTime) {
    final List<String> reps = day.sets
        .map((SetRecord r) => isTime ? '${r.reps}秒' : '${r.reps}')
        .toList();
    final double? w = day.sets
        .map((SetRecord r) => r.weightKg)
        .firstWhere((double? x) => x != null, orElse: () => null);
    final String load = w == null ? '自重' : formatWeight(w, widget.unit);
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s3),
      child: Row(
        key: Key('detail-day-${day.date}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 52,
            child: Text(
              _prettyDate(day.date),
              style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsSub),
            ),
          ),
          Expanded(
            child: Text(
              '${day.setCount} 组 · $load × ${reps.join(' · ')}',
              style: const TextStyle(color: Tokens.text, fontSize: Tokens.fsSub),
            ),
          ),
        ],
      ),
    );
  }

  /// `2026-09-29` → `9/29`（详情页里不需要年份，短了才看得清）
  static String _prettyDate(String iso) {
    final List<String> parts = iso.split('-');
    if (parts.length != 3) return iso;
    return '${int.tryParse(parts[1]) ?? parts[1]}/${int.tryParse(parts[2]) ?? parts[2]}';
  }
}

/// 动作插图（RepDB 免费档静图）。
///
/// **为什么放在说明卡上方而不是下方**：用户点进详情页时，第一个问题是"这个动作
/// 长什么样"——图先回答它，文字再补"最容易错的点"。反过来（先文字后图）会让人
/// 读完一段字才发现下面有图。
///
/// **为什么图里画的人和 App 里其他地方不一样也没关系**：插图是"动作是什么样"的
/// 示意，不是我们的品牌视觉。做成**有边界的图片框**（圆角 + 细线 + 固定底色）
/// 就是承认这一点：它是一张贴进来的图，不是我们的插画体系。
///
/// 两张姿势（start / peak）时给一个切换：`peak` 是默认（最能看出这个动作的一张）。
/// 单张图（拉伸/静力）没有切换。**边上有"AI 生成"标注** —— 这些图是 RepDB 用
/// AI 工具生成后人工挑选的（许可原文 Origin of the data 一节），
/// 国内《人工智能生成合成内容标识办法》（2025-09-01 生效）要求标识，所以写出来。
/// 完整出处与许可在「我」→「隐私与关于」→「动作插图来源」。
class _ArtCard extends StatefulWidget {
  const _ArtCard({required this.art});

  final ExerciseArt art;

  @override
  State<_ArtCard> createState() => _ArtCardState();
}

class _ArtCardState extends State<_ArtCard> {
  /// true = 显示 peak（默认），false = 显示 start
  bool _peak = true;

  @override
  Widget build(BuildContext context) {
    final ExerciseArt art = widget.art;
    final String? path = _peak ? art.hero : art.start;
    final bool canToggle = art.hasSecondPose && path != null;
    return Column(
      key: const Key('detail-art'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            // 插图自带浅色底（RepDB 的扁平风是实色背景），所以给一个中性底把
            // 圆角外的像素统一掉，避免浅色方块直接怼在深色页面上显得像漏图。
            color: Tokens.elevated,
            borderRadius: BorderRadius.circular(Tokens.rCard),
            border: Border.all(color: Tokens.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: 1,
            child: Image.asset(
              path ?? '',
              key: const Key('detail-art-image'),
              fit: BoxFit.cover,
              // 内存：425 张图各自 320×320，整包解码会很大；这里按实际绘制宽度解码。
              cacheWidth: (MediaQuery.of(context).size.width *
                      MediaQuery.of(context).devicePixelRatio)
                  .round(),
              // 文件缺失（清单与实物不一致）**不该崩**：画一个安静的占位，
              // 因为"少一张图"远好过"详情页红屏"。守卫会去抓清单不一致。
              errorBuilder: (_, __, ___) => Center(
                child: Icon(iconOf('imageMissing'),
                    color: Tokens.text3, size: IconSpec.m),
              ),
            ),
          ),
        ),
        const SizedBox(height: Tokens.s2),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                // 标注"AI 生成"是合规要求（见类文档），不是排版偏好
                '示意图 · AI 生成 · RepDB',
                key: const Key('detail-art-caption'),
                style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro),
              ),
            ),
            if (canToggle)
              GestureDetector(
                key: const Key('detail-art-toggle'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _peak = !_peak),
                child: Text(
                  _peak ? '看起始姿势' : '看顶峰姿势',
                  // 橙色文字只许走 accentText（accent_budget_test 守着这条）
                  style: const TextStyle(color: Tokens.accentText, fontSize: Tokens.fsCap),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
