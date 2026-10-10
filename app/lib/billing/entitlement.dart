/// 练了么 · 会员（**Ultra**）权益模型 —— 纯函数，不碰 IO（M1）
///
/// 施工图是 `docs/plan-membership-2026-10-10.md`：
///   * §4「权益的真相在哪」：商店收据 → 服务端 entitlement → 本机缓存（本文件是第三层）；
///   * §4.1 那张**九态状态机**表 —— 这个文件就是它的可执行版本。
///
/// 三条设计约束（写在前面，改之前先读）：
///
///   1. **纯函数**：只吃"字段 + 当前时间"，返回"该给什么权益"。不读时钟、不读库、不联网
///      —— 于是九态可以一条一条测（`app/test/entitlement_test.dart`）。
///   2. **宁松不严**：离线优先的产品里，本机缓存过期**不能**把用户锁在门外太久
///      （`kOfflineGraceMs`），但也**不能**永远给 —— 那等于"退款了还一直能用"。
///   3. **只减新能力，不删数据**：这里只回答"给不给 Ultra"，**不回答**"要不要删数据"；
///      降级的处置（云上多版本停止、本地数据一个字不动）在各自功能那边，见方案 §4.1。
library;

/// 权益的**来源**。
///
/// ⚠️ 它的含义是"**我们是从哪知道这条权益的**"，不是"钱付给了谁" ——
/// 真相永远在商店收据上（方案 §4）。`debug` 只可能出现在 debug 构建里。
enum UltraSource {
  apple,
  google,

  /// 国内自建兑换码（只在**非 iOS** 与官网渠道核销，见方案 §6.2/§6.3）
  redeemCode,

  /// **只在 debug 构建里存在**的假权益（M1 走查界面用，见 `debug_grant.dart`）
  debug,
}

/// 商品档位。与 App Store Connect / Play 里的商品一一对应（ID 见方案 §3.1）。
enum UltraProduct {
  monthly,
  yearly,

  /// 非消耗型买断。`expiresAtMs == null` 就是它。
  lifetime,
}

/// 权益的**系统状态**（方案 §4.1 那张表的左列）。
///
/// 表里那两个"离线态"**不在这里**，而是叠加在状态之上的一个标记
/// （[UltraAccess.unverified]）—— 理由：离线不是"另一种权益"，它只是
/// "我们对同一条权益**暂时没法核实**"。把它做成独立状态会让"到期"与"没网"
/// 这两个正交的维度互相污染（比如"离线但没到期"到底算 active 还是 offline-grace）。
enum UltraState {
  /// 什么都没有（也从没买过）
  none,

  /// 试用期内（年订阅的 7 天免费试用）
  trial,

  /// 有效（含**终身**）
  active,

  /// 扣款失败，但在 Apple 的**宽限期**内 → 照给
  grace,

  /// 宽限期也过了，Apple 仍在**账单重试** → 照给
  billingRetry,

  /// 订阅到期（且不在任何宽限/重试窗里）
  expired,

  /// 已退款（Apple 退款通知到达）→ 立即降级
  refunded,

  /// 已撤销（家庭共享被撤 / 购买被撤）→ 立即降级
  revoked,
}

/// 一条权益记录（对应 `entitlement` 表的一行）。
///
/// 字段名与表列一一对应；`id` 是**幂等键**（商店的原始交易号 / 兑换码批次 / 调试授权的固定串）。
class UltraEntitlement {
  const UltraEntitlement({
    required this.id,
    required this.product,
    required this.source,
    required this.purchasedAtMs,
    this.expiresAtMs,
    this.isTrial = false,
    this.graceUntilMs,
    this.billingRetryUntilMs,
    this.revokedAtMs,
    this.refundedAtMs,
    this.lastVerifiedAtMs,
  });

  /// 幂等键：同一条交易重复写入只会覆盖自己那一行。
  final String id;
  final UltraProduct product;
  final UltraSource source;
  final int purchasedAtMs;

  /// **null = 终身**（非消耗型买断）。有值 = 那一刻到期。
  final int? expiresAtMs;

  /// 是不是"免费试用期内"（Apple 的 introductory offer）。
  final bool isTrial;

  /// Apple 宽限期的截止时刻（`BillingGracePeriod`，要在 App Store Connect 里主动开）
  final int? graceUntilMs;

  /// Apple 账单重试的截止时刻
  final int? billingRetryUntilMs;

  /// 撤销 / 退款的时刻。**任何一条非空 → 立即降级**（不看到期时间）。
  final int? revokedAtMs;
  final int? refundedAtMs;

  /// 最近一次**成功核实**（服务端/商店）的时刻。离线宽限按它算。
  final int? lastVerifiedAtMs;

  /// 终态：退款或撤销。**一旦置上就不再恢复** —— 恢复购买会写一条新的记录。
  bool get isTerminal => revokedAtMs != null || refundedAtMs != null;

  /// 终身买断（没有到期时间）。仅在没有被撤销/退款时成立。
  bool get isLifetime => expiresAtMs == null && !isTerminal;

  /// ⚠️ **`null` 在这里的含义是"保持原值"，不是"清空"** ——
  /// 所以"把宽限窗清掉"这种动作必须用显式的 `clearGrace` / `clearBillingRetry`
  /// （`entitlement_test.dart` 里"续订要清掉宽限与重试窗"那条就是为了钉这件事写出来的：
  /// 最初没有 clear，续订之后旧的宽限窗还在，用户会看到"明明续上了却还写着宽限期"）。
  UltraEntitlement copyWith({
    int? expiresAtMs,
    bool clearExpiresAt = false,
    bool? isTrial,
    int? graceUntilMs,
    bool clearGrace = false,
    int? billingRetryUntilMs,
    bool clearBillingRetry = false,
    int? revokedAtMs,
    int? refundedAtMs,
    int? lastVerifiedAtMs,
  }) =>
      UltraEntitlement(
        id: id,
        product: product,
        source: source,
        purchasedAtMs: purchasedAtMs,
        expiresAtMs: clearExpiresAt ? null : (expiresAtMs ?? this.expiresAtMs),
        isTrial: isTrial ?? this.isTrial,
        graceUntilMs: clearGrace ? null : (graceUntilMs ?? this.graceUntilMs),
        billingRetryUntilMs:
            clearBillingRetry ? null : (billingRetryUntilMs ?? this.billingRetryUntilMs),
        revokedAtMs: revokedAtMs ?? this.revokedAtMs,
        refundedAtMs: refundedAtMs ?? this.refundedAtMs,
        lastVerifiedAtMs: lastVerifiedAtMs ?? this.lastVerifiedAtMs,
      );
}

/// 离线宽限：**最后一次成功核实之后**最多还能按缓存给多久。
///
/// 为什么是 7 天：它要同时满足两件事 —— 用户"飞一趟/出个差没网"不该被降级；
/// 而"退款了但设备一直离线"也不该无限期用下去。7 天是这两者之间一个说得出口的数，
/// 且与"每周至少打开一次"的使用节奏同量级。
const int kOfflineGraceMs = 7 * 24 * 60 * 60 * 1000;

/// 多久没核实就该去核一次（**给界面用**，不影响给不给权益）。
const int kReverifyAfterMs = 24 * 60 * 60 * 1000;

/// 一次判定的结果。界面只认这个对象，不自己拼状态。
class UltraAccess {
  const UltraAccess({
    required this.ultra,
    required this.state,
    this.msLeft,
    this.unverified = false,
  });

  /// **这一条判定就是"给不给 Ultra 能力"**（方案 §4.1 的"权益"那一列）。
  final bool ultra;
  final UltraState state;

  /// 距离到期还有多久（终身 = null）。界面写「有效期至…」/「还剩 N 天」用它。
  final int? msLeft;

  /// "我们暂时没法核实这条权益"（离线超过 `kReverifyAfterMs`）。
  ///
  /// ⚠️ 它与给不给权益**无关**：方案 §4.1 的 `offline-grace` 就是"给了 + 这个标记为真"，
  /// `offline-expired` 就是"没给 + 这个标记为真"。界面据此决定要不要写一句
  /// 「暂时连不上，先按上次的结果」——**但绝不弹"验证失败"**。
  final bool unverified;

  /// 免费用户：什么都没买过
  static const UltraAccess free = UltraAccess(ultra: false, state: UltraState.none);
}

/// **状态机本体**（方案 §4.1 的九态，逐条对应）。
///
/// 判定顺序（顺序本身是规格，不要重排）：
///   1. 没有记录 → `none`；
///   2. 退款 / 撤销 → **立即降级**（哪怕到期时间还没到）；
///   3. 终身 → `active`；
///   4. 未到期 → `trial`（试用中）或 `active`；
///   5. 已到期但在**宽限期**内 → `grace`（照给）；
///   6. 宽限期过了但在**账单重试**窗内 → `billingRetry`（照给）；
///   7. 否则 → `expired`（不给）。
UltraAccess resolveUltraAccess(UltraEntitlement? e, int nowMs) {
  if (e == null) return UltraAccess.free;

  final bool unverified = e.lastVerifiedAtMs != null &&
      nowMs - e.lastVerifiedAtMs! > kReverifyAfterMs;

  if (e.refundedAtMs != null) {
    return UltraAccess(ultra: false, state: UltraState.refunded, unverified: unverified);
  }
  if (e.revokedAtMs != null) {
    return UltraAccess(ultra: false, state: UltraState.revoked, unverified: unverified);
  }

  final int? exp = e.expiresAtMs;
  if (exp == null) {
    return UltraAccess(ultra: true, state: UltraState.active, unverified: unverified);
  }
  if (nowMs < exp) {
    return UltraAccess(
      ultra: true,
      state: e.isTrial ? UltraState.trial : UltraState.active,
      msLeft: exp - nowMs,
      unverified: unverified,
    );
  }

  final int? grace = e.graceUntilMs;
  if (grace != null && nowMs < grace) {
    return UltraAccess(
      ultra: true,
      state: UltraState.grace,
      msLeft: grace - nowMs,
      unverified: unverified,
    );
  }
  final int? retry = e.billingRetryUntilMs;
  if (retry != null && nowMs < retry) {
    return UltraAccess(
      ultra: true,
      state: UltraState.billingRetry,
      msLeft: retry - nowMs,
      unverified: unverified,
    );
  }
  return UltraAccess(ultra: false, state: UltraState.expired, unverified: unverified);
}

/// 从若干条记录里挑出**现在最该生效的那一条**（方案 §4「同一账号绑多个 Apple ID」那条：
/// 权益取**最长到期**；终身一旦绑定就是终身）。
///
/// 排序规则（同样是规格）：
///   1. 可用的（`ultra == true`）永远赢过不可用的；
///   2. 都可用时：终身 > 到期晚的 > 到期早的；
///   3. 都不可用时：给一条**信息量最大**的（refunded/revoked 优先于 expired）——
///      界面要能如实说"已退款"，而不是干巴巴写"已到期"。
UltraEntitlement? pickBestEntitlement(
    List<UltraEntitlement> all, int nowMs) {
  if (all.isEmpty) return null;

  UltraEntitlement? best;
  UltraAccess? bestAccess;
  for (final UltraEntitlement e in all) {
    final UltraAccess a = resolveUltraAccess(e, nowMs);
    if (best == null || bestAccess == null) {
      best = e;
      bestAccess = a;
      continue;
    }
    if (_better(e, a, best, bestAccess)) {
      best = e;
      bestAccess = a;
    }
  }
  return best;
}

bool _better(UltraEntitlement a, UltraAccess aa, UltraEntitlement b, UltraAccess ba) {
  if (aa.ultra != ba.ultra) return aa.ultra;
  if (aa.ultra) {
    final bool aLife = a.isLifetime;
    final bool bLife = b.isLifetime;
    if (aLife != bLife) return aLife;
    return (a.expiresAtMs ?? 0) > (b.expiresAtMs ?? 0);
  }
  return _terminalRank(aa.state) > _terminalRank(ba.state);
}

/// 不可用状态里"对用户更有信息量"的排序（退款/撤销 > 到期 > 什么都没有）
int _terminalRank(UltraState s) {
  switch (s) {
    case UltraState.refunded:
      return 3;
    case UltraState.revoked:
      return 2;
    case UltraState.expired:
      return 1;
    case UltraState.none:
    case UltraState.trial:
    case UltraState.active:
    case UltraState.grace:
    case UltraState.billingRetry:
      return 0;
  }
}

/// 服务端/商店回来的**事件**怎么改本机那一条（M3 会真正接上；M1 先把规则写死并测掉）。
///
/// 为什么现在就要写：这些规则**决定用户会不会觉得"我买了却不认"**，
/// 而它们全是纯函数 —— 等 M3 再补，就得在真实收据上试错。
UltraEntitlement applyBillingEvent(
  UltraEntitlement e,
  UltraBillingEvent event,
  int nowMs,
) {
  switch (event.kind) {
    case UltraEventKind.renewed:
      return e.copyWith(
        expiresAtMs: event.expiresAtMs ?? e.expiresAtMs,
        isTrial: false,
        clearGrace: true,
        clearBillingRetry: true,
        lastVerifiedAtMs: nowMs,
      );
    case UltraEventKind.graceStarted:
      // ⚠️ 宽限期与账单重试是**互斥的两种模式**（Apple 的语义：开了 Billing Grace Period
      // 就在宽限里，没开就直接进重试），不是"先宽限、宽限过了再重试"的串行两段 ——
      // 所以进入一个就清掉另一个，否则判定会按"先看宽限"的顺序给出与事实不符的状态。
      return e.copyWith(
        graceUntilMs: event.expiresAtMs,
        clearBillingRetry: true,
        lastVerifiedAtMs: nowMs,
      );
    case UltraEventKind.billingRetryStarted:
      return e.copyWith(
        billingRetryUntilMs: event.expiresAtMs,
        clearGrace: true,
        lastVerifiedAtMs: nowMs,
      );
    case UltraEventKind.refunded:
      return e.copyWith(refundedAtMs: nowMs, lastVerifiedAtMs: nowMs);
    case UltraEventKind.revoked:
      return e.copyWith(revokedAtMs: nowMs, lastVerifiedAtMs: nowMs);
    case UltraEventKind.verified:
      return e.copyWith(lastVerifiedAtMs: nowMs);
    case UltraEventKind.expired:
      // 到期不写"撤销"，只是时间过了 —— 判定由 `resolveUltraAccess` 按时间做。
      return e.copyWith(lastVerifiedAtMs: nowMs);
  }
}

/// 商店/服务端会告诉我们的几件事（`App Store Server Notifications V2` 的那几个关键类型）
enum UltraEventKind {
  /// 续订成功 / 首次购买（带新的到期时间）
  renewed,

  /// 进入宽限期（Apple `DID_FAIL_TO_RENEW` + `isInBillingRetryPeriod=false` 且开了宽限）
  graceStarted,

  /// 进入账单重试
  billingRetryStarted,

  /// 退款（`REFUND`）
  refunded,

  /// 撤销（家庭共享被撤 / `REVOKE`）
  revoked,

  /// 只是核实了一次（没有任何状态变化）
  verified,

  /// 到期（`EXPIRED`）
  expired,
}

/// 一条计费事件（M3 会从 `App Store Server Notifications V2` 映射过来）
class UltraBillingEvent {
  const UltraBillingEvent(this.kind, {this.expiresAtMs});

  final UltraEventKind kind;

  /// `renewed` 时是新的到期时间；`graceStarted` / `billingRetryStarted` 时是那个窗口的截止时刻。
  final int? expiresAtMs;
}
