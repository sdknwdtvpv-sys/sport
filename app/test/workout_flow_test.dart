/// 练了么 · 训练主屏 widget 测试
///
/// 这是 `docs/interaction-spec.md` §12「设计验收清单」的自动化版本。
/// 覆盖三条最容易在迭代中被改坏的规则：
///   1. 1 次点击 = 1 组（tap_count 中位数必须为 1）
///   2. 长按不误记
///   3. 离线可用、且训练中不发网络请求
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/analytics.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/sync_queue.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/domain/tap_meter.dart';
import 'package:lianleme/features/workout/haptics.dart';
import 'package:lianleme/features/workout/workout_controller.dart';
import 'package:lianleme/features/workout/workout_screen.dart';
import 'package:lianleme/features/workout/workout_session.dart';

/// 与 seed/exercises.json 的 ex_bb_bench_press 保持一致。
const ExerciseSpec _bench = ExerciseSpec(
  id: 'ex_bb_bench_press',
  name: '杠铃卧推',
  weightIncrement: 2.5,
  defaultWeightKg: 40,
  defaultRestSec: 120,
);

/// 与 seed 里的 ex_treadmill_incline_walk 一致：按距离记（用来测"没设距离时那一下不算"）。
const ExerciseSpec _treadmill = ExerciseSpec(
  id: 'ex_treadmill_incline_walk',
  name: '跑步机爬坡走',
  weightIncrement: 0,
  defaultWeightKg: null,
  defaultRestSec: 60,
  trackType: 'distance_time',
);

const PlanTarget _plan3x8to10 = PlanTarget(
  targetSets: 3,
  targetRepsLow: 8,
  targetRepsHigh: 10,
);

/// 记下"该震的时候震了没有"的替身（v1.53）。真机上的震动测不了，
/// 但"什么时候该调它"是逻辑，必须钉住 —— 尤其是**没记上那一组不许震**。
class _FakeHaptics implements Haptics {
  int sets = 0;
  int rests = 0;
  int targets = 0;

  @override
  Future<void> setLogged() async => sets += 1;

  @override
  Future<void> restFinished() async => rests += 1;

  @override
  Future<void> targetReached() async => targets += 1;
}

class _Harness {
  _Harness({LastSession? lastSession}) : this._(exercise: _bench, lastSession: lastSession);

  /// 距离动作那条路（没设距离时 `canLog=false`）。
  _Harness.distance() : this._(exercise: _treadmill);

  _Harness._({required ExerciseSpec exercise, LastSession? lastSession}) {
    controller = WorkoutController(
      exercise: exercise,
      plan: _plan3x8to10,
      analytics: analytics,
      store: store,
      syncQueue: syncQueue,
      haptics: haptics,
      lastSession: lastSession,
      // 钟是**单调递增的毫秒**（每次取值 +1，保证时间戳各不相同），
      // 而测试可以用 [advance] 把它一次推过去 —— 因为休息倒计时现在
      // **按墙上时钟算**（`_restEndsAtMs - now`），不再"每秒减一"。
      // 后者在 App 被系统挂起时会白送掉挂起的那段时间，见 `rest_activity_test.dart`。
      clock: () => _t++,
    );
  }



  final RecordingAnalytics analytics = RecordingAnalytics();
  final _FakeHaptics haptics = _FakeHaptics();
  final InMemoryLocalStore store = InMemoryLocalStore();
  final InMemorySyncQueue syncQueue = InMemorySyncQueue();
  late final WorkoutController controller;

  int _t = 1000;

  /// 把假时钟往前推 [ms] 毫秒（与 `tester.pump(Duration)` 配对使用）。
  ///
  /// 休息倒计时现在**按墙上时钟算**（`_restEndsAtMs - now`），不再"每秒减一"——
  /// 后者在 App 被系统挂起时会白送掉挂起的那段时间（见 `rest_activity_test.dart`）。
  /// 所以测"倒计时真的在走"必须**同时**推进这个假钟与 `tester.pump`。
  void advance(int ms) => _t += ms;

  List<Map<String, Object?>> get setEvents => analytics.propsOf('set_logged');
}

Future<void> _pump(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      // 单动作会话：多动作切换的测试在 workout_session_test.dart 里
      home: WorkoutScreen(session: WorkoutSession.single(h.controller)),
    ),
  );
}

/// 必须显式销毁页面并 dispose 控制器，否则 Timer.periodic 会留下 pending timer，
/// testWidgets 会直接判失败。这是 widget 测试里最常见的假失败来源。
Future<void> _teardown(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  h.controller.dispose();
}

void main() {
  testWidgets('点大按钮 = 记录 1 组，tap_count = 1', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    expect(find.text('40 kg × 8'), findsOneWidget, reason: '按钮上就是要写入的值');

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    expect(h.controller.loggedSets.length, 1);
    expect(h.setEvents.length, 1);
    expect(h.setEvents.single['tap_count'], 1);
    expect(h.setEvents.single['tap_kinds'], <String>['big_button']);
    expect(h.setEvents.single['weight_kg'], 40);

    await _teardown(tester, h);
  });

  testWidgets('连点两次 = 两条记录，各自 tap_count = 1', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    expect(h.controller.loggedSets.length, 2);
    expect(
      h.setEvents.map((Map<String, Object?> p) => p['tap_count']).toList(),
      <int>[1, 1],
      reason: '两次点击必须是两个独立周期，不能被合并计数',
    );

    await _teardown(tester, h);
  });

  testWidgets('长按不误记：弹出修改层，且不产生任何记录', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    await tester.longPress(find.byKey(const Key('big-log-button')));
    await tester.pump();

    expect(h.controller.loggedSets, isEmpty, reason: '长按绝不能顺手记一组');
    expect(h.analytics.countOf('set_logged'), 0);
    expect(find.byKey(const Key('sheet')), findsOneWidget);
    expect(h.controller.sheetOpen, isTrue);

    await _teardown(tester, h);
  });

  testWidgets('长按 → 改重量 → 确定 → 记录：tap_count = 4，且新重量生效',
      (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    await tester.longPress(find.byKey(const Key('big-log-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('step-weight-up'))); // 40 → 42.5
    await tester.pump();
    await tester.tap(find.byKey(const Key('sheet-confirm')));
    await tester.pump();
    expect(find.byKey(const Key('sheet')), findsNothing);

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    expect(h.setEvents.single['tap_count'], 4);
    expect(h.setEvents.single['weight_kg'], 42.5);
    expect(h.controller.loggedSets.single.weightKg, 42.5);

    await _teardown(tester, h);
  });

  testWidgets('端到端口径：控制器被构造之前的导航点击也要算进第一组',
      (WidgetTester tester) async {
    // 模拟**走建议卡那条路**（首页「看看今天练什么」→ 卡片「开始训练」= 两次导航点击）：
    // 进入时先开周期并记下这两下，等卡片走完才构造控制器。
    // 构造函数里若调 begin() 就会把它们清零 —— 那正是"只算大按钮"的窄口径，
    // 会让闸门自我满足。
    //
    // 首页现在一跳直开练（只 1 次 nav），但"累计"这个不变量必须守住：
    // 少了它，建议卡那条路又会回到窄口径。
    final RecordingAnalytics analytics = RecordingAnalytics();
    analytics.beginSetInteraction();
    analytics.countTap(TapKind.nav); // 今日页那一下
    analytics.countTap(TapKind.nav); // 建议卡「就用这个，开始练」

    final WorkoutController controller = WorkoutController(
      exercise: _bench,
      plan: _plan3x8to10,
      analytics: analytics,
      store: InMemoryLocalStore(),
      syncQueue: InMemorySyncQueue(),
      clock: () => 1000,
    );

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: WorkoutScreen(session: WorkoutSession.single(controller)),
    ));

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    final Map<String, Object?> props = analytics.propsOf('set_logged').single;
    expect(props['tap_count'], 3,
        reason: '今日页 → 建议卡 → 大按钮 = 3 次；记成 1 就是窄口径在骗自己');
    expect(props['tap_kinds'], <String>['nav', 'nav', 'big_button']);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('长按已完成的那一行 → 撤销这一组（误触的后悔药）',
      (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();
    expect(h.controller.loggedSets, hasLength(1));
    final String id = h.controller.loggedSets.single.id;

    await tester.longPress(find.byKey(Key('done-set-$id')));
    await tester.pumpAndSettle();

    expect(h.controller.loggedSets, isEmpty, reason: '那一行要真的消失');
    expect(h.controller.setNumber, 1, reason: '计划进度也要退回，否则"第 2 组"是假的');
    expect(h.controller.hint, contains('已撤销'));

    // 埋点：撤销要能被统计到（analytics.md 的事件字典里有 set_undone）
    final Map<String, Object?> undone = h.analytics.propsOf('set_undone').single;
    expect(undone['set_index'], 1);
    expect(undone['method'], 'longpress');

    // 同步队列要带上删除动作（否则服务端永远不知道这组没了）
    expect(h.syncQueue.pending, greaterThan(0));

    // 本地库也要真的删掉（软删除），否则重启又冒出来
    expect(await h.store.setsFor(h.controller.workout.id), isEmpty);

    await _teardown(tester, h);
  });

  testWidgets('撤销之后大按钮上的值不变 —— 可以直接再点一下补回来',
      (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();
    final String id = h.controller.loggedSets.single.id;
    await tester.longPress(find.byKey(Key('done-set-$id')));
    await tester.pumpAndSettle();

    expect(find.text('40 kg × 8'), findsOneWidget, reason: '值没变，手抖点快了再点一下就回来了');

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();
    expect(h.controller.loggedSets, hasLength(1));
    expect(h.analytics.propsOf('set_logged'), hasLength(2), reason: '这是新的一条记录');

    await _teardown(tester, h);
  });

  testWidgets('离线可用：记录照常成功、进同步队列、界面不报错', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    h.controller.setOffline(true);
    await tester.pump();
    expect(find.byKey(const Key('offline-chip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    expect(h.controller.loggedSets.length, 1, reason: '离线必须能完整记录');
    expect(h.syncQueue.pending, 1, reason: '写入进队列，等联网后补报');
    expect(h.setEvents.single['is_offline'], isTrue);
    expect(find.textContaining('失败'), findsNothing, reason: '离线不允许弹错误 UI');

    // 恢复网络后补报成功，队列清空
    h.controller.setOffline(false);
    await tester.pump();
    final SyncOutcome outcome = await h.controller.flushSync();
    expect(outcome, SyncOutcome.ok);
    expect(h.syncQueue.pending, 0);

    await _teardown(tester, h);
  });

  testWidgets('★ 做满计划组数之后：底部换成两个明确的出口（10.8 清单第 3 条）',
      (WidgetTester tester) async {
    // 用户原话："推荐的四组，四组做完后给选项：跳转到下个动作或者加一组挑战下自己。"
    // 之前只有一行小字（隐式出口），现在是一颗按钮（动作）+ 一条去路。
    final _Harness h = _Harness();
    await _pump(tester, h);

    // 还没做满：底部还是那行解释大按钮的小字
    expect(find.byKey(const Key('planned-done-row')), findsNothing);

    for (int i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('big-log-button')));
      await tester.pump();
    }
    expect(h.controller.loggedSets.length, 3, reason: '计划的 3 组做满了');

    // 做满的那一刻：两个出口出现，那行小字让位
    expect(find.byKey(const Key('planned-done-row')), findsOneWidget);
    expect(find.byKey(const Key('add-extra-set')), findsOneWidget);
    expect(find.byKey(const Key('planned-done-next')), findsOneWidget);
    expect(find.byKey(const Key('workout-hint')), findsNothing,
        reason: '做满之后那行小字说不清"还能干什么"，换成按钮');

    // 「再加一组」= 立刻再记一组（**计划是建议不是牢笼** 这条不许退化）
    await tester.tap(find.byKey(const Key('add-extra-set')));
    await tester.pump();
    expect(h.controller.loggedSets.length, 4,
        reason: '禁止加组会逼用户回备忘录 —— 计划是建议不是牢笼');

    // 单动作会话 → 右侧那颗是「结束训练」
    expect(
      tester.widget<Text>(find.descendant(
        of: find.byKey(const Key('planned-done-next')),
        matching: find.byType(Text),
      )).data,
      '结束训练',
      reason: '没有下一个动作时（单动作）这里就是结束训练',
    );

    await _teardown(tester, h);
  });

  testWidgets('★ 休息时长跟着你实际歇的节奏（10.8 清单第 2 条）',
      (WidgetTester tester) async {
    // 用户原话："根据过往训练中的休息时长动态调整后面同一个动作的休息时间"。
    // 判据是**确定的**：本场同动作已歇 ≥ 2 次 → 取中位数（5 秒取整），
    // 夹在动作自带值的 0.5×～2× 之间。杠铃卧推自带 120 秒 → 夹在 [60, 240]。
    final _Harness h = _Harness();
    await _pump(tester, h);

    expect(h.controller.plannedRestSec, 120);
    expect(h.controller.observedRestCount, 0);
    expect(h.controller.restIsAdaptive, isFalse, reason: '还没有数据就不许"自适应"');
    expect(h.controller.nextRestSec, 120, reason: '没有数据时就是计划值');

    // 第 1 组 → 实际歇 150 秒 → 第 2 组 → 实际歇 170 秒 → 第 3 组
    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();
    h.advance(150 * 1000);
    await tester.pump();
    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();
    h.advance(170 * 1000);
    await tester.pump();
    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    expect(h.controller.observedRestCount, 2, reason: '三条记录之间有两次间隔');
    // 中位数 = 170（偶数个取上中位）→ 170 → 落在 [60,240] 内
    expect(h.controller.nextRestSec, 170);
    expect(h.controller.restIsAdaptive, isTrue);

    // 界面上要说出来（否则用户以为 App 偷偷改了休息时间）
    expect(find.textContaining('按你的节奏'), findsOneWidget);

    // ⚠️ 它**不改设置**：动作自带值与"这一场"的计划值一个字节都不动
    expect(h.controller.plannedRestSec, 120,
        reason: '自适应只影响这一场接下来的默认值，不写回任何设置');

    await _teardown(tester, h);
  });

  testWidgets('训练中不重算建议（建议是本次训练的处方）', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    final String? before =
        tester.widget<Text>(find.byKey(const Key('suggestion-reason'))).data;

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    final String? after =
        tester.widget<Text>(find.byKey(const Key('suggestion-reason'))).data;

    expect(after, before,
        reason: '每组后重算会让提示立刻变成「上次只完成 1 组，先把组数补满」这种荒谬文案');

    await _teardown(tester, h);
  });

  testWidgets('记录后自动开始休息计时，跳过可结束', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();
    expect(h.controller.restRunning, isTrue);
    expect(h.controller.restRemainingSec, 120);

    h.advance(1000); // 真实世界过了 1 秒（倒计时按墙上时钟算）
    await tester.pump(const Duration(seconds: 1));
    expect(h.controller.restRemainingSec, 119, reason: '倒计时必须真的走');

    await tester.tap(find.byKey(const Key('skip-rest')));
    await tester.pump();
    expect(h.controller.restRunning, isFalse);
    expect(find.text('休息结束'), findsOneWidget);
    expect(h.analytics.countOf('rest_skipped'), 1);

    await _teardown(tester, h);
  });

  testWidgets('记录会落到本地库（本地优先），并写入同步队列', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    final List<SetRecord> stored = await h.store.setsFor(h.controller.workout.id);
    expect(stored.length, 1);
    expect(h.controller.workout.totalSets, 1);
    expect(h.controller.workout.totalVolume, 320); // 40kg × 8

    await _teardown(tester, h);
  });

  testWidgets('S5 弹层里选 RPE → 记录带上它 → 完成列表里看得见', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    expect(h.controller.rpe, isNull, reason: '默认不记');

    await tester.longPress(find.byKey(const Key('big-log-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rpe-8')));
    await tester.pumpAndSettle();
    expect(h.controller.rpe, 8);

    await tester.tap(find.byKey(const Key('sheet-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    expect(h.controller.loggedSets.single.rpe, 8);
    expect(h.setEvents.single['rpe'], 8);
    // 只写库不显示 = 用户看不见的隐藏数据
    expect(find.text('RPE 8'), findsOneWidget);

    await _teardown(tester, h);
  });

  testWidgets('再点一次已选中的 RPE 即清除（不需要额外的清除按钮）',
      (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    await tester.longPress(find.byKey(const Key('big-log-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rpe-7')));
    await tester.pumpAndSettle();
    expect(h.controller.rpe, 7);

    await tester.tap(find.byKey(const Key('rpe-7')));
    await tester.pumpAndSettle();
    expect(h.controller.rpe, isNull, reason: '再点一次同一个值 = 清除');

    await _teardown(tester, h);
  });

  testWidgets('RPE 不影响计划进度与引擎判定（它只是可选记录）',
      (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    h.controller.setRpe(10);
    await tester.pump();
    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    expect(h.controller.setNumber, 2, reason: '记了 RPE 仍然是正式组，照常推进');
    expect(h.controller.workout.totalSets, 1);
    expect(h.controller.workout.totalVolume, 320);

    await _teardown(tester, h);
  });

  // ---------- S5 热身组（规格要求的弱化控件，此前只有数据层没有入口）----------

  testWidgets('长按 → 点「热身组」→ 确定 → 记录：这一组是热身，不吃掉计划进度',
      (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    expect(h.controller.setNumber, 1, reason: '前置：下一组是第 1 组');

    await tester.longPress(find.byKey(const Key('big-log-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-warmup')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    final SetRecord logged = h.controller.loggedSets.single;
    expect(logged.setType, SetType.warmup, reason: '必须是热身组');
    expect(h.controller.warmupSets, 1);

    // 关键：热身不能推进计划进度，否则做两组热身就把"共 3 组"顶掉了
    expect(h.controller.setNumber, 1, reason: '热身不计入计划进度，下一组仍是第 1 组');
    expect(h.controller.workout.totalSets, 0, reason: 'totalSets 只数正式组');

    // 埋点也要如实反映
    expect(h.setEvents.single['set_type'], 'warmup');

    await _teardown(tester, h);
  });

  testWidgets('热身状态是"粘住"的，且 S4 上有可见标记（否则用户会记错）',
      (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    expect(
      tester.widget<Text>(find.byKey(const Key('set-number'))).data,
      '第 1 组',
    );

    await tester.longPress(find.byKey(const Key('big-log-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-warmup')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-confirm')));
    await tester.pumpAndSettle();

    // 状态粘住 + 标题换掉：用户看得见才安全
    expect(h.controller.warmup, isTrue);
    expect(
      tester.widget<Text>(find.byKey(const Key('set-number'))).data,
      '热身组',
      reason: '标题必须换掉 —— 显示"第 1 组"却记成热身，用户完全不知道发生了什么',
    );

    // 记一组之后仍然粘住（连做两组热身时不该每次重新打开）
    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();
    expect(h.controller.warmup, isTrue, reason: '粘住，不自动弹回');

    // 手动关掉就回到正式组
    await tester.longPress(find.byKey(const Key('big-log-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-warmup')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-confirm')));
    await tester.pumpAndSettle();

    expect(h.controller.warmup, isFalse);
    expect(
      tester.widget<Text>(find.byKey(const Key('set-number'))).data,
      '第 1 组',
    );

    await _teardown(tester, h);
  });

  testWidgets('连续两组热身不会撞 id（setIndex 必须用全部组计数）',
      (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    h.controller.toggleWarmup();
    await tester.pump();
    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    final List<SetRecord> sets = h.controller.loggedSets;
    expect(sets.length, 2);
    expect(sets.every((SetRecord s) => s.setType == SetType.warmup), isTrue);
    // 两条热身如果都用 _normalSets 当序号，id 会一样 —— 后一条覆盖前一条，直接丢数据
    expect(sets[0].id, isNot(sets[1].id));
    expect(<int>[sets[0].setIndex, sets[1].setIndex], <int>[1, 2]);
    expect(h.controller.workout.totalSets, 0, reason: '两组热身都不算正式组');

    await _teardown(tester, h);
  });

  testWidgets('记一组震一下；撤销入口在屏幕上是看得见的（不是只写在代码里）',
      (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    expect(find.byKey(const Key('done-list-hint')), findsNothing,
        reason: '一组都没记时不该摆"长按可撤销"——那是废话');

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    expect(h.haptics.sets, 1, reason: '记上了就该震一下（健身房里不看屏幕也知道）');
    expect(find.byKey(const Key('done-list-hint')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('done-list-hint'))).data,
      contains('长按'),
      reason: '撤销入口要写在屏幕上——误触的人第一反应是"这下完了"',
    );

    await _teardown(tester, h);
  });

  testWidgets('**没记上的那一下不许震**（假装记上了比不震更糟）',
      (WidgetTester tester) async {
    // 距离动作还没设距离 → canLog=false → 那一下什么都不写
    final _Harness h = _Harness.distance();
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    expect(h.controller.loggedSets, isEmpty);
    expect(h.haptics.sets, 0, reason: '没写进库就不该震——用户会以为记上了');
    await _teardown(tester, h);
  });

  testWidgets('休息走到 0 震一下（那一下通常不看屏幕）', (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();
    h.advance(121 * 1000); // 休息 120 秒，推过去
    await tester.pump(const Duration(seconds: 1));

    expect(h.controller.restRunning, isFalse);
    expect(h.haptics.rests, 1);

    await _teardown(tester, h);
  });

  testWidgets('大按钮上方有「上次练了多少」那一行（站在器械前最想知道的数字）',
      (WidgetTester tester) async {
    final _Harness h = _Harness(
      lastSession: const LastSession(weightKg: 45, reps: <int>[10, 10, 10]),
    );
    await _pump(tester, h);

    expect(
      tester.widget<Text>(find.byKey(const Key('last-time'))).data,
      '上次 3 组 · 45 kg × 10 次',
      reason: '与建议页那条证据链是同一句话（同一份实现）',
    );
    await _teardown(tester, h);
  });

  testWidgets('没有历史时那一行**整个不出现**（不编一个"上次"出来）',
      (WidgetTester tester) async {
    final _Harness h = _Harness();
    await _pump(tester, h);

    expect(find.byKey(const Key('last-time')), findsNothing);
    await _teardown(tester, h);
  });

  testWidgets('★ 系统大字号 1.5× 也不溢出（训练屏是站着、出汗时看的那一屏）',
      (WidgetTester tester) async {
    // 常见安卓机的逻辑尺寸 411×914 + 1.5 倍字体
    tester.view.physicalSize = const Size(1233, 2742);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final _Harness h = _Harness(
      lastSession: const LastSession(weightKg: 45, reps: <int>[10, 10, 10]),
    );
    await _pump(tester, h);
    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pump();

    // 溢出会让测试直接失败；这里再钉住"该在的都在"
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('big-log-button')), findsOneWidget);
    expect(find.byKey(const Key('rest-bar')), findsOneWidget);
    expect(find.byKey(const Key('last-time')), findsOneWidget);

    await _teardown(tester, h);
  });
}
