#!/usr/bin/env node
/**
 * 练了么 · 埋点口径计算（北极星 / 漏斗 / 发布门禁）
 *
 * **它解决什么**：`docs/analytics.md` 把指标定义写得非常死
 * （分母是"首次 app_open 的设备"、窗口 24 小时、门禁是"tap_count 中位数不高于上一版"），
 * 但**没有任何东西能把它算出来** —— 口径只活在文档里，就一定会被各自解释。
 * 这个脚本是那份定义的**可执行版本**：同一份数据、同一个问题，只有一种答案。
 *
 * 用法：
 *   node tool/analytics-report.mjs                       # 读 server/data
 *   node tool/analytics-report.mjs --dir path/to/data
 *   node tool/analytics-report.mjs --json                # 机器可读
 *   node tool/analytics-report.mjs --baseline 12         # 与上一版的中位数比（发布门禁）
 *
 * 退出码：`--baseline` 且中位数上升 → 1（发布门禁失败，`docs/analytics.md` §7 的红线）。
 */

import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const DAY_MS = 24 * 60 * 60 * 1000;

/** 读一批 JSONL（收集端落盘的格式，一行一条） */
export function readEvents(dir) {
  if (!existsSync(dir)) return [];
  const out = [];
  for (const f of readdirSync(dir).filter((n) => n.endsWith('.jsonl')).sort()) {
    for (const line of readFileSync(join(dir, f), 'utf8').split('\n')) {
      if (!line.trim()) continue;
      try { out.push(JSON.parse(line)); } catch { /* 坏行跳过 */ }
    }
  }
  return out;
}

/** 中位数（偶数个取中间两个的平均；口径与"看板上的中位数"一致） */
export function median(values) {
  if (!values.length) return null;
  const s = [...values].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

/** 分位数（nearest-rank，向上取整）。P90 是发布门禁看的那个数。 */
export function percentile(values, p) {
  if (!values.length) return null;
  const s = [...values].sort((a, b) => a - b);
  const rank = Math.ceil((p / 100) * s.length);
  return s[Math.min(s.length - 1, Math.max(0, rank - 1))];
}

/**
 * 北极星：**首次 `app_open` 起 24 小时内**完成一次 `workout_finished`（且该次 `total_sets ≥ 1`）
 * 的设备比例（`docs/analytics.md` §1.1）。
 *
 * 三个刻意的取舍，都写在这里免得下一个人自己发明：
 *   1. 分母 = 有 `app_open` 的设备（`device_id` 去重）
 *   2. 窗口锚在**该设备第一次** `app_open` 的 `ts` 上，不是数据里的最早时间
 *   3. `total_sets ≥ 1` 才算完成 —— 一个都没记就退出的不算
 */
export function northStar(events) {
  const firstOpen = new Map();
  const finished = new Map();
  for (const e of events) {
    if (!e.device_id) continue;
    if (e.event === 'app_open') {
      const prev = firstOpen.get(e.device_id);
      if (prev === undefined || e.ts < prev) firstOpen.set(e.device_id, e.ts);
    }
    if (e.event === 'workout_finished') {
      if (!finished.has(e.device_id)) finished.set(e.device_id, []);
      finished.get(e.device_id).push(e);
    }
  }
  let converted = 0;
  for (const [device, t0] of firstOpen) {
    const hits = (finished.get(device) ?? []).filter(
      (e) => e.ts >= t0 && e.ts - t0 <= DAY_MS && Number(e.total_sets ?? 0) >= 1,
    );
    if (hits.length) converted++;
  }
  return {
    denominator: firstOpen.size,
    numerator: converted,
    rate: firstOpen.size ? converted / firstOpen.size : null,
    target: 0.55,
  };
}

/**
 * 转化漏斗（§1.2）：按**设备**算每一步的到达率，分母是 `app_open` 的设备。
 *
 * `first_set_logged` 是**推导**出来的（每个设备的第一条 `set_logged`），
 * 不是单独上报的事件 —— 事件字典里没有它，漏斗图里有它。
 */
export function funnel(events) {
  const open = new Set();
  const started = new Set();
  const firstSet = new Set();
  const finished = new Set();
  for (const e of events) {
    if (!e.device_id) continue;
    if (e.event === 'app_open') open.add(e.device_id);
    if (e.event === 'workout_started') started.add(e.device_id);
    if (e.event === 'set_logged') firstSet.add(e.device_id);
    if (e.event === 'workout_finished' && Number(e.total_sets ?? 0) >= 1) {
      finished.add(e.device_id);
    }
  }
  const of = (set) => (open.size ? [...set].filter((d) => open.has(d)).length / open.size : null);
  return {
    app_open: open.size,
    workout_started: of(started),
    first_set_logged: of(firstSet),
    workout_finished: of(finished),
    targets: { workout_started: 0.8, first_set_logged: 0.7, workout_finished: 0.55 },
  };
}

/**
 * `tap_count` 分布 —— **发布门禁看的是它**（§7：中位数或 P90 比上一版上升就不许发）。
 * 只统计 `set_logged`（那是唯一"记下一组"的事件）。
 */
export function tapCount(events) {
  const byVersion = new Map();
  for (const e of events) {
    if (e.event !== 'set_logged') continue;
    const n = Number(e.tap_count);
    if (!Number.isFinite(n)) continue;
    const v = e.app_version ?? 'unknown';
    if (!byVersion.has(v)) byVersion.set(v, []);
    byVersion.get(v).push(n);
  }
  const out = {};
  for (const [v, ns] of byVersion) {
    out[v] = { n: ns.length, median: median(ns), p90: percentile(ns, 90) };
  }
  return out;
}

/** §5 反指标里**能算的**那几条。算不了的（要跨版本/DAU）如实说明，不假装。 */
export function antiMetrics(events) {
  const started = new Set();
  const finished = new Set();
  for (const e of events) {
    if (!e.device_id) continue;
    if (e.event === 'workout_started') started.add(e.device_id);
    if (e.event === 'workout_finished') finished.add(e.device_id);
  }
  const abandon = started.size
    ? 1 - [...finished].filter((d) => started.has(d)).length / started.size
    : null;
  const events_seen = new Set(events.map((e) => e.event));
  return {
    abandoned_rate: abandon,
    not_computable: [
      events_seen.has('suggestion_shown') ? null : '建议采纳率（客户端还没发 suggestion_* 事件）',
      events_seen.has('set_edited') ? null : '编辑后容量不增长（客户端还没发 set_edited 事件）',
      'tap_count 与 DAU 同时上升（需要两个版本 + DAU，单份数据算不出）',
    ].filter(Boolean),
  };
}

/** 规范里 §12 那条 sanity check：`set_logged` 条数要和 `workout_finished.total_sets` 对得上 */
export function sanity(events) {
  let logged = 0;
  let declared = 0;
  let workouts = 0;
  for (const e of events) {
    if (e.event === 'set_logged') logged++;
    if (e.event === 'workout_finished') {
      workouts++;
      declared += Number(e.total_sets ?? 0);
    }
  }
  return { setLogged: logged, declaredNormalSets: declared, workouts };
}

export function buildReport(events) {
  return {
    events: events.length,
    devices: new Set(events.map((e) => e.device_id).filter(Boolean)).size,
    northStar: northStar(events),
    funnel: funnel(events),
    tapCount: tapCount(events),
    antiMetrics: antiMetrics(events),
    sanity: sanity(events),
  };
}

// ---------------------------------------------------------------- CLI

if (process.argv[1] && process.argv[1].endsWith('analytics-report.mjs')) {
  const argv = process.argv.slice(2);
  const argOf = (n, d) => {
    const i = argv.indexOf(n);
    return i >= 0 && argv[i + 1] ? argv[i + 1] : d;
  };
  const dir = argOf('--dir', join(ROOT, 'server/data'));
  const asJson = argv.includes('--json');
  const baseline = argOf('--baseline', null);

  const events = readEvents(dir);
  const r = buildReport(events);

  const pct = (v) => (v === null ? '—' : `${(v * 100).toFixed(1)}%`);

  if (asJson) {
    console.log(JSON.stringify(r, null, 2));
  } else {
    console.log(`练了么 · 埋点口径报告（${dir}）`);
    console.log(`数据：${r.events} 条事件 / ${r.devices} 台设备\n`);

    console.log('北极星：首次 app_open 起 24h 内完成一次训练（含 ≥1 组）');
    console.log(`  分母 ${r.northStar.denominator} 台 · 分子 ${r.northStar.numerator} 台`
      + ` · **${pct(r.northStar.rate)}**（目标 ≥ ${pct(r.northStar.target)}）\n`);

    console.log('漏斗（分母 = 有 app_open 的设备）');
    console.log(`  app_open          ${r.funnel.app_open}`);
    console.log(`  workout_started   ${pct(r.funnel.workout_started)}（目标 ≥ ${pct(r.funnel.targets.workout_started)}）`);
    console.log(`  first_set_logged  ${pct(r.funnel.first_set_logged)}（目标 ≥ ${pct(r.funnel.targets.first_set_logged)}）`);
    console.log(`  workout_finished  ${pct(r.funnel.workout_finished)}（目标 ≥ ${pct(r.funnel.targets.workout_finished)}）\n`);

    console.log('tap_count（发布门禁：中位数 / P90 不得高于上一版）');
    const versions = Object.keys(r.tapCount);
    if (!versions.length) console.log('  （还没有 set_logged 事件）');
    for (const v of versions) {
      const t = r.tapCount[v];
      console.log(`  ${v.padEnd(12)} n=${t.n}  中位数 ${t.median}  P90 ${t.p90}`);
    }
    console.log('');

    console.log('反指标（§5）');
    console.log(`  训练中途流失率  ${pct(r.antiMetrics.abandoned_rate)}`);
    for (const why of r.antiMetrics.not_computable) console.log(`  ⊘ ${why}`);
    console.log('');

    console.log('一致性自查（§12）');
    console.log(`  set_logged ${r.sanity.setLogged} 条 · `
      + `workout_finished 声明 ${r.sanity.declaredNormalSets} 组（${r.sanity.workouts} 次训练）`
      + `${r.sanity.setLogged === r.sanity.declaredNormalSets ? ' ✓ 对得上' : ' ⚠️ 对不上，先查埋点'}`);
  }

  if (baseline !== null) {
    const current = Object.values(r.tapCount)[0] ?? null;
    const prev = Number(baseline);
    if (current && current.median !== null && current.median > prev) {
      console.error(`\n✗ 发布门禁失败：tap_count 中位数 ${current.median} 高于上一版 ${prev}`);
      console.error('  （docs/analytics.md §7：中位数或 P90 上升，该版本不允许发布）');
      process.exit(1);
    }
    console.log(`\n✓ 发布门禁通过：tap_count 中位数 ${current?.median ?? '—'} ≤ 上一版 ${prev}`);
  }
}
