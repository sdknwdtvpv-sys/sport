/// 练了么 · **设置**（2026-10-07，v1.60.0）
///
/// 用户原话："**所有的设置相关的能不能集成到右上角，一个小齿轮图标。**"
///
/// 之前这三组（偏好设置 / 数据与备份 / 隐私与关于）铺在「我」页上，与"我练了多少、
/// 我拿到了什么"混在一起 —— 而「我」页真正该回答的是后者。现在它们搬到这一屏，
/// 入口是**外壳顶栏右上角那枚齿轮**（`core/app_top_bar.dart`）：与你在哪一屏无关，
/// 五个 tab 都点得到。
///
/// ⚠️ **三个入口的 key 一个都没改**（`open-preferences` / `open-data-tools` /
/// `open-privacy-about`）：改的只是"从哪儿进去"。测试也跟着只改入口
/// （`profile_test.dart` 里那几条现在从这一屏开始），断言本身原样。
library;

import 'package:flutter/material.dart';

import '../../analytics/analytics.dart';
import '../../analytics/outbox.dart';
import '../../backup/backup_config.dart';
import '../../backup/cloud_backup.dart';
import '../../backup/login_session.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../data/body_metric_repository.dart';
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import '../../data/profile_repository.dart';
import '../../domain/models.dart';
import 'backup_exporter.dart';
import 'data_tools_screen.dart';
import 'privacy_about_screen.dart';
import 'profile_widgets.dart';
import 'reminder.dart';
import 'settings_screen.dart';
import 'training_time.dart';

class SettingsHomeScreen extends StatelessWidget {
  const SettingsHomeScreen({
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
    this.defaultStepKg,
    this.onStepChanged,
    this.restOverrideSec,
    this.onRestOverrideChanged,
    this.backupExporter = const PluginBackupExporter(),
    this.loadEvents,
    this.onDataChanged,
    this.cloudBackupAvailable,
    this.cloud,
    this.account,
    this.reminder = ReminderSettings.off,
    this.reminderHint,
    this.onReminderChanged,
    this.sets = const <SetRecord>[],
  });

  final LocalStore store;
  final ExerciseRepository repository;
  final ProfileRepository profile;
  final Analytics? analytics;
  final BodyMetricRepository? bodyMetrics;
  final WeightUnit unit;
  final BodyWeightUnit bodyUnit;
  final ValueChanged<WeightUnit>? onUnitChanged;
  final ValueChanged<BodyWeightUnit>? onBodyUnitChanged;

  /// 用户定过的加重步进（kg）。null = 没设过（10.9 清单第 8a 条）。
  final double? defaultStepKg;

  /// 步进改了之后通知上层留一份（否则退出设置再进来看到的还是旧值 ——
  /// 这一屏是 push 上来的，上层的 state 不会自己知道）。
  final ValueChanged<double>? onStepChanged;
  final int? restOverrideSec;
  final ValueChanged<int?>? onRestOverrideChanged;
  final BackupExporter backupExporter;
  final Future<List<AnalyticsEventPayload>> Function()? loadEvents;
  final VoidCallback? onDataChanged;
  final bool? cloudBackupAvailable;
  final CloudBackup? cloud;
  final LoginSession? account;
  final ReminderSettings reminder;
  final String? reminderHint;
  final Future<bool> Function(ReminderSettings settings)? onReminderChanged;

  /// 全部训练记录。只有「偏好设置」里那条"你多数几点开练"的建议要用它
  /// （由调用方算好传进来也行，但直接给记录更省一层参数 —— `dominantWorkoutHour` 是纯函数）。
  final List<SetRecord> sets;

  @override
  Widget build(BuildContext context) {
    final bool cloudOn = cloudBackupAvailable ?? isCloudBackupConfigured;
    return ProfileSubPage(
      title: '设置',
      children: <Widget>[
        settingsCard(<Widget>[
          navTile(
            key: const Key('open-preferences'),
            title: '偏好设置',
            subtitle: _prefsSubtitle,
            onTap: () => _openPreferences(context),
          ),
          const Divider(height: 1, color: Tokens.line),
          navTile(
            key: const Key('open-data-tools'),
            title: '数据与备份',
            subtitle: '身体数据 · 导出 / 导入 · 删除全部数据',
            onTap: () => _openDataTools(context),
          ),
          const Divider(height: 1, color: Tokens.line),
          navTile(
            key: const Key('open-privacy-about'),
            title: '隐私与关于',
            subtitle: '统计开关 · 隐私政策 · 收集清单 · 开源许可',
            onTap: () => _openPrivacyAbout(context),
          ),
        ]),
        const SizedBox(height: Tokens.s5),
        // 一句实话：这些开关**都在本机生效**，与"要不要联网"是两件事
        // （会联网的只有统计与云备份，两处都在各自的二级页里说清了）。
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s1),
          child: Text(
            cloudOn
                ? '设置都存在这台手机上。唯一会联网的是匿名统计与你自己开的云备份。'
                : '设置都存在这台手机上，不上传任何人。',
            style: const TextStyle(color: Tokens.text3, fontSize: 13, height: 1.5),
          ),
        ),
      ],
    );
  }

  /// 入口的"当前值"直接写在副标题里（少进一次页面就能看到现状）。
  String get _prefsSubtitle {
    final String rest = restOverrideSec == null ? '休息跟随动作' : '休息 $restOverrideSec 秒';
    return '$rest · 单位 ${unit.wire} · 渐进建议';
  }

  Future<void> _openPreferences(BuildContext context) {
    // 固定训练时段建议（第二部分第 6 条）：从**全部记录**里算"你多数几点开练"。
    // 算在点进那一刻（这一屏只用得上这一处），不必每次进设置都算。
    final ({int hour, int count})? dominant = dominantWorkoutHour(sets);
    return Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PreferencesScreen(
        profile: profile,
        unit: unit,
        onUnitChanged: onUnitChanged,
        defaultStepKg: defaultStepKg,
        // 「所有动作都改」的落库在这里：这一屏手里有动作仓库（偏好那一页只拿到
        // ProfileRepository）。选完**立刻**铺开，不等返回 —— 设置页没有"刷新"这一步。
        onStepAllChanged: (double kg) async {
          await repository.setAllWeightIncrements(kg);
          await profile.setDefaultWeightIncrement(kg);
          onStepChanged?.call(kg);
        },
        restOverrideSec: restOverrideSec,
        onRestOverrideChanged: onRestOverrideChanged,
        reminder: reminder,
        reminderHint: reminderHint,
        onReminderChanged: onReminderChanged,
        trainingTimeSuggestion: trainingTimeSuggestion(sets),
        suggestedReminderMinutes:
            dominant == null ? null : suggestedReminderMinutes(dominant.hour),
      ),
    ));
  }

  Future<void> _openDataTools(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => DataToolsScreen(
          store: store,
          repository: repository,
          profile: profile,
          analytics: analytics,
          bodyMetrics: bodyMetrics,
          unit: unit,
          bodyUnit: bodyUnit,
          onBodyUnitChanged: onBodyUnitChanged,
          backupExporter: backupExporter,
          onDataChanged: onDataChanged,
          cloudBackupAvailable: cloudBackupAvailable,
          cloud: cloud,
          account: account,
        ),
      ));

  Future<void> _openPrivacyAbout(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PrivacyAboutScreen(
          profile: profile,
          analytics: analytics,
          loadEvents: loadEvents,
          backupExporter: backupExporter,
        ),
      ));
}
