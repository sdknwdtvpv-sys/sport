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
import 'backup.dart';
import 'backup_exporter.dart';
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
    this.bodyUnit = BodyWeightUnit.kg,
    this.onUnitChanged,
    this.onBodyUnitChanged,
    this.restOverrideSec,
    this.onRestOverrideChanged,
    this.backupExporter = const PluginBackupExporter(),
    this.onDataChanged,
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

  /// **体重**的显示单位（千克 / 斤）。与训练重量的 [unit] 是两个设置。
  final BodyWeightUnit bodyUnit;

  /// 用户改了体重单位之后通知上层（理由同 [onUnitChanged]）。
  final ValueChanged<BodyWeightUnit>? onBodyUnitChanged;

  /// 用户切了单位之后通知上层重建（否则别的 Tab 还按旧单位显示）。
  final ValueChanged<WeightUnit>? onUnitChanged;

  /// 休息时长偏好。**null = 跟随动作自带的值**，这是默认。
  final int? restOverrideSec;

  /// 用户改了休息时长之后通知上层（训练屏要用新值）
  final ValueChanged<int?>? onRestOverrideChanged;

  /// 把备份交给系统。默认走 share_plus（不需要新依赖，也不需要权限）；
  /// 测试里换成假的就能断言"到底交出去了什么"。
  final BackupExporter backupExporter;

  /// 数据被改动过（删光 / 导入）—— 外壳要跟着刷新首页那个"我上周练了 N 次"。
  /// 只清库不刷新的话，界面还显示着刚被删掉的数据（用户会以为没删掉）。
  final VoidCallback? onDataChanged;

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

  /// 导出**可导回的备份**（JSON，不是那份给人看的 CSV）。
  ///
  /// 为什么单独做一个：`_export` 那份 CSV 是**报表** —— 日期精确到分钟、
  /// 重量跟着显示单位走，拿它当备份等于把数据换成"长得像"的另一份。
  /// 这一份带上组 id、训练 id、热身标记、RPE、秒级时间，重量一律 kg，
  /// 导回来是同一批数据。对手最集中的抱怨就是数据丢失，这是我们的答案。
  Future<void> _exportBackup() async {
    // allSets() 只给正式组，正好用来枚举"练过哪些训练"；
    // 再按训练把**整份**记录（含热身组）读回来。
    final List<SetRecord> normal = await widget.store.allSets();
    final List<String> ids = <String>[];
    for (final SetRecord s in normal) {
      if (!ids.contains(s.workoutId)) ids.add(s.workoutId);
    }

    final List<Workout> workouts = <Workout>[];
    for (final String id in ids) {
      final List<SetRecord> sets = await widget.store.setsFor(id);
      if (sets.isEmpty) continue;
      // 训练行只用来拿起止时间，**不作为数据来源**：项目里真发生过
      // "只写了 set_record、没写 workout 行"的缺陷，那时 loadWorkout 返回 null ——
      // 如果备份依赖它，那一整次训练就会被静默丢掉。备份是最后一道防线，
      // 所以缺训练行时用最早那一组的完成时间兜底，宁可时间粗一点也不丢数据。
      final Workout? loaded = await widget.store.loadWorkout(id);
      final Workout w = Workout(
        id: id,
        startedAtMs: loaded?.startedAtMs ?? sets.first.completedAtMs,
        endedAtMs: loaded?.endedAtMs,
      );
      w.sets.addAll(sets);
      workouts.add(w);
    }

    final List<ExerciseData> rows = await widget.repository.search(limit: 500);
    final Map<String, String> names = <String, String>{
      for (final ExerciseData r in rows) r.id: r.name,
    };

    final int now = DateTime.now().millisecondsSinceEpoch;
    final String json = encodeBackup(
      workouts: workouts,
      exerciseNames: names,
      nowMs: now,
    );
    await widget.backupExporter
        .shareBackup(json, fileName: backupFileName(now));
    if (!mounted) return;

    final int sets = workouts.fold<int>(0, (int a, Workout w) => a + w.sets.length);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已导出 ${workouts.length} 次训练 / $sets 组'),
        backgroundColor: Tokens.elevated,
      ),
    );
  }

  /// 粘贴导入备份。
  ///
  /// 这条路径同时解决三件事：数据可携带（合规）、用户换了手机能回来、
  /// 以及可用性测试需要的"预置 6 周历史"（`docs/usability-test-kit.md` §4）。
  Future<void> _importBackup() async {
    final BackupParse? parsed = await showDialog<BackupParse>(
      context: context,
      builder: (BuildContext ctx) => const _ImportBackupDialog(),
    );
    if (parsed == null || !mounted) return;

    if (!parsed.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('没导入：${parsed.error}'),
          backgroundColor: Tokens.danger,
        ),
      );
      return;
    }

    for (final Workout w in parsed.workouts) {
      for (final SetRecord s in w.sets) {
        await widget.store.saveSet(s);
      }
      // 训练行本身也要写：时长要用 started_at / ended_at
      await widget.store.saveWorkout(w);
    }
    if (!mounted) return;

    await _load();
    widget.onDataChanged?.call();
    if (!mounted) return;

    final String skipped =
        parsed.skippedSets > 0 ? '，跳过 ${parsed.skippedSets} 条没认出来的' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '已导入 ${parsed.workoutCount} 次训练 / ${parsed.setCount} 组$skipped'),
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

  /// 切换**体重**单位。与训练重量那个开关各写各的列 ——
  /// `setBodyWeightUnit` 里会把其它设置原样带回去。
  Future<void> _setBodyUnit(BodyWeightUnit u) async {
    if (u == widget.bodyUnit) return;
    await widget.profile.setBodyWeightUnit(u);
    widget.onBodyUnitChanged?.call(u);
  }

  Widget _bodyUnitChip(BodyWeightUnit u) {
    final bool active = widget.bodyUnit == u;
    return GestureDetector(
      key: Key('body-unit-${u.wire}'),
      onTap: () => _setBodyUnit(u),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
        height: 36,
        decoration: BoxDecoration(
          color: active ? Tokens.volt : Tokens.surface,
          borderRadius: BorderRadius.circular(Tokens.rPill),
        ),
        child: Text(
          u.label,
          style: TextStyle(
            color: active ? Tokens.voltInk : Tokens.text2,
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
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
          unit: widget.bodyUnit,
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
    // 首页那行"我上周练了 N 次"也要跟着归零
    widget.onDataChanged?.call();
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
          const Divider(height: 1),
          // **体重单独一行**：中国用户称体重说斤（1 斤 = 500 g），
          // 而杠铃重量说 kg —— 一个开关管两件事就会打架：
          // 把训练切到磅的人，不该连体重也变成磅。
          Padding(
            padding: const EdgeInsets.all(Tokens.s4),
            child: Row(
              children: <Widget>[
                const Text('体重',
                    style: TextStyle(color: Tokens.text2, fontSize: 13)),
                const SizedBox(width: Tokens.s3),
                _bodyUnitChip(BodyWeightUnit.kg),
                const SizedBox(width: Tokens.s2),
                _bodyUnitChip(BodyWeightUnit.jin),
                const Spacer(),
                const Text(
                  '1 斤 = 500 g',
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
              '复制成 CSV 到剪贴板，可贴进表格（报表，不能导回来）',
              style: TextStyle(color: Tokens.text3, fontSize: 13),
            ),
            trailing: const Icon(Icons.ios_share, color: Tokens.text3, size: 20),
          ),
          const Divider(height: 1, color: Tokens.line),
          ListTile(
            key: const Key('export-backup'),
            contentPadding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
            onTap: _exportBackup,
            title: const Text(
              '导出备份文件',
              style: TextStyle(color: Tokens.text, fontSize: 15),
            ),
            subtitle: const Text(
              '存成文件或发给自己。导回来是同一批数据',
              style: TextStyle(color: Tokens.text3, fontSize: 13),
            ),
            trailing: const Icon(Icons.save_alt, color: Tokens.text3, size: 20),
          ),
          const Divider(height: 1, color: Tokens.line),
          ListTile(
            key: const Key('import-backup'),
            contentPadding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
            onTap: _importBackup,
            title: const Text(
              '导入备份',
              style: TextStyle(color: Tokens.text, fontSize: 15),
            ),
            subtitle: const Text(
              '把备份内容粘进来。换手机、或想补齐历史都用它',
              style: TextStyle(color: Tokens.text3, fontSize: 13),
            ),
            trailing: const Icon(Icons.download, color: Tokens.text3, size: 20),
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

/// 粘贴导入的弹层。
///
/// 做成独立 StatefulWidget 而不是就地 showDialog：错误要**留在弹层里**显示 ——
/// 关掉弹层再弹一条 SnackBar，用户就得重新粘一遍。
class _ImportBackupDialog extends StatefulWidget {
  const _ImportBackupDialog();

  @override
  State<_ImportBackupDialog> createState() => _ImportBackupDialogState();
}

class _ImportBackupDialogState extends State<_ImportBackupDialog> {
  final TextEditingController _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// 从剪贴板取。手机上长按输入框也能粘，但多一个按钮少一步操作。
  Future<void> _paste() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    setState(() {
      _text.text = data?.text ?? '';
      _error = _text.text.isEmpty ? '剪贴板是空的' : null;
    });
  }

  void _confirm() {
    final BackupParse parsed = parseBackup(_text.text);
    if (!parsed.ok) {
      setState(() => _error = parsed.error);
      return;
    }
    if (parsed.setCount == 0) {
      setState(() => _error = '这份备份里一条记录都没有');
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('import-backup-dialog'),
      backgroundColor: Tokens.elevated,
      title: const Text('导入备份'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '把「导出备份文件」得到的内容粘进下面。\n'
            '导入是幂等的：同一份粘两次不会变成两份。',
            style: TextStyle(color: Tokens.text3, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: Tokens.s3),
          TextField(
            key: const Key('import-text'),
            controller: _text,
            maxLines: 6,
            style: const TextStyle(color: Tokens.text, fontSize: 13),
            decoration: InputDecoration(
              hintText: '{\"app\":\"lianleme\", …}',
              hintStyle: const TextStyle(color: Tokens.text3, fontSize: 13),
              filled: true,
              fillColor: Tokens.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Tokens.rCard),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: Tokens.s2),
            Text(
              _error!,
              key: const Key('import-error'),
              style: const TextStyle(color: Tokens.danger, fontSize: 13),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('import-paste'),
          onPressed: _paste,
          child: const Text('从剪贴板粘贴'),
        ),
        TextButton(
          key: const Key('import-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('import-confirm'),
          onPressed: _confirm,
          child: const Text('导入'),
        ),
      ],
    );
  }
}
