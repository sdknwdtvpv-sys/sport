/// 练了么 · **站内消息的三条生成规则**（2026-10-05，v1.50）
///
/// 三类消息**全部本地生成**，没有一条来自服务器 —— 这与"数据不出设备"那条承诺一致：
/// 通知中心里出现的东西，都是这台设备自己算得出来的事。
///
///   * **成就解锁** —— 徽章解锁了（`badges.dart` 现算）；`refKey` = 徽章 id，
///     所以同一个徽章一辈子只发一条（数据库层的唯一索引兜底，见 `notification_repository.dart`）；
///     **A3 的每周挑战也走这一条**（同一个 kind，不新增枚举值）：`refKey` 带上周序号，
///     于是"同一周只发一条、下一周同一枚挑战还能再发一条"；
///   * **训练提醒** —— 提醒时间过了、而**今天还没练**（进 App 时补记一条）；
///     `refKey` = 那一天的日期，所以一天最多一条；
///   * **备份结果** —— 云备份成功后由云备份那一屏调用（成功/失败各一条，
///     `refKey` 带上备份时刻，允许同一天多条 —— 那是真的发生了多次）。
///
/// 为什么不写在各自的页面里：这三条规则都要**被测试直接调**，
/// 埋在 initState 里就只能靠"跑一遍界面"来验，而界面测试看不到"到底发了哪几条"。
library;

import '../../core/units.dart';
import '../../domain/models.dart';
import '../../data/notification_repository.dart';
import '../profile/reminder.dart';
import '../progress/badges.dart';
import '../progress/weekly_challenge.dart';

/// 徽章解锁 → 站内消息。返回**这次新发了几条**（已发过的不会重复发）。
///
/// 文案口径（2026-10-07 用户："这个消息通知里的内容有点无聊"）：
/// **事实 + 你自己的数字 + 一句去路**。老文案只有"怎么拿到"那一句，
/// 读完不知道自己走到哪儿了；现在补上"已拿到 N / M 枚"——那个数字是现算的，
/// 不是编的（`badgeTally`），它同时也回答了"还差多少"。
Future<int> syncAchievementMessages({
  required NotificationRepository repo,
  required List<SetRecord> sets,
  DateTime? now,
}) async {
  final DateTime today = now ?? DateTime.now();
  final List<BadgeStatus> statuses = badgeStatuses(sets, now: today);
  // 整批只算一次：解放一枚徽章时，"目前 N / M 枚"里的 N 是**这一轮**的口径，
  // 逐枚重算会让同一次同步里几条消息的数字互相矛盾。
  final ({int unlocked, int total}) tally = badgeTally(statuses);
  int sent = 0;
  for (final BadgeStatus b in statuses) {
    if (!b.unlocked) continue;
    final bool ok = await repo.add(
      kind: NotificationKind.achievement,
      title: '解锁「${b.name}」',
      body: '${b.how}。已拿到 ${tally.unlocked} / ${tally.total} 枚。',
      refKey: b.id, // ← 同一个徽章只发一次
      nowMs: today.millisecondsSinceEpoch,
    );
    if (ok) sent++;
  }
  return sent;
}

/// **A3 本周挑战完成** → 站内消息（复用 `NotificationKind.achievement`，不新增枚举值）。
///
/// 什么时候才发：**这一周的挑战已经完成**、而且**这一周还没为它发过**。
///
/// ⚠️ `refKey` 里**必须带周序号**，不能只用 `weekly-<id>`：池子只有 9 枚，第 10 周会轮回到
/// 第一枚 —— 只用 id 的话，那一周完成了也**发不出来**（被第 1 周那条挡住）。
///
/// ⚠️ 而周序号是**只增不减**的（见 `weekly_challenge.dart` 的 `weekIndex`），
/// 所以"上周完成了 → 这周又完成同一枚"会生成两个不同的 key，两条消息都出得来 ——
/// 那是对的：**它们是两件事**（两次独立的限时挑战）。
Future<bool> maybeWeeklyChallengeDone({
  required NotificationRepository repo,
  required List<SetRecord> sets,
  DateTime? now,
}) async {
  final DateTime today = now ?? DateTime.now();
  final WeeklyChallenge c = weeklyChallenge(sets, today);
  if (!c.done) return false;
  return repo.add(
    kind: NotificationKind.achievement,
    title: '本周挑战完成：${c.spec.name}',
    body: '${c.spec.how}。这一周还剩 ${c.daysLeft} 天（含今天），下周换一枚新的。',
    refKey: 'weekly-${weekIndex(today)}-${c.spec.id}',
    nowMs: today.millisecondsSinceEpoch,
  );
}

/// 提醒到点却还没练 → 站内消息。
///
/// 判据（三条都要成立）：
///   1. 提醒是**开着**的；
///   2. 今天该响的那个时刻**已经过了**；
///   3. **今天还没练**（练过就不该再提这件事 —— 提醒的价值是"别断掉"）。
///
/// `refKey` 用日期，所以一天最多一条。返回是否新发了一条。
Future<bool> maybeRemindMissed({
  required NotificationRepository repo,
  required ReminderSettings settings,
  required List<SetRecord> sets,
  DateTime? now,
}) async {
  if (!settings.enabled) return false;
  final DateTime t = now ?? DateTime.now();
  final int scheduledMinutes = settings.minutesOfDay;
  final int nowMinutes = t.hour * 60 + t.minute;
  if (nowMinutes < scheduledMinutes) return false; // 还没到点
  if (hasTrainedOn(sets: sets, day: t)) return false; // 今天练过了

  final String day = formatDateSortable(t);
  return repo.add(
    kind: NotificationKind.reminder,
    title: '今天还没练',
    // 文案（2026-10-07）：提醒那条最容易写成"催"，而催是没用的 ——
    // 有用的是**你自己的数字**（昨天练了几组 / 上次是几天前），
    // 它把"接上"从一句口号变成一件具体的事。三种局面按真记录分，不随机换句。
    body: '${settings.label} 的提醒到点了。${_reminderTail(sets, t)}',
    refKey: day,
    nowMs: t.millisecondsSinceEpoch,
  );
}

/// 提醒那条消息的**下半句**：用这台设备上真实的记录说一句"接着练"的话。
///
/// 三种局面（按数据分，不是按心情）：
///   * **昨天练过** → 写昨天练了几组。"接上"这件事要有具体的样子才做得出来；
///   * **更早练过** → 写上次是几天前。间隔本身就是最有用的一条事实；
///   * **一次都没练过** → **不许提连续天数**（0 天没有链可接，说"别断了"是拿不存在的东西
///     压人），只写"练一组就开始记"。
///
/// ⚠️ 只算**正式组**（与 `streak.dart` 同一口径：热身不算"练过了"）。
String _reminderTail(List<SetRecord> sets, DateTime now) {
  final DateTime day0 = DateTime(now.year, now.month, now.day);
  DateTime? lastDay;
  int lastGroups = 0;
  for (final SetRecord s in sets) {
    if (s.setType != SetType.normal) continue;
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(s.completedAtMs);
    final DateTime d = DateTime(t.year, t.month, t.day);
    if (lastDay == null || d.isAfter(lastDay)) {
      lastDay = d;
      lastGroups = 1;
    } else if (d.isAtSameMomentAs(lastDay)) {
      lastGroups++;
    }
  }
  if (lastDay == null) {
    return '今天练一组就开始记连续天数 —— 第一次是最容易接上的那次。';
  }
  final int daysAgo = day0.difference(lastDay).inDays;
  if (daysAgo <= 1) {
    return '昨天练了 $lastGroups 组，今天做一组也算接上。';
  }
  return '上次训练是 $daysAgo 天前，今天做一组也算接上。';
}

/// 云备份结果 → 站内消息（成功 / 失败各一条）。
///
/// `refKey` 带上**备份时刻**：同一天备份两次是真的发生了两次，
/// 不该被去重挡掉（这与"徽章只发一次"是两种不同的语义）。
Future<bool> addBackupMessage({
  required NotificationRepository repo,
  required bool ok,
  String? detail,
  DateTime? now,
}) async {
  final DateTime t = now ?? DateTime.now();
  // ⚠️ 去重键里**必须带上结果**：成功与失败即使落在同一毫秒也是两件事
  // （测试当场抓到的：只用时间戳时，"失败"那条被"成功"那条挡掉了）。
  final String stamp = '${t.millisecondsSinceEpoch}-${ok ? 'ok' : 'fail'}';
  return repo.add(
    kind: NotificationKind.backup,
    title: ok ? '云备份已完成' : '云备份没成功',
    body: ok
        ? (detail ?? '训练记录已加密上传。换手机时用恢复码取回。')
        : (detail ?? '这次没传上去。数据还在本机，下次打开 App 会再试。'),
    refKey: 'backup-$stamp',
    nowMs: t.millisecondsSinceEpoch,
  );
}
