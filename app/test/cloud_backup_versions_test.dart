/// 练了么 · 云备份多版本界面（M4b）
///
/// 判据：
///   * **有权益**才去请求历史；免费/降级**一个请求都不发**；
///   * `kUltraReleased == false` 时免费用户看不到任何新的付费说明/入口；
///   * 恢复某一份 → **二次确认** → 取密文 → 客户端解密 → 合并 → 服务端设为最新；
///   * 失败（未登录/没网）如实说，不假装成功。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/backup/backup_crypto.dart';
import 'package:lianleme/backup/backup_transport.dart';
import 'package:lianleme/backup/backup_versions.dart';
import 'package:lianleme/backup/cloud_backup.dart';
import 'package:lianleme/backup/recovery_code.dart';
import 'package:lianleme/billing/entitlement.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/entitlement_repository.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/features/backup/cloud_backup_screen.dart';

import 'fake_backup_versions.dart';

const String _payload = '{"version":1,"workouts":[{"id":"w_1",'
    '"exercise_name":"深蹲","sets":[{"weight_kg":102.5,"reps":3}]}],'
    '"body":{},"marker":"cloud-versions-test"}';

String _code() => encodeRecoveryKey(
      Uint8List.fromList(List<int>.generate(16, (int i) => (i * 11 + 5) % 256)),
    );

class _Harness {
  _Harness(this.db, this.store, this.profile, this.repository, this.transport, this.entitlements);

  final AppDatabase db;
  final DriftLocalStore store;
  final ProfileRepository profile;
  final ExerciseRepository repository;
  final FakeBackupTransport transport;
  final EntitlementRepository entitlements;

  CloudBackup get cloud => CloudBackup(transport: transport);

  Future<void> dispose() => db.close();
}

Future<_Harness> _harness() async {
  final AppDatabase db = AppDatabase(NativeDatabase.memory());
  final _Harness h = _Harness(
    db,
    DriftLocalStore(db),
    ProfileRepository(db),
    ExerciseRepository(db),
    FakeBackupTransport(),
    EntitlementRepository(db),
  );
  await h.profile.setCloudAccount(_code(), nowMs: 1760000000000);
  return h;
}

Future<void> _seedEntitlement(_Harness h, {required bool active}) async {
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

Future<void> _pump(
  WidgetTester tester,
  _Harness h,
  FakeBackupVersionApi api, {
  bool? showUltra,
}) async {
  tester.view.physicalSize = const Size(600, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: CloudBackupScreen(
      store: h.store,
      repository: h.repository,
      profile: h.profile,
      cloud: h.cloud,
      entitlements: h.entitlements,
      versions: api,
      showUltra: showUltra,
      clock: () => DateTime(2026, 11, 6, 12),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.dragUntilVisible(target, find.byType(ListView), const Offset(0, -220));
  await tester.pumpAndSettle();
}

void main() {
  late _Harness h;
  late FakeBackupVersionApi api;

  setUp(() async {
    h = await _harness();
    api = FakeBackupVersionApi(versions: <CloudBackupVersion>[
      const CloudBackupVersion(seq: 2, bytes: 2048, createdAtMs: 1760000000000, isLatest: true),
      const CloudBackupVersion(seq: 1, bytes: 1024, createdAtMs: 1750000000000, isLatest: false),
    ]);
  });

  tearDown(() async => h.dispose());

  testWidgets('有权益：列出历史版本，且请求了列表', (WidgetTester tester) async {
    await _seedEntitlement(h, active: true);
    await _pump(tester, h, api);
    await _scrollTo(tester, find.byKey(const Key('cloud-version-2')));

    expect(api.calls, <String>['list']);
    expect(find.byKey(const Key('cloud-version-2')), findsOneWidget);
    expect(find.byKey(const Key('cloud-version-restore-1')), findsOneWidget);
    expect(find.byKey(const Key('cloud-version-restore-2')), findsNothing, reason: '最新一份不需要"恢复到这一份"');
  });

  testWidgets('免费/没有权益：不请求、不出现新的付费说明（发版口径）', (WidgetTester tester) async {
    await _pump(tester, h, api, showUltra: false);
    await tester.pumpAndSettle();

    expect(api.calls, isEmpty);
    expect(find.byKey(const Key('cloud-version-2')), findsNothing);
    expect(find.byKey(const Key('cloud-history-ultra-note')), findsNothing);
    expect(find.text('备份历史（Ultra）'), findsNothing);
  });

  testWidgets('免费 + 未来售卖开关：只给一行说明，仍然不发请求', (WidgetTester tester) async {
    await _pump(tester, h, api, showUltra: true);
    await _scrollTo(tester, find.byKey(const Key('cloud-history-ultra-note')));

    expect(api.calls, isEmpty);
    expect(find.byKey(const Key('cloud-history-ultra-note')), findsOneWidget);
  });

  testWidgets('降级（权益过期）：不再请求历史', (WidgetTester tester) async {
    await _seedEntitlement(h, active: false);
    await _pump(tester, h, api, showUltra: false);
    await tester.pumpAndSettle();

    expect(api.calls, isEmpty);
    expect(find.text('备份历史（Ultra）'), findsNothing);
  });

  testWidgets('恢复某一份：二次确认 → 取密文 → 解密合并 → 设为最新', (WidgetTester tester) async {
    await _seedEntitlement(h, active: true);
    final Uint8List key = decodeRecoveryKey(_code());
    api.envelopes[1] = await encryptBackupWithKey(plaintext: utf8.encode(_payload), key: key);
    await _pump(tester, h, api);
    await _scrollTo(tester, find.byKey(const Key('cloud-version-restore-1')));

    await tester.tap(find.byKey(const Key('cloud-version-restore-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cloud-version-restore-dialog')), findsOneWidget);
    expect(api.calls, <String>['list'], reason: '确认之前不许下载');

    await tester.tap(find.byKey(const Key('cloud-version-restore-ok')));
    await tester.pumpAndSettle();

    // 恢复完会刷新一次列表（'list' 再出现一次）
    expect(api.calls, <String>['list', 'download:1', 'restore:1', 'list']);
    expect(find.byKey(const Key('cloud-notice')), findsOneWidget);
    expect(find.textContaining('已恢复第 1 份'), findsOneWidget);
  });

  testWidgets('二次确认里点取消 → 不下载、不恢复', (WidgetTester tester) async {
    await _seedEntitlement(h, active: true);
    await _pump(tester, h, api);
    await _scrollTo(tester, find.byKey(const Key('cloud-version-restore-1')));

    await tester.tap(find.byKey(const Key('cloud-version-restore-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cloud-version-restore-cancel')));
    await tester.pumpAndSettle();

    expect(api.calls, <String>['list']);
  });

  testWidgets('未登录/取不到历史：如实说原因，不假装成功', (WidgetTester tester) async {
    await _seedEntitlement(h, active: true);
    api.listError = const BackupVersionException('登录状态已失效，请重新登录后再看备份历史。', statusCode: 401);
    await _pump(tester, h, api);
    await _scrollTo(tester, find.byKey(const Key('cloud-versions-error')));

    expect(find.byKey(const Key('cloud-versions-error')), findsOneWidget);
    expect(find.textContaining('重新登录'), findsOneWidget);
  });
}
