/// 练了么 · 单位切换测试
///
/// 核心不变量：**存储、引擎、埋点始终是 kg**，单位只影响显示与输入。
/// 所以这里既验换算，也验"切到 lb 之后 kg 那一侧的数据一点没变"。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/data/db.dart' hide UserProfile;
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/data/body_metric_repository.dart';
import 'package:lianleme/features/body/body_metric_screen.dart';
import 'package:lianleme/features/profile/profile_screen.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/workout/workout_controller.dart';
import 'package:lianleme/analytics/analytics.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/sync_queue.dart';

void main() {
  group('换算', () {
    test('kg ↔ lb 往返不丢精度（一位小数内）', () {
      for (final double kg in <double>[0.5, 20, 60, 62.5, 100, 137.5]) {
        final double back = toStoredKg(toDisplayWeight(kg, WeightUnit.lb), WeightUnit.lb);
        expect(round1(back), closeTo(kg, 0.05), reason: '$kg kg 往返');
      }
    });

    test('kg 模式下换算是恒等的', () {
      expect(toDisplayWeight(62.5, WeightUnit.kg), 62.5);
      expect(toStoredKg(62.5, WeightUnit.kg), 62.5);
    });

    test('fromWire 只认 lb，其余都回落 kg（老数据 / 脏数据都安全）', () {
      expect(WeightUnit.fromWire('lb'), WeightUnit.lb);
      expect(WeightUnit.fromWire('kg'), WeightUnit.kg);
      expect(WeightUnit.fromWire(null), WeightUnit.kg);
      expect(WeightUnit.fromWire('KG'), WeightUnit.kg, reason: '大小写不敏感是刻意的吗？不，是安全兜底');
    });
  });

  group('格式化', () {
    test('重量：kg 与 lb 各自的样子', () {
      expect(formatWeight(60, WeightUnit.kg), '60 kg');
      expect(formatWeight(60, WeightUnit.lb), '132.3 lb',
          reason: '60 kg = 132.277 lb，一位小数');
      expect(formatWeight(62.5, WeightUnit.kg), '62.5 kg');
      expect(formatWeight(62.5, WeightUnit.lb), '137.8 lb');
    });

    test('null 与自重：不瞎编数字', () {
      expect(formatWeight(null, WeightUnit.kg), '—');
      expect(formatWeight(null, WeightUnit.lb), '—');
      expect(formatWeight(null, WeightUnit.lb, nullText: '自重'), '自重');
    });

    test('容量带千分位，且 zeroText 由调用方决定', () {
      expect(formatVolume(5400, WeightUnit.kg), '5,400 kg');
      expect(formatVolume(5400, WeightUnit.lb), '11,905 lb');
      expect(formatVolume(0, WeightUnit.kg), '—');
      expect(formatVolume(0, WeightUnit.kg, zeroText: '自重'), '自重');
    });

    test('trimNumber 去掉多余的 .0', () {
      expect(trimNumber(60), '60');
      expect(trimNumber(62.5), '62.5');
      expect(trimNumber(132.3), '132.3');
    });

    test('withThousands 处理五位数与负数', () {
      expect(withThousands(480), '480');
      expect(withThousands(1480), '1,480');
      expect(withThousands(11905), '11,905');
      expect(withThousands(-1480), '-1,480');
    });
  });

  group('训练控制器：大按钮上就是用户单位', () {
    WorkoutController controllerWith(WeightUnit unit) => WorkoutController(
          exercise: const ExerciseSpec(
            id: 'ex_bb_bench_press',
            name: '杠铃卧推',
            weightIncrement: 2.5,
            defaultWeightKg: 40,
            defaultRestSec: 120,
          ),
          plan: const PlanTarget(targetSets: 3, targetRepsLow: 8, targetRepsHigh: 10),
          analytics: RecordingAnalytics(),
          store: InMemoryLocalStore(),
          syncQueue: InMemorySyncQueue(),
          profile: UserProfile(unit: unit),
        );

    test('kg 用户看到 kg', () {
      expect(controllerWith(WeightUnit.kg).primaryButtonLabel, '40 kg × 8');
    });

    test('lb 用户看到 lb（值仍是同一个 40kg，只是换了个念法）', () {
      final WorkoutController c = controllerWith(WeightUnit.lb);
      expect(c.primaryButtonLabel, '88.2 lb × 8');
      // 底层量没变 —— 这正是"只改显示"的意思
      expect(c.weightKg, 40);
    });

    test('自重动作两种单位下都显示「自重」', () {
      final WorkoutController c = WorkoutController(
        exercise: const ExerciseSpec(id: 'pullup', weightIncrement: 0),
        plan: const PlanTarget(targetSets: 3, targetRepsLow: 8, targetRepsHigh: 10),
        analytics: RecordingAnalytics(),
        store: InMemoryLocalStore(),
        syncQueue: InMemorySyncQueue(),
        profile: const UserProfile(unit: WeightUnit.lb),
      );
      expect(c.primaryButtonLabel, '自重 × 8');
    });
  });

  group('设置持久化', () {
    late AppDatabase db;
    late ProfileRepository profile;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      profile = ProfileRepository(db);
    });

    tearDown(() => db.close());

    test('默认是 kg', () async {
      expect(await profile.unit(), WeightUnit.kg);
    });

    test('切到 lb 之后读回来还是 lb', () async {
      await profile.setUnit(WeightUnit.lb, nowMs: 1000);
      expect(await profile.unit(), WeightUnit.lb);
    });

    test('⚠️ 切单位不会把别的设置抹掉', () async {
      // 这条是照着 setProgressionMode 注释里记的那个坑写的：
      // 只写自己那一列、其余传默认值，会把用户别的设置悄悄改回去。
      await profile.setProgressionMode(ProgressionMode.off, nowMs: 1000);
      await profile.setAnalyticsEnabled(false, nowMs: 1000);

      await profile.setUnit(WeightUnit.lb, nowMs: 2000);

      expect(await profile.unit(), WeightUnit.lb);
      expect(await profile.progressionMode(), ProgressionMode.off,
          reason: '渐进建议开关被切单位带回去了');
      expect(await profile.analyticsEnabled(), isFalse,
          reason: '隐私开关被切单位带回去了');
    });

    test('反向也成立：切渐进建议不会把单位带回去', () async {
      await profile.setUnit(WeightUnit.lb, nowMs: 1000);
      await profile.setProgressionMode(ProgressionMode.off, nowMs: 2000);

      expect(await profile.unit(), WeightUnit.lb, reason: '单位被切开关带回去了');
    });
  });

  group('S10 的单位开关', () {
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

    testWidgets('点 lb → 落库 + 通知上层重建', (WidgetTester tester) async {
      WeightUnit? notified;

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ProfileScreen(
            store: store,
            repository: repo,
            profile: profile,
            unit: WeightUnit.kg,
            onUnitChanged: (WeightUnit u) => notified = u,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 2026-10-01 重排：单位收进「我 → 偏好设置」
      final Finder entry = find.byKey(const Key('open-preferences'));
      await tester.dragUntilVisible(entry, find.byType(ListView), const Offset(0, -220));
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.byKey(const Key('unit-lb')),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unit-lb')));
      await tester.pumpAndSettle();

      expect(await profile.unit(), WeightUnit.lb, reason: '必须落库');
      expect(notified, WeightUnit.lb, reason: '必须通知上层，否则别的 Tab 还按 kg 显示');
    });

    testWidgets('已经是 lb 时再点 lb 不会重复写库', (WidgetTester tester) async {
      int calls = 0;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ProfileScreen(
            store: store,
            repository: repo,
            profile: profile,
            unit: WeightUnit.lb,
            onUnitChanged: (WeightUnit _) => calls++,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final Finder entry = find.byKey(const Key('open-preferences'));
      await tester.dragUntilVisible(entry, find.byType(ListView), const Offset(0, -220));
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.byKey(const Key('unit-lb')),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unit-lb')));
      await tester.pumpAndSettle();

      expect(calls, 0, reason: '没变化就不该通知，也不该重建');
    });
  });

  group('体重单位：千克 / 斤', () {
    test('1 kg = 2 斤，换算是精确的（来回倒不掉精度）', () {
      expect(toDisplayBodyWeight(85.5, BodyWeightUnit.jin), 171);
      expect(bodyWeightToKg(171, BodyWeightUnit.jin), 85.5);
      expect(toDisplayBodyWeight(85.5, BodyWeightUnit.kg), 85.5);
      expect(bodyWeightToKg(85.5, BodyWeightUnit.kg), 85.5);
      // 半斤 = 0.25 kg，用说明"斤"的粒度是 0.5 斤而不是 1 斤
      expect(toDisplayBodyWeight(85.25, BodyWeightUnit.jin), 170.5);
      // 2026-10-01 补的磅：与训练重量共用同一个换算常数
      expect(round1(toDisplayBodyWeight(85.5, BodyWeightUnit.lb)),
          round1(85.5 * kLbPerKg));
      expect(round1(bodyWeightToKg(toDisplayBodyWeight(80, BodyWeightUnit.lb),
          BodyWeightUnit.lb)), 80);
    });

    test('念法：斤 不带多余小数，kg 保留一位', () {
      expect(formatBodyWeight(85.5, BodyWeightUnit.jin), '171 斤');
      expect(formatBodyWeight(85.5, BodyWeightUnit.kg), '85.5 kg');
      expect(formatBodyWeight(70.0, BodyWeightUnit.jin), '140 斤');
      expect(formatBodyWeight(70.0, BodyWeightUnit.kg), '70 kg');
      expect(formatBodyWeight(null, BodyWeightUnit.jin), '—');
    });

    test('wire 与 DB 默认值一致，未知值回落 kg', () {
      expect(BodyWeightUnit.jin.wire, 'jin');
      expect(BodyWeightUnit.lb.wire, 'lb');
      expect(BodyWeightUnit.fromWire('jin'), BodyWeightUnit.jin);
      expect(BodyWeightUnit.fromWire('lb'), BodyWeightUnit.lb,
          reason: '2026-10-01 起体重也有磅 —— 全局选了磅的人不该在身体页看到 kg');
      expect(BodyWeightUnit.fromWire(null), BodyWeightUnit.kg);
      expect(BodyWeightUnit.fromWire('stone'), BodyWeightUnit.kg,
          reason: '没见过的值回落 kg，不许猜');
    });

    test('念法照旧用各自的单位（格式化不联动）', () {
      expect(formatWeight(60, WeightUnit.lb), '132.3 lb');
      expect(formatBodyWeight(85.5, BodyWeightUnit.kg), '85.5 kg');
      expect(formatBodyWeight(85.5, BodyWeightUnit.lb), '188.5 lb');
    });

    test('体重单位**默认跟随训练单位**（2026-10-01 统一口径）', () async {
      final AppDatabase db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final ProfileRepository profile = ProfileRepository(db);

      // 什么都没选过：两个都是默认 kg → 换训练单位时体重跟着换
      await profile.setUnit(WeightUnit.lb, nowMs: 1000);
      expect(await profile.bodyWeightUnit(), BodyWeightUnit.lb,
          reason: '没单独选过就该跟随 —— 否则"全局选了磅、体重还是 kg"');

      // 用户单独选了「斤」：以后换训练单位不再动它
      await profile.setBodyWeightUnit(BodyWeightUnit.jin, nowMs: 2000);
      await profile.setUnit(WeightUnit.kg, nowMs: 3000);
      expect(await profile.bodyWeightUnit(), BodyWeightUnit.jin,
          reason: '单独选过的是用户的选择，不许被联动抹掉');
    });
  });

  group('两个单位互不抹掉：体重在身体数据页切，训练单位不受影响', () {
    testWidgets('在身体数据页切「斤」→ 落库，训练单位不动',
        (WidgetTester tester) async {
      final AppDatabase db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final ProfileRepository profile = ProfileRepository(db);
      await profile.setUnit(WeightUnit.lb); // 训练单位先设成磅
      // 这一页 v1.31.0 起先过敏感个人信息单独同意；这条测的是"两个单位互不抹掉"
      await profile.setBodyMetricConsent(nowMs: 1);

      await tester.pumpWidget(MaterialApp(
        home: BodyMetricScreen(
          repository: BodyMetricRepository(db),
          profile: profile,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('body-unit-jin')));
      await tester.pumpAndSettle();

      expect(await profile.bodyWeightUnit(), BodyWeightUnit.jin);
      expect(await profile.unit(), WeightUnit.lb,
          reason: '改体重单位不能把训练单位抹成默认值');
    });

    testWidgets('单独选过「斤」之后，改训练单位不会把它抹掉',
        (WidgetTester tester) async {
      final AppDatabase db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final ProfileRepository profile = ProfileRepository(db);
      await profile.setBodyWeightUnit(BodyWeightUnit.jin);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProfileScreen(
            store: DriftLocalStore(db),
            repository: ExerciseRepository(db),
            profile: profile,
            analytics: RecordingAnalytics(),
            unit: WeightUnit.kg,
            bodyUnit: BodyWeightUnit.jin,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 2026-10-01 重排：先进「偏好设置」，再滚到单位那一行
      final Finder entry = find.byKey(const Key('open-preferences'));
      await tester.dragUntilVisible(entry, find.byType(ListView), const Offset(0, -220));
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      final Finder lb = find.byKey(const Key('unit-lb'));
      await tester.dragUntilVisible(lb, find.byType(ListView), const Offset(0, -220));
      await tester.pumpAndSettle();
      await tester.tap(lb);
      await tester.pumpAndSettle();

      expect(await profile.unit(), WeightUnit.lb);
      expect(await profile.bodyWeightUnit(), BodyWeightUnit.jin,
          reason: '改训练单位不能把体重单位抹掉');
    });
  });
}
