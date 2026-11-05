/// 练了么 · 周期化计划落库（Ultra 权益 10，v32）
///
/// 与 `routine_repository.dart` / `day_plan_repository.dart` 同一个写法：
/// 构造时拿 `AppDatabase`，方法里读写 drift，**不缓存**。
///
/// 推进/加重/完成判定的算术**一行都不在这里**（在 `lib/domain/periodization.dart` 的纯函数里）；
/// 这一层只负责"把那份快照搬进/搬出两张表"和"按纯函数的结果写 current_week"。
library;

import 'package:drift/drift.dart';

import '../domain/models.dart' show SetRecord;
import '../domain/periodization.dart';
import 'db.dart' hide SetRecord;

class PeriodPlanRepository {
  PeriodPlanRepository(this._db);

  final AppDatabase _db;

  static String _sessionId(String planId, int week, PeriodSessionSpec s) =>
      '$planId-w$week-day${s.day}-p${s.position}';

  Future<PeriodPlanSnapshot?> _load(String planId) async {
    final PeriodPlanData? row = await (_db.select(_db.periodPlan)
          ..where((PeriodPlan t) => t.id.equals(planId)))
        .getSingleOrNull();
    if (row == null) return null;
    final List<PeriodPlanSessionData> sessions = await (_db.select(_db.periodPlanSession)
          ..where((PeriodPlanSession t) => t.planId.equals(planId))
          ..orderBy(<OrderingTerm Function(PeriodPlanSession)>[
            (PeriodPlanSession t) => OrderingTerm.asc(t.week),
            (PeriodPlanSession t) => OrderingTerm.asc(t.day),
            (PeriodPlanSession t) => OrderingTerm.asc(t.position),
          ]))
        .get();
    return PeriodPlanSnapshot(
      id: row.id,
      name: row.name,
      weeks: row.weeks,
      daysPerWeek: row.daysPerWeek,
      startDate: DateTime.parse(row.startDate),
      currentWeek: row.currentWeek,
      status: PeriodPlanStatus.fromWire(row.status),
      sessions: <PeriodSessionSpec>[
        for (final PeriodPlanSessionData s in sessions)
          PeriodSessionSpec(
            week: s.week,
            day: s.day,
            position: s.position,
            exerciseId: s.exerciseId,
            targetSets: s.targetSets,
            repsLow: s.repsLow,
            repsHigh: s.repsHigh,
            targetWeightKg: s.targetWeightKg,
          ),
      ],
    );
  }

  /// 当前 active 计划（最多一份）。没有就 null。
  Future<PeriodPlanSnapshot?> activePlan() async {
    final PeriodPlanData? row = await (_db.select(_db.periodPlan)
          ..where((PeriodPlan t) => t.status.equals(PeriodPlanStatus.active.wire))
          ..orderBy(<OrderingTerm Function(PeriodPlan)>[
            (PeriodPlan t) => OrderingTerm.desc(t.updatedAt),
          ])
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    return _load(row.id);
  }

  Future<PeriodPlanSnapshot?> byId(String id) => _load(id);

  /// 新建一份计划：**先归档当前 active 的**（不删数据），再把 `baseSessions`（第 1 周模板）
  /// 按 `targetWeightForWeek` 展开成每一周写库。
  ///
  /// `baseSessions` 的 `week` 会被忽略（一律按第 1 周模板处理）。
  Future<PeriodPlanSnapshot> createPlan({
    required String name,
    required int weeks,
    required int daysPerWeek,
    required DateTime startDate,
    required List<PeriodSessionSpec> baseSessions,
    int? nowMs,
  }) async {
    if (!<int>{4, 6, 8}.contains(weeks)) {
      throw ArgumentError('weeks 只能是 4/6/8');
    }
    if (daysPerWeek != 3 && daysPerWeek != 4) {
      throw ArgumentError('daysPerWeek 只能是 3/4');
    }
    if (baseSessions.isEmpty) throw ArgumentError('课表不能为空');
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final String id = 'pp_$now';
    final String start = '${startDate.year}-'
        '${startDate.month.toString().padLeft(2, '0')}-'
        '${startDate.day.toString().padLeft(2, '0')}';
    await _db.transaction(() async {
      await (_db.update(_db.periodPlan)
            ..where((PeriodPlan t) => t.status.equals(PeriodPlanStatus.active.wire)))
          .write(PeriodPlanCompanion(
        status: Value<String>(PeriodPlanStatus.archived.wire),
        updatedAt: Value<int>(now),
      ));
      await _db.into(_db.periodPlan).insert(PeriodPlanData(
            id: id,
            name: name,
            weeks: weeks,
            daysPerWeek: daysPerWeek,
            startDate: start,
            currentWeek: 1,
            status: PeriodPlanStatus.active.wire,
            createdAt: now,
            updatedAt: now,
          ));
      for (int w = 1; w <= weeks; w += 1) {
        for (final PeriodSessionSpec s in baseSessions) {
          await _db.into(_db.periodPlanSession).insert(PeriodPlanSessionData(
                id: _sessionId(id, w, s),
                planId: id,
                week: w,
                day: s.day,
                position: s.position,
                exerciseId: s.exerciseId,
                targetSets: s.targetSets,
                repsLow: s.repsLow,
                repsHigh: s.repsHigh,
                targetWeightKg: targetWeightForWeek(s.targetWeightKg, w),
                updatedAt: now,
              ));
        }
      }
    });
    return (await _load(id))!;
  }

  /// 打开计划/首页时调：按本周完成度决定是否推进（纯函数算，这里只写结果）。
  Future<PeriodPlanSnapshot> refreshProgress(PeriodPlanSnapshot plan, List<SetRecord> sets) async {
    final PeriodAdvanceResult r = advanceAfterWeek(plan: plan, sets: sets);
    if (r.currentWeek == plan.currentWeek && r.status == plan.status) return plan;
    await (_db.update(_db.periodPlan)
          ..where((PeriodPlan t) => t.id.equals(plan.id)))
        .write(PeriodPlanCompanion(
      currentWeek: Value<int>(r.currentWeek),
      status: Value<String>(r.status.wire),
      updatedAt: Value<int>(DateTime.now().millisecondsSinceEpoch),
    ));
    return (await _load(plan.id))!;
  }

  /// 归档（换计划/用户主动结束）。数据保留，不删。
  Future<void> archive(String planId, {int? nowMs}) async {
    await (_db.update(_db.periodPlan)
          ..where((PeriodPlan t) => t.id.equals(planId)))
        .write(PeriodPlanCompanion(
      status: Value<String>(PeriodPlanStatus.archived.wire),
      updatedAt: Value<int>(nowMs ?? DateTime.now().millisecondsSinceEpoch),
    ));
  }

  /// 导入一份解析好的计划：归档当前 active，生成新 id/时间戳后落库。
  Future<PeriodPlanSnapshot> importPlan(PeriodPlanSnapshot parsed, {int? nowMs}) {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return createPlan(
      name: parsed.name,
      weeks: parsed.weeks,
      daysPerWeek: parsed.daysPerWeek,
      startDate: parsed.startDate,
      baseSessions: parsed.sessions.where((PeriodSessionSpec s) => s.week == 1).toList(),
      nowMs: now,
    );
  }

  /// "删除全部数据"用。
  Future<void> deleteAll() async {
    await _db.transaction(() async {
      await _db.delete(_db.periodPlanSession).go();
      await _db.delete(_db.periodPlan).go();
    });
  }
}
