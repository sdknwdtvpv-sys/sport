#!/usr/bin/env node
/**
 * 练了么 · 埋点链路的自检（收集端 + 口径计算）
 *
 * **为什么要一条自检**：`server/collector.mjs` 与 `tool/analytics-report.mjs` 是
 * "指标到底能不能算出来"的实现 —— 它们自己错了，报表就会给出**看起来很确定**的错数字。
 * 所以这条自检做的事和三件事对齐：
 *   1. 收集端真的收、真的落盘、坏批真的拒（客户端的退避重试才有机会被触发）
 *   2. 口径算出来的是**人工算得出的那几个数**（分母/分子/中位数/P90）
 *   3. 北极星的 24 小时窗口在**边界**上不差一分钟
 *
 * 退出码：0 全过 / 1 有失败。
 */

import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { createCollector } from './collector.mjs';
import { readEvents, buildReport, median, percentile } from '../tool/analytics-report.mjs';

const DAY = 24 * 60 * 60 * 1000;
const T0 = 1_790_000_000_000; // 固定时间锚，避免"今天"影响结果

/** 造一条合法事件（字段与 docs/analytics.md §2.1 的公共字段一致） */
const ev = (over) => ({
  id: `e_${Math.random().toString(16).slice(2)}`,
  ts: T0,
  priority: 0,
  schema_version: 1,
  device_id: 'dev_a',
  session_id: 'sess_a',
  app_version: '1.7.0',
  platform: 'android',
  is_offline: false,
  ...over,
});

export async function selftest() {
  const dir = mkdtempSync(join(tmpdir(), 'lianleme-collector-'));
  const { server, handleBatch } = createCollector({ outDir: dir });
  const failures = [];
  const check = (name, ok, detail = '') => {
    if (!ok) failures.push(`${name}${detail ? `：${detail}` : ''}`);
  };

  try {
    // ---- 1. 收集端：收 / 拒 / 落盘 ----
    const good = handleBatch({ events: [ev({ event: 'app_open' }), ev({ event: 'workout_started' })] });
    check('合法批次返回 202', good.status === 202, `实际 ${good.status}`);
    check('accepted = 2', good.payload.accepted === 2, `实际 ${good.payload.accepted}`);

    const missingDevice = handleBatch({ events: [{ id: 'x', event: 'app_open', ts: T0 }] });
    check('缺公共字段的批次被拒（400）', missingDevice.status === 400);
    check('拒的时候说明缺了什么',
      (missingDevice.payload.rejected ?? []).some((r) => r.includes('device_id')));

    const broken = handleBatch({ nope: true });
    check('结构不对的批次被拒（400）', broken.status === 400);

    const events = readEvents(dir);
    check('落盘条数 = 客户端送进来的条数', events.length === 2, `实际 ${events.length}`);
    check('落盘带 received_at（服务端时间）', events.every((e) => typeof e.received_at === 'number'));

    // ---- 2. 口径：北极星的 24 小时窗口（含边界） ----
    const good2 = [
      ev({ event: 'app_open', device_id: 'd1', ts: T0 }),
      // 正好 24 小时：算完成（窗口是"起 24 小时内"，含端点）
      ev({ event: 'workout_finished', device_id: 'd1', ts: T0 + DAY, total_sets: 3 }),
      // 24 小时零 1 毫秒：不算
      ev({ event: 'app_open', device_id: 'd2', ts: T0 }),
      ev({ event: 'workout_finished', device_id: 'd2', ts: T0 + DAY + 1, total_sets: 3 }),
      // 记了 0 组：不算完成（§1.1 明确要求 total_sets ≥ 1）
      ev({ event: 'app_open', device_id: 'd3', ts: T0 }),
      ev({ event: 'workout_finished', device_id: 'd3', ts: T0 + 1000, total_sets: 0 }),
      // 没有任何 app_open 的设备不进分母
      ev({ event: 'workout_finished', device_id: 'd4', ts: T0, total_sets: 5 }),
    ];
    const ns = buildReport(good2).northStar;
    check('北极星分母 = 有 app_open 的 3 台设备', ns.denominator === 3, `实际 ${ns.denominator}`);
    check('北极星分子 = 1 台（24h 边界内）', ns.numerator === 1, `实际 ${ns.numerator}`);

    // ---- 3. 漏斗与 tap_count ----
    const funnelEvents = [
      ev({ event: 'app_open', device_id: 'd1' }),
      ev({ event: 'app_open', device_id: 'd2' }),
      ev({ event: 'app_open', device_id: 'd3' }),
      ev({ event: 'app_open', device_id: 'd4' }),
      ev({ event: 'workout_started', device_id: 'd1' }),
      ev({ event: 'workout_started', device_id: 'd2' }),
      ev({ event: 'set_logged', device_id: 'd1', tap_count: 1 }),
      ev({ event: 'set_logged', device_id: 'd1', tap_count: 3 }),
      ev({ event: 'workout_finished', device_id: 'd1', total_sets: 2 }),
    ];
    const r = buildReport(funnelEvents);
    check('漏斗：app_open 分母 4', r.funnel.app_open === 4);
    check('漏斗：workout_started = 50%', Math.abs(r.funnel.workout_started - 0.5) < 1e-9);
    check('漏斗：first_set_logged = 25%', Math.abs(r.funnel.first_set_logged - 0.25) < 1e-9);

    const tap = r.tapCount['1.7.0'];
    check('tap_count 中位数 = 2（1 与 3 的中间）', tap.median === 2, `实际 ${tap.median}`);
    check('tap_count P90 = 3', tap.p90 === 3, `实际 ${tap.p90}`);

    check('一致性自查对得上（2 组 vs 2 条 set_logged）', r.sanity.setLogged === r.sanity.declaredNormalSets);

    // ---- 4. 纯函数边界 ----
    check('空数组的中位数是 null 而不是 0（分母为 0 时不许编一个数）', median([]) === null);
    check('P90 用 nearest-rank（5 个数的 P90 是第 5 个）', percentile([1, 2, 3, 4, 5], 90) === 5);
    check('没有数据时北极星率是 null', buildReport([]).northStar.rate === null);

    // ---- 5. 真的起一次 HTTP（客户端走的就是这条路） ----
    //
    // 两处刻意的写法，都是被**不稳定的门禁**逼出来的：
    //   1. 显式绑定 127.0.0.1 —— 只写 `listen(0)` 时，某些环境下监听在 `::` 上，
    //      而客户端连的是 IPv4 的 127.0.0.1，偶发不通。
    //   2. 第一个请求**重试** —— 2026-09-30 机器负载 8.4 时这里抛过一次
    //      `fetch failed / read ECONNRESET`，整层门禁变红；单跑又立刻通过。
    //      这种抖动最坏的地方不是它本身，而是**它会让人开始忽略门禁**。
    //      （重试只包第一个请求：后面几个请求证明的是同一件事，真坏了照样红。）
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const port = server.address().port;
    const post = () => fetch(`http://127.0.0.1:${port}/v1/events`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ events: [ev({ event: 'set_logged', tap_count: 1 })] }),
    });
    let res;
    for (let attempt = 1; ; attempt++) {
      try {
        res = await post();
        break;
      } catch (e) {
        if (attempt >= 3) throw e;
        await new Promise((r) => setTimeout(r, 150 * attempt));
      }
    }
    check('HTTP 收下并回 202', res.status === 202, `实际 ${res.status}`);
    const health = await (await fetch(`http://127.0.0.1:${port}/healthz`)).json();
    check('healthz 报出了事件数', health.events >= 3, JSON.stringify(health));
    await new Promise((resolve) => server.close(resolve));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }

  if (failures.length) {
    console.error(`✗ 埋点自检失败 ${failures.length} 项：`);
    for (const f of failures) console.error(`  · ${f}`);
    return 1;
  }
  console.log('✓ 埋点链路自检通过（收集端收/拒/落盘 · 北极星边界 · 漏斗 · tap_count · HTTP）');
  return 0;
}

if (process.argv[1] && process.argv[1].endsWith('collector.selftest.mjs')) {
  process.exit(await selftest());
}
