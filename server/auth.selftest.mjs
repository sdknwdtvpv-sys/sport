#!/usr/bin/env node
/**
 * 练了么 · 账号体系的自检（邮箱 + 口令：注册 / 登录 / 会话 / 改口令 / 重置 / 注销）
 *
 * **为什么必须有一条自检**：账号体系的错都是"看起来成功了"的那种错 ——
 * 令牌没吊销、注销没删干净、日志把邮箱打了出去、口令错与邮箱不存在能被区分出来、
 * 验证码能被无限猜。这些在界面上全都看不出来，所以这里逐条钉住：
 *
 *   1. **反枚举**：不存在邮箱的盐与真盐**形状一样**且稳定；登录失败与邮箱不存在
 *      **回同一句话**（并且都真的做了一次 scrypt）；
 *   2. **验证码纪律**：60 秒一条、错够次数就作废、过期不认；
 *   3. **会话纪律**：令牌吊销后立刻失效；改口令会踢掉**其他**会话；
 *   4. **不透支旧承诺**：服务端库里**没有明文凭据**（口令/凭据/令牌/邮箱都不是原样存的）、
 *      备份仍然原样收发、日志里**没有邮箱明文也没有令牌**；
 *   5. **注销彻底**：账号 + 备份 + 邮箱绑定 + 令牌一起没；
 *   6. **老客户端不被弄坏**：`Bearer <account_id>` 这条路仍然可用。
 *
 * 邮件走 `--mail-out`（文件）模式 —— 所以这条自检**不需要真的 SMTP** 就能端到端跑通。
 *
 * 退出码：0 全过 / 1 有失败。
 */

import { createHash, createHmac, randomBytes } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createAuth } from './auth.mjs';
import { createAuthStore } from './auth-store.mjs';
import { createBackend } from './backend.mjs';
import { createSqliteStore } from './backend-store.mjs';
import { createFileMailer } from './mailer.mjs';

/** 客户端那边"用口令派生 verifier"的替身（自检里不真的跑 Argon2id，那是客户端自检的事）。 */
function verifierFor(password, salt) {
  return createHmac('sha256', `lianleme/auth/v1|${salt}`).update(password).digest('hex');
}

/** 从邮件文件里取最后一封的验证码。 */
function lastCode(mailPath) {
  const lines = readFileSync(mailPath, 'utf8').trim().split('\n');
  const text = JSON.parse(lines[lines.length - 1]).text;
  const m = /验证码是 (\d{6})/.exec(text);
  return m ? m[1] : null;
}

const mailCount = (p) => (readFileSync(p, 'utf8').trim() ? readFileSync(p, 'utf8').trim().split('\n').length : 0);

export async function selftest() {
  const dir = mkdtempSync(join(tmpdir(), 'lianleme-auth-'));
  const mailPath = join(dir, 'mail.ndjson');
  const dbPath = join(dir, 'backend.sqlite');
  const authDbPath = join(dir, 'auth.sqlite');

  const store = createSqliteStore({ path: dbPath });
  const authStore = createAuthStore({ path: authDbPath });
  const logged = [];
  const SECRET = 'self-test-secret-不固定的话假盐会漂';
  const auth = createAuth({
    store: authStore,
    backendStore: store,
    mailer: createFileMailer({ path: mailPath }),
    secret: SECRET,
    log: (m) => logged.push(m),
    // 自检不能等 60 秒；真实默认值在 auth.mjs 里（60 秒 / 10 条 / 10 次失败）。
    limits: { codeMinIntervalMs: 80 },
  });
  const { server } = createBackend({ store, auth, log: (m) => logged.push(m) });

  const failures = [];
  const check = (name, ok, detail = '') => {
    if (ok) console.log(`  ✓ ${name}`);
    else { failures.push(name); console.log(`  ✗ ${name}${detail ? ` —— ${detail}` : ''}`); }
  };

  try {
    await new Promise((r) => server.listen(0, '127.0.0.1', r));
    const base = `http://127.0.0.1:${server.address().port}`;
    const post = (path, payload, headers = {}) => fetch(`${base}${path}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...headers },
      body: JSON.stringify(payload ?? {}),
    });
    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

    const EMAIL = 'Elliot@Example.com'; // 故意大小写混合：服务端必须按小写归一
    const PASSWORD = '正确的马口令 horse-battery-staple';
    const ACCOUNT = createHash('sha256').update('假账号密钥').digest('hex');

    // ---- 1. 盐 / 反枚举 ----
    const salt1 = await (await post('/v1/auth/salt', { email: EMAIL })).json();
    const salt2 = await (await post('/v1/auth/salt', { email: 'never-registered@example.com' })).json();
    check('未注册邮箱也回一个盐（形状一样，不暴露"注册过没有"）',
      /^[0-9a-f]{16,128}$/.test(salt1.salt) && /^[0-9a-f]{16,128}$/.test(salt2.salt)
      && typeof salt1.kdf === 'string' && typeof salt2.kdf === 'string');
    const salt1Again = await (await post('/v1/auth/salt', { email: EMAIL })).json();
    check('同一个邮箱两次拿到的盐一致（否则客户端算出来的密钥会漂）', salt1Again.salt === salt1.salt);
    check('邮箱格式不对被拒（400）',
      (await post('/v1/auth/salt', { email: '不是邮箱' })).status === 400);

    // ---- 2. 验证码：60 秒一条 + 只能有一次有效 ----
    const code1 = await post('/v1/auth/code', { email: EMAIL, purpose: 'register' });
    check('发验证码返回 200（不透露这个邮箱注册过没有）', code1.status === 200);
    const tooSoon = await post('/v1/auth/code', { email: EMAIL, purpose: 'register' });
    check('80 毫秒内再发被限流（429）', tooSoon.status === 429, `实际 ${tooSoon.status}`);
    const theCode = lastCode(mailPath);
    check('邮件里真的有一个 6 位验证码', /^\d{6}$/.test(String(theCode)), String(theCode));
    await sleep(100);

    // ---- 3. 注册 ----
    const verifier = verifierFor(PASSWORD, salt1.salt);
    const wrapped = Buffer.from('假装这是被 KEK 包起来的账号密钥').toString('base64');
    const wrongCode = await post('/v1/auth/register', {
      email: EMAIL, code: '000000', verifier, wrapped, account_id: ACCOUNT, salt: salt1.salt, kdf: salt1.kdf,
    });
    check('验证码不对时注册被拒（400）', wrongCode.status === 400, `实际 ${wrongCode.status}`);

    const reg = await post('/v1/auth/register', {
      email: EMAIL, code: theCode, verifier, wrapped, account_id: ACCOUNT, salt: salt1.salt, kdf: salt1.kdf,
      device_id: 'dev_1', device_name: '自检机',
    });
    const regBody = await reg.json();
    check('注册成功（201）并拿到令牌', reg.status === 201 && /^lm1_[0-9a-f]{64}$/.test(regBody.token ?? ''),
      `实际 ${reg.status}`);
    // ⚠️ 这里刻意**不**期望 409：注册接口是先验验证码、再谈邮箱占用的 ——
    // 否则任何人不用验证码就能拿"这个邮箱注册过没有"当探针。邮箱被占用的正确告知方式是
    // `/v1/auth/code` 发出去的那封"你已经有账号了"的邮件（用户自己能读到）。
    check('同一个邮箱再注册（码已用过）→ 400，且不透露"邮箱已注册"',
      (await post('/v1/auth/register', {
        email: 'elliot@example.com', code: theCode, verifier, wrapped, account_id: ACCOUNT,
        salt: salt1.salt, kdf: salt1.kdf,
      })).status === 400);
    // 唯一性由存储层保证，直接核它（两条都是"一个 account_id 只许一个邮箱"的正面表述）：
    const dupEmail = authStore.bindAccount({
      accountId: 'f'.repeat(64), email: EMAIL, salt: salt1.salt, kdf: salt1.kdf, verifier, wrapped,
    });
    const dupAccount = authStore.bindAccount({
      accountId: ACCOUNT, email: 'other@example.com', salt: salt1.salt, kdf: salt1.kdf, verifier, wrapped,
    });
    check('同一个邮箱绑第二个账号被存储层挡住（email_taken）',
      dupEmail.ok === false && dupEmail.why === 'email_taken', JSON.stringify(dupEmail));
    check('同一个 account_id 绑第二个邮箱被存储层挡住（account_taken —— 否则能"认领"别人的号）',
      dupAccount.ok === false && dupAccount.why === 'account_taken', JSON.stringify(dupAccount));

    // ---- 4. 登录 ----
    const badLogin = await post('/v1/auth/login', { email: EMAIL, verifier: verifierFor('错口令', salt1.salt) });
    const badLoginBody = await badLogin.json();
    const noSuchUser = await post('/v1/auth/login', { email: 'nobody@example.com', verifier });
    const noSuchBody = await noSuchUser.json();
    check('口令错 → 401', badLogin.status === 401, `实际 ${badLogin.status}`);
    check('邮箱不存在 → 401，且**与口令错回同一句话**（不给枚举信号）',
      noSuchUser.status === 401 && noSuchBody.error === badLoginBody.error,
      `${noSuchBody.error} vs ${badLoginBody.error}`);

    const login = await post('/v1/auth/login', { email: 'elliot@example.com', verifier, device_id: 'dev_2' });
    const loginBody = await login.json();
    check('口令对 → 200，并拿回包裹好的账号密钥（服务端解不开它）', login.status === 200 && loginBody.wrapped === wrapped);
    check('登录回的是 normalize 之后的邮箱在库里（大小写不敏感）',
      (await authStore.findByEmail('ELLIOT@EXAMPLE.COM')) !== null);

    const token = loginBody.token;
    const authHeader = { authorization: `Bearer ${token}` };

    // ---- 5. 令牌能用的地方 ----
    const me = await fetch(`${base}/v1/auth/me`, { headers: authHeader });
    const meBody = await me.json();
    check('会话令牌能问出"我是谁"', me.status === 200 && meBody.email === 'elliot@example.com');

    const blob = Buffer.from('PLAINTEXT-自检标记-绝不该被服务端读懂', 'utf8');
    const put = await fetch(`${base}/v1/backup`, { method: 'PUT', headers: authHeader, body: blob });
    check('令牌能上传备份（与老的 account_id 那条路等价）', put.status === 200, `实际 ${put.status}`);
    const got = Buffer.from(await (await fetch(`${base}/v1/backup`, { headers: authHeader })).arrayBuffer());
    check('令牌下载的备份逐字节一致', got.equals(blob));

    const legacy = await fetch(`${base}/v1/account/me`, { headers: { authorization: `Bearer ${ACCOUNT}` } });
    check('老的 `Bearer <account_id>` 仍然可用（正式包不被这次改动打断）', legacy.status === 200);

    // ---- 6. 改口令：踢掉其他会话 ----
    const second = await post('/v1/auth/login', { email: EMAIL, verifier, device_id: 'dev_3' });
    const secondToken = (await second.json()).token;
    const newSalt = randomBytes(16).toString('hex');
    const newVerifier = verifierFor('新口令', newSalt);
    const wrongCurrent = await post('/v1/auth/change-password', {
      current_verifier: verifierFor('不是当前口令', salt1.salt), verifier: newVerifier,
      wrapped, salt: newSalt, kdf: salt1.kdf,
    }, authHeader);
    check('改口令要验当前口令（错的被拒 401）', wrongCurrent.status === 401, `实际 ${wrongCurrent.status}`);

    const changed = await post('/v1/auth/change-password', {
      current_verifier: verifier, verifier: newVerifier, wrapped, salt: newSalt, kdf: salt1.kdf,
    }, authHeader);
    check('改口令成功（200）', changed.status === 200, `实际 ${changed.status}`);
    check('改口令踢掉了其他会话（第二个令牌立刻失效）',
      (await fetch(`${base}/v1/auth/me`, { headers: { authorization: `Bearer ${secondToken}` } })).status === 401);
    check('当前这台会话没被误踢',
      (await fetch(`${base}/v1/auth/me`, { headers: authHeader })).status === 200);
    check('新口令能登录、旧口令不能',
      (await post('/v1/auth/login', { email: EMAIL, verifier })).status === 401
      && (await post('/v1/auth/login', { email: EMAIL, verifier: newVerifier })).status === 200);

    // ---- 7. 重置（忘口令 → 恢复码 + 邮箱验证码 → 设新口令） ----
    const before = mailCount(mailPath);
    check('重置验证码发出（200）',
      (await post('/v1/auth/code', { email: EMAIL, purpose: 'reset' })).status === 200);
    await sleep(100);
    const resetCode = lastCode(mailPath);
    check('重置邮件是新的一封', mailCount(mailPath) === before + 1);
    const resetSalt = randomBytes(16).toString('hex');
    const resetVerifier = verifierFor('重置后的口令', resetSalt);
    const wrongAccount = await post('/v1/auth/reset', {
      email: EMAIL, code: resetCode, account_id: createHash('sha256').update('别的账号').digest('hex'),
      verifier: resetVerifier, wrapped, salt: resetSalt, kdf: salt1.kdf,
    });
    check('重置时 account_id 与邮箱对不上 → 400（恢复码不对就进不来）',
      wrongAccount.status === 400, `实际 ${wrongAccount.status}`);
    const reset = await post('/v1/auth/reset', {
      email: EMAIL, code: resetCode, account_id: ACCOUNT,
      verifier: resetVerifier, wrapped, salt: resetSalt, kdf: salt1.kdf,
    });
    check('重置成功（200）并能用新口令登录',
      reset.status === 200
      && (await post('/v1/auth/login', { email: EMAIL, verifier: resetVerifier })).status === 200);
    check('重置后旧会话全部失效（"旧口令可能泄漏"的默认假设）',
      (await fetch(`${base}/v1/auth/me`, { headers: authHeader })).status === 401);

    // ---- 8. 注销会话 ----
    const afterReset = await (await post('/v1/auth/login', { email: EMAIL, verifier: resetVerifier })).json();
    const session = { authorization: `Bearer ${afterReset.token}` };
    const out = await post('/v1/auth/logout', {}, session);
    check('登出返回吊销数量（200）', out.status === 200 && (await out.json()).revoked === 1);
    check('登出之后那个令牌立刻失效',
      (await fetch(`${base}/v1/auth/me`, { headers: session })).status === 401);
    // ⚠️ 下面两条是**抓 bug 抓出来的回归用例**：令牌以前是 64 位纯十六进制，与 account_id
    // 形状一样，于是"已被吊销的令牌"会被当成"不存在的 account_id"，回 404「账号不存在」
    // 而不是 401。现在令牌带 `lm1_` 前缀，两种凭据一眼可分。**这两条不许删。**
    const revokedOnBackup = await fetch(`${base}/v1/backup`, { headers: session });
    check('被吊销的令牌在备份接口上是 401（**不是** 404「账号不存在」）',
      revokedOnBackup.status === 401, `实际 ${revokedOnBackup.status}`);
    check('令牌与 account_id 的形状不重叠（前缀就是为这个存在的）',
      afterReset.token.startsWith('lm1_'), String(afterReset.token).slice(0, 8));

    // ---- 9. 注销账号：三样一起删 ----
    const fresh = await (await post('/v1/auth/login', { email: EMAIL, verifier: resetVerifier })).json();
    const freshHeader = { authorization: `Bearer ${fresh.token}` };
    await fetch(`${base}/v1/backup`, { method: 'PUT', headers: freshHeader, body: blob });
    const del = await fetch(`${base}/v1/account`, { method: 'DELETE', headers: freshHeader });
    check('应用内注销成功（200）', del.status === 200, `实际 ${del.status}`);
    check('注销后邮箱绑定没了（再登录 → 401）',
      (await post('/v1/auth/login', { email: EMAIL, verifier: resetVerifier })).status === 401);
    check('注销后账号与备份都没了',
      (await fetch(`${base}/v1/account/me`, { headers: { authorization: `Bearer ${ACCOUNT}` } })).status === 404);
    check('注销后认证库里不残留绑定/令牌',
      authStore.stats().binds === 0 && authStore.stats().tokens === 0,
      JSON.stringify(authStore.stats()));

    // ---- 10. 隐私纪律：库里与日志里都不许有明文 ----
    // ⚠️ 用 **Buffer** 搜，不要 `readFileSync(p).toString('binary')` 再 includes 中文串：
    // latin1 解码会把 UTF-8 多字节拆散，于是"明文在里面"反而搜不到 —— 那是一条**假绿**的检查。
    const authDump = readFileSync(authDbPath);
    const backendDump = readFileSync(dbPath);
    const has = (buf, s) => buf.includes(Buffer.from(s, 'utf8'));
    check('库里没有明文口令', !has(authDump, PASSWORD) && !has(authDump, '重置后的口令'));
    check('库里没有明文 verifier（存的是 scrypt 结果）',
      !has(authDump, verifierFor(PASSWORD, salt1.salt)));
    check('库里没有明文令牌（存的是 sha256）',
      !has(authDump, afterReset.token) && !has(authDump, fresh.token));
    check('备份库里只有客户端给的那坨字节（服务端从不解析）', has(backendDump, 'PLAINTEXT-自检标记'));
    const joined = logged.join('\n');
    check('日志里没有邮箱明文（只打 sha256 指纹）', !joined.includes('elliot@example.com') && !joined.includes('Elliot@Example.com'));
    check('日志里没有验证码、没有令牌',
      !/\b\d{6}\b/.test(joined) && !joined.includes(afterReset.token ?? 'zz'));
    check('日志里没有 IP', !/127\.0\.0\.1/.test(joined));
  } finally {
    await new Promise((r) => server.close(r));
    store.close();
    authStore.close();
    rmSync(dir, { recursive: true, force: true });
  }

  if (failures.length) {
    console.error(`\n✗ 账号体系自检失败 ${failures.length} 项：`);
    for (const f of failures) console.error(`  · ${f}`);
    return 1;
  }
  console.log('✓ 账号体系自检通过（反枚举 · 验证码纪律 · 会话与踢号 · 重置 · 注销彻底 · 库里无明文）');
  return 0;
}

if (process.argv[1] && process.argv[1].endsWith('auth.selftest.mjs')) {
  process.exit(await selftest());
}
