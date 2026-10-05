#!/usr/bin/env node
/**
 * 练了么 · shell 脚本的「变量后面紧跟中文」核对（**bash 3.2 的地雷**）
 *
 * **它为什么存在**（2026-10-05 真踩，而且第一轮我复现错了）：
 * 你在自己的 Terminal 里跑 `app/android/tool/gen-upload-keystore.sh`，走到问完密码之后报：
 *
 *     ./tool/gen-upload-keystore.sh: line 71: KEYSTORE?: unbound variable
 *
 * 那一行是 `echo "→ 生成 $KEYSTORE（RSA 2048，有效期 10000 天，PKCS12 格式）"`。
 * 我第一反应以为是脚本写错了，但那句在**我的 bash 调用里跑得好好的** ——
 * 因为**触发条件是 locale**（这一点必须记下来，否则下次还会判错方向）：
 *
 *     LC_ALL=C            → /tmp/x（RSA 2048，PKCS12）        正常
 *     LC_ALL=en_US.UTF-8  → /bin/bash: KEYSTORE?: unbound variable   ← Terminal 的默认
 *
 * 根因：macOS 自带的是 **bash 3.2**（2007 年，苹果为了 GPLv3 一直没升级）。
 * 在 UTF-8 locale 下，它会把 `$KEYSTORE（` 里**紧跟在变量名后面的那个全角括号的字节
 * 当成变量名的一部分** → 去找一个叫 `KEYSTORE（` 的变量 → `set -u` 当场 unbound。
 * 于是症状是"脚本坏在生成密钥之前"，而**输入的密码与它无关**。
 *
 * 判据**很窄**，所以不误报：只抓「**没有花括号**的 `$VAR`，后面紧邻一个非 ASCII 字符」。
 * 修法一行：写成 `${VAR}` —— 花括号把变量名的边界说死了，bash 3.2 就不会猜。
 *
 * 用法：
 *   node tool/check-shell-locale.mjs              # 扫全仓库的 .sh / .bash
 *   node tool/check-shell-locale.mjs --selftest    # 自检（四条正向/负向用例）
 *
 * 退出码：发现任何一处 → 1。
 */

import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SKIP_DIRS = new Set(['.git', '.pub-cache', 'build', 'node_modules', '.dart_tool', 'dist', 'ios-dd']);

/** `$VAR`（不带花括号）后面紧跟一个非 ASCII 字符。 */
const RISKY = /\$([A-Za-z_][A-Za-z0-9_]*)(?=[^\x00-\x7f])/g;

/** 注释行不参与判定 —— 注释里写中文说明完全正常（这条是"不误报"的边界）。 */
const isComment = (line) => /^\s*#/.test(line);

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    if (SKIP_DIRS.has(name)) continue;
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) walk(p, out);
    else if (name.endsWith('.sh') || name.endsWith('.bash')) out.push(p);
  }
  return out;
}

export function inspect(root = ROOT) {
  const problems = [];
  const facts = [];
  let scanned = 0;
  for (const file of walk(root)) {
    scanned += 1;
    const lines = readFileSync(file, 'utf8').split('\n');
    lines.forEach((line, i) => {
      if (isComment(line)) return;
      for (const m of line.matchAll(RISKY)) {
        problems.push(`${relative(root, file)}:${i + 1} 的 \`$${m[1]}\` 后面紧邻一个非 ASCII 字符`
          + `（\`${line.trim().slice(0, 60)}\`）—— macOS 的 bash 3.2 在 UTF-8 locale 下`
          + '会把那个字符的字节吞进变量名，`set -u` 直接 unbound variable。写成 `${' + m[1] + '}` 即可');
      }
    });
  }
  facts.push(`扫了 ${scanned} 个 .sh / .bash`);
  return { problems, facts };
}

function selftest() {
  const cases = [
    ['干净的脚本：变量都带花括号', { 'a.sh': 'set -u\nK=/tmp/x\necho "生成 ${K}（RSA）"\necho "$K, ok"\n' }, true, null],
    ['★ 变量后面紧跟全角括号（真踩过的那一行）', { 'a.sh': 'set -u\nK=/tmp/x\necho "→ 生成 $K（RSA 2048，有效期 10000 天）"\n' }, false, '后面紧邻一个非 ASCII 字符'],
    ['注释里写同样的东西不算（不误报）', { 'a.sh': '# 生成 $K（RSA）\necho "hi"\n' }, true, null],
    ['带花括号 + 中文 → 绿', { 'a.sh': 'echo "${K}（RSA）"\n' }, true, null],
    ['变量后面是 ASCII 标点/空格 → 绿', { 'a.sh': 'echo "$K（x）"\necho "$K: 中文"\n'.replace('$K（x）', '$K') }, true, null],
    // ★ 我自己第一版把这条写成"绿"了 —— 实测**也是红的**：
    //   LC_ALL=en_US.UTF-8 + `echo "生成（$K）"` → `K?: unbound variable`
    //   规律是"变量**后面**紧邻任意非 ASCII 字符"，不看它是左括号还是右括号。
    ['★ 变量后面跟全角**右**括号（同样会炸 —— 我第一版以为不会）',
      { 'a.sh': 'echo "生成（$K）"\n' }, false, '后面紧邻一个非 ASCII 字符'],
    ['加花括号 + 全角右括号 → 绿', { 'a.sh': 'echo "生成（${K}）"\n' }, true, null],
  ];
  let bad = 0;
  for (const [label, files, wantGreen, expect] of cases) {
    const root = mkdtempSync(join(tmpdir(), 'lianleme-sh-'));
    for (const [rel, body] of Object.entries(files)) {
      mkdirSync(dirname(join(root, rel)), { recursive: true });
      writeFileSync(join(root, rel), body);
    }
    const { problems } = inspect(root);
    const green = problems.length === 0;
    let ok = green === wantGreen;
    let why = green ? '' : `　→ ${problems[0].slice(0, 78)}`;
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
  console.log('\n✓ 自检通过：变量后紧跟中文会被抓到，花括号写法 / 注释 / 中文在前 / ASCII 标点都不误报');
}

if (process.argv.includes('--selftest')) {
  selftest();
} else {
  const { problems, facts } = inspect();
  console.log('shell 脚本的「变量后紧跟中文」核对（bash 3.2 + UTF-8 locale 的坑）\n');
  for (const f of facts) console.log(`  ${f}`);
  console.log();
  if (problems.length) {
    for (const p of problems) console.error(`\x1b[31m✗\x1b[0m ${p}`);
    console.error(`\n✗ ${problems.length} 处 —— 修法都是加一对花括号：\`$VAR（\` → \`\${VAR}（\``);
    process.exit(1);
  }
  console.log('✓ 没有「未加花括号的变量紧跟非 ASCII 字符」的写法（macOS 上跑不会炸）');
}
