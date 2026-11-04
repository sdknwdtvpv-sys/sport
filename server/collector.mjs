#!/usr/bin/env node
/**
 * 练了么 · 埋点参考收集端（**零依赖**，只用 node:http）
 *
 * **它解决什么**：`docs/analytics-sdk.md` 把上报的客户端那一半全写完了
 * （outbox / 批量 ≤100 / 退避重试 / 训练期间挂起 / P0 不丢），
 * 但"发到哪"一直是个空 —— `main.dart` 里挂的是 `_NullTransport`，
 * 于是北极星与 `tap_count` 门禁**一个数都没有**。
 *
 * 这个文件是最小的另一端：**收下来、落成 JSONL、说清楚收了多少**。
 * 它不是要上线的后端（没有鉴权、没有限流、没有分库），
 * 而是三件事的共同前提：
 *   1. 真机联调时有个能收的东西（`--dart-define=LIANLEME_ANALYTICS_URL=...`）
 *   2. `tool/analytics-report.mjs` 有数据可算（那份口径是可执行的）
 *   3. 将来写真后端时，**线格式与语义有一份可运行的参考**
 *
 * 接口：
 *   POST /v1/events   体：{"events":[{id,event,ts,priority,...}]} → 202 {"accepted":N}
 *   GET  /healthz     → 200 {"ok":true,"events":N}
 *   GET  /stats       → 200 {"byEvent":{...},"devices":N}
 *
 * 用法：
 *   node server/collector.mjs --port 8787 --out server/data
 *   node server/collector.selftest.mjs            # 收集端 + 口径计算的自检（verify.sh 会跑）
 *
 * 落盘格式：`<out>/events-YYYY-MM-DD.jsonl`，一行一条事件（追加写，重启不丢）。
 */

import { createServer } from 'node:http';
import { appendFileSync, mkdirSync, existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** 事件的必需字段：缺了就没法归因（`docs/analytics.md` §2.1 的公共字段） */
const REQUIRED = ['id', 'event', 'ts', 'device_id', 'session_id', 'app_version', 'schema_version'];

/** 请求体上限（5 MB）。客户端一批最多 100 条，正常请求只有几十 KB。 */
export const MAX_BODY_BYTES = 5 * 1024 * 1024;

/**
 * 把某一天的一批行追加到 `<outDir>/events-<day>.jsonl`。
 *
 * 抽出来是为了**可被测**：`collector.selftest.mjs` 用一个计数的包装验"一批 N 条
 * 只落盘一次"，而不是靠"看起来更快"。默认实现保持"追加写、重启不丢"。
 */
export function appendDayFile(outDir, day, text) {
  mkdirSync(outDir, { recursive: true });
  appendFileSync(join(outDir, `events-${day}.jsonl`), text, 'utf8');
}

export function createCollector({ outDir, maxBodyBytes = MAX_BODY_BYTES, writeDayFile = appendDayFile }) {
  const state = { events: 0, byEvent: new Map(), devices: new Set(), files: new Map() };

  function lineFor(ev) {
    const day = new Date(Number(ev.ts) || Date.now()).toISOString().slice(0, 10);
    return { day, line: JSON.stringify({ ...ev, received_at: Date.now() }) + '\n' };
  }

  function handleBatch(body) {
    if (!body || typeof body !== 'object' || !Array.isArray(body.events)) {
      return { status: 400, payload: { error: 'body 必须是 {"events":[...]}' } };
    }
    let accepted = 0;
    const rejected = [];
    // 统计先记在**本地**，落盘成功后才并进 state：否则写失败的批次会出现在
    // /stats 的 byEvent / devices 里，却不计入 events（两个数字互相矛盾）。
    const acceptedByEvent = new Map();
    const acceptedDevices = new Set();
    // **按天分组、一天只写一次**（2026-11-05）：原先每条事件各调一次
    // `mkdirSync` + `appendFileSync` —— 一批 100 条就是 200 次同步文件系统调用，
    // 而这些调用把 Node 的事件循环**整段挡住**（同步 I/O），别的连接全在等。
    // 分组的顺序与"一条一条追加"完全一致（同一个 Map 按插入顺序，事件本身也按原顺序），
    // 落盘内容逐字节相同；跨天的批次本来就写两个文件，只是少掉 N 次重复的 open/mkdir。
    const byDay = new Map();
    for (const ev of body.events) {
      if (!ev || typeof ev !== 'object') { rejected.push('not_an_object'); continue; }
      const missing = REQUIRED.filter((k) => ev[k] === undefined || ev[k] === null);
      if (missing.length) { rejected.push(`${ev.event ?? '?'}:missing:${missing.join(',')}`); continue; }
      const { day, line } = lineFor(ev);
      const lines = byDay.get(day);
      if (lines) lines.push(line); else byDay.set(day, [line]);
      accepted++;
      acceptedByEvent.set(ev.event, (acceptedByEvent.get(ev.event) ?? 0) + 1);
      acceptedDevices.add(ev.device_id);
    }
    // 一条都没收下就是 400 —— 让客户端的退避重试逻辑真的有机会跑起来
    // （全 202 的收集端会让"重试"这条路径永远测不到）。
    if (accepted === 0) return { status: 400, payload: { accepted: 0, rejected } };
    // 落盘失败要如实回 500（而不是让异常从 'end' 回调里抛出去把进程带走）。
    // 状态计数放在**写成功之后**：失败的批次不该被算进 /healthz 与 /stats。
    try {
      for (const [day, lines] of byDay) writeDayFile(outDir, day, lines.join(''));
    } catch (e) {
      return { status: 500, payload: { error: `落盘失败：${e?.message ?? e}` } };
    }
    state.events += accepted;
    for (const [name, n] of acceptedByEvent) {
      state.byEvent.set(name, (state.byEvent.get(name) ?? 0) + n);
    }
    for (const d of acceptedDevices) state.devices.add(d);
    return { status: 202, payload: { accepted, rejected } };
  }

  const server = createServer((req, res) => {
    const url = new URL(req.url ?? '/', 'http://localhost');
    const json = (status, payload) => {
      res.writeHead(status, { 'content-type': 'application/json' });
      res.end(JSON.stringify(payload));
    };

    if (req.method === 'GET' && url.pathname === '/healthz') {
      return json(200, { ok: true, events: state.events });
    }
    if (req.method === 'GET' && url.pathname === '/stats') {
      return json(200, {
        events: state.events,
        devices: state.devices.size,
        byEvent: Object.fromEntries(state.byEvent),
      });
    }
    if (req.method === 'POST' && url.pathname === '/v1/events') {
      const chunks = [];
      let size = 0;
      let tooLarge = false;
      req.on('data', (c) => {
        size += c.length;
        // 客户端一批最多 100 条，正常的体是几十 KB；超过上限（默认 5 MB）直接拒。
        //
        // ⚠️ **不能 `req.destroy()`**（2026-11-05 改的，与 `backend.mjs` 的 `readBody`
        // 同一条教训）：掐断连接时客户端拿到的是 socket reset，而不是一个干净的 413 ——
        // 客户端的退避重试会把它当"网络抖了"，然后一直重试同一个超大包。
        // 正确姿势：不再缓存（内存有界），但把流读完，再回一个能读懂的状态码。
        if (size > maxBodyBytes) {
          if (!tooLarge) { tooLarge = true; chunks.length = 0; }
          return;
        }
        chunks.push(c);
      });
      req.on('end', () => {
        if (tooLarge) {
          return json(413, { error: `请求体超过上限 ${maxBodyBytes} 字节` });
        }
        let body = null;
        try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { body = null; }
        const { status, payload } = handleBatch(body);
        json(status, payload);
      });
      return;
    }
    json(404, { error: 'not found' });
  });

  return { server, state, handleBatch };
}

/** 读收集端落下的 JSONL（`--selftest` 与 report 工具共用同一份读法） */
export function readEventsFromDir(dir) {
  if (!existsSync(dir)) return [];
  const out = [];
  for (const f of readdirSync(dir).filter((n) => n.endsWith('.jsonl')).sort()) {
    for (const line of readFileSync(join(dir, f), 'utf8').split('\n')) {
      if (!line.trim()) continue;
      try { out.push(JSON.parse(line)); } catch { /* 坏行跳过，不整份作废 */ }
    }
  }
  return out;
}

// ---------------------------------------------------------------- CLI

if (process.argv[1] && process.argv[1].endsWith('collector.mjs')) {
  const argv = process.argv.slice(2);
  const argOf = (name, fallback) => {
    const i = argv.indexOf(name);
    return i >= 0 && argv[i + 1] ? argv[i + 1] : fallback;
  };

  // 自检有自己的入口：`node server/collector.selftest.mjs`。
  //
  // ⚠️ **不要**在这里 `await import('./collector.selftest.mjs')` ——
  // 那个文件 import 回本文件，而本文件正卡在那个 await 上，
  // 于是循环等待、Node 只丢一句 "unsettled top-level await" 就安静退出。
  // （第一版就是这么写的：跑起来什么都不输出，看着像"通过了"。）
  const port = Number(argOf('--port', '8787'));
  const outDir = argOf('--out', join(ROOT, 'server/data'));
  const { server } = createCollector({ outDir });
  // ⚠️ **必须显式绑 127.0.0.1**（2026-10-04 真机上量到的）：只写 server.listen(port)
  // 会绑到**所有网卡**（`ss` 里显示 `*:8790`）。那样安全边界就只剩云厂商安全组一道 ——
  // 安全组一改、或同 VPC 里另一台机器，就能直连这两个服务；而文档与单元注释里
  // 写的是「只监听本机、对外只有反代一个入口」。**声明与实现不一致就是 bug**，绑死环回。
  server.listen(port, '127.0.0.1', () => {
    console.log(`✓ 埋点收集端在 http://127.0.0.1:${port}`);
    console.log(`  收：POST /v1/events   看：GET /healthz /stats`);
    console.log(`  落盘：${outDir}/events-YYYY-MM-DD.jsonl`);
    console.log('');
    console.log('  让 App 发到这里，两条路选一条：');
    console.log('  1) 真机 + USB（推荐，不用同一 Wi-Fi）：');
    console.log(`       adb reverse tcp:${port} tcp:${port}`);
    console.log(`       flutter build apk --release --dart-define=LIANLEME_ANALYTICS_URL=http://127.0.0.1:${port}/v1/events`);
    console.log('  2) 真机 + 同一局域网（用本机 IP，不是 127.0.0.1）：');
    console.log(`       flutter run --dart-define=LIANLEME_ANALYTICS_URL=http://<你的IP>:${port}/v1/events`);
    console.log('');
    console.log('  验完务必换回不带地址的正式包：配了地址的包会真的往外发。');
    console.log('  （2026-09-30 用第 1 条做过一次真机端到端，见 docs/analytics.md §10）');
  });
}
