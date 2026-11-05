#!/usr/bin/env node
/**
 * 练了么 · 云备份多版本 + 配额自检（M4b / Sprint 6）
 *
 * 不联网、不依赖真 Apple：用内存/临时 sqlite + 假账号令牌，端到端走 HTTP。
 * 覆盖：
 *   * 存量回填幂等（老 `backups` 行 → seq=1，重启不重复）；
 *   * 免费 1 份（上传即替换）、Ultra 10 份（seq 单调、超出保留数物理清理）；
 *   * 单份/总量配额边界（413 / 409，服务端按权益算，不信客户端）；
 *   * 版本列表不含 blob；指定版本读取；越权/不可见 404；
 *   * 恢复为最新**幂等**（重复恢复同一版结果一样、不新增版本）；
 *   * 降级（权益过期）→ 只显示最新 1 份、停止新增、**旧版本不立刻删**；
 *   * 删除账号连带删版本；旧 PUT/GET 语义不变；会话令牌鉴权。
 *
 * 退出码：0 全过 / 1 有失败。
 */

import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { createHash } from 'node:crypto';

import { createAuth } from './auth.mjs';
import { createAuthStore } from './auth-store.mjs';
import { createBackend } from './backend.mjs';
import { createSqliteStore } from './backend-store.mjs';
import { createBackupVersions, PLAN_LIMITS } from './backup-versions.mjs';
import { createBilling } from './billing.mjs';
import { createBillingStore } from './billing-store.mjs';
import { createFileMailer } from './mailer.mjs';

const hash = (s) => createHash('sha256').update(s, 'utf8').digest('hex');

const MB = 1024 * 1024;
const day = 24 * 60 * 60 * 1000;

export async function selftest() {
  const dir = mkdtempSync(join(tmpdir(), 'lianleme-backup-versions-'));
  const failures = [];
  const check = (name, ok, detail = '') => {
    if (!ok) failures.push(name);
    console.log(`  ${ok ? '✓' : '✗'} ${name}${ok || !detail ? '' : ` —— ${detail}`}`);
  };

  const clock = Date.now();
  let now = clock;
  const path = join(dir, 'backend.sqlite');
  const store = createSqliteStore({ path });
  const billingStore = createBillingStore({ path: join(dir, 'billing.sqlite'), now: () => now });
  const billing = createBilling({ store: billingStore, now: () => now, log: () => {} });
  const versions = createBackupVersions({ store, billing, now: () => now, log: () => {} });
  const authStore = createAuthStore({ path: join(dir, 'auth.sqlite'), now: () => now });
  const auth = createAuth({
    store: authStore,
    backendStore: store,
    mailer: createFileMailer({ path: join(dir, 'mail.ndjson') }),
    secret: 'backup-versions-selftest',
    now: () => now,
  });
  const { server } = createBackend({ store, auth, billing, versions, log: () => {} });

  function makeAccount(name, { ultra = false } = {}) {
    const accountId = hash(`account:${name}`);
    const token = `lm1_${hash(`token:${name}`)}`;
    store.createAccount(accountId);
    authStore.bindAccount({
      accountId,
      email: `${name}@example.com`,
      salt: '00'.repeat(16),
      kdf: '{}',
      verifier: 'v'.repeat(40),
      wrapped: 'W'.repeat(16),
    });
    authStore.createToken({ tokenHash: hash(token), accountId, deviceId: `dev_${name}` });
    if (ultra) {
      billingStore.applyStoreTransaction({
        accountId,
        product: 'com.sdknwdtvpv.lianleme.ultra.yearly',
        source: 'apple',
        originalTxn: `otx:${name}`,
        expiresAt: clock + 30 * day,
        environment: 'Production',
        transactionId: `tx:${name}`,
        atMs: clock,
      });
    }
    return { accountId, token, headers: { authorization: `Bearer ${token}` } };
  }

  const A = makeAccount('a', { ultra: true });
  const B = makeAccount('b');
  const L = makeAccount('legacy');

  let base = null;
  const request = (method, p, { body, headers = {}, raw = false } = {}) => fetch(`${base}${p}`, {
    method,
    headers: raw ? { ...headers } : { 'content-type': 'application/json', ...headers },
    body: raw ? body : (body === undefined ? undefined : JSON.stringify(body)),
  });
  const post = (p, body, headers) => request('POST', p, { body, headers });
  const get = (p, headers) => request('GET', p, { headers });
  const putRaw = (body, headers) => request('PUT', '/v1/backup', { body, headers, raw: true });

  try {
    // ── 0. 存量回填幂等（独立库，模拟"重启"）──────────────────────────
    {
      const p2 = join(dir, 'legacy.sqlite');
      const s1 = createSqliteStore({ path: p2 });
      s1.createAccount('acc_legacy');
      s1.putBackup('acc_legacy', Buffer.from('old-ciphertext'));
      check('老库回填：第一次写入 seq=1', s1.ensureBackupVersion('acc_legacy') === true);
      check('老库回填：第二次不再写（幂等）', s1.ensureBackupVersion('acc_legacy') === false);
      const list1 = s1.listBackupVersions('acc_legacy', { includeHidden: true });
      check('老库回填：版本只有 1 条且 is_latest', list1.length === 1 && list1[0].seq === 1 && list1[0].isLatest);
      s1.close();
      const s2 = createSqliteStore({ path: p2 });
      check('重启后再回填仍幂等（不重复插）', s2.ensureBackupVersion('acc_legacy') === false);
      check('重启后版本仍是 1 条', s2.listBackupVersions('acc_legacy', { includeHidden: true }).length === 1);
      check('重启后 GET 最新一份原样', s2.getBackup('acc_legacy')?.blob.toString() === 'old-ciphertext');
      s2.close();
    }

    // ── 1. 生产配额常量（与方案 §二 权益 5/6 对齐）───────────────────
    check('配额常量：Ultra 10 份 / 32MB 单份 / 256MB 总量',
      PLAN_LIMITS.ultra.maxVersions === 10
      && PLAN_LIMITS.ultra.maxBlobBytes === 32 * MB
      && PLAN_LIMITS.ultra.maxTotalBytes === 256 * MB,
      JSON.stringify(PLAN_LIMITS.ultra));
    check('配额常量：免费 1 份 / 8MB', PLAN_LIMITS.free.maxVersions === 1
      && PLAN_LIMITS.free.maxBlobBytes === 8 * MB, JSON.stringify(PLAN_LIMITS.free));

    await new Promise((r) => server.listen(0, '127.0.0.1', r));
    base = `http://127.0.0.1:${server.address().port}`;

    // ── 2. 未登录 / 老设备凭据：版本端点一律 401 ─────────────────────
    {
      const no = await get('/v1/billing/backups');
      check('未登录列版本 → 401', no.status === 401, `实际 ${no.status}`);
      const legacy = await get('/v1/billing/backups', { authorization: `Bearer ${A.accountId}` });
      check('老 `Bearer <account_id>` → 401（多版本只认会话令牌）', legacy.status === 401, `实际 ${legacy.status}`);
    }

    // ── 3. 旧 PUT/GET 语义不变 + 免费 1 份（上传即替换）──────────────
    {
      const r1 = await putRaw(Buffer.from('free-v1'), B.headers);
      const b1 = await r1.json();
      check('PUT /v1/backup 响应形状与老客户端约定一致（bytes/updated_at）',
        r1.status === 200 && typeof b1.bytes === 'number' && typeof b1.updated_at === 'number', JSON.stringify(b1));
      const g1 = await get('/v1/backup', B.headers);
      check('GET /v1/backup 原样还最新一份', (await g1.text()) === 'free-v1');
      const r2 = await putRaw(Buffer.from('free-v2'), B.headers);
      check('免费第二次上传仍 200（覆盖，不报错）', r2.status === 200, `实际 ${r2.status}`);
      const list = await (await get('/v1/billing/backups', B.headers)).json();
      check('免费只有 1 份版本（seq=1、is_latest）',
        list.ultra === false && list.versions.length === 1 && list.versions[0].seq === 1
        && list.versions[0].is_latest === true, JSON.stringify(list));
      check('免费覆盖后最新一份是新内容', (await (await get('/v1/backup', B.headers)).text()) === 'free-v2');
      check('免费第二次覆盖不会留下第二条版本行', store.backupVersionCount(B.accountId) === 1);
      const tooBig = await putRaw(Buffer.alloc(8 * MB + 1), B.headers);
      check('免费单份 >8MB → 413 且原因可读', tooBig.status === 413, `实际 ${tooBig.status}`);
    }

    // ── 4. Ultra 多版本：seq 单调、列表无 blob、指定版本可读 ─────────
    {
      for (let i = 1; i <= 3; i += 1) {
        const r = await putRaw(Buffer.from(`ultra-v${i}`), A.headers);
        check(`Ultra 第 ${i} 次上传 200`, r.status === 200, `实际 ${r.status}`);
      }
      const list = await (await get('/v1/billing/backups', A.headers)).json();
      check('Ultra 列表 3 个版本、seq 递减返回（3,2,1）',
        list.versions.map((v) => v.seq).join(',') === '3,2,1', JSON.stringify(list.versions));
      check('列表不含 blob（只有 seq/bytes/created_at/is_latest）',
        list.versions.every((v) => !('blob' in v)), JSON.stringify(list.versions[0]));
      check('最新一份标记正确（seq=3）', list.versions[0].is_latest === true && list.versions[1].is_latest === false);
      const v2 = await get('/v1/backup/versions/2', A.headers);
      check('GET 指定版本 2 → 200 且密文正确', v2.status === 200 && (await v2.text()) === 'ultra-v2', `实际 ${v2.status}`);
      const cross = await get('/v1/backup/versions/2', B.headers);
      check('B 读 A 的版本 → 404（越权不泄露存在性）', cross.status === 404, `实际 ${cross.status}`);
      const freeOwn = await get('/v1/backup/versions/1', B.headers);
      check('免费账号读自己最新一份 → 200（它只有这一份）',
        freeOwn.status === 200 && (await freeOwn.text()) === 'free-v2', `实际 ${freeOwn.status}`);
    }

    // ── 5. 恢复为最新：幂等、不新增版本 ────────────────────────────
    {
      const before = store.backupVersionCount(A.accountId);
      const r1 = await post('/v1/billing/backups/restore', { seq: 1 }, A.headers);
      check('恢复 seq=1 → 200', r1.status === 200, `实际 ${r1.status}`);
      check('恢复后最新一份 = 老内容', (await (await get('/v1/backup', A.headers)).text()) === 'ultra-v1');
      const r2 = await post('/v1/billing/backups/restore', { seq: 1 }, A.headers);
      check('重复恢复同一版 → 200（幂等）', r2.status === 200, `实际 ${r2.status}`);
      check('恢复不新增版本（版本数不变）', store.backupVersionCount(A.accountId) === before);
      const list = await (await get('/v1/billing/backups', A.headers)).json();
      check('恢复后 is_latest 指向 seq=1', list.versions.find((v) => v.is_latest)?.seq === 1, JSON.stringify(list.versions));
      const bad = await post('/v1/billing/backups/restore', { seq: 99 }, A.headers);
      check('恢复不存在的版本 → 404', bad.status === 404, `实际 ${bad.status}`);
    }

    // ── 6. 保留 10 份：第 11 次上传物理清理最旧 ─────────────────────
    {
      for (let i = 4; i <= 11; i += 1) await putRaw(Buffer.from(`ultra-v${i}`), A.headers);
      const list = await (await get('/v1/billing/backups', A.headers)).json();
      check('Ultra 最多保留 10 份（第 11 次上传后列表 10 条）', list.versions.length === 10, String(list.versions.length));
      check('保留的是最近 10 份（seq 11..2，最旧 seq=1 被清理）',
        list.versions.map((v) => v.seq).join(',') === '11,10,9,8,7,6,5,4,3,2', list.versions.map((v) => v.seq).join(','));
      check('物理清理后库里也只有 10 条', store.backupVersionCount(A.accountId) === 10);
      const gone = await get('/v1/backup/versions/1', A.headers);
      check('被清理的旧版本 → 404', gone.status === 404, `实际 ${gone.status}`);
    }

    // ── 7. 配额/大小边界（独立小配额实例，不靠 33MB 的内存）──────────
    {
      const small = createBackupVersions({
        store,
        billing: { hasUltra: () => true },
        now: () => now,
        planLimits: {
          free: PLAN_LIMITS.free,
          ultra: { maxVersions: 10, maxBlobBytes: 100, maxTotalBytes: 150 },
        },
      });
      const Q = makeAccount('quota');
      const q1 = small.putBackup(Q.accountId, Buffer.alloc(80));
      check('总配额：80/150 可写', q1.ok === true, JSON.stringify(q1));
      const q2 = small.putBackup(Q.accountId, Buffer.alloc(80));
      check('总配额：再加 80 超 150 → 409 且原因可读',
        q2.ok === false && q2.status === 409 && typeof q2.error === 'string', JSON.stringify(q2));
      const q3 = small.putBackup(Q.accountId, Buffer.alloc(101));
      check('单份超限 → 413 且原因可读',
        q3.ok === false && q3.status === 413 && typeof q3.error === 'string', JSON.stringify(q3));
      const q4 = small.putBackup(Q.accountId, Buffer.alloc(60));
      check('总量内更小的一份可以写', q4.ok === true, JSON.stringify(q4));
    }

    // ── 8. 降级：只显示最新 1 份、停止新增、旧版本不立刻删 ─────────
    {
      now = clock + 40 * day; // 权益过期
      const list = await (await get('/v1/billing/backups', A.headers)).json();
      check('权益过期后：ultra=false 且列表只剩最新 1 份',
        list.ultra === false && list.versions.length === 1, JSON.stringify(list));
      const hiddenCount = store.backupVersionCount(A.accountId);
      check('降级不立刻删旧版本（行还在，只是不显示）', hiddenCount === 10, String(hiddenCount));
      const up = await putRaw(Buffer.from('after-expiry'), A.headers);
      check('降级后仍可上传（只覆盖最新一份，200）', up.status === 200, `实际 ${up.status}`);
      const list2 = await (await get('/v1/billing/backups', A.headers)).json();
      check('降级后上传不新增版本（仍是 1 条可见）', list2.versions.length === 1, JSON.stringify(list2));
      const hiddenVersion = await get('/v1/backup/versions/2', A.headers);
      check('降级后读隐藏的旧版本 → 404（只保留最新 1 份可见）', hiddenVersion.status === 404, `实际 ${hiddenVersion.status}`);
      const restore = await post('/v1/billing/backups/restore', { seq: 2 }, A.headers);
      check('免费（降级）账号恢复旧版本 → 403（多版本是 Ultra 权益）', restore.status === 403, `实际 ${restore.status}`);
      now = clock; // 复位，后续删除测试用
    }

    // ── 9. 删除账号连带删版本 ───────────────────────────────────────
    {
      const del = await request('DELETE', '/v1/account', { headers: A.headers });
      check('删除账号 200', del.status === 200, `实际 ${del.status}`);
      check('删除账号后版本行 = 0', store.backupVersionCount(A.accountId) === 0);
      check('删除账号后 backing 最新一份也没了', store.getBackup(A.accountId) === null);
    }
  } finally {
    await new Promise((r) => server.close(r));
    store.close();
    billingStore.close();
    authStore.close();
    rmSync(dir, { recursive: true, force: true });
  }

  if (failures.length) {
    console.error(`\n✗ 云备份多版本自检失败 ${failures.length} 项：`);
    for (const f of failures) console.error(`  · ${f}`);
    return 1;
  }
  console.log('✓ 云备份多版本自检通过（回填幂等 · 免费1/Ultra10 · 配额413/409 · 越权404 · 恢复幂等 · 降级不删 · 注销连带）');
  return 0;
}

if (process.argv[1] && process.argv[1].endsWith('backup-versions.selftest.mjs')) {
  process.exit(await selftest());
}
