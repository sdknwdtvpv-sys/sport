/// 练了么 · 「导出进阶（Ultra）」入口的权益门（Ultra 权益 9）
///
/// 判据：**没有权益就整组不渲染**（连说明都没有）；有权益才出现；
/// `kUltraReleased=false` 期间不因此多出任何付费入口。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/billing/entitlement.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/entitlement_repository.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/features/profile/data_tools_screen.dart';

class _Harness {
  _Harness(this.db, this.store, this.repository, this.profile, this.entitlements);

  final AppDatabase db;
  final DriftLocalStore store;
  final ExerciseRepository repository;
  final ProfileRepository profile;
  final EntitlementRepository entitlements;

  Future<void> dispose() => db.close();
}

Future<_Harness> _harness() async {
  final AppDatabase db = AppDatabase(NativeDatabase.memory());
  return _Harness(
    db,
    DriftLocalStore(db),
    ExerciseRepository(db),
    ProfileRepository(db),
    EntitlementRepository(db),
  );
}

Future<void> _pump(WidgetTester tester, _Harness h) async {
  tester.view.physicalSize = const Size(700, 4200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: DataToolsScreen(
      store: h.store,
      repository: h.repository,
      profile: h.profile,
      entitlements: h.entitlements,
    ),
  ));
  await tester.pumpAndSettle();
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

void main() {
  late _Harness h;
  setUp(() async => h = await _harness());
  tearDown(() async => h.dispose());

  testWidgets('没有权益：整组「导出进阶」不渲染（连 Ultra 字样都没有）', (WidgetTester tester) async {
    await _pump(tester, h);
    expect(find.byKey(const Key('export-annual-report')), findsNothing);
    expect(find.byKey(const Key('export-per-exercise-csv')), findsNothing);
    expect(find.textContaining('导出进阶'), findsNothing);
    expect(find.textContaining('Ultra'), findsNothing);
    // 原有免费导出照常存在（不误伤红线）
    expect(find.byKey(const Key('export-csv')), findsOneWidget);
  });

  testWidgets('权益过期：同样不渲染（降级不残留入口）', (WidgetTester tester) async {
    await _seedUltra(h, active: false);
    await _pump(tester, h);
    expect(find.byKey(const Key('export-annual-report')), findsNothing);
    expect(find.byKey(const Key('export-per-exercise-csv')), findsNothing);
  });

  testWidgets('有权益：出现「年度报告卡 / 按动作导出 CSV」，点年报能进去', (WidgetTester tester) async {
    await _seedUltra(h, active: true);
    await _pump(tester, h);

    expect(find.byKey(const Key('export-annual-report')), findsOneWidget);
    expect(find.byKey(const Key('export-per-exercise-csv')), findsOneWidget);

    await tester.tap(find.byKey(const Key('export-annual-report')));
    await tester.pumpAndSettle();
    expect(find.text('年度报告'), findsOneWidget);
    expect(find.byKey(const Key('annual-report-card')), findsOneWidget);
  });
}
