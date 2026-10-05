/**
 * 练了么 · 五份"陈述项目现状"的文档 → 结构化
 *
 * **它解决什么**：项目现在的"还剩什么、卡在哪"散在五份文档里，各自有各自的写法：
 *   * `ROADMAP.md`        —— 一张「一眼看懂」表：8 阶段 × 状态 × 卡在谁那
 *   * `docs/release-checklist.md` —— `- [ ]` / `- [x]` 勾选，按 `## N.` 分节
 *   * `docs/feature-backlog.md`   —— 六节，有表有列表有正文
 *   * `docs/decision-index.md`    —— A/B/C… 分组表
 *   * `docs/your-todo.md`         —— 二/三/四节是"卡在你那边"，五节是"我这边会做的"
 * 想一眼看全，就得五份都翻、还在各自的写法里数数。这个模块把它们读成同一形状。
 *
 * ⚠️ **贯穿全篇的一条规矩：解析不了就返回 `available: false` + 原因，不猜。**
 * 本项目的铁律是「过期状态比没有状态更坏」—— 一页看板画一个假的进度条，
 * 比它在那一格写「解析不了：找不到那张表」坏得多。
 * 所以这里**故意**不做模糊匹配：表头对不上就是对不上。
 *
 * 自检：`node tool/lib/collect-docs.mjs --selftest`
 */

import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { findTable, fenceMask, isStruck, plainText, sections } from './markdown-table.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, '..', '..');

/** 状态记号：这四种覆盖了本仓库全部写法。取不到就给 `unknown`，不默认成"完成"。 */
export const STATUS_TOKENS = [
  { token: '✅', key: 'done', label: '已完成' },
  { token: '🟡', key: 'partial', label: '部分 / 就差一步' },
  { token: '⏸', key: 'paused', label: '明确推后' },
  { token: '⬜', key: 'todo', label: '未开始' },
];

function statusOf(cell) {
  for (const t of STATUS_TOKENS) if (cell.includes(t.token)) return t.key;
  return 'unknown';
}

function readText(root, rel) {
  const p = join(root, rel);
  if (!existsSync(p)) return { ok: false, why: `找不到 ${rel}` };
  try {
    return { ok: true, text: readFileSync(p, 'utf8') };
  } catch (e) {
    return { ok: false, why: `读不了 ${rel}：${e.message.split('\n')[0]}` };
  }
}

// ─────────────────────────────────────────────── ROADMAP.md「一眼看懂」

/**
 * 纯函数：从 `ROADMAP.md` 正文里读「一眼看懂」那张表。
 *
 * 判据是**表头里同时有"阶段"和"卡在谁那"** —— 不按"第一章之后第一张表"取，
 * 因为那份文档里别处还有别的表，位置一变就会读错一张（读错一张表的后果是
 * 页面上显示 8 个阶段里有一半是别人的数字，而且看不出错）。
 */
export function parseRoadmapStages(text) {
  const lines = text.split('\n');
  const sec = sections(lines).find((s) => s.title.includes('一眼看懂'));
  const t = findTable(lines, {
    from: sec ? sec.from : 0,
    until: sec ? sec.until : lines.length,
    accept: (h) => h.includes('阶段') && h.some((x) => x.includes('卡在谁')),
  });
  if (!t) return { available: false, why: '找不到「一眼看懂」表（表头应含"阶段"与"卡在谁那"）', stages: [] };

  const iName = t.header.findIndex((h) => h.includes('阶段'));
  const iStatus = t.header.findIndex((h) => h.includes('状态'));
  const iOwner = t.header.findIndex((h) => h.includes('卡在谁'));
  const stages = t.rows.map((c) => ({
    n: plainText(c[0] ?? ''),
    name: plainText(c[iName] ?? ''),
    status: statusOf(c[iStatus] ?? ''),
    statusText: plainText(c[iStatus] ?? ''),
    owner: plainText(c[iOwner] ?? ''),
  }));
  if (!stages.length) return { available: false, why: '「一眼看懂」表里一行都没有', stages: [] };
  return { available: true, why: null, stages };
}

export function readRoadmapStages(root = REPO) {
  const r = readText(root, 'ROADMAP.md');
  if (!r.ok) return { available: false, why: r.why, stages: [] };
  return parseRoadmapStages(r.text);
}

// ─────────────────────────────────────────────── release-checklist.md

/**
 * 纯函数：读 `release-checklist.md` 的 `- [ ]` / `- [x]` 勾选，按 `## N.` 分节。
 *
 * 两处刻意：
 *   1. **围栏代码块里的行不算** —— 那份文档里有把命令贴出来的段落，
 *      里面的示例可能带 `- [ ]`；数进去就是凭空多出几个"待办"。
 *   2. **含 `⛔` 的节标成硬门槛** —— 这是原文档自己的标记（"这一步不过就上不了架"），
 *      页面上要能一眼分出来，而不是和普通条目混在一起排队。
 */
export function parseReleaseChecklist(text) {
  const lines = text.split('\n');
  const mask = fenceMask(lines);
  const secs = sections(lines).filter((s) => /^[0-9]/.test(s.title)); // 只认 `## 0.` `## 1.` 这种编号节
  if (!secs.length) return { available: false, why: '找不到编号节（`## 1.` 这种）', sections: [], totals: { done: 0, total: 0 } };

  const out = [];
  for (const s of secs) {
    const items = [];
    for (let i = s.from; i < s.until; i += 1) {
      if (mask[i]) continue;
      const m = /^\s*-\s*\[([ xX])\]\s*(.*)$/.exec(lines[i]);
      if (!m) continue;
      items.push({ done: m[1].toLowerCase() === 'x', text: plainText(m[2]) });
    }
    out.push({
      title: s.title,
      hard: s.title.includes('⛔'),
      items,
      done: items.filter((x) => x.done).length,
      total: items.length,
    });
  }
  const totals = {
    done: out.reduce((a, s) => a + s.done, 0),
    total: out.reduce((a, s) => a + s.total, 0),
  };
  return { available: true, why: null, sections: out, totals };
}

export function readReleaseChecklist(root = REPO) {
  const r = readText(root, 'docs/release-checklist.md');
  if (!r.ok) return { available: false, why: r.why, sections: [], totals: { done: 0, total: 0 } };
  return parseReleaseChecklist(r.text);
}

// ─────────────────────────────────────────────── feature-backlog.md

/**
 * 纯函数：读 `docs/feature-backlog.md` 的六节。
 *
 * 这一份是**半结构化**的：二/三/五节是表，四节是 `- ❌ …` 列表，六节是正文。
 * 所以每一节返回一个 `kind`（`table` / `list` / `prose`），让页面按形状渲染；
 * 表的行按"任一格里出现 `~~划掉~~` 或 `✅`"判完成 —— 与 `your-todo.md` 同一套判据。
 *
 * 缺某一节时**单独把那一节标成缺**，不让整份文档解析失败：
 * 六节里少一节，另外五节的信息仍然是真的，一起丢掉反而更亏。
 */
export function parseFeatureBacklog(text) {
  const lines = text.split('\n');
  const mask = fenceMask(lines);
  const secs = sections(lines).filter((s) => /^[一二三四五六七八九十]+、/.test(s.title));
  if (!secs.length) return { available: false, why: '找不到「一、二、…」这种编号节', sections: [] };

  const out = [];
  for (const s of secs) {
    const t = findTable(lines, { from: s.from, until: s.until, mask });
    if (t) {
      const items = t.rows.map((c) => ({
        text: plainText(c[1] ?? c[0] ?? ''),
        done: c.some((x) => isStruck(x)) || c.some((x) => x.includes('✅')),
      }));
      out.push({ title: s.title, kind: 'table', header: t.header, items, done: items.filter((x) => x.done).length });
      continue;
    }
    const bullets = [];
    for (let i = s.from; i < s.until; i += 1) {
      if (mask[i]) continue;
      const m = /^\s*[-*]\s+(.*)$/.exec(lines[i]);
      // 判"做完"的两个信号与表格那一路保持一致：划掉（`~~`）或行首 ✅。
      // 只认 `~~` 会漏掉本仓库大量"- ✅ **…已做完**"的写法（五节里就有三条），
      // 漏掉的后果是页面上把已经做完的事还列在"要做的"里。
      if (m) bullets.push({ text: plainText(m[1]), done: isStruck(m[1]) || m[1].includes('✅') });
    }
    if (bullets.length) {
      out.push({ title: s.title, kind: 'list', items: bullets, done: bullets.filter((x) => x.done).length });
      continue;
    }
    const body = s.lines.slice(1).filter((l) => l.trim() && !/^>/.test(l.trim()));
    out.push({ title: s.title, kind: 'prose', items: [], done: 0, note: plainText(body[0] ?? '').slice(0, 120) });
  }
  return { available: true, why: null, sections: out };
}

export function readFeatureBacklog(root = REPO) {
  const r = readText(root, 'docs/feature-backlog.md');
  if (!r.ok) return { available: false, why: r.why, sections: [] };
  return parseFeatureBacklog(r.text);
}

// ─────────────────────────────────────────────── decision-index.md

/**
 * 纯函数：读 `docs/decision-index.md` 的分组表（A/B/C…）。
 *
 * 这一页的价值不在条目本身（它自己写着"只做索引、不复制正文"），
 * 而在于**分组**：A 是"条件到了就能做"、B 是"价值判断上否掉的"。
 * 所以这里按节分组返回，页面上也按组显示 —— 把 A 和 B 混成一张清单，
 * 就等于把这份文档唯一的信息量扔了。
 */
export function parseDecisionIndex(text) {
  const lines = text.split('\n');
  const mask = fenceMask(lines);
  const secs = sections(lines).filter((s) => /^[A-Z][.、]/.test(s.title));
  if (!secs.length) return { available: false, why: '找不到 A/B/C… 分组节', groups: [] };
  const groups = [];
  for (const s of secs) {
    const t = findTable(lines, { from: s.from, until: s.until, mask });
    const rows = t ? t.rows.map((c) => ({ name: plainText(c[0] ?? ''), cond: plainText(c[1] ?? ''), src: plainText(c[2] ?? '') })) : [];
    groups.push({ title: s.title, rows });
  }
  const total = groups.reduce((a, g) => a + g.rows.length, 0);
  if (!total) return { available: false, why: 'A/B/C… 各节里一张表都没读到', groups };
  return { available: true, why: null, groups };
}

export function readDecisionIndex(root = REPO) {
  const r = readText(root, 'docs/decision-index.md');
  if (!r.ok) return { available: false, why: r.why, groups: [] };
  return parseDecisionIndex(r.text);
}

// ─────────────────────────────────────────────── your-todo.md

/**
 * 纯函数：读 `docs/your-todo.md`。
 *
 * **判据沿用仓库自己的写法**：做完了就**划掉**而不是删掉（划掉保留了"这件事曾经存在"），
 * 所以"标题里还有 `~~` = 已完成"。这条判据是有代价的（它依赖作者守规矩），
 * 但它同时是**唯一**能把"已完成"和"还没做"分开的信号 —— 所以它进自检钉着。
 *
 * 二/三/四节是"卡在你那边"，五节是"我这边会做的"，**两者不许混**：
 * 页面上把它们混成一张清单，就会让人以为"卡着我"的还有几十件。
 */
export function parseTodos(text, cfg = {}) {
  const sectionsWanted = cfg.sections ?? ['二', '三', '四'];
  const mineSection = cfg.mine ?? '五';
  const lines = text.split('\n');
  const mask = fenceMask(lines);
  const secs = sections(lines);

  const pick = (prefix) => secs.find((s) => new RegExp(`^${prefix}[、.]`).test(s.title));

  const items = [];
  const out = [];
  for (const p of sectionsWanted) {
    const s = pick(p);
    if (!s) continue;
    const t = findTable(lines, { from: s.from, until: s.until, mask });
    if (!t) { out.push({ title: s.title, header: [], items: [], note: '这一节里没有表 —— 判据对不上，不猜' }); continue; }
    const secItems = t.rows.map((c) => ({
      id: plainText(c[0] ?? ''),
      title: plainText(c[1] ?? ''),
      done: isStruck(c[1] ?? ''),
      cells: c.map(plainText),
    }));
    items.push(...secItems.map((x) => ({ ...x, section: s.title })));
    out.push({ title: s.title, header: t.header.map(plainText), items: secItems, raw: t });
  }

  // 五节：「我这边会做的」——多是划掉的历史条目 + 少量 bullet
  const mine = pick(mineSection);
  const mineItems = [];
  if (mine) {
    for (let i = mine.from; i < mine.until; i += 1) {
      if (mask[i]) continue;
      const m = /^\s*[-*]\s+(.*)$/.exec(lines[i]);
      if (m) mineItems.push({ text: plainText(m[1]).slice(0, 160), done: isStruck(m[1]) || m[1].includes('✅') });
    }
  }

  if (!out.length && !mineItems.length) {
    return { available: false, why: '二/三/四/五 节一个都没读到', sections: [], items: [], open: [], mine: [] };
  }
  return {
    available: true,
    why: null,
    sections: out,
    items,
    open: items.filter((x) => !x.done),
    mine: mineItems,
    mineOpen: mineItems.filter((x) => !x.done),
  };
}

export function readTodos(root = REPO) {
  const r = readText(root, 'docs/your-todo.md');
  if (!r.ok) return { available: false, why: r.why, sections: [], items: [], open: [], mine: [] };
  return parseTodos(r.text);
}

// ───────────────────────────────────────────────────────────── 自检

const FIXTURE_ROADMAP = [
  '# 路线图',
  '',
  '## 一眼看懂',
  '',
  '| # | 阶段 | 状态 | 卡在谁那 |',
  '|---|---|---|---|',
  '| **0** | 钉住工程 | ✅ 完成 | — |',
  '| **1** | 装到真机 | 🟡 就差一台服务器 | 你（服务器） |',
  '| **2** | 去练一次 | ⬜ 未开始 | 只能人做 |',
  '',
  '## 别的节',
  '',
  '| 无关 | 的表 |',
  '|---|---|',
  '| x | y |',
].join('\n');

const FIXTURE_CHECKLIST = [
  '# 清单',
  '',
  '## 1. ⛔ 真机验证',
  '',
  '- [x] 已经做完的甲',
  '- [ ] 还没做的乙',
  '```bash',
  '- [ ] 这是示例文本，不许被数进去',
  '```',
  '- [X] 大写 X 也算做完',
  '',
  '## 2. 发布签名',
  '',
  '- [ ] 生成 keystore',
  '',
  '## 8. 没编号也认的节（`## 8.` 是编号）',
  '',
  '- [x] 一条',
].join('\n');

const FIXTURE_BACKLOG = [
  '# 待办总表',
  '',
  '## 一、现在就能做',
  '',
  '| # | 决定 | 现状 |',
  '|---|---|---|',
  '| 1 | ~~已经结清的~~ ✅ 拍板 B | 已完成 |',
  '| 2 | 还没做的那件 | 待定 |',
  '',
  '## 四、明确不做',
  '',
  '- ❌ 社区',
  '- ❌ 排行榜',
  '',
  '## 六、下一版不排功能',
  '',
  '这一节只有正文，没有表也没有列表。',
].join('\n');

const FIXTURE_DECISIONS = [
  '# 决策索引',
  '',
  '## A. 有明确解禁条件的',
  '',
  '| 能力 | 触发条件 | 出处 |',
  '|---|---|---|',
  '| **Watch** | DAU 稳定 | `tech-decisions.md` |',
  '',
  '## B. 价值判断上否掉的',
  '',
  '| 能力 | 触发条件 | 出处 |',
  '|---|---|---|',
  '| **社区** | 改定位才能解禁 | `PRODUCT.md` |',
].join('\n');

const FIXTURE_TODO = [
  '# 等你的',
  '## 一、最长的两根杆',
  '| 1 | 不该被算进来 | x | x |',
  '## 二、必须你本人办的',
  '',
  '| # | 事项 | 为什么必须你来 | 卡住什么 | 备注 |',
  '|---|---|---|---|---|',
  '| 3 | **生成正式 keystore** | 私钥必须你保管 | 商店产物 | 细节见 x |',
  '| 4 | ~~**隐私政策 URL**~~ ✅ 已完成 | 需要你的名义 | 提交必填 | — |',
  '',
  '## 三、需要你拍板的技术选择',
  '',
  '| # | 选择 | 为什么问你 | 我的建议 |',
  '|---|---|---|---|',
  '| 9 | **备份范围** | 这是范围决策 | 按现状 |',
  '',
  '## 四、一分钟就能解锁的',
  '',
  '| # | 事项 | 解锁什么 |',
  '|---|---|---|',
  '| 12 | **解锁真机** | 云备份端到端 |',
  '',
  '## 五、我这边接下来会做的',
  '',
  '- ✅ **部署包已备好**',
  '- 线 1 里不需要 Xcode 的部分',
].join('\n');

function selftest() {
  let bad = 0;
  const check = (ok, label, extra = '') => {
    if (!ok) bad += 1;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}${extra ? `　→ ${extra}` : ''}`);
  };

  // 1. ROADMAP
  const rm = parseRoadmapStages(FIXTURE_ROADMAP);
  check(rm.available && rm.stages.length === 3, 'ROADMAP：读到 3 个阶段', JSON.stringify(rm.stages.map((s) => s.n)));
  check(rm.stages[0].status === 'done' && rm.stages[1].status === 'partial' && rm.stages[2].status === 'todo',
    'ROADMAP：✅/🟡/⬜ 三种状态分得开', JSON.stringify(rm.stages.map((s) => s.status)));
  check(rm.stages[1].owner === '你（服务器）', 'ROADMAP：卡在谁那读出来', rm.stages[1].owner);
  check(rm.stages[1].statusText.includes('就差一台服务器'), 'ROADMAP：状态原文保留（不只剩一个 emoji）', rm.stages[1].statusText);
  check(!rm.stages.some((s) => s.name.includes('无关')), 'ROADMAP：没有读到后面那张无关的表');
  const rmMissing = parseRoadmapStages('# 没有那张表\n\n正文\n');
  check(!rmMissing.available && rmMissing.stages.length === 0,
    '★ ROADMAP：找不到表时说找不到（不画假进度）', rmMissing.why);
  const rmWrongHeader = parseRoadmapStages('# x\n## 一眼看懂\n\n| 阶段 | 别的 |\n|---|---|\n| a | b |\n');
  check(!rmWrongHeader.available,
    '★ ROADMAP：表头缺"卡在谁那"就不认（表头对不上就是对不上）', rmWrongHeader.why);

  // 2. release-checklist
  const cl = parseReleaseChecklist(FIXTURE_CHECKLIST);
  check(cl.available && cl.totals.total === 5, '清单：共 5 条（围栏里那条不算、大写 X 算）', JSON.stringify(cl.totals));
  check(cl.totals.done === 3, '清单：已经做完 3 条（含大写 X）', JSON.stringify(cl.totals));
  check(cl.sections[0].hard === true && cl.sections[1].hard === false, '清单：⛔ 硬门槛标出来', JSON.stringify(cl.sections.map((s) => s.hard)));
  check(!cl.sections.some((s) => s.items.some((i) => i.text.includes('示例文本'))),
    '★ 清单：围栏代码块里的 `- [ ]` 不许被当成待办');
  check(cl.sections.length === 3, '清单：按 ## 分节（含 4.5/6.5 那种带点的编号）', String(cl.sections.length));
  const clNo = parseReleaseChecklist('# 没有编号节\n\n随便写点\n');
  check(!clNo.available, '★ 清单：没有编号节时说找不到', clNo.why);

  // 3. feature-backlog
  const fb = parseFeatureBacklog(FIXTURE_BACKLOG);
  check(fb.available && fb.sections.length === 3, '功能待办：读到 3 节', JSON.stringify(fb.sections.map((s) => s.title)));
  check(fb.sections[0].kind === 'table' && fb.sections[0].done === 1,
    '功能待办：表节按"划掉或 ✅"判完成', JSON.stringify({ kind: fb.sections[0].kind, done: fb.sections[0].done }));
  check(fb.sections[1].kind === 'list' && fb.sections[1].items.length === 2,
    '功能待办：列表节（四、明确不做）按 bullet 读', JSON.stringify(fb.sections[1].items));
  check(fb.sections[2].kind === 'prose', '功能待办：纯正文节也如实标成 prose，不硬造条目', fb.sections[2].kind);

  // 4. decision-index
  const di = parseDecisionIndex(FIXTURE_DECISIONS);
  check(di.available && di.groups.length === 2, '决策索引：读到 A/B 两组', JSON.stringify(di.groups.map((g) => g.title)));
  check(di.groups[0].rows[0].name === 'Watch' && di.groups[1].rows[0].name === '社区',
    '决策索引：组与组不混（A 是"能解禁"、B 是"否掉"）', JSON.stringify(di.groups.map((g) => g.rows.length)));
  check(!parseDecisionIndex('# 没有分组\n').available, '★ 决策索引：没有分组时说找不到');

  // 5. your-todo
  const td = parseTodos(FIXTURE_TODO);
  check(td.available && td.items.length === 4, '待办：二/三/四共 4 条（一、五 不算进来）', String(td.items.length));
  check(td.open.length === 3 && !td.open.some((i) => i.title.includes('隐私政策')),
    '★ 待办：划掉的（已完成）不算"卡在你那边"', JSON.stringify(td.open.map((i) => i.title)));
  check(td.sections.length === 3, '待办：三节都读到了', String(td.sections.length));
  check(td.mine.length === 2 && td.mineOpen.length === 1,
    '★ 待办：五节单列成"我这边会做的"，不混进"卡你"', JSON.stringify({ mine: td.mine.length, open: td.mineOpen.length }));
  check(td.items[0].cells.length === 5, '待办：整行原样保留（列数不一的节也不丢列）', String(td.items[0].cells.length));

  // 6. ★ 在真仓库上跑一遍 —— 防止"全都解析失败"其实是我自己写错了
  //    （工作台第一版就踩过同类坑：守卫路径漏了 tool/，13 个守卫全部报红）
  const realChecks = [
    ['ROADMAP.md', readRoadmapStages(REPO), (r) => r.available && r.stages.length >= 8, '阶段数'],
    ['release-checklist.md', readReleaseChecklist(REPO), (r) => r.available && r.totals.total > 0, '条目数'],
    ['feature-backlog.md', readFeatureBacklog(REPO), (r) => r.available && r.sections.length >= 5, '节数'],
    ['decision-index.md', readDecisionIndex(REPO), (r) => r.available && r.groups.length >= 3, '组数'],
    ['your-todo.md', readTodos(REPO), (r) => r.available && r.items.length > 0 && r.mine.length > 0, '待办数'],
  ];
  for (const [name, res, pred, what] of realChecks) {
    const ok = pred(res);
    check(ok, `★ 真仓库：${name} 读得出来`, ok ? `${what} ${res.stages?.length ?? res.totals?.total ?? res.sections?.length ?? res.groups?.length ?? res.items?.length}` : res.why);
  }

  if (bad) {
    console.error(`\n✗ collect-docs 自检失败 ${bad} 项`);
    process.exit(1);
  }
  console.log('\n✓ 自检通过：五份文档都读得成同一形状；找不到就说找不到；真仓库五份全读得出');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href
    && process.argv.includes('--selftest')) {
  selftest();
}
