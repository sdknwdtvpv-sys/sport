/**
 * 练了么 · markdown 表格切分的公共零件
 *
 * **为什么有它**：新的工作台要从五份文档里把表格读出来
 * （`ROADMAP.md` 一眼看懂表、`feature-backlog.md` 六节、
 * `release-checklist.md` 的勾选、`decision-index.md` 的 A/B 组、`your-todo.md` 的三节），
 * 五处各写一遍"怎么切一行 `| a | b |`"，就会有五份略有差异的切法 ——
 * 而本项目已经为"三处抄同一份逻辑、改一处漏两处"付过学费
 * （`check-doc-*` 的文档清单、`markdown.mjs` 的渲染器都是因此被抽出来的）。
 *
 * ⚠️ **这是一个"宁可说不，也不猜"的零件。**
 * 切不出来时返回 `null` / 空数组，由调用方把"解析不了"如实显示出来 ——
 * 本项目的铁律是「过期状态比没有状态更坏」，一页看板画一个假的进度条，
 * 比它在那一格写"解析不了"坏得多。
 *
 * 自检：`node tool/lib/markdown-table.mjs --selftest`
 */

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

/** 一行是不是表格行（以 `|` 开头）。 */
export function isRow(line) {
  return /^\s*\|/.test(line);
}

/** 一行是不是表头下的分隔行（`|---|---|`、`| :-- | --: |` 都算）。 */
export function isSeparator(line) {
  return isRow(line) && /^[\s|:-]+$/.test(line.trim()) && line.includes('-');
}

/**
 * 切一行表格。
 *
 * 处理两件真会发生的事：
 *   1. **转义的竖线 `\|`** —— 单元格里写"或"的时候很容易写成 `a \| b`；
 *      不认它，一行就会被切成两格，后面每一列的语义全部错位。
 *   2. **退化行**（只有一个 `|`）不能抛。
 *
 * 注意：`` `a | b` `` 这种**行内代码里的裸竖线仍按分隔符切** —— 与 GitHub 的行为一致。
 * 不假装支持它，是因为"假装支持"的代价是遇到时静默切错，而静默切错正是本项目最怕的那种错。
 */
export function splitRow(line) {
  const s = line.trim().replace(/^\|/, '').replace(/\|$/, '');
  const cells = [];
  let cur = '';
  for (let i = 0; i < s.length; i += 1) {
    const ch = s[i];
    if (ch === '\\' && s[i + 1] === '|') { cur += '|'; i += 1; continue; }
    if (ch === '|') { cells.push(cur.trim()); cur = ''; continue; }
    cur += ch;
  }
  cells.push(cur.trim());
  return cells;
}

/**
 * 把 `lines` 标出"哪些行在围栏代码块里"。
 *
 * **为什么必须有**：`release-checklist.md` 里就有把命令贴进 ``` 的段落，
 * 而那些段落里带着 `|` 与 `- [ ]` 这样的记号。不排除代码块，
 * 就会把"示例文本"当成"真的表格行/待办条目"数进去 ——
 * 页面上多出来的那几条，没有任何办法从界面看出它是假的。
 */
export function fenceMask(lines) {
  const mask = new Array(lines.length).fill(false);
  let fenceChar = null;
  for (let i = 0; i < lines.length; i += 1) {
    const m = /^\s*(`{3,}|~{3,})/.exec(lines[i]);
    if (m) {
      if (!fenceChar) { fenceChar = m[1][0]; mask[i] = true; continue; }
      if (m[1][0] === fenceChar) { fenceChar = null; mask[i] = true; continue; }
    }
    mask[i] = Boolean(fenceChar);
  }
  return mask;
}

/**
 * 从 `lines[start]` 处读一张表（表头 + 分隔行 + 若干数据行）。
 * 不是表就返回 `null`；是表就返回 `{ header, rows, end }`（`end` 是表格之后的第一行下标）。
 */
export function tableAt(lines, start, mask = null) {
  if (mask && mask[start]) return null;
  if (start < 0 || start >= lines.length) return null;
  if (!isRow(lines[start])) return null;
  if (start + 1 >= lines.length || !isSeparator(lines[start + 1])) return null;
  const header = splitRow(lines[start]);
  const rows = [];
  let i = start + 2;
  while (i < lines.length && isRow(lines[i]) && !(mask && mask[i])) {
    rows.push(splitRow(lines[i]));
    i += 1;
  }
  return { header, rows, end: i };
}

/**
 * 找第一张满足 `accept(header)` 的表。
 *
 * `from` / `until` 用来限定搜索区间（一般拿"某个 `##` 节的起止行"）——
 * 同一份文档里常有好几张结构不同的表，**按表头定位比按"第一张表"稳**。
 * 找不到就返回 `null`：调用方据此显示"解析不了"，不许硬凑。
 */
export function findTable(lines, { from = 0, until = lines.length, accept = () => true, mask = null } = {}) {
  const m = mask ?? fenceMask(lines);
  for (let i = from; i < Math.min(until, lines.length); i += 1) {
    if (m[i]) continue;
    const t = tableAt(lines, i, m);
    if (t && accept(t.header)) return { ...t, start: i };
  }
  return null;
}

/** 把一份文档按 `^## ` 切成节。返回 `[{ title, from, until, lines }]`（`#` 一级标题不算节）。 */
export function sections(lines) {
  const out = [];
  let cur = null;
  for (let i = 0; i < lines.length; i += 1) {
    if (/^##\s/.test(lines[i])) {
      if (cur) { cur.until = i; cur.lines = lines.slice(cur.from, i); out.push(cur); }
      cur = { title: lines[i].replace(/^##\s*/, '').trim(), from: i, until: lines.length };
    }
  }
  if (cur) { cur.until = lines.length; cur.lines = lines.slice(cur.from); out.push(cur); }
  return out;
}

/**
 * 去掉行内记号，留一句能给人看的话。
 *
 * ⚠️ 这一条是被真事逼出来的：`Text`/HTML **都不渲染 markdown**，
 * 写了 `**` 用户就真的看到星号 —— 工作台的自检里有一条
 * "渲染出的 HTML 里不许出现裸 `**`"，`plainText` 是它的第一道闸。
 */
export function plainText(s) {
  return String(s ?? '')
    .replace(/\*\*/g, '')
    .replace(/~~/g, '')
    .replace(/`/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

/** 是否含删除线（本仓库"做完了就划掉而不是删掉"，所以删除线 = 已完成）。 */
export function isStruck(s) {
  return /~~/.test(String(s ?? ''));
}

// ───────────────────────────────────────────────────────────── 自检

function selftest() {
  let bad = 0;
  const check = (ok, label, extra = '') => {
    if (!ok) bad += 1;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}${extra ? `　→ ${extra}` : ''}`);
  };

  // 1. 切一行：普通 / 转义竖线 / 退化行
  check(JSON.stringify(splitRow('| a | b |')) === '["a","b"]', '普通一行切成两格', JSON.stringify(splitRow('| a | b |')));
  check(JSON.stringify(splitRow('| a \\| b | c |')) === '["a | b","c"]',
    '★ 转义的竖线不当分隔符（认错了整行后面全部错位）', JSON.stringify(splitRow('| a \\| b | c |')));
  check(splitRow('|').length === 1, '退化行（只有一个竖线）不抛');
  check(JSON.stringify(splitRow('|')) === '[""]', '退化行切出一个空格', JSON.stringify(splitRow('|')));

  // 2. 分隔行识别
  check(isSeparator('|---|---|') && isSeparator('| :-- | --: |'), '分隔行认得出来');
  check(!isSeparator('| a | b |'), '数据行不是分隔行');

  // 3. 读一张完整的表（并且跳过前面那张"假表头"）
  const doc = [
    '前言',
    '|---|---|',
    '| 阶段 | 状态 |',
    '|---|---|',
    '| 0 | ✅ |',
    '| 1 | 🟡 |',
    '',
    '后面还有话',
  ];
  const t = findTable(doc, { accept: (h) => h.includes('阶段') });
  check(t !== null && t.rows.length === 2, '按表头找到正确的表（前面那张假的跳过）', t ? JSON.stringify(t.rows) : 'null');
  check(t !== null && t.end === 6, '表的结束位置对（空行处停）', t ? String(t.end) : 'null');
  check(findTable(doc, { accept: (h) => h.includes('不存在') }) === null,
    '★ 找不到就说找不到（返回 null，不硬凑一张假表）');

  // 4. ★ 围栏代码块里的表格行不许被当成真的表
  const fenced = [
    '| 真表头 |',
    '|---|',
    '| 真行 |',
    '```bash',
    '| 假表头 |',
    '|---|',
    '| 假行 |',
    '```',
  ];
  const m = fenceMask(fenced);
  check(m[4] && m[6] && !m[2], '围栏内的行被标记、围栏外的没有', JSON.stringify(m));
  check(findTable(fenced, { accept: () => true }).rows.length === 1,
    '★ 围栏代码块里的表格行不许被当成真的表');

  // 5. 按 `##` 切节
  const secs = sections(['# 一', '## 二、甲', 'x', '## 三、乙', 'y', '## 四、丙']);
  check(secs.length === 3 && secs[0].title === '二、甲' && secs[2].title === '四、丙',
    '按 ## 切节（# 一级标题不算一节）', JSON.stringify(secs.map((s) => s.title)));
  check(secs[0].lines.length === 2, '每节带上自己的行', JSON.stringify(secs[0].lines));

  // 6. plainText / isStruck
  const p = plainText('**粗体** 与 ~~划掉~~ 与 `code`');
  check(!p.includes('*') && !p.includes('~') && !p.includes('`'),
    '★ 去掉行内记号（HTML 里出现裸 ** 会被工作台自检判红）', p);
  check(isStruck('~~已经做完的事~~') && !isStruck('还没做的事'),
    '删除线判据（本仓库：划掉 = 已完成）');

  // 7. ★ 在真仓库上跑一次 —— 防止"全都解析失败"其实是我自己写错了
  //    （工作台第一版就踩过同类的坑：守卫路径漏了 tool/，13 个守卫全部报红）
  const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
  let realOk = false;
  let realWhy = '';
  try {
    const lines = readFileSync(join(root, 'ROADMAP.md'), 'utf8').split('\n');
    const rt = findTable(lines, { accept: (h) => h.includes('阶段') });
    realOk = rt !== null && rt.rows.length >= 8;
    realWhy = rt ? `${rt.rows.length} 行` : 'null';
  } catch (e) {
    realWhy = e.message.split('\n')[0];
  }
  check(realOk, '★ 在真 ROADMAP.md 上找到「一眼看懂」表（防"全红"其实是我错了）', realWhy);

  if (bad) {
    console.error(`\n✗ markdown-table 自检失败 ${bad} 项`);
    process.exit(1);
  }
  console.log('\n✓ 自检通过：切行（含转义竖线）· 读表并跳过假表头 · 围栏排除 · 切节 · 去记号 · 真仓库能读到');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href
    && process.argv.includes('--selftest')) {
  selftest();
}
