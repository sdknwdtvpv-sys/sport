/// 练了么 · 极简 Markdown 渲染器（够用就行）
///
/// **为什么自己写**：仓库里 tool/ 全是零依赖，不为了一份文档去装 markdown 库；
/// 而这些文档用到的语法就那么几种（标题 / 表格 / 列表 / 引用 / 围栏代码 /
/// 行内粗体与代码 / 段落），数得清。
///
/// 2026-09-30 从 `gen-privacy-page.mjs` 抽出来共用：隐私政策页与软著说明书都要渲染，
/// 两份各写一遍早晚会不一致。抽出来后隐私页的防漂检查（`--check`）立刻验证了
/// "抽得一模一样" —— 生成物字节没变。
// ── 行内元素 ────────────────────────────────────────────────────────────
export const esc = (s) => s
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;');

export function inline(s) {
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

export function renderMarkdown(md) {
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
      out.push(`<blockquote>${renderMarkdown(buf.join('\n'))}</blockquote>\n`);
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
