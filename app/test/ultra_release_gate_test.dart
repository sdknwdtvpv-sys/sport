/// 练了么 · **首版不上会员**这条闸门的判据（2026-10-11）
///
/// 背景：用户拍板"**免费版先上**"（`app/lib/billing/ultra_visibility.dart` 里有完整理由）。
/// 于是 release 里 Ultra 的三个入口全部关闭，但代码留着（M2 真内购落地时打开）。
///
/// 这一份守**两头**，缺一条这条闸门就不可信：
///   ① **默认（= 发版）状态下，三个入口一个都不许渲染** —— 半成品入口是 Apple 2.1 / 3.1.1 的拒审面；
///   ② **`showUltra: true` 时它们必须真的回来** —— 否则开关打开那天会发现那几屏早就画不出来了
///      （"有开关但功能已烂"比"没开关"更坏）。
///
/// ⚠️ 所以：**把 `kUltraReleased` 改成 true 时，下面那几条"不渲染"的断言会红** ——
/// 那是**故意的**：它逼你回来确认"这一版真的要卖了"，并顺手把文档与商店表单一起改
/// （清单写在 `ultra_visibility.dart` 的文件头）。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/billing/ultra_visibility.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart' hide SetRecord, Workout, Exercise, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/entitlement_repository.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/progress/all_data_screen.dart';
import 'package:lianleme/features/progress/progress_screen.dart';
import 'package:lianleme/features/profile/settings_home_screen.dart';

late AppDatabase db;
late DriftLocalStore store;
late ExerciseRepository repo;

void main() {
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLocalStore(db);
    repo = ExerciseRepository(db);
    // ⚠️ 进步页的卡片（含「进阶分析」）只在**有训练记录**那一条分支里 ——
    // 不种一条，那一屏给的是空态，卡片自然找不到（第一版就是这么红的）。
    await store.saveSet(SetRecord(
      id: 's1',
      workoutId: 'w1',
      exerciseId: 'ex_bb_bench_press',
      setIndex: 1,
      reps: 10,
      weightKg: 60,
      completedAtMs: DateTime(2026, 10, 6, 19).millisecondsSinceEpoch,
    ));
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, Widget child) async {
    // 这一屏有懒构建的 ListView → 给够高度，别让 key 因为"没建出来"而不见
    tester.view.physicalSize = const Size(500, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: child));
    for (int i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  test('常量本身：首版是关的（改成 true 时要连带改这一份与商店表单）', () {
    expect(kUltraReleased, isFalse,
        reason: '首版免费上架 —— 要翻成 true 之前先读 ultra_visibility.dart 文件头的三步');
  });

  group('① 默认（发版）状态：三个入口都不渲染', () {
    testWidgets('设置页：没有「练了么 Ultra」那一行', (WidgetTester tester) async {
      await pump(
        tester,
        SettingsHomeScreen(
          store: store,
          repository: repo,
          profile: ProfileRepository(db),
          sets: const <SetRecord>[],
        ),
      );
      expect(find.byKey(const Key('open-ultra')), findsNothing);
      // 但设置页本身照常能用（不是把整页弄坏了）
      expect(find.byKey(const Key('open-preferences')), findsOneWidget);
    });

    testWidgets('进步页：没有「进阶分析」那张卡（连预览态都没有）', (WidgetTester tester) async {
      await pump(
        tester,
        ProgressScreen(
          store: store,
          repository: repo,
          now: DateTime(2026, 10, 11),
          onOpenToday: () {},
        ),
      );
      expect(find.text('进阶分析'), findsNothing);
      expect(find.byKey(const Key('advanced-locked-note')), findsNothing);
      expect(find.byKey(const Key('advanced-try-ultra')), findsNothing);
    });

    testWidgets('全部数据页：没有「整理（Ultra）」那一栏', (WidgetTester tester) async {
      await pump(
        tester,
        AllDataScreen(
          store: store,
          repository: repo,
          now: DateTime(2026, 10, 11),
        ),
      );
      expect(find.byKey(const Key('all-data-organize')), findsNothing);
      expect(find.textContaining('整理'), findsNothing);
    });
  });

  group('② showUltra: true（= M2 那一版）时它们会回来', () {
    testWidgets('设置页：那一行回来了', (WidgetTester tester) async {
      await pump(
        tester,
        SettingsHomeScreen(
          store: store,
          repository: repo,
          profile: ProfileRepository(db),
          showUltra: true,
          entitlements: EntitlementRepository(db),
          sets: const <SetRecord>[],
        ),
      );
      expect(find.byKey(const Key('open-ultra')), findsOneWidget);
    });

    testWidgets('进步页：卡回来了（免费用户看到的是预览态）', (WidgetTester tester) async {
      await pump(
        tester,
        ProgressScreen(
          store: store,
          repository: repo,
          showUltra: true,
          entitlements: EntitlementRepository(db),
          now: DateTime(2026, 10, 11),
          onOpenToday: () {},
        ),
      );
      expect(find.text('进阶分析'), findsOneWidget);
      expect(find.byKey(const Key('advanced-locked-note')), findsOneWidget);
    });

    testWidgets('全部数据页：「整理（Ultra）」回来了', (WidgetTester tester) async {
      await pump(
        tester,
        AllDataScreen(
          store: store,
          repository: repo,
          showUltra: true,
          entitlements: EntitlementRepository(db),
          onOpenUltra: () {},
          now: DateTime(2026, 10, 11),
        ),
      );
      expect(find.byKey(const Key('all-data-organize')), findsOneWidget);
    });
  });
}
