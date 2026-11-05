#!/usr/bin/env node
/**
 * 练了么 · 会员（Ultra）服务端**协议层**（M3）：Apple 验签 / 通知 / 权益下发 / 自建码核销
 *
 * 设计：`docs/plan-membership-2026-10-10.md` §五 / §6.2 / §6.4 / §八.3；口径写进
 * `docs/backend-design.md`。这一层**不联网**：Apple 根证书随代码入库（`server/apple/`），
 * 验签只用 `node:crypto`（`X509Certificate` 证书链 + ES256）。
 *
 * 四个端点（三个要登录，通知不要）：
 *
 *   POST /v1/billing/verify                 登录 · 体：{"signedTransaction":"<Apple JWS>"}
 *                                           → 用 x5c 链 + 内嵌 Apple Root CA - G3 验签，写权益
 *   POST /v1/billing/notifications/apple    **不鉴权** · 体：{"signedPayload":"<Apple V2 JWS>"}
 *                                           → 验签后按 notificationType 处理；notificationUUID 去重
 *   GET  /v1/billing/entitlement            登录 → 当前权益（过期/退款如实）
 *   POST /v1/billing/redeem                 登录 · 体：{"code":"LMU-…"} → 自建码原子核销
 *
 * 五条纪律：
 *   1. **日志里没有明文码、没有收据、没有 Authorization**（只打产品与结果）；
 *   2. **验签失败有不同的可读错误码**（`invalid_jws` / `untrusted_chain` / `wrong_bundle` …），
 *      但都**不回**任何证书/claim 内容；
 *   3. **只延长不缩短**；退款/撤销是终态（见 `billing-store.mjs`）；
 *   4. **通知幂等**：同一 `notificationUUID` 只处理一次；Apple 重试永远回 200；
 *   5. **不按 IP 记录**：兑换码限速需要来源，但只存 `sha256(ip)[:16]`，且不写进日志；
 *   6. **沙盒交易默认不能换真权益**：`allowSandboxTransactions` 默认 false，
 *      `verify` 拒绝沙盒 JWS（400 `sandbox_not_allowed`），沙盒通知只记事件不写权益。
 *      只有联调/TestFlight 沙盒验证时才显式打开（`LIANLEME_ALLOW_SANDBOX=1`）。
 */

import { createHash, verify, X509Certificate } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { REDEEM_PRODUCT } from './billing-store.mjs';
import { hashRedeemCode, isValidRedeemCode, normalizeRedeemCode } from './redeem-admin.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** App 的 bundle id —— 验签 claims 必核。 */
export const BUNDLE_ID = 'com.sdknwdtvpv.lianleme';

/** 三个商品 ID —— 与 `docs/plan-membership-2026-10-10.md` §3.1 与客户端逐字一致。 */
export const PRODUCT_IDS = Object.freeze({
  monthly: 'com.sdknwdtvpv.lianleme.ultra.monthly',
  yearly: 'com.sdknwdtvpv.lianleme.ultra.yearly',
  lifetime: 'com.sdknwdtvpv.lianleme.ultra.lifetime',
});
export const PRODUCT_SET = new Set(Object.values(PRODUCT_IDS));

/** Apple Root CA - G3 的 SHA-256（与 `server/apple/README.md` 同一串）。 */
export const APPLE_ROOT_SHA256 =
  '63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79';

/** 兑换码限速（方案 §6.4；自检可以覆盖）。 */
export const DEFAULT_LIMITS = Object.freeze({
  redeemPerIpPerHour: 20,
  redeemPerAccountPerHour: 5,
  /** 连续失败 ≥ 10 次 → 锁 1 小时 */
  redeemFailLock: 10,
  redeemFailWindowMs: 60 * 60 * 1000,
  redeemAttemptWindowMs: 60 * 60 * 1000,
  /** 请求体上限：JWS/JSON 都很小，64KB 足够 */
  bodyLimitBytes: 64 * 1024,
});

/** 读入库的 Apple 根证书（**不联网**）。每次调用新读，自检可注入自己的根。 */
export function loadAppleRootPem() {
  return readFileSync(join(ROOT, 'server/apple/AppleRootCA-G3.pem'), 'utf8');
}

/**
 * 读库里的根证书并检查它没被换掉：SHA-256 必须等于 [APPLE_ROOT_SHA256]。
 * 返回 PEM 字符串；对不上就 throw（宁可计费端点起不来，也不要拿一个来路不明的根验签）。
 */
export function loadVerifiedAppleRootPem() {
  const pem = loadAppleRootPem();
  const got = new X509Certificate(pem).fingerprint256;
  if (got.toUpperCase() !== APPLE_ROOT_SHA256) {
    throw new Error(`Apple 根证书指纹对不上：期望 ${APPLE_ROOT_SHA256}，实际 ${got}`);
  }
  return pem;
}

const b64url = (buf) => Buffer.from(buf).toString('base64url');

function decodePart(s) {
  try {
    return Buffer.from(String(s), 'base64url');
  } catch {
    return null;
  }
}

/**
 * 解析一个 compact JWS（不验签）。失败返回 null。
 * @returns {{header: object, payload: object, signingInput: Buffer, signature: Buffer}|null}
 */
export function decodeJws(jws) {
  if (typeof jws !== 'string' || jws.length > 64 * 1024) return null;
  const parts = jws.trim().split('.');
  if (parts.length !== 3) return null;
  const header = decodePart(parts[0]);
  const payload = decodePart(parts[1]);
  const signature = decodePart(parts[2]);
  if (!header || !payload || !signature) return null;
  let h;
  let p;
  try {
    h = JSON.parse(header.toString('utf8'));
    p = JSON.parse(payload.toString('utf8'));
  } catch {
    return null;
  }
  if (!h || typeof h !== 'object' || !p || typeof p !== 'object') return null;
  return {
    header: h,
    payload: p,
    signingInput: Buffer.from(`${parts[0]}.${parts[1]}`),
    signature,
  };
}

const fail = (code, message) => ({ ok: false, code, message });

/**
 * 验证 Apple 的 signedTransaction / signedPayload（compact JWS）。
 *
 * 判据（一条不能少）：
 *   * header.alg === 'ES256'，header.x5c 是 3 张证书（叶子 / 中间 / 根）；
 *   * 叶子 ← 中间 ← 根 的签名链成立（`X509Certificate.verify`）；
 *   * 根证书 **逐字节等于** 传入的受信根（生产 = 入库的 Apple Root CA - G3）；
 *   * 三张证书都在有效期内（用 `nowMs`，自检可拨）；
 *   * JWS 签名用叶子的公钥按 ES256（`ieee-p1363`）验过。
 *
 * @param {string} jws
 * @param {{rootPem?: string, nowMs?: number}} [opts]
 */
export function verifyAppleJws(jws, { rootPem = loadVerifiedAppleRootPem(), nowMs = Date.now() } = {}) {
  const decoded = decodeJws(jws);
  if (!decoded) return fail('invalid_jws', 'JWS 结构不对（空 / 段数不是 3 / 不是合法 base64url JSON）');
  const { header, payload, signingInput, signature } = decoded;
  if (header.alg !== 'ES256') return fail('wrong_alg', 'JWS 的 alg 不是 ES256');
  if (!Array.isArray(header.x5c) || header.x5c.length !== 3) {
    return fail('bad_x5c', 'JWS 的 x5c 必须是 3 张证书（叶子 / 中间 / 根）');
  }

  let certs;
  try {
    certs = header.x5c.map((b64) => new X509Certificate(Buffer.from(String(b64), 'base64')));
  } catch {
    return fail('bad_x5c', 'x5c 里的证书解析不出来');
  }
  const [leaf, intermediate, root] = certs;

  // 有效期（生产给真实时钟；自检给夹具时间）
  for (const [label, cert] of [['叶子', leaf], ['中间', intermediate], ['根', root]]) {
    const from = Date.parse(cert.validFrom);
    const to = Date.parse(cert.validTo);
    if (!Number.isFinite(from) || !Number.isFinite(to)) return fail('bad_x5c', `${label}证书有效期解析不出来`);
    if (nowMs < from || nowMs > to) return fail('cert_expired', `${label}证书不在有效期内`);
  }

  // 证书链 + 根钉死（der 字节比较：等价于"就是我们信任的那张根"）
  if (!leaf.ca) {
    try {
      if (!leaf.verify(intermediate.publicKey)) return fail('bad_chain', '叶子证书不是中间证书签的');
      if (!intermediate.verify(root.publicKey)) return fail('bad_chain', '中间证书不是根证书签的');
    } catch {
      return fail('bad_chain', '证书链验签失败');
    }
  } else {
    return fail('bad_chain', '叶子证书不能是 CA');
  }
  if (!intermediate.ca || !root.ca) return fail('bad_chain', '证书链里的 CA 标记不对');
  let pinned;
  try {
    pinned = new X509Certificate(rootPem);
  } catch {
    return fail('untrusted_chain', '受信根证书解析失败');
  }
  if (!Buffer.from(root.raw).equals(Buffer.from(pinned.raw))) {
    return fail('untrusted_chain', '根证书不是受信的那一张（x5c 被换掉了？）');
  }

  // JWS 签名（ES256 原始 R||S 用 ieee-p1363）
  let sigOk = false;
  try {
    sigOk = verify('sha256', signingInput, { key: leaf.publicKey, dsaEncoding: 'ieee-p1363' }, signature);
  } catch {
    sigOk = false;
  }
  if (!sigOk) return fail('invalid_signature', 'JWS 签名验证失败（内容被改过？）');

  return { ok: true, header, payload, certs };
}

/**
 * 从 Apple 交易 JWS 的 payload 里取我们需要的 claims 并校验。
 *
 * 这些字段都是 **JWS 自带的**（方案 §五：核心验签不依赖 App Store Server API）。
 * 校验：bundleId 必须是我们；productId 必须是三个之一；transactionId 必须非空；
 * environment 只接受 Sandbox / Production；订阅必须有合法的 expiresDate，
 * 终身（非消耗型）可以没有。
 */
export function transactionClaims(payload, { bundleId = BUNDLE_ID } = {}) {
  if (!payload || typeof payload !== 'object') return fail('bad_claims', 'JWS payload 不是对象');
  if (payload.bundleId !== bundleId) return fail('wrong_bundle', '这笔交易不属于本 App（bundleId 不匹配）');
  const productId = payload.productId;
  if (typeof productId !== 'string' || !PRODUCT_SET.has(productId)) {
    return fail('wrong_product', '商品 ID 不在 Ultra 三档里');
  }
  const transactionId = payload.transactionId;
  if (typeof transactionId !== 'string' || transactionId.length === 0) {
    return fail('missing_transaction', '交易缺少 transactionId');
  }
  const environment = payload.environment;
  if (environment !== 'Sandbox' && environment !== 'Production') {
    return fail('bad_environment', `不认识的 environment：${String(environment)}`);
  }
  const originalTransactionId =
    typeof payload.originalTransactionId === 'string' && payload.originalTransactionId.length > 0
      ? payload.originalTransactionId
      : transactionId;
  const expiresRaw = payload.expiresDate;
  let expiresAt = null;
  if (expiresRaw !== undefined && expiresRaw !== null) {
    const n = typeof expiresRaw === 'string' ? Number(expiresRaw) : expiresRaw;
    if (!Number.isFinite(n) || n <= 0) return fail('bad_expiry', 'expiresDate 不是合法毫秒时间戳');
    expiresAt = Number(n);
  } else if (productId !== PRODUCT_IDS.lifetime) {
    return fail('missing_expiry', '订阅交易缺少 expiresDate');
  }
  return {
    ok: true,
    claims: {
      bundleId,
      productId,
      transactionId,
      originalTxn: originalTransactionId,
      expiresAt,
      environment,
    },
  };
}

/** 对外的权益 JSON（**不含任何账号标识**；客户端按自己的 account 请求）。 */
export function serializeEntitlement(current) {
  if (!current || !current.row) return { status: current?.status ?? 'none', entitlement: null };
  const r = current.row;
  return {
    status: current.status,
    entitlement: {
      product: r.product,
      source: r.source,
      environment: r.environment,
      expires_at: r.expires_at,
      revoked_at: r.revoked_at,
      refunded_at: r.refunded_at,
      updated_at: r.updated_at,
    },
  };
}

const sha256Hex = (s) => createHash('sha256').update(s, 'utf8').digest('hex');

/** 请求来源（只用于限速；**不记录**、不打印）。Caddy 会带 X-Forwarded-For。 */
function requestSource(req) {
  const xff = req.headers['x-forwarded-for'];
  if (typeof xff === 'string' && xff.trim() !== '') return xff.split(',')[0].trim();
  return req.socket?.remoteAddress ?? 'unknown';
}

/**
 * 建计费协议层。
 *
 * @param {{
 *   store: ReturnType<import('./billing-store.mjs').createBillingStore>,
 *   log?: (m: string) => void,
 *   now?: () => number,
 *   rootPem?: string,
 *   bundleId?: string,
 *   limits?: object,
 * }} opts
 */
export function createBilling({
  store,
  log = () => {},
  now = () => Date.now(),
  rootPem = loadVerifiedAppleRootPem(),
  bundleId = BUNDLE_ID,
  allowSandboxTransactions = false,
  limits = {},
} = {}) {
  if (!store) throw new Error('createBilling 需要 store（billing-store）');
  const L = { ...DEFAULT_LIMITS, ...limits };
  const nowMs = () => Number(now());

  const jsonError = (res, json, status, code, message, headers = {}) =>
    json(res, status, { error: message, code }, headers);

  /** 交易落库（verify 与续订通知共用）。 */
  function applyAppleTransaction(accountId, claims) {
    return store.applyStoreTransaction({
      accountId,
      product: claims.productId,
      source: 'apple',
      originalTxn: claims.originalTxn,
      expiresAt: claims.expiresAt,
      environment: claims.environment,
      transactionId: claims.transactionId,
      atMs: nowMs(),
    });
  }

  /** Apple V2 通知：处理一条 payload，返回 `{ok, code?, duplicate?}`。 */
  function processAppleNotification(payload) {
    if (!payload || typeof payload !== 'object') return fail('bad_payload', '通知 payload 不是对象');
    if (payload.bundleId !== bundleId) {
      return fail('wrong_bundle', '这条通知不属于本 App（bundleId 不匹配）');
    }
    const uuid = payload.notificationUUID;
    if (typeof uuid !== 'string' || uuid.length === 0) return fail('bad_payload', '通知缺少 notificationUUID');
    if (store.hasEvent('notification', uuid)) return { ok: true, duplicate: true };

    const type = String(payload.notificationType ?? '');
    const nested = payload.data?.signedTransactionInfo;
    let claims = null;
    if (typeof nested === 'string' && nested.length > 0) {
      const v = verifyAppleJws(nested, { rootPem, nowMs: nowMs() });
      if (!v.ok) return v;
      const c = transactionClaims(v.payload, { bundleId });
      if (!c.ok) return c;
      claims = c.claims;
    }

    // ---- 沙盒交易默认不换真权益 ----
    // Apple 的沙盒通知**照常回 200**（否则它会一直重试），但**不写权益**，只留一条事件。
    const env = claims?.environment ?? payload.environment;
    if (env === 'Sandbox' && !allowSandboxTransactions) {
      store.recordEvent('sandbox_ignored', `${type || 'UNKNOWN'}|${uuid}`, nowMs());
      store.recordEvent('notification', uuid, nowMs());
      log(`账单通知：${type || 'UNKNOWN'}（沙盒，已忽略；要联调请开 LIANLEME_ALLOW_SANDBOX=1）`);
      return { ok: true, ignored: true };
    }

    switch (type) {
      case 'DID_RENEW':
      case 'SUBSCRIBED':
      case 'OFFER_REDEEMED': {
        if (!claims) return fail('bad_payload', '续订通知里没有可用的 signedTransactionInfo');
        const rows = store.findByOriginal(claims.originalTxn);
        if (rows.length === 0) {
          // 通知比客户端 verify 先到：记下来，verify 落库时把更晚的到期算进去。
          store.recordEvent('renew_pending', `${claims.originalTxn}|${claims.expiresAt ?? ''}`, nowMs());
        } else {
          for (const row of rows) applyAppleTransaction(row.account_id, claims);
        }
        break;
      }
      case 'EXPIRED':
      case 'GRACE_PERIOD_EXPIRED': {
        if (!claims) return fail('bad_payload', '到期通知里没有可用的 signedTransactionInfo');
        store.markExpired({ originalTxn: claims.originalTxn, expiresAt: claims.expiresAt, atMs: nowMs() });
        break;
      }
      case 'REFUND':
      case 'REVOKE': {
        if (!claims) return fail('bad_payload', '退款/撤销通知里没有可用的 signedTransactionInfo');
        store.markTerminal({
          originalTxn: claims.originalTxn,
          kind: type === 'REFUND' ? 'refunded' : 'revoked',
          atMs: nowMs(),
        });
        break;
      }
      default:
        // DID_CHANGE_RENEWAL_STATUS / DID_FAIL_TO_RENEW / PRICE_INCREASE / TEST…：
        // 不影响本机权益判定（到期时间与终态由上面几类负责），记事件即可。
        break;
    }
    store.recordEvent('notification', uuid, nowMs());
    log(`账单通知：${type || 'UNKNOWN'}（已处理）`);
    return { ok: true, type };
  }

  /** 兑换码限速：返回 `{retryAfterSec}` 或 null。 */
  function redeemLimited(accountId, ipHash) {
    const at = nowMs();
    const window = L.redeemAttemptWindowMs;
    const ipCount = store.countEvents('redeem_attempt_ip', ipHash, at - window);
    if (ipCount >= L.redeemPerIpPerHour) {
      return { retryAfterSec: Math.max(1, Math.ceil((store.firstEventAt('redeem_attempt_ip', ipHash, at - window) + window - at) / 1000)) };
    }
    const accCount = store.countEvents('redeem_attempt_account', accountId, at - window);
    if (accCount >= L.redeemPerAccountPerHour) {
      return { retryAfterSec: Math.max(1, Math.ceil((store.firstEventAt('redeem_attempt_account', accountId, at - window) + window - at) / 1000)) };
    }
    // 连续失败锁：只看"上一次成功之后"的失败（成功一次就从头算）。
    const failWindowStart = at - L.redeemFailWindowMs;
    const lastSuccess = store.lastEventAt('redeem_success', accountId);
    const since = lastSuccess === null ? failWindowStart : Math.max(failWindowStart, lastSuccess + 1);
    const fails = store.countEvents('redeem_fail', accountId, since);
    if (fails >= L.redeemFailLock) {
      const first = store.firstEventAt('redeem_fail', accountId, since) ?? at;
      return { retryAfterSec: Math.max(1, Math.ceil((first + L.redeemFailWindowMs - at) / 1000)) };
    }
    return null;
  }

  /** 记一次失败的兑换（用于"连续失败锁"与审计）。 */
  function recordRedeemFail(accountId, reason) {
    store.recordEvent('redeem_fail', accountId, nowMs());
    store.recordEvent('redeem_audit', `${accountId}|fail|${reason}`, nowMs());
  }

  /**
   * 处理 `/v1/billing/*` 里**需要登录**的三个端点。
   * @returns {Promise<boolean>} true = 这个请求我接了
   */
  async function tryHandle({ req, res, p, accountId, authVia, say, json, readBody }) {
    if (!String(p).startsWith('/v1/billing/')) return false;
    if (p === '/v1/billing/notifications/apple') {
      // 通知端点必须在鉴权闸门**之前**处理（见 backend.mjs）；走到这里说明配置错了。
      say(404);
      jsonError(res, json, 404, 'not_here', '通知端点不走这条鉴权路径');
      return true;
    }
    const authed = typeof accountId === 'string' && accountId.length > 0 && authVia === 'token';
    if (!authed) {
      say(401);
      jsonError(res, json, 401, 'login_required', '这个接口需要登录（会话令牌，不是设备凭据）');
      return true;
    }

    if (p === '/v1/billing/entitlement') {
      if (req.method !== 'GET') { say(405); jsonError(res, json, 405, 'method_not_allowed', '只支持 GET'); return true; }
      const current = store.currentFor(accountId, nowMs());
      say(200);
      json(res, 200, serializeEntitlement(current));
      return true;
    }

    if (p === '/v1/billing/verify') {
      if (req.method !== 'POST') { say(405); jsonError(res, json, 405, 'method_not_allowed', '只支持 POST'); return true; }
      const { body, tooLarge } = await readBody(req, L.bodyLimitBytes);
      if (tooLarge) { say(413); jsonError(res, json, 413, 'too_large', '请求体太大'); return true; }
      let payload;
      try { payload = JSON.parse(body?.toString('utf8') ?? ''); } catch { payload = null; }
      if (!payload || typeof payload.signedTransaction !== 'string' || payload.signedTransaction.length === 0) {
        say(400);
        jsonError(res, json, 400, 'bad_request', '需要 {"signedTransaction":"<Apple JWS>"}');
        return true;
      }
      const v = verifyAppleJws(payload.signedTransaction, { rootPem, nowMs: nowMs() });
      if (!v.ok) {
        say(400);
        jsonError(res, json, 400, v.code, v.message);
        return true;
      }
      const c = transactionClaims(v.payload, { bundleId });
      if (!c.ok) {
        say(400);
        jsonError(res, json, 400, c.code, c.message);
        return true;
      }
      if (c.claims.environment === 'Sandbox' && !allowSandboxTransactions) {
        say(400);
        jsonError(res, json, 400, 'sandbox_not_allowed',
          '沙盒交易不能兑换正式权益（服务端默认拒绝；联调请显式开 LIANLEME_ALLOW_SANDBOX=1）');
        return true;
      }
      const applied = applyAppleTransaction(accountId, c.claims);
      log(`账单：verify ${c.claims.productId}（replay=${applied.replayed}）`);
      say(200);
      json(res, 200, {
        ok: true,
        replayed: applied.replayed,
        ...serializeEntitlement(store.currentFor(accountId, nowMs())),
      });
      return true;
    }

    if (p === '/v1/billing/redeem') {
      if (req.method !== 'POST') { say(405); jsonError(res, json, 405, 'method_not_allowed', '只支持 POST'); return true; }
      const ipHash = sha256Hex(requestSource(req)).slice(0, 16);
      const limited = redeemLimited(accountId, ipHash);
      if (limited) {
        say(429);
        jsonError(res, json, 429, 'rate_limited', '尝试太频繁，请稍后再试',
          { 'retry-after': String(limited.retryAfterSec) });
        return true;
      }
      // 先记"尝试"（猜码也会打服务器，正是限速要拦的）；失败再记 redeem_fail。
      store.recordEvent('redeem_attempt_ip', ipHash, nowMs());
      store.recordEvent('redeem_attempt_account', accountId, nowMs());

      const { body, tooLarge } = await readBody(req, L.bodyLimitBytes);
      if (tooLarge) { say(413); jsonError(res, json, 413, 'too_large', '请求体太大'); return true; }
      let payload;
      try { payload = JSON.parse(body?.toString('utf8') ?? ''); } catch { payload = null; }
      const normalized = normalizeRedeemCode(payload?.code);
      if (!normalized || !isValidRedeemCode(normalized)) {
        recordRedeemFail(accountId, 'invalid_format');
        say(400);
        jsonError(res, json, 400, 'invalid_code', '兑换码格式不对（抄错一位就会校验失败）');
        return true;
      }
      const r = store.redeemCode({ codeHash: hashRedeemCode(normalized), accountId, atMs: nowMs() });
      if (!r.ok) {
        recordRedeemFail(accountId, r.reason);
        if (r.reason === 'missing') {
          say(404); jsonError(res, json, 404, 'not_found', '兑换码不存在');
        } else if (r.reason === 'used') {
          say(409); jsonError(res, json, 409, 'used', '这个兑换码已经被使用过了（一次性）');
        } else {
          say(410); jsonError(res, json, 410, 'expired', '兑换码已经过期');
        }
        return true;
      }
      const at = nowMs();
      const expiresAt = r.days === null ? null : at + Number(r.days) * 24 * 60 * 60 * 1000;
      store.applyStoreTransaction({
        accountId,
        product: REDEEM_PRODUCT,
        source: 'redeem',
        originalTxn: `redeem:${hashRedeemCode(normalized).slice(0, 24)}`,
        expiresAt,
        transactionId: null,
        atMs: at,
      });
      store.recordEvent('redeem_success', accountId, at);
      store.recordEvent('redeem_audit', `${accountId}|ok|${r.kind}`, at);
      store.prune();
      log(`兑换码：核销成功（${r.kind}）`);
      say(200);
      json(res, 200, {
        ok: true,
        kind: r.kind,
        days: r.days,
        ...serializeEntitlement(store.currentFor(accountId, nowMs())),
      });
      return true;
    }

    say(404);
    jsonError(res, json, 404, 'not_found', '没有这个计费接口');
    return true;
  }

  /**
   * Apple App Store Server Notifications V2 接收端（**无鉴权**，靠 signedPayload JWS）。
   * 必须快速回 200：Apple 会重试，重复投递由 notificationUUID 去重。
   */
  async function handleAppleNotification({ req, res, readBody, say = () => {}, json }) {
    if (req.method !== 'POST') {
      say(405);
      jsonError(res, json, 405, 'method_not_allowed', '只支持 POST');
      return;
    }
    const { body, tooLarge } = await readBody(req, L.bodyLimitBytes);
    if (tooLarge) { say(413); jsonError(res, json, 413, 'too_large', '请求体太大'); return; }
    let payload;
    try { payload = JSON.parse(body?.toString('utf8') ?? ''); } catch { payload = null; }
    if (!payload || typeof payload.signedPayload !== 'string' || payload.signedPayload.length === 0) {
      say(400);
      jsonError(res, json, 400, 'bad_request', '需要 {"signedPayload":"<Apple V2 JWS>"}');
      return;
    }
    const v = verifyAppleJws(payload.signedPayload, { rootPem, nowMs: nowMs() });
    if (!v.ok) {
      say(400);
      jsonError(res, json, 400, v.code, v.message);
      return;
    }
    const r = processAppleNotification(v.payload);
    if (!r.ok) {
      say(400);
      jsonError(res, json, 400, r.code, r.message);
      return;
    }
    // **永远回 200**（哪怕是重放/未知类型）：Apple 收到非 2xx 会一直重试。
    say(200);
    json(res, 200, { ok: true, duplicate: r.duplicate === true, ignored: r.ignored === true });
  }

  return {
    tryHandle,
    handleAppleNotification,
    store,
    allowSandboxTransactions,
    _internals: {
      verifyAppleJws,
      transactionClaims,
      processAppleNotification,
      requestSource,
      normalizeRedeemCode,
      hashRedeemCode,
    },
  };
}
