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

export function createCollector({ outDir }) {
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
    for (const ev of body.events) {
      if (!ev || typeof ev !== 'object') { rejected.push('not_an_object'); continue; }
      const missing = REQUIRED.filter((k) => ev[k] === undefined || ev[k] === null);
      if (missing.length) { rejected.push(`${ev.event ?? '?'}:missing:${missing.join(',')}`); continue; }
      const { day, line } = lineFor(ev);
      mkdirSync(outDir, { recursive: true });
      appendFileSync(join(outDir, `events-${day}.jsonl`), line, 'utf8');
      accepted++;
      state.events++;
      state.byEvent.set(ev.event, (state.byEvent.get(ev.event) ?? 0) + 1);
      state.devices.add(ev.device_id);
    }
    // 一条都没收下就是 400 —— 让客户端的退避重试逻辑真的有机会跑起来
    // （全 202 的收集端会让"重试"这条路径永远测不到）。
    if (accepted === 0) return { status: 400, payload: { accepted: 0, rejected } };
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
      req.on('data', (c) => {
        size += c.length;
        // 客户端一批最多 100 条，正常的体是几十 KB；超过 5 MB 直接拒
        if (size > 5 * 1024 * 1024) { req.destroy(); return; }
        chunks.push(c);
      });
      req.on('end', () => {
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
  server.listen(port, () => {
    console.log(`✓ 埋点收集端在 http://127.0.0.1:${port}`);
    console.log(`  收：POST /v1/events   看：GET /healthz /stats`);
    console.log(`  落盘：${outDir}/events-YYYY-MM-DD.jsonl`);
    console.log('');
    console.log('  让 App 发到这里（真机联调用本机 IP，不是 127.0.0.1）：');
    console.log(`    flutter run --dart-define=LIANLEME_ANALYTICS_URL=http://<你的IP>:${port}/v1/events`);
  });
}
