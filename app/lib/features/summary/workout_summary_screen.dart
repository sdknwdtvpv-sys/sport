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
import '../../data/db.dart' show ExerciseData;
import 'share_card_exporter.dart';
import 'share_card_preview_screen.dart';
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
              const Text(
                '训练完成',
                style: TextStyle(
                  color: Tokens.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: Tokens.s5),
              _stats(s),
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
            ],
          ),
        ),
        _shareButton(s),
        _doneButton(),
      ],
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
                style: const TextStyle(
                  color: Tokens.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
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
