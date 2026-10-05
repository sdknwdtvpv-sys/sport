#!/usr/bin/env node
/**
 * 练了么 · 可用性测试口径的自检
 *
 * **为什么要它**：`tool/usability-report.mjs` 会给出"通过 / 不通过"这种结论性输出。
 * 它自己算错了，人不会发现 —— 只会照着错结论去砍功能或改定位。
 * 所以这里把口径钉死在三件事上：
 *   1. **中位数**：5 个人 1/1/1/2/4 的中位数是 1（不是 1.8）
 *   2. **硬错误真的会拦**：分项加总 ≠ 手填合计、缺 T1、q3 写了别的词 —— 必须 exit 1
 *   3. **判定与 §8 的目标一致**：差一点点（tap 中位数 = 2）也必须判不通过
 *
 * 退出码：0 全过 / 1 有失败。
 */

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build, median, compute, verdict, TARGETS, TASKS } from './usability-report.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

const person = (id, over = {}) => ({
  id,
  consent: true,
  tasks: Object.fromEntries(
    ['T1', 'T2', 'T3', 'T4', 'T5', 'T6'].map((t) => [t, { done: true, prompts: 0, seconds: 60 }]),
  ),
  tap: {
    firstLog: { bigButton: 1, stepper: 0, sheetConfirm: 0, keyboard: 0, other: 0 },
    t6Edit: { bigButton: 1, stepper: 0, sheetConfirm: 0, keyboard: 0, other: 0 },
  },
  typing: 0,
  scrolls: 0,
  t6: { adopted: true },
  q3: 'lianleme',
  ...over,
});

/**
 * 判据表 ↔ 脚本的 TARGETS 对账。
 *
 * **为什么要有**：`docs/usability-test.md` 的「定量指标」表写着几行目标，脚本只判其中几项 ——
 * 两边各写一份就会漂，而漂了**没有任何症状**（报告照出、结论照样"通过"）。
 * SUS-lite 就是这么挂着的：文档写了一行、脚本里也有目标值 `susLite: 80`，
 * 但**题项与计分公式全仓不存在**，而且判据是"没填就不判" —— 等于一道永远不生效的门。
 * 2026-10-01 拍板删掉它，同时加上这条对账。
 *
 * 判据用的是**行数**（文档表里的数据行 == 脚本判的项数）而不是逐字匹配：
 * 措辞可以改，但"文档承诺几项、脚本就判几项"这条不能少。
 * 另外两边都不许再出现 `SUS` —— 它已经不在判据里了。
 */
export function docConsistency() {
  const failures = [];
  const docPath = join(ROOT, 'docs/usability-test.md');
  let doc = '';
  try {
    doc = readFileSync(docPath, 'utf8');
  } catch {
    return ['读不到 docs/usability-test.md —— 判据表与脚本的对账没法做'];
  }

  // 取「## 定量指标」这一节里的第一张表
  const section = doc.split(/^## /m).find((s) => s.startsWith('定量指标')) ?? '';
  const rows = section
    .split('\n')
    .filter((l) => l.trim().startsWith('|'))
    .map((l) => l.trim());
  const body = rows.slice(2); // 去掉表头与分隔行
  const rowsCount = body.filter((l) => l.length > 2).length;

  // 脚本实际会判几项（拿一份样例跑一遍 verdict，数 checks）
  const sample = build({ participants: [person('P1')] }).verdict.checks;
  if (rowsCount !== sample.length) {
    failures.push(`docs/usability-test.md 的「定量指标」表有 ${rowsCount} 行，`
      + `而脚本只判 ${sample.length} 项 —— 文档承诺了脚本不判的东西`
      + `（或反过来）：脚本判的是 [${sample.map((c) => c.name).join('、')}]`);
  }
  if (body.some((r) => /SUS/i.test(r))) {
    failures.push('docs/usability-test.md 的「定量指标」表里还有 SUS 这一行 —— '
      + '它已不在判据里（2026-10-01 删掉：题项与公式全仓不存在）');
  }
  if (/SUS/i.test(JSON.stringify(TARGETS))) failures.push('TARGETS 里还有 SUS —— 已拍板删掉');
  if (TARGETS.susLite !== undefined) failures.push('TARGETS.susLite 还在');
  if (!TASKS.length) failures.push('TASKS 是空的');
  return failures;
}

export async function selftest() {
  const failures = [];
  const check = (name, ok, detail = '') => {
    if (!ok) failures.push(`${name}${detail ? `：${detail}` : ''}`);
  };

  // ---- 1. 中位数口径 ----
  check('中位数：[1,1,1,2,4] → 1', median([1, 1, 1, 2, 4]) === 1, `实际 ${median([1, 1, 1, 2, 4])}`);
  check('中位数：偶数个取中间两个的平均（[1,2] → 1.5）', median([1, 2]) === 1.5);
  check('中位数：空数组 → null（没有数据就不许编一个数）', median([]) === null);

  // ---- 2. 五个人全达标 → 通过 ----
  const good = { participants: [person('P1'), person('P2'), person('P3'), person('P4'), person('P5')] };
  const g = build(good);
  check('全达标时没有硬错误', g.errors.length === 0, g.errors.join('；'));
  check('全达标 → 通过', g.verdict.pass === true);
  check('tap 中位数 = 1', g.tapMedian === 1, `实际 ${g.tapMedian}`);

  // ---- 3. 差一点点也必须判不通过 ----
  const worse = {
    participants: [
      person('P1'),
      person('P2', { tap: { firstLog: { bigButton: 2, stepper: 0, sheetConfirm: 0, keyboard: 0, other: 0 }, t6Edit: { bigButton: 1, stepper: 0, sheetConfirm: 0, keyboard: 0, other: 0 } } }),
      person('P3'),
      person('P4'),
      person('P5'),
    ],
  };
  const w = build(worse);
  check('有一人点了 2 次 → 中位数仍是 1', w.tapMedian === 1, `实际 ${w.tapMedian}`);
  // 5 个人的中位数要变成 2，得**至少 3 个人**是 2 次 ——
  // 第一版这里只改了 2 个人，算出中位数 1，于是这条自检自己红了（口径没错，是测试写错）。
  const twoThree = build({
    participants: [
      person('P1', { tap: { firstLog: { bigButton: 2, stepper: 0, sheetConfirm: 0, keyboard: 0, other: 0 } } }),
      person('P2', { tap: { firstLog: { bigButton: 2, stepper: 0, sheetConfirm: 0, keyboard: 0, other: 0 } } }),
      person('P3', { tap: { firstLog: { bigButton: 2, stepper: 0, sheetConfirm: 0, keyboard: 0, other: 0 } } }),
      person('P4'),
      person('P5'),
    ],
  });
  check('3 人点 2 次 → 中位数 2', twoThree.tapMedian === 2, `实际 ${twoThree.tapMedian}`);
  check('中位数 2 → 不通过（硬约束 = 1）', twoThree.verdict.pass === false);

  // ---- 4. Q3 的裁判作用 ----
  const q3Bad = build({
    participants: [person('P1'), person('P2'), person('P3', { q3: 'xunji' }), person('P4', { q3: 'xunji' }), person('P5', { q3: 'xunji' })],
  });
  check('Q3 只有 2/5 选本品 → 不通过（3/5 = 60% 才够）', q3Bad.verdict.pass === false);
  check('Q3 是比例口径：2/2 也算达标（n<5 时绝对数不可达）',
    build({ participants: [person('P1'), person('P2')] }).verdict.checks
      .find((c) => c.name === 'Q3 选本品').ok === true);
  check('Q3 统计对得上', q3Bad.q3Count === 2 && q3Bad.q3Xunji === 3);

  // ---- 5. 硬错误：抄错必须拦住 ----
  const mismatch = build({
    participants: [person('P1', { tap: { firstLog: { bigButton: 1, stepper: 1, sheetConfirm: 1, keyboard: 0, other: 1, total: 3 } } })],
  });
  check('分项合计 ≠ 手填 total → 硬错误',
    mismatch.errors.some((e) => e.includes('分项合计')), mismatch.errors.join('；'));

  const noT1 = build({ participants: [(() => { const p = person('P1'); delete p.tasks.T1; return p; })()] });
  check('缺 T1 → 硬错误', noT1.errors.some((e) => e.includes('缺 T1')));

  const doneNoSeconds = build({
    participants: [person('P1', { tasks: { ...person('P1').tasks, T1: { done: true, prompts: 0, seconds: 0 } } })],
  });
  check('标了完成却没有耗时 → 硬错误',
    doneNoSeconds.errors.some((e) => e.includes('没有耗时')));

  const badQ3 = build({ participants: [person('P1', { q3: '也许吧' })] });
  check('q3 写了自由文本 → 硬错误', badQ3.errors.some((e) => e.includes('q3 必须是')));

  const zeroTap = build({
    participants: [person('P1', { tap: { firstLog: { bigButton: 0, stepper: 0, sheetConfirm: 0, keyboard: 0, other: 0 } } })],
  });
  check('第一次记录 0 次点击 → 硬错误（不可能）',
    zeroTap.errors.some((e) => e.includes('合计为 0')));

  // ---- 6. 少于 5 人只警告，不静默 ----
  const three = build({ participants: [person('P1'), person('P2'), person('P3')] });
  check('只填 3 人 → 警告（不阻断）',
    three.warnings.some((x) => x.includes('被试数是 3')), three.warnings.join('；'));

  // ---- 7. 任务失败模式要能聚合出来（复盘用） ----
  const withFailures = build({
    participants: [
      person('P1', { tasks: { ...person('P1').tasks, T4: { done: false, prompts: 2, seconds: 0 } } }),
      person('P2', { tasks: { ...person('P2').tasks, T4: { done: true, prompts: 1, seconds: 40 } } }),
    ],
  });
  check('T4 的失败/提示能聚合',
    withFailures.taskFailures.T4?.failed?.includes('P1')
    && withFailures.taskFailures.T4?.prompted?.includes('P2'),
    JSON.stringify(withFailures.taskFailures));

  // ---- 8. compute 口径直测：打字/滚动是**求和**，不是平均 ----
  const sums = compute({
    participants: [
      person('P1', { typing: 1, scrolls: 2 }),
      person('P2', { typing: 2, scrolls: 0 }),
    ],
  });
  check('打字次数求和 = 3', sums.typing === 3, `实际 ${sums.typing}`);
  check('滚动次数求和 = 2', sums.scrolls === 2, `实际 ${sums.scrolls}`);

  check('verdict 是纯函数（同样的输入两次结果一致）',
    JSON.stringify(verdict(compute({ participants: [person('P1')] })))
    === JSON.stringify(verdict(compute({ participants: [person('P1')] }))));

  // ---- 9. 判据表 ↔ 脚本对账（跨文件，见 docConsistency 的注释） ----
  for (const f of docConsistency()) failures.push(f);

  if (failures.length) {
    console.error(`✗ 可用性测试口径自检失败 ${failures.length} 项：`);
    for (const f of failures) console.error(`  · ${f}`);
    return 1;
  }
  console.log('✓ 可用性测试口径自检通过（中位数 · 硬错误拦截 · 判定与目标一致 · 失败模式聚合 '
    + '· 判据表与脚本项数对得上且都没有 SUS）');
  return 0;
}

if (process.argv[1] && process.argv[1].endsWith('usability-selftest.mjs')) {
  process.exit(await selftest());
}
