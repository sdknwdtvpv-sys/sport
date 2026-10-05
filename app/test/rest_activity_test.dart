/// 练了么 · 组间休息的 Live Activity（iOS 锁屏 / 灵动岛）
///
/// 这一组测试守两件事：
///   1. **什么时候该开、什么时候该撤** —— 尤其是"跳过休息"和"休息自然走完"
///      这两个分支（只撤界面不撤锁屏，用户放下手机就会看到一条永远数不完的倒计时）；
///   2. **倒计时在 App 被挂起之后还准不准** —— 这是 2026-10-04 顺手抓到的一个**真 bug**：
///      旧实现是"每秒减一"，而 App 被系统挂起时 Dart 定时器不走，
///      回来之后剩余时间会把被挂起的那段白送掉；而锁屏上系统走的倒计时是准的，
///      于是同一个事实在两个界面上对不上。
library;

import 'package:flutter/services.dart';
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
  defaultRestSec: 180,
);

const PlanTarget _plan = PlanTarget(
  targetSets: 3,
  targetRepsLow: 8,
  targetRepsHigh: 10,
);

/// 记下"该开的时候开了没有、该撤的时候撤了没有"的替身。
class FakeRestActivity implements RestActivityBridge {
  final List<RestActivityInfo> started = <RestActivityInfo>[];
  int ended = 0;

  @override
  Future<void> start(RestActivityInfo info) async => started.add(info);

  @override
  Future<void> end() async => ended++;

  @override
  Future<int> activeCount() async => started.length - ended;
}

WorkoutController _controller({
  RestActivityBridge? bridge,
  int Function()? clock,
  int? restOverrideSec,
}) =>
    WorkoutController(
      exercise: _squat,
      plan: _plan,
      analytics: RecordingAnalytics(),
      store: InMemoryLocalStore(),
      syncQueue: InMemorySyncQueue(),
      profile: UserProfile(restOverrideSec: restOverrideSec),
      clock: clock,
      restActivity: bridge ?? const NoopRestActivity(),
    );

void main() {
  group('该开的时候开、该撤的时候撤', () {
    test('记一组 → 广播这次休息；结束时刻 = 现在 + 这个动作的休息时长', () async {
      final FakeRestActivity bridge = FakeRestActivity();
      int now = 1000000;
      final WorkoutController c =
          _controller(bridge: bridge, clock: () => now);

      c.onBigButtonTap();

      expect(bridge.started, hasLength(1), reason: '记完一组就该在锁屏上看到倒计时');
      final RestActivityInfo info = bridge.started.single;
      expect(info.exerciseName, '杠铃深蹲');
      // ⚠️ 是**下一组**的序号（记完第 1 组之后锁屏上该写"第 2/3 组"），
      // 与大按钮上方那个"第 N 组"是同一个数 —— 所以直接跟控制器对账，别写死。
      expect(info.setIndex, c.setNumber);
      expect(info.setIndex, 2);
      expect(info.totalSets, 3);
      // 深蹲自带 180 秒
      expect(info.endAtMs, now + 180 * 1000);
      expect(info.nextLabel, isNotEmpty,
          reason: '锁屏上必须写清"下一组练什么"，那正是这个功能的一半价值');
    });

    test('跳过休息 → 锁屏上那条也要撤（不能只撤界面）', () async {
      final FakeRestActivity bridge = FakeRestActivity();
      final WorkoutController c = _controller(bridge: bridge);

      c.onBigButtonTap();
      c.skipRest();

      expect(bridge.ended, 1);
    });

    test('退出训练屏 → 撤掉（否则用户放下手机会看到一条永远数不完的倒计时）', () {
      final FakeRestActivity bridge = FakeRestActivity();
      final WorkoutController c = _controller(bridge: bridge);

      c.onBigButtonTap();
      c.dispose();

      expect(bridge.ended, greaterThanOrEqualTo(1));
    });

    testWidgets('休息自然走完 → 也要撤', (WidgetTester tester) async {
      final FakeRestActivity bridge = FakeRestActivity();
      int now = 1000000;
      final WorkoutController c = _controller(
          bridge: bridge, clock: () => now, restOverrideSec: 30);

      c.onBigButtonTap();
      expect(bridge.started, hasLength(1));
      expect(bridge.ended, 0);

      now += 30000; // 30 秒过完
      await tester.pump(const Duration(seconds: 1)); // 让那一跳跑起来

      expect(bridge.ended, 1, reason: '倒计时归零时锁屏上那条必须撤下');
      c.dispose();
    });
  });

  group('倒计时：被系统挂起之后还准不准（2026-10-04 修的真 bug）', () {
    testWidgets('★ 挂起 20 秒再回来：剩余时间按真实时刻重算，而不是接着旧数字减',
        (WidgetTester tester) async {
      int now = 1000000;
      final WorkoutController c =
          _controller(clock: () => now, restOverrideSec: 60);

      c.onBigButtonTap();
      expect(c.restRemainingSec, 60);

      // App 被挂起 20 秒：这期间 Dart 的定时器**一跳都没走**
      now += 20000;
      await tester.pump(const Duration(seconds: 1));

      expect(c.restRemainingSec, 40,
          reason: '旧实现会显示 59（被挂起的那 20 秒白送了）—— '
              '而锁屏上系统按结束时刻走，会显示 40，两个界面当场对不上');
      c.dispose();
    });

    testWidgets('挂起时间超过整段休息 → 直接判定结束，而不是显示负数',
        (WidgetTester tester) async {
      final FakeRestActivity bridge = FakeRestActivity();
      int now = 1000000;
      final WorkoutController c = _controller(
          bridge: bridge, clock: () => now, restOverrideSec: 30);

      c.onBigButtonTap();
      now += 90000; // 挂了 90 秒才回来
      await tester.pump(const Duration(seconds: 1));

      expect(c.restRemainingSec, 0);
      expect(c.restRunning, isFalse);
      expect(bridge.ended, 1, reason: '结束的那一刻也要把锁屏上那条撤下');
      c.dispose();
    });
  });

  group('通道载荷（Swift 那边按这些键取值）', () {
    testWidgets('start / end / activeCount 的方法名与字段名', (WidgetTester tester) async {
      final List<MethodCall> calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannelRestActivity.channel,
        (MethodCall call) async {
          calls.add(call);
          if (call.method == 'activeCount') return 3;
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannelRestActivity.channel, null));

      const MethodChannelRestActivity bridge = MethodChannelRestActivity();
      await bridge.start(const RestActivityInfo(
        exerciseName: '杠铃卧推',
        nextLabel: '62.5 kg × 8',
        setIndex: 2,
        totalSets: 4,
        endAtMs: 1790612345678,
      ));
      await bridge.end();
      final int count = await bridge.activeCount();

      expect(count, 3);
      expect(calls.map((MethodCall c) => c.method).toList(),
          <String>['start', 'end', 'activeCount']);
      final Map<Object?, Object?> args =
          calls.first.arguments as Map<Object?, Object?>;
      expect(args.keys.toSet(), <String>{
        'exerciseName',
        'nextLabel',
        'setIndex',
        'totalSets',
        'endAtMs',
      });
      expect(args['nextLabel'], '62.5 kg × 8');
    });

    testWidgets('平台上没有这个通道时**静默**（Android / 老 iOS / 测试环境）',
        (WidgetTester tester) async {
      // 显式让 handler 抛 MissingPluginException —— 这才是 Android / 老 iOS 上的真实形状
      // （不装 handler 的写法依赖未处理通道的行为，会挂住测试进程）。
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannelRestActivity.channel,
        (MethodCall call) async => throw MissingPluginException('没有实现'),
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannelRestActivity.channel, null));

      const MethodChannelRestActivity bridge = MethodChannelRestActivity();

      await expectLater(
        bridge.start(const RestActivityInfo(
          exerciseName: 'x',
          nextLabel: 'y',
          setIndex: 1,
          totalSets: 1,
          endAtMs: 0,
        )),
        completes,
        reason: '锁屏上少一个倒计时，绝不该让训练屏记不了组（北极星指标）',
      );
      await expectLater(bridge.end(), completes);
      expect(await bridge.activeCount(), 0);
    });
  });
}
