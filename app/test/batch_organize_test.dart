/// 练了么 · **批量整理历史**（Ultra 权益 8）的界面判据
///
/// 三条要守的：
///   1. **免费用户**：看得见「整理（Ultra）」，点下去是**去会员页**（不是偷偷允许、也不是没反应）；
///   2. **Ultra 用户**：进多选态 → 勾选 → 移到回收站（**先确认**，文案要说清可恢复）
///      → 真的只删勾中的那几条；
///   3. **退出多选**要干净（取消之后底部条消失、已选清空）—— 留着会让下一次点带着上次的选择。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/billing/entitlement.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/data/db.dart' hide SetRecord, Workout, Exercise, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/entitlement_repository.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/progress/all_data_screen.dart';

late AppDatabase db;
late DriftLocalStore store;
late ExerciseRepository repo;

/// 三条卧推记录（**同一个动作**，否则"全部记录"列表里一条都看不到）
const String _bench = 'ex_bb_bench_press';
List<SetRecord> _seed() => <SetRecord>[
      for (int i = 0; i < 3; i++)
        SetRecord(
          id: 's$i',
          workoutId: 'w1',
          exerciseId: _bench,
          setIndex: i + 1,
          reps: 10,
          weightKg: 60,
          completedAtMs: DateTime(2026, 10, 6, 19).millisecondsSinceEpoch + i * 60000,
        ),
    ];

Future<void> pumpAllData(
  WidgetTester tester, {
  EntitlementRepository? entitlements,
  VoidCallback? onOpenUltra,
}) async {
  tester.view.physicalSize = const Size(500, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: AllDataScreen(
      store: store,
      repository: repo,
      unit: WeightUnit.kg,
      now: DateTime(2026, 10, 10, 12),
      // ⚠️ **显式打开**（2026-10-11）：这一份测的是「批量整理」这个功能本身 ——
      // 它的默认开关 `kUltraReleased` 首版是 `false`（免费版先上，那一栏不渲染），
      // 「首版关着它 / 打开之后回来」那条判据在 `ultra_release_gate_test.dart` 里守。
      showUltra: true,
      entitlements: entitlements,
      onOpenUltra: onOpenUltra,
    ),
  ));
  // 这一屏加载时转圈 → 推固定时长（`pumpAndSettle` 等不到静止）
  for (int i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLocalStore(db);
    repo = ExerciseRepository(db);
    // ⚠️ **必须导种子**：这一屏默认选"最近练过的那个动作"，而那一步要
    // `repository.byId(...)` —— 库里没有那个动作时它选不出来，记录列表就是空的，
    // 于是"多选"根本没有行可勾（第一版就是这么写的，测试报"找不到 all-data-pick-s0"）。
    await repo.importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
    for (final SetRecord r in _seed()) {
      await store.saveSet(r);
    }
  });
  tearDown(() => db.close());

  Future<EntitlementRepository> ultraRepo() async {
    final EntitlementRepository r = EntitlementRepository(db);
    await r.upsert(UltraEntitlement(
      id: 'one',
      product: UltraProduct.yearly,
      source: UltraSource.apple,
      purchasedAtMs: DateTime(2026, 10, 1).millisecondsSinceEpoch,
      expiresAtMs: DateTime(2027, 10, 1).millisecondsSinceEpoch,
      lastVerifiedAtMs: DateTime(2026, 10, 9).millisecondsSinceEpoch,
    ));
    return r;
  }

  testWidgets('免费用户：看得见「整理（Ultra）」，点它是去会员页', (WidgetTester tester) async {
    var opened = 0;
    await pumpAllData(
      tester,
      entitlements: EntitlementRepository(db),
      onOpenUltra: () => opened++,
    );
    expect(find.text('整理（Ultra）'), findsOneWidget);
    expect(find.byKey(const Key('all-data-selection-bar')), findsNothing,
        reason: '免费用户不许进多选态');
    await tester.tap(find.byKey(const Key('all-data-organize')));
    await tester.pump();
    expect(opened, 1, reason: '点它应当是"去会员页"，而不是没反应或偷偷允许');
    expect(find.byKey(const Key('all-data-selection-bar')), findsNothing);
  });

  testWidgets('Ultra：进多选态 → 勾两组 → 移到回收站（先确认）→ 只删勾中的', (WidgetTester tester) async {
    final EntitlementRepository ent = await ultraRepo();
    await pumpAllData(tester, entitlements: ent);

    await tester.tap(find.byKey(const Key('all-data-organize')));
    await tester.pump();
    expect(find.byKey(const Key('all-data-selection-bar')), findsOneWidget);
    expect(find.text('已选 0 组'), findsOneWidget);

    await tester.tap(find.byKey(const Key('all-data-pick-s0')));
    await tester.tap(find.byKey(const Key('all-data-pick-s1')));
    await tester.pump();
    expect(find.text('已选 2 组'), findsOneWidget);

    await tester.tap(find.byKey(const Key('organize-trash')));
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.textContaining('把这 2 组移到回收站？'), findsOneWidget);
    expect(find.textContaining('可以随时'), findsOneWidget,
        reason: '确认文案要说清"能恢复" —— 否则用户不敢用这个功能');

    await tester.tap(find.byKey(const Key('organize-trash-confirm')));
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect((await store.allSets()).map((SetRecord r) => r.id).toList(), <String>['s2'],
        reason: '只删勾中的那两条');
    expect((await store.deletedSets()).map((DeletedSet d) => d.set.id).toSet(),
        <String>{'s0', 's1'});
    expect(find.byKey(const Key('all-data-selection-bar')), findsNothing,
        reason: '动作做完要退出多选态，别让用户以为还选着');
  });

  testWidgets('Ultra：取消之后底部条消失、已选清空', (WidgetTester tester) async {
    final EntitlementRepository ent = await ultraRepo();
    await pumpAllData(tester, entitlements: ent);
    await tester.tap(find.byKey(const Key('all-data-organize')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('all-data-pick-s0')));
    await tester.pump();
    expect(find.text('已选 1 组'), findsOneWidget);

    await tester.tap(find.byKey(const Key('organize-cancel')));
    await tester.pump();
    expect(find.byKey(const Key('all-data-selection-bar')), findsNothing);
    // 再进来一次：必须回到"已选 0 组"（上一次的选择不许留着）
    await tester.tap(find.byKey(const Key('all-data-organize')));
    await tester.pump();
    expect(find.text('已选 0 组'), findsOneWidget);
  });

  testWidgets('Ultra：没勾任何组时，两个动作都是不可点的（不是点了没反应）', (WidgetTester tester) async {
    final EntitlementRepository ent = await ultraRepo();
    await pumpAllData(tester, entitlements: ent);
    await tester.tap(find.byKey(const Key('all-data-organize')));
    await tester.pump();
    final TextButton trash = tester.widget<TextButton>(find.byKey(const Key('organize-trash')));
    final TextButton reassign = tester.widget<TextButton>(find.byKey(const Key('organize-reassign')));
    expect(trash.onPressed, isNull);
    expect(reassign.onPressed, isNull);
  });
}
