/// 练了么 · **连续打卡天数**（2026-10-05，新 VI 的首页打卡卡）
///
/// 纯函数，不碰数据库：**连续天数是算出来的，不是存下来的**。
/// 这一点是刻意的 —— 存一个 `streak` 列就意味着它会和训练记录不一致
/// （改一条历史记录、导入备份、跨时区……都会让那个数字变成假话），
/// 而这个仓库最防的就是"过期状态"。
///
/// 三条口径（都有理由，测试逐条钉着）：
///   * **只有正常组算数**（`SetType.normal`）—— 与提醒、周次数同一口径：
///     热身组不算"今天练过了"；
///   * **今天还没练不算断**：晚上 8 点打开 App 看到"连续 0 天"会让人以为断了，
///     于是从**昨天**往前数 —— 今天还没练完，账不该先扣；
///   * 相邻两天之间**必须真的连上**，中间空一天就归零。
library;

import '../../domain/models.dart';
import '../profile/reminder.dart' show hasTrainedOn;

/// 下一档里程碑（VI 里那行「再坚持 7 天解锁…」用的就是它）。
const List<int> kStreakMilestones = <int>[7, 30, 100, 365];

/// 连续练了多少天（含今天；今天还没练就从昨天往前数）。
int currentStreak(List<SetRecord> sets, DateTime today) {
  final DateTime day = DateTime(today.year, today.month, today.day);
  // 今天练过 → 从今天数；没练 → 从昨天数（今天还没过完，不算断）
  DateTime cursor = hasTrainedOn(sets: sets, day: day)
      ? day
      : day.subtract(const Duration(days: 1));
  int n = 0;
  while (hasTrainedOn(sets: sets, day: cursor)) {
    n++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return n;
}

/// 下一档里程碑；已经到顶（365 天以上）返回 null。
int? nextStreakMilestone(int streak) {
  for (final int m in kStreakMilestones) {
    if (streak < m) return m;
  }
  return null;
}

/// 距下一档还差几天。到顶时为 0。
int daysToNextMilestone(int streak) {
  final int? next = nextStreakMilestone(streak);
  return next == null ? 0 : next - streak;
}

/// 打卡卡上的那句话。**没有连续天数时不说"0 天"** ——
/// 那读起来像"你什么都没有"，而事实是"今天练一次就开始记了"。
String streakCopy(int streak) {
  if (streak <= 0) return '今天练一次，就开始记连续天数';
  final int? next = nextStreakMilestone(streak);
  if (next == null) return '连续 $streak 天 —— 你已经把这件事变成习惯了';
  return '再坚持 ${next - streak} 天解锁「${_milestoneName(next)}」';
}

String _milestoneName(int days) => switch (days) {
      7 => '一周不断',
      30 => '月度铁人',
      100 => '百日坚持',
      _ => '一年不断',
    };
