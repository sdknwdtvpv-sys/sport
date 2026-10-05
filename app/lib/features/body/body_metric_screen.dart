/// 练了么 · S12 身体数据录入
///
/// 规格（`docs/screens.md` S11–S15）：**体重 + 备注，一天一条**。
///
/// 两点刻意的决定：
///   1. **日期可补录最近 7 天**。体重常常是事后补记的，
///      而"一天一条"意味着补录同一天应该是**改**那一条，不是新增。
///      用一排日期 chips 而不是日期选择器：少一次弹窗、少一层交互。
///   2. **体重用数字输入而不是步进按钮**。项目一贯"不做全键盘"是针对
///      S5 每组改重量那种场景（一手拿手机、一手拿杠铃）；体重是一个
///      你早上就知道的确定数值，从默认值一步步加减反而荒唐。
///      这是一个有意的例外，不是忘了规矩。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../core/vi_area_chart.dart';
import '../../core/vi_cards.dart';
import 'bmi.dart';
import 'body_trend.dart';
import '../../core/units.dart';
import '../../analytics/analytics.dart';
import '../../data/body_metric_repository.dart';
import '../../data/db.dart';
import '../../data/profile_repository.dart';

class BodyMetricScreen extends StatefulWidget {
  const BodyMetricScreen({
    super.key,
    required this.repository,
    this.unit = BodyWeightUnit.kg,
    this.analytics,
    this.profile,
    this.clock,
    this.onSaved,
    this.onUnitChanged,
  });

  final BodyMetricRepository repository;

  /// 体重的显示与输入单位（**千克 / 斤**）的**初始值**。
  /// **存储始终是 kg**（见 core/units.dart）。
  ///
  /// 它在**本页内**可以实时切换（[onUnitChanged] / 页内那个小开关）——
  /// 用户的理由很直接：称体重的时候才想起来"我要按斤看"，
  /// 那时不该退出去到「我」页翻设置。
  final BodyWeightUnit unit;

  /// 埋点（可选）。上报 `body_metric_logged` —— **只报"填没填"，不报数值**（见隐私政策 §6）。
  final Analytics? analytics;

  /// 用户偏好仓库。传了才会把实时切换的单位**落库**（测试可以不传）。
  final ProfileRepository? profile;

  /// 单位在本页被切换后通知上层（让「进步」页那张卡片也跟着变）。
  final ValueChanged<BodyWeightUnit>? onUnitChanged;

  /// 便于测试固定"今天"。不传则用真实时间。
  final DateTime Function()? clock;

  /// 保存后回调，让上一页刷新（「我」和「进步」都要显示体重）
  final VoidCallback? onSaved;

  @override
  State<BodyMetricScreen> createState() => _BodyMetricScreenState();
}

class _BodyMetricScreenState extends State<BodyMetricScreen> {
  final TextEditingController _weight = TextEditingController();

  /// 本页当前使用的体重单位。**初值来自构造参数，之后由页内那个开关实时改。**
  late BodyWeightUnit _unit = widget.unit;
  final TextEditingController _note = TextEditingController();
  List<BodyMetricData> _recent = const <BodyMetricData>[];

  /// 腰围 / 肌肉量 / 身高的输入（2026-10-05，v1.52）。
  ///
  /// ⚠️ 身高**不是**每日指标，它存进 `user_profile`（只用来算 BMI）——
  /// 和其它三项一起进表单，但保存时走的是另一条路（见 `_save`）。
  final TextEditingController _waist = TextEditingController();
  final TextEditingController _muscle = TextEditingController();
  final TextEditingController _height = TextEditingController();

  /// 最近一次记录里的体脂/肌肉量/腰围（摘要块用）。
  BodyMetricData? _latest;

  /// 身高（cm）。存在 `user_profile` 里，不是每日指标 —— 只用来算 BMI。
  double? _heightCm;

  /// 趋势卡当前选中的指标（v1.52）。记过哪个才切得过去，见 `trendMetrics`。
  BodyTrendMetric _trendMetric = BodyTrendMetric.weight;
  late DateTime _selected;
  bool _loading = true;

  /// 单独同意还没问完时为 true。
  ///
  /// 为什么单独一个状态：同意未决时如果照旧走 `_loading` 那条分支，弹层后面会挂一个
  /// **永远转的圈**（`_load()` 要等同意之后才调）—— 测试里表现为 `pumpAndSettle` 超时，
  /// 用户那边表现为"提示框后面卡住了"。所以这段时间渲染一块**静态**占位。
  bool _consentPending = false;
  bool _saving = false;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _selected = _now;
    // **敏感个人信息的单独同意**（PIPL 第 29 条）：
    // 体重属于医疗健康类的敏感个人信息，首次启动那道"政策总同意"**不等于**单独同意。
    // 所以进这一页先单独问一次；同意过就直接读数据，没同意过就先弹说明。
    unawaited(_ensureSensitiveConsent());
  }

  /// 过"单独同意"这道门：没同意过就弹一次；用户点「先不用」就退出这一页（不收集任何东西）。
  Future<void> _ensureSensitiveConsent() async {
    final ProfileRepository? profile = widget.profile;
    // 没有 profile（纯嵌入/测试场景，比如截图脚本）时不做拦截 —— 真实 App 一定传。
    if (profile == null) {
      await _load();
      return;
    }
    if (await profile.bodyMetricConsentAtMs() != null) {
      await _load();
      return;
    }
    if (!mounted) return;
    setState(() => _consentPending = true); // 静态占位，别再转圈
    final bool? agree = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: Tokens.surface,
        title: const Text('身体数据是敏感个人信息，要先单独征得你同意',
            style: TextStyle(color: Tokens.text)),
        content: const Text(
          // ⚠️ 这里**不能**写 markdown 的 `**`：`Text` 不渲染 markdown，
          // 用户会直接看到星号（v1.31.0 真机截图时抓到过一次）。
          // test/body_consent_test.dart 里有一条断言专门守着这件事。
          //
          // v1.52：这一页不止记体重了（还记体脂率 / 腰围 / 肌肉量 / 身高），
          // 所以说明里的"记的是体重"必须跟着改 —— 只写体重就变成"收集了没说"。
          // 它们共用**这一次**同意（同一类数据、同一个页面、同一个用途），
          // 不是每加一个字段就再弹一次窗。
          '「身体数据」记的是你的体重、体脂率、腰围、肌肉量和身高 —— '
          '按《个人信息保护法》，这类健康数据属于'
          '敏感个人信息，需要我们单独征求你的同意（首次启动时那次是政策总同意，'
          '不等于这一条）。\n\n'
          '· 它们只存在这台手机上，不会上传（云备份里也不含身体数据）；\n'
          '· 用途只有一个：给你自己看长期变化（身高只用来算 BMI）；\n'
          '· 你可以随时在「全部数据」里改或删掉它们。',
          key: Key('body-consent'),
          style: TextStyle(color: Tokens.text2, height: 1.6),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('body-consent-decline'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('先不用', style: TextStyle(color: Tokens.text2)),
          ),
          TextButton(
            key: const Key('body-consent-agree'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('同意并记录', style: TextStyle(color: Tokens.accent)),
          ),
        ],
      ),
    );
    if (agree != true) {
      // 不同意 → 直接退出这一页：不读、不写、不收集
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    await profile.setBodyMetricConsent();
    if (mounted) setState(() => _consentPending = false);
    await _load();
  }

  /// 撤回"处理体重"的同意：先问一声，并说清**撤回的是同意、不是数据**。
  Future<void> _revokeConsent() async {
    final ProfileRepository? profile = widget.profile;
    if (profile == null) return;
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: Tokens.surface,
        title: const Text('撤回后不再收集身体数据',
            style: TextStyle(color: Tokens.text)),
        content: const Text(
          '撤回的是「同意」，不是数据：\n\n'
          '· 这一页下次进来会重新问你一次；\n'
          '· 你不同意之前，不会再读、也不会再写体重、体脂率、腰围、肌肉量和身高；\n'
          '· 已经记下来的历史不会被删掉 —— 要删请去「全部数据」。',
          key: Key('body-revoke-note'),
          style: TextStyle(color: Tokens.text2, height: 1.6),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('body-revoke-no'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('算了', style: TextStyle(color: Tokens.text2)),
          ),
          TextButton(
            key: const Key('body-revoke-yes'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('撤回', style: TextStyle(color: Tokens.accent)),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await profile.clearBodyMetricConsent();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已撤回：下次进这一页会重新问你')),
    );
    // 撤回后立刻退出这一页：留在这里就等于"刚撤回还在处理"
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _weight.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 最近 7 天，含今天（倒序：今天在最左）。
  List<DateTime> get _dayChoices {
    final DateTime today = _now;
    return <DateTime>[
      for (int i = 0; i < 7; i++) DateTime(today.year, today.month, today.day - i),
    ];
  }

  Future<void> _load() async {
    final double? height = await widget.profile?.heightCm();
    final List<BodyMetricData> recent = await widget.repository.recent();
    if (!mounted) return;
    setState(() {
      _recent = recent;
      _heightCm = height;
      // 摘要块看的是**最近一条有体重的记录**（`recent` 已按日期倒序）
      _latest = recent.isEmpty ? null : recent.first;
      if (height != null) _height.text = trimNumber(round1(height));
      _loading = false;
    });
    await _prefill();
  }

  /// 选中某天时，把已有的记录填进输入框 —— 补录应该是"看到已有值再改"，
  /// 而不是"面对空框重新猜上次填了什么"。
  Future<void> _prefill() async {
    final BodyMetricData? row =
        await widget.repository.forDate(dayKey(_selected));
    if (!mounted) return;
    setState(() {
      // 软删除过的不填 —— 用户已经删掉它了
      final bool usable = row != null && row.deletedAt == null;
      _weight.text = usable
          ? trimNumber(round1(toDisplayBodyWeight(row.weightKg ?? 0, _unit)))
          : '';
      _note.text = usable ? (row.note ?? '') : '';
      // 新字段也一样回填（2026-10-05）：补录时"看到已有值再改"，不是面对空框重猜
      _waist.text = usable && row.waistCm != null ? trimNumber(round1(row.waistCm!)) : '';
      _muscle.text =
          usable && row.muscleMassKg != null ? trimNumber(round1(row.muscleMassKg!)) : '';
    });
  }

  @override
  void didUpdateWidget(BodyMetricScreen old) {
    super.didUpdateWidget(old);
    // 上层换了单位（比如整棵树按新偏好重建）→ 跟着换，并把输入框里的数字一起换过去。
    // 本地已经切过（_switchUnit 已经通知过上层）时这里通常是 no-op。
    if (old.unit != widget.unit && widget.unit != _unit) {
      _adoptUnit(widget.unit, persist: false, notify: false);
    }
  }

  /// 把当前单位换成 [next]：输入框里的数字**跟着换成同一个体重**，其余不动。
  void _adoptUnit(BodyWeightUnit next,
      {required bool persist, required bool notify}) {
    if (next == _unit) return;
    final double? asKg = _parsedWeight;
    setState(() {
      _unit = next;
      if (asKg != null) {
        _weight.text = trimNumber(round1(toDisplayBodyWeight(asKg, next)));
      }
    });
    if (persist) unawaited(_persistUnit(next));
    if (notify) widget.onUnitChanged?.call(next);
  }

  /// 实时切换体重单位。
  ///
  /// **数字要跟着变**（"实时数据变动"）：输入框里已经填的值是**旧单位**下的数，
  /// 切换后换成新单位下**同一个体重**的值 —— 85.5 切到斤就是 171，而不是留个 85.5
  /// 让人以为自己体重变了。已经存进库的 kg 一个字节都不动。
  ///
  /// 输入框里的内容解析不出来（空的、半截的、超范围的）就原样留着，不猜。
  void _switchUnit(BodyWeightUnit next) =>
      _adoptUnit(next, persist: true, notify: true);

  Future<void> _persistUnit(BodyWeightUnit u) async {
    final ProfileRepository? p = widget.profile;
    if (p == null) return;
    await p.setBodyWeightUnit(u);
  }

  /// 只接受数字与小数点的输入。
  double? get _parsedWeight {
    final String t = _weight.text.trim();
    if (t.isEmpty) return null;
    final double? v = double.tryParse(t);
    if (v == null) return null;
    // 明显不合理的值当作没填，避免把 720kg 存进去。
    // 范围按**显示单位**判断：400 kg（= 882 lb = 800 斤），再换成 kg 存库。
    // ⚠️ 三个单位都要算 —— 以前只有 kg/斤，加了 lb 之后
    // 用 `_unit == kg ? 400 : 400 * 2` 会把 400 lb（≈181 kg）也判成超标。
    final double maxInDisplay = toDisplayBodyWeight(400, _unit);
    if (v <= 0 || v > maxInDisplay) return null;
    return round1(bodyWeightToKg(v, _unit));
  }

  bool get _canSave => !_saving && _parsedWeight != null;

  /// 把输入框里的字变成数字。**空 / 非法一律当"没填"**（null），
  /// 而不是当 0 —— 0 会写进库里，变成"今天腰围 0 厘米"。
  double? _parsed(TextEditingController c) {
    final String t = c.text.trim();
    if (t.isEmpty) return null;
    final double? v = double.tryParse(t);
    return (v == null || v <= 0) ? null : v;
  }

  /// 表单里的一个小输入框（腰围 / 肌肉量 / 身高）。
  Widget _smallField(String hint, String key, TextEditingController c) => TextField(
        key: Key(key),
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        style: const TextStyle(color: Tokens.text, fontSize: 18),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Tokens.text3, fontSize: 15),
          filled: true,
          fillColor: Tokens.surface,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: Tokens.s4, vertical: Tokens.s3),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Tokens.rCard),
            borderSide: BorderSide.none,
          ),
        ),
      );

  /// 趋势卡（v1.52）：把最近记过的那几项画成一条线。
  ///
  /// 规则全在 `body_trend.dart`（纯计算，有单测），这里只管画：
  ///  * **一个点都不画** —— 记不到两次就不出现这张卡。画一条两个点的"趋势"是编故事，
  ///    而画一条平线会让人以为"我这段时间完全没变"。
  ///  * 切换器**只列画得出的指标** —— 列一个点了没反应的，等于给个假入口。
  ///  * 用 `ViAreaChart`（与「进步」页那张容量图同一个组件），不抄第二份画法。
  Widget _trendCard() {
    final List<BodyTrendMetric> available = trendMetrics(_recent);
    if (available.isEmpty) return const SizedBox.shrink();
    final BodyTrendMetric metric =
        available.contains(_trendMetric) ? _trendMetric : available.first;
    final BodyTrend trend = bodyTrend(_recent, metric);
    final double? delta = trend.delta;
    return Padding(
      padding: const EdgeInsets.only(top: Tokens.s5),
      child: ViCard(
        key: const Key('body-trend'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text('身体数据趋势',
                      style: TextStyle(
                          color: Tokens.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ),
                ViSegmented(
                  key: const Key('body-trend-seg'),
                  labels: <String>[
                    for (final BodyTrendMetric m in available) m.label,
                  ],
                  current: available.indexOf(metric),
                  onChanged: (int i) =>
                      setState(() => _trendMetric = available[i]),
                ),
              ],
            ),
            const SizedBox(height: Tokens.s3),
            ViAreaChart(
              key: const Key('body-trend-chart'),
              points: trendPoints(trend.values),
              height: 110,
            ),
            const SizedBox(height: Tokens.s2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(shortDate(trend.firstDate),
                    style: const TextStyle(color: Tokens.text3, fontSize: 11)),
                // 首尾差：**带单位和正负号**，否则"掉了 2"读不出是 kg 还是 cm
                Text(
                  delta == null ? '' : trendDeltaText(metric, delta),
                  key: const Key('body-trend-delta'),
                  style: TextStyle(
                    color: delta != null && delta < 0
                        ? Tokens.success
                        : Tokens.text2,
                    fontSize: 11,
                  ),
                ),
                Text(shortDate(trend.lastDate),
                    style: const TextStyle(color: Tokens.text3, fontSize: 11)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: Tokens.s2),
              child: Text(
                '这条线只有 ${trend.samples.length} 次记录，'
                '${metric.label}的单位是 ${metric.unit}',
                key: const Key('body-trend-hint'),
                style: const TextStyle(color: Tokens.text3, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 摘要：当前体重 + BMI（含分档）+ 体脂 / 肌肉量 / 腰围。
  ///
  /// ⚠️ 有一项没记就**不摆那一格**，而不是摆一个「—」占位 ——
  /// 空格子会让人以为"我记过但是丢了"。
  Widget _summaryCard(BodyMetricData m) {
    final double? bmi = bmiOf(weightKg: m.weightKg, heightCm: _heightCm);
    final List<(String, String)> tiles = <(String, String)>[
      if (m.bodyFatPct != null) ('体脂率', '${m.bodyFatPct!.toStringAsFixed(1)} %'),
      if (m.muscleMassKg != null) ('肌肉量', '${m.muscleMassKg!.toStringAsFixed(1)} kg'),
      if (m.waistCm != null) ('腰围', '${m.waistCm!.toStringAsFixed(1)} cm'),
      ('BMI', bmiText(bmi)),
    ];
    return Container(
      key: const Key('body-summary'),
      padding: const EdgeInsets.all(Tokens.s4),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
        border: Border.all(color: Tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                m.weightKg == null
                    ? '还没记体重'
                    : formatBodyWeight(m.weightKg!, _unit),
                key: const Key('body-summary-weight'),
                style: Tokens.display(28, weight: 700, letterSpacing: -0.5),
              ),
              const SizedBox(width: Tokens.s2),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(m.date, style: const TextStyle(color: Tokens.text3, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: Tokens.s3),
          Wrap(
            spacing: Tokens.s3,
            runSpacing: Tokens.s2,
            children: <Widget>[
              for (final (String label, String value) in tiles)
                Column(
                  key: Key('body-tile-$label'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(label, style: const TextStyle(color: Tokens.text3, fontSize: 11)),
                    Text(value,
                        style: const TextStyle(
                            color: Tokens.text, fontSize: 15, fontWeight: FontWeight.w600)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: Tokens.s2),
          Text(
            bmi == null ? bmiHint(bmi) : 'BMI ${bmiText(bmi)} · ${bmiBand(bmi)} —— ${bmiHint(bmi)}',
            key: const Key('body-bmi-hint'),
            style: const TextStyle(color: Tokens.text3, fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);

    await widget.repository.save(
      date: dayKey(_selected),
      weightKg: _parsedWeight,
      bodyFatPct: null, // 体脂本页不录（走「全部数据」/导入）；保留字段以免覆盖
      waistCm: _parsed(_waist),
      muscleMassKg: _parsed(_muscle),
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    // 身高不是每日指标：存进 profile（只用来算 BMI）。填了才存，空着不动。
    final double? newHeight = _parsed(_height);
    if (newHeight != null && widget.profile != null) {
      await widget.profile!.setHeightCm(newHeight);
      _heightCm = newHeight;
    }

    // `body_metric_logged`：**保存成功之后**才报 —— 放在 `_load` 里会变成
    // "一打开页面就报记了一次体重"（第一次就是这么写错的，测试当场抓到）。
    // 只报"填没填"，数值一律不出设备（隐私政策 §6）。
    widget.analytics?.track('body_metric_logged', <String, Object?>{
      'has_weight': _parsedWeight != null,
      'has_note': _note.text.trim().isNotEmpty,
    });

    final List<BodyMetricData> recent = await widget.repository.recent();
    if (!mounted) return;
    setState(() {
      _recent = recent;
      // 摘要块跟着更新（刚记完的那条可能不是"最近一条有体重的"）
      _latest = recent.isEmpty ? null : recent.first;
      _saving = false;
    });
    widget.onSaved?.call();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已记录 ${dayKey(_selected)} 的身体数据'),
        backgroundColor: Tokens.elevated,
        // 浮动到保存按钮**上方**。默认贴底会盖住按钮 —— 用户发现填错了
        // 想立刻改一次，却点不到按钮（这个是被测试抓出来的）。
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(Tokens.s5, 0, Tokens.s5, 88),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, 0),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton(
                      key: const Key('body-back'),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.chevron_left, color: Tokens.text2),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  const Expanded(
                    child: Text(
                      '身体数据',
                      style: TextStyle(
                        color: Tokens.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_consentPending)
              const Expanded(
                child: Center(
                  child: Text('先确认上面那条说明',
                      key: Key('body-consent-pending'),
                      style: TextStyle(color: Tokens.text3)),
                ),
              )
            else if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                // 这一页里有两个滚动体（纵向整页 + 「日期」那排横向 chips），
                // 所以给整页这个一个 key：测试里 `find.byType(ListView)` 会同时命中两个，
                // 拖拽/滚动就无从下手。有了名字，测试点的是"整页"而不是"某个 ListView"。
                child: ListView(
                  key: const Key('body-scroll'),
                  padding: const EdgeInsets.fromLTRB(
                      Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s6),
                  children: <Widget>[
                    // 摘要在最上面（2026-10-05）：进来第一眼该看到"现在是多少"，
                    // 而不是先看到一排输入框。没有记录时整块不出现。
                    if (_latest != null) ...<Widget>[
                      _summaryCard(_latest!),
                      const SizedBox(height: Tokens.s5),
                    ],
                    // 趋势卡：两个点以上才出现（一个点画不出趋势，见 body_trend.dart）
                    _trendCard(),
                    _label('日期'),
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: <Widget>[
                          for (final DateTime d in _dayChoices) _dayChip(d),
                        ],
                      ),
                    ),
                    // 标签本身带一个**行内实时开关**：称体重的时候才想起来要按斤看，
                    // 那时不该退出去到「我」页翻设置。
                    _weightUnitRow(),
                    TextField(
                      key: const Key('body-weight'),
                      controller: _weight,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(color: Tokens.text, fontSize: 24,
                          fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        hintText: '例如 72.5',
                        hintStyle: const TextStyle(color: Tokens.text3, fontSize: 20),
                        filled: true,
                        fillColor: Tokens.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: Tokens.s5,
                          vertical: Tokens.s4,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(Tokens.rCard),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    // 腰围与肌肉量并排（都是可选的）—— 一次录完，不用翻两页
                    Row(
                      children: <Widget>[
                        Expanded(child: _smallField('腰围 cm', 'body-waist', _waist)),
                        const SizedBox(width: Tokens.s3),
                        Expanded(child: _smallField('肌肉量 kg', 'body-muscle', _muscle)),
                      ],
                    ),
                    _label('身高 cm（只用来算 BMI，只存本机）'),
                    _smallField('例如 175', 'body-height', _height),
                    _label('备注（可选）'),
                    TextField(
                      key: const Key('body-note'),
                      controller: _note,
                      maxLines: 2,
                      style: const TextStyle(color: Tokens.text, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: '例如：空腹、练后',
                        hintStyle: const TextStyle(color: Tokens.text3, fontSize: 15),
                        filled: true,
                        fillColor: Tokens.surface,
                        contentPadding: const EdgeInsets.all(Tokens.s4),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(Tokens.rCard),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    if (_recent.isNotEmpty) ...<Widget>[
                      _label('最近记录'),
                      for (final BodyMetricData r in _recent.take(10))
                        _historyRow(r),
                    ],
                    // ── 撤回同意（PIPL 第 15 条：同意不是一次性的）──────────
                    // 放在这一页，因为**收集发生在哪儿，撤回入口就该在哪儿**。
                    // 没有 profile（嵌入/测试场景）时不显示 —— 那种场景没有落库的地方。
                    if (widget.profile != null)
                      Padding(
                        padding: const EdgeInsets.only(top: Tokens.s6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            TextButton(
                              key: const Key('body-revoke'),
                              onPressed: _revokeConsent,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                foregroundColor: Tokens.text2,
                              ),
                              child: const Text(
                                '撤回我的同意',
                                style: TextStyle(
                                  fontSize: 14,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                            const SizedBox(height: Tokens.s1),
                            const Text(
                              // ⚠️ 这里同样不能出现 markdown 的星号（Text 不渲染 markdown）
                              key: Key('body-revoke-caption'),
                              '撤回后不再收集新的身体数据，这一页会重新问你一次；'
                              '已经记下来的历史不会被删掉 —— 要删请去「全部数据」。',
                              style: TextStyle(
                                color: Tokens.text3,
                                fontSize: 12,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
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
                  key: const Key('body-save'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _canSave ? Tokens.accent : Tokens.line,
                    foregroundColor: _canSave ? Tokens.accentInk : Tokens.text3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Tokens.rPill),
                    ),
                  ),
                  // 没填有效体重就不能存：存一条空的身体数据没有意义
                  onPressed: _canSave ? _save : null,
                  child: const Text('保存',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayChip(DateTime d) {
    final String key = dayKey(d);
    final bool active = dayKey(_selected) == key;
    final bool isToday = key == dayKey(_now);
    return Padding(
      padding: const EdgeInsets.only(right: Tokens.s2),
      child: GestureDetector(
        key: Key('body-day-$key'),
        onTap: () async {
          setState(() => _selected = d);
          await _prefill();
        },
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
          decoration: BoxDecoration(
            color: active ? Tokens.accent : Tokens.surface,
            borderRadius: BorderRadius.circular(Tokens.rPill),
          ),
          child: Text(
            isToday ? '今天' : '${d.month}/${d.day}',
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

  Widget _historyRow(BodyMetricData r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 84,
            child: Text(r.date,
                style: const TextStyle(color: Tokens.text3, fontSize: 13)),
          ),
          Text(
            r.weightKg == null
                ? '—'
                : formatBodyWeight(r.weightKg, _unit),
            style: const TextStyle(color: Tokens.text, fontSize: 16,
                fontWeight: FontWeight.w600),
          ),
          if (r.note != null && r.note!.isNotEmpty) ...<Widget>[
            const SizedBox(width: Tokens.s3),
            Expanded(
              child: Text(
                r.note!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Tokens.text3, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 「体重  [kg][斤]」——标签行右边挂两个小 chip，切换立即生效。
  Widget _weightUnitRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s2),
      child: Row(
        children: <Widget>[
          const Text('体重',
              style: TextStyle(
                  color: Tokens.text2, fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          for (final BodyWeightUnit u in BodyWeightUnit.values) ...<Widget>[
            GestureDetector(
              key: Key('body-unit-${u.wire}'),
              onTap: () => _switchUnit(u),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: Tokens.s3),
                height: 28,
                decoration: BoxDecoration(
                  color: _unit == u ? Tokens.accent : Tokens.surface,
                  borderRadius: BorderRadius.circular(Tokens.rPill),
                ),
                child: Text(
                  u.label,
                  style: TextStyle(
                    color: _unit == u ? Tokens.accentInk : Tokens.text2,
                    fontSize: 12,
                    fontWeight: _unit == u ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ),
            if (u != BodyWeightUnit.values.last) const SizedBox(width: Tokens.s2),
          ],
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, Tokens.s5, 0, Tokens.s2),
        child: Text(
          text,
          style: const TextStyle(
            color: Tokens.text3,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      );
}
