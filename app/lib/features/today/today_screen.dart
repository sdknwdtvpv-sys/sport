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
import '../../core/units.dart';
import '../../core/vi_cards.dart';
import '../progress/streak.dart';
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
    this.streak = 0,
    this.streakCopy,
    this.recent = const <({String workoutId, DateTime day, int exercises, int sets, double volume})>[],
    this.onOpenLibrary,
    this.onLogWeight,
    this.onOpenAchievements,
    this.onOpenNotifications,
    this.unreadNotifications = 0,
  });

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

  /// 快速入口：动作库（按动作看历史）。
  final VoidCallback? onOpenLibrary;

  /// 快速入口：记录体重。
  final VoidCallback? onLogWeight;

  /// 快速入口：我的成就（徽章与收集进度）。
  final VoidCallback? onOpenAchievements;

  /// 右上角铃铛（通知中心）。为 null 时不显示。
  final VoidCallback? onOpenNotifications;

  /// 未读消息数（0 = 不显示那个点）。
  final int unreadNotifications;

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
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s4),
      children: <Widget>[
        // 「接着练」永远排最上面：此刻用户是"我刚才在练"，接着练是他唯一该做的事
        if (onResume != null) _resumeCard(),
        _greeting(),
        const SizedBox(height: Tokens.s4),
        _streakCard(),
        const SizedBox(height: Tokens.s3),
        // 今日训练：清单 + 「换一批」+ **主按钮**（都在卡里）
        _TodayPlanCard(
          plan: todayPlan,
          label: todayLabel,
          onReroll: onReroll,
          onOpen: onSeePlan,
          footer: _startButton(),
        ),
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

  /// 顶部那两行：今天 + 日期。**没有账号，所以不写"下午好，某某"**——
  /// VI 里那行问候带着用户名，我们没有用户体系，印一句假名字比不印更糟。
  Widget _greeting() {
    const List<String> weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
    final DateTime now = DateTime.now();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        const Text(
          '今天',
          style: TextStyle(
            color: Tokens.text,
            fontSize: 34,
            height: 1.05,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(width: Tokens.s3),
        // ⚠️ `Flexible` + 省略号（v1.53）：系统字号调大时（1.5×），
        // "今天"(34pt) 与这行日期会一起变宽，把右上角的铃铛挤出屏幕 ——
        // 而铃铛是通知中心的唯一入口，挤没了等于那个功能消失。
        // 宁可日期结尾省略，也不能挤掉入口（测试在 `today_plan_test` 的大字号那条）。
        Flexible(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${now.month} 月 ${now.day} 日 · 周${weekdays[now.weekday - 1]}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Tokens.text3, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(width: Tokens.s2),
        // 铃铛（2026-10-05，新 VI 的首页右上角）。有未读才带那个点 ——
        // 永远亮着的红点等于没有点。
        if (onOpenNotifications != null)
          GestureDetector(
            key: const Key('open-notifications'),
            behavior: HitTestBehavior.opaque,
            onTap: onOpenNotifications,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  const Icon(Icons.notifications_none, color: Tokens.text2, size: 22),
                  if (unreadNotifications > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        key: const Key('notifications-unread-dot'),
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: Tokens.accent, shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
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
    return ViCard(
      glow: streak > 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.local_fire_department, color: Tokens.accent, size: 18),
              const SizedBox(width: Tokens.s2),
              Text(streak > 0 ? '已连续打卡 $streak 天' : '打卡',
                  style: const TextStyle(
                      color: Tokens.text, fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          if (streakCopy != null) ...<Widget>[
            const SizedBox(height: Tokens.s2),
            Text(streakCopy!,
                style: const TextStyle(color: Tokens.text2, fontSize: 12, height: 1.4)),
          ],
          if (next != null) ...<Widget>[
            const SizedBox(height: Tokens.s3),
            ViProgressBar(value: progress),
          ],
        ],
      ),
    );
  }

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
      final DateTime now = DateTime.now();
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
                    '${formatVolume(r.volume, WeightUnit.kg)} · ${when(r.day)}',
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
      {required this.plan, this.label, this.onReroll, this.onOpen, this.footer});

  /// 卡底的**主按钮**（2026-10-05 移进来，与新 VI 一致：
  /// "今天练什么"和"开始"本来就是一件事，分成两块反而让人多找一次）。
  final Widget? footer;

  final List<PlannedExercise> plan;
  final String? label;
  final VoidCallback? onReroll;

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
            Padding(
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
          if (plan.length > head.length)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('…还有 ${plan.length - head.length} 个',
                  style: const TextStyle(color: Tokens.text3, fontSize: 12)),
            ),
          if (footer != null) ...<Widget>[
            const SizedBox(height: Tokens.s4),
            footer!,
          ],
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
