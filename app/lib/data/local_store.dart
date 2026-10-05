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

/// 距某个时间点过了几天（向下取整，未来时间归 0）。
///
/// 为什么做成共享函数而不是两个实现各写一遍：`LastSession.daysAgo` 是引擎
/// 「21 天回归保护」（`progression.dart` 的 `kStaleDays` 分支）的唯一输入，
/// 两个实现必须算出同一个数 —— 契约测试对两者跑同一组断言。
///
/// 这个字段曾经**两个实现都漏了**，于是 `daysAgo` 恒为默认值 0，
/// 回归保护永远不触发 —— 写在 `PRODUCT.md` §6 的一条承诺从来没生效过。
int daysSince(int fromMs, {int? nowMs}) {
  final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final int diff = now - fromMs;
  return diff <= 0 ? 0 : diff ~/ Duration.millisecondsPerDay;
}

/// 未结束的训练会话只会有**一行**，固定用这个 id。
const String kActiveSessionId = 'local';

abstract class LocalStore {
  Future<void> saveSet(SetRecord record);
  Future<void> deleteSet(String id);
  Future<List<SetRecord>> setsFor(String workoutId);

  /// **回收站**（2026-10-04）：被软删除的组，最近删的在前。
  ///
  /// 为什么要有它：`deleteSet` 一直是**软删除**（只写 `deletedAt`），
  /// 但全仓**没有任何恢复入口** —— 训练中长按撤销之后，那组就永远取不回来了。
  /// 而项目自己写着"数据丢失是工具类死刑"（`PRODUCT.md` §10.5），
  /// 对手最集中的抱怨也正是数据丢失。**留痕不留出路，等于没留。**
  Future<List<DeletedSet>> deletedSets({int limit = 200});

  /// 从回收站恢复一组（清掉 `deletedAt`）。
  ///
  /// ⚠️ **不发埋点**：这是罕见的数据找回动作，不是可用性信号；而多发一个事件
  /// 就要同步中英政策 + 隐私事实表 + 两张商店表单
  /// （`tool/privacy-audit.mjs` 会把代码里多发的事件判红）。理由留在这里，
  /// 免得下次有人"顺手补上"。
  Future<void> restoreSet(String id);

  Future<void> saveWorkout(Workout workout);
  Future<Workout?> loadWorkout(String id);

  /// 引擎的输入：某动作上一次训练的表现（只含正式组，最近一次训练的全部正式组）。
  ///
  /// [excludeWorkoutId] 用来排除**本次**训练：同一次训练里再次进入同一个动作时，
  /// 不排除就会把"两秒前刚记的组"当成"上次"，引擎据此说出"上次 3 组达标 → +2.5kg"。
  ///
  /// 返回值里的 `daysAgo` 必须是**真实天数** —— 引擎靠它做回归保护。
  Future<LastSession?> lastSessionFor(
    String exerciseId, {
    String? excludeWorkoutId,
  });

  /// 保存"还没结束的训练会话"（2026-10-01）。
  ///
  /// 每次记一组、每换一个动作都会重写它 —— 所以实现要**足够便宜**（一行 upsert）。
  /// 训练正常结束（回到总结页）时由调用方清掉；App 被杀掉时它就留在库里，
  /// 下次冷启动据此把用户送回训练屏。
  Future<void> saveActiveSession(ActiveSession session);

  /// 读出未结束的会话（没有就返回 null）。
  Future<ActiveSession?> activeSession();

  /// 训练结束（或用户明确不练了）时清掉。
  Future<void> clearActiveSession();

  /// 全部正式组，按完成时间升序。用于「我」页的训练统计与数据导出。
  Future<List<SetRecord>> allSets();

  /// 某动作的正式组（跨训练）。[excludeWorkoutId] 用来排除本次训练 ——
  /// S7 判定"这次破纪录了吗"必须排除本次，否则每次都是纪录。
  Future<List<SetRecord>> setsForExercise(
    String exerciseId, {
    String? excludeWorkoutId,
  });

  /// 最近一次训练里练到的动作 id（去重，按首次出现顺序）。
  ///
  /// "今天练什么"要做部位轮转，就必须知道上次练了哪些部位 ——
  /// 而部位要拿动作 id 去动作库换，所以这里只返回 id。
  Future<List<String>> recentExerciseIds();

  /// **动作置顶**（收藏）的 id，**按用户定的顺序**。
  ///
  /// 为什么它在这个接口里（而不是 `user_profile` 那条偏好通道）：用它的两处都只拿着
  /// 一个 `LocalStore` —— 选择器（S3）要按它分「置顶」区，备份要把它写进文件。
  /// 而它又不是标量偏好，是一份有顺序的集合，所以落库形态是一张自己的表。
  Future<List<String>> pinnedExerciseIds();

  /// 整体替换置顶清单（顺序即数组顺序）。**不做增量**：这是一份 3–5 项的小清单，
  /// 整体写既简单又不会出现"取消一半"的中间态。
  Future<void> setPinnedExerciseIds(List<String> ids);

  /// 删除**全部用户数据**（S10「我 → 数据与备份 → 删除全部数据」）。
  ///
  /// 只清用户自己产生的数据 —— 训练、组记录、个人设置。**动作库不动**：
  /// 内置的 318 个动作是产品资产、不是用户数据，删了就再也记不了。
  ///
  /// 是**硬删除**，不是软删除。用户按下"删除全部数据"的语义就是"真的没了"；
  /// 只打 `deleted_at` 标记等于骗自己，也过不了《个人信息保护法》第四十七条
  /// 要求的"删除"。
  ///
  /// 调用方随后必须刷新界面 —— 内存里的会话状态不会自己失效。
  Future<void> deleteAllUserData();
}

/// 内存实现。写入**同步生效**（先改内存再返回 Future），
/// 这样 widget 测试不需要 pumpAndSettle 就能断言结果。
class InMemoryLocalStore implements LocalStore {
  final Map<String, SetRecord> _sets = <String, SetRecord>{};
  final Map<String, Workout> _workouts = <String, Workout>{};

  /// 未结束的会话（契约测试对两个实现跑同一组断言，所以这里必须与 drift 行为一致）
  ActiveSession? _active;

  @override
  Future<void> saveActiveSession(ActiveSession session) async {
    _active = session;
  }

  @override
  Future<ActiveSession?> activeSession() async => _active;

  @override
  Future<void> clearActiveSession() async {
    _active = null;
  }

  /// 记录被删除的 id，供"撤销误触"的测试断言。
  final List<String> deletedIds = <String>[];

  /// 回收站：软删除的组挪到这里，`restoreSet` 再挪回去。
  final Map<String, DeletedSet> _bin = <String, DeletedSet>{};

  /// 动作置顶（顺序即列表顺序）
  final List<String> _pinned = <String>[];

  @override
  Future<void> saveSet(SetRecord record) async {
    _sets[record.id] = record;
  }

  @override
  Future<void> deleteSet(String id) async {
    final SetRecord? gone = _sets.remove(id);
    if (gone == null) return;
    deletedIds.add(id);
    _bin[id] = DeletedSet(set: gone, deletedAtMs: DateTime.now().millisecondsSinceEpoch);
  }

  @override
  Future<List<DeletedSet>> deletedSets({int limit = 200}) async =>
      (_bin.values.toList()
            ..sort((DeletedSet a, DeletedSet b) => b.deletedAtMs.compareTo(a.deletedAtMs)))
          .take(limit)
          .toList();

  @override
  Future<void> restoreSet(String id) async {
    final DeletedSet? back = _bin.remove(id);
    if (back == null) return;
    _sets[id] = back.set;
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
  Future<Workout?> loadWorkout(String id) async {
    final w = _workouts[id];
    if (w == null) return null;
    // 必须把组记录一并带回 —— 否则与 DriftLocalStore 的行为不一致，
    // 契约测试会立刻抓到（这正是那份契约存在的意义）。
    final sets = await setsFor(id);
    return Workout(id: w.id, startedAtMs: w.startedAtMs)..sets.addAll(sets);
  }

  @override
  Future<List<SetRecord>> allSets() async {
    final all = _sets.values
        .where((s) => s.setType == SetType.normal)
        .toList()
      ..sort((a, b) => a.completedAtMs.compareTo(b.completedAtMs));
    return all;
  }

  @override
  Future<List<SetRecord>> setsForExercise(
    String exerciseId, {
    String? excludeWorkoutId,
  }) async {
    final all = _sets.values
        .where((s) =>
            s.exerciseId == exerciseId &&
            s.setType == SetType.normal &&
            (excludeWorkoutId == null || s.workoutId != excludeWorkoutId))
        .toList()
      ..sort((a, b) => a.completedAtMs.compareTo(b.completedAtMs));
    return all;
  }

  @override
  Future<List<String>> recentExerciseIds() async {
    final all = _sets.values
        .where((s) => s.setType == SetType.normal)
        .toList()
      ..sort((a, b) => a.completedAtMs.compareTo(b.completedAtMs));
    if (all.isEmpty) return const <String>[];

    final latestWorkoutId = all.last.workoutId;
    final ids = <String>[];
    for (final s in all) {
      if (s.workoutId == latestWorkoutId && !ids.contains(s.exerciseId)) {
        ids.add(s.exerciseId);
      }
    }
    return ids;
  }

  @override
  Future<List<String>> pinnedExerciseIds() async =>
      List<String>.unmodifiable(_pinned);

  @override
  Future<void> setPinnedExerciseIds(List<String> ids) async {
    _pinned
      ..clear()
      ..addAll(ids);
  }

  @override
  Future<LastSession?> lastSessionFor(
    String exerciseId, {
    String? excludeWorkoutId,
  }) async {
    final all = _sets.values
        .where((s) =>
            s.exerciseId == exerciseId &&
            s.setType == SetType.normal &&
            (excludeWorkoutId == null || s.workoutId != excludeWorkoutId))
        .toList()
      ..sort((a, b) => a.completedAtMs.compareTo(b.completedAtMs));
    if (all.isEmpty) return null;
    final latestWorkoutId = all.last.workoutId;
    final sameWorkout = all.where((s) => s.workoutId == latestWorkoutId).toList();
    return LastSession(
      weightKg: sameWorkout.last.weightKg,
      reps: sameWorkout.map((s) => s.reps).toList(),
      distances: sameWorkout.map((s) => s.distanceM).toList(),
      daysAgo: daysSince(sameWorkout.last.completedAtMs),
    );
  }

  @override
  Future<void> deleteAllUserData() async {
    _active = null; // 未结束的会话也算用户状态（与 drift 实现保持一致）
    _sets.clear();
    _workouts.clear();
    _pinned.clear(); // 置顶也是用户数据（"删除全部数据"之后它必须真的没了）
  }
}
