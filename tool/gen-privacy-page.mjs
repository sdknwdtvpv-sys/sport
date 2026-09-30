#!/usr/bin/env node
/**
 * 练了么 · 把隐私政策渲染成可发布的静态页
 *
 * **为什么要有这一步**：应用商店（小米、应用宝、Google Play）都要求一个
 * **公网可访问的隐私政策 URL**。而"公开的那份"和"仓库里的那份"一旦各写各的，
 * 早晚会对不上 —— 那是最不该漂移的一类文本。
 *
 * 所以：`docs/privacy-policy.md` 是**唯一的事实来源**，这个脚本把它渲染成 HTML，
 * 产物 **入库**（`store-assets/privacy/`），因为它是交给商店的交付物
 * —— 不是 `dist/` 里的构建产物。
 * （这个区别是踩过的：商店图标第一版写进 `dist/`，clean 跑道上检查当场红。）
 *
 * `--check` 用来防漂移：政策正文改了却没重新生成 HTML → 退出码 1。
 * 它进了 verify.sh 第 2 层。
 *
 * 零依赖：自己写了一个够用的 Markdown 子集渲染器（标题 / 表格 / 列表 / 引用 /
 * 围栏代码 / 行内粗体与代码 / 段落）。不装 markdown 库，是因为这个仓库
 * 的 tool/ 全是零依赖 —— 而且这份文档用到的语法就这么几种，全在上面数过。
 *
 * 用法：
 *   node tool/gen-privacy-page.mjs          # 重新生成（写 store-assets/privacy/）
 *   node tool/gen-privacy-page.mjs --check  # 只校验是否过期
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// 渲染器抽到 tool/lib/markdown.mjs 共用（软著说明书也要渲染同一套语法）
import { renderMarkdown, esc } from './lib/markdown.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT_DIR = join(ROOT, 'store-assets/privacy');
const check = process.argv.includes('--check');

const PAGES = [
  { src: 'docs/privacy-policy.md', out: 'index.html', lang: 'zh-CN', title: '练了么 · 隐私政策' },
  { src: 'docs/privacy-policy.en.md', out: 'en.html', lang: 'en', title: 'LianLeMe · Privacy Policy' },
];

const STYLE = `
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin: 0; background: #0B0B0D; color: #F5F5F7;
    font: 16px/1.75 -apple-system, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif; }
  main { max-width: 760px; margin: 0 auto; padding: 40px 20px 96px; }
  h1 { font-size: 28px; margin: 0 0 8px; }
  h2 { font-size: 21px; margin: 40px 0 12px; padding-top: 16px; border-top: 1px solid #2A2A31; }
  h3 { font-size: 17px; margin: 28px 0 8px; color: #D8FF47; }
  h4 { font-size: 16px; margin: 22px 0 6px; }
  a { color: #D8FF47; }
  code { background: #1F1F24; padding: 1px 5px; border-radius: 4px; font-size: 90%; }
  pre { background: #16161A; border: 1px solid #2A2A31; border-radius: 8px; padding: 12px 14px; overflow-x: auto; }
  pre code { background: none; padding: 0; }
  blockquote { margin: 16px 0; padding: 10px 16px; border-left: 3px solid #D8FF47;
    background: #16161A; border-radius: 0 8px 8px 0; color: #C9C9D1; }
  blockquote p { margin: 6px 0; }
  table { border-collapse: collapse; width: 100%; margin: 16px 0; font-size: 15px; display: block; overflow-x: auto; }
  th, td { border: 1px solid #2A2A31; padding: 8px 10px; text-align: left; vertical-align: top; }
  /* 表头别折行：「什么时候发」被挤成三行很难看。表格本身可横向滚动，够了。 */
  th { white-space: nowrap; }
  th { background: #1F1F24; }
  hr { border: none; border-top: 1px solid #2A2A31; margin: 32px 0; }
  footer { margin-top: 48px; color: #9A9AA5; font-size: 14px; }
`;

function page(md, { lang, title }) {
  return `<!DOCTYPE html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(title)}">
<style>${STYLE}</style>
</head>
<body>
<main>
${renderMarkdown(md)}
<footer>本页由 <code>tool/gen-privacy-page.mjs</code> 从仓库里的
<code>docs/privacy-policy.md</code> 生成 —— 页面内容与随包发布的那份同源，
改政策只改 Markdown，然后重跑这个脚本。</footer>
</main>
</body>
</html>
`;
}

/// Markdown → **纯文本**（给应用内的隐私政策页用）
///
/// 为什么不直接把 Markdown 丢进 App：README 级别的 Markdown 语法（`**加粗**`、表格管道符、
/// 链接方括号）在 TextView 里就是一堆符号，用户看到的会是"**我们**"这种带星号的东西。
/// 而应用内那份**必须能正常阅读** —— 小米商店的隐私合规指引里明确要求
/// "应用内的隐私政策必须是可以正常打开和查看的状态"。
///
/// 三条转换规则（够用即可，不做完整 Markdown 解析）：
///   * 标题去掉 `#`，前后留空行（纯文本里靠空行分段）
///   * 表格每行变成 `列1　列2　列3`（用全角空格分隔），去掉 `|---|` 那种分隔行
///   * 行内语法：`**粗**`/`*斜*`/`` `码` `` 去掉标记，`[文字](链接)` → `文字（链接）`
function toPlainText(md) {
  const out = [];
  // HTML 注释不显示在页面上，纯文本里也不该出现（维护者注就藏在这里面）
  md = md.replace(/<!--[\s\S]*?-->/g, '');
  for (const raw of md.split('\n')) {
    let line = raw;

    // 表格分隔行（|---|:--:|）直接丢掉
    if (/^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$/.test(line)) continue;

    // 表格数据行
    if (/^\s*\|.*\|\s*$/.test(line)) {
      const cells = line.trim().replace(/^\|/, '').replace(/\|$/, '')
        .split('|').map((c) => c.trim());
      // ⚠️ 单元格也要过 inline()：第一版漏了，于是表格里的 `**加粗**`
      // 在纯文本里原样留着（正文里没有，只有表格里漏 —— 所以 grep 正文看不出来）
      out.push(cells.filter((c) => c !== '').map(inline).join('　'));
      continue;
    }

    // 标题
    const h = line.match(/^(#{1,6})\s+(.*)$/);
    if (h) {
      out.push('');
      out.push(inline(h[2]));
      out.push('');
      continue;
    }

    // 引用块：去掉 `>`，保留内容（政策里那些"⚠️ 待决"就是引用）
    line = line.replace(/^\s*>\s?/, '');
    // 分隔线
    if (/^\s*---\s*$/.test(line)) { out.push(''); continue; }
    out.push(inline(line));
  }
  // 压掉连续空行
  return out.join('\n').replace(/\n{3,}/g, '\n\n').trim() + '\n';
}

function inline(s) {
  return s
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '$1（$2）')
    .replace(/\*\*([^*]+)\*\*/g, '$1')
    .replace(/\*([^*]+)\*/g, '$1')
    .replace(/`([^`]+)`/g, '$1')
    // 兜底：加粗跨行时（源文件里 `> **第一行…` / `> …最后一行**`）配对不成立，
    // 上面那条按行匹配的正则会漏掉，于是纯文本里留下一串光秃秃的 `**`。
    // 生成物是给人读的，宁可把这类残留一律去掉。
    .replace(/\*\*/g, '');
}

/// 剥掉 `<!-- 内部 -->` 与 `<!-- /内部 -->` 之间的内容。
///
/// 政策源文件里既有"给用户看的正文"，也有"给开发者看的注记"（当前状态、上架待办、
/// 文件路径、核对命令）。两处生成物 —— 公网页面与应用内那份 —— **都不该带后者**：
/// 放上去既难看，也会让商店审核员看到"未经法务审核"这种话。
/// 与其维护两份会漂的文档，不如一份源 + 显式标记 + 生成时剥掉。
function stripInternal(md) {
  // ⚠️ 标记**必须独占一行**才算数。第一版只匹配标记本身，于是"块内解释标记写法"那句
  // 让剥除提前闭合，内部内容照样漏进生成物（生成出来才发现）。
  return md
    // ⚠️ 顺序要紧，两个方向都踩过：
    //   1. **先剥"内部块"，再剥剩下的 HTML 注释** —— 反过来会把内部块自己的
    //      `<!-- 内部 -->` 当成普通注释先吃掉，于是块标记消失、整段内部内容留在生成物里。
    //   2. 剩下的 HTML 注释也必须剥：renderMarkdown **不认** HTML 注释，
    //      会把注释里的文字渲染成 <p>。第一版就是这么把"维护者注"印上了公网页面。
    .replace(/^[ \t]*<!--\s*内部\s*-->[ \t]*$[\s\S]*?^[ \t]*<!--\s*\/内部\s*-->[ \t]*$/gm, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/\n{3,}/g, '\n\n')
    .trim() + '\n';
}

// 应用内那份：**同一份 Markdown** 生成的纯文本，随包发布
const APP_TEXT = join(ROOT, 'app/assets/privacy-policy.txt');
const APP_SRC = 'docs/privacy-policy.md';

// ── 跑 ──────────────────────────────────────────────────────────────────
let stale = 0;
let written = 0;
mkdirSync(OUT_DIR, { recursive: true });

for (const p of PAGES) {
  const srcPath = join(ROOT, p.src);
  if (!existsSync(srcPath)) { console.log(`  跳过（缺 ${p.src}）`); continue; }
  const html = page(stripInternal(readFileSync(srcPath, 'utf8')), p);
  const outPath = join(OUT_DIR, p.out);
  const existing = existsSync(outPath) ? readFileSync(outPath, 'utf8') : null;

  if (check) {
    if (existing !== html) {
      console.log(`✗ ${p.out} 与 ${p.src} 不一致 —— 政策改了但页面没重新生成`);
      console.log(`  修：node tool/gen-privacy-page.mjs`);
      stale++;
    } else {
      console.log(`  ${p.out} 与 ${p.src} 一致`);
    }
  } else {
    writeFileSync(outPath, html, 'utf8');
    written++;
    console.log(`  写入 store-assets/privacy/${p.out}（${html.length} 字节）`);
  }
}

// 应用内那份（纯文本）：和公网页面同一份 Markdown，一起防漂
if (existsSync(join(ROOT, APP_SRC))) {
  const text = toPlainText(stripInternal(readFileSync(join(ROOT, APP_SRC), 'utf8')));
  const existing = existsSync(APP_TEXT) ? readFileSync(APP_TEXT, 'utf8') : null;

  if (check) {
    if (existing !== text) {
      console.log(`✗ app/assets/privacy-policy.txt 与 ${APP_SRC} 不一致 —— 政策改了但应用内那份没重新生成`);
      console.log('  修：node tool/gen-privacy-page.mjs');
      stale++;
    } else {
      console.log(`  app/assets/privacy-policy.txt 与 ${APP_SRC} 一致（${text.length} 字节）`);
    }
  } else {
    mkdirSync(dirname(APP_TEXT), { recursive: true });
    writeFileSync(APP_TEXT, text, 'utf8');
    written++;
    console.log(`  写入 app/assets/privacy-policy.txt（${text.length} 字节）`);
  }
}

if (check && stale) process.exit(1);
console.log(check ? '\n✓ 隐私政策页面与正文同源（含应用内那份）' : `\n✓ 生成 ${written} 份`);
