/// 练了么 · 首页那两个入口（S1）
///
/// 这一批改的是**开练路径**：首页大按钮从「今日页 → 建议卡 → 大按钮」的 3 跳
/// 压成 **1 跳直开练**。理由不是"少点一下更爽"，而是它是唯一客观指标
/// （端到端 `tap_count`）的直接改善，而 `PRODUCT.md` §1 的红线正是
/// "超过 3 次点击判负" —— 原来的路径刚好压线。
///
/// 建议卡**没有被砍掉**，只是不再挡在开练前面，所以这里两条路都要测。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

import 'package:lianleme/analytics/outbox.dart';
import 'package:lianleme/core/app_info.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/main.dart';

/// 从 outbox 里读事件（按入队顺序）。
///
/// 用 `takeBatch()` 而不是 `peekAll()`：outbox 没有"偷看"接口。
/// ⚠️ **`takeBatch()` 不是纯读**（2026-10-05 起）：它会先把**超过 30 天**的事件删掉
/// （D 方案，见 `docs/analytics.md` §10）。这里读的是刚记下的事件，所以不受影响；
/// 但如果哪天有人把这条断言改成"翻出很久以前的事件"，它会先被清掉 —— 那时该用 `peekAll()`。
Future<List<AnalyticsOutboxData>> _rows(AppDatabase db) async {
  await AnalyticsOutboxStore(db).takeBatch();
  final rows = await db.select(db.analyticsOutbox).get();
  rows.sort((AnalyticsOutboxData a, AnalyticsOutboxData b) =>
      a.createdAt.compareTo(b.createdAt));
  return rows;
}

Future<List<String>> _names(AppDatabase db) async =>
    (await _rows(db)).map((AnalyticsOutboxData r) => r.name).toList();

void main() {
  late AppDatabase db;
  late String seedJson;

  // 种子在 setUp 里读好：**setUp 不在 testWidgets 的 fake-async 区里**，
  // 真实文件 I/O 在那里能落地。
  //
  // 为什么不能直接在 testWidgets 里读：那个区里 `rootBundle` 要经平台通道、
  // 连 `File.readAsString` 的真实 I/O 也等不到回调 —— `await importSeed()`
  // 会永远挂住，而且 `Future.timeout` 也救不了（假时钟不推进，定时器根本不触发）。
  // 这正是这个仓库此前"没有任何测试驱动过完整开练流程"的原因。
  // 现在 loader 只负责把一个**已就绪**的字符串交回去（微任务即可完成），
  // 所以整条流程可以在 widget 测试里跑。
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    seedJson = await File('assets/exercises.json').readAsString();
  });

  tearDown(() => db.close());

  Future<void> pumpApp(WidgetTester tester, {bool analyticsOn = false}) async {
    // 先"同意过隐私政策"：首次启动多了一道同意门（法律要求，见
    // features/onboarding/privacy_consent_screen.dart）。这里测的是**主流程**，
    // 所以把库预置成"已经同意"的状态；那道门本身由 privacy_consent_test.dart 覆盖。
    await ProfileRepository(db).setPrivacyConsent(nowMs: 1);
    // 匿名统计**默认关**（2026-09-30，审计 A 的后半段）。要测"漏斗有没有真的发出去"，
    // 就得先像用户那样把它打开 —— 库里写 true，启动时会被同步进 analytics。
    // 默认不打开，是为了让别的测试也活在"新装用户"的真实状态里。
    if (analyticsOn) {
      await ProfileRepository(db).setAnalyticsEnabled(true, nowMs: 2);
    }
    await tester.pumpWidget(LianLeMeApp(
      database: db,
      seedLoader: () async => seedJson,
    ));
    await tester.pumpAndSettle();
  }

  /// 必须销毁页面：外壳里有两个埋点上报定时器（冷启动 5 秒 + 前台每 60 秒），
  /// 不销毁的话 testWidgets 会因 pending timer 直接判失败。
  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets('漏斗真的会发出四个环：app_open → workout_started → set_logged → workout_finished',
      (WidgetTester tester) async {
    // 这一条守的是 2026-09-29 查出来的窟窿：上报管线（outbox / 批量 / 退避 /
    // 训练期挂起 / 环回 HTTP 测试）全都写完了，但客户端**只发 6 个事件**，
    // 而 `docs/analytics.md` 定义了 31 个 —— 其中 `app_open` 与 `workout_finished`
    // 从来没发过，等于**北极星的分母和分子都是空的**。
    // 所以这条测试不看字段拼得对不对，只看"那条链路到底有没有走通"。
    // ⚠️ 前置条件：用户已经**主动打开**了「帮助改进产品」（默认是关的）。
    await pumpApp(tester, analyticsOn: true);

    // 环 1：冷启动
    expect(await _names(db), contains('app_open'));

    // 环 2：首页大按钮直开练
    await tester.tap(find.byKey(const Key('start-workout')));
    await tester.pumpAndSettle();
    expect(await _names(db), contains('workout_started'));

    // 环 3：点大按钮记一组
    await tester.tap(find.byKey(const Key('big-log-button')));
    await tester.pumpAndSettle();
    expect(await _names(db), contains('set_logged'));

    // 环 4：结束训练 —— 训练屏左上角那个 chevron（key: back-button）退出，
    // 主壳接着会推总结页，workout_finished 就是在那里发的
    await tester.tap(find.byKey(const Key('back-button')));
    await tester.pumpAndSettle();

    final List<AnalyticsOutboxData> rows = await _rows(db);
    final AnalyticsOutboxData finished =
        rows.lastWhere((AnalyticsOutboxData r) => r.name == 'workout_finished');
    final Map<String, Object?> props =
        (jsonDecode(finished.payload) as Map<String, dynamic>)
            .cast<String, Object?>();

    // docs/analytics-sdk.md §12 那条 sanity check：两边的组数必须对得上。
    // 对不上就说明有一条埋点漏了或者多算了，报表全跟着错。
    final int logged = rows.where((AnalyticsOutboxData r) => r.name == 'set_logged').length;
    expect(props['total_sets'], logged,
        reason: 'set_logged 条数与 workout_finished.total_sets 必须一致');
    expect(props['total_sets'], 1);
    expect(props['exercise_count'], 1);
    expect(props.containsKey('duration_sec'), isTrue);

    // 公共字段必须在（否则这些事件到了服务端认不出是同一台设备）
    expect(props['device_id'], hasLength(32));
    expect(props['session_id'], hasLength(32));
    expect(props['app_version'], kAppVersion);

    await teardown(tester);
  });

  testWidgets('冷启动就把动作库导进去了 —— 不需要先点「开始训练」',
      (WidgetTester tester) async {
    // 这一条守的是 2026-09-29 在真机上抓到的 bug：`importSeed` 原来只在
    // 「开始训练」与「看看今天练什么」两个按钮里调，冷启动不调 ——
    // 于是「计划 → 加动作 → 选择器」这条路永远看到升级前的**旧库**，
    // 新补的 186 个动作（热身/拉伸/有氧）在那些路径上根本不存在。
    // 真机那次：库里还是 165 条。
    //
    // 断言的是**库本身**，不是某个界面：这是内容层的不变量。
    await pumpApp(tester);

    final ExerciseRepository repo = ExerciseRepository(db);
    expect(await repo.builtinCount(), greaterThan(300),
        reason: '冷启动后库里应该是当前种子（351 条），而不是升级前那份 165 条');

    // 抽一个"升级才有"的类别：它在新库里，老库里没有
    final List<ExerciseData> cardio =
        await repo.search(category: 'cardio', limit: 50);
    expect(cardio, isNotEmpty, reason: '有氧这一类是 v1.4.0 才有的');
  });

  testWidgets('首页给两个入口：大按钮直开练 + 「今天的安排」卡（整块可点）',
      (WidgetTester tester) async {
    await pumpApp(tester);

    expect(find.byKey(const Key('start-workout')), findsOneWidget);
    // 2026-10-04：入口从"一行文字"换成"整张卡" —— 同一件事不留两个入口
    expect(find.byKey(const Key('open-plan')), findsOneWidget);
    expect(find.byKey(const Key('see-plan')), findsNothing);

    await teardown(tester);
  });

  testWidgets('大按钮一跳进训练屏 —— 建议卡不再挡在开练前面',
      (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('start-workout')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('big-log-button')), findsOneWidget,
        reason: '首页那一下应当直接落到训练屏');
    expect(find.byKey(const Key('today-title')), findsNothing,
        reason: '建议卡不该再挡在开练前面（它挪到「今天的安排」卡后面了）');

    await teardown(tester);
  });

  testWidgets('「今天的安排」卡仍然进建议卡（换一批 / 我自己选还在那儿）',
      (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('open-plan')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('today-title')), findsOneWidget);
    expect(find.byKey(const Key('reroll')), findsOneWidget);
    expect(find.byKey(const Key('pick-myself')), findsOneWidget);
    expect(find.byKey(const Key('big-log-button')), findsNothing,
        reason: '这一条路上还没进训练屏');

    await teardown(tester);
  });
}
