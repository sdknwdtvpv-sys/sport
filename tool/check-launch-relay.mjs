#!/usr/bin/env node
/**
 * 练了么 · **启动接力对位**（VI 计划 T3-6 判据 3）
 *
 * **它要回答的问题**：冷启动那一刻，屏幕上有两枚"同一枚品牌环" ——
 * 先是原生的 `LaunchImage@1x/2x/3x.png`（UIKit 画的），再是 Flutter 第一帧的
 * `SplashOverlay`（`BrandMark` 画的）。**两枚对不上，接力那一刻就会看到一次跳变**
 * （环跳一下、或者大小变一点）。这件事眼睛在生产设备上很难看清，但**量得出来**。
 *
 * 它核四件事：
 *   1. **环心是透明的**（alpha < 8）—— 否则原生启动图渲出来是"白饼 + 橙环"；
 *   2. **环的几何**：外径换算成 pt 之后，与 Flutter 那一侧的 `BrandMark` 同尺寸外径
 *      相差 ≤ 2pt（比例从 `app/lib/core/brand_mark.dart` 里读，画布从 `splash_overlay.dart`
 *      里读 —— 不在这里再抄一份数）；
 *   3. **环在画布正中**（偏移 ≤ 0.5pt）：偏了的话两枚环的圆心会错开；
 *   4. 三档（1x / 2x / 3x）彼此一致（同一枚环的三个分辨率）。
 *
 * ⚠️ **2026-10-10 从 Python 重写成 Node**，理由必须留在这里：
 *   它原来是 `tool/check-launch-relay.py`（Python + **PIL**）。PIL 是**门禁里唯一一个
 *   需要额外环境的东西** —— 本机装了才跑得起来，而 ubuntu runner 上没有，于是
 *   2026-10-10 那次 CI 直接红在 `ModuleNotFoundError: No module named 'PIL'`。
 *   当时的第一反应是"在 CI 里装 Pillow"，但仓库自己的守卫当场把它拦下来了：
 *   **「CI 里不许有一条门禁不管的命令」**（`tool/check-ci.mjs`）—— CI 跑的东西必须就是
 *   门禁跑的东西，否则"本地门禁复现不了它"。于是正确的修法是**把依赖去掉**：
 *   Node 自带 `zlib`，PNG 的 IDAT 解压 + 反滤波不到 60 行，自检夹具需要的"造一张假图"
 *   也能用 `deflateSync` 写出来。**门禁里不该有一条需要额外环境的守卫。**
 *
 * 用法：
 *     node tool/check-launch-relay.mjs            # 核仓库里的启动图
 *     node tool/check-launch-relay.mjs --selftest # 自检（造几张假的，验它抓得住）
 *
 * 退出码：任何一项不符 → 1。
 */

import { deflateSync, inflateSync } from 'node:zlib';
import { mkdtempSync, readdirSync, readFileSync, rmSync, unlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const LAUNCH = join(ROOT, 'app/ios/Runner/Assets.xcassets/LaunchImage.imageset');
const BRAND = join(ROOT, 'app/lib/core/brand_mark.dart');
const SPLASH = join(ROOT, 'app/lib/features/onboarding/splash_overlay.dart');

const TOL_PT = 2.0; // 判据给的对位容差
const TOL_CENTER_PT = 0.5; // 圆心偏移容差

/** 从 Dart 源码里读"Flutter 这一侧"的两个数：外径比例与画布边长。 */
function flutterSide() {
  const ratio = /outerRatio\s*=\s*([0-9.]+)/.exec(readFileSync(BRAND, 'utf8'));
  const canvas = /canvas\s*=\s*([0-9.]+)/.exec(readFileSync(SPLASH, 'utf8'));
  if (!ratio || !canvas) {
    console.error('✗ 读不到 brand_mark.dart 的 outerRatio 或 splash_overlay.dart 的 canvas');
    process.exit(1);
  }
  return { ratio: Number(ratio[1]), canvas: Number(canvas[1]) };
}

// ─────────────────────────────── PNG 解码 ───────────────────────────────
//
// 只支持我们自己的启动图用到的格式：8 位、colorType 6（RGBA）。遇到别的格式**明确报错**，
// 而不是猜 —— 猜错会让这条守卫悄悄失去意义（它最怕的就是"看着跑过了"）。

function decodePng(buf) {
  if (buf.subarray(0, 8).toString('latin1') !== '\x89PNG\r\n\x1a\n') {
    throw new Error('不是 PNG（文件头不对）');
  }
  let off = 8;
  let width = 0;
  let height = 0;
  let colorType = 0;
  let bitDepth = 0;
  const idat = [];
  while (off < buf.length) {
    const len = buf.readUInt32BE(off);
    const type = buf.subarray(off + 4, off + 8).toString('latin1');
    const data = buf.subarray(off + 8, off + 8 + len);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colorType = data[9];
    } else if (type === 'IDAT') {
      idat.push(data);
    } else if (type === 'IEND') {
      break;
    }
    off += 12 + len;
  }
  if (bitDepth !== 8 || colorType !== 6) {
    throw new Error(`只支持 8 位 RGBA 的 PNG，这张是 bitDepth=${bitDepth} colorType=${colorType}`);
  }
  const raw = inflateSync(Buffer.concat(idat));
  const bpp = 4; // RGBA
  const stride = width * bpp;
  const out = Buffer.alloc(width * height * bpp);
  let prev = Buffer.alloc(stride);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const line = raw.subarray(y * (stride + 1) + 1, y * (stride + 1) + 1 + stride);
    const cur = Buffer.alloc(stride);
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? cur[i - bpp] : 0;
      const b = prev[i];
      const c = i >= bpp ? prev[i - bpp] : 0;
      let v = line[i];
      switch (filter) {
        case 0: break;
        case 1: v = (v + a) & 0xff; break;
        case 2: v = (v + b) & 0xff; break;
        case 3: v = (v + ((a + b) >> 1)) & 0xff; break;
        case 4: {
          const p = a + b - c;
          const pa = Math.abs(p - a);
          const pb = Math.abs(p - b);
          const pc = Math.abs(p - c);
          const pred = pa <= pb && pa <= pc ? a : (pb <= pc ? b : c);
          v = (v + pred) & 0xff;
          break;
        }
        default: throw new Error(`不认识的 PNG 滤波类型 ${filter}`);
      }
      cur[i] = v;
    }
    cur.copy(out, y * stride);
    prev = cur;
  }
  return { width, height, pixels: out };
}

/** 量一张启动图：中心 alpha、环外径（pt）、圆心偏移（pt）。 */
function measure(path) {
  const { width: W, height: H, pixels } = decodePng(readFileSync(path));
  const alpha = (x, y) => pixels[(y * W + x) * 4 + 3];
  const scale = Math.round(W / 96); // 画布 96pt 的 @1x/@2x/@3x
  const cx = W / 2 - 0.5;
  const cy = H / 2 - 0.5;
  let centerAlpha = 0;
  for (const dx of [-1, 0, 1]) {
    for (const dy of [-1, 0, 1]) {
      centerAlpha = Math.max(centerAlpha, alpha(Math.floor(cx) + dx, Math.floor(cy) + dy));
    }
  }

  // 过中心横扫一行，取 alpha>200 的第一段与最后一段 → 环带
  const segs = [];
  let start = null;
  for (let x = 0; x < W; x++) {
    const solid = alpha(x, Math.floor(cy)) > 200;
    if (solid && start === null) start = x;
    else if (!solid && start !== null) {
      segs.push([start, x - 1]);
      start = null;
    }
  }
  if (start !== null) segs.push([start, W - 1]);
  if (segs.length < 2) return null;
  const outerPx = segs[segs.length - 1][1] - segs[0][0] + 1;
  const centerPx = (segs[0][0] + segs[segs.length - 1][1]) / 2;
  return {
    scale,
    centerAlpha,
    outerPt: outerPx / scale,
    offsetPt: Math.abs(centerPx - (W - 1) / 2) / scale,
    size: [W, H],
  };
}

function check(launchDir) {
  const { ratio, canvas } = flutterSide();
  const want = ratio * canvas; // Flutter 那一侧的环外径（pt）
  const problems = [];
  const facts = [];
  const outs = [];
  for (const name of readdirSync(launchDir).filter((f) => /^LaunchImage.*\.png$/.test(f)).sort()) {
    const p = join(launchDir, name);
    let m;
    try {
      m = measure(p);
    } catch (e) {
      problems.push(`${name}：读不出来（${e.message}）`);
      continue;
    }
    if (m === null) {
      problems.push(`${name}：过中心那一行找不到两段实心 —— 这不像一枚环`);
      continue;
    }
    outs.push([name, m.outerPt]);
    if (m.centerAlpha >= 8) {
      problems.push(`${name}：环心 alpha = ${m.centerAlpha}（要 < 8）—— `
        + '原生启动图会渲成"白饼 + 橙环"');
    }
    if (Math.abs(m.outerPt - want) > TOL_PT) {
      problems.push(`${name}：环外径 ${m.outerPt.toFixed(2)}pt，Flutter 那一侧是 ${want.toFixed(2)}pt`
        + `（差 ${Math.abs(m.outerPt - want).toFixed(2)}pt > ${TOL_PT}）`);
    }
    if (m.offsetPt > TOL_CENTER_PT) {
      problems.push(`${name}：环心偏了 ${m.offsetPt.toFixed(2)}pt（> ${TOL_CENTER_PT}）`);
    }
    facts.push(`${name}: 外径 ${m.outerPt.toFixed(2)}pt · 环心 alpha ${m.centerAlpha} · `
      + `偏移 ${m.offsetPt.toFixed(2)}pt`);
  }
  if (outs.length >= 2) {
    const vals = outs.map(([, v]) => v);
    const lo = Math.min(...vals);
    const hi = Math.max(...vals);
    if (hi - lo > TOL_PT) {
      problems.push(`三档彼此不一致：外径从 ${lo.toFixed(2)}pt 到 ${hi.toFixed(2)}pt`);
    }
  }
  return { problems, facts, want };
}

// ───────────────────────── 自检夹具：造一张假启动图 ─────────────────────────
//
// 需要**写** PNG（Python 那版靠 PIL 的 `Image.save`）。Node 里手写三个 chunk 即可：
// IHDR + IDAT（deflate）+ IEND，每块前面有长度、后面有 CRC32。滤波统一用 0（None）。

const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (const byte of buf) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, 'latin1'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}

function encodePng(width, height, rgba) {
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = 0; // filter: None
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, y * stride + stride);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  return Buffer.concat([
    Buffer.from('\x89PNG\r\n\x1a\n', 'latin1'),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

/** 造一张假启动图：画布 96pt 的 @(size/96)x，环外径 ringPt，可选白饼与偏移。 */
function fake(name, size, ringPt, { centerAlpha = 0, hole = true, offset = 0 } = {}, dir) {
  const rgba = Buffer.alloc(size * size * 4);
  const s = size / 96;
  const r = (ringPt * s) / 2;
  const c = size / 2 + offset * s;
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const dx = x - c;
      const dy = y - c;
      const d = Math.sqrt(dx * dx + dy * dy);
      if (d > r) continue;
      const inHole = hole && d < r * 0.6;
      if (inHole) continue;
      const i = (y * size + x) * 4;
      rgba[i] = 255;
      rgba[i + 1] = 92;
      rgba[i + 2] = 38;
      rgba[i + 3] = 255;
    }
  }
  if (centerAlpha) {
    const i = (Math.floor(c) * size + Math.floor(c)) * 4;
    rgba[i] = 255;
    rgba[i + 1] = 255;
    rgba[i + 2] = 255;
    rgba[i + 3] = centerAlpha;
  }
  writeFileSync(join(dir, name), encodePng(size, size, rgba));
}

function selftest() {
  const tmp = mkdtempSync(join(tmpdir(), 'lianleme-launch-'));
  const problems = [];
  const clear = () => {
    for (const f of readdirSync(tmp)) unlinkSync(join(tmp, f));
  };

  try {
    // ① 正常的一档：外径 42.9pt（= 0.447 × 96）、环心透明
    fake('LaunchImage.png', 96, 42.9, {}, tmp);
    let r = check(tmp);
    if (r.problems.length) problems.push(`正常的启动图被判红：${r.problems.join(' / ')}`);
    if (Math.abs(r.want - 42.9) > 0.05) {
      problems.push(`从 Dart 源码读出来的外径 ${r.want.toFixed(3)} 不是 42.9`);
    }

    // ② 环心不透明（白饼）
    clear();
    fake('LaunchImage.png', 96, 42.9, { centerAlpha: 255 }, tmp);
    r = check(tmp);
    if (!r.problems.some((x) => x.includes('环心 alpha'))) {
      problems.push('环心不透明没被抓出来');
    }

    // ③ 环太小（对不上）
    clear();
    fake('LaunchImage.png', 96, 30.0, {}, tmp);
    r = check(tmp);
    if (!r.problems.some((x) => x.includes('环外径'))) {
      problems.push('环外径对不上没被抓出来');
    }

    // ④ 环心偏了
    clear();
    fake('LaunchImage.png', 96, 42.9, { offset: 4 }, tmp);
    r = check(tmp);
    if (!r.problems.some((x) => x.includes('偏了'))) {
      problems.push('环心偏移没被抓出来');
    }

    // ⑤ 三档彼此不一致（1x 对、3x 小一圈）
    clear();
    fake('LaunchImage.png', 96, 42.9, {}, tmp);
    fake('LaunchImage@3x.png', 288, 36.0, {}, tmp);
    r = check(tmp);
    if (!r.problems.some((x) => x.includes('三档'))) {
      problems.push('三档不一致没被抓出来');
    }
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }

  if (problems.length) {
    console.log('✗ 自检失败：');
    for (const x of problems) console.log(`  - ${x}`);
    return 1;
  }
  console.log('✓ 自检通过 5 条：正常 / 环心不透明 / 环太小 / 环心偏移 / 三档不一致 都判对了');
  return 0;
}

function main() {
  if (process.argv.includes('--selftest')) return selftest();
  const { ratio, canvas } = flutterSide();
  const { problems, facts, want } = check(LAUNCH);
  for (const f of facts) console.log(`  ${f}`);
  if (problems.length) {
    console.log('');
    for (const x of problems) console.log(`✗ ${x}`);
    console.log(`\n✗ 启动图与 Flutter 那一侧的环对不上（容差 ${TOL_PT}pt）—— 冷启动接力那一刻会看到跳变`);
    return 1;
  }
  console.log(`✓ 三档启动图与 Flutter 那一侧的环对得上：外径 ${want.toFixed(2)}pt`
    + `（${ratio} × ${canvas}pt），环心透明、居中`);
  return 0;
}

process.exit(main());
