#!/usr/bin/env node
/**
 * 练了么 · 生成软著**鉴别材料的 PDF**（源程序 + 软件说明书）
 *
 * **为什么需要它**：`copyright-export.mjs` 产出的是 `.txt`，而登记系统要上传的是 PDF：
 * 按[中国版权保护中心·所需文件](https://www.ccopyright.com/index.php?optionid=1080)：
 *
 *   * 鉴别材料 = 源程序和任何一种文档的**前、后各连续 30 页**；不到 60 页交全部
 *   * **程序每页不少于 50 行，文档每页不少于 30 行**
 *   * 申请文件应**纵向排版**
 *   * **鉴别材料页眉的软件版本号应与申请表一致**（有无 V 以申请表为准）
 *
 * 最后那条是最容易翻车的：页眉版本号与申请表对不上，等于材料不一致。
 * 所以版本号从 `app/lib/core/app_info.dart` 读（与 App、与申请表同一个来源）。
 *
 * 做法：自己排版成 A4 的 HTML（每页 50 行、页眉带版本与真实页码、页脚著作权人），
 * 再用**无头 Chrome** 打成 PDF —— 汉字字体、A4、纵向都由浏览器保证，
 * 不必手写 PDF 编码器（那是另一件容易出错的事）。
 *
 * 用法：
 *   node tool/copyright-pdf.mjs --owner "张三"     # 著作权人（页码页脚要写）
 *   node tool/copyright-pdf.mjs                    # 不带 --owner 会**警告**并留占位
 *
 * 产物：`dist/copyright/*.pdf`（dist 已 gitignore —— 那是源码的副本，不进仓库）
 */

import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync, statSync, rmSync, mkdtempSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { dirname, join, relative } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { collect, lineStream, APP_VERSION } from './copyright-export.mjs';
import { renderMarkdown } from './lib/markdown.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = join(ROOT, 'dist/copyright');
const APP_NAME = '练了么';           // 与申请表「软件全称」前缀一致
const PER_PAGE = 50;                  // 官方要求"程序每页不少于 50 行"
const FRONT = 30;
const BACK = 30;

const argv = process.argv.slice(2);
const argOf = (n, d) => { const i = argv.indexOf(n); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };
const owner = argOf('--owner', '');

const ownerText = owner || '（著作权人：待填）';

/** 把 HTML 落到磁盘（Chrome 要按 file:// 打开它） */
function writeHtml(html, pdfPath) {
  const htmlPath = pdfPath.replace(/\.pdf$/, '.html');
  writeFileSync(htmlPath, html, 'utf8');
  return htmlPath;
}

// ---------------------------------------------------------------- 找 Chrome
function findChrome() {
  const candidates = [
    process.env.CHROME_PATH,
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
    '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
  ].filter(Boolean);
  return candidates.find((p) => existsSync(p)) ?? null;
}

const CHROME = findChrome();
if (!CHROME) {
  console.error('✗ 找不到 Chrome / Chromium —— 用无头浏览器打 PDF 是这里唯一依赖的外部程序。');
  console.error('  装一个，或设 CHROME_PATH 指向它。');
  process.exit(1);
}

// ---------------------------------------------------------------- 通用样式
const PAGE_CSS = `
  @page { size: A4 portrait; margin: 0; }
  * { box-sizing: border-box; }
  body { margin: 0; font-family: "PingFang SC", "Hiragino Sans GB", "Heiti SC", sans-serif; color: #000; }
  .page { width: 210mm; height: 297mm; padding: 14mm 12mm 16mm; position: relative;
          page-break-after: always; overflow: hidden; background: #fff; }
  .page:last-child { page-break-after: auto; }
  .hd { display: flex; justify-content: space-between; align-items: baseline;
        font-size: 9pt; border-bottom: 0.6pt solid #000; padding-bottom: 1.5mm; margin-bottom: 3mm; }
  .ft { position: absolute; left: 12mm; right: 12mm; bottom: 8mm; font-size: 8pt; color: #333;
        border-top: 0.6pt solid #000; padding-top: 1.2mm; display: flex; justify-content: space-between; }
  pre.src { margin: 0; font-family: "Courier New", Menlo, monospace; font-size: 7.6pt;
            line-height: 1.46; white-space: pre; }
`;

function hd(left, right) {
  return `<div class="hd"><span>${left}</span><span>${right}</span></div>`;
}
function ft(left, right = '') {
  return `<div class="ft"><span>${left}</span><span>${right}</span></div>`;
}

// ---------------------------------------------------------------- 源程序 PDF
function sourceHtml() {
  const { files, skipped } = collect();
  const lines = lineStream(files);
  const totalPages = Math.ceil(lines.length / PER_PAGE);

  const front = [];
  for (let i = 0; i < FRONT && i < totalPages; i++) front.push(i);
  const back = [];
  for (let i = Math.max(0, totalPages - BACK); i < totalPages; i++) {
    if (!front.includes(i)) back.push(i);
  }

  const renderPage = (pageIdx, isLastFront) => {
    const slice = lines.slice(pageIdx * PER_PAGE, (pageIdx + 1) * PER_PAGE);
    const no = pageIdx + 1;
    // 第 30 页的页脚说明"中间省略"，这样 60 页里不出多余的说明页
    const note = isLastFront && totalPages > front.length + back.length
      ? `　·　中间省略 ${totalPages - front.length - back.length} 页（共 ${lines.length} 行 / ${files.length} 个源文件）`
      : '';
    return `<div class="page">`
      + hd(`${APP_NAME} V${APP_VERSION}　源程序`, `第 ${no} 页 / 共 ${totalPages} 页`)
      + `<pre class="src">${slice.map((l) => l.replace(/&/g, '&amp;').replace(/</g, '&lt;')).join('\n')}</pre>`
      + ft(`著作权人：${ownerText}`, `本页 ${slice.length} 行${note}`)
      + `</div>`;
  };

  const pages = [
    ...front.map((i) => renderPage(i, i === front[front.length - 1])),
    ...back.map((i) => renderPage(i, false)),
  ];

  const html = `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<title>${APP_NAME} V${APP_VERSION} 源程序</title><style>${PAGE_CSS}</style></head>
<body>${pages.join('\n')}</body></html>`;

  return { html, totalPages, lineCount: lines.length, fileCount: files.length, pageCount: pages.length, skipped };
}

// ---------------------------------------------------------------- 说明书 PDF
//
// 说明书是"文档"，跟源程序不一样：它自然分页，段落/表格/图片高度不一。
//
// **页眉页脚必须由我们自己盖**，因为 Chrome 的 header/footer 模板在这台机器上
// 不替换 `{{pageNumber}}` / `{{totalPages}}`（新旧 headless 都试过，原样印出占位符）。
// 所以走两步：① 先用同一个样式把文档渲染到浏览器里，**量出每个块的位置与高度**；
// ② 按可用高度切页，再输出**显式页**，每页盖真实页码。跟源程序是同一套机制。
//
// 官方要求在这里落地：A4 纵向、**文档每页不少于 30 行**（正文行高下每页约 45 行）、
// 页眉带软件名称与版本号（**必须与申请表一致**）。

const MM = 3.7795275591;                 // 1mm = 3.7795px（CSS 96dpi）
const PAGE_W = 210, PAGE_H = 297;
const MARGIN = { top: 18, right: 16, bottom: 20, left: 16 };
const CONTENT_W = PAGE_W - MARGIN.left - MARGIN.right;          // 178mm
const CONTENT_H = PAGE_H - MARGIN.top - MARGIN.bottom - 12;     // 再扣掉页眉页脚占位

const MANUAL_CSS = `
  * { box-sizing: border-box; }
  body { margin: 0; font-family: "PingFang SC", "Hiragino Sans GB", sans-serif;
         font-size: 10.5pt; line-height: 1.7; color: #000; }
  h1 { font-size: 18pt; margin: 0 0 5mm; }
  h2 { font-size: 14pt; margin: 7mm 0 2.5mm; border-bottom: 0.6pt solid #999; padding-bottom: 1mm; }
  h3 { font-size: 12pt; margin: 5mm 0 1.5mm; }
  table { border-collapse: collapse; width: 100%; margin: 2.5mm 0; font-size: 9.5pt; }
  th, td { border: 0.6pt solid #666; padding: 1.4mm 2mm; text-align: left; vertical-align: top; }
  th { background: #f0f0f0; }
  code { font-family: "Courier New", monospace; font-size: 9pt; background: #f4f4f4; padding: 0 1mm; }
  pre { background: #f4f4f4; padding: 2.5mm; font-size: 8.5pt; white-space: pre-wrap; }
  blockquote { margin: 2.5mm 0; padding: 2mm 3mm; border-left: 2pt solid #888; background: #fafafa; }
  img { max-width: 100%; border: 0.6pt solid #bbb; margin: 1.5mm 0; }
  hr { border: none; border-top: 0.6pt solid #aaa; margin: 5mm 0; }
  p { margin: 2mm 0; }
  ul { margin: 2mm 0; padding-left: 6mm; }
`;

/** 测量版：所有块放在一个固定宽度的容器里，量它们的 offsetTop/高度与上下外边距 */
function manualMeasureHtml() {
  const md = readFileSync(join(ROOT, 'docs/copyright-manual.md'), 'utf8');
  const body = renderMarkdown(md).replace(/src="\.\.\//g, `src="file://${ROOT}/`);
  return `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<style>${MANUAL_CSS}
  #m { width: ${CONTENT_W}mm; }
</style></head><body><div id="m">${body}</div></body></html>`;
}

/** 按量出来的块切页，并盖上页眉页脚 */
function manualFromBlocks(blocks) {
  const avail = CONTENT_H * MM;
  const pages = [];
  let cur = [];
  let used = 0;
  for (const b of blocks) {
    const h = b.h + b.mt + b.mb;
    // 一页装不下就翻页（单个块比一页还高时，它自己占一页 —— 溢出会被 page 的
    // overflow:visible 顺延到下一页，宁可多一页也不许裁掉内容）
    if (used > 0 && used + h > avail) { pages.push(cur); cur = []; used = 0; }
    cur.push(b);
    used += h;
  }
  if (cur.length) pages.push(cur);

  const body = pages.map((page, i) => {
    const inner = page.map((b) => b.html).join('\n');
    return `<div class="page">`
      + `<div class="hd"><span>${APP_NAME} V${APP_VERSION}　软件说明书</span>`
      + `<span>第 ${i + 1} 页 / 共 ${pages.length} 页</span></div>`
      + `<div class="bd">${inner}</div>`
      + `<div class="ft"><span>著作权人：${ownerText}</span><span>${APP_NAME} V${APP_VERSION}</span></div>`
      + `</div>`;
  }).join('\n');

  return `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<style>${MANUAL_CSS}
  @page { size: A4 portrait; margin: 0; }
  .page { width: ${PAGE_W}mm; height: ${PAGE_H}mm; padding: ${MARGIN.top}mm ${MARGIN.right}mm ${MARGIN.bottom}mm ${MARGIN.left}mm;
          position: relative; page-break-after: always; background: #fff; }
  .page:last-child { page-break-after: auto; }
  .hd { display: flex; justify-content: space-between; font-size: 9pt;
        border-bottom: 0.6pt solid #000; padding-bottom: 1.2mm; margin-bottom: 2.5mm; }
  .bd { height: ${CONTENT_H}mm; overflow: visible; }
  .ft { position: absolute; left: ${MARGIN.left}mm; right: ${MARGIN.right}mm; bottom: 7mm;
        font-size: 8pt; color: #333; border-top: 0.6pt solid #000; padding-top: 1.2mm;
        display: flex; justify-content: space-between; }
</style></head><body>${body}</body></html>`;
}

// ---------------------------------------------------------------- 打 PDF
//
// 用 **CDP 的 Page.printToPDF**，而不是 `chrome --print-to-pdf`：
// 命令行那条路给不了 header/footer 模板（只能开 Chrome 自带的，它会印上 file:// 路径），
// 而"每页页眉带软件名称与版本号、右上角页码"正是登记材料的要求。
// Node 22 自带 fetch 与 WebSocket，所以这一步仍然是零依赖。

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** 起一个 headless Chrome、连上 CDP，把 send 交给 fn；结束负责收摊 */
async function withCdp(htmlPath, fn) {
  const port = 9333;
  const profile = mkdtempSync(join(tmpdir(), 'lianleme-pdf-'));
  const chrome = spawn(CHROME, [
    '--headless=new', '--disable-gpu', '--no-sandbox', '--no-first-run',
    `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, 'about:blank',
  ], { stdio: 'ignore' });

  try {
    for (let i = 0; i < 80; i++) {
      try { await fetch(`http://127.0.0.1:${port}/json/version`); break; }
      catch { await sleep(150); }
    }
    const url = `file://${htmlPath}`;
    const target = await (await fetch(
      `http://127.0.0.1:${port}/json/new?${encodeURIComponent(url)}`, { method: 'PUT' },
    )).json();

    const ws = new WebSocket(target.webSocketDebuggerUrl);
    let seq = 0;
    const pending = new Map();
    let onLoad;
    const loaded = new Promise((resolve) => { onLoad = resolve; });

    ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(ev.data);
      if (msg.method === 'Page.loadEventFired') onLoad();
      if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg.result); pending.delete(msg.id); }
    });
    await new Promise((resolve) => ws.addEventListener('open', resolve, { once: true }));

    const send = (method, params = {}) => new Promise((resolve) => {
      const id = ++seq;
      pending.set(id, resolve);
      ws.send(JSON.stringify({ id, method, params }));
    });

    await send('Page.enable');
    await send('Runtime.enable');
    await Promise.race([loaded, sleep(5000)]);
    await sleep(400); // 让字体与图片落定

    const out = await fn(send);
    ws.close();
    return out;
  } finally {
    chrome.kill();
    // Chrome 收摊要一点时间：直接 rm 会 ENOTEMPTY（它还在写 profile）。
    // 删不掉也不该让整个工具失败 —— 那只是临时目录。
    try { rmSync(profile, { recursive: true, force: true, maxRetries: 8, retryDelay: 120 }); }
    catch { /* 留给系统清理 tmp */ }
  }
}

/** 量出每个顶层块的位置/高度/外边距，并把它的 HTML 一起带回来 */
async function measureBlocks(htmlPath) {
  const expr = `JSON.stringify([...document.querySelectorAll('#m > *')].map((e) => {
    const s = getComputedStyle(e);
    return { html: e.outerHTML, h: e.offsetHeight,
             mt: parseFloat(s.marginTop) || 0, mb: parseFloat(s.marginBottom) || 0 };
  }))`;
  return withCdp(htmlPath, async (send) => {
    const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true });
    return JSON.parse(r.result.value);
  });
}

async function printPdf(htmlPath, pdfPath, opts = {}) {
  return withCdp(htmlPath, async (send) => {
    const { data } = await send('Page.printToPDF', {
      printBackground: true, preferCSSPageSize: true, displayHeaderFooter: false, ...opts,
    });
    writeFileSync(pdfPath, Buffer.from(data, 'base64'));
    return pdfPath;
  });
}

/** PDF 页数：直接数 `/Type /Page` 对象（零依赖，够用） */
function pdfPages(p) {
  const buf = readFileSync(p, 'latin1');
  return (buf.match(/\/Type\s*\/Page[^s]/g) ?? []).length;
}

function a4Check(p) {
  const buf = readFileSync(p, 'latin1');
  // A4 = 595.28 × 841.89 pt；允许 1pt 误差
  const m = buf.match(/\/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]/);
  if (!m) return '找不到 MediaBox';
  const [, w, h] = m;
  const ok = Math.abs(Number(w) - 595.28) < 1.5 && Math.abs(Number(h) - 841.89) < 1.5;
  return `${w} × ${h} pt ${ok ? '✓ A4 纵向' : '✗ 不是 A4'}`;
}

// ---------------------------------------------------------------- 文档数字防漂
//
// 说明书与申请表里都写了「N 个源文件 / M 行」。这两个数字**加一个文件就会变**，
// 而它们是要填进申请表、并且与鉴别材料一起交上去的 —— 写错了就是材料不一致。
// 2026-09-30 就是这么发现的：加完本工具自己之后，文档里还写着 106 / 26,658，
// 实际已经是 108 / 26,910。所以把它变成一条能跑的命令。
const DOCS = ['docs/copyright-manual.md', 'docs/copyright-application.md'];
const NUM_RE = /(\d+) 个源文件 \/ ([\d,]+) 行/g;
const AS_OF_RE = /截至 V(\d+\.\d+\.\d+)/g;

// 说明书里还有两个数字会跟着代码漂：**软件版本**与**数据库模式版本**。
// 2026-09-30 就抓过一次：说明书正文写着 V1.17.0 / 模式 v9，而仓库已经是 V1.23.0 / v10 ——
// 源程序量那条有守卫，这两条没有，于是它们悄悄烂了。
// 它们是提交材料，写错就是"材料与实际不符"。所以一起钉住，真源分别是
// app/lib/core/app_info.dart 与 app/lib/data/db.dart。
const MANUAL = 'docs/copyright-manual.md';
const VERSION_RE = /\*\*版本\*\*：V?(\d+\.\d+\.\d+)/;
const SCHEMA_RE = /当前模式版本 \*\*v(\d+)\*\*/;

function checkManualNumbers(appVersion, schemaVersion) {
  const problems = [];
  const text = readFileSync(join(ROOT, MANUAL), 'utf8');

  const v = text.match(VERSION_RE);
  if (!v) {
    problems.push(`${MANUAL}：找不到「**版本**：Vx.y.z」（措辞变了？检查要跟着改）`);
  } else if (v[1] !== appVersion) {
    problems.push(`${MANUAL}：写的是版本 V${v[1]}，实际是 V${appVersion}`);
  }

  // ⚠️ **申请表**用的是另一种写法（`| 版本号 | **V1.2.3** |`），而第一版的守卫只认
  // 说明书那句 `**版本**：Vx.y.z` —— 于是申请表里的版本号从 V1.17.0 一路烂到 V1.25.1
  // 都没人发现（2026-09-30 才翻出来）。守卫必须把两份材料的**各自措辞**都覆盖。
  const APP_DOC = 'docs/copyright-application.md';
  const appText = readFileSync(join(ROOT, APP_DOC), 'utf8');
  const av = appText.match(/\|\s*版本号\s*\|\s*\*\*V?(\d+\.\d+\.\d+)\*\*/);
  if (!av) {
    problems.push(`${APP_DOC}：找不到「| 版本号 | **Vx.y.z** |」（措辞变了？检查要跟着改）`);
  } else if (av[1] !== appVersion) {
    problems.push(`${APP_DOC}：写的是版本 V${av[1]}，实际是 V${appVersion}`);
  }

  const sc = text.match(SCHEMA_RE);
  if (!sc) {
    problems.push(`${MANUAL}：找不到「当前模式版本 **vN**」（措辞变了？检查要跟着改）`);
  } else if (Number(sc[1]) !== schemaVersion) {
    problems.push(`${MANUAL}：写的是模式版本 v${sc[1]}，实际是 v${schemaVersion}`);
  }

  return problems;
}

/** db.dart 里的 schemaVersion 就是事实（drift 的迁移版本号） */
function schemaVersionFromDb() {
  const src = readFileSync(join(ROOT, 'app/lib/data/db.dart'), 'utf8');
  const m = src.match(/int get schemaVersion => (\d+);/);
  if (!m) throw new Error('app/lib/data/db.dart 里找不到 schemaVersion');
  return Number(m[1]);
}

function checkDocNumbers(fileCount, lineCount, appVersion) {
  const problems = [];
  for (const rel of DOCS) {
    const text = readFileSync(join(ROOT, rel), 'utf8');
    const hits = [...text.matchAll(NUM_RE)];
    if (!hits.length) {
      problems.push(`${rel}：找不到「N 个源文件 / M 行」（措辞变了？检查要跟着改）`);
      continue;
    }
    for (const m of hits) {
      const [, n, l] = m;
      if (Number(n) !== fileCount || Number(l.replace(/,/g, '')) !== lineCount) {
        problems.push(`${rel}：写的是 ${n} 个源文件 / ${l} 行，实际是 ${fileCount} / ${lineCount}`);
      }
    }
    // 「（截至 Vx.y.z）」这枚印章单独钉住：切一个版本如果只改 app_info.dart，
    // **行数一个字都不变**，上面那条源程序量守卫不会红 —— 印章就会悄悄烂掉。
    // 2026-09-30 就是这么发现的：两处都还写着「截至 V1.23.0」，而仓库已是 V1.27.0。
    const asOf = [...text.matchAll(AS_OF_RE)];
    if (!asOf.length) {
      problems.push(`${rel}：找不到「截至 Vx.y.z」（措辞变了？检查要跟着改）`);
    }
    for (const m of asOf) {
      if (m[1] !== appVersion) {
        problems.push(`${rel}：源程序量写的是「截至 V${m[1]}」，实际是 V${appVersion}`);
      }
    }
  }
  return problems;
}

// `release-checklist` 的「终局核验」表里还抄了一份**带页数**的：
// `182 个源文件 / 49,027 行 / 全文 981 页`。上面那条守卫只认「N 个源文件 / M 行」，
// **页数不在它的射程里** —— 2026-10-04 就是这么发现的：页数从 979 变成 981（源码多了、
// 每页 50 行，于是多出两页），行数那条当场红了，页数却没人看。
// 页数会变、且它是**要填进申请表**的数字，所以一并钉住；真源就是 PDF 本身（数页对象，
// 零依赖），不是谁记在文档里的旧值。
const CHECKLIST = 'docs/release-checklist.md';
// ⚠️ 措辞与说明书那边**不一样**：这里是「N 个文件 / M 行 / 全文 P 页」（没有"源"字），
// 说明书是「N 个源文件 / M 行」。第一版守卫照抄了说明书那套措辞，于是对 checklist 永远
// 匹配不上、直接报"找不到" —— 两种措辞都得认。
const FULL_RE = /(\d+) 个(?:源)?文件 \/ ([\d,]+) 行 \/ 全文 ([\d,]+) 页/g;
/**
 * **同一批数字的另一种措辞**：「源程序 283 文件 / 77,332 行 / 1547 页」
 * （`release-checklist` 里 `dist/` 内容那一行就是这么写的）。
 *
 * ⚠️ 为什么补这一条：原来只认「N 个源文件 / M 行 / 全文 P 页」那一种写法，
 * 于是 dist 那一行**漂了两轮都没人发现**（2026-10-06 一次改名时它正写着 77,215 —— 差两行）。
 * 一个只认一种措辞的守卫，等于给另一种措辞开了后门。
 */
const ALT_RE = /源程序\s+([\d,]+)\s+文件\s*\/\s*([\d,]+)\s+行\s*\/\s*([\d,]+)\s+页/g;

/** 纯函数版（自检用）：文本进、问题出，不碰磁盘。 */
function checkChecklistText(text, fileCount, lineCount, totalPages) {
  const problems = [];
  const hits = [...text.matchAll(FULL_RE)];
  const altHits = [...text.matchAll(ALT_RE)];
  // ⚠️ 「找不到」的判据要**两种措辞一起看**：只认第一种的话，一段只有第二种写法的文本
  // 会被报成"找不到"（自检当场抓到了这个：假数据只写了 dist 那一行）。
  if (!hits.length && !altHits.length) {
    problems.push(`${CHECKLIST}：找不到「N 个文件 / M 行 / 全文 P 页」（措辞变了？检查要跟着改）`);
    return problems;
  }
  for (const m of hits) {
    const [, n, l, p] = m;
    if (Number(n) !== fileCount || Number(l.replace(/,/g, '')) !== lineCount) {
      problems.push(`${CHECKLIST}：写的是 ${n} 个文件 / ${l} 行，实际是 ${fileCount} / ${lineCount}`);
    }
    // ⚠️ 「全文 P 页」**不能**去数 dist 里那份 PDF：那是提交用的「前 30 + 后 30」= 60 页的
    // 鉴别材料，不是全文。全文页数是排版算出来的（每页 50 行 → ceil(行数/50)），
    // 真源就是上面那两行（行数 ÷ 每页 50 行）。第一版守卫数了 PDF、于是把 981 判成"实际 60 页"。
    if (Number(p.replace(/,/g, '')) !== totalPages) {
      problems.push(`${CHECKLIST}：写的是源程序"全文 ${p} 页"，实际是 ${totalPages} 页`
        + `（= ${lineCount} 行 ÷ 每页 ${PER_PAGE} 行；申请表与鉴别材料要跟着改）`);
    }
  }
  // 另一种措辞（`dist/` 内容那一行）；命中 0 条不算问题 —— 那一行可能被改写掉
  for (const m of altHits) {
    const [, n, l, p] = m;
    if (Number(n.replace(/,/g, '')) !== fileCount || Number(l.replace(/,/g, '')) !== lineCount
      || Number(p.replace(/,/g, '')) !== totalPages) {
      problems.push(`${CHECKLIST}：另一种措辞那一行写的是 ${n} 文件 / ${l} 行 / ${p} 页，`
        + `实际是 ${fileCount} / ${lineCount} / ${totalPages}`);
    }
  }
  return problems;
}

function checkChecklistNumbers(fileCount, lineCount, totalPages) {
  return checkChecklistText(readFileSync(join(ROOT, CHECKLIST), 'utf8'), fileCount, lineCount, totalPages);
}

// ---------------------------------------------------------------- 自检
//
// 为什么这条守卫也要自检：它盯的三个数字（文件数 / 行数 / 页数）**都是"加几行代码就会变"**的，
// 而它自己很容易变成"永远绿的摆设" —— 第一版就是这么写的：页数去数提交用的那份 60 页 PDF，
// 于是正的、反的都报"实际是 60 页"。自检把四种漂法各造一份，验它真的抓得住。
// `--selftest` 不碰磁盘（纯函数进、纯函数出），所以它能在干净克隆上跑。
if (argv.includes('--selftest')) {
  let failed = 0;
  const ok = (name, cond) => { if (!cond) { failed++; console.log(`✗ ${name}`); } };
  const row = (n, l, p) => `| 软著材料 | 源程序 **${n} 个文件 / ${l} 行 / 全文 ${p} 页** |`;
  const F = 3, L = 1234, P = 25;             // ⚠️ 自检用的**假数据**，不是仓库真值（真值由门禁每次实测）

  ok('对得上时不出问题', checkChecklistText(row(F, '1,234', P), F, L, P).length === 0);
  const pag = checkChecklistText(row(F, '1,234', '24'), F, L, P);
  ok('页数漂了要抓住', pag.length === 1 && /全文 24 页.*实际是 25 页/.test(pag[0]));
  const lin = checkChecklistText(row(F, '9,999', P), F, L, P);
  ok('行数漂了要抓住', lin.length === 1 && /实际是 3 \/ 1234/.test(lin[0]));
  const fil = checkChecklistText(row('9', '1,234', P), F, L, P);
  ok('文件数漂了要抓住', fil.length === 1 && /写的是 9 个文件/.test(fil[0]));
  // 另一种措辞（dist 内容那一行）也必须有自检 —— 这条正是被漏掉过的那种
  const altOk = checkChecklistText(`| \`dist/\` 内容 | 源程序 ${F} 文件 / 1,234 行 / ${P} 页 |`, F, L, P);
  ok('另一种措辞对得上时不出问题', altOk.length === 0);
  const altBad = checkChecklistText(`| \`dist/\` 内容 | 源程序 ${F} 文件 / 9,999 行 / ${P} 页 |`, F, L, P);
  ok('另一种措辞漂了要抓住', altBad.length === 1 && /另一种措辞/.test(altBad[0]));
  const miss = checkChecklistText('这一行被改写过了', F, L, P);
  ok('措辞变了要报"找不到"', miss.length === 1 && /找不到/.test(miss[0]));

  if (failed) { console.log(`✗ 软著文档数字守卫自检：${failed} 条不过`); process.exit(1); }
  console.log('✓ 软著文档数字守卫自检 7 条通过（文件数 / 行数 / 页数 / 两种措辞 / 措辞改写）');
  process.exit(0);
}

// ---------------------------------------------------------------- 跑
mkdirSync(OUT, { recursive: true });
console.log(`软著鉴别材料 PDF　${APP_NAME} V${APP_VERSION}　著作权人：${ownerText}\n`);

const src = sourceHtml();

/**
 * `dist/copyright/` 里**不该留着旧版本的 PDF**。
 *
 * 为什么单独看一眼：软著提交材料是**从 dist/ 里拿的**，而那是生成物、不进仓库。
 * 切版重出之后，上一版那份还躺在同一个目录里（2026-09-30 就真的捞出来过 V1.28.0 与
 * V1.31.0 两份）—— 提交时随手挑一个，就可能把**旧版本**的材料交上去，
 * 而页眉的版本号与申请表里填的对不上。这条不检查"文件内容对不对"，只检查
 * **"目录里有没有不该在的版本"**：它存在的意义就是防止拿错。
 *
 * 目录不存在（例如干净克隆上）时跳过 —— dist/ 是 .gitignore 的。
 */
/**
 * 生成完之后**自动清掉旧版本**。
 *
 * 为什么由工具来做而不是让人记得删：这个目录是**它自己拥有**的产物目录，而"留着上一版"
 * 已经在 2026-09-30 让提交材料差一点拿错（当时目录里躺着 V1.28.0 与 V1.31.0 两份）。
 * 切版时生成新版 + 删旧版应当是**同一个动作**，否则迟早会忘 —— 忘了的代价是把旧版本的
 * 材料交上去（页眉的版本号与申请表对不上）。
 */
function pruneStaleDist() {
  if (!existsSync(OUT)) return [];
  const current = `V${APP_VERSION}`;
  const removed = [];
  for (const f of readdirSync(OUT)) {
    if (/V\d+\.\d+\.\d+/.test(f) && !f.includes(current)) {
      rmSync(join(OUT, f));
      removed.push(f);
    }
  }
  return removed;
}

/** 只查不删（`--check-docs` 用）：文档守卫不该有副作用。 */
function checkStaleDist() {
  const problems = [];
  if (!existsSync(OUT)) return problems;
  const current = `V${APP_VERSION}`;
  const stale = readdirSync(OUT)
    .filter((f) => /V\d+\.\d+\.\d+/.test(f) && !f.includes(current));
  for (const f of stale) {
    const v = f.match(/V\d+\.\d+\.\d+/)[0];
    problems.push(`dist/copyright/${f}：版本 ${v} 不是当前版本（${current}）—— `
      + '提交材料是从这个目录拿的，留着旧的就有"拿错一份"的风险，重跑一次本工具会自动清掉');
  }
  return problems;
}

if (argv.includes('--check-docs')) {
  const problems = [
    ...checkDocNumbers(src.fileCount, src.lineCount, APP_VERSION),
    ...checkChecklistNumbers(src.fileCount, src.lineCount, src.totalPages),
    ...checkManualNumbers(APP_VERSION, schemaVersionFromDb()),
    ...checkStaleDist(),
  ];
  console.log(`实际：${src.fileCount} 个源文件 / ${src.lineCount} 行`);
  console.log(`     版本 V${APP_VERSION} · 数据库模式 v${schemaVersionFromDb()}`);
  if (problems.length) { for (const p of problems) console.log(`✗ ${p}`); process.exit(1); }
  console.log('✓ 说明书/申请表/release-checklist 里的源程序量与实际一致，dist/copyright 里没有旧版本残留');
  process.exit(0);
}

const pruned = pruneStaleDist();
if (pruned.length) {
  console.log(`  已清掉旧版本产物 ${pruned.length} 个：${pruned.join('、')}`);
}

if (!owner) {
  console.log('⚠️  没有给 --owner（著作权人）。页脚会留占位文字 —— 正式提交前请补：');
  console.log('      node tool/copyright-pdf.mjs --owner "你的姓名"\n');
}

const srcPdf = join(OUT, `${APP_NAME}-源程序-V${APP_VERSION}.pdf`);
// 源程序用**自己的每页 div**（每页 50 行、页码是真实页码）
await printPdf(writeHtml(src.html, srcPdf), srcPdf);
const srcPages = pdfPages(srcPdf);
console.log(`源程序：${src.fileCount} 个文件 / ${src.lineCount} 行 / 共 ${src.totalPages} 页`);
console.log(`  提交前 ${FRONT} 页 + 后 ${BACK} 页 → 期望 ${src.pageCount} 页，实际 ${srcPages} 页`
  + `　${srcPages === src.pageCount ? '✓' : '✗'}`);
console.log(`  ${a4Check(srcPdf)}　${(statSync(srcPdf).size / 1024).toFixed(0)} KB`);
console.log(`  ${relative(ROOT, srcPdf)}`);

const manPdf = join(OUT, `${APP_NAME}-软件说明书-V${APP_VERSION}.pdf`);
// 先量后切：把文档渲染进浏览器量出块高，再切成显式页并盖真实页码
const blocks = await measureBlocks(writeHtml(manualMeasureHtml(), join(OUT, 'measure.html')));
await printPdf(writeHtml(manualFromBlocks(blocks), manPdf), manPdf);
console.log(`\n说明书：`);
console.log(`  ${pdfPages(manPdf)} 页　${a4Check(manPdf)}　${(statSync(manPdf).size / 1024).toFixed(0)} KB`);
console.log(`  ${relative(ROOT, manPdf)}`);

if (src.skipped.size) {
  console.log('\n已排除：' + [...src.skipped.entries()].map(([k, v]) => `${k}×${v}`).join('　'));
}
console.log('\n⚠️ dist/ 已 gitignore：PDF 是源码与说明书的副本，不要提交进仓库。');
console.log('⚠️ 页眉里的版本号必须与申请表填的一致 —— 两处都来自 app/lib/core/app_info.dart。');
