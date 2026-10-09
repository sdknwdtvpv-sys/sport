/// 练了么 ·「练」Tab 空态（S1）
///
/// 对应 `docs/screens.md` S1 与 `prototype/index.html` 第 1 屏。
///
/// 外壳（`main.dart` 的 `HomeShell`）负责 Scaffold、安全区与底部 Tab 栏；
/// 这一屏只做内容 —— Tab 栏必须由外壳持有状态才可能真的切换，
/// 假的可点按元件比没有更糟。
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/app_tab_bar.dart';
import '../../core/app_top_bar.dart';
import '../../core/units.dart';
import '../../core/vi_cards.dart';
import '../progress/streak.dart';
import '../progress/weekly_report.dart';
import '../progress/streak_protection.dart';
import 'today_planner.dart';

/// 「今天不想练」那条约 5 分钟的活动里放哪些动作（2026-10-01）。
///
/// 三条口径，都有理由：
///   * **全是按时长动作**（`track_type = time`）—— 它们没有"重量 × 次数"的容量，
///     所以**不会污染总容量与 PR 榜**（用户要的是"今天也算练了"，不是"今天破了纪录"）；
///   * **每个 1 组**（调用方给的是热身处方 `kDefaultWarmupPlan`）—— 它是活动，不是训练量；
///   * **动作从热身/拉伸/核心里挑**，不碰力量动作 —— 免得有人以为 5 分钟能替代训练。
///
/// 放在这里（而不是壳层里）是为了**能被测试直接断言**：清单里的 id 必须在动作库里真的存在。
const List<String> kLightActivityIds = <String>[
  'ex_arm_circles', // 绕臂
  'ex_cat_cow_stretch', // 猫牛式
  'ex_plank', // 平板支撑
  'ex_childs_pose', // 婴儿式
];

class TodayScreen extends StatelessWidget {
  const TodayScreen({
    super.key,
    required this.onStart,
    this.lastWeekSessions = 0,
    this.onSeePlan,
    this.onPlanHelp,
    this.onLightWorkout,
    this.onResume,
    this.resumeLabel,
    this.todayPlan = const <PlannedExercise>[],
    this.todayLabel,
    this.onReroll,
    this.onEditPlan,
    this.streak = 0,
    this.streakCopy,
    this.recent = const <({String workoutId, DateTime day, int exercises, int sets, double volume})>[],
    this.unit = WeightUnit.kg,
    this.onOpenLibrary,
    this.onLogWeight,
    this.onOpenAchievements,
    this.weeklyReport,
    this.onOpenWeeklyReport,
    this.muscleBalance,
    this.comebackNudge,
    this.protectedInStreak = 0,
    this.protectionOffer,
    this.weeklyChallengeLine,
    this.debugToday,
    this.onProtectStreak,
  });

  /// **上一周的周报**（第二部分第 1 条，2026-10-06）。
  ///
  /// 为 null = 这次不显示周报这一块。**该不该显示由外壳决定**
  /// （`weekly_report.dart` 的 `shouldShowWeeklyReport()`：周一 / 周二 + 上周练过），
  /// 这一屏只负责画 —— 判据是纯函数，测试直接打它，不必去改系统时钟。
  final WeeklyReport? weeklyReport;

  /// 点「做成一张卡」之后去哪（外壳接上分享卡预览）。
  /// **不在这里直接推页面**：这一屏是可测的纯展示层，导航留给外壳。
  final VoidCallback? onOpenWeeklyReport;

  /// **回归激励卡**（第二部分第 9 条）。
  ///
  /// 它是首页最上面那一块（问候语之下），因为**此刻这条是唯一该做的事**：
  /// 断了一周的人翻开 App，最不该看到的就是"今天练上肢"。
  ///
  /// 卡里就一句话 + 一颗"做 5 分钟活动"的按钮（[onLightWorkout]）——
  /// 没有"你落后了"、没有天数红字、也没有把连续天数拿出来说事。
  Widget _comebackCard(String text) => ViCard(
        key: const Key('comeback-nudge'),
        glow: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(text,
                key: const Key('comeback-copy'),
                style: const TextStyle(color: Tokens.text, fontSize: 14, height: 1.4)),
            if (onLightWorkout != null) ...<Widget>[
              const SizedBox(height: Tokens.s3),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: const Key('comeback-light'),
                  onPressed: onLightWorkout,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Tokens.text2,
                    side: const BorderSide(color: Tokens.line),
                    padding: const EdgeInsets.symmetric(vertical: Tokens.s3),
                  ),
                  child: const Text('做 5 分钟活动', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ],
        ),
      );

  /// **部位平衡那一行**（第二部分第 5 条）。null = 不显示。
  /// 判据与文案都在 `muscle_balance.dart`（纯函数）；外壳把动作表查好传进来。
  final String? muscleBalance;

  /// 首页那一行**本周挑战**（A3 / 第二部分第 3 条"一处实现两处用"）。
  ///
  /// 与成就页那块卡**同一份实现**（`weekly_challenge.dart` 的纯函数）：
  /// 成就页给完整的一块（怎么做、还剩几天、进度条），首页只给一行 ——
  /// 首页是"今天要做什么"的地方，挑战是"这周顺便做到什么"，给一行就够。
  ///
  /// null = 不显示（由外壳按纯函数决定，见 `weeklyChallengeLine()`）。
  final String? weeklyChallengeLine;

  /// **测试/证据图专用**：把"今天"固定成这一天（null = 真的今天）。
  ///
  /// 只影响**问候语那一行日期**与「最近训练」的"今天/昨天"措辞 ——
  /// 判据与数字都由调用方算好传进来，这一屏本来就不算任何东西。
  /// 留这个口子的原因很实际：证据图里必须出现"（其中 N 天是补签）"，
  /// 而那要求"昨天恰好是那个洞"，日子不是每天都能撞上的
  /// （第一版图里就因此出现"写着 10 月 12 日、抬头却是 10 月 6 日"的自相矛盾）。
  final DateTime? debugToday;

  /// 当前这条链里有几天是**补签**撑住的（0 = 没有）。第二部分第 2 条。
  ///
  /// 连续天数里含补签却不写出来 = 假话，所以 [streak] 与它必须一起给。
  /// 算它的函数（`protectedDaysInStreak`）在外壳那一侧，用的是与 [streak] 同一份记录 ——
  /// 两处各算一遍的话，"连续 12 天"与"其中 1 天是补签"迟早会对不上。
  final int protectedInStreak;

  /// **现在能补签**时的信息（null = 不给补）。判据在
  /// `streak_protection.dart` 的 `protectionOffer()`（纯函数），外壳算好传进来。
  final StreakProtectionOffer? protectionOffer;

  /// 点了「补签保护」。外壳负责写库 + 刷新（这一屏不碰数据层）。
  final VoidCallback? onProtectStreak;

  /// **回归激励那一句**（第二部分第 9 条）。null = 不显示。
  ///
  /// 文案由 `comeback.dart` 的 `comebackCopy()` 给（纯函数：几天没练、到没到 7 天）。
  /// 它出现时，轻量入口（5 分钟活动）会**一起搬到最上面** ——
  /// 断了一周的人需要的是一条不可能失败的路，不是一整场训练。
  final String? comebackNudge;

  /// **今天的安排**（2026-10-04 加）—— 首页中间那一块。
  ///
  /// 为什么加：这一屏原先只有"标题 + 大按钮"，中间靠一个 `Spacer()` 撑开，
  /// 于是越高的手机中间越空（真机上看就是一大片什么都没有）。
  /// 现在那块空白换成**今天要练的动作清单**：用户点之前就知道自己要练什么，
  /// 而大按钮仍然压在拇指区、仍然 1 跳直开练。
  ///
  /// ⚠️ 它与大按钮开练的是**同一份计划**（由 `main.dart` 持有）——
  /// 显示的是 A、练的是 B，比不显示更糟。
  final List<PlannedExercise> todayPlan;

  /// 「上肢」/「下肢」—— 今天的训练日（null 时不显示那一行）
  final String? todayLabel;

  /// 「换一批」：同一天的分化里换动作。为 null 时不显示那个入口。
  final VoidCallback? onReroll;

  /// **长按「今天的安排」里的一行** → 调整顺序 / 替换 / 删除
  /// （2026-10-09，10.9 清单第 6 条）。为 null 时整块不可编辑（老调用方与测试）。
  ///
  /// 为什么是"长按行"而不是加一个「编辑」按钮：这块卡片上已经有一个「换一批」
  /// 和一个 `›`，再塞第三个入口就变成一排按钮了 —— 而拖动这件事用户本来就习惯长按。
  final VoidCallback? onEditPlan;

  /// 大按钮：**一跳直接进训练屏**（用今天的第一条建议），不再强制过建议卡。
  ///
  /// 为什么：端到端口径下原来的路径是「今日页 → 建议卡 → 大按钮」= 3 次点击才记下
  /// 第一组，而 `PRODUCT.md` §1 的红线是"超过 3 次点击判负"—— 刚好压线。
  /// 现在第一组 2 次（首页 + 大按钮），同一动作的第 2 组起 1 次。
  final VoidCallback onStart;

  final int lastWeekSessions;

  /// 进建议卡（**换一批 / 我的计划 / 我自己选**都在那儿）。
  ///
  /// 建议卡没有被砍掉，只是**不再挡在开练前面**，也不再单独占一行 ——
  /// 2026-10-04：删掉了那一行「看看今天练什么 ›」，改由**「今天的安排」卡整块**承担
  /// （点卡片即进建议卡）。两只手数得清的理由：
  ///   * 卡已经把"今天练什么"回答了（动作 + 建议重量 × 次数），同一件事不留两个入口；
  ///   * 「我自己选 / 我的计划」**只在建议卡里**，所以入口不能真删，只换成更大的触摸目标；
  ///   * 删掉的是**一行文字**、对所有用户一视同仁 —— 不需要"按状态显隐"，
  ///     因此不违反 `product-review-2026-10-01.md` ➖2 的结论（那条否的是"随状态收成一条"）。
  final VoidCallback? onSeePlan;

  /// S13 的可选入口。**为 null 时不显示** —— 已经定过计划的人不需要它，
  /// 而放一个点不动的链接比没有更糟。
  final VoidCallback? onPlanHelp;

  /// 继续上次没结束的训练（2026-10-01 加）。为 null 时不显示。
  ///
  /// 为什么摆在**最上面**：用户此刻的状态是"我刚才在练"，接着练是他唯一该做的事；
  /// 把「开始今天的训练」放在上面会让他又开一次新的（那条路一样能走，只是更绕）。
  final VoidCallback? onResume;

  /// 恢复条上的那行小字（例如「上次练到第 2/3 个动作」）。
  final String? resumeLabel;

  /// 连续打卡天数（2026-10-05，新 VI 的打卡卡）。0 = 还没开始。
  ///
  /// **算出来的，不是存下来的** —— 见 `features/progress/streak.dart` 的文件头：
  /// 存一份 `streak` 列就一定会和训练记录不一致（改历史、导入备份、跨时区都会）。
  final int streak;

  /// 打卡卡下面那行话（「再坚持 4 天解锁…」），由 `streakCopy()` 生成。
  final String? streakCopy;

  /// 最近几次训练（日期 / 动作数 / 容量）。空列表时整块不显示。
  final List<({String workoutId, DateTime day, int exercises, int sets, double volume})> recent;

  /// **重量显示单位**（kg / lb）。容量那几处必须用它 —— 2026-10-08 用户真机反馈
  /// （10.8 清单第 7 条）："最近训练列表的单位跟上面的实际的单位不一致"。
  /// 原因就是 `_recentBlock` 里写死了 `WeightUnit.kg`：上面「今天的安排」按用户单位显示，
  /// 而「最近训练」那三行永远是 kg —— 同一个屏幕上两种单位，看着就像数据错了。
  final WeightUnit unit;

  /// 快速入口：动作库（按动作看历史）。
  final VoidCallback? onOpenLibrary;

  /// 快速入口：记录体重。
  final VoidCallback? onLogWeight;

  /// 快速入口：我的成就（徽章与收集进度）。
  final VoidCallback? onOpenAchievements;

  /// 右上角铃铛（通知中心）。为 null 时不显示。


  /// 「今天不想练？做 5 分钟活动 ›」（2026-10-01 加）。
  ///
  /// 习惯养成的敌人是"全有或全无"：今天没力气做 5 组深蹲，不等于该断掉。
  /// 这条路径给 4 个**按时长的活动**（1 组、30–45 秒），几分钟就能走完，
  /// 也算一次训练。**它不抢主按钮的位置**，只是主按钮下面一行小字。
  final VoidCallback? onLightWorkout;

  @override
  Widget build(BuildContext context) {
    // 2026-10-05：按新 VI 重做成**信息流**（打卡 / 今日训练 / 快速入口 / 最近训练）。
    // 原来那套"标题贴顶 + Spacer + 按钮压底"没法容纳四块内容 ——
    // 要么按钮被挤出拇指区、要么中间再长出一大片空白。
    //
    // ⚠️ **主按钮现在在「今日训练」卡里**（VI 就是这么放的），
    // 位置从"屏幕底部"变成"第二块内容的下沿"。这是**刻意的取舍**：
    // 首屏顶部到按钮约 1.5 屏高的 1/3，单手仍然够得着，而卡片把"练什么"与
    // "开始"合成了一件事。`docs/screens.md` S1 记着这次改动。
    return ListView(
      // 底部多留出浮动底栏的位置（Android 上那一项是 0 —— 底栏在内容下面）
      padding: EdgeInsets.fromLTRB(
          Tokens.s5,
          // 顶部那条给浮动顶栏（iOS 非零、Android 为 0）
          Tokens.s4 + AppTopBar.reservedSpaceFor(context),
          Tokens.s5,
          Tokens.s4 + AppTabBar.reservedSpaceFor(context)),
      children: <Widget>[
        // 「接着练」永远排最上面：此刻用户是"我刚才在练"，接着练是他唯一该做的事
        if (onResume != null) _resumeCard(),
        // 回归激励（第二部分第 9 条）：**断 7 天以上才出现**，出现时把那条
        // 轻量入口一起搬上来（见 `_comebackCard`）。
        if (comebackNudge != null) ...<Widget>[
          const SizedBox(height: Tokens.s4),
          _comebackCard(comebackNudge!),
        ],
        const SizedBox(height: Tokens.s4),
        _streakCard(),
        if (weeklyChallengeLine != null) ...<Widget>[
          const SizedBox(height: Tokens.s3),
          _weeklyChallengeLine(weeklyChallengeLine!),
        ],
        const SizedBox(height: Tokens.s3),
        // 今日训练：**卡里只有清单与「换一批」**
        _TodayPlanCard(
          plan: todayPlan,
          label: todayLabel,
          onReroll: onReroll,
          onOpen: onSeePlan,
          onEdit: onEditPlan,
        ),
        // 主按钮是**卡外**的一颗大胶囊（用户 2026-10-06 的备忘条第 1 条：
        // "开始今天的训练是一个大胶囊 放在训练计划的方框外"）。
        // 2026-10-05 曾把它移进卡里（"练什么"和"开始"合成一件事），真机用下来
        // 反倒是"它像清单的一部分"——`docs/screens.md` 当初就写了"觉得别扭就挪回来"。
        const SizedBox(height: Tokens.s4),
        _startButton(),
        if (onPlanHelp != null) ...<Widget>[
          const SizedBox(height: Tokens.s2),
          Center(
            child: TextButton(
              key: const Key('plan-help'),
              onPressed: onPlanHelp,
              child: const Text('不知道怎么练？帮我定个计划 ›',
                  style: TextStyle(color: Tokens.text2, fontSize: 14)),
            ),
          ),
        ],
        const SizedBox(height: Tokens.s4),
        _quickEntries(),
        // 周报（第二部分第 1 条，2026-10-06）：**只在周一 / 周二**出现，
        // 而且上一周至少练过一次（判据在 `weekly_report.dart` 的 `shouldShowWeeklyReport`，
        // 由外壳算好传进来）。位置在"快速入口"之后、"最近训练"之前：
        // 它是"回顾"，不是"今天要做什么"。
        if (weeklyReport != null && !weeklyReport!.isEmpty) ...<Widget>[
          const SizedBox(height: Tokens.s4),
          _weeklyReportCard(weeklyReport!),
        ],
        // 部位平衡提示（第二部分第 5 条）：**只陈述事实**的一行，
        // 没有任何值得说的就不出现（判据在 `muscle_balance.dart`，纯函数）。
        if (muscleBalance != null) ...<Widget>[
          const SizedBox(height: Tokens.s3),
          _muscleBalanceLine(muscleBalance!),
        ],
        if (recent.isNotEmpty) ...<Widget>[
          const SizedBox(height: Tokens.s5),
          _recentBlock(),
        ],
        const SizedBox(height: Tokens.s4),
        Center(
          child: Text(
            lastWeekSessions > 0 ? '我上周练了 $lastWeekSessions 次' : '还没有训练记录',
            style: const TextStyle(color: Tokens.text3, fontSize: 13),
          ),
        ),
      ],
    );
  }


  /// 打卡卡（新 VI）。**0 天不写"0 天"** —— 那读起来像"你什么都没有"，
  /// 而事实是"今天练一次就开始记了"（文案在 `streakCopy()` 里，有测试钉着）。
  Widget _streakCard() {
    final int? next = nextStreakMilestone(streak);
    final double progress = next == null ? 1 : (streak / next).clamp(0.0, 1.0);
    // 连续天数里若含补签，**必须写出来**（"其中 N 天是补签"）——
    // 不写就等于告诉用户"这些天我天天都练了"。判据与文案都在 streak_protection.dart，
    // 数由外壳用**同一份记录**一起算好传进来（这一屏不碰数据层）。
    final String label = streak > 0
        ? streakLabelWithProtection(streak, protectedInStreak)
        : '打卡';
    return ViCard(
      key: const Key('streak-card'),
      glow: streak > 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.local_fire_department, color: Tokens.accent, size: 18),
              const SizedBox(width: Tokens.s2),
              Expanded(
                child: Text(label,
                    key: const Key('streak-label'),
                    style: const TextStyle(
                        color: Tokens.text, fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (streakCopy != null) ...<Widget>[
            const SizedBox(height: Tokens.s2),
            Text(streakCopy!,
                style: const TextStyle(color: Tokens.text2, fontSize: 12, height: 1.4)),
          ],
          // 补签保护（第二部分第 2 条）：**只在"恰好断了一天 + 本周练过 + 本周没补过"
          // 时才出现**，而且用一句话说清代价与"每周一次"。
          if (protectionOffer != null && onProtectStreak != null) ...<Widget>[
            const SizedBox(height: Tokens.s3),
            Text(protectionOffer!.label,
                key: const Key('protection-offer'),
                style: const TextStyle(color: Tokens.text2, fontSize: 12, height: 1.4)),
            const SizedBox(height: Tokens.s2),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('protect-streak'),
                onPressed: onProtectStreak,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Tokens.text2,
                  side: const BorderSide(color: Tokens.line),
                  padding: const EdgeInsets.symmetric(vertical: Tokens.s3),
                ),
                child: const Text('补签保护这一天', style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
          if (next != null) ...<Widget>[
            const SizedBox(height: Tokens.s3),
            ViProgressBar(value: progress),
          ],
        ],
      ),
    );
  }

  /// **本周挑战那一行**（A3 的首页入口 / 第二部分第 3 条"一处实现两处用"）。
  ///
  /// 刻意只给**一行**（图标 + 文案）：成就页那块卡已经把事情说全了，
  /// 首页再多一块卡只会把"今天的安排"往下挤 —— 而那一块才是这一屏的主角。
  Widget _weeklyChallengeLine(String text) => Row(
        key: const Key('weekly-challenge-line'),
        children: <Widget>[
          const Icon(Icons.flag_outlined, color: Tokens.text3, size: 16),
          const SizedBox(width: Tokens.s2),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: Tokens.text3, fontSize: 12)),
          ),
        ],
      );

  /// **周报卡**（第二部分第 1 条，2026-10-06 拍板）。
  ///
  /// 只在周一 / 周二出现（外壳按 `shouldShowWeeklyReport()` 传进来），内容全是算出来的：
  /// 次数 / 天数 / 组数 / 吨数 + 一句 `headline` + 破纪录与徽章的"额外收获"。
  ///
  /// "做成一张卡"走的是**现有那套分享卡**（抓成 PNG / 存相册 / 剪贴板），
  /// 不联网、不上传 —— 这是第二部分开头那三条红线的第 1 条与第 9 条。
  Widget _weeklyReportCard(WeeklyReport r) {
    final List<String> extras = <String>[
      if (r.prs.isNotEmpty) '刷新 ${r.prs.length} 项纪录',
      if (r.badgesUnlocked > 0) '新徽章 ${r.badgesUnlocked} 枚',
      if (r.distanceM >= 1000) '${(r.distanceM / 1000).toStringAsFixed(1)} 公里',
    ];
    return ViCard(
      key: const Key('weekly-report'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.insights, color: Tokens.accent, size: 18),
              const SizedBox(width: Tokens.s2),
              const Expanded(
                child: Text('上周小结',
                    style: TextStyle(
                        color: Tokens.text, fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              Text(r.rangeLabel,
                  key: const Key('weekly-report-range'),
                  style: const TextStyle(color: Tokens.text3, fontSize: 12)),
            ],
          ),
          const SizedBox(height: Tokens.s3),
          Text(r.headline,
              key: const Key('weekly-report-headline'),
              style: const TextStyle(color: Tokens.text, fontSize: 14, height: 1.4)),
          const SizedBox(height: Tokens.s2),
          Text(r.statsLine,
              key: const Key('weekly-report-stats'),
              style: const TextStyle(color: Tokens.text3, fontSize: 12, height: 1.4)),
          if (extras.isNotEmpty) ...<Widget>[
            const SizedBox(height: Tokens.s2),
            Text(extras.join(' · '),
                style: const TextStyle(color: Tokens.text2, fontSize: 12)),
          ],
          if (onOpenWeeklyReport != null) ...<Widget>[
            const SizedBox(height: Tokens.s3),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('weekly-report-share'),
                onPressed: onOpenWeeklyReport,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Tokens.text2,
                  side: const BorderSide(color: Tokens.line),
                  padding: const EdgeInsets.symmetric(vertical: Tokens.s3),
                ),
                child: const Text('做成一张卡', style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// **部位平衡那一行**（第二部分第 5 条）。
  ///
  /// 刻意**做成一行小字**而不是一张卡：这是"看一眼就知道"的信息，
  /// 给它一张卡就等于把它抬成和"今天的安排"同级的事 —— 而它不配。
  /// 文案由 `muscleBalanceHint()` 给（纯函数，含"没练过的部位"那条判据）。
  Widget _muscleBalanceLine(String text) => Row(
        key: const Key('muscle-balance'),
        children: <Widget>[
          const Icon(Icons.balance, color: Tokens.text3, size: 16),
          const SizedBox(width: Tokens.s2),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: Tokens.text3, fontSize: 12)),
          ),
        ],
      );

  /// 快速入口四宫格（新 VI）。
  ///
  /// ⚠️ **与 VI 有一处刻意的不同**：VI 给的是「自由训练 / 动作库 / 训练计划 / 成就」，
  /// 而"训练计划"与"成就"在我们这儿分别是**一级 Tab** 与**还没做的功能**。
  /// 所以这里放的是四个"不是 Tab、但你会想直接点进去"的动作，避免同一件事两个入口。
  Widget _quickEntries() {
    final List<({IconData icon, String label, VoidCallback? onTap, Key key})> items =
        <({IconData icon, String label, VoidCallback? onTap, Key key})>[
      // ⚠️ 这个 Key 原来是屏幕底部那条「今天不想练？做 5 分钟活动 ›」的。
      // 2026-10-05 改成信息流时删掉了那条 —— 快速入口里已经有同一个动作，
      // 同一件事留两个入口正是这一轮一直在清的那种毛病。
      (icon: Icons.timer_outlined, label: '5 分钟活动', onTap: onLightWorkout, key: const Key('light-workout')),
      (icon: Icons.menu_book_outlined, label: '动作库', onTap: onOpenLibrary, key: const Key('quick-library')),
      (icon: Icons.monitor_weight_outlined, label: '记录体重', onTap: onLogWeight, key: const Key('quick-weight')),
      // 2026-10-05：这一格原来是「我的计划」—— 但计划已经是一级 Tab，
      // 同一件事留两个入口正是这一轮在清的毛病，所以换成「成就」（新功能，没有 Tab）。
      (icon: Icons.emoji_events_outlined, label: '成就', onTap: onOpenAchievements, key: const Key('quick-achievements')),
    ];
    return Row(
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: Tokens.s3),
          Expanded(
            child: GestureDetector(
              key: items[i].key,
              behavior: HitTestBehavior.opaque,
              onTap: items[i].onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: Tokens.s3),
                decoration: BoxDecoration(
                  color: Tokens.surface,
                  borderRadius: BorderRadius.circular(Tokens.rCard),
                  border: Border.all(color: Tokens.line),
                ),
                child: Column(
                  children: <Widget>[
                    Icon(items[i].icon, color: Tokens.accent, size: 20),
                    const SizedBox(height: Tokens.s2),
                    Text(items[i].label,
                        style: const TextStyle(color: Tokens.text2, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 最近训练（新 VI）。**最多三条** —— 首页不是历史页，看全量去「数据」。
  Widget _recentBlock() {
    String when(DateTime d) {
      final DateTime now = debugToday ?? DateTime.now();
      final DateTime today0 = DateTime(now.year, now.month, now.day);
      final DateTime d0 = DateTime(d.year, d.month, d.day);
      final int diff = today0.difference(d0).inDays;
      if (diff <= 0) return '今天';
      if (diff == 1) return '昨天';
      return '${d.month}/${d.day}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('最近训练',
            style: TextStyle(color: Tokens.text, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: Tokens.s2),
        for (final ({String workoutId, DateTime day, int exercises, int sets, double volume}) r in recent)
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.s2),
            child: ViCard(
              key: Key('recent-${r.workoutId}'),
              padding: const EdgeInsets.symmetric(
                  horizontal: Tokens.s4, vertical: Tokens.s3),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${r.exercises} 个动作 · ${r.sets} 组',
                      style: const TextStyle(color: Tokens.text, fontSize: 14),
                    ),
                  ),
                  Text(
                    '${formatVolume(r.volume, unit)} · ${when(r.day)}',
                    style: const TextStyle(color: Tokens.text3, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _resumeCard() => GestureDetector(
        key: const Key('resume-session'),
        onTap: onResume,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: Tokens.s4),
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s4, vertical: Tokens.s3),
          decoration: BoxDecoration(
            color: Tokens.surface,
            borderRadius: BorderRadius.circular(Tokens.rCard),
            border: Border.all(color: Tokens.accent),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.play_circle_outline, color: Tokens.accent, size: 20),
              const SizedBox(width: Tokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('上次的训练还没结束',
                        style: TextStyle(
                            color: Tokens.text, fontSize: 14, fontWeight: FontWeight.w600)),
                    if (resumeLabel != null)
                      Text(resumeLabel!,
                          style: const TextStyle(color: Tokens.text3, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Tokens.text3, size: 20),
            ],
          ),
        ),
      );

  /// 主按钮。**一跳直接进训练屏**（见构造函数里那段关于"3 次点击"的说明）。
  Widget _startButton() => SizedBox(
        height: Tokens.hPrimary,
        width: double.infinity,
        child: FilledButton(
          key: const Key('start-workout'),
          style: FilledButton.styleFrom(
            backgroundColor: Tokens.accent,
            foregroundColor: Tokens.accentInk,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Tokens.rPill),
            ),
          ),
          onPressed: onStart,
          child: const Text(
            '开始今天的训练',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
      );
}

/// 「今天的安排」卡片（2026-10-04）。
///
/// **它替掉了原来那个 `Spacer()`**：同样是屏幕中间那块地方，
/// 与其空着（真机上越高的手机空得越多），不如摆用户此刻最想知道的东西 ——
/// 今天练什么、每个动作做多重。
///
/// 三条纪律：
///   * **点它不开练**（开练永远是大按钮的事）：整块点进建议卡，卡内只有「换一批」是另一个目标；
///   * **与大按钮同一份计划**：内容是 `main.dart` 那份 `_todayPlan`，不是这里现算的；
///   * 动作值用的是引擎已经算好的 `loadLabel`（"62.5 kg × 8"），不是动作库默认值。
class _TodayPlanCard extends StatelessWidget {
  const _TodayPlanCard(
      {required this.plan,
      this.label,
      this.onReroll,
      this.onOpen,
      this.onEdit});

  final List<PlannedExercise> plan;
  final String? label;
  final VoidCallback? onReroll;

  /// 长按某一行 → 调整安排（排序 / 替换 / 删除）。为 null 时长按无效。
  final VoidCallback? onEdit;

  /// 点整块卡片 → 进建议卡。为 null 时卡片**不可点**（老调用方 / 测试），
  /// 也不摆那个 `›` —— 摆一个点不动的箭头比没有更糟。
  final VoidCallback? onOpen;

  /// 卡片里最多列几个 —— 再多会把主按钮挤出屏幕（那正是这个改动要避免的）
  static const int _maxRows = 6;

  @override
  Widget build(BuildContext context) {
    final List<PlannedExercise> head = plan.take(_maxRows).toList();
    final Widget card = Container(
      key: const Key('today-plan'),
      padding: const EdgeInsets.symmetric(
          horizontal: Tokens.s4, vertical: Tokens.s3),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
        border: Border.all(color: Tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label == null ? '今天的安排' : '今天练 $label',
                  style: const TextStyle(
                      color: Tokens.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
              ),
              if (onReroll != null)
                GestureDetector(
                  key: const Key('today-reroll'),
                  onTap: onReroll,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: Tokens.s2, vertical: Tokens.s1),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.refresh, size: 15, color: Tokens.text3),
                        SizedBox(width: 4),
                        Text('换一批',
                            style: TextStyle(color: Tokens.text3, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              // 「整块可点」必须**看得出来** —— 不然它就是一个装饰。
              if (onOpen != null)
                const Icon(Icons.chevron_right, size: 18, color: Tokens.text3),
            ],
          ),
          const SizedBox(height: Tokens.s2),
          // 计划为空（算失败 / 动作库还没导入）时的样子：说清发生了什么，
          // 并把"怎么练"指出去。**不显示一个空框**。
          if (head.isEmpty) ...<Widget>[
            const Text('今天还没有排动作',
                style: TextStyle(color: Tokens.text2, fontSize: 14)),
            // 不可点时**不写"点这里"** —— 一句点不动的话比没有更糟
            if (onOpen != null) ...<Widget>[
              const SizedBox(height: 3),
              const Text('点这里看看怎么练 ›',
                  style: TextStyle(color: Tokens.text3, fontSize: 13)),
            ],
          ],
          for (int i = 0; i < head.length; i++)
            GestureDetector(
              // 长按整行 → 调整安排（2026-10-09，10.9 清单第 6 条）。
              // ⚠️ 外层整块还有一个 `onTap`（进建议卡）：`onLongPress` 与它不冲突，
              // 但**不能**用 `onLongPressStart` 之类去抢手势，那会把手感弄坏。
              onLongPress: onEdit,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                // 每行一个 key：测试要按**结构**数行，而不是猜"文字里有没有 kg"
                // （自重动作念「自重 × 8」，按 ' kg ' 数会漏掉它们）
                key: Key('today-plan-row-$i'),
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        head[i].exercise.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Tokens.text2, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: Tokens.s2),
                    Text(head[i].loadLabel,
                        style: const TextStyle(color: Tokens.text3, fontSize: 13)),
                  ],
                ),
              ),
            ),
          if (plan.length > head.length)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('…还有 ${plan.length - head.length} 个',
                  style: const TextStyle(color: Tokens.text3, fontSize: 12)),
            ),
          // 「能长按」这件事必须被看见 —— 一个只有长按才知道的入口等于没有
          // （10.9 清单第 6 条。文案刻意用"长按调整"，与弹层里那句"长按一行可以拖动排序"同一口径）
          if (onEdit != null && head.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: Text('长按调整顺序 / 换动作 / 删掉',
                  key: Key('today-plan-hint'),
                  style: TextStyle(color: Tokens.text3, fontSize: 11.5)),
            ),
        ],
      ),
    );
    if (onOpen == null) return card;
    return GestureDetector(
      key: const Key('open-plan'),
      onTap: onOpen,
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }
}
