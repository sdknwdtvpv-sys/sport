#!/usr/bin/env node
/**
 * 练了么 · CHANGELOG 的结构核对
 *
 * **它为什么存在**：这条检查原先是 `verify.sh` 里的一段 `node -e '...'` ——
 * **逻辑写死在 bash 字符串里，所以它自己没法被测**。2026-09-30 抓到过一个真缺陷：
 * 有几节被粘到上一行去了（少一个换行），而在 `^## v` 的眼里那些小节**根本不存在**，
 * "降序"照样成立 —— 守护全程绿灯。当时修了判据，但那段代码仍然不可测。
 * 2026-10-01 抽成独立工具，并补上自检。
 *
 * 它核三件事：
 *   1. **每个版本小节都从行首开始**（`^## vX.Y.Z`）—— 粘到上一行的那种要抓出来；
 *   2. **降序排列**（最新的在最上面）；
 *   3. **同一版本不出现两次**（复制粘贴时最容易犯，肉眼又最容易漏）。
 *
 * 用法：
 *   node tool/check-changelog.mjs              # 核仓库里的 CHANGELOG.md
 *   node tool/check-changelog.mjs --selftest   # 自检
 *
 * 退出码：任何一处不对 → 1。
 */

import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** 从文本里抽版本小节：[{ version, line, atLineStart }]。 */
export function versionSections(text) {
  const out = [];
  const lines = text.split('\n');
  lines.forEach((line, i) => {
    // 行首的：`## v1.2.3`
    const head = /^## v(\d+)\.(\d+)\.(\d+)/.exec(line);
    if (head) {
      out.push({
        version: [Number(head[1]), Number(head[2]), Number(head[3])],
        label: `v${head[1]}.${head[2]}.${head[3]}`,
        line: i + 1,
        atLineStart: true,
      });
      return;
    }
    // 不在行首但确实写着的（少个换行、粘到上一行了）—— 这才是要抓的那种
    for (const m of line.matchAll(/## v(\d+)\.(\d+)\.(\d+)/g)) {
      out.push({
        version: [Number(m[1]), Number(m[2]), Number(m[3])],
        label: `v${m[1]}.${m[2]}.${m[3]}`,
        line: i + 1,
        atLineStart: false,
      });
    }
  });
  return out;
}

/** 比较两个版本号：a 比 b 新 → 正数。 */
function cmp(a, b) {
  for (let i = 0; i < 3; i += 1) {
    if (a[i] !== b[i]) return a[i] - b[i];
  }
  return 0;
}

export function inspectText(text) {
  const problems = [];
  const sections = versionSections(text);
  if (!sections.length) {
    problems.push('CHANGELOG.md 里一个小节都没有（`## vX.Y.Z`）—— 措辞变了？检查要跟着改');
    return { problems, sections };
  }

  // 1. 必须从行首开始
  for (const s of sections) {
    if (!s.atLineStart) {
      problems.push(`第 ${s.line} 行：${s.label} 这一节**没从行首开始**（少了换行、粘到上一行去了）`
        + ' —— 那种小节在"降序"检查里根本看不见，等于没人管');
    }
  }

  // 2. 降序（只看行首那些：粘住的上面已经单独报了）
  const heads = sections.filter((s) => s.atLineStart);
  for (let i = 1; i < heads.length; i += 1) {
    if (cmp(heads[i - 1].version, heads[i].version) <= 0) {
      problems.push(`${heads[i - 1].label} 之后出现了 ${heads[i].label}`
        + `（第 ${heads[i].line} 行）—— 小节必须降序`);
    }
  }

  // 3. 同一版本不许出现两次
  const seen = new Map();
  for (const s of sections) {
    if (seen.has(s.label)) {
      problems.push(`${s.label} 出现了两次（第 ${seen.get(s.label)} 行与第 ${s.line} 行）`
        + ' —— 复制粘贴时最容易犯，肉眼又最容易漏');
    } else {
      seen.set(s.label, s.line);
    }
  }

  return { problems, sections };
}

// ───────────────────────────────────────────────────────────── 自检
function selftest() {
  const cases = [
    ['正常降序 → 绿', '## v1.3.0\n\n## v1.2.1\n\n## v1.2.0\n', true, null],
    ['升序 → 必须报', '## v1.2.0\n\n## v1.3.0\n', false, '之后出现了 v1.3.0'],
    ['同一版本出现两次 → 必须报', '## v1.3.0\n\n## v1.3.0\n', false, '出现了两次'],
    ['粘到上一行 → 必须报（这就是 2026-09-30 那个真缺陷）',
      '上一句没换行。## v1.27.1 · 挤在同一行\n\n## v1.27.0\n', false, '没从行首开始'],
    ['一个都没有 → 必须报', '# 更新日志\n\n## 同版追加\n', false, '一个小节都没有'],
    ['小节之间夹着同版追加（### 级）不算版本小节 → 绿',
      '## v1.3.0\n\n### 同版追加：xxx\n\n## v1.2.0\n', true, null],
  ];

  let bad = 0;
  for (const [label, text, wantGreen, expect] of cases) {
    const { problems } = inspectText(text);
    const green = problems.length === 0;
    let ok = green === wantGreen;
    let why = green ? '' : `　→ ${problems[0].slice(0, 62)}`;
    if (ok && !wantGreen && expect && !problems.some((p) => p.includes(expect))) {
      ok = false;
      why = `　→ 红了，但不是因为「${expect}」（红在：${problems[0].slice(0, 40)}）`;
    }
    if (!ok) bad += 1;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}${why}`);
  }

  if (bad) {
    console.error(`\n✗ 自检失败 ${bad} 项 —— 这个工具本身不可信，先修它`);
    process.exit(1);
  }
  console.log('\n✓ 自检通过：乱序、重复版本、粘到上一行、一节都没有都藏不住');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href
    && process.argv.includes('--selftest')) {
  selftest();
} else if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  // 允许用 --root= 指到别处（自检/夹具需要）
  const rootArg = process.argv.find((a) => a.startsWith('--root='));
  const root = rootArg ? rootArg.slice('--root='.length) : ROOT;
  let text;
  try {
    text = readFileSync(join(root, 'CHANGELOG.md'), 'utf8');
  } catch {
    console.error('✗ 读不到 CHANGELOG.md');
    process.exit(1);
  }
  const { problems, sections } = inspectText(text);
  console.log('CHANGELOG 结构核对\n');
  console.log(`  版本小节 ${sections.length} 个（行首 ${sections.filter((s) => s.atLineStart).length} 个）`);
  if (problems.length) {
    console.log('');
    for (const p of problems) console.error(`  \x1b[31m✗\x1b[0m ${p}`);
    console.error(`\n✗ ${problems.length} 处不对 —— CHANGELOG 是给用户看的更新日志`);
    process.exit(1);
  }
  console.log('\n✓ 版本小节降序、无重复、都从行首开始');
}
