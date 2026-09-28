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

class TodayScreen extends StatelessWidget {
  const TodayScreen({
    super.key,
    required this.onStart,
    this.lastWeekSessions = 0,
    this.onPlanHelp,
  });

  final VoidCallback onStart;
  final int lastWeekSessions;

  /// S13 的可选入口。**为 null 时不显示** —— 已经定过计划的人不需要它，
  /// 而放一个点不动的链接比没有更糟。
  final VoidCallback? onPlanHelp;

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
