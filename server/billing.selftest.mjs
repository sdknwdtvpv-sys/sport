#!/usr/bin/env node
/**
 * 练了么 · 计费协议层自检（M3：Apple 验签 / V2 通知 / 权益下发 / 自建兑换码）
 *
 * 设计：`docs/plan-membership-2026-10-10.md` §九 判据 9 / 10。**不依赖真 Apple、不联网**：
 *
 *   * 用 `openssl` 现造一套测试 CA（根 / 中间 / 叶子），再用 `node:crypto` 的 ES256
 *     签出各种 JWS 夹具；生产代码验的就是同一条代码路径（只把"受信根"换成测试根）；
 *   * 覆盖"故意改坏就红"：改一位签名、换根、错 bundleId、错商品、缺 expiresDate、
 *     重放、退款/撤销、EXPIRE、通知重放、并发同码、三类限速、未登录、通知无鉴权；
 *   * 服务端**日志不漏凭据**：明文码 / 令牌 / JWS 一个都不许出现。
 *
 * 为什么测试证书不用纯 `node:crypto` 造：Node 没有 X.509 **签发** API（只有解析/校验）；
 * 所以证书用 `openssl` 生成，**JWS 本身**仍由 `node:crypto` 现签（这也是生产用的同一套）。
 *
 * 退出码：0 全过 / 1 有失败。
 */

import { execFileSync } from 'node:child_process';
import { X509Certificate, createHash, sign } from 'node:crypto';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { createAuth } from './auth.mjs';
import { createAuthStore } from './auth-store.mjs';
import { createBackend } from './backend.mjs';
import { createSqliteStore } from './backend-store.mjs';
import {
  APPLE_ROOT_SHA256,
  BUNDLE_ID,
  PRODUCT_IDS,
  createBilling,
  loadVerifiedAppleRootPem,
  verifyAppleJws,
} from './billing.mjs';
import { createBillingStore } from './billing-store.mjs';
import { createFileMailer } from './mailer.mjs';
import {
  checkChar,
  formatRedeemCode,
  generateRedeemCode,
  hashRedeemCode,
  isValidRedeemCode,
  normalizeRedeemCode,
} from './redeem-admin.mjs';

const sha256hex = (s) => createHash('sha256').update(s, 'utf8').digest('hex');
const b64url = (s) => Buffer.from(s).toString('base64url');

function sh(cmd, args, cwd) {
  return execFileSync(cmd, args, { cwd, stdio: ['ignore', 'pipe', 'pipe'] });
}

/** 用 openssl 造一套测试证书链（根 / 中间 / 叶子），返回 PEM 与 x5c（base64 DER）。 */
function makeTestChain(dir, name) {
  const sub = (cn) => `-subj`;
  sh('openssl', ['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', 'root.key'], dir);
  // ⚠️ 不用 `req -x509`：LibreSSL 那条路生成出来**没有 basicConstraints**（Node 读 ca=false），
  // 而我们的验签要求根/中间是 CA。所以先造 CSR，再用 x509 -req 自签并显式加扩展。
  sh('openssl', ['req', '-new', '-key', 'root.key', sub(), `/CN=${name} Test Root`, '-out', 'root.csr'], dir);
  writeFileSync(join(dir, 'root.ext'), 'basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n');
  sh('openssl', ['x509', '-req', '-in', 'root.csr', '-signkey', 'root.key', '-days', '3650',
    '-sha256', '-extfile', 'root.ext', '-out', 'root.pem'], dir);
  sh('openssl', ['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', 'int.key'], dir);
  sh('openssl', ['req', '-new', '-key', 'int.key', sub(), `/CN=${name} Test Intermediate`, '-out', 'int.csr'], dir);
  writeFileSync(join(dir, 'int.ext'), 'basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n');
  sh('openssl', ['x509', '-req', '-in', 'int.csr', '-CA', 'root.pem', '-CAkey', 'root.key',
    '-CAcreateserial', '-days', '3650', '-sha256', '-extfile', 'int.ext', '-out', 'int.pem'], dir);
  sh('openssl', ['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', 'leaf.key'], dir);
  sh('openssl', ['req', '-new', '-key', 'leaf.key', sub(), `/CN=${name} Test Leaf`, '-out', 'leaf.csr'], dir);
  writeFileSync(join(dir, 'leaf.ext'), 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\n');
  sh('openssl', ['x509', '-req', '-in', 'leaf.csr', '-CA', 'int.pem', '-CAkey', 'int.key',
    '-CAcreateserial', '-days', '3650', '-sha256', '-extfile', 'leaf.ext', '-out', 'leaf.pem'], dir);

  const der = (file) => sh('openssl', ['x509', '-in', file, '-outform', 'DER'], dir);
  return {
    rootPem: readFileSync(join(dir, 'root.pem'), 'utf8'),
    leafKeyPem: readFileSync(join(dir, 'leaf.key'), 'utf8'),
    x5c: [der('leaf.pem'), der('int.pem'), der('root.pem')].map((b) => Buffer.from(b).toString('base64')),
  };
}

function signJws(payload, signer) {
  const header = { alg: 'ES256', x5c: signer.x5c };
  const input = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
  const sig = sign('sha256', Buffer.from(input), { key: signer.leafKeyPem, dsaEncoding: 'ieee-p1363' });
  return `${input}.${sig.toString('base64url')}`;
}

function transaction(over = {}) {
  return {
    bundleId: BUNDLE_ID,
    productId: PRODUCT_IDS.monthly,
    transactionId: 'tx_1',
    originalTransactionId: 'otx_1',
    expiresDate: 0,
    environment: 'Sandbox',
    ...over,
  };
}

export async function selftest() {
  const dir = mkdtempSync(join(tmpdir(), 'lianleme-billing-'));
  const failures = [];
  const check = (name, ok, detail = '') => {
    if (!ok) failures.push(name);
    console.log(`  ${ok ? '✓' : '✗'} ${name}${ok || !detail ? '' : ` —— ${detail}`}`);
  };

  // ── 夹具：受信链 / 冒充根（每条链一套 key 与证书，`openssl` 生成）─────
  let trusted;
  let rogue;
  try {
    mkdirSync(join(dir, 'trusted'), { recursive: true });
    mkdirSync(join(dir, 'rogue'), { recursive: true });
    trusted = makeTestChain(join(dir, 'trusted'), 'Trusted');
    rogue = makeTestChain(join(dir, 'rogue'), 'Rogue');
  } catch (e) {
    console.error(`✗ 需要 openssl 生成测试证书：${e?.message ?? e}`);
    rmSync(dir, { recursive: true, force: true });
    return 1;
  }

  const clockStart = Date.now();
  let clock = clockStart;
  const day = 24 * 60 * 60 * 1000;

  const store = createBillingStore({ path: join(dir, 'billing.sqlite'), now: () => clock });
  const backendStore = createSqliteStore({ path: join(dir, 'backend.sqlite') });
  const authStore = createAuthStore({ path: join(dir, 'auth.sqlite'), now: () => clock });
  const logged = [];
  const auth = createAuth({
    store: authStore,
    backendStore,
    mailer: createFileMailer({ path: join(dir, 'mail.ndjson') }),
    secret: 'billing-selftest-secret',
    now: () => clock,
  });
  const billing = createBilling({
    store,
    now: () => clock,
    rootPem: trusted.rootPem,
    log: (m) => logged.push(m),
    // 主服务把限速放宽到"测不到"：限速另有专门的实例测。
    limits: { redeemPerIpPerHour: 1000, redeemPerAccountPerHour: 1000, redeemFailLock: 1000 },
    // 主服务是"联调配置"：现有夹具全是 Sandbox 交易，所以这里显式允许；
    // **默认拒绝**的行为在 §8b 用独立实例测。
    allowSandboxTransactions: true,
  });
  const { server } = createBackend({ store: backendStore, auth, billing, log: (m) => logged.push(m) });

  // 账号 / 令牌（不走邮件注册：直接把绑定与令牌塞进 auth store，自检不测邮件）
  function makeAccount(name) {
    const accountId = sha256hex(`account:${name}`);
    const token = `lm1_${sha256hex(`token:${name}`)}`;
    backendStore.createAccount(accountId);
    authStore.bindAccount({
      accountId,
      email: `${name}@example.com`,
      salt: '00'.repeat(16),
      kdf: '{}',
      verifier: 'v'.repeat(40),
      wrapped: 'W'.repeat(16),
    });
    authStore.createToken({ tokenHash: sha256hex(token), accountId, deviceId: `dev_${name}` });
    return { accountId, token, headers: { authorization: `Bearer ${token}` } };
  }
  const A = makeAccount('a');
  const B = makeAccount('b');

  let base = null;
  const post = (path, payload, headers = {}) => fetch(`${base}${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: JSON.stringify(payload ?? {}),
  });
  const get = (path, headers = {}) => fetch(`${base}${path}`, { headers });
  const notif = (payload) => post('/v1/billing/notifications/apple', { signedPayload: payload });

  try {
    await new Promise((r) => server.listen(0, '127.0.0.1', r));
    base = `http://127.0.0.1:${server.address().port}`;

    // ── 0. 入库的 Apple 根证书：指纹必须与常量一致 ─────────────────────
    {
      const pem = loadVerifiedAppleRootPem();
      const fp = new X509Certificate(pem).fingerprint256;
      check('入库的 Apple 根证书指纹 = 代码里的常量', fp.toUpperCase() === APPLE_ROOT_SHA256, fp);
    }

    // ── 1. 验签正例 / 改一位 / 换根 / 错 alg ─────────────────────────────
    const tx1 = transaction({ expiresDate: clock + 30 * day, transactionId: 'tx_1', originalTransactionId: 'otx_1' });
    const jws1 = signJws(tx1, trusted);
    {
      const direct = verifyAppleJws(jws1, { rootPem: trusted.rootPem, nowMs: clock });
      check('验签正例：证书链 + ES256 都过', direct.ok === true, direct.code);

      const tamperedPayload = { ...tx1, transactionId: 'tx_hacked' };
      const input = jws1.split('.');
      const tampered = `${input[0]}.${b64url(JSON.stringify(tamperedPayload))}.${input[2]}`;
      const r = verifyAppleJws(tampered, { rootPem: trusted.rootPem, nowMs: clock });
      check('改一位（重编码 payload）→ invalid_signature', r.ok === false && r.code === 'invalid_signature', r.code);

      const rogueJws = signJws(tx1, rogue);
      const r2 = verifyAppleJws(rogueJws, { rootPem: trusted.rootPem, nowMs: clock });
      check('换一条根（冒充 CA 自签的链）→ untrusted_chain', r2.ok === false && r2.code === 'untrusted_chain', r2.code);

      const badAlg = (() => {
        const header = { alg: 'none', x5c: trusted.x5c };
        return `${b64url(JSON.stringify(header))}.${betterPayload(tx1)}.`;
      })();
      const r3 = verifyAppleJws(badAlg, { rootPem: trusted.rootPem, nowMs: clock });
      check('alg 不是 ES256 → wrong_alg', r3.ok === false && r3.code === 'wrong_alg', r3.code);

      const broken = jws1.slice(0, jws1.length - 4) + 'AAAA';
      const r4 = verifyAppleJws(broken, { rootPem: trusted.rootPem, nowMs: clock });
      check('签名被截断/改坏 → invalid_signature', r4.ok === false && r4.code === 'invalid_signature', r4.code);
    }

    // ── 2. 未登录 / 老设备凭据 都不许碰计费 ─────────────────────────────
    {
      const noAuth = await get('/v1/billing/entitlement');
      check('未登录 GET entitlement → 401', noAuth.status === 401, `实际 ${noAuth.status}`);
      const legacy = await get('/v1/billing/entitlement', { authorization: `Bearer ${A.accountId}` });
      check('老的 `Bearer <account_id>`（设备凭据）→ 401（计费只认会话令牌）',
        legacy.status === 401, `实际 ${legacy.status}`);
      const noAuthVerify = await post('/v1/billing/verify', { signedTransaction: jws1 });
      check('未登录 verify → 401', noAuthVerify.status === 401, `实际 ${noAuthVerify.status}`);
    }

    // ── 3. verify：写权益 / 错 bundle / 错商品 / 缺 expiresDate ─────────
    {
      const ok = await post('/v1/billing/verify', { signedTransaction: jws1 }, A.headers);
      const body = await ok.json();
      check('verify 正例 200 且权益 active', ok.status === 200 && body.status === 'active', JSON.stringify(body));
      check('verify 写下的到期时间 = JWS 里的 expiresDate',
        body.entitlement?.expires_at === tx1.expiresDate, JSON.stringify(body.entitlement));

      const wrongBundle = signJws(transaction({ bundleId: 'com.evil.app', expiresDate: clock + 30 * day }), trusted);
      const r1 = await post('/v1/billing/verify', { signedTransaction: wrongBundle }, A.headers);
      check('bundleId 不是我们 → 400 wrong_bundle', r1.status === 400 && (await r1.json()).code === 'wrong_bundle');

      const wrongProduct = signJws(transaction({ productId: 'com.other.thing', expiresDate: clock + 30 * day }), trusted);
      const r2 = await post('/v1/billing/verify', { signedTransaction: wrongProduct }, A.headers);
      check('商品不在 Ultra 三档 → 400 wrong_product', r2.status === 400 && (await r2.json()).code === 'wrong_product');

      const noExpiry = signJws(transaction({ productId: PRODUCT_IDS.monthly, expiresDate: undefined }), trusted);
      const r3 = await post('/v1/billing/verify', { signedTransaction: noExpiry }, A.headers);
      check('订阅缺 expiresDate → 400 missing_expiry', r3.status === 400 && (await r3.json()).code === 'missing_expiry');
    }

    // ── 4. 重放 / 只延长不缩短 ───────────────────────────────────────────
    {
      const replay = await post('/v1/billing/verify', { signedTransaction: jws1 }, A.headers);
      const rb = await replay.json();
      check('同一笔 transaction 重放 → 200 且 replayed=true', replay.status === 200 && rb.replayed === true, JSON.stringify(rb));
      const ent = await (await get('/v1/billing/entitlement', A.headers)).json();
      check('重放不重复延长（到期时间没变）', ent.entitlement?.expires_at === tx1.expiresDate, JSON.stringify(ent));

      const earlier = signJws(transaction({
        transactionId: 'tx_earlier', originalTransactionId: 'otx_1', expiresDate: clock + 10 * day,
      }), trusted);
      await post('/v1/billing/verify', { signedTransaction: earlier }, A.headers);
      const ent2 = await (await get('/v1/billing/entitlement', A.headers)).json();
      check('更早的到期时间不会把权益缩短', ent2.entitlement?.expires_at === tx1.expiresDate, JSON.stringify(ent2));
    }

    // ── 4b. 已过期的交易：如实报 expired（不是 active）───────────────────
    {
      const C = makeAccount('expired');
      const expiredJws = signJws(transaction({
        transactionId: 'tx_expired', originalTransactionId: 'otx_expired',
        expiresDate: clock - 1 * day,
      }), trusted);
      await post('/v1/billing/verify', { signedTransaction: expiredJws }, C.headers);
      const ent = await (await get('/v1/billing/entitlement', C.headers)).json();
      check('过期交易的权益 → status=expired（不会假装 active）', ent.status === 'expired', JSON.stringify(ent));
    }

    // ── 5. Apple V2 通知：验签 / 延长 / 重放 / 退款 / 撤销 / 到期 ────────
    const renewalTxn = transaction({
      transactionId: 'tx_renew_1', originalTransactionId: 'otx_1', expiresDate: clock + 60 * day,
    });
    const notify = (type, innerTxn, uuid) => signJws({
      notificationType: type,
      notificationUUID: uuid,
      bundleId: BUNDLE_ID,
      environment: 'Sandbox',
      signedDate: clock,
      data: { signedTransactionInfo: signJws(innerTxn, trusted) },
    }, trusted);
    {
      const renew = await notif(notify('DID_RENEW', renewalTxn, 'uuid-renew-1'));
      check('DID_RENEW 通知 200（无鉴权，靠 JWS）', renew.status === 200, `实际 ${renew.status}`);
      const ent = await (await get('/v1/billing/entitlement', A.headers)).json();
      check('DID_RENEW 把到期时间延长', ent.entitlement?.expires_at === clock + 60 * day, JSON.stringify(ent));

      const replay = await notif(notify('DID_RENEW', renewalTxn, 'uuid-renew-1'));
      const rb = await replay.json();
      check('同一 notificationUUID 重放 → 200 且 duplicate=true', replay.status === 200 && rb.duplicate === true, JSON.stringify(rb));
      const ent2 = await (await get('/v1/billing/entitlement', A.headers)).json();
      check('通知重放不重复延长', ent2.entitlement?.expires_at === clock + 60 * day, JSON.stringify(ent2));

      const refundTx = transaction({ transactionId: 'tx_refund', originalTransactionId: 'otx_1', expiresDate: clock + 60 * day });
      const refund = await notif(notify('REFUND', refundTx, 'uuid-refund-1'));
      check('REFUND 通知 200', refund.status === 200, `实际 ${refund.status}`);
      const ent3 = await (await get('/v1/billing/entitlement', A.headers)).json();
      check('退款后权益立即失效（status=refunded，哪怕还没到期）', ent3.status === 'refunded', JSON.stringify(ent3));

      // 退款后的续订不能复活
      const afterRefund = signJws(transaction({
        transactionId: 'tx_after_refund', originalTransactionId: 'otx_1', expiresDate: clock + 90 * day,
      }), trusted);
      await post('/v1/billing/verify', { signedTransaction: afterRefund }, A.headers);
      const ent4 = await (await get('/v1/billing/entitlement', A.headers)).json();
      check('退款是终态：后续 verify 不会复活权益', ent4.status === 'refunded', JSON.stringify(ent4));

      // 撤销（另一个账号 / 另一条 original_txn）
      const revokePurchase = signJws(transaction({
        transactionId: 'tx_b_1', originalTransactionId: 'otx_b_1', expiresDate: clock + 30 * day,
      }), trusted);
      await post('/v1/billing/verify', { signedTransaction: revokePurchase }, B.headers);
      await notif(notify('REVOKE', transaction({
        transactionId: 'tx_b_1', originalTransactionId: 'otx_b_1', expiresDate: clock + 30 * day,
      }), 'uuid-revoke-1'));
      const ent5 = await (await get('/v1/billing/entitlement', B.headers)).json();
      check('REVOKE 通知 → 权益立即失效（status=revoked）', ent5.status === 'revoked', JSON.stringify(ent5));

      // EXPIRED 不许缩短仍在生效的权益
      await notif(notify('EXPIRED', transaction({
        transactionId: 'tx_renew_1', originalTransactionId: 'otx_1', expiresDate: clock + 1 * day,
      }), 'uuid-expire-1'));
      const ent6 = await (await get('/v1/billing/entitlement', A.headers)).json();
      check('EXPIRED 通知不会缩短仍在生效的权益（已退款账号仍如实 refunded）',
        ent6.status === 'refunded', JSON.stringify(ent6));

      // 一个从未见过的 original_txn 的 EXPIRED：行不存在也不崩
      const orphan = await notif(notify('EXPIRED', transaction({
        transactionId: 'tx_orphan', originalTransactionId: 'otx_orphan', expiresDate: clock - 1,
      }), 'uuid-expire-orphan'));
      check('未知 original_txn 的到期通知也回 200（幂等、不崩）', orphan.status === 200, `实际 ${orphan.status}`);
    }

    // ── 6. 通知端点：坏 JWS / 坏 body ───────────────────────────────────
    {
      const bad = await post('/v1/billing/notifications/apple', { signedPayload: 'not-a-jws' });
      check('坏 JWS 的通知 → 400', bad.status === 400, `实际 ${bad.status}`);
      const empty = await post('/v1/billing/notifications/apple', {});
      check('没有 signedPayload → 400', empty.status === 400, `实际 ${empty.status}`);
    }

    // ── 7. 兑换码：正例 / 已用 / 不存在 / 过期 / 格式错 / 并发 ───────────
    let aRedeemedCode = null;
    const mkCode = () => {
      const plain = generateRedeemCode();
      const norm = normalizeRedeemCode(plain);
      return { plain, norm };
    };
    {
      const c = mkCode();
      store.insertCodes([{ codeHash: hashRedeemCode(c.norm), kind: 'year', days: 365, batch: 'selftest', expireAt: null }]);
      aRedeemedCode = c.plain;
      const r = await post('/v1/billing/redeem', { code: c.plain }, A.headers);
      const rb = await r.json();
      check('兑换码核销 200 且写权益', r.status === 200 && rb.ok === true && rb.days === 365, JSON.stringify(rb));
      const ent = await (await get('/v1/billing/entitlement', A.headers)).json();
      check('兑换后的权益 source=redeem / product=redeem',
        ent.entitlement?.source === 'redeem' && ent.entitlement?.product === 'redeem', JSON.stringify(ent));

      const again = await post('/v1/billing/redeem', { code: c.plain }, A.headers);
      check('同一个码再兑 → 409 used', again.status === 409, `实际 ${again.status}`);
      const byB = await post('/v1/billing/redeem', { code: c.plain }, B.headers);
      check('同一个码换账号兑 → 409 used（一次性绑定）', byB.status === 409, `实际 ${byB.status}`);

      const ghost = mkCode();
      const missing = await post('/v1/billing/redeem', { code: ghost.plain }, A.headers);
      check('格式合法但不存在的码 → 404', missing.status === 404, `实际 ${missing.status}`);

      const expired = mkCode();
      store.insertCodes([{
        codeHash: hashRedeemCode(expired.norm), kind: 'month', days: 30,
        batch: 'expired-batch', expireAt: clock - 1000,
      }]);
      const gone = await post('/v1/billing/redeem', { code: expired.plain }, A.headers);
      check('过期码 → 410', gone.status === 410, `实际 ${gone.status}`);

      const badShape = await post('/v1/billing/redeem', { code: 'LMU-AAAAA-AAAAA-AAAAA-AAAAA' }, A.headers);
      check('校验位不对的码 → 400', badShape.status === 400, `实际 ${badShape.status}`);

      // 并发同一码：10 个账号同时兑 → 只成功 1 个
      const concurrencyCode = mkCode();
      store.insertCodes([{ codeHash: hashRedeemCode(concurrencyCode.norm), kind: 'month', days: 30, batch: 'race', expireAt: null }]);
      const racers = Array.from({ length: 10 }, (_, i) => makeAccount(`race${i}`));
      const results = await Promise.all(racers.map((acc) =>
        post('/v1/billing/redeem', { code: concurrencyCode.plain }, acc.headers)));
      const okCount = results.filter((r) => r.status === 200).length;
      const usedCount = results.filter((r) => r.status === 409).length;
      check('并发同一码只成功 1 次（其余 409）', okCount === 1 && usedCount === 9, `200×${okCount} / 409×${usedCount}`);
    }

    // ── 8. 三类限速（独立实例，避免污染主库的计数）──────────────────────
    async function freshBilling(limits, { allowSandbox = false } = {}) {
      const d = mkdtempSync(join(tmpdir(), 'lianleme-billing-rl-'));
      const s = createBillingStore({ path: join(d, 'b.sqlite'), now: () => clock });
      const bStore = createSqliteStore({ path: join(d, 'backend.sqlite') });
      const aStore = createAuthStore({ path: join(d, 'auth.sqlite'), now: () => clock });
      const a = createAuth({
        store: aStore, backendStore: bStore,
        mailer: createFileMailer({ path: join(d, 'mail.ndjson') }),
        secret: 'rate-limit-secret', now: () => clock,
      });
      const b = createBilling({ store: s, now: () => clock, rootPem: trusted.rootPem, limits, allowSandboxTransactions: allowSandbox });
      const srv = createBackend({ store: bStore, auth: a, billing: b, log: () => {} }).server;
      await new Promise((r) => srv.listen(0, '127.0.0.1', r));
      const port = srv.address().port;
      const mk = (name) => {
        const accountId = sha256hex(`rl:${d}:${name}`);
        const token = `lm1_${sha256hex(`rl-token:${d}:${name}`)}`;
        bStore.createAccount(accountId);
        aStore.bindAccount({ accountId, email: `${name}-${port}@example.com`, salt: '00'.repeat(16), kdf: '{}', verifier: 'v'.repeat(40), wrapped: 'W' });
        aStore.createToken({ tokenHash: sha256hex(token), accountId, deviceId: 'dev' });
        return { token, headers: { authorization: `Bearer ${token}` } };
      };
      const rpost = (path, payload, headers) => fetch(`http://127.0.0.1:${port}${path}`, {
        method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(payload ?? {}),
      });
      const rget = (path, headers) => fetch(`http://127.0.0.1:${port}${path}`, { headers });
      return {
        srv, s, mk, rpost, rget, dir: d, billing: b,
        authStore: aStore, backendStore: bStore,
        base: `http://127.0.0.1:${port}`,
        dbPath: join(d, 'b.sqlite'),
      };
    }
    {
      // 每账号 2 次/小时
      const h = await freshBilling({ redeemPerAccountPerHour: 2, redeemPerIpPerHour: 1000, redeemFailLock: 1000 });
      const acc = h.mk('acc');
      const bad = 'LMU-AAAAA-AAAAA-AAAAA-AAAAA';
      const r1 = await h.rpost('/v1/billing/redeem', { code: bad }, acc.headers);
      const r2 = await h.rpost('/v1/billing/redeem', { code: bad }, acc.headers);
      const r3 = await h.rpost('/v1/billing/redeem', { code: bad }, acc.headers);
      check('每账号限速：前 2 次 400（码不对），第 3 次 429',
        r1.status === 400 && r2.status === 400 && r3.status === 429, `${r1.status}/${r2.status}/${r3.status}`);
      check('429 带 Retry-After', Number(r3.headers.get('retry-after')) >= 1, String(r3.headers.get('retry-after')));
      await new Promise((r) => h.srv.close(r));
    }
    {
      // 每 IP 2 次/小时（换账号也绕不过）
      const h = await freshBilling({ redeemPerIpPerHour: 2, redeemPerAccountPerHour: 1000, redeemFailLock: 1000 });
      const a1 = h.mk('ip1');
      const a2 = h.mk('ip2');
      const a3 = h.mk('ip3');
      const bad = 'LMU-AAAAA-AAAAA-AAAAA-AAAAA';
      const r1 = await h.rpost('/v1/billing/redeem', { code: bad }, a1.headers);
      const r2 = await h.rpost('/v1/billing/redeem', { code: bad }, a2.headers);
      const r3 = await h.rpost('/v1/billing/redeem', { code: bad }, a3.headers);
      check('每 IP 限速：换账号也绕不过（第 3 次 429）',
        r1.status === 400 && r2.status === 400 && r3.status === 429, `${r1.status}/${r2.status}/${r3.status}`);
      await new Promise((r) => h.srv.close(r));
    }
    {
      // 连续失败 2 次锁 1 小时：第 3 次即使给合法码也 429
      const h = await freshBilling({ redeemPerIpPerHour: 1000, redeemPerAccountPerHour: 1000, redeemFailLock: 2 });
      const acc = h.mk('lock');
      // 先塞一个合法码（能兑的话会成功；但被锁就不该成功）
      const plain = generateRedeemCode();
      const norm = normalizeRedeemCode(plain);
      h.s.insertCodes([{ codeHash: hashRedeemCode(norm), kind: 'month', days: 30, batch: 'lock', expireAt: null }]);
      const bad = 'LMU-AAAAA-AAAAA-AAAAA-AAAAA';
      const r1 = await h.rpost('/v1/billing/redeem', { code: bad }, acc.headers);
      const r2 = await h.rpost('/v1/billing/redeem', { code: bad }, acc.headers);
      const r3 = await h.rpost('/v1/billing/redeem', { code: plain }, acc.headers);
      check('连续失败锁：2 次失败后，合法码也被 429（锁 1 小时）',
        r1.status === 400 && r2.status === 400 && r3.status === 429, `${r1.status}/${r2.status}/${r3.status}`);
      check('锁定时带 Retry-After 且 ≤ 3600 秒', Number(r3.headers.get('retry-after')) >= 1
        && Number(r3.headers.get('retry-after')) <= 3600, String(r3.headers.get('retry-after')));
      await new Promise((r) => h.srv.close(r));
    }


    // ── 8b. 沙盒交易默认不能换真权益（安全口径）─────────────────────────
    {
      const high = { redeemPerIpPerHour: 1000, redeemPerAccountPerHour: 1000, redeemFailLock: 1000 };
      const note = (type, inner, uuid) => signJws({
        notificationType: type,
        notificationUUID: uuid,
        bundleId: BUNDLE_ID,
        environment: inner.environment,
        signedDate: clock,
        data: { signedTransactionInfo: signJws(inner, trusted) },
      }, trusted);

      // (a) 默认配置（allowSandboxTransactions 缺省 false）：沙盒 verify 被拒、不写权益
      const h = await freshBilling(high);
      const acc = h.mk('sb-default');
      const sbTxn = transaction({
        environment: 'Sandbox', transactionId: 'tx_sb_1', originalTransactionId: 'otx_sb_1',
        expiresDate: clock + 30 * day,
      });
      const r1 = await h.rpost('/v1/billing/verify', { signedTransaction: signJws(sbTxn, trusted) }, acc.headers);
      const b1 = await r1.json();
      check('默认配置：沙盒 verify → 400 sandbox_not_allowed',
        r1.status === 400 && b1.code === 'sandbox_not_allowed', `${r1.status} ${JSON.stringify(b1)}`);
      const e1 = await (await h.rget('/v1/billing/entitlement', acc.headers)).json();
      check('默认配置：沙盒 verify 不写权益', e1.status === 'none' && e1.entitlement === null, JSON.stringify(e1));

      // (b) 同一默认配置：生产 JWS 正常
      const prodTxn = transaction({
        environment: 'Production', transactionId: 'tx_pr_1', originalTransactionId: 'otx_pr_1',
        expiresDate: clock + 30 * day,
      });
      const r2 = await h.rpost('/v1/billing/verify', { signedTransaction: signJws(prodTxn, trusted) }, acc.headers);
      const b2 = await r2.json();
      check('默认配置：生产 JWS 正常写权益', r2.status === 200 && b2.status === 'active', JSON.stringify(b2));
      const e2 = await (await h.rget('/v1/billing/entitlement', acc.headers)).json();
      check('GET entitlement 如实带出 environment=Production',
        e2.entitlement?.environment === 'Production', JSON.stringify(e2));

      // (c) 明确打开 allowSandboxTransactions：沙盒正常写
      const h2 = await freshBilling(high, { allowSandbox: true });
      const acc2 = h2.mk('sb-allow');
      const r3 = await h2.rpost('/v1/billing/verify', { signedTransaction: signJws(sbTxn, trusted) }, acc2.headers);
      const b3 = await r3.json();
      check('allowSandboxTransactions=true：沙盒 verify 正常写权益',
        r3.status === 200 && b3.status === 'active', JSON.stringify(b3));
      const e3 = await (await h2.rget('/v1/billing/entitlement', acc2.headers)).json();
      check('沙盒权益的 environment 如实为 Sandbox',
        e3.entitlement?.environment === 'Sandbox', JSON.stringify(e3));

      // (d) 默认配置：沙盒通知回 200 但不写权益（只记 sandbox_ignored）
      const sbRefund = transaction({
        environment: 'Sandbox', transactionId: 'tx_sb_1', originalTransactionId: 'otx_pr_1',
        expiresDate: clock + 30 * day,
      });
      const r4 = await h.rpost('/v1/billing/notifications/apple', {
        signedPayload: note('REFUND', sbRefund, 'uuid-sb-refund'),
      });
      const b4 = await r4.json();
      check('默认配置：沙盒通知照常 200（Apple 不会重试）',
        r4.status === 200 && b4.ignored === true, JSON.stringify(b4));
      const e4 = await (await h.rget('/v1/billing/entitlement', acc.headers)).json();
      check('默认配置：沙盒通知不写权益（生产购买仍 active）', e4.status === 'active', JSON.stringify(e4));
      const raw = new DatabaseSync(h.dbPath);
      const ignored = raw.prepare("select count(*) as n from billing_events where kind='sandbox_ignored'").get().n;
      raw.close();
      check('默认配置：沙盒通知只留 sandbox_ignored 事件', Number(ignored) === 1, String(ignored));

      // (e) 生产通知在默认配置下正常生效（DID_RENEW 延长）
      const prodRenew = transaction({
        environment: 'Production', transactionId: 'tx_pr_2', originalTransactionId: 'otx_pr_1',
        expiresDate: clock + 60 * day,
      });
      await h.rpost('/v1/billing/notifications/apple', {
        signedPayload: note('DID_RENEW', prodRenew, 'uuid-pr-renew'),
      });
      const e5 = await (await h.rget('/v1/billing/entitlement', acc.headers)).json();
      check('默认配置：生产 DID_RENEW 正常延长',
        e5.entitlement?.expires_at === clock + 60 * day, JSON.stringify(e5));

      await new Promise((r) => h.srv.close(r));
      await new Promise((r) => h2.srv.close(r));
      rmSync(h.dir, { recursive: true, force: true });
      rmSync(h2.dir, { recursive: true, force: true });
    }

    // ── 9. 码形状 / 校验位 / 哈希 / 批次作废（纯函数 + store）───────────
    {
      const seen = new Set();
      let formatOk = true;
      for (let i = 0; i < 200; i += 1) {
        const c = generateRedeemCode();
        if (!/^LMU-[0-9A-HJKMNP-TV-Z]{5}-[0-9A-HJKMNP-TV-Z]{5}-[0-9A-HJKMNP-TV-Z]{5}-[0-9A-HJKMNP-TV-Z]{5}$/.test(c)) formatOk = false;
        const n = normalizeRedeemCode(c);
        if (!n || !isValidRedeemCode(n)) formatOk = false;
        seen.add(c);
      }
      check('200 个码形状正确、全部唯一、校验位自洽', formatOk && seen.size === 200, `${seen.size}/200`);
      const c = generateRedeemCode();
      const n = normalizeRedeemCode(c);
      check('大小写/空格/短横线都能规范化', normalizeRedeemCode(` ${c.toLowerCase().replace(/-/g, ' ')} `) === n);
      const body = n.slice(3);
      const tampered = n.slice(0, 3) + (body[0] === '0' ? '1' : '0') + n.slice(4);
      check('打错一位 → 校验位抓得住', isValidRedeemCode(tampered) === false);
      check('入库的是 SHA-256（64 hex）', /^[0-9a-f]{64}$/.test(hashRedeemCode(n)));
      check('校验位函数与生成一致', checkChar(body.slice(0, 19)) === body[19]);
      const bodyChars = formatRedeemCode(n).replace(/-/g, '').slice(3);
      check('Crockford 字符集里没有 I/L/O/U', !/[ILOU]/.test(bodyChars), formatRedeemCode(n));

      // 批次作废：未核销的删、已核销的留（权益是用户已经买到的）
      const c1 = mkCode();
      const c2 = mkCode();
      store.insertCodes([
        { codeHash: hashRedeemCode(c1.norm), kind: 'month', days: 30, batch: 'revoke-batch', expireAt: null },
        { codeHash: hashRedeemCode(c2.norm), kind: 'month', days: 30, batch: 'revoke-batch', expireAt: null },
      ]);
      await post('/v1/billing/redeem', { code: c1.plain }, A.headers);
      const removed = store.revokeUnused({ batch: 'revoke-batch' });
      const stats = store.batchStats('revoke-batch');
      check('作废批次：只删未核销的（1 条），已核销的留着', removed === 1 && stats.total === 1 && stats.used === 1,
        JSON.stringify({ removed, stats }));
    }


    // ── 11. 注销联动删除计费数据（合规：注销后不再保留购买记录）────────
    {
      const raw = new DatabaseSync(join(dir, 'billing.sqlite'));
      // 预置：属于 A 的几种事件（renew_pending / refund_pending / redeem_*）
      store.recordEvent('renew_pending', `otx_1|${clock + 120 * day}`, clock);
      store.recordEvent('refund_pending', 'otx_1', clock);
      store.recordEvent('redeem_fail', A.accountId, clock);
      store.recordEvent('redeem_audit', `${A.accountId}|ok|year`, clock);

      const n1 = (sql, ...args) => Number(raw.prepare(sql).get(...args).n);
      const beforeHealth = await (await fetch(`${base}/healthz`)).json();
      const aEnt = n1('select count(*) as n from entitlements where account_id = ?', A.accountId);
      const aEvents = n1('select count(*) as n from billing_events where key = ? or key like ?',
        A.accountId, `${A.accountId}|%`);
      const aTxnIds = raw.prepare("select key from billing_events where kind='txn_account' and key like ?")
        .all(`${A.accountId}|%`).map((r) => String(r.key).slice(A.accountId.length + 1));
      const inTxn = aTxnIds.length ? `key in (${aTxnIds.map(() => '?').join(',')})` : '1 = 0';
      const aTxnEvents = n1(`select count(*) as n from billing_events where kind='txn' and ${inTxn}`, ...aTxnIds);
      const bEnt = n1('select count(*) as n from entitlements where account_id = ?', B.accountId);
      const bEvents = n1('select count(*) as n from billing_events where key = ? or key like ?',
        B.accountId, `${B.accountId}|%`);
      const codeRows = n1('select count(*) as n from redeem_codes where used_by = ?', A.accountId);
      check('注销前：A 有权益/事件/已核销码，B 的数据也在',
        aEnt > 0 && aEvents > 0 && aTxnEvents > 0 && codeRows > 0 && bEnt > 0,
        JSON.stringify({ aEnt, aEvents, aTxnEvents, codeRows, bEnt }));

      const del = await fetch(`${base}/v1/account`, { method: 'DELETE', headers: A.headers });
      const delBody = await del.json();
      check('注销 200 且 deleted 计入计费删除行数',
        del.status === 200 && delBody.deleted >= aEnt, `${del.status} ${JSON.stringify(delBody)}`);

      check('注销后：A 的 entitlements = 0',
        n1('select count(*) as n from entitlements where account_id = ?', A.accountId) === 0);
      check('注销后：按 accountId 的 billing_events = 0',
        n1('select count(*) as n from billing_events where key = ? or key like ?',
          A.accountId, `${A.accountId}|%`) === 0);
      check('注销后：A 的 txn 事件 = 0（含更早的交易，不只 last_txn_id）',
        aTxnIds.length > 0 && n1(`select count(*) as n from billing_events where kind='txn' and ${inTxn}`, ...aTxnIds) === 0);
      check('注销后：renew_pending / refund_pending 事件 = 0',
        n1("select count(*) as n from billing_events where kind in ('renew_pending','refund_pending') "
          + "and (key = 'otx_1' or key like 'otx_1|%')") === 0);
      check('注销后：别的账号（B）的权益与事件一条不少',
        n1('select count(*) as n from entitlements where account_id = ?', B.accountId) === bEnt
        && n1('select count(*) as n from billing_events where key = ? or key like ?',
          B.accountId, `${B.accountId}|%`) === bEvents);

      const codeRow = raw.prepare('select used_by, used_at from redeem_codes where code_hash = ?')
        .get(hashRedeemCode(normalizeRedeemCode(aRedeemedCode)));
      check('注销后：已核销码 used_by 置空、used_at 保留（码仍算已用）',
        codeRow.used_by === null && codeRow.used_at !== null, JSON.stringify(codeRow));
      const reuse = await post('/v1/billing/redeem', { code: aRedeemedCode }, B.headers);
      check('注销后：把码给别人再兑仍 409（不能因注销变可复用）', reuse.status === 409, `实际 ${reuse.status}`);

      const afterHealth = await (await fetch(`${base}/healthz`)).json();
      check('/healthz 的 entitlements 计数跟着降（A 的权益行被删）',
        Number(afterHealth.entitlements) === Number(beforeHealth.entitlements) - aEnt,
        `${beforeHealth.entitlements} → ${afterHealth.entitlements}（A ${aEnt}）`);
      raw.close();
    }
    {
      // 计费删除失败 → 整体 500、账号保留可重试（不能报"已删"但其实没删干净）
      const h = await freshBilling(
        { redeemPerIpPerHour: 1000, redeemPerAccountPerHour: 1000, redeemFailLock: 1000 },
        { allowSandbox: true },
      );
      const acc = h.mk('del-fail');
      h.billing.store.close();   // 模拟计费库故障
      const del = await fetch(`${h.base}/v1/account`, { method: 'DELETE', headers: acc.headers });
      check('计费删除失败：注销整体 500（不报已删）', del.status === 500, `实际 ${del.status}`);
      const me = await fetch(`${h.base}/v1/account/me`, { headers: acc.headers });
      check('计费删除失败：账号还在（可重试）', me.status === 200, `实际 ${me.status}`);
      await new Promise((r) => h.srv.close(r));
      h.authStore.close();
      h.backendStore.close();
      rmSync(h.dir, { recursive: true, force: true });
    }

    // ── 10. 日志纪律：明文码 / 令牌 / JWS 不许出现 ─────────────────────
    {
      const joined = logged.join('\n');
      const lastCode = generateRedeemCode();
      check('日志里没有明文兑换码', !joined.includes('LMU-') && !joined.includes(lastCode));
      check('日志里没有会话令牌', !joined.includes(A.token) && !joined.includes('lm1_'));
      check('日志里没有 JWS 原文', !joined.includes(jws1) && !joined.includes(jws1.slice(0, 40)));
      check('日志里没有 Authorization 头', !/Authorization/i.test(joined));
    }
  } finally {
    await new Promise((r) => server.close(r));
    store.close();
    backendStore.close();
    authStore.close();
    rmSync(dir, { recursive: true, force: true });
  }

  if (failures.length) {
    console.error(`\n✗ 计费自检失败 ${failures.length} 项：`);
    for (const f of failures) console.error(`  · ${f}`);
    return 1;
  }
  console.log('✓ 计费自检通过（Apple JWS 验签 · V2 通知幂等/退款撤销 · 权益只延长 · '
    + '兑换码原子核销/限速 · 日志不漏凭据）');
  return 0;
}

function betterPayload(payload) {
  return b64url(JSON.stringify(payload));
}

if (process.argv[1] && process.argv[1].endsWith('billing.selftest.mjs')) {
  process.exit(await selftest());
}
