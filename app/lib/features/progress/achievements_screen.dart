/// 练了么 · **我的成就**（2026-10-05，新 VI 的 `vi/achievement-badges.html`）
///
/// 一屏回答两件事：**已经拿到几枚**、**下一枚还差多少**。
/// 所以未解锁的徽章也照常显示（灰底 + 「还差 X」），而不是藏起来 ——
/// 藏起来的徽章没有任何激励作用，用户不知道自己要往哪儿使劲。
///
/// 徽章**全部现算**（见 `badges.dart` 的文件头），这一屏不落任何库。
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/vi_cards.dart';
import '../../domain/models.dart';
import 'badges.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key, required this.sets});

  /// 全部组记录。**由调用方传进来**（外壳/我的页已经加载过）——
  /// 这一屏不自己去碰数据库：同一个数据两处各读一遍，迟早会不一致。
  final List<SetRecord> sets;

  @override
  Widget build(BuildContext context) {
    final List<BadgeStatus> all = badgeStatuses(sets);
    final ({int unlocked, int total}) tally = badgeTally(all);
    final Map<BadgeCategory, List<BadgeStatus>> groups = badgeGroups(all);

    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, Tokens.s5),
          children: <Widget>[
            Row(
              children: <Widget>[
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    key: const Key('achievements-back'),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.chevron_left, color: Tokens.text2),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: Tokens.s3),
                const Text('我的成就',
                    style: TextStyle(
                        color: Tokens.text, fontSize: 20, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: Tokens.s3),
            Text('已解锁 ${tally.unlocked} / ${tally.total} 枚徽章',
                key: const Key('achievements-tally'),
                style: const TextStyle(color: Tokens.text2, fontSize: 13)),
            const SizedBox(height: Tokens.s4),

            // 收集进度
            ViCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text('收集进度',
                            style: TextStyle(
                                color: Tokens.text, fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                      Text('${tally.unlocked} / ${tally.total}',
                          style: Tokens.display(18, weight: 700)),
                    ],
                  ),
                  const SizedBox(height: Tokens.s3),
                  ViProgressBar(
                    value: tally.total == 0 ? 0 : tally.unlocked / tally.total,
                  ),
                ],
              ),
            ),

            // 四个分区
            for (final MapEntry<BadgeCategory, List<BadgeStatus>> e in groups.entries) ...<Widget>[
              const SizedBox(height: Tokens.s5),
              Text(badgeCategoryLabel(e.key),
                  style: const TextStyle(
                      color: Tokens.text, fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: Tokens.s3),
              Wrap(
                spacing: Tokens.s3,
                runSpacing: Tokens.s3,
                children: <Widget>[
                  for (final BadgeStatus b in e.value) _BadgeTile(badge: b),
                ],
              ),
            ],

            const SizedBox(height: Tokens.s5),
            _tierLegend(all),
          ],
        ),
      ),
    );
  }

  /// 稀有度图例。**每一档都写出"是自己算的、判据不掺水"** ——
  /// 徽章最容易变成"随便发发的贴纸"，而这一屏的设计意图是让人知道目标在哪。
  Widget _tierLegend(List<BadgeStatus> all) {
    int countOf(BadgeTier t) => all.where((BadgeStatus b) => b.tier == t).length;
    final List<(BadgeTier, String)> rows = <(BadgeTier, String)>[
      (BadgeTier.common, '基础成就'),
      (BadgeTier.rare, '进阶挑战'),
      (BadgeTier.epic, '终极目标'),
    ];
    return ViCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('稀有度',
              style: TextStyle(color: Tokens.text, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: Tokens.s3),
          for (final (BadgeTier tier, String why) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s2),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: badgeTierColor(tier),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  Text(badgeTierLabel(tier),
                      style: const TextStyle(color: Tokens.text, fontSize: 13)),
                  const SizedBox(width: Tokens.s2),
                  Text('${countOf(tier)} 枚 · $why',
                      style: const TextStyle(color: Tokens.text3, fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 一枚徽章：三档各有自己的颜色，未解锁的**照样显示**并写出还差多少。
class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge});

  final BadgeStatus badge;

  @override
  Widget build(BuildContext context) {
    final Color color = badgeTierColor(badge.tier);
    return SizedBox(
      width: 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            key: Key('badge-${badge.id}'),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: badge.unlocked ? color : Tokens.elevated,
              borderRadius: BorderRadius.circular(Tokens.rCard),
              boxShadow: badge.unlocked
                  ? <BoxShadow>[
                      BoxShadow(
                        color: color.withValues(alpha: 0.22),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              // 未解锁用锁、已解锁用勾：**不只靠颜色**表达解锁与否
              badge.unlocked ? Icons.check_rounded : Icons.lock_outline,
              color: badge.unlocked ? const Color(0xFF1A1208) : Tokens.text3,
              size: 26,
            ),
          ),
          const SizedBox(height: Tokens.s2),
          Text(
            badge.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: badge.unlocked ? Tokens.text : Tokens.text2,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            badge.unlocked ? badge.how : '还差 ${badge.target - badge.current}',
            key: Key('badge-meta-${badge.id}'),
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(color: Tokens.text3, fontSize: 11, height: 1.3),
          ),
        ],
      ),
    );
  }
}
