/// 练了么 · 购买/恢复 → 服务端上送 → 本机权益（M4a 接线）
///
/// 用**假商店 + 假服务端**把整条链路跑通：交易流 → 本地立即生效 → 上送 JWS →
/// 服务端到期时间覆盖本地估算；服务端失败/未登录时**购买结果不受影响**。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/billing/billing_client.dart';
import 'package:lianleme/billing/billing_server.dart';
import 'package:lianleme/billing/entitlement.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/entitlement_repository.dart';

import 'fake_billing_gateway.dart';
import 'fake_billing_server.dart';

const int day = 24 * 60 * 60 * 1000;

void main() {
  late AppDatabase db;
  late EntitlementRepository repo;
  late FakeBillingGateway gateway;
  late FakeBillingServerApi api;
  late FakeSessionStore sessions;
  late BillingServerClient server;
  late BillingClient client;
  final int nowMs = DateTime(2026, 11, 6, 12).millisecondsSinceEpoch;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = EntitlementRepository(db);
    gateway = FakeBillingGateway(products: fakeStoreProducts());
    api = FakeBillingServerApi();
    sessions = FakeSessionStore.loggedIn();
    server = BillingServerClient(
      api: api,
      sessionStore: sessions,
      repository: repo,
      now: () => DateTime.fromMillisecondsSinceEpoch(nowMs),
      timeout: const Duration(milliseconds: 200),
    );
    client = BillingClient(
      gateway: gateway,
      repository: repo,
      server: server,
      now: () => DateTime.fromMillisecondsSinceEpoch(nowMs),
      restoreQuietWindow: const Duration(milliseconds: 30),
      transactionTimeout: const Duration(seconds: 2),
    );
  });

  tearDown(() async {
    await client.dispose();
    await gateway.dispose();
    await db.close();
  });

  Future<void> flush() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test('iOS 购买：上送 JWS → 服务端到期时间覆盖本地估算', () async {
    await client.start();
    final int txAt = nowMs - day;
    api.verifyResponse = serverEntitlement(expiresAtMs: nowMs + 45 * day);

    final Future<BillingResult> buying = client.buy(UltraProductIds.yearly);
    gateway.emit(purchasedTx(atMs: txAt, serverVerificationData: 'jws-1'));
    final BillingResult r = await buying;

    expect(r.ok, isTrue);
    expect(api.verifiedJws, <String>['jws-1']);
    expect(server.lastServerError, isNull);
    expect(r.entitlement?.expiresAtMs, nowMs + 45 * day);
    expect((await repo.best(nowMs))?.expiresAtMs, nowMs + 45 * day);
    expect(server.lastEnvironment, 'Production');
    expect(gateway.completedTransactions, hasLength(1), reason: '交付后要 complete（iOS 不完成会重弹）');
  });

  test('服务端 500 / 超时：购买仍成功，回退本地估算，原因可读', () async {
    await client.start();
    final int txAt = nowMs - day;
    api.verifyError = const BillingServerException('服务器返回 HTTP 500', statusCode: 500);

    final Future<BillingResult> buying = client.buy(UltraProductIds.yearly);
    gateway.emit(purchasedTx(atMs: txAt, serverVerificationData: 'jws-2'));
    final BillingResult r = await buying;

    expect(r.ok, isTrue, reason: '已经扣款了，服务端挂了不能反过来说购买失败');
    expect(r.entitlement?.expiresAtMs, estimatedExpiryMs(UltraProduct.yearly, txAt));
    expect(server.lastServerError, isNotNull);
    expect((await repo.access(nowMs)).ultra, isTrue);
  });

  test('未登录：不上送，纯本地生效（不建会话）', () async {
    sessions.session = null;
    await client.start();

    final Future<BillingResult> buying = client.buy(UltraProductIds.yearly);
    gateway.emit(purchasedTx(atMs: nowMs - day, serverVerificationData: 'jws-3'));
    final BillingResult r = await buying;

    expect(r.ok, isTrue);
    expect(api.calls, isEmpty);
    expect((await repo.access(nowMs)).ultra, isTrue);
    expect(sessions.session, isNull, reason: '购买不应该顺手建一个会话');
  });

  test('恢复购买：同样上送 JWS，服务端校准到期时间', () async {
    await client.start();
    api.verifyResponse = serverEntitlement(expiresAtMs: nowMs + 60 * day);
    gateway.restoreQueue.add(restoredTx(
      productId: UltraProductIds.yearly,
      atMs: nowMs - day,
      serverVerificationData: 'jws-restore',
    ));

    final BillingResult r = await client.restore();

    expect(r.ok, isTrue);
    expect(api.verifiedJws, <String>['jws-restore']);
    expect((await repo.best(nowMs))?.expiresAtMs, nowMs + 60 * day);
  });

  test('同一笔交易重放：只 complete 一次、只上送一次（幂等）', () async {
    await client.start();
    final BillingTransaction tx = purchasedTx(atMs: nowMs - day, serverVerificationData: 'jws-4');

    final Future<BillingResult> buying = client.buy(UltraProductIds.yearly);
    gateway.emit(tx);
    await buying;
    gateway.emit(tx);
    await flush();

    expect(gateway.completedTransactions, hasLength(1));
    expect(api.verifiedJws, hasLength(1));
  });

  test('登录后同步：服务端到期更晚 → 本地延长（只延长不缩短）', () async {
    await repo.upsert(UltraEntitlement(
      id: 'tx_seed',
      product: UltraProduct.yearly,
      source: UltraSource.apple,
      purchasedAtMs: nowMs - 30 * day,
      expiresAtMs: nowMs + 10 * day,
      lastVerifiedAtMs: nowMs - day,
    ));
    api.fetchResponse = serverEntitlement(expiresAtMs: nowMs + 40 * day);

    final ServerSyncResult r = await server.syncFromServer();

    expect(r.status, ServerSyncStatus.synced);
    expect((await repo.best(nowMs))?.expiresAtMs, nowMs + 40 * day);
  });

  test('登录后同步：服务端退款 → 本地立即降级', () async {
    await repo.upsert(UltraEntitlement(
      id: 'tx_seed',
      product: UltraProduct.yearly,
      source: UltraSource.apple,
      purchasedAtMs: nowMs - 30 * day,
      expiresAtMs: nowMs + 30 * day,
      lastVerifiedAtMs: nowMs - day,
    ));
    expect((await repo.access(nowMs)).ultra, isTrue);
    api.fetchResponse = serverEntitlement(status: 'refunded', refundedAtMs: nowMs);

    final ServerSyncResult r = await server.syncFromServer();

    expect(r.status, ServerSyncStatus.synced);
    final UltraAccess access = await repo.access(nowMs);
    expect(access.ultra, isFalse);
    expect(access.state, UltraState.refunded);
  });
}
