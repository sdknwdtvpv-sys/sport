/// 练了么 · 休息条的 **±15 秒**（v1.53）
///
/// 现场依据：健身房里「今天想多歇半分钟」几乎必然发生，而原先休息条上只有「跳过」。
///
/// 这一组测试守四件事，每一件都是"做错了不会报错、只会静默算错"的那种：
///   1. 改的是**结束时刻**（真源只有一份），不是自己另存一个"剩余秒数"；
///   2. 锁屏/灵动岛那条倒计时会**跟着重播**（否则手机上 +15 了、锁屏上还是原来那个点）；
///   3. 减到已经过去时，结束这件事仍然**只由计时器那一跳**收尾（`rest_completed` 只报一次）；
///   4. 不在休息中时按了**什么都不发生**（不凭空起一个倒计时）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/analytics.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/sync_queue.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/workout/rest_activity.dart';
import 'package:lianleme/features/workout/workout_controller.dart';

const ExerciseSpec _squat = ExerciseSpec(
  id: 'ex_bb_squat',
  name: '杠铃深蹲',
  weightIncrement: 2.5,
  defaultWeightKg: 60,
  defaultRestSec: 90,
);

const PlanTarget _plan = PlanTarget(
  targetSets: 3,
  targetRepsLow: 8,
  targetRepsHigh: 10,
);

class _FakeRest implements RestActivityBridge {
  final List<RestActivityInfo> started = <RestActivityInfo>[];
  int ended = 0;

  @override
  Future<void> start(RestActivityInfo info) async => started.add(info);

  @override
  Future<void> end() async => ended += 1;

  /// 这条测试不关心"系统里还挂着几条"，只要个真值。
  @override
  Future<int> activeCount() async => started.isEmpty ? 0 : 1;
}

class _Harness {
  _Harness() {
    controller = WorkoutController(
      exercise: _squat,
      plan: _plan,
      analytics: analytics,
      store: store,
      syncQueue: syncQueue,
      restActivity: rest,
      clock: () => _t,
    );
  }

  final RecordingAnalytics analytics = RecordingAnalytics();
  final InMemoryLocalStore store = InMemoryLocalStore();
  final InMemorySyncQueue syncQueue = InMemorySyncQueue();
  final _FakeRest rest = _FakeRest();
  late final WorkoutController controller;

  int _t = 1000000;

  /// 推进假时钟（休息按墙上时钟算，测"真的在走"必须推它）。
  void advance(int ms) => _t += ms;
}

void main() {
  test('记一组之后休息在走；−15 让结束时刻提前 15 秒', () {
    final _Harness h = _Harness();
    h.controller.onBigButtonTap();
    expect(h.controller.restRunning, isTrue);
    expect(h.controller.restRemainingSec, 90);
    final int endsAt = h.controller.restEndsAtMs!;

    h.controller.adjustRest(-15);

    expect(h.controller.restEndsAtMs, endsAt - 15000,
        reason: '改的是结束时刻——全项目只有这一份真相');
    expect(h.controller.restRemainingSec, 75);
    h.controller.dispose();
  });

  test('+15 让结束时刻推后 15 秒', () {
    final _Harness h = _Harness();
    h.controller.onBigButtonTap();
    final int endsAt = h.controller.restEndsAtMs!;

    h.controller.adjustRest(15);

    expect(h.controller.restEndsAtMs, endsAt + 15000);
    expect(h.controller.restRemainingSec, 105);
    h.controller.dispose();
  });

  test('锁屏那条倒计时跟着重播（否则两个界面会各说各的）', () {
    final _Harness h = _Harness();
    h.controller.onBigButtonTap();
    final int before = h.rest.started.length;
    final int oldEnd = h.rest.started.last.endAtMs;

    h.controller.adjustRest(15);

    expect(h.rest.started.length, before + 1, reason: '要再广播一次新的结束时刻');
    expect(h.rest.started.last.endAtMs, oldEnd + 15000);
    h.controller.dispose();
  });

  test('减到已经过去：留到计时器那一跳收尾，`rest_completed` 只报一次', () {
    final _Harness h = _Harness();
    h.controller.onBigButtonTap();
    h.advance(80000); // 已经歇了 80 秒

    h.controller.adjustRest(-15); // 90 → 剩 -5 秒

    expect(h.controller.restRemainingSec, 0, reason: '不许出现负数倒计时');
    expect(h.controller.restRunning, isTrue,
        reason: '还没收尾——收尾只由计时器那一跳做，免得埋点重复报或漏报');
    h.controller.dispose();
  });

  test('不在休息中时按了什么都不发生（不凭空起一个倒计时）', () {
    final _Harness h = _Harness();
    expect(h.controller.restRunning, isFalse);

    h.controller.adjustRest(15);
    h.controller.adjustRest(-15);

    expect(h.controller.restRunning, isFalse);
    expect(h.controller.restEndsAtMs, isNull);
    expect(h.controller.restRemainingSec, 0);
    expect(h.rest.started, isEmpty, reason: '没在休息就不该给锁屏广播什么');
    h.controller.dispose();
  });

  test('调整休息**不计入 tap_count**（那条护栏量的是"为得到下一组多付出的操作"）', () {
    final _Harness h = _Harness();
    h.controller.onBigButtonTap();
    h.controller.adjustRest(15);
    h.controller.adjustRest(15);
    h.controller.onBigButtonTap();

    final List<Map<String, Object?>> sets = h.analytics.propsOf('set_logged');
    expect(sets.last['tap_count'], 1,
        reason: '第二组的 tap_count 仍然是 1：调整休息没有产生记录，不该算进去');
    h.controller.dispose();
  });
}
