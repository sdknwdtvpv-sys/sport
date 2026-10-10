/// 练了么 · 会员（**Ultra**）权益仓储（M1）
///
/// 职责很小、也很硬：**把 `UltraEntitlement` 与 `entitlement` 表来回搬**，
/// 外加一条事件流水。判定逻辑一行都不在这里（它在 `lib/billing/entitlement.dart` 的纯函数里）
/// —— 这样"给不给权益"这件事可以被一次性测干净，而不用起数据库。
///
/// 与 `auth_session_repository.dart` / `body_metric_repository.dart` 同一个写法：
/// 构造时拿 `AppDatabase`，方法里读写 drift，**不缓存**（本机库很便宜，缓存会造出
/// "界面看到的和库里存的不是一件事"那类 bug）。
library;

import 'package:drift/drift.dart';

import '../billing/entitlement.dart';
import 'db.dart';

class EntitlementRepository {
  EntitlementRepository(this._db);

  final AppDatabase _db;

  /// 全部权益记录（含已退款/已撤销的 —— 界面要能如实说"已退款"）
  Future<List<UltraEntitlement>> all() async {
    final List<EntitlementData> rows = await _db.select(_db.entitlement).get();
    return rows.map(_fromRow).toList(growable: false);
  }

  /// **现在最该生效的那一条**（挑选规则是纯函数，在 `pickBestEntitlement` 里）。
  Future<UltraEntitlement?> best(int nowMs) async => pickBestEntitlement(await all(), nowMs);

  /// 现在该给什么权益（界面用这一个就够）。
  ///
  /// ⚠️ 它**不联网**：远端核实是 M3 的事。本机这一层的作用就是"没网也能用"。
  Future<UltraAccess> access(int nowMs) async => resolveUltraAccess(await best(nowMs), nowMs);

  /// 写入 / 覆盖一条权益（按 `id` 幂等）。
  Future<void> upsert(UltraEntitlement e) async {
    await _db.into(_db.entitlement).insertOnConflictUpdate(
          EntitlementCompanion.insert(
            id: e.id,
            product: e.product.name,
            source: e.source.name,
            purchasedAtMs: e.purchasedAtMs,
            expiresAtMs: Value<int?>(e.expiresAtMs),
            isTrial: Value<bool>(e.isTrial),
            graceUntilMs: Value<int?>(e.graceUntilMs),
            billingRetryUntilMs: Value<int?>(e.billingRetryUntilMs),
            revokedAtMs: Value<int?>(e.revokedAtMs),
            refundedAtMs: Value<int?>(e.refundedAtMs),
            lastVerifiedAtMs: Value<int?>(e.lastVerifiedAtMs),
          ),
        );
  }

  /// 记一条计费事件（客服与排障用，见 `db.dart` 那张表的注释）
  Future<void> logEvent(String kind, {String? detail, required int atMs}) async {
    await _db.into(_db.billingEvent).insert(
          BillingEventCompanion.insert(
            kind: kind,
            atMs: atMs,
            detail: Value<String?>(detail),
          ),
        );
  }

  /// 最近的计费事件（新的在前）
  Future<List<BillingEventData>> recentEvents({int limit = 50}) {
    final Selectable<BillingEventData> q = _db.select(_db.billingEvent)
      ..orderBy(<OrderClauseGenerator<$BillingEventTable>>[
        ($BillingEventTable t) => OrderingTerm.desc(t.atMs),
      ])
      ..limit(limit);
    return q.get();
  }

  /// 清空（"删除全部数据"用；也用于测试）
  Future<void> clear() async {
    await _db.delete(_db.entitlement).go();
    await _db.delete(_db.billingEvent).go();
  }

  static UltraEntitlement _fromRow(EntitlementData r) => UltraEntitlement(
        id: r.id,
        product: UltraProduct.values.firstWhere(
          (UltraProduct p) => p.name == r.product,
          orElse: () => UltraProduct.monthly,
        ),
        source: UltraSource.values.firstWhere(
          (UltraSource x) => x.name == r.source,
          orElse: () => UltraSource.debug,
        ),
        purchasedAtMs: r.purchasedAtMs,
        expiresAtMs: r.expiresAtMs,
        isTrial: r.isTrial,
        graceUntilMs: r.graceUntilMs,
        billingRetryUntilMs: r.billingRetryUntilMs,
        revokedAtMs: r.revokedAtMs,
        refundedAtMs: r.refundedAtMs,
        lastVerifiedAtMs: r.lastVerifiedAtMs,
      );
}
