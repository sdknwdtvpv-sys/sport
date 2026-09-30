#!/usr/bin/env node
/**
 * 练了么 · 极薄后端的自检（账号 / 备份 / 删除 + 三条隐私承诺）
 *
 * **为什么要一条自检**：后端的错是"看起来很确定"的那种错 ——
 * 备份收少了一半、删除其实没删、日志把凭据打了出去，界面都看不出来。
 * 所以这条自检盯四件事：
 *
 *   1. **接口通**：建账号（幂等）、上传、下载、注销，都真的走过一次 HTTP
 *   2. **原样收发**：上传什么字节，下载就得到什么字节（服务端不解析、不改写）
 *   3. **删除是真的删**：注销后账号查不到、备份读不到、库里也不留（合规要求）
 *   4. **三条承诺**：元信息接口里**不含任何备份字节**；
 *      日志里**不出现 Authorization**；服务端**不记录 IP**
 *
 * 退出码：0 全过 / 1 有失败。
 */

import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createBackend } from './backend.mjs';
import { createSqliteStore, MAX_BACKUP_BYTES } from './backend-store.mjs';

export async function selftest() {
  const dir = mkdtempSync(join(tmpdir(), 'lianleme-backend-'));
  const store = createSqliteStore({ path: join(dir, 'test.sqlite') });
  // 日志注入：既拿到了服务端的日志（用来断言不泄漏凭据），
  // 又不会吞掉自检自己的输出
  const logged = [];
  const { server } = createBackend({ store, log: (m) => logged.push(m) });

  const failures = [];
  const check = (name, ok, detail = '') => {
    if (ok) console.log(`  ✓ ${name}`);
    else { failures.push(name); console.log(`  ✗ ${name}${detail ? ` —— ${detail}` : ''}`); }
  };

  try {
    await new Promise((r) => server.listen(0, '127.0.0.1', r));
    const base = `http://127.0.0.1:${server.address().port}`;

    const ACCOUNT = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
    const SECRET_MARK = 'PLAINTEXT-卧推-60kg-绝不该被服务端读懂';

    // ---- 1. 建账号 ----
    const created = await fetch(`${base}/v1/account`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ account_id: ACCOUNT, device_id: 'dev_1', device_name: '我的手机' }),
    });
    check('建账号返回 201', created.status === 201, `实际 ${created.status}`);

    const again = await fetch(`${base}/v1/account`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ account_id: ACCOUNT, device_id: 'dev_1' }),
    });
    check('同一个 account_id 再建是幂等的（200 而不是 500/重复行）',
      again.status === 200 && (await again.json()).created === false);

    const bad = await fetch(`${base}/v1/account`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ account_id: '不是十六进制' }),
    });
    check('非法 account_id 被拒（400）', bad.status === 400, `实际 ${bad.status}`);

    // ---- 2. 鉴权 ----
    const noAuth = await fetch(`${base}/v1/account/me`);
    check('没有 Authorization 时 401', noAuth.status === 401, `实际 ${noAuth.status}`);

    const wrong = await fetch(`${base}/v1/account/me`, {
      headers: { authorization: 'Bearer 00000000000000000000000000000000' },
    });
    check('不存在的账号 404（恢复码算错时会走到这里）', wrong.status === 404, `实际 ${wrong.status}`);

    const auth = { authorization: `Bearer ${ACCOUNT}` };

    const me0 = await (await fetch(`${base}/v1/account/me`, { headers: auth })).json();
    check('还没备份时 bytes = 0（不编造数字）', me0.bytes === 0 && me0.updatedAt === null);

    // ---- 3. 上传/下载：原样收发 ----
    // 真实场景里这是客户端加密后的密文；这里塞一个醒目明文标记，用来验证
    // "服务端只是原样搬字节" —— 它既不该改，也不该在任何地方把它解析出来。
    const blob = Buffer.concat([
      Buffer.from(SECRET_MARK, 'utf8'),
      Buffer.from(Array.from({ length: 5000 }, (_, i) => i % 251)),
    ]);
    const put = await fetch(`${base}/v1/backup`, { method: 'PUT', headers: auth, body: blob });
    const putJson = await put.json();
    check('上传备份返回字节数', put.status === 200 && putJson.bytes === blob.length,
      `实际 ${put.status} / ${putJson.bytes}`);

    const got = Buffer.from(await (await fetch(`${base}/v1/backup`, { headers: auth })).arrayBuffer());
    check('下载得到**逐字节一致**的备份（服务端不解析、不改写）', got.equals(blob),
      `上传 ${blob.length} 字节，下载 ${got.length} 字节`);

    const me1 = await (await fetch(`${base}/v1/account/me`, { headers: auth })).json();
    check('元信息里有大小与时间', me1.bytes === blob.length && typeof me1.updatedAt === 'number');
    check('元信息里**没有任何备份内容**（只有元数据）',
      JSON.stringify(me1).length < 300 && !JSON.stringify(me1).includes(SECRET_MARK));

    // ---- 4. 上限 ----
    const huge = Buffer.alloc(MAX_BACKUP_BYTES + 1024, 7);
    const tooBig = await fetch(`${base}/v1/backup`, { method: 'PUT', headers: auth, body: huge });
    check(`超过上限（${MAX_BACKUP_BYTES} 字节）返回 413`, tooBig.status === 413, `实际 ${tooBig.status}`);

    // ---- 5. 日志纪律 ----
    const joined = logged.join('\n');
    check('日志里没有出现 Authorization 凭据', !joined.includes(ACCOUNT));
    check('日志里没有出现 IP / 端口等来源信息', !/127\.0\.0\.1|:\d{2,5}\b/.test(joined),
      joined.split('\n').slice(0, 2).join(' | '));

    // ---- 6. 注销：真删 ----
    const del = await (await fetch(`${base}/v1/account`, { method: 'DELETE', headers: auth })).json();
    check('注销返回删除行数', typeof del.deleted === 'number' && del.deleted > 0);

    const meAfter = await fetch(`${base}/v1/account/me`, { headers: auth });
    check('注销后账号查不到（404）', meAfter.status === 404, `实际 ${meAfter.status}`);
    const backupAfter = await fetch(`${base}/v1/backup`, { headers: auth });
    check('注销后备份读不到（404）', backupAfter.status === 404, `实际 ${backupAfter.status}`);

    const stats = store.stats();
    check('库里确实不留备份（合规：删除就是删除）',
      stats.backups === 0 && stats.accounts === 0, JSON.stringify(stats));
  } finally {
    await new Promise((r) => server.close(r));
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }

  if (failures.length) {
    console.error(`\n✗ 后端自检失败 ${failures.length} 项：`);
    for (const f of failures) console.error(`  · ${f}`);
    return 1;
  }
  console.log('✓ 后端自检通过（账号幂等 · 逐字节收发 · 上限 · 删除彻底 · 日志不漏凭据）');
  return 0;
}

if (process.argv[1] && process.argv[1].endsWith('backend.selftest.mjs')) {
  process.exit(await selftest());
}
