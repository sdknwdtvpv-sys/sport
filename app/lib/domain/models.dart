/// 练了么 · 纯 Dart 领域模型
///
/// 本文件（及同目录的 progression.dart、tap_meter.dart）**刻意不 import flutter**。
/// 这样领域逻辑既能被 flutter test 跑，也能被纯 dart test 跑，
/// 更重要是：它不需要 widget 环境就能验证，CI 里跑得飞快。
library;

import 'dart:math' as math;

import '../core/units.dart';

/// 动作库条目的领域视图。只需要引擎用得上的三个字段。
/// 这个 `track_type` 的数字是不是**秒**而不是次数。
///
/// 词表本身见 `docs/data-model.md`。判定刻意只留这一处 ——
/// 引擎、planner、界面都问它，避免三处各写一遍 `== 'time'` 而慢慢分叉。
bool isTimeTrack(String trackType) =>
    trackType == 'time' || trackType == 'weight_time';

/// 这个动作的"重量"是不是**助力**（辅助引体/双杠）。
///
/// 辅助动作的推进方向与负重**相反**：越练越强 = 助力越少。
/// 把它当负重推，用户看到的是"越练越轻松"，而系统以为在进步。
bool isAssistedTrack(String trackType) => trackType == 'assisted_reps';

/// 这个动作记不记**距离**。
///
/// `distance_time` 的数字仍是秒（沿用 time 那一列的约定，不另开一列），
/// 但多带一个 `distance_m`。跑步机、划船机、跳绳、农夫行走都是它。
///
/// ⚠️ 它与 `isTimeTrack` **不重叠**：距离动作不走"加秒数"的推进
/// （引擎对它们不给建议，见 `progression.dart` 的说明），
/// 所以判定必须分开问，不能图省事把 distance_time 并进 isTimeTrack。
bool isDistanceTrack(String trackType) => trackType == 'distance_time';

class ExerciseSpec {
  const ExerciseSpec({
    required this.id,
    required this.weightIncrement,
    this.defaultWeightKg,
    this.defaultRestSec = 90,
    this.name = '',
    this.category = 'strength',
    this.trackType = 'weight_reps',
  });

  final String id;

  /// 加重步长。0 表示自重动作 —— 由数据层不变量保证此时 defaultWeightKg 为 null。
  final double weightIncrement;

  /// 怎么记这个动作（`docs/data-model.md` 的词表）：
  ///
  /// * `weight_reps`（缺省）—— 负重次数
  /// * `reps_only`  —— 自重次数
  /// * `time`       —— **按时长**（平板支撑、侧平板）：数字是**秒**不是次数
  /// * `weight_time`—— 负重时长（负重平板支撑）
  ///
  /// 缺省值是 `weight_reps`，所以没有这个字段的老数据、老 fixture 行为完全不变。
  /// 上游 `bryllim/workout-guide` 的 `exerciseType` 是同一件事的更细版本
  /// （多出 `distance_duration` / `assisted_bodyweight`），映射表见
  /// `【9月28日竞品分析】` 附录 E.3。
  final String trackType;

  /// 该动作零历史时的起始重量。null = 自重。
  final double? defaultWeightKg;

  /// 默认组间休息秒数。来自动作库的 default_rest_sec。
  final int defaultRestSec;

  final String name;

  /// strength | warmup | stretch（`docs/data-model.md`）。
  ///
  /// 缺省 `strength`：老 fixture、老调用点行为完全不变。
  /// 「今天练什么」只从 strength 里挑 —— 这一条是 `today_planner` 的职责，
  /// 引擎本身不关心类别（热身和拉伸也有可能要走推进建议）。
  final String category;

  /// 自重动作：唯一可行的推进方式是加次数（或加秒数）。
  bool get isBodyweight => weightIncrement == 0;

  /// 是不是力量动作 —— **推荐规则的唯一判据**。
  bool get isStrength => category == 'strength';

  /// 按时长的动作：`reps` 这个数字表示**秒**。引擎对它们不说"次"。
  bool get isTime => isTimeTrack(trackType);

  /// 有重量的时长动作（负重平板支撑）：到时长上限时可以直接加重。
  bool get isWeightedTime => trackType == 'weight_time';

  /// 记距离的动作（有氧、农夫行走）。
  bool get isDistance => isDistanceTrack(trackType);

  /// "重量"是助力的动作（辅助引体/双杠）。
  bool get isAssisted => isAssistedTrack(trackType);
}

/// 计划项。
/// 一次**还没结束**的训练会话（2026-10-01）。
///
/// **它解决的事**：健身房里的中断 —— 接个电话、切到微信、系统把 App 杀掉。
/// 组记录一直都会落库（那是资产），但"练到第几个动作、休息还剩多久"原先只在内存里，
/// 回来就没了。用户看到的是：又回到首页，刚才那次像没发生过。
///
/// 存的东西**刚好够重建那一屏**：哪个训练、哪几个动作（含处方）、当前第几个、
/// 以及休息到什么时候（记的是**绝对时间戳**，不是剩余秒数 —— 被杀掉的那几分钟
/// 也该算进休息里，而不是"回来接着从 90 秒倒数"）。
///
/// 只允许一行：本机同时只会有一次未结束的训练（`kActiveSessionId`）。
class ActiveSession {
  const ActiveSession({
    required this.workoutId,
    required this.entries,
    required this.startedAtMs,
    this.index = 0,
    this.restEndsAtMs,
    this.source = 'home_button',
  });

  final String workoutId;
  final List<ActiveEntry> entries;

  /// 当前在第几个动作（0 起）
  final int index;

  /// 休息结束的**绝对**毫秒时间戳；不在休息中就是 null
  final int? restEndsAtMs;

  final int startedAtMs;

  /// 从哪条路开始的（home_button / suggestion / picker / light）——
  /// 恢复时按原样上报，漏斗口径不变。
  final String source;

  int get length => entries.length;

  ActiveSession copyWith({int? index, int? restEndsAtMs, bool clearRest = false}) =>
      ActiveSession(
        workoutId: workoutId,
        entries: entries,
        startedAtMs: startedAtMs,
        index: index ?? this.index,
        restEndsAtMs: clearRest ? null : (restEndsAtMs ?? this.restEndsAtMs),
        source: source,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'workout_id': workoutId,
        'index': index,
        'rest_ends_at': restEndsAtMs,
        'started_at': startedAtMs,
        'source': source,
        'entries': <Object?>[for (final ActiveEntry e in entries) e.toJson()],
      };

  static ActiveSession? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? list = raw['entries'];
    if (list is! List || list.isEmpty) return null;
    final List<ActiveEntry> entries = <ActiveEntry>[];
    for (final Object? item in list) {
      final ActiveEntry? e = ActiveEntry.fromJson(item);
      if (e != null) entries.add(e);
    }
    if (entries.isEmpty) return null;
    return ActiveSession(
      workoutId: (raw['workout_id'] ?? '').toString(),
      entries: entries,
      index: (raw['index'] is num) ? (raw['index'] as num).toInt() : 0,
      restEndsAtMs:
          (raw['rest_ends_at'] is num) ? (raw['rest_ends_at'] as num).toInt() : null,
      startedAtMs:
          (raw['started_at'] is num) ? (raw['started_at'] as num).toInt() : 0,
      source: (raw['source'] ?? 'home_button').toString(),
    );
  }
}

/// 会话里的一个动作：练哪个 + 什么处方。
class ActiveEntry {
  const ActiveEntry({required this.exerciseId, required this.plan});

  final String exerciseId;
  final PlanTarget plan;

  Map<String, Object?> toJson() => <String, Object?>{
        'exercise_id': exerciseId,
        'sets': plan.targetSets,
        'reps_low': plan.targetRepsLow,
        'reps_high': plan.targetRepsHigh,
      };

  static ActiveEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final String id = (raw['exercise_id'] ?? '').toString();
    if (id.isEmpty) return null;
    int intOf(Object? v, int fallback) => v is num ? v.toInt() : fallback;
    return ActiveEntry(
      exerciseId: id,
      plan: PlanTarget(
        targetSets: intOf(raw['sets'], 3),
        targetRepsLow: intOf(raw['reps_low'], 8),
        targetRepsHigh: intOf(raw['reps_high'], 12),
      ),
    );
  }
}

class PlanTarget {
  const PlanTarget({
    required this.targetSets,
    required this.targetRepsLow,
    required this.targetRepsHigh,
    this.targetWeightKg,
    this.targetDistanceM,
  });

  final int targetSets;

  /// 次数；`time` / `distance_time` 动作装的是**秒**
  final int targetRepsLow;
  final int targetRepsHigh;
  final double? targetWeightKg;

  /// **距离处方：每组多少米**。只有 `distance_time` 动作有值。
  ///
  /// 有了它，「今天练什么」才敢推荐农夫行走这类动作 ——
  /// 之前它"能记但不被推荐"，因为处方只有次数与秒数两种形态，开不出"走 20 米"。
  final double? targetDistanceM;
}

/// 上次同动作的表现。reps **只含正式组**，热身组由调用方过滤掉。
class LastSession {
  const LastSession({
    required this.reps,
    this.weightKg,
    this.distances,
    this.daysAgo = 0,
  });

  final double? weightKg;
  final List<int> reps;

  /// 上次各组记的距离（米），与 [reps] 一一对应。null = 那一组没记距离。
  ///
  /// 有氧动作靠它做两件事：
  ///   1. 训练屏的默认值（"今天还跑上次那么多" → 一次点击就是一组）
  ///   2. 证据链那一行念「上次 5.0 公里 · 30:00」而不是「自重 × 1800 秒」
  /// 缺省 null 而不是空列表：老调用点（几十个 fixture）不传就是"不记距离"，
  /// 与空列表同义，但不用改它们。
  final List<double?>? distances;

  final int daysAgo;

  /// 上次最后一组的距离。null = 上次没记（或这个动作不记距离）。
  double? get lastDistanceM {
    final List<double?>? d = distances;
    if (d == null || d.isEmpty) return null;
    return d.last;
  }

  /// 上次最远的一组 —— 有氧的"最好成绩"是里程，不是次数。
  double? get maxDistanceM {
    final List<double?>? d = distances;
    if (d == null) return null;
    double? best;
    for (final double? v in d) {
      if (v == null) continue;
      if (best == null || v > best) best = v;
    }
    return best;
  }

  int get completedSets => reps.length;

  int get minReps => reps.isEmpty ? 0 : reps.reduce(math.min);
}

enum ProgressionMode {
  doubleProgression('double'),
  linear('linear'),
  off('off');

  const ProgressionMode(this.wire);
  final String wire;

  static ProgressionMode fromWire(String? v) =>
      ProgressionMode.values.firstWhere((e) => e.wire == v, orElse: () => ProgressionMode.doubleProgression);
}

class UserProfile {
  const UserProfile({
    this.progressionMode = ProgressionMode.doubleProgression,
    this.unit = WeightUnit.kg,
    this.restOverrideSec,
  });

  final ProgressionMode progressionMode;

  /// 显示单位。**存储与引擎始终是 kg**（见 core/units.dart 的设计说明），
  /// 所以这个字段只影响界面怎么念数字。
  final WeightUnit unit;

  /// 用户指定的休息时长（秒）。**null = 跟随动作自带的值**，这是默认。
  ///
  /// 为什么不干脆一律用它：种子里各动作差异很大（核心 45s、深蹲 180s），
  /// 统一覆盖会把这份真实信息抹掉。所以默认是"跟随动作"，用户明确选了
  /// 具体秒数才全局覆盖 —— 那是他自己的选择。
  final int? restOverrideSec;
}

/// 用户的一次手动修改。overrides 由调用方按动作过滤好，最新在前。
class ManualOverride {
  const ManualOverride({required this.weightKg, required this.reps});
  final double weightKg;
  final int reps;
}

/// 建议理由的粗粒度枚举。UI 依据它的 wire 值做埋点拆分，reasonText 才是给人看的。
enum ReasonCode {
  firstTime('first_time'),
  linearProgress('linear_progress'),
  hold('hold'),
  addRep('add_rep'),
  deload('deload'),
  userPreferred('user_preferred');

  const ReasonCode(this.wire);
  final String wire;

  static ReasonCode? fromWire(String? v) {
    for (final e in ReasonCode.values) {
      if (e.wire == v) return e;
    }
    return null;
  }
}

/// 一条建议。weightKg 为 null 表示自重（UI 显示「自重 × N」）。
class Suggestion {
  const Suggestion({
    required this.weightKg,
    required this.reps,
    required this.reasonCode,
    required this.reasonText,
  });

  final double? weightKg;
  final int reps;
  final ReasonCode reasonCode;
  final String reasonText;

  bool get isBodyweight => weightKg == null;
}

/// 一条已记录的组。
class SetRecord {
  const SetRecord({
    required this.id,
    required this.workoutId,
    required this.exerciseId,
    required this.setIndex,
    required this.reps,
    required this.completedAtMs,
    this.weightKg,
    this.distanceM,
    this.setType = SetType.normal,
    this.rpe,
  });

  final String id;
  final String workoutId;
  final String exerciseId;
  final int setIndex;
  final int reps;
  final int completedAtMs;
  final double? weightKg;

  /// 距离（**米**）。只有 `distance_time` 的动作会写它，其余恒为 null。
  ///
  /// null 与 0 是两件事：null = 这个动作不记距离（或老记录没这个字段），
  /// 0 = 记了，而且是"没动"。
  final double? distanceM;

  final SetType setType;

  /// 自觉用力程度 RPE。**null = 用户没记**，这是默认状态。
  ///
  /// 规格（`docs/screens.md` S5）要求它以弱化样式存在、不主动教，
  /// 所以它只是个可选输入，不参与任何引擎判定 —— 计划进度、渐进建议、
  /// 破纪录判定都不看它。DB 的 `rpe` 列早就有了，只是领域模型一直没接。
  final double? rpe;

  /// 容量。**距离动作恒为 0**：它的"次数"是秒，拿重量乘秒数没有量纲意义
  /// （与 drift_local_store 里物化的那份保持一致，两处口径必须一样）。
  double get volume => hasDistance ? 0 : (weightKg ?? 0) * reps;

  /// 有距离的组：有氧与农夫行走。容量（重量 × 次数）对它们没有意义，
  /// 它们该看的是**里程与配速**（见 features/progress 的呈现）。
  bool get hasDistance => distanceM != null;
}

/// 回收站里的一条：被软删除的组 + 删除时间（2026-10-04）。
///
/// 为什么单独包一层、而不给 [SetRecord] 加个 `deletedAt`：领域模型是"活着的记录"，
/// 而回收站要的是"活着的记录 + 它什么时候被删的"——后者只有库里有。
/// 混进 [SetRecord] 会让每个构造点都要多想一次"这个字段该填什么"。
class DeletedSet {
  const DeletedSet({required this.set, required this.deletedAtMs});

  final SetRecord set;

  /// 删除时刻（毫秒）。回收站按它倒序，界面按它显示"什么时候删的"。
  final int deletedAtMs;
}

enum SetType {
  normal('normal'),
  warmup('warmup');

  const SetType(this.wire);
  final String wire;
}

/// 一次训练。
class Workout {
  Workout({
    required this.id,
    required this.startedAtMs,
    this.endedAtMs,
    this.note,
  });

  final String id;
  final int startedAtMs;

  /// 这次训练的一句话（2026-10-04 接上）。
  ///
  /// 列从第一天起就在（`workout.note`），`progress_screen` 也一直在显示它 ——
  /// 但**没有任何写入路径**，是个死字段。训记的「训记备忘录 / 过往心得」就是它，
  /// 而它的价值比"备忘"大：它是"为什么这次没加重"的原始解释（引擎只看数字，
  /// 数字解释不了"昨天没睡好"）。
  String? note;

  /// 结束时间。null = 还在进行中（S7 训练结束总结会把它填上）。
  int? endedAtMs;

  final List<SetRecord> sets = <SetRecord>[];

  bool get isFinished => endedAtMs != null;

  /// 训练时长。算不出来时返回 null —— UI 要显示「—」而不是 0。
  Duration? get duration {
    final int? end = endedAtMs;
    if (end == null || end <= startedAtMs) return null;
    return Duration(milliseconds: end - startedAtMs);
  }

  int get totalSets => sets.where((s) => s.setType == SetType.normal).length;

  double get totalVolume =>
      sets.where((s) => s.setType == SetType.normal).fold<double>(0, (a, s) => a + s.volume);

  int get totalVolumeKg => totalVolume.round();
}
