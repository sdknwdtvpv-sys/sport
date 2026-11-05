/// 测试用**假商店**（不进真商店、不碰平台通道）
///
/// M2 的判据全部靠它跑：购买成功 / 失败 / 取消 / pending / 恢复 / 商品拿不到。
/// 它实现 [BillingGateway]，所以 `BillingClient` 那一层被**原样测到**（不是只测一个假控制器）。
library;

import 'dart:async';

import 'package:lianleme/billing/billing_client.dart';
import 'package:lianleme/billing/entitlement.dart';

class FakeBillingGateway implements BillingGateway {
  FakeBillingGateway({
    this.available = true,
    List<StoreProduct> products = const <StoreProduct>[],
    this.storeSource = UltraSource.apple,
  }) : products = List<StoreProduct>.of(products);

  bool available;
  List<StoreProduct> products;
  @override
  final UltraSource storeSource;

  /// 商店给的商品查询错误（不为 null 时 queryProducts 抛它）
  BillingException? queryError;

  /// 商店给的商品购买错误（不为 null 时 buy 抛它）
  BillingException? buyError;

  /// 恢复购买时"回放"的交易（真商店是通过购买流异步回来的）
  final List<BillingTransaction> restoreQueue = <BillingTransaction>[];

  final List<String> boughtProductIds = <String>[];
  int restoreCalls = 0;
  final List<BillingTransaction> completedTransactions = <BillingTransaction>[];
  final StreamController<BillingTransaction> _tx =
      StreamController<BillingTransaction>.broadcast();

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<StoreProduct>> queryProducts(Iterable<String> ids) async {
    if (queryError != null) throw queryError!;
    final Set<String> wanted = ids.toSet();
    return products.where((StoreProduct p) => wanted.contains(p.id)).toList();
  }

  @override
  Future<void> buy(String productId) async {
    boughtProductIds.add(productId);
    if (buyError != null) throw buyError!;
  }

  @override
  Future<void> restore() async {
    restoreCalls += 1;
    for (final BillingTransaction tx in restoreQueue) {
      _tx.add(tx);
    }
  }

  @override
  Stream<BillingTransaction> get transactions => _tx.stream;

  @override
  Future<void> complete(BillingTransaction tx) async {
    completedTransactions.add(tx);
  }

  /// 往交易流里推一条事件（模拟用户完成购买/商店回调）。
  void emit(BillingTransaction tx) => _tx.add(tx);

  @override
  Future<void> dispose() async {
    await _tx.close();
  }
}

/// 三个假商品：价格用 2026-11-05 用户拍板的新档位（¥8 / ¥38 / ¥68）。
/// 假商店的价格**只用于测试**；真目录的价格一律来自 `ProductDetails.price`。
List<StoreProduct> fakeStoreProducts() => const <StoreProduct>[
      StoreProduct(
        id: UltraProductIds.monthly,
        title: 'Ultra 月订阅',
        priceLabel: '¥8.00',
      ),
      StoreProduct(
        id: UltraProductIds.yearly,
        title: 'Ultra 年订阅',
        priceLabel: '¥38.00',
      ),
      StoreProduct(
        id: UltraProductIds.lifetime,
        title: 'Ultra 终身',
        priceLabel: '¥68.00',
      ),
    ];

/// 造一条"购买成功"的交易（时间固定，测试可预期）。
BillingTransaction purchasedTx({
  String productId = UltraProductIds.yearly,
  String purchaseId = 'tx_1',
  int atMs = 1760000000000,
  bool needsComplete = true,
}) =>
    BillingTransaction(
      productId: productId,
      status: BillingTxStatus.purchased,
      purchaseId: purchaseId,
      transactionDateMs: atMs,
      needsComplete: needsComplete,
    );

BillingTransaction restoredTx({
  String productId = UltraProductIds.lifetime,
  String purchaseId = 'tx_restore_1',
  int atMs = 1760000000000,
  bool needsComplete = true,
}) =>
    BillingTransaction(
      productId: productId,
      status: BillingTxStatus.restored,
      purchaseId: purchaseId,
      transactionDateMs: atMs,
      needsComplete: needsComplete,
    );

BillingTransaction pendingTx({String productId = UltraProductIds.yearly}) =>
    BillingTransaction(
      productId: productId,
      status: BillingTxStatus.pending,
      purchaseId: 'tx_pending',
      transactionDateMs: 1760000000000,
    );

BillingTransaction canceledTx({String productId = UltraProductIds.yearly}) =>
    BillingTransaction(productId: productId, status: BillingTxStatus.canceled);

BillingTransaction errorTx({
  String productId = UltraProductIds.yearly,
  String message = '商店返回错误（BILLING_UNAVAILABLE）：计费服务不可用',
}) =>
    BillingTransaction(
      productId: productId,
      status: BillingTxStatus.error,
      errorMessage: message,
    );
