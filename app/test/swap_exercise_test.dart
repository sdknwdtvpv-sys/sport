/// 练了么 · 训练中**换动作**（器械被占）（v1.53）
///
/// 现场依据：健身房最高频的意外就是深蹲架被占。原来的做法是退出训练、重新选动作、
/// 重量次数还得重填 —— 那 20 秒正是训练被打断的地方，而且它直接伤
/// 「单次 ≥ 12 组」这条护栏。
///
/// 这一组测试守四件事：
///   1. 换掉的是**当前那一格**，会话的 `1 / N` 与前后名字跟着变；
///   2. **已经记过的组一条不动**（组是逐条落库的，换动作只换"接下来练什么"）；
///   3. 新动作的默认值**来自它自己的历史**，不是沿用上一个动作的重量
///      （腿举 100 kg 挪到箭步蹲上会把人练伤）；
///   4. 换回来时，这个动作在这次训练里记过的组还在（`alreadyLogged`）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/analytics.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/sync_queue.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/domain/tap_meter.dart';
import 'package:lianleme/features/workout/workout_controller.dart';
import 'package:lianleme/features/workout/workout_session.dart';

const ExerciseSpec _bench = ExerciseSpec(
  id: 'ex_bb_bench_press',
  name: '杠铃卧推',
  weightIncrement: 2.5,
  defaultWeightKg: 40,
  defaultRestSec: 120,
);

const ExerciseSpec _incline = ExerciseSpec(
  id: 'ex_db_incline_press',
  name: '哑铃上斜卧推',
  weightIncrement: 2,
  defaultWeightKg: 12,
  defaultRestSec: 90,
);

const ExerciseSpec _squat = ExerciseSpec(
  id: 'ex_bb_squat',
  name: '杠铃深蹲',
  weightIncrement: 2.5,
  defaultWeightKg: 60,
  defaultRestSec: 180,
);

const PlanTarget _plan = PlanTarget(
  targetSets: 3,
  targetRepsLow: 8,
  targetRepsHigh: 10,
);

WorkoutController _controller(
  ExerciseSpec exercise, {
  RecordingAnalytics? analytics,
  InMemoryLocalStore? store,
  LastSession? lastSession,
  List<SetRecord> alreadyLogged = const <SetRecord>[],
}) =>
    WorkoutController(
      workoutId: 'w_test',
      exercise: exercise,
      plan: _plan,
      analytics: analytics ?? RecordingAnalytics(),
      store: store ?? InMemoryLocalStore(),
      syncQueue: InMemorySyncQueue(),
      lastSession: lastSession,
      alreadyLogged: alreadyLogged,
      clock: () => 1000000,
    );

void main() {
  test('换掉当前那一格：会话长度不变、当前动作变了、位置不变', () {
    final WorkoutSession session = WorkoutSession(<WorkoutController>[
      _controller(_bench),
      _controller(_squat),
    ]);
    session.next(); // 落在深蹲上
    expect(session.current.exercise.name, '杠铃深蹲');
    expect(session.index, 1);

    session.replaceCurrent(_controller(_incline));

    expect(session.length, 2, reason: '换动作不是"加一个动作"');
    expect(session.current.exercise.name, '哑铃上斜卧推');
    expect(session.index, 1, reason: '换完还停在同一格');
    expect(session.previousName, '杠铃卧推', reason: '前后名字要跟着更新');
    expect(session.hasMultiple, isTrue);
  });

  test('新动作的默认值来自**它自己的**历史，不是沿用上一个动作的重量', () {
    final WorkoutSession session = WorkoutSession(<WorkoutController>[
      _controller(_squat, lastSession: const LastSession(weightKg: 100, reps: <int>[8])),
    ]);
    // 深蹲：100 kg（上一次练的）
    expect(session.current.primaryButtonLabel, '100 kg × 8');

    // 器械被占 → 换成哑铃上斜卧推（它自己的历史是 14 kg）
    session.replaceCurrent(_controller(
      _incline,
      lastSession: const LastSession(weightKg: 14, reps: <int>[10]),
    ));

    // 关键是**重量**：14 来自新动作自己的历史。
    // 次数由引擎/处方给（14 kg 那次的 10 次高于区间下沿，引擎会回到 8 次起步），
    // 所以这里只钉重量，不把引擎的次数口径抄一遍。
    expect(session.current.primaryButtonLabel, startsWith('14 kg × '),
        reason: '把 100 kg 挪到哑铃上会直接把人练伤 —— 必须用新动作自己的历史');
    expect(session.current.primaryButtonLabel, isNot(contains('100')));
  });

  test('已经记过的组一条不动（换的是"接下来练什么"，不是抹掉记录）', () {
    final InMemoryLocalStore store = InMemoryLocalStore();
    final WorkoutController squat = _controller(_squat, store: store);
    final WorkoutSession session = WorkoutSession(<WorkoutController>[squat]);

    squat.onBigButtonTap();
    squat.onBigButtonTap();
    expect(squat.loggedSets.length, 2);

    session.replaceCurrent(_controller(_incline, store: store));

    expect(squat.loggedSets.length, 2, reason: '旧控制器里的记录不会被换掉');
    expect(session.totalSetsSoFar, 0,
        reason: '新动作自己还没记过 —— 统计按动作各自算');
  });

  test('换回来时，这个动作在这次训练里记过的组还在（alreadyLogged）', () {
    final SetRecord earlier = SetRecord(
      id: 's_w_test_ex_db_incline_press_1',
      workoutId: 'w_test',
      exerciseId: 'ex_db_incline_press',
      setIndex: 1,
      reps: 12,
      weightKg: 12,
      completedAtMs: 1,
    );
    final WorkoutSession session = WorkoutSession(<WorkoutController>[
      _controller(_squat),
    ]);

    // 先换成上斜卧推、记过一组，之后又换走；现在换回来
    session.replaceCurrent(_controller(_incline, alreadyLogged: <SetRecord>[earlier]));

    expect(session.current.loggedSets.length, 1, reason: '换回来要认得之前记过的那一组');
    expect(session.current.setNumber, 2, reason: '组号接着数，否则再记会覆盖第 1 组');
  });

  test('换动作计一次 `exercise_switch`（与点底部条切动作同一个意图）', () {
    final RecordingAnalytics analytics = RecordingAnalytics();
    final WorkoutSession session = WorkoutSession(<WorkoutController>[
      _controller(_squat),
    ]);
    final WorkoutController next = _controller(_incline, analytics: analytics);
    session.replaceCurrent(next);
    // 与 main.dart 里那条调用同序：换完之后在**新控制器**上计一次
    next.analytics.countTap(TapKind.exerciseSwitch);
    next.onBigButtonTap();

    expect(analytics.propsOf('set_logged').single['tap_kinds'],
        <String>['exercise_switch', 'big_button']);
  });
}
