#!/usr/bin/env node
/**
 * 练了么 · 软件著作权登记用的**源代码文档导出**
 *
 * **它解决什么**：软著申请要交"源代码前后各 30 页"（每页 50 行，页眉带软件名称与版本）。
 * 手工拼 60 页是纯粹的机械劳动，而且**每次改代码都会过期** —— 所以做成一条命令：
 *
 *   node tool/copyright-export.mjs                 # 导出到 dist/copyright/
 *   node tool/copyright-export.mjs --lines 50      # 每页行数（默认 50）
 *   node tool/copyright-export.mjs --check         # 只算统计，不写文件
 *
 * 约定与取舍（都是可复核的，不藏在代码里）：
 *   * **收录**：我们自己的源码（Dart / JS / Python）。**排除**生成物（`*.g.dart`、`exercises.json/sql`）、
 *     资源、种子数据 JSON、以及任何第三方依赖 —— 软著登记的是**我们写的**程序
 *   * **顺序**：按路径字典序。不是为了"最好看"，而是为了**可复现**：
 *     同一份代码每次导出的页码必须一样（审查会看前后页是否衔接）
 *   * **页码**：前 30 页编 1–30；后 30 页接着总页数往上编（第 N-29 … N 页），
 *     两段之间有一行分隔说明 —— 中间那几百页按惯例不交
 *   * 输出目录 `dist/` 已 gitignore：**不要把导出结果提交进仓库**
 *     （它是源码的副本，提交等于同一份代码存两遍）
 *
 * 需要交 PDF 时：用任一编辑器打开这两个 txt 转 PDF 即可（行宽已限制在 80 列内，
 * 用等宽字体 A4 竖排刚好一页 50 行）。
 */

import { readdirSync, readFileSync, mkdirSync, writeFileSync, statSync } from 'node:fs';
import { dirname, join, relative, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const APP_VERSION = readFileSync(join(ROOT, 'app/lib/core/app_info.dart'), 'utf8')
  .match(/kAppVersion = '([^']+)'/)?.[1] ?? '0.0.0';

/** 收录我们自己的源码目录（按路径字典序，可复现） */
const INCLUDE_DIRS = ['app/lib', 'app/test', 'app/tool', 'engine', 'server', 'tool', 'seed'];

/** 明确排除：生成物、资源、数据 */
function excluded(rel) {
  if (rel.endsWith('.g.dart')) return '生成物（drift）';
  if (rel.endsWith('.json') || rel.endsWith('.sql')) return '数据/产物';
  if (rel.startsWith('seed/parts/')) return '种子数据';
  if (rel.includes('/build/') || rel.startsWith('dist/')) return '构建产物';
  return null;
}

function collect() {
  const files = [];
  const skipped = new Map();
  const walk = (abs) => {
    for (const name of readdirSync(abs).sort()) {
      const p = join(abs, name);
      const rel = relative(ROOT, p);
      if (statSync(p).isDirectory()) { walk(p); continue; }
      const ext = extname(name);
      // .py 也收：tool/gen-icons.py 是我们自己写的程序的一部分。
      // （2026-09-30 之前只收 .dart/.mjs，于是它既在仓库里、又不在软著材料里。）
      if (ext !== '.dart' && ext !== '.mjs' && ext !== '.py') continue;
      const why = excluded(rel);
      if (why) { skipped.set(why, (skipped.get(why) ?? 0) + 1); continue; }
      files.push(rel);
    }
  };
  for (const d of INCLUDE_DIRS) walk(join(ROOT, d));
  // app/lib/core/app_info.dart 等都在 app/lib 里；app/tool 是纯 Dart 校验脚本
  return { files: files.sort(), skipped };
}

/** 把源文件摊成"行流"，每行前面带 `文件:行号` 便于审查时定位 */
function lineStream(files) {
  const out = [];
  for (const rel of files) {
    out.push(`// ===== ${rel} =====`);
    const lines = readFileSync(join(ROOT, rel), 'utf8').replace(/\t/g, '    ').split('\n');
    lines.forEach((l, i) => out.push(`${String(i + 1).padStart(4, ' ')}| ${l}`));
    out.push('');
  }
  return out;
}

const argv = process.argv.slice(2);
const argOf = (n, d) => {
  const i = argv.indexOf(n);
  return i >= 0 && argv[i + 1] ? Number(argv[i + 1]) : d;
};
const PER_PAGE = argOf('--lines', 50);
const FRONT = argOf('--front', 30);
const BACK = argOf('--back', 30);
const checkOnly = argv.includes('--check');

const { files, skipped } = collect();
const lines = lineStream(files);
const totalPages = Math.ceil(lines.length / PER_PAGE);

const header = (pageNo) =>
  `练了么 V${APP_VERSION}   源代码   第 ${String(pageNo).padStart(4, ' ')} 页 / 共 ${totalPages} 页`;
const page = (slice, pageNo) =>
  [header(pageNo), '', ...slice, '\f'].join('\n');

const frontPages = [];
for (let i = 0; i < FRONT && i < totalPages; i++) {
  frontPages.push(page(lines.slice(i * PER_PAGE, (i + 1) * PER_PAGE), i + 1));
}
const backPages = [];
for (let i = Math.max(0, totalPages - BACK); i < totalPages; i++) {
  backPages.push(page(lines.slice(i * PER_PAGE, (i + 1) * PER_PAGE), i + 1));
}

const divider = [
  '',
  '='.repeat(78),
  `【中间省略 ${Math.max(0, totalPages - FRONT - BACK)} 页】`,
  '按《计算机软件著作权登记办法》的惯例提交：源代码前 30 页 + 后 30 页。',
  `完整源代码见仓库（共 ${files.length} 个源文件 / ${lines.length} 行）。`,
  '='.repeat(78),
  '',
].join('\n');

const doc = frontPages.join('\n') + divider + backPages.join('\n');

console.log('软著源代码导出');
console.log(`  版本 V${APP_VERSION}　源文件 ${files.length} 个　${lines.length} 行　`
  + `每页 ${PER_PAGE} 行 → 共 ${totalPages} 页`);
console.log(`  本次导出：前 ${frontPages.length} 页 + 后 ${backPages.length} 页`);
if (skipped.size) {
  console.log('  已排除：' + [...skipped.entries()].map(([k, v]) => `${k}×${v}`).join('　'));
}

if (checkOnly) process.exit(0);

const outDir = join(ROOT, 'dist/copyright');
mkdirSync(outDir, { recursive: true });
const outFile = join(outDir, `练了么-源代码-V${APP_VERSION}.txt`);
writeFileSync(outFile, doc, 'utf8');
console.log(`\n✓ 已写入 ${relative(ROOT, outFile)}`);
console.log('  转 PDF：用编辑器打开 → 等宽字体、A4 竖排 → 导出 PDF');
console.log('  ⚠️ dist/ 已 gitignore：不要把导出结果提交进仓库（那是源码的副本）');
