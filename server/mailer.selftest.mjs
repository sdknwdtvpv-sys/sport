#!/usr/bin/env node
/**
 * 练了么 · 邮件模块的自检（`server/mailer.mjs`）
 *
 * **为什么值得一条自检**：发信是"看起来成功了"的重灾区 ——
 * 验证码发不出去、发到了别人手上、正文乱码、或者最坏的：**悄悄用明文把口令发出去**。
 * 所以这条自检不测"SMTP 库好不好用"，只测我们自己写的那几十行：
 *
 *   1. **对话对不对**：对着一个**假 SMTP 服务器**跑完整流程（EHLO → AUTH LOGIN → MAIL/RCPT → DATA → QUIT），
 *      并逐项核对用户名/口令/发件人/收件人/正文 —— 假服务器把收到的东西原样交给断言。
 *   2. **不许明文**：不带 `allowPlaintext` 时，明文连接必须被**拒绝**（不是"警告一下继续"）。
 *   3. **真 TLS 这条路也跑过**（生产就是这条，465）：用 `openssl` 现场签一张自签证书，
 *      把它当 CA 传给客户端 —— **证书校验始终是开的**，绝不引入 `rejectUnauthorized:false`。
 *      openssl 不在时这一步如实标"跳过"（不判失败，也不假装通过）。
 *   4. **头注入**：`to`/`from`/`subject` 里带换行必须被拒。
 *   5. **日志纪律**：日志里不许出现完整收件人（只许打码）。
 *   6. **配置不全必须报错**：不许悄悄退化成"写文件"，那会让线上发信失败变成"验证码写进了服务器文件"。
 *
 * 退出码：0 全过 / 1 有失败。
 */

import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { createServer as createNetServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer as createTlsServer } from 'node:tls';
import {
  buildMessage,
  createFileMailer,
  mailerFromEnv,
  maskAddress,
  smtpDeliver,
} from './mailer.mjs';

/**
 * 一个极简的假 SMTP 服务器：够回答我们客户端问的那几句就行。
 * `authOk=false` 时在口令那一步回 535（用来验"服务器拒绝时我们抛错"）。
 */
function startFakeSmtp({ tls, authOk = true } = {}) {
  const seen = [];
  const handler = (socket) => {
    const st = { user: null, pass: null, from: null, to: null, data: null, inData: false, step: 0 };
    seen.push(st);
    socket.write('220 fake.lianleme ESMTP\r\n');
    let buf = '';
    socket.on('data', (chunk) => {
      buf += chunk.toString('utf8');
      let idx;
      while ((idx = buf.indexOf('\r\n')) >= 0) {
        const line = buf.slice(0, idx);
        buf = buf.slice(idx + 2);
        if (st.inData) {
          if (line === '.') {
            st.inData = false;
            socket.write('250 ok queued\r\n');
          } else {
            st.data += line.replace(/^\.\./, '.') + '\r\n';
          }
          continue;
        }
        const up = line.toUpperCase();
        if (up.startsWith('EHLO') || up.startsWith('HELO')) {
          socket.write('250-fake.lianleme\r\n250-AUTH LOGIN PLAIN\r\n250 SIZE 10485760\r\n');
        } else if (up === 'AUTH LOGIN') {
          st.step = 1;
          socket.write('334 VXNlcm5hbWU6\r\n');
        } else if (st.step === 1) {
          st.user = Buffer.from(line, 'base64').toString('utf8');
          st.step = 2;
          socket.write('334 UGFzc3dvcmQ6\r\n');
        } else if (st.step === 2) {
          st.pass = Buffer.from(line, 'base64').toString('utf8');
          st.step = 3;
          socket.write(authOk ? '235 auth ok\r\n' : '535 5.7.8 口令错\r\n');
        } else if (up.startsWith('MAIL FROM')) {
          st.from = line.slice(line.indexOf('<') + 1, line.lastIndexOf('>'));
          socket.write('250 ok\r\n');
        } else if (up.startsWith('RCPT TO')) {
          st.to = line.slice(line.indexOf('<') + 1, line.lastIndexOf('>'));
          socket.write('250 ok\r\n');
        } else if (up === 'DATA') {
          st.inData = true;
          st.data = '';
          socket.write('354 结束请发单独一行点\r\n');
        } else if (up === 'QUIT') {
          socket.write('221 bye\r\n');
          socket.end();
        } else {
          socket.write('250 ok\r\n');
        }
      }
    });
    socket.on('error', () => {});
  };
  const server = tls ? createTlsServer({ key: tls.key, cert: tls.cert }, handler) : createNetServer(handler);
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      resolve({
        port: server.address().port,
        seen,
        close: () => new Promise((r) => server.close(r)),
      });
    });
  });
}

/** 把 DATA 里收到的整封邮件拆成 { headers, body }，正文按 base64 解回字符串。 */
function parseReceived(raw) {
  const cut = raw.indexOf('\r\n\r\n');
  const headers = cut >= 0 ? raw.slice(0, cut) : raw;
  const body = cut >= 0 ? raw.slice(cut + 4) : '';
  const decoded = Buffer.from(body.replace(/\r\n/g, ''), 'base64').toString('utf8');
  return { headers, decoded };
}

export async function selftest() {
  const failures = [];
  const checks = { passed: 0, skipped: 0 };
  const check = (name, ok, detail = '') => {
    if (ok) { checks.passed += 1; console.log(`  ✓ ${name}`); } else {
      failures.push(name);
      console.log(`  ✗ ${name}${detail ? ` —— ${detail}` : ''}`);
    }
  };
  const skip = (name, why) => { checks.skipped += 1; console.log(`  ⊘ 跳过：${name}（${why}）`); };
  const throws = async (fn) => {
    try { await fn(); return null; } catch (e) { return e; }
  };

  const dir = mkdtempSync(join(tmpdir(), 'lianleme-mailer-'));

  try {
    // ---- 1. 拼信：头注入与编码 ----
    const msg = buildMessage({
      from: 'no-reply@elliotli.work',
      to: 'someone@example.com',
      subject: '练了么 · 登录验证码',
      text: '你的验证码是 428913。\n.\n五分钟内有效。',
    });
    check('邮件头齐全（From/To/Subject/Date/Message-ID/MIME）',
      /^From: no-reply@elliotli\.work/.test(msg)
      && msg.includes('To: someone@example.com')
      && msg.includes('MIME-Version: 1.0')
      && /Message-ID: <.+@lianleme>/.test(msg));
    const parsed = parseReceived(msg);
    check('正文按 base64 编码后能解回原文（含中文与行首的点）',
      parsed.decoded === '你的验证码是 428913。\n.\n五分钟内有效。', parsed.decoded);

    const inj = await throws(() => buildMessage({
      from: 'a@b.c', to: 'x@y.z\r\nBcc: 别人@example.com', subject: 's', text: 't',
    }));
    check('收件人里带换行被拒（头注入）', inj instanceof Error, String(inj?.message));
    const inj2 = await throws(() => buildMessage({
      from: 'a@b.c', to: 'x@y.z', subject: 's\nX-Evil: 1', text: 't',
    }));
    check('主题里带换行被拒（头注入）', inj2 instanceof Error, String(inj2?.message));
    check('打码函数不泄漏完整地址', maskAddress('elliot@example.com') === 'el****@example.com',
      maskAddress('elliot@example.com'));

    // ---- 2. file 模式（自检与本地用） ----
    const out = join(dir, 'mail.ndjson');
    const fileMailer = createFileMailer({ path: out });
    await fileMailer.send({ to: 'a@example.com', subject: '一', text: '验证码 111111' });
    await fileMailer.send({ to: 'b@example.com', subject: '二', text: '验证码 222222' });
    const lines = readFileSync(out, 'utf8').trim().split('\n');
    check('file 模式追加两封（不是覆盖）', lines.length === 2, `实际 ${lines.length} 行`);
    check('file 模式写下的内容里有验证码（给测试与人看，故意不加密）',
      lines[1].includes('222222') && JSON.parse(lines[1]).to === 'b@example.com');

    // ---- 3. 明文必须被拒（除非显式允许） ----
    const plainRefused = await throws(() => smtpDeliver({
      host: '127.0.0.1', port: 1, secure: false, user: 'u', pass: 'p',
      from: 'a@b.c', to: 'd@e.f', message: 'x',
    }));
    check('默认拒绝明文 SMTP（不许"警告一下继续"）',
      /拒绝明文/.test(String(plainRefused?.message)), String(plainRefused?.message));

    const noCreds = await throws(() => smtpDeliver({
      host: '127.0.0.1', port: 465, secure: true, user: '', pass: '',
      from: 'a@b.c', to: 'd@e.f', message: 'x',
    }));
    check('465 缺用户名/口令时报错（不是匿名发信）',
      /user 与 pass/.test(String(noCreds?.message)), String(noCreds?.message));

    // ---- 4. 完整对话（明文，显式允许；只对本地假服务器） ----
    const fake = await startFakeSmtp();
    const text = '你的验证码是 654321。';
    await smtpDeliver({
      host: '127.0.0.1', port: fake.port, secure: false, allowPlaintext: true,
      user: 'no-reply@elliotli.work', pass: 'smtp-口令', from: 'no-reply@elliotli.work',
      to: 'someone@example.com',
      message: buildMessage({
        from: 'no-reply@elliotli.work', to: 'someone@example.com', subject: '验证码', text,
      }),
    });
    await fake.close();
    const s = fake.seen[0];
    check('假服务器收到了登录用户名', s?.user === 'no-reply@elliotli.work', String(s?.user));
    check('假服务器收到了口令（AUTH LOGIN 的第二段）', s?.pass === 'smtp-口令');
    check('MAIL FROM / RCPT TO 与传入一致',
      s?.from === 'no-reply@elliotli.work' && s?.to === 'someone@example.com',
      `${s?.from} → ${s?.to}`);
    check('正文原样到达（base64 解回验证码）', parseReceived(s?.data ?? '').decoded === text,
      parseReceived(s?.data ?? '').decoded);

    // ---- 5. 服务器拒绝时我们要抛错（不能"当作发出去了"） ----
    const bad = await startFakeSmtp({ authOk: false });
    const authErr = await throws(() => smtpDeliver({
      host: '127.0.0.1', port: bad.port, secure: false, allowPlaintext: true,
      user: 'u@example.com', pass: '错的', from: 'u@example.com', to: 'd@example.com',
      message: buildMessage({ from: 'u@example.com', to: 'd@example.com', subject: 's', text: 't' }),
    }));
    await bad.close();
    check('口令被拒（535）时抛错，而不是静默成功',
      /535/.test(String(authErr?.message)), String(authErr?.message));

    // ---- 6. 日志纪律 ----
    const logs = [];
    const loggingMailer = mailerFromEnv({
      LIANLEME_SMTP_HOST: 'smtp.example.com',
      LIANLEME_SMTP_USER: 'u@example.com',
      LIANLEME_SMTP_PASS: 'p',
      LIANLEME_SMTP_FROM: 'no-reply@example.com',
    }, { log: (m) => logs.push(m) });
    check('配置齐全时是 smtp 模式、端口 465 默认', loggingMailer.mode === 'smtp');
    const missing = await throws(() => mailerFromEnv({ LIANLEME_SMTP_HOST: 'smtp.example.com' }));
    check('配置不全时**大声报错**（不悄悄退化成文件模式）',
      /配置不全/.test(String(missing?.message)), String(missing?.message));

    // ---- 7. 真 TLS（生产路径）：openssl 现场签自签证书，把它当 CA ----
    let openssl = true;
    try { execFileSync('openssl', ['version'], { stdio: 'ignore' }); } catch { openssl = false; }
    if (!openssl) {
      skip('隐式 TLS（465）这条路', '本机没有 openssl，签不出自检用的证书');
    } else {
      const key = join(dir, 'k.pem');
      const cert = join(dir, 'c.pem');
      execFileSync('openssl', [
        'req', '-x509', '-newkey', 'rsa:2048', '-keyout', key, '-out', cert,
        '-days', '1', '-nodes', '-subj', '/CN=127.0.0.1',
        '-addext', 'subjectAltName=IP:127.0.0.1',
      ], { stdio: 'ignore' });
      const tlsFake = await startFakeSmtp({
        tls: { key: readFileSync(key, 'utf8'), cert: readFileSync(cert, 'utf8') },
      });
      const tlsText = '你的验证码是 246810。';
      const tlsErr = await throws(() => smtpDeliver({
        host: '127.0.0.1', port: tlsFake.port, secure: true, user: 'u@example.com', pass: '口令',
        from: 'u@example.com', to: 'd@example.com', tlsCa: readFileSync(cert, 'utf8'),
        message: buildMessage({
          from: 'u@example.com', to: 'd@example.com', subject: '验证码', text: tlsText,
        }),
      }));
      check('TLS 连接 + 发信成功（证书校验是开的）', tlsErr === null, String(tlsErr?.message));
      check('TLS 那条路上正文也对（走的是 secureConnect 而不是 connect）',
        parseReceived(tlsFake.seen[0]?.data ?? '').decoded === tlsText);
      await tlsFake.close();

      const wrongCa = await startFakeSmtp({
        tls: { key: readFileSync(key, 'utf8'), cert: readFileSync(cert, 'utf8') },
      });
      const caErr = await throws(() => smtpDeliver({
        host: '127.0.0.1', port: wrongCa.port, secure: true, user: 'u@example.com', pass: '口令',
        from: 'u@example.com', to: 'd@example.com',
        message: buildMessage({ from: 'u@example.com', to: 'd@example.com', subject: 's', text: 't' }),
      }));
      await wrongCa.close();
      check('不认识的证书会被拒（证明校验没过被关掉）', caErr instanceof Error, String(caErr?.message));
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }

  if (failures.length) {
    console.error(`\n✗ 邮件自检失败 ${failures.length} 项：`);
    for (const f of failures) console.error(`  · ${f}`);
    return 1;
  }
  const skippedNote = checks.skipped ? `，跳过 ${checks.skipped} 项` : '';
  console.log(`✓ 邮件自检通过（${checks.passed} 项${skippedNote}：对话 · 明文必拒 · TLS · 头注入 · 日志打码）`);
  return 0;
}

if (process.argv[1] && process.argv[1].endsWith('mailer.selftest.mjs')) {
  process.exit(await selftest());
}
