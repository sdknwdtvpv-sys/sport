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
    -- 云备份多版本（M4b/Sprint 6）：每账号最多保留 N 份，seq 单调递增。
    -- ⚠️ seq 只增不减；恢复某一版只改 backups.current_seq，不新增版本。
    create table if not exists backup_versions (
      account_id text not null references accounts(id),
      seq        integer not null,
      blob       blob not null,       -- **密文**
      bytes      integer not null,
      created_at integer not null,
      primary key (account_id, seq)
    );
    create index if not exists backup_versions_account on backup_versions(account_id, seq desc);
  `);

  // 存量库迁移：backups 加 current_seq（老库只有"最新一份"，没有版本指针）。
  // SQLite 的 add column 是幂等的（先查 pragma），线上库直接跑这一句即可。
  {
    const cols = db.prepare('pragma table_info(backups)').all();
    if (!cols.some((c) => c.name === 'current_seq')) {
      db.exec('alter table backups add column current_seq integer');
    }
  }

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
        `insert into backups (account_id, blob, bytes, updated_at, current_seq)
         values (?, ?, ?, ?, 1)
         on conflict(account_id) do update set blob = excluded.blob,
                                              bytes = excluded.bytes,
                                              updated_at = excluded.updated_at,
                                              current_seq = coalesce(current_seq, 1)`,
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

    // ────────────────────────────────────────────── 云备份多版本（M4b）
    //
    // 存量兼容：老库只有 `backups` 一行（= 最新一份）。第一次用到这个账号时把它
    // **幂等回填**成 seq=1：`insert or ignore` + 主键保证重启/多次调用不会重复。
    // 现有 `PUT/GET /v1/backup` 的语义（原样收、原样还最新一份）一个字节都不变。

    /** 把老库的"最新一份"回填成 seq=1。返回 true = 这次真的写入了。 */
    ensureBackupVersion(accountId) {
      const has = db.prepare('select 1 as one from backup_versions where account_id = ? limit 1').get(accountId);
      if (has) return false;
      const b = db.prepare('select blob, bytes, updated_at from backups where account_id = ?').get(accountId);
      if (!b) return false;
      const r = db.prepare(
        `insert or ignore into backup_versions (account_id, seq, blob, bytes, created_at)
         values (?, 1, ?, ?, ?)`,
      ).run(accountId, b.blob, b.bytes, b.updated_at);
      db.prepare('update backups set current_seq = coalesce(current_seq, 1) where account_id = ?').run(accountId);
      return Number(r.changes) > 0;
    },

    /**
     * 上传并**同时**写"最新一份"与版本表（同一事务）。
     *
     * 返回 `{ok:true, bytes, updatedAt, seq, pruned}` 或
     * `{ok:false, status:413|409, error}`（服务端自己按权益算的 limits 由调用方传入）：
     *   * 单份超过 [maxBlobBytes] → 413；
     *   * 账号总量超过 [maxTotalBytes] → 409；
     *   * `maxVersions <= 1`（免费/降级）：只更新 seq=1，**旧版本不删**（用户数据不立刻删）；
     *   * `maxVersions > 1`（Ultra）：seq 递增，超过保留数的旧版本物理清理（保留最近 N 份）。
     */
    putBackupVersion({ accountId, blob, maxVersions, maxBlobBytes, maxTotalBytes }) {
      const buf = Buffer.isBuffer(blob) ? blob : Buffer.from(blob);
      const at = now();
      if (buf.length > maxBlobBytes) {
        return { ok: false, status: 413, error: `单份备份超过上限（${maxBlobBytes} 字节）` };
      }
      db.exec('BEGIN IMMEDIATE');
      try {
        this.ensureBackupVersion(accountId);
        const rows = db.prepare('select seq, bytes from backup_versions where account_id = ? order by seq desc')
          .all(accountId).map((r) => ({ seq: Number(r.seq), bytes: Number(r.bytes) }));
        const current = db.prepare('select current_seq, bytes from backups where account_id = ?').get(accountId);
        const replaceSeq = maxVersions <= 1 ? 1 : null;
        const baseTotal = rows.reduce((sum, r) => sum + (replaceSeq !== null && r.seq === replaceSeq ? 0 : r.bytes), 0);
        if (maxVersions > 1 && baseTotal + buf.length > maxTotalBytes) {
          db.exec('ROLLBACK');
          return { ok: false, status: 409, error: `账号总配额不够（上限 ${maxTotalBytes} 字节）` };
        }
        const seq = replaceSeq ?? Math.max(0, ...rows.map((r) => r.seq)) + 1;
        db.prepare(
          `insert into backup_versions (account_id, seq, blob, bytes, created_at)
           values (?, ?, ?, ?, ?)
           on conflict(account_id, seq) do update set blob = excluded.blob,
                                                      bytes = excluded.bytes,
                                                      created_at = excluded.created_at`,
        ).run(accountId, seq, buf, buf.length, at);
        let pruned = 0;
        if (maxVersions > 1) {
          const keep = db.prepare(
            'select seq from backup_versions where account_id = ? order by seq desc limit ?',
          ).all(accountId, maxVersions).map((r) => Number(r.seq));
          if (keep.length > 0) {
            const placeholders = keep.map(() => '?').join(',');
            const p = db.prepare(
              `delete from backup_versions where account_id = ? and seq not in (${placeholders})`,
            ).run(accountId, ...keep);
            pruned = Number(p.changes);
          }
        }
        db.prepare(
          `insert into backups (account_id, blob, bytes, updated_at, current_seq) values (?, ?, ?, ?, ?)
           on conflict(account_id) do update set blob = excluded.blob,
                                                bytes = excluded.bytes,
                                                updated_at = excluded.updated_at,
                                                current_seq = excluded.current_seq`,
        ).run(accountId, buf, buf.length, at, seq);
        db.exec('COMMIT');
        void current;
        return { ok: true, bytes: buf.length, updatedAt: at, seq, pruned };
      } catch (e) {
        db.exec('ROLLBACK');
        throw e;
      }
    },

    /** 列版本（**不含 blob**）。`includeHidden=false` 时只返回当前可见的（免费/降级只 1 份）。 */
    listBackupVersions(accountId, { includeHidden = false } = {}) {
      this.ensureBackupVersion(accountId);
      const b = db.prepare('select current_seq from backups where account_id = ?').get(accountId);
      const currentSeq = b?.current_seq == null ? null : Number(b.current_seq);
      let rows = db.prepare(
        'select seq, bytes, created_at from backup_versions where account_id = ? order by seq desc',
      ).all(accountId).map((r) => ({
        seq: Number(r.seq),
        bytes: Number(r.bytes),
        createdAtMs: Number(r.created_at),
        isLatest: currentSeq !== null && Number(r.seq) === currentSeq,
      }));
      if (!includeHidden && currentSeq !== null) rows = rows.filter((r) => r.isLatest);
      return rows;
    },

    /** 取指定版本的密文（越权/不存在/不可见都返回 null）。 */
    getBackupVersion(accountId, seq, { includeHidden = false } = {}) {
      this.ensureBackupVersion(accountId);
      const b = db.prepare('select current_seq from backups where account_id = ?').get(accountId);
      const currentSeq = b?.current_seq == null ? null : Number(b.current_seq);
      if (!includeHidden && (currentSeq === null || Number(seq) !== currentSeq)) return null;
      const row = db.prepare(
        'select blob, bytes, created_at from backup_versions where account_id = ? and seq = ?',
      ).get(accountId, Number(seq));
      if (!row) return null;
      return { blob: Buffer.from(row.blob), bytes: Number(row.bytes), createdAtMs: Number(row.created_at) };
    },

    /** 把指定版本设为最新（幂等：重复恢复同一版结果一样，不新增版本）。 */
    restoreBackupVersion(accountId, seq, { includeHidden = false } = {}) {
      this.ensureBackupVersion(accountId);
      const b = db.prepare('select current_seq from backups where account_id = ?').get(accountId);
      const currentSeq = b?.current_seq == null ? null : Number(b.current_seq);
      if (!includeHidden && (currentSeq === null || Number(seq) !== currentSeq)) return null;
      const row = db.prepare(
        'select blob, bytes from backup_versions where account_id = ? and seq = ?',
      ).get(accountId, Number(seq));
      if (!row) return null;
      const at = now();
      db.prepare(
        `update backups set blob = ?, bytes = ?, updated_at = ?, current_seq = ?
         where account_id = ?`,
      ).run(row.blob, row.bytes, at, Number(seq), accountId);
      return { seq: Number(seq), bytes: Number(row.bytes), updatedAt: at };
    },

    /** 测试/运维用：这个账号一共有多少版本（含降级后隐藏的旧版本）。 */
    backupVersionCount(accountId) {
      const row = db.prepare('select count(*) as n from backup_versions where account_id = ?').get(accountId);
      return Number(row.n);
    },

    /** 注销：账号、设备、备份、**版本**一起清掉（合规要求）。返回删了多少行。 */
    deleteAccount(id) {
      const v = db.prepare('delete from backup_versions where account_id = ?').run(id);
      const b = db.prepare('delete from backups where account_id = ?').run(id);
      const d = db.prepare('delete from devices where account_id = ?').run(id);
      const a = db.prepare('delete from accounts where id = ?').run(id);
      return Number(a.changes) + Number(d.changes) + Number(b.changes) + Number(v.changes);
    },

    stats() {
      const n = (sql) => Number(db.prepare(sql).get().n);
      return {
        accounts: n('select count(*) as n from accounts'),
        backups: n('select count(*) as n from backups'),
        bytes: n('select coalesce(sum(bytes), 0) as n from backups'),
        backupVersions: n('select count(*) as n from backup_versions'),
      };
    },

    close() {
      db.close();
    },
  };
}
