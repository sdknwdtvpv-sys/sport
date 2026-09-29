/// 练了么 ·「今天练什么」
///
/// 这是产品的第二个楔子：训记只回答"我练了什么"，我们还要回答"今天该练什么"。
/// 用户连计划都不用搭 —— 与"不抬高门槛"是同一条线。
///
/// 规则引擎本身在 `lib/domain/progression.dart`（纯 Dart，有 28 条共用向量守着）。
/// 这里只负责上一层：**今天轮到哪个部位、挑哪几个动作**，然后把每个动作交给引擎算建议。
///
/// 一期不上大模型，全部是可解释的规则：
///   1. 部位轮转：按固定顺序取"最近一次训练没练到的第一个部位"
///   2. 挑动作：该部位里按 popularity 取前 N 个（动作库已有常用度排序）
///   3. 给建议：逐动作查历史，交给引擎
library;

// db.dart（drift 表）与 models.dart（领域模型）都定义了 Workout / SetRecord，预先 hide。
import '../../data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import '../../core/units.dart';
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import '../../domain/models.dart';
import '../../domain/progression.dart';

/// 部位轮转顺序。练过没练过都按这个顺序找"下一个没练的"。
const List<String> kMuscleRotation = <String>[
  'chest',
  'back',
  'legs',
  'shoulders',
  'arms',
  'core',
];

/// 从动作库选中的动作默认用这个处方：3 组 8–10 次。
///
/// 简化：真实产品该按动作给不同区间（核心 3×12、平板支撑按秒等），
/// 那是 S11 计划模板的活儿。先统一，好让整条链路能跑通。
const PlanTarget kDefaultPlan = PlanTarget(
  targetSets: 3,
  targetRepsLow: 8,
  targetRepsHigh: 10,
);

/// 按时长动作（平板支撑 / 侧平板）的处方：**30–45 秒**。
///
/// 以前所有动作一律套 `kDefaultPlan`（3 组 × 8–10），于是平板支撑被开成
/// "3 组 × 8–10 次" —— 用户一眼就能看出这个 App 不懂健身。
/// 数字放在哪一列不变，含义由 `track_type` 决定。
const PlanTarget kDefaultTimePlan = PlanTarget(
  targetSets: 3,
  targetRepsLow: 30,
  targetRepsHigh: 45,
);

/// 距离动作的处方：**多少组 × 每组多少米**。
///
/// * 组数：有氧（category=cardio）是 **1 组** —— "3 组 5 公里跑"没有人这么练；
///   力量类的距离动作（农夫行走）是 3 组
/// * 距离：**来自种子**（`default_target_distance_m`），不在这里推导 ——
///   5 公里跑与 20 米农夫行走差两个数量级，任何默认值都是编数据
/// * 秒数（`targetRepsLow/High`）留 0：配速因人而异，距离处方只说"多少米"，
///   时长由用户在训练屏自己设（有历史时默认沿用上次）
PlanTarget distancePlanFor(ExerciseData e) => PlanTarget(
      targetSets: e.category == 'cardio' ? 1 : 3,
      targetRepsLow: 0,
      targetRepsHigh: 0,
      targetDistanceM: e.defaultTargetDistanceM,
    );

/// 按动作类型给默认处方。有计划模板（S11）时以模板里的为准。
PlanTarget defaultPlanFor(ExerciseData e) => isDistanceTrack(e.trackType)
    ? distancePlanFor(e)
    : isTimeTrack(e.trackType)
        ? kDefaultTimePlan
        : kDefaultPlan;

/// 一条推荐：动作 + 处方 + 引擎给的下一组建议。
class PlannedExercise {
  const PlannedExercise({
    required this.exercise,
    required this.plan,
    this.suggestion,
    this.lastSession,
    this.unit = WeightUnit.kg,
  });

  final ExerciseData exercise;
  final PlanTarget plan;

  /// null 表示"不给建议"（用户关掉了渐进建议）
  final Suggestion? suggestion;

  /// 引擎据以判断的**原始事实**：上一次这个动作练成什么样。
  ///
  /// 存下来只为了一件事：**把建议的证据摆到屏幕上**。建议不是黑箱 ——
  /// 用户能看见"上次 3 组 × 10 次 @ 60 kg"，因此这条建议是可解释、也是可反驳的
  /// （"这不是我上次记的" 本身就是一个有用的反馈信号）。
  final LastSession? lastSession;

  /// 显示单位。**引擎给的建议值始终是 kg**，这里只影响怎么念。
  final WeightUnit unit;

  /// UI 上直接显示的一行，如「62.5 kg × 8」；自重动作显示「自重 × 8」。
  ///
  /// 按时长动作的数字是**秒**：显示「自重 × 30 秒」而不是「自重 × 30」——
  /// 后者会被读成 30 次。
  String get loadLabel {
    final Suggestion? s = suggestion;
    if (s == null) return '—';
    final String w = s.isBodyweight ? '自重' : formatWeight(s.weightKg, unit);
    return '$w × ${s.reps}${isTimeTrack(exercise.trackType) ? ' 秒' : ''}';
  }

  /// 「上次」那一行：把引擎据以判断的事实原样摆出来。没历史时返回 null。
  ///
  /// 次数在组间不一致时只报**最少**的那一组 —— 那正是引擎做判断用的口径，
  /// 报最大值会让用户觉得"我明明做到了 10 次，为什么还提示我保持重量"。
  String? get historyLabel {
    final LastSession? last = lastSession;
    if (last == null || last.completedSets == 0) return null;
    final String w =
        last.weightKg == null ? '自重' : formatWeight(last.weightKg, unit);
    final String u = isTimeTrack(exercise.trackType) ? '秒' : '次';
    final String reps = last.reps.toSet().length == 1
        ? '${last.minReps} $u'
        : '最少 ${last.minReps} $u';
    return '上次 ${last.completedSets} 组 · $w × $reps';
  }
}

/// 计划模板里的一项：哪个动作 + 什么处方。
class RoutineEntry {
  const RoutineEntry({required this.exerciseId, required this.plan});

  final String exerciseId;
  final PlanTarget plan;
}

class TodayPlanner {
  TodayPlanner({
    required ExerciseRepository repository,
    required LocalStore store,
  })  : _repo = repository,
        _store = store;

  final ExerciseRepository _repo;
  final LocalStore _store;

  /// 今天该练哪个部位。
  ///
  /// 规则：取最近一次训练练过的所有部位，然后在轮转顺序里找**第一个没练过的**。
  /// 全练过了（或从没练过）就回到轮转的第一个。
  Future<String> nextMuscleGroup() async {
    final List<String> recentIds = await _store.recentExerciseIds();
    if (recentIds.isEmpty) return kMuscleRotation.first;

    final Set<String> trained = <String>{};
    for (final String id in recentIds) {
      final ExerciseData? row = await _repo.byId(id);
      if (row != null) trained.add(row.muscleGroup);
    }

    for (final String g in kMuscleRotation) {
      if (!trained.contains(g)) return g;
    }
    return kMuscleRotation.first;
  }

  /// 生成今天的建议。
  ///
  /// [muscleGroup] 传 null 时自动做部位轮转；[count] 是要推荐几个动作。
  /// 计划模板里的一项在"交接给引擎"时的形状（S11）。
  ///
  /// 刻意不复用 `RoutineItemData`：planner 不该知道数据库长什么样，
  /// 它只要「哪个动作 + 什么处方」。
  Future<List<PlannedExercise>> planFromRoutine({
    required List<RoutineEntry> entries,
    WeightUnit unit = WeightUnit.kg,
  }) async {
    final List<PlannedExercise> out = <PlannedExercise>[];
    for (final RoutineEntry e in entries) {
      final ExerciseData? ex = await _repo.byId(e.exerciseId);
      // 动作被删掉了就跳过这一项，不让整份计划作废
      if (ex == null) continue;
      final LastSession? last = await _store.lastSessionFor(e.exerciseId);
      out.add(PlannedExercise(
        exercise: ex,
        plan: e.plan,
        unit: unit,
        lastSession: last,
        suggestion: suggestNext(
          exercise: _repo.specOf(ex),
          plan: e.plan,
          lastSession: last,
        ),
      ));
    }
    return out;
  }

  Future<List<PlannedExercise>> planToday({
    int count = 3,
    String? muscleGroup,
    WeightUnit unit = WeightUnit.kg,
  }) async {
    final String group = muscleGroup ?? await nextMuscleGroup();
    final List<ExerciseData> candidates =
        // category: 'strength' —— **只从力量动作里挑**。
        // 库里现在有热身（12 个）与拉伸（9 个），它们也会按部位归属（拉伸多半是腿），
        // 不挡的话「今天练什么」会推荐「站姿股四头肌拉伸 × 3 组」。
        // 距离类动作现在**可以**被推荐了：处方能表达"3 组 × 20 米"（见 distancePlanFor）。
        // 有氧仍然不会出现 —— 它靠 category 挡着（推荐只挑 strength）。
        await _repo.search(muscleGroup: group, category: 'strength', limit: count);

    final List<PlannedExercise> out = <PlannedExercise>[];
    for (final ExerciseData e in candidates) {
      final LastSession? last = await _store.lastSessionFor(e.id);
      final PlanTarget plan = defaultPlanFor(e);
      out.add(PlannedExercise(
        exercise: e,
        plan: plan,
        unit: unit,
        lastSession: last,
        suggestion: suggestNext(
          exercise: _repo.specOf(e),
          plan: plan,
          lastSession: last,
        ),
      ));
    }
    return out;
  }

  /// 「换一批」：同一个部位换一组动作。
  ///
  /// 简化：一期直接沿用部位、只换动作（靠 limit 放大后跳过已推荐过的）。
  /// 真正的"换一批"应当换部位或换组合，那是后续迭代。
  Future<List<PlannedExercise>> reroll({
    required List<PlannedExercise> current,
    int count = 3,
    WeightUnit unit = WeightUnit.kg,
  }) async {
    if (current.isEmpty) return planToday(count: count, unit: unit);
    final String group = current.first.exercise.muscleGroup;
    final List<ExerciseData> all =
        // 「换一批」也必须是 strength：这是最容易被漏掉的一处 ——
        // 它取回的是**整组**（limit 60）再跳过已推荐的，
        // 热身/拉伸不挡的话，常用度排完一定会轮到它们。
        await _repo.search(
            muscleGroup: group, category: 'strength', limit: 60);
    final Set<String> already = current
        .map((PlannedExercise p) => p.exercise.id)
        .toSet();
    final List<ExerciseData> next = all
        .where((ExerciseData e) => !already.contains(e.id))
        .take(count)
        .toList();
    if (next.isEmpty) return current; // 没有再多的了，保持原样

    final List<PlannedExercise> out = <PlannedExercise>[];
    for (final ExerciseData e in next) {
      final LastSession? last = await _store.lastSessionFor(e.id);
      final PlanTarget plan = defaultPlanFor(e);
      out.add(PlannedExercise(
        exercise: e,
        plan: plan,
        // unit 以前在这里漏了：用户选了 lb，「换一批」之后又变回 kg —— 同一屏两种单位。
        unit: unit,
        lastSession: last,
        suggestion: suggestNext(
          exercise: _repo.specOf(e),
          plan: plan,
          lastSession: last,
        ),
      ));
    }
    return out;
  }
}
