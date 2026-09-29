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

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT_DIR = join(ROOT, 'store-assets/privacy');
const check = process.argv.includes('--check');

const PAGES = [
  { src: 'docs/privacy-policy.md', out: 'index.html', lang: 'zh-CN', title: '练了么 · 隐私政策' },
  { src: 'docs/privacy-policy.en.md', out: 'en.html', lang: 'en', title: 'LianLeMe · Privacy Policy' },
];

// ── 行内元素 ────────────────────────────────────────────────────────────
const esc = (s) => s
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;');

function inline(s) {
  let t = esc(s);
  t = t.replace(/`([^`]+)`/g, '<code>$1</code>');
  t = t.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  // [文字](链接)：只允许相对路径与 http(s)，避免渲染出 javascript: 之类
  t = t.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (m, text, href) => {
    const safe = /^(https?:\/\/|#|\/|[\w.-]+\.(md|json|mjs|dart|sh|html))/i.test(href);
    if (!safe) return text;
    const target = href.endsWith('.md') ? href : href; // 保留原链接，便于同仓库互跳
    return `<a href="${target}">${text}</a>`;
  });
  return t;
}

/** 表格：连续的 `| … |` 行；第二行是 `|---|---|` 分隔时才算表头。 */
function renderTable(rows) {
  const cells = (r) => r.replace(/^\||\|$/g, '').split('|').map((c) => c.trim());
  const head = cells(rows[0]);
  const body = rows.slice(1).map(cells);
  let html = '<table>\n<thead><tr>'
    + head.map((c) => `<th>${inline(c)}</th>`).join('')
    + '</tr></thead>\n<tbody>\n';
  for (const r of body) {
    html += '<tr>' + r.map((c) => `<td>${inline(c)}</td>`).join('') + '</tr>\n';
  }
  return html + '</tbody>\n</table>\n';
}

function render(md) {
  const lines = md.split('\n');
  const out = [];
  let i = 0;
  let para = [];

  const flushPara = () => {
    if (para.length) { out.push(`<p>${inline(para.join(' '))}</p>\n`); para = []; }
  };

  while (i < lines.length) {
    const line = lines[i];

    // 围栏代码块
    if (line.startsWith('```')) {
      flushPara();
      const lang = line.slice(3).trim();
      const buf = [];
      i++;
      while (i < lines.length && !lines[i].startsWith('```')) { buf.push(lines[i]); i++; }
      i++; // 跳过结束围栏
      out.push(`<pre><code${lang ? ` class="lang-${lang}"` : ''}>${esc(buf.join('\n'))}</code></pre>\n`);
      continue;
    }

    // 标题
    const h = /^(#{1,4})\s+(.*)$/.exec(line);
    if (h) {
      flushPara();
      const level = h[1].length;
      const text = inline(h[2]);
      const id = h[2].toLowerCase().replace(/[^\w\u4e00-\u9fa5]+/g, '-').replace(/^-|-$/g, '');
      out.push(`<h${level} id="${id}">${text}</h${level}>\n`);
      i++;
      continue;
    }

    // 表格
    if (/^\|/.test(line) && i + 1 < lines.length && /^\|[\s:|-]+\|$/.test(lines[i + 1])) {
      flushPara();
      const rows = [lines[i]];
      i += 2; // 跳过表头与分隔行
      while (i < lines.length && /^\|/.test(lines[i])) { rows.push(lines[i]); i++; }
      out.push(renderTable(rows));
      continue;
    }

    // 列表（- 或数字）
    if (/^(\s*)([-*]|\d+\.)\s+/.test(line)) {
      flushPara();
      const items = [];
      while (i < lines.length) {
        const m = /^(\s*)([-*]|\d+\.)\s+(.*)$/.exec(lines[i]);
        if (!m) break;
        // 续行（比标记多缩进的非空行）并入上一条
        let text = m[3];
        i++;
        while (i < lines.length && /^\s+\S/.test(lines[i]) && !/^\s*([-*]|\d+\.)\s+/.test(lines[i])) {
          text += ' ' + lines[i].trim();
          i++;
        }
        items.push(`<li>${inline(text)}</li>`);
      }
      out.push(`<ul>\n${items.join('\n')}\n</ul>\n`);
      continue;
    }

    // 引用
    if (/^>\s?/.test(line)) {
      flushPara();
      const buf = [];
      while (i < lines.length && /^>\s?/.test(lines[i])) { buf.push(lines[i].replace(/^>\s?/, '')); i++; }
      // ⚠️ 引用块里的内容要**再走一遍块级渲染**，不能逐行当段落。
      // 政策里就有一个写在引用里的表格（运营者/联系方式），
      // 第一版逐行渲染，结果表格原样漏成了一串 `| ... |` 文本。
      out.push(`<blockquote>${render(buf.join('\n'))}</blockquote>\n`);
      continue;
    }

    // 分隔线
    if (/^---+$/.test(line.trim())) { flushPara(); out.push('<hr>\n'); i++; continue; }

    // 空行 → 段落边界
    if (!line.trim()) { flushPara(); i++; continue; }

    para.push(line.trim());
    i++;
  }
  flushPara();
  return out.join('');
}

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
${render(md)}
<footer>本页由 <code>tool/gen-privacy-page.mjs</code> 从仓库里的
<code>docs/privacy-policy.md</code> 生成 —— 页面内容与随包发布的那份同源，
改政策只改 Markdown，然后重跑这个脚本。</footer>
</main>
</body>
</html>
`;
}

// ── 跑 ──────────────────────────────────────────────────────────────────
let stale = 0;
let written = 0;
mkdirSync(OUT_DIR, { recursive: true });

for (const p of PAGES) {
  const srcPath = join(ROOT, p.src);
  if (!existsSync(srcPath)) { console.log(`  跳过（缺 ${p.src}）`); continue; }
  const html = page(readFileSync(srcPath, 'utf8'), p);
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

if (check && stale) process.exit(1);
console.log(check ? '\n✓ 隐私政策页面与正文同源' : `\n✓ 生成 ${written} 个页面`);
