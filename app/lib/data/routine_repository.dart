/// 练了么 · 计划模板（S11）
///
/// 字段照 `docs/data-model.md` 的 `routine` / `routine_item` DDL。
/// **简化版只有动作 + 组数 + 次数区间**（规格 S11 明确说的），
/// `targetWeightKg`（NULL = 交给规则引擎）与 `restSec` 照建但这一版不暴露编辑入口。
///
/// ⚠️ 改表结构之后必须重跑代码生成，否则分析会报 "Target of URI doesn't exist"。
library;

import 'package:drift/drift.dart';
import '../domain/models.dart' show PlanTarget;

import '../core/uuid.dart';
import 'db.dart';

class RoutineRepository {
  RoutineRepository(this._db);

  final AppDatabase _db;

  // ---------- 计划本身 ----------

  /// 全部未删除的计划，最近更新的在前。
  Future<List<RoutineData>> routines() => (_db.select(_db.routine)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy(<OrderingTerm Function($RoutineTable)>[
          (t) => OrderingTerm.desc(t.updatedAt),
        ]))
      .get();

  Future<RoutineData?> byId(String id) => (_db.select(_db.routine)
        ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
      .getSingleOrNull();

  /// 新建一个空计划。
  /// 建一份计划。
  ///
  /// [source] 回答"它从哪来"（2026-10-01 起真的用上了）：
  ///   * `user` —— 用户自己一条一条建的（默认）；
  ///   * `builtin` —— 从**内置模板**建的（`plan_templates.dart`）；
  ///   * `suggested` —— 把**当天的建议**存成了计划。
  /// 三者在界面上都是普通计划（可改可删）；这个字段只用来回答
  /// "新手到底用不用模板"这种问题 —— 没有它就只能猜。
  Future<RoutineData> create(String name, {String source = 'user', int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final RoutineData row = RoutineData(
      // ⚠️ 用 UUID 而不是时间戳。最初写的是 'r_$now'，测试里在同一毫秒建两个计划
      // 直接撞主键（UNIQUE constraint failed）—— 这正是 data-model.md 那句
      // 「客户端生成 UUID 主键」要避免的事。
      id: newPrefixedId('r'),
      name: name.trim(),
      source: source,
      isActive: false,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.routine).insert(row);
    return row;
  }

  /// 从一份"动作 + 处方"清单**一次性**建出计划（2026-10-01）。
  ///
  /// 内置模板与"把今天的建议存成计划"共用这一条路径 —— 两条各写一遍的话，
  /// 迟早一条会漏掉 `position`、另一条忘了 `_touch`。
  /// 顺序按传进来的顺序落 `position`；`source` 由调用方给（builtin / suggested）。
  Future<RoutineData> createFromPlan(
    String name,
    List<({String exerciseId, PlanTarget plan})> items, {
    String source = 'user',
    int? nowMs,
  }) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final RoutineData routine = await create(name, source: source, nowMs: now);
    for (final ({String exerciseId, PlanTarget plan}) it in items) {
      // addItem 的签名是 (routineId, exerciseId, {...})，position 由它自己按现有项续号 ——
      // 这里按顺序调用即可（顺序就是落库顺序）。
      await addItem(
        routine.id,
        it.exerciseId,
        targetSets: it.plan.targetSets,
        targetRepsLow: it.plan.targetRepsLow,
        targetRepsHigh: it.plan.targetRepsHigh,
        nowMs: now,
      );
    }
    return routine;
  }

  Future<void> rename(String id, String name, {int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.routine)..where((t) => t.id.equals(id)))
        .write(RoutineCompanion(
      name: Value<String>(name.trim()),
      updatedAt: Value<int>(now),
    ));
  }

  /// 软删除。计划里的项**不跟着删** —— 万一用户是想恢复，
  /// 重新建同名计划时那些项还在（项按 routine_id 关联，查的时候会过滤掉父计划）。
  Future<void> delete(String id, {int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.routine)..where((t) => t.id.equals(id)))
        .write(RoutineCompanion(
      deletedAt: Value<int>(now),
      updatedAt: Value<int>(now),
    ));
  }

  // ---------- 计划里的项 ----------

  /// 某个计划的全部项，按 position 升序。
  Future<List<RoutineItemData>> items(String routineId) =>
      (_db.select(_db.routineItem)
            ..where((t) => t.routineId.equals(routineId) & t.deletedAt.isNull())
            ..orderBy(<OrderingTerm Function($RoutineItemTable)>[
              (t) => OrderingTerm.asc(t.position),
            ]))
          .get();

  /// 往计划里加一个动作，排在最后。
  ///
  /// **同一个动作在同一计划里可以出现两次**（有人喜欢练两组不同强度的卧推），
  /// 所以不按 exercise_id 去重。
  Future<RoutineItemData> addItem(
    String routineId,
    String exerciseId, {
    int targetSets = 3,
    int targetRepsLow = 8,
    int targetRepsHigh = 10,
    int? nowMs,
  }) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final List<RoutineItemData> existing = await items(routineId);
    final RoutineItemData row = RoutineItemData(
      // 同样用 UUID：序号 + 时间戳在"同一毫秒加两项"时仍会撞
      id: newPrefixedId('ri'),
      routineId: routineId,
      exerciseId: exerciseId,
      position: existing.length,
      targetSets: targetSets,
      targetRepsLow: targetRepsLow,
      targetRepsHigh: targetRepsHigh,
      restSec: 90,
      updatedAt: now,
    );
    await _db.into(_db.routineItem).insert(row);
    await _touch(routineId, now);
    return row;
  }

  /// 改组数 / 次数区间。**只有这三项可改** —— 简化版的全部范围。
  Future<void> updateItem(
    String itemId, {
    int? targetSets,
    int? targetRepsLow,
    int? targetRepsHigh,
    int? nowMs,
  }) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final RoutineItemData? item = await (_db.select(_db.routineItem)
          ..where((t) => t.id.equals(itemId)))
        .getSingleOrNull();
    if (item == null) return;

    await (_db.update(_db.routineItem)..where((t) => t.id.equals(itemId)))
        .write(RoutineItemCompanion(
      targetSets: targetSets == null ? const Value.absent() : Value<int>(targetSets),
      targetRepsLow:
          targetRepsLow == null ? const Value.absent() : Value<int>(targetRepsLow),
      targetRepsHigh:
          targetRepsHigh == null ? const Value.absent() : Value<int>(targetRepsHigh),
      updatedAt: Value<int>(now),
    ));
    await _touch(item.routineId, now);
  }

  Future<void> removeItem(String itemId, {int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final RoutineItemData? item = await (_db.select(_db.routineItem)
          ..where((t) => t.id.equals(itemId)))
        .getSingleOrNull();
    if (item == null) return;

    await (_db.update(_db.routineItem)..where((t) => t.id.equals(itemId)))
        .write(RoutineItemCompanion(
      deletedAt: Value<int>(now),
      updatedAt: Value<int>(now),
    ));
    await _touch(item.routineId, now);
  }

  /// 计划改动之后更新它的 updatedAt，好让列表按"最近改过"排序。
  Future<void> _touch(String routineId, int now) async {
    await (_db.update(_db.routine)..where((t) => t.id.equals(routineId)))
        .write(RoutineCompanion(updatedAt: Value<int>(now)));
  }
}
