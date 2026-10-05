/// 练了么 · 训练提醒设置的读写（单行表 `reminder_setting`）
///
/// 单独一个 repository（而不是塞进 `ProfileRepository`）：
/// 那张表的每个 setter 都要把整行带回来，提醒放进去就会跟"改单位/改统计开关"
/// 绑在一起 —— 两件事没关系，就不该共享一次整行写入。
library;

import '../features/profile/reminder.dart';
import 'db.dart';

class ReminderRepository {
  ReminderRepository(this._db);

  final AppDatabase _db;

  /// 本机只有一份提醒设置
  static const String kReminderId = 'local';

  /// 读设置。**没有那行时返回默认值（关、20:00）** —— 与"从没设置过"是同一件事。
  Future<ReminderSettings> load() async {
    final ReminderSettingData? row = await (_db.select(_db.reminderSetting)
          ..where((t) => t.id.equals(kReminderId)))
        .getSingleOrNull();
    if (row == null) return ReminderSettings.off;
    return ReminderSettings(
      enabled: row.enabled,
      minutesOfDay: row.minutesOfDay,
    );
  }

  Future<void> save(ReminderSettings settings, {int? nowMs}) async {
    // 非法时间**不许静默落库**：`nextReminderAtMs` 对越界值会返回 null（= 不排提醒），
    // 于是"设了却不响"这种最难查的状态就成立了。宁可当场喊出来。
    if (settings.minutesOfDay < 0 || settings.minutesOfDay >= 24 * 60) {
      throw ArgumentError.value(
          settings.minutesOfDay, 'minutesOfDay', '必须在 0–1439 之间');
    }
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.reminderSetting).insertOnConflictUpdate(
          ReminderSettingData(
            id: kReminderId,
            enabled: settings.enabled,
            minutesOfDay: settings.minutesOfDay,
            updatedAt: now,
          ),
        );
  }
}
