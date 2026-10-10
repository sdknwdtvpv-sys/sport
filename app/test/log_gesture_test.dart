/// 练了么 · **记一组的完整确认链**（VI 计划 T2-2，2026-10-10）
///
/// 这是**全产品调用最频繁的一次交互**（一次训练 12–25 次），
/// 而它原来是"一行字瞬间出现 + 手机震一下"。规格书里其实写着两条
/// （§5 按压缩放 0.975 / 100ms、§8 新行 pop 入场 280ms）——**两条都只写在纸上**。
///
/// 在"组间 60 秒、屏幕有汗、注意力在器械上"的场景里，这直接对应 `PRODUCT.md` §5
/// 那条硬约束「1 次点击 = 1 组」的**可信度**：按下去没有回应，用户就会再点一次 —— 那是两组。
///
/// 判据（与计划一致）：
///   1. **长按滑出按钮不误记一组**，且按钮缩放回到 1.0；
///   2. 新行入场**真的在动**（140ms 时透明度严格在 0 与 1 之间）；
///   3. 触觉与 `setState` 在同一个同步块里（源码扫描：那两行之间没有 `await`）；
///   4. `haptics.dart` 里没有 `Future.delayed`（它**不可取消**）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/analytics.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/sync_queue.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/workout/haptics.dart';
import 'package:lianleme/features/workout/workout_controller.dart';
import 'package:lianleme/features/workout/workout_screen.dart';
import 'package:lianleme/features/workout/workout_session.dart';

const ExerciseSpec _bench = ExerciseSpec(
  id: 'ex_bb_bench_press',
  name: '杠铃卧推',
  weightIncrement: 2.5,
  defaultWeightKg: 40,
  defaultRestSec: 60,
);

const PlanTarget _plan = PlanTarget(
  targetSets: 5,
  targetRepsLow: 8,
  targetRepsHigh: 10,
);

class _FakeHaptics implements Haptics {
  final List<HapticCue> cues = <HapticCue>[];

  @override
  Future<void> play(HapticCue cue) async => cues.add(cue);

  @override
  void cancelPending() {}
}

class _Harness {
  _Harness() {
    controller = WorkoutController(
      exercise: _bench,
      plan: _plan,
      analytics: RecordingAnalytics(),
      store: InMemoryLocalStore(),
      syncQueue: InMemorySyncQueue(),
      haptics: haptics,
      clock: () => _t,
    );
  }

  final _FakeHaptics haptics = _FakeHaptics();
  late final WorkoutController controller;
  int _t = 1000000;

  void dispose() => controller.dispose();
}

Future<void> _pump(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: WorkoutScreen(session: WorkoutSession.single(h.controller)),
  ));
  await tester.pump();
}

/// 大按钮上那一层的目标缩放值（`AnimatedScale.scale`）。
double _buttonScale(WidgetTester tester) => tester
    .widget<AnimatedScale>(find.descendant(
      of: find.byKey(const Key('big-log-button')),
      matching: find.byType(AnimatedScale),
    ))
    .scale;

void main() {
  testWidgets('按下 → 缩到 0.975；抬手 → 回 1.0，并记上一组', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);
    expect(_buttonScale(tester), 1.0);

    final TestGesture g =
        await tester.startGesture(tester.getCenter(find.byKey(const Key('big-log-button'))));
    // ⚠️ 要 `pump` 过 `kPressTimeout`（100ms）：`onTapDown` 不是在指针按下的那一刻
    // 就回调的（手势竞技场里还有长按那一位在争），Flutter 给它 100ms 的判定窗口。
    await tester.pump(const Duration(milliseconds: 120));
    expect(_buttonScale(tester), 0.975, reason: '手指按下去必须有回应（规格 §5）');

    await g.up();
    await tester.pumpAndSettle();
    expect(_buttonScale(tester), 1.0);
    expect(h.controller.loggedSets.length, 1);
    expect(h.haptics.cues, contains(HapticCue.setLogged));
    h.dispose();
  });

  testWidgets('长按滑出按钮不误记一组', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    final TestGesture g =
        await tester.startGesture(tester.getCenter(find.byKey(const Key('big-log-button'))));
    await tester.pump(const Duration(milliseconds: 120));
    expect(_buttonScale(tester), 0.975);

    // 手指滑出按钮（`onTapCancel`）—— 这是最容易漏的那条路
    await g.moveBy(const Offset(0, 200));
    await tester.pump();
    expect(_buttonScale(tester), 1.0, reason: '滑出去就该弹回来，不能保持"按过"的样子');

    await g.up();
    await tester.pumpAndSettle();
    expect(h.controller.loggedSets, isEmpty, reason: '滑出手指 ≠ 记一组');
    expect(h.haptics.cues, isEmpty, reason: '没记上就不许震（震了用户会以为记上了）');
    h.dispose();
  });

  testWidgets('新行入场在 140ms 时透明度严格在 0 与 1 之间', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump(); // 新行出现的那一帧
    final String id = h.controller.loggedSets.first.id;

    await tester.pump(const Duration(milliseconds: 140));
    final Finder fade = find.byKey(Key('done-row-fade-$id-opacity'));
    expect(fade, findsOneWidget, reason: '入场那一层要在（`_popIn`）');
    final double t = tester.widget<Opacity>(fade).opacity;
    expect(t, greaterThan(0.0), reason: '140ms 时透明度 = $t —— 还在起点就是"瞬现"');
    expect(t, lessThan(1.0), reason: '140ms 时透明度 = $t —— 已经到终点就等于没有动画');

    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(fade).opacity, 1.0);
    h.dispose();
  });

  testWidgets('连点两下：两行**各自**入场，不排队（不是 AnimatedList）',
      (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 140));

    expect(h.controller.loggedSets.length, 2);
    // 第二行也在动（如果排在一个队列后面，它这一刻还没开始 = 透明度还是 0）
    final String second = h.controller.loggedSets[1].id;
    final double t = tester
        .widget<Opacity>(find.byKey(Key('done-row-fade-$second-opacity')))
        .opacity;
    expect(t, greaterThan(0.0),
        reason: '健身房里连点两下是常态 —— 第二行不许排队等第一行播完（迟到 = 用户会再点一次）');
    h.dispose();
  });

  testWidgets('减弱动态效果下：行直接到位（不用等）', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: WorkoutScreen(session: WorkoutSession.single(h.controller)),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    final String id = h.controller.loggedSets.first.id;
    expect(find.byKey(Key('done-row-fade-$id')), findsNothing,
        reason: '减弱动态效果时不套那一层（直接给终值）');
    h.dispose();
  });

  test('反向自检：触觉与 setState 写在同一个同步块里（中间没有 await）', () {
    final String src =
        File('lib/features/workout/workout_controller.dart').readAsStringSync();
    final int i = src.indexOf('haptics.play(HapticCue.setLogged)');
    expect(i, greaterThan(0), reason: '找不到记一组的触觉调用点');
    // 判据取"从触觉调用到紧随其后的 `_notify()` 之间不许有 await"：
    // 那一段就是"视觉更新 + 震动"该在的同一个同步块。出现 await 就意味着
    // "视觉已经变了、震动还在等一个异步操作"——掉帧时用户会觉得那一下没记上。
    final int notify = src.indexOf('_notify();', i);
    expect(notify, greaterThan(i), reason: '记完一组要在同一个同步块里 _notify()');
    final String block = src.substring(i, notify);
    expect(block.contains('await '), isFalse,
        reason: '触觉与 _notify() 之间出现了 await（两者被拆到了两个同步块）');
  });

  test('反向自检：haptics.dart 里不许有 Future.delayed（它不可取消）', () {
    final String src = File('lib/features/workout/haptics.dart').readAsStringSync();
    expect(src.contains('Future.delayed'), isFalse,
        reason: '"两下"的间隔要用**可取消**的 Timer —— 用户离开这一屏时第二下不该再震');
    expect(src.contains('cancelPending'), isTrue,
        reason: '可取消这件事要真的接出来（`WorkoutController.dispose` 里调它）');
    // 控制器确实在 dispose 里掐了它
    final String ctrl =
        File('lib/features/workout/workout_controller.dart').readAsStringSync();
    expect(ctrl.contains('haptics.cancelPending()'), isTrue);
  });

  test('时长来自令牌：按压 100ms、入场 260ms（不是字面量）', () {
    final String src =
        File('lib/features/workout/workout_screen.dart').readAsStringSync();
    expect(src.contains('Motion.instant'), isTrue, reason: '按压缩放走 Motion.instant（100ms）');
    expect(src.contains('Motion.base'), isTrue,
        reason: '新行入场走 Motion.base（260ms）—— 规格写 280ms，令牌里最近的一档是它（T1-4 的裁决）');
  });
}
