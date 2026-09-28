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
            // 可选的 RPE。DB 列早就有，以前一直没写值 —— 现在接上。
            rpe: r.rpe,
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
            // 结束时间与状态都要回写，否则 S7 之后再来一组就会把结束时间抹掉
            status: w.isFinished ? 'finished' : 'in_progress',
            startedAt: w.startedAtMs,
            endedAt: w.endedAtMs,
            totalVolume: w.totalVolume,
            totalSets: w.totalSets,
            createdAt: w.startedAtMs,
            updatedAt: w.endedAtMs ?? w.startedAtMs,
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
    return domain.Workout(
      id: row.id,
      startedAtMs: row.startedAt,
      endedAtMs: row.endedAt,
    )..sets.addAll(sets);
  }

  @override
  Future<List<domain.SetRecord>> allSets() async {
    final rows = await (_db.select(_db.setRecord)
          ..where((t) => t.setType.equals('normal') & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.completedAt)]))
        .get();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<List<domain.SetRecord>> setsForExercise(
    String exerciseId, {
    String? excludeWorkoutId,
  }) async {
    final rows = await (_db.select(_db.setRecord)
          ..where((t) =>
              t.exerciseId.equals(exerciseId) &
              t.setType.equals('normal') &
              t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.completedAt)]))
        .get();
    // 排除本次训练放在 Dart 里做：SQL 层的"取反"要用到 .not() / Constant(true)，
    // 而我无法在本机编译验证这些 API。筛选逻辑本身极便宜（单个动作的历史不过几十条），
    // 用确定能跑的形式换掉一次可能的编译失败是划算的。
    final filtered = excludeWorkoutId == null
        ? rows
        : rows.where((SetRecordData r) => r.workoutId != excludeWorkoutId).toList();
    return filtered.map(_toDomain).toList();
  }

  @override
  Future<List<String>> recentExerciseIds() async {
    final rows = await (_db.select(_db.setRecord)
          ..where((t) => t.setType.equals('normal') & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.completedAt)]))
        .get();
    if (rows.isEmpty) return const <String>[];

    final latestWorkoutId = rows.last.workoutId;
    final ids = <String>[];
    for (final SetRecordData r in rows) {
      if (r.workoutId == latestWorkoutId && !ids.contains(r.exerciseId)) {
        ids.add(r.exerciseId);
      }
    }
    return ids;
  }

  @override
  Future<domain.LastSession?> lastSessionFor(
    String exerciseId, {
    String? excludeWorkoutId,
  }) async {
    // 只取正式组；按完成时间升序，最后一条所在的那次训练就是"上次"。
    // excludeWorkoutId 排除本次训练（同一次里再次进入同一个动作时要用）。
    final rows = await (_db.select(_db.setRecord)
          ..where((t) {
            Expression<bool> cond = t.exerciseId.equals(exerciseId) &
                t.setType.equals('normal') &
                t.deletedAt.isNull();
            if (excludeWorkoutId != null) {
              cond = cond & t.workoutId.equals(excludeWorkoutId).not();
            }
            return cond;
          })
          ..orderBy([(t) => OrderingTerm.asc(t.completedAt)]))
        .get();
    if (rows.isEmpty) return null;

    final latestWorkoutId = rows.last.workoutId;
    final same = rows.where((SetRecordData r) => r.workoutId == latestWorkoutId).toList();
    return domain.LastSession(
      weightKg: same.last.weightKg,
      reps: same.map((SetRecordData r) => r.reps ?? 0).toList(),
      // 真实天数。以前这里漏了这个字段 → daysAgo 恒为 0 →
      // 引擎的 21 天回归保护（progression.dart 的 kStaleDays 分支）永远不触发。
      daysAgo: daysSince(same.last.completedAt),
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
        rpe: row.rpe,
      );

  @override
  Future<void> deleteAllUserData() async {
    // 整个清空放进一个事务：中途失败就整体回滚，不会留下"训练没了但组还在"的
    // 半残状态 —— 那比不删更糟，用户会以为删干净了。
    //
    // 删除顺序按"子 → 父"（组 → 训练项 → 训练），虽然这些表没有外键级联，
    // 但顺序符合直觉，将来加上外键也不会突然炸。
    await _db.transaction(() async {
      await _db.delete(_db.setRecord).go();
      await _db.delete(_db.workoutItem).go();
      await _db.delete(_db.workout).go();
      // 个人设置一并清掉：用户说"删除全部数据"就包括他的偏好开关。
      // 之后会回落到默认值（渐进建议开、单位默认、"帮助改进产品"开）。
      await _db.delete(_db.userProfile).go();
      // 还没发出去的埋点事件也必须清 —— 否则"删了数据"之后还会继续上报，
      // 这在合规上是明确不允许的。
      await _db.delete(_db.analyticsOutbox).go();
      // 身体数据（S12）同样是用户数据。新加表时最容易漏掉这一步，
      // 于是用户点了"删除全部数据"、体重还留在库里。
      await _db.delete(_db.bodyMetric).go();
      // 计划模板（S11）同样是用户数据
      await _db.delete(_db.routineItem).go();
      await _db.delete(_db.routine).go();
      // exercise（动作库）刻意不删：那是产品资产，不是用户数据，
      // 删了用户就没法再记录任何动作。
    });
  }
}
