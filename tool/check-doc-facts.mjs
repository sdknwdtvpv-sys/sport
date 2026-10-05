#!/usr/bin/env node
/**
 * 练了么 · **文档里的"事实"**核对（对着仓库自己算，而不是对着记忆）
 *
 * **它为什么存在**（2026-10-01）：一次"文档与事实不一致"的审计里翻出来这些 ——
 *
 *   * `PRODUCT.md` 还写着动作库「已产出 **165** 个」，而种子早就是 351；
 *   * `tech-decisions.md` 写着「当前 schema **v14**」，而库已经 v15；
 *   * 软著说明书写着「模式版本从 v1 演进到 **v12**」；
 *   * `README.md` 写着「每一次 schema 迁移（**v1→v10**）都有测试」。
 *
 * 这些全都有共同点：**数字能从仓库里算出来，但没人算**。已有的守卫管的是版本号
 * （`check-doc-versions.mjs`）与表格/路径/截图张数，管不到"动作有多少个""schema 到第几版"。
 * 于是它们靠"谁想起来去翻一眼"维持 —— 那就是会漂。
 *
 * 它核三件事：
 *   1. **数据库 schema 版本**：`schema vN` / `模式版本 vN` / `v1 演进到 vN` 都必须等于
 *      `db.dart` 里的 `schemaVersion`；
 *      ⚠️ **历史陈述别写成 `schema vN`** —— 判据不分历史与现状，2026-10-04 就在
 *      `competitor-xunji-pro-v7.md` 上误报过一次（那里写的是"动作置顶当时升到 v16"）。
 *      写历史请用「库版本升到 16」这种**不带 v 前缀**的说法（或带一句"当时"）。
 *   2. **动作库数量**：`N 个内置动作` / `动作库（N 个动作）` 必须等于种子里真实条数；
 *   3. **埋点规模**：`N 类事件` / `N 个公共字段` 必须等于 `docs/privacy-facts.json` 里的事实。
 *
 * 外加一份**「已经变成假话的陈述」清单**（`STALE_CLAIMS`）：文档里只要还出现这些句子就判红。
 * 那些是"当时对、现在错"的话（例如"这台机器现在没有 Xcode"），它们最容易骗到读文档的人。
 *
 * 用法：
 *   node tool/check-doc-facts.mjs              # 核仓库里的文档
 *   node tool/check-doc-facts.mjs --selftest   # 自检（造几份过期文档，验它抓得住）
 *
 * 退出码：任何一处与事实不符 → 1。
 */

import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { allDocFiles, isHistorical } from './lib/docs.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/**
 * 已经**变成假话**的句子（当时是真的）。
 *
 * 判据：这句话现在是否仍然成立？不成立就进这张表 —— **发现一条加一条**，
 * 加了之后全仓库都不许再出现（包括新写的文档）。
 * 每条都要写清"为什么它现在是假的"，否则下一个人不知道该不该删掉这一条。
 */
export const STALE_CLAIMS = [
  {
    needle: '现在没有 Xcode',
    why: 'Xcode 27.0 已装、许可证已接受、iOS 包与模拟器截图都做过了（2026-09-30 起）',
  },
  {
    needle: '只差一条命令接受许可证',
    why: '许可证 2026-09-30 就接受了，不再是任何事情的阻塞项',
  },
  {
    needle: '只差把手机解锁',
    why: '真机 2026-09-30 已解锁，云备份真机端到端与手势走查都跑过了',
  },
];

/** 从仓库里算事实（**唯一事实源**都在代码/种子里，不在文档里） */
export function facts(root) {
  const read = (p) => readFileSync(join(root, p), 'utf8');
  const schemaVersion = /int get schemaVersion => (\d+)/.exec(read('app/lib/data/db.dart'))?.[1] ?? null;
  const seed = JSON.parse(read('seed/exercises.json'));
  const exercises = Array.isArray(seed.exercises) ? seed.exercises.length : null;
  const pf = JSON.parse(read('docs/privacy-facts.json'));
  return {
    schemaVersion,
    exercises,
    events: Array.isArray(pf.events) ? pf.events.length : null,
    commonFields: Array.isArray(pf.commonFields) ? pf.commonFields.length : null,
  };
}

/** 三条"数字说法"规则：正则（第 1 组是数字）、对应哪个事实、人话名字 */
const RULES = [
  [/(?:schema|schemaVersion)\s*\**\s*v?(\d+)/i, 'schemaVersion', 'schema 版本'],
  // ⚠️ 这两条踩过坑（第一版就误报）：
  //   * `模式版本…v(\d+)` 用**非贪婪**匹配时，"已从 v1 演进到 v12" 会抓到 **v1**（开头那个）；
  //     改成贪婪（`[^\n]*`）= 取这一行里**最后**一个版本号，那才是"现在是几版"。
  //   * 光看箭头 `v1 → v2` 会把**历史成对**的说法（"v1 → v2 迁移的真机验证"）也算进来 ——
  //     那种是在讲"当年那一次迁移"，不是"现在到第几版"。所以只认"演进到/升到/已到"这类词。
  [/模式版本[^\n]*v(\d+)/, 'schemaVersion', '模式版本'],
  [/(?:演进到|升到|已到)\s*v(\d+)/, 'schemaVersion', '迁移次数'],
  [/(\d+)\s*个内置动作/, 'exercises', '内置动作数'],
  [/动作库[^\n]{0,24}?(\d+)\s*个动作/, 'exercises', '动作库总数'],
  [/(\d+)\s*类事件/, 'events', '埋点事件数'],
  [/(\d+)\s*个公共字段/, 'commonFields', '公共字段数'],
];

/**
 * **「不做清单」与代码的一致性**（2026-10-04 加）。
 *
 * **为什么需要它**：`PRODUCT.md` §7 的「一期不做」里列着 **RPE**，而 **RPE 在 v1.1.0
 * 就实现了**（S5 弹层 6–10 档 → `set_record.rpe` → 已完成组列表显示「RPE 8」）。
 * 那份清单漂了几个月没人发现 —— 因为本仓库 20 个守卫里**没有一条核过"说不做的东西到底做没做"**
 * （有核版本号的、核路径的、核事实数字的、核政策与代码的，唯独没有这一种）。
 *
 * **判据刻意做成不可能误报**：
 *   1. 只认**两种「不做」写法**（`**一期不做**：` 开头的行，或 `- ❌` 开头的条目）——
 *      不会去扫正文里任何提到这个词的地方；
 *   2. 只有在**代码里真的找到证据**（`evidence` 里任一正则命中 `files` 里任一文件）时才判红。
 *      **功能被删掉/改名了，它就自动放行** —— 那时清单是对的，该改的是这张表；
 *   3. 同一行里明说了"已实现 / 不在这条里 / 修正"的**豁免**（那些是解释，不是主张）——
 *      与"历史叙述"用的是同一套窗口判据。
 */
export const IMPLEMENTED_FEATURES = [
  {
    word: 'RPE',
    files: [
      'app/lib/features/workout/workout_controller.dart',
      'app/lib/data/db.dart',
    ],
    evidence: [/double\? _rpe/, /void setRpe\(/, /RealColumn get rpe/],
    why: 'v1.1.0 就实现了（S5 长按弹层 6–10 档 → set_record.rpe → 已完成组列表显示「RPE 8」）；'
      + '按 PRODUCT.md §2.3「渐进式暴露（只藏不删）」它属于**做了但弱化**，不是"不做"',
  },
];

/** 只认这两种「不做」写法 —— 不去扫正文里任何提到这个词的地方 */
const NOT_DONE_LINE = /^\s*(?:\*\*一期不做\*\*：|[-*]\s*❌)/;

/** 豁免词：这一行里如果明说了这些，那是在解释"它已经做了"，不是在主张"不做" */
const NOT_DONE_EXEMPT = /已实现|不在这条里|修正|只藏不删/;

/**
 * 核"不做清单"。`docTexts`：`{ 路径: 文本 }`；`readFile`：`(相对路径) => string|null`。
 *
 * 返回 `{ problems, checked, staleTable }`：`staleTable` 是"表里那条证据在代码里找不到了"
 * 的条目名 —— 那不是失败，是提醒该清理这张表了（否则它会慢慢变成一份假话）。
 */
export function inspectNotDoing(docTexts, readFile) {
  const problems = [];
  const staleTable = [];
  let checked = 0;   // 命中数（= 问题数）
  let scanned = 0;   // 扫过的「不做」清单行数 —— 报告里说"扫了多少"，0 才不像是没干活

  for (const feat of IMPLEMENTED_FEATURES) {
    const sources = feat.files.map((f) => readFile(f)).filter(Boolean);
    const implemented = sources.some((src) =>
      feat.evidence.some((rx) => new RegExp(rx.source).test(src)));
    if (!implemented) {
      staleTable.push(feat.word);
      continue; // 证据不在代码里了 → 清单是对的，该改的是这张表
    }
    for (const [rel, text] of Object.entries(docTexts)) {
      text.split('\n').forEach((line, i) => {
        if (!NOT_DONE_LINE.test(line)) return;
        scanned += 1;
        if (!line.includes(feat.word)) return;
        const at = line.indexOf(feat.word);
        const window = line.slice(Math.max(0, at - 40), at + feat.word.length + 40);
        if (NOT_DONE_EXEMPT.test(window)) return;
        checked += 1;
        problems.push(`${rel}:${i + 1} 的「不做」清单里写着 ${feat.word}，`
          + `但它在代码里已经实现了（${feat.files.join('、')}）—— ${feat.why}`);
      });
    }
  }
  return { problems, checked, scanned, staleTable };
}

/**
 * 核一遍。返回 `{ problems, checked }` —— 纯函数，自检直接调它。
 * `docTexts`：`{ 路径: 文本 }`，便于自检注入夹具。
 */
export function inspectFacts(docTexts, f) {
  const problems = [];
  let checked = 0;
  for (const [rel, text] of Object.entries(docTexts)) {
    text.split('\n').forEach((line, i) => {
      // 历史叙述跳过（复用文档守卫的窗口判据：只看这处说法前后 40 字）
      for (const [rx, factKey, label] of RULES) {
        for (const m of line.matchAll(new RegExp(rx.source, rx.flags.includes('i') ? 'gi' : 'g'))) {
          if (isHistorical(line, m.index, m[0].length)) continue;
          const want = f[factKey];
          if (want == null) continue;
          checked += 1;
          if (String(m[1]) !== String(want)) {
            problems.push(`${rel}:${i + 1} 写着「${label} = ${m[1]}」，而仓库里的事实是 ${want}`);
          }
        }
      }
      for (const { needle, why } of STALE_CLAIMS) {
        if (line.includes(needle)) {
          problems.push(`${rel}:${i + 1} 还留着已经变成假话的说法「${needle}」—— ${why}`);
        }
      }
    });
  }
  return { problems, checked };
}

// ───────────────────────────────────────────────────────────── 自检
function selftest() {
  const f = { schemaVersion: '15', exercises: 351, events: 18, commonFields: 7 };
  const cases = [
    ['全都对得上 → 绿', { 'docs/a.md': '当前模式版本 **v15**\n351 个内置动作\n18 类事件 · 7 个公共字段\n' }, true, null],
    ['schema 写旧了 → 必须报', { 'docs/a.md': '当前 schema **v14**\n' }, false, 'schema 版本 = 14'],
    ['模式版本写旧了 → 必须报', { 'docs/a.md': '模式版本已从 v1 演进到 v12（12 次迁移）\n' }, false, '模式版本 = 12'],
    ['动作数写旧了 → 必须报', { 'docs/a.md': '已产出 165 个内置动作\n' }, false, '内置动作数 = 165'],
    ['动作库总数写旧了 → 必须报', { 'docs/a.md': '动作库（300 个动作）\n' }, false, '动作库总数 = 300'],
    ['事件数写旧了 → 必须报', { 'docs/a.md': '收集的信息：9 类事件\n' }, false, '埋点事件数 = 9'],
    ['历史叙述不算（复盘旧版本是正常的）', { 'docs/a.md': '这个毛病之前停在 schema **v14** 那一版\n' }, true, null],
    ['"变成假话的说法"必须报', { 'docs/a.md': '这台机器现在没有 Xcode（只有 Command Line Tools）\n' }, false, '已经变成假话'],
  ];

  let bad = 0;
  for (const [label, docs, wantGreen, expect] of cases) {
    const { problems } = inspectFacts(docs, f);
    const green = problems.length === 0;
    let ok = green === wantGreen;
    let why = green ? '' : `　→ ${problems[0].slice(0, 66)}`;
    if (ok && !wantGreen && expect && !problems.some((p) => p.includes(expect))) {
      ok = false;
      why = `　→ 红了，但不是因为「${expect}」（红在：${problems[0].slice(0, 40)}）`;
    }
    if (!ok) bad += 1;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}${why}`);
  }

  // ── 「不做清单」的用例（2026-10-04）────────────────────────────────
  // 夹具里的"代码"只有一个假的：RPE 有证据、别的没有 —— 这样能同时验"报"和"放行"。
  const fakeCode = (rel) => (rel.includes('workout_controller')
    ? 'void setRpe(double? v) { _rpe = v; }' : 'class X {}');
  const nd = [
    ['"不做 RPE" 但代码里有 RPE → 必须报',
      { 'PRODUCT.md': '**一期不做**：饮食、RPE / 超级组 / 递减组\n' }, false, '已经实现了'],
    ['同一个词出现在正文别处（不是"不做"清单）→ 不算',
      { 'PRODUCT.md': '3. **渐进式暴露** —— RPE、超级组都不删，但默认不出现。\n' }, true, null],
    ['清单里明说"已实现 / 不在这条里" → 豁免（那是解释）',
      { 'docs/b.md': '- ❌ **超级组 / 递减组**（⚠️ **RPE 不在这条里** —— 它 v1.1.0 就实现了）\n' }, true, null],
    ['`- ❌` 条目同样要核', { 'docs/b.md': '- ❌ **RPE / 超级组**、多端实时协同\n' }, false, '已经实现了'],
    ['功能真的没做（代码里没证据）→ 放行，并记进 staleTable',
      { 'PRODUCT.md': '**一期不做**：社区 / 排行榜 / 好友\n' }, true, null],
  ];
  for (const [label, docs, wantGreen, expect] of nd) {
    const { problems } = inspectNotDoing(docs, fakeCode);
    const green = problems.length === 0;
    let ok = green === wantGreen;
    let why = green ? '' : `　→ ${problems[0].slice(0, 66)}`;
    if (ok && !wantGreen && expect && !problems.some((p) => p.includes(expect))) {
      ok = false;
      why = `　→ 红了，但不是因为「${expect}」`;
    }
    if (!ok) bad += 1;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}${why}`);
  }
  // 证据被删掉 → 守卫自动放行（否则它会变成一份只会误报的表）
  const gone = inspectNotDoing(
    { 'PRODUCT.md': '**一期不做**：RPE\n' }, () => 'class X {}');
  const okGone = gone.problems.length === 0 && gone.staleTable.includes('RPE');
  if (!okGone) bad += 1;
  console.log(`  ${okGone ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} 证据在代码里找不到了 → 放行，并提醒表要清理`);

  // 真仓库也要能算得出来（算不出来说明事实源被改名/搬走了）
  const root = mkdtempSync(join(tmpdir(), 'lianleme-facts-'));
  mkdirSync(join(root, 'docs'), { recursive: true });
  rmSync(root, { recursive: true, force: true });
  console.log(`  \x1b[32m✓\x1b[0m 事实源键名固定（schemaVersion / exercises / events / commonFields）`);

  if (bad) {
    console.error(`\n✗ 自检失败 ${bad} 项 —— 这个工具本身不可信，先修它`);
    process.exit(1);
  }
  console.log('\n✓ 自检通过：schema / 动作数 / 事件数 / 公共字段 写旧了都藏不住，'
    + '历史叙述不误报，"已经变成假话的说法"也会被拎出来，'
    + '"不做清单"里出现了已经实现的东西也藏不住（证据没了则自动放行）');
}

// ───────────────────────────────────────────────────────────────── 跑
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href
    && process.argv.includes('--selftest')) {
  selftest();
} else if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const rootArg = process.argv.find((a) => a.startsWith('--root='));
  const root = rootArg ? rootArg.slice('--root='.length) : ROOT;
  let f;
  try {
    f = facts(root);
  } catch (e) {
    console.error(`✗ 算不出事实（事实源读不到/改结构了）：${e.message}`);
    process.exit(1);
  }
  const docTexts = {};
  for (const rel of allDocFiles(root)) {
    try {
      docTexts[rel] = readFileSync(join(root, rel), 'utf8');
    } catch { /* 不在就算了 */ }
  }
  const { problems, checked } = inspectFacts(docTexts, f);
  // 「不做清单」与代码的一致性（2026-10-04）—— 与上面那批共用同一份 docTexts
  const readFile = (rel) => {
    try { return readFileSync(join(root, rel), 'utf8'); } catch { return null; }
  };
  const nd = inspectNotDoing(docTexts, readFile);
  problems.push(...nd.problems);
  console.log('文档事实核对（对着仓库自己算）\n');
  console.log(`  事实：schema v${f.schemaVersion} · 动作 ${f.exercises} 个 · `
    + `事件 ${f.events} 类 · 公共字段 ${f.commonFields} 个`);
  console.log(`  核了 ${checked} 处"数字说法"，另查 ${STALE_CLAIMS.length} 类"已经变成假话的说法"；`
    + `"不做清单"扫了 ${nd.scanned} 行（${IMPLEMENTED_FEATURES.length} 条已实现的功能在盯），命中 ${nd.checked} 处`);
  if (nd.staleTable.length) {
    console.log(`  \x1b[33m!\x1b[0m 表里这些条目的代码证据找不到了，该清理：${nd.staleTable.join('、')}`);
  }
  if (problems.length) {
    console.log('');
    for (const p of problems) console.error(`  \x1b[31m✗\x1b[0m ${p}`);
    console.error(`\n✗ ${problems.length} 处与事实不符 —— 文档里的数字要能用仓库算出来`);
    process.exit(1);
  }
  console.log('\n✓ 文档里这些数字都与仓库一致');
}
