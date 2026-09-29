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
import '../../core/units.dart';
import '../../data/body_metric_repository.dart';
import '../../data/db.dart';
import '../../data/profile_repository.dart';

class BodyMetricScreen extends StatefulWidget {
  const BodyMetricScreen({
    super.key,
    required this.repository,
    this.unit = BodyWeightUnit.kg,
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
  late DateTime _selected;
  bool _loading = true;
  bool _saving = false;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _selected = _now;
    _load();
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
    final List<BodyMetricData> recent = await widget.repository.recent();
    if (!mounted) return;
    setState(() {
      _recent = recent;
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
    // 范围按**显示单位**判断：400 kg / 800 斤（两者等价），再换成 kg 存库。
    final double maxInDisplay =
        _unit == BodyWeightUnit.kg ? 400 : 400 * kJinPerKg;
    if (v <= 0 || v > maxInDisplay) return null;
    return round1(bodyWeightToKg(v, _unit));
  }

  bool get _canSave => !_saving && _parsedWeight != null;

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);

    await widget.repository.save(
      date: dayKey(_selected),
      weightKg: _parsedWeight,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );

    final List<BodyMetricData> recent = await widget.repository.recent();
    if (!mounted) return;
    setState(() {
      _recent = recent;
      _saving = false;
    });
    widget.onSaved?.call();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已记录 ${dayKey(_selected)} 的体重'),
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
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                      Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s6),
                  children: <Widget>[
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
                    backgroundColor: _canSave ? Tokens.volt : Tokens.line,
                    foregroundColor: _canSave ? Tokens.voltInk : Tokens.text3,
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
            color: active ? Tokens.volt : Tokens.surface,
            borderRadius: BorderRadius.circular(Tokens.rPill),
          ),
          child: Text(
            isToday ? '今天' : '${d.month}/${d.day}',
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
                  color: _unit == u ? Tokens.volt : Tokens.surface,
                  borderRadius: BorderRadius.circular(Tokens.rPill),
                ),
                child: Text(
                  u.label,
                  style: TextStyle(
                    color: _unit == u ? Tokens.voltInk : Tokens.text2,
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
