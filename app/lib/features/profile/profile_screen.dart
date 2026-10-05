/// 练了么 · S10「我」
///
/// 对应 `docs/screens.md` S10。
///
/// **2026-10-01 重排**（用户反馈："我里面现在有些复杂能否有些收纳进次级页面？"，
/// 真机走查也证实了这一条：7 个区块、8 个选项胶囊、要滚三屏，导出/导入/删除
/// 全被埋在第一屏之后）。现在这一页**只留两类东西**：
///   1. **训练统计**（只读，进这页第一眼就想看的三个数）
///   2. **三个入口**：偏好设置 / 数据与备份 / 隐私与关于
/// 外加底部一行版本与环境声明。其余全部收进二级页：
///   * 「休息时长、显示单位、渐进建议」→ `settings_screen.dart`
///   * 「身体数据、导出、导入、云备份、删除全部数据」→ `data_tools_screen.dart`
///   * 「帮助改进产品开关、隐私政策、收集清单、开源许可」→ `privacy_about_screen.dart`
///
/// 为什么这么分（而不是按"数据/设置/关于"随便切）：**按"多久碰一次"切**。
/// 统计每天看；偏好和备份都是"设一次就不管"；隐私与关于是"给别人看的"。
///
/// 刻意**没有**放的：会员入口（还没有付费功能，占位入口比没有更糟）。
library;

import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/theme.dart';
import '../../core/vi_cards.dart';
import '../progress/achievements_screen.dart';
import '../progress/streak.dart';
import '../../core/units.dart';
import '../../data/body_metric_repository.dart';
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import '../../analytics/analytics.dart';
import '../../analytics/outbox.dart';
import '../../backup/backup_config.dart';
import '../../backup/cloud_backup.dart';
import '../../data/profile_repository.dart';
import '../../domain/models.dart';
import 'backup_exporter.dart';
import 'data_tools_screen.dart';
import 'privacy_about_screen.dart';
import 'profile_widgets.dart';
import 'reminder.dart';
import 'settings_screen.dart';
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
    this.loadEvents,
    this.onDataChanged,
    this.cloudBackupAvailable,
    this.cloud,
    this.reminder = ReminderSettings.off,
    this.reminderHint,
    this.onReminderChanged,
  });

  final LocalStore store;
  final ExerciseRepository repository;
  final ProfileRepository profile;

  /// 训练提醒（S10 的「训练提醒」一节）。默认关。
  final ReminderSettings reminder;

  /// 「下次提醒：…」那一行（由 main.dart 算好）
  final String? reminderHint;

  /// 用户改了提醒设置；返回"是否真的生效"（false = 系统没给通知权限）。
  final Future<bool> Function(ReminderSettings settings)? onReminderChanged;

  /// 隐私开关要能立刻生效，所以直接持有埋点实例（测试可不传）。
  /// 这一页只负责**启动时同步一次**（界面读到什么，就按什么记），开关本身在二级页。
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

  /// 读出本机攒下的埋点事件（「隐私与关于」里的导出用）。
  /// **null = 不显示那个入口**（测试与不接埋点的调用点保持干净）。
  final Future<List<AnalyticsEventPayload>> Function()? loadEvents;

  /// 数据被改动过（删光 / 导入 / 从云端恢复）—— 外壳要跟着刷新首页那个"我上周练了 N 次"。
  final VoidCallback? onDataChanged;

  /// 云备份服务。**null = 按编译期配置建一个真身**（没配地址就是 null）。
  /// 只有「删除全部数据」会用到它 —— 那一句"云端也删吗"得真的删得掉。
  final CloudBackup? cloud;

  /// 要不要显示「云备份」入口。**null = 按编译期配置判断**
  /// （`isCloudBackupConfigured`：没配服务器地址就不显示 —— 详见 lib/backup/backup_config.dart）。
  ///
  /// 做成可覆盖的参数是为了**能测**：编译期常量在测试里改不了，
  /// 于是"配了地址会怎样"这条路径就会永远没人验证过。
  final bool? cloudBackupAvailable;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  TrainingStats? _stats;
  bool _loading = true;

  /// 连续打卡天数（2026-10-05，新 VI 的「我」页要）。**算出来的**，见
  /// `features/progress/streak.dart` —— 存一份就会和训练记录不一致。
  int _streak = 0;

  /// 全部组记录。成就页要用（徽章也是现算的），**在这里存一份传给那一屏** ——
  /// 让成就页自己去数据库再读一遍，同一份数据就有了两条路径。
  List<SetRecord> _sets = const <SetRecord>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<SetRecord> sets = await widget.store.allSets();
    // 页面读到的值也同步给 analytics：用户可能在别处改过（或刚启动），
    // 界面与"到底记不记"必须是同一个事实。开关本身在「隐私与关于」里。
    final bool enabled = await widget.profile.analyticsEnabled();
    widget.analytics?.setEnabled(enabled);
    if (!mounted) return;
    setState(() {
      _stats = TrainingStats.fromSets(sets, unit: widget.unit);
      _streak = currentStreak(sets, DateTime.now());
      _sets = sets;
      _loading = false;
    });
  }

  /// 进二级页、回来刷新统计（删光 / 导入 / 云端恢复都会改统计）。
  Future<void> _open(Widget page) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (BuildContext ctx) => page),
    );
    if (!mounted) return;
    await _load();
  }

  Future<void> _openPreferences() => _open(PreferencesScreen(
        profile: widget.profile,
        unit: widget.unit,
        onUnitChanged: widget.onUnitChanged,
        restOverrideSec: widget.restOverrideSec,
        onRestOverrideChanged: widget.onRestOverrideChanged,
        reminder: widget.reminder,
        reminderHint: widget.reminderHint,
        onReminderChanged: widget.onReminderChanged,
      ));

  Future<void> _openDataTools() => _open(DataToolsScreen(
        store: widget.store,
        repository: widget.repository,
        profile: widget.profile,
        analytics: widget.analytics,
        bodyMetrics: widget.bodyMetrics,
        unit: widget.unit,
        bodyUnit: widget.bodyUnit,
        onBodyUnitChanged: widget.onBodyUnitChanged,
        backupExporter: widget.backupExporter,
        onDataChanged: widget.onDataChanged,
        cloudBackupAvailable: widget.cloudBackupAvailable,
        cloud: widget.cloud,
      ));

  Future<void> _openPrivacyAbout() => _open(PrivacyAboutScreen(
        profile: widget.profile,
        analytics: widget.analytics,
        loadEvents: widget.loadEvents,
        backupExporter: widget.backupExporter,
      ));

  /// 底下一行：入口的"当前值"直接写在副标题里（少进一次页面就能看到现状）。
  String get _prefsSubtitle {
    final String rest =
        widget.restOverrideSec == null ? '休息跟随动作' : '休息 ${widget.restOverrideSec} 秒';
    return '$rest · 单位 ${widget.unit.wire} · 渐进建议';
  }

  /// 打开「我的成就」。徽章与进度都在那一屏现算（数据由这一页带过去）。
  Future<void> _openAchievements() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AchievementsScreen(sets: _sets),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final TrainingStats s = _stats!;
    final bool cloudOn = widget.cloudBackupAvailable ?? isCloudBackupConfigured;

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
        profileSectionTitle('训练统计'),
        // 2026-10-05 按新 VI 换成**四张统计卡 + 打卡进度**（原来是三行文字）。
        // 等级 Lv 与成就徽章要新数据，按计划留给 v1.47。
        if (s.isEmpty)
          settingsCard(<Widget>[
            const Padding(
              padding: EdgeInsets.all(Tokens.s5),
              child: Text(
                '还没有训练记录。练完第一次，这里就有数了。',
                style: TextStyle(color: Tokens.text3, fontSize: 15, height: 1.5),
              ),
            ),
          ])
        else ...<Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: ViCard(
                  child: StatTile(
                    label: '训练次数',
                    value: '${s.workoutCount} 次',
                    valueKey: const Key('profile-stat-workouts'),
                  ),
                ),
              ),
              const SizedBox(width: Tokens.s3),
              Expanded(
                child: ViCard(
                  child: StatTile(
                    label: '连续天数',
                    value: '$_streak 天',
                    valueKey: const Key('profile-stat-streak'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.s3),
          Row(
            children: <Widget>[
              Expanded(
                child: ViCard(
                  child: StatTile(
                    label: '总组数',
                    value: '${s.setCount} 组',
                    valueKey: const Key('profile-stat-sets'),
                  ),
                ),
              ),
              const SizedBox(width: Tokens.s3),
              Expanded(
                child: ViCard(
                  child: StatTile(
                    label: '总容量',
                    value: s.volumeLabel,
                    valueKey: const Key('profile-stat-volume'),
                  ),
                ),
              ),
            ],
          ),
          if (_streak > 0) ...<Widget>[
            const SizedBox(height: Tokens.s3),
            _streakCard(),
          ],
        ],
        const SizedBox(height: Tokens.s5),
        // 成就入口（2026-10-05）：**放统计下面、设置上面** ——
        // 它读的就是刚算出来的那些数，"我练了多少"与"我拿到了什么"挨着看才成立。
        profileSectionTitle('成就'),
        settingsCard(<Widget>[
          navTile(
            key: const Key('open-achievements'),
            title: '我的成就',
            subtitle: '徽章与收集进度',
            onTap: _openAchievements,
          ),
        ]),
        const SizedBox(height: Tokens.s5),
        profileSectionTitle('设置'),
        settingsCard(<Widget>[
          navTile(
            key: const Key('open-preferences'),
            title: '偏好设置',
            subtitle: _prefsSubtitle,
            onTap: _openPreferences,
          ),
          const Divider(height: 1, color: Tokens.line),
          navTile(
            key: const Key('open-data-tools'),
            title: '数据与备份',
            subtitle: '身体数据 · 导出 / 导入 · 删除全部数据',
            onTap: _openDataTools,
          ),
          const Divider(height: 1, color: Tokens.line),
          navTile(
            key: const Key('open-privacy-about'),
            title: '隐私与关于',
            subtitle: '统计开关 · 隐私政策 · 收集清单 · 开源许可',
            onTap: _openPrivacyAbout,
          ),
        ]),
        const SizedBox(height: Tokens.s5),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s1),
          child: Text(
            // 版本号来自 core/app_info.dart，由 app_version_test 与 pubspec 对齐。
            // 以前这里写死 '1.0.0'，两次切版后界面上的版本号就错了两个版本。
            //
            // ⚠️ 后半句**必须跟着配置走**：这个包一旦配了备份服务器，
            // 再写"不上传任何人"就是界面在撒谎（而隐私政策那边是硬门禁，
            // 界面这边只能靠这条注释 + 测试守着）。
            cloudOn
                ? '版本 $kAppVersion · 数据默认只在本机；云备份要你手动开启，且内容端到端加密。'
                : '版本 $kAppVersion · 数据只存在这台设备上，不上传任何人。',
            style: const TextStyle(color: Tokens.text3, fontSize: 13, height: 1.5),
          ),
        ),
      ],
    );
  }

  /// 打卡进度（新 VI）。文案与首页那张卡同一套口径（`streakCopy` / 里程碑）。
  Widget _streakCard() {
    final int? next = nextStreakMilestone(_streak);
    return ViCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.local_fire_department, color: Tokens.accent, size: 18),
              const SizedBox(width: Tokens.s2),
              Text('已连续打卡 $_streak 天',
                  style: const TextStyle(
                      color: Tokens.text, fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: Tokens.s2),
          Text(streakCopy(_streak),
              style: const TextStyle(color: Tokens.text2, fontSize: 12, height: 1.4)),
          if (next != null) ...<Widget>[
            const SizedBox(height: Tokens.s3),
            ViProgressBar(value: (_streak / next).clamp(0.0, 1.0)),
          ],
        ],
      ),
    );
  }

}
