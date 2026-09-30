#!/usr/bin/env node
/**
 * 练了么 · 极薄后端的**存储层**
 *
 * 只存三样东西：账号、设备、**加密后的备份包**。
 * 设计见 `docs/backend-design.md`；这份文件只回答"数据怎么落"。
 *
 * 三条不可破的规矩（都是隐私承诺，不是实现细节）：
 *
 *   1. **服务端不存明文**。备份是客户端加密后的一坨字节，这里原样收、原样还。
 *      本文件里**没有任何字段**能解出动作名、重量、体重 —— 那是设计的一部分。
 *   2. **不给 `account_id` 建任何反向索引**。它就是客户端算出来的密钥哈希，
 *      服务端拿它当主键用，但**不记录它来自哪台设备、哪个 IP**（日志纪律见 backend.mjs）。
 *   3. **删除就是删除**：`DELETE /v1/account` 会把账号、设备、备份一起清掉
 *      （政策里那句"云端的也删"必须有对应实现，否则就是假话）。
 *
 * 为什么用 `node:sqlite` 而不是 Postgres：为了**零依赖、本地就能跑通并自检**。
 * 接口按可替换设计（下面 `BackendStore` 的那几个方法），换 Postgres 只改这一个文件。
 * ⚠️ `node:sqlite` 在 Node 22 上会打印一句 ExperimentalWarning —— 这是已知的，
 * 上线前若要换成 Postgres 正好一起处理。
 */

import { DatabaseSync } from 'node:sqlite';

/** 备份包大小上限（8MB）。一次训练的加密备份远小于它；超了多半是走错了接口。 */
export const MAX_BACKUP_BYTES = 8 * 1024 * 1024;

export function createSqliteStore({ path = ':memory:' } = {}) {
  const db = new DatabaseSync(path);

  db.exec(`
    create table if not exists accounts (
      id          text primary key,   -- = 客户端算出的 account_id（密钥哈希）
      created_at  integer not null,
      deleted_at  integer null
    );
    create table if not exists devices (
      id           text primary key,
      account_id   text not null references accounts(id),
      name         text,
      last_seen_at integer not null
    );
    create table if not exists backups (
      account_id  text primary key references accounts(id),
      blob        blob not null,      -- **密文**，服务端看不懂
      bytes       integer not null,
      updated_at  integer not null
    );
  `);

  const now = () => Date.now();

  return {
    /** 建账号。**幂等**：同一 account_id 重复调用返回 false（表示"早就有了"）。 */
    createAccount(id) {
      const r = db
        .prepare('insert or ignore into accounts (id, created_at) values (?, ?)')
        .run(id, now());
      return r.changes > 0;
    },

    exists(id) {
      const row = db
        .prepare('select id from accounts where id = ? and deleted_at is null')
        .get(id);
      return row !== undefined;
    },

    /** 记一下有这台设备在用（只为"我在哪些设备上登过"这种展示，不做追踪）。 */
    touchDevice(accountId, deviceId, name) {
      if (!deviceId) return;
      db.prepare(
        `insert into devices (id, account_id, name, last_seen_at) values (?, ?, ?, ?)
         on conflict(id) do update set account_id = excluded.account_id,
                                      name = excluded.name,
                                      last_seen_at = excluded.last_seen_at`,
      ).run(deviceId, accountId, name ?? null, now());
    },

    deviceCount(accountId) {
      const row = db
        .prepare('select count(*) as n from devices where account_id = ?')
        .get(accountId);
      return Number(row.n);
    },

    /** 存（覆盖）备份包。**原样收、原样还** —— 这里不做任何解析。 */
    putBackup(accountId, blob) {
      const buf = Buffer.isBuffer(blob) ? blob : Buffer.from(blob);
      const at = now();
      db.prepare(
        `insert into backups (account_id, blob, bytes, updated_at) values (?, ?, ?, ?)
         on conflict(account_id) do update set blob = excluded.blob,
                                              bytes = excluded.bytes,
                                              updated_at = excluded.updated_at`,
      ).run(accountId, buf, buf.length, at);
      return { bytes: buf.length, updatedAt: at };
    },

    getBackup(accountId) {
      const row = db
        .prepare('select blob, bytes, updated_at from backups where account_id = ?')
        .get(accountId);
      if (!row) return null;
      return {
        blob: Buffer.from(row.blob),
        bytes: Number(row.bytes),
        updatedAt: Number(row.updated_at),
      };
    },

    /** 账号的元信息（**不含任何业务内容**）：有没有备份、多大、什么时候。 */
    accountInfo(accountId) {
      const acc = db
        .prepare('select created_at from accounts where id = ? and deleted_at is null')
        .get(accountId);
      if (!acc) return null;
      const b = db
        .prepare('select bytes, updated_at from backups where account_id = ?')
        .get(accountId);
      return {
        createdAt: Number(acc.created_at),
        bytes: b ? Number(b.bytes) : 0,
        updatedAt: b ? Number(b.updated_at) : null,
        devices: this.deviceCount(accountId),
      };
    },

    /** 注销：账号、设备、备份一起清掉（合规要求）。返回删了多少行。 */
    deleteAccount(id) {
      const b = db.prepare('delete from backups where account_id = ?').run(id);
      const d = db.prepare('delete from devices where account_id = ?').run(id);
      const a = db.prepare('delete from accounts where id = ?').run(id);
      return Number(a.changes) + Number(d.changes) + Number(b.changes);
    },

    stats() {
      const n = (sql) => Number(db.prepare(sql).get().n);
      return {
        accounts: n('select count(*) as n from accounts'),
        backups: n('select count(*) as n from backups'),
        bytes: n('select coalesce(sum(bytes), 0) as n from backups'),
      };
    },

    close() {
      db.close();
    },
  };
}
