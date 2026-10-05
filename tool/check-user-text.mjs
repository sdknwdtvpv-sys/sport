#!/usr/bin/env node
/**
 * 练了么 · 用户可见文案核对（`app/lib` 里会不会漏出"给我们自己看"的东西）
 *
 * **它为什么存在**：这个项目为此付过三次学费，每次都是**眼睛**先看见的：
 *   1. 体重单独同意那个弹层里写着 `单独征得你同意` 的正文却夹了 `**`（markdown 记号）——
 *      真机截图时才发现，用户会直接看到星号；
 *   2. 政策里那句「（上架时替换为实际日期）」——给我们的待办，跟着随包资产发出去；
 *   3. 收集清单开头「本页由仓库自动生成…请勿手改」——同样是给我们的话，用户与审核员都会读；
 *   4. 云备份那几个弹层里还有 6 处 `**`（2026-09-30 用 grep 扫出来，此前一直没人看见，
 *      因为它们只在"配了服务器地址"的包里出现）。
 *
 * `Text` **不渲染 markdown** —— `**` 不是加粗，是三个星号印在屏幕上。这类问题单测看不见字形，
 * 截图也未必翻到那一屏，所以只能靠**扫源码里的字符串字面量**这一条机械规则。
 *
 * 它核两件事：
 *   1. **用户可见的字符串里不许有 `**`**（markdown 记号）；
 *   2. **不许出现"给我们自己看"的记号**（仓库/生成物/请勿手改/TODO/FIXME/待填/占位…）。
 *
 * 判据的边界（写明白，免得被当成全覆盖）：
 *   * 只看 `app/lib/**\/*.dart`，**跳过注释**（`//`、`///`、块注释行首的 `*`）——
 *     注释里写 markdown 是我们的自由；
 *   * 不解析 Dart 语法，只按"这一行去掉注释后还有没有那些记号"判断，所以它**保守**：
 *     宁可偶尔漏，也不要把注释误报成文案（假阳性会让人把守卫关掉）；
 *   * 资产（`app/assets/*.txt`）走的是另一条：`tool/privacy-audit.mjs` 扫生成物，
 *     `app/test/*_test.dart` 各守一份。
 *
 * 用法：
 *   node tool/check-user-text.mjs              # 扫 app/lib
 *   node tool/check-user-text.mjs --selftest   # 自检（造几个假的 .dart，验它抓得住）
 *
 * 退出码：发现任何一处 → 1。
 */

import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** 用户可见字符串里不许出现的记号。每一条都对应一次真发生过的漏字。 */
const BAD = [
  ['**', 'markdown 记号：`Text` 不渲染 markdown，用户会看到星号'],
  ['由仓库自动生成', '这是给我们自己的说明，用户会读到'],
  ['生成物', '同上'],
  ['请勿手改', '同上'],
  ['不要手改', '同上'],
  ['TODO', '开发待办不该印在界面上'],
  ['FIXME', '同上'],
  ['待填', '占位说明不该印在界面上'],
  ['上架时替换', '同上'],
  // ── 下面两条是 2026-10-04 那次「解释性文案审计」加的 ────────────────────────
  // 它们抓的是同一类漏字："我们内部的知识/状态"被写进了用户界面。
  // 为什么能机械判：这两个词**在界面上永远不该出现**，而写在我们自己的注释里完全正常
  // （守卫本来就跳过注释）—— 所以它们不会误报，也正因为不误报才值得加。
  ['开发者', '我们自己的角色/部署状态，不是用户能用的信息（"在开发者那边，还没上"）'],
  ['号文', '规章依据是我们的知识，不是用户的信息（"164 号文要求的两份清单"）'],
];

/**
 * 整条异常（`$e` / `${e}`）不许直接插进字符串。
 *
 * 为什么单列一条：`'没成功：$e'` 在屏幕上会变成 `没成功：PlatformException(…, null, null)` ——
 * 用户看不懂，而且可能带出路径之类的设备细节。我们自己的异常（消息本来就是中文人话）
 * 走 `_userFacing()` 之类的小助手，别的兜底成一句人话，细节进 `debugPrint`。
 *
 * ⚠️ 只匹配**整个变量**：`${e.key}` / `${e.id}` / `${e.aliasList}` 这类取字段是正常的
 * （那些 `e` 是数据模型，不是异常），不能误伤 —— 所以规则写成"`$e` 后面既不是点也不是字母"。
 */
const RAW_EXCEPTION = /\$(?:\{e\}|e(?![.\w]))/;

/** 遥测里也不许整条插（政策的字段说明写的是"错误类型，不含内容"）。 */
const TELEMETRY_HINT = 'analytics.track';

/** 是不是"整行都是注释"（含块注释的行首 `*`）。 */
function isCommentLine(line) {
  const t = line.trimStart();
  return t.startsWith('//') || t.startsWith('*') || t.startsWith('/*');
}

/** 去掉行尾注释（保守：只在引号数成对时切，切不准就不切）。 */
function stripTrailingComment(line) {
  const idx = line.indexOf('//');
  if (idx < 0) return line;
  const before = line.slice(0, idx);
  const quotes = (before.match(/'/g) ?? []).length;
  return quotes % 2 === 0 ? before : line;
}

function inspect(root) {
  const problems = [];
  const libDir = join(root, 'app/lib');
  let scanned = 0;
  let lines = 0;

  const walk = (dir) => {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      const p = join(dir, e.name);
      if (e.isDirectory()) { walk(p); continue; }
      if (!e.name.endsWith('.dart')) continue;
      scanned += 1;
      const text = readFileSync(p, 'utf8');
      text.split('\n').forEach((raw, i) => {
        lines += 1;
        if (isCommentLine(raw)) return;
        const line = stripTrailingComment(raw);
        for (const [needle, why] of BAD) {
          if (line.includes(needle)) {
            problems.push(`${relative(root, p)}:${i + 1} 的字符串里有「${needle}」——${why}`);
          }
        }
        if (RAW_EXCEPTION.test(line) && !line.includes('debugPrint')) {
          const where = line.includes(TELEMETRY_HINT) ? '遥测字段' : '字符串';
          problems.push(`${relative(root, p)}:${i + 1} 把**整条异常**插进了${where}（\`$e\`）——`
            + '屏幕上会连类名一起印出来；我们自己的异常取 `.message`，别的兜底成一句人话，'
            + '细节进 debugPrint');
        }
      });
    }
  };
  walk(libDir);
  return { problems, scanned, lines };
}

// ───────────────────────────────────────────────────────────── 自检
function selftest() {
  const makeTree = (files) => {
    const root = mkdtempSync(join(tmpdir(), 'lianleme-text-'));
    for (const [rel, content] of Object.entries(files)) {
      mkdirSync(dirname(join(root, rel)), { recursive: true });
      writeFileSync(join(root, rel), content);
    }
    return root;
  };
  const cases = [
    ['干净的界面代码：全绿', { 'app/lib/a.dart': "Text('你好'),\n// 注释里写 ** 没关系\n" }, true, null],
    ['字符串里夹了 markdown 记号', { 'app/lib/a.dart': "Text('本机数据也**没删**'),\n" }, false, '「**」'],
    ['字符串里夹了给我们自己的说明', { 'app/lib/a.dart': "Text('本页由仓库自动生成'),\n" }, false, '「由仓库自动生成」'],
    ['整行注释里的记号不算', { 'app/lib/a.dart': "// TODO: 这里以后改\nText('你好'),\n" }, true, null],
    ['块注释行首的 * 不算', { 'app/lib/a.dart': " * TODO 写在块注释里\nText('你好'),\n" }, true, null],
    ['行尾注释里写记号不算', { 'app/lib/a.dart': "Text('你好'), // TODO 稍后\n" }, true, null],
    ['待填这种占位也不许', { 'app/lib/a.dart': "Text('生效日期：待填'),\n" }, false, '「待填」'],
    ['整条异常插进界面字符串', { 'app/lib/a.dart': "Text('没成功：$e'),\n" }, false, '整条异常'],
    ['遥测里整条插异常也不许', { 'app/lib/a.dart': "a.track('x', {'error': '$e'});\n" }, false, '整条异常'],
    ['取异常的 message 是允许的', { 'app/lib/a.dart': "Text('连不上：${e.message}'),\n" }, true, null],
    ['数据模型取字段不算异常（不能误伤）', { 'app/lib/a.dart': "Text('也叫：${e.aliasList}'),\nKey('equip-${e.key}')\n" }, true, null],
    ['debugPrint 里插整条是允许的（日志）', { 'app/lib/a.dart': "debugPrint('失败：$e');\n" }, true, null],
    // 2026-10-04 文案审计新增的两条规则，各自对应一处真实删掉的文案
    ['部署状态写进界面（"在开发者那边"）', { 'app/lib/a.dart': "Text('云备份需要一台服务器（在开发者那边，还没上）'),\n" }, false, '「开发者」'],
    ['规章依据写进界面（"164 号文"）', { 'app/lib/a.dart': "Text('收集了什么、与谁共享（164 号文要求的两份清单）'),\n" }, false, '「号文」'],
    ['同一个词写在注释里不算（这两条规则的边界）', { 'app/lib/a.dart': "// 164 号文要求的双清单，二级菜单形式\nText('个人信息收集清单'),\n" }, true, null],
  ];
  let bad = 0;
  for (const [label, files, wantGreen, expect] of cases) {
    const root = makeTree(files);
    const { problems } = inspect(root);
    const green = problems.length === 0;
    let ok = green === wantGreen;
    let why = green ? '' : `　→ ${problems[0].slice(0, 66)}`;
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
  console.log('\n✓ 自检通过：markdown 记号、"给我们自己看"的说明（含"我们内部的知识/状态"那两条）、'
    + '整条异常插进界面/遥测都藏不住；注释、取 .message、数据模型取字段、debugPrint 都不误报');
}

// ───────────────────────────────────────────────────────────────── 跑
if (process.argv.includes('--selftest')) {
  selftest();
} else {
  const rootArg = process.argv.find((a) => a.startsWith('--root='));
  const { problems, scanned, lines } = inspect(rootArg ? rootArg.slice('--root='.length) : ROOT);
  console.log('用户可见文案核对（app/lib）\n');
  console.log(`  扫了 ${scanned} 个 .dart / ${lines} 行（跳过注释行）`);
  if (problems.length) {
    console.log('');
    for (const p of problems) console.error(`  \x1b[31m✗\x1b[0m ${p}`);
    console.error(`\n✗ ${problems.length} 处 —— Text 不渲染 markdown，星号与内部说明会被用户看见`);
    process.exit(1);
  }
  console.log('\n✓ 界面字符串里没有 markdown 记号，也没有"给我们自己看"的说明');
}
