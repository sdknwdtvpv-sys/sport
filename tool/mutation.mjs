#!/usr/bin/env node
/**
 * 练了么 · 变异测试（mutation smoke）
 *
 * **它回答的问题**：我们那 455 条测试，到底真的在守着行为，还是只是在自我安慰？
 *
 * 这个问题不是假想的。那份只读分析里最重的一句指控就是：
 * *"209 项测试全绿，而核心引擎从未在真实路径上运行过"* ——
 * 测试证明了引擎是对的，而生产代码根本没调引擎。**测试数量从来不等于测试有效性。**
 *
 * 它同时守两套检查：`engine/run-tests.mjs`（向量 = 单步正确性）与
 * `engine/run-scenarios.mjs`（场景 eval = 序列级产品红线）。清单里带
 * `runner: 'scenarios'` 的变异体是"只有场景 eval 抓得住"的那类 ——
 * 那是场景 eval 存在的证明，否则它只是个永远通过的装饰。
 *
 * 做法（借自参考项目 healthy-fitness-coach 的 `quality-tests/run-mutation-smoke.js`）：
 * 把源码**故意改坏**，再跑既有测试；测试红了 = 这个变异被"杀死"，
 * 测试还是绿的 = **盲区**（survived）。**盲区才是这个工具真正的产出。**
 *
 * 三条刻意的设计：
 *   1. **在临时目录里跑**（只拷领域层需要的 7 个文件，不碰工作区）。
 *      变异测试会改源码；若改的是真源码，一次崩溃就会把仓库留在坏状态。
 *   2. **编译不过的变异体不算杀死**。`from`/`to` 写错会变成语法错误，
 *      那种"失败"证明不了任何事，单独标成 INVALID。
 *   3. **每个变异体显式写出两种语言的原文**，不做"一套写法自动翻译成两种语言" ——
 *      翻译规则本身会变成 bug 来源（第一版就这么写的，写错了两条）。
 *
 * 用法：
 *   node tool/mutation.mjs            # 两套引擎都跑
 *   node tool/mutation.mjs --dart     # 只跑 Dart 引擎（check_domain.dart）
 *   node tool/mutation.mjs --js       # 只跑 JS 引擎（run-tests.mjs）
 *   node tool/mutation.mjs -v         # 存活时打印失败输出尾部
 *
 * 退出码：有存活或无效 → 1（盲区不能被当成没看见）
 *
 * **这个工具看不见什么**（写明边界，免得被当成"全覆盖"）：
 *   暂存区只拷 `app/lib` + `app/tool` + `engine`，Dart 侧跑的是零依赖的
 *   `check_domain.dart` —— 所以**需要 drift / flutter_test 的数据层变异体进不来**。
 *   典型的一条：`exercise_repository.dart` 里 `importSeed` 的
 *   `insertOnConflictUpdate(...)` 换成 `insert(..., onConflict: DoNothing())`
 *   （冲突项原样不动），条数照样对、引擎也不受影响，
 *   但**已装 App 的人永远拿不到新写的动作说明**。它由
 *   `app/test/exercise_repository_test.dart` 的「老库冷启动也会拿到新写的说明」守着
 *   （2026-09-30 验证过：换掉那一行，只有这条测试红，旧的幂等测试照绿）。
 *   要把它并进来，得让 runner 支持 `flutter test` + 整个 app 工程 —— 那是另一件事。
 */

import { spawnSync } from 'node:child_process';
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const argv = process.argv.slice(2);
const only = argv.includes('--dart') ? 'dart' : argv.includes('--js') ? 'js' : null;
const verbose = argv.includes('-v') || argv.includes('--verbose');

// ---------------------------------------------------------------- 工具链定位
//
// 不假设 PATH：本机 flutter/dart 在 ~/development/flutter，harness 的 node 也不在 PATH 里。
// 找不到就明确"跳过"，不假装通过。

function resolveDart() {
  const candidates = [
    process.env.DART,
    join(process.env.HOME ?? '', 'development/flutter/bin/cache/dart-sdk/bin/dart'),
    join(process.env.HOME ?? '', 'development/flutter/bin/dart'),
    '/usr/local/bin/dart',
    '/opt/homebrew/bin/dart',
  ].filter(Boolean);
  for (const c of candidates) {
    if (spawnSync(c, ['--version'], { encoding: 'utf8' }).status === 0) return c;
  }
  return spawnSync('dart', ['--version'], { encoding: 'utf8' }).status === 0 ? 'dart' : null;
}

const DART = resolveDart();
const NODE = process.execPath;

const PROG_DART = 'app/lib/domain/progression.dart';
const PROG_JS = 'engine/progression.mjs';
const TAP_DART = 'app/lib/domain/tap_meter.dart';

// ---------------------------------------------------------------- 变异清单
//
// 每条都对应**一类真实会犯的错**，而不是随手改个数字。
// 前几条刻意对准这份分析报告点名过的缺陷类型。

const MUTANTS = [
  {
    name: '删掉按时长分支（平板支撑退回按次数推进）',
    why: '这一支就是"平板支撑被开成 3 组 × 8 次"的修复本体',
    js: { file: PROG_JS, from: 'if (isTime) {', to: 'if (false) {' },
    dart: { file: PROG_DART, from: 'if (isTime) {', to: 'if (false) {' },
  },
  {
    name: '按时长步长 5 秒 → 10 秒',
    why: '推进幅度是最容易被顺手改掉的一处',
    js: { file: PROG_JS, from: 'TIME_STEP_SEC = 5', to: 'TIME_STEP_SEC = 10' },
    dart: { file: PROG_DART, from: 'kTimeStepSec = 5', to: 'kTimeStepSec = 10' },
  },
  {
    name: '按时长上限 +15 秒 → +5 秒',
    why: '它决定"什么时候不再加秒、改成加负重"，边界最容易漏测',
    js: { file: PROG_JS, from: 'TIME_CAP_BONUS = 15', to: 'TIME_CAP_BONUS = 5' },
    dart: { file: PROG_DART, from: 'kTimeCapBonus = 15', to: 'kTimeCapBonus = 5' },
  },
  {
    name: '自重分支整体失效（硬红线 2：自重不许返回重量）',
    why: '三条硬红线之一，测试里有强制断言 —— 该杀不死才算新闻',
    // 两处 `if (isBodyweight)`：自重主分支 + 时长分支里那个"到上限了怎么办"的内层判断。
    // 一起改掉更彻底（自重动作会掉进负重路径，必然违反硬红线 2）。
    js: { file: PROG_JS, from: 'if (isBodyweight) {', to: 'if (false) {', all: true },
    dart: { file: PROG_DART, from: 'if (isBodyweight) {', to: 'if (false) {', all: true },
  },
  {
    name: '21 天回归保护整支失效',
    why: '这条分支曾经因为 daysAgo 恒为 0 而从未生效；现在必须被测试守住',
    js: { file: PROG_JS, from: 'if (days >= STALE_DAYS) {', to: 'if (false) {' },
    dart: { file: PROG_DART, from: 'if (days >= kStaleDays) {', to: 'if (false) {' },
  },
  {
    name: '回归保护差一天（>= 21 → > 21）',
    why: '经典差一天错误，且它决定"第 21 天算不算过期"',
    js: { file: PROG_JS, from: 'days >= STALE_DAYS', to: 'days > STALE_DAYS' },
    dart: { file: PROG_DART, from: 'days >= kStaleDays', to: 'days > kStaleDays' },
  },
  {
    name: '自重次数上限 +5 → +1',
    why: '"到上限后改成建议加负重"的门槛',
    js: { file: PROG_JS, from: 'BODYWEIGHT_REP_CAP_BONUS = 5', to: 'BODYWEIGHT_REP_CAP_BONUS = 1' },
    dart: { file: PROG_DART, from: 'kBodyweightRepCapBonus = 5', to: 'kBodyweightRepCapBonus = 1' },
  },
  {
    name: '组数没做满的判定差一（< sets → <= sets）',
    why: '"先把组数补满"的入口条件，差一就会把做满的那次也判成没满',
    js: { file: PROG_JS, from: 'if (completed < sets) {', to: 'if (completed <= sets) {', all: true },
    dart: { file: PROG_DART, from: 'if (completed < sets) {', to: 'if (completed <= sets) {', all: true },
  },
  {
    name: '达标加重时不加步长（原地踏步）',
    why: '双重渐进的另一半：全部达标却不加重',
    js: { file: PROG_JS, from: 'lastW + inc', to: 'lastW', all: true },
    dart: { file: PROG_DART, from: 'lastW + inc', to: 'lastW', all: true },
  },
  {
    // 等价变异体：**留在清单里是有意的**，不是漏删。
    // 实测 0.1–400 kg、步长 2 / 2.5 / 5 的整个范围内，单次加法都正确舍入 ——
    // 也就是说这个变异体在现实输入下**语义等价**，没有任何测试能（也应当）杀死它。
    // 把知识记在这儿，比删掉它更好：下一个人会问"round2 为什么没有变异覆盖"。
    // （round2 真正非它不可的地方是 estimate1RM 的除法。）
    name: '去掉重量加法的浮点噪声消除（等价变异体，见注释）',
    why: '现实输入下语义等价：没有可泄漏的加法',
    equivalent: true,
    js: { file: PROG_JS, from: 'round2(lastW + inc)', to: '(lastW + inc)', all: true },
    dart: { file: PROG_DART, from: '_round2(lastW + inc)', to: '(lastW + inc)', all: true },
  },
  {
    name: '辅助自重的助力方向反了（达标 → 加助力 = 越练越轻松）',
    why: '这正是 2026-09-29 修掉的那个反向 bug：辅助引体走"负重"分支时，"达标 → +5kg" '
      + '意味着给你更多助力。六个 assisted 向量 + 一条不变量（只减不增）共同守它',
    js: { file: PROG_JS, from: 'const next = round2(lastW - inc);', to: 'const next = round2(lastW + inc);' },
    dart: { file: PROG_DART, from: 'final double next = _round2(lastW - inc);', to: 'final double next = _round2(lastW + inc);' },
  },
  // ---- 只有场景 eval 抓得住的一类：文案红线 ----
  //
  // 向量只校验文案里的**子串**（`text_includes`），查不出"一行放得下"、
  // 也查不出"有没有把内部状态泄漏给用户"。这两条是产品红线，只有序列级的
  // 场景 eval 在守。这条变异体就是那条红线的**存在性证明** ——
  // 没有它，场景 eval 只是一个永远通过的装饰。
  {
    name: '回归保护的文案写到一行放不下（向量查不出来）',
    why: '向量只查子串；「理由必须一行放得下」是产品红线，只有场景 eval 守得住',
    runner: 'scenarios',
    js: {
      file: PROG_JS,
      // JS 那边是**反引号模板串**（第一版写成单引号，变异点没找到 → INVALID）。
      // 这正是 INVALID 这一类的用处：它把"我写错了锚点"和"测试真的没抓到"分开了。
      from: '`已经有 ${days} 天没练这个动作，先按上次重量找回感觉`',
      to: '`已经有 ${days} 天没练这个动作了，别急着加重，先按上次的重量找回感觉'
        + ' —— 这属于回归保护，三周以上的数据不足以支撑加重`',
    },
  },

  {
    name: 'tap 计数 +1 → +2（唯一的发布闸门算错）',
    why: 'tap_count 算错，发版闸门就失效',
    dart: { file: TAP_DART, from: '_count++;', to: '_count += 2;' },
  },
  {
    name: 'ensure() 不再接住已有周期（控制器构造时清零导航点击）',
    why: '端到端口径的关键：清零了第一组就退回"只算大按钮"的窄口径',
    dart: { file: TAP_DART, from: 'if (_active) return;', to: 'if (false) return;' },
  },
  {
    name: 'flush() 之后周期仍然开着（周期外的点击被计入）',
    why: '"点完立刻再点一次"必须各自算 1 次',
    // ⚠️ 必须带上前面两行才有唯一性：单写 `_active = false;` 会命中**字段声明**
    // （`bool _active = false;`），那是个空变异 —— 第一版就撞上了这个坑。
    dart: {
      file: TAP_DART,
      from: '_count = 0;\n    _kinds.clear();\n    _active = false;',
      to: '_count = 0;\n    _kinds.clear();\n    _active = true;',
    },
  },
];

// ---------------------------------------------------------------- 暂存区
//
// `app/tool/check_domain.dart` 是零依赖纯 Dart，所以只拷这几只 ——
// 仓库里 2.2G 的 build/ 与 446M 的 .dart_tool 都不需要。

// **整个 app/lib 都要拷**，不能只拷"看起来需要的"那几个文件。
// 第一版手工列了 7 个，结果 models.dart 引用的 core/units.dart 没进去，
// 于是**每个 Dart 变异体都变成"编译失败"**，被误当成"测试杀死了它" ——
// 一次跑出 100% 的假成绩。（留这段注释是有意的：暂存区不全 = 变异测试在说谎。）
//
// 仓库里 2.2G 的 build/ 与 446M 的 .dart_tool 仍然不需要。

const COPY_DIRS = ['app/lib', 'app/tool', 'engine'];

const staged = mkdtempSync(join(tmpdir(), 'lianleme-mutants-'));
for (const d of COPY_DIRS) {
  cpSync(join(ROOT, d), join(staged, d), { recursive: true });
}

// ---------------------------------------------------------------- 跑

const results = [];
let killed = 0, survived = 0, invalid = 0, equivalent = 0, skipped = 0;

for (const m of MUTANTS) {
  for (const lang of ['js', 'dart']) {
    const spec = m[lang];
    if (!spec) continue;
    if (only && only !== lang) continue;
    if (lang === 'dart' && !DART) { skipped++; continue; }

    const abs = join(staged, spec.file);
    const original = readFileSync(abs, 'utf8');
    // 唯一性守卫：不唯一的变异点等于在改一处**没被测试覆盖的地方**，
    // 跑出来是"存活"，但结论完全错 —— 必须标成无效（第一版把一个字段声明
    // 当成了 flush() 里的赋值，白跑一轮）。
    const hits = original.split(spec.from).length - 1;
    if (hits === 0) {
      results.push({ name: m.name, lang, verdict: 'INVALID', detail: `变异点没找到：${spec.from.slice(0, 40)}` });
      invalid++;
      continue;
    }
    if (hits > 1 && !spec.all) {
      results.push({ name: m.name, lang, verdict: 'INVALID', detail: `变异点不唯一（${hits} 处），要么写得更具体，要么显式 all:true` });
      invalid++;
      continue;
    }

    const mutated = spec.all
      ? original.split(spec.from).join(spec.to)
      : original.replace(spec.from, spec.to);

    writeFileSync(abs, mutated, 'utf8');
    // 两套检查：向量（单步正确性）与场景 eval（序列级产品红线）。
    // 后者只跑在 JS 参考实现上，所以这类变异体只声明 js。
    const r = m.runner === 'scenarios'
      ? spawnSync(NODE, ['engine/run-scenarios.mjs'], { cwd: staged, encoding: 'utf8' })
      : lang === 'dart'
        ? spawnSync(DART, ['app/tool/check_domain.dart'], { cwd: staged, encoding: 'utf8' })
        : spawnSync(NODE, ['engine/run-tests.mjs'], { cwd: staged, encoding: 'utf8' });
    const out = `${r.stdout ?? ''}${r.stderr ?? ''}`;
    writeFileSync(abs, original, 'utf8');

    // 编译不过 ≠ 被杀：那证明不了任何事
    // ⚠️ Dart 的诊断格式是 `path.dart:行:列: Error: ...`（位置在前）。
    // 第一版按 `Error: ... .dart:行` 写，**一条都没匹配上** —— 见上面暂存区那段注释：
    // 结果是"编译失败"被算成了"被测试杀死"。
    const compileBroken =
      /\.dart:\d+:\d+:\s*(Error|Warning)|SyntaxError|Cannot find name|isn't defined|isn't a type/.test(out);
    const verdict = compileBroken
      ? 'INVALID'
      : r.status !== 0
        ? 'KILLED'
        : m.equivalent
          ? 'EQUIVALENT' // 语义等价：活着是对的，见清单里的注释
          : 'SURVIVED';

    results.push({
      name: m.name, lang, verdict, why: m.why,
      via: m.runner === 'scenarios' ? '场景' : '向量',
      tail: out.trim().split('\n').filter(Boolean).slice(-2).join(' | '),
    });
    if (verdict === 'KILLED') killed++;
    else if (verdict === 'SURVIVED') survived++;
    else if (verdict === 'EQUIVALENT') equivalent++;
    else invalid++;
  }
}

rmSync(staged, { recursive: true, force: true });

// ---------------------------------------------------------------- 报告

const mark = { KILLED: '✓ 杀死', SURVIVED: '✗ 存活', INVALID: '? 无效', EQUIVALENT: '= 等价' };
console.log('练了么 · 变异测试（把源码改坏，看既有测试红不红）\n');
for (const r of results) {
  console.log(`${r.lang.padEnd(4)} ${mark[r.verdict].padEnd(10)} ${r.name}`
    + (r.via === '场景' ? '  ← 只有场景 eval 抓得住' : ''));
  if (r.verdict !== 'KILLED') {
    console.log(`       ${r.detail ?? r.why}`);
    if (verbose && r.tail) console.log(`       输出：${r.tail}`);
  }
}
if (skipped) console.log(`\n⊘ 跳过 ${skipped} 个（找不到 dart；装好工具链或用 --js 单独跑）`);

// 得分只按"可被杀死的"算：等价变异体既不该算进分子，也不该算进分母
const scorable = killed + survived;
console.log(`\n${'─'.repeat(74)}`);
console.log(`杀死 ${killed} / 存活 ${survived} / 等价 ${equivalent} / 无效 ${invalid}　`
  + `→　变异得分 ${scorable ? Math.round((killed / scorable) * 100) : 0}%`);
if (survived) {
  console.log('\n存活 = 测试盲区：源码被改坏了，却没有任何测试变红。');
  console.log('处理方式只有一种 —— 补一条能抓住它的测试，不要改这个数字。');
}
if (invalid) console.log('\n无效 = 变异点没找到或编译不过，要修的是变异清单本身。');
if (survived || invalid) process.exitCode = 1;
