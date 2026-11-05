#!/usr/bin/env node
/**
 * 练了么 · 会员（Ultra）服务端**存储层**（M3）
 *
 * 设计：`docs/plan-membership-2026-10-10.md` §八.3；只做三张表，零依赖（`node:sqlite`）：
 *
 *   1. `entitlements` —— 权益。**一条商店交易一行**，`original_txn` 是幂等键：
 *      * 重放同一 `transactionId` / 同一到期时间 → **不重复延长**；
 *      * 新的续订（同一 `original_txn`、更晚的 `expires_at`）→ **只延长、不缩短**；
 *      * 退款 / 撤销是**终态**：立即失效，且**不允许后续续订把它复活**。
 *   2. `redeem_codes` —— 自建兑换码。**只存 SHA-256**（明文只在生成那一刻出现一次）；
 *      一次性、原子核销（`UPDATE … WHERE used_at IS NULL` 一条语句，并发只有一个成功）。
 *   3. `billing_events` —— 限速与审计（与 `auth_events` 同一套写法）。
 *
 * 三条纪律：
 *   * **不记明文兑换码、不记收据内容**；事件表里只放哈希/交易号/状态；
 *   * **账目可对**：`transactionId` / `notificationUUID` 都进事件表做去重，重放不会二次生效；
 *   * **先落库再回 2xx**：通知重试是常态（Apple 会重投），幂等必须写在存储层而不是路由层。
 */

import { DatabaseSync } from 'node:sqlite';

/** 权益来源（与客户端 `UltraSource` 的三个商店来源对齐；服务端不认识 debug）。 */
export const ENTITLEMENT_SOURCES = Object.freeze(['apple', 'google', 'redeem']);

/** 自建码核销写进权益时用的 `product` —— M4 客户端把它映射成"兑换来的 Ultra"。 */
export const REDEEM_PRODUCT = 'redeem';

/**
 * 兑换码档位 → 天数。`lifetime` 是终身码（`days = null`）。
 * 与 `redeem-admin.mjs` 的 `--kind` 共用这一份，不在两处各写一套。
 */
export const REDEEM_KINDS = Object.freeze({
  month: 30,
  quarter: 90,
  year: 365,
  lifetime: null,
});

/**
 * 建一个权益存储。
 *
 * @param {{path?: string, now?: () => number}} [opts]
 *   `now` 只给自检用（可拨时钟测过期/限速窗口）；生产不传。
 */
export function createBillingStore({ path = ':memory:', now = () => Date.now() } = {}) {
  const db = new DatabaseSync(path);
  const nowMs = () => Number(now());

  db.exec(`
    create table if not exists entitlements (
      account_id    text not null,
      product       text not null,
      source        text not null,
      original_txn  text not null,
      expires_at    integer null,             -- null = 终身（非消耗型买断 / 终身兑换码）
      environment   text null,                -- Apple 交易环境：Sandbox / Production（兑换码为 null）
      revoked_at    integer null,             -- 撤销（家庭共享被撤 / 商店 REVOKE）：终态
      refunded_at   integer null,             -- 退款：终态
      last_txn_id   text null,                -- 最近一次生效的商店交易号（审计用）
      created_at    integer not null,
      updated_at    integer not null,
      primary key (account_id, original_txn)
    );
    -- 通知回调只知道 originalTransactionId，不知道我们的 account_id —— 必须能反查。
    create index if not exists entitlements_original on entitlements(original_txn);
    create index if not exists entitlements_account on entitlements(account_id, updated_at);

    create table if not exists redeem_codes (
      code_hash text primary key,             -- sha256(规范化后的码)；**明文从不入库**
      kind      text not null,                -- month / quarter / year / lifetime
      days      integer null,                 -- lifetime 为 null
      batch     text not null,                -- 批次（发错/取消活动时整批作废）
      expire_at integer null,                 -- 码本身的失效时刻（null = 不过期）
      used_by   text null,                    -- 核销账号；一次性绑定、不可转移
      used_at   integer null,
      created_at integer not null
    );
    create index if not exists redeem_codes_batch on redeem_codes(batch, used_at);
    create index if not exists redeem_codes_used on redeem_codes(used_by, used_at);

    create table if not exists billing_events (
      id   integer primary key autoincrement,
      kind text not null,
      key  text not null,
      at   integer not null
    );
    create index if not exists billing_events_lookup on billing_events(kind, key, at);
  `);

  const rowOf = (stmt, ...args) => stmt.get(...args) ?? null;

  const findEntitlement = (accountId, originalTxn) => rowOf(
    db.prepare(`select account_id, product, source, original_txn, expires_at, environment,
                       revoked_at, refunded_at, last_txn_id, created_at, updated_at
                from entitlements where account_id = ? and original_txn = ?`),
    accountId, originalTxn,
  );

  const eventExists = (kind, key) => db
    .prepare('select 1 as one from billing_events where kind = ? and key = ? limit 1')
    .get(kind, key) !== undefined;

  const recordEvent = (kind, key, at = nowMs()) => {
    db.prepare('insert into billing_events (kind, key, at) values (?, ?, ?)').run(kind, key, at);
  };

  /** 「更晚的到期」：`null` 代表终身（最大）。退款/撤销不参与这个比较。 */
  const laterExpiry = (a, b) => {
    if (a === null) return null;
    if (b === null) return null;
    return Math.max(Number(a), Number(b));
  };

  /** 通知先于客户端 verify 到达时，把"终态"记在事件表里，等 verify 落库时补上。 */
  const pendingTerminalAt = (originalTxn, kind) => {
    const row = db
      .prepare('select at from billing_events where kind = ? and key = ? order by at asc limit 1')
      .get(kind, originalTxn);
    return row ? Number(row.at) : null;
  };

  return {
    // ─────────────────────────────────────────────── 权益
    /** 按 `(account_id, original_txn)` 取一条；没有就 null。 */
    getEntitlement: findEntitlement,

    /** 通知回调按 `originalTransactionId` 反查（可能有多行：同一订阅换了账号）。 */
    findByOriginal(originalTxn) {
      return db
        .prepare(`select account_id, product, source, original_txn, expires_at, environment,
                         revoked_at, refunded_at, last_txn_id, created_at, updated_at
                  from entitlements where original_txn = ?`)
        .all(originalTxn);
    },

    listByAccount(accountId) {
      return db
        .prepare(`select account_id, product, source, original_txn, expires_at, environment,
                         revoked_at, refunded_at, last_txn_id, created_at, updated_at
                  from entitlements where account_id = ? order by updated_at desc`)
        .all(accountId);
    },

    /**
     * 客户端 verify 落库 / Apple 通知的续订落库都走这一条。
     *
     * 返回 `{ changed, replayed, row }`：
     *   * `replayed=true` = 这笔 `transactionId` 已经处理过（不重复延长）；
     *   * `changed=false` = 新信息的到期时间不比库里晚（只延长不缩短）；
     *   * 退款/撤销过的行不会被"续订"复活（终态）。
     */
    applyStoreTransaction({
      accountId,
      product,
      source,
      originalTxn,
      expiresAt = null,
      environment = null,
      transactionId = null,
      atMs = nowMs(),
    }) {
      if (!accountId || !originalTxn || !product) {
        throw new Error('applyStoreTransaction 需要 accountId / originalTxn / product');
      }
      if (transactionId && eventExists('txn', transactionId)) {
        return { changed: false, replayed: true, row: findEntitlement(accountId, originalTxn) };
      }
      const at = Number(atMs);
      let row = findEntitlement(accountId, originalTxn);
      if (!row) {
        db.prepare(`insert into entitlements
            (account_id, product, source, original_txn, expires_at, environment, last_txn_id, created_at, updated_at)
            values (?, ?, ?, ?, ?, ?, ?, ?, ?)`)
          .run(accountId, product, source, originalTxn, expiresAt, environment, transactionId, at, at);
        row = findEntitlement(accountId, originalTxn);
      } else if (row.revoked_at === null && row.refunded_at === null) {
        // 通知可能比客户端 verify 先到（DID_RENEW）：把 pending 续订的到期时间也算进来。
        // ⚠️ `pendingRenewExpiry` 返回 null 表示"没有 pending"，不能当成"终身"（那是 infinity）。
        const pending = this.pendingRenewExpiry(originalTxn);
        const next = pending === null
          ? laterExpiry(row.expires_at, expiresAt)
          : laterExpiry(row.expires_at, laterExpiry(expiresAt, pending));
        const nextEnv = environment ?? row.environment;
        if (next !== row.expires_at || nextEnv !== row.environment) {
          db.prepare(`update entitlements set expires_at = ?, environment = ?, last_txn_id = ?, updated_at = ?
                      where account_id = ? and original_txn = ?`)
            .run(next, nextEnv, transactionId ?? row.last_txn_id, at, accountId, originalTxn);
        } else if (transactionId && transactionId !== row.last_txn_id) {
          db.prepare('update entitlements set last_txn_id = ?, updated_at = ? where account_id = ? and original_txn = ?')
            .run(transactionId, at, accountId, originalTxn);
        }
        row = findEntitlement(accountId, originalTxn);
      } else {
        // 终态行：任何续订都不能复活它；只更新"最近一次交易号"方便排障。
        if (transactionId && transactionId !== row.last_txn_id) {
          db.prepare('update entitlements set last_txn_id = ?, updated_at = ? where account_id = ? and original_txn = ?')
            .run(transactionId, at, accountId, originalTxn);
        }
        row = findEntitlement(accountId, originalTxn);
      }
      // 「通知早于 verify」的迟到终态：落库时补上（退款/撤销优先级最高）。
      const refundPending = pendingTerminalAt(originalTxn, 'refund_pending');
      const revokePending = pendingTerminalAt(originalTxn, 'revoke_pending');
      if (refundPending !== null || revokePending !== null) {
        db.prepare(`update entitlements set
              refunded_at = coalesce(refunded_at, ?),
              revoked_at = coalesce(revoked_at, ?),
              updated_at = ?
            where account_id = ? and original_txn = ?`)
          .run(refundPending, revokePending, at, accountId, originalTxn);
        row = findEntitlement(accountId, originalTxn);
      }
      if (transactionId) {
        recordEvent('txn', transactionId, at);
        // 注销要能按账号找齐"这个人的所有 transactionId"：单靠 entitlements.last_txn_id 只有最近一笔。
        recordEvent('txn_account', `${accountId}|${transactionId}`, at);
      }
      return { changed: true, replayed: false, row };
    },

    /**
     * 退款 / 撤销 / 到期标记（Apple 通知用）。
     * * `refunded` / `revoked` 是终态，立即失效；
     * * 没有对应权益行时（通知先于 verify）记一条 pending 事件，verify 落库时补上。
     */
    markTerminal({ originalTxn, kind, atMs = nowMs() }) {
      if (kind !== 'refunded' && kind !== 'revoked') throw new Error(`未知终态：${kind}`);
      const at = Number(atMs);
      const column = kind === 'refunded' ? 'refunded_at' : 'revoked_at';
      const pendingKind = kind === 'refunded' ? 'refund_pending' : 'revoke_pending';
      const r = db.prepare(`update entitlements set ${column} = coalesce(${column}, ?), updated_at = ?
                            where original_txn = ?`).run(at, at, originalTxn);
      if (Number(r.changes) === 0) recordEvent(pendingKind, originalTxn, at);
      return Number(r.changes) > 0;
    },

    /** 到期（EXPIRED 通知）：只把"已知到期时间"落下来，不缩短已有更晚到期。 */
    markExpired({ originalTxn, expiresAt = null, atMs = nowMs() }) {
      const at = Number(atMs);
      const rows = this.findByOriginal(originalTxn);
      let n = 0;
      for (const row of rows) {
        if (row.revoked_at !== null || row.refunded_at !== null) continue;
        const next = expiresAt === null ? row.expires_at : laterExpiry(row.expires_at, Math.min(Number(expiresAt), at));
        if (next !== row.expires_at) {
          db.prepare('update entitlements set expires_at = ?, updated_at = ? where account_id = ? and original_txn = ?')
            .run(next, at, row.account_id, originalTxn);
          n += 1;
        }
      }
      return n;
    },

    /**
     * 现在该给什么权益（按账号）。返回 `{ row, status }`：
     * `status ∈ none | active | expired | refunded | revoked`。
     * 退款/撤销优先于到期；终身（expires_at = null）永远 active。
     */
    currentFor(accountId, atMs = nowMs()) {
      const at = Number(atMs);
      const rows = this.listByAccount(accountId);
      if (rows.length === 0) return { row: null, status: 'none' };
      const usable = rows.filter((r) => r.revoked_at === null && r.refunded_at === null
        && (r.expires_at === null || Number(r.expires_at) > at));
      if (usable.length > 0) {
        // 终身 > 到期晚的；同档取 updated_at 更晚的（最近一次写入）
        usable.sort((a, b) => {
          const aLife = a.expires_at === null ? 1 : 0;
          const bLife = b.expires_at === null ? 1 : 0;
          if (aLife !== bLife) return bLife - aLife;
          const d = Number(b.expires_at) - Number(a.expires_at);
          return d !== 0 ? d : Number(b.updated_at) - Number(a.updated_at);
        });
        return { row: usable[0], status: 'active' };
      }
      // 不可用：退款/撤销优先（如实告诉用户"已退款"比"已到期"更有信息量）
      const terminal = rows.find((r) => r.refunded_at !== null)
        ?? rows.find((r) => r.revoked_at !== null);
      if (terminal) return { row: terminal, status: terminal.refunded_at !== null ? 'refunded' : 'revoked' };
      return { row: rows[0], status: 'expired' };
    },

    // ─────────────────────────────────────────────── 兑换码
    /** 批量入库（只收哈希）。返回实际插入条数。 */
    insertCodes(rows) {
      if (!rows.length) return 0;
      let n = 0;
      db.exec('BEGIN IMMEDIATE');
      try {
        const stmt = db.prepare(`insert or ignore into redeem_codes
            (code_hash, kind, days, batch, expire_at, created_at) values (?, ?, ?, ?, ?, ?)`);
        for (const r of rows) {
          const res = stmt.run(r.codeHash, r.kind, r.days ?? null, r.batch, r.expireAt ?? null, nowMs());
          n += Number(res.changes);
        }
        db.exec('COMMIT');
      } catch (e) {
        db.exec('ROLLBACK');
        throw e;
      }
      return n;
    },

    /**
     * **原子核销**：一条 `UPDATE … WHERE used_at IS NULL AND (expire_at IS NULL OR expire_at > ?)`。
     * 并发同一码只可能有一个 `changes = 1`；返回 `{ok, reason, kind, days, batch}`。
     * 不返回明文码、也不把它写进日志。
     */
    redeemCode({ codeHash, accountId, atMs = nowMs() }) {
      const at = Number(atMs);
      const upd = db.prepare(`update redeem_codes set used_by = ?, used_at = ?
                              where code_hash = ? and used_at is null
                                and (expire_at is null or expire_at > ?)`)
        .run(accountId, at, codeHash, at);
      const row = db.prepare('select code_hash, kind, days, batch, expire_at, used_by, used_at from redeem_codes where code_hash = ?')
        .get(codeHash) ?? null;
      if (Number(upd.changes) === 1) {
        return { ok: true, kind: row.kind, days: row.days === null ? null : Number(row.days), batch: row.batch };
      }
      if (!row) return { ok: false, reason: 'missing' };
      if (row.used_at !== null) {
        return { ok: false, reason: 'used', usedBySameAccount: row.used_by === accountId };
      }
      return { ok: false, reason: 'expired' };
    },

    /** 作废**未核销**的码（已核销的不动 —— 那是用户已买到的权益）。返回作废条数。 */
    revokeUnused({ batch = null, codeHash = null } = {}) {
      if (!batch && !codeHash) throw new Error('revokeUnused 需要 batch 或 codeHash');
      const res = codeHash
        ? db.prepare('delete from redeem_codes where code_hash = ? and used_at is null').run(codeHash)
        : db.prepare('delete from redeem_codes where batch = ? and used_at is null').run(batch);
      return Number(res.changes);
    },

    /** 批次统计（运营查"这批发出多少、核销多少、作废多少"用）。 */
    batchStats(batch) {
      const row = db.prepare(`select count(*) as total,
          sum(case when used_at is not null then 1 else 0 end) as used,
          sum(case when used_at is null then 1 else 0 end) as unused
        from redeem_codes where batch = ?`).get(batch);
      return { batch, total: Number(row.total), used: Number(row.used ?? 0), unused: Number(row.unused ?? 0) };
    },

    listBatches() {
      return db.prepare(`select batch, count(*) as total,
          sum(case when used_at is not null then 1 else 0 end) as used
        from redeem_codes group by batch order by batch`).all()
        .map((r) => ({ batch: r.batch, total: Number(r.total), used: Number(r.used ?? 0) }));
    },

    // ─────────────────────────────────────────────── 事件（限速/审计/去重）
    recordEvent,
    hasEvent: eventExists,

    countEvents(kind, key, sinceMs) {
      const row = db.prepare('select count(*) as n from billing_events where kind = ? and key = ? and at >= ?')
        .get(kind, key, Number(sinceMs));
      return Number(row.n);
    },

    /** 「通知先于 verify」的续订到期时间：事件表里 `renew_pending` 的 key 是 `originalTxn|expiresAt`。 */
    pendingRenewExpiry(originalTxn) {
      const rows = db.prepare("select key from billing_events where kind = 'renew_pending' and key like ?")
        .all(`${originalTxn}|%`);
      let max = null;
      for (const r of rows) {
        const raw = String(r.key).slice(String(originalTxn).length + 1);
        const n = Number(raw);
        if (!Number.isFinite(n)) continue;
        max = max === null ? n : Math.max(max, n);
      }
      return max;
    },

    firstEventAt(kind, key, sinceMs) {
      const row = db.prepare('select min(at) as at from billing_events where kind = ? and key = ? and at >= ?')
        .get(kind, key, Number(sinceMs));
      return row?.at == null ? null : Number(row.at);
    },

    lastEventAt(kind, key) {
      const row = db.prepare('select max(at) as at from billing_events where kind = ? and key = ?').get(kind, key);
      return row?.at == null ? null : Number(row.at);
    },

    /** 清陈旧事件（默认 30 天；限速窗口最长 1 小时，留足排障余量）。 */
    prune({ eventTtlMs = 30 * 24 * 3600 * 1000 } = {}) {
      const res = db.prepare('delete from billing_events where at < ?').run(nowMs() - Number(eventTtlMs));
      return Number(res.changes);
    },

    stats() {
      const one = (sql) => Number(db.prepare(sql).get().n);
      return {
        entitlements: one('select count(*) as n from entitlements'),
        redeemUnused: one('select count(*) as n from redeem_codes where used_at is null'),
      };
    },

    /**
     * 账号注销（合规）：**一个事务里**把计费数据一起删干净。
     *
     * 删三样（顺序有讲究）：
     *   1. 先取出这个账号的权益行（`original_txn` / `last_txn_id`）与 `txn_account` 事件
     *      （后者记着这个账号**每一笔** transactionId —— 只靠 `last_txn_id` 只有最近一笔）；
     *   2. 删 `entitlements`；删 `billing_events` 里所有属于这个人的键：
     *      `key = accountId`、`key like accountId||'|%'`（`redeem_fail` / `redeem_audit` /
     *      `redeem_attempt_account` / `txn_account`），以及上面那批 `txn` 事件、
     *      `renew_pending`（key 形如 `originalTxn|expiry`）与 `refund_pending` / `revoke_pending`；
     *   3. `redeem_codes.used_by` 置空、**`used_at` 保留** —— 码仍然算"已核销"，别人不能再用；
     *      摘掉的只是"与这个人的绑定"。
     *
     * 返回各类删了多少行（`total` 给 `DELETE /v1/account` 的 `deleted` 计数用）。
     */
    deleteByAccount(accountId) {
      if (typeof accountId !== 'string' || accountId.length === 0) {
        return { entitlements: 0, events: 0, redeemUnlinks: 0, total: 0 };
      }
      const esc = (v) => String(v).replace(/[\\%_]/g, '\\$&');
      const rows = db
        .prepare('select original_txn, last_txn_id from entitlements where account_id = ?')
        .all(accountId);
      const originals = [...new Set(rows.map((r) => r.original_txn))];
      const txnIds = new Set(rows.map((r) => r.last_txn_id).filter(Boolean));
      for (const r of db
        .prepare("select key from billing_events where kind = 'txn_account' and key like ? escape '\\'")
        .all(`${esc(accountId)}|%`)) {
        const txn = String(r.key).slice(String(accountId).length + 1);
        if (txn) txnIds.add(txn);
      }

      db.exec('BEGIN IMMEDIATE');
      try {
        const ent = db.prepare('delete from entitlements where account_id = ?').run(accountId);
        let events = Number(db.prepare('delete from billing_events where key = ?').run(accountId).changes);
        events += Number(db
          .prepare("delete from billing_events where key like ? escape '\\'")
          .run(`${esc(accountId)}|%`).changes);
        for (const txn of txnIds) {
          events += Number(db.prepare("delete from billing_events where kind = 'txn' and key = ?").run(txn).changes);
        }
        for (const otx of originals) {
          events += Number(db
            .prepare("delete from billing_events where kind in ('refund_pending','revoke_pending') and key = ?")
            .run(otx).changes);
          events += Number(db
            .prepare("delete from billing_events where kind = 'renew_pending' and key like ? escape '\\'")
            .run(`${esc(otx)}|%`).changes);
        }
        // 已核销的码不能"回到未核销"（那等于凭空多一个可再卖的码）——保留行、只摘绑定。
        const unlink = db.prepare('update redeem_codes set used_by = null where used_by = ?').run(accountId);
        db.exec('COMMIT');
        const entitlements = Number(ent.changes);
        const redeemUnlinks = Number(unlink.changes);
        return { entitlements, events, redeemUnlinks, total: entitlements + events + redeemUnlinks };
      } catch (e) {
        db.exec('ROLLBACK');
        throw e;
      }
    },

    close() {
      db.close();
    },
  };
}
