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
 * 它核七件事：
 *   1. **CI 必须跑 `./verify.sh`**（不是把它的步骤抄一遍 —— 抄一遍就会漂，
 *      而且抄漏一层没人发现）；
 *   2. **不许 `--fast`**：那会跳过第 5 层 widget 测试，CI 就又变成"看着像门禁"的东西；
 *   3. **CI 里不许有别的东西**：除了 `./verify.sh` 本身，只允许"把失败行抬成注解"那一步
 *      （它不做任何检查，只是搬日志，且必须只碰那份日志）；加一条门禁不管的命令就红；
 *   4. **版本必须钉死**：`runs-on: ubuntu-24.04`（不是 `ubuntu-latest`）、
 *      `node-version: '22'`（`node:sqlite` 要 22.5+）、`flutter-version: '3.47.5'`；
 *   5. **绿必须是真的**：CI 里要有一道"账目"—— `verify.sh` 的约定是"环境导致的无法执行
 *      算**阻塞**、不计入失败"（开发机上是对的：环境坏了与测试失败是两件事），
 *      但在 CI 上这条约定会让"某一层根本没跑"也 exit 0 —— 那就是**无声的绿**。
 *      所以 CI 必须自己查一遍日志：六层的标记都在、**没有「⊘ 阻塞」**、并且写着"未发现失败"。
 *   6. **头部必须说清现在是等价关系**：要出现「CI 跑的就是门禁本身」这种说法，
 *      并且**不许**再出现过去那句"**子集**"的措辞（否则文档里的承诺又与被核的东西对不上），
 *      还必须在 `push` 与 `pull_request` 上都触发。
 *   7. **依赖 registry 必须与锁文件一致**（2026-11-05 补，一次真实事故）：pub 把
 *      registry 地址当成包身份的一部分，CI 的 `PUB_HOSTED_URL`（不设 = pub.dev）与
 *      `app/pubspec.lock` 里记的 `url:` 对不上时，**锁文件整份失效**、按 `^` 约束重新解析 ——
 *      2026-10-14 的 build_runner 2.16.2 事故就是这么来的（详见 workflow 头部注释）。
 *      所以：CI 显式声明的 registry 必须**等于**锁文件里那个。
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

/** 锁文件、以及 CI 不设 registry 时 pub 的默认值（第 7 条要核的两个值）。 */
const LOCK_REL = 'app/pubspec.lock';
const PUB_DEV = 'https://pub.dev';

/** 从锁文件里读 registry：hosted 依赖的 `url:`。读不到返回 null。 */
function lockRegistry(root) {
  let lock;
  try {
    lock = readFileSync(join(root, LOCK_REL), 'utf8');
  } catch {
    return null;
  }
  const m = /url:\s*"([^"]+)"/.exec(lock);
  return m ? m[1] : null;
}

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

  // ── 5. 绿必须是真的：要有一步"账目"挡住"被阻塞却 exit 0"
  if (!commands.some((c) => /lianleme-gate\.log/.test(c) && /阻塞/.test(c))) {
    problems.push('CI 里没有"账目"这一步 —— `verify.sh` 把"环境阻塞"当**不失败**'
      + '（开发机上是对的，CI 上意味着某一层没跑也可能绿）。'
      + '需要一步查日志：没有「⊘ 阻塞」才允许绿');
  }

  // ── 6. 头部说清等价关系，且不留过去那句"子集"
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
  // ── 7. 依赖 registry 必须与锁文件一致（2026-11-05，build_runner 2.16.2 事故之后补）
  //
  // pub 的 hosted 包身份 = (name, registry url)。CI 的 `PUB_HOSTED_URL` 与锁文件里的
  // `url:` 不一致时，锁文件里那些条目会被当成"另一个源"的包、整份失效 —— pub 会按
  // pubspec 的 `^` 约束重新解析最新版。2026-10-14 就是这样把锁着的 build_runner 2.16.1
  // 换成了 2.16.2（那一版本 Dart SDK 上编译不过），而 2026-11-04 重跑又绿。
  const lockUrl = lockRegistry(root);
  const envMatch = /^\s*PUB_HOSTED_URL:\s*(\S+)/m.exec(text);
  const ciRegistry = envMatch ? envMatch[1].replace(/^['"]|['"]$/g, '') : PUB_DEV;
  if (!lockUrl) {
    problems.push(`读不到 ${LOCK_REL} 里 hosted 依赖的 \`url:\` —— `
      + '没有它就无法判断 CI 用的 registry 是否与锁文件一致（锁文件是依赖版本唯一真源）');
  } else if (ciRegistry !== lockUrl) {
    problems.push(`CI 的依赖 registry 是 ${ciRegistry}，而 ${LOCK_REL} 记的是 ${lockUrl} —— `
      + 'pub 把 registry 当成包身份的一部分，两者不一致时**锁文件整份失效**、'
      + '依赖会按 `^` 约束重新解析（2026-10-14 的 build_runner 2.16.2 事故就是这么来的）。'
      + (envMatch
        ? '把 workflow 的 PUB_HOSTED_URL 改成锁文件里那个值。'
        : '在 workflow 的 job 里显式设 PUB_HOSTED_URL 为锁文件里那个值。'));
  } else {
    facts.push(`依赖 registry：CI ${ciRegistry} = ${LOCK_REL} ${lockUrl}`);
  }

  return { problems, facts };
}

// ───────────────────────────────────────────────────────────── 自检
function selftest() {
  const original = readFileSync(join(ROOT, CI_REL), 'utf8');
  /** 自检夹具：锁文件里记的 registry（与真仓库一致，见第 7 条）。 */
  const LOCK_MIRROR = 'packages:\n  build_runner:\n    description:\n      url: "https://pub.flutter-io.cn"\n';
  const LOCK_PUB_DEV = 'packages:\n  build_runner:\n    description:\n      url: "https://pub.dev"\n';
  const makeTree = (mutate, lockText = LOCK_MIRROR) => {
    const root = mkdtempSync(join(tmpdir(), 'lianleme-ci-'));
    const dir = join(root, '.github/workflows');
    mkdirSync(dir, { recursive: true });
    mkdirSync(join(root, 'app'), { recursive: true });
    writeFileSync(join(root, LOCK_REL), lockText);
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
    // 这一条是**无声的绿**：verify.sh 把"环境阻塞"当不失败（开发机上对），
    // CI 上少了这道账，某一层没跑也照样 exit 0 —— 而那正是这个仓库最怕的绿。
    ['账目那一步被删（被阻塞也可能绿）', (t) => {
      const i = t.indexOf('      - name: 门禁账目');
      const j = t.indexOf('      # 门禁红了要能');
      if (i < 0 || j < 0 || j < i) throw new Error('自检夹具失效：找不到账目那一步');
      return t.slice(0, i) + t.slice(j);
    }, false, '账目'],
    // 第 7 条（2026-11-05）：CI 与锁文件的 registry 必须是同一个
    ['CI 不声明 registry（回落 pub.dev，而锁文件是镜像）', (t) =>
      edit(t, '      PUB_HOSTED_URL: https://pub.flutter-io.cn\n', ''), false, 'registry'],
    ['CI 的 PUB_HOSTED_URL 抄错一个字符（与锁文件不一致）', (t) =>
      edit(t, 'PUB_HOSTED_URL: https://pub.flutter-io.cn', 'PUB_HOSTED_URL: https://pub.flutter-io.com'),
      false, 'registry'],
    ['锁文件换到 pub.dev，而 CI 还指着镜像', null, false, 'registry', LOCK_PUB_DEV],
    ['锁文件里读不出 registry（url: 没了）', null, false, '读不到', 'packages: {}\n'],
  ];

  let bad = 0;
  for (const [label, mutate, wantGreen, expect, lockText] of cases) {
    const root = makeTree(mutate, lockText);
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
    + '版本没钉住、registry 与锁文件不一致、头部说法与事实不符都藏不住');
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
  console.log('\n✓ CI 跑的就是门禁本身、没混进别的东西、版本与依赖 registry 都钉死、头部说法与事实一致');
}
