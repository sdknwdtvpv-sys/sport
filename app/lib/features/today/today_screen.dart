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
  const TodayScreen({super.key, required this.onStart, this.lastWeekSessions = 0});

  final VoidCallback onStart;
  final int lastWeekSessions;

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
