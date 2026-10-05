/// 练了么 · 身体数据（S12）
///
/// 字段照 `docs/data-model.md` 的 `body_metric` DDL：体重 / 体脂 / 备注，**一天一条**。
///
/// 「一天一条」是在这一层保证的，**不是靠数据库唯一索引**：
/// 用户删掉某天的记录之后还要能重新录入同一天，唯一索引会让那次插入直接炸。
/// 所以这里的做法是"先按日期找，找到就改那一条"。
library;

import 'package:drift/drift.dart';

import 'db.dart';

/// 日期的业务键：`YYYY-MM-DD`（本地时区）。
///
/// 用字符串而不是时间戳：用户说的"今天"是**日历上的今天**，
/// 用时间戳的话 23:50 和次日 00:10 会被判成两天，而用户认为是同一天。
String dayKey(DateTime d) {
  final String m = d.month.toString().padLeft(2, '0');
  final String day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

class BodyMetricRepository {
  BodyMetricRepository(this._db);

  final AppDatabase _db;

  /// 找某一天的记录。**包含已软删除的** —— 重新录入同一天时要把它复活，
  /// 而不是撞 id。是否算"有效记录"由调用方按 `deletedAt` 判断。
  Future<BodyMetricData?> forDate(String date) =>
      (_db.select(_db.bodyMetric)..where((t) => t.date.equals(date)))
          .getSingleOrNull();

  /// 最近一条**有效**记录（按日期降序）。没有任何记录返回 null。
  Future<BodyMetricData?> latest() async {
    final List<BodyMetricData> rows = await (_db.select(_db.bodyMetric)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy(<OrderingTerm Function($BodyMetricTable)>[
            (t) => OrderingTerm.desc(t.date),
          ])
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// 最近若干天的**有效**记录，按日期降序。
  Future<List<BodyMetricData>> recent({int limit = 30}) =>
      (_db.select(_db.bodyMetric)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy(<OrderingTerm Function($BodyMetricTable)>[
              (t) => OrderingTerm.desc(t.date),
            ])
            ..limit(limit))
          .get();

  /// **全部有效记录**，按日期升序（老的在前）。
  ///
  /// 为什么升序：它只给**备份**用（`collectBackup`），而写进 JSON 的顺序
  /// 最好与"人翻记录"的顺序一致 —— 导回来之后时间线还是顺着读的。
  /// 软删除的（还在回收站里）**不算**：备份是"有效数据"的副本，
  /// 与训练记录同一个口径（`allSets()` 也只给有效组）。
  Future<List<BodyMetricData>> all() =>
      (_db.select(_db.bodyMetric)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy(<OrderingTerm Function($BodyMetricTable)>[
              (t) => OrderingTerm.asc(t.date),
            ]))
          .get();

  /// 保存某天的身体数据。同一天再存就是**改那一条**，不会变成两条。
  Future<BodyMetricData> save({
    required String date,
    double? weightKg,
    double? bodyFatPct,
    /// 腰围（cm）。2026-10-05（v20）加的 —— 与体重共享同一道单独同意门。
    double? waistCm,
    /// 骨骼肌量（kg）。同上。
    double? muscleMassKg,
    String? note,
    int? nowMs,
    String? id,
  }) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final BodyMetricData? existing = await forDate(date);

    // id 沿用已存在的那条（哪怕它被软删除过）；否则新建。
    // 这样"重新录入同一天"是复活，而不是产生第二条。
    final String rowId = existing?.id ?? (id ?? 'bm_$now');

    // id 沿用已存在的那条（哪怕它被软删除过）；否则新建一条。
    // 这样"重新录入同一天"是复活，而不是产生第二条。
    // ⚠️ 必须用 **Companion** 而不是直接传 BodyMetricData。
    //
    // drift 在 insert/upsert 时对 DataClass 用 `nullToAbsent: true`：
    // 字段是 null 就**当作"这次没提供"而跳过**，冲突时保留旧值。
    // 于是"软删除过的记录重新录入同一天"会复活失败 —— deletedAt 没被清掉，
    // 用户会发现记录保存了却查不到（这个坑我自己踩了一次，是测试抓出来的）。
    // Companion + `Value(x)` 才是"显式写这个值，哪怕是 null"。
    await _db.into(_db.bodyMetric).insertOnConflictUpdate(
          BodyMetricCompanion(
            id: Value<String>(rowId),
            date: Value<String>(date),
            weightKg: Value<double?>(weightKg),
            bodyFatPct: Value<double?>(bodyFatPct),
            waistCm: Value<double?>(waistCm),
            muscleMassKg: Value<double?>(muscleMassKg),
            note: Value<String?>(note),
            updatedAt: Value<int>(now),
            // 显式清掉删除标记 = 复活
            deletedAt: const Value<int?>(null),
          ),
        );

    return (await forDate(date))!;
  }

  /// 软删除某一天。训练数据不留白，身体数据同理 —— 误删还能查回来。
  Future<void> delete(String id, {int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.bodyMetric)..where((t) => t.id.equals(id)))
        .write(BodyMetricCompanion(
      deletedAt: Value<int>(now),
      updatedAt: Value<int>(now),
    ));
  }

  /// 有效记录条数。用于测试与「我」页的统计。
  Future<int> count() async {
    final List<BodyMetricData> rows = await (_db.select(_db.bodyMetric)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    return rows.length;
  }
}
