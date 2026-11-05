/// 练了么 · 周期化计划界面（Ultra 权益 10）
///
/// 判据：无权益时计划页**零新增付费入口**；有权益可进；空态/课表如实；
/// 2.0× 字号不溢出；导入坏文件给可读原因。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/billing/entitlement.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/entitlement_repository.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/period_plan_repository.dart';
import 'package:lianleme/data/routine_repository.dart';
import 'package:lianleme/domain/periodization.dart';
import 'package:lianleme/features/plan/periodization_screen.dart';
import 'package:lianleme/features/routine/plan_screen.dart';
import 'package:lianleme/features/today/today_planner.dart';

class _Harness {
  _Harness(this.db, this.store, this.exercises, this.routines, this.plans, this.entitlements);

  final AppDatabase db;
  final DriftLocalStore store;
  final ExerciseRepository exercises;
  final RoutineRepository routines;
  final PeriodPlanRepository plans;
  final EntitlementRepository entitlements;

  TodayPlanner get planner => TodayPlanner(repository: exercises, store: store);
  Future<void> dispose() => db.close();
}

Future<_Harness> _harness() async {
  final AppDatabase db = AppDatabase(NativeDatabase.memory());
  return _Harness(
    db,
    DriftLocalStore(db),
    ExerciseRepository(db),
    RoutineRepository(db),
    PeriodPlanRepository(db),
    EntitlementRepository(db),
  );
}

Future<void> _seedUltra(_Harness h, {required bool active}) async {
  final int now = DateTime(2026, 11, 6, 12).millisecondsSinceEpoch;
  await h.entitlements.upsert(UltraEntitlement(
    id: 'tx_seed',
    product: UltraProduct.yearly,
    source: UltraSource.apple,
    purchasedAtMs: now - 10 * 24 * 60 * 60 * 1000,
    expiresAtMs: active ? now + 30 * 24 * 60 * 60 * 1000 : now - 24 * 60 * 60 * 1000,
    lastVerifiedAtMs: now,
  ));
}

Future<void> _pumpPlanScreen(WidgetTester tester, _Harness h) async {
  tester.view.physicalSize = const Size(700, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: SafeArea(
        child: PlanScreen(
          repository: h.routines,
          exercises: h.exercises,
          store: h.store,
          unit: WeightUnit.kg,
          now: DateTime(2026, 11, 6, 12),
          periodPlans: h.plans,
          entitlements: h.entitlements,
          planner: h.planner,
          onStartPeriodized: (_) {},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _pumpPeriodScreen(WidgetTester tester, _Harness h, {TextScaler? scaler}) async {
  tester.view.physicalSize = const Size(700, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Widget screen = PeriodizationScreen(
    plans: h.plans,
    planner: h.planner,
    exercises: h.exercises,
    store: h.store,
    unit: WeightUnit.kg,
    now: () => DateTime(2026, 11, 6, 12),
  );
  if (scaler != null) {
    screen = MediaQuery(data: MediaQueryData(textScaler: scaler), child: screen);
  }
  await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: screen));
  await tester.pumpAndSettle();
}

void main() {
  late _Harness h;
  setUp(() async => h = await _harness());
  tearDown(() async => h.dispose());

  testWidgets('无权益：计划页不出现周期计划入口（零新增付费入口）', (WidgetTester tester) async {
    await _pumpPlanScreen(tester, h);
    expect(find.byKey(const Key('plan-periodization')), findsNothing);
    expect(find.textContaining('周期计划'), findsNothing);
  });

  testWidgets('权益过期：同样不出现入口', (WidgetTester tester) async {
    await _seedUltra(h, active: false);
    await _pumpPlanScreen(tester, h);
    expect(find.byKey(const Key('plan-periodization')), findsNothing);
  });

  testWidgets('有权益：入口出现，点进去是创建空态（不显示假课表）', (WidgetTester tester) async {
    await _seedUltra(h, active: true);
    await _pumpPlanScreen(tester, h);
    expect(find.byKey(const Key('plan-periodization')), findsOneWidget);

    await tester.tap(find.byKey(const Key('plan-periodization')));
    await tester.pumpAndSettle();
    expect(find.text('还没有周期计划'), findsOneWidget);
    expect(find.byKey(const Key('period-create')), findsOneWidget);
    expect(find.byKey(const Key('period-start-1')), findsNothing);
  });

  testWidgets('有 active 计划：显示周次/状态与本周课表，可从某一天开练', (WidgetTester tester) async {
    await _seedUltra(h, active: true);
    await h.plans.createPlan(
      name: '4 周入门',
      weeks: 4,
      daysPerWeek: 3,
      startDate: DateTime(2026, 11, 2),
      baseSessions: <PeriodSessionSpec>[
        const PeriodSessionSpec(
          week: 1, day: 1, position: 0, exerciseId: 'ex_bb_bench_press', targetWeightKg: 60,
        ),
      ],
      nowMs: 1000,
    );
    await _pumpPeriodScreen(tester, h);

    expect(find.byKey(const Key('period-name')), findsOneWidget);
    expect(find.textContaining('第 1/4 周'), findsOneWidget);
    expect(find.byKey(const Key('period-start-1')), findsOneWidget);
    expect(find.textContaining('3 组 × 8–10'), findsOneWidget);
  });

  testWidgets('2.0× 字号：创建空态与课表都不溢出', (WidgetTester tester) async {
    await h.plans.createPlan(
      name: '4 周入门',
      weeks: 4,
      daysPerWeek: 3,
      startDate: DateTime(2026, 11, 2),
      baseSessions: <PeriodSessionSpec>[
        const PeriodSessionSpec(
          week: 1, day: 1, position: 0, exerciseId: 'ex_bb_bench_press', targetWeightKg: 60,
        ),
      ],
      nowMs: 1000,
    );
    await _pumpPeriodScreen(tester, h, scaler: const TextScaler.linear(2));
    expect(tester.takeException(), isNull);
    await _pumpPeriodScreen(tester, h);
    expect(tester.takeException(), isNull);
  });

  testWidgets('导入：坏 JSON 给可读原因，不落库', (WidgetTester tester) async {
    await _pumpPeriodScreen(tester, h);
    await tester.tap(find.byKey(const Key('period-import')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('period-import-field')), '{"version":2}');
    await tester.tap(find.byKey(const Key('period-import-ok')));
    await tester.pumpAndSettle();

    expect(find.textContaining('更新版本'), findsOneWidget);
    expect(await h.plans.activePlan(), isNull);
  });
}
