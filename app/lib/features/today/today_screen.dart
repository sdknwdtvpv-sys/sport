/// 练了么 ·「练」Tab 空态（S1）+ 今日建议卡（S2）
///
/// 对应 `docs/screens.md` S1 / S2 与 `prototype/index.html` 第 1、2 屏。
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key, required this.onStart, this.lastWeekSessions = 0});

  final VoidCallback onStart;
  final int lastWeekSessions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: Padding(
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
              ),
            ),
            const _TabBar(),
          ],
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Tokens.line)),
      ),
      child: const Row(
        children: <Widget>[
          _TabItem(icon: Icons.fitness_center, label: '练', active: true),
          _TabItem(icon: Icons.show_chart, label: '进步'),
          _TabItem(icon: Icons.person_outline, label: '我'),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.icon, required this.label, this.active = false});

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? Tokens.volt : Tokens.text3;
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontSize: 11, height: 1.2)),
        ],
      ),
    );
  }
}
