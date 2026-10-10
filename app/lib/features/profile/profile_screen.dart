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

import '../../core/icon_spec.dart';
import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/theme.dart';
import '../../core/app_tab_bar.dart';
import '../../core/vi_cards.dart';
import '../progress/achievements_screen.dart';
import '../progress/badges.dart';
import '../progress/streak_protection.dart';
import '../progress/level.dart';
import '../progress/progress_data.dart' show workoutCountIn;
import '../progress/weekly_challenge.dart' show weekBounds;
import '../../core/units.dart';
import '../../data/body_metric_repository.dart';
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import '../../analytics/analytics.dart';
import '../../analytics/outbox.dart';
import '../../backup/cloud_backup.dart';
import '../../backup/login_session.dart';
import '../../data/profile_repository.dart';
import '../../domain/models.dart';
import 'backup_exporter.dart';
import 'profile_widgets.dart';
import 'reminder.dart';
import 'identity_screen.dart';
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
  /// （现在只有设置页 `SettingsHomeScreen` 在用这个值：没配服务器地址时，
  /// 那句实话写成"不上传任何人"。见 lib/backup/backup_config.dart。）
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

  /// 昵称 / 账号 ID（null = 没设过 / 没登录）。身份块用，见 `_identityCard()`。
  String? _nickname;
  String? _accountId;
  String? _email;

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
    // 身份那两行（昵称 / 账号 ID）。ID 只在**登录之后**才有 —— 从会话里读，
    // 读不到就显示"还没登录"（**不编一个号**，见 identity_screen.dart 的文件头）。
    final String? nickname = await widget.profile.nickname();
    final StoredSession? session = await widget.profile.authSessionStore().read();
    if (!mounted) return;
    setState(() {
      _nickname = nickname;
      _accountId = session?.accountId;
      _email = session?.email;
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

  /// 「本周已练 N 次」—— 与首页那行事实**同一个口径**（训练次数，不是当周挑战的进度）。
  ///
  /// 2026-10-10：这一页原来那张「我的进度」卡有三条进度条，收成一条之后，
  /// 连续天数与本周次数降级成**一行事实**，就摆在等级那条进度下面。
  String? get _weekWorkoutFact {
    if (_sets.isEmpty) return null;
    final ({DateTime start, DateTime end}) w = weekBounds(DateTime.now());
    final int n = workoutCountIn(_sets, w.start, w.end);
    return n <= 0 ? null : '本周已练 $n 次';
  }

  /// 身份块：**昵称 + 账号 ID**（10.7 清单第 7 条）。
  ///
  /// 这里只**显示**，点一下进「身份」那一屏改 —— 「我」页要一眼看出"这是谁的记录"，
  /// 而不是变成一个表单。
  ///
  /// ⚠️ 两行字的口气不一样，是因为两件事的性质不一样：
  ///   * 昵称没设过 → 如实写「还没设昵称」（**不编默认名**）；
  ///   * 没登录 → 写「还没登录」，**不显示 ID**（凭空编号 = 假身份）。
  Widget _identityCard() => ViCard(
        key: const Key('profile-identity'),
        onTap: _openIdentity,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _nickname ?? '还没设昵称',
                    key: const Key('profile-nickname'),
                    style: TextStyle(
                      color: _nickname == null ? Tokens.text3 : Tokens.text,
                      fontSize: Tokens.fsBody,
                      fontWeight: Tokens.fwBold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _accountId == null
                        ? '还没登录 · 点一下设昵称'
                        : 'ID ${IdentityScreen.shortId(_accountId!)} · 点一下改昵称',
                    key: const Key('profile-id-line'),
                    style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Tokens.text3, size: IconSpec.m),
          ],
        ),
      );

  Future<void> _openIdentity() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => IdentityScreen(
        profile: widget.profile,
        accountId: _accountId,
        email: _email,
      ),
    ));
    if (mounted) await _load(); // 昵称可能改了
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
    // ⚠️ 这里原来还有一行 `final bool cloudOn = …`，只给页脚那句隐私说明用；
    // 那句话 2026-10-09 删掉了（10.9 清单第 5 条），所以这个局部变量也一并删 ——
    // 留着就是一个"算出来没人用"的值，而 `dart analyze --fatal-infos` 会红。
    // ⚠️ 但 `cloudBackupAvailable` 这个**构造参数要保留**：设置页（SettingsHomeScreen）
    // 还在用它决定那句实话怎么写，而它的入口就在设置页上。

    return ListView(
            padding: EdgeInsets.fromLTRB(
          Tokens.s5,
          Tokens.s4,
          Tokens.s5,
          Tokens.s5 + AppTabBar.reservedSpaceFor(context)),
      children: <Widget>[
        // 身份块（2026-10-07，10.7 清单第 7 条）：昵称 + 账号 ID。
        // ⚠️ 页面的标题（「我的」）不在这里了 —— v1.60.0 起它在外壳顶栏上
        // （`core/app_top_bar.dart`），五个 tab 共用一条；这一页从身份开始。
        _identityCard(),
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

        // 2026-10-05 按新 VI 换成统计卡；**2026-10-09 收成两张**（10.9 清单第 4 条）。
        //
        // 原来这四张是「训练次数 / 连续天数 / 总组数 / 总容量」，而进步页那四张是
        // 「区间容量 / 训练次数 / 总组数 / 个人纪录」—— 三项重名，用户的原话是
        // "重复度太高"。分工写死：
        //   * **进步页 = 周期口径**（本周/本月/全年 + 与上一周期对比 + 趋势 + 个人纪录）；
        //   * **这一页 = 累计口径 + 连续天数**。
        // 于是「训练次数」「总组数」两张卡**从这一页拿掉** —— 不是信息没了：
        // 那两个累计数字就在上面那张「我的进度」里（Lv 那一行右边是「12 次」，
        // 经验条那一行右边是「340 组」，key 是 `profile-level-count` / `experience-sets`）。
        // 一张页面上同一个数字出现两遍，才是这一条要治的东西。
        if (s.isEmpty)
          settingsCard(<Widget>[
            const Padding(
              padding: EdgeInsets.all(Tokens.s5),
              child: Text(
                '还没有训练记录。练完第一次，这里就有数了。',
                style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsSub, height: Tokens.lhNormal),
              ),
            ),
          ])
        else ...<Widget>[
          // ⚠️ 2026-10-10：这两格原来是**两张 ViCard**（与「进步」页那四张同款的大方块）。
          // 按"只有图表配卡片底、纯数字用细线分节"这条规矩收成**一条细线带**
          // （上下 hairline + 中间一道竖线），与「进步」页的统计带同一个语言。
          IntrinsicHeight(
            child: Container(
              key: const Key('profile-stats-band'),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Tokens.hair),
                  bottom: BorderSide(color: Tokens.hair),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(width: 0),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Tokens.s4),
                      child: StatTile(
                        label: '连续天数',
                        value: '$_streak 天',
                        valueKey: const Key('profile-stat-streak'),
                      ),
                    ),
                  ),
                  Container(width: 1, color: Tokens.line),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(
                          left: Tokens.s4, top: Tokens.s4, bottom: Tokens.s4),
                      child: StatTile(
                        // 「累计容量」而不是「总容量」：与进步页那个「本周容量」对看时，
                        // 口径写在标签上，用户不必去猜哪边是全部历史
                        label: '累计容量',
                        value: s.volumeLabel,
                        valueKey: const Key('profile-stat-volume'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // **含补签时必须写出来**（与首页同一句文案，见 `streak_protection.dart`）——
          // 只写"连续 12 天"而其中 1 天是补的，那就是一句假话。
          //
          // 这句话的位置改过两次，第二次是**回归修复**（用户看完 v1.57.0 截图指出
          // "两个格子不一样高"）：A 档重排把打卡卡撤了（它复述的就是这一格），
          // 这句披露不能跟着没，于是我先把它塞进了「连续天数」那张卡里 ——
          // 结果那张卡比同排的「训练次数」高出一行。
          // 现在它是**网格下面独立的一行**：格子只放数字，披露不占格子的高度；
          // 靠右对齐，是为了让它在视觉上仍然归属右边那格（连续天数）。
          if (_protectedInStreak > 0)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.s1),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  streakProtectionSuffix(_protectedInStreak),
                  key: const Key('profile-streak-label'),
                  style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro),
                ),
              ),
            ),
        ],
        const SizedBox(height: Tokens.s5),
        // 成就入口（2026-10-05）：**放统计下面、设置上面** ——
        // 它读的就是刚算出来的那些数，"我练了多少"与"我拿到了什么"挨着看才成立。
        profileSectionTitle('成就'),
        settingsCard(<Widget>[
          navTile(
            key: const Key('open-achievements'),
            title: '成就',
            // ⚠️ 2026-10-10：这一行现在是**收藏册的唯一入口**，所以把"我拿到几枚"
            // 直接写在右边（`12 / 73`）—— 原来那句"徽章与收集进度 · 再坚持 4 天解锁…"
            // 把**下一个目标**塞在这里，而目标属于首页那行事实、不该再占一行。
            subtitle: '已解锁 $_unlockedBadges / $_totalBadges 枚'
                '${_completeLines.isEmpty ? '' : ' · 集齐 ${_completeLines.length} 条收集线'}',
            onTap: _openAchievements,
          ),
        ]),
        // ⚠️ 这里原来有三组设置入口（偏好设置 / 数据与备份 / 隐私与关于）。
        // 2026-10-07（v1.60.0）按用户的要求搬进了**独立设置页**（`settings_home_screen.dart`），
        // 入口是外壳顶栏右上角那枚齿轮 —— 与你在哪一屏无关，五个 tab 都点得到。
        // 三个入口的 key 一个都没改。
        const SizedBox(height: Tokens.s5),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s1),
          child: Text(
            // ⚠️ **只剩版本号了**（2026-10-09，用户 10.9 清单第 5 条）：
            // 这里原来还跟着一句"数据默认只在本机 / 不上传任何人"——用户问"真的有必要吗"，
            // 结论是**不必要**：那是**去向**承诺，而它已经在三处说得更正式
            // （「我 → 隐私与关于」、两道单独同意门、隐私政策正文）；写在页脚像小字免责声明。
            //
            // ⚠️ 删掉它顺带**取消了那条"跟着配置走"的规则**（`cloudOn` 曾在这里分叉：
            // 配了备份服务器就不能说"不上传"）。那句话不在了，这条规则也就没有对象 ——
            // 所以守着它的测试一并删掉，别留一条永远为真的空规则。
            // 版本号仍然来自 core/app_info.dart，由 app_version_test 与 pubspec 对齐
            // （以前这里写死 '1.0.0'，两次切版后界面上的版本号就错了两个版本）。
            '版本 $kAppVersion',
            style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap, height: Tokens.lhNormal),
          ),
        ),
      ],
    );
  }

  /// **唯一的进度条**（2026-10-10）：等级。
  ///
  /// 这一格原来有**三行**（等级 / 段位 / 经验），每行各带一条进度条 —— 用户 10.10 的
  /// 设计评审之后收成**一条**（`docs/plan-ux-2026-10-10.md` §五-B）：
  ///   * **段位与收集线**搬去「成就」页 —— 那本收藏册本来就有分组与段位图例，
  ///     同一件事在两张屏上各画一条进度条，正是"读不出哪个才是主线"的来源；
  ///   * **经验那一行取消**：它和等级都是"练了多少"的另一种说法（一个看次数、一个看组数），
  ///     两把尺子量同一件事；
  ///   * **连续天数与本周次数留在这里，但只是事实** —— 一行小字，没有进度条。
  ///
  /// 留下的 key：`profile-level-number` / `profile-level-label` / `profile-level-count` /
  /// `profile-level-hint`（原来那四行里钉着它们的测试一条没改）。
  Widget _progressCard() {
    final LevelInfo lv = levelFor(_stats?.workoutCount ?? 0);
    return ViCard(
      // 等级 > 1 时整张卡发光（原来挂在等级卡上；收成一张之后它就是这张卡的状态）
      glow: lv.level > 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                    color: Tokens.accent, shape: BoxShape.circle),
                child: Center(
                  child: Text('${lv.level}',
                      key: const Key('profile-level-number'),
                      style: Tokens.display(13,
                          weight: 700, color: Tokens.accentInk)),
                ),
              ),
              const SizedBox(width: Tokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(levelLabel(lv),
                              key: const Key('profile-level-label'),
                              style: const TextStyle(
                                  color: Tokens.text,
                                  fontSize: Tokens.fsSub,
                                  fontWeight: Tokens.fwStrong)),
                        ),
                        Text('${_stats?.workoutCount ?? 0} 次',
                            key: const Key('profile-level-count'),
                            style: Tokens.display(13,
                                weight: 700, color: Tokens.text2)),
                      ],
                    ),
                    const SizedBox(height: Tokens.s2),
                    ViProgressBar(value: lv.progress),
                    const SizedBox(height: Tokens.s2),
                    Text(levelHint(lv),
                        key: const Key('profile-level-hint'),
                        style: const TextStyle(
                            color: Tokens.text3, fontSize: Tokens.fsMicro, height: Tokens.lhSnug)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.s3),
          // **事实，不是进度**：连续多少天 + 这周练了几次。
          // 与首页那行同一个口径（`main.dart` 的 `_weekWorkoutFact`）。
          Row(
            key: const Key('profile-fact-line'),
            children: <Widget>[
              const Icon(Icons.local_fire_department, color: Tokens.text3, size: IconSpec.s),
              const SizedBox(width: Tokens.s2),
              Expanded(
                child: Text(
                  <String>[
                    _streak > 0
                        ? streakLabelWithProtection(_streak, _protectedInStreak)
                        : '还没开始记连续天数',
                    if (_weekWorkoutFact != null) _weekWorkoutFact!,
                  ].join(' · '),
                  key: const Key('profile-fact-label'),
                  style: const TextStyle(
                      color: Tokens.text3, fontSize: Tokens.fsMicro, height: Tokens.lhSnug),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
