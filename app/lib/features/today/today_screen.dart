/// 练了么 ·「练」Tab 空态（S1）
///
/// 对应 `docs/screens.md` S1 与 `prototype/index.html` 第 1 屏。
///
/// 外壳（`main.dart` 的 `HomeShell`）负责 Scaffold、安全区与底部 Tab 栏；
/// 这一屏只做内容 —— Tab 栏必须由外壳持有状态才可能真的切换，
/// 假的可点按元件比没有更糟。
library;

import '../../core/icon_spec.dart';
import 'package:flutter/material.dart';

import '../../core/empty_state.dart';
import '../../core/theme.dart';
import '../../core/accent_button.dart';
import '../../core/app_tab_bar.dart';
import '../../core/units.dart';
import '../../core/vi_cards.dart';
import '../../domain/models.dart' show Suggestion, isTimeTrack;
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
    this.onOpenPlan,
    this.onLightWorkout,
    this.onResume,
    this.resumeLabel,
    this.todayPlan = const <PlannedExercise>[],
    this.todayLabel,
    this.onReroll,
    this.onEditPlan,
    this.streak = 0,
    this.streakCopy,
    this.recent = const <({
      String workoutId,
      DateTime day,
      int exercises,
      int sets,
      double volume
    })>[],
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
    this.weeklyFact,
    this.debugToday,
    this.onProtectStreak,
    this.weekTrainedWeekdays = const <int>{},
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
                style: const TextStyle(
                    color: Tokens.text,
                    fontSize: Tokens.fsSub,
                    height: Tokens.lhSnug)),
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
                  child: const Text('做 5 分钟活动',
                      style: TextStyle(fontSize: Tokens.fsCap)),
                ),
              ),
            ],
          ],
        ),
      );

  /// **部位平衡那一行**（第二部分第 5 条）。null = 不显示。
  /// 判据与文案都在 `muscle_balance.dart`（纯函数）；外壳把动作表查好传进来。
  final String? muscleBalance;

  /// **本周已经练了几次**（2026-10-10 改成"事实"）。
  ///
  /// ⚠️ 这一格原来是「本周挑战」——一整行带目标的挑战文案（"本周练 3 次 · 1 / 3 次 · 还剩 5 天"），
  /// 与上面那张打卡卡一起，让首页同时摆着**两套"坚持"的进度**。
  /// 现在它是**事实**（`本周已练 3 次`），与连续天数拼成同一行 ——
  /// 判据在 `docs/plan-ux-2026-10-10.md` §五-B：全 app **只有一条进度条**（「我」里的等级），
  /// 其余都是数字本身。挑战本身没消失：完整的那块（怎么做 / 进度 / 还剩几天）在成就页。
  ///
  /// null = 不显示（由外壳按纯函数决定）。
  final String? weeklyFact;

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

  /// 本周已练的星期几（1=周一 … 7=周日）——「本周节奏」7 个点用它。
  final Set<int> weekTrainedWeekdays;

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
  final List<
      ({
        String workoutId,
        DateTime day,
        int exercises,
        int sets,
        double volume
      })> recent;

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

  /// 进「计划」页（本周 / 模板库 / 历史）。为 null 时不显示那个入口。
  ///
  /// ⚠️ 2026-10-10：这一格原来是**底栏的一格**（回 3 个 tab 之后撤了），
  /// 所以入口搬到首页这张卡的右上角（`换一批 · 计划 ›`）。
  final VoidCallback? onOpenPlan;

  /// 「今天不想练？做 5 分钟活动 ›」（2026-10-01 加）。
  ///
  /// 习惯养成的敌人是"全有或全无"：今天没力气做 5 组深蹲，不等于该断掉。
  /// 这条路径给 4 个**按时长的活动**（1 组、30–45 秒），几分钟就能走完，
  /// 也算一次训练。**它不抢主按钮的位置**，只是主按钮下面一行小字。
  final VoidCallback? onLightWorkout;

  @override
  Widget build(BuildContext context) {
    final DateTime now = debugToday ?? DateTime.now();
    final bool tall = MediaQuery.sizeOf(context).height >= 900;
    return ListView(
      padding: EdgeInsets.fromLTRB(
          Tokens.s6,
          Tokens.s6 + (tall ? 24 : 0),
          Tokens.s6,
          Tokens.s8 + AppTabBar.reservedSpaceFor(context) + (tall ? 70 : 0)),
      children: <Widget>[
        if (onResume != null) _resumeCard(),
        if (comebackNudge != null) ...<Widget>[
          const SizedBox(height: Tokens.s4),
          _comebackCard(comebackNudge!),
        ],
        const SizedBox(height: Tokens.s7),
        // ⚠️ v2.0.1：这里原来又画了一遍 34pt「今天 + 日期」—— 外壳顶栏
        // （`AppTopBar` 的 title/subtitle）已经是同一行，两遍叠在真机上就是两个「今天」。
        // 页面不再写自己的名字，标题只由顶栏那一处提供。
        _TodayPlanCard(
          plan: todayPlan,
          label: todayLabel,
          onEdit: onEditPlan,
          onOpen: onSeePlan,
          onStart: onStart,
        ),
        const SizedBox(height: Tokens.s7),
        _factLine(now),
      ],
    );
  }

  /// 首页唯一的辅助行（v2.3.0）：最近一次 + 本周节奏合并成一行。
  Widget _factLine(DateTime now) {
    final int trained = weekTrainedWeekdays.length;
    final String recentPart =
        recent.isEmpty ? '还没有训练记录' : '最近 ${formatDateAxis(recent.first.day)}';
    return GestureDetector(
      key: const Key('home-fact-line'),
      onTap: onOpenLibrary,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Tokens.s3),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Tokens.hair)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text('$recentPart · 本周 $trained 天',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Tokens.text2, fontSize: Tokens.fsSub)),
            ),
            const Icon(Icons.chevron_right,
                size: IconSpec.s, color: Tokens.text3),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _recentLine(
      ({
        String workoutId,
        DateTime day,
        int exercises,
        int sets,
        double volume
      }) r) {
    final String when = formatDateAxis(r.day);
    final String volume = formatVolume(r.volume, unit);
    return GestureDetector(
      key: const Key('home-recent'),
      onTap: onOpenLibrary,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: <Widget>[
          const Text('最近一次',
              style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap)),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Text('$when · ${r.exercises} 个动作 · $volume',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Tokens.text2, fontSize: Tokens.fsCap)),
          ),
          if (onOpenLibrary != null)
            const Icon(Icons.chevron_right,
                size: IconSpec.s, color: Tokens.text3),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _weekRhythm(DateTime now) {
    final int trained = weekTrainedWeekdays.length;
    return Container(
      key: const Key('home-week'),
      padding: const EdgeInsets.only(top: Tokens.s3),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Tokens.hair)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          children: <Widget>[
            const Text('本周节奏',
                style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap)),
            const SizedBox(width: Tokens.s3),
            for (int d = 1; d <= 7; d += 1)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: Tokens.s2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: weekTrainedWeekdays.contains(d)
                      ? Tokens.accentText
                      : Tokens.line,
                ),
              ),
            const SizedBox(width: Tokens.s3),
            Text('已练 $trained 天',
                key: const Key('home-week-trained'),
                style: const TextStyle(
                    color: Tokens.text2, fontSize: Tokens.fsCap)),
          ],
        ),
      ),
    );
  }

  /// **一行事实**：连续多少天 + 这周练了几次（2026-10-10）。
  ///
  /// 用户 10.10 的设计评审之后，这一屏从"两块讲坚持的东西"（一张带进度条、带补签按钮的
  /// **打卡卡** + 一行**本周挑战**）收成**一行**。为什么这不是"把激励删了"：
  ///   * **连续天数与本周次数是事实** —— 一个数字，不带进度条。全 app 唯一的进度条
  ///     是「我」里那条等级（`docs/plan-ux-2026-10-10.md` §五-B）；
  ///   * 挑战的完整那块（怎么做 / 进度 / 还剩几天）在成就页；
  ///   * **补签保护仍然留在这里**（`protection-offer` / `protect-streak`）——
  ///     它只在"昨天恰好断了 + 这周练过 + 这周还没补过"时出现，是要用户**动手**的一件事，
  ///     不是一条进度；藏起来等于把功能删了。
  // ignore: unused_element
  Widget _streakFactLine() {
    // ⚠️ `streakLabelWithProtection` 里那句"其中 N 天是补签"**必须留着** ——
    // 只写"连续 12 天"而其中 2 天是补的，就是一句假话（有测试钉着）。
    final String streakText = streak > 0
        ? streakLabelWithProtection(streak, protectedInStreak)
        : (streakCopy ?? '今天练一次，就开始记连续天数');
    final String text =
        weeklyFact == null ? streakText : '$streakText · $weeklyFact';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          key: const Key('streak-line'),
          children: <Widget>[
            Icon(
              streak > 0
                  ? Icons.local_fire_department
                  : Icons.local_fire_department_outlined,
              color: streak > 0 ? Tokens.accent : Tokens.text3,
              size: IconSpec.s,
            ),
            const SizedBox(width: Tokens.s2),
            Expanded(
              child: Text(
                text,
                key: const Key('streak-label'),
                style: TextStyle(
                  color: streak > 0 ? Tokens.text2 : Tokens.text3,
                  fontSize: Tokens.fsCap,
                  height: Tokens.lhSnug,
                ),
              ),
            ),
          ],
        ),
        if (protectionOffer != null && onProtectStreak != null) ...<Widget>[
          const SizedBox(height: Tokens.s2),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(protectionOffer!.label,
                    key: const Key('protection-offer'),
                    style: const TextStyle(
                        color: Tokens.text2,
                        fontSize: Tokens.fsMicro,
                        height: Tokens.lhSnug)),
              ),
              const SizedBox(width: Tokens.s2),
              TextButton(
                key: const Key('protect-streak'),
                onPressed: onProtectStreak,
                style: TextButton.styleFrom(
                  foregroundColor: Tokens.accent,
                  padding: const EdgeInsets.symmetric(horizontal: Tokens.s2),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('补签这一天',
                    style: TextStyle(fontSize: Tokens.fsCap)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// **周报卡**（第二部分第 1 条，2026-10-06 拍板）。
  ///
  /// 只在周一 / 周二出现（外壳按 `shouldShowWeeklyReport()` 传进来），内容全是算出来的：
  /// 次数 / 天数 / 组数 / 吨数 + 一句 `headline` + 破纪录与徽章的"额外收获"。
  ///
  /// "做成一张卡"走的是**现有那套分享卡**（抓成 PNG / 存相册 / 剪贴板），
  /// 不联网、不上传 —— 这是第二部分开头那三条红线的第 1 条与第 9 条。
  // ignore: unused_element
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
              const Icon(Icons.insights,
                  color: Tokens.accent, size: IconSpec.m),
              const SizedBox(width: Tokens.s2),
              const Expanded(
                child: Text('上周小结',
                    style: TextStyle(
                        color: Tokens.text,
                        fontSize: Tokens.fsSub,
                        fontWeight: Tokens.fwStrong)),
              ),
              Text(r.rangeLabel,
                  key: const Key('weekly-report-range'),
                  style: const TextStyle(
                      color: Tokens.text3, fontSize: Tokens.fsMicro)),
            ],
          ),
          const SizedBox(height: Tokens.s3),
          Text(r.headline,
              key: const Key('weekly-report-headline'),
              style: const TextStyle(
                  color: Tokens.text,
                  fontSize: Tokens.fsSub,
                  height: Tokens.lhSnug)),
          const SizedBox(height: Tokens.s2),
          Text(r.statsLine,
              key: const Key('weekly-report-stats'),
              style: const TextStyle(
                  color: Tokens.text3,
                  fontSize: Tokens.fsMicro,
                  height: Tokens.lhSnug)),
          if (extras.isNotEmpty) ...<Widget>[
            const SizedBox(height: Tokens.s2),
            Text(extras.join(' · '),
                style: const TextStyle(
                    color: Tokens.text2, fontSize: Tokens.fsMicro)),
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
                child: const Text('做成一张卡',
                    style: TextStyle(fontSize: Tokens.fsCap)),
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
  // ignore: unused_element
  Widget _muscleBalanceLine(String text) => Row(
        key: const Key('muscle-balance'),
        children: <Widget>[
          const Icon(Icons.balance, color: Tokens.text3, size: IconSpec.s),
          const SizedBox(width: Tokens.s2),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: Tokens.text3, fontSize: Tokens.fsMicro)),
          ),
        ],
      );

  /// **三个快捷入口**（2026-10-10 从四个大方块改过来的）。
  ///
  /// 两处改动：
  ///   1. **去掉「成就」那一格** —— 它搬去了「我」（那是"我拿到了什么"，
  ///      与"现在要做什么"不是一类；首页不该有它的位置）；
  ///   2. 从四个各自为政的方块收成**一只卡里的三格**（图标 + 字 + 细线分隔）：
  ///      上一版缩成一行小灰字，用户反馈「太不显眼、完全没存在感」，所以保留存在感，
  ///      但不再是四个等权重的方块（`docs/plan-ux-2026-10-10.md` P1-5 记着这次返工）。
  // ignore: unused_element
  Widget _quickEntries() {
    final List<({IconData icon, String label, VoidCallback? onTap, Key key})>
        items = <({IconData icon, String label, VoidCallback? onTap, Key key})>[
      (
        icon: Icons.menu_book_outlined,
        label: '动作库',
        onTap: onOpenLibrary,
        key: const Key('quick-library')
      ),
      (
        icon: Icons.monitor_weight_outlined,
        label: '记录体重',
        onTap: onLogWeight,
        key: const Key('quick-weight')
      ),
      // ⚠️ 这个 Key 原来是屏幕底部那条「今天不想练？做 5 分钟活动 ›」的
      // （2026-10-05 改成信息流时删掉了那条，快速入口里已经有同一个动作）。
      (
        icon: Icons.timer_outlined,
        label: '5 分钟活动',
        onTap: onLightWorkout,
        key: const Key('light-workout')
      ),
    ];
    // ⚠️ 高度**不写死**：写死 78 在 1.5× 系统字号下会溢出 15px
    // （today_plan_test 那条大字号用例当场抓到的）。用 `IntrinsicHeight` +
    // 格子自己的上下留白撑开，同时让中间那两道细线长满整行。
    return IntrinsicHeight(
      child: Container(
        decoration: BoxDecoration(
          color: Tokens.surface,
          borderRadius: BorderRadius.circular(Tokens.rCard),
          border: Border.all(color: Tokens.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < items.length; i++) ...<Widget>[
              if (i > 0) Container(width: 1, color: Tokens.line),
              Expanded(
                child: GestureDetector(
                  key: items[i].key,
                  behavior: HitTestBehavior.opaque,
                  onTap: items[i].onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(items[i].icon,
                            color: Tokens.text2, size: IconSpec.l),
                        const SizedBox(height: Tokens.s2),
                        Text(items[i].label,
                            style: const TextStyle(
                                color: Tokens.text, fontSize: Tokens.fsSub)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 最近训练（新 VI）。**最多三条** —— 首页不是历史页，看全量去「数据」。
  // ignore: unused_element
  Widget _recentBlock() {
    String when(DateTime d) {
      final DateTime now = debugToday ?? DateTime.now();
      final DateTime today0 = DateTime(now.year, now.month, now.day);
      final DateTime d0 = DateTime(d.year, d.month, d.day);
      final int diff = today0.difference(d0).inDays;
      if (diff <= 0) return '今天';
      if (diff == 1) return '昨天';
      return formatDateAxis(d);
    }

    // T3-2：一次都没练过时，"最近训练"下面原来**什么都没有** ——
    // 用户看到的是一片空黑。现在它是一处空态：说清事实 + **给一个下一步**
    // （去动作库挑一个，而不是"点下面那颗大按钮"——大按钮已经在他眼前了，再说一遍是废话）。
    if (recent.isEmpty) {
      if (onOpenLibrary == null) return const SizedBox.shrink();
      return EmptyState(
        key: const Key('empty-today'),
        art: EmptyArt.dashedRing,
        title: '还没有训练记录。',
        body: '练完第一次，这里会记下最近几次练了什么。',
        action: '去动作库挑一个',
        onAction: onOpenLibrary!,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('最近训练',
            style: TextStyle(
                color: Tokens.text,
                fontSize: Tokens.fsSub,
                fontWeight: Tokens.fwStrong)),
        const SizedBox(height: Tokens.s2),
        for (final ({
          String workoutId,
          DateTime day,
          int exercises,
          int sets,
          double volume
        }) r in recent)
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
                      style: const TextStyle(
                          color: Tokens.text, fontSize: Tokens.fsSub),
                    ),
                  ),
                  Text(
                    '${formatVolume(r.volume, unit)} · ${when(r.day)}',
                    style: const TextStyle(
                        color: Tokens.text3, fontSize: Tokens.fsMicro),
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
          padding: const EdgeInsets.symmetric(
              horizontal: Tokens.s4, vertical: Tokens.s3),
          decoration: BoxDecoration(
            color: Tokens.surface,
            borderRadius: BorderRadius.circular(Tokens.rCard),
            border: Border.all(color: Tokens.accent),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.play_circle_outline,
                  color: Tokens.accent, size: IconSpec.m),
              const SizedBox(width: Tokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('上次的训练还没结束',
                        style: TextStyle(
                            color: Tokens.text,
                            fontSize: Tokens.fsSub,
                            fontWeight: Tokens.fwStrong)),
                    if (resumeLabel != null)
                      Text(resumeLabel!,
                          style: const TextStyle(
                              color: Tokens.text3, fontSize: Tokens.fsMicro)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: Tokens.text3, size: IconSpec.m),
            ],
          ),
        ),
      );

  /// 主按钮。**一跳直接进训练屏**（见构造函数里那段关于"3 次点击"的说明）。
  // ignore: unused_element
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
            style: TextStyle(
                fontSize: Tokens.fsHeadline, fontWeight: Tokens.fwBold),
          ),
        ),
      );
}

/// **今日训练卡**（v2.0.0）：表格化 + 显式「编辑」+ 卡内一体的大按钮。
///
/// 只回答一次"今天练什么"：表头 `# / 动作 / 组×次 / 重量`、最多 4 行、
/// 右上「编辑」（换动作/排序/删除/从模板载入/重新安排都进编辑页）。
/// 主按钮在卡内底部（88pt），点击直接开练 —— 1 次点击 = 1 组不变。
class _TodayPlanCard extends StatelessWidget {
  const _TodayPlanCard({
    required this.plan,
    this.label,
    this.onEdit,
    this.onOpen,
    this.onStart,
  });

  final List<PlannedExercise> plan;
  final String? label;
  final VoidCallback? onEdit;
  final VoidCallback? onOpen;
  final VoidCallback? onStart;

  static const int _maxRows = 3;

  @override
  Widget build(BuildContext context) {
    final List<PlannedExercise> head = plan.take(_maxRows).toList();
    final Widget card = Container(
      key: const Key('today-plan'),
      padding: const EdgeInsets.all(Tokens.s5),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
        border: Border.all(color: Tokens.line),
        boxShadow: <BoxShadow>[...Tokens.shadowCard, ...Tokens.edgeHighlight],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('今日训练',
                        style: TextStyle(
                            color: Tokens.text3, fontSize: Tokens.fsMicro)),
                    const SizedBox(height: Tokens.s1),
                    Text(
                      label ?? '未安排',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Tokens.text,
                          fontSize: Tokens.fsNum,
                          fontWeight: Tokens.fwBold,
                          letterSpacing: Tokens.lsSnug),
                    ),
                    const SizedBox(height: Tokens.s1),
                    Text(_planSummary(plan),
                        key: const Key('home-plan-summary'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Tokens.text3, fontSize: Tokens.fsMicro)),
                  ],
                ),
              ),
              if (onEdit != null)
                GestureDetector(
                  key: const Key('home-plan-edit'),
                  onTap: onEdit,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: Tokens.s2, vertical: Tokens.s1),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.edit_outlined,
                            size: IconSpec.s, color: Tokens.text2),
                        SizedBox(width: 4),
                        Text('编辑',
                            style: TextStyle(
                                color: Tokens.text2, fontSize: Tokens.fsCap)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Tokens.s3),
          if (head.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Tokens.s3),
              child: Text('今天还没有安排',
                  style:
                      TextStyle(color: Tokens.text2, fontSize: Tokens.fsSub)),
            )
          else ...<Widget>[
            const Padding(
              padding: EdgeInsets.only(bottom: Tokens.s1),
              child: Row(
                children: <Widget>[
                  SizedBox(
                      width: 20,
                      child: Text('#',
                          style: TextStyle(
                              color: Tokens.text3, fontSize: Tokens.fsMicro))),
                  Expanded(
                      child: Text('动作',
                          style: TextStyle(
                              color: Tokens.text3, fontSize: Tokens.fsMicro))),
                  SizedBox(
                      width: 92,
                      child: Text('组×次',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: Tokens.text3, fontSize: Tokens.fsMicro))),
                  SizedBox(
                      width: 72,
                      child: Text('重量',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: Tokens.text3, fontSize: Tokens.fsMicro))),
                ],
              ),
            ),
            for (int i = 0; i < head.length; i += 1)
              GestureDetector(
                onLongPress: onEdit,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  key: Key('today-plan-row-$i'),
                  padding: const EdgeInsets.symmetric(vertical: Tokens.s3),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Tokens.hair)),
                  ),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                          width: 20,
                          child: Text('${i + 1}',
                              style: const TextStyle(
                                  color: Tokens.text3,
                                  fontSize: Tokens.fsCap))),
                      Expanded(
                        child: Text(head[i].exercise.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Tokens.text, fontSize: Tokens.fsBody)),
                      ),
                      SizedBox(
                        width: 92,
                        // ⚠️ v2.2.0 真机：`4×8–10次` 在 fsSub 15 下比原 64pt 列宽，
                        // 会折成两行（`4×8–10` / `次`）。加宽到 92 并用 FittedBox：
                        // 正常字号不缩，2.0× 字号下等比缩小而不是折行。
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(_setsReps(head[i]),
                              maxLines: 1,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  color: Tokens.text2, fontSize: Tokens.fsSub)),
                        ),
                      ),
                      SizedBox(
                        width: 72,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(_weight(head[i]),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  color: Tokens.text2,
                                  fontSize: Tokens.fsSub,
                                  fontFeatures: Tokens.tabular)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // v2.3.0 结构减负：**不渲染「…还有 N 个动作」** —— 卡头副标题已经写了
            // 「N 个动作 · M 组 · 约 X 分钟」，第 4+ 个动作从「编辑」看；多一行尾巴
            // 反而把卡片撑高、把主按钮往下推（真机验收抓到的漏改）。
          ],
          const SizedBox(height: Tokens.s4),
          AccentButton(
            key: const Key('start-workout'),
            label: '开始训练',
            labelSize: Tokens.fsBody,
            height: Tokens.hCardCta,
            onPressed: onStart,
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

  static String _planSummary(List<PlannedExercise> plan) {
    if (plan.isEmpty) return '';
    final int sets =
        plan.fold<int>(0, (int a, PlannedExercise p) => a + p.plan.targetSets);
    final int minutes = (sets * 2.5).round().clamp(5, 120);
    return '${plan.length} 个动作 · $sets 组 · 约 $minutes 分钟';
  }

  static String _setsReps(PlannedExercise p) {
    final bool time = isTimeTrack(p.exercise.trackType);
    final String unit = time ? '秒' : '次';
    final String reps = p.plan.targetRepsLow == p.plan.targetRepsHigh
        ? '${p.plan.targetRepsLow}$unit'
        : '${p.plan.targetRepsLow}–${p.plan.targetRepsHigh}$unit';
    return '${p.plan.targetSets}×$reps';
  }

  static String _weight(PlannedExercise p) {
    final Suggestion? s = p.suggestion;
    if (s == null)
      return p.plan.targetWeightKg == null
          ? '自重'
          : formatWeight(p.plan.targetWeightKg, p.unit);
    if (s.isBodyweight) return '自重';
    return formatWeight(s.weightKg, p.unit);
  }
}
