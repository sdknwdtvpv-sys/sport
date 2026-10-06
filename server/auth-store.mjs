#!/usr/bin/env node
/**
 * 练了么 · 账号体系的**存储层**（邮箱 / 凭据 / 会话令牌 / 验证码 / 限流计数）
 *
 * 与 `server/backend-store.mjs` 分工一致：那一份管"账号 → 密文备份"，这一份管"**谁**是这个账号"。
 * 两个文件之间只有一根线：`account_id`。
 *
 * 四条不可破的规矩（与后端那三条同源，都是承诺）：
 *
 *   1. **`wrapped` 是密文**（客户端用口令派生的 KEK 把账号密钥包起来的那一坨）。
 *      本文件**不解它、不看它**，只存字节。服务端读不到训练数据的底线就压在这条上。
 *   2. **`verifier` 不存原文**：它虽然已经是客户端派生出来的值，仍然只存它的 scrypt 结果。
 *      库被拖走时，攻击者拿到的是"要再算一遍 scrypt 才能比对"的东西。
 *   3. **一个 `account_id` 只许绑一个邮箱**（`account_id` 是主键）。否则"换个邮箱把别人的号
 *      认领过来"会变成一条真的攻击路径。
 *   4. **删除就是删除**：`deleteByAccount()` 把邮箱绑定、令牌、验证码一起清掉
 *      （政策里"注销后不再保留"必须有对应实现）。
 *
 * 为什么用 `node:sqlite`：与后端同一条理由 —— **零依赖、本地就能跑通并自检**。
 * 换 Postgres 只改这一个文件。
 */

import { DatabaseSync } from 'node:sqlite';

/**
 * 会话令牌的形状：`lm1_` + 32 字节随机数的十六进制（共 68 个字符）。
 *
 * ⚠️ **那个前缀不是装饰**：老客户端用 `Bearer <account_id>`（32–64 位纯十六进制），
 * 而会话令牌也曾经是 64 位纯十六进制 —— 两者**形状一样**，于是"这个令牌已经被吊销了"
 * 会被解释成"这是一个不存在的 account_id"，回一句 404（"账号不存在（恢复码算错了？）"），
 * 而不是 401。加前缀之后两种凭据一眼可分，吊销就是 401。
 */
export const TOKEN_RE = /^lm1_[0-9a-f]{64}$/;

/** 令牌的前缀（发令牌与验令牌两处都要用同一个常量） */
export const TOKEN_PREFIX = 'lm1_';

export function createAuthStore({ path = ':memory:' } = {}) {
  const db = new DatabaseSync(path);

  db.exec(`
    create table if not exists auth_accounts (
      account_id  text primary key,          -- = 客户端算出的账号密钥哈希（与 backups 表同一个值）
      email       text not null unique,      -- 规范化后的邮箱（小写 + 去空白）
      salt        text not null,             -- 客户端 KDF 的盐（**不是**秘密）
      kdf         text not null,             -- 客户端 KDF 参数（JSON 字符串，服务端只保管）
      verifier    text not null,             -- scrypt(客户端派生的认证凭据)
      wrapped     text not null,             -- AEAD 包起来的账号密钥（**密文，服务端看不懂**）
      created_at  integer not null,
      changed_at  integer not null
    );
    create index if not exists auth_accounts_email on auth_accounts(email);

    create table if not exists auth_tokens (
      token_hash   text primary key,         -- sha256(令牌)：明文令牌只在客户端手里
      account_id   text not null,
      device_id    text,
      created_at   integer not null,
      last_used_at integer not null,
      revoked_at   integer null
    );
    create index if not exists auth_tokens_account on auth_tokens(account_id);

    create table if not exists auth_codes (
      id         integer primary key autoincrement,
      email      text not null,
      purpose    text not null,              -- register / reset
      code_hash  text not null,              -- sha256(验证码)：只活 10 分钟，够用
      created_at integer not null,
      expires_at integer not null,
      used_at    integer null,
      attempts   integer not null default 0
    );
    create index if not exists auth_codes_lookup on auth_codes(email, purpose, created_at);

    -- 限流计数（发信、登录失败）。**不按 IP**：这台服务不处理来源地址（见 auth.mjs）。
    create table if not exists auth_events (
      id   integer primary key autoincrement,
      kind text not null,
      key  text not null,
      at   integer not null
    );
    create index if not exists auth_events_lookup on auth_events(kind, key, at);
  `);

  const now = () => Date.now();

  return {
    // ------------------------------------------------------------ 账号
    /** 规范化：小写 + 去首尾空白。**只做这一件事**（别在这里做正则校验，那是 auth.mjs 的事）。 */
    normalizeEmail(email) {
      return String(email ?? '').trim().toLowerCase();
    },

    findByEmail(email) {
      return db
        .prepare(`select account_id, email, salt, kdf, verifier, wrapped, created_at, changed_at
                  from auth_accounts where email = ?`)
        .get(this.normalizeEmail(email)) ?? null;
    },

    findByAccount(accountId) {
      return db
        .prepare(`select account_id, email, salt, kdf, verifier, wrapped, created_at, changed_at
                  from auth_accounts where account_id = ?`)
        .get(accountId) ?? null;
    },

    /**
     * 建绑定。**一个 account_id 只许一个邮箱**（主键）；邮箱也唯一。
     * 返回 {ok:true} / {ok:false, why:'account_taken'|'email_taken'}。
     */
    bindAccount({ accountId, email, salt, kdf, verifier, wrapped }) {
      const e = this.normalizeEmail(email);
      if (db.prepare('select 1 from auth_accounts where account_id = ?').get(accountId)) {
        return { ok: false, why: 'account_taken' };
      }
      if (db.prepare('select 1 from auth_accounts where email = ?').get(e)) {
        return { ok: false, why: 'email_taken' };
      }
      const at = now();
      db.prepare(
        `insert into auth_accounts (account_id, email, salt, kdf, verifier, wrapped, created_at, changed_at)
         values (?, ?, ?, ?, ?, ?, ?, ?)`,
      ).run(accountId, e, salt, kdf, verifier, wrapped, at, at);
      return { ok: true };
    },

    /** 改口令（或恢复码那条路重设口令）：换 verifier 与 wrapped，**account_id 与备份都不动**。 */
    updateCredentials({ accountId, salt, kdf, verifier, wrapped }) {
      const r = db
        .prepare(`update auth_accounts set salt = ?, kdf = ?, verifier = ?, wrapped = ?, changed_at = ?
                  where account_id = ?`)
        .run(salt, kdf, verifier, wrapped, now(), accountId);
      return r.changes > 0;
    },

    // ------------------------------------------------------------ 令牌
    createToken({ tokenHash, accountId, deviceId }) {
      const at = now();
      db.prepare(
        `insert into auth_tokens (token_hash, account_id, device_id, created_at, last_used_at)
         values (?, ?, ?, ?, ?)`,
      ).run(tokenHash, accountId, deviceId ?? null, at, at);
      return at;
    },

    /** 令牌 → account_id。**已吊销的不算**。顺带记一下"最近用过"。 */
    resolveToken(tokenHash) {
      const row = db
        .prepare(`select account_id, revoked_at from auth_tokens where token_hash = ?`)
        .get(tokenHash);
      if (!row || row.revoked_at !== null) return null;
      db.prepare('update auth_tokens set last_used_at = ? where token_hash = ?').run(now(), tokenHash);
      return row.account_id;
    },

    revokeToken(tokenHash) {
      const r = db
        .prepare('update auth_tokens set revoked_at = ? where token_hash = ? and revoked_at is null')
        .run(now(), tokenHash);
      return Number(r.changes);
    },

    /** 改口令时把**其他**会话也踢掉（当前这台留着）——这是"口令可能已经泄漏"的正确反应。 */
    revokeOtherTokens(accountId, keepTokenHash) {
      const r = db
        .prepare(`update auth_tokens set revoked_at = ?
                  where account_id = ? and revoked_at is null and token_hash <> ?`)
        .run(now(), accountId, keepTokenHash);
      return Number(r.changes);
    },

    tokenCount(accountId) {
      const row = db
        .prepare('select count(*) as n from auth_tokens where account_id = ? and revoked_at is null')
        .get(accountId);
      return Number(row.n);
    },

    // ------------------------------------------------------------ 验证码
    insertCode({ email, purpose, codeHash, ttlMs }) {
      const at = now();
      db.prepare(
        `insert into auth_codes (email, purpose, code_hash, created_at, expires_at)
         values (?, ?, ?, ?, ?)`,
      ).run(this.normalizeEmail(email), purpose, codeHash, at, at + ttlMs);
      return at;
    },

    /** 取这个邮箱最近一条**没用过**的验证码（不判过期 —— 过期是读取方的事，见 consumeCode）。 */
    latestCode(email, purpose) {
      return db
        .prepare(`select id, code_hash, created_at, expires_at, attempts
                  from auth_codes where email = ? and purpose = ? and used_at is null
                  order by created_at desc limit 1`)
        .get(this.normalizeEmail(email), purpose) ?? null;
    },

    bumpCodeAttempts(id) {
      db.prepare('update auth_codes set attempts = attempts + 1 where id = ?').run(id);
    },

    markCodeUsed(id) {
      db.prepare('update auth_codes set used_at = ? where id = ?').run(now(), id);
    },

    countCodes(email, sinceMs) {
      const row = db
        .prepare('select count(*) as n from auth_codes where email = ? and created_at >= ?')
        .get(this.normalizeEmail(email), sinceMs);
      return Number(row.n);
    },

    countAllCodes(sinceMs) {
      const row = db.prepare('select count(*) as n from auth_codes where created_at >= ?').get(sinceMs);
      return Number(row.n);
    },

    latestCodeAt(email) {
      const row = db
        .prepare('select created_at from auth_codes where email = ? order by created_at desc limit 1')
        .get(this.normalizeEmail(email));
      return row ? Number(row.created_at) : null;
    },

    // ------------------------------------------------------------ 限流计数
    recordEvent(kind, key) {
      db.prepare('insert into auth_events (kind, key, at) values (?, ?, ?)').run(kind, key, now());
    },

    countEvents(kind, key, sinceMs) {
      const row = db
        .prepare('select count(*) as n from auth_events where kind = ? and key = ? and at >= ?')
        .get(kind, key, sinceMs);
      return Number(row.n);
    },

    /** 清掉过期的验证码与陈旧的限流计数（每次调用顺手做一点，避免库无限长）。 */
    prune({ codeTtlMs = 24 * 3600 * 1000, eventTtlMs = 48 * 3600 * 1000 } = {}) {
      const at = now();
      const c = db.prepare('delete from auth_codes where created_at < ?').run(at - codeTtlMs);
      const e = db.prepare('delete from auth_events where at < ?').run(at - eventTtlMs);
      return { codes: Number(c.changes), events: Number(e.changes) };
    },

    // ------------------------------------------------------------ 注销
    deleteByAccount(accountId) {
      const row = this.findByAccount(accountId);
      const t = db.prepare('delete from auth_tokens where account_id = ?').run(accountId);
      let c = { changes: 0 };
      if (row) c = db.prepare('delete from auth_codes where email = ?').run(row.email);
      const a = db.prepare('delete from auth_accounts where account_id = ?').run(accountId);
      return Number(a.changes) + Number(t.changes) + Number(c.changes);
    },

    stats() {
      const n = (sql) => Number(db.prepare(sql).get().n);
      return {
        binds: n('select count(*) as n from auth_accounts'),
        tokens: n('select count(*) as n from auth_tokens where revoked_at is null'),
      };
    },

    close() {
      db.close();
    },
  };
}
