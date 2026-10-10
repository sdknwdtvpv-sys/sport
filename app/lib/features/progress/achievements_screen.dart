/// 练了么 · **我的成就**（2026-10-05，新 VI 的 `vi/achievement-badges.html`）
///
/// 一屏回答两件事：**已经拿到几枚**、**下一枚还差多少**。
/// 所以未解锁的徽章也照常显示（暗底勋章 + 环形进度 + 「还差 X」），而不是藏起来 ——
/// 藏起来的徽章没有任何激励作用，用户不知道自己要往哪儿使劲。
///
/// 2026-10-05 重绘：徽章那一格从"圆角方块 + 一个勾/锁"改成**一枚一枚的勋章**
/// （图形按 `badge.id` 走 `badgeIcon()`，未解锁的进度画在外圈上）。
/// 判据、文案、分组、Key 一个都没动 —— 这一屏仍然只是 `badges.dart` 的皮。
///
/// 2026-10-06：徽章从 13 枚扩到 73 枚，于是**每个分区默认只摊两行**（"展开全部 N 枚"）。
/// 73 枚一次铺满 ≈ 3000px：那是"看起来很多"而不是"看得下去"，四个分区各自的
/// 进度反而被冲掉了。折叠状态下每区两行共 6 枚 —— 一眼扫到"这一区我在哪儿"。
/// **默认折叠而不是默认展开**：进度条 + "已解锁 N/M"在顶部已经说了总量，
/// 分区里要的是"看得见的几枚"；想细看的人点一下就行（多一下点击 << 滚 3000px）。
///
/// 徽章**全部现算**（见 `badges.dart` 的文件头），这一屏不落任何库。
library;

import '../../core/icon_spec.dart';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/vi_cards.dart';
import '../../domain/models.dart';
import 'badge_medallion.dart';
import 'badges.dart';
import 'weekly_challenge.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key, required this.sets});

  /// 全部组记录。**由调用方传进来**（外壳/我的页已经加载过）——
  /// 这一屏不自己去碰数据库：同一个数据两处各读一遍，迟早会不一致。
  final List<SetRecord> sets;

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  /// 哪几个分区被展开过（Key = 分类）。默认空 = 全都折叠成两行。
  final Set<BadgeCategory> _expanded = <BadgeCategory>{};

  /// 折叠时每个分区显示几行、一行几枚。
  ///
  /// 3 枚一行是按**勋章实际宽度**定的（`_BadgeTile` 宽 100 + `Tokens.s3` 间距）：
  /// 手机宽度（375～430）正好 3 枚一行，测试视口 800 宽也是 3 枚 —— 于是"两行"
  /// 在任何屏上都是 6 枚，不必按宽度分支（那会变成另一种"看设备脸色"）。
  static const int _rowsCollapsed = 2;
  static const int _perRow = 3;

  @override
  Widget build(BuildContext context) {
    final List<BadgeStatus> all = badgeStatuses(widget.sets);
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
                        color: Tokens.text, fontSize: Tokens.fsHeadline, fontWeight: Tokens.fwBold)),
              ],
            ),
            const SizedBox(height: Tokens.s3),
            Text('已解锁 ${tally.unlocked} / ${tally.total} 枚徽章',
                key: const Key('achievements-tally'),
                style: const TextStyle(color: Tokens.text2, fontSize: Tokens.fsCap)),
            const SizedBox(height: Tokens.s1),
            // **段位**（2026-10-10 从「我」那张三行进度卡搬过来的）。
            // 它本来就是"按已解锁枚数分的档"，属于这本收藏册；放在这里之后，
            // 「我」那一页只剩等级一条进度（`docs/plan-ux-2026-10-10.md` §五-B）。
            Row(
              children: <Widget>[
                Text('${rankFor(tally.unlocked).name} · ${rankFor(tally.unlocked).need} 枚',
                    key: const Key('rank-name'),
                    style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
                const SizedBox(width: Tokens.s2),
                Expanded(
                  child: Text(
                    nextRank(tally.unlocked) == null
                        ? '已经是最高段位'
                        : '还差 ${nextRank(tally.unlocked)!.remaining} 枚到'
                            '${nextRank(tally.unlocked)!.name}',
                    key: const Key('rank-next'),
                    style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Tokens.s3),
            _nearestCard(all),
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
                                color: Tokens.text, fontSize: Tokens.fsSub, fontWeight: Tokens.fwStrong)),
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
            const SizedBox(height: Tokens.s4),

            // A1：四条收集线各自的进度 + 集齐奖励（展示性）
            _lineProgress(all),
            const SizedBox(height: Tokens.s4),

            // A3：本周挑战（周序号纯函数推导，过期作废）
            _weeklyCard(),

            // 四个分区（每区默认两行，可展开）
            for (final MapEntry<BadgeCategory, List<BadgeStatus>> e in groups.entries)
              ...<Widget>[
                const SizedBox(height: Tokens.s5),
                _sectionHeader(e.key, e.value),
                const SizedBox(height: Tokens.s3),
                _sectionBody(e.key, e.value),
              ],

            const SizedBox(height: Tokens.s5),
            _tierLegend(all),
          ],
        ),
      ),
    );
  }

  /// 分区标题：**这一区我拿到几枚**直接写在标题右边。
  ///
  /// 不写"这一区一共几枚"而写 `已拿 / 全部`：折叠起来之后，用户最想知道的是
  /// "我在这条线上走到哪了"，而不是"这条线有多少枚"（那是展开之后才关心的）。
  Widget _sectionHeader(BadgeCategory c, List<BadgeStatus> rows) {
    final int got = rows.where((BadgeStatus b) => b.unlocked).length;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(badgeCategoryLabel(c),
              style: const TextStyle(
                  color: Tokens.text, fontSize: Tokens.fsSub, fontWeight: Tokens.fwStrong)),
        ),
        Text('$got / ${rows.length}',
            key: Key('badge-section-count-${c.name}'),
            style: Tokens.display(14, weight: 700, color: Tokens.text2)),
      ],
    );
  }

  /// 分区内容：折叠时两行（6 枚），展开后全部。
  Widget _sectionBody(BadgeCategory c, List<BadgeStatus> rows) {
    final bool open = _expanded.contains(c);
    final int limit = _rowsCollapsed * _perRow;
    final bool foldable = rows.length > limit;
    final List<BadgeStatus> shown =
        open || !foldable ? rows : rows.take(limit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // **每一排都必须占满整行**（2026-10-07 用户看截图问"为什么没有设计成居中"）：
        // 原来是"写死 100 宽 + Wrap" —— 一排三枚 = 3×100 + 2×12 = 324，而内容宽度是
        // "屏宽 − 左右各 20"（Redmi 上 ≈ 353），于是**右边永远剩下二十几像素的空档**，
        // 整排看着往左偏。根因是那个写死的 100：换一台手机（更窄的、宽屏的、
        // 系统大字号下的）剩多剩少又不一样。
        // 现在按**可用宽度反算**每一枚的宽：三枚 + 两条间隙 = 正好一整行，
        // 左右只剩页面自己的留白 —— 这才是"居中"（不是把整排往中间挪一点点）。
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints cts) {
            final double tile = cts.maxWidth.isFinite
                ? (cts.maxWidth - Tokens.s3 * (_perRow - 1)) / _perRow
                : 100;
            return Wrap(
              spacing: Tokens.s3,
              runSpacing: Tokens.s3,
              children: <Widget>[
                for (final BadgeStatus b in shown)
                  _BadgeTile(
                      key: Key('badge-tile-${b.id}'), badge: b, width: tile),
              ],
            );
          },
        ),
        if (foldable) ...<Widget>[
          const SizedBox(height: Tokens.s3),
          // 折叠/展开按钮：文案**如实**写还有多少枚没显示，
          // 并且是一枚真的按钮（不是文字链 —— 45px 高的点击区在真机上好按）
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: Key('badge-section-toggle-${c.name}'),
              onPressed: () => setState(() {
                if (open) {
                  _expanded.remove(c);
                } else {
                  _expanded.add(c);
                }
              }),
              style: OutlinedButton.styleFrom(
                foregroundColor: Tokens.text2,
                side: const BorderSide(color: Tokens.line),
                padding: const EdgeInsets.symmetric(vertical: Tokens.s3),
              ),
              child: Text(
                open ? '收起' : '展开全部 ${rows.length} 枚',
                style: const TextStyle(fontSize: Tokens.fsCap),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// **A3 本周挑战**（2026-10-06 拍板）：一周一枚、同一周内人人一样、跨周自动换。
  ///
  /// 三句文案各说一件事，**都不许省**：
  ///   * 挑战名 + 进度（"本周练 3 次 · 1 / 3"）；完成之后写"本周已完成"（不再画进度）；
  ///   * 怎么算数（`how`）—— 一周挑战最怕"我不知道怎样才算"；
  ///   * **还剩几天**（周一起算，含今天）。"过期作废"必须写出来，
  ///     否则用户以为下周还能补 —— 那样稀缺感就没了，而稀缺感正是这一条的全部意义。
  ///
  /// 判据全在 `weekly_challenge.dart`（纯函数 + 单测），这一屏只负责画。
  Widget _weeklyCard() {
    final WeeklyChallenge c = weeklyChallenge(widget.sets, DateTime.now());
    return ViCard(
      key: const Key('weekly-challenge'),
      glow: !c.done,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // 与徽章同一个"周"字：这里是**限时**的那一类，所以用沙漏不用奖杯
              Icon(c.done ? Icons.check_circle : Icons.hourglass_top,
                  size: IconSpec.m,
                  color: c.done ? Tokens.success : Tokens.accent),
              const SizedBox(width: Tokens.s2),
              const Expanded(
                child: Text('本周挑战',
                    style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
              ),
              Text('还剩 ${c.daysLeft} 天',
                  key: const Key('weekly-days-left'),
                  style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
            ],
          ),
          const SizedBox(height: Tokens.s2),
          Text(c.spec.name,
              key: const Key('weekly-name'),
              style: const TextStyle(
                  color: Tokens.text, fontSize: Tokens.fsSub, fontWeight: Tokens.fwBold)),
          const SizedBox(height: 4),
          Text(
            c.done ? '本周已完成 · 下周换一枚' : '${c.spec.how} · ${c.current} / ${c.spec.target}${c.spec.unit}',
            key: const Key('weekly-progress'),
            style: const TextStyle(color: Tokens.text2, fontSize: Tokens.fsMicro, height: Tokens.lhSnug),
          ),
          if (!c.done) ...<Widget>[
            const SizedBox(height: Tokens.s3),
            ViProgressBar(value: c.progress),
          ],
        ],
      ),
    );
  }

  /// **A1 收集线进度**（2026-10-06 拍板）：四条线各自的进度 + 集齐奖励。
  ///
  /// 为什么单开一张卡，而不是只在分区标题上写"7 / 20"：分区标题是**在读的时候**
  /// 顺便看到的，而"我在哪条线上有断层"是要**一眼比出来**的（四条线并排四根条）。
  /// 集齐一条线只给**看得见的东西**：这根条走满、徽记点亮、颜色变成这条线的颜色
  /// （「我」页那张段位卡也会跟着换色 —— 见 `profile_screen.dart` 的 `_rankCard()`）；
  /// **不做**皮肤商城、不发任何可消费的东西（三条红线）。
  Widget _lineProgress(List<BadgeStatus> all) {
    final List<BadgeLine> lines = badgeLines(all);
    final int done = lines.where((BadgeLine l) => l.complete).length;
    return ViCard(
      key: const Key('badge-lines'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text('收集线',
                    style: TextStyle(
                        color: Tokens.text, fontSize: Tokens.fsSub, fontWeight: Tokens.fwStrong)),
              ),
              Text(done == 0 ? '还差一点点' : '已集齐 $done / ${lines.length} 条',
                  key: const Key('badge-lines-done'),
                  style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
            ],
          ),
          const SizedBox(height: Tokens.s3),
          for (final BadgeLine l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s3),
              child: Row(
                children: <Widget>[
                  // 集齐之后**徽记点亮**（这是奖励的第一半，另一半是下面那根条变色）
                  Icon(
                    lineIcon(l.category),
                    size: IconSpec.m,
                    color: l.complete ? lineColor(l.category) : Tokens.text3,
                    key: Key('line-emblem-${l.category.name}'),
                  ),
                  const SizedBox(width: Tokens.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(l.label,
                                  style: TextStyle(
                                    color: l.complete ? Tokens.text : Tokens.text2,
                                    fontSize: Tokens.fsCap,
                                    fontWeight: l.complete
                                        ? Tokens.fwStrong
                                        : Tokens.fwBody,
                                  )),
                            ),
                            Text(
                              l.complete ? '已集齐' : '${l.unlocked} / ${l.total}',
                              key: Key('line-count-${l.category.name}'),
                              style: TextStyle(
                                color: l.complete ? lineColor(l.category) : Tokens.text3,
                                fontSize: Tokens.fsMicro,
                                fontWeight:
                                    l.complete ? Tokens.fwStrong : Tokens.fwBody,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // 线自己的颜色（没集齐也用它 —— 四条线并排时才分得出谁是谁）
                        ViProgressBar(value: l.progress, color: lineColor(l.category)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
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
              style: TextStyle(color: Tokens.text, fontSize: Tokens.fsSub, fontWeight: Tokens.fwStrong)),
          const SizedBox(height: Tokens.s3),
          for (final (BadgeTier tier, String why) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s2),
              child: Row(
                children: <Widget>[
                  // 与徽章内芯同一个形状与同一个渐变：图例里的那三块，
                  // 就是页面上一枚枚勋章真正用的颜色（不是另配的三个色块）
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: badgeTierGradient(tier),
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  Text(badgeTierLabel(tier),
                      style: const TextStyle(color: Tokens.text, fontSize: Tokens.fsCap)),
                  const SizedBox(width: Tokens.s2),
                  Text('${countOf(tier)} 枚 · $why',
                      style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 一枚徽章（2026-10-05 重绘）。
///
/// 老样子是"一格圆角方块 + 一个勾/一把锁"，十几枚全一样，看过去就是占位符。
/// 现在每一枚是一枚**圆形勋章**：外圈环形进度 + 内芯该档渐变 + 自己的图形。
///
/// 三件事同时在说"拿没拿到"，**没有一件是只靠颜色**：
/// 1. **图形**：右下角那个戳 —— 已解锁是勾、未解锁是锁（`docs/screens.md` §S16 的纪律）；
/// 2. **进度**：未解锁的外圈按 `current / target` 画到哪算哪，"还差多少"不用读字也看得出；
/// 3. **颜色**：三档稀有度（[badgeTierColor]）只说"这枚值多少"，不说"拿没拿到"。
class _BadgeTile extends StatelessWidget {
  const _BadgeTile({super.key, required this.badge, required this.width});

  final BadgeStatus badge;

  /// 这一格占多宽 —— **由可用宽度反算**（见 `_sectionBody`），不是写死的常数。
  /// 写死宽度正是"三枚一排、右边空一截"的根因（2026-10-07 修）。
  final double width;

  /// 勋章外圈直径（环形进度线画在这一圈上）。
  static const double _ring = 64;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _medallion(),
          const SizedBox(height: Tokens.s2),
          Text(
            badge.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: badge.unlocked ? Tokens.text : Tokens.text2,
              fontSize: Tokens.fsCap,
              fontWeight: Tokens.fwStrong,
            ),
          ),
          const SizedBox(height: 4),
          // ⚠️ **T3-4（用户 2026-10-10 拍板）**：未解锁的徽章**不再写「还差 N」**。
          // 一屏原来最多同时 8 个数字 + 6 根进度条 —— 那是报表，不是收藏册；
          // 而"还差多少"这件事已经由**外圈那根进度环**说清楚了（不用读字也看得出）。
          // 唯一保留的一句是隐藏徽章的「？？？」：它说的是"有这么一枚，条件先不告诉你"，
          // 与"还差几次"是两件事。
          if (badge.unlocked || badge.hidden)
            Text(
              badge.unlocked ? badge.how : '？？？',
              key: Key('badge-meta-${badge.id}'),
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro, height: Tokens.lhSnug),
            ),
        ],
      ),
    );
  }

  /// 勋章本体：**唯一渲染器**（`BadgeMedallion`）——
  /// 完成页那枚 38pt 的与这一枚 64pt 的是同一个组件、同一个 id 图形（T3-4）。
  Widget _medallion() => BadgeMedallion(
        id: badge.id,
        tier: badge.tier,
        unlocked: badge.unlocked,
        progress: badge.progress,
        diameter: _ring,
      );

}

Widget _nearestCard(List<BadgeStatus> all) {
  final BadgeStatus? next = nearestBadge(all);
  if (next == null) {
    return ViCard(
      key: const Key('nearest-badge'),
      child: Text('全部 ${all.length} 枚都拿到了 —— 厉害。',
          style: const TextStyle(color: Tokens.text2, fontSize: Tokens.fsCap)),
    );
  }
  return ViCard(
    key: const Key('nearest-badge'),
    glow: true,
    child: Row(
      children: <Widget>[
        Icon(badgeIcon(next.id), color: badgeTierColor(next.tier), size: IconSpec.l),
        const SizedBox(width: Tokens.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('离你最近的一枚',
                  style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
              const SizedBox(height: 4),
              Text(next.name,
                  key: const Key('nearest-badge-name'),
                  style: const TextStyle(
                      color: Tokens.text, fontSize: Tokens.fsSub, fontWeight: Tokens.fwBold)),
              const SizedBox(height: 4),
              Text('还差 ${next.target - next.current} · ${next.how}',
                  style: const TextStyle(color: Tokens.text2, fontSize: Tokens.fsMicro, height: Tokens.lhSnug)),
            ],
          ),
        ),
      ],
    ),
  );
}
