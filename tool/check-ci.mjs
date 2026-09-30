#!/usr/bin/env node
/**
 * 练了么 · CI 与门禁的关系核对（`.github/workflows/ci.yml` ↔ `verify.sh`）
 *
 * **它为什么存在**：2026-09-30 之前，workflow 头部写着「这个 workflow 是 `./verify.sh` 的
 * **子集**」，`docs/your-todo.md` 与 `README.md` 也各写了一遍。那是**承诺**，而承诺会漂：
 * CI 里加一条门禁不管的命令（比如顺手加个 lint），"子集"那句话当场变成假的 —— 更糟的是
 * **本地门禁永远复现不了它**，CI 红了你却不知道为什么。
 *
 * 2026-09-30 用户拍板："CI 直接跑 `./verify.sh`"。于是关系变了，守卫跟着变：
 * 现在**不是**核"CI 是不是子集"，而是核"**CI 跑的是不是门禁本身**"。
 *
 * 它核五件事：
 *   1. **CI 必须跑 `./verify.sh`**（不是把它的步骤抄一遍 —— 抄一遍就会漂，
 *      而且抄漏一层没人发现）；
 *   2. **不许 `--fast`**：那会跳过第 5 层 widget 测试，CI 就又变成"看着像门禁"的东西；
 *   3. **CI 里不许有别的东西**：除了 `./verify.sh` 本身，只允许"把失败行抬成注解"那一步
 *      （它不做任何检查，只是搬日志，且必须只碰那份日志）；加一条门禁不管的命令就红；
 *   4. **版本必须钉死**：`runs-on: ubuntu-24.04`（不是 `ubuntu-latest`）、
 *      `node-version: '22'`（`node:sqlite` 要 22.5+）、`flutter-version: '3.47.5'`；
 *   5. **头部必须说清现在是等价关系**：要出现「CI 跑的就是门禁本身」这种说法，
 *      并且**不许**再出现过去那句"**子集**"的措辞（否则文档里的承诺又与被核的东西对不上），
 *      还必须在 `push` 与 `pull_request` 上都触发。
 *
 * 用法：
 *   node tool/check-ci.mjs              # 核仓库里的 workflow
 *   node tool/check-ci.mjs --selftest   # 自检（造几份动过手脚的，验它抓得住）
 *
 * 退出码：任何一项不符 → 1。
 */

import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const CI_REL = '.github/workflows/ci.yml';

/** 门禁本身那条命令。CI 必须跑它，且只跑它。 */
const GATE_CMD = /\.\/verify\.sh/;

/**
 * 允许出现在 CI 里的、**不做检查**的辅助步骤。
 * 名单要写理由 —— 允许"搬日志"是因为 GitHub 的 job 日志要凭据才读得到，
 * 而注解匿名可读：门禁红在哪儿必须能被人看见。它不许调用任何测试工具。
 */
const ALLOWED_HELPERS = [
  {
    re: /lianleme-gate\.log/,
    why: '把门禁的失败行抬成注解（只 sed/grep 那份日志，不做任何检查）',
  },
];

/** 文档里写明"必须钉住"的三样。 */
const PINS = [
  [/runs-on:\s*ubuntu-24\.04/, /runs-on:\s*ubuntu-latest/, 'runs-on 必须是 ubuntu-24.04'],
  [/node-version:\s*'22'/, /node-version:\s*'(?!22')/, "node-version 必须钉在 '22'（node:sqlite 要 22.5+）"],
  [/flutter-version:\s*'3\.47\.5'/, /flutter-version:\s*'(?!3\.47\.5')/, "flutter-version 必须钉在 '3.47.5'"],
];

/** 把 workflow 里所有 `run:` 的命令抽出来（含 `run: |` 的多行块）。 */
function extractRunCommands(text) {
  const lines = text.split('\n');
  const out = [];
  for (let i = 0; i < lines.length; i += 1) {
    const m = /^\s*(?:-\s*)?run:\s*(.*)$/.exec(lines[i]);
    if (!m) continue;
    // ⚠️ `defaults:\n  run:\n    working-directory: app` 里也有一个 `run:`，
    // 它是 YAML 结构而不是命令 —— 值里什么都没有，按这个把它区别出来。
    if (m[1].trim() === '') continue;
    if (m[1] === '|' || m[1] === '>' || m[1] === '|-' || m[1] === '>-') {
      const indent = lines[i].search(/\S/);
      const block = [];
      for (let j = i + 1; j < lines.length; j += 1) {
        const l = lines[j];
        if (l.trim() === '') { block.push(''); continue; }
        if (l.search(/\S/) <= indent) break;
        block.push(l.trim());
      }
      out.push(block.join('\n'));
    } else {
      out.push(m[1].trim());
    }
  }
  return out;
}

function inspect(root) {
  const problems = [];
  const facts = [];
  const ciPath = join(root, CI_REL);
  let text;
  try {
    text = readFileSync(ciPath, 'utf8');
  } catch {
    return { problems: [`找不到 ${CI_REL} —— 这条检查的对象没了`], facts };
  }

  const commands = extractRunCommands(text);
  const gateRuns = commands.filter((c) => GATE_CMD.test(c));

  // ── 1. CI 必须跑门禁本身
  if (!gateRuns.length) {
    problems.push(`${CI_REL} 里没有跑 \`./verify.sh\` —— 那"CI 绿 = 门禁绿"就不成立了`
      + '（把门禁的步骤抄一遍不算：抄漏一层没人会发现）');
  }
  // ── 2. 不许 --fast（跳过第 5 层）
  for (const c of gateRuns) {
    if (/--fast/.test(c)) {
      problems.push('CI 用 `./verify.sh --fast` 跑 —— 那会跳过第 5 层 widget 测试，'
        + 'CI 就又变成"看着像门禁"的东西了');
    }
  }

  // ── 3. 除了门禁本身，不许有别的东西（辅助步骤按名单放行，名单里逐条写了理由）
  for (const cmd of commands) {
    if (GATE_CMD.test(cmd)) continue;
    if (ALLOWED_HELPERS.some((h) => h.re.test(cmd))) continue;
    problems.push(`CI 里有一条命令门禁不管：「${cmd.split('\n')[0].slice(0, 70)}」—— `
      + 'CI 跑的东西必须就是门禁跑的东西，否则本地门禁复现不了它');
  }
  facts.push(`CI 里的 run 命令 ${commands.length} 条：门禁 ${gateRuns.length} 条`
    + `${commands.length > 1 ? ` + ${commands.length - 1} 条搬日志的辅助步骤` : ''}`);

  // ── 4. 版本钉死
  for (const [good, bad, why] of PINS) {
    if (!good.test(text)) {
      problems.push(`${why}（现在是别的值或没写）—— CI 就会去验证一个你没验证过的环境`);
    } else if (bad.test(text)) {
      problems.push(`${why}（文件里同时还有没钉住的写法）`);
    }
  }
  facts.push('钉版本：ubuntu-24.04 · node 22 · flutter 3.47.5');

  // ── 5. 头部说清等价关系，且不留过去那句"子集"
  const head = text.slice(0, text.indexOf('\non:'));
  if (!/CI 跑的就是门禁本身/.test(head)) {
    problems.push('workflow 头部没写"CI 跑的就是门禁本身"—— 读者不知道 CI 绿是不是等于门禁绿');
  }
  if (/\*\*子集\*\*/.test(head)) {
    problems.push('workflow 头部还留着「**子集**」那句旧说法 —— '
      + '现在 CI 跑的就是门禁本身，两种说法不能同时挂着');
  }
  if (!/on:\s*\n\s*push:/.test(text) || !/pull_request:/.test(text)) {
    problems.push('CI 没有在 push 与 pull_request 上都触发');
  }
  return { problems, facts };
}

// ───────────────────────────────────────────────────────────── 自检
function selftest() {
  const original = readFileSync(join(ROOT, CI_REL), 'utf8');
  const makeTree = (mutate) => {
    const root = mkdtempSync(join(tmpdir(), 'lianleme-ci-'));
    const dir = join(root, '.github/workflows');
    mkdirSync(dir, { recursive: true });
    let text = original;
    if (mutate) text = mutate(text);
    writeFileSync(join(dir, 'ci.yml'), text);
    return root;
  };
  const edit = (text, from, to) => {
    if (!text.includes(from)) throw new Error(`自检夹具失效：ci.yml 里没有 ${from}`);
    const out = text.split(from).join(to);
    if (out.includes(from)) throw new Error(`自检夹具没换干净：还剩 ${from}`);
    return out;
  };

  const cases = [
    ['好的 workflow：全绿', null, true, null],
    ['CI 改成 --fast（想省掉第 5 层）', (t) => edit(t, './verify.sh 2>&1', './verify.sh --fast 2>&1'),
      false, '--fast'],
    ['CI 不再跑 verify.sh，改成抄一层 flutter test', (t) => edit(t, './verify.sh 2>&1 | tee /tmp/lianleme-gate.log',
      'flutter test 2>&1 | tee /tmp/lianleme-gate.log'), false, '没有跑 `./verify.sh`'],
    ['CI 偷偷加了一条门禁不管的命令', (t) => {
      const anchor = '      - name: 门禁（./verify.sh 六层全跑）';
      if (!t.includes(anchor)) throw new Error('自检夹具失效：找不到锚点');
      return t.replace(anchor, `      - name: 顺手加个 lint\n        run: npm run lint\n\n${anchor}`);
    }, false, '门禁不管'],
    ['搬日志那一步被换成了真的跑测试', (t) => edit(t,
      "sed 's/\\x1b\\[[0-9;]*m//g' /tmp/lianleme-gate.log", 'flutter test'),
      false, '门禁不管'],
    ['flutter 版本没钉住', (t) => edit(t, "flutter-version: '3.47.5'", 'channel: stable'),
      false, 'flutter-version 必须钉在'],
    ['runs-on 换成 ubuntu-latest', (t) => edit(t, 'runs-on: ubuntu-24.04', 'runs-on: ubuntu-latest'),
      false, 'runs-on 必须是 ubuntu-24.04'],
    ['node 版本降到 18', (t) => edit(t, "node-version: '22'", "node-version: '18'"),
      false, 'node-version 必须钉在'],
    ['头部不再说"CI 跑的就是门禁本身"', (t) => edit(t, 'CI 跑的就是门禁本身', '这个 workflow 会跑一些检查'),
      false, '没写"CI 跑的就是门禁本身"'],
    ['头部又挂上了旧的"子集"说法', (t) => edit(t,
      '# 复查时间：2027-01，或收到 GitHub 弃用公告时。',
      '# 这个 workflow 是 **子集**，不是门禁本身。'), false, '还留着「**子集**」'],
    ['pull_request 触发被删', (t) => edit(t, '  pull_request:\n', ''), false, 'push 与 pull_request'],
  ];

  let bad = 0;
  for (const [label, mutate, wantGreen, expect] of cases) {
    const root = makeTree(mutate);
    const { problems } = inspect(root);
    const green = problems.length === 0;
    let ok = green === wantGreen;
    let why = green ? '' : `　→ ${problems[0].slice(0, 64)}`;
    if (ok && !wantGreen && expect && !problems.some((p) => p.includes(expect))) {
      ok = false;
      why = `　→ 红了，但不是因为「${expect}」（红在：${problems[0].slice(0, 46)}）`;
    }
    if (!ok) bad += 1;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}${why}`);
    rmSync(root, { recursive: true, force: true });
  }
  if (bad) {
    console.error(`\n✗ 自检失败 ${bad} 项 —— 这个工具本身不可信，先修它`);
    process.exit(1);
  }
  console.log('\n✓ 自检通过：CI 不跑门禁、用 --fast 偷跳、混进别的命令、'
    + '版本没钉住、头部说法与事实不符都藏不住');
}

// ───────────────────────────────────────────────────────────────── 跑
if (process.argv.includes('--selftest')) {
  selftest();
} else {
  const rootArg = process.argv.find((a) => a.startsWith('--root='));
  const { problems, facts } = inspect(rootArg ? rootArg.slice('--root='.length) : ROOT);
  console.log('CI ↔ 门禁关系核对\n');
  for (const f of facts) console.log(`  ${f}`);
  if (problems.length) {
    console.log('');
    for (const p of problems) console.error(`  \x1b[31m✗\x1b[0m ${p}`);
    console.error('\n✗ CI 与门禁的关系不对 —— "CI 绿 = 门禁绿"是写在 README 与政策里的承诺');
    process.exit(1);
  }
  console.log('\n✓ CI 跑的就是门禁本身、没混进别的东西、版本钉死、头部说法与事实一致');
}
