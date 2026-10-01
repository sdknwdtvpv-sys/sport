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
  });

  /// 大按钮：**一跳直接进训练屏**（用今天的第一条建议），不再强制过建议卡。
  ///
  /// 为什么：端到端口径下原来的路径是「今日页 → 建议卡 → 大按钮」= 3 次点击才记下
  /// 第一组，而 `PRODUCT.md` §1 的红线是"超过 3 次点击判负"—— 刚好压线。
  /// 现在第一组 2 次（首页 + 大按钮），同一动作的第 2 组起 1 次。
  final VoidCallback onStart;

  final int lastWeekSessions;

  /// 「看看今天练什么 ›」：进建议卡（换一批 / 我的计划 / 我自己选都在那儿）。
  ///
  /// 建议卡没有被砍掉，只是**不再挡在开练前面** —— 想看的人看得见，
  /// 不想想的人点一下就能开始记。
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.s5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
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
          const SizedBox(height: Tokens.s8),
          SizedBox(
            height: Tokens.hPrimary,
            width: double.infinity,
            child: FilledButton(
              key: const Key('start-workout'),
              style: FilledButton.styleFrom(
                backgroundColor: Tokens.volt,
                foregroundColor: Tokens.voltInk,
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
                  border: Border.all(color: Tokens.volt),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.play_circle_outline,
                        color: Tokens.volt, size: 20),
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
          // 建议卡入口：**可选**。主按钮已经能直接开练，这一行只是给想先看看的人。
          if (onSeePlan != null) ...<Widget>[
            const SizedBox(height: Tokens.s2),
            Center(
              child: TextButton(
                key: const Key('see-plan'),
                onPressed: onSeePlan,
                child: const Text('看看今天练什么 ›',
                    style: TextStyle(color: Tokens.text2, fontSize: 14)),
              ),
            ),
          ],
          // S13 的入口：**可选、非阻塞**。主按钮仍然是"点一下就能开始训练"，
          // 这一行只是给"不知道从哪下手"的人一个台阶。
          if (onPlanHelp != null) ...<Widget>[
            if (onSeePlan == null) const SizedBox(height: Tokens.s2),
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
        ],
      ),
    );
  }
}
