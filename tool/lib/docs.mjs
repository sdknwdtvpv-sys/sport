/**
 * 练了么 · 文档守卫的公共零件（三个 `check-doc-*` 共用）
 *
 * **为什么有它**：`check-doc-paths` / `check-doc-tables` / `check-doc-versions` 三个工具
 * 各自抄了一遍"要核哪些文档"的枚举（README + `docs/*.md`），`check-doc-versions`
 * 还多带一份"历史行判定"。三处一模一样的代码意味着：**加一个文档目录要改三处**，
 * 漏一处就是"新目录里的文档从来没人核过" —— 2026-10-01 合成一处。
 *
 * 自检：`node tool/lib/docs.mjs --selftest`
 */

import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

/**
 * 要核的文档清单（相对仓库根）。
 *
 * 口径：仓库根的 `README.md` + `docs/` 下的**全部** `.md`。
 * 只认这两个位置是**刻意的**：`store-assets/`、`prototype/`、`usability/` 里也有
 * 面向用户/测试者的文本，但它们不是"陈述项目现状"的文档（核它们会带来无穷的例外）。
 */
export function docFiles(root) {
  const docs = ['README.md'];
  try {
    for (const f of readdirSync(join(root, 'docs'))) {
      if (f.endsWith('.md')) docs.push(`docs/${f}`);
    }
  } catch {
    // docs/ 不在（自检夹具只造了 README）—— 那就是只有 README 可核
  }
  return docs;
}

/**
 * **仓库根上另外几份"陈述项目现状"的文档。**
 *
 * 它们与 `docs/` 下那些是同一类东西，却因为不在 `docs/` 里而**长期没有任何守卫扫过**
 * —— 2026-10-01 才发现，而且代价已经真实发生过：
 * `ROADMAP.md` 抬头写着「v1.7.0 已切版并装在真机上（versionCode 8）」，
 * 而**同一页的表格里**写着「已装 v1.36.0（versionCode 49）」——
 * 一份文档自己跟自己矛盾，六个守卫全绿。
 *
 * 为什么以前没被发现：`check-doc-facts.mjs` 自己另写了一份清单（含这两份），
 * 而 `check-doc-versions` / `check-doc-paths` 只用 `docFiles()`。
 * **两份清单并存 = 有一半文档从来没人核**，所以现在合成一处。
 *
 * `CHANGELOG.md` **刻意不进**：它的版本号全是历史叙述，扫它只会全是误报
 * （它由 `tool/check-changelog.mjs` 单独守）。
 */
export const EXTRA_DOCS = ['ROADMAP.md', 'PRODUCT.md'];

/** 全套要核的文档：README + `docs/*.md` + `EXTRA_DOCS`（去重、顺序稳定、不存在就跳过）。 */
export function allDocFiles(root) {
  const out = docFiles(root);
  for (const f of EXTRA_DOCS) {
    if (out.includes(f)) continue;
    try {
      readFileSync(join(root, f));
      out.push(f);
    } catch {
      // 不在就算了（自检夹具不会造它们）
    }
  }
  return out;
}

/**
 * "这是过去的事"的标记词。
 *
 * ⚠️ 这里踩过一次坑（2026-09-30，记在 `check-doc-versions.mjs` 里）：
 * 判据原本是**整行**匹配，而文档里的表格行很长，行尾一句"旧行写的…"就能把
 * **同一行里当期的版本说法**一起放过。所以判定要看**这处说法前后的一段窗口**，
 * 而不是整行 —— 窗口宽度由 `isHistorical` 的调用方给（默认 40 字）。
 */
export const HISTORY = /历史|曾经|之前|旧|改来|当时|停在|CHANGELOG|复盘/;

/**
 * 某处说法（在 [line] 的第 [index] 个字符、长度 [len]）周围有没有"过去时"标记。
 * 有 → 这一处跳过（它是复盘/叙述，不是"当前状态"）。
 */
export function isHistorical(line, index, len, window = 40) {
  const from = Math.max(0, index - window);
  return HISTORY.test(line.slice(from, index + len + window));
}

// ───────────────────────────────────────────────────────────── 自检
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';

function selftest() {
  let bad = 0;
  const check = (ok, label, extra = '') => {
    if (!ok) bad += 1;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}${extra}`);
  };

  // 1. README + docs/*.md 都要在；非 .md 不要
  const root = mkdtempSync(join(tmpdir(), 'lianleme-docs-'));
  mkdirSync(join(root, 'docs'), { recursive: true });
  writeFileSync(join(root, 'README.md'), '# x');
  writeFileSync(join(root, 'docs', 'a.md'), '# a');
  writeFileSync(join(root, 'docs', 'b.md'), '# b');
  writeFileSync(join(root, 'docs', 'note.txt'), 'x');
  const files = docFiles(root);
  check(files.length === 3, 'README + docs 下两个 .md 都收（共 3 个）', `（${files.length}）`);
  check(files.includes('docs/b.md') && !files.includes('docs/note.txt'),
    '新加的 docs/*.md 自动进来、非 .md 不进');

  // 2. 没有 docs/ 目录时不能炸（自检夹具常常只造 README）
  const bare = mkdtempSync(join(tmpdir(), 'lianleme-docs-'));
  writeFileSync(join(bare, 'README.md'), '# x');
  let threw = false;
  let got = [];
  try { got = docFiles(bare); } catch { threw = true; }
  check(!threw && got.length === 1, '没有 docs/ 目录时只返回 README（不抛）');

  // 3. 历史行判定：**看窗口，不看整行**（这是那个真事故的回归用例）
  // ⚠️ 夹具要**照着真事**来做：那次的"旧"离当期说法很远（几百字的长表格行），
  // 所以窗口判据把它拒绝了。第一版夹具把两者写得太近（30 字），于是
  // "近处的历史标记"被判成历史 —— 那其实是**对**的行为，红的是夹具。
  const pad = '这一行很长，长到把两处说法隔开：' + 'x'.repeat(30) + '；';
  const long = `旧行写的 59.8M 是 v1.22 那会儿的。${pad}**在 v9.9.8 上重编重核**`;
  const claimAt = long.indexOf('v9.9.8');
  check(claimAt > 40, '夹具本身成立：当期说法离"旧"超过 40 字窗口', `（相距 ${claimAt}）`);
  check(!isHistorical(long, claimAt, 7),
    '长行里别处的"旧"不能把当期说法一起放过（窗口判据）');
  const hist = '历史上装的是 v1.0.0（当时）';
  check(isHistorical(hist, hist.indexOf('v1.0.0'), 6),
    '紧挨着说法的"历史/当时"要算历史');

  // 4. ★ 根目录那两份也要进清单（2026-10-01 的真事故的回归用例）
  //    真事：`ROADMAP.md` 抬头写着 versionCode 8、同一页表里写着 49（自己跟自己矛盾），
  //    还有一张表被引用行从中间截断 —— **一个守卫都没扫过这个文件**，所以全都绿着。
  writeFileSync(join(root, 'ROADMAP.md'), '# r\n');
  writeFileSync(join(root, 'PRODUCT.md'), '# p\n');
  const all = allDocFiles(root);
  check(all.includes('ROADMAP.md') && all.includes('PRODUCT.md'),
    '根目录的 ROADMAP.md / PRODUCT.md 也进清单（以前它们没人核）');
  check(all.filter((f) => f === 'README.md').length === 1,
    'README 不重复（旧的 check-doc-facts 那份清单会把它算两遍）');
  check(all.length === files.length + 2,
    'allDocFiles = docFiles + 两份根文档', `（${all.length} vs ${files.length}+2）`);
  rmSync(join(root, 'PRODUCT.md'));
  let noThrow = true;
  let after = [];
  try { after = allDocFiles(root); } catch { noThrow = false; }
  check(noThrow && !after.includes('PRODUCT.md'),
    '根文档不存在时不进清单、也不抛（自检夹具常常只造 README）');

  rmSync(root, { recursive: true, force: true });
  rmSync(bare, { recursive: true, force: true });

  if (bad) {
    console.error(`\n✗ docs 公共零件自检失败 ${bad} 项`);
    process.exit(1);
  }
  console.log('\n✓ 自检通过：文档枚举口径一处、历史判定按窗口（不按整行）');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href
    && process.argv.includes('--selftest')) {
  selftest();
}
