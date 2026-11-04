#!/usr/bin/env node
/**
 * 练了么 · 文档表格核对（README + docs/*.md 里的 markdown 表格是不是"连着的、列数对的"）
 *
 * **它为什么存在**：这些文档里的表格**大半是要照着填的**（商店表单、软著申请表、
 * 逐条核对清单、状态总览），而 markdown 表格坏起来**很安静**：
 *   * 中间插进一行引用/空行 → 表格被**截断**，后面那些行渲染成"一堆竖线"；
 *   * 少写一个 `|` → 那一行**错列**，读者会把 A 列的值填到 B 列去。
 * 两种都不会报错，只有人眼睛看得出来。2026-09-30 自查时，20 份文档里有 **9 处**这种问题，
 * 其中两处是**我自己**往里插说明时弄断的（Play 数据安全表、iOS 素材表）。
 *
 * 判据三条：
 *   1. 连续的 `|` 行为一组，组的**第二行必须是分隔行**（`|---|---|`）——
 *      没有表头就是被截断了；
 *   2. 组里每一行的**单元格数必须与表头一致**（`|` 前有反斜杠的 `\|` 不算分隔符）；
 *   3. **表头之后不许再出现分隔行**（2026-11-04 补）：那通常是"表头被抄了两遍"
 *      （`| 截图 | 说明 |` + `|---|---|` 又写了一次），渲染时那行 `---` 会原样印进 PDF。
 *      真实事故：`docs/copyright-manual.md` 第四节的配图表就是这么坏的 ——
 *      而它是**要交给版权中心的提交材料**，列数对得上，所以前两条都放它过去。
 *
 * 刻意做对的两件事（否则误报会把人逼到关掉守卫）：
 *   * **跳过围栏代码块**：代码里的 `|`（管道）不是表格；
 *   * **认转义竖线**：`` `string \| null` `` 是一个单元格，不是两个。
 *
 * 用法：
 *   node tool/check-doc-tables.mjs              # 扫 README + docs/*.md
 *   node tool/check-doc-tables.mjs --selftest   # 自检（造几张坏表，验它抓得住）
 *
 * 退出码：任何一处坏表 → 1。
 */

import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { allDocFiles } from './lib/docs.mjs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** 按**未转义**的竖线切单元格。 */
const cells = (line) => line.replace(/\\\|/g, '\u0000').split('|').map((c) => c.trim());

/** 分隔行：只有 -、:、空格与竖线（转义过的当普通字符）。 */
const isSeparator = (line) => /^\|[\s\-:|]+\|$/.test(line.replace(/\\\|/g, 'x'));

function inspect(root) {
  const problems = [];
  const docs = allDocFiles(root);
  let tables = 0;

  for (const rel of docs) {
    let text;
    try { text = readFileSync(join(root, rel), 'utf8'); } catch { continue; }
    const lines = text.split('\n');
    let fence = false;
    let i = 0;
    while (i < lines.length) {
      const line = lines[i];
      if (line.trimStart().startsWith('```')) { fence = !fence; i += 1; continue; }
      if (fence || !line.startsWith('|')) { i += 1; continue; }
      const start = i;
      while (i < lines.length && lines[i].startsWith('|')) i += 1;
      const block = lines.slice(start, i);
      tables += 1;
      if (block.length < 2 || !isSeparator(block[1])) {
        problems.push(`${rel}:${start + 1} 起有 ${block.length} 行「表格」，但第二行不是分隔行 —— `
          + '表格被截断了（中间插了引用/空行？），渲染出来是一堆竖线');
        continue;
      }
      const n = cells(block[0]).length - 2; // 去掉首尾空串
      block.forEach((row, k) => {
        const m = cells(row).length - 2;
        if (m !== n) {
          problems.push(`${rel}:${start + k + 1} 这行有 ${m} 个单元格，表头是 ${n} 个 —— `
            + '表格错列，读者会把 A 列的值填到 B 列');
        }
        // 第 0 行是表头、第 1 行是分隔行；再往后出现分隔行 = 表头/分隔线被抄了两遍
        if (k >= 2 && isSeparator(row)) {
          problems.push(`${rel}:${start + k + 1} 表格**中间**又出现一行分隔线（表头被抄了两遍？）—— `
            + '列数对得上，所以只看列数的检查放它过去；但渲染出来那行 `---` 会原样印在表里'
            + '（提交材料里那是一条没意义的横杠）');
        }
      });
    }
  }
  return { problems, docs: docs.length, tables };
}

// ───────────────────────────────────────────────────────────── 自检
function selftest() {
  const makeTree = (doc, rootDoc) => {
    const root = mkdtempSync(join(tmpdir(), 'lianleme-tables-'));
    mkdirSync(join(root, 'docs'), { recursive: true });
    writeFileSync(join(root, 'README.md'), '# x\n');
    writeFileSync(join(root, 'docs/a.md'), doc);
    if (rootDoc) writeFileSync(join(root, 'ROADMAP.md'), rootDoc);
    return root;
  };
  const good = '| A | B |\n|---|---|\n| 1 | 2 |\n';
  const cases = [
    ['规整的表 → 绿', good, true, null],
    ['第二行不是分隔行（被截断）', '| A | B |\n\n| 1 | 2 |\n| 3 | 4 |\n', false, '不是分隔行'],
    ['行里少一个竖线（错列）', '| A | B | C |\n|---|---|---|\n| 1 | 2 |\n', false, '个单元格'],
    ['转义竖线算一个单元格（不能误报）', '| A | B |\n|---|---|\n| `string \\| null` | 2 |\n', true, null],
    ['围栏代码块里的竖线不是表格（不能误报）', '```\ngrep x | head\ncat a | wc -l\n```\n', true, null],
    ['两张表连着但各自有表头 → 绿', good + '\n' + good, true, null],
    // ★ 真实事故的回归（2026-11-04）：`docs/copyright-manual.md` 第四节的配图表
    //   表头被写了两遍（`| 截图 | 说明 |` + 第二条 `|---|---|`），列数完全对得上，
    //   所以只核"截断/错列"的判据放它过去了 —— 而它是要交给版权中心的提交材料。
    ['表头之后又出现一条分隔线（表头抄了两遍）→ 必须报',
      '| A | B |\n|---|---|\n| A | B |\n|---|---|\n| 1 | 2 |\n', false, '表格**中间**又出现一行分隔线'],
    // ★ 真实事故的回归：`ROADMAP.md` 的「一眼看懂」阶段表被一行 `>` 引用**从中间截断**，
    //   第 6/7/8 行渲染成乱竖线 —— 而当时没有守卫扫这个文件，所以它是绿的。
    ['根目录 ROADMAP.md 里被截断的表 → 必须报', good, false, '不是分隔行',
      '| 阶段 | 状态 |\n|---|---|\n\n| 6 | 🟡 |\n| 7 | 🟡 |\n'],
  ];
  let bad = 0;
  for (const [label, doc, wantGreen, expect, rootDoc] of cases) {
    const root = makeTree(doc, rootDoc);
    const { problems } = inspect(root);
    const green = problems.length === 0;
    let ok = green === wantGreen;
    let why = green ? '' : `　→ ${problems[0].slice(0, 62)}`;
    if (ok && !wantGreen && expect && !problems.some((p) => p.includes(expect))) {
      ok = false;
      why = `　→ 红了，但不是因为「${expect}」（红在：${problems[0].slice(0, 44)}）`;
    }
    if (!ok) bad += 1;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}${why}`);
    rmSync(root, { recursive: true, force: true });
  }
  if (bad) {
    console.error(`\n✗ 自检失败 ${bad} 项 —— 这个工具本身不可信，先修它`);
    process.exit(1);
  }
  console.log('\n✓ 自检通过：被截断的表、错列的行、表头抄两遍都藏不住；'
    + '转义竖线与代码块里的管道不误报');
}

// ───────────────────────────────────────────────────────────────── 跑
if (process.argv.includes('--selftest')) {
  selftest();
} else {
  const rootArg = process.argv.find((a) => a.startsWith('--root='));
  const { problems, docs, tables } = inspect(rootArg ? rootArg.slice('--root='.length) : ROOT);
  console.log('文档表格核对（README + docs/*.md）\n');
  console.log(`  扫了 ${docs} 份文档里的 ${tables} 张表`);
  if (problems.length) {
    console.log('');
    for (const p of problems) console.error(`  \x1b[31m✗\x1b[0m ${p}`);
    console.error(`\n✗ ${problems.length} 处表格问题 —— 这些表大半是要照着填的，`
      + '断了/错列/表头抄两遍，交出去就是填错');
    process.exit(1);
  }
  console.log('\n✓ 所有表格都是连着的、每行列数与表头一致、表头没有抄两遍');
}
