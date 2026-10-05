#!/usr/bin/env node
/**
 * 练了么 · 可用性测试的 7 个数字（可执行版）
 *
 * **它解决什么**：`docs/usability-test-kit.md` §5 的纸面记录表已经能记了，
 * 但"收工后那 7 个数字"要靠人拿计算器汇总 5 个人的正字：
 *   * 中位数算错 / 口径不一致（是"每人一次的 tap_count"还是"全部组的"?）
 *   * 抄错没人发现（分项加总对不上合计 —— 纸面上这两栏是分开填的）
 *   * 结论写成"感觉还不错"，而不是对着 §8 的目标逐条判
 *
 * 所以这里把那份定义变成可运行的：**输入每个被试的原始计数，输出 7 个数字 + 通过/不通过**，
 * 并且**对不上就大声报错**（分项 ≠ 合计、完成了却没有耗时、缺 T1 之类）。
 *
 * 用法：
 *   node tool/usability-report.mjs --template > usability/sessions/P1.json
 *   node tool/usability-report.mjs                      # 读 usability/sessions/
 *   node tool/usability-report.mjs --dir <目录> --json  # 机器可读
 *   node tool/usability-report.mjs --example            # 拿样例数据跑一遍看输出长什么样
 *   node tool/usability-report.mjs --selftest           # 口径自检（verify.sh 会跑）
 *
 * ⚠️ **`tap_count` 的门槛不写在这份脚本里**（2026-10-05 改）：它读
 * `docs/analytics.md` §3 那张表 —— 门槛由**熟人短测**标定（`docs/usability-test-kit.md` §A），
 * 标定结果只写在那里。没标定时报告把那一项标成"⚠️ 未标定"，**不判不通过**
 * （正式那 5 场已经降级成"建议做、不卡上架"，更不该拿一把没做出来的尺子宣布失败）。
 *
 * 退出码：输入有硬错误（抄错/缺项）→ 1；只有"没达标"不会返回非 0
 *        —— 测试结果是事实，不该让脚本失败把人吓回去改数字。
 */

import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** 目标（`docs/usability-test.md` §定量指标 / 通过判据） */
export const TARGETS = {
  t1Completion: 1.0,      // T1 完成率 5/5
  t1MedianSeconds: 90,    // T1 中位耗时 ≤ 90 秒
  // ⚠️ **`tapMedian` 不在这里**（2026-10-05 移走）：门槛的**唯一事实源**是
  // `docs/analytics.md` §3 那张「分位 / 目标」表（由熟人手测的分布标定），
  // 见下面的 [readTapMedianTarget]。以前这里硬编码 `tapMedian: 1`，
  // 那是**窄口径**时代拍的估计值：换成端到端口径后光导航就 2–3 次，
  // 于是正式那 5 场**必然判"不通过"** —— 一把量错东西的尺子比没有尺子更坏。
  typing: 0,              // 首次训练全程打字 0 次
  scrolls: 0,             // 需滚动找动作 0 次
  adoptRate: 0.6,         // 建议采纳率 ≥ 60%（T6）
  // Q3「明天带哪个 App」选本品 ≥ 3/5 —— 用**比例**表达（0.6）：
  // 阶段测试可能只跑了 3 个人，绝对数 3 在那时是不可达的，而口径本身没变。
  q3Rate: 0.6,
  // ⚠️ 这里**刻意没有** SUS-lite。
  //
  // 2026-10-01 拍板删掉：曾经写着 `susLite: 80`，但全仓**既没有题项、也没有计分公式**
  // （kit §7 只留了一格时间），而且它的判据是"没填就不判" —— 等于一个永远不生效的闸门。
  // 4 题简版的信度也撑不起"≥ 80"这条线。**删掉比补一套题更诚实**：
  // 留着它只会让人以为有这么一道门。
};

/**
 * 从 `docs/analytics.md` 的 markdown 里读出 `tap_count` 中位数门槛（**纯函数，可测**）。
 *
 * 口径：只看 `## 3.` 那一节（体验守卫指标）里的第一张表，取 `| 中位数 | … |` 那一行，
 * 把单元格里**第一个数字**当门槛。
 *   * `待定` / `待校准` / 空 → `null` = **未标定**（熟人短测还没做）。
 *     ⚠️ 这时**不许拿某个数去判**，也不许把整份报告判成"不通过" —— 要说"未标定"。
 *   * `3` / `≤ 3` / `3 次` → `3`（写法宽松，含义只有一个）。
 *
 * 为什么门槛要"读"而不是"写死"：它由**熟人短测的实测分布**标定（kit §A5），
 * 标定结果写在 `docs/analytics.md` §3（那里是唯一真源）。
 * 两处各写一个数的下场是"文档说 3、脚本按 1 判"，而且**没有任何症状**。
 */
export function parseTapMedianTarget(markdown) {
  const section = String(markdown ?? '').split(/^## /m).find((s) => s.startsWith('3.'));
  if (!section) return { value: null, why: 'docs/analytics.md 里找不到 §3 那一节' };
  const row = section.split('\n').find((l) => /^\|\s*中位数\s*\|/.test(l.trim()));
  if (!row) return { value: null, why: '§3 那张表里没有「中位数」这一行' };
  const cell = row.split('|').map((c) => c.trim())[2] ?? '';
  const m = cell.match(/-?\d+(?:\.\d+)?/);
  if (!m) return { value: null, why: `§3 的中位数门槛还是「${cell || '空'}」——熟人短测还没标定` };
  return { value: Number(m[0]), why: `来自 docs/analytics.md §3：「${cell}」` };
}

/** 读真仓库里那份；读不到也不算致命（报告照样出，只是那一项标"未标定"）。 */
export function readTapMedianTarget() {
  try {
    return parseTapMedianTarget(readFileSync(join(ROOT, 'docs/analytics.md'), 'utf8'));
  } catch (e) {
    return { value: null, why: `读不到 docs/analytics.md（${e.message}）` };
  }
}

export const TASKS = ['T1', 'T2', 'T3', 'T4', 'T5', 'T6'];
const TAP_SOURCES = ['bigButton', 'stepper', 'sheetConfirm', 'keyboard', 'other'];

/** 中位数（偶数个取中间两个的平均）—— 与 tool/analytics-report.mjs 同一口径 */
export function median(values) {
  if (!values.length) return null;
  const s = [...values].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

const tapTotal = (t) => TAP_SOURCES.reduce((a, k) => a + Number(t?.[k] ?? 0), 0);

/**
 * 校验一份输入。**这是本工具最值钱的部分**：现场手抄最容易出的就是这几类错，
 * 而它们都会让 7 个数字静静算错。
 */
export function validate(doc) {
  const errors = [];
  const warnings = [];
  if (!doc || typeof doc !== 'object' || !Array.isArray(doc.participants)) {
    return { errors: ['顶层必须是 {"participants":[...]}'], warnings };
  }
  if (doc.participants.length === 0) errors.push('一个被试都没有');
  if (doc.participants.length !== 5) {
    warnings.push(`被试数是 ${doc.participants.length}，脚本按 §1 的配额期望 5 人`);
  }
  doc.participants.forEach((p, i) => {
    const at = p?.id ? `${p.id}` : `第 ${i + 1} 位`;
    if (!p?.id) errors.push(`${at}：缺 id`);
    if (p?.consent !== true) warnings.push(`${at}：没有确认知情同意（consent 不是 true）`);
    for (const t of TASKS) {
      const task = p?.tasks?.[t];
      if (!task) { errors.push(`${at}：缺 ${t} 的任务记录`); continue; }
      if (task.done === true && !(Number(task.seconds) > 0)) {
        errors.push(`${at} ${t}：标了完成却没有耗时 —— 中位耗时会被算错`);
      }
      if (task.done === false && task.prompts > 0) {
        warnings.push(`${at} ${t}：未完成但有提示次数，确认一下是不是记反了`);
      }
    }
    // tap：分项与合计必须一致（纸面上这两栏是分开填的）
    for (const key of ['firstLog', 't6Edit']) {
      const t = p?.tap?.[key];
      if (!t) { errors.push(`${at}：缺 tap.${key}`); continue; }
      const sum = tapTotal(t);
      if (t.total !== undefined && Number(t.total) !== sum) {
        errors.push(`${at} tap.${key}：分项合计 ${sum} ≠ 手填的 total ${t.total}`);
      }
      if (key === 'firstLog' && sum === 0) {
        errors.push(`${at} tap.firstLog 合计为 0 —— 请确认真的没点过（大按钮至少 1 次）`);
      }
    }
    if (p?.typing === undefined) errors.push(`${at}：缺 typing（首次训练打字次数）`);
    if (p?.scrolls === undefined) errors.push(`${at}：缺 scrolls（滚动找动作次数）`);
    if (typeof p?.t6?.adopted !== 'boolean') {
      errors.push(`${at}：缺 t6.adopted（是采纳了建议还是手改了）`);
    }
    if (!['lianleme', 'xunji', 'unsure'].includes(p?.q3)) {
      errors.push(`${at}：q3 必须是 lianleme / xunji / unsure 之一（当前 ${JSON.stringify(p?.q3)}）`);
    }
  });
  return { errors, warnings };
}

/** 算那 7 个数字（外加逐任务失败模式） */
export function compute(doc) {
  const ps = (doc?.participants ?? []).filter(Boolean);
  const n = ps.length;
  const done = (t) => ps.filter((p) => p?.tasks?.[t]?.done === true).length;

  const t1Seconds = ps
    .map((p) => Number(p?.tasks?.T1?.seconds))
    .filter((v) => Number.isFinite(v) && v > 0);

  // 每人的"记录一组"合计 → 中位数。取每人的**第一次记录（T1）**，
  // 因为那才是"第一次用时的成本"；T6 是改完之后的第二次，不能混进来。
  const tapTotals = ps.map((p) => tapTotal(p?.tap?.firstLog));

  const adopted = ps.filter((p) => p?.t6?.adopted === true).length;
  const t6Done = ps.filter((p) => p?.tasks?.T6?.done === true).length;

  const taskFailures = {};
  for (const t of TASKS) {
    const failed = ps.filter((p) => p?.tasks?.[t]?.done !== true).map((p) => p.id);
    const prompted = ps.filter((p) => Number(p?.tasks?.[t]?.prompts ?? 0) > 0).map((p) => p.id);
    if (failed.length || prompted.length) taskFailures[t] = { failed, prompted };
  }

  return {
    n,
    t1Completion: n ? done('T1') / n : null,
    t1Done: done('T1'),
    t1MedianSeconds: median(t1Seconds),
    tapMedian: median(tapTotals),
    tapTotals,
    typing: ps.reduce((a, p) => a + Number(p?.typing ?? 0), 0),
    scrolls: ps.reduce((a, p) => a + Number(p?.scrolls ?? 0), 0),
    adoptRate: t6Done ? adopted / t6Done : null,
    adopted,
    t6Done,
    q3Count: ps.filter((p) => p?.q3 === 'lianleme').length,
    q3Xunji: ps.filter((p) => p?.q3 === 'xunji').length,
    q3Unsure: ps.filter((p) => p?.q3 === 'unsure').length,
    taskFailures,
  };
}

/**
 * 逐条对着 §8 的目标判；返回 `{pass, uncalibrated, checks:[{name, value, target, ok}]}`。
 *
 * `ok` 三态：`true` 达标 / `false` 没达标 / **`null` = 这一项现在判不了**（目前只有
 * "门槛还没标定"这一种情形）。三态是刻意的：把"判不了"当成"没达标"，
 * 会让正式那 5 场在**尺子还没做出来**的时候就被宣布失败。
 *
 * [opts.tapTarget] 不传就读 `docs/analytics.md` §3（生产路径）；测试直接传值。
 */
export function verdict(r, opts = {}) {
  const tapTarget = opts.tapTarget === undefined ? readTapMedianTarget().value : opts.tapTarget;
  const checks = [
    { name: 'T1 完成率', value: `${r.t1Done}/${r.n}`, ok: r.t1Completion === 1, target: '5/5' },
    { name: 'T1 中位耗时', value: r.t1MedianSeconds, ok: r.t1MedianSeconds !== null && r.t1MedianSeconds <= TARGETS.t1MedianSeconds, target: `≤ ${TARGETS.t1MedianSeconds} 秒` },
    {
      name: '记录一组中位 tap_count',
      value: r.tapMedian,
      // 门槛在 `docs/analytics.md` §3（熟人短测标的）；没标定就**不判**，标"未标定"
      target: tapTarget === null
        ? '未标定 —— 先按 docs/usability-test-kit.md §A 做熟人短测，把门槛写进 docs/analytics.md §3'
        : `≤ ${tapTarget}`,
      ok: tapTarget === null ? null : (r.tapMedian !== null && r.tapMedian <= tapTarget),
    },
    { name: '首次训练打字次数', value: r.typing, ok: r.typing === TARGETS.typing, target: `= ${TARGETS.typing}` },
    { name: '需滚动找动作次数', value: r.scrolls, ok: r.scrolls === TARGETS.scrolls, target: `= ${TARGETS.scrolls}` },
    { name: '建议采纳率（T6）', value: r.adoptRate === null ? '—' : `${Math.round(r.adoptRate * 100)}%`, ok: r.adoptRate !== null && r.adoptRate >= TARGETS.adoptRate, target: `≥ ${Math.round(TARGETS.adoptRate * 100)}%` },
    {
      name: 'Q3 选本品',
      value: `${r.q3Count}/${r.n}`,
      ok: r.n > 0 && r.q3Count / r.n >= TARGETS.q3Rate,
      target: `≥ ${Math.round(TARGETS.q3Rate * 100)}%（5 人时即 3/5）`,
    },
  ];
  // 这里**刻意没有** SUS-lite —— 见 TARGETS 上方那段注释（2026-10-01 拍板删掉）。
  const uncalibrated = checks.filter((c) => c.ok === null).map((c) => c.name);
  const judged = checks.filter((c) => c.ok !== null);
  return { pass: judged.length > 0 && judged.every((c) => c.ok), uncalibrated, checks };
}

/**
 * 任务卡（**唯一事实源**在 `usability/tasks.json`，由 `tool/check-usability-tasks.mjs` 守着）。
 *
 * 报告里要把任务原文打出来：以前报告只有 `T1`–`T6` 这几个 id，
 * 读报告的人得回头翻文档才知道"T5 到底是什么" —— 而 2026-10-01 发现
 * kit §4 与记录表里的 T5 **内容不一致**，那种时候光看 id 是看不出来的。
 *
 * 读不到就返回空数组：报告本身不该因为少了这个文件而崩（它只是附注信息）。
 */
export function taskCards() {
  try {
    const doc = JSON.parse(readFileSync(join(ROOT, 'usability/tasks.json'), 'utf8'));
    return Array.isArray(doc.tasks) ? doc.tasks : [];
  } catch {
    return [];
  }
}

function markdown(r, v) {
  const L = [];
  L.push('<!-- 由 tool/usability-report.mjs 生成，可直接粘进 docs/usability-test.md -->');
  L.push(`> 可用性测试结果（n=${r.n}）`);
  L.push('');
  L.push('| 指标 | 实测 | 目标 | 判定 |');
  L.push('|---|---|---|---|');
  for (const c of v.checks) {
    L.push(`| ${c.name} | ${c.value} | ${c.target} | ${c.ok === null ? '⚠️ 未标定' : (c.ok ? '✅' : '❌')} |`);
  }
  L.push('');
  L.push(`**结论：${v.pass ? '通过（可冻结设计）' : '不通过'}**`
    + (v.uncalibrated.length ? `（⚠️ 未判：${v.uncalibrated.join('、')}）` : ''));
  const cards = taskCards();
  if (cards.length) {
    L.push('');
    L.push('这次跑的 6 个任务（原文来自 `usability/tasks.json`，**不是**回头翻文档猜的）：');
    L.push('');
    L.push('| # | 递给被试的原话 | 判定标准 |');
    L.push('|---|---|---|');
    for (const t of cards) {
      L.push(`| ${t.id}${t.deliberateFailure ? '（刻意必败）' : ''} | ${t.card} | ${t.success} |`);
    }
  }
  if (!v.pass) {
    L.push('');
    L.push('按 `docs/usability-test.md` §通过/不通过判据逐条对：');
    L.push('');
    if (!v.checks[0].ok || !v.checks[1].ok) L.push('- T1 超时或需提示 → 砍掉 S2 建议卡，直接进 S4 训练主屏');
    if (!v.checks[2].ok) L.push('- 每组点击 > 1 → **这是发布门禁（`docs/analytics.md` §7）**：先查是哪几次点击，再决定砍什么');
    if (!v.checks[3].ok) L.push('- 打字 > 0 → 首次训练仍有键盘输入，检查重量/次数输入路径');
    if (!v.checks[4].ok) L.push('- 需要滚动找动作 → 选择器的首屏排序（最近/常用）没起作用');
    if (!v.checks[5].ok) L.push('- 采纳率 < 60% → 建议不可信或不显眼，先看 T6 的原话');
    if (!v.checks[6].ok) L.push('- Q3 多数不选本品 → **回到定位本身**：换楔子，而不是继续打磨极简');
  }
  return L.join('\n');
}

export function build(doc) {
  const { errors, warnings } = validate(doc);
  const r = compute(doc);
  const v = verdict(r);
  return { errors, warnings, ...r, verdict: v, markdown: markdown(r, v) };
}

// ---------------------------------------------------------------- CLI

const template = {
  _note: '一位被试的记录。一个"正字" = 1 次点击；纸面表见 docs/usability-test-kit.md §5。',
  participants: [
    {
      id: 'P1',
      consent: true,
      tasks: Object.fromEntries(TASKS.map((t) => [t, { done: false, prompts: 0, seconds: 0 }])),
      tap: {
        firstLog: { bigButton: 0, stepper: 0, sheetConfirm: 0, keyboard: 0, other: 0 },
        t6Edit: { bigButton: 0, stepper: 0, sheetConfirm: 0, keyboard: 0, other: 0 },
      },
      typing: 0,
      scrolls: 0,
      t6: { adopted: false },
      q3: 'unsure',
    },
  ],
};

function readDir(dir) {
  if (!existsSync(dir)) return { participants: [] };
  const participants = [];
  for (const f of readdirSync(dir).filter((n) => n.endsWith('.json')).sort()) {
    try {
      const doc = JSON.parse(readFileSync(join(dir, f), 'utf8'));
      const list = Array.isArray(doc) ? doc : (doc.participants ?? [doc]);
      participants.push(...list);
    } catch (e) {
      console.error(`✗ ${f} 读不了：${e.message}`);
      process.exitCode = 1;
    }
  }
  return { participants };
}

if (process.argv[1] && process.argv[1].endsWith('usability-report.mjs')) {
  const argv = process.argv.slice(2);
  const argOf = (n, d) => {
    const i = argv.indexOf(n);
    return i >= 0 && argv[i + 1] ? argv[i + 1] : d;
  };

  if (argv.includes('--template')) {
    console.log(JSON.stringify(template, null, 2));
  } else if (argv.includes('--selftest')) {
    // ⚠️ 这里**不能** `await import('./usability-selftest.mjs')`（2026-10-05 修这个 bug）：
    // 那份自检**静态 import 本文件**（它要检查这里的 TARGETS / verdict），
    // 于是本文件动态 import 它就构成**循环依赖**：两边互相等对方求值完，
    // 顶层 await 永远不落定 —— Node 报 "Detected unsettled top-level await"，
    // **退出码是 13**（不是 0 也不是 1）。也就是说这个 `--selftest` 开关一直是坏的，
    // 只是门禁跑的是 `usability-selftest.mjs` 那个文件本身、没经过这条路，所以没人发现。
    // 正解：**开子进程**跑它，环就断了（stdio 直通，输出与单独跑一模一样）。
    const r = spawnSync(process.execPath, [join(ROOT, 'tool/usability-selftest.mjs')], {
      stdio: 'inherit',
    });
    process.exitCode = r.status ?? 1;
  } else {
    const useExample = argv.includes('--example');
    const dir = useExample ? join(ROOT, 'usability') : argOf('--dir', join(ROOT, 'usability/sessions'));
    const doc = useExample
      ? JSON.parse(readFileSync(join(ROOT, 'usability/participants.example.json'), 'utf8'))
      : readDir(dir);
    const out = build(doc);

    if (out.errors.length) {
      console.error(`✗ 输入有 ${out.errors.length} 处硬错误（先改这些，7 个数字才可信）：`);
      for (const e of out.errors) console.error(`  · ${e}`);
      process.exit(1);
    }
    for (const w of out.warnings) console.error(`⚠️ ${w}`);

    if (argv.includes('--json')) {
      console.log(JSON.stringify(out, null, 2));
    } else {
      console.log(`可用性测试：n=${out.n}　数据目录 ${useExample ? 'usability/（样例）' : dir}\n`);
      for (const c of out.verdict.checks) {
        console.log(`  ${c.ok === null ? '⚠︎' : (c.ok ? '✓' : '✗')} ${c.name.padEnd(22)} ${String(c.value).padEnd(10)} 目标 ${c.target}`);
      }
      if (out.verdict.uncalibrated.length) {
        console.log(`\n  ⚠️ 这几项**判不了**（不是没达标）：${out.verdict.uncalibrated.join('、')}`);
      }
      console.log(`\n  ${out.verdict.pass ? '通过（可冻结设计）' : '不通过 —— 按 §判据逐条对'}`
        + `\n  Q3：本品 ${out.q3Count} · 训记 ${out.q3Xunji} · 犹豫 ${out.q3Unsure}`);
      if (Object.keys(out.taskFailures).length) {
        console.log('\n  没做成的任务（复盘用）：');
        for (const [t, f] of Object.entries(out.taskFailures)) {
          console.log(`    ${t}：未完成 [${f.failed.join(',') || '—'}]　需提示 [${f.prompted.join(',') || '—'}]`);
        }
      }
      console.log('\n--- 可粘贴的 markdown ---\n');
      console.log(out.markdown);
    }
  }
}
