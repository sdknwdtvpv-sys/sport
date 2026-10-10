/// 练了么 · **休息归零那一帧 + 3 秒预告**（VI 计划 T2-4，2026-10-10）
///
/// `PRODUCT.md` §1 说这个 App 服务的唯一场景是"组间休息的 60 秒"——
/// **这 60 秒的终点是整个产品最该被设计好的一帧**。用户此时多半在看器械或手机背面，
/// 他需要一个"到了"的信号，而且这个信号要**视觉与触觉同时发生**。
///
/// 这一条之前规格书自己在三处写了三种行为（§6 说"不震动"、§8 说"success notification"、
/// `haptics.dart` 是 `heavyImpact`），实现只做了触觉那一半。现在：
///   * **归零那一帧**：文字与颜色换 `success`／「休息结束」**与** `heavyImpact` 在同一个同步块里；
///   * **还剩 3 秒**：数字转 accent（视觉）+ 一次 `selectionClick`（触觉）—— 预告，不是提示；
///     **只响一次**、比到点轻两档、总时长 ≤ 5 秒的休息不发。
///
/// 判据就是计划里那四条（另加一条源码自检）。
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
  int sets = 0;
  int rests = 0;
  int targets = 0;
  int previews = 0;

  @override
  Future<void> setLogged() async => sets += 1;

  @override
  Future<void> restFinished() async => rests += 1;

  @override
  Future<void> restPreview() async => previews += 1;

  @override
  Future<void> targetReached() async => targets += 1;
}

class _Harness {
  _Harness({int restSec = 60}) {
    controller = WorkoutController(
      exercise: restSec == 60
          ? _bench
          : const ExerciseSpec(
              id: 'ex_bb_bench_press',
              name: '杠铃卧推',
              weightIncrement: 2.5,
              defaultWeightKg: 40,
              defaultRestSec: 3,
            ),
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

  void advance(int ms) => _t += ms;
  void dispose() => controller.dispose();
}

Future<void> _pump(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: WorkoutScreen(session: WorkoutSession.single(h.controller)),
  ));
  await tester.pump();
  // 记一组 → 休息自动开始
  await tester.tap(find.byKey(const Key('big-log-button')));
  await tester.pump();
}

/// 把假钟与 `tester.pump` 一起往前推 [sec] 秒（每秒一跳）。
Future<void> _tick(WidgetTester tester, _Harness h, int sec) async {
  for (int i = 0; i < sec; i++) {
    h.advance(1000);
    await tester.pump(const Duration(seconds: 1));
  }
}

Color _timeColor(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('rest-time'))).style!.color!;

void main() {
  testWidgets('休息归零那一帧：文案转「休息结束」+ 一次 heavyImpact', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);
    expect(h.haptics.rests, 0, reason: '刚记完一组，休息才刚开始');

    await _tick(tester, h, 60);
    await tester.pump();

    expect(find.text('休息结束'), findsOneWidget);
    expect(h.haptics.rests, 1, reason: '归零那一下要震（不看屏幕时只有它）');
    expect(_timeColor(tester), Tokens.accent);
    h.dispose();
  });

  testWidgets('休息归零那一帧立刻点大按钮，新组仍写入', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);
    final int before = h.controller.loggedSets.length;

    await _tick(tester, h, 60); // 走到 0
    // **不 settle**：归零那一帧就点下去 —— 防"动画/状态切换把主按钮吃掉"
    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    expect(h.controller.loggedSets.length, before + 1,
        reason: '归零那一帧点下去也必须记上（1 次点击 = 1 组在这 60 秒的终点上也不能破）');
    h.dispose();
  });

  testWidgets('restTotalSec = 60 时预告触觉恰好一次', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    await _tick(tester, h, 56); // 剩 4 秒
    expect(h.haptics.previews, 0, reason: '还剩 4 秒时不该预告');

    await _tick(tester, h, 1); // 剩 3 秒 → 预告
    expect(h.haptics.previews, 1);
    expect(_timeColor(tester), Tokens.accent, reason: '预告与颜色变化是同一刻');

    await _tick(tester, h, 1); // 剩 2 秒
    await _tick(tester, h, 1); // 剩 1 秒
    expect(h.haptics.previews, 1, reason: '不是 3-2-1 三下，也不是每秒一次');

    await _tick(tester, h, 3); // 归零
    expect(h.haptics.previews, 1, reason: '归零是"到点"，不是又一次预告');
    expect(h.haptics.rests, 1);
    h.dispose();
  });

  testWidgets('总时长 ≤ 5 秒的休息不发预告', (WidgetTester tester) async {
    final _Harness h = _Harness(restSec: 3);
    await _pump(tester, h);
    await _tick(tester, h, 5);
    expect(h.haptics.previews, 0,
        reason: '本来就短的休息里，"还剩 3 秒"几乎就是"开始" —— 发了等于两次提示挤在一起');
    expect(h.haptics.rests, 1, reason: '到点那一下仍然要震');
    h.dispose();
  });

  testWidgets('还剩 10 秒时按 +15：预告还没到，之后仍然只响一次',
      (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    await _tick(tester, h, 50); // 剩 10 秒
    await tester.tap(find.byKey(const Key('rest-plus')));
    await tester.pump();
    expect(h.haptics.previews, 0);

    // +15 之后剩 25 秒 —— 走到剩 3 秒（22 秒）
    await _tick(tester, h, 22);
    expect(h.haptics.previews, 1, reason: '预告时刻跟着新的结束时刻重算');
    await _tick(tester, h, 4);
    expect(h.haptics.previews, 1, reason: '重算之后也只响一次');
    h.dispose();
  });

  test('反向自检：归零分支里颜色/文案的切换与触觉在同一个同步块（没有 await）', () {
    final String src =
        File('lib/features/workout/workout_controller.dart').readAsStringSync();
    final int i = src.indexOf('haptics.restFinished()');
    expect(i, greaterThan(0), reason: '找不到 restFinished 的调用点');
    // 从 `if (left <= 0) {` 到 `haptics.restFinished()` 之间不许出现 await ——
    // 那意味着"震动"要等一个异步操作，掉帧时就会与视觉脱开。
    final int start = src.lastIndexOf('if (left <= 0)', i);
    expect(start, greaterThan(0));
    final String block = src.substring(start, i);
    expect(block.contains('await '), isFalse,
        reason: '归零那一帧的视觉切换与触觉必须在同一个同步块里');
    expect(RegExp(r'_restPreviewed\s*=\s*true').hasMatch(src), isTrue,
        reason: '预告要记"发过了"，否则每秒都会响一次');
  });
}
