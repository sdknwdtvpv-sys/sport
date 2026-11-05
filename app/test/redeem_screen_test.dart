/// 练了么 · 兑换页（M4a）平台分支 + 兑换状态
///
/// 判据（方案 §9 判据 3 的那一条，M4a 先做自建码；Apple Offer Code 面板在 M4b）：
///   * **iOS 不渲染输入框**（Apple 3.1.1 不允许自建码解锁内容）；
///   * 非 iOS 有输入框，成功写权益、失败给准确原因。
library;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/billing/billing_server.dart';
import 'package:lianleme/billing/entitlement.dart';
import 'package:lianleme/billing/redeem_screen.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/entitlement_repository.dart';
import 'package:flutter/material.dart';

import 'fake_billing_server.dart';

const int day = 24 * 60 * 60 * 1000;

void main() {
  late AppDatabase db;
  late EntitlementRepository repo;
  late FakeBillingServerApi api;
  late FakeSessionStore sessions;
  late BillingServerClient client;
  final int nowMs = DateTime(2026, 11, 6, 12).millisecondsSinceEpoch;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = EntitlementRepository(db);
    api = FakeBillingServerApi();
    sessions = FakeSessionStore.loggedIn();
    client = BillingServerClient(
      api: api,
      sessionStore: sessions,
      repository: repo,
      now: () => DateTime.fromMillisecondsSinceEpoch(nowMs),
      timeout: const Duration(milliseconds: 200),
    );
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    client.close();
    await db.close();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RedeemScreen(
        client: client,
        repository: repo,
        now: () => DateTime.fromMillisecondsSinceEpoch(nowMs),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('iOS：不渲染自建码输入框（只如实说明去 App Store 兑换）', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpScreen(tester);

    expect(find.byKey(const Key('redeem-code-field')), findsNothing);
    expect(find.byKey(const Key('redeem-submit')), findsNothing);
    expect(find.byKey(const Key('redeem-ios-note')), findsOneWidget);
    expect(api.calls, isEmpty);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android：出现输入框，兑换成功 → 权益生效', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    api.redeemResponse = serverEntitlement(
      product: 'redeem',
      source: 'redeem',
      environment: null,
      expiresAtMs: nowMs + 365 * day,
    );
    await pumpScreen(tester);

    expect(find.byKey(const Key('redeem-code-field')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('redeem-code-field')), 'lmu-aaaaa-aaaaa-aaaaa-aaaaa');
    await tester.tap(find.byKey(const Key('redeem-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('redeem-success')), findsOneWidget);
    expect(api.redeemedCodes, hasLength(1));
    final UltraEntitlement? best = await repo.best(nowMs);
    expect(best?.source, UltraSource.redeemCode);
    expect((await repo.access(nowMs)).ultra, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('已用 / 限速：显示准确原因，不写权益', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    api.redeemError = const BillingServerException(
      '这个兑换码已经被使用过了（一次性）',
      statusCode: 409,
      code: 'used',
    );
    await pumpScreen(tester);
    await tester.enterText(find.byKey(const Key('redeem-code-field')), 'LMU-AAAAA-AAAAA-AAAAA-AAAAA');
    await tester.tap(find.byKey(const Key('redeem-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('redeem-error')), findsOneWidget);
    expect(find.textContaining('使用过'), findsOneWidget);
    expect(await repo.all(), isEmpty);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('未登录：提示先登录，不发请求', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    sessions.session = null;
    await pumpScreen(tester);
    await tester.enterText(find.byKey(const Key('redeem-code-field')), 'LMU-AAAAA-AAAAA-AAAAA-AAAAA');
    await tester.tap(find.byKey(const Key('redeem-submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('登录'), findsOneWidget);
    expect(api.calls, isEmpty);
    debugDefaultTargetPlatformOverride = null;
  });
}
