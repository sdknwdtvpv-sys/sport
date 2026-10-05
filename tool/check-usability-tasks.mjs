#!/usr/bin/env node
/**
 * 练了么 · 可用性测试**任务卡**的一致性守卫
 *
 * **它解决什么**：同一批任务现在写在**三个地方**，各有各的用途：
 *   * `docs/usability-test-kit.md` §4 —— **递给被试的原话**（`card`）
 *   * `docs/usability-test.md` §任务清单 —— 主持人看的汇总（`summary` / `success` / `measures`）
 *   * `usability/记录表.md` §1 —— 现场手抄的短名（`label`）
 *
 * 三处各写一份，就会漂 —— 而它**真的漂过**（2026-10-01 发现）：
 * kit §4 与记录表的 **T3 / T4 / T5 内容不一致**。kit 的 T5 是「超级组」**刻意必败**任务，
 * 记录表里被换成了「看这周练了几次」；而 `tool/usability-report.mjs` **只认 T1–T6 的 id、
 * 不认内容**，所以没有任何东西会发现。
 *
 * 代价不是美观：kit §10 的复盘模板直接依赖「T5 的失败方式」
 * （被试找不到时说「这软件没有」还是「这软件不需要」）——
 * 按记录表跑完 5 场，那一格**没有输入**，等于白跑一场。
 *
 * 所以：`usability/tasks.json` 是**唯一**的事实源，这个脚本核三份文档有没有跟上。
 *
 * 判据（偏保守，宁可漏报也不误报）：
 *   * 归一化后再判子串 —— 去掉空白与 markdown 强调符（`*` 与 `` ` ``），
 *     所以同一句话在文档里换行、加粗、写进表格都不影响；
 *   * `card` 只在 kit 里核，`summary`/`success`/`measures` 只在测试脚本里核，
 *     `label` 只在记录表里核 —— 各核各的，不去要求三份文档说一样的话。
 *
 * 用法：
 *   node tool/check-usability-tasks.mjs              # 核仓库里的三份文档
 *   node tool/check-usability-tasks.mjs --selftest   # 自检（造几套动过手脚的，验它抓得住）
 *
 * 退出码：对不上 → 1。
 */

import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { TASKS } from './usability-report.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

export const SOURCE = 'usability/tasks.json';
export const KIT = 'docs/usability-test-kit.md';
export const SCRIPT = 'docs/usability-test.md';
export const SHEET = 'usability/记录表.md';

/**
 * 归一化：去掉行首引用标记 + 空白 + markdown 强调符 —— 只在归一化后判子串。
 *
 * ⚠️ **这里踩过一次坑**（写完第一版自检就抓到了）：只去空白与 `*`/`` ` `` 时，
 * kit §4 那些**跨两行 `>` 写的卡**（T1、T6）中间会留下一个 `>`，
 * 于是"递卡文档里找不到这张卡"是**假阳性** —— 而假阳性会让人把这个守卫关掉。
 * 所以行首的 `>` 必须一起去掉。
 */
export const norm = (s) => String(s ?? '')
  .replace(/^[ \t]*>[ \t]?/gm, '')
  .replace(/[*`\s]/g, '');

/** 一份任务必须有这些字段，缺了就是"某个消费方没法取到它要的那部分"。 */
const REQUIRED_FIELDS = ['id', 'label', 'card', 'summary', 'success', 'measures'];

export function inspect(root) {
  const problems = [];
  let checked = 0;

  const read = (rel) => {
    try { return readFileSync(join(root, rel), 'utf8'); } catch { return null; }
  };

  const src = read(SOURCE);
  if (src === null) return { problems: [`读不到 ${SOURCE} —— 任务卡的单一事实源不见了`], checked: 0 };
  let doc;
  try {
    doc = JSON.parse(src);
  } catch (e) {
    return { problems: [`${SOURCE} 不是合法 JSON：${e.message}`], checked: 0 };
  }

  const tasks = Array.isArray(doc.tasks) ? doc.tasks : [];
  if (!tasks.length) return { problems: [`${SOURCE} 里没有 tasks 数组`], checked: 0 };

  // 1. id 必须与报告工具认的那一组**逐个一致**（顺序也一致：报告按这个顺序打印）
  const ids = tasks.map((t) => t.id);
  if (ids.join(',') !== TASKS.join(',')) {
    problems.push(`${SOURCE} 的任务是 [${ids.join(', ')}]，而 tool/usability-report.mjs 的 `
      + `TASKS 是 [${TASKS.join(', ')}] —— 两边不一致，报告会漏项或错位`);
  }
  if (new Set(ids).size !== ids.length) problems.push(`${SOURCE} 里有重复的任务 id`);

  // 2. 三份文档都要读得到
  const texts = {};
  for (const [rel, what] of [[KIT, '递卡文档'], [SCRIPT, '测试脚本'], [SHEET, '记录表']]) {
    const t = read(rel);
    if (t === null) problems.push(`读不到 ${rel}（${what}）`);
    texts[rel] = t === null ? null : norm(t);
  }

  // 3. 逐项核：每一部分只去它该去的那份文档里找
  const where = {
    card: [KIT, '递卡文档（被试看到的原话）'],
    summary: [SCRIPT, '测试脚本（任务清单）'],
    success: [SCRIPT, '测试脚本（成功标准）'],
    measures: [SCRIPT, '测试脚本（测什么）'],
    label: [SHEET, '记录表（现场手抄的短名）'],
  };
  for (const t of tasks) {
    for (const f of REQUIRED_FIELDS) {
      if (typeof t[f] !== 'string' || !t[f].trim()) {
        problems.push(`${SOURCE} 的任务 ${t.id ?? '(缺 id)'} 缺少字段 ${f}`);
      }
    }
    for (const [field, [rel, what]] of Object.entries(where)) {
      if (typeof t[field] !== 'string' || !t[field].trim()) continue;
      if (texts[rel] === null) continue;
      checked += 1;
      if (!texts[rel].includes(norm(t[field]))) {
        problems.push(`${rel}（${what}）里找不到任务 ${t.id} 的 ${field}：「${t[field]}」`
          + ' —— 三处写同一件事就会漂，这里只认 '
          + `${SOURCE}`);
      }
    }
  }

  // 4. 必败任务必须在两份文档里都写明白"必败"（否则复盘时没人知道该看失败方式）
  const mustFail = tasks.filter((t) => t.deliberateFailure === true);
  if (mustFail.length) {
    for (const rel of [KIT, SCRIPT]) {
      if (texts[rel] !== null && !texts[rel].includes('必败')) {
        problems.push(`${rel} 里没有"必败"二字，但 ${SOURCE} 标了 `
          + `${mustFail.map((t) => t.id).join('/')} 是刻意设计的必败任务 —— `
          + '复盘的判据（被试说「没有」还是「不需要」）会失去出处');
      }
    }
  }

  return { problems, checked, count: tasks.length };
}

// ───────────────────────────────────────────────────────────── 自检
function selftest() {
  const T = (id, over = {}) => ({
    id,
    label: `短名${id}`,
    card: `原话${id}`,
    summary: `汇总${id}`,
    success: `标准${id}`,
    measures: `测什么${id}`,
    deliberateFailure: false,
    ...over,
  });
  const base = [
    T('T1'), T('T2'), T('T3'), T('T4'),
    T('T5', { deliberateFailure: true }), T('T6'),
  ];
  // 三份文档按"全部一致"生成
  const docs = (tasks) => ({
    [KIT]: tasks.map((t) => `**${t.id}**\n> ${t.card}\n`).join('\n') + (tasks.some((t) => t.deliberateFailure) ? '\n**T5 是刻意设计的必败任务**\n' : ''),
    [SCRIPT]: tasks.map((t) => `| ${t.id} | "${t.summary}" | ${t.success} | ${t.measures} |`).join('\n')
      + (tasks.some((t) => t.deliberateFailure) ? '\n**必败任务**\n' : ''),
    [SHEET]: tasks.map((t) => `| ${t.id} ${t.label} | ☐ |`).join('\n'),
  });
  const makeTree = (tasks, overrides = {}) => {
    const root = mkdtempSync(join(tmpdir(), 'lianleme-tasks-'));
    mkdirSync(join(root, 'docs'), { recursive: true });
    mkdirSync(join(root, 'usability'), { recursive: true });
    writeFileSync(join(root, SOURCE), JSON.stringify({ tasks }, null, 1));
    const d = { ...docs(tasks), ...overrides };
    for (const [rel, text] of Object.entries(d)) writeFileSync(join(root, rel), text);
    return root;
  };

  const d = docs(base);
  const cases = [
    ['三份文档都跟上 → 绿', base, {}, true, null],
    // ★ 真实事故的回归：记录表把 T5 换成了别的内容（kit 的 T5 是必败任务）。
    //   当时没有任何东西会发现 —— usability-report 只认 id。
    ['记录表里 T5 被换成别的内容 → 必须报', base,
      { [SHEET]: d[SHEET].replace('短名T5', '看这周练了几次') }, false, '短名T5'],
    ['递卡文档缺一张卡 → 必须报', base,
      { [KIT]: d[KIT].replace(`> ${base[2].card}`, '> （漏了）') }, false, base[2].card],
    ['测试脚本的成功标准过期 → 必须报', base,
      { [SCRIPT]: d[SCRIPT].replace('标准T4', '标准改了') }, false, '标准T4'],
    ['归一化：文档里换行/加粗不影响判定（不能误报）', base,
      { [KIT]: d[KIT].replace(`> ${base[0].card}`, `> **${base[0].card.slice(0, 3)}**\n> ${base[0].card.slice(3)}`) },
      true, null],
    ['缺字段 → 必须报', [T('T1'), { id: 'T2' }, T('T3'), T('T4'), T('T5'), T('T6')],
      {}, false, '缺少字段'],
    ['必败任务在递卡文档里没写"必败" → 必须报', base,
      { [KIT]: d[KIT].replace('**T5 是刻意设计的必败任务**', '（说明删了）') }, false, '必败'],
  ];

  let bad = 0;
  for (const [label, tasks, overrides, wantGreen, expect] of cases) {
    const root = makeTree(tasks, overrides);
    const { problems } = inspect(root);
    const green = problems.length === 0;
    let ok = green === wantGreen;
    let why = green ? '' : `　→ ${problems[0].slice(0, 70)}`;
    if (ok && !wantGreen && expect && !problems.some((p) => p.includes(expect))) {
      ok = false;
      why = `　→ 红了，但不是因为「${expect}」（红在：${problems[0].slice(0, 44)}）`;
    }
    if (!ok) bad += 1;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}${why}`);
    rmSync(root, { recursive: true, force: true });
  }

  // id 与报告工具对不上：必须报（这条用的是**真实**的 TASKS，不是夹具）
  const wrongId = mkdtempSync(join(tmpdir(), 'lianleme-tasks-'));
  mkdirSync(join(wrongId, 'docs'), { recursive: true });
  mkdirSync(join(wrongId, 'usability'), { recursive: true });
  writeFileSync(join(wrongId, SOURCE), JSON.stringify({ tasks: [...base, T('T7')] }));
  const w = inspect(wrongId);
  const idOk = w.problems.some((p) => p.includes('TASKS'));
  console.log(`  ${idOk ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} 多出一个 T7（与报告工具的 TASKS 对不上）→ 必须报`);
  if (!idOk) bad += 1;
  rmSync(wrongId, { recursive: true, force: true });

  if (bad) {
    console.error(`\n✗ 自检失败 ${bad} 项 —— 这个工具本身不可信，先修它`);
    process.exit(1);
  }
  console.log('\n✓ 自检通过：任务卡在三份文档里漂了会被抓到；换行/加粗不误报');
}

// ───────────────────────────────────────────────────────────────── 跑
if (process.argv.includes('--selftest')) {
  selftest();
} else {
  const rootArg = process.argv.find((a) => a.startsWith('--root='));
  const { problems, checked, count } = inspect(rootArg ? rootArg.slice('--root='.length) : ROOT);
  console.log('可用性测试任务卡一致性核对\n');
  console.log(`  事实源：${SOURCE}（${count ?? 0} 个任务）· 核了 ${checked} 处引用`);
  if (problems.length) {
    console.log('');
    for (const p of problems) console.error(`  \x1b[31m✗\x1b[0m ${p}`);
    console.error('\n✗ 任务卡对不上 —— 改任务请改 '
      + `${SOURCE}，不要只改其中一份文档`);
    process.exit(1);
  }
  console.log('\n✓ 递卡文档 / 测试脚本 / 记录表 三处与事实源一致');
}
