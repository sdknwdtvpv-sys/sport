/// 练了么 · 渐进建议的**接线**测试
///
/// 引擎本身是对的，而且 35 条共用向量守着它（`progression_vectors_test.dart`）。
/// 但曾经**生产代码根本没把历史交给它**：`main.dart` 构造 `WorkoutController`
/// 时不传 `lastSession`，于是真实训练页永远命中 `progression.dart` 的"零历史"
/// 分支 —— 大按钮上恒是动作库默认重量（卧推 40kg）、理由恒是"第一次练这个动作"，
/// 而两秒前建议卡上写的是按历史算出来的数字。**同一个用户，两张屏，两个数。**
///
/// 测试自己传了 `lastSession`，生产没传 —— 所以那 209/381 项测试全是绿的。
/// 这个文件补的就是这条线：**从库里读出来的历史，真的走进了控制器。**
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/analytics.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/sync_queue.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/workout/workout_controller.dart';

/// 与 seed/exercises.json 的 ex_bb_bench_press 一致。
const ExerciseSpec _bench = ExerciseSpec(
  id: 'ex_bb_bench_press',
  name: '杠铃卧推',
  weightIncrement: 2.5,
  defaultWeightKg: 40,
  defaultRestSec: 120,
);

const PlanTarget _plan = PlanTarget(
  targetSets: 3,
  targetRepsLow: 8,
  targetRepsHigh: 10,
);

const int _day = Duration.millisecondsPerDay;

int _agoDays(int days) =>
    DateTime.now().millisecondsSinceEpoch - days * _day;

SetRecord _set({
  required String id,
  required String workoutId,
  required int setIndex,
  required int reps,
  required int atMs,
  double weightKg = 60,
}) =>
    SetRecord(
      id: id,
      workoutId: workoutId,
      exerciseId: _bench.id,
      setIndex: setIndex,
      reps: reps,
      completedAtMs: atMs,
      weightKg: weightKg,
      setType: SetType.normal,
    );

/// 完全照 `main.dart` 的 `_trainSession` 那样构造控制器：
/// 历史从库里查，并且**排除本次训练**。
Future<WorkoutController> _controllerLikeProduction(
  LocalStore store,
  String workoutId,
) async =>
    WorkoutController(
      workoutId: workoutId,
      exercise: _bench,
      plan: _plan,
      analytics: RecordingAnalytics(),
      store: store,
      syncQueue: InMemorySyncQueue(),
      lastSession: await store.lastSessionFor(
        _bench.id,
        excludeWorkoutId: workoutId,
      ),
    );

void main() {
  late InMemoryLocalStore store;

  setUp(() => store = InMemoryLocalStore());

  test('库里没有历史 → 零历史分支，用动作库起始重量', () async {
    final WorkoutController c = await _controllerLikeProduction(store, 'w_new');

    expect(c.weightKg, 40);
    expect(c.suggestion!.reasonCode, ReasonCode.firstTime);
    expect(c.primaryButtonLabel, '40 kg × 8');
    c.dispose();
  });

  test('库里有历史 → 大按钮用的是按历史算出来的重量（这就是以前断掉的那条线）',
      () async {
    // 昨天练了 3 组 60kg × 10 次（全部达标）
    for (int i = 1; i <= 3; i++) {
      await store.saveSet(_set(
        id: 's$i',
        workoutId: 'w_prev',
        setIndex: i,
        reps: 10,
        atMs: _agoDays(1) - i * 1000,
      ));
    }

    final WorkoutController c = await _controllerLikeProduction(store, 'w_now');

    expect(c.weightKg, 62.5, reason: '60 + 2.5：达标就该线性加重');
    expect(c.suggestion!.reasonCode, ReasonCode.linearProgress);
    expect(c.primaryButtonLabel, '62.5 kg × 8');

    // 对照：不传 lastSession 就是这个 bug 当年的样子 —— 40kg + "第一次练"
    final WorkoutController broken = WorkoutController(
      workoutId: 'w_now',
      exercise: _bench,
      plan: _plan,
      analytics: RecordingAnalytics(),
      store: store,
      syncQueue: InMemorySyncQueue(),
    );
    expect(broken.weightKg, 40, reason: '这正是"两屏两个数"的那个错值');
    expect(broken.suggestion!.reasonCode, ReasonCode.firstTime);

    c.dispose();
    broken.dispose();
  });

  test('22 天没练 → 回归保护真的触发（daysAgo 以前恒为 0，这条永远走不到）',
      () async {
    for (int i = 1; i <= 3; i++) {
      await store.saveSet(_set(
        id: 's$i',
        workoutId: 'w_prev',
        setIndex: i,
        reps: 10, // 达标，但长期未练要优先降量
        // 各组的完成时间都**不早于** 22 天前：用减法而不是加法，
        // 否则最后一组变成"22 天差 3 秒"，取整成 21 天。
        atMs: _agoDays(22) - i * 1000,
      ));
    }

    final WorkoutController c = await _controllerLikeProduction(store, 'w_now');

    expect(c.suggestion!.reasonCode, ReasonCode.deload);
    expect(c.weightKg, 60, reason: '回归保护按上次重量，不加重');
    expect(c.suggestion!.reasonText, contains('22 天'));
    c.dispose();
  });

  test('同一次训练里再次进入同一动作：不把"两秒前刚记的组"当成上次', () async {
    // 上次训练：60kg
    await store.saveSet(_set(id: 'p1', workoutId: 'w_prev', setIndex: 1, reps: 10, atMs: _agoDays(1) - 2000));
    await store.saveSet(_set(id: 'p2', workoutId: 'w_prev', setIndex: 2, reps: 10, atMs: _agoDays(1) - 1000));
    await store.saveSet(_set(id: 'p3', workoutId: 'w_prev', setIndex: 3, reps: 10, atMs: _agoDays(1)));
    // 本次训练已经记了一组 80kg（用户手改过）
    await store.saveSet(_set(id: 'n1', workoutId: 'w_now', setIndex: 1, reps: 12, atMs: _agoDays(0), weightKg: 80));

    final WorkoutController c = await _controllerLikeProduction(store, 'w_now');

    expect(c.weightKg, 62.5,
        reason: '应当基于上一次训练（60kg 达标 → 62.5），而不是本次那组 80kg');
    expect(c.suggestion!.reasonCode, ReasonCode.linearProgress);
    c.dispose();
  });

  test('关掉建议 → 引擎闭嘴，界面不显示数字', () async {
    final WorkoutController c = WorkoutController(
      workoutId: 'w_off',
      exercise: _bench,
      plan: _plan,
      analytics: RecordingAnalytics(),
      store: store,
      syncQueue: InMemorySyncQueue(),
      profile: const UserProfile(progressionMode: ProgressionMode.off),
    );

    expect(c.suggestion, isNull);
    c.dispose();
  });
}
