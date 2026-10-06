#!/usr/bin/env node
/**
 * 练了么 · 邮件发送（**零依赖**：只用 `node:net` / `node:tls`）
 *
 * 为什么要自己写 SMTP：`server/` 的规矩是**零依赖**（`node:http` + `node:sqlite` +
 * `node:crypto`，见 `server/backend-store.mjs` 文件头）。注册/找回要发验证码，
 * 而 Node 没有内置 SMTP 客户端；引 `nodemailer` 就等于给这个"一个文件能跑起来"的后端
 * 塞进一棵依赖树（还有供应链面）—— 而我们要发的只有一种邮件：**一封纯文本验证码**。
 * 一封纯文本邮件需要的协议面很小，所以自己写，并把每一处纪律写在代码里。
 *
 * 两种模式（这是**测试能用**的关键）：
 *
 *   * `file`  —— 把邮件（含验证码）追加到一个文件。自检与本地跑用这个，
 *                所以 `server/backend.selftest.mjs` **不需要真的 SMTP** 就能端到端跑通。
 *   * `smtp`  —— 真的发。**只实现隐式 TLS（465）**，见下面「为什么不支持 STARTTLS」。
 *
 * 三条纪律（与 `server/backend.mjs` 的那三条同源）：
 *   1. **日志里不许出现验证码、也不许出现口令/授权头**。本文件的所有日志只打
 *      "发给谁（打码）+ 成功/失败"。`file` 模式**故意**写全文（那是给测试与人看的）。
 *   2. **不许有头注入**：`to`/`from`/`subject` 里的 CR/LF 一律拒绝 —— 否则收件人
 *      能往邮件头里塞东西（Bcc、伪造 From）。
 *   3. **正文用 base64**：中文正文直接进 DATA 会撞上"行太长 / 行首的点"，base64 一次
 *      解决两个问题，代价只是不可读（收件人那边照常显示）。
 *
 * ⚠️ **为什么不支持 STARTTLS（587）**：STARTTLS 是"先明文握手、再升级"，实现上要
 * 重开一次 TLS 并把随后的对话换成新的读取器；而它的历史漏洞正是**剥离攻击**
 * （中间人拦掉 STARTTLS 广告，客户端退回明文发凭据）。主流邮箱（QQ/163/阿里/腾讯企业邮）
 * 都给 465 隐式 TLS。所以一期**只做 465**，配错端口会得到一句明确的报错，
 * 而不是"悄悄用明文把口令发出去"。
 *
 * 用法：
 *   node server/mailer.mjs --selftest
 *   （生产配置见 server/deploy/README.md 的环境变量表）
 */

import { appendFileSync, mkdirSync } from 'node:fs';
import { connect as netConnect, isIP } from 'node:net';
import { dirname } from 'node:path';
import { connect as tlsConnect } from 'node:tls';

const CRLF = '\r\n';

/** 头部注入防线：任何 CR/LF 都不许出现在地址或主题里。 */
function assertNoInjection(name, value) {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`${name} 不能为空`);
  }
  if (/[\r\n]/.test(value)) {
    throw new Error(`${name} 里不许有换行（头注入）`);
  }
  return value;
}

/** 用途：日志里打码的收件人（验证码/邮箱都不许进日志）。 */
export function maskAddress(addr) {
  const s = String(addr ?? '');
  const at = s.indexOf('@');
  if (at <= 0) return '***';
  const head = s.slice(0, at);
  const tail = s.slice(at);
  const keep = head.slice(0, 2);
  return `${keep}${'*'.repeat(Math.max(1, head.length - keep.length))}${tail}`;
}

/** 拼一封纯文本邮件（UTF-8 正文走 base64，见文件头纪律 3）。 */
export function buildMessage({ from, to, subject, text, date = new Date(), messageId }) {
  assertNoInjection('from', from);
  assertNoInjection('to', to);
  assertNoInjection('subject', subject);
  const id = messageId ?? `<${Date.now()}.${Math.random().toString(16).slice(2)}@lianleme>`;
  const body = Buffer.from(String(text ?? ''), 'utf8').toString('base64');
  // base64 每 76 字符折一行：省得某些 MTA 按"行太长"处理
  const folded = body.replace(/(.{76})/g, `$1${CRLF}`);
  return [
    `From: ${from}`,
    `To: ${to}`,
    `Subject: ${subject}`,
    `Date: ${date.toUTCString()}`,
    `Message-ID: ${id}`,
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset=utf-8',
    'Content-Transfer-Encoding: base64',
    '',
    folded,
  ].join(CRLF);
}

/**
 * SMTP 应答读取器：一次只允许一个"等待中的命令"（SMTP 是严格一问一答的）。
 * 多行应答（`250-XXX` 续行 + `250 YYY` 结束行）在这里被合成一条。
 */
function createReplyReader(socket) {
  let buf = '';
  let waiter = null;

  const settle = (fn, arg) => {
    const w = waiter;
    waiter = null;
    if (w) fn.call(null, arg);
  };

  const flush = () => {
    if (!waiter) return;
    const acc = [];
    let idx;
    while ((idx = buf.indexOf(CRLF)) >= 0) {
      const line = buf.slice(0, idx);
      buf = buf.slice(idx + CRLF.length);
      acc.push(line);
      if (/^\d{3} /.test(line)) {
        const w = waiter;
        waiter = null;
        w.resolve(acc.join('\n'));
        return;
      }
    }
  };

  socket.on('data', (c) => {
    buf += c.toString('utf8');
    flush();
  });
  socket.on('error', (e) => settle((x) => waiter?.reject?.(x), e));
  socket.on('close', () => settle(() => {}, new Error('SMTP 连接被对端关闭')));

  return () =>
    new Promise((resolve, reject) => {
      waiter = { resolve, reject };
      flush();
    });
}

/**
 * 真的发一封（隐式 TLS 或**显式允许**的明文，明文只给自检的假服务器用）。
 * 导出是为了让自检能直接对着一个假 SMTP 服务器跑完整对话。
 */
export async function smtpDeliver({
  host,
  port,
  secure = true,
  allowPlaintext = false,
  user,
  pass,
  from,
  to,
  message,
  timeoutMs = 15000,
  ehloName = 'lianleme.local',
  tlsCa,
}) {
  if (!host || !port) throw new Error('SMTP 需要 host 与 port');
  if (!secure && !allowPlaintext) {
    throw new Error('拒绝明文 SMTP：要么用 465（隐式 TLS），要么显式开 allowPlaintext（只给自检用）');
  }
  if (secure && (!user || !pass)) {
    throw new Error('SMTP 需要 user 与 pass（465 也要 AUTH）');
  }

  // ⚠️ `tlsCa` **只给自检**：自检用 openssl 现场签一张自签证书并把它当 CA，
  // 于是证书校验**始终是开的**（绝不提供 `rejectUnauthorized:false` 那种开关 ——
  // 那种开关迟早会被人复制到生产配置里）。
  // ⚠️ `servername` 只在 host 是域名时才给：对 IP 字面量设 SNI 既违反 RFC 6066，
  // Node 也会打一条 DeprecationWarning（自检里就是这么发现的）。
  const sni = isIP(host) ? {} : { servername: host };
  const socket = secure
    ? tlsConnect({ host, port, ...sni, ...(tlsCa ? { ca: tlsCa } : {}) })
    : netConnect({ host, port });
  let timedOut = false;
  socket.setTimeout(timeoutMs, () => {
    timedOut = true;
    socket.destroy(new Error('SMTP 超时'));
  });

  try {
    await new Promise((resolve, reject) => {
      socket.once(secure ? 'secureConnect' : 'connect', resolve);
      socket.once('error', reject);
    });

    const read = createReplyReader(socket);
    const expect = (reply, code) => {
      if (!reply.startsWith(String(code))) {
        throw new Error(`SMTP 期待 ${code}，收到：${reply.split('\n')[0]}`);
      }
    };
    const cmd = async (line, code) => {
      socket.write(line + CRLF);
      const reply = await read();
      if (code) expect(reply, code);
      return reply;
    };

    expect(await read(), 220); // 服务端问候
    await cmd(`EHLO ${ehloName}`, 250);
    if (user && pass) {
      await cmd('AUTH LOGIN', 334);
      await cmd(Buffer.from(user, 'utf8').toString('base64'), 334);
      await cmd(Buffer.from(pass, 'utf8').toString('base64'), 235);
    }
    await cmd(`MAIL FROM:<${from}>`, 250);
    await cmd(`RCPT TO:<${to}>`, 250);
    await cmd('DATA', 354);
    // 正文整体 base64、行首不会是单独的 `.`，但仍按规矩做一次点填充
    const stuffed = message.replace(/^\./gm, '..');
    socket.write(stuffed + CRLF + '.' + CRLF);
    expect(await read(), 250);
    await cmd('QUIT', 221).catch(() => {}); // 已经发出去了，QUIT 失败不算失败
    return { ok: true };
  } finally {
    socket.destroy();
    if (timedOut) throw new Error('SMTP 超时（邮件可能没发出去）');
  }
}

/** `file` 模式：写文件。自检与本地跑用，**故意**写全文。 */
export function createFileMailer({ path }) {
  mkdirSync(dirname(path), { recursive: true });
  return {
    mode: 'file',
    async send({ to, subject, text }) {
      const record = JSON.stringify({ at: new Date().toISOString(), to, subject, text });
      appendFileSync(path, record + '\n', 'utf8');
      return { ok: true, mode: 'file' };
    },
  };
}

/** `smtp` 模式：真发。 */
export function createSmtpMailer({
  host,
  port = 465,
  secure = true,
  allowPlaintext = false,
  user,
  pass,
  from,
  timeoutMs,
  tlsCa,
  log = () => {},
}) {
  return {
    mode: 'smtp',
    async send({ to, subject, text }) {
      const message = buildMessage({ from, to, subject, text });
      log(`SMTP → ${maskAddress(to)}`);
      await smtpDeliver({
        host, port, secure, allowPlaintext, user, pass, from, to, message, timeoutMs, tlsCa,
      });
      return { ok: true, mode: 'smtp' };
    },
  };
}

/**
 * 从环境变量造一个 mailer。**配置不全时大声报错**，而不是悄悄退化成"文件模式"
 * —— 那会让线上"验证码发不出去"变成"验证码写进了服务器上的一个文件"，更坏。
 */
export function mailerFromEnv(env = process.env, { log = () => {} } = {}) {
  if (env.LIANLEME_MAIL_OUT) {
    return createFileMailer({ path: env.LIANLEME_MAIL_OUT });
  }
  const host = env.LIANLEME_SMTP_HOST;
  const user = env.LIANLEME_SMTP_USER;
  const pass = env.LIANLEME_SMTP_PASS;
  const from = env.LIANLEME_SMTP_FROM;
  if (!host || !user || !pass || !from) {
    throw new Error(
      'SMTP 配置不全：需要 LIANLEME_SMTP_HOST / LIANLEME_SMTP_USER / LIANLEME_SMTP_PASS / '
        + 'LIANLEME_SMTP_FROM（或设 LIANLEME_MAIL_OUT 走文件模式，只给本地与自检）',
    );
  }
  const port = Number(env.LIANLEME_SMTP_PORT ?? 465);
  return createSmtpMailer({
    host,
    port,
    secure: port === 465,
    user,
    pass,
    from,
    log,
  });
}

// ---------------------------------------------------------------- CLI
const isMain = process.argv[1] && new URL(import.meta.url).pathname === process.argv[1];
if (isMain && !process.argv.includes('--selftest')) {
  console.log('邮件模块。用法：node server/mailer.mjs --selftest（自检在 server/mailer.selftest.mjs）');
  console.log('生产配置见 server/deploy/README.md 的环境变量表。');
}
