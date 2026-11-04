#!/usr/bin/env node
/**
 * 练了么 · 熟人短测的 **tap_count 门槛**（可执行版）
 *
 * **它解决什么**（`docs/feature-backlog.md` 第 12 项）：熟人短测（`docs/usability-test-kit.md`
 * §A）做完之后，要把 3–5 个人的"记录一组要点几下"变成 `docs/analytics.md` §3 那三行。
 * 这一步现场手抄最容易错的就是**口径**：
 *   * 中位数算成"平均"（n 为偶数时是两中数的平均，不是全部平均）；
 *   * 中位数是 .5 时不知道该写 2.5 还是 3（门槛取**向上**的整数，但**实测值必须一并留下**）；
 *   * P90 拿插值假装算（n=3–5 **算不出**可信分位数，填法在 kit §A5.4 里是写死的）；
 *   * 分项之和与手填的总点击对不上（纸面上这两栏是分开填的）却没发现。
 *
 * 所以这里把 kit §A5 的口径变成可运行的：**输入原始计数，输出该填进 §3 的确切 markdown**，
 * 并且**对不上就大声报错**（退出码 1）—— 一个算错的门槛会被 `tool/usability-report.mjs`
 * 当成真门槛读走（它读的就是 §3 那一格），从此每份报告都用一把错尺子量。
 *
 * 用法：
 *   mkdir -p usability/thresholds                               # 原始记录不进仓库（见 .gitignore）
 *   node tool/usability-threshold.mjs --template > usability/thresholds/S1.json  # 每人一份模板
 *   node tool/usability-threshold.mjs                       # 读 usability/thresholds/
 *   node tool/usability-threshold.mjs --dir <目录> --json    # 机器可读
 *   node tool/usability-threshold.mjs --entry 'S1=1,0,0,1=2' --entry 'S2=1,0,0,1=2' …  # 命令行给数
 *   node tool/usability-threshold.mjs --example             # 拿 kit §A5 那个 2/2/3/4 的例子跑一遍
 *   node tool/usability-threshold.mjs --selftest            # 口径自检（verify.sh 会跑）
 *
 * `--entry` 的格式：`代号=①,②,③,④=总点击`，四个分项的顺序就是 kit §A4 的表头
 * （①到训练屏 / ②选/换动作 / ③改重量 / ④大按钮写入）。**不自己发明步骤名** ——
 * 表头是唯一真源，多一个少一个都会被 validate() 拦住。
 *
 * 退出码：输入有硬错误（抄错/缺项/人数不对）→ 1；只有"某步 > 3 次"这类提示不会返回非 0
 *        —— 那是实测事实，不该让脚本失败把人吓回去改数字（但会大声提示"先修那一步"）。
 */

import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// ⚠️ 这里**故意**依赖报告工具的解析函数：本工具打印的三行就是回填给 `docs/analytics.md` §3
// 的那三行，而 `tool/usability-report.mjs` 的 `parseTapMedianTarget()` 读的正是那一格。
// 两边一旦对不上（比如把中位数写成「约 3 次左右」这种没有整数起头的说法），报告会安静地
// 判成"未标定"或读错数 —— 所以自检里直接用**真解析器**验一遍，不另写一份判据。
import { parseTapMedianTarget } from './usability-report.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const DEFAULT_DIR = join(ROOT, 'usability/thresholds');

/**
 * 四个步骤（**唯一真源**是 `docs/usability-test-kit.md` §A4 的记录表表头）。
 *
 * `key` 是 JSON 里的字段名，`label` 是给人看的说法 —— 两者都别改：改了就等于换了口径，
 * 而 §A4 那张表、§A6 的回填说明、以及现场纸面记录都按这四个步骤对。
 */
export const STEPS = [
  { key: 'toWorkout', label: '①到训练屏' },
  { key: 'pickOrSwitchExercise', label: '②选/换动作' },
  { key: 'adjustWeight', label: '③改重量（长按+步进+确定）' },
  { key: 'bigButton', label: '④大按钮写入' },
];

/** `PRODUCT.md` §1 的红线："超过 3 次点击判负"。超了的那一步就是"先修哪一步"的答案。 */
export const RED_LINE = 3;

/** 中位数（偶数个取中间两个的平均）—— 与 `tool/usability-report.mjs` / `tool/analytics-report.mjs` 同一口径 */
export function median(values) {
  if (!values.length) return null;
  const s = [...values].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

const isISODate = (s) => {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(s))) return false;
  const d = new Date(`${s}T00:00:00`);
  if (Number.isNaN(d.getTime())) return false;
  // `2026-02-31` 这种 Date 会滚到 3 月 —— 滚过就说明这个日期不存在
  const [y, m, day] = String(s).split('-').map(Number);
  return d.getFullYear() === y && d.getMonth() + 1 === m && d.getDate() === day;
};

/** 没给测量日期就用今天（**会提示**，因为 §3 注释里那条日期必须是测量当天） */
function todayLocal() {
  const d = new Date();
  const p = (x) => String(x).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

/**
 * 测量日期从哪来：`--date` > JSON 顶层的 `date` > 今天。
 * 返回值里带 `source`，好让命令行在"按今天算"时提醒一句 —— 日期抄错比数字抄错更难发现。
 */
export function resolveDate(doc, opts = {}) {
  if (opts.date !== undefined && String(opts.date).trim() !== '') {
    return { date: String(opts.date).trim(), source: '--date' };
  }
  const inDoc = typeof doc?.date === 'string' ? doc.date.trim() : '';
  if (inDoc) return { date: inDoc, source: 'JSON 里的 date' };
  return { date: todayLocal(), source: '今天（没提供测量日期）' };
}

/**
 * 校验一份输入。**这是本工具最值钱的部分**：现场手抄最容易出的就是这几类错，
 * 而它们都会让门槛静静算错、然后被报告工具当真读走。
 */
export function validate(doc, opts = {}) {
  const errors = [];
  const warnings = [];
  if (!doc || typeof doc !== 'object' || !Array.isArray(doc.participants)) {
    return { errors: ['顶层必须是 {"participants":[...]}（--template 会生成模板）'], warnings };
  }
  const ps = doc.participants;
  if (ps.length === 0) {
    errors.push('一个被试都没有 —— 门槛至少要 3 个人的分布（kit §A1）；用 --template 生成模板，或 --entry 在命令行给数');
  }
  if (ps.length > 0 && ps.length < 3) {
    errors.push(`n=${ps.length}：少于 3 个人不要定门槛（kit §A1）—— 那不是分布，是一个人的手感`);
  }
  if (ps.length > 5) {
    errors.push(`n=${ps.length}：只招 3–5 个人（kit §A1）—— 多出来的人不参与这次标定，别混进中位数`);
  }
  const dateInfo = resolveDate(doc, opts);
  if (!isISODate(dateInfo.date)) {
    errors.push(`测量日期「${dateInfo.date}」（来自${dateInfo.source}）不是 YYYY-MM-DD 的真实日期 —— §3 注释要能追溯，日期不能含糊`);
  }

  const seen = new Map();
  ps.forEach((p, i) => {
    if (!p || typeof p !== 'object' || Array.isArray(p)) {
      errors.push(`第 ${i + 1} 位不是对象 —— 每一位要写成 {"id","steps","total"}`);
      return;
    }
    const at = p.id ? String(p.id) : `第 ${i + 1} 位`;
    if (!p.id || !String(p.id).trim()) {
      errors.push(`${at}：缺代号（id）—— 代号用来在结论里指认"是谁点了 4 下"`);
    } else if (seen.has(String(p.id).trim())) {
      errors.push(`代号「${p.id}」重复：同一个人只能记一行（两行会被当成两个人算进中位数）`);
    } else {
      seen.set(String(p.id).trim(), i);
    }

    const steps = p.steps;
    const stepsOk = steps && typeof steps === 'object' && !Array.isArray(steps);
    if (!stepsOk) {
      errors.push(`${at}：缺 steps（分步骤点击数）—— 没有分项就没法核总点击是怎么来的`);
    } else {
      for (const s of STEPS) {
        if (!(s.key in steps)) {
          errors.push(`${at}：缺步骤「${s.label}」（key \`${s.key}\`）—— 四个分项要逐个写，缺一个就没法核分项之和`);
          continue;
        }
        const v = steps[s.key];
        if (!Number.isInteger(v) || v < 0) {
          errors.push(`${at} 的「${s.label}」不是非负整数（${JSON.stringify(v)}）—— 一个"正字" = 1 次点击，只能是整数`);
        }
      }
      for (const k of Object.keys(steps)) {
        if (!STEPS.some((s) => s.key === k)) {
          errors.push(`${at}：多了一个步骤字段「${k}」—— 只认 ${STEPS.map((s) => s.key).join(' / ')}（步骤名以 kit §A4 表头为准，别自己发明）`);
        }
      }
    }

    if (p.total === undefined) {
      errors.push(`${at}：缺 total（总点击）—— 分项之和要靠它核对，这两栏是分开填的，最常见的错就在这`);
    } else if (!Number.isInteger(p.total)) {
      errors.push(`${at}：总点击必须是整数（当前 ${JSON.stringify(p.total)}）`);
    } else if (p.total < 1) {
      errors.push(`${at}：总点击是 0 —— 这一组根本没记成，不算一次标定（要么重测，要么如实注明他没做成，别按 0 记）`);
    } else if (stepsOk && STEPS.every((s) => Number.isInteger(steps[s.key]))) {
      const sum = STEPS.reduce((a, s) => a + steps[s.key], 0);
      if (sum !== p.total) {
        errors.push(`${at}：分项之和 ${sum} ≠ 手填的总点击 ${p.total} —— 纸面上这两栏是分开填的，先手加一遍（kit §A4）`);
      }
    }

    // 起跑状态会改变点击行为（kit §A2）。没记就不吭声（最小输入里本来就没有这一栏）；
    // 明确记了"不是冷启动"才提示 —— 那种数字可能偏小，写结论时要注明。
    if (p.coldStart === false) {
      warnings.push(`${at}：没有从冷启动开始（coldStart=false）—— 数字可能偏小，回填时要在 §3 注释里注明（kit §A2）`);
    }
  });
  return { errors, warnings };
}

/**
 * 算这次标定的全部派生数。
 *
 * 三个口径都写死在这里（别再散到别处）：
 *   * `median`：偶数个取两中数平均；
 *   * `threshold = ceil(median)`：中位数是 .5 时取**向上**的整数（**宽松侧** —— 门槛写成
 *     "多数人 ≤ N 次"，把 2.5 写成 3 是"多数人做到了"，写成 2 会把一半人判负）；
 *     但 `median` 本身**原样保留**在输出里，§3 注释必须写实测值（A5.3：门禁比的是"与上一版比有没有上升"，
 *     实测值丢了就没法比）；
 *   * `p90 = max`、`p99 = null`：n=3–5 **算不出**可信分位数（kit §A5.4）——
 *     P90 填本次最大值并**注明"小样本最大值，不是分位数"**，P99 留空等真实上报数据。
 *     **不许**用插值假装算出一个 P90：那比留空更坏，因为它看起来像个分位数。
 */
export function compute(doc, opts = {}) {
  const ps = (doc?.participants ?? []).filter((p) => p && typeof p === 'object' && !Array.isArray(p));
  const totals = ps.map((p) => Number(p.total));
  const medianValue = median(totals);
  const threshold = medianValue === null ? null : Math.ceil(medianValue);
  const max = totals.length ? Math.max(...totals) : null;
  const { date, source } = resolveDate(doc, opts);
  const overThreeSteps = STEPS.map((s) => ({
    key: s.key,
    label: s.label,
    ids: ps.filter((p) => Number(p?.steps?.[s.key]) > RED_LINE).map((p) => String(p?.id ?? '?')),
  })).filter((x) => x.ids.length);
  return {
    n: ps.length,
    date,
    dateSource: source,
    participants: ps.map((p) => ({
      id: String(p.id ?? '?'),
      total: Number(p.total),
      steps: Object.fromEntries(STEPS.map((s) => [s.key, Number(p?.steps?.[s.key] ?? 0)])),
    })),
    // 排序后的分布：kit §A5 举的例子就是排好序的（"2 / 2 / 3 / 4"），读的人也按排序比分
    totals: [...totals].sort((a, b) => a - b),
    median: medianValue,
    threshold,
    max,
    p90: max,
    p99: null,
    overThreeSteps,
  };
}

/**
 * 该填进 `docs/analytics.md` §3 那张表的三行 markdown（**恰好三行**）。
 *
 * 中位数那一格是 `tool/usability-report.mjs` **机器读的**（`parseTapMedianTarget` 取第一个数字），
 * 所以写成「≤ N 次」这种宽松写法也读得出 N —— 但**必须有那个整数**。
 * P90 那行按 kit §A5.4 写"小样本最大值，不是分位数"；P99 **留空**（空单元格就是"留空"）。
 */
export function tableRows(r) {
  const rows = [];
  if (r.median === null || r.threshold === null) {
    rows.push('| 中位数 |  |');
  } else if (r.threshold === r.median) {
    rows.push(`| 中位数 | ≤ ${r.threshold} 次 |`);
  } else {
    // 只有偶数 n 会走到这里，且小数部分必然是 .5（整数计数）
    rows.push(`| 中位数 | ≤ ${r.threshold} 次（实测中位数 ${r.median}，向上取整） |`);
  }
  rows.push(r.max === null
    ? '| P90 |  |'
    : `| P90 | ${r.max} 次（小样本最大值，不是分位数） |`);
  rows.push('| P99 |  |');
  return rows;
}

/** §3 表下那条注释要的东西：原始分布 + 测量日期（门槛要能追溯到这张表） */
export function commentText(r) {
  const bits = [
    `测量日期 ${r.date}`,
    `n=${r.n}`,
    `逐人总点击 ${r.totals.join(' / ')}`,
    `中位数 ${r.median}${r.threshold !== r.median ? `（向上取整为门槛 ${r.threshold}）` : ''}`,
    `最大值 ${r.max}`,
  ];
  return `> ${bits.join('；')}。P90 按 kit §A5.4 填本次最大值（不是分位数）；`
    + 'P99 留空，等真实上报数据。原始记录表按 kit §A4 留存、不进仓库。';
}

/**
 * 那句"结论只写事实"的现成措辞（kit §A5.6 的写法）：
 * `n=4，总点击 2 / 2 / 3 / 4，中位数 2.5，门槛取 3`。
 *
 * **不写**"体验良好""达到目标""通过测试" —— n=3–5 撑不起这三句话（kit §A0）。
 */
export function factualConclusion(r) {
  return `n=${r.n}，总点击 ${r.totals.join(' / ')}，中位数 ${r.median}，门槛取 ${r.threshold}`;
}

/**
 * 某步超过 3 次点击时的提示 —— **这就是"先修哪一步"的答案**（kit §A5.5、`PRODUCT.md` §1）。
 * 超线时**先别回填 §3**：把"多数人做不到"的数字写成目标值，等于用一把量错东西的尺子。
 */
export function overThreeHints(r) {
  return r.overThreeSteps.map((s) => `⚠️ ${s.label}：${s.ids.join('、')} 超过 ${RED_LINE} 次点击。`
    + `PRODUCT.md §1 的红线是"超过 ${RED_LINE} 次点击判负" —— 先修这一步（kit §A5.5），`
    + '不要把这个"多数人做不到"的数字写成目标值');
}

/** 汇总：校验 + 计算 + 三行 markdown + 注释 + 结论（`--json` 输出的就是这一份） */
export function build(doc, opts = {}) {
  const { errors, warnings } = validate(doc, opts);
  const r = compute(doc, opts);
  return {
    errors,
    warnings,
    ...r,
    tableRows: tableRows(r),
    comment: commentText(r),
    conclusion: factualConclusion(r),
    // 给自检与调用方用的"提示"，正常输出时由 CLI 打到 stderr
    overThreeHints: overThreeHints(r),
  };
}

// ---------------------------------------------------------------- 输入

/**
 * `--entry 'S1=1,0,0,1=2'` → 一位被试。
 *
 * 为什么命令行要单独一条路：短测现场可能只有纸，回车房不想先建目录/JSON ——
 * 但**分项必须给全**（四个数），不许只报一个总数：没有分项就查不出"哪一步 > 3 次"，
 * 而那才是这个工具第二个值钱的产出。
 */
export function parseEntry(text) {
  const raw = String(text ?? '').trim();
  const parts = raw.split('=');
  if (parts.length !== 3) {
    return { error: `--entry「${raw}」看不懂：要写成 代号=①,②,③,④=总点击，例如 S1=1,0,0,1=2` };
  }
  const [id, stepsCsv, totalStr] = parts.map((s) => s.trim());
  if (!id) return { error: `--entry「${raw}」缺代号` };
  const cells = stepsCsv.split(',').map((s) => s.trim());
  if (cells.length !== STEPS.length) {
    return { error: `--entry「${raw}」给了 ${cells.length} 个分项，要 ${STEPS.length} 个（顺序是 kit §A4 的 ①–④）` };
  }
  const steps = {};
  for (let i = 0; i < STEPS.length; i += 1) {
    const v = Number(cells[i]);
    if (!Number.isInteger(v)) {
      return { error: `--entry「${raw}」的「${STEPS[i].label}」不是整数（${cells[i]}）` };
    }
    steps[STEPS[i].key] = v;
  }
  const total = Number(totalStr);
  if (!Number.isInteger(total)) {
    return { error: `--entry「${raw}」的总点击不是整数（${totalStr}）` };
  }
  return { participant: { id, steps, total } };
}

/**
 * 读一个目录（每人一份 JSON，文件名随便）。三种写法都认（与 `tool/usability-report.mjs` 同款）：
 * 单个人对象 / `{participants:[…]}` / 数组。
 *
 * ⚠️ 读不了的文件是**硬错误**：跳过它等于"少一个人"却照样算中位数 —— 那正是最坏的结果
 * （数字看起来正常，样本却悄悄少了一个）。
 */
export function readDir(dir) {
  const errors = [];
  const warnings = [];
  if (!existsSync(dir)) {
    errors.push(`读不到目录 ${dir} —— 先 \`mkdir -p usability/thresholds\`，`
      + '再每人一份 `--template` 打出来的 JSON；或者直接用 `--entry` 在命令行给数（人多时更省事）');
    return { doc: { participants: [] }, errors, warnings };
  }
  const participants = [];
  const dates = new Set();
  for (const f of readdirSync(dir).filter((n) => n.endsWith('.json')).sort()) {
    try {
      const doc = JSON.parse(readFileSync(join(dir, f), 'utf8'));
      if (doc && typeof doc === 'object' && typeof doc.date === 'string' && doc.date.trim()) {
        dates.add(doc.date.trim());
      }
      const list = Array.isArray(doc)
        ? doc
        : (Array.isArray(doc?.participants) ? doc.participants : [doc]);
      participants.push(...list);
    } catch (e) {
      errors.push(`${f} 读不了：${e.message} —— 一个坏文件会让中位数静静算错，所以这里直接停`);
    }
  }
  let date;
  if (dates.size > 1) {
    warnings.push(`文件里的测量日期不止一个（${[...dates].join(' / ')}）—— 到底哪天的？`);
    // 仍然取最早那个：它至少是"真的测过的一天"，但提示要让人自己去统一
    date = [...dates].sort()[0];
  } else if (dates.size === 1) {
    date = [...dates][0];
  }
  const doc = { participants };
  if (date) doc.date = date;
  return { doc, errors, warnings };
}

// ---------------------------------------------------------------- 夹具

/** kit §A5 举的那个例子（2 / 2 / 3 / 4 → 中位数 2.5 → 门槛 3），当 `--example` 用 */
const EXAMPLE = {
  date: '2026-11-04',
  participants: [
    { id: 'S1', coldStart: true, steps: { toWorkout: 1, pickOrSwitchExercise: 0, adjustWeight: 0, bigButton: 1 }, total: 2 },
    { id: 'S2', coldStart: true, steps: { toWorkout: 1, pickOrSwitchExercise: 0, adjustWeight: 0, bigButton: 1 }, total: 2 },
    { id: 'S3', coldStart: true, steps: { toWorkout: 1, pickOrSwitchExercise: 0, adjustWeight: 1, bigButton: 1 }, total: 3 },
    { id: 'S4', coldStart: true, steps: { toWorkout: 1, pickOrSwitchExercise: 1, adjustWeight: 1, bigButton: 1 }, total: 4 },
  ],
};

/** 一个人的模板（存成 `usability/thresholds/S1.json` 这样的名字；每人一份） */
function template() {
  return {
    _note: '一位被试的熟人短测记录。一个"正字" = 1 次点击；表见 docs/usability-test-kit.md §A4。'
      + '四个 steps 的顺序/含义照 §A4 表头，total 要自己再手加一遍（分项之和必须等于它）。'
      + '保存成 usability/thresholds/S1.json 这样的名字，每位一份。',
    date: 'YYYY-MM-DD',
    participants: [
      {
        id: 'S1',
        coldStart: true,
        steps: Object.fromEntries(STEPS.map((s) => [s.key, 0])),
        total: 0,
      },
    ],
  };
}

// ---------------------------------------------------------------- 自检

/**
 * 自检。**每一条都对应一次真会犯的错**，不是凑数：
 * 奇数/偶数中位数、.5 上取整且实测值保留、n=2、分项≠总、缺步骤、重复、非整数、
 * 某步 >3 的"先修"提示、P90=max、P99 留空、`--json` 结构稳定、空输入不崩、`--entry` 解析。
 */
export function selftest() {
  let bad = 0;
  const check = (label, cond, why = '') => {
    if (cond) {
      console.log(`  \x1b[32m✓\x1b[0m ${label}`);
    } else {
      bad += 1;
      console.log(`  \x1b[31m✗\x1b[0m ${label}${why ? `　→ ${why}` : ''}`);
    }
  };
  const p = (id, total, v) => ({
    id,
    coldStart: true,
    steps: Object.fromEntries(STEPS.map((s, i) => [s.key, v[i]])),
    total,
  });
  const doc = (...ps) => ({ date: '2026-11-04', participants: ps });

  // ① 奇数 n：中位数就是中间那个（3、4、5 人各一条意思一样，这里用 3 人）
  {
    const out = build(doc(p('S1', 2, [1, 0, 0, 1]), p('S2', 3, [1, 0, 1, 1]), p('S3', 4, [1, 1, 1, 1])));
    check('奇数 n=3 的中位数取中间那个（2/3/4 → 3）',
      out.errors.length === 0 && out.median === 3 && out.threshold === 3,
      `median=${out.median} threshold=${out.threshold} errors=${out.errors.join(';')}`);
  }

  // ② 偶数 n 的 .5：门槛向上取整，但**实测值 2.5 必须留在输出里**（§3 注释要写它）
  {
    const out = build(EXAMPLE);
    check('偶数 n 的 .5 → 门槛 3，且实测中位数 2.5 保留在输出里',
      out.median === 2.5 && out.threshold === 3
        && out.tableRows[0].includes('2.5')
        && out.comment.includes('中位数 2.5')
        && out.conclusion === 'n=4，总点击 2 / 2 / 3 / 4，中位数 2.5，门槛取 3',
      `rows[0]=${out.tableRows[0]} conclusion=${out.conclusion}`);
  }

  // ③ n=2 / n=6：人数不在 3–5 就不该出门槛（kit §A1）
  {
    const two = build(doc(p('S1', 2, [1, 0, 0, 1]), p('S2', 3, [1, 0, 1, 1])));
    const six = build(doc(...Array.from({ length: 6 }, (_, i) => p(`S${i + 1}`, 2, [1, 0, 0, 1]))));
    check('n=2 / n=6 → 硬报错（kit §A1 只招 3–5 个人）',
      two.errors.some((e) => e.includes('少于 3 个人'))
        && six.errors.some((e) => e.includes('只招 3–5 个人')),
      `errors=${[...two.errors, ...six.errors].join(';')}`);
  }

  // ④ 分项之和 ≠ 手填的总点击：纸面上这两栏是分开填的，最常见的错
  {
    const out = build(doc(
      p('S1', 2, [1, 0, 0, 1]),
      p('S2', 2, [1, 0, 0, 1]),
      p('S3', 5, [1, 0, 1, 1]), // 分项 3，手填 5
    ));
    check('分项之和 ≠ 总点击 → 硬报错（并报出两个数）',
      out.errors.some((e) => e.includes('分项之和 3') && e.includes('5')),
      `errors=${out.errors.join(';')}`);
  }

  // ⑤ 缺步骤：只报总数不算数（没有分项就查不出哪一步 > 3 次）
  {
    const missing = p('S1', 2, [1, 0, 0, 1]);
    delete missing.steps.bigButton;
    const out = build(doc(missing, p('S2', 2, [1, 0, 0, 1]), p('S3', 3, [1, 0, 1, 1])));
    check('缺步骤 → 硬报错（并点名缺的是哪一个）',
      out.errors.some((e) => e.includes('缺步骤') && e.includes('④大按钮写入')),
      `errors=${out.errors.join(';')}`);
  }

  // ⑥ 同一人重复、总点击不是整数、多了一个自创步骤：三类静默错都要拦住
  {
    const out = build(doc(
      p('S1', 2, [1, 0, 0, 1]),
      p('S1', 3, [1, 0, 1, 1]),
      { id: 'S3', steps: { ...p('x', 1, [1, 0, 0, 0]).steps }, total: 2.5 },
      { id: 'S4', steps: { toWorkout: 1, pickOrSwitchExercise: 0, adjustWeight: 0, bigButton: 1, extra: 0 }, total: 2 },
    ));
    check('代号重复 / 总点击非整数 / 自创步骤名 → 三类都硬报错',
      out.errors.some((e) => e.includes('重复'))
        && out.errors.some((e) => e.includes('总点击必须是整数'))
        && out.errors.some((e) => e.includes('多了一个步骤字段')),
      `errors=${out.errors.join(';')}`);
  }

  // ⑦ 某步 > 3 次：给"先修那一步"的提示，且**点名是哪一步、是谁**
  {
    const out = build(doc(
      p('S1', 2, [1, 0, 0, 1]),
      p('S2', 2, [1, 0, 0, 1]),
      p('S3', 7, [1, 0, 5, 1]), // ③改重量点了 5 下
    ));
    check('某步 > 3 次 → 提示"先修那一步"，并点名步骤与被试',
      out.errors.length === 0
        && out.overThreeSteps.length === 1
        && out.overThreeSteps[0].key === 'adjustWeight'
        && out.overThreeSteps[0].ids.includes('S3')
        && out.overThreeHints.length === 1
        && out.overThreeHints[0].includes('先修这一步'),
      `overThreeSteps=${JSON.stringify(out.overThreeSteps)}`);
  }

  // ⑧ P90 = 本次最大值（不是插值算出来的分位数）、P99 留空
  {
    const out = build(EXAMPLE);
    check('P90 = 本次最大值，且注明"小样本最大值，不是分位数"',
      out.p90 === out.max && out.p90 === 4
        && out.tableRows[1] === '| P90 | 4 次（小样本最大值，不是分位数） |',
      `rows[1]=${out.tableRows[1]}`);
    check('P99 留空（n=3–5 算不出可信分位数，不用插值假装）',
      out.p99 === null && out.tableRows[2] === '| P99 |  |',
      `rows[2]=${out.tableRows[2]}`);
  }

  // ⑨ 三行 markdown 的**确切样子**（会被原样粘进 docs/analytics.md §3；中位数那格是机器读的）
  {
    const out = build(EXAMPLE);
    const want = [
      '| 中位数 | ≤ 3 次（实测中位数 2.5，向上取整） |',
      '| P90 | 4 次（小样本最大值，不是分位数） |',
      '| P99 |  |',
    ];
    check('三行 markdown 与 §3 的表逐字对得上（中位数那格有可读的整数）',
      JSON.stringify(out.tableRows) === JSON.stringify(want),
      JSON.stringify(out.tableRows));
  }

  // ⑩ `--json` 结构稳定：同一份输入两次构建逐字相同，且关键字段齐全、类型对
  {
    const a = JSON.stringify(build(EXAMPLE));
    const b = JSON.stringify(build(EXAMPLE));
    const out = build(EXAMPLE);
    const keys = ['errors', 'warnings', 'n', 'date', 'totals', 'median', 'threshold', 'max',
      'p90', 'p99', 'overThreeSteps', 'participants', 'tableRows', 'comment', 'conclusion'];
    check('--json 结构稳定（两次逐字相同、关键字段齐全）',
      a === b && keys.every((k) => k in out) && Array.isArray(out.tableRows) && out.p99 === null,
      a === b ? '字段缺了' : '两次输出不同');
  }

  // ⑪ 空输入不崩：没有输入 / 顶层不对 / 目录不存在 —— 都该是"人话错误"，不是栈
  {
    let crashed = null;
    let out = null;
    try {
      out = build({ participants: [] });
      const out2 = build(null);
      const out3 = build({});
      const dir = readDir('/definitely/not/a/real/dir/lianleme-threshold');
      check('空输入不崩（无被试 / null / 顶层错 / 目录不存在 → 人话错误）',
        out.errors.length > 0 && out2.errors.length > 0 && out3.errors.length > 0
          && dir.errors.length > 0 && dir.doc.participants.length === 0,
        `errors=${out.errors.join(';')} dir=${dir.errors.join(';')}`);
    } catch (e) {
      crashed = e;
      check('空输入不崩（无被试 / null / 顶层错 / 目录不存在 → 人话错误）', false, crashed.message);
    }
  }

  // ⑫ `--entry` 解析：格式对/错都要有确定答案
  {
    const ok = parseEntry('S1=1,0,0,1=2');
    const noTotal = parseEntry('S1=1,0,0,1');
    const shortSteps = parseEntry('S1=1,0,1=2');
    const badStep = parseEntry('S1=1,0,x,1=2');
    check('--entry 解析（对的解析出 4 个分项 + 总点击；少一截/非整数都报错）',
      ok.participant && ok.participant.total === 2 && ok.participant.steps.bigButton === 1
        && Boolean(noTotal.error) && Boolean(shortSteps.error) && Boolean(badStep.error),
      JSON.stringify({ ok, noTotal, shortSteps, badStep }));
  }

  // ⑬ 测量日期：真实日期才收；`2026-02-31` 这种滚月的也要抓（§3 注释要能追溯）
  {
    const out = build(EXAMPLE, { date: '2026-02-31' });
    check('测量日期不是真实日期 → 硬报错',
      out.errors.some((e) => e.includes('测量日期')),
      `errors=${out.errors.join(';')}`);
  }

  // ⑭ 奇数 n 时中位数就是整数，那一格不该出现"向上取整"（别把 3 写成 3.0 / 3.5）
  {
    const out = build({ date: '2026-11-04', participants: [p('S1', 2, [1, 0, 0, 1]), p('S2', 3, [1, 0, 1, 1]), p('S3', 4, [1, 1, 1, 1])] });
    check('整数中位数时 §3 中位数格只写整数（不出现 .0 / 向上取整）',
      out.tableRows[0] === '| 中位数 | ≤ 3 次 |',
      out.tableRows[0]);
  }

  // ⑮ 打印出来的那三行必须能被**报告工具的解析器**读出同一个门槛 ——
  // 这是本工具存在的全部意义（§3 那一格是机器读的）：格式改坏了，这里当场红。
  {
    const out = build(EXAMPLE);
    const section = '## 3. 体验守卫指标\n\n| 分位 | 目标（**待校准**） |\n|---|---|\n'
      + `${out.tableRows.join('\n')}\n\n> 注释\n\n## 4. 看板布局\n`;
    const read = parseTapMedianTarget(section);
    check('打印的中位数那一行能被 tool/usability-report.mjs 读出同一个门槛',
      read.value === out.threshold,
      `读出来 ${read.value}，门槛 ${out.threshold}（${read.why}）`);
  }

  if (bad) {
    console.error(`\n\x1b[31m✗ 自检失败 ${bad} 项 —— 门槛口径本身就不可信，先修它\x1b[0m`);
    return 1;
  }
  console.log('\n\x1b[32m✓ 自检通过：中位数 / .5 向上去整 / P90 小样本最大值 / P99 留空 / 硬校验都算得对\x1b[0m');
  return 0;
}

// ---------------------------------------------------------------- CLI

if (process.argv[1] && process.argv[1].endsWith('usability-threshold.mjs')) {
  const argv = process.argv.slice(2);
  const valuesOf = (flag) => {
    const out = [];
    for (let i = 0; i < argv.length; i += 1) {
      if (argv[i] === flag && argv[i + 1] !== undefined) out.push(argv[i + 1]);
    }
    return out;
  };
  const argOf = (flag, dflt) => {
    const i = argv.indexOf(flag);
    return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : dflt;
  };

  if (argv.includes('--template')) {
    console.log(JSON.stringify(template(), null, 2));
  } else if (argv.includes('--selftest')) {
    process.exitCode = selftest();
  } else {
    const entries = valuesOf('--entry');
    const date = argOf('--date', undefined);
    const useExample = argv.includes('--example');
    const dir = argOf('--dir', DEFAULT_DIR);

    let input;
    if (useExample) {
      input = { doc: EXAMPLE, errors: [], warnings: [] };
    } else if (entries.length) {
      const participants = [];
      const inputErrors = [];
      for (const e of entries) {
        const { participant, error } = parseEntry(e);
        if (error) inputErrors.push(error);
        else participants.push(participant);
      }
      input = { doc: { participants }, errors: inputErrors, warnings: [] };
    } else {
      input = readDir(dir);
    }

    const out = build(input.doc, { date });
    // 读入阶段（目录/命令行）的错误排在最前面：它们是"数还没进来"，与"数本身抄错了"不同。
    // 同一个根因只报一次：目录读不到时 build() 还会说「一个被试都没有」，那是重复噪音。
    const noParticipants = (input.doc?.participants ?? []).length === 0;
    const rest = input.errors.length && noParticipants
      ? out.errors.filter((e) => !e.includes('一个被试都没有'))
      : out.errors;
    out.errors = [...input.errors, ...rest];
    out.warnings = [...input.warnings, ...out.warnings];

    if (out.errors.length) {
      console.error(`✗ 输入有 ${out.errors.length} 处硬错误（先改这些，门槛才可信）：`);
      for (const e of out.errors) console.error(`  · ${e}`);
      process.exit(1);
    }

    if (useExample) {
      console.error('⚠️ 这是 kit §A5 那个例子（2/2/3/4）的**样例数据**，不是真测的 —— 别回填。');
    }
    for (const w of out.warnings) console.error(`⚠️ ${w}`);
    for (const h of out.overThreeHints) console.error(h);
    if (out.overThreeSteps.length) {
      console.error('⚠️ 这次**先别回填** docs/analytics.md §3 —— 按 kit §A5.5「超线先修」把那一步修掉再标定。');
    }
    if (out.dateSource === '今天（没提供测量日期）') {
      console.error(`⚠️ 没给测量日期，按今天（${out.date}）算 —— 不是测量当天就用 --date 或 JSON 的 date 改正（§3 注释要写测量日期）。`);
    }
    if (!useExample) {
      console.error('⚠️ 回填时把 §3 表头里的「待校准」删掉（kit §A6 第 1 条）。');
    }

    if (argv.includes('--json')) {
      console.log(JSON.stringify(out, null, 2));
    } else {
      console.log(out.tableRows.join('\n'));
      console.log();
      console.log(out.comment);
      console.log();
      console.log(out.conclusion);
    }
  }
}
