/// 练了么 · 会员页接真商店（M2）的接线判据
///
/// 用的是**假商店**（`test/fake_billing_gateway.dart`），不进真商店：
///   ① 价格显示的是商店给的字符串（不是硬编码）；
///   ② 购买成功 → 权益落库 + 页面状态跟着变；
///   ③ 购买失败 / pending / 取消 → 页面如实说，权益不变；
///   ④ 恢复购买成功 → 权益回来；商品拿不到 → 不显示价格（宁可不卖）。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/billing/billing_client.dart';
import 'package:lianleme/billing/entitlement.dart';
import 'package:lianleme/billing/paywall_screen.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart' show AppDatabase;
import 'package:lianleme/data/entitlement_repository.dart';

import 'fake_billing_gateway.dart';

void main() {
  late AppDatabase db;
  late EntitlementRepository repo;
  late FakeBillingGateway gateway;
  late BillingClient client;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = EntitlementRepository(db);
    gateway = FakeBillingGateway(products: fakeStoreProducts());
    client = BillingClient(
      gateway: gateway,
      repository: repo,
      now: () => DateTime(2026, 11, 5, 12),
      restoreQuietWindow: const Duration(milliseconds: 20),
      transactionTimeout: const Duration(seconds: 2),
    );
  });

  tearDown(() async {
    await client.dispose();
    await gateway.dispose();
    await db.close();
  });

  Future<void> pumpFrames(WidgetTester tester, {int frames = 20}) async {
    for (int i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpPaywall(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: PaywallScreen(repository: repo, billing: client),
    ));
    await pumpFrames(tester);
  }

  /// 等某个 finder 出现（异步购买/恢复的结果要经过 stream + DB + setState）。
  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    for (int i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('★ 真目录：价格逐字来自商店商品（¥8 / ¥38 / ¥68 是商店返回值）',
      (WidgetTester tester) async {
    await pumpPaywall(tester);
    expect(find.byKey(const Key('product-price-monthly')), findsOneWidget);
    expect(find.text('¥8.00'), findsOneWidget);
    expect(find.text('¥38.00'), findsOneWidget);
    expect(find.text('¥68.00'), findsOneWidget);
    expect(find.byKey(const Key('buy-yearly')), findsOneWidget);
  });

  testWidgets('购买成功 → 权益落库 + 页面状态变成已开通', (WidgetTester tester) async {
    await pumpPaywall(tester);
    expect(find.text('你还没有开通 Ultra。'), findsOneWidget);

    await tester.tap(find.byKey(const Key('buy-yearly')));
    await tester.pump();
    gateway.emit(purchasedTx(
        productId: UltraProductIds.yearly,
        purchaseId: 'tx_y1',
        atMs: DateTime(2026, 11, 5, 11).millisecondsSinceEpoch,
      ));
    await pumpUntil(tester, find.textContaining('购买成功'));

    expect(find.textContaining('购买成功'), findsOneWidget);
    expect((await repo.access(DateTime(2026, 11, 5, 13).millisecondsSinceEpoch)).ultra,
        isTrue);
    // _load() 刷新后的状态行（有效期到某天）
    await pumpFrames(tester);
    expect(find.textContaining('有效期到'), findsOneWidget);
  });

  testWidgets('购买失败 → 可读原因、权益不变', (WidgetTester tester) async {
    gateway.buyError = BillingException('商店没有接受这次购买请求，请稍后再试。');
    await pumpPaywall(tester);
    await tester.tap(find.byKey(const Key('buy-monthly')));
    await pumpUntil(tester, find.textContaining('商店没有接受'));

    expect(find.textContaining('商店没有接受'), findsOneWidget);
    expect(await repo.all(), isEmpty);
  });

  testWidgets('pending（待确认）→ 如实说明，不写权益', (WidgetTester tester) async {
    await pumpPaywall(tester);
    await tester.tap(find.byKey(const Key('buy-yearly')));
    await tester.pump();
    gateway.emit(pendingTx());
    await pumpUntil(tester, find.textContaining('等待商店确认'));

    expect(find.textContaining('等待商店确认'), findsOneWidget);
    expect(await repo.all(), isEmpty);
  });

  testWidgets('取消购买 → 说明没有扣款、权益不变', (WidgetTester tester) async {
    await pumpPaywall(tester);
    await tester.tap(find.byKey(const Key('buy-monthly')));
    await tester.pump();
    gateway.emit(canceledTx(productId: UltraProductIds.monthly));
    await pumpUntil(tester, find.textContaining('没有扣款'));

    expect(find.textContaining('没有扣款'), findsOneWidget);
    expect(await repo.all(), isEmpty);
  });

  testWidgets('★ 恢复购买成功 → 权益回来（终身：没有到期时间）', (WidgetTester tester) async {
    gateway.restoreQueue.add(restoredTx());
    await pumpPaywall(tester);
    await tester.tap(find.byKey(const Key('restore-purchases')));
    await pumpUntil(tester, find.textContaining('已恢复 1 项'));

    expect(find.textContaining('已恢复 1 项'), findsOneWidget);
    final List<UltraEntitlement> all = await repo.all();
    expect(all, hasLength(1));
    expect(all.single.expiresAtMs, isNull);
  });

  testWidgets('没有可恢复的购买 → 不假装成功', (WidgetTester tester) async {
    await pumpPaywall(tester);
    await tester.tap(find.byKey(const Key('restore-purchases')));
    await pumpUntil(tester, find.textContaining('没有找到'));

    expect(find.textContaining('没有找到'), findsOneWidget);
    expect(await repo.all(), isEmpty);
    expect(gateway.restoreCalls, 1);
  });

  testWidgets('商品拿不到 → 不显示任何价格与购买按钮（宁可不卖，也不编价格）',
      (WidgetTester tester) async {
    gateway.available = false;
    await pumpPaywall(tester);
    expect(find.byKey(const Key('ultra-unavailable')), findsOneWidget);
    expect(find.byKey(const Key('buy-monthly')), findsNothing);
    expect(find.byKey(const Key('buy-yearly')), findsNothing);
    expect(find.byKey(const Key('buy-lifetime')), findsNothing);
    // 页面上不允许出现任何"看起来像价格"的金额（旧价/新价都不行）
    expect(find.textContaining('¥'), findsNothing);
  });
}
