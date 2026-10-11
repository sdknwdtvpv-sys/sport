#!/usr/bin/env node
/**
 * 练了么 · RepDB 动作插图 vendoring（**只在需要重新生成时手工跑**，不进 CI）
 *
 *   用法：
 *     node tool/vendor-repdb-art.mjs            # 生成/更新 app/assets/repdb-art/ 与 repdb-art.json
 *     node tool/vendor-repdb-art.mjs --check    # 只核对，不写任何文件（门禁走这一条）
 *
 * ## 它做什么
 *
 *   1. 读 `tool/repdb-art-map.tsv`（**唯一真源**，人工维护的"我们的动作 → RepDB 动作"对应表）；
 *   2. 按许可证**逐条核对**（见下），任何一条不成立就整体失败、不写文件；
 *   3. 把匹配到的 RepDB 免费档静图（512×512 WebP）缩到 320×320、质量 82，
 *      落到 `app/assets/repdb-art/`；
 *   4. 写 `app/assets/repdb-art.json`（清单：动作 id → 图片路径 + 出处 + 许可信息）；
 *   5. 把许可原文抄一份到 `tool/repdb-license.txt`（署名义务的凭据，必须随仓库走）。
 *
 * ## 许可证是这个工具的"第 0 步"，不是免责声明
 *
 * RepDB 免费档允许商用**应用内**使用，代价是三条我们承担得起的义务 + 三条禁令：
 *   * 义务：署名（"Exercise data by RepDB (repdb.co)"，可见链接）；
 *   * 义务：只随端分发，**不得**作为数据集/API 再分发（第 3 条）→ 我们不做导出图库；
 *   * 义务：保留许可与出处记录（本文件 + `tool/repdb-license.txt`）；
 *   * 禁令：不得作为生成式模型的输入/参考/训练素材（第 5 条）；
 *   * 禁令：付费档预览（`premium-samples/`）**仅限评估**，不得进生产（第 6 条）；
 *   * 禁令：不得把图当自己的作品（署名不可去）。
 *
 * ## 依赖
 *
 *   * Node 18+（`--check` 只用 Node）；
 *   * **重新生成**时还要 Python 3 + Pillow（用来缩放/重编码 WebP）。
 *     本机（macOS）已装：`python3 -c "import PIL"`。CI **不跑生成**，只跑 `--check`，
 *     所以 CI 不需要 Pillow —— 这条是刻意的：门禁不该要求一个跟构建无关的依赖
 *     （踩过一次坑：`check-launch-relay.py` 要 Pillow，CI 上直接红）。
 *   * 重新生成时还要能拿到 RepDB 的图：优先用 `--src=<本地已解压的仓库目录>`，
 *     否则回落到 `https://raw.githubusercontent.com/RepDB/exercise-dataset/main/`
 *     （逐个 curl 下载，慢，但只在生成时才发生）。
 */
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const MAP_PATH = join(ROOT, 'tool', 'repdb-art-map.tsv');
const LICENSE_PATH = join(ROOT, 'tool', 'repdb-license.txt');
const OUT_DIR = join(ROOT, 'app', 'assets', 'repdb-art');
const MANIFEST_PATH = join(ROOT, 'app', 'assets', 'repdb-art.json');
const SEED_PATH = join(ROOT, 'app', 'assets', 'exercises.json');

/** 输出尺寸。**320 而不是 512**：详情页最大也就画到 ~160pt，320 在 2× 屏上正合适，
 *  而把 1126 张原图整包塞进去是 21MB —— 那是"免费送一个图库"，不是"加几张插图"。*/
const TARGET_PX = 320;
const QUALITY = 82;
/** 整包预算（见 README/文档里引用的数字）。超了就说明有人往里塞了不该塞的东西。 */
const BUDGET_BYTES = 6 * 1024 * 1024;
/** RepDB 免费档的署名文本，**逐字**。改之前先读 tool/repdb-license.txt。 */
const ATTRIBUTION = 'Exercise data by RepDB (repdb.co)';
const REPO_RAW = 'https://raw.githubusercontent.com/RepDB/exercise-dataset/main';
const REPO_URL = 'https://github.com/RepDB/exercise-dataset';

const args = process.argv.slice(2);
const CHECK = args.includes('--check');
const SRC = (args.find((a) => a.startsWith('--src=')) ?? '').slice(6) || null;

// ---------------------------------------------------------------- 读映射表

/** 解析 `tool/repdb-art-map.tsv`。`#` 开头的行是注释。 */
function readMap() {
  const text = readFileSync(MAP_PATH, 'utf8');
  const rows = [];
  const problems = [];
  for (const [i, raw] of text.split('\n').entries()) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const cols = raw.split('\t');
    if (cols.length < 3) {
      problems.push(`第 ${i + 1} 行：字段少于 3 个（要用 TAB 分隔）`);
      continue;
    }
    const [our, rep, src, ...rest] = cols;
    if (!/^ex_[a-z0-9_]+$/.test(our)) problems.push(`第 ${i + 1} 行：our_id「${our}」不像我们的动作 id`);
    if (!/^[a-z0-9-]+$/.test(rep)) problems.push(`第 ${i + 1} 行：repdb_id「${rep}」格式不对`);
    if (!['exact', 'auto', 'review'].includes(src)) {
      problems.push(`第 ${i + 1} 行：来源「${src}」必须是 exact / auto / review 之一`);
    }
    const note = rest.join('\t').trim();
    if (!note) problems.push(`第 ${i + 1} 行（${our}）：备注不能为空 —— 写清楚为什么这两条是同一个动作`);
    rows.push({ our, rep, src, note, line: i + 1 });
  }
  return { rows, problems };
}

/** 读我们的动作库（校验 our_id 真的存在） */
function readOurIds() {
  const data = JSON.parse(readFileSync(SEED_PATH, 'utf8'));
  return new Set((data.exercises ?? []).map((e) => e.id));
}

/** RepDB 的动作库：`--src` 给的是本地仓库/解压目录，否则读下载好的副本。
 *
 *  两种分发形状都要认（它们的 `images.flat` 结构**不一样**）：
 *    * GitHub 仓库 `exercises.json` —— `images.flat` 是 `{start, peak}` 或 `{main}`，
 *      值是仓库相对路径（如 `images/flat/<id>-peak.webp`）；
 *    * 官网下载的 ZIP `free.json` —— `images.flat` 是数组 `["start","peak"]`，
 *      文件名要自己按 `<id>-<pose>.webp` 拼（1126/1126 条都符合这个规律，已核对）。
 *  统一成 `{start?, peak?, main?}`，值是"源目录里的相对路径"。 */
function readRepdbIndex() {
  const roots = [];
  if (SRC) roots.push(SRC);
  for (const root of roots) {
    for (const file of ['free.json', 'exercises.json']) {
      const p = join(root, file);
      if (!existsSync(p)) continue;
      const d = JSON.parse(readFileSync(p, 'utf8'));
      const map = new Map();
      // ⚠️ 快照日期**不写生成时刻**：它要的是"这批图是从 RepDB 哪一天的快照来的"
      // （README 里写了 Free Tier 的计数核对日期是 2026-10-08），
      // 不是"我这个脚本哪一秒跑的"——后者会让清单每次都不一样，破坏可复现。
      map.snapshot = (d.generated_at ?? '').slice(0, 10) || null;
      for (const e of d.exercises ?? []) {
        const flat = e.images?.flat;
        const poses = {};
        if (Array.isArray(flat)) {
          for (const pose of flat) poses[pose] = `images/flat/${e.id}-${pose}.webp`;
        } else if (flat && typeof flat === 'object') {
          for (const k of ['start', 'peak', 'main']) if (flat[k]) poses[k] = String(flat[k]);
        }
        map.set(e.id, { ...e, poses });
      }
      return map;
    }
  }
  return null;
}

// ---------------------------------------------------------------- 校验（许可证逐条）

function validate(rows, ourIds, repdb, problems) {
  // 1. our_id 存在且唯一
  const seenOur = new Map();
  for (const r of rows) {
    if (!ourIds.has(r.our)) problems.push(`映射表里的「${r.our}」在 app/assets/exercises.json 里不存在`);
    if (seenOur.has(r.our)) problems.push(`「${r.our}」在映射表里出现了两次（第 ${seenOur.get(r.our)} 行与第 ${r.line} 行）`);
    seenOur.set(r.our, r.line);
  }
  // 2. repdb_id 存在且唯一 —— 一张图配两个动作，必然有一边是错的
  const seenRep = new Map();
  for (const r of rows) {
    if (repdb && !repdb.has(r.rep)) problems.push(`RepDB 里没有「${r.rep}」（${r.our} 那一行）`);
    if (seenRep.has(r.rep)) {
      problems.push(`RepDB id「${r.rep}」被 ${seenRep.get(r.rep)} 与 ${r.our} 共用 —— `
        + '一张图只能配一个动作，否则其中一个必然显示错的动作');
    }
    seenRep.set(r.rep, r.our);
  }
  // 3. 付费档预览：一个字节都不许进包（许可第 6 条）
  if (existsSync(OUT_DIR)) {
    for (const f of readdirSync(OUT_DIR)) {
      if (/premium|sample/i.test(f)) {
        problems.push(`app/assets/repdb-art/ 里出现了「${f}」—— 付费档预览图是"仅限评估"，不得进包`);
      }
    }
  }
  return { byRep: seenRep };
}

// ---------------------------------------------------------------- 图片

const md5 = (buf) => createHash('md5').update(buf).digest('hex');

/** 图片文件名：`<repdb-id>-<pose>.webp`。pose 是 start / peak / main。 */
const fileNameOf = (repdbId, pose) => `${repdbId}-${pose}.webp`;

/** 素材从哪来：本地仓库目录优先，否则逐个下载。 */
function fetchWebp(relPath) {
  if (SRC) {
    const p = join(SRC, relPath);
    if (!existsSync(p)) throw new Error(`本地仓库里没有 ${relPath}`);
    return readFileSync(p);
  }
  const url = `${REPO_RAW}/${relPath}`;
  const out = execFileSync('curl', ['-sS', '--max-time', '120', '-f', url], { maxBuffer: 64 * 1024 * 1024 });
  if (!out.length) throw new Error(`下载 ${url} 得到 0 字节`);
  return out;
}

/** 用 Pillow 缩到 TARGET_PX 并重编码。写进临时文件再读回来，避免命令行里塞二进制。 */
function shrinkToWebp(inputBuf, outPath) {
  const tmpIn = join('/tmp', `repdb-shrink-${process.pid}-in.webp`);
  writeFileSync(tmpIn, inputBuf);
  const py = `
from PIL import Image
im = Image.open(${JSON.stringify(tmpIn)}).convert('RGB')
im = im.resize((${TARGET_PX}, ${TARGET_PX}), Image.LANCZOS)
im.save(${JSON.stringify(outPath)}, 'WEBP', quality=${QUALITY}, method=6)
`;
  execFileSync('python3', ['-c', py], { stdio: ['ignore', 'inherit', 'pipe'] });
  rmSync(tmpIn, { force: true });
}

/** 读回一张已经生成好的图，拿它的尺寸做核对（只用 zlib 与 Buffer，无第三方依赖）。 */
function webpSize(buf) {
  const fourcc = buf.toString('ascii', 12, 16);
  if (fourcc === 'VP8 ') return { w: buf[26] | (buf[27] << 8), h: buf[28] | (buf[29] << 8), lossless: false };
  if (fourcc === 'VP8L') {
    const bits = buf[21] | (buf[22] << 8) | (buf[23] << 16) | (buf[24] << 24);
    return { w: (bits & 0x3fff) + 1, h: ((bits >> 14) & 0x3fff) + 1, lossless: true };
  }
  return { w: 0, h: 0, lossless: false, fourcc };
}

// ---------------------------------------------------------------- 清单

function buildManifest(rows, artByOur, repdb) {
  const exercises = rows.map((r) => {
    const art = artByOur.get(r.our);
    const p = repdb?.get(r.rep);
    const row = { id: r.our, repdb: r.rep };
    if (art.start) row.start = art.start;
    if (art.peak) row.peak = art.peak;
    if (art.main) row.main = art.main;
    return { row, name: p?.name_en ?? null };
  });
  return {
    schema: 1,
    source: REPO_URL,
    source_snapshot: repdb?.snapshot ?? null,
    license: 'RepDB Free Tier License v1.0（原文副本：tool/repdb-license.txt）',
    attribution: ATTRIBUTION,
    attribution_where: 'app/lib/features/profile/repdb_credits_screen.dart',
    note:
      'RepDB 免费档静图（512px WebP 缩到 320px）。许可：应用内个人与商业用途免费，须署名；'
      + '不得作为数据集/API 再分发；不得作为生成式模型素材；付费档预览图不得使用。'
      + '动作说明文字**不是** RepDB 的，是我们自己写的（RepDB 只有英/德/西）。',
    count: exercises.length,
    exercises: exercises.map(({ row }) => row),
  };
}

// ---------------------------------------------------------------- 主流程

function fail(problems) {
  console.error(`✗ RepDB 插图核对失败，共 ${problems.length} 处：`);
  for (const p of problems) console.error(`  · ${p}`);
  process.exit(1);
}

const { rows, problems } = readMap();
const ourIds = readOurIds();
const repdb = readRepdbIndex();
validate(rows, ourIds, repdb, problems);
if (problems.length) fail(problems);

console.log(`✓ 映射表：${rows.length} 条，字段与唯一性检查通过`);
if (!repdb) console.log('  （没有本地 RepDB 副本，跳过"repdb_id 是否存在"的核对）');

// ---- --check：只核对已提交的产物，不写文件，不需要 Pillow ----

if (CHECK) {
  const checkProblems = [];
  if (!existsSync(MANIFEST_PATH)) {
    checkProblems.push('app/assets/repdb-art.json 不存在 —— 先跑 node tool/vendor-repdb-art.mjs');
  } else {
    const manifest = JSON.parse(readFileSync(MANIFEST_PATH, 'utf8'));
    if (manifest.attribution !== ATTRIBUTION) {
      checkProblems.push(`清单里的署名不是逐字的「${ATTRIBUTION}」`);
    }
    const listed = new Map((manifest.exercises ?? []).map((e) => [e.id, e]));
    if (listed.size !== rows.length) {
      checkProblems.push(`清单里 ${listed.size} 条，映射表 ${rows.length} 条 —— 重新生成（node tool/vendor-repdb-art.mjs）`);
    }
    let total = 0;
    let files = 0;
    for (const r of rows) {
      const e = listed.get(r.our);
      if (!e) {
        checkProblems.push(`映射表里的「${r.our}」不在清单里`);
        continue;
      }
      if (e.repdb !== r.rep) {
        checkProblems.push(`「${r.our}」清单里配的是 ${e.repdb}，映射表写的是 ${r.rep}`);
      }
      const poses = ['start', 'peak', 'main'].filter((k) => e[k]);
      if (poses.length === 0) checkProblems.push(`「${r.our}」在清单里一张图都没有`);
      for (const pose of poses) {
        const rel = e[pose];
        if (!rel.startsWith('assets/repdb-art/')) {
          checkProblems.push(`「${r.our}」的 ${pose} 路径「${rel}」不在 assets/repdb-art/ 下`);
          continue;
        }
        const abs = join(ROOT, 'app', rel);
        if (!existsSync(abs)) {
          checkProblems.push(`图片文件不存在：app/${rel}（${r.our}）`);
          continue;
        }
        const buf = readFileSync(abs);
        total += buf.length;
        files++;
        const { w, h, fourcc } = webpSize(buf);
        if (w !== TARGET_PX || h !== TARGET_PX) {
          checkProblems.push(`app/${rel} 是 ${w}×${h}（fourcc=${fourcc}），应当是 ${TARGET_PX}×${TARGET_PX}`);
        }
      }
    }
    // 目录里不许有清单没引用的图（防止有人手工塞图绕过许可审查）
    if (existsSync(OUT_DIR)) {
      const referenced = new Set();
      for (const e of manifest.exercises ?? []) {
        for (const k of ['start', 'peak', 'main']) {
          if (e[k]) referenced.add(e[k].split('/').pop());
        }
      }
      for (const f of readdirSync(OUT_DIR)) {
        if (!referenced.has(f)) checkProblems.push(`app/assets/repdb-art/${f} 没有被清单引用（多出来的图）`);
      }
    }
    console.log(`  清单 ${listed.size} 条 · 图片 ${files} 个 · 合计 ${(total / 1024 / 1024).toFixed(2)} MB`
      + `（预算 ${(BUDGET_BYTES / 1024 / 1024).toFixed(0)} MB）`);
    if (total > BUDGET_BYTES) {
      checkProblems.push(`插图合计 ${(total / 1024 / 1024).toFixed(2)} MB，超过 ${(BUDGET_BYTES / 1024 / 1024).toFixed(0)} MB 预算`);
    }
  }
  // 许可原文必须在仓库里（署名义务的凭据）
  if (!existsSync(LICENSE_PATH)) {
    checkProblems.push('tool/repdb-license.txt 不在仓库里 —— 许可原文必须随仓库走（署名义务的凭据）');
  } else {
    const t = readFileSync(LICENSE_PATH, 'utf8');
    if (!t.includes('Attribution required') || !t.includes('RepDB')) {
      checkProblems.push('tool/repdb-license.txt 看起来不是 RepDB 的许可原文');
    }
  }
  if (checkProblems.length) fail(checkProblems);
  console.log('✓ RepDB 插图产物与映射表一致');
  process.exit(0);
}

// ---- 生成 ----

console.log(`→ 生成模式：源=${SRC ? `本地仓库 ${SRC}` : 'GitHub 原始文件（逐张下载，慢）'}`);

// 先把所有需要的图定下来（先不下载），确认形状
const wanted = [];
for (const r of rows) {
  const e = repdb?.get(r.rep);
  const poses = e?.poses;
  if (!poses || Object.keys(poses).length === 0) {
    console.log(`  ⚠ 「${r.our}」→「${r.rep}」在 RepDB 里没有 images.flat —— 跳过这个动作`);
    continue;
  }
  wanted.push({ our: r.our, rep: r.rep, poses });
}
console.log(`  需要 ${wanted.length} 个动作的图，共 ${wanted.reduce((n, w) => n + Object.keys(w.poses).length, 0)} 张`);

mkdirSync(OUT_DIR, { recursive: true });
const artByOur = new Map();
let done = 0;
for (const w of wanted) {
  const art = { start: null, peak: null, main: null };
  for (const [pose, rel] of Object.entries(w.poses)) {
    const outPath = join(OUT_DIR, fileNameOf(w.rep, pose));
    const already = existsSync(outPath);
    if (!already || process.env.REPDB_FORCE === '1') {
      const raw = fetchWebp(rel);
      shrinkToWebp(raw, outPath);
    }
    art[pose] = `assets/repdb-art/${fileNameOf(w.rep, pose)}`;
    done++;
    if (done % 25 === 0) console.log(`  … ${done} 张`);
  }
  artByOur.set(w.our, art);
}

const manifest = buildManifest(rows.filter((r) => artByOur.has(r.our)), artByOur, repdb);
writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 1) + '\n', 'utf8');

// 许可原文抄一份进仓库（署名义务的凭据；生成时联网拿，之后随仓库走）
if (!existsSync(LICENSE_PATH)) {
  let text = null;
  if (SRC) {
    // ZIP 里叫 LICENSE.md，GitHub 仓库里叫 LICENSE-DATA.md
    for (const name of ['LICENSE-DATA.md', 'LICENSE.md']) {
      const p = join(SRC, name);
      if (existsSync(p)) {
        text = readFileSync(p, 'utf8');
        break;
      }
    }
  } else {
    text = execFileSync('curl', ['-sS', '--max-time', '120', '-f', `${REPO_RAW}/LICENSE-DATA.md`], { encoding: 'utf8' });
  }
  if (!text) {
    console.error('✗ 没找到许可原文（LICENSE-DATA.md / LICENSE.md）—— 没有它就不能合法分发这些图');
    process.exit(1);
  }
  writeFileSync(LICENSE_PATH, text, 'utf8');
  console.log(`✓ 许可原文已存到 tool/repdb-license.txt（${text.length} 字节）`);
}

const total = readdirSync(OUT_DIR).reduce((n, f) => n + statSync(join(OUT_DIR, f)).size, 0);
console.log(`✓ 生成完成：${artByOur.size} 个动作 / ${readdirSync(OUT_DIR).length} 张图 / `
  + `${(total / 1024 / 1024).toFixed(2)} MB`);
console.log(`  清单：app/assets/repdb-art.json（${manifest.count} 条）`);
if (total > BUDGET_BYTES) {
  console.error(`✗ 超出 ${(BUDGET_BYTES / 1024 / 1024).toFixed(0)} MB 预算 —— 检查是不是把付费档的图也拷进来了`);
  process.exit(1);
}
void md5;
