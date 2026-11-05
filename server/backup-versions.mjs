#!/usr/bin/env node
/**
 * 练了么 · 云备份多版本 + 配额（M4b / Sprint 6）
 *
 * 设计：`docs/plan-membership-2026-10-10.md` §二（权益 5/6）、§4.1（降级不删数据）、
 * `docs/backend-design.md` §十（服务端计费）。一句话：**多版本是 Ultra 权益，配额由服务端按权益算**。
 *
 * 三条边界：
 *   1. **存量兼容**：老的 `PUT/GET /v1/backup` 语义（原样收、原样还"最新一份"）一个字节都不变；
 *      新上传同时写最新一份 + 版本表；老库第一次碰到时把那一行幂等回填成 seq=1。
 *   2. **服务端自己判权益**：不信客户端传的"我是 Ultra"。免费 = 1 份 / 8MB；
 *      Ultra = 10 份 / 单份 32MB / 账号总 256MB。单份超限 → 413；总量超限 → 409。
 *   3. **降级不立刻删数据**：权益过期/退款后**停止新增版本**、列表只显示最新 1 份；
 *      已存在的旧版本行**保留**（不删），清理策略见 `docs/backend-design.md` §十。
 *      删除账号时版本**连带删除**。
 */

/** 单份/总量的上限（与方案 §二 的权益 6 一致）。 */
export const ULTRA_MAX_VERSIONS = 10;
export const ULTRA_MAX_BLOB_BYTES = 32 * 1024 * 1024;
export const ULTRA_MAX_TOTAL_BYTES = 256 * 1024 * 1024;

/** 免费档沿用现有 `MAX_BACKUP_BYTES`（8MB）/ 1 份。 */
export const FREE_MAX_VERSIONS = 1;
export const FREE_MAX_BLOB_BYTES = 8 * 1024 * 1024;
export const FREE_MAX_TOTAL_BYTES = 8 * 1024 * 1024;

export const PLAN_LIMITS = Object.freeze({
  free: Object.freeze({
    maxVersions: FREE_MAX_VERSIONS,
    maxBlobBytes: FREE_MAX_BLOB_BYTES,
    maxTotalBytes: FREE_MAX_TOTAL_BYTES,
  }),
  ultra: Object.freeze({
    maxVersions: ULTRA_MAX_VERSIONS,
    maxBlobBytes: ULTRA_MAX_BLOB_BYTES,
    maxTotalBytes: ULTRA_MAX_TOTAL_BYTES,
  }),
});

/**
 * @param {{
 *   store: ReturnType<import('./backend-store.mjs').createSqliteStore>,
 *   billing?: {hasUltra: (accountId: string) => boolean} | null,
 *   now?: () => number,
 *   planLimits?: typeof PLAN_LIMITS,
 *   log?: (m: string) => void,
 * }} opts
 */
export function createBackupVersions({
  store,
  billing = null,
  now = () => Date.now(),
  planLimits = PLAN_LIMITS,
  log = () => {},
} = {}) {
  if (!store) throw new Error('createBackupVersions 需要 backend store');

  const nowMs = () => Number(now());
  const hasUltra = (accountId) => (accountId && billing ? billing.hasUltra(accountId) : false);
  const limitsFor = (accountId) => (hasUltra(accountId) ? planLimits.ultra : planLimits.free);

  /**
   * 上传入口（`PUT /v1/backup` 调它）。返回 store 的结果：
   * `{ok:true,...}` / `{ok:false,status,error}`。
   */
  function putBackup(accountId, blob) {
    const limits = limitsFor(accountId);
    const r = store.putBackupVersion({ accountId, blob, ...limits });
    if (r.ok) {
      log(`备份版本已写：seq=${r.seq} bytes=${r.bytes} pruned=${r.pruned}${hasUltra(accountId) ? '（Ultra）' : ''}`);
    }
    return r;
  }

  /** 列版本（不含 blob）；免费/降级只看得到最新一份。 */
  function listVersions(accountId) {
    const ultra = hasUltra(accountId);
    return {
      ultra,
      versions: store.listBackupVersions(accountId, { includeHidden: ultra }),
      limits: limitsFor(accountId),
    };
  }

  /**
   * 处理需要登录的版本端点（由 `backend.mjs` 在鉴权闸门之后调用）。
   *
   *   GET  /v1/billing/backups              列版本（**不含 blob**）
   *   GET  /v1/backup/versions/:seq         取指定版本密文（越权/不可见 → 404）
   *   POST /v1/billing/backups/restore      把指定版本设为最新（**幂等**）
   *
   * ⚠️ 只认**会话令牌**（`authVia === 'token'`）：老的 `Bearer <account_id>` 是设备凭据，
   * 不能用来证明"这个账号现在有 Ultra"。
   */
  async function tryHandle({ req, res, p, accountId, authVia, say, json, readBody }) {
    const isList = p === '/v1/billing/backups';
    const isRestore = p === '/v1/billing/backups/restore';
    const versionMatch = /^\/v1\/backup\/versions\/(\d+)$/.exec(p);
    if (!isList && !isRestore && !versionMatch) return false;

    if (authVia !== 'token' || !accountId) {
      say(401);
      json(res, 401, { error: '云备份多版本需要登录（会话令牌）' });
      return true;
    }
    const ultra = hasUltra(accountId);
    const limits = limitsFor(accountId);

    if (isList) {
      if (req.method !== 'GET') {
        say(405);
        json(res, 405, { error: '只支持 GET' });
        return true;
      }
      const r = listVersions(accountId);
      say(200);
      json(res, 200, {
        ok: true,
        ultra: r.ultra,
        versions: r.versions.map((v) => ({
          seq: v.seq,
          bytes: v.bytes,
          created_at: v.createdAtMs,
          is_latest: v.isLatest,
        })),
        limits: {
          max_versions: r.limits.maxVersions,
          max_blob_bytes: r.limits.maxBlobBytes,
          max_total_bytes: r.limits.maxTotalBytes,
        },
      });
      return true;
    }

    if (versionMatch) {
      if (req.method !== 'GET') {
        say(405);
        json(res, 405, { error: '只支持 GET' });
        return true;
      }
      const seq = Number(versionMatch[1]);
      // 越权（不是这个账号的）/ 免费账号看旧版本 / 不存在 —— 一律 404，不泄露"有没有"。
      const v = store.getBackupVersion(accountId, seq, { includeHidden: ultra });
      if (!v) {
        say(404);
        json(res, 404, { error: '没有这个备份版本' });
        return true;
      }
      res.writeHead(200, {
        'content-type': 'application/octet-stream',
        'content-length': String(v.bytes),
        'x-backup-seq': String(seq),
        'x-backup-created-at': String(v.createdAtMs),
      });
      res.end(v.blob);
      say(200);
      return true;
    }

    // restore
    if (req.method !== 'POST') {
      say(405);
      json(res, 405, { error: '只支持 POST' });
      return true;
    }
    if (!ultra) {
      say(403);
      json(res, 403, { error: '云备份多版本是 Ultra 权益；当前只保留最新 1 份' });
      return true;
    }
    const { body, tooLarge } = await readBody(req, 4096);
    if (tooLarge) {
      say(413);
      json(res, 413, { error: '请求体太大' });
      return true;
    }
    let payload = null;
    try {
      payload = JSON.parse(body?.toString('utf8') ?? '');
    } catch {
      payload = null;
    }
    const seq = Number(payload?.seq);
    if (!Number.isInteger(seq) || seq <= 0) {
      say(400);
      json(res, 400, { error: '需要 {"seq": 版本号}' });
      return true;
    }
    const restored = store.restoreBackupVersion(accountId, seq, { includeHidden: true });
    if (!restored) {
      say(404);
      json(res, 404, { error: '没有这个备份版本' });
      return true;
    }
    log(`备份恢复：seq=${seq} → 最新（幂等）`);
    say(200);
    json(res, 200, { ok: true, seq: restored.seq, bytes: restored.bytes, updated_at: restored.updatedAt });
    return true;
  }

  return {
    putBackup,
    listVersions,
    tryHandle,
    hasUltra,
    planLimits,
    _internals: { limitsFor, nowMs },
  };
}
