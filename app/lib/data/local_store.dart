/// 练了么 · 本地存储
///
/// 生产实现是 **drift（SQLite）**，表结构见 `docs/data-model.md`，DDL 已可直接使用
/// （`seed/exercises.sql` 是动作库种子，已用 sqlite3 实测导入）。
///
/// 这里刻意只定义**接口 + 内存实现**：引入 drift 会带来 build_runner 代码生成，
/// 让 CI 首次运行多一个失败点，而当前阶段要验证的是"契约可执行"而不是持久化性能。
/// 接线 drift 时只需实现本接口，调用方一行不用改。
library;

import '../domain/models.dart';

abstract class LocalStore {
  Future<void> saveSet(SetRecord record);
  Future<void> deleteSet(String id);
  Future<List<SetRecord>> setsFor(String workoutId);
  Future<void> saveWorkout(Workout workout);
  Future<Workout?> loadWorkout(String id);

  /// 引擎的输入：某动作上一次训练的表现（只含正式组，最近一次训练的全部正式组）。
  Future<LastSession?> lastSessionFor(String exerciseId);
}

/// 内存实现。写入**同步生效**（先改内存再返回 Future），
/// 这样 widget 测试不需要 pumpAndSettle 就能断言结果。
class InMemoryLocalStore implements LocalStore {
  final Map<String, SetRecord> _sets = <String, SetRecord>{};
  final Map<String, Workout> _workouts = <String, Workout>{};

  /// 记录被删除的 id，供"撤销误触"的测试断言。
  final List<String> deletedIds = <String>[];

  @override
  Future<void> saveSet(SetRecord record) async {
    _sets[record.id] = record;
  }

  @override
  Future<void> deleteSet(String id) async {
    if (_sets.remove(id) != null) deletedIds.add(id);
  }

  @override
  Future<List<SetRecord>> setsFor(String workoutId) async =>
      _sets.values.where((s) => s.workoutId == workoutId).toList()
        ..sort((a, b) => a.setIndex.compareTo(b.setIndex));

  @override
  Future<void> saveWorkout(Workout workout) async {
    _workouts[workout.id] = workout;
  }

  @override
  Future<Workout?> loadWorkout(String id) async => _workouts[id];

  @override
  Future<LastSession?> lastSessionFor(String exerciseId) async {
    final all = _sets.values
        .where((s) => s.exerciseId == exerciseId && s.setType == SetType.normal)
        .toList()
      ..sort((a, b) => a.completedAtMs.compareTo(b.completedAtMs));
    if (all.isEmpty) return null;
    final latestWorkoutId = all.last.workoutId;
    final sameWorkout = all.where((s) => s.workoutId == latestWorkoutId).toList();
    return LastSession(
      weightKg: sameWorkout.last.weightKg,
      reps: sameWorkout.map((s) => s.reps).toList(),
    );
  }
}
