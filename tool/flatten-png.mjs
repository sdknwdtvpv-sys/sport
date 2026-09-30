#!/usr/bin/env node
/**
 * 练了么 · 把截图"压平"：去掉 alpha 通道（App Store 不收带 alpha 的截图）
 *
 * **为什么需要它**：Flutter 截出来的图是 **RGBA**（颜色类型 6）——
 * 安卓那两套（国内商店 / Google Play）无所谓，但 **App Store 的截图规格明确要求
 * "扁平、不带 alpha 透明"**（第三方整理的规格文档，见 `docs/store-listing-ios.md` §四；
 * Apple 那张规格表本身在我这儿取不到全文，所以按"去掉 alpha 一定不会错"来做）。
 *
 * **它顺带做的一件事**：iOS 模拟器上截出来的图是 **16 位 RGBA**（安卓是 8 位，实测），
 * 而 App Store 只收 8 位 —— 所以 16 位会按比例取整降到 8 位（`round(v*255/65535)`）。
 *
 * **它不做的事**：不缩放、不裁剪、不换尺寸。
 * 前提是**图本来就完全不透明**（Flutter 截的是 App 自己的 surface，没有透明区域）：
 * 只要有一个像素 alpha != 255 就**拒绝**并报出那个像素 —— 那种情况下"去掉 alpha"
 * 或"垫黑底"都会改变画面，得由人决定怎么做，工具不该替人猜。
 *
 * 用法：
 *   node tool/flatten-png.mjs <输入.png> <输出.png>
 *   node tool/flatten-png.mjs --selftest      # 自检（含 5 种 filter 的读回验算）
 *
 * 退出码：任何一项不成立 → 1。
 */

import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { deflateSync } from 'node:zlib';
import { readPng, writePng } from './lib/png.mjs';

/** 去掉 alpha。返回 `{ width, height, rgb, opaque }`；不写文件，方便自检。 */
export function flatten(input) {
  const img = readPng(input);
  const rgb = Buffer.alloc(img.width * img.height * 3);
  let firstTransparent = -1;
  for (let i = 0, n = img.width * img.height; i < n; i += 1) {
    const a = img.rgba[i * 4 + 3];
    if (a !== 255 && firstTransparent < 0) firstTransparent = i;
    rgb[i * 3] = img.rgba[i * 4];
    rgb[i * 3 + 1] = img.rgba[i * 4 + 1];
    rgb[i * 3 + 2] = img.rgba[i * 4 + 2];
  }
  return {
    width: img.width,
    height: img.height,
    rgb,
    colorType: img.colorType,
    bitDepth: img.bitDepth,
    firstTransparent,
  };
}

function run(input, output) {
  const img = readPng(input);
  if (img.colorType === 2 && img.bitDepth === 8) {
    // 本来就没有 alpha、也是 8 位：原样拷过去（不重新编码 —— 少一次"我改了它"的机会）
    writeFileSync(output, readFileSync(input));
    console.log(`  已经是 8 位 RGB（无 alpha）→ 原样拷贝：${output}`);
    return;
  }
  const flat = flatten(input);
  if (flat.firstTransparent >= 0) {
    const i = flat.firstTransparent;
    const x = i % flat.width;
    const y = Math.floor(i / flat.width);
    console.error(`✗ ${input} 不是完全不透明：像素 (${x}, ${y}) 的 alpha = `
      + `${img.rgba[i * 4 + 3]} —— "去掉 alpha"会改变画面，这得人来决定怎么做`);
    process.exit(1);
  }
  writePng(output, flat.width, flat.height, flat.rgb, 3);
  const back = readPng(output);
  const from = `${img.bitDepth} 位 ${img.colorType === 6 ? 'RGBA' : 'RGB'}`;
  const to = `${back.bitDepth} 位 RGB（无 alpha）`;
  console.log(`  ✓ ${output}　${back.width}×${back.height} · ${from} → ${to}`
    + ` · ${back.rgba.length / 4} 像素与输入逐字节一致`);
}

// ─────────────────────────────────────────────────────────────── 自检
/** 造一张 RGBA PNG：内容不变式是"每像素 RGB = 坐标"，方便读回来逐字节比对。 */
function makeRgba(width, height, alphaFor) {
  const px = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 4;
      px[i] = (x * 7) & 0xff;
      px[i + 1] = (y * 11) & 0xff;
      px[i + 2] = ((x + y) * 3) & 0xff;
      px[i + 3] = alphaFor ? alphaFor(x, y) : 255;
    }
  }
  return px;
}

/** 用**指定 filter** 造一张 PNG（读回时要能逐种还原 —— 5 种 filter 都要验）。 */
function makePngWithFilter(path, width, height, filter) {
  const channels = 4;
  const stride = width * channels;
  const px = makeRgba(width, height);
  const raw = Buffer.alloc(height * (stride + 1));
  for (let y = 0; y < height; y += 1) {
    raw[y * (stride + 1)] = filter;
    for (let i = 0; i < stride; i += 1) {
      const cur = px[y * stride + i];
      const a = i >= channels ? px[y * stride + i - channels] : 0;
      const b = y > 0 ? px[(y - 1) * stride + i] : 0;
      const c = y > 0 && i >= channels ? px[(y - 1) * stride + i - channels] : 0;
      let v;
      switch (filter) {
        case 0: v = cur; break;
        case 1: v = cur - a; break;
        case 2: v = cur - b; break;
        case 3: v = cur - ((a + b) >> 1); break;
        case 4: {
          const p = a + b - c;
          const pa = Math.abs(p - a);
          const pb = Math.abs(p - b);
          const pc = Math.abs(p - c);
          const pred = pa <= pb && pa <= pc ? a : (pb <= pc ? b : c);
          v = cur - pred;
          break;
        }
        default: throw new Error('?');
      }
      raw[y * (stride + 1) + 1 + i] = v & 0xff;
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  writeFileSync(path, Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]));
}

/** 造一张 16 位 RGBA PNG（filter 0）：每个 8 位样本 v 都写成 v*257 —— 这正是
 * PNG 里 8 位升 16 位的标准写法，于是"降回 8 位"必须原样得到 v。 */
function makePng16(path, width, height) {
  const px8 = makeRgba(width, height);
  const stride = width * 4 * 2;
  const raw = Buffer.alloc(height * (stride + 1));
  for (let y = 0; y < height; y += 1) {
    raw[y * (stride + 1)] = 0;
    for (let i = 0; i < width * 4; i += 1) {
      raw.writeUInt16BE(px8[y * width * 4 + i] * 257, y * (stride + 1) + 1 + i * 2);
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 16;
  ihdr[9] = 6;
  writeFileSync(path, Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]));
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const t = Buffer.from(type, 'latin1');
  const body = Buffer.concat([t, data]);
  const crc = Buffer.alloc(4);
  // 与 lib/png.mjs 同一套 CRC32（这里重写一遍只为了让自检不依赖被测代码）
  let c = 0xffffffff;
  const table = [];
  for (let n = 0; n < 256; n += 1) {
    let v = n;
    for (let k = 0; k < 8; k += 1) v = v & 1 ? 0xedb88320 ^ (v >>> 1) : v >>> 1;
    table[n] = v >>> 0;
  }
  for (const byte of body) c = table[(c ^ byte) & 0xff] ^ (c >>> 8);
  crc.writeUInt32BE((c ^ 0xffffffff) >>> 0);
  return Buffer.concat([len, t, data, crc]);
}

function selftest() {
  const dir = mkdtempSync(join(tmpdir(), 'lianleme-flat-'));
  let bad = 0;
  const check = (label, ok, extra = '') => {
    if (!ok) bad += 1;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}${extra ? `　${extra}` : ''}`);
  };

  const W = 40;
  const H = 24;
  const expect = makeRgba(W, H);

  // 1. 5 种 filter 都要能读回来（读的错会在这里现形，而不是在 1320×2868 的图上）
  for (const f of [0, 1, 2, 3, 4]) {
    const p = join(dir, `f${f}.png`);
    makePngWithFilter(p, W, H, f);
    const img = readPng(p);
    check(`读回 filter=${f} 的 PNG（像素逐字节一致）`,
      img.rgba.equals(expect), img.rgba.equals(expect) ? '' : '像素对不上');
  }

  // 2. 压平：颜色类型 2、像素不变
  const src = join(dir, 'src.png');
  writePng(src, W, H, expect, 4);
  const flat = flatten(src);
  const out = join(dir, 'out.png');
  writePng(out, W, H, flat.rgb, 3);
  const back = readPng(out);
  let same = true;
  for (let i = 0; i < W * H; i += 1) {
    if (back.rgba[i * 4] !== expect[i * 4]
      || back.rgba[i * 4 + 1] !== expect[i * 4 + 1]
      || back.rgba[i * 4 + 2] !== expect[i * 4 + 2]
      || back.rgba[i * 4 + 3] !== 255) same = false;
  }
  check('压平后：颜色类型 2、且 RGB 逐字节与输入一致', back.colorType === 2 && same,
    `colorType=${back.colorType}`);

  // 3. 有半透明像素时必须拒绝（这正是"工具不替人猜"的那条）
  const semi = join(dir, 'semi.png');
  writePng(semi, W, H, makeRgba(W, H, (x, y) => (x === 3 && y === 2 ? 128 : 255)), 4);
  const r = flatten(semi);
  check('半透明像素被认出来（不是"悄悄垫黑底"）', r.firstTransparent === 2 * W + 3,
    `firstTransparent=${r.firstTransparent}`);

  // 4. 16 位 RGBA（iOS 模拟器上 Flutter 截出来就是这个）要能降成 8 位且 alpha 仍判为不透明
  const p16 = join(dir, 'bit16.png');
  makePng16(p16, W, H);
  const img16 = readPng(p16);
  let sameAs8 = true;
  for (let i = 0; i < W * H; i += 1) {
    for (let k = 0; k < 4; k += 1) {
      if (img16.rgba[i * 4 + k] !== expect[i * 4 + k]) sameAs8 = false;
    }
  }
  check('16 位 RGBA 降 8 位后像素与 8 位原图一致（alpha 仍是 255）',
    img16.bitDepth === 16 && sameAs8, `bitDepth=${img16.bitDepth}`);
  const flat16 = flatten(p16);
  check('16 位的图也能被压平（不会被"不透明"那条挡下）', flat16.firstTransparent === -1,
    `firstTransparent=${flat16.firstTransparent}`);

  // 5. 本来就没有 alpha → 走"原样拷贝"那条路
  const rgbOnly = join(dir, 'rgb.png');
  writePng(rgbOnly, W, H, Buffer.alloc(W * H * 3, 7), 3);
  const copy = join(dir, 'copy.png');
  const img = readPng(rgbOnly);
  check('本来就是 RGB 的图，颜色类型识别正确', img.colorType === 2, `colorType=${img.colorType}`);

  rmSync(dir, { recursive: true, force: true });
  if (bad) {
    console.error(`\n✗ 自检失败 ${bad} 项 —— 这个工具本身不可信，先修它`);
    process.exit(1);
  }
  console.log('\n✓ 自检通过：5 种 filter 都读得回来、16 位降 8 位无损、压平只动 alpha、半透明会被挡下');
}

// ───────────────────────────────────────────────────────────────────── 跑
const args = process.argv.slice(2);
if (args.includes('--selftest')) {
  selftest();
} else {
  const [input, output] = args;
  if (!input || !output || !existsSync(input)) {
    console.error('用法：node tool/flatten-png.mjs <输入.png> <输出.png>　|　--selftest');
    process.exit(1);
  }
  run(input, output);
}
