/// 练了么 · 服务端计费客户端（M4a）
///
/// 假 API + 内存会话 + 内存库：覆盖「只延长不缩短 / 退款立即降级 / 离线保留本地 /
/// 未登录不发请求 / 上送 JWS 后以服务端到期为准 / 兑换码各状态」。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/billing/billing_client.dart' show estimatedExpiryMs, UltraProductIds;
import 'package:lianleme/billing/billing_server.dart';
import 'package:lianleme/billing/entitlement.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/entitlement_repository.dart';

import 'fake_billing_server.dart';

const int day = 24 * 60 * 60 * 1000;

void main() {
  late AppDatabase db;
  late EntitlementRepository repo;
  late FakeBillingServerApi api;
  late FakeSessionStore sessions;
  late BillingServerClient client;
  final int nowMs = DateTime(2026, 11, 6, 12).millisecondsSinceEpoch;

  UltraEntitlement localYearly({int? expiresAtMs, int purchasedAtMs = 1760000000000}) =>
      UltraEntitlement(
        id: 'tx_local',
        product: UltraProduct.yearly,
        source: UltraSource.apple,
        purchasedAtMs: purchasedAtMs,
        expiresAtMs: expiresAtMs ?? nowMs + 10 * day,
        lastVerifiedAtMs: nowMs - day,
      );

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
    client.close();
    await db.close();
  });

  test('拉取权益：服务端到期更晚 → 只延长，并记下环境', () async {
    await repo.upsert(localYearly());
    api.fetchResponse = serverEntitlement(expiresAtMs: nowMs + 40 * day, updatedAtMs: nowMs);

    final ServerSyncResult r = await client.syncFromServer();

    expect(r.status, ServerSyncStatus.synced);
    final UltraEntitlement? best = await repo.best(nowMs);
    expect(best?.expiresAtMs, nowMs + 40 * day);
    expect(best?.lastVerifiedAtMs, nowMs);
    expect(client.lastEnvironment, 'Production');
    expect(api.calls.single, startsWith('fetch:lm1_'));
  });

  test('拉取权益：服务端到期更早 → 不缩短（离线优先的产品口径）', () async {
    await repo.upsert(localYearly(expiresAtMs: nowMs + 30 * day));
    api.fetchResponse = serverEntitlement(expiresAtMs: nowMs + 5 * day);

    await client.syncFromServer();

    expect((await repo.best(nowMs))?.expiresAtMs, nowMs + 30 * day);
  });

  test('服务端退款 → 本机立即降级（不等到期）', () async {
    await repo.upsert(localYearly(expiresAtMs: nowMs + 30 * day));
    api.fetchResponse = serverEntitlement(
      status: 'refunded',
      expiresAtMs: nowMs + 30 * day,
      refundedAtMs: nowMs,
    );

    final ServerSyncResult r = await client.syncFromServer();
    final UltraAccess access = await repo.access(nowMs);

    expect(r.status, ServerSyncStatus.synced);
    expect(access.ultra, isFalse);
    expect(access.state, UltraState.refunded);
    expect((await repo.all()).single.refundedAtMs, isNotNull);
  });

  test('服务端撤销 → 本机立即降级', () async {
    await repo.upsert(localYearly());
    api.fetchResponse = serverEntitlement(status: 'revoked', revokedAtMs: nowMs);

    await client.syncFromServer();

    final UltraAccess access = await repo.access(nowMs);
    expect(access.ultra, isFalse);
    expect(access.state, UltraState.revoked);
  });

  test('服务端说已到期 → 以服务端为准（可以缩短）', () async {
    await repo.upsert(localYearly(expiresAtMs: nowMs + 30 * day));
    api.fetchResponse = serverEntitlement(status: 'expired', expiresAtMs: nowMs - day);

    await client.syncFromServer();

    final UltraAccess access = await repo.access(nowMs);
    expect(access.ultra, isFalse);
    expect(access.state, UltraState.expired);
  });

  test('服务端没有权益（none）→ 不动本地（离线时不能凭"查不到"删权益）', () async {
    await repo.upsert(localYearly());
    api.fetchResponse = serverEntitlement(status: 'none', product: null);

    final ServerSyncResult r = await client.syncFromServer();

    expect(r.status, ServerSyncStatus.none);
    expect((await repo.access(nowMs)).ultra, isTrue);
  });

  test('没登录 → 一个请求都不发，本地权益原样', () async {
    await repo.upsert(localYearly());
    sessions.session = null;

    final ServerSyncResult r = await client.syncFromServer();

    expect(r.status, ServerSyncStatus.notLoggedIn);
    expect(api.calls, isEmpty);
    expect((await repo.access(nowMs)).ultra, isTrue);
  });

  test('连不上服务器 / 超时 → 回退本地，给出可读原因', () async {
    await repo.upsert(localYearly());
    api.fetchError = const BillingServerException('连不上服务器，先按本机记录显示。');

    final ServerSyncResult r = await client.syncFromServer();

    expect(r.status, ServerSyncStatus.offline);
    expect(r.message, contains('先按本机记录显示'));
    expect(client.lastServerError, isNotNull);
    expect((await repo.access(nowMs)).ultra, isTrue);
  });

  test('会话过期（HTTP 401）→ 按未登录处理，不留脏状态', () async {
    await repo.upsert(localYearly());
    api.fetchError = const BillingServerException('缺少或非法的会话令牌', statusCode: 401);

    final ServerSyncResult r = await client.syncFromServer();

    expect(r.status, ServerSyncStatus.notLoggedIn);
    expect((await repo.access(nowMs)).ultra, isTrue);
  });

  test('上送交易 JWS：成功则以服务端到期时间为准', () async {
    await repo.upsert(localYearly(expiresAtMs: nowMs + 10 * day));
    api.verifyResponse = serverEntitlement(expiresAtMs: nowMs + 60 * day);

    final ServerSyncResult r = await client.submitPurchase('jws-abc');

    expect(r.status, ServerSyncStatus.synced);
    expect(api.verifiedJws, <String>['jws-abc']);
    expect((await repo.best(nowMs))?.expiresAtMs, nowMs + 60 * day);
  });

  test('上送空 JWS / 没登录 → 不上送（购买仍按本地）', () async {
    expect((await client.submitPurchase('')).status, ServerSyncStatus.skipped);
    sessions.session = null;
    expect((await client.submitPurchase('jws')).status, ServerSyncStatus.notLoggedIn);
    expect(api.calls, isEmpty);
  });

  test('沙盒交易被服务端拒绝 → 可读原因，且本机权益不被改坏', () async {
    await repo.upsert(localYearly(expiresAtMs: nowMs + 10 * day));
    api.verifyError = const BillingServerException(
      '沙盒交易不能兑换正式权益',
      statusCode: 400,
      code: 'sandbox_not_allowed',
    );

    final ServerSyncResult r = await client.submitPurchase('jws-sandbox');

    expect(r.status, ServerSyncStatus.rejected);
    expect(r.message, contains('沙盒'));
    expect((await repo.best(nowMs))?.expiresAtMs, nowMs + 10 * day);
  });

  group('兑换码', () {
    test('成功：写一条 redeemCode 权益（到期以服务端为准）', () async {
      api.redeemResponse = serverEntitlement(
        product: 'redeem',
        source: 'redeem',
        environment: null,
        expiresAtMs: nowMs + 365 * day,
      );

      final RedeemResult r = await client.redeem('LMU-AAAAA-AAAAA-AAAAA-AAAAA');

      expect(r.status, RedeemStatus.success);
      expect(api.redeemedCodes, hasLength(1));
      final UltraEntitlement? best = await repo.best(nowMs);
      expect(best?.source, UltraSource.redeemCode);
      expect(best?.expiresAtMs, nowMs + 365 * day);
      expect((await repo.access(nowMs)).ultra, isTrue);
    });

    test('已用 / 过期 / 不存在 / 格式错 / 限速 各有准确状态（不糊成"兑换失败"）', () async {
      final Map<int, RedeemStatus> expected = <int, RedeemStatus>{
        400: RedeemStatus.invalidCode,
        404: RedeemStatus.notFound,
        409: RedeemStatus.used,
        410: RedeemStatus.expired,
        429: RedeemStatus.rateLimited,
      };
      for (final MapEntry<int, RedeemStatus> e in expected.entries) {
        api.redeemError = BillingServerException('服务端说不行', statusCode: e.key, retryAfterSec: 60);
        final RedeemResult r = await client.redeem('LMU-AAAAA-AAAAA-AAAAA-AAAAA');
        expect(r.status, e.value, reason: 'HTTP ${e.key}');
        expect(r.message, isNotNull);
      }
    });

    test('连线失败 → offline，本机权益不变', () async {
      api.redeemError = const BillingServerException('连不上服务器，先按本机记录显示。');
      final RedeemResult r = await client.redeem('LMU-AAAAA-AAAAA-AAAAA-AAAAA');
      expect(r.status, RedeemStatus.offline);
      expect(await repo.all(), isEmpty);
    });

    test('没登录 → 不发请求，提示先登录', () async {
      sessions.session = null;
      final RedeemResult r = await client.redeem('LMU-AAAAA-AAAAA-AAAAA-AAAAA');
      expect(r.status, RedeemStatus.notLoggedIn);
      expect(r.message, contains('登录'));
      expect(api.calls, isEmpty);
    });
  });

  test('本地估算函数仍是兜底（服务端不可用时的到期时间）', () {
    final DateTime from = DateTime.fromMillisecondsSinceEpoch(nowMs);
    expect(estimatedExpiryMs(UltraProduct.yearly, nowMs),
        DateTime(from.year + 1, from.month, from.day, from.hour, from.minute, from.second, from.millisecond)
            .millisecondsSinceEpoch);
    expect(estimatedExpiryMs(UltraProduct.lifetime, nowMs), isNull);
    expect(UltraProductIds.all, contains('com.sdknwdtvpv.lianleme.ultra.yearly'));
  });
}
