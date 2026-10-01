#!/usr/bin/env node
/**
 * 练了么 · "守卫有没有真的在跑"核对
 *
 * **它为什么存在**：这个仓库有二十多个自检工具，而"写了一个守卫"和"这个守卫真的在门禁里跑"
 * 是两件事 —— 2026-09-30 自查时发现 `tool/check-aab.mjs`（核 AAB 能不能上架）**从来没在门禁里跑过**，
 * 只在人想起来时被手动跑一次。一个不跑的守卫等于没有守卫，而它还会让人以为"这块有人守着"。
 *
 * 判据（三选一，**每条例外都要写理由**）：
 *   1. **直接跑**：`verify.sh` 里有 `node tool/<名字>`；
 *   2. **代跑**：被别的工具在门禁里调用（例如 `check-aab.mjs` 由 `check-dist.mjs` 在
 *      `dist/` 里有 AAB 时调用）—— 要求那个"代跑者"的源码里真的提到它；
 *   3. **按需**：报表类工具（要真实数据或要人做完测试才有意义）—— 名单里逐条写理由。
 *
 * 用法：
 *   node tool/check-guards-wired.mjs              # 核仓库
 *   node tool/check-guards-wired.mjs --selftest   # 自检（造几份假的，验它抓得住）
 *
 * 退出码：有守卫"存在但从不跑"且没写理由 → 1。
 */

import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/**
 * 由**别的工具**在门禁里代跑：值 = 代跑者（要能在它的源码里找到这个名字）。
 * 每条都写清"为什么不直接跑"。
 */
const DELEGATED = {
  'tool/check-aab.mjs': {
    by: 'tool/check-dist.mjs',
    why: '需要一份真的 AAB；交给 check-dist 在 dist/ 里有当前版本 AAB 时调用（干净克隆上自然跳过）',
  },
};

/**
 * **按需**工具（不是守卫，不该每次门禁都跑）。理由必须具体。
 */
const ON_DEMAND = {
  'tool/analytics-report.mjs': '看板报表：要真实的埋点数据才有意义',
  'tool/content-report.mjs': '内容报表：给"要不要加动作"做参考',
  'tool/usability-report.mjs': '可用性报告：要人做完测试、填了记录表才跑',
  'tool/copyright-export.mjs': '导出软著材料：只在要做提交材料时跑',
  'tool/add-upstream-exercises.mjs': '一次性补库脚本：往种子里加动作时才跑',
  'tool/map-upstream.mjs': '生成上游映射表：种子或快照变了才重跑',
  'tool/gen-feature-graphic.py': '生成特征图：素材变了才重跑（产物有 asset-check 守着）',
  'tool/gen-icons.py': '生成图标：品牌资源变了才重跑（产物有 asset-check 守着）',
};

function inspect(root) {
  const problems = [];
  const facts = [];
  const verify = readFileSync(join(root, 'verify.sh'), 'utf8');

  const guards = [];
  for (const f of readdirSync(join(root, 'tool'))) {
    if (/^(check-.*\.mjs)$/.test(f)) guards.push(`tool/${f}`);
  }
  for (const f of ['usability-selftest.mjs', 'mutation.mjs']) guards.push(`tool/${f}`);
  for (const f of readdirSync(join(root, 'server'))) {
    if (f.endsWith('.selftest.mjs')) guards.push(`server/${f}`);
  }
  for (const f of readdirSync(join(root, 'app/tool'))) {
    if (f.endsWith('.dart')) guards.push(`app/tool/${f}`);
  }

  // 直接跑的判据要分语言：`.mjs` 认 `node <路径>`；`.dart` 认 `<dart 或 $DART_BIN> <路径>`
  // （第一版只认 node，于是把 `app/tool/check_domain.dart` 误报成"从不跑" —— 它其实在第 3 层跑）
  //
  // ⚠️ 2026-10-01：门禁里那 14 段"跑某工具自检"的 if/else 抽成了一个 `selfcheck` 函数
  // （见 `verify.sh`），调用形式变成 `selfcheck tool/x.mjs "…" "…"` —— 于是
  // 这条判据**当场就把两个守卫报成"从不跑"**（它只认 `node <路径>`）。
  // 判据跟着扩展：`node <路径>` 与 `selfcheck <路径>` 都算"在门禁里直接跑"。
  const runsDirectly = (g) => {
    if (g.endsWith('.dart')) {
      return new RegExp(`(?:dart|DART_BIN"?)\\s+${g.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`).test(verify);
    }
    return verify.includes(`node ${g}`) || verify.includes(`selfcheck ${g}`);
  };

  for (const g of guards) {
    if (runsDirectly(g)) continue;                               // ① 直接跑
    if (DELEGATED[g]) {                                          // ② 代跑
      const { by, why } = DELEGATED[g];
      let delegator = '';
      try { delegator = readFileSync(join(root, by), 'utf8'); } catch { /* 缺文件 */ }
      if (!delegator.includes(g.split('/').pop())) {
        problems.push(`${g} 写着由 ${by} 代跑，但 ${by} 的源码里根本没提到它 —— `
          + '这条"代跑"关系是假的，守卫实际不会跑');
      } else {
        facts.push(`${g} ← ${by} 代跑（${why}）`);
      }
      continue;
    }
    if (ON_DEMAND[g]) continue;                                   // ③ 按需（有理由）
    problems.push(`${g} 既没在 verify.sh 里直接跑，也没写"由谁代跑"或"为什么按需" —— `
      + '不跑的守卫等于没有守卫，而它还会让人以为这块有人守着');
  }
  return { problems, facts, guards: guards.length };
}

// ───────────────────────────────────────────────────────────── 自检
function selftest() {
  const makeTree = (verify, tools, extra = {}) => {
    const root = mkdtempSync(join(tmpdir(), 'lianleme-wired-'));
    mkdirSync(join(root, 'tool'), { recursive: true });
    mkdirSync(join(root, 'server'), { recursive: true });
    mkdirSync(join(root, 'app/tool'), { recursive: true });
    // 夹具里也要有"另外两个固定会被扫到"的守卫，并把它们写进假的 verify.sh ——
    // 否则每条用例都会因为"它们没在跑"而红（假红），第一版就是这样
    writeFileSync(join(root, 'verify.sh'),
      `node tool/mutation.mjs\nnode tool/usability-selftest.mjs\n${verify}`);
    for (const t of tools) writeFileSync(join(root, t), '// x');
    writeFileSync(join(root, 'tool/mutation.mjs'), '// x');
    writeFileSync(join(root, 'tool/usability-selftest.mjs'), '// x');
    for (const [rel, body] of Object.entries(extra)) writeFileSync(join(root, rel), body);
    return root;
  };
  const cases = [
    ['直接跑的守卫 → 绿', 'node tool/check-a.mjs\n', ['tool/check-a.mjs'], true, null],
    // 门禁把"跑自检"抽成 selfcheck 之后，这条写法也必须算"在跑"（2026-10-01）
    ['用 selfcheck 跑的守卫 → 也算直接跑', 'selfcheck tool/check-a.mjs "过了" "红了"\n', ['tool/check-a.mjs'], true, null],
    ['存在但从不跑 → 必须报', 'echo hi\n', ['tool/check-a.mjs'], false, '不跑的守卫'],
    ['代跑关系成立 → 绿', 'node tool/delegator.mjs\n', ['tool/check-b.mjs', 'tool/delegator.mjs'],
      true, null],
    ['代跑关系是假的（代跑者没提它）→ 必须报', 'node tool/delegator.mjs\n',
      ['tool/check-b.mjs', 'tool/delegator.mjs'], false, null],
  ];
  // 把 check-b / delegator 写进名单与源码里模拟"代跑"
  const delegated = { 'tool/check-b.mjs': { by: 'tool/delegator.mjs', why: '测试用' } };
  let bad = 0;
  for (const [label, verify, tools, wantGreen, expect] of cases) {
    const root = makeTree(verify, tools, {
      'tool/delegator.mjs': label.includes('假') ? '// 没提别的工具' : '// 调用 check-b.mjs',
    });
    // 用局部的 DELEGATED 覆盖：临时把模块常量换成测试用（只在这条用例里）
    const saved = JSON.parse(JSON.stringify(DELEGATED));
    for (const k of Object.keys(DELEGATED)) delete DELEGATED[k];
    Object.assign(DELEGATED, delegated);
    const { problems } = inspect(root);
    for (const k of Object.keys(DELEGATED)) delete DELEGATED[k];
    Object.assign(DELEGATED, saved);
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
  console.log('\n✓ 自检通过：不跑的守卫、假的"代跑"关系都藏不住');
}

// ───────────────────────────────────────────────────────────────── 跑
if (process.argv.includes('--selftest')) {
  selftest();
} else {
  const rootArg = process.argv.find((a) => a.startsWith('--root='));
  const { problems, facts, guards } = inspect(rootArg ? rootArg.slice('--root='.length) : ROOT);
  console.log('守卫接线核对（有没有"存在但从不跑"的守卫）\n');
  console.log(`  共 ${guards} 个守卫/自检文件`);
  for (const f of facts) console.log(`  · ${f}`);
  if (problems.length) {
    console.log('');
    for (const p of problems) console.error(`  \x1b[31m✗\x1b[0m ${p}`);
    console.error(`\n✗ ${problems.length} 个守卫没在跑（且没写理由）`);
    process.exit(1);
  }
  console.log('\n✓ 每个守卫要么在门禁里直接跑，要么写明由谁代跑 / 为什么按需');
}
