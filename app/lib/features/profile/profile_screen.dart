/// 练了么 · S10「我」
///
/// 对应 `docs/screens.md` S10。这里放**每一行都真的有用**的东西：
///   1. 训练统计（读现有数据，只读）
///   2. 渐进建议开关（真的能关掉引擎的建议）
///   3. 数据导出（全量 CSV 到剪贴板）
///
/// 刻意**没有**放的：单位切换、默认休息时长、会员入口。
/// 单位会牵动全链路的显示，默认休息和每个动作自带的 `default_rest_sec` 打架，
/// 会员页在还没有付费功能之前是假的。占位入口比没有更糟。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// db.dart（drift 表）与 models.dart（领域模型）都定义了 Workout / SetRecord，预先 hide。
import '../../core/theme.dart';
import '../../data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import '../../analytics/analytics.dart';
import '../../data/profile_repository.dart';
import '../../domain/models.dart';
import 'training_stats.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.store,
    required this.repository,
    required this.profile,
    this.analytics,
  });

  final LocalStore store;
  final ExerciseRepository repository;
  final ProfileRepository profile;

  /// 隐私开关要能立刻生效，所以直接持有埋点实例（测试可不传）
  final Analytics? analytics;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  TrainingStats? _stats;
  ProgressionMode _mode = ProgressionMode.doubleProgression;
  bool _analyticsEnabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<SetRecord> sets = await widget.store.allSets();
    final ProgressionMode mode = await widget.profile.progressionMode();
    final bool enabled = await widget.profile.analyticsEnabled();
    if (!mounted) return;
    setState(() {
      _stats = TrainingStats.fromSets(sets);
      _mode = mode;
      _analyticsEnabled = enabled;
      _loading = false;
    });
  }

  Future<void> _toggleProgression(bool on) async {
    final ProgressionMode next =
        on ? ProgressionMode.doubleProgression : ProgressionMode.off;
    setState(() => _mode = next);
    await widget.profile.setProgressionMode(next);
  }

  /// 关掉隐私开关：立刻生效 + 落库。
  /// **功能完全不受影响** —— 只是不再记录（崩溃上报走独立通道）。
  Future<void> _toggleAnalytics(bool on) async {
    setState(() => _analyticsEnabled = on);
    widget.analytics?.setEnabled(on);
    await widget.profile.setAnalyticsEnabled(on);
  }

  Future<void> _export() async {
    final List<SetRecord> sets = await widget.store.allSets();
    // 动作名要一次性取好，不能每条记录查一次库
    final List<ExerciseData> rows = await widget.repository.search(limit: 500);
    final Map<String, String> names = <String, String>{
      for (final ExerciseData r in rows) r.id: r.name,
    };
    final String csv = buildSetsCsv(sets: sets, exerciseNames: names);
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 ${sets.length} 条记录到剪贴板'),
        backgroundColor: Tokens.elevated,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final TrainingStats s = _stats!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s5),
      children: <Widget>[
        const Text(
          '我',
          style: TextStyle(
            color: Tokens.text,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: Tokens.s5),
        _sectionTitle('训练统计'),
        _card(<Widget>[
          if (s.isEmpty)
            const Padding(
              padding: EdgeInsets.all(Tokens.s5),
              child: Text(
                '还没有训练记录。练完第一次，这里就有数了。',
                style: TextStyle(color: Tokens.text3, fontSize: 15, height: 1.5),
              ),
            )
          else ...<Widget>[
            _statRow('训练次数', '${s.workoutCount} 次', const Key('profile-stat-workouts')),
            _statRow('总组数', '${s.setCount} 组', const Key('profile-stat-sets')),
            _statRow('总容量', s.volumeLabel, const Key('profile-stat-volume')),
          ],
        ]),
        const SizedBox(height: Tokens.s5),
        _sectionTitle('渐进建议'),
        _card(<Widget>[
          SwitchListTile(
            key: const Key('progression-switch'),
            value: _mode != ProgressionMode.off,
            onChanged: _toggleProgression,
            activeThumbColor: Tokens.voltInk,
            activeTrackColor: Tokens.volt,
            contentPadding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
            title: const Text(
              '根据历史提示重量',
              style: TextStyle(color: Tokens.text, fontSize: 15),
            ),
            subtitle: const Text(
              '关掉后只记录，不再提示该上多少重量',
              style: TextStyle(color: Tokens.text3, fontSize: 13, height: 1.4),
            ),
          ),
        ]),
        const SizedBox(height: Tokens.s5),
        _sectionTitle('隐私'),
        _card(<Widget>[
          SwitchListTile(
            key: const Key('analytics-switch'),
            value: _analyticsEnabled,
            onChanged: _toggleAnalytics,
            activeThumbColor: Tokens.voltInk,
            activeTrackColor: Tokens.volt,
            contentPadding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
            title: const Text(
              '帮助改进产品',
              style: TextStyle(color: Tokens.text, fontSize: 15),
            ),
            subtitle: const Text(
              '关掉后不再上报任何使用数据，功能完全不受影响',
              style: TextStyle(color: Tokens.text3, fontSize: 13, height: 1.4),
            ),
          ),
        ]),
        const SizedBox(height: Tokens.s5),
        _sectionTitle('数据'),
        _card(<Widget>[
          ListTile(
            key: const Key('export-csv'),
            contentPadding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
            onTap: _export,
            title: const Text(
              '导出全部记录',
              style: TextStyle(color: Tokens.text, fontSize: 15),
            ),
            subtitle: const Text(
              '复制成 CSV 到剪贴板，可贴进表格',
              style: TextStyle(color: Tokens.text3, fontSize: 13),
            ),
            trailing: const Icon(Icons.ios_share, color: Tokens.text3, size: 20),
          ),
        ]),
        const SizedBox(height: Tokens.s5),
        _sectionTitle('关于'),
        _card(<Widget>[
          const Padding(
            padding: EdgeInsets.all(Tokens.s4),
            child: Text(
              '版本 1.0.0 · 数据只存在这台设备上，不上传任何人。',
              style: TextStyle(color: Tokens.text3, fontSize: 13, height: 1.5),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(left: Tokens.s1, bottom: Tokens.s2),
        child: Text(
          t,
          style: const TextStyle(color: Tokens.text3, fontSize: 13),
        ),
      );

  /// 卡片容器。
  ///
  /// ⚠️ 背景色必须交给 `Material` 而不是 `DecoratedBox`：
  /// ListTile / SwitchListTile 的水波纹画在**最近的 Material 祖先**上，
  /// 中间隔一层带背景色的 DecoratedBox 会把它盖住 ——
  /// Flutter 在 debug 下会直接抛断言（`ListTile background color or ink splashes may be invisible`）。
  /// 边框用 `shape` 画，不引入额外的 DecoratedBox。
  Widget _card(List<Widget> children) => Material(
        color: Tokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.rCard),
          side: const BorderSide(color: Tokens.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );

  Widget _statRow(String label, String value, Key key) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s4, vertical: Tokens.s4),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: Tokens.text2, fontSize: 15)),
            ),
            Text(
              value,
              key: key,
              style: const TextStyle(
                color: Tokens.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}
