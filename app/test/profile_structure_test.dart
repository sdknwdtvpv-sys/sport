/// 练了么 · 「我」页 + 「设置」页的**结构**（2026-10-01 重排 / 2026-10-07 再收一次）
///
/// 两次重排的原话：
///   * 2026-10-01：「我」里面现在有些复杂能否有些收纳进次级页面？ —— 于是这一页只留
///     统计 + 三个入口（偏好设置 / 数据与备份 / 隐私与关于）+ 底部版本行；
///   * **2026-10-07（v1.60.0）**：「**所有的设置相关的能不能集成到右上角，一个小齿轮图标**」
///     —— 三个入口**连"我"页都不待了**，搬进独立的设置页（`SettingsHomeScreen`），
///     入口是外壳顶栏右上角那枚齿轮（与你在哪一屏无关）。
///
/// 这个文件钉三件事：
///   1. **三个入口都在、都进得去**（点进去落到正确的二级页，且看到标志性内容）；
///   2. **「我」页上不许再出现设置类入口** —— 它们搬家了，回来一个就是 IA 走回头路；
///   3. **「我」页自己不许再长回去** —— 被收走的那些 key（开关 / 导出 / 删除 / 政策…）
///      一旦重新出现在「我」页上就判红。没有这一条，下一次"顺手加一行"又会把它撑回三屏。
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/core/units.dart';
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
import 'package:lianleme/features/profile/settings_home_screen.dart';

/// 三个入口（都在**设置页**上）
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
  // ⚠️ 2026-10-07 新增：三个设置入口本身也不许回到「我」页上
  ...kEntries,
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

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SettingsHomeScreen(
          store: store,
          repository: repo,
          profile: profile,
        ),
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
            reason: '$key 属于二级页/设置页，不许再出现在「我」页上（第 $i 屏）');
      }
      if (i == 7) break;
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('「我」页 = 身份 + 我的进度 + 统计 + 成就 + 版本行（设置入口不许回来）',
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

    // 身份块在**首屏第一个**（10.7 清单第 7 条：昵称 + 账号 ID）
    expect(find.byKey(const Key('profile-identity')), findsOneWidget);
    expect(find.byKey(const Key('profile-nickname')), findsOneWidget);
    expect(find.byKey(const Key('profile-id-line')), findsOneWidget);
    expect(find.text('还没设昵称'), findsOneWidget, reason: '没设过就如实写，不编默认名');

    // 统计还在这一页（它是"每天看"的那一类）
    await tester.dragUntilVisible(find.byKey(const Key('profile-stat-volume')),
        find.byType(ListView), const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-stat-volume')), findsOneWidget);

    // 成就入口也还在（它读的就是这一页刚算出来的数）
    await tester.dragUntilVisible(find.byKey(const Key('open-achievements')),
        find.byType(ListView), const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-achievements')), findsOneWidget);

    await scrollThroughAndCheck(tester);

    // 版本行也留着：它是"这一页是什么版本"的唯一出口
    expect(find.textContaining('版本 '), findsOneWidget);
  });

  testWidgets('「设置」页 = 三个入口 + 一行实话（原来的「我」页入口搬到这里）',
      (WidgetTester tester) async {
    await pumpSettings(tester);

    for (final String key in kEntries) {
      await tester.dragUntilVisible(
          find.byKey(Key(key)), find.byType(ListView), const Offset(0, -220));
      await tester.pumpAndSettle();
      expect(find.byKey(Key(key)), findsOneWidget, reason: '$key 必须在设置页上');
    }
    // 一行实话：这些设置都在本机
    await tester.dragUntilVisible(find.textContaining('设置都存在这台手机上'),
        find.byType(ListView), const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(find.textContaining('设置都存在这台手机上'), findsOneWidget);
  });

  /// 点开一个入口，断言落到哪一屏、且有页内返回箭头。
  Future<void> openEntry(WidgetTester tester, String key, Type page) async {
    await pumpSettings(tester);
    final Finder row = find.byKey(Key(key));
    await tester.dragUntilVisible(row, find.byType(ListView), const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(page), findsOneWidget, reason: '$key 应该落到 $page');
    // 二级页有统一的返回箭头（页内返回，不是系统返回键）
    expect(find.byKey(const Key('subpage-back')), findsOneWidget);
  }

  // ⚠️ 三个入口**分成三个测试**，不要写成循环里连着 pumpSettings：
  // `MaterialApp` 的路由栈会被复用，第二轮其实还压在第一轮推上去的
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
    await pumpSettings(tester);
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
    await pumpSettings(tester);
    await tester.tap(find.byKey(const Key('open-data-tools')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('export-csv')), findsOneWidget);
    await tester.dragUntilVisible(find.byKey(const Key('delete-all')),
        find.byType(ListView), const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(find.text('危险动作'), findsOneWidget);
  });

  testWidgets('隐私与关于里有政策、清单与许可三个入口', (WidgetTester tester) async {
    await pumpSettings(tester);
    await tester.tap(find.byKey(const Key('open-privacy-about')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('privacy-policy')), findsOneWidget);
    expect(find.byKey(const Key('collection-list')), findsOneWidget);
    expect(find.byKey(const Key('open-source-licenses')), findsOneWidget);
  });

  // ── 偏好设置里的「加重量」（2026-10-09，10.9 清单第 8a 条）──────────────────
  //
  // 训练屏上那一处改的是"手上这个动作"，而有些健身房的片子**只有 5 kg 一档** ——
  // 那种地方要的是"我这儿的档就是这个"，那是设置的话题，不是训练中的话题。
  group('偏好设置 · 加重步进', () {
    Future<void> pumpPrefs(WidgetTester tester,
        {required List<double> written,
        WeightUnit unit = WeightUnit.kg,
        double? current}) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: PreferencesScreen(
            profile: profile,
            unit: unit,
            defaultStepKg: current,
            onStepAllChanged: (double kg) async => written.add(kg),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('没设过时写「跟随动作」，改一次就是"铺到所有动作"',
        (WidgetTester tester) async {
      final List<double> written = <double>[];
      await pumpPrefs(tester, written: written);

      // 没设过 = 跟随动作（副标题解释这是什么）
      expect(find.byKey(const Key('step-row')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('step-current'))).data, '跟随动作');

      await tester.tap(find.byKey(const Key('step-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('step-preset-5')));
      await tester.pumpAndSettle();
      // ⚠️ 设置页里**没有**「只改这个动作」：那件事只影响以后新建的动作，
      // 摆在设置里就是让人猜（训练屏那一处才有）
      expect(find.byKey(const Key('step-apply-one')), findsNothing,
          reason: '设置页只有"所有动作都改"这一种范围');
      await tester.tap(find.byKey(const Key('step-apply-all')));
      await tester.pumpAndSettle();

      expect(written, <double>[5.0]);
      expect(tester.widget<Text>(find.byKey(const Key('step-current'))).data, '5 kg',
          reason: '选完这一行要立刻显示新值');
    });

    testWidgets('lb 单位下档位念的是磅，落库折回 kg（不许把 1 lb 存成 1 kg）',
        (WidgetTester tester) async {
      final List<double> written = <double>[];
      await pumpPrefs(tester,
          written: written, unit: WeightUnit.lb, current: 5 * 0.45359237);

      // 存的是 kg（2.27），念出来还是 5 lb（不是 2.3 这种换算尾巴）
      expect(tester.widget<Text>(find.byKey(const Key('step-current'))).data, '5 lb');

      await tester.tap(find.byKey(const Key('step-row')));
      await tester.pumpAndSettle();
      // lb 下的档位是 1/2.5/5/10（kg 下才是 0.5/1/2/2.5/5）
      expect(find.byKey(const Key('step-preset-0.5')), findsNothing);
      await tester.tap(find.byKey(const Key('step-preset-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('step-apply-all')));
      await tester.pumpAndSettle();

      expect(written.single, closeTo(0.45359237, 1e-9),
          reason: '1 lb 要折成 0.4536 kg —— 直接存 1 的话 lb 用户点"1"会得到 2.2 lb 的一步');
      expect(tester.widget<Text>(find.byKey(const Key('step-current'))).data, '1 lb');
    });
  });
}
