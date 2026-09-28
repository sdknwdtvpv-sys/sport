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

class ExerciseSpec {
  const ExerciseSpec({
    required this.id,
    required this.weightIncrement,
    this.defaultWeightKg,
    this.defaultRestSec = 90,
    this.name = '',
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

  /// 自重动作：唯一可行的推进方式是加次数（或加秒数）。
  bool get isBodyweight => weightIncrement == 0;

  /// 按时长的动作：`reps` 这个数字表示**秒**。引擎对它们不说"次"。
  bool get isTime => isTimeTrack(trackType);

  /// 有重量的时长动作（负重平板支撑）：到时长上限时可以直接加重。
  bool get isWeightedTime => trackType == 'weight_time';
}

/// 计划项。
class PlanTarget {
  const PlanTarget({
    required this.targetSets,
    required this.targetRepsLow,
    required this.targetRepsHigh,
    this.targetWeightKg,
  });

  final int targetSets;
  final int targetRepsLow;
  final int targetRepsHigh;
  final double? targetWeightKg;
}

/// 上次同动作的表现。reps **只含正式组**，热身组由调用方过滤掉。
class LastSession {
  const LastSession({
    required this.reps,
    this.weightKg,
    this.daysAgo = 0,
  });

  final double? weightKg;
  final List<int> reps;
  final int daysAgo;

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
  final SetType setType;

  /// 自觉用力程度 RPE。**null = 用户没记**，这是默认状态。
  ///
  /// 规格（`docs/screens.md` S5）要求它以弱化样式存在、不主动教，
  /// 所以它只是个可选输入，不参与任何引擎判定 —— 计划进度、渐进建议、
  /// 破纪录判定都不看它。DB 的 `rpe` 列早就有了，只是领域模型一直没接。
  final double? rpe;

  double get volume => (weightKg ?? 0) * reps;
}

enum SetType {
  normal('normal'),
  warmup('warmup');

  const SetType(this.wire);
  final String wire;
}

/// 一次训练。
class Workout {
  Workout({required this.id, required this.startedAtMs, this.endedAtMs});

  final String id;
  final int startedAtMs;

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
