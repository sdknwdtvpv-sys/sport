/// 练了么 · 真内购（M2）：**可注入的商店网关 + 交易 → 权益的接线**
///
/// 施工图：`docs/plan-membership-2026-10-10.md` §五（内购实现）、§八（代码落点）、
/// §九（判据）、§十 M2。一句话说清这一层的职责：
///
///   **把 `in_app_purchase` 的「商品 / 交易事件」翻译成我们的「商品视图 / 权益记录」**，
///   并且把 iOS 必须做的 `completePurchase` 做完（不做的话同一笔交易每次启动都重弹），
///   把 Android 的 `pendingCompletePurchase` 按插件给的指示处理掉。
///
/// 三条边界（都是仓库既有决策，不在这里重新设计）：
///
///   1. **价格只来自商店**：`StoreProduct.priceLabel` 逐字取 `ProductDetails.price`；
///      拿不到商品就返回空目录 → 会员页写"暂时获取不到商品信息"，**绝不硬编码价格**
///      （硬编码价与 App Store 不一致是明确的拒审理由）。
///   2. **不引第三方变现 SDK**：只有 Flutter 官方的 `in_app_purchase`（pubspec 里有理由）。
///   3. **未登录也能买 / 恢复**：这一层只认 `EntitlementRepository`（本机库），
///      不依赖账号会话 —— Apple 5.1.1(v) 与方案 §7.1 第 4 条。
///
/// ⚠️ **M4a 起**：如果注入了 [BillingServerClient]，交易成功后会把它上送服务端，
///   **以服务端返回的到期时间/环境为准**；服务端失败/超时/未登录则回退本地估算
///   （离线可用是红线）。本地估算仍然是兜底：月 +1 自然月 / 年 +1 自然年 / 终身 = null。
///   `isTrial` 恒为 false、**不显示"试用 N 天"** —— 试用信息不在 `ProductDetails` 里
///   （插件 3.3.1 不暴露 introductory offer），编一个数字比不写更危险。
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, debugPrint, defaultTargetPlatform;
import 'package:in_app_purchase/in_app_purchase.dart';

import '../data/entitlement_repository.dart';
import 'billing_server.dart';
import 'entitlement.dart';
import 'paywall_copy.dart';

/// 三个商品的 ID —— **唯一真源**。
///
/// 与 `docs/plan-membership-2026-10-10.md` §3.1 逐字一致；商品 ID 一旦在
/// App Store Connect 创建就**不能改**，改字符串等于换一个没人买过的商品。
class UltraProductIds {
  const UltraProductIds._();

  static const String monthly = 'com.sdknwdtvpv.lianleme.ultra.monthly';
  static const String yearly = 'com.sdknwdtvpv.lianleme.ultra.yearly';
  static const String lifetime = 'com.sdknwdtvpv.lianleme.ultra.lifetime';

  static const Set<String> all = <String>{monthly, yearly, lifetime};
}

/// 商品 ID → 我们的商品档位。不是我们的商品返回 null（调用方据此跳过，不猜）。
UltraProduct? ultraProductForStoreId(String id) {
  switch (id) {
    case UltraProductIds.monthly:
      return UltraProduct.monthly;
    case UltraProductIds.yearly:
      return UltraProduct.yearly;
    case UltraProductIds.lifetime:
      return UltraProduct.lifetime;
    default:
      return null;
  }
}

/// 可读的商店错误。**不吞异常**：它带着原始 message，界面可以如实告诉用户。
class BillingException implements Exception {
  BillingException(this.message) : detail = null;

  BillingException.withDetail(this.message, this.detail);

  /// 已经翻译成中文、可直接给用户看的一句；原始错误放 [detail]。
  final String message;

  /// 平台原始信息（排障用，不直接展示）。
  final String? detail;

  @override
  String toString() =>
      detail == null ? 'BillingException: $message' : 'BillingException: $message（$detail）';
}

/// 商店返回的一个商品。**价格字符串逐字来自商店**，这一层不拼也不改。
class StoreProduct {
  const StoreProduct({required this.id, required this.title, required this.priceLabel});

  final String id;
  final String title;
  final String priceLabel;
}

/// 一次交易事件的归一化状态。
enum BillingTxStatus { purchased, restored, pending, error, canceled }

/// 从商店交易流归一化出来的一条事件（平台差异已抹平）。
class BillingTransaction {
  const BillingTransaction({
    required this.productId,
    required this.status,
    this.purchaseId,
    this.transactionDateMs,
    this.errorMessage,
    this.needsComplete = false,
    this.serverVerificationData,
  });

  final String productId;
  final BillingTxStatus status;

  /// 商店的交易号（iOS `transactionId` / Android `orderId`）。**权益的幂等键**。
  final String? purchaseId;

  /// 交易时间（毫秒时间戳）。`purchased/restored` 才有。
  final int? transactionDateMs;

  /// `status == error` 时的可读原因。
  final String? errorMessage;

  /// 插件说"这笔交易需要调用 completePurchase"（iOS 必须；Android 由 isAcknowledged 推导）。
  final bool needsComplete;

  /// StoreKit 2 的交易 JWS（`verificationData.serverVerificationData`）。
  /// **只有 iOS 有**；Android 是 purchaseToken，服务端计费端点不吃它 → 客户端只走本地。
  final String? serverVerificationData;

  /// 幂等键：同一笔交易第二次到达时，不许再写一遍权益、也不许再 complete 一次。
  String get key => '${purchaseId ?? productId}@${transactionDateMs ?? 0}';
}

/// **可注入的商店网关**。
///
/// 生产用 [InAppPurchaseGateway]（包官方插件）；测试用假实现（`test/fake_billing_gateway.dart`）
/// —— 假商店让"购买成功 / 失败 / 取消 / pending / 恢复 / 商品拿不到"全部可测，且**不进真商店**。
abstract class BillingGateway {
  /// 这台设备的商店是否可用（未登录 Apple ID、家长控制、设备限制都会让它为 false）。
  Future<bool> isAvailable();

  /// 拉商品。返回的 [StoreProduct.priceLabel] 必须**逐字**是商店给的价。
  Future<List<StoreProduct>> queryProducts(Iterable<String> ids);

  /// 发起购买（订阅与非消耗型都走非消耗型接口）。
  /// 抛 [BillingException] = 商店没接住请求（可读原因在里面）。
  Future<void> buy(String productId);

  /// 发起恢复购买；结果通过 [transactions] 异步回来（可能一笔都没有）。
  Future<void> restore();

  /// 归一化后的交易流（真实现订阅 `InAppPurchase.purchaseStream`）。
  Stream<BillingTransaction> get transactions;

  /// 完成一笔交易（iOS 不调用会重复弹；Android 的 acknowledge 也走这里）。
  Future<void> complete(BillingTransaction tx);

  /// 这笔权益来自哪个商店（写进 `entitlement.source`）。
  UltraSource get storeSource;

  Future<void> dispose();
}

/// 真实现：包 Flutter 官方的 `in_app_purchase`。
///
/// ⚠️ 插件文档要求**启动时**就订阅 `purchaseStream`（否则会漏掉上次没完成的交易）。
/// 本版（`kUltraReleased == false`）会员页在 release 里不可达，所以订阅发生在**会员页打开时**；
/// M4 翻开关之前要把 `BillingClient.start()` 挪到 `main()`（与"启动静默恢复"一起做）。
class InAppPurchaseGateway implements BillingGateway {
  InAppPurchaseGateway({InAppPurchase? iap}) : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  final Map<String, ProductDetails> _products = <String, ProductDetails>{};
  final Map<String, PurchaseDetails> _raw = <String, PurchaseDetails>{};
  final StreamController<BillingTransaction> _out =
      StreamController<BillingTransaction>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _sub;

  @override
  UltraSource get storeSource =>
      defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS
          ? UltraSource.apple
          : UltraSource.google;

  @override
  Stream<BillingTransaction> get transactions {
    _ensureListening();
    return _out.stream;
  }

  void _ensureListening() {
    if (_sub != null) return;
    _sub = _iap.purchaseStream.listen(
      _handle,
      onError: (Object e) {
        // 平台流本身出错（而不是某一笔交易 error）：作为一条可读事件送出去，
        // 让界面能把"恢复/购买失败"说清楚，而不是静默等超时。
        _out.add(BillingTransaction(
          productId: '',
          status: BillingTxStatus.error,
          errorMessage: '商店连接出错了：${_short(e)}',
        ));
      },
    );
  }

  @override
  Future<bool> isAvailable() async {
    try {
      return await _iap.isAvailable();
    } catch (e) {
      throw BillingException.withDetail('商店暂时不可用，请稍后再试。', _short(e));
    }
  }

  @override
  Future<List<StoreProduct>> queryProducts(Iterable<String> ids) async {
    final Set<String> wanted = ids.toSet();
    if (wanted.isEmpty) return const <StoreProduct>[];
    try {
      final ProductDetailsResponse resp = await _iap.queryProductDetails(wanted);
      if (resp.error != null) {
        throw BillingException.withDetail(
          '获取商品信息失败：${resp.error!.message}',
          '${resp.error!.code}/${resp.error!.source}',
        );
      }
      // 查到的商品要缓存：buy() 需要 ProductDetails 对象（插件要求），不能现编。
      for (final ProductDetails d in resp.productDetails) {
        _products[d.id] = d;
      }
      return resp.productDetails
          .map((ProductDetails d) => StoreProduct(
                id: d.id,
                title: d.title,
                // **价格逐字来自商店**（含货币符号/本地化格式），这一行不许"美化"。
                priceLabel: d.price,
              ))
          .toList(growable: false);
    } on BillingException {
      rethrow;
    } catch (e) {
      throw BillingException.withDetail('获取商品信息失败，请稍后再试。', _short(e));
    }
  }

  @override
  Future<void> buy(String productId) async {
    final ProductDetails? details = _products[productId];
    if (details == null) {
      throw BillingException('商品信息还没加载好，请返回重试。');
    }
    try {
      final bool ok = await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: details),
      );
      if (!ok) throw BillingException('商店没有接受这次购买请求，请稍后再试。');
    } on BillingException {
      rethrow;
    } catch (e) {
      throw BillingException.withDetail('购买请求没有发出去，请稍后再试。', _short(e));
    }
  }

  @override
  Future<void> restore() async {
    try {
      await _iap.restorePurchases();
    } catch (e) {
      throw BillingException.withDetail('恢复购买请求没有发出去，请稍后再试。', _short(e));
    }
  }

  void _handle(List<PurchaseDetails> list) {
    for (final PurchaseDetails d in list) {
      _raw[_key(d.productID, d.purchaseID, d.transactionDate)] = d;
      _out.add(BillingTransaction(
        productId: d.productID,
        purchaseId: d.purchaseID,
        transactionDateMs: int.tryParse(d.transactionDate ?? ''),
        status: _statusOf(d.status),
        errorMessage: d.error == null ? null : _readableError(d.error!),
        needsComplete: d.pendingCompletePurchase,
        serverVerificationData: d.verificationData.serverVerificationData.isEmpty
            ? null
            : d.verificationData.serverVerificationData,
      ));
    }
  }

  @override
  Future<void> complete(BillingTransaction tx) async {
    final PurchaseDetails? raw =
        _raw[_key(tx.productId, tx.purchaseId, tx.transactionDateMs?.toString())];
    if (raw == null) {
      // 重复事件/跨会话的事件：插件已经没有对应的 PurchaseDetails 了，没有可完成的。
      return;
    }
    await _iap.completePurchase(raw);
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _out.close();
  }

  // ── 内部工具 ─────────────────────────────────────────────────────────
  static String _key(String productId, String? purchaseId, String? dateMs) =>
      '$productId@${purchaseId ?? ''}@${dateMs ?? ''}';

  static BillingTxStatus _statusOf(PurchaseStatus s) {
    switch (s) {
      case PurchaseStatus.purchased:
        return BillingTxStatus.purchased;
      case PurchaseStatus.restored:
        return BillingTxStatus.restored;
      case PurchaseStatus.pending:
        return BillingTxStatus.pending;
      case PurchaseStatus.error:
        return BillingTxStatus.error;
      case PurchaseStatus.canceled:
        return BillingTxStatus.canceled;
    }
  }

  static String _readableError(IAPError e) {
    // 不吞原始 message：商店的报错是排障唯一线索（也避免"购买失败"一句空话）。
    final String code = e.code.isEmpty ? '' : '（${e.code}）';
    return '商店返回错误$code：${e.message}';
  }

  static String _short(Object e) {
    final String s = e.toString();
    return s.length <= 120 ? s : '${s.substring(0, 120)}…';
  }
}

/// 一次用户动作（购买 / 恢复）的结果。界面只认这个对象，不自己拼状态。
enum BillingActionResult { success, pending, canceled, failed }

class BillingResult {
  const BillingResult._(this.action, this.message, {this.entitlement});

  factory BillingResult.success(UltraEntitlement e, String message) =>
      BillingResult._(BillingActionResult.success, message, entitlement: e);

  factory BillingResult.pending(String message) =>
      BillingResult._(BillingActionResult.pending, message);

  factory BillingResult.canceled(String message) =>
      BillingResult._(BillingActionResult.canceled, message);

  factory BillingResult.failed(String message) =>
      BillingResult._(BillingActionResult.failed, message);

  final BillingActionResult action;

  /// 可直接显示给用户的一句（成功 / 取消 / 待确认 / 失败原因）。
  final String message;

  /// 成功时的权益记录（失败/取消/pending 为 null）。
  final UltraEntitlement? entitlement;

  bool get ok => action == BillingActionResult.success;
}

/// **交易 → 权益**的接线（M2 判据 4 的落点）。
///
/// 它只做四件事：订阅交易流、把成功交易写成权益、替商店完成交易、把结果以
/// [BillingResult] 交回给界面。九态判定一行都不在这里（在 `entitlement.dart` 的纯函数里）。
class BillingClient {
  BillingClient({
    required this.gateway,
    required this.repository,
    this.server,
    DateTime Function()? now,
    this.transactionTimeout = const Duration(minutes: 2),
    this.restoreQuietWindow = const Duration(milliseconds: 900),
  }) : _now = now ?? DateTime.now;

  final BillingGateway gateway;
  final EntitlementRepository repository;

  /// 服务端计费客户端（M4a）。null = 这个包没配服务器 / 测试只测本地。
  ///
  /// ⚠️ 它**不阻塞购买结果**：上送失败只影响到期时间是否被服务端校准，
  /// 本地权益照常写、购买照常报成功（`lastServerError` 留一句可读原因）。
  final BillingServerClient? server;
  final DateTime Function() _now;

  /// 购买后等交易流的最长时间（超时如实说，不假装成功）。
  final Duration transactionTimeout;

  /// 恢复购买时"多久没有新事件就算结束"的安静窗口（`restorePurchases()` 不返回结果）。
  final Duration restoreQuietWindow;

  StreamSubscription<BillingTransaction>? _sub;
  final Set<String> _handled = <String>{};
  Completer<BillingResult>? _buyWaiter;
  Completer<BillingResult>? _restoreWaiter;
  int _restoredCount = 0;
  Timer? _restoreTimer;
  UltraEntitlement? _lastDelivered;
  bool _disposed = false;

  int get _nowMs => _now().millisecondsSinceEpoch;

  /// 最近一次商品拉取失败的可读原因（成功时为 null）。页面可据此显示更具体的话。
  String? lastCatalogError;

  /// 订阅交易流。**必须在任何购买/恢复之前调用**（页面 initState 里）。
  Future<void> start() async {
    if (_sub != null || _disposed) return;
    _sub = gateway.transactions.listen(_onTransaction, onError: (Object e) {
      _finishBuy(BillingResult.failed('商店连接出错了：${_shorten(e)}'));
      _finishRestore(BillingResult.failed('恢复购买失败：${_shorten(e)}'));
    });
  }

  /// 会员页商品目录：**价格来自商店**；拿不到就返回空（页面写"暂时获取不到"）。
  ///
  /// 不向上抛：页面对"拿不到商品"的处置是同一句如实说明；原因留在 [lastCatalogError]。
  Future<List<UltraProductView>> loadCatalog() async {
    lastCatalogError = null;
    try {
      final bool available = await gateway.isAvailable();
      if (!available) {
        lastCatalogError = '这台设备的商店暂时不可用。';
        return const <UltraProductView>[];
      }
      final List<StoreProduct> products = await gateway.queryProducts(UltraProductIds.all);
      return products.map(_viewOf).whereType<UltraProductView>().toList(growable: false);
    } on BillingException catch (e) {
      lastCatalogError = e.message;
      return const <UltraProductView>[];
    } catch (e) {
      lastCatalogError = '获取商品信息失败：${_shorten(e)}';
      return const <UltraProductView>[];
    }
  }

  /// 现在该给什么权益（与 `EntitlementRepository.access` 同一个口径）。
  Future<UltraAccess> currentAccess() => repository.access(_nowMs);

  /// 发起购买；**等交易流给出终态**再返回（成功/取消/失败/待确认）。
  Future<BillingResult> buy(String productId) async {
    if (_buyWaiter != null) return BillingResult.failed('正在处理上一次购买，请稍候。');
    final Completer<BillingResult> waiter = Completer<BillingResult>();
    _buyWaiter = waiter;
    try {
      await gateway.buy(productId);
    } on BillingException catch (e) {
      _buyWaiter = null;
      return BillingResult.failed(e.message);
    } catch (e) {
      _buyWaiter = null;
      return BillingResult.failed('购买请求没有发出去，请稍后再试（${_shorten(e)}）。');
    }
    try {
      return await waiter.future.timeout(transactionTimeout);
    } on TimeoutException {
      _buyWaiter = null;
      return BillingResult.failed(
          '购买没有完成（等了 ${transactionTimeout.inSeconds} 秒没有结果）。'
          '如果已经扣款，请稍后点「恢复购买」。');
    }
  }

  /// 恢复购买。`restorePurchases()` 本身不返回结果：收集一段**安静窗口**内的事件，
  /// 有就报恢复了几项，没有就如实说"没有找到可以恢复的购买"（不假装成功）。
  Future<BillingResult> restore() async {
    if (_restoreWaiter != null) return BillingResult.failed('正在恢复中，请稍候。');
    _restoredCount = 0;
    final Completer<BillingResult> waiter = Completer<BillingResult>();
    _restoreWaiter = waiter;
    _armRestoreTimer();
    try {
      await gateway.restore();
    } on BillingException catch (e) {
      _finishRestore(BillingResult.failed(e.message));
    } catch (e) {
      _finishRestore(BillingResult.failed('恢复购买请求没有发出去，请稍后再试（${_shorten(e)}）。'));
    }
    return waiter.future;
  }

  void _armRestoreTimer() {
    _restoreTimer?.cancel();
    _restoreTimer = Timer(restoreQuietWindow, () {
      if (_restoreWaiter == null) return;
      final UltraEntitlement? e = _lastDelivered;
      if (_restoredCount > 0 && e != null) {
        _finishRestore(BillingResult.success(e, '已恢复 $_restoredCount 项购买。'));
      } else {
        _finishRestore(BillingResult.failed('没有找到可以恢复的购买。'));
      }
    });
  }

  /// 交易流到达。
  void _onTransaction(BillingTransaction tx) {
    switch (tx.status) {
      case BillingTxStatus.pending:
        // 待确认（例如家长批准 / 商店延迟）：**不写权益、不完成**，如实告诉用户。
        _finishBuy(BillingResult.pending('购买正在等待商店确认；确认之后 Ultra 会自动生效。'));
      case BillingTxStatus.canceled:
        _finishBuy(BillingResult.canceled('已取消购买，没有扣款。'));
      case BillingTxStatus.error:
        _finishBuy(BillingResult.failed(tx.errorMessage ?? '购买失败，请稍后再试。'));
        _finishRestore(BillingResult.failed(tx.errorMessage ?? '恢复购买失败，请稍后再试。'));
      case BillingTxStatus.purchased:
      case BillingTxStatus.restored:
        unawaited(_deliver(tx));
    }
  }

  /// 交付：写权益 → 完成交易 → 回报结果。**幂等**：同一笔交易只做一次。
  Future<void> _deliver(BillingTransaction tx) async {
    final UltraProduct? product = ultraProductForStoreId(tx.productId);
    if (product == null) {
      // 不是我们的商品（商店配置错了/旧商品）：不写权益，但要完成交易，
      // 否则 iOS 会一直重投这笔未完成的交易。
      if (tx.needsComplete) {
        try {
          await gateway.complete(tx);
        } catch (_) {
          // 完成失败由插件下次重投兜底；不是我们的商品也不该让界面崩。
        }
      }
      _finishBuy(BillingResult.failed('这个商品不属于 Ultra（${tx.productId}），没有开通权益。'));
      return;
    }

    final String key = tx.key;
    if (_handled.contains(key)) {
      // 重复事件：权益已经写过、交易也完成过了 —— 不再写、不再 complete。
      return;
    }
    _handled.add(key);

    final int purchasedAtMs = tx.transactionDateMs ?? _nowMs;
    final UltraEntitlement entitlement = UltraEntitlement(
      id: key,
      product: product,
      source: gateway.storeSource,
      purchasedAtMs: purchasedAtMs,
      // ⚠️ M2 无服务端验签：到期时间按商品周期**估算**，M3 用收据里的真实值覆盖。
      expiresAtMs: estimatedExpiryMs(product, purchasedAtMs),
      lastVerifiedAtMs: _nowMs,
    );
    await repository.upsert(entitlement);
    UltraEntitlement delivered = entitlement;
    _lastDelivered = entitlement;
    await repository.logEvent(
      tx.status == BillingTxStatus.restored ? 'restored' : 'purchased',
      detail: tx.productId,
      atMs: _nowMs,
    );

    // ── 上送服务端校准（M4a）：失败/超时/未登录都**不影响**购买结果 ──
    final BillingServerClient? server = this.server;
    final String? jws = tx.serverVerificationData;
    if (server != null &&
        jws != null &&
        jws.isNotEmpty &&
        gateway.storeSource == UltraSource.apple) {
      try {
        final ServerSyncResult synced = await server.submitPurchase(jws);
        if (synced.ok && synced.entitlement != null) {
          delivered = synced.entitlement!;
          _lastDelivered = delivered;
        }
      } catch (e) {
        // 服务端这一层自己已经兜住大多数错误；这是最后一道保险（绝不反推购买失败）。
        debugPrint('billing server sync failed: $e');
      }
    }

    // 先交付、再完成（插件要求：内容交付之后才能 complete）。
    if (tx.needsComplete) {
      try {
        await gateway.complete(tx);
      } catch (_) {
        // 完成失败不推翻权益（权益已落库）；插件会在下次启动重投，客户端走幂等路径。
      }
    }

    if (_restoreWaiter != null) {
      _restoredCount += 1;
      _armRestoreTimer();
    }
    _finishBuy(BillingResult.success(delivered, '购买成功，Ultra 已开通。'));
  }

  void _finishBuy(BillingResult result) {
    final Completer<BillingResult>? w = _buyWaiter;
    if (w == null || w.isCompleted) return;
    _buyWaiter = null;
    w.complete(result);
  }

  void _finishRestore(BillingResult result) {
    final Completer<BillingResult>? w = _restoreWaiter;
    if (w == null || w.isCompleted) return;
    _restoreWaiter = null;
    _restoreTimer?.cancel();
    _restoreTimer = null;
    w.complete(result);
  }

  /// 界面用完（会员页 dispose）时调用：取消订阅、清掉未完成的等待。
  Future<void> dispose() async {
    _disposed = true;
    _restoreTimer?.cancel();
    _restoreTimer = null;
    await _sub?.cancel();
    _sub = null;
    _finishBuy(BillingResult.failed('页面已关闭。'));
    _finishRestore(BillingResult.failed('页面已关闭。'));
    // 谁建的 server 客户端谁关（HttpClient 不关会把测试进程挂住）。
    server?.close();
  }

  UltraProductView? _viewOf(StoreProduct p) {
    final UltraProduct? product = ultraProductForStoreId(p.id);
    if (product == null) return null;
    return UltraProductView(
      id: p.id,
      product: product,
      title: switch (product) {
        UltraProduct.monthly => 'Ultra 月订阅',
        UltraProduct.yearly => 'Ultra 年订阅',
        UltraProduct.lifetime => 'Ultra 终身',
      },
      duration: switch (product) {
        UltraProduct.monthly => '每月',
        UltraProduct.yearly => '1 年',
        UltraProduct.lifetime => '一次性买断',
      },
      // 价格**只来自商店**（`ProductDetails.price`），这里一个字都不拼。
      priceLabel: p.priceLabel,
      // M2 不写试用天数：插件 3.3.1 不暴露 introductory offer，编一个数字比不写更危险。
      // 商品在 App Store Connect 配了试用时，M3/M4 改由服务端下发的真实信息展示。
      trialDays: null,
      recommended: product == UltraProduct.yearly,
    );
  }

  static String _shorten(Object e) {
    final String s = e.toString();
    return s.length <= 120 ? s : '${s.substring(0, 120)}…';
  }
}

/// 商品周期 → 估算的到期时间（毫秒）。**终身 = null**。
///
/// ⚠️ 仅用于 M2（没有服务端验签）的本地离线显示；M3 会被收据里的真实到期时间覆盖。
/// 月度/年度用"自然月/自然年"并**把日期夹到目标月的最后一天**（1 月 31 日 + 1 月 → 2 月 28/29 日）：
/// 宁可显示得稍早一天，也不要让用户以为比实际多一天。
int? estimatedExpiryMs(UltraProduct product, int purchasedAtMs) {
  if (product == UltraProduct.lifetime) return null;
  final DateTime from = DateTime.fromMillisecondsSinceEpoch(purchasedAtMs);
  final DateTime to =
      product == UltraProduct.monthly ? _addMonths(from, 1) : _addYears(from, 1);
  return to.millisecondsSinceEpoch;
}

DateTime _addMonths(DateTime t, int months) {
  final int total = t.month - 1 + months;
  final int year = t.year + total ~/ 12;
  final int month = total % 12 + 1;
  final int day = _clampDay(year, month, t.day);
  return DateTime(year, month, day, t.hour, t.minute, t.second, t.millisecond);
}

DateTime _addYears(DateTime t, int years) {
  final int year = t.year + years;
  final int day = _clampDay(year, t.month, t.day);
  return DateTime(year, t.month, day, t.hour, t.minute, t.second, t.millisecond);
}

int _clampDay(int year, int month, int day) {
  final int last = DateTime(year, month + 1, 0).day;
  return day > last ? last : day;
}
