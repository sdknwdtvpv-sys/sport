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
    this.isTime = false,
  });

  /// 按时长动作（平板支撑）：那个数字是**秒**，不是次数。
  final bool isTime;

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

  /// 一行展示，如「65 kg（上次最好 60 kg）」或「12 次（上次最好 10 次）」。
  /// 按时长动作说「秒」—— 破纪录破的是坚持的秒数。
  String get detail {
    if (isBodyweight) {
      final String u = isTime ? '秒' : '次';
      return '$reps $u（上次最好 ${previousBest.toInt()} $u）';
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
    this.distanceM = 0,
    this.distanceSets = 0,
    this.cardiovascularLabels = const <String>[],
    this.unit = WeightUnit.kg,
    this.note,
  });

  final String workoutId;
  final int totalSets;

  /// 这次训练的一句话（2026-10-04）。null / 空 = 没写。
  final String? note;
  final double totalVolumeKg;
  final Duration? duration;
  final int exerciseCount;
  final List<SetPr> prs;

  /// 这次训练的有氧里程（米）。0 = 这次没记有氧。
  ///
  /// 与 [totalVolumeKg] **并列而不是相加**：容量是力量的口径（kg × 次），
  /// 里程是心肺的口径（米）。把 5 公里加进容量里是两种量纲混在一起。
  final double distanceM;

  /// 记了距离的组数 —— 用来区分"没练有氧"与"练了但距离记成 0"。
  final int distanceSets;

  /// 这次练到的有氧动作名（去重、按首次出现）。总结页据此说"练了什么有氧"。
  final List<String> cardiovascularLabels;

  bool get hasDistance => distanceSets > 0 && distanceM > 0;

  /// 这次训练的开始时间。分享卡要显示日期 —— 一张没有日期的"训练完成"
  /// 卡片没有任何纪念意义。
  final int startedAtMs;

  /// 显示单位（存储始终是 kg）
  final WeightUnit unit;

  bool get hasPr => prs.isNotEmpty;

  /// 如「42 分钟」。算不出时长返回「—」而不是 0。
  String get durationLabel =>
      duration == null ? '—' : durationLabelOf(duration!.inSeconds);

  /// 秒数 → 同一套写法（T2-3 的完成页时间轴要**按秒滚**，而滚完必须与
  /// [durationLabel] 一字不差 —— 所以两者只能是同一个实现，不许各写一份）。
  static String durationLabelOf(int seconds) {
    final int m = seconds ~/ 60;
    if (m < 1) return '不到 1 分钟';
    if (m < 60) return '$m 分钟';
    final int h = m ~/ 60;
    final int rest = m % 60;
    return rest == 0 ? '$h 小时' : '$h 小时 $rest 分';
  }

  /// 自重训练容量记 0，这时显示「自重」而不是「0 kg」
  String get volumeLabel => formatVolume(totalVolumeKg, unit, zeroText: '自重');

  /// 里程那一个格子。没记有氧时返回 null —— 总结页据此决定要不要显示它。
  String? get distanceLabel =>
      hasDistance ? formatDistanceKm(distanceM) : null;

  /// 有氧的平均配速：总里程 ÷ 总时长。时长缺失或为 0 时返回 null。
  ///
  /// ⚠️ 用**整场训练的时长**算，是近似的（中间的力量组也被算进去了）。
  /// 精确做法要按每个有氧动作自己的组时间求和 —— 那是后续版本的事，
  /// 这里宁可说"平均"也不假装精确（写在 UI 文案里）。
  String? get paceLabel {
    final Duration? d = duration;
    if (!hasDistance || d == null) return null;
    return formatPace(distanceM, d.inSeconds);
  }
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

    // 有氧：里程与"练了哪些有氧"。**与力量那三个大数并列，不相加。**
    double distanceM = 0;
    int distanceSets = 0;
    final List<String> cardio = <String>[];
    for (final SetRecord s in w.sets) {
      if (!s.hasDistance) continue;
      distanceM += s.distanceM!;
      if (s.setType == SetType.normal) distanceSets++;
      if (!cardio.contains(s.exerciseId)) cardio.add(s.exerciseId);
    }
    final List<String> cardioNames = <String>[];
    for (final String id in cardio) {
      final ExerciseData? row = await _repo.byId(id);
      cardioNames.add(row?.name ?? id);
    }

    return WorkoutSummary(
      workoutId: workoutId,
      totalSets: w.totalSets,
      totalVolumeKg: w.totalVolume,
      duration: w.duration,
      exerciseCount: exerciseIds.length,
      prs: prs,
      startedAtMs: w.startedAtMs,
      distanceM: distanceM,
      distanceSets: distanceSets,
      cardiovascularLabels: cardioNames,
      unit: unit,
      note: w.note,
    );
  }

  /// 写下（或改掉）这次训练的一句话（2026-10-04）。
  ///
  /// 为什么放在服务里而不是界面里：界面不该认识数据库的形状，
  /// 而且"写 note"必须**连整行一起 upsert**（`saveWorkout` 是整行覆盖，
  /// 少了这一句就会把 endedAt / 容量抹掉）。
  Future<void> setNote(String workoutId, String note) async {
    final Workout? w = await _store.loadWorkout(workoutId);
    if (w == null) return;
    final String trimmed = note.trim();
    w.note = trimmed.isEmpty ? null : trimmed;
    await _store.saveWorkout(w);
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

    // 距离动作**不判力量纪录**：它的"次数"是秒，"重量"多半是 null，
    // 按自重那条路比次数就会得出一条"1800 次新纪录"——那是假数据。
    // （有氧的最好成绩是里程与配速，那是另一套呈现，不是这里的 PR。）
    if (mine.any((SetRecord s) => s.hasDistance)) return null;

    // 走到这里一定没有距离组（上面已经返回），所以"全是 null 重量"就是自重动作
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
      isTime: row != null && isTimeTrack(row.trackType),
    );
  }
}
