#!/usr/bin/env node
/**
 * 练了么 · 极薄后端（**零依赖**，只用 node:http + node:sqlite）
 *
 * 设计见 `docs/backend-design.md`。一句话：**只做账号、备份、删除**，
 * 不做任何服务端计算 —— 渐进建议与 PR 判定永远在客户端算（健身房地下层没信号）。
 *
 * 接口：
 *   POST   /v1/account        体：{"account_id":"…","device_id":"…","device_name":"…"}
 *                             → 201 新建 / 200 已存在（幂等）
 *   GET    /v1/account/me     → 200 {"exists":true,"bytes":N,"updatedAt":…,"devices":N}
 *   PUT    /v1/backup         体：**原始密文**（application/octet-stream，≤8MB）
 *                             → 200 {"bytes":N,"updated_at":…}
 *   GET    /v1/backup         → 200 原始密文（原样还）
 *   DELETE /v1/account        → 200 {"deleted":N}  （账号+设备+备份一起删）
 *   GET    /healthz           → 200 {"ok":true,"accounts":N,"backups":N}
 *
 * 账号体系（**可选**，配了邮件通道才有；见 `docs/plan-account-login.md`）：
 *   POST   /v1/auth/salt            体：{"email"} → 200 {"salt","kdf"}（不存在的邮箱回**假盐**）
 *   POST   /v1/auth/code            体：{"email","purpose"} → 200 {"ok":true}（发 6 位验证码）
 *   POST   /v1/auth/register        体：{email,code,verifier,wrapped,account_id,salt,kdf,…}
 *                                   → 201 {"account_id","token"}
 *   POST   /v1/auth/login           体：{email,verifier} → 200 {"account_id","token","wrapped","salt","kdf"}
 *   POST   /v1/auth/reset           体：{email,code,account_id,verifier,wrapped,salt,kdf}
 *                                   → 200 {"account_id","token"}（忘口令 → 用恢复码设新口令）
 *   POST   /v1/auth/logout          头：Bearer 令牌 → 200 {"revoked":N}
 *   POST   /v1/auth/change-password 体：{current_verifier,verifier,wrapped,salt,kdf} → 200
 *   GET    /v1/auth/me              头：Bearer 令牌 → 200 {"email","account_id",…}
 *
 * 鉴权：`Authorization: Bearer <凭据>`。凭据有两种解释 —— **先当会话令牌**
 * （`/v1/auth/login` 发的那串），解释不出来再按老规矩当 `account_id`
 * （= 客户端密钥的哈希；账号体系上线之前只有这一种）。服务端仍然不认识别的身份。
 *
 * 三条安全纪律（写在代码里，因为它们是承诺）：
 *   1. **日志绝不打印 `Authorization`**（它等同于凭据）。下面所有日志只打方法与路径。
 *   2. **服务端不解析备份内容**：原样收、原样还，没有"顺手看一眼"的代码。
 *   3. **不做 IP 记录**：这台服务不知道也不想知道请求从哪来。
 *
 * 生产部署要点（阶段 4，需要用户买服务器/域名/备案）：
 *   * 必须走 **HTTPS**（凭据在 Authorization 头里）
 *   * 反向代理（Caddy/nginx）负责 TLS 与请求体上限；本进程只管业务
 *   * 落库文件放在持久卷上；`node:sqlite` 换 Postgres 只改 backend-store.mjs
 *
 * 用法：
 *   node server/backend.mjs --port 8790 --db server/data/backend.sqlite
 *   node server/backend.selftest.mjs      # 端到端自检（verify.sh 会跑）
 */

import { createServer } from 'node:http';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createSqliteStore, MAX_BACKUP_BYTES } from './backend-store.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** account_id 的形状：客户端算出的 32 字节哈希，用十六进制表示 */
const ACCOUNT_ID_RE = /^[0-9a-f]{32,64}$/;

function json(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' });
  res.end(body);
}

/**
 * 把请求体读成 Buffer，**超过上限就不再缓存**（内存始终有界），
 * 但**继续把请求读完**再回 413。
 *
 * ⚠️ 这里踩过一个坑：第一版超限时直接 `req.destroy()` —— 客户端拿到的是
 * "socket 被对端关闭"而不是一个干净的 413（自检里当场炸了）。掐断连接**不是**
 * 拒绝请求的正确姿势：HTTP 语义上要先给答复。
 *
 * 生产上真正的请求体上限由反向代理把关（见文件头）；这里的上限是"业务上的合理边界"。
 */
function readBody(req, limit = MAX_BACKUP_BYTES) {
  return new Promise((resolve) => {
    const chunks = [];
    let total = 0;
    let tooLarge = false;
    req.on('data', (c) => {
      total += c.length;
      if (total > limit) {
        // 不再缓存（内存有界），但要让流继续走到 end
        if (!tooLarge) { tooLarge = true; chunks.length = 0; }
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => resolve(tooLarge ? { tooLarge: true } : { body: Buffer.concat(chunks) }));
    req.on('error', () => resolve(tooLarge ? { tooLarge: true } : { body: null }));
  });
}

const bearer = (req) => {
  const h = req.headers['authorization'] ?? '';
  const m = /^Bearer\s+(.+)$/i.exec(h);
  return m ? m[1].trim() : null;
};

export function createBackend({ store, log = console.log, auth = null }) {
  const server = createServer(async (req, res) => {
    const url = new URL(req.url, 'http://127.0.0.1');
    const p = url.pathname;
    // ⚠️ 只打方法与路径：**绝不打 Authorization、绝不打 IP**
    // 日志走可注入的 `log`：自检要**检查日志里有没有泄漏凭据**，
    // 而猴子补丁 `console.log` 会把自检自己的输出也吞掉（第一版就是这么错的）。
    const say = (status) => log(`${req.method} ${p} → ${status}`);

    try {
      // ---- 健康检查（不需要鉴权）----
      if (req.method === 'GET' && p === '/healthz') {
        say(200);
        return json(res, 200, { ok: true, ...store.stats(), ...(auth ? auth.store.stats() : {}) });
      }

      // ---- 账号体系没启用时，`/v1/auth/*` 要**明确**回 404 ----
      // 不写这一段的话，请求会落到下面那道"账号必须存在"的闸门后面，
      // 回一句 `401 缺少或非法的 Authorization: Bearer` —— 对用户毫无意义
      // （2026-10-06 部署时在线上实测到过：老服务端 + 新客户端就是这个症状）。
      if (!auth && p.startsWith('/v1/auth/')) {
        say(404);
        return json(res, 404, { error: '账号体系没有启用（服务端还没配邮件）' });
      }

      // ---- 账号体系（注册 / 登录 / 会话 / 改口令 / 重置 / 注销会话）----
      // ⚠️ **必须写在下面那道"账号必须存在"的闸门之前**：否则会变成"要先登录才能登录"。
      // 什么时候有账号体系由调用方决定（没配 SMTP 就没有）——没配时这几个路径会落到 404。
      if (auth && (await auth.tryHandle({ req, res, p, say, json, readBody }))) return;

      // ---- 建账号（幂等）----
      if (req.method === 'POST' && p === '/v1/account') {
        const { body } = await readBody(req, 4096);
        let payload = null;
        try { payload = JSON.parse(body?.toString('utf8') ?? ''); } catch { /* 下面统一报错 */ }
        const id = payload?.account_id;
        if (typeof id !== 'string' || !ACCOUNT_ID_RE.test(id)) {
          say(400);
          return json(res, 400, { error: 'account_id 必须是 32–64 位十六进制' });
        }
        const created = store.createAccount(id);
        store.touchDevice(id, payload?.device_id, payload?.device_name);
        say(created ? 201 : 200);
        return json(res, created ? 201 : 200, { created });
      }

      // ---- 以下都要鉴权 ----
      // 凭据有两种解释：**先当会话令牌**（账号体系上线后客户端用的就是这个），
      // 再按老规矩当 `account_id`（恢复码算出来的哈希；正式包还没有账号体系那一版就靠它）。
      // 两种都解释不出来 → 401；这里不区分"令牌过期"与"账号不存在"，外面不需要知道差别。
      const raw = bearer(req);
      const resolved = auth ? auth.resolveBearer(raw) : (raw && ACCOUNT_ID_RE.test(raw) ? { accountId: raw } : null);
      const accountId = resolved?.accountId ?? null;
      if (!accountId) {
        say(401);
        return json(res, 401, { error: '缺少或非法的 Authorization: Bearer' });
      }
      if (!store.exists(accountId)) {
        say(404);
        return json(res, 404, { error: '账号不存在（恢复码算错了？）' });
      }

      if (req.method === 'GET' && p === '/v1/account/me') {
        say(200);
        return json(res, 200, { exists: true, ...store.accountInfo(accountId) });
      }

      // ---- 上传/下载备份：**原样收发，不解析内容** ----
      if (req.method === 'PUT' && p === '/v1/backup') {
        const { body, tooLarge } = await readBody(req);
        if (tooLarge) {
          say(413);
          return json(res, 413, { error: `备份超过上限 ${MAX_BACKUP_BYTES} 字节` });
        }
        if (!body || body.length === 0) {
          say(400);
          return json(res, 400, { error: '备份内容为空' });
        }
        const r = store.putBackup(accountId, body);
        say(200);
        return json(res, 200, { bytes: r.bytes, updated_at: r.updatedAt });
      }

      if (req.method === 'GET' && p === '/v1/backup') {
        const b = store.getBackup(accountId);
        if (!b) { say(404); return json(res, 404, { error: '这个账号还没有备份' }); }
        res.writeHead(200, {
          'content-type': 'application/octet-stream',
          'content-length': String(b.bytes),
          'x-updated-at': String(b.updatedAt),
        });
        res.end(b.blob);
        return say(200);
      }

      // ---- 注销：账号、设备、备份一起删；**加了账号体系之后，邮箱绑定与令牌也一起删** ----
      // 这一条是合规要求（应用内注销），少删任何一样，政策里那句"注销后不再保留"就是假话。
      if (req.method === 'DELETE' && p === '/v1/account') {
        const n = store.deleteAccount(accountId);
        const a = auth ? auth.store.deleteByAccount(accountId) : 0;
        say(200);
        return json(res, 200, { deleted: n + a });
      }

      say(404);
      return json(res, 404, { error: '没有这个接口' });
    } catch (e) {
      // 不把内部细节回给客户端（也避免把路径/栈写进日志）
      console.error(`内部错误（${req.method} ${p}）：${e?.message ?? e}`);
      say(500);
      return json(res, 500, { error: 'internal' });
    }
  });

  return { server };
}

// ---------------------------------------------------------------- CLI
const isMain = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isMain) {
  const argv = process.argv.slice(2);
  const argOf = (n, d) => { const i = argv.indexOf(n); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };
  const port = Number(argOf('--port', '8790'));
  const dbPath = argOf('--db', join(ROOT, 'server/data/backend.sqlite'));

  const store = createSqliteStore({ path: dbPath });
  // ---- 账号体系是**可选**的：没配邮件通道就没有它（那台服务仍然只做备份）----
  // 为什么做成可选而不是"必须有"：正式包（没有账号体系那一版）与 DEV/自检都还在用
  // 只有备份的那套接口。加一个账号体系不该让"只跑备份"变成跑不起来。
  let auth = null;
  const authDbPath = argOf('--auth-db', dbPath.replace(/\.sqlite$/, '') + '-auth.sqlite');
  const mailOut = argOf('--mail-out', process.env.LIANLEME_MAIL_OUT ?? null);
  const authSecret = argOf('--auth-secret', process.env.LIANLEME_AUTH_SECRET ?? null);
  const smtpHost = process.env.LIANLEME_SMTP_HOST;
  if (mailOut || smtpHost) {
    try {
      const { createAuthStore } = await import('./auth-store.mjs');
      const { createAuth } = await import('./auth.mjs');
      const { mailerFromEnv } = await import('./mailer.mjs');
      if (!authSecret) {
        throw new Error('开了账号体系就必须给 --auth-secret 或 LIANLEME_AUTH_SECRET（生成随机盐要用它；'
          + '不固定的话每次重启都会换一套假盐，客户端拿到的盐对不上）');
      }
      auth = createAuth({
        store: createAuthStore({ path: authDbPath }),
        backendStore: store,
        mailer: mailerFromEnv({ ...process.env, ...(mailOut ? { LIANLEME_MAIL_OUT: mailOut } : {}) }),
        secret: authSecret,
      });
    } catch (e) {
      // ⚠️ **配错账号体系，不许把整个后端拖下水**（2026-10-06 部署前想通的）：
      // 这台服务同时供着**云备份**，而备份是既有用户在用的功能。
      // 如果这里直接 throw，一个 SMTP 口令拼错就会让服务起不来 —— 云备份、埋点全挂，
      // 而症状（systemd 无限重启）跟真正的原因隔得很远。
      // 所以：**大声说、但照常启动**，只是 /v1/auth/* 回 404（等于没有账号体系）。
      // 判据很好认：/healthz 里没有 `binds` / `tokens` 两个字段就是没起来。
      console.error('⚠️  账号体系没能启用：' + (e?.message ?? e));
      console.error('    服务会照常启动（备份与埋点不受影响），/v1/auth/* 会明确返回 404。');
      console.error('    去检查 /etc/lianleme/mail.env（怎么填见 server/deploy/README.md），改完 restart。');
      auth = null;
    }
  }
  const { server } = createBackend({ store, auth });
  // `--port 0` 让内核挑一个空闲端口；**必须把真实端口打出来**，
  // 否则自动化测试拿到 "0" 就没法连上（app/test/cloud_backup_test.dart 正靠这一行）。
  // ⚠️ **必须显式绑 127.0.0.1**（2026-10-04 真机上量到的）：只写 server.listen(port)
  // 会绑到**所有网卡**（`ss` 里显示 `*:8790`）。那样安全边界就只剩云厂商安全组一道 ——
  // 安全组一改、或同 VPC 里另一台机器，就能直连这两个服务；而文档与单元注释里
  // 写的是「只监听本机、对外只有反代一个入口」。**声明与实现不一致就是 bug**，绑死环回。
  server.listen(port, '127.0.0.1', () => {
    const actual = server.address().port;
    console.log(`✓ 极薄后端在 http://127.0.0.1:${actual}`);
    console.log(`  库：${dbPath}`);
    console.log('  接口：POST /v1/account · GET /v1/account/me · PUT|GET /v1/backup · DELETE /v1/account');
    console.log(auth
      ? `  账号：已开（库 ${authDbPath}）· POST /v1/auth/{salt,code,register,login,reset,logout,change-password} · GET /v1/auth/me`
      : '  账号：**没开**（没有 SMTP 或 --mail-out；接口 /v1/auth/* 会 404）');
    console.log('  ⚠️ 服务端只存密文；生产必须走 HTTPS（凭据在 Authorization 头里）。');
  });
}
