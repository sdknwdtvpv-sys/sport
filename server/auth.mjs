#!/usr/bin/env node
/**
 * 练了么 · 账号体系的**协议层**（邮箱 + 口令：注册 / 登录 / 会话 / 改口令 / 重置 / 注销）
 *
 * 设计见 `docs/plan-account-login.md`；这一份文件回答"请求怎么进来、怎么出去"。
 *
 * ## 一句话讲清它为什么长这样
 *
 * 口令**永远不来服务端**。客户端用口令 + 盐派生出两样东西：
 *
 *   * `verifier`——**认证凭据**（HKDF(info="lianleme/auth/v1")），只用来证明"我是这个人"；
 *   * KEK——**根本不发过来**，它用来把账号密钥包起来（`wrapped` 就是这么来的）。
 *
 * 服务端只保管：邮箱 → account_id 的映射、`verifier` 的 scrypt 结果、`wrapped`（密文）。
 * 于是"服务端读不到训练数据"这条底线**没有被账号体系破坏** —— 它拿到的两样东西
 * 一样推不出账号密钥（HKDF 单向、AEAD 解不开）。
 *
 * ## 三条纪律（与 backend.mjs 同源）
 *
 *   1. **日志里不出现邮箱明文、不出现验证码、不出现 Authorization**。邮箱只打指纹
 *      （`sha256(email)[:8]`），因为它是**可识别信息**，而日志是最容易漏出去的地方。
 *   2. **不按 IP 限流**。这台服务刻意不处理来源地址（`backend.mjs` 的第三条承诺）。
 *      发信限流改成"每邮箱 60 秒 1 条 / 24 小时 10 条 + 全局每日上限"。
 *   3. **不告诉外面"这个邮箱注册过没有"**：`/v1/auth/salt` 对不存在的邮箱回一个
 *      HMAC 算出来的**假盐**；`/v1/auth/login` 对不存在的邮箱与口令错**回同一句话**
 *      （并且照样做一次 scrypt，免得用耗时把答案漏出去）。
 *      唯一的例外是注册：邮箱被占用必须如实说（否则用户会一直卡在验证码那一步），
 *      所以 `/v1/auth/code` 对已注册邮箱**不发验证码、改发一封"你已经有账号"的邮件**。
 *
 * ## 与旧接口的关系（**不许弄坏**）
 *
 * `POST /v1/account`、`GET /v1/account/me`、`PUT|GET /v1/backup`、`DELETE /v1/account`
 * 全部**保持不变**，连鉴权都保持向后兼容：`Authorization: Bearer` 里
 * **先当会话令牌解释**，解释不出来再按老规矩当 `account_id` 用。
 * 这样正式包（还没有账号体系的那一版）不会被这次改动打断。
 */

import { createHash, createHmac, randomBytes, randomInt, scrypt as scryptCb, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
import { TOKEN_PREFIX, TOKEN_RE } from './auth-store.mjs';

const scrypt = promisify(scryptCb);

const ACCOUNT_ID_RE = /^[0-9a-f]{32,64}$/;
const EMAIL_RE = /^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$/;
const CODE_RE = /^\d{6}$/;
/** 客户端派生的认证凭据：hex 或 base64，长度按 32 字节上下的量级给。 */
const VERIFIER_RE = /^[0-9a-zA-Z+/=_-]{32,128}$/;
const SALT_RE = /^[0-9a-f]{16,128}$/;
const WRAPPED_MAX = 1024;
const KDF_MAX = 256;

/** 客户端 KDF 的默认参数（只在"这个邮箱还没注册"时用来凑形状，真值由客户端在建号时报上来）。 */
export const DEFAULT_KDF = JSON.stringify({ alg: 'argon2id', m: 65536, t: 3, p: 4, v: 19 });

const CODE_TTL_MS = 10 * 60 * 1000;

const sha256hex = (s) => createHash('sha256').update(s, 'utf8').digest('hex');

/** `scrypt` 的结果串：`s1$<salt>$<hash>`。带版本号，将来换参数时能认出来。 */
async function hashSecret(secret) {
  const salt = randomBytes(16);
  const key = await scrypt(secret, salt, 32, { N: 16384, r: 8, p: 1 });
  return `s1$${salt.toString('hex')}$${key.toString('hex')}`;
}

async function verifySecret(secret, stored) {
  const parts = String(stored ?? '').split('$');
  if (parts.length !== 3 || parts[0] !== 's1') return false;
  const salt = Buffer.from(parts[1], 'hex');
  const expected = Buffer.from(parts[2], 'hex');
  const key = await scrypt(secret, salt, expected.length, { N: 16384, r: 8, p: 1 });
  return key.length === expected.length && timingSafeEqual(key, expected);
}

export function createAuth({
  store,
  backendStore = null,
  mailer,
  secret,
  log = () => {},
  now = () => Date.now(),
  limits = {},
  appName = '练了么',
} = {}) {
  if (!store) throw new Error('createAuth 需要 store（auth-store）');
  if (!mailer) throw new Error('createAuth 需要 mailer（server/mailer.mjs）');
  if (!secret) throw new Error('createAuth 需要 secret（用于反枚举的假盐，生产必须固定）');

  const L = {
    codeMinIntervalMs: 60 * 1000,
    codePerDayPerEmail: 10,
    codePerDayGlobal: 200,
    loginFailWindowMs: 15 * 60 * 1000,
    loginFailPerEmail: 10,
    codeMaxAttempts: 6,
    ...limits,
  };

  /** 邮箱在日志里的样子：指纹，不是明文。 */
  const fp = (email) => sha256hex(store.normalizeEmail(email)).slice(0, 8);

  const validEmail = (e) => typeof e === 'string' && e.length <= 254 && EMAIL_RE.test(e);
  const fakeSaltFor = (email) => createHmac('sha256', secret).update(`salt|${store.normalizeEmail(email)}`).digest('hex');

  /** 发一个会话令牌：**明文只回给客户端一次**，库里只留 sha256。
   *  前缀 `lm1_` 的作用见 auth-store.mjs 的 TOKEN_RE 注释（不加前缀的话，
   *  "令牌被吊销"会退化成"账号不存在"）。 */
  function issueToken(accountId, deviceId) {
    const token = TOKEN_PREFIX + randomBytes(32).toString('hex');
    store.createToken({ tokenHash: sha256hex(token), accountId, deviceId });
    return token;
  }

  /**
   * 校验验证码。**每一步失败都回同一句话**（不给爆破者任何区分信号），
   * 并且把 attempts 记在行上（超过上限这条码就作废，必须重新发）。
   */
  async function consumeCode(email, purpose, code) {
    const row = store.latestCode(email, purpose);
    if (!row) return { ok: false, why: 'missing' };
    if (now() > Number(row.expires_at)) return { ok: false, why: 'expired' };
    if (Number(row.attempts) >= L.codeMaxAttempts) return { ok: false, why: 'attempts' };
    store.bumpCodeAttempts(row.id);
    const ok = sha256hex(String(code)) === row.code_hash;
    if (!ok) return { ok: false, why: 'mismatch' };
    store.markCodeUsed(row.id);
    return { ok: true };
  }

  async function sendCode(email, purpose) {
    const existing = store.findByEmail(email);
    if (purpose === 'register' && existing) {
      // 不发明文验证码：这个邮箱已经有账号，注册这一步无论如何都会 409。
      await mailer.send({
        to: email,
        subject: `${appName} · 这个邮箱已经有账号了`,
        text: `你正在注册的邮箱已经有一个${appName}账号。\n\n如果忘了口令，用「忘记口令」重新设置（需要再次收到本邮箱的验证码）。\n如果不是你本人操作，忽略这封邮件即可。`,
      });
      return { sent: false };
    }
    if (purpose === 'reset' && !existing) {
      await mailer.send({
        to: email,
        subject: `${appName} · 没有找到这个邮箱的账号`,
        text: `我们没有找到用这个邮箱注册的${appName}账号。\n\n如果要用这个邮箱开始，请在 App 里注册。\n如果不是你本人操作，忽略这封邮件即可。`,
      });
      return { sent: false };
    }
    const code = String(randomInt(0, 1000000)).padStart(6, '0');
    store.insertCode({ email, purpose, codeHash: sha256hex(code), ttlMs: CODE_TTL_MS });
    await mailer.send({
      to: email,
      subject: `${appName} · ${purpose === 'reset' ? '重设口令' : '注册'}验证码 ${code}`,
      text: `你的验证码是 ${code}。\n\n十分钟内有效，只能用在「${purpose === 'reset' ? '重设口令' : '注册'}」这一步。\n如果这不是你本人操作，忽略这封邮件即可 —— 没有人能凭它读到你的训练数据。`,
    });
    return { sent: true };
  }

  /**
   * 处理一个请求。**返回 true 表示"这个请求我接了"**，false 表示"不归我管"。
   * 所有 `/v1/auth/*` 都必须在这里处理完 —— 它们**不能**走到 `backend.mjs` 的
   * "必须先有账号"那道闸门后面去（那会变成"要先登录才能登录"）。
   */
  async function tryHandle({ req, res, p, say, json, readBody }) {
    if (!p.startsWith('/v1/auth/')) return false;

    const body = async (limit = 8192) => {
      const r = await readBody(req, limit);
      if (r.tooLarge) return null;
      try { return JSON.parse(r.body?.toString('utf8') ?? ''); } catch { return null; }
    };

    // ---------------------------------------------------------- 拿盐
    if (req.method === 'POST' && p === '/v1/auth/salt') {
      const payload = await body();
      const email = payload?.email;
      if (!validEmail(email)) { say(400); json(res, 400, { error: '邮箱格式不对' }); return true; }
      const row = store.findByEmail(email);
      // ⚠️ 不存在的邮箱也要回一个**形状一样**的盐（HMAC 算出来的），否则这里有枚举口子。
      say(200);
      json(res, 200, {
        salt: row ? row.salt : fakeSaltFor(email),
        kdf: row ? row.kdf : DEFAULT_KDF,
      });
      return true;
    }

    // ---------------------------------------------------------- 发验证码
    if (req.method === 'POST' && p === '/v1/auth/code') {
      const payload = await body();
      const email = payload?.email;
      const purpose = payload?.purpose === 'reset' ? 'reset' : 'register';
      if (!validEmail(email)) { say(400); json(res, 400, { error: '邮箱格式不对' }); return true; }

      const t = now();
      const last = store.latestCodeAt(email);
      if (last !== null && t - last < L.codeMinIntervalMs) {
        say(429);
        json(res, 429, { error: '刚发过一封，请 60 秒后再试' });
        return true;
      }
      if (store.countCodes(email, t - 24 * 3600 * 1000) >= L.codePerDayPerEmail
        || store.countAllCodes(t - 24 * 3600 * 1000) >= L.codePerDayGlobal) {
        say(429);
        json(res, 429, { error: '今天发得太多了，明天再试' });
        return true;
      }

      try {
        await sendCode(email, purpose);
      } catch (e) {
        // 发不出去就如实说 —— 别让用户对着"已发送"干等（这也是 mailer 配置不全的暴露口）。
        log(`发信失败（${fp(email)}）：${e?.message ?? e}`);
        say(502);
        json(res, 502, { error: '验证码没发出去，请稍后再试' });
        return true;
      }
      store.prune();
      log(`验证码已发（${purpose} · ${fp(email)}）`);
      say(200);
      json(res, 200, { ok: true });
      return true;
    }

    // ---------------------------------------------------------- 注册
    if (req.method === 'POST' && p === '/v1/auth/register') {
      const payload = await body();
      const { email, code, verifier, wrapped, account_id: accountId, salt, kdf, device_id: deviceId, device_name: deviceName } = payload ?? {};
      if (!validEmail(email) || !CODE_RE.test(String(code ?? ''))
        || !VERIFIER_RE.test(String(verifier ?? '')) || !SALT_RE.test(String(salt ?? ''))
        || !ACCOUNT_ID_RE.test(String(accountId ?? ''))
        || typeof wrapped !== 'string' || wrapped.length > WRAPPED_MAX
        || typeof kdf !== 'string' || kdf.length > KDF_MAX) {
        say(400); json(res, 400, { error: '注册参数不完整或形状不对' }); return true;
      }
      const c = await consumeCode(email, 'register', code);
      if (!c.ok) { say(400); json(res, 400, { error: '验证码不对或已过期' }); return true; }

      const bound = store.bindAccount({
        accountId, email, salt, kdf, verifier: await hashSecret(verifier), wrapped,
      });
      if (!bound.ok) {
        say(409);
        json(res, 409, {
          error: bound.why === 'email_taken' ? '这个邮箱已经注册过了' : '这个账号已经绑过邮箱了',
        });
        return true;
      }
      if (backendStore) {
        backendStore.createAccount(accountId);
        backendStore.touchDevice(accountId, deviceId, deviceName);
      }
      const token = issueToken(accountId, deviceId);
      log(`注册成功（${fp(email)}）`);
      say(201);
      json(res, 201, { account_id: accountId, token });
      return true;
    }

    // ---------------------------------------------------------- 登录
    if (req.method === 'POST' && p === '/v1/auth/login') {
      const payload = await body();
      const { email, verifier, device_id: deviceId, device_name: deviceName } = payload ?? {};
      if (!validEmail(email) || !VERIFIER_RE.test(String(verifier ?? ''))) {
        say(400); json(res, 400, { error: '登录参数不完整' }); return true;
      }
      const t = now();
      if (store.countEvents('login_fail', store.normalizeEmail(email), t - L.loginFailWindowMs) >= L.loginFailPerEmail) {
        say(429);
        json(res, 429, { error: '失败次数太多，请过一会儿再试' });
        return true;
      }
      const row = store.findByEmail(email);
      // ⚠️ 邮箱不存在时**照样做一次 scrypt**：否则"快 = 没这个邮箱"，等于把枚举答案写在耗时里。
      const ok = row ? await verifySecret(verifier, row.verifier) : (await hashSecret(verifier), false);
      if (!ok) {
        store.recordEvent('login_fail', store.normalizeEmail(email));
        say(401);
        json(res, 401, { error: '邮箱或口令不对' });
        return true;
      }
      if (backendStore) backendStore.touchDevice(row.account_id, deviceId, deviceName);
      const token = issueToken(row.account_id, deviceId);
      store.prune();
      log(`登录成功（${fp(email)}）`);
      say(200);
      json(res, 200, {
        account_id: row.account_id,
        token,
        wrapped: row.wrapped,
        salt: row.salt,
        kdf: row.kdf,
      });
      return true;
    }

    // ---------------------------------------------------------- 重置（用恢复码 → 设新口令）
    if (req.method === 'POST' && p === '/v1/auth/reset') {
      const payload = await body();
      const { email, code, verifier, wrapped, account_id: accountId, salt, kdf, device_id: deviceId } = payload ?? {};
      if (!validEmail(email) || !CODE_RE.test(String(code ?? ''))
        || !VERIFIER_RE.test(String(verifier ?? '')) || !SALT_RE.test(String(salt ?? ''))
        || !ACCOUNT_ID_RE.test(String(accountId ?? ''))
        || typeof wrapped !== 'string' || wrapped.length > WRAPPED_MAX
        || typeof kdf !== 'string' || kdf.length > KDF_MAX) {
        say(400); json(res, 400, { error: '重置参数不完整或形状不对' }); return true;
      }
      // ⚠️ 顺序很重要：**先核"这个邮箱与这个 account_id 是不是一对"，再去核验证码**。
      // 反过来的话，一次手滑（恢复码抄错）就会把刚收到的验证码烧掉 —— 用户得再等一分钟重发，
      // 而且他会以为是验证码坏了。三条失败一律回同一句话，外面分不出差在哪。
      const row = store.findByEmail(email);
      if (!row || row.account_id !== accountId) {
        say(400); json(res, 400, { error: '验证码不对、已过期，或者这个邮箱与恢复码对不上' }); return true;
      }
      const c = await consumeCode(email, 'reset', code);
      if (!c.ok) {
        say(400); json(res, 400, { error: '验证码不对、已过期，或者这个邮箱与恢复码对不上' }); return true;
      }
      store.updateCredentials({ accountId, salt, kdf, verifier: await hashSecret(verifier), wrapped });
      // 改口令 = "旧口令可能已经泄漏"的默认假设：把这家账号**所有**旧会话踢掉，再发一个新的。
      store.revokeOtherTokens(accountId, '');
      const token = issueToken(accountId, deviceId);
      log(`口令已重置（${fp(email)}）`);
      say(200);
      json(res, 200, { account_id: accountId, token });
      return true;
    }

    // ---------------------------------------------------------- 以下都要令牌
    const bearer = (() => {
      const h = req.headers['authorization'] ?? '';
      const m = /^Bearer\s+(.+)$/i.exec(h);
      return m ? m[1].trim() : null;
    })();
    const tokenAccount = bearer && TOKEN_RE.test(bearer)
      ? store.resolveToken(sha256hex(bearer))
      : null;
    const row = tokenAccount ? store.findByAccount(tokenAccount) : null;
    if (!row) { say(401); json(res, 401, { error: '缺少或非法的会话令牌' }); return true; }

    if (req.method === 'POST' && p === '/v1/auth/logout') {
      const n = store.revokeToken(sha256hex(bearer));
      say(200);
      json(res, 200, { revoked: n });
      return true;
    }

    if (req.method === 'POST' && p === '/v1/auth/change-password') {
      const payload = await body();
      const { current_verifier: current, verifier, wrapped, salt, kdf } = payload ?? {};
      if (!VERIFIER_RE.test(String(current ?? '')) || !VERIFIER_RE.test(String(verifier ?? ''))
        || !SALT_RE.test(String(salt ?? '')) || typeof wrapped !== 'string' || wrapped.length > WRAPPED_MAX
        || typeof kdf !== 'string' || kdf.length > KDF_MAX) {
        say(400); json(res, 400, { error: '改口令参数不完整或形状不对' }); return true;
      }
      if (!(await verifySecret(current, row.verifier))) {
        say(401); json(res, 401, { error: '当前口令不对' }); return true;
      }
      store.updateCredentials({ accountId: row.account_id, salt, kdf, verifier: await hashSecret(verifier), wrapped });
      const revoked = store.revokeOtherTokens(row.account_id, sha256hex(bearer));
      log(`口令已改（${fp(row.email)}，踢掉 ${revoked} 个旧会话）`);
      say(200);
      json(res, 200, { ok: true, revoked_others: revoked });
      return true;
    }

    if (req.method === 'GET' && p === '/v1/auth/me') {
      say(200);
      json(res, 200, {
        email: row.email,
        account_id: row.account_id,
        changed_at: Number(row.changed_at),
        devices: store.tokenCount(row.account_id),
      });
      return true;
    }

    say(404);
    json(res, 404, { error: '没有这个认证接口' });
    return true;
  }

  /**
   * 把 `Authorization: Bearer <x>` 解释成 account_id。
   * **先当会话令牌，再按老规矩当 account_id** —— 老客户端（没有账号体系那一版）不受影响。
   */
  function resolveBearer(value) {
    if (!value) return null;
    if (TOKEN_RE.test(value)) {
      const accountId = store.resolveToken(sha256hex(value));
      if (accountId) return { accountId, via: 'token' };
    }
    if (ACCOUNT_ID_RE.test(value)) return { accountId: value, via: 'account_id' };
    return null;
  }

  return { tryHandle, resolveBearer, store, _internals: { hashSecret, verifySecret, sha256hex } };
}
