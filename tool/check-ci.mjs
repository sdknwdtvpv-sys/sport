#!/usr/bin/env node
/**
 * 练了么 · CI 与门禁的关系核对（`.github/workflows/ci.yml` ↔ `verify.sh`）
 *
 * **它为什么存在**：workflow 头部写着「这个 workflow 是 `./verify.sh` 的**子集**」，
 * `docs/your-todo.md` 与 `docs/release-checklist.md` 也各写了一遍。这三处都是**承诺**，
 * 而承诺会漂：CI 里加一条新命令（比如顺手加个 lint），"子集"这句话当场变成假的 ——
 * 更糟的是**本地门禁永远复现不了它**，CI 红了你却不知道为什么。
 * 反方向同样坏：CI 少了一步（比如哪天把 `dart analyze` 删了），头部那句"覆盖：…"就是空话。
 *
 * 它核四件事：
 *   1. **CI 不许跑门禁没跑的东西**：每条 `run:` 命令都要能对上一条门禁覆盖项
 *      （覆盖表写死在下面，带"门禁在哪一层跑的"）；
 *   2. **核心步骤不许少**：种子重建 / JS 向量 / Dart 领域校验 / drift 生成 /
 *      静态分析 / flutter test —— 少一条就红（因为头部那句"覆盖"点了它们；
 *      **注意 `dart tool/check_domain.dart` 与门禁里的 `app/tool/check_domain.dart`
 *      是同一个文件**，CI 的 working-directory 是 app/）；
 *   3. **版本必须钉死**：`runs-on: ubuntu-24.04`（不是 `ubuntu-latest`）、
 *      `node-version: '22'`（`node:sqlite` 要 22.5+）、`flutter-version: '3.47.5'`。
 *      这三条都是文档里写明的决定，漂了就是"CI 验证的不是我验证过的环境"；
 *   4. **"子集"这份说明必须点出没覆盖的东西**：头部要出现「子集」，并点到
 *      `run-scenarios` 与变异测试（第 6 层）—— 只说"子集"不说什么没覆盖，等于没说。
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

/** 门禁里覆盖得了的命令（CI 只许跑这些）。 */
const COVERED = [
  [/node seed\/build\.mjs/, '第 1 层：动作库种子重建'],
  [/git diff --quiet[^\n]*seed\/exercises\.json/, '第 1 层：生成物必须与提交一致（同一条守卫）'],
  [/node engine\/run-tests\.mjs/, '第 1 层：JS 规则引擎向量'],
  [/dart tool\/check_domain\.dart/, '第 3 层：Dart 领域校验（门禁跑的是 app/tool/check_domain.dart，同一个文件）'],
  [/flutter pub get/, '第 0 层：拉依赖'],
  [/dart run build_runner build/, '第 0 层：drift 代码生成'],
  [/dart analyze --fatal-infos/, '第 4 层：静态分析'],
  [/flutter test/, '第 5 层：widget / 单元测试'],
];

/** 头部那句"覆盖：…"点到的步骤：少一条就红。 */
const REQUIRED_STEPS = [
  [/node seed\/build\.mjs/, '种子重建'],
  [/node engine\/run-tests\.mjs/, 'JS 向量'],
  [/dart tool\/check_domain\.dart/, 'Dart 领域校验'],
  [/dart run build_runner build/, 'drift 代码生成'],
  [/dart analyze --fatal-infos/, '静态分析'],
  [/flutter test/, 'flutter test'],
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

  // ── 1. CI 只许跑门禁跑的东西
  const commands = extractRunCommands(text);
  for (const cmd of commands) {
    const covered = COVERED.find(([re]) => re.test(cmd));
    if (!covered) {
      problems.push(`CI 里有一条命令门禁不管：「${cmd.split('\n')[0].slice(0, 70)}」—— `
        + '「CI 是门禁子集」这句话当场变成假的，而且本地门禁复现不了它');
    }
  }
  facts.push(`CI 命令 ${commands.length} 条，全部落在门禁覆盖表内`);

  // ── 2. 核心步骤不许少
  for (const [re, label] of REQUIRED_STEPS) {
    if (!commands.some((c) => re.test(c))) {
      problems.push(`CI 少了「${label}」这一步 —— 而 workflow 头部的"覆盖：…"点了它`);
    }
  }

  // ── 3. 版本钉死
  for (const [good, bad, why] of PINS) {
    if (!good.test(text)) {
      problems.push(`${why}（现在是别的值或没写）—— CI 就会去验证一个你没验证过的环境`);
    } else if (bad.test(text)) {
      problems.push(`${why}（文件里同时还有没钉住的写法）`);
    }
  }

  // ── 4. "子集"这份说明必须点出没覆盖的东西
  const head = text.slice(0, text.indexOf('\non:'));
  if (!/子集/.test(head)) {
    problems.push('workflow 头部没写"这是门禁的子集"这句话 —— 读者会以为 CI 绿 = 门禁绿');
  }
  for (const [needle, why] of [['run-scenarios', '场景级 eval'], ['变异', '第 6 层变异测试']]) {
    if (!head.includes(needle)) {
      problems.push(`头部那份"没覆盖"的清单里没点到${why}（${needle}）—— `
        + '只说"子集"不说什么没覆盖，等于没说');
    }
  }
  if (!/on:\s*\n\s*push:/.test(text) || !/pull_request:/.test(text)) {
    problems.push('CI 没有在 push 与 pull_request 上都触发');
  }

  facts.push(`钉版本：ubuntu-24.04 · node 22 · flutter 3.47.5`);
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
    // 这条是"插入"，不是"替换"：锚点那句本来就该留着，所以不能用 edit 的"没换干净"断言
    ['CI 偷偷加了一条门禁不管的命令', (t) => {
      const anchor = '      - name: 单元测试 + widget 测试';
      if (!t.includes(anchor)) throw new Error('自检夹具失效：找不到锚点');
      return t.replace(anchor, `      - name: 顺手加个 lint\n        run: npm run lint\n\n${anchor}`);
    }, false, '门禁不管'],
    ['CI 少了静态分析这一步', (t) => edit(t, '      - name: 静态分析（dart analyze --fatal-infos）', '      - name: （这一步被删了）')
      .replace(/^.*dart analyze --fatal-infos.*$/m, ''), false, '少了「静态分析」'],
    ['flutter 版本没钉住', (t) => edit(t, "flutter-version: '3.47.5'", 'channel: stable'), false, 'flutter-version 必须钉在'],
    ['runs-on 换成 ubuntu-latest', (t) => edit(t, 'runs-on: ubuntu-24.04', 'runs-on: ubuntu-latest'), false, 'runs-on 必须是 ubuntu-24.04'],
    ['node 版本降到 18', (t) => edit(t, "node-version: '22'", "node-version: '18'"), false, 'node-version 必须钉在'],
    ['头部不再说"子集"', (t) => edit(t, '**子集**', '的一部分'), false, '没写"这是门禁的子集"'],
    ['头部不再点出"没覆盖变异测试"', (t) => edit(t, '以及第 6 层的**变异测试**', '以及一些别的检查'), false, '没点到第 6 层变异测试'],
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
  console.log('\n✓ 自检通过：CI 偷跑门禁不管的命令、少了核心步骤、版本没钉住、'
    + '头部不再说"子集"都藏不住');
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
    console.error(`\n✗ ${problems.length} 处不对 —— "CI 是门禁子集"是写在三处文档里的承诺`);
    process.exit(1);
  }
  console.log('\n✓ CI 只跑门禁覆盖得了的东西、核心步骤没少、版本钉死、'
    + '"子集"那句话点明了没覆盖什么');
}
