/// 练了么 · 回收站（2026-10-04）
///
/// **为什么有这一屏**：`deleteSet` 从第一天起就是**软删除**（只写 `deletedAt`），
/// 但全仓**没有任何地方读它** —— 训练中长按撤销之后，那组就永远取不回来了。
/// 而项目自己写着"数据丢失是工具类死刑"（`PRODUCT.md` §10.5），
/// 对手最集中的抱怨也正是数据丢失。**留痕不留出路，等于没留。**
///
/// 三条口径：
///   * 只列**软删除的组**（不是整次训练）—— 组才是这个 App 的最小单位，
///     而删除动作也只发生在组上（长按撤销 / 撤销误触）；
///   * 恢复 = 清掉 `deletedAt`（drift 里必须用 Companion + `Value(null)`，
///     否则是"这一列不改"而不是"清空"）；
///   * **不发埋点**：罕见的数据找回动作，不是可用性信号；多发一个事件
///     就要同步中英政策 + 隐私事实表 + 两张商店表单。
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/units.dart';
import '../../data/db.dart' show ExerciseData;
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import '../../domain/models.dart';
import 'profile_widgets.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({
    super.key,
    required this.store,
    required this.repository,
    this.unit = WeightUnit.kg,
    /// 恢复之后要通知上层刷新（进步页/首页的数字会变）
    this.onRestored,
  });

  final LocalStore store;
  final ExerciseRepository repository;
  final WeightUnit unit;
  final VoidCallback? onRestored;

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<DeletedSet> _rows = const <DeletedSet>[];
  Map<String, String> _names = const <String, String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<DeletedSet> rows = await widget.store.deletedSets();
      final List<ExerciseData> ex = await widget.repository.search(limit: 500);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _names = <String, String>{
          for (final ExerciseData e in ex) e.id: e.name,
        };
        _loading = false;
      });
    } catch (_) {
      // 读不出来就当作空 —— 回收站本身不该把这一页弄崩
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _restore(DeletedSet row) async {
    await widget.store.restoreSet(row.set.id);
    widget.onRestored?.call();
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已恢复 ${_label(row.set)}'),
        backgroundColor: Tokens.elevated,
      ),
    );
  }

  String _label(SetRecord s) {
    final String name = _names[s.exerciseId] ?? s.exerciseId;
    final String amount = s.hasDistance
        ? '${(s.distanceM ?? 0).toStringAsFixed(0)} 米'
        : (s.weightKg == null
            ? '自重 × ${s.reps}'
            : '${formatWeight(s.weightKg!, widget.unit)} × ${s.reps}');
    return '$name $amount';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Tokens.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return ProfileSubPage(
      title: '回收站',
      children: <Widget>[
        profileSectionTitle('删除的组'),
        if (_rows.isEmpty)
          settingsCard(<Widget>[
            const Padding(
              padding: EdgeInsets.all(Tokens.s4),
              child: Text(
                '这里空着。训练中长按「已完成」里的一行撤销掉的组会落到这儿，'
                '想撤回那次撤销就点「恢复」。',
                style: TextStyle(color: Tokens.text3, fontSize: 13, height: 1.5),
              ),
            ),
          ])
        else
          settingsCard(<Widget>[
            for (int i = 0; i < _rows.length; i++) ...<Widget>[
              if (i > 0) const Divider(height: 1, color: Tokens.line),
              ListTile(
                key: Key('trash-${_rows[i].set.id}'),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: Tokens.s4),
                title: Text(
                  _label(_rows[i].set),
                  style: const TextStyle(color: Tokens.text, fontSize: 15),
                ),
                subtitle: Text(
                  _when(_rows[i].deletedAtMs),
                  style: const TextStyle(color: Tokens.text3, fontSize: 13),
                ),
                trailing: TextButton(
                  key: Key('restore-${_rows[i].set.id}'),
                  style: TextButton.styleFrom(foregroundColor: Tokens.accent),
                  onPressed: () => _restore(_rows[i]),
                  child: const Text('恢复'),
                ),
              ),
            ],
          ]),
        const SizedBox(height: Tokens.s4),
        const Text(
          '恢复只是把那一组放回原来的训练里 —— 它不会重新计算容量或 PR，'
          '那些数字本来就在算的时候把它算上了。',
          style: TextStyle(color: Tokens.text3, fontSize: 12, height: 1.5),
        ),
      ],
    );
  }

  /// 「3 分钟前 / 昨天 14:20 / 9月28日 14:20」—— 回收站看的是"什么时候删的"
  String _when(int ms) {
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(ms);
    final DateTime now = DateTime.now();
    final Duration ago = now.difference(t);
    String two(int n) => n.toString().padLeft(2, '0');
    if (ago.inMinutes < 1) return '刚刚删的';
    if (ago.inHours < 1) return '${ago.inMinutes} 分钟前删的';
    if (ago.inHours < 24 && now.day == t.day) return '今天 ${two(t.hour)}:${two(t.minute)} 删的';
    return '${t.month}月${t.day}日 ${two(t.hour)}:${two(t.minute)} 删的';
  }
}
