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

  /// 「今天不想练？做 5 分钟活动 ›」（2026-10-01 加）。
  ///
  /// 习惯养成的敌人是"全有或全无"：今天没力气做 5 组深蹲，不等于该断掉。
  /// 这条路径给 4 个**按时长的活动**（1 组、30–45 秒），几分钟就能走完，
  /// 也算一次训练。**它不抢主按钮的位置**，只是主按钮下面一行小字。
  final VoidCallback? onLightWorkout;

  @override
  Widget build(BuildContext context) {
    // 2026-10-04：中间多了「今天的安排」那张卡之后，**矮屏会溢出**
    // （Flutter 的 `overflowed` 是本项目盯着的异常之一，真机走查也把它算进验收）。
    // 所以这一屏改成"填满视口、内容更高时可滚动"：
    //   * `minHeight = 视口高` → 高屏上 Spacer 把按钮压到底部（拇指区那个决定不变）；
    //   * 内容真的比视口高（小屏 / 大字体 / 6 行计划）→ 整屏可滚，不炸。
    // `IntrinsicHeight` 是让 `Spacer` 在有 ConstrainedBox 的滚动视图里仍能工作的那一招。
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: IntrinsicHeight(
            child: _content(),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.s5),
      child: Column(
        // ⚠️ 刻意**不用 MainAxisAlignment.center**（2026-10-01 真机走查后改的）：
        // 居中会让标题落在屏幕 1/4 处、上下各空一大块，而大按钮落在 48% ——
        // 上面那块空白白白浪费，按钮又没落到最舒服的拇指区。
        // 现在是"标题贴上去 + 中间 Spacer + 按钮与链接压在下面"：
        // 顶部留白从约 1/4 屏收到 24pt，大按钮落到屏幕下方（单手持机更顺）。
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: Tokens.s6),
          // 空态不要求先做计划：点一下就开始记录。
          const Text(
            '今天\n练点什么？',
            style: TextStyle(
              color: Tokens.text,
              fontSize: 44,
              height: 1.09,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.2,
            ),
          ),
          const SizedBox(height: Tokens.s3),
          const Text(
            '不需要先做计划。点一下就开始记录。',
            style: TextStyle(color: Tokens.text2, fontSize: 17, height: 1.4),
          ),
          // 中间那块（原来是一个 `Spacer()`，真机上看就是一大片空白）：
          // 2026-10-04 换成**今天的安排** —— 清单 + 「换一批」，**整块可点**（进建议卡）。
          // 空白没了，而按钮仍然压在下面（不动拇指区的那个决定）。
          //
          // 计划还没算出来时**也照常显示**（内容换成一句"点这里看看怎么练"）：
          // 入口不能因为一次加载失败就消失，那会让「我自己选 / 我的计划」变得够不着。
          if (todayPlan.isNotEmpty || onSeePlan != null) ...<Widget>[
            const SizedBox(height: Tokens.s4),
            _TodayPlanCard(
              plan: todayPlan,
              label: todayLabel,
              onReroll: onReroll,
              onOpen: onSeePlan,
            ),
          ],
          const Spacer(),
          // 上次没练完 → 一条"接着练"（放在主按钮之前：此刻它才是该做的那件事）
          if (onResume != null) ...<Widget>[
            GestureDetector(
              key: const Key('resume-session'),
              onTap: onResume,
              behavior: HitTestBehavior.opaque,
              child: Container(
                margin: const EdgeInsets.only(bottom: Tokens.s3),
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
                        color: Tokens.accent, size: 20),
                    const SizedBox(width: Tokens.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text('上次的训练还没结束',
                              style: TextStyle(
                                  color: Tokens.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          if (resumeLabel != null)
                            Text(resumeLabel!,
                                style: const TextStyle(
                                    color: Tokens.text3, fontSize: 12)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Tokens.text3, size: 20),
                  ],
                ),
              ),
            ),
          ],
          SizedBox(
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
          ),
          // S13 的入口：**可选、非阻塞**。主按钮仍然是"点一下就能开始训练"，
          // 这一行只是给"不知道从哪下手"的人一个台阶。
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
          // 「今天不想练」的轻量出口：主按钮之下、次要链接之列 —— 需要它的人看得见，
          // 不需要它的人不会被它拦住。
          if (onLightWorkout != null) ...<Widget>[
            const SizedBox(height: Tokens.s2),
            Center(
              child: TextButton(
                key: const Key('light-workout'),
                onPressed: onLightWorkout,
                child: const Text('今天不想练？做 5 分钟活动 ›',
                    style: TextStyle(color: Tokens.text3, fontSize: 13)),
              ),
            ),
          ],
          const SizedBox(height: Tokens.s3),
          Center(
            child: Text(
              lastWeekSessions > 0 ? '我上周练了 $lastWeekSessions 次' : '还没有训练记录',
              style: const TextStyle(color: Tokens.text3, fontSize: 13),
            ),
          ),
          const SizedBox(height: Tokens.s4),
        ],
      ),
    );
  }
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
      {required this.plan, this.label, this.onReroll, this.onOpen});

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
