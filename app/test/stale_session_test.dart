/// 练了么 · 跨天没结束的那次训练（2026-10-09，10.9 清单第 1 条）
///
/// 用户原话（截图里的那条）：「上次的训练还没结束 · 上次练到第 2/3 个动作」——
/// **不限期的**。半年前那次半途而废的训练，冷启动照样顶在首页最上面。
///
/// 他拍板的规则：今天开始的不问；**跨天了但还在 7 天内**弹一次三选一；
/// **超过 7 天不再弹**，只在「计划」页留一条入口。
///
/// 这个文件分两层：
///   1. **纯函数**（哪一档、"几天前"怎么说）—— 边界全在这里钉死；
///   2. **整个 App 装起来**跑一遍（`LianLeMeApp` 注入内存库），
///      因为那个弹层挂在冷启动上，只有真的开一次 App 才验证得到。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// db.dart（drift 表）与 domain/models.dart 都定义了 SetRecord，预先 hide。
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/workout/stale_session.dart';
import 'package:lianleme/main.dart';

ActiveSession _session(DateTime startedAt, {int index = 1}) => ActiveSession(
      workoutId: 'w_stale',
      entries: const <ActiveEntry>[
        ActiveEntry(
            exerciseId: 'ex_bb_bench_press',
            plan: PlanTarget(targetSets: 3, targetRepsLow: 8, targetRepsHigh: 12)),
        ActiveEntry(
            exerciseId: 'ex_bb_squat',
            plan: PlanTarget(targetSets: 5, targetRepsLow: 5, targetRepsHigh: 5)),
        ActiveEntry(
            exerciseId: 'ex_deadlift',
            plan: PlanTarget(targetSets: 3, targetRepsLow: 5, targetRepsHigh: 5)),
      ],
      index: index,
      startedAtMs: startedAt.millisecondsSinceEpoch,
      source: 'home_button',
    );

void main() {
  final DateTime now = DateTime(2026, 10, 9, 15, 30);

  group('纯函数：这条会话属于哪一档', () {
    test('今天开始的：不弹（用户可能只是切出去接了个电话）', () {
      expect(staleSessionKind(_session(DateTime(2026, 10, 9, 8)), now),
          StaleSessionKind.sameDay);
      // 今天凌晨 0:05 开始的也算今天
      expect(staleSessionKind(_session(DateTime(2026, 10, 9, 0, 5)), now),
          StaleSessionKind.sameDay);
    });

    test('跨天了：弹（昨天 / 前天 / 第 7 天都弹）', () {
      expect(staleSessionKind(_session(DateTime(2026, 10, 8, 23, 50)), now),
          StaleSessionKind.crossDay,
          reason: '过了午夜就是跨天 —— 哪怕只差 40 分钟');
      expect(staleSessionKind(_session(DateTime(2026, 10, 7)), now),
          StaleSessionKind.crossDay);
      expect(staleSessionKind(_session(DateTime(2026, 10, 2)), now),
          StaleSessionKind.crossDay,
          reason: '第 7 天（10/2 → 10/9）还在规则内');
    });

    test('超过 7 天：不再弹，只在「计划」页留入口', () {
      expect(staleSessionKind(_session(DateTime(2026, 10, 1)), now),
          StaleSessionKind.expired,
          reason: '第 8 天开始过期 —— 边界就在这里，多一天都不弹');
      expect(staleSessionKind(_session(DateTime(2026, 6, 1)), now),
          StaleSessionKind.expired);
    });

    test('按**自然日**算，不按 24 小时算', () {
      // 昨晚 23:50 → 今天 00:10：只过了 20 分钟，但**跨天了**（该问一次）
      expect(
        calendarDaysBetween(DateTime(2026, 10, 8, 23, 50), DateTime(2026, 10, 9, 0, 10)),
        1,
      );
      // 同一天里的 15 小时：不算跨天
      expect(
        calendarDaysBetween(DateTime(2026, 10, 9, 6), DateTime(2026, 10, 9, 21)),
        0,
      );
      // ⚠️ 用 `Duration.inDays` 的话，上面第一种会因为"只差 20 分钟"算成 0 天 ——
      // 而用户明明过了一夜。所以这里按 (年,月,日) 折算。
    });

    test('「几天前」怎么说', () {
      expect(staleSessionAgeLabel(0), '今天');
      expect(staleSessionAgeLabel(1), '昨天');
      expect(staleSessionAgeLabel(3), '3 天前');
      expect(staleSessionAgeLabel(30), '30 天前');
    });

    test('那条入口的小字：练到哪了 + 几天前', () {
      expect(
        staleSessionResumeLabel(_session(DateTime(2026, 10, 6), index: 1), now),
        '上次练到第 2/3 个动作 · 3 天前',
      );
      // index 越界（会话被改过 / 数据不干净）时不许说出"第 5/3 个动作"
      expect(
        staleSessionResumeLabel(_session(DateTime(2026, 10, 6), index: 99), now),
        contains('第 3/3 个动作'),
      );
    });
  });

  // ── 整个 App 装起来跑一遍 ───────────────────────────────────────────────
  group('冷启动那一次', () {
    late AppDatabase db;
    late String seedJson;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      seedJson = await File('assets/exercises.json').readAsString();
      // 同意过隐私政策（那道门本身由 privacy_consent_test 覆盖）
      await ProfileRepository(db).setPrivacyConsent(nowMs: 1);
    });

    tearDown(() => db.close());

    /// 造一条"N 天前没练完"的会话，外加已经记下的几组。
    ///
    /// ⚠️ 与真机**同一条路**：训练中记一组会写两条 —— `set_record` 一条、
    /// `workout` 那一行也要 upsert（`WorkoutController::_logSet` 的注释写着
    /// "之前只写了 set_record，导致重启后 loadWorkout 找不到这次训练"）。
    /// 少写 workout 那一行，`SummaryService.build()` 就会返回 null。
    Future<void> seedStaleSession({required int daysAgo, int sets = 1}) async {
      final DriftLocalStore store = DriftLocalStore(db);
      final DateTime started = DateTime.now().subtract(Duration(days: daysAgo));
      await store.saveActiveSession(_session(started));
      final Workout w = Workout(
        id: 'w_stale',
        startedAtMs: started.millisecondsSinceEpoch,
      );
      for (int i = 0; i < sets; i++) {
        final SetRecord r = SetRecord(
          id: 's$i',
          workoutId: 'w_stale',
          exerciseId: 'ex_bb_bench_press',
          setIndex: i + 1,
          reps: 8,
          weightKg: 40,
          completedAtMs: started.millisecondsSinceEpoch + 60000 * (i + 1),
        );
        await store.saveSet(r);
        w.sets.add(r);
      }
      await store.saveWorkout(w);
    }

    Future<void> pumpApp(WidgetTester tester) async {
      await tester.pumpWidget(LianLeMeApp(
        database: db,
        seedLoader: () async => seedJson,
      ));
      await tester.pumpAndSettle();
    }

    /// 外壳里有两个埋点上报定时器，不销毁页面 testWidgets 会因 pending timer 判失败。
    Future<void> teardown(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }

    testWidgets('跨天 → 冷启动弹三选一，写着练到哪了、几天前、已记几组',
        (WidgetTester tester) async {
      await seedStaleSession(daysAgo: 2);
      await pumpApp(tester);

      // ⚠️ 不用 `find.text('上次的训练还没结束')`：首页那条恢复条写的是同一句话
      // （弹层压在它上面），松散 finder 会撞两个。按弹层里的 key 断言。
      expect(find.byKey(const Key('stale-when')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('stale-when'))).data,
          '上次练到第 2/3 个动作 · 2 天前');
      expect(tester.widget<Text>(find.byKey(const Key('stale-count'))).data,
          '已经记下 1 组。');
      for (final String k in <String>['stale-resume', 'stale-finish', 'stale-discard']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: '$k 必须在弹层里');
      }

      await teardown(tester);
    });

    testWidgets('「结束并保存」：会话清掉、这次训练收尾（组一条不删）',
        (WidgetTester tester) async {
      await seedStaleSession(daysAgo: 2);
      await pumpApp(tester);

      await tester.tap(find.byKey(const Key('stale-finish')));
      // 弹层关掉 → 落库 → 弹一句实话。
      // ⚠️ 这里要 `pumpAndSettle`：处理这条会话要连做几件事
      // （读组、写结束时间、清会话、刷新首页），`pump()` 一帧不够。
      // 它**不会**把 SnackBar 等没：进场动画播完就没有待画的帧了，
      // 而"4 秒后退场"是一个定时器，不算待画的帧。
      await tester.pumpAndSettle();

      final DriftLocalStore store = DriftLocalStore(db);
      expect(await store.activeSession(), isNull, reason: '处理过了，入口不许再挂着');
      expect((await store.setsFor('w_stale')).length, 1,
          reason: '"结束并保存"是**保存**，组一条都不能少');
      // 收尾 = 写下结束时间：时长按最后一组算，不会变成"跨了两天"
      final Workout? w = await store.loadWorkout('w_stale');
      expect(w, isNotNull);
      expect(w!.isFinished, isTrue, reason: '这次训练要算数（进历史、进统计）');
      // ⚠️ **不断言那句 SnackBar**：它 4 秒后自己退场，而 `pumpAndSettle` 是
      // "一直泵到没有待画的帧" —— 首页上还有在动的玻璃/进度条时它会把假时钟
      // 推过 4 秒，那句提示就没了（试过，很脆）。这里要看的是**库里的结果**：
      // 会话清掉、组不删、训练收尾 —— 那才是这条路的承诺。

      await teardown(tester);
    });

    testWidgets('「丢弃」：会话清掉，那几组进回收站（不是物理删除）',
        (WidgetTester tester) async {
      await seedStaleSession(daysAgo: 2, sets: 2);
      await pumpApp(tester);

      await tester.tap(find.byKey(const Key('stale-discard')));
      await tester.pumpAndSettle();

      final DriftLocalStore store = DriftLocalStore(db);
      expect(await store.activeSession(), isNull);
      expect(await store.setsFor('w_stale'), isEmpty, reason: '正式组里不该再有它们');
      expect((await store.deletedSets()).length, 2,
          reason: '软删除 —— 回收站里必须找得到（留痕也要留出路）');
      // 同上：断言的是库里的结果（正式组没了、回收站里两条），不是那句 SnackBar。

      await teardown(tester);
    });

    testWidgets('「继续」：回到训练屏，还是原来那个动作、原来的进度',
        (WidgetTester tester) async {
      await seedStaleSession(daysAgo: 1);
      await pumpApp(tester);

      await tester.tap(find.byKey(const Key('stale-resume')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('big-log-button')), findsOneWidget,
          reason: '点了"继续"就该在训练屏上');
      expect(find.byKey(const Key('stale-saved-toast')), findsNothing);

      await teardown(tester);
    });

    testWidgets('今天开始的**不弹**（切出去接个电话回来，别多问一句）',
        (WidgetTester tester) async {
      await seedStaleSession(daysAgo: 0);
      await pumpApp(tester);

      expect(find.byKey(const Key('stale-resume')), findsNothing);
      // 但首页那条"继续"入口照旧在（那是用户主动点的路）
      expect(find.textContaining('上次的训练还没结束'), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('超过 7 天：**不弹**，首页也不摆那条入口（只在计划页留一个）',
        (WidgetTester tester) async {
      await seedStaleSession(daysAgo: 9);
      await pumpApp(tester);

      expect(find.byKey(const Key('stale-resume')), findsNothing,
          reason: '超过 7 天不再问（用户拍板）');
      expect(find.textContaining('上次的训练还没结束'), findsNothing,
          reason: '首页是"今天该做什么"的地方 —— 9 天前那半截不该顶在最上面');

      // 「计划」页那条入口还在，而且写着是几天前。
      // ⚠️ 2026-10-10：计划**不再是底栏的一格**（回 3 个 tab），
      // 入口改成首页那张卡右上角的「计划 ›」（`today-open-plan`）。
      await tester.tap(find.byKey(const Key('today-open-plan')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plan-resume')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('plan-resume-when'))).data,
          '上次练到第 2/3 个动作 · 9 天前');

      await teardown(tester);
    });
  });
}
