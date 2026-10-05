/// 练了么 · 新建自定义动作
///
/// 入口在 S3 动作选择器右上角（`docs/screens.md` S3：「右上角『新建自定义动作』」）。
///
/// 刻意只有一个输入框（名称），其余全是 chips —— 延续本项目
/// 「不做全键盘」的一贯做法：表单页也不该逼人打字。
///
/// 器械决定加重步长，因此**不单独问步长**：杠铃 2.5 / 哑铃 2 / 器械 5 /
/// 绳索 2.5 / 自重 0。这与内置动作库的约定一致（引擎向量里有对应断言：
/// 「哑铃步长是 2kg，不是 2.5」「器械配重片档位是 5kg」）。
library;

import 'package:flutter/material.dart';

import '../../core/labels.dart';
import '../../core/pills.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../data/db.dart';
import '../../data/exercise_repository.dart';

/// 器械 → 加重步长。0 表示自重（引擎会走"加次数"推进）。
const Map<String, double> kIncrementForEquipment = <String, double>{
  'barbell': 2.5,
  'dumbbell': 2,
  'machine': 5,
  'cable': 2.5,
  'bodyweight': 0,
};

const List<int> kRestChoices = <int>[60, 90, 120, 180];

class CustomExerciseScreen extends StatefulWidget {
  const CustomExerciseScreen({
    super.key,
    required this.repository,
    this.unit = WeightUnit.kg,
  });

  final ExerciseRepository repository;

  /// 显示单位（步长的文案要跟着变）
  final WeightUnit unit;

  @override
  State<CustomExerciseScreen> createState() => _CustomExerciseScreenState();
}

class _CustomExerciseScreenState extends State<CustomExerciseScreen> {
  final TextEditingController _name = TextEditingController();
  String _muscle = 'chest';
  String _equipment = 'barbell';
  int _restSec = 90;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 名称决定保存按钮能否点，所以要跟着重建
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty && !_saving;

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);

    final ExerciseData created = await widget.repository.createCustom(
      name: _name.text.trim(),
      muscleGroup: _muscle,
      equipment: _equipment,
      weightIncrement: kIncrementForEquipment[_equipment] ?? 2.5,
      defaultRestSec: _restSec,
    );

    if (!mounted) return;
    // 把新建的动作直接带回 S3 并选中它 —— 建完还要再找一遍是最烦的
    Navigator.of(context).pop(created);
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
                      key: const Key('custom-back'),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.chevron_left, color: Tokens.text2),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  const Expanded(
                    child: Text(
                      '新建自定义动作',
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
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s6),
                children: <Widget>[
                  _label('名称'),
                  TextField(
                    key: const Key('custom-name'),
                    controller: _name,
                    autofocus: true,
                    style: const TextStyle(color: Tokens.text, fontSize: 17),
                    decoration: InputDecoration(
                      hintText: '例如：坐姿划船机',
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
                  _label('部位'),
                  Wrap(
                    spacing: Tokens.s2,
                    runSpacing: Tokens.s2,
                    children: <Widget>[
                      for (final String k in kPrimaryMuscleGroups)
                        _chip(
                          key: 'custom-muscle-$k',
                          label: muscleLabel(k),
                          active: _muscle == k,
                          onTap: () => setState(() => _muscle = k),
                        ),
                    ],
                  ),
                  _label('器械'),
                  Wrap(
                    spacing: Tokens.s2,
                    runSpacing: Tokens.s2,
                    children: <Widget>[
                      for (final MapEntry<String, String> e
                          in kEquipmentLabels.entries)
                        _chip(
                          key: 'custom-equipment-${e.key}',
                          label: e.value,
                          active: _equipment == e.key,
                          onTap: () => setState(() => _equipment = e.key),
                        ),
                    ],
                  ),
                  // 不单独问步长：器械已经决定了它（见 kIncrementForEquipment）。
                  // 自重动作会走"加次数"推进，所以这里说明一下，免得用户以为坏了。
                  Padding(
                    padding: const EdgeInsets.only(top: Tokens.s2),
                    child: Text(
                      _equipment == 'bodyweight'
                          ? '自重动作：按次数推进，不加重'
                          : '加重步长 ${formatWeight(kIncrementForEquipment[_equipment] ?? 2.5, widget.unit)}',
                      style: const TextStyle(color: Tokens.text3, fontSize: 13),
                    ),
                  ),
                  _label('默认休息'),
                  Wrap(
                    spacing: Tokens.s2,
                    runSpacing: Tokens.s2,
                    children: <Widget>[
                      for (final int sec in kRestChoices)
                        _chip(
                          key: 'custom-rest-$sec',
                          label: '$sec 秒',
                          active: _restSec == sec,
                          onTap: () => setState(() => _restSec = sec),
                        ),
                    ],
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
                  key: const Key('custom-save'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _canSave ? Tokens.accent : Tokens.line,
                    foregroundColor: _canSave ? Tokens.accentInk : Tokens.text3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Tokens.rPill),
                    ),
                  ),
                  onPressed: _canSave ? _save : null,
                  child: const Text(
                    '保存并选用',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
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

  Widget _chip({
    required String key,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    // ⚠️ 别再手写一遍 `Container(alignment: ...)`：它会被 `Wrap` 的有界宽度撑成通栏
    // （部位/器械/类别各占一整行）。共用件见 `core/pills.dart`。
    return choicePill(label: label, active: active, onTap: onTap, key: Key(key));
  }
}
