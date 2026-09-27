/// 练了么 · 训练会话状态机
///
/// 对应 `docs/interaction-spec.md` §6 的状态机与 §7 的手势规范。
///
/// 两条容易做错、且都有测试守着的规则：
///   1. **训练中不重算建议。** 建议是"本次训练的处方"，在训练开始时算一次就固定；
///      如果每组后重算，会立刻变成「上次只完成 1 组，先把组数补满」这种荒谬提示。
///      重算只发生在下一次训练开始时。
///   2. **组数达标后不禁用按钮。** 计划是建议不是牢笼，禁止加组会让用户退回备忘录。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../analytics/analytics.dart';
import '../../data/local_store.dart';
import '../../data/sync_queue.dart';
import '../../domain/models.dart';
import '../../domain/progression.dart';
import '../../domain/tap_meter.dart';

/// 单动作训练时的默认 id。多动作场景由调用方传入同一个 id。
const String kLocalWorkoutId = 'w_local_1';

class WorkoutController extends ChangeNotifier {
  WorkoutController({
    required this.exercise,
    required this.plan,
    required this.analytics,
    required this.store,
    required this.syncQueue,
    /// 同一次训练里的多个动作**共享同一个 workoutId**，
    /// 这样记录会挂在一条 workout 下，而不是被拆成多次训练。
    String workoutId = kLocalWorkoutId,
    LastSession? lastSession,
    List<ManualOverride> overrides = const <ManualOverride>[],
    UserProfile profile = const UserProfile(),
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    workout = Workout(id: workoutId, startedAtMs: _clock());
    _suggestion = suggestNext(
      exercise: exercise,
      plan: plan,
      lastSession: lastSession,
      profile: profile,
      overrides: overrides,
    );
    _weightKg = _suggestion?.weightKg ?? 0;
    _reps = _suggestion?.reps ?? plan.targetRepsLow;
    analytics.beginSetInteraction();
  }

  final ExerciseSpec exercise;
  final PlanTarget plan;
  final Analytics analytics;
  final LocalStore store;
  final SyncQueue syncQueue;
  final int Function() _clock;

  late final Workout workout;
  Suggestion? _suggestion;

  double _weightKg = 0;
  int _reps = 0;
  int _normalSets = 0;
  int _restRemaining = 0;
  bool _restRunning = false;
  bool _sheetOpen = false;
  bool _disposed = false;
  String? _hint;
  Timer? _restTimer;

  Suggestion? get suggestion => _suggestion;
  double get weightKg => _weightKg;
  int get reps => _reps;
  int get restRemainingSec => _restRemaining;
  bool get restRunning => _restRunning;
  bool get restDone => !_restRunning && _restRemaining == 0 && _normalSets > 0;
  bool get sheetOpen => _sheetOpen;
  bool get isOffline => syncQueue.offline;
  bool get isBodyweight => exercise.isBodyweight;
  int get setNumber => _normalSets + 1;
  int get plannedSets => plan.targetSets;
  String? get hint => _hint;
  List<SetRecord> get loggedSets => List<SetRecord>.unmodifiable(workout.sets);

  /// 大按钮上显示的文案 —— 就是即将写入的值。
  /// 这是全产品唯一不可妥协的指标：点击即写入，1 次点击 = 1 组。
  String get primaryButtonLabel {
    final w = isBodyweight ? '自重' : '${_trimZero(_weightKg)}kg';
    return '$w × $_reps';
  }

  // ---------- 手势入口（UI 只调用这四个） ----------

  /// 点按大按钮：记一组。
  void onBigButtonTap() {
    analytics.countTap(TapKind.bigButton);
    _logSet();
  }

  /// 长按大按钮 500ms：打开修改弹层。**不记录任何一组。**
  void onLongPress() {
    analytics.countTap(TapKind.longPress);
    _sheetOpen = true;
    _hint = '步进调整，不需要键盘';
    _notify();
  }

  /// 弹层里每按一次步进按钮。
  void onStepper({double deltaWeight = 0, int deltaReps = 0}) {
    analytics.countTap(TapKind.stepper);
    if (deltaWeight != 0) {
      final next = _weightKg + deltaWeight;
      _weightKg = next < 0 ? 0 : (next * 10).round() / 10;
    }
    if (deltaReps != 0) {
      final next = _reps + deltaReps;
      _reps = next < 1 ? 1 : next;
    }
    _notify();
  }

  /// 弹层「确定」：关闭弹层，把修改应用到后续的组。
  void onSheetConfirm() {
    analytics.countTap(TapKind.sheetConfirm);
    _sheetOpen = false;
    _hint = null;
    _notify();
  }

  void skipRest() {
    _stopRest();
    _restRemaining = 0;
    analytics.track('rest_skipped', <String, Object?>{
      'exercise_id': exercise.id,
      'planned_sec': exercise.defaultRestSec,
    });
    _notify();
  }

  void setOffline(bool value) {
    syncQueue.offline = value;
    _notify();
  }

  Future<SyncOutcome> flushSync() => syncQueue.flush();

  // ---------- 内部 ----------

  void _logSet() {
    final reading = analytics.flushTap();
    _normalSets++;

    final record = SetRecord(
      // 确定性 id，包含 workout + 动作 + 组序 —— 三者确定唯一一条记录。
      //
      // 之前写的是 's_${workout.sets.length + 1}'：那是**每个控制器各自计数**的，
      // 所以同一次训练里两个动作都会生成 's_1'，后者把前者覆盖掉 —— 直接丢数据。
      // set_record.id 是全局主键，id 就不能按局部计数器生成。
      // 确定性还有个好处：同一组重复写入是幂等的。
      id: 's_${workout.id}_${exercise.id}_$_normalSets',
      workoutId: workout.id,
      exerciseId: exercise.id,
      setIndex: _normalSets,
      reps: _reps,
      weightKg: isBodyweight ? null : _weightKg,
      completedAtMs: _clock(),
      setType: SetType.normal,
    );
    workout.sets.add(record);

    // 本地优先：先落本地库、再进队列。训练中绝不发网络请求。
    unawaited(store.saveSet(record));
    // 训练行本身也必须落库（totalSets / totalVolume 随之更新）。
    // 之前只写了 set_record，导致重启后 loadWorkout 找不到这次训练。
    unawaited(store.saveWorkout(workout));
    syncQueue.enqueue('set_record', <String, Object?>{
      'id': record.id,
      'workout_id': record.workoutId,
      'exercise_id': record.exerciseId,
      'set_index': record.setIndex,
      'weight_kg': record.weightKg,
      'reps': record.reps,
      'set_type': record.setType.wire,
      'completed_at': record.completedAtMs,
    });

    analytics.track('set_logged', <String, Object?>{
      'workout_id': workout.id,
      'exercise_id': exercise.id,
      'set_index': record.setIndex,
      'weight_kg': record.weightKg,
      'reps': record.reps,
      'set_type': record.setType.wire,
      'tap_count': reading.count,
      'tap_kinds': reading.kinds.map((k) => k.wire).toList(),
      'entry': reading.kinds.isEmpty ? 'unknown' : reading.kinds.first.wire,
      'is_offline': syncQueue.offline,
    });

    // 组数达标后不禁用，只提示。计划是建议不是牢笼。
    if (_normalSets >= plan.targetSets) {
      _hint = '已达到计划组数，再点会继续记录（不加限制）';
    }

    _startRest();
    analytics.beginSetInteraction(); // 开启下一组的交互周期
    _notify();
  }

  void _startRest() {
    _stopRest();
    _restRemaining = exercise.defaultRestSec;
    _restRunning = true;
    analytics.track('rest_started', <String, Object?>{
      'exercise_id': exercise.id,
      'planned_sec': exercise.defaultRestSec,
      'auto': true,
    });
    _restTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_disposed) {
        t.cancel();
        return;
      }
      if (_restRemaining <= 1) {
        _restRemaining = 0;
        _restRunning = false;
        t.cancel();
        analytics.track('rest_completed', <String, Object?>{
          'exercise_id': exercise.id,
          'planned_sec': exercise.defaultRestSec,
        });
      } else {
        _restRemaining--;
      }
      _notify();
    });
  }

  void _stopRest() {
    _restTimer?.cancel();
    _restTimer = null;
    _restRunning = false;
  }

  String _trimZero(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopRest();
    super.dispose();
  }
}
