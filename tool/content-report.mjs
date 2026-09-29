#!/usr/bin/env node
/**
 * 练了么 · 内容债的可见形式（动作说明覆盖率）
 *
 * **它解决什么**：动作库有 351 个动作，App 里只有**名字**。
 * 这一类债的危险在于"看不见"：没人会说"我们的说明覆盖率是 12%"，
 * 只会说"差不多写好了"。所以把它变成一个数字 + 一条待办队列。
 *
 * 用法：
 *   node tool/content-report.mjs              # 覆盖率 + 待写队列（按常用度排）
 *   node tool/content-report.mjs --queue 40   # 只打印最该先写的前 40 个
 *   node tool/content-report.mjs --check 50   # 覆盖率低于 50% 视为内容债过重 → 退出码 1
 *
 * **不把它塞进 verify.sh 当门禁**：内容进度不该拦代码合并 ——
 * 但它必须能被一条命令问出来（`--check` 给需要拦的场合留了口子）。
 */

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

export function analyze(seed) {
  const all = seed.exercises ?? [];
  const withText = all.filter((e) => typeof e.instructions === 'string' && e.instructions.trim());
  const missing = all
    .filter((e) => !withText.includes(e))
    .sort((a, b) => b.popularity - a.popularity || a.name.localeCompare(b.name));
  // 推荐位上真的会出现的那些：各部位按常用度前 8 —— 它们没说明才是真问题
  const byGroup = {};
  for (const e of all) {
    if (e.category !== 'strength') continue;
    (byGroup[e.muscle_group] ??= []).push(e);
  }
  const topPerGroup = Object.values(byGroup)
    .flatMap((rows) => rows.sort((a, b) => b.popularity - a.popularity).slice(0, 8))
    .sort((a, b) => b.popularity - a.popularity);
  const topMissing = topPerGroup.filter((e) => !withText.includes(e));
  return {
    total: all.length,
    written: withText.length,
    coverage: all.length ? withText.length / all.length : 0,
    topTotal: topPerGroup.length,
    topWritten: topPerGroup.length - topMissing.length,
    missing,
    topMissing,
  };
}

if (process.argv[1] && process.argv[1].endsWith('content-report.mjs')) {
  const seed = JSON.parse(readFileSync(join(ROOT, 'seed/exercises.json'), 'utf8'));
  const r = analyze(seed);
  const argv = process.argv.slice(2);
  const argOf = (n, d) => {
    const i = argv.indexOf(n);
    return i >= 0 && argv[i + 1] ? Number(argv[i + 1]) : d;
  };
  const pct = (v) => `${(v * 100).toFixed(1)}%`;

  console.log('动作说明覆盖率（内容债的可见形式）');
  console.log(`  全部：${r.written}/${r.total} = **${pct(r.coverage)}**`);
  console.log(`  推荐位（各部位按常用度前 8，共 ${r.topTotal} 个）：`
    + `${r.topWritten}/${r.topTotal} = ${pct(r.topTotal ? r.topWritten / r.topTotal : 0)}`);
  console.log('');

  const queue = argOf('--queue', 0) || argOf('--check', 0);
  if (queue > 0) {
    console.log(`最该先写的 ${queue} 个（按常用度；推荐位上的排最前）:`);
    const seen = new Set();
    const ordered = [...r.topMissing, ...r.missing].filter((e) => {
      if (seen.has(e.id)) return false;
      seen.add(e.id);
      return true;
    });
    for (const e of ordered.slice(0, queue)) {
      console.log(`  ${String(e.popularity).padStart(3)}  ${e.id.padEnd(30)} ${e.name}`);
    }
  }

  const threshold = argOf('--check', null);
  if (threshold !== null) {
    if (r.coverage * 100 < threshold) {
      console.error(`\n✗ 内容债过重：覆盖率 ${pct(r.coverage)} < ${threshold}%`);
      process.exit(1);
    }
    console.log(`\n✓ 覆盖率 ${pct(r.coverage)} ≥ ${threshold}%`);
  }
}
