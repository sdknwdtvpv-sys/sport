/// 练了么 · S10「我」
///
/// 对应 `docs/screens.md` S10。这里放**每一行都真的有用**的东西：
///   1. 训练统计（读现有数据，只读）
///   2. 渐进建议开关（真的能关掉引擎的建议）
///   3. 数据导出（全量 CSV 到剪贴板）
///
/// 刻意**没有**放的：会员入口。
///（单位切换、默认休息时长原先也在这行里，S15 落地后都加回来了）
/// 单位会牵动全链路的显示，默认休息和每个动作自带的 `default_rest_sec` 打架，
/// 会员页在还没有付费功能之前是假的。占位入口比没有更糟。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// db.dart（drift 表）与 models.dart（领域模型）都定义了 Workout / SetRecord，预先 hide。
import '../../core/app_info.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import '../../data/body_metric_repository.dart';
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import '../../analytics/analytics.dart';
import '../../data/profile_repository.dart';
import '../../domain/models.dart';
import '../body/body_metric_screen.dart';
import 'training_stats.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.store,
    required this.repository,
    required this.profile,
    this.analytics,
    this.bodyMetrics,
    this.unit = WeightUnit.kg,
    this.onUnitChanged,
    this.restOverrideSec,
    this.onRestOverrideChanged,
  });

  final LocalStore store;
  final ExerciseRepository repository;
  final ProfileRepository profile;

  /// 隐私开关要能立刻生效，所以直接持有埋点实例（测试可不传）
  final Analytics? analytics;

  /// 身体数据（S12）。可选：不传就不显示那一项。
  final BodyMetricRepository? bodyMetrics;

  /// 当前显示单位。**只影响显示**：统计与判定始终按 kg 算。
  final WeightUnit unit;

  /// 用户切了单位之后通知上层重建（否则别的 Tab 还按旧单位显示）。
  final ValueChanged<WeightUnit>? onUnitChanged;

  /// 休息时长偏好。**null = 跟随动作自带的值**，这是默认。
  final int? restOverrideSec;

  /// 用户改了休息时长之后通知上层（训练屏要用新值）
  final ValueChanged<int?>? onRestOverrideChanged;

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
      _stats = TrainingStats.fromSets(sets, unit: widget.unit);
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
    final String csv =
        buildSetsCsv(sets: sets, exerciseNames: names, unit: widget.unit);
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 ${sets.length} 条记录到剪贴板'),
        backgroundColor: Tokens.elevated,
      ),
    );
  }

  /// 休息时长的候选值。放在这里而不是 units.dart：它是产品决定，不是单位问题。
  static const List<int> kRestChoices = <int>[45, 60, 90, 120, 180];

  Future<void> _setRest(int? sec) async {
    if (sec == widget.restOverrideSec) return;
    await widget.profile.setRestOverrideSec(sec);
    widget.onRestOverrideChanged?.call(sec);
  }

  Widget _restChip(int? sec, String label) {
    final bool active = widget.restOverrideSec == sec;
    return GestureDetector(
      key: Key('rest-${sec ?? 'follow'}'),
      onTap: () => _setRest(sec),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
        height: 36,
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
    );
  }

  /// 切换显示单位。**先落库再通知上层重建** —— 反过来的话，
  /// 上层重建时读到的还是旧值，界面会闪一下又变回去。
  Future<void> _setUnit(WeightUnit u) async {
    if (u == widget.unit) return;
    await widget.profile.setUnit(u);
    widget.onUnitChanged?.call(u);
  }

  Widget _unitChip(WeightUnit u) {
    final bool active = widget.unit == u;
    return GestureDetector(
      key: Key('unit-${u.wire}'),
      onTap: () => _setUnit(u),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
        height: 36,
        decoration: BoxDecoration(
          color: active ? Tokens.volt : Tokens.surface,
          borderRadius: BorderRadius.circular(Tokens.rPill),
        ),
        child: Text(
          u.wire,
          style: TextStyle(
            color: active ? Tokens.voltInk : Tokens.text2,
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Future<void> _openBodyMetric() async {
    final BodyMetricRepository? repo = widget.bodyMetrics;
    if (repo == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BodyMetricScreen(
          repository: repo,
          unit: widget.unit,
          onSaved: _load,
        ),
      ),
    );
    await _load();
  }

  /// 删除全部用户数据。**必须二次确认** —— 不可撤销。
  ///
  /// 存在的原因：《个人信息保护法》第四十七条要求提供删除个人信息的途径。
  /// 之前只有开关和 CSV 导出，用户想"把我的数据删掉"在应用内无路可走。
  ///
  /// 删掉的是本机的训练、组记录、个人设置、以及还没发出去的埋点事件；
  /// **动作库保留**（那是产品资产，不是用户数据）。详见 `LocalStore.deleteAllUserData`。
  Future<void> _deleteAll() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        key: const Key('delete-all-dialog'),
        backgroundColor: Tokens.elevated,
        title: const Text('删除全部数据？'),
        content: const Text(
          '会删掉这台手机上所有训练记录、组记录和个人设置。\n\n'
          '无法撤销，也无法恢复。内置的动作库会保留。',
          style: TextStyle(height: 1.5),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('delete-all-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('delete-all-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Tokens.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    // 用户点了取消、或点了外面关掉 —— 都不能删
    if (confirmed != true) return;

    await widget.store.deleteAllUserData();
    if (!mounted) return;

    // 重新拉一遍：统计清零、各项开关回落到默认值。
    // 只清库不刷新的话，界面还显示着刚被删掉的数据 —— 用户会以为没删掉。
    await _load();
    widget.analytics?.setEnabled(_analyticsEnabled);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已删除全部数据'),
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
        // 规格（docs/screens.md S15）把「单位」列在设置里。
        // 放在最上面：它是唯一会改变**所有其它数字怎么念**的设置。
        _sectionTitle('单位'),
        _card(<Widget>[
          Padding(
            padding: const EdgeInsets.all(Tokens.s4),
            child: Row(
              children: <Widget>[
                _unitChip(WeightUnit.kg),
                const SizedBox(width: Tokens.s2),
                _unitChip(WeightUnit.lb),
                const Spacer(),
                const Text(
                  '只影响显示，数据按 kg 存',
                  style: TextStyle(color: Tokens.text3, fontSize: 12),
                ),
              ],
            ),
          ),
        ]),
        _sectionTitle('休息时长'),
        _card(<Widget>[
          Padding(
            padding: const EdgeInsets.all(Tokens.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: Tokens.s2,
                  runSpacing: Tokens.s2,
                  children: <Widget>[
                    // 「跟随动作」是默认，也是推荐：种子里各动作差异很大
                    // （核心 45s、深蹲 180s），统一覆盖会把这层信息抹掉。
                    _restChip(null, '跟随动作'),
                    for (final int sec in kRestChoices) _restChip(sec, '$sec 秒'),
                  ],
                ),
                const SizedBox(height: Tokens.s3),
                Text(
                  widget.restOverrideSec == null
                      ? '每个动作用它自带的休息时长（核心 45 秒、深蹲 180 秒……）'
                      : '所有动作统一休息 ${widget.restOverrideSec!} 秒',
                  style: const TextStyle(color: Tokens.text3, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ]),
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
          if (widget.bodyMetrics != null) ...<Widget>[
            ListTile(
              key: const Key('open-body-metric'),
              contentPadding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
              onTap: _openBodyMetric,
              title: const Text(
                '身体数据',
                style: TextStyle(color: Tokens.text, fontSize: 15),
              ),
              subtitle: const Text(
                '记录体重，看长期变化。一天一条',
                style: TextStyle(color: Tokens.text3, fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right, color: Tokens.text3, size: 20),
            ),
            const Divider(height: 1, color: Tokens.line),
          ],
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
          const Divider(height: 1, color: Tokens.line),
          ListTile(
            key: const Key('delete-all'),
            contentPadding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
            onTap: _deleteAll,
            title: const Text(
              '删除全部数据',
              style: TextStyle(color: Tokens.danger, fontSize: 15),
            ),
            subtitle: const Text(
              '清空本机记录与设置，动作库保留。不可撤销',
              style: TextStyle(color: Tokens.text3, fontSize: 13),
            ),
            trailing: const Icon(Icons.delete_outline, color: Tokens.danger, size: 20),
          ),
        ]),
        const SizedBox(height: Tokens.s5),
        _sectionTitle('关于'),
        _card(<Widget>[
          Padding(
            padding: const EdgeInsets.all(Tokens.s4),
            child: Text(
              // 版本号来自 core/app_info.dart，由 app_version_test 与 pubspec 对齐。
              // 以前这里写死 '1.0.0'，两次切版后界面上的版本号就错了两个版本。
              '版本 $kAppVersion · 数据只存在这台设备上，不上传任何人。',
              style: const TextStyle(
                  color: Tokens.text3, fontSize: 13, height: 1.5),
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
