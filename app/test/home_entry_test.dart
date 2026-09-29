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
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/main.dart';

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

  Future<void> pumpApp(WidgetTester tester) async {
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

  testWidgets('首页给两个入口：大按钮直开练 + 「看看今天练什么」', (WidgetTester tester) async {
    await pumpApp(tester);

    expect(find.byKey(const Key('start-workout')), findsOneWidget);
    expect(find.byKey(const Key('see-plan')), findsOneWidget);

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
        reason: '建议卡不该再挡在开练前面（它挪到「看看今天练什么」后面了）');

    await teardown(tester);
  });

  testWidgets('「看看今天练什么」仍然进建议卡（换一批 / 我自己选还在那儿）',
      (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('see-plan')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('today-title')), findsOneWidget);
    expect(find.byKey(const Key('reroll')), findsOneWidget);
    expect(find.byKey(const Key('pick-myself')), findsOneWidget);
    expect(find.byKey(const Key('big-log-button')), findsNothing,
        reason: '这一条路上还没进训练屏');

    await teardown(tester);
  });
}
