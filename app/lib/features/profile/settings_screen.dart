/// 练了么 · 「偏好设置」（从「我」页收进来的第一组）
///
/// **为什么有这一页**（2026-10-01，用户反馈「我」页太复杂）：
/// 原先「休息时长、显示单位、渐进建议」三块直接铺在「我」页上 ——
/// 光休息时长那一组（6 个胶囊）就占掉整整一屏，而它们都是**设一次就不管**的东西。
/// 收进二级页之后，「我」页第一屏只剩统计和三个入口。
///
/// 三个设置的性质在这一页里是分明的：
///   * **休息时长**：`null` = 跟随动作自带（默认，也是推荐）；选了数字就是全局覆盖。
///   * **重量单位**：只影响**显示**，统计与判定始终按 kg 算（见 `core/units.dart`）。
///   * **渐进建议**：关掉后只记录，不再提示该上多少重量。
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/units.dart';
import '../../data/profile_repository.dart';
import '../../domain/models.dart';
import 'profile_widgets.dart';

/// 休息时长的候选值。放在这里而不是 units.dart：它是产品决定，不是单位问题。
const List<int> kRestChoices = <int>[45, 60, 90, 120, 180];

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({
    super.key,
    required this.profile,
    required this.unit,
    this.onUnitChanged,
    this.restOverrideSec,
    this.onRestOverrideChanged,
  });

  final ProfileRepository profile;

  /// 当前显示单位。**只影响显示**：统计与判定始终按 kg 算。
  final WeightUnit unit;

  /// 用户切了单位之后通知上层重建（否则别的 Tab 还按旧单位显示）。
  final ValueChanged<WeightUnit>? onUnitChanged;

  /// 休息时长偏好。**null = 跟随动作自带的值**，这是默认。
  final int? restOverrideSec;

  /// 用户改了休息时长之后通知上层（训练屏要用新值）
  final ValueChanged<int?>? onRestOverrideChanged;

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  ProgressionMode _mode = ProgressionMode.doubleProgression;
  bool _loading = true;

  // ⚠️ 单位和休息时长都要**在本页留一份自己的状态**：它们是上层传进来的值，
  // 而这一页是 push 上来的路由 —— 上层 setState 不会重建它，
  // 直接用 widget.unit / widget.restOverrideSec 的话，点完胶囊界面不会变
  // （值存进库了，但看起来像没生效）。
  late WeightUnit _unit = widget.unit;
  late int? _rest = widget.restOverrideSec;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ProgressionMode mode = await widget.profile.progressionMode();
    if (!mounted) return;
    setState(() {
      _mode = mode;
      _loading = false;
    });
  }

  Future<void> _toggleProgression(bool on) async {
    final ProgressionMode next =
        on ? ProgressionMode.doubleProgression : ProgressionMode.off;
    setState(() => _mode = next);
    await widget.profile.setProgressionMode(next);
  }

  Future<void> _setRest(int? sec) async {
    if (sec == _rest) return;
    await widget.profile.setRestOverrideSec(sec);
    widget.onRestOverrideChanged?.call(sec);
    if (mounted) setState(() => _rest = sec);
  }

  /// 切换显示单位。**先落库再通知上层重建** —— 反过来的话，
  /// 上层重建时读到的还是旧值，界面会闪一下又变回去。
  Future<void> _setUnit(WeightUnit u) async {
    if (u == _unit) return;
    await widget.profile.setUnit(u);
    widget.onUnitChanged?.call(u);
    if (mounted) setState(() => _unit = u);
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
      title: '偏好设置',
      children: <Widget>[
        profileSectionTitle('休息时长'),
        settingsCard(<Widget>[
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
                    choicePill(
                      key: const Key('rest-follow'),
                      label: '跟随动作',
                      active: _rest == null,
                      onTap: () => _setRest(null),
                    ),
                    for (final int sec in kRestChoices)
                      choicePill(
                        key: Key('rest-$sec'),
                        label: '$sec 秒',
                        active: _rest == sec,
                        onTap: () => _setRest(sec),
                      ),
                  ],
                ),
                const SizedBox(height: Tokens.s3),
                Text(
                  _rest == null
                      ? '每个动作用它自带的休息时长（核心 45 秒、深蹲 180 秒……）'
                      : '所有动作统一休息 $_rest 秒',
                  style: const TextStyle(color: Tokens.text3, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ]),
        const SizedBox(height: Tokens.s5),
        // 训练重量的单位：样式刻意弱化（一行文字 + 两个小胶囊）。
        // 它确实会改变所有数字怎么念，但那是"设置一次就不管"的东西。
        profileSectionTitle('显示'),
        settingsCard(<Widget>[
          Padding(
            padding: const EdgeInsets.all(Tokens.s4),
            child: Row(
              children: <Widget>[
                const Text('重量单位',
                    style: TextStyle(color: Tokens.text2, fontSize: 13)),
                const SizedBox(width: Tokens.s3),
                for (final WeightUnit u in WeightUnit.values) ...<Widget>[
                  choicePill(
                    key: Key('unit-${u.wire}'),
                    label: u.wire,
                    active: _unit == u,
                    onTap: () => _setUnit(u),
                  ),
                  if (u != WeightUnit.values.last) const SizedBox(width: Tokens.s2),
                ],
                const Spacer(),
                const Text(
                  '只影响显示',
                  style: TextStyle(color: Tokens.text3, fontSize: 12),
                ),
              ],
            ),
          ),
        ]),
        const SizedBox(height: Tokens.s5),
        profileSectionTitle('渐进建议'),
        settingsCard(<Widget>[
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
      ],
    );
  }
}
