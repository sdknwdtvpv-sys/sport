/// 练了么 · S7 训练结束总结的逻辑
///
/// 页面只负责画，规则全在这里，纯 Dart、可测。
///
/// 破纪录的判定原则：**必须排除本次训练**，否则每次练完都是"新纪录"。
/// 而且有重量比重量、自重比次数 —— 引体向上的"纪录"不可能是公斤数。
library;

import '../../data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import '../../core/units.dart';
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import '../../domain/models.dart';

/// 一条破纪录
class SetPr {
  const SetPr({
    required this.exerciseId,
    required this.exerciseName,
    required this.reps,
    required this.previousBest,
    this.weightKg,
    this.unit = WeightUnit.kg,
  });

  final String exerciseId;
  final String exerciseName;
  final int reps;

  /// 之前的最佳：有重量的比公斤数，自重的比次数
  final double previousBest;

  /// 自重动作为 null
  final double? weightKg;

  /// 显示单位（存储始终是 kg）
  final WeightUnit unit;

  bool get isBodyweight => weightKg == null;

  /// 本次的成绩（重量或次数）
  double get value => isBodyweight ? reps.toDouble() : (weightKg ?? 0);

  /// 一行展示，如「65kg（上次最好 60kg）」或「12 次（上次最好 10 次）」
  String get detail {
    if (isBodyweight) {
      return '$reps 次（上次最好 ${previousBest.toInt()} 次）';
    }
    return '${formatWeight(weightKg, unit)}（上次最好 ${formatWeight(previousBest, unit)}）';
  }
}

class WorkoutSummary {
  const WorkoutSummary({
    required this.workoutId,
    required this.totalSets,
    required this.totalVolumeKg,
    required this.duration,
    required this.exerciseCount,
    required this.prs,
    required this.startedAtMs,
    this.unit = WeightUnit.kg,
  });

  final String workoutId;
  final int totalSets;
  final double totalVolumeKg;
  final Duration? duration;
  final int exerciseCount;
  final List<SetPr> prs;

  /// 这次训练的开始时间。分享卡要显示日期 —— 一张没有日期的"训练完成"
  /// 卡片没有任何纪念意义。
  final int startedAtMs;

  /// 显示单位（存储始终是 kg）
  final WeightUnit unit;

  bool get hasPr => prs.isNotEmpty;

  /// 如「42 分钟」。算不出时长返回「—」而不是 0。
  String get durationLabel {
    final Duration? d = duration;
    if (d == null) return '—';
    final int m = d.inMinutes;
    if (m < 1) return '不到 1 分钟';
    if (m < 60) return '$m 分钟';
    final int h = m ~/ 60;
    final int rest = m % 60;
    return rest == 0 ? '$h 小时' : '$h 小时 $rest 分';
  }

  /// 自重训练容量记 0，这时显示「自重」而不是「0 kg」
  String get volumeLabel => formatVolume(totalVolumeKg, unit, zeroText: '自重');
}

class SummaryService {
  SummaryService({required LocalStore store, required ExerciseRepository repository})
      : _store = store,
        _repo = repository;

  final LocalStore _store;
  final ExerciseRepository _repo;

  /// 生成总结。查不到这次训练返回 null（比如用户一个动作都没练就退出）。
  ///
  /// [nowMs] 用于补上结束时间；不传则用最后一组的完成时间。
  Future<WorkoutSummary?> build(String workoutId,
      {int? nowMs, WeightUnit unit = WeightUnit.kg}) async {
    final Workout? w = await _store.loadWorkout(workoutId);
    if (w == null || w.sets.isEmpty) return null;

    // 结束时把结束时间落库，S7 之后重开也算得出时长
    final int endMs = nowMs ?? _lastCompletedAt(w);
    if (!w.isFinished) {
      w.endedAtMs = endMs;
      await _store.saveWorkout(w);
    }

    // 本次训练里出现过的动作，按首次出现顺序
    final List<String> exerciseIds = <String>[];
    for (final SetRecord s in w.sets) {
      if (!exerciseIds.contains(s.exerciseId)) exerciseIds.add(s.exerciseId);
    }

    final List<SetPr> prs = <SetPr>[];
    for (final String id in exerciseIds) {
      final SetPr? pr = await _prFor(id, workoutId, w, unit);
      if (pr != null) prs.add(pr);
    }

    return WorkoutSummary(
      workoutId: workoutId,
      totalSets: w.totalSets,
      totalVolumeKg: w.totalVolume,
      duration: w.duration,
      exerciseCount: exerciseIds.length,
      prs: prs,
      startedAtMs: w.startedAtMs,
      unit: unit,
    );
  }

  int _lastCompletedAt(Workout w) {
    int latest = w.startedAtMs;
    for (final SetRecord s in w.sets) {
      if (s.completedAtMs > latest) latest = s.completedAtMs;
    }
    return latest;
  }

  /// 某个动作在本次训练里是否破纪录
  Future<SetPr?> _prFor(
      String exerciseId, String workoutId, Workout w, WeightUnit unit) async {
    final List<SetRecord> mine = w.sets
        .where((SetRecord s) =>
            s.exerciseId == exerciseId && s.setType == SetType.normal)
        .toList();
    if (mine.isEmpty) return null;

    final bool bodyweight = mine.every((SetRecord s) => s.weightKg == null);

    // 本次最佳
    double best;
    SetRecord bestSet = mine.first;
    if (bodyweight) {
      best = mine.map((SetRecord s) => s.reps).reduce((a, b) => a > b ? a : b).toDouble();
      for (final SetRecord s in mine) {
        if (s.reps.toDouble() >= best) bestSet = s;
      }
    } else {
      best = mine
          .map((SetRecord s) => s.weightKg ?? 0)
          .reduce((a, b) => a > b ? a : b);
      for (final SetRecord s in mine) {
        if ((s.weightKg ?? 0) >= best) bestSet = s;
      }
    }

    final List<SetRecord> history =
        await _store.setsForExercise(exerciseId, excludeWorkoutId: workoutId);
    if (history.isEmpty) return null; // 第一次练这个动作，不算破纪录

    final double previousBest = bodyweight
        ? history.map((SetRecord s) => s.reps).reduce((a, b) => a > b ? a : b).toDouble()
        : history
            .map((SetRecord s) => s.weightKg ?? 0)
            .reduce((a, b) => a > b ? a : b);

    if (best <= previousBest) return null;

    final ExerciseData? row = await _repo.byId(exerciseId);
    return SetPr(
      exerciseId: exerciseId,
      exerciseName: row?.name ?? exerciseId,
      reps: bestSet.reps,
      weightKg: bodyweight ? null : bestSet.weightKg,
      previousBest: previousBest,
      unit: unit,
    );
  }
}
