/// 练了么 · **站内消息 / 通知中心**的数据层（2026-10-05，v1.50）
///
/// 三类消息**全部本地生成**，没有一条来自服务器：
///   * `achievement` —— 徽章解锁（与已发过的消息对账，见 [refKey]）；
///   * `reminder` —— 训练提醒到点还没练（进 App 时补记一条）；
///   * `backup` —— 云备份结果（成功 / 失败）。
///
/// **去重靠数据库的唯一索引**（`kind + ref_key`），不靠这里"先查一次再插"——
/// 那种写法在多处调用时会漏，而漏了的后果是同一个徽章每练一次报一次。
/// 所以 [add] 用的是 `insertOrIgnore`：重复的那条**静默丢掉**，不抛异常、也不覆盖。
library;

import 'package:drift/drift.dart';

import '../../core/uuid.dart';
import 'db.dart';

/// 三类消息的 kind（**只有这三种**，别随手加第四种：
/// 界面上那排筛选 chip 与这里的取值是一一对应的）。
abstract final class NotificationKind {
  static const String achievement = 'achievement';
  static const String reminder = 'reminder';
  static const String backup = 'backup';

  static const List<String> all = <String>[achievement, reminder, backup];

  static String label(String kind) => switch (kind) {
        achievement => '成就',
        reminder => '训练',
        backup => '系统',
        _ => '其他',
      };
}

class NotificationRepository {
  NotificationRepository(this._db);

  final AppDatabase _db;

  /// 写一条消息。
  ///
  /// [refKey] 非空时**同一个 kind + refKey 只会有一条**（重复的静默丢掉）。
  /// 返回是否真的写进去了 —— 调用方可以据此决定要不要弹提示。
  Future<bool> add({
    required String kind,
    required String title,
    required String body,
    String? refKey,
    int? nowMs,
  }) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final String id = newUuid();
    await _db.into(_db.appNotification).insert(
          AppNotificationCompanion.insert(
            id: id,
            kind: kind,
            title: title,
            body: body,
            createdAtMs: now,
            refKey: Value<String?>(refKey),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    // ⚠️ **不能拿 `insert()` 的返回值判断"插进去没有"**：`INSERT OR IGNORE` 被唯一索引
    // 挡掉时，drift 返回的是 `last_insert_rowid()`，它仍是上一次插入的值 —— 会谎报成功
    // （这个坑是测试当场抓出来的：第二次 add 返回了 true，而表里其实只有一行）。
    // 所以按**这一行在不在**来判断：id 是每次新生成的，它在 → 这次真写进去了。
    final List<AppNotificationData> mine = await (_db.select(_db.appNotification)
          ..where(($AppNotificationTable t) => t.id.equals(id)))
        .get();
    return mine.isNotEmpty;
  }

  /// 最近的消息（新的在前）。
  Future<List<AppNotificationData>> list({int limit = 100}) => (_db.select(_db.appNotification)
        ..orderBy(<OrderClauseGenerator<$AppNotificationTable>>[
          ($AppNotificationTable t) => OrderingTerm(expression: t.createdAtMs, mode: OrderingMode.desc),
        ])
        ..limit(limit))
      .get();

  /// 某一类的消息（通知中心那排 chip 用）。`kind` 为 null = 全部。
  Future<List<AppNotificationData>> listOf(String? kind, {int limit = 100}) {
    final SimpleSelectStatement<$AppNotificationTable, AppNotificationData> q =
        _db.select(_db.appNotification);
    if (kind != null) {
      q.where(($AppNotificationTable t) => t.kind.equals(kind));
    }
    q
      ..orderBy(<OrderClauseGenerator<$AppNotificationTable>>[
        ($AppNotificationTable t) => OrderingTerm(expression: t.createdAtMs, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.get();
  }

  Future<int> unreadCount() async {
    final Expression<int> c = _db.appNotification.id.count();
    final TypedResult r = await (_db.selectOnly(_db.appNotification)
          ..addColumns(<Expression<Object>>[c])
          ..where(_db.appNotification.readAtMs.isNull()))
        .getSingle();
    return r.read(c) ?? 0;
  }

  Future<void> markAllRead({int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.appNotification)..where(($AppNotificationTable t) => t.readAtMs.isNull()))
        .write(AppNotificationCompanion(readAtMs: Value<int>(now)));
  }

  /// 清空（「删除全部数据」会调它；见 `deleteAllUserData`）。
  Future<void> clearAll() => _db.delete(_db.appNotification).go();
}
