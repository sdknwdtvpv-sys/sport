/// 练了么 · 真内购接线（M2）的判据
///
/// 全部用**假商店**跑（`test/fake_billing_gateway.dart`），不进真商店、不碰平台通道。
/// 对应 `docs/plan-membership-2026-10-10.md` §九：判据 4（未登录也能买/恢复）、
/// 判据 2 的价格来源（商品视图）、判据 8（降级不删本机数据，这里补"状态机接线"那一半）。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/billing/billing_client.dart';
import 'package:lianleme/billing/entitlement.dart';
import 'package:lianleme/billing/paywall_copy.dart';
import 'package:lianleme/data/db.dart' show AppDatabase;
import 'package:lianleme/data/entitlement_repository.dart';

import 'fake_billing_gateway.dart';

void main() {
  late AppDatabase db;
  late EntitlementRepository repo;
  late FakeBillingGateway gateway;
  late BillingClient client;

  const int nowMs = 1760000000000;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = EntitlementRepository(db);
    gateway = FakeBillingGateway(products: fakeStoreProducts());
    client = BillingClient(
      gateway: gateway,
      repository: repo,
      now: () => DateTime.fromMillisecondsSinceEpoch(nowMs),
      restoreQuietWindow: const Duration(milliseconds: 20),
      transactionTimeout: const Duration(seconds: 2),
    );
  });

  tearDown(() async {
    await client.dispose();
    await gateway.dispose();
    await db.close();
  });

  Future<void> flush() async {
    // 让 broadcast stream 的事件与微任务落地（不依赖真实计时器）。
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  group('商品目录：价格只能来自商店', () {
    test('三个商品都拉到：priceLabel 逐字是商店给的字符串，档位/推荐档正确', () async {
      await client.start();
      final List<UltraProductView> views = await client.loadCatalog();
      expect(views, hasLength(3));
      final Map<UltraProduct, UltraProductView> byProduct = <UltraProduct, UltraProductView>{
        for (final UltraProductView v in views) v.product: v,
      };
      expect(byProduct[UltraProduct.monthly]!.priceLabel, '¥8.00');
      expect(byProduct[UltraProduct.yearly]!.priceLabel, '¥38.00');
      expect(byProduct[UltraProduct.lifetime]!.priceLabel, '¥68.00');
      expect(byProduct[UltraProduct.yearly]!.recommended, isTrue,
          reason: '年订阅是推荐档（这一屏唯一的 accent 按钮）');
      expect(byProduct[UltraProduct.monthly]!.duration, '每月');
      expect(byProduct[UltraProduct.lifetime]!.duration, '一次性买断');
      expect(client.lastCatalogError, isNull);
    });

    test('商店给的是别的价 → 界面跟着变（证明没有硬编码价格）', () async {
      gateway.products = const <StoreProduct>[
        StoreProduct(id: UltraProductIds.monthly, title: 'x', priceLabel: 'JP¥450'),
      ];
      final List<UltraProductView> views = await client.loadCatalog();
      expect(views.single.priceLabel, 'JP¥450');
    });

    test('拉商品失败 → 空目录 + 可读原因（不编价格、不假装有商品）', () async {
      gateway.queryError = BillingException('获取商品信息失败：商品还没在后台创建');
      final List<UltraProductView> views = await client.loadCatalog();
      expect(views, isEmpty);
      expect(client.lastCatalogError, contains('获取商品信息失败'));
    });

    test('商店不可用 → 空目录（未登录 Apple ID / 设备限制都是这条路）', () async {
      gateway.available = false;
      expect(await client.loadCatalog(), isEmpty);
      expect(client.lastCatalogError, isNotNull);
    });

    test('M2 不写试用天数（插件不暴露 introductory offer，编数字比不写更危险）', () async {
      final List<UltraProductView> views = await client.loadCatalog();
      for (final UltraProductView v in views) {
        expect(v.trialDays, isNull, reason: '试用信息只能来自商店；拿不到就不写');
      }
    });
  });

  group('购买：成功 / 失败 / 取消 / pending', () {
    test('★ 购买成功 → 权益 active、到期时间按年周期估算、交易被完成一次', () async {
      await client.start();
      final Future<BillingResult> pending = client.buy(UltraProductIds.yearly);
      await flush();
      gateway.emit(purchasedTx());
      final BillingResult r = await pending;

      expect(r.ok, isTrue);
      expect(r.entitlement, isNotNull);
      expect(gateway.completedTransactions, hasLength(1),
          reason: 'iOS 不完成交易会重复弹；这里必须 complete 一次');
      expect(gateway.completedTransactions.single.purchaseId, 'tx_1');

      final UltraAccess access = await client.currentAccess();
      expect(access.ultra, isTrue);
      expect(access.state, UltraState.active);
      expect((await repo.all()).single.expiresAtMs, isNotNull);
    });

    test('购买失败 → 可读原因 + 权益不变（不写半条）', () async {
      await client.start();
      gateway.buyError = BillingException('商店没有接受这次购买请求，请稍后再试。');
      final BillingResult r = await client.buy(UltraProductIds.monthly);
      expect(r.ok, isFalse);
      expect(r.message, contains('商店没有接受'));
      expect(await repo.all(), isEmpty, reason: '失败不许改权益');
    });

    test('交易流回 error → 可读原因、权益不变、不 complete', () async {
      await client.start();
      final Future<BillingResult> pending = client.buy(UltraProductIds.yearly);
      await flush();
      gateway.emit(errorTx());
      final BillingResult r = await pending;
      expect(r.ok, isFalse);
      expect(r.message, contains('商店返回错误'));
      expect(await repo.all(), isEmpty);
      expect(gateway.completedTransactions, isEmpty);
    });

    test('用户取消 → 明确"没有扣款"、权益不变', () async {
      await client.start();
      final Future<BillingResult> pending = client.buy(UltraProductIds.yearly);
      await flush();
      gateway.emit(canceledTx());
      final BillingResult r = await pending;
      expect(r.action, BillingActionResult.canceled);
      expect(r.message, contains('没有扣款'));
      expect(await repo.all(), isEmpty);
    });

    test('★ pending（家长批准/延迟）→ 不写权益、不完成交易、界面能说明"待确认"', () async {
      await client.start();
      final Future<BillingResult> pending = client.buy(UltraProductIds.yearly);
      await flush();
      gateway.emit(pendingTx());
      final BillingResult r = await pending;
      expect(r.action, BillingActionResult.pending);
      expect(r.message, contains('等待商店确认'));
      expect(await repo.all(), isEmpty);
      expect(gateway.completedTransactions, isEmpty);
    });

    test('交易流重复同一笔 → 权益只有一条、complete 只一次（幂等）', () async {
      await client.start();
      final Future<BillingResult> pending = client.buy(UltraProductIds.yearly);
      await flush();
      gateway.emit(purchasedTx());
      await pending;
      gateway.emit(purchasedTx()); // 同一 purchaseId + transactionDate
      await flush();
      expect(await repo.all(), hasLength(1));
      expect(gateway.completedTransactions, hasLength(1),
          reason: '重复事件不许再 complete 一次');
    });

    test('商店配置错了（不是我们的商品）→ 不写权益，但交易要完成掉', () async {
      await client.start();
      final Future<BillingResult> pending = client.buy(UltraProductIds.yearly);
      await flush();
      gateway.emit(BillingTransaction(
        productId: 'com.someone.else.thing',
        status: BillingTxStatus.purchased,
        purchaseId: 'tx_other',
        transactionDateMs: nowMs,
        needsComplete: true,
      ));
      final BillingResult r = await pending;
      expect(r.ok, isFalse);
      expect(r.message, contains('不属于 Ultra'));
      expect(await repo.all(), isEmpty);
      expect(gateway.completedTransactions, hasLength(1),
          reason: '未知商品也要完成交易，否则 iOS 一直重投');
    });

    test('needsComplete=false 时不调用 complete（重复完成会报错）', () async {
      await client.start();
      final Future<BillingResult> pending = client.buy(UltraProductIds.lifetime);
      await flush();
      gateway.emit(purchasedTx(
        productId: UltraProductIds.lifetime,
        purchaseId: 'tx_no_complete',
        needsComplete: false,
      ));
      await pending;
      expect(gateway.completedTransactions, isEmpty);
    });
  });

  group('恢复购买', () {
    test('★ 恢复成功（终身）→ 权益 active、expiresAt null、界面报恢复了几项', () async {
      gateway.restoreQueue.add(restoredTx());
      await client.start();
      final BillingResult r = await client.restore();
      expect(r.ok, isTrue);
      expect(r.message, contains('已恢复 1 项'));
      final UltraAccess access = await client.currentAccess();
      expect(access.ultra, isTrue);
      expect(access.state, UltraState.active);
      expect((await repo.all()).single.expiresAtMs, isNull, reason: '终身没有到期时间');
      expect(gateway.completedTransactions, hasLength(1));
    });

    test('恢复时一笔都没有 → 如实说"没有找到"、权益不变（不假装成功）', () async {
      await client.start();
      final BillingResult r = await client.restore();
      expect(r.ok, isFalse);
      expect(r.message, contains('没有找到'));
      expect(await repo.all(), isEmpty);
      expect(gateway.restoreCalls, 1);
    });
  });

  group('未登录也能买 / 恢复（判据 4）', () {
    test('★ 本机没有任何账号会话时，购买成功、权益照样生效', () async {
      // 前提：登录会话表是空的（未登录用户）。
      expect(await db.select(db.authSession).get(), isEmpty);
      await client.start();
      final Future<BillingResult> pending = client.buy(UltraProductIds.monthly);
      await flush();
      gateway.emit(purchasedTx(productId: UltraProductIds.monthly, purchaseId: 'tx_anon'));
      final BillingResult r = await pending;
      expect(r.ok, isTrue);
      expect((await client.currentAccess()).ultra, isTrue);
      expect(await db.select(db.authSession).get(), isEmpty,
          reason: '买内购不该顺手建出登录会话（Apple 5.1.1(v)）');
    });
  });

  group('降级/退款：状态机接线的另一半', () {
    test('退款记录 → 立即降级（refunded），但本机数据一条不删', () async {
      await repo.upsert(UltraEntitlement(
        id: 'tx_refunded',
        product: UltraProduct.monthly,
        source: UltraSource.apple,
        purchasedAtMs: nowMs - 1000,
        expiresAtMs: nowMs + 30 * 24 * 3600 * 1000,
        refundedAtMs: nowMs - 500,
      ));
      final UltraAccess access = await client.currentAccess();
      expect(access.ultra, isFalse);
      expect(access.state, UltraState.refunded);
      expect(await repo.all(), hasLength(1),
          reason: '降级只改"给不给能力"，不许删记录/数据');
    });

    test('到期且没有宽限/重试窗 → expired；有宽限期 → 照给', () async {
      await repo.upsert(UltraEntitlement(
        id: 'tx_expired',
        product: UltraProduct.yearly,
        source: UltraSource.apple,
        purchasedAtMs: nowMs - 400 * 24 * 3600 * 1000,
        expiresAtMs: nowMs - 1000,
      ));
      expect((await client.currentAccess()).state, UltraState.expired);

      await repo.clear();
      await repo.upsert(UltraEntitlement(
        id: 'tx_grace',
        product: UltraProduct.yearly,
        source: UltraSource.apple,
        purchasedAtMs: nowMs - 400 * 24 * 3600 * 1000,
        expiresAtMs: nowMs - 1000,
        graceUntilMs: nowMs + 6 * 24 * 3600 * 1000,
      ));
      final UltraAccess grace = await client.currentAccess();
      expect(grace.ultra, isTrue);
      expect(grace.state, UltraState.grace);
    });
  });

  group('到期时间估算（M2 本地口径，M3 会被收据覆盖）', () {
    test('月度 = +1 自然月，1 月 31 日夹到 2 月最后一天', () {
      final DateTime jan31 = DateTime(2026, 1, 31, 12);
      final int? exp = estimatedExpiryMs(UltraProduct.monthly, jan31.millisecondsSinceEpoch);
      final DateTime got = DateTime.fromMillisecondsSinceEpoch(exp!);
      expect(got.month, 2);
      expect(got.day, 28, reason: '2026 不是闰年');
      expect(got.hour, 12);
    });

    test('年度 = +1 自然年，2 月 29 日夹到 2 月 28 日', () {
      final DateTime feb29 = DateTime(2024, 2, 29, 9);
      final int? exp = estimatedExpiryMs(UltraProduct.yearly, feb29.millisecondsSinceEpoch);
      final DateTime got = DateTime.fromMillisecondsSinceEpoch(exp!);
      expect(got.year, 2025);
      expect(got.month, 2);
      expect(got.day, 28);
    });

    test('终身 = null', () {
      expect(estimatedExpiryMs(UltraProduct.lifetime, nowMs), isNull);
    });
  });
}
