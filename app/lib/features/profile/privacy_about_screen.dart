/// 练了么 · 「隐私与关于」（从「我」页收进来的第三组）
///
/// **为什么有这一页**（2026-10-01，用户反馈「我」页太复杂）：隐私开关与三份对外文本
/// 原先直接铺在「我」页最下面，和"训练统计""休息时长"混在一起 ——
/// 而这一组的共同点是**给别人看的**（审核员、想查清单的用户），不是每天要碰的。
///
/// 有两条合规约束在这一页上必须继续成立（它们是硬要求，不是排版偏好）：
///   * **隐私政策两次点击之内到**（小米隐私合规指引的"四步之内"）：冷启动 →「我」→
///     「隐私与关于」→「隐私政策」= 3 次点击，仍在四步之内；
///   * **164 号文的双清单**必须是**二级菜单**（不能只埋在政策长文里）：
///     现在它是三级页，但入口链路上每一步都是独立可见的菜单项 —— 判定依据是
///     「能不能从菜单点进去」，不是"第几层"。`tool/privacy-audit.mjs` 与
///     `app/test/collection_list_test.dart` 都盯着这条。
library;

import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/theme.dart';
import '../../analytics/analytics.dart';
import '../../analytics/analytics_export.dart';
import '../../analytics/outbox.dart';
import '../../data/profile_repository.dart';
import 'backup_exporter.dart';
import 'collection_list_screen.dart';
import 'privacy_policy_screen.dart';
import 'profile_widgets.dart';

class PrivacyAboutScreen extends StatefulWidget {
  const PrivacyAboutScreen({
    super.key,
    required this.profile,
    this.analytics,
    this.loadEvents,
    this.backupExporter =
        const PluginBackupExporter(subject: '练了么 · 统计事件（核对用）'),
  });

  final ProfileRepository profile;

  /// 隐私开关要能立刻生效，所以直接持有埋点实例（测试可不传）
  final Analytics? analytics;

  /// 读出本机攒下的**全部**埋点事件（含发不出去的那些），供导出用。
  ///
  /// **null = 不显示导出入口。** 用回调而不是直接拿 outbox，是为了让这一屏
  /// 不认识数据库（测试注入一个闭包就够，不必建库）。
  ///
  /// 为什么这个入口必须存在：没配上报地址的包里 `_NullTransport` 恒失败，
  /// 事件只会在本地越攒越多、**没有任何出口** —— 而 `tap_count` 是
  /// "less is more"唯一的客观守卫（见 `analytics_export.dart` 的文件头）。
  final Future<List<AnalyticsEventPayload>> Function()? loadEvents;

  /// 交给系统分享（与"导出备份文件"同一个通道；只是主题不同）
  final BackupExporter backupExporter;

  @override
  State<PrivacyAboutScreen> createState() => _PrivacyAboutScreenState();
}

class _PrivacyAboutScreenState extends State<PrivacyAboutScreen> {
  bool _analyticsEnabled = false; // 默认关（见 db.dart 那一列的注释）
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bool enabled = await widget.profile.analyticsEnabled();
    // 页面读到的值也同步给 analytics：用户可能在别处改过（或刚启动），
    // 界面与"到底记不记"必须是同一个事实。
    widget.analytics?.setEnabled(enabled);
    if (!mounted) return;
    setState(() {
      _analyticsEnabled = enabled;
      _loading = false;
    });
  }

  /// 关掉隐私开关：立刻生效 + 落库。
  /// **功能完全不受影响** —— 只是不再记录（崩溃上报走独立通道）。
  Future<void> _toggleAnalytics(bool on) async {
    setState(() => _analyticsEnabled = on);
    widget.analytics?.setEnabled(on);
    await widget.profile.setAnalyticsEnabled(on);
  }

  /// 打开隐私政策（应用内必须能读到 —— 见 privacy_policy_screen.dart 的说明）
  Future<void> _openPrivacyPolicy() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext ctx) => const PrivacyPolicyScreen(),
      ),
    );
  }

  /// 打开「个人信息收集清单 / 与第三方共享清单」（164 号文，二级菜单）。
  void _openCollectionList() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext ctx) => const CollectionListScreen(),
      ),
    );
  }

  /// 导出本机攒下的统计事件（JSONL，一行一条）。
  ///
  /// 三个刻意的行为，都在 UI 上如实反映：
  ///   * **空队列不导出空文件** —— 那只会让收件人以为"导出了但里面什么都没有"；
  ///   * **导出完不做任何清理**（不删队列、不改开关）—— 导出是只读动作；
  ///   * **这个动作本身不上报**（见 `analytics_export.dart` 的文件头）。
  Future<void> _exportEvents() async {
    final Future<List<AnalyticsEventPayload>> Function()? load =
        widget.loadEvents;
    if (load == null) return;

    final List<AnalyticsEventPayload> events = await load();
    if (!mounted) return;
    if (events.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            '还没有攒下事件。先练一次再回来导',
          ),
          backgroundColor: Tokens.elevated,
        ),
      );
      return;
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    await widget.backupExporter.shareBackup(
      buildEventsJsonl(events),
      fileName: eventsFileName(now),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已导出 ${events.length} 条统计事件（一行一条）'),
        backgroundColor: Tokens.elevated,
      ),
    );
  }

  /// 打开开源许可（Flutter 自带页面）。
  ///
  /// 为什么有这个入口：隐私政策的第三方清单只列了**直接依赖**，而"包里到底有什么"
  /// 的准确答案在 Flutter 的许可页 —— 它由构建时的 `NOTICES` 生成，覆盖**全部**传递依赖。
  /// 与其在文档里写一句无法自证的"全部第三方代码"，不如让用户（和审核员）能当场翻。
  ///
  /// 页面语言跟随 App 的本地化（`MaterialApp.localizationsDelegates` 里带了中文），
  /// 包名与许可原文仍是英文 —— 那本来就是英文。
  void _openLicenses() {
    showLicensePage(
      context: context,
      applicationName: '练了么',
      applicationVersion: kAppVersion,
      applicationLegalese: '训练数据只存在这台设备上。',
    );
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
      title: '隐私与关于',
      children: <Widget>[
        profileSectionTitle('隐私开关'),
        settingsCard(<Widget>[
          SwitchListTile(
            key: const Key('analytics-switch'),
            value: _analyticsEnabled,
            onChanged: _toggleAnalytics,
            activeThumbColor: Tokens.accentInk,
            activeTrackColor: Tokens.accent,
            contentPadding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
            title: const Text(
              '帮助改进产品',
              style: TextStyle(color: Tokens.text, fontSize: 15),
            ),
            subtitle: const Text(
              // 默认是**关**的（v1.28.0），所以这句话要从"打开会怎样"写起 ——
              // 旧文案「关掉后不再上报」是给"默认开"写的，对新装用户是错的。
              '打开后会匿名上报使用数据；关闭时一条都不发，功能完全不受影响',
              style: TextStyle(color: Tokens.text3, fontSize: 13, height: 1.4),
            ),
          ),
          // 导出入口**只在开关打开时出现**（2026-10-01 拍板）：
          // 关着的时候本来就没有在收集，入口必然是空的 —— 那种按钮比没有更糟。
          if (_analyticsEnabled && widget.loadEvents != null) ...<Widget>[
            const Divider(height: 1, color: Tokens.line),
            navTile(
              key: const Key('analytics-export'),
              title: '导出统计事件',
              subtitle: '把本机攒下的事件导成文件，一行一条',
              onTap: _exportEvents,
            ),
          ],
        ]),
        const SizedBox(height: Tokens.s5),
        profileSectionTitle('对外文本'),
        settingsCard(<Widget>[
          // 隐私政策入口。**必须在四步之内能到**（小米的隐私合规指引）：
          // 冷启动 → 「我」→ 「隐私与关于」→ 这里 = 三次点击，够了。
          navTile(
            key: const Key('privacy-policy'),
            title: '隐私政策',
            // 文案审计（2026-10-04）：原来这里写着「我们收集什么、不收集什么，逐条写在里面」——
            // 那是把标题换个说法又说一遍。**想不出该说什么，就什么都不说**（`subtitle` 现在可空）。
            onTap: _openPrivacyPolicy,
          ),
          const Divider(height: 1, color: Tokens.line),
          // 164 号文要求的「双清单」，以**二级菜单**形式展示（不能只在政策长文里写一段）。
          // 文本是生成物：收集清单 ← privacy-facts.json，共享清单 ← 政策里的 SDK 表。
          navTile(
            key: const Key('collection-list'),
            title: '个人信息收集清单',
            // 删掉「收集了什么、与谁共享（164 号文要求的两份清单）」：前半句是复述标题，
            // 后半句是**我们自己的规章知识**（哪条文要求它），用户在界面上一辈子用不到。
            // 「164 号文」这个依据仍然留在本文件的注释与 `docs/` 里，没有丢信息，只是不上屏。
            onTap: _openCollectionList,
          ),
          const Divider(height: 1, color: Tokens.line),
          // 开源许可：政策里说"完整第三方清单在应用内可查"，这里就是那个"应用内"。
          // 用 Flutter 自带的 `showLicensePage` —— 不引入任何 UI 依赖，它会把
          // 随包分发的**全部**组件（含传递依赖：框架、Skia、ICU…）及其许可列出来。
          navTile(
            key: const Key('open-source-licenses'),
            title: '开源许可',
            // 「这个包里用到的全部第三方组件与许可」= 复述「开源许可」四个字 → 删。
            onTap: _openLicenses,
          ),
        ]),
      ],
    );
  }
}
