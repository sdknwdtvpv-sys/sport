/// 练了么 · LocalStore 的 drift 实现
///
/// 与 `InMemoryLocalStore` 实现同一个接口，行为必须完全一致 ——
/// 由 `test/local_store_contract_test.dart` 用**同一组断言**同时验证两者。
///
/// 注意 import 前缀：drift 生成的表类叫 `Workout` / `SetRecord`，
/// 领域模型里也有同名类（`domain.Workout` / `domain.SetRecord`），
/// 所以领域模型一律加 `domain.` 前缀，避免歧义。
library;

import 'package:drift/drift.dart';

import '../domain/models.dart' as domain;
import 'db.dart';
import 'local_store.dart';

class DriftLocalStore implements LocalStore {
  DriftLocalStore(this._db);

  final AppDatabase _db;

  @override
  Future<void> saveSet(domain.SetRecord r) async {
    // workout_item 是"某次训练里的某个动作"，由组记录派生。
    // 用确定性 id，保证同一 (workout, exercise) 反复写入不会产生重复行。
    final itemId = 'wi_${r.workoutId}_${r.exerciseId}';
    await _db.into(_db.workoutItem).insertOnConflictUpdate(
          WorkoutItemData(
            id: itemId,
            workoutId: r.workoutId,
            exerciseId: r.exerciseId,
            position: 0,
            updatedAt: r.completedAtMs,
          ),
        );

    await _db.into(_db.setRecord).insertOnConflictUpdate(
          SetRecordData(
            id: r.id,
            workoutId: r.workoutId,
            workoutItemId: itemId,
            exerciseId: r.exerciseId,
            setIndex: r.setIndex,
            setType: r.setType.wire,
            weightKg: r.weightKg,
            reps: r.reps,
            // 注意：withDefault() 只给 SQL 层加 DEFAULT，Dart 数据类里这些字段仍是 required，
            // 必须显式传。setType 同理（上面已传）。
            isPr: false,
            // volume 物化：weight × reps（自重动作 weight 为 null，容量记 0）
            volume: (r.weightKg ?? 0) * r.reps,
            completedAt: r.completedAtMs,
            updatedAt: r.completedAtMs,
          ),
        );
  }

  @override
  Future<void> deleteSet(String id) async {
    // 软删除：训练数据不物理删除，留痕可回溯
    await (_db.update(_db.setRecord)..where((t) => t.id.equals(id)))
        .write(SetRecordCompanion(
      deletedAt: Value(DateTime.now().millisecondsSinceEpoch),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  @override
  Future<List<domain.SetRecord>> setsFor(String workoutId) async {
    final rows = await (_db.select(_db.setRecord)
          ..where((t) => t.workoutId.equals(workoutId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.setIndex)]))
        .get();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<void> saveWorkout(domain.Workout w) async {
    // 领域模型 `Workout` 目前只有 id / startedAtMs / sets，没有 status。
    // 先把容量与组数物化进去，status 固定 in_progress；
    // 等 S7「训练结束总结」落地时领域模型会补上 status 与 endedAt。
    await _db.into(_db.workout).insertOnConflictUpdate(
          WorkoutData(
            id: w.id,
            status: 'in_progress',
            startedAt: w.startedAtMs,
            totalVolume: w.totalVolume,
            totalSets: w.totalSets,
            createdAt: w.startedAtMs,
            updatedAt: w.startedAtMs,
          ),
        );
  }

  @override
  Future<domain.Workout?> loadWorkout(String id) async {
    final row = await (_db.select(_db.workout)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) return null;
    final sets = await setsFor(id);
    return domain.Workout(id: row.id, startedAtMs: row.startedAt)
      ..sets.addAll(sets);
  }

  @override
  Future<domain.LastSession?> lastSessionFor(String exerciseId) async {
    // 只取正式组；按完成时间升序，最后一条所在的那次训练就是"上次"
    final rows = await (_db.select(_db.setRecord)
          ..where((t) =>
              t.exerciseId.equals(exerciseId) &
              t.setType.equals('normal') &
              t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.completedAt)]))
        .get();
    if (rows.isEmpty) return null;

    final latestWorkoutId = rows.last.workoutId;
    final same = rows.where((SetRecordData r) => r.workoutId == latestWorkoutId).toList();
    return domain.LastSession(
      weightKg: same.last.weightKg,
      reps: same.map((SetRecordData r) => r.reps ?? 0).toList(),
    );
  }

  domain.SetRecord _toDomain(SetRecordData row) => domain.SetRecord(
        id: row.id,
        workoutId: row.workoutId,
        exerciseId: row.exerciseId,
        setIndex: row.setIndex,
        reps: row.reps ?? 0,
        completedAtMs: row.completedAt,
        weightKg: row.weightKg,
        setType: row.setType == 'warmup' ? domain.SetType.warmup : domain.SetType.normal,
      );
}
