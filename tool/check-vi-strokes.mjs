#!/usr/bin/env node
/**
 * 练了么 · `vi/*.html` 的**线宽纪律**（VI 计划 T3-7）
 *
 * **它为什么存在**：客户稿子自己的线宽就有 **5 个值** —— `progress-home.html` 一张里
 * 同时有 1.5 / 1.8 / 2 / 3，`tab-icon-system.html` 整张是 1.8。而 VI 交付物里
 * 最重要的一条是"**下一个照做的人不会做错**"：稿子混着，App 就一定会混
 * （`app/lib` 曾经 112 个字形、12 个尺寸、3 套图标族，正是这件事的下游，见 T1-3）。
 *
 * 规则：所有 `vi/*.html` 的 `stroke-width` 只许三个值 —— **2**（默认）、
 * **2.5**（主按钮里压在大色块上的勾）、**3**（120pt 以上的大插画）。
 * 前两个值今天真的在用；第三个是给插画留的口子，**不是"随便可以调粗一点"的意思**。
 *
 * 用法：
 *   node tool/check-vi-strokes.mjs              # 核 vi/*.html
 *   node tool/check-vi-strokes.mjs --selftest   # 自检（造几份假稿子，验它抓得住）
 *
 * 退出码：任何一处越界 → 1。
 */

import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** 三个合法值（字符串形式，因为稿子里就是写的字面量）。 */
export const ALLOWED = ['2', '2.5', '3'];

/** 一份稿子里出现的所有 `stroke-width` 值（去重、排序）。 */
export function strokeWidths(text) {
  const out = new Set();
  for (const m of text.matchAll(/stroke-width:\s*([0-9.]+)/g)) out.add(m[1]);
  return [...out].sort((a, b) => Number(a) - Number(b));
}

/** 核一个目录：返回 [{ file, values, bad }]。 */
export function inspect(dir) {
  const files = readdirSync(dir).filter((f) => f.endsWith('.html')).sort();
  return files.map((f) => {
    const values = strokeWidths(readFileSync(join(dir, f), 'utf8'));
    return { file: f, values, bad: values.filter((v) => !ALLOWED.includes(v)) };
  });
}

function selftest() {
  const tmp = mkdtempSync(join(tmpdir(), 'vi-strokes-'));
  try {
    writeFileSync(join(tmp, 'ok.html'), '<path stroke-width: 2/>');
    writeFileSync(join(tmp, 'exceptions.html'), 'a stroke-width: 2.5 b stroke-width: 3 c');
    writeFileSync(join(tmp, 'bad-1_8.html'), '<path stroke-width: 1.8/>');
    writeFileSync(join(tmp, 'bad-1_5.html'), 'stroke-width: 1.5; stroke-width: 2');
    writeFileSync(join(tmp, 'no-strokes.html'), '<div>没有描边</div>');

    const byName = Object.fromEntries(inspect(tmp).map((r) => [r.file, r]));
    const problems = [];
    if (byName['ok.html']?.bad.length) problems.push('合法值 2 被判成了越界');
    if (byName['exceptions.html']?.bad.length) problems.push('两个例外（2.5 / 3）被判成了越界');
    if (!byName['bad-1_8.html']?.bad.includes('1.8')) problems.push('1.8 没被抓出来');
    if (!byName['bad-1_5.html']?.bad.includes('1.5')) problems.push('1.5 没被抓出来');
    if (byName['no-strokes.html']?.values.length !== 0) problems.push('没有描边的稿子被误报');
    // 两个值混在一份里：只报越界的那个
    if (byName['bad-1_5.html']?.bad.length !== 1) problems.push('一份里混着合法与越界时，只该报越界那一个');

    if (problems.length) {
      console.error('✗ 自检失败：');
      for (const p of problems) console.error(`  - ${p}`);
      return 1;
    }
    console.log('✓ 自检通过 5 条：合法值 / 两个例外 / 1.8 / 1.5 / 无描边 都判对了');
    return 0;
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

function main() {
  if (process.argv.includes('--selftest')) process.exit(selftest());

  const viDir = join(ROOT, 'vi');
  const results = inspect(viDir);
  const offenders = results.filter((r) => r.bad.length);
  const used = new Set(results.flatMap((r) => r.values));

  for (const r of results) {
    if (r.bad.length) {
      console.error(`✗ vi/${r.file}：线宽 ${r.bad.join(' / ')} 不在 {${ALLOWED.join(', ')}} 里` +
        `（整份稿子用的是 ${r.values.join(' / ') || '—'}）`);
    }
  }
  if (offenders.length) {
    console.error(`\n✗ ${offenders.length} 份稿子的线宽越界 —— ` +
      'VI 交付物最重要的一条是"下一个照做的人不会做错"：稿子混着，App 就一定会混');
    process.exit(1);
  }
  console.log(`✓ vi/ 下 ${results.length} 份稿子的线宽只用 ${[...used].sort((a, b) => Number(a) - Number(b)).join(' / ')}` +
    `（合法集合 {${ALLOWED.join(', ')}}）`);
  process.exit(0);
}

// ⚠️ **无条件跑 main**（不写"是不是主模块"的判断）：
// 真源路径里有一个撇号（`Elliot's SSD`），`import.meta.url` 会把它编码成 `%27`。
// 我第一版写的是 `import.meta.url === \`file://${process.argv[1]}\`` ——
// 那个等式在真源路径下**永远为假**，守卫于是一声不吭地什么也不做（连 `--selftest` 都不跑）。
// 仓库里别的工具用的是 `pathToFileURL(...).href`（那个是对的）；
// 这里干脆不判断：少一个能悄悄失效的条件。
main();
