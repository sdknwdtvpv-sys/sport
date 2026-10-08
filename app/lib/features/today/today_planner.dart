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
import '../../core/last_time.dart';
import '../../core/units.dart';
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import '../../domain/models.dart';
import '../../domain/progression.dart';

/// 上肢日练的部位。
///
/// ⚠️ `arms` 也在里面：分化的构图里上肢日不单列手臂（推/拉的复合动作已经把它喂了），
/// 但用户**自己选**一个弯举来练时，最近一次训练就会被算成上肢 ——
/// 少了这一项，"上次练了手臂"会被误判成下肢，今天又给你排一次上肢。
const List<String> kUpperGroups = <String>['chest', 'back', 'shoulders', 'arms'];

/// 下肢日练的部位
const List<String> kLowerGroups = <String>['legs', 'core'];

/// **训练日的分化**（2026-10-04 从"6 部位轮转"改成上下肢 ×2）。
///
/// ## 为什么改（有证据，不是口味）
///
/// 循证区间是「**每块肌肉每周 12–20 组**」—— Baz-Valle 2022 系统综述+元分析的结论
/// （中等 12–20 组与高容量 >20 组在股四头肌 p=0.19、肱二头肌 p=0.59 上**没有差异**，
/// 也就是说超过 20 组只是白练加疲劳）；下限门槛「> 9 组/周」见 Schoenfeld 2017 元分析。
///
/// 而旧设计的实际产出是：1 个部位 × 3 个动作 × 3 组 = **9 组/次**，
/// 而轮转有 **6 个部位** —— 每周练 3–4 次的用户，同一块肌肉 **两周才轮到一次**，
/// 折合每肌群每周只有 **4.5–6 组**，不到门槛的一半。
///
/// 还有一条算术事实：6 块肌肉 × 12 组 = 72 组/周，3 练/周就是 24 组/次（≈8 个动作）。
/// 所以每周 3 练的人**不可能**把所有肌群都练进区间 —— 必须按复合动作聚集、
/// 让协同肌群靠间接量搭便车。这正是上下肢分化存在的原因。
enum TrainingDay {
  upper('上肢', 'upper'),
  lower('下肢', 'lower');

  const TrainingDay(this.label, this.wire);

  /// 中文名（界面直接显示"今天练 上肢"）
  final String label;

  /// 落库/埋点用的稳定标识
  final String wire;
}

/// **每个训练日的构图**：练哪些部位、各几个动作。
///
/// 组数按 3 组/动作算 —— 上肢 6 个 = 18 组、下肢 6 个 = 18 组，
/// 都过项目自己的「单次 ≥ 12 组」护栏。
///
/// 上肢不单列手臂：推与拉的复合动作已经把三头/二头喂了（复合动作的组数要算进协同肌群，
/// 这是 Baz-Valle 采用的计法）。下肢把核心放在后面收尾。
const Map<TrainingDay, List<({String group, int count})>> kDayComposition =
    <TrainingDay, List<({String group, int count})>>{
  TrainingDay.upper: <({String group, int count})>[
    (group: 'chest', count: 3),
    (group: 'back', count: 2),
    (group: 'shoulders', count: 1),
  ],
  TrainingDay.lower: <({String group, int count})>[
    (group: 'legs', count: 4),
    (group: 'core', count: 2),
  ],
};

/// **第一次训练只给 4 个动作（12 组）**。
///
/// 为什么不一上来就给 6 个：北极星是「首次打开 → 完成第一次训练」，
/// 而一屏 6 个动作的清单比 4 个更容易劝退。第 2 次起按完整分化给。
/// 12 组正好压在「单次 ≥ 12 组」那条护栏上 —— 不因为照顾新手就掉出去。
const int kFirstSessionExercises = 4;

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

/// 热身处方：**1 组 30–45 秒**。
///
/// 热身不是训练量：给 3 组会让人在正式组之前就累了，也把"练之前花两分钟"
/// 变成一件有负担的事。（`kDefaultTimePlan` 是 3 组，那是给平板支撑这类正式动作的。）
const PlanTarget kDefaultWarmupPlan = PlanTarget(
  targetSets: 1,
  targetRepsLow: 30,
  targetRepsHigh: 45,
);

/// 热身与拉伸的**人工定序**。
///
/// 为什么要人工写：库里 11 个热身 + 9 个拉伸的 `popularity` **全是 20**
/// （它们是 2026-09-29 从上游补库进来的长尾），按常用度排等于没排。
/// 真要自动排，得给它们加上"通用性"这类字段 —— 那是内容侧的事；
/// 在那之前，把"胸日先热肩"这种常识写在代码里，比随机挑一个诚实。
const Map<String, List<String>> _warmupByGroup = <String, List<String>>{
  'legs': <String>['ex_leg_swings_stretch', 'ex_high_knees'],
  'glutes': <String>['ex_leg_swings_stretch', 'ex_high_knees'],
  'core': <String>['ex_cat_cow_stretch', 'ex_bear_crawl'],
  // 推之前先把肩热开：胸/手臂自己没有热身动作，肩是它们最近的邻居
  'chest': <String>['ex_arm_circles'],
  'arms': <String>['ex_arm_circles'],
  'shoulders': <String>['ex_arm_circles'],
  // 拉之前先热脊椎
  'back': <String>['ex_cat_cow_stretch'],
};

/// 兜底（部位没匹配上时用）：全身性的、谁都做得来的两个
const List<String> _generalWarmup = <String>['ex_jumping_jack', 'ex_arm_circles'];

const Map<String, List<String>> _stretchByGroup = <String, List<String>>{
  'chest': <String>['ex_doorway_chest_stretch'],
  'back': <String>['ex_childs_pose'],
  'shoulders': <String>['ex_cross_body_shoulder_stretch'],
  'legs': <String>['ex_hamstring_stretch', 'ex_standing_quad_stretch'],
  'glutes': <String>['ex_butterfly_stretch'],
};

/// 兜底拉伸：背与腿，覆盖最常见的紧张部位
const List<String> _generalStretch = <String>['ex_childs_pose', 'ex_hamstring_stretch'];

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
PlanTarget defaultPlanFor(ExerciseData e) =>
    // 热身单独一档：1 组，别让它变成"训练量"（见 kDefaultWarmupPlan）
    e.category == 'warmup'
        ? kDefaultWarmupPlan
        : isDistanceTrack(e.trackType)
            ? distancePlanFor(e)
            : isTimeTrack(e.trackType)
                ? kDefaultTimePlan
                : kDefaultPlan;

/// 从"这次练了什么"里挑出该拉伸的部位。
///
/// **热身与拉伸本身不参选**：它们是准备/收尾动作，不是这次训练的重点。
/// 2026-09-30 真机走查时发现反例：一次"胸日"的训练里加了两个热身（绕臂/开合跳），
/// 用户先记了一组绕臂，拉伸建议就变成了**肩**——而该拉的是胸。
///
/// 取组数最多的那个部位：一次胸+三头里三头只做两组、胸做了九组，该拉的是胸。
/// 没练（或只有热身）时返回 null —— 调用方据此不显示拉伸块。
String? topMuscleGroupForStretch(
  Iterable<({String muscleGroup, String category})> trained,
) {
  final Map<String, int> byGroup = <String, int>{};
  for (final ({String muscleGroup, String category}) e in trained) {
    if (e.category == 'warmup' || e.category == 'stretch') continue;
    byGroup[e.muscleGroup] = (byGroup[e.muscleGroup] ?? 0) + 1;
  }
  if (byGroup.isEmpty) return null;
  return byGroup.entries
      .reduce((MapEntry<String, int> a, MapEntry<String, int> b) =>
          a.value >= b.value ? a : b)
      .key;
}

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
    if (s != null) {
      final String w = s.isBodyweight ? '自重' : formatWeight(s.weightKg, unit);
      return '$w × ${s.reps}${isTimeTrack(exercise.trackType) ? ' 秒' : ''}';
    }
    // 没有渐进建议时**念处方**，而不是留一个破折号。
    //
    // 破折号等于"这一行没有任何信息"，而用户此刻正需要知道做多久、做几组。
    // 两个真实的场景会走到这里：① 热身（本来就没有渐进建议，见 kDefaultWarmupPlan）；
    // ② 用户关掉了「渐进建议」开关 —— 那种情况下整页都不该变成一排破折号。
    // （2026-09-30 真机走查时发现：加进今天的热身显示成「—」。）
    final bool time = isTimeTrack(exercise.trackType);
    final String unit2 = time ? ' 秒' : ' 次';
    final String amount = plan.targetRepsLow == plan.targetRepsHigh
        ? '${plan.targetRepsLow}$unit2'
        : '${plan.targetRepsLow}–${plan.targetRepsHigh}$unit2';
    final double? planW = plan.targetWeightKg;
    final String load = planW == null ? '' : '${formatWeight(planW, unit)} · ';
    return '${plan.targetSets} 组 · $load$amount';
  }

  /// 「上次」那一行：把引擎据以判断的事实原样摆出来。没历史时返回 null。
  ///
  /// 次数在组间不一致时只报**最少**的那一组 —— 那正是引擎做判断用的口径，
  /// 报最大值会让用户觉得"我明明做到了 10 次，为什么还提示我保持重量"。
  /// 证据链那一行。**实现搬到 `core/last_time.dart` 了**（v1.53）：
  /// 训练屏也要念同一句话，两处各写一遍迟早会念得不一样。
  String? get historyLabel =>
      lastTimeLabel(lastSession, unit: unit, trackType: exercise.trackType);
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

  /// **今天轮到哪个训练日**（上下肢交替）。
  ///
  /// 规则：看**最近一次训练**练了哪些部位（`recentExerciseIds()` 只看最近那一次）——
  /// 只要碰到了上肢的部位，今天就是下肢；否则今天上肢。从没练过 → 上肢。
  ///
  /// 旧版在这里做的是"6 部位轮转里找第一个没练过的"，那不是交替而是**两周一轮**
  /// （见 [TrainingDay] 的注释里那笔组数账）。
  Future<TrainingDay> nextTrainingDay() async {
    final List<String> recentIds = await _store.recentExerciseIds();
    if (recentIds.isEmpty) return TrainingDay.upper;

    final Set<String> trained = <String>{};
    for (final String id in recentIds) {
      final ExerciseData? row = await _repo.byId(id);
      if (row != null) trained.add(row.muscleGroup);
    }
    if (trained.isEmpty) return TrainingDay.upper;
    final bool lastWasUpper = trained.any(kUpperGroups.contains);
    return lastWasUpper ? TrainingDay.lower : TrainingDay.upper;
  }

  /// **下一次练的第一个部位**（`docs/feature-backlog.md` 第 6 条：训练结束那条预告的输入）。
  ///
  /// 取"下一次那个训练日的构图里的第一个部位"——上肢日是 `chest`（3 个动作，份额最大）、
  /// 下肢日是 `legs`（4 个），于是文案念出来是「明天该练胸了 / 明天该练腿了」。
  /// 为什么不用 `TrainingDay.label`（"上肢/下肢"）：那是分化的名字，不是叫人练什么；
  /// 而"明天该练上肢了"在健身房里是句没信息量的话。
  ///
  /// **从没练过 → null**（不是"上肢"）：没有上一次，就没有"下一次"可言 ——
  /// 预告那条的口径是"宁可不排，也不编"。
  Future<String?> nextMuscleGroupKey() async {
    final List<String> recentIds = await _store.recentExerciseIds();
    if (recentIds.isEmpty) return null;
    final TrainingDay day = await nextTrainingDay();
    final List<({String group, int count})>? slots = kDayComposition[day];
    if (slots == null || slots.isEmpty) return null;
    return slots.first.group;
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

  /// 生成**今天**的计划（按上下肢分化）。
  ///
  /// [day] 不传就自动轮转（[nextTrainingDay]）。
  /// [count] 不传就按 [kDayComposition] 给（上肢 6 个 / 下肢 6 个）；
  ///   **第一次训练自动收成 [kFirstSessionExercises] 个**（引导页与轻量路径会显式传）。
  /// [firstTime] 只给测试用 —— 生产路径由"库里有没有正常组"推断。
  Future<List<PlannedExercise>> planToday({
    TrainingDay? day,
    int? count,
    WeightUnit unit = WeightUnit.kg,
    bool? firstTime,
  }) async {
    final TrainingDay d = day ?? await nextTrainingDay();
    final bool first = firstTime ?? (await _store.allSets()).isEmpty;
    final int full = kDayComposition[d]!
        .fold<int>(0, (int a, ({String group, int count}) s) => a + s.count);
    final int budget = count ?? (first ? kFirstSessionExercises : full);

    final List<PlannedExercise> out = <PlannedExercise>[];
    int left = budget;
    for (final ({String group, int count}) slot in kDayComposition[d]!) {
      if (left <= 0) break;
      final int take = slot.count < left ? slot.count : left;
      final List<PlannedExercise> picked =
          await planForGroup(muscleGroup: slot.group, count: take, unit: unit);
      out.addAll(picked);
      // 取不到就少一点（种子换过也不崩），但不把余量让给下一个部位 ——
      // 那会让"胸 3 个"变成"胸 5 个"，构图就没了。
      left -= take;
    }
    return out;
  }

  /// **一个部位的计划**。今天的分化按格调用它；测试也直接用它核"每个部位各自的不变量"
  /// （比如核心部位只该推按时长的动作）。
  ///
  /// 只从 `category: 'strength'` 里挑 —— 库里现在有热身（11 个）与拉伸（9 个），
  /// 它们也按部位归属（拉伸多半是腿），不挡的话「今天练什么」会推荐
  /// 「站姿股四头肌拉伸 × 3 组」。
  Future<List<PlannedExercise>> planForGroup({
    required String muscleGroup,
    int count = 3,
    WeightUnit unit = WeightUnit.kg,
    Set<String> exclude = const <String>{},
  }) async {
    final List<ExerciseData> rows = await _repo.search(
      muscleGroup: muscleGroup,
      category: 'strength',
      limit: count + exclude.length,
    );
    final List<ExerciseData> picked = rows
        .where((ExerciseData e) => !exclude.contains(e.id))
        .take(count)
        .toList();
    return _build(picked, unit: unit);
  }

  /// 把一批动作包成 `PlannedExercise`（逐动作查历史 + 交给引擎算建议）。
  Future<List<PlannedExercise>> _build(List<ExerciseData> rows,
      {required WeightUnit unit}) async {
    final List<PlannedExercise> out = <PlannedExercise>[];
    for (final ExerciseData e in rows) {
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

  /// 今日热身：练之前该做的那 1–2 个动作。
  ///
  /// 为什么要有它：库里 11 个热身动作在主流程里**一个都见不到** ——
  /// 「今天练什么」按 `category: 'strength'` 过滤，热身只能靠用户自己去
  /// 选动作页按类别筛。而热身是每次训练都该做的事，属于"写了内容却没人用得上"。
  ///
  /// 顺序：先按部位取（人工定序表），不够再补通用的，去重。
  /// 取不到的动作**直接跳过**（种子改了也不崩），所以返回值可能少于 [count]。
  Future<List<ExerciseData>> warmupFor({
    String? muscleGroup,
    int count = 2,
  }) async {
    final List<String> ids = <String>[
      ...?_warmupByGroup[muscleGroup],
      ..._generalWarmup,
    ];
    return _lookup(ids, 'warmup', count);
  }

  /// 练完该拉伸的那 1–2 个动作。口径同 [warmupFor]。
  Future<List<ExerciseData>> stretchFor({
    String? muscleGroup,
    int count = 2,
  }) async {
    final List<String> ids = <String>[
      ...?_stretchByGroup[muscleGroup],
      ..._generalStretch,
    ];
    return _lookup(ids, 'stretch', count);
  }

  /// 按 id 取动作，去重、校验类别、够 [count] 就停。
  ///
  /// 校验类别是刻意的：定序表里写错一个 id（或将来它被改成力量动作）时，
  /// 宁可少一个热身，也不要把一个力量动作塞进"热身"里。
  Future<List<ExerciseData>> _lookup(
    List<String> ids,
    String category,
    int count,
  ) async {
    final List<ExerciseData> out = <ExerciseData>[];
    final Set<String> seen = <String>{};
    for (final String id in ids) {
      if (out.length >= count) break;
      if (!seen.add(id)) continue;
      final ExerciseData? e = await _repo.byId(id);
      if (e == null || e.category != category) continue;
      out.add(e);
    }
    return out;
  }

  /// 「换一批」：同一个部位换一组动作。
  ///
  /// 「换一批」：**按原来的形状换** —— 同部位、同个数。
  ///
  /// 为什么按形状而不是按"今天的训练日"：这个方法的输入有两种 ——
  /// 主页那一份（上下肢构图）与 `planForGroup` 的结果（某一部位的 3 个）。
  /// 早期版本写死了"按今天的分化换"，于是换一份"核心 3 个"时会返回上肢的动作
  /// （`today_planner_test` 那条"换一批也不放热身/拉伸进来"当场红了）。
  ///
  /// 某个部位已经没有别的动作了就**保留原来那些**（不缩水），并尽量把个数补齐。
  Future<List<PlannedExercise>> reroll({
    required List<PlannedExercise> current,
    WeightUnit unit = WeightUnit.kg,
  }) async {
    if (current.isEmpty) return current;
    final Set<String> already =
        current.map((PlannedExercise p) => p.exercise.id).toSet();

    // 先按原来的顺序记住"每个部位几个"
    final List<String> order = <String>[];
    final Map<String, int> want = <String, int>{};
    final Map<String, List<PlannedExercise>> original =
        <String, List<PlannedExercise>>{};
    for (final PlannedExercise p in current) {
      final String g = p.exercise.muscleGroup;
      if (!want.containsKey(g)) {
        order.add(g);
        want[g] = 0;
        original[g] = <PlannedExercise>[];
      }
      want[g] = want[g]! + 1;
      original[g]!.add(p);
    }

    final List<PlannedExercise> out = <PlannedExercise>[];
    for (final String g in order) {
      final int n = want[g]!;
      final List<PlannedExercise> picked = await planForGroup(
        muscleGroup: g,
        count: n,
        unit: unit,
        exclude: already,
      );
      out.addAll(picked);
      already.addAll(picked.map((PlannedExercise p) => p.exercise.id));
      // 不够就用原来那些补齐 —— 换一批不该让计划缩水
      if (picked.length < n) {
        out.addAll(original[g]!.take(n - picked.length));
      }
    }
    return out;
  }
}


/// **手动换进来的动作与"今天这场"协不协同**（2026-10-08，10.8 清单第 5 条）。
///
/// 用户原话："如果在同一天的计划里，我手动改了一个完全没有协同作用的肌群动作，
/// 能否进行提示"。
///
/// 判据（纯函数，所以"什么算不协同"能被单测钉住）：
///   * 把"今天这场已经在练的肌群"（每个动作的主肌群 + 辅助肌群）合成一个集合；
///   * 把要换进来的动作的**主肌群**拿来比 —— **主肌群不在那个集合里**就算不协同；
///   * ⚠️ 只看**主肌群**：辅助肌群几乎每个动作都有两三个，用它比会把"腿 + 核心"
///     这种正常搭配也判成协同（那就等于这条提示永远不响）。
///
/// 返回 `null` = 没事（协同，或今天这场还没有别的动作可比）；否则返回**一句人话**：
/// 事实 + 一句去路，不说教、不带感叹号（与 `copy.md` 的口径一致）。
String? muscleSynergyWarning({
  required String pickedId,
  required String pickedMuscle,
  required List<({String id, String muscle, List<String> secondary})> session,
  Map<String, String> muscleNames = const <String, String>{},
}) {
  final List<({String id, String muscle, List<String> secondary})> others =
      session.where((({String id, String muscle, List<String> secondary}) e) => e.id != pickedId).toList();
  if (others.isEmpty || pickedMuscle.isEmpty) return null;
  final Set<String> today = <String>{
    for (final ({String id, String muscle, List<String> secondary}) e in others) e.muscle,
  };
  if (today.contains(pickedMuscle)) return null;
  final String Function(String) name = (String m) => muscleNames[m] ?? m;
  final String todayText = today.map(name).join('、');
  return '这个动作主要练${name(pickedMuscle)}，而今天这一场安排的是$todayText。';
}
