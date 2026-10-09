/// 练了么 · 未结束的训练会话**有多旧**（2026-10-09，10.9 清单第 1 条）
///
/// 用户原话：「上次的训练还没结束 · 上次练到第 N/M 个动作」——**不限期的**。
/// 那条会话来自 `active_session`（每次记一组、每次换动作都会重写它），
/// 而在此之前它**不区分是哪一天的**：三个月前那次半途而废的训练，
/// 冷启动照样顶在首页最上面喊"接着练"。
///
/// 他拍板的规则：
///   * **今天就开始的** → 什么都不弹（用户可能只是切出去接了个电话）；
///   * **跨天了、但还在 7 天内** → 冷启动弹一次三选一
///     （继续 / 结束并保存 / 丢弃）；
///   * **超过 7 天** → 不再弹，只在「计划」页留一条入口（不骚扰）。
///
/// 为什么这些判断是**纯函数**：它们决定"要不要打断用户"，
/// 而"哪天算跨天""第 8 天算不算过期"这种边界最容易在两次实现里长歪
/// （首页一处、计划页一处）—— 一处算出"该弹"、另一处算出"过期"，
/// 用户就会看到一条自相矛盾的东西。所以只有一份，且有测试钉着。
library;

import '../../domain/models.dart';

/// 跨天之后还愿意问几天的上限（用户拍板：7 天）。
const int kStaleSessionAskDays = 7;

/// 这条未结束的会话属于哪一档。
enum StaleSessionKind {
  /// 今天开始的：不弹任何东西。
  sameDay,

  /// 跨天了但还在规则内：冷启动弹一次「继续 / 结束并保存 / 丢弃」。
  crossDay,

  /// 超过 [kStaleSessionAskDays] 天：**不再弹**，只在「计划」页留一条入口。
  expired,
}

/// 两个**自然日**之间差几天（只看日历，不看时刻）。
///
/// ⚠️ 不能用 `Duration.inDays`：夏令时那两天本地午夜之间只差 23 或 25 小时，
/// 于是"昨晚 23:50 开始的训练"会被算成 0 天（不跨天，不弹）——
/// 而用户明明过了一夜。所以按 `(年,月,日)` 折算成 UTC 再相减。
int calendarDaysBetween(DateTime from, DateTime to) {
  final DateTime a = DateTime.utc(from.year, from.month, from.day);
  final DateTime b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// 这条会话属于哪一档。[now] 由调用方给（可注入，测试用）。
StaleSessionKind staleSessionKind(ActiveSession session, DateTime now) {
  final int days = sessionAgeDays(session, now);
  if (days <= 0) return StaleSessionKind.sameDay;
  if (days <= kStaleSessionAskDays) return StaleSessionKind.crossDay;
  return StaleSessionKind.expired;
}

/// 这条会话开始于几天前（自然日）。今天开始的就是 0。
int sessionAgeDays(ActiveSession session, DateTime now) =>
    calendarDaysBetween(
        DateTime.fromMillisecondsSinceEpoch(session.startedAtMs), now);

/// 「今天」/「昨天」/「3 天前」—— 三选一弹层的正文与计划页那行小字共用同一份说法。
String staleSessionAgeLabel(int days) {
  if (days <= 0) return '今天';
  if (days == 1) return '昨天';
  return '$days 天前';
}

/// 「上次练到第 2/3 个动作 · 3 天前」。
///
/// 放在这里而不是各屏自己拼：首页那条恢复条与计划页那条入口说的是**同一件事**，
/// 两处各拼一遍就会出现"首页说第 2/3、计划页说第 3/3"（一个用 index、
/// 一个用 index+1 这种低级错位）。
String staleSessionResumeLabel(ActiveSession session, DateTime now) {
  final int at = (session.index + 1).clamp(1, session.length);
  return '上次练到第 $at/${session.length} 个动作 · '
      '${staleSessionAgeLabel(sessionAgeDays(session, now))}';
}
