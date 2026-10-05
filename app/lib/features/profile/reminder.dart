/// 训练提醒（**本地通知**）。
///
/// 它服务的是 D7（次日回访）：见 `docs/plan-scene-and-return.md` ②。
/// 四条口径（每一条都对应一处实现或一条测试）：
///   1. **默认关闭**，用户主动开 —— 通知是这个 App 拿到的**第四个**能力，
///      按项目一贯的做法：不主动要（`docs/privacy-policy.md` §2.1 与隐私事实表都这么写）；
///   2. **只在"该练没练"时打扰**：到点了当天还没有训练记录才提醒；练过了就顺延到明天
///      —— 提醒的功能是"把人叫回来"，不是"每天准点响一次"；
///   3. **不联网**：由系统在本机排程并显示，内容也在设备上生成。服务端不知道你几点该练；
///   4. **失败静默**：排不上提醒绝不该影响记录训练（与 Live Activity 同一条纪律）。
library;

import '../../domain/models.dart';

/// 用户的提醒设置。
class ReminderSettings {
  const ReminderSettings({required this.enabled, required this.minutesOfDay});

  final bool enabled;

  /// 一天中的第几分钟（0–1439）。默认 20:00 = 1200。
  final int minutesOfDay;

  /// 没设置过时的样子：**关**，时间是 20:00（用户开了就直接用这个默认值）。
  static const ReminderSettings off =
      ReminderSettings(enabled: false, minutesOfDay: 20 * 60);

  int get hour => minutesOfDay ~/ 60;
  int get minute => minutesOfDay % 60;

  /// 界面上怎么念：`20:00`
  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  ReminderSettings copyWith({bool? enabled, int? minutesOfDay}) =>
      ReminderSettings(
        enabled: enabled ?? this.enabled,
        minutesOfDay: minutesOfDay ?? this.minutesOfDay,
      );
}

/// **今天练过没有**（只算正式组：热身不算"练过了"）。
///
/// 与 `weekWorkoutCount` 同一个口径：按**本地日**比，而不是"距今 24 小时"——
/// 晚上 11 点练完、第二天早上 7 点再打开 App，不该被算成"今天练过了"。
bool hasTrainedOn({required List<SetRecord> sets, required DateTime day}) {
  for (final SetRecord s in sets) {
    if (s.setType != SetType.normal) continue;
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(s.completedAtMs);
    if (t.year == day.year && t.month == day.month && t.day == day.day) {
      return true;
    }
  }
  return false;
}

/// 下一次该提醒的时刻（毫秒时间戳）。
///
/// 规则一句话：**到点了还没练，就提醒你一次；练过了就顺延到明天。**
///
/// * 今天还没练、而且今天那个点还没到 → 今天那个点；
/// * 否则 → 明天那个点（包括"今天已经练过"与"今天那个点已经过去"两种情形）。
///
/// ⚠️ 用 `DateTime(y, m, d + 1, h, min)` 而不是"加 24 小时"：
/// 夏令时切换那天一天不是 24 小时，加固定毫秒会让提醒漂到别的钟点。
int? nextReminderAtMs({
  required int nowMs,
  required int minutesOfDay,
  required bool trainedToday,
}) {
  if (minutesOfDay < 0 || minutesOfDay >= 24 * 60) return null;
  final DateTime now = DateTime.fromMillisecondsSinceEpoch(nowMs);
  final int h = minutesOfDay ~/ 60;
  final int m = minutesOfDay % 60;
  final DateTime todayAt = DateTime(now.year, now.month, now.day, h, m);
  if (!trainedToday && todayAt.isAfter(now)) return todayAt.millisecondsSinceEpoch;
  return DateTime(now.year, now.month, now.day + 1, h, m).millisecondsSinceEpoch;
}

/// 界面上那行**「下次什么时候响」**。
///
/// 为什么必须有它（2026-10-04 真机反馈"设了闹钟但没响"）：排程规则是对的
/// （到点还没练才提醒、练过就顺延），但**用户看不到它排到了哪天** ——
/// 于是"设了 17:58、现在就是 17:58"看起来就是"坏了"。把事实写出来，
/// 这条困惑就消失了；顺带也解释了"为什么刚练完设的提醒不响"。
///
/// 返回 null = 没开提醒（界面不显示这一行）。
String? reminderHint({
  required ReminderSettings settings,
  required bool trainedToday,
  required int nowMs,
}) {
  if (!settings.enabled) return null;
  final DateTime now = DateTime.fromMillisecondsSinceEpoch(nowMs);
  final int h = settings.hour;
  final int m = settings.minute;
  final DateTime todayAt = DateTime(now.year, now.month, now.day, h, m);
  final bool laterToday = !trainedToday && todayAt.isAfter(now);
  final String clock =
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  if (laterToday) return '下次提醒：今天 $clock';
  return trainedToday
      ? '下次提醒：明天 $clock（今天已经练过了，不打扰）'
      : '下次提醒：明天 $clock（今天的点已经过了）';
}
