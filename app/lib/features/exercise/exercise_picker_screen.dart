/// 练了么 · 动作选择页（S3）
///
/// 对应 `docs/screens.md` S3。目标：从打开到选中一个动作 ≤ 5 秒，不滚动。
/// 搜索同时匹配名称与别名（"bp" → 杠铃卧推，"rdl" → 罗马尼亚硬拉），
/// 默认按 popularity 降序，所以常用动作天然排在最前面。
library;

import 'package:flutter/material.dart';

import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../data/db.dart';
import '../../data/exercise_repository.dart';

class ExercisePickerScreen extends StatefulWidget {
  const ExercisePickerScreen({super.key, required this.repository});

  final ExerciseRepository repository;

  @override
  State<ExercisePickerScreen> createState() => _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends State<ExercisePickerScreen> {
  final TextEditingController _query = TextEditingController();
  List<ExerciseData> _rows = const <ExerciseData>[];
  bool _loading = true;
  String? _muscleGroup;

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
    final List<ExerciseData> rows = await widget.repository.search(
      query: _query.text,
      muscleGroup: _muscleGroup,
      limit: 60,
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  void _pick(ExerciseData e) => Navigator.of(context).pop(e);

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
                      ? const Center(
                          child: Text(
                            '没找到这个动作。\n换个词试试，或者在「我」里自建。',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Tokens.text3, fontSize: 15, height: 1.5),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                            Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s6),
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const Divider(
                            color: Tokens.line,
                            height: 1,
                          ),
                          itemBuilder: (BuildContext context, int i) {
                            final ExerciseData e = _rows[i];
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
                                bodyweight ? '自重' : '${_trim(e.defaultWeightKg)}kg',
                                style: const TextStyle(
                                  color: Tokens.text2,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
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

  String _trim(double? v) {
    if (v == null) return '-';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }
}
