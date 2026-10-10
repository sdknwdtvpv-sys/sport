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
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/vi_cards.dart';
import '../../domain/models.dart';
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
          const SizedBox(height: 2),
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
                        const SizedBox(height: 6),
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

  /// 内芯直径。
  static const double _core = 46;

  /// 环形进度线的粗细。
  static const double _stroke = 3;

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
          const SizedBox(height: 2),
          Text(
            // A4：隐藏徽章**解锁前**只说"？？？"，解锁后才把条件讲明白。
            // 名字（上面那一行）照常显示 —— 藏名字的话用户不知道有这么回事。
            badge.unlocked
                ? badge.how
                : (badge.hidden ? '？？？' : '还差 ${badge.target - badge.current}'),
            key: Key('badge-meta-${badge.id}'),
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro, height: Tokens.lhSnug),
          ),
        ],
      ),
    );
  }

  Widget _medallion() {
    final bool on = badge.unlocked;
    final Color tier = badgeTierColor(badge.tier);
    return SizedBox(
      width: _ring,
      height: _ring,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          // 外圈：已解锁画满一整圈，未解锁只画到 progress
          Positioned.fill(
            child: CustomPaint(
              painter: _BadgeRingPainter(
                progress: badge.progress,
                color: tier,
                unlocked: on,
              ),
            ),
          ),
          // 内芯：已解锁 = 该档渐变 + 一点外发光；未解锁 = 暗底 + 该档色的细描边
          Center(
            child: Container(
              key: Key('badge-${badge.id}'),
              width: _core,
              height: _core,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: on ? badgeTierGradient(badge.tier) : null,
                color: on ? null : Tokens.elevated,
                border: on ? null : Border.all(color: tier.withValues(alpha: 0.35)),
                // 已解锁的徽章发光（颜色跟着稀有度走）
                boxShadow: on ? Tokens.glow(tier) : null,
              ),
              child: Icon(
                // **每枚徽章自己的图形**（不是所有人的勾）：见 badges.dart 的 badgeIcon
                badgeIcon(badge.id),
                size: IconSpec.m,
                // 渐变上走深墨：亮橙配白只有 3.08:1，深墨是 6:1（Tokens.accentInk 的注释）
                color: on ? Tokens.accentInk : Tokens.text3,
              ),
            ),
          ),
          // 右下角的状态戳：**咬**进外圈里，勾/锁一眼可辨
          Positioned(right: 0, bottom: 0, child: _statusChip(tier)),
        ],
      ),
    );
  }

  Widget _statusChip(Color tier) {
    final bool on = badge.unlocked;
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? tier : Tokens.lift,
        // 用底色描一圈：这个戳与内芯、外圈之间不会糊成一坨
        border: Border.all(color: Tokens.bg, width: 2),
      ),
      child: Icon(
        on ? Icons.check : Icons.lock_outline,
        size: IconSpec.s,
        color: on ? Tokens.accentInk : Tokens.text3,
      ),
    );
  }
}

/// 勋章外圈的环形进度。
///
/// 自己画而不用 `CircularProgressIndicator`：那个的线宽与圆头都得再包一层去覆盖，
/// 而且 `value: null`（不确定态）在这一屏没有意义 —— "还差多少"永远是个确数。
class _BadgeRingPainter extends CustomPainter {
  const _BadgeRingPainter({
    required this.progress,
    required this.color,
    required this.unlocked,
  });

  final double progress;
  final Color color;
  final bool unlocked;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = (size.shortestSide - _BadgeTile._stroke) / 2;

    // 底圈：未解锁时它就是"还差的那一段"。**必须比内芯亮一点**（内芯是 elevated）——
    // 用同一个色的话，进度为 0 的徽章（早鸟/夜猫还没练到时）连"有个环"都看不出来。
    // 这只是一层中性灰，没有引入新的色相：就是把 elevated 往 text3 提了 35%。
    final Color lockedTrack = Color.lerp(Tokens.lift, Tokens.text3, 0.35)!;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _BadgeTile._stroke
        ..color = unlocked ? color.withValues(alpha: 0.25) : lockedTrack,
    );

    final double v = progress.isNaN ? 0 : progress.clamp(0.0, 1.0);
    if (v <= 0) return;

    // 从 12 点开始顺时针：方向和"训练量在往上涨"一致
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * v,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _BadgeTile._stroke
        ..strokeCap = StrokeCap.round
        ..color = unlocked ? color : color.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(covariant _BadgeRingPainter old) =>
      old.progress != progress || old.color != color || old.unlocked != unlocked;
}

/// **A2「离你最近的一枚」**（2026-10-06 拍板）：顶部回答"今天做什么能再拿一枚"。
/// 判据在 `nearestBadge()`（纯函数、有单测）；全拿到了就如实说，不挑一枚充数。
/// 点它不跳走 —— 与首页"今天的安排"同一条纪律：不给假入口。
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
              const SizedBox(height: 2),
              Text(next.name,
                  key: const Key('nearest-badge-name'),
                  style: const TextStyle(
                      color: Tokens.text, fontSize: Tokens.fsSub, fontWeight: Tokens.fwBold)),
              const SizedBox(height: 2),
              Text('还差 ${next.target - next.current} · ${next.how}',
                  style: const TextStyle(color: Tokens.text2, fontSize: Tokens.fsMicro, height: Tokens.lhSnug)),
            ],
          ),
        ),
      ],
    ),
  );
}
