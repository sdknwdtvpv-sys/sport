/// 练了么 · 身体数据（S12）
///
/// 字段照 `docs/data-model.md` 的 `body_metric` DDL：体重 / 体脂 / 备注，**一天一条**。
///
/// 「一天一条」是在这一层保证的，**不是靠数据库唯一索引**：
/// 用户删掉某天的记录之后还要能重新录入同一天，唯一索引会让那次插入直接炸。
/// 所以这里的做法是"先按日期找，找到就改那一条"。
library;

import 'package:drift/drift.dart';

import '../core/units.dart';
import 'db.dart';

/// 日期的业务键：`YYYY-MM-DD`（本地时区）。
///
/// 用字符串而不是时间戳：用户说的"今天"是**日历上的今天**，
/// 用时间戳的话 23:50 和次日 00:10 会被判成两天，而用户认为是同一天。
String dayKey(DateTime d) => formatDateSortable(d);

/// 从系统健康库写进 `note` 的那句话 —— **来源必须留痕**。
///
/// 为什么非留不可：用户哪天把权限撤了、或者过半年回头看，得能一眼分辨
/// "这个 72.5 是我自己称的，还是体脂秤 App 写进健康库、我们抄过来的"。
/// 写进 `note` 而不是单开一列（2026-10-09 的取舍）：`body_metric` 加一列要动
/// schema、动备份格式（`kBackupFormat` 是长期稳定的形状），而 `note` 本来就会
/// 跟着备份走、本来就会在「最近记录」里显示。**代价说清楚**：这一句话占的是
/// 用户自己的备注栏，他改掉或删掉之后这个痕迹就没了 —— 所以合并**从不覆盖**
/// 用户已有的备注（见 [BodyMetricRepository.mergeHealthDays]）。
const String kHealthNote = '来自系统健康';

/// 健康库给**某一天**的体成分值（导入的输入）。身高不在这里 ——
/// 它不是每日指标，存在档案里，由 `ProfileRepository.setHeightCm` 单独处理。
class HealthDayValues {
  const HealthDayValues({
    required this.date,
    this.weightKg,
    this.bodyFatPct,
    this.waistCm,
  });

  /// `YYYY-MM-DD`（本地日），与库里的业务键同一个口径（[dayKey]）。
  final String date;
  final double? weightKg;
  final double? bodyFatPct;

  /// 腰围（cm）。2026-10-09（10.9 清单第 9 条）加 —— 与体重/体脂同属体成分，
  /// 共用同一道单独同意门，**不是**新的一类敏感数据。
  final double? waistCm;

  /// 至少有一个值才算"有内容"：只有日期的空壳不该被写进库。
  bool get hasContent =>
      weightKg != null || bodyFatPct != null || waistCm != null;
}

/// 一次导入的**逐日结果**。界面照它如实报数：
/// 不许把"跳过 N 天"说成"没有那天"，也不许把"补了一个字段"说成"新记了一天"。
class HealthMergeReport {
  const HealthMergeReport({
    this.days = 0,
    this.created = 0,
    this.filled = 0,
    this.unchanged = 0,
    this.skipped = 0,
  });

  /// 一共处理了几天。
  final int days;

  /// 我们原本**没有**那天 → 新建了一条。
  final int created;

  /// 那天已经有记录，我们**缺的字段**被补上了（"我们的字段不覆盖"）。
  final int filled;

  /// 那天已经有记录，系统里有的我们都有 → 一个字没动。
  final int unchanged;

  /// 看了但没动的其它情况：系统那天没值、或者那条记录**被用户删过**（不复活）。
  final int skipped;

  /// 真正被这次导入改动的天数（新建 + 补齐）。
  int get touched => created + filled;
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

  /// 把系统健康库的值**按天合并**进来（`docs/plan-health-sync.md` §三④）。
  ///
  /// 三条规则，每条都有理由：
  ///
  ///  1. **那天我们自己记过 → 我们的字段一个都不覆盖**，只补"我们缺的"。
  ///     体重与体脂**分开看**（只缺体脂就只补体脂）。`note` **永远不动**：
  ///     那是用户自己写的东西，我们凭什么替他改。
  ///  2. **那天只有系统有 → 新建一条，`note` 写 [kHealthNote]**（来源留痕，见那个常量）。
  ///  3. **整批在同一个事务里** —— 中途失败就整批回滚，不留"一半进来一半没进来"
  ///     （那会让用户对着一个说不清来源的库）。
  ///
  /// ⚠️ **不用 [save]**：它把每个字段都写成显式的 `Value(x)`，传 null 就是**擦掉**旧值
  /// （`note` 与 `deletedAt` 也会被一起重写）—— 那是"覆盖"，不是"合并"。
  ///
  /// ⚠️ **被用户软删除过的那天不复活**：`forDate` 会把它查出来（那是给"重新录入同一天"
  /// 用的），但我们不在用户删过的东西上做手脚 —— 记进 `skipped`，界面上会如实说
  /// "有 N 天没动"。
  Future<HealthMergeReport> mergeHealthDays(
    List<HealthDayValues> days, {
    int? nowMs,
  }) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    int created = 0;
    int filled = 0;
    int unchanged = 0;
    int skipped = 0;

    await _db.transaction(() async {
      for (int i = 0; i < days.length; i++) {
        final HealthDayValues d = days[i];
        if (!d.hasContent) {
          skipped++;
          continue;
        }
        final BodyMetricData? existing = await forDate(d.date);

        if (existing == null) {
          // id 里带上日期：一批里 now 是同一个值，只用 `bm_$now` 会撞成一模一样。
          await _db.into(_db.bodyMetric).insertOnConflictUpdate(
                BodyMetricCompanion(
                  id: Value<String>('bm_${now}_${i}_${d.date}'),
                  date: Value<String>(d.date),
                  weightKg: Value<double?>(d.weightKg),
                  bodyFatPct: Value<double?>(d.bodyFatPct),
                  // ⚠️ 这一列以前恒为 null（健康库当时只读体重/体脂/身高）——
                  // 10.9 清单第 9 条起腰围也读，缺的照样补
                  waistCm: Value<double?>(d.waistCm),
                  muscleMassKg: const Value<double?>(null),
                  note: const Value<String?>(kHealthNote),
                  updatedAt: Value<int>(now),
                  deletedAt: const Value<int?>(null),
                ),
              );
          created++;
          continue;
        }

        if (existing.deletedAt != null) {
          skipped++;
          continue;
        }

        final double? weight = existing.weightKg ?? d.weightKg;
        final double? bodyFat = existing.bodyFatPct ?? d.bodyFatPct;
        final double? waist = existing.waistCm ?? d.waistCm;
        if (weight == existing.weightKg &&
            bodyFat == existing.bodyFatPct &&
            waist == existing.waistCm) {
          unchanged++;
          continue;
        }

        await _db.into(_db.bodyMetric).insertOnConflictUpdate(
              BodyMetricCompanion(
                id: Value<String>(existing.id),
                date: Value<String>(existing.date),
                weightKg: Value<double?>(weight),
                bodyFatPct: Value<double?>(bodyFat),
                waistCm: Value<double?>(waist),
                muscleMassKg: Value<double?>(existing.muscleMassKg),
                // 用户的备注原样带回去 —— 合并**从不**碰它
                note: Value<String?>(existing.note),
                updatedAt: Value<int>(now),
                deletedAt: Value<int?>(existing.deletedAt),
              ),
            );
        filled++;
      }
    });

    return HealthMergeReport(
      days: days.length,
      created: created,
      filled: filled,
      unchanged: unchanged,
      skipped: skipped,
    );
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
