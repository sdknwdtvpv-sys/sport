/// 练了么 · **连续打卡保护（补签）的仓库**（2026-10-06，第二部分第 2 条）
///
/// 表定义与"为什么它是唯一一条关于历史的用户声明"写在 `db.dart` 的 `StreakProtection`。
/// 这里只做四件事：读全部 / 存一天 / 查某天有没有 / 清空。
///
/// **判据一概不在这里**（"能不能补签"是 `features/progress/streak_protection.dart`
/// 里的纯函数）—— 仓库只搬数据，界面只画，判据只在一个地方、有单测。
library;

import 'package:drift/drift.dart';

import 'db.dart';

class StreakProtectionRepository {
  StreakProtectionRepository(this._db);

  final AppDatabase _db;

  /// 全部被保护的日期（`YYYY-MM-DD`），**升序**。
  ///
  /// 返回 `Set` 而不是 `List`：调用方（连续天数的判定）永远只做"这一天在不在里面"，
  /// 而顺序在那里没有意义 —— 给它 `Set` 就不会有人不小心依赖某个顺序。
  Future<Set<String>> protectedDays() async {
    final List<StreakProtectionData> rows = await (_db.select(_db.streakProtection)
          ..orderBy(<OrderingTerm Function($StreakProtectionTable)>[
            (t) => OrderingTerm.asc(t.date),
          ]))
        .get();
    return <String>{for (final StreakProtectionData r in rows) r.date};
  }

  /// 被保护的日期，**按日期升序的列表**（界面要显示"其中 N 天是补签"时要数天数）。
  Future<List<String>> protectedDayList() async {
    final List<StreakProtectionData> rows = await (_db.select(_db.streakProtection)
          ..orderBy(<OrderingTerm Function($StreakProtectionTable)>[
            (t) => OrderingTerm.asc(t.date),
          ]))
        .get();
    return <String>[for (final StreakProtectionData r in rows) r.date];
  }

  /// 补签 [day] 那一天。**已经补过就什么都不做**（主键冲突不该是一个错误：
  /// 用户连点两下按钮是最常见的情况，而"这一天已被保护"本来就是同一个结果）。
  Future<void> protect(String day, {int? nowMs}) async {
    await _db.into(_db.streakProtection).insert(
          StreakProtectionData(
            date: day,
            createdAtMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<bool> isProtected(String day) async {
    final StreakProtectionData? row =
        await (_db.select(_db.streakProtection)..where((t) => t.date.equals(day)))
            .getSingleOrNull();
    return row != null;
  }

  /// 清空（「删除全部数据」会调它；见 `drift_local_store.deleteAllUserData`）。
  Future<void> clearAll() => _db.delete(_db.streakProtection).go();
}
