/// 练了么 · **连续保护（补签）**（第二部分第 2 条，2026-10-06 用户拍板）
///
/// 一句话：**每周一次，代价 = 本周至少练过 1 次；补签不涨连续天数，只防断。**
///
/// 为什么这一条值得做：连续打卡是这个产品里唯一会"归零"的东西，而归零是**放弃**的
/// 最强触发器 —— 断了一天之后，很多人不是第二天回来，而是再也不回来（"反正断了"）。
/// 补签把那个"反正断了"往后推一天：**链还在，明天接着练就行**。
///
/// 三条约束（拍板时就定死的，别在下一次改口径时忘掉）：
///   1. **每周一次**：一周之内只能补一天。额度不是查表得到的，而是**由已补的那一天反推**
///      （周一那天所在的周）；
///   2. **代价 = 本周至少练过 1 次**：白送的保护没有意义，而且这条代价让用户
///      "先练一次再补" —— 顺序是对的（先动起来，再谈保护）；
///   3. **不涨连续天数，只防断**：被补的那天**不计入**连续天数（所以界面必须
///      如实写出"其中 N 天是补签"，否则那个数字就成了假话）。
///
/// ⚠️ 被补的那些日子**存在 `streak_protection` 表里**（唯一一条关于历史的用户声明），
/// 判据全部是这里的纯函数，界面只负责画、仓库只负责搬。
library;

import '../../domain/models.dart';

/// 这一轮能补签哪一天（不能补时为 null）。
class StreakProtectionOffer {
  const StreakProtectionOffer({
    required this.day,
    required this.label,
  });

  /// 要补的那一天（本地日零点）
  final DateTime day;

  /// 界面上那一行（"要补的是昨天（10 月 4 日）"这种，由 [offerCopy] 生成）
  final String label;
}

/// `YYYY-MM-DD`（**本地日**）。与 `body_metric.date` 同一种写法：
/// 这一列要能被人肉读出来，排障时一眼看到"补的是哪一天"。
String dayKey(DateTime t) => '${t.year.toString().padLeft(4, '0')}-'
    '${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}';

/// 一天有没有练（只算正式组：热身不算"今天练过了"—— 与 `streak.dart` 同一口径）。
bool trainedOn(List<SetRecord> sets, DateTime day) {
  for (final SetRecord s in sets) {
    if (s.setType != SetType.normal) continue;
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(s.completedAtMs);
    if (t.year == day.year && t.month == day.month && t.day == day.day) {
      return true;
    }
  }
  return false;
}

/// 这一天算不算"链没断"（练过 **或** 被补签保护）。
bool chainKept(List<SetRecord> sets, Set<String> protectedDays, DateTime day) =>
    trainedOn(sets, day) || protectedDays.contains(dayKey(day));

/// **连续天数（含今天）**：与 `streak.dart` 的 `currentStreak` 同一套口径，
/// 只是多认一种"那天没断"——被补签保护过的那天。
///
/// 三条口径照旧：
///   * 只有正常组算数；
///   * **今天还没练不算断**（晚上 8 点打开 App 看到"连续 0 天"会让人以为断了）；
///   * 相邻两天之间必须真的连上。
///
/// ⚠️ **被补的那天计 1**（它撑住了链），所以界面上必须同时写出"其中 N 天是补签" ——
/// 否则"连续 12 天"里有 1 天其实没练，那个数字就是句假话。
int streakWithProtection(
  List<SetRecord> sets,
  Set<String> protectedDays,
  DateTime today,
) {
  final DateTime day = DateTime(today.year, today.month, today.day);
  DateTime cursor = chainKept(sets, protectedDays, day)
      ? day
      : day.subtract(const Duration(days: 1));
  int n = 0;
  while (chainKept(sets, protectedDays, cursor)) {
    n++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return n;
}

/// 有保护的今天之前、落在当前这条链里的被保护天数（"其中 N 天是补签"用的）。
///
/// 只数**当前这条链里**的：历史上前几个月补过的那些不该被算进"这 12 天里有 1 天"。
int protectedDaysInStreak(
  List<SetRecord> sets,
  Set<String> protectedDays,
  DateTime today,
) {
  final DateTime day = DateTime(today.year, today.month, today.day);
  DateTime cursor = chainKept(sets, protectedDays, day)
      ? day
      : day.subtract(const Duration(days: 1));
  int n = 0;
  while (chainKept(sets, protectedDays, cursor)) {
    if (protectedDays.contains(dayKey(cursor))) n++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return n;
}

/// 这一周（周一 00:00 起算）有没有补过签。
///
/// 额度**由已补的那一天反推**，不另存计数 —— 存计数就会和表本身不一致。
bool usedThisWeek(Set<String> protectedDays, DateTime today) {
  final DateTime monday = DateTime(today.year, today.month, today.day)
      .subtract(Duration(days: today.weekday - DateTime.monday));
  final DateTime next = monday.add(const Duration(days: 7));
  for (final String key in protectedDays) {
    final DateTime d = DateTime.parse(key);
    if (!d.isBefore(monday) && d.isBefore(next)) return true;
  }
  return false;
}

/// 这一周（周一起算）练过没有 —— 补签的**代价**。
bool trainedThisWeek(List<SetRecord> sets, DateTime today) {
  final DateTime monday = DateTime(today.year, today.month, today.day)
      .subtract(Duration(days: today.weekday - DateTime.monday));
  final DateTime next = monday.add(const Duration(days: 7));
  for (final SetRecord s in sets) {
    if (s.setType != SetType.normal) continue;
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(s.completedAtMs);
    if (!t.isBefore(monday) && t.isBefore(next)) return true;
  }
  return false;
}

/// **现在能不能补签**。不能则返回 null（界面据此什么都不显示）。
///
/// 判据三条（每一条都有理由）：
///   1. **本周至少练过 1 次**（代价）。白送的保护没有意义，而且这条代价让用户
///      "**先练一次再补**"——顺序是对的：先动起来，再谈保护；
///   2. 这一周**还没补过**（每周一次，额度由已补的那天反推）；
///   3. **昨天与前天里恰好断了一天**（没练、也没被保护）。⚠️ **今天不参与判断**：
///      "今天还没练"从来不算断（与 `streak.dart` 同一条纪律），把它算进来会拒掉
///      最常见的局面（晚上打开 App、今天还没练、昨天断了）——而那正是最该补的时刻。
///
/// ⚠️ 这条规则改了三版，每一版都错在"按感觉写"：
///   * 第一版要求"断点**之后**练过" —— 只断了昨天时永远不成立（后面只剩今天）；
///   * 第二版要求"断点**前一天**也练过" —— 想多了：代价 + 恰好一个洞，
///     已经把"三个月没来的人"挡在外面（那种人的窗口里全是洞）；
///   * 第三版把"今天"也算进没练的天数 —— 于是晚上打开 App 拿不到补签。
///   判据要按**局面**写，而且必须给每一个局面写一条测试。
StreakProtectionOffer? protectionOffer(
  List<SetRecord> sets,
  Set<String> protectedDays,
  DateTime today,
) {
  final DateTime day = DateTime(today.year, today.month, today.day);
  // ① 代价：这一周至少练过 1 次
  if (!trainedThisWeek(sets, today)) return null;
  // ② 每周一次
  if (usedThisWeek(protectedDays, today)) return null;

  // ③ 只看**昨天与前天**：这两天里没练（也没被保护）的**恰好一天**，那就是要补的那天。
  //
  // ⚠️ ** "今天"不参与这个判断** —— "今天还没练"从来不算断（与 `streak.dart` 的
  // "今天还没练不算断"是同一条纪律：账不该先扣）。把它算进来的话，
  // 最常见的局面（晚上打开 App、今天还没练、昨天断了）会因为"两天没练"被拒掉，
  // 而那时恰恰是最该给补签的时刻。这一条也是靠测试才发现写反的。
  final List<DateTime> gaps = <DateTime>[
    for (int i = 1; i <= 2; i++)
      if (!chainKept(sets, protectedDays, day.subtract(Duration(days: i))))
        day.subtract(Duration(days: i)),
  ];
  if (gaps.length != 1) return null;

  return StreakProtectionOffer(
      day: gaps.first, label: offerCopy(gaps.first, day));
}

/// 界面上那一行：**只说事实 + 一句去路**。
///
/// 口径：不制造愧疚（没有感叹号、不说"你差点就断了"）。补签本身是一个
/// "我知道、我选择继续"的动作，语气越平常越容易被做出来。
String offerCopy(DateTime missed, DateTime today) {
  final int daysAgo = today.difference(missed).inDays;
  final String when = switch (daysAgo) {
    1 => '昨天',
    2 => '前天',
    _ => '${missed.month} 月 ${missed.day} 日',
  };
  return '$when（${missed.month} 月 ${missed.day} 日）没练，'
      '补签一次就能接上 —— 每周一次。';
}

/// 补完之后那句"如实交代"：「已连续打卡 N 天」，若其中有补签则补上括号。
///
/// ⚠️ 这个函数存在的唯一理由就是**不许说假话**：连续天数里含补签时，
/// 不写出来就等于在告诉用户"这 12 天我天天都练了"。
String streakLabelWithProtection(int streak, int protectedInStreak) {
  if (streak <= 0) return '今天练一次，就开始记连续天数';
  if (protectedInStreak <= 0) return '已连续打卡 $streak 天';
  return '已连续打卡 $streak 天（其中 $protectedInStreak 天是补签）';
}
