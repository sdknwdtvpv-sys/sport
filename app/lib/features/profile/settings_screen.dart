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

import 'package:flutter/cupertino.dart' show CupertinoPicker, FixedExtentScrollController;
import 'package:flutter/material.dart';

import '../../core/glass_segmented.dart';
import '../../core/glass_switch.dart';
import '../../core/glass_surface.dart';
import '../../core/theme.dart';
import '../../core/glass_overlay.dart';
import '../../core/units.dart';
import '../../core/weight_step_dialog.dart';
import '../../data/profile_repository.dart';
import '../../domain/models.dart';
import 'profile_widgets.dart';

import 'reminder.dart';

/// `Color` → `#RRGGBB`（原生按这个解析；`GlassSegmented` 的原生字色用它）
String _hexOf(Color c) {
  final int v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}


/// 休息时长的候选值。放在这里而不是 units.dart：它是产品决定，不是单位问题。
const List<int> kRestChoices = <int>[45, 60, 90, 120, 180];

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({
    super.key,
    required this.profile,
    required this.unit,
    this.onUnitChanged,
    this.defaultStepKg,
    this.onStepAllChanged,
    this.restOverrideSec,
    this.onRestOverrideChanged,
    this.reminder = ReminderSettings.off,
    this.reminderHint,
    this.trainingTimeSuggestion,
    this.suggestedReminderMinutes,
    this.onReminderChanged,
  });

  final ProfileRepository profile;

  /// 当前显示单位。**只影响显示**：统计与判定始终按 kg 算。
  final WeightUnit unit;

  /// 用户切了单位之后通知上层重建（否则别的 Tab 还按旧单位显示）。
  final ValueChanged<WeightUnit>? onUnitChanged;

  /// 用户自己定过的**加重步进**（kg）。null = 还没设过 → 各动作按器械给
  /// （10.9 清单第 8a 条）。
  final double? defaultStepKg;

  /// 用户把步进改成「所有动作都改」（kg）。
  ///
  /// ⚠️ 落库**不在这里**：这一页不认识动作仓库（它只拿到 `ProfileRepository`）。
  /// 与训练屏同一条边界 —— 界面负责问，写由外壳做（否则就是两个真相）。
  final Future<void> Function(double kg)? onStepAllChanged;

  /// 休息时长偏好。**null = 跟随动作自带的值**，这是默认。
  final int? restOverrideSec;

  /// 用户改了休息时长之后通知上层（训练屏要用新值）
  final ValueChanged<int?>? onRestOverrideChanged;

  /// 当前的训练提醒设置。
  final ReminderSettings reminder;

  /// 「下次提醒：…」那一行。**由上层算好传下来**（要"今天练过没有"，那是数据层的事）。
  /// null = 没开提醒，不显示。
  final String? reminderHint;

  /// 建议里那个时刻（一天里的第几分钟）。null = 没有建议。
  /// **单独给一个数**而不是让这一页去解析那句话：文案与数不该互相依赖。
  final int? suggestedReminderMinutes;

  /// **固定训练时段建议**（第二部分第 6 条）。null = 不说（数据不够 / 没有固定时段）。
  ///
  /// 由上层按 `training_time.dart` 的 `trainingTimeSuggestion()` 算好传下来
  /// （那需要全部训练记录）。**点它只是把提醒时间改成建议那个点**，
  /// 开关仍然要用户自己开 —— 我们不偷偷设闹钟。
  final String? trainingTimeSuggestion;

  /// 用户改了提醒设置。**返回是否真的生效** —— false 表示系统没给通知权限
  /// （Android 13+ / iOS 都会问一次；用户拒绝时开关要弹回去，不能假装打开了）。
  ///
  /// 存库与请求权限都**不在这里做**：那是 `ReminderService` 的事。
  /// 否则会出现"设置页存了一份、训练结束又按另一份排"这种两个真相。
  final Future<bool> Function(ReminderSettings settings)? onReminderChanged;

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  ProgressionMode _mode = ProgressionMode.doubleProgression;
  bool _loading = true;

  /// 提醒设置在本页也留一份（理由同上面的单位/休息时长：这一页是 push 上来的路由）
  late ReminderSettings _reminder = widget.reminder;

  // ⚠️ 单位和休息时长都要**在本页留一份自己的状态**：它们是上层传进来的值，
  // 而这一页是 push 上来的路由 —— 上层 setState 不会重建它，
  // 直接用 widget.unit / widget.restOverrideSec 的话，点完胶囊界面不会变
  // （值存进库了，但看起来像没生效）。
  late WeightUnit _unit = widget.unit;
  late int? _rest = widget.restOverrideSec;

  /// 加重步进同样在本页留一份（同上的理由）—— 选完胶囊界面要立刻变，
  /// 而这一页是 push 上来的路由，上层 setState 不会重建它。
  late double? _step = widget.defaultStepKg;

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

  /// 开/关提醒。**打开时先要系统权限**（Android 13+ / iOS 都会问一次）——
  /// 用户拒绝时开关要弹回去并说清原因，不能假装打开了。
  Future<void> _toggleReminder(bool on) async {
    final ReminderSettings next = _reminder.copyWith(enabled: on);
    final Future<bool> Function(ReminderSettings)? handler = widget.onReminderChanged;
    final bool ok = handler == null ? true : await handler(next);
    if (!mounted) return;
    if (!ok) {
      // 权限被拒：**不改开关**，并如实说（比"开了但什么都不响"好）
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('系统没有给通知权限 —— 到「系统设置 → 通知」里允许之后再来开'),
      ));
      return;
    }
    setState(() => _reminder = next);
  }

  /// 选休息时长：**底部弹出**。
  ///
  /// 为什么收进弹出层：6 个选项铺在页面上就是半个屏幕（真机两次反馈），
  /// 而它是"设一次就不管"的偏好。页面只留当前值 + 一句解释，
  /// 与「提醒时间」同一套交互 —— 用户不必学第二种。
  ///
  /// ⚠️ 返回值用 [_RestPick] 包一层：`null` 有两种含义（"关掉了弹层" 与
  /// "选了跟随动作"），直接 pop `int?` 会把它们混成一件（经典坑）。
  Future<void> _pickRest() async {
    final _RestPick? pick = await showAppSheet<_RestPick>(
      context: context,
      backgroundColor: Tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.rCard)),
      ),
      // ⚠️ **必须可滚动**（widget 测试当场抓到 `RenderFlex overflowed by 50 pixels`）：
      // 标题 + 6 个选项 ≈ 400pt，而底部弹层默认最高只到屏幕的 9/16 ——
      // 小屏 / 大字号下会直接溢出。滚一下就好，不需要 `isScrollControlled`。
      builder: (BuildContext ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(Tokens.s4, Tokens.s4, Tokens.s4, Tokens.s2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('休息时长',
                    style: TextStyle(
                        color: Tokens.text2,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ),
            _restOption(ctx, key: 'rest-follow', sec: null, label: '跟随动作'),
            for (final int sec in kRestChoices)
              _restOption(ctx, key: 'rest-$sec', sec: sec, label: '$sec 秒'),
            const SizedBox(height: Tokens.s2),
          ],
          ),
        ),
      ),
    );
    if (pick == null || !mounted) return; // 关掉弹层 = 没改
    await _setRest(pick.sec);
  }

  Widget _restOption(BuildContext ctx,
          {required String key, required int? sec, required String label}) =>
      ListTile(
        key: Key(key),
        onTap: () => Navigator.of(ctx).pop(_RestPick(sec)),
        title: Text(label,
            style: TextStyle(
                color: _rest == sec ? Tokens.accent : Tokens.text, fontSize: 15)),
        trailing: _rest == sec
            ? const Icon(Icons.check, size: 18, color: Tokens.accent)
            : null,
      );

  /// 采纳"固定训练时段"建议：**只把提醒时间改到那个点，并打开开关**（用户是点了
  /// 那句话才走到这里的，点了就等于同意"定在这个点"）。仍然走 `_toggleReminder`
  /// 那条路，所以系统权限那一步一个字都没少。
  Future<void> _applySuggestedTime() async {
    final int? minutes = widget.suggestedReminderMinutes;
    if (minutes == null) return;
    final ReminderSettings next = _reminder.copyWith(
      enabled: true,
      minutesOfDay: minutes,
    );
    final Future<bool> Function(ReminderSettings)? handler = widget.onReminderChanged;
    final bool ok = handler == null ? true : await handler(next);
    if (!mounted) return;
    if (!ok) {
      // 权限被拒：与 `_toggleReminder` 同一套话术（同一条路，不许两处口径）
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('系统没有给通知权限 —— 到「系统设置 → 通知」里允许之后再来开'),
      ));
      return;
    }
    setState(() => _reminder = next);
  }

  /// 选提醒时间：**闹钟式双滚轮**（与系统闹钟同一种交互）。
  ///
  /// 2026-10-04 真机反馈换掉的：Material 那个表盘点了半天、它的"输入模式"在 iOS 上
  /// 还会被键盘挡住下半屏（截图为证）。而"设提醒时间"这件事，iPhone 用户的肌肉记忆
  /// 就是**滚轮 + 完成** —— 这也与仓库一贯的"用用户已经会的东西"一致。
  Future<void> _pickReminderTime() async {
    final TimeOfDay? picked = await _showTimeWheel(
      context,
      initialHour: _reminder.hour,
      initialMinute: _reminder.minute,
    );
    if (picked == null || !mounted) return;
    final ReminderSettings next =
        _reminder.copyWith(minutesOfDay: picked.hour * 60 + picked.minute);
    final Future<bool> Function(ReminderSettings)? handler = widget.onReminderChanged;
    final bool ok = handler == null ? true : await handler(next);
    if (!mounted || !ok) return;
    setState(() => _reminder = next);
  }

  /// 当前休息时长怎么念（页面上那一行的标题）。
  String get _restLabel => _rest == null ? '跟随动作' : '$_rest 秒';

  /// 当前加重步进怎么念。⚠️ 库里的值**永远是 kg**，这里按显示单位念
  /// （lb 用户看到的是 「5 lb」而不是 2.3 这种换算尾巴）。
  String get _stepLabel => _step == null
      ? '跟随动作'
      : '${formatStep(_step!, _unit)} ${_unit.wire}';

  /// 改加重步进（10.9 清单第 8a 条）。
  ///
  /// 与训练屏里那一处是**同一个弹层**（`core/weight_step_dialog.dart`），
  /// 只是这里不问范围 —— 设置页里"只改默认值"是件用户看不见效果的事
  /// （它只影响以后新建的自定义动作），摆出来就是让人猜。
  ///
  /// 语义与训练屏的「所有动作都改」完全一致：铺到整个动作库 + 记成默认值。
  /// 有些健身房的片子只有 5 kg 一档，那种地方就是要一次铺开。
  Future<void> _pickStep() async {
    final WeightStepPick? pick = await pickWeightStep(
      context,
      unit: _unit,
      // 没设过时拿 2.5 开场（那是引擎的兜底步进，见 `workout_controller.dart`）
      current: _step ?? 2.5,
      allowSingleScope: false,
    );
    if (pick == null || !mounted) return;
    await widget.onStepAllChanged?.call(pick.kg);
    if (!mounted) return;
    setState(() => _step = pick.kg);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('所有动作的加重步进都改成 ±${formatStep(pick.kg, _unit)} ${_unit.wire}'),
    ));
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
        // **一行 + 底部弹出**（2026-10-04 第二次真机反馈）：6 个选项铺在页面上就是
        // 半个屏幕，而它是"设一次就不管"的偏好 —— 页面上只留**当前值**与一句解释，
        // 选择收进弹出层（和下面的「提醒时间」同构）。顺带说明：那 6 个胶囊
        // 之前是"每个占一整行"，根因是共享组件 `choicePill` 在 `Wrap` 里被撑满，
        // 那个 bug 也一起修掉了（见 `CHANGELOG.md` v1.42.2）。
        settingsCard(<Widget>[
          ListTile(
            key: const Key('rest-row'),
            onTap: _pickRest,
            contentPadding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
            title: Text(
              _restLabel,
              key: const Key('rest-current'),
              style: const TextStyle(
                  color: Tokens.accent, fontSize: 15, fontWeight: FontWeight.w600),
            ),
            // 副标题只在**真的需要解释**的时候出现（2026-10-04 文案审计）：
            //   选「跟随动作」时，「跟随动作」这四个字本身看不出是什么 → 留一句解释；
            //   选了具体秒数时，标题已经写着 `90 秒` → **副标题删掉**（复述一遍而已）。
            // 原来那句还带了个「（核心 45 秒、深蹲 180 秒……）」的例子，属于"顺便科普"，一并去掉。
            subtitle: _rest == null
                ? const Text(
                    // 10.8 清单第 9 条：训练屏上那句「休息 · 按你的节奏」被删掉了
                    // （用户原话：「这几个字有什么存在的必要吗？或者能不能集成到设置里的
                    // 休息时间里」）—— 解释挪到这里：休息时长**是**会跟着你实际节奏微调的，
                    // 而这件事属于"设置"的话题，不该占用训练屏。
                    '每个动作用它自带的休息时长；练起来之后会按你实际歇的节奏微调',
                    style: TextStyle(color: Tokens.text3, fontSize: 12.5, height: 1.4),
                  )
                : null,
            trailing: const Icon(Icons.chevron_right, size: 18, color: Tokens.text3),
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
                // iOS 26：等宽 + 底托/选中胶囊两块玻璃；非 iOS 原样（Android 一个像素都不动）。
                // ⚠️ 这里在**卡片的平底**上，所以用 `.clear` + 一点点白，而不是 `.regular` ——
                // 背后没有内容经过时，`.regular` 会变成一块灰板（2026-10-06 试出来的）。
                GlassSegmentedRow(
                  count: WeightUnit.values.length,
                  index: WeightUnit.values.indexOf(_unit),
                  itemWidth: 52,
                  height: 32,
                  style: GlassStyle.clear,
                  baseTint: '#FFFFFF14',
                  pillTint: '#FFFFFF2E',
                  // 字由原生画（玻璃里面）——Flutter 那份在玻璃背后会被折射出第二份虚影
                  labels: <String>[for (final WeightUnit u in WeightUnit.values) u.wire],
                  selectedColor: _hexOf(Tokens.text),
                  unselectedColor: _hexOf(Tokens.text2),
                  labelFontSize: 13,
                  itemBuilder: (int i, bool glass) {
                    final WeightUnit u = WeightUnit.values[i];
                    final bool on = _unit == u;
                    if (!glass) {
                      // 老样子（`choicePill` 自己就是热区）
                      return Padding(
                        padding: EdgeInsets.only(
                            right: u == WeightUnit.values.last ? 0 : Tokens.s2),
                        child: choicePill(
                          key: Key('unit-${u.wire}'),
                          label: u.wire,
                          active: on,
                          onTap: () => _setUnit(u),
                        ),
                      );
                    }
                    return GestureDetector(
                      key: Key('unit-${u.wire}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _setUnit(u),
                      child: Text(
                        u.wire,
                        style: TextStyle(
                          color: on ? Tokens.text : Tokens.text2,
                          fontSize: 13,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    );
                  },
                ),
                // ⚠️ 这里原来右边还有一句「只影响显示」（12pt 灰字）。
                // 2026-10-08 用户真机反馈（10.8 清单第 4 条）："**只影响显示这五个字
                // 有什么显示的必要吗**" —— 而且它**挤在 kg/lb 分段控件上**（截图里
                // 两层文字叠在一起，那不是文案问题、是布局事故）。
                // 删掉它是两头都对的做法：`docs/copy.md` 早就定了"别写解释性语言"，
                // 而这一句正是那类（"单位只影响显示"是**我们内部的实现约定**，
                // 用户不需要知道底层存的是 kg）。约定仍然写在代码注释与
                // `docs/data-model.md` §单位里，只是不再印到界面上。
              ],
            ),
          ),
        ]),
        const SizedBox(height: Tokens.s5),
        // 加重步进（10.9 清单第 8a 条）：与「休息时长」同一套交互 ——
        // 一行写当前值，选择收进弹层。
        profileSectionTitle('加重量'),
        settingsCard(<Widget>[
          ListTile(
            key: const Key('step-row'),
            onTap: _pickStep,
            contentPadding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
            title: Text(
              _stepLabel,
              key: const Key('step-current'),
              style: const TextStyle(
                  color: Tokens.accent, fontSize: 15, fontWeight: FontWeight.w600),
            ),
            // 副标题只在**真的需要解释**的时候出现（同「休息时长」那条规矩）：
            // 「跟随动作」四个字看不出是什么意思，所以要一句；选了具体数值时
            // 标题已经写着 `5 kg`，再说一遍就是复述。
            subtitle: _step == null
                ? const Text(
                    '每个动作按器械给一个合适的档；改一次可以铺到所有动作',
                    style: TextStyle(color: Tokens.text3, fontSize: 12.5, height: 1.4),
                  )
                : null,
            trailing: const Icon(Icons.chevron_right, size: 18, color: Tokens.text3),
          ),
        ]),
        const SizedBox(height: Tokens.s5),
        profileSectionTitle('渐进建议'),
        settingsCard(<Widget>[
          AppSwitchTile(
            key: const Key('progression-switch'),
            value: _mode != ProgressionMode.off,
            onChanged: _toggleProgression,
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
        profileSectionTitle('训练提醒'),
        settingsCard(<Widget>[
          AppSwitchTile(
            key: const Key('reminder-switch'),
            value: _reminder.enabled,
            onChanged: _toggleReminder,
            title: const Text(
              '到点还没练就提醒我',
              style: TextStyle(color: Tokens.text, fontSize: 15),
            ),
            // 文案审计（2026-10-04，你点名删掉「练过就不打扰」）：
            //   * 打开时**不要副标题** —— 下面那一行「提醒时间」已经写着几点，
            //     再写「每天 14:13 提醒一次」是复述（而且要维护两处，容易写岔）；
            //     「（本地通知，不联网）」也是复述（关闭态那句已经说了去向）。
            //   * 关闭时只留**去向**那一句（"本地 / 不上传"是隐私承诺，不能说没就没），
            //     删掉「默认关闭」—— 开关就摆在眼前，谁都看得见它是关的。
            //   * 「练过就不打扰」这条**行为**没有丢：它出现在真正影响用户的那一刻 ——
            //     提示行会写「下次提醒：明天 14:13（今天已经练过了，不打扰）」。
            subtitle: _reminder.enabled
                ? null
                : const Text(
                    '在本机提醒，不上传任何东西',
                    style: TextStyle(color: Tokens.text3, fontSize: 13, height: 1.4),
                  ),
          ),
          // 固定训练时段建议（第二部分第 6 条）：**只在有明确集中时段时出现**，
          // 而且只是"要不要定在这个点"的一句话 —— 点它只改时间，不改开关。
          if (widget.trainingTimeSuggestion != null)
            ListTile(
              key: const Key('reminder-suggestion'),
              onTap: _applySuggestedTime,
              contentPadding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
              leading: const Icon(Icons.schedule, color: Tokens.text3, size: 20),
              title: Text(
                widget.trainingTimeSuggestion!,
                style: const TextStyle(color: Tokens.text2, fontSize: 13, height: 1.4),
              ),
            ),
          if (_reminder.enabled)
            Column(
              children: <Widget>[
                ListTile(
                  key: const Key('reminder-time'),
                  onTap: _pickReminderTime,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: Tokens.s4),
                  title: const Text('提醒时间',
                      style: TextStyle(color: Tokens.text, fontSize: 15)),
                  trailing: Text(
                    _reminder.label,
                    key: const Key('reminder-time-label'),
                    style: const TextStyle(
                        color: Tokens.accent,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                // 「下次什么时候响」—— 没有这一行时，用户设完看不到任何反馈，
                // 而规则会把"今天已过/今天已练"的情形顺延到明天（真机上就是这么被误解成"没响"的）。
                if (widget.reminderHint != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Tokens.s4, 0, Tokens.s4, Tokens.s3),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.reminderHint!,
                        key: const Key('reminder-next'),
                        style: const TextStyle(
                            color: Tokens.text3, fontSize: 12.5, height: 1.35),
                      ),
                    ),
                  ),
              ],
            ),
        ]),
      ],
    );
  }
}

/// 闹钟式的**双滚轮**选时间（小时 / 分钟），底部弹出。
///
/// 为什么不用 `showTimePicker`：真机上试过 —— 表盘要一格一格转、容易点偏，
/// 切到"输入模式"后键盘会把对话框下半截挡住（中文键盘还有候选栏）。
/// 而滚轮是 iPhone 用户设闹钟的肌肉记忆，两个滚轮一次就能拨到位。
Future<TimeOfDay?> _showTimeWheel(
  BuildContext context, {
  required int initialHour,
  required int initialMinute,
}) {
  final FixedExtentScrollController hourCtl =
      FixedExtentScrollController(initialItem: initialHour);
  final FixedExtentScrollController minuteCtl =
      FixedExtentScrollController(initialItem: initialMinute);
  return showAppSheet<TimeOfDay>(
    context: context,
    backgroundColor: Tokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.rCard)),
    ),
    builder: (BuildContext ctx) {
      return SafeArea(
        child: SizedBox(
          height: 300,
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  TextButton(
                    key: const Key('time-wheel-cancel'),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('取消',
                        style: TextStyle(color: Tokens.text2)),
                  ),
                  const Spacer(),
                  const Text('提醒时间',
                      style: TextStyle(
                          color: Tokens.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton(
                    key: const Key('time-wheel-done'),
                    // ⚠️ `looping: true` 的 CupertinoPicker，`selectedItem` 是
                    // **不取模的绝对索引**：从 20 往上拨 13 格会得到 33，而不是 9。
                    // 不取模的后果很隐蔽：33 时 → 33*60 分钟 → 超出 0–1439 →
                    // 排程函数返回 null → **提醒永远不响**（测试就是这么抓到的）。
                    onPressed: () => Navigator.of(ctx).pop(TimeOfDay(
                      hour: hourCtl.selectedItem % 24,
                      minute: minuteCtl.selectedItem % 60,
                    )),
                    child: const Text('完成',
                        style: TextStyle(
                            color: Tokens.accent, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const Divider(color: Tokens.line, height: 1),
              Expanded(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: CupertinoPicker(
                        key: const Key('time-wheel-hour'),
                        scrollController: hourCtl,
                        itemExtent: 44,
                        looping: true,
                        onSelectedItemChanged: (_) {},
                        children: <Widget>[
                          for (int h = 0; h < 24; h++)
                            Center(
                              child: Text('${h.toString().padLeft(2, '0')} 时',
                                  style: const TextStyle(
                                      color: Tokens.text, fontSize: 20)),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: CupertinoPicker(
                        key: const Key('time-wheel-minute'),
                        scrollController: minuteCtl,
                        itemExtent: 44,
                        looping: true,
                        onSelectedItemChanged: (_) {},
                        children: <Widget>[
                          for (int m = 0; m < 60; m++)
                            Center(
                              child: Text('${m.toString().padLeft(2, '0')} 分',
                                  style: const TextStyle(
                                      color: Tokens.text, fontSize: 20)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 「选了哪个休息时长」。存在的意义只有一个：把"关掉弹层"（null）与
/// "选了跟随动作"（sec == null）**分开** —— 用裸 `int?` 会混成一件。
class _RestPick {
  const _RestPick(this.sec);
  final int? sec;
}
