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
import '../../core/app_tab_bar.dart';
import '../../core/vi_cards.dart';
import '../progress/achievements_screen.dart';
import '../progress/badges.dart';
import '../progress/experience.dart';
import '../progress/streak_protection.dart';
import 'training_time.dart';
import '../progress/level.dart';
import '../progress/streak.dart';
import '../../core/units.dart';
import '../../data/body_metric_repository.dart';
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import '../../analytics/analytics.dart';
import '../../analytics/outbox.dart';
import '../../backup/backup_config.dart';
import '../../backup/cloud_backup.dart';
import '../../backup/login_session.dart';
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
    this.debugCompleteLines,
    this.cloud,
    this.account,
    this.reminder = ReminderSettings.off,
    this.reminderHint,
    this.protectedDays = const <String>{},
    this.onReminderChanged,
  });

  final LocalStore store;
  final ExerciseRepository repository;
  final ProfileRepository profile;

  /// **被补签保护过的那些日子**（`YYYY-MM-DD`，第二部分第 2 条）。
  ///
  /// 连续天数要用它："这一天算不算断"多了一种答案。⚠️ 它与首页必须**同名同值** ——
  /// 两处各算一遍就会出现"首页说连续 12 天、这一页说 0 天"那种一眼可见的矛盾
  /// （这一段就是为此补的）。判据在 `features/progress/streak_protection.dart`。
  final Set<String> protectedDays;

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

  /// 登录会话（可选注入：测试用）—— 与 [cloud] 同一个模式
  final LoginSession? account;

  /// 要不要显示「云备份」入口。**null = 按编译期配置判断**
  /// （`isCloudBackupConfigured`：没配服务器地址就不显示 —— 详见 lib/backup/backup_config.dart）。
  ///
  /// 做成可覆盖的参数是为了**能测**：编译期常量在测试里改不了，
  /// 于是"配了地址会怎样"这条路径就会永远没人验证过。
  final bool? cloudBackupAvailable;

  /// **测试专用**：覆盖"已集齐的收集线"（A1 的展示性奖励）。
  ///
  /// 为什么要留这个口子：集齐一条线在真实数据里意味着 **20 枚徽章全解锁** ——
  /// 连续打卡那条线要 365 天不断，力量那条线要 500 吨。为了测"集齐之后段位卡会换色"
  /// 去造一年记录，测的是"数据生成器"而不是这段界面；而**判据本身**
  /// （`completedLines()`）已经在 `badges_test.dart` 里用构造出来的 BadgeStatus 钉死了。
  /// 所以这里只覆盖**展示层**的输入，判据一个字节都没动。
  ///
  /// null（默认）= 按真实记录算 —— 生产路径永远是这一条。
  final List<BadgeLine>? debugCompleteLines;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  TrainingStats? _stats;
  bool _loading = true;

  /// 连续打卡天数（2026-10-05，新 VI 的「我」页要）。**算出来的**，见
  /// `features/progress/streak.dart` —— 存一份就会和训练记录不一致。
  int _streak = 0;

  /// 当前这条链里有几天是补签撑住的（"其中 N 天是补签"要用）。
  int _protectedInStreak = 0;


  /// 全部组记录。成就页要用（徽章也是现算的），**在这里存一份传给那一屏** ——
  /// 让成就页自己去数据库再读一遍，同一份数据就有了两条路径。
  List<SetRecord> _sets = const <SetRecord>[];

  /// 已解锁徽章枚数（A5 段位）。**在 [`_load`] 里算一次**，不在 `build` 里算 ——
  /// `badgeStatuses()` 是 O(全部组记录) 的全表扫，放进 `build` 就是每帧一次。
  /// 好在 `_load()` 本来就已经把全量 `allSets()` 读出来了（成就页要用），
  /// 所以这里再扫一遍只是同一份数据上多跑一次纯计算，**不额外碰库**。
  ///
  /// ⚠️ 段位、徽章都不落库：改历史 / 导入备份 / 换设备恢复之后它自己就对。
  int _unlockedBadges = 0;

  /// 徽章总数（段位卡的进度条要用；随徽章扩到 70~80 自己涨，不写死）。
  int _totalBadges = 0;

  /// **已集齐的收集线**（A1 的展示性奖励）。空 = 一条都没集齐。
  ///
  /// 它和 [_unlockedBadges] 是同一次计算的两个结果：集齐一条线 = 那条线上每一枚都解锁，
  /// 所以**不能**另存一份状态（那就会和徽章本身不一致）。
  List<BadgeLine> _completeLines = const <BadgeLine>[];

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
      // **认补签**的连续天数（与首页同一个函数、同一份 protectedDays）——
      // 用 `streak.dart` 的 `currentStreak` 就会在补过签之后和首页对不上。
      final DateTime now = DateTime.now();
      _streak = streakWithProtection(sets, widget.protectedDays, now);
      _protectedInStreak =
          protectedDaysInStreak(sets, widget.protectedDays, now);
      _sets = sets;
      // 段位只看"已解锁几枚"，线奖励只看"哪条线集齐了"。同一份 sets 上再跑一次纯函数，
      // 见字段注释里的取舍（不额外碰库）。
      final List<BadgeStatus> badges = badgeStatuses(sets);
      final ({int unlocked, int total}) tally = badgeTally(badges);
      _unlockedBadges = tally.unlocked;
      _totalBadges = tally.total;
      _completeLines = completedLines(badges);
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

  Future<void> _openPreferences() {
    // 固定训练时段建议（第二部分第 6 条）：从**全部记录**里算"你多数几点开练"。
    // 算在这里（点进偏好设置那一刻）而不是 `_load()`：它只在那一屏用得上，
    // 没必要每次进「我」页都算一遍。
    final ({int hour, int count})? dominant = dominantWorkoutHour(_sets);
    return _open(PreferencesScreen(
      profile: widget.profile,
      unit: widget.unit,
      onUnitChanged: widget.onUnitChanged,
      restOverrideSec: widget.restOverrideSec,
      onRestOverrideChanged: widget.onRestOverrideChanged,
      reminder: widget.reminder,
      reminderHint: widget.reminderHint,
      onReminderChanged: widget.onReminderChanged,
      trainingTimeSuggestion: trainingTimeSuggestion(_sets),
      suggestedReminderMinutes:
          dominant == null ? null : suggestedReminderMinutes(dominant.hour),
    ));
  }

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
        account: widget.account,
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
      padding: EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s5,
          Tokens.s5 + AppTabBar.reservedSpaceFor(context)),
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
        // 「我的进度」（2026-10-06，A 档重排）：**等级 / 段位 / 经验收成一张卡三行**。
        // 起因是用户看完训记「我的」页拆解之后说"我们这一屏太乱了"，诊断见
        // `docs/plan-profile-ia.md` §三：三张并列的大卡各带一条进度条、视觉权重一样，
        // 用户读不出"哪个才是主线"；而它们本来就是同一件事的三种说法
        // （Lv 看次数、段位看徽章数、经验看组数）。**数据口径一个都没动**。
        profileSectionTitle('我的进度'),
        _progressCard(),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      StatTile(
                        label: '连续天数',
                        value: '$_streak 天',
                        valueKey: const Key('profile-stat-streak'),
                      ),
                      // **含补签时必须写出来**（与首页同一句文案，见 streak_protection.dart）——
                      // 只写"连续 12 天"而其中 1 天是补的，那就是一句假话。
                      // 原来这句话在下面那张打卡卡里；A 档重排把打卡卡撤了（它复述的就是这一格），
                      // 但**这句披露不能跟着没**，所以搬到这里。
                      if (_protectedInStreak > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: Tokens.s1),
                          child: Text(
                            streakProtectionSuffix(_protectedInStreak),
                            key: const Key('profile-streak-label'),
                            style: const TextStyle(color: Tokens.text3, fontSize: 11),
                          ),
                        ),
                    ],
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
        ],
        const SizedBox(height: Tokens.s5),
        // 成就入口（2026-10-05）：**放统计下面、设置上面** ——
        // 它读的就是刚算出来的那些数，"我练了多少"与"我拿到了什么"挨着看才成立。
        profileSectionTitle('成就'),
        settingsCard(<Widget>[
          navTile(
            key: const Key('open-achievements'),
            title: '我的成就',
            // 下一个连续里程碑（原来在打卡卡里）挪进副标题 —— A 档重排撤掉了那张卡，
            // 而它其实是"目标"，与"我拿到了什么"同属成就那一族。
            // 到顶时 `streakCopy` 会如实换一句话，**不编**下一个目标。
            subtitle: _streak > 0 ? '徽章与收集进度 · ${streakCopy(_streak)}' : '徽章与收集进度',
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

  /// 等级卡。数字走 Oswald，进度条复用共用件 —— 与首页打卡卡是同一种"卡片 + 进度"。
  /// **我的进度**（2026-10-06，A 档重排）：等级 / 段位 / 经验**三行一张卡**。
  ///
  /// 为什么收：三张并列的大卡各带一条进度条、视觉权重一样，用户读不出"哪个才是主线"；
  /// 而它们本来就是同一件事的三种说法（Lv 看**次数**、段位看**已解锁徽章枚数**、
  /// 经验看**累计组数**）—— 诊断与取舍见 `docs/plan-profile-ia.md` §三/§四。
  /// **数据口径一个都没动**：三个数仍然是算出来的，一列都没落库。
  ///
  /// 三行的 key 与原来那三张卡**同名**（`profile-level-*` / `rank-*` / `experience-*`），
  /// 所以钉着它们的测试依然有效；只有 `rank-card` / `rank-card-line` 的语义从"整张卡"
  /// 变成"段位那一行"—— A1 的集齐奖励仍然是"给这一行描一圈那条线的颜色"。
  Widget _progressCard() {
    final LevelInfo lv = levelFor(_stats?.workoutCount ?? 0);
    final ExperienceInfo exp = experienceFor(_stats?.setCount ?? 0);
    final ({String name, int need}) cur = rankFor(_unlockedBadges);
    final ({String name, int need, int remaining})? next = nextRank(_unlockedBadges);
    // 段位这一段内部的进度：底线 = 当前段位门槛，顶线 = 下一段门槛。
    // 从 0 算的话青铜与白银会长得一模一样；到顶画满（已经没有"下一段"，画半截是假话）。
    final double rankProgress = next == null
        ? 1
        : ((_unlockedBadges - cur.need) / (next.need - cur.need)).clamp(0.0, 1.0);
    final List<BadgeLine> done = widget.debugCompleteLines ?? _completeLines;

    /// 一行 = 图标 + 标题（右侧可带一个数）+ 进度条 + 一行小字。
    Widget row({
      required Widget leading,
      required String title,
      required Key titleKey,
      String? trailing,
      Key? trailingKey,
      required double progress,
      required String hint,
      required Key hintKey,
    }) =>
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(width: 28, height: 28, child: Center(child: leading)),
            const SizedBox(width: Tokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(title,
                            key: titleKey,
                            style: const TextStyle(
                                color: Tokens.text, fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                      if (trailing != null)
                        Text(trailing,
                            key: trailingKey,
                            style: Tokens.display(13, weight: 700, color: Tokens.text2)),
                    ],
                  ),
                  const SizedBox(height: Tokens.s2),
                  ViProgressBar(value: progress),
                  const SizedBox(height: Tokens.s2),
                  Text(hint,
                      key: hintKey,
                      style: const TextStyle(color: Tokens.text3, fontSize: 11, height: 1.4)),
                ],
              ),
            ),
          ],
        );

    // 段位那一行：集齐一条收集线时给它描一圈那条线的颜色（A1 的展示性奖励）。
    // 只有"已集齐"时才包那层 Container —— 一枚都没集齐时出现色圈就是在说假话。
    final Widget rankRow = row(
      leading: const Icon(Icons.workspace_premium, color: Tokens.accent, size: 20),
      title: '${cur.name} · ${cur.need} 枚',
      titleKey: const Key('rank-name'),
      progress: rankProgress,
      hint: next == null
          ? '已经是最高段位 · 已解锁 $_unlockedBadges / $_totalBadges 枚'
          : '还差 ${next.remaining} 枚到${next.name} · 已解锁 $_unlockedBadges / $_totalBadges 枚',
      hintKey: const Key('rank-next'),
    );

    return ViCard(
      // 等级 > 1 时整张卡发光（原来挂在等级卡上；收成一张之后它就是这张卡的状态）
      glow: lv.level > 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          row(
            leading: Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(color: Tokens.accent, shape: BoxShape.circle),
              child: Center(
                child: Text('${lv.level}',
                    key: const Key('profile-level-number'),
                    style: Tokens.display(13, weight: 700, color: Tokens.accentInk)),
              ),
            ),
            title: levelLabel(lv),
            titleKey: const Key('profile-level-label'),
            trailing: '${_stats?.workoutCount ?? 0} 次',
            trailingKey: const Key('profile-level-count'),
            progress: lv.progress,
            hint: levelHint(lv),
            hintKey: const Key('profile-level-hint'),
          ),
          const Divider(height: Tokens.s5, color: Tokens.line),
          if (done.isEmpty)
            KeyedSubtree(key: const Key('rank-card'), child: rankRow)
          else
            Container(
              key: const Key('rank-card-line'),
              padding: const EdgeInsets.all(Tokens.s2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Tokens.rCard),
                border: Border.all(color: lineColor(done.first.category), width: 1.5),
              ),
              child: KeyedSubtree(key: const Key('rank-card'), child: rankRow),
            ),
          const Divider(height: Tokens.s5, color: Tokens.line),
          row(
            leading: const Icon(Icons.bolt, color: Tokens.accent, size: 20),
            title: '经验 · ${exp.title}',
            titleKey: const Key('experience-title'),
            trailing: '${exp.sets} 组',
            trailingKey: const Key('experience-sets'),
            progress: exp.progress,
            hint: experienceHint(exp),
            hintKey: const Key('experience-hint'),
          ),
        ],
      ),
    );
  }
}
