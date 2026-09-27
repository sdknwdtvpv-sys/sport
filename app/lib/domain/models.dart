/// 练了么 · 纯 Dart 领域模型
///
/// 本文件（及同目录的 progression.dart、tap_meter.dart）**刻意不 import flutter**。
/// 这样领域逻辑既能被 flutter test 跑，也能被纯 dart test 跑，
/// 更重要是：它不需要 widget 环境就能验证，CI 里跑得飞快。
library;

import 'dart:math' as math;

/// 动作库条目的领域视图。只需要引擎用得上的三个字段。
class ExerciseSpec {
  const ExerciseSpec({
    required this.id,
    required this.weightIncrement,
    this.defaultWeightKg,
    this.defaultRestSec = 90,
    this.name = '',
  });

  final String id;

  /// 加重步长。0 表示自重动作 —— 由数据层不变量保证此时 defaultWeightKg 为 null。
  final double weightIncrement;

  /// 该动作零历史时的起始重量。null = 自重。
  final double? defaultWeightKg;

  /// 默认组间休息秒数。来自动作库的 default_rest_sec。
  final int defaultRestSec;

  final String name;

  /// 自重动作：唯一可行的推进方式是加次数。
  bool get isBodyweight => weightIncrement == 0;
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
  const UserProfile({this.progressionMode = ProgressionMode.doubleProgression});
  final ProgressionMode progressionMode;
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
  });

  final String id;
  final String workoutId;
  final String exerciseId;
  final int setIndex;
  final int reps;
  final int completedAtMs;
  final double? weightKg;
  final SetType setType;

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
  Workout({required this.id, required this.startedAtMs});

  final String id;
  final int startedAtMs;
  final List<SetRecord> sets = <SetRecord>[];

  int get totalSets => sets.where((s) => s.setType == SetType.normal).length;

  double get totalVolume =>
      sets.where((s) => s.setType == SetType.normal).fold<double>(0, (a, s) => a + s.volume);

  int get totalVolumeKg => totalVolume.round();
}
