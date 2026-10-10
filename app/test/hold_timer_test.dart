/// 练了么 · 计时动作的**做组计时器**（v1.53）
///
/// 现场依据：平板支撑这类动作，原先只能在弹层里**挑一个秒数** ——
/// 等于让用户在垫子上自己数。这一版把它做成"开始计时 → 到点震一下 → 点一下记下"。
///
/// 守五件事（每一条错了都不会报错，只会静默算错）：
///   1. 计时**只给出这一组的值**，不改变「1 次点击 = 1 组」；
///   2. 记下来的秒数来自**开始时刻**（App 被挂起时 Dart 定时器不走，靠累加会白送时间）；
///   3. 到点**只震一次**（之后继续撑是用户的选择，不该每秒震）；
///   4. 长按 = "改"，会**收起计时器**，而且不记组；
///   5. 力量/距离动作上**根本没有这个功能**（`canTimeSet` 为假，按了也没反应）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/analytics.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/sync_queue.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/workout/haptics.dart';
import 'package:lianleme/features/workout/workout_controller.dart';

/// 与 seed 里的平板支撑一致：按时长记。
const ExerciseSpec _plank = ExerciseSpec(
  id: 'ex_plank',
  name: '平板支撑',
  weightIncrement: 0,
  defaultWeightKg: null,
  defaultRestSec: 60,
  trackType: 'time',
);

const ExerciseSpec _bench = ExerciseSpec(
  id: 'ex_bb_bench_press',
  name: '杠铃卧推',
  weightIncrement: 2.5,
  defaultWeightKg: 40,
  defaultRestSec: 120,
);

const PlanTarget _plan = PlanTarget(
  targetSets: 3,
  targetRepsLow: 30,
  targetRepsHigh: 60,
);

class _FakeHaptics implements Haptics {
  int sets = 0;
  int targets = 0;

  @override
  Future<void> setLogged() async => sets += 1;

  @override
  Future<void> restFinished() async {}

  @override
  Future<void> restPreview() async {}

  @override
  Future<void> targetReached() async => targets += 1;
}

class _Harness {
  _Harness({ExerciseSpec exercise = _plank}) {
    controller = WorkoutController(
      exercise: exercise,
      plan: _plan,
      analytics: analytics,
      store: store,
      syncQueue: syncQueue,
      haptics: haptics,
      clock: () => _t,
    );
  }

  final RecordingAnalytics analytics = RecordingAnalytics();
  final InMemoryLocalStore store = InMemoryLocalStore();
  final InMemorySyncQueue syncQueue = InMemorySyncQueue();
  final _FakeHaptics haptics = _FakeHaptics();
  late final WorkoutController controller;

  int _t = 500000;

  void advance(int ms) => _t += ms;
}

void main() {
  test('只有按时长记的动作能计时（力量动作没有这个功能）', () {
    final _Harness plank = _Harness();
    expect(plank.controller.canTimeSet, isTrue);
    plank.controller.startHold();
    expect(plank.controller.holding, isTrue);
    plank.controller.dispose();

    final _Harness bench = _Harness(exercise: _bench);
    expect(bench.controller.canTimeSet, isFalse);
    bench.controller.startHold(); // 按了也没反应
    expect(bench.controller.holding, isFalse);
    bench.controller.dispose();
  });

  test('秒数按**开始时刻**算（挂起 40 秒回来也认）', () {
    final _Harness h = _Harness();
    h.controller.startHold();

    h.advance(42000); // App 被挂起 42 秒（Dart 定时器不走）
    expect(h.controller.holdElapsedSec, 42,
        reason: '靠"每秒加一"会白送掉被挂起的那段时间');
    h.controller.dispose();
  });

  test('计时中记一组：值就是已计秒数（记组那一下仍然只算一次）', () {
    final _Harness h = _Harness();
    h.controller.startHold();
    h.advance(47000);

    h.controller.onBigButtonTap();

    final List<Map<String, Object?>> sets = h.analytics.propsOf('set_logged');
    expect(sets.length, 1);
    expect(sets.single['reps'], 47, reason: '记下来的就是计到的那 47 秒');
    // 「开始计时」诚实计入（stepper 类），记下来算一次大按钮 —— 见下面那条测试。
    // 这里要钉的是：**记组那一下仍然只算一次**，没有被计时器重复计数。
    expect(sets.single['tap_count'], 2);
    expect(h.controller.holding, isFalse, reason: '记完计时器要收掉');
    expect(h.controller.loggedSets.single.reps, 47);
    h.controller.dispose();
  });

  test('秒数取整到最少 1 秒（0 秒的记录是假数据）', () {
    final _Harness h = _Harness();
    h.controller.startHold();
    h.advance(200); // 0.2 秒就点了

    h.controller.onBigButtonTap();

    expect(h.controller.loggedSets.single.reps, 1);
    h.controller.dispose();
  });

  test('撑到今天的秒数震**一次**（之后继续撑不再震）', () async {
    final _Harness h = _Harness();
    h.controller.startHold();

    h.advance(30000); // 计划 30 秒
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(h.haptics.targets, 1, reason: '到点提醒一下');

    h.advance(10000); // 又撑了 10 秒
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(h.haptics.targets, 1, reason: '每秒震一下会把用户逼疯——只震一次');
    h.controller.dispose();
  });

  test('长按 = 改：收起计时器且不记组', () {
    final _Harness h = _Harness();
    h.controller.startHold();
    h.advance(20000);

    h.controller.onLongPress();

    expect(h.controller.holding, isFalse, reason: '弹层关掉之后计时器不该还在悄悄倒数');
    expect(h.controller.loggedSets, isEmpty, reason: '长按的语义始终是"改"，不是"记"');
    expect(h.controller.sheetOpen, isTrue);
    h.controller.dispose();
  });

  test('「开始计时」也诚实计入 tap_count（与手动调次数同一件事）', () {
    final _Harness h = _Harness();
    h.controller.startHold();
    h.advance(30000);
    h.controller.onBigButtonTap();

    expect(h.analytics.propsOf('set_logged').single['tap_count'], 2,
        reason: '开始计时算一次（stepper 类），记下来算一次 —— 这是这个动作真实的代价');
    expect(h.analytics.propsOf('set_logged').single['tap_kinds'],
        <String>['stepper', 'big_button']);
    h.controller.dispose();
  });

  test('大按钮上是那个在走的数字（抬眼看得到"我撑了多久"）', () {
    final _Harness h = _Harness();
    h.controller.startHold();
    h.advance(65000);
    expect(h.controller.primaryButtonLabel, '1:05');
    h.controller.dispose();
  });
}
