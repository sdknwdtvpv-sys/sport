/// 练了么 · 「我」页的**结构**（2026-10-01 重排）
///
/// 用户原话：「我」里面现在有些复杂能否有些收纳进次级页面？
/// 真机走查证实了这条 —— 原先 7 个区块、8 个选项胶囊、要滚三屏，
/// 导出 / 导入 / 删除全被埋在第一屏之后。重排之后这一页只留：
/// 训练统计 + 三个入口（偏好设置 / 数据与备份 / 隐私与关于）+ 底部版本行。
///
/// 这个文件钉两件事：
///   1. **三个入口都在、都进得去**（点进去落到正确的二级页，且看到标志性内容）；
///   2. **第一屏不许再长回去** —— 被收走的那些 key（开关 / 导出 / 删除 / 政策…）
///      一旦重新出现在「我」页上就判红。没有这一条，下一次"顺手加一行"又会把它撑回三屏，
///      而那时没人会记得今天为什么收。
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
// db.dart（drift 表）与 models.dart（领域模型）都定义了 SetRecord，预先 hide。
import 'package:lianleme/data/db.dart' hide SetRecord, Workout, Exercise, WorkoutItem;
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/features/profile/data_tools_screen.dart';
import 'package:lianleme/features/profile/settings_screen.dart';
import 'package:lianleme/features/profile/privacy_about_screen.dart';
import 'package:lianleme/features/profile/profile_screen.dart';

/// 三个入口
const List<String> kEntries = <String>[
  'open-preferences',
  'open-data-tools',
  'open-privacy-about',
];

/// **被收走的**那些 key：它们属于二级页，绝不许再出现在「我」页上。
const List<String> kMovedAway = <String>[
  'progression-switch',
  'analytics-switch',
  'export-csv',
  'export-backup',
  'import-backup',
  'delete-all',
  'open-body-metric',
  'cloud-backup',
  'privacy-policy',
  'collection-list',
  'open-source-licenses',
  'rest-follow',
  'rest-90',
  'unit-lb',
];

void main() {
  // 与其它 drift 测试同一条：不要在测试里跑后台 isolate
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late AppDatabase db;
  late DriftLocalStore store;
  late ExerciseRepository repo;
  late ProfileRepository profile;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLocalStore(db);
    repo = ExerciseRepository(db);
    profile = ProfileRepository(db);
    await repo.importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
  });

  tearDown(() => db.close());

  Future<void> pumpProfile(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: ProfileScreen(store: store, repository: repo, profile: profile),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// 从头滚到底，每一步都检查一遍"这些 key 不许出现"。
  ///
  /// 为什么不只看首屏：ListView 是懒构建的，**没滚到 = 不存在** ——
  /// 只查首屏的话，把某一行塞到页面底部同样能骗过测试。
  Future<void> scrollThroughAndCheck(WidgetTester tester) async {
    for (int i = 0; i < 8; i++) {
      for (final String key in kMovedAway) {
        expect(find.byKey(Key(key)), findsNothing,
            reason: '$key 属于二级页，不许再出现在「我」页上（第 $i 屏）');
      }
      if (i == 7) break;
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('「我」页只有三个入口 + 统计 + 版本行（收走的那些不许回来）',
      (WidgetTester tester) async {
    await store.saveSet(SetRecord(
      id: 's1',
      workoutId: 'w1',
      exerciseId: 'ex_bb_bench_press',
      setIndex: 1,
      reps: 8,
      weightKg: 60,
      setType: SetType.normal,
      completedAtMs: 1000,
    ));
    await pumpProfile(tester);

    // 三个入口都在，但**可能不在首屏**（2026-10-06 加了段位卡之后，
    // `open-preferences` 被顶到测试视口之外）—— ListView 懒构建，不滚过去
    // `find` 就是空的。老规矩：先 dragUntilVisible，再断言。
    for (final String key in kEntries) {
      await tester.dragUntilVisible(
          find.byKey(Key(key)), find.byType(ListView), const Offset(0, -220));
      await tester.pumpAndSettle();
      expect(find.byKey(Key(key)), findsOneWidget, reason: '$key 必须在「我」页上');
    }

    // 统计还在这一页（它是"每天看"的那一类）。**先滚回去再断言**：
    // 上面为了找那三个入口已经滚到页面下部，统计卡此时已经被 ListView 回收掉了。
    await tester.dragUntilVisible(find.byKey(const Key('profile-stat-workouts')),
        find.byType(ListView), const Offset(0, 220));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-stat-workouts')), findsOneWidget);

    await scrollThroughAndCheck(tester);

    // 版本行也留着：它是"这一页是什么版本"的唯一出口
    expect(find.textContaining('版本 '), findsOneWidget);
  });

  /// 点开一个入口，断言落到哪一屏、且有页内返回箭头。
  Future<void> openEntry(WidgetTester tester, String key, Type page) async {
    await pumpProfile(tester);
    final Finder row = find.byKey(Key(key));
    await tester.dragUntilVisible(row, find.byType(ListView), const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(page), findsOneWidget, reason: '$key 应该落到 $page');
    // 二级页有统一的返回箭头（页内返回，不是系统返回键）
    expect(find.byKey(const Key('subpage-back')), findsOneWidget);
  }

  // ⚠️ 三个入口**分成三个测试**，不要写成循环里连着 pumpProfile：
  // `MaterialApp` 的路由栈会被复用，第二轮的「我」页其实还压在第一轮推上去的
  // 二级页下面 —— 于是"再滚到入口"直接找不到（2026-10-01 踩过）。

  testWidgets('入口一：偏好设置', (WidgetTester tester) async {
    await openEntry(tester, 'open-preferences', PreferencesScreen);
  });

  testWidgets('入口二：数据与备份', (WidgetTester tester) async {
    await openEntry(tester, 'open-data-tools', DataToolsScreen);
  });

  testWidgets('入口三：隐私与关于', (WidgetTester tester) async {
    await openEntry(tester, 'open-privacy-about', PrivacyAboutScreen);
  });

  testWidgets('偏好设置里能看到休息时长与单位', (WidgetTester tester) async {
    await pumpProfile(tester);
    // 老规矩：入口可能不在首屏（2026-10-06 段位卡把它往下推了一格）
    await tester.dragUntilVisible(
        find.byKey(const Key('open-preferences')),
        find.byType(ListView),
        const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-preferences')));
    await tester.pumpAndSettle();

    expect(find.text('休息时长'), findsOneWidget);
    // 2026-10-04 起：休息时长在页面上只占一行（当前值），选项收进底部弹层
    expect(find.byKey(const Key('rest-row')), findsOneWidget);
    expect(find.byKey(const Key('unit-kg')), findsOneWidget);
  });

  testWidgets('数据与备份里能看到导出与删除（危险动作单独一区）',
      (WidgetTester tester) async {
    await pumpProfile(tester);
    // 同上：先滚到入口再点（不滚就是"点了个寂寞"，警告里已经写着）
    await tester.dragUntilVisible(
        find.byKey(const Key('open-data-tools')),
        find.byType(ListView),
        const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-data-tools')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('export-csv')), findsOneWidget);
    await tester.dragUntilVisible(find.byKey(const Key('delete-all')),
        find.byType(ListView), const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(find.text('危险动作'), findsOneWidget);
  });

  testWidgets('隐私与关于里有政策、清单与许可三个入口', (WidgetTester tester) async {
    await pumpProfile(tester);
    // 2026-10-05：这一屏顶部多了等级卡，`open-privacy-about` 被推出测试视口 ——
    // 不先滚到它就点了个寂寞（同一屏的 `openEntry` 一直是这么做的，这里漏了）。
    await tester.dragUntilVisible(
      find.byKey(const Key('open-privacy-about')),
      find.byType(ListView),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-privacy-about')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('privacy-policy')), findsOneWidget);
    expect(find.byKey(const Key('collection-list')), findsOneWidget);
    expect(find.byKey(const Key('open-source-licenses')), findsOneWidget);
  });
}
