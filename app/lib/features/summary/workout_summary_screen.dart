/// 练了么 · S7 训练结束总结
///
/// 对应 `docs/screens.md` S7。训练闭环的收尾。
///
/// **一处有意的范围裁剪**：规格里的「生成分享卡图片」在本版**没有实现**。
/// 那需要 RepaintBoundary.toImage() 加相册写入插件与平台通道，
/// 是我在受限环境里无法验证的东西 —— 做出来只会是"看起来完成了但没人跑过"的代码。
/// 数据部分（三项大数 + 破纪录）先做扎实，分享卡列在 ROADMAP 的后续增量里。
library;

import 'package:flutter/material.dart';

import '../../analytics/analytics.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../core/vi_cards.dart';
import '../../data/db.dart' show ExerciseData;
import '../progress/badges.dart';
import 'share_card_exporter.dart';
import 'share_card_preview_screen.dart';
import 'tips.dart';
import 'workout_summary.dart';

class WorkoutSummaryScreen extends StatefulWidget {
  const WorkoutSummaryScreen({
    super.key,
    required this.service,
    required this.workoutId,
    this.unit = WeightUnit.kg,
    this.exporter = const PluginShareCardExporter(),
    this.stretches = const <ExerciseData>[],
    this.nextLine,
    this.analytics,
    this.streak = 0,
    this.ordinal,
    this.newBadges = const <BadgeStatus>[],
    this.onOpenAchievements,
  });

  final SummaryService service;
  final String workoutId;

  /// 显示单位。**只影响显示**：服务算出来的量与 PR 判定始终是 kg。
  final WeightUnit unit;

  /// 练完建议拉伸的 1–2 个动作（由调用方按今天练的部位算好传进来）。
  ///
  /// 为空就整块不显示 —— 不做"没有数据也占一块地方"的界面。
  final List<ExerciseData> stretches;

  /// 「下一次练什么」那一行（2026-10-01 加的）。
  ///
  /// 为什么放在总结页：**刚练完的那一刻是唯一一个用户愿意想"下一次"的时刻** ——
  /// 等他回到首页，注意力已经散了。文案由调用方算好（壳层手里有 planner 与历史），
  /// 这一屏只负责显示；传 null 就不显示。
  final String? nextLine;

  /// 埋点（可选）。用它上报 `pr_achieved` —— 破纪录是留存钩子，
  /// 而"这个钩子有没有用"目前没有任何数据能回答。
  final Analytics? analytics;

  /// 连续打卡天数与"第几次训练"（2026-10-05）：分享卡的打卡版要用。
  /// 由外壳算好传进来 —— **不在这一屏现算**，否则同一件事会有两份口径。
  final int streak;
  final int? ordinal;

  /// **这一场新挣到的徽章**（2026-10-10）。
  ///
  /// 由外壳用**差额法**算好传进来（`badges.dart` 的 `newlyUnlockedBadges`：
  /// 把刚练完这一场的组排除再算一遍，两次一减）—— 徽章是纯函数，没有"解锁事件"表，
  /// 不需要为这一条新增任何落库状态。
  /// **空列表 = 这块整个不出现**（不是摆一句"暂无新徽章"）。
  final List<BadgeStatus> newBadges;

  /// 点「全部 ›」去哪（外壳接上成就页）。不传就没有那个入口。
  final VoidCallback? onOpenAchievements;

  /// 分享卡的交付实现。测试里换成假的（插件调用在 widget 测试里跑不了）。
  final ShareCardExporter exporter;

  @override
  State<WorkoutSummaryScreen> createState() => _WorkoutSummaryScreenState();
}

class _WorkoutSummaryScreenState extends State<WorkoutSummaryScreen> {
  WorkoutSummary? _summary;
  bool _loading = true;

  /// 一句话笔记（2026-10-04）。列早就存在，但在此之前**没有任何写入路径**
  /// （`progress_screen` 一直在显示它，所以它是个"只读的死字段"）。
  late final TextEditingController _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// 保存笔记。**幂等**，调用点有三个：点「完成」、按回车、离开这一屏。
  ///
  /// 为什么不 debounce 逐字写库：这一屏是**低频**屏（一次训练走一次），
  /// 一句话也就几十个字；而漏保存的代价是用户白写 —— 宁可多写几次。
  Future<void> _saveNote() async {
    final WorkoutSummary? s = _summary;
    if (s == null) return;
    if ((s.note ?? '') == _note.text.trim()) return; // 没改就不写
    await widget.service.setNote(s.workoutId, _note.text);
  }

  Future<void> _load() async {
    final WorkoutSummary? s =
        await widget.service.build(widget.workoutId, unit: widget.unit);
    if (!mounted) return;
    // `pr_achieved`：每破一次纪录上报一条。
    // 放在这里（而不是界面渲染里）是因为它必须**只报一次** ——
    // 渲染函数会被调用很多次，把埋点放进去会重复计数。
    for (final SetPr p in s?.prs ?? const <SetPr>[]) {
      widget.analytics?.track('pr_achieved', <String, Object?>{
        'exercise_id': p.exerciseId,
        // 有重量的比公斤、自重的比次数、按时长的比秒数
        'pr_type': p.isTime ? 'time' : (p.isBodyweight ? 'reps' : 'weight'),
        'value': p.value,
        'prev_value': p.previousBest,
      });
    }

    if (s != null && _note.text.isEmpty && (s.note ?? '').isNotEmpty) {
      _note.text = s.note!;
    }
    setState(() {
      _summary = s;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _body(),
      ),
    );
  }

  Widget _body() {
    final WorkoutSummary? s = _summary;
    if (s == null) {
      return Column(
        children: <Widget>[
          const Expanded(
            child: Center(
              child: Text(
                '这次没有记录到任何一组。',
                style: TextStyle(color: Tokens.text3, fontSize: 15),
              ),
            ),
          ),
          _doneButton(),
        ],
      );
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s6, Tokens.s5, Tokens.s4),
            children: <Widget>[
              // 2026-10-05 按新 VI 重做：一个**成功的绿勾** + 「训练完成！」 + 一句人话。
              // 旧版只有一行「训练完成」四个字 —— 刚练完那一刻值得给一个明确的完成感。
              _doneMark(),
              const SizedBox(height: Tokens.s5),
              _stats(s),
              if (widget.newBadges.isNotEmpty) ...<Widget>[
                const SizedBox(height: Tokens.s4),
                _unlockBlock(),
              ],
              if (s.hasDistance) _cardio(s),
              if (s.hasPr) ...<Widget>[
                const SizedBox(height: Tokens.s5),
                _prBlock(s),
              ],
              const SizedBox(height: Tokens.s5),
              // 一句话笔记（2026-10-04）：列早就有、界面也一直在显示，但没有写入路径。
              // 放这里是因为**刚练完是唯一还记得"今天为什么这样"的时刻**。
              _noteField(s),
              // 「下一次」放在最上面（刚练完最愿意看），拉伸建议跟在后面
              if (widget.nextLine != null) _nextBlock(),
              if (widget.stretches.isNotEmpty) ...<Widget>[
                const SizedBox(height: Tokens.s5),
                _stretchBlock(),
              ],
              // 练后小知识（第二部分第 8 条）：**每次一条，由 workoutId 纯函数挑**
              // （同一屏刷新两次看到的是同一条 —— 见 `tips.dart`）。
              const SizedBox(height: Tokens.s5),
              _tipBlock(),
            ],
          ),
        ),
        _shareButton(s),
        _doneButton(),
      ],
    );
  }

  /// **练后小知识**（第二部分第 8 条）。
  ///
  /// 放在拉伸建议之后、总结屏的最后一块：前面几块都是"你刚才做了什么"，
  /// 这一块是唯一说"为什么"的地方，读不读都不影响操作。
  ///
  /// 文案来自 `tips.dart` 的内置表（**不联网**）；挑哪一条是按 `workoutId` 的
  /// 纯函数，所以这一屏重建时不会换一句。
  Widget _tipBlock() {
    final Tip t = tipFor(widget.workoutId);
    return ViCard(
      key: const Key('post-workout-tip'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.lightbulb_outline, color: Tokens.text3, size: 16),
              const SizedBox(width: Tokens.s2),
              const Text('练后小知识',
                  style: TextStyle(color: Tokens.text3, fontSize: 12)),
            ],
          ),
          const SizedBox(height: Tokens.s2),
          Text(t.title,
              key: const Key('tip-title'),
              style: const TextStyle(
                  color: Tokens.text, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: Tokens.s2),
          Text(t.body,
              key: const Key('tip-body'),
              style: const TextStyle(color: Tokens.text2, fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }

  /// 「练完拉伸一下」。
  ///
  /// 库里 9 个拉伸动作在主流程里同样一个都见不到（只能去选动作页按类别筛）。
  /// 放在总结屏是有意的：练完这一屏是用户一定会看的地方，
  /// 而"练完顺手拉一下"是此时最该被提醒的一件事。
  /// 只给名字与做法，不塞进记录 —— 拉伸要不要单独记是他的选择。
  /// 一句话笔记：**不是"备忘"，是解释**。
  ///
  /// 引擎只看数字，数字解释不了"昨天没睡好 / 肩膀有点疼 / 今天状态好" ——
  /// 而那句话恰恰是几周后回看"为什么那次没加重"时唯一的线索。
  Widget _noteField(WorkoutSummary s) {
    return Container(
      key: const Key('summary-note'),
      padding: const EdgeInsets.symmetric(horizontal: Tokens.s4, vertical: Tokens.s3),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
        border: Border.all(color: Tokens.line),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.edit_note, size: 20, color: Tokens.text3),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: TextField(
              key: const Key('summary-note-input'),
              controller: _note,
              // 一句话：不换行、不展开
              maxLines: 1,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveNote(),
              style: const TextStyle(color: Tokens.text, fontSize: 14),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '今天的一句话（状态 / 感觉 / 为什么没加重）',
                hintStyle: TextStyle(color: Tokens.text3, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 「下一次」：刚练完就把下一次摆出来 —— 这是回访钩子最便宜的位置。
  Widget _nextBlock() {
    final String line = widget.nextLine!;
    return Container(
      key: const Key('summary-next'),
      margin: const EdgeInsets.only(top: Tokens.s3),
      padding: const EdgeInsets.symmetric(vertical: Tokens.s4, horizontal: Tokens.s4),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
        border: Border.all(color: Tokens.line),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.event_repeat, size: 18, color: Tokens.accent),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('下一次',
                    style: TextStyle(color: Tokens.text3, fontSize: 12)),
                const SizedBox(height: 2),
                Text(
                  line,
                  key: const Key('summary-next-text'),
                  style: const TextStyle(
                      color: Tokens.text, fontSize: 15, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stretchBlock() {
    return Container(
      key: const Key('summary-stretch'),
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
            '练完拉伸一下',
            style: TextStyle(
              color: Tokens.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Tokens.s3),
          for (final ExerciseData e in widget.stretches)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    e.name,
                    style: const TextStyle(
                      color: Tokens.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (e.instructions != null && e.instructions!.isNotEmpty)
                    Text(
                      e.instructions!,
                      style: const TextStyle(
                        color: Tokens.text3,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 一行三个大数：容量 / 时长 / 组数
  /// 完成标记（新 VI）：绿色圆 + 白勾 + 标题与一句人话。
  ///
  /// **不只靠颜色**：勾的图形本身就在表达"完成"，色盲用户读到的信息一样
  /// （`docs/interaction-spec.md` 的第二条硬约束）。
  Widget _doneMark() => Column(
        children: <Widget>[
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Tokens.success,
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Tokens.success.withValues(alpha: 0.25),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.check_rounded, color: Color(0xFF06231A), size: 42),
          ),
          const SizedBox(height: Tokens.s4),
          const Text(
            '训练完成！',
            key: Key('summary-done-title'),
            style: TextStyle(
              color: Tokens.text,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: Tokens.s2),
          const Text(
            '干得漂亮，又变强了一点',
            style: TextStyle(color: Tokens.text2, fontSize: 14),
          ),
        ],
      );

  /// **「新解锁 N 枚」**（2026-10-10）。
  ///
  /// 勋章在**整个 app 里只有两个地方露面**：这一条（训练完成那一刻）与「我 → 成就」
  /// 那本收藏册（`docs/plan-ux-2026-10-10.md` §五-B）。一级页面（首页 / 我）
  /// 永远不写"还差 N 枚" —— 这条例外只在**真的有新解锁**时出现，所以它天然稀有。
  ///
  /// 只列**前两枚**（两枚圆 + 名字）：一次给五枚也不铺开，想看全的点「全部 ›」。
  Widget _unlockBlock() {
    final List<BadgeStatus> shown = widget.newBadges.take(2).toList();
    final int rest = widget.newBadges.length - shown.length;
    return Container(
      key: const Key('summary-unlock'),
      padding: const EdgeInsets.all(Tokens.s4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Tokens.rCard),
        border: Border.all(color: Tokens.accent.withValues(alpha: 0.28)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Tokens.accent.withValues(alpha: 0.12),
            Tokens.accent.withValues(alpha: 0.03),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '✦ 新解锁 ${widget.newBadges.length} 枚',
                  key: const Key('summary-unlock-title'),
                  style: const TextStyle(
                      color: Tokens.accent,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700),
                ),
              ),
              if (widget.onOpenAchievements != null)
                GestureDetector(
                  key: const Key('summary-unlock-all'),
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onOpenAchievements,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: Tokens.s1, vertical: 2),
                    child: Text('全部 ›',
                        style: TextStyle(color: Tokens.text3, fontSize: 12.5)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Tokens.s3),
          Row(
            children: <Widget>[
              for (int i = 0; i < shown.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: Tokens.s4),
                Row(
                  key: Key('summary-badge-${shown[i].id}'),
                  children: <Widget>[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: badgeTierColor(shown[i].tier).withValues(alpha: 0.16),
                        border: Border.all(
                            color: badgeTierColor(shown[i].tier).withValues(alpha: 0.5)),
                      ),
                      child: Icon(_badgeIcon(shown[i]),
                          color: badgeTierColor(shown[i].tier), size: 19),
                    ),
                    const SizedBox(width: Tokens.s3),
                    Text(shown[i].name,
                        style: const TextStyle(color: Tokens.text, fontSize: 13.5)),
                  ],
                ),
              ],
              if (rest > 0) ...<Widget>[
                const SizedBox(width: Tokens.s3),
                Text('还有 $rest 枚',
                    style: const TextStyle(color: Tokens.text3, fontSize: 12.5)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 徽章圆里那枚图标：照类别给（收藏册里是同一套，见 `achievements_screen.dart`）。
  IconData _badgeIcon(BadgeStatus b) {
    switch (b.category) {
      case BadgeCategory.streak:
        return Icons.local_fire_department;
      case BadgeCategory.strength:
        return Icons.fitness_center;
      case BadgeCategory.explore:
        return Icons.explore;
      case BadgeCategory.milestone:
        return Icons.emoji_events;
    }
  }

  Widget _stats(WorkoutSummary s) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Tokens.s5, horizontal: Tokens.s4),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
        border: Border.all(color: Tokens.line),
      ),
      child: Row(
        children: <Widget>[
          _stat('容量', s.volumeLabel, const Key('summary-volume')),
          _divider(),
          _stat('时长', s.durationLabel, const Key('summary-duration')),
          _divider(),
          _stat('组数', '${s.totalSets}', const Key('summary-sets')),
        ],
      ),
    );
  }

  /// 有氧那一行：**单独一块，不与容量并列成三个大数**。
  ///
  /// 容量（kg × 次）和里程（米）是两个量纲 —— 并排放会让人以为能相加。
  /// 有配速就一起显示，没记时长就只显示里程（配速没定义时不要编一个）。
  Widget _cardio(WorkoutSummary s) {
    final String? pace = s.paceLabel;
    return Container(
      key: const Key('summary-cardio'),
      margin: const EdgeInsets.only(top: Tokens.s3),
      padding: const EdgeInsets.symmetric(vertical: Tokens.s4, horizontal: Tokens.s4),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
        border: Border.all(color: Tokens.line),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.directions_run, size: 18, color: Tokens.text3),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  s.cardiovascularLabels.join(' · '),
                  style: const TextStyle(color: Tokens.text3, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  pace == null
                      ? '${s.distanceLabel}'
                      : '${s.distanceLabel} · 平均 $pace',
                  key: const Key('summary-distance'),
                  style: const TextStyle(
                    color: Tokens.text,
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

  Widget _stat(String label, String value, Key key) {
    return Expanded(
      child: Column(
        children: <Widget>[
          // ⚠️ 大数**必须是一行**，而且要在固定的高度里：
          // "不到 1 分钟"这类人话会长到换行，一换行就把这一格的标签顶下去，
          // 三格看起来就歪了（2026-10-01 真机走查拍到的）。所以：
          //   * `maxLines: 1` + `FittedBox(scaleDown)` —— 太长就整行缩一点，不换行；
          //   * 外层给一个固定高度 —— 缩放后仍与另外两格**同高**，标签自然对齐。
          SizedBox(
            height: 30,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                key: key,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: Tokens.display(22, weight: 700, letterSpacing: -0.5),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Tokens.text3, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 32, color: Tokens.line);

  Widget _prBlock(WorkoutSummary s) {
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
          Row(
            children: <Widget>[
              // 破纪录用专属色，且**不只靠颜色**表达 —— 有文字
              const Text('★',
                  style: TextStyle(color: Tokens.pr, fontSize: 16, height: 1.2)),
              const SizedBox(width: Tokens.s2),
              Text(
                s.prs.length == 1 ? '破纪录' : '破了 ${s.prs.length} 项纪录',
                style: const TextStyle(
                  color: Tokens.pr,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.s3),
          for (final SetPr pr in s.prs)
            Padding(
              key: Key('summary-pr-${pr.exerciseId}'),
              padding: const EdgeInsets.only(bottom: Tokens.s2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      pr.exerciseName,
                      style: const TextStyle(
                        color: Tokens.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  Text(
                    pr.detail,
                    style: const TextStyle(color: Tokens.text2, fontSize: 13),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 分享训练卡。**只在真的有记录时才出现** —— 一次都没练的总结页
  /// 没有可分享的东西，给个按钮只会误导。
  Widget _shareButton(WorkoutSummary s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, 0),
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: OutlinedButton.icon(
          key: const Key('summary-share'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Tokens.text,
            side: const BorderSide(color: Tokens.lineStrong),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Tokens.rPill),
            ),
          ),
          icon: const Icon(Icons.ios_share, size: 18),
          label: const Text('分享训练卡',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ShareCardPreviewScreen(
                summary: s,
                exporter: widget.exporter,
                analytics: widget.analytics,
                // 打卡版要用：连续天数与"第几次训练"都由外壳算好传进来
                streak: widget.streak,
                ordinal: widget.ordinal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _doneButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, Tokens.s5),
      child: SizedBox(
        height: Tokens.hPrimary,
        width: double.infinity,
        child: FilledButton(
          key: const Key('summary-done'),
          style: FilledButton.styleFrom(
            backgroundColor: Tokens.accent,
            foregroundColor: Tokens.accentInk,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Tokens.rPill),
            ),
          ),
          // 先落库再退：总结页是"训练结束"这条路上的最后一屏，
          // 用户在这里写的那句话不该因为退出的方式不同而丢掉。
          onPressed: () async {
            await _saveNote();
            if (!context.mounted) return;
            Navigator.of(context).pop();
          },
          child: const Text(
            '完成',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
