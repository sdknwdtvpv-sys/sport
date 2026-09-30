/// 练了么 · 极简 PNG 读写（零依赖）
///
/// **为什么自己写**：仓库里 `tool/` 全是零依赖，不为"去掉一张图的 alpha 通道"去装
/// sharp / pngjs；而这里要处理的 PNG 只有一种来源 —— Flutter 自己截的图
/// （非隔行、真彩或真彩+alpha、5 种 filter 都会出现）。
///
/// 2026-09-30 从 `check-screenshots.mjs` 里抽出来共用：那边只需要写（造自检夹具），
/// 这边还需要**读**（App Store 不收带 alpha 的截图，要去掉 alpha 又要证明像素没变）。
///
/// 能力边界（写明白，免得被当通用库用）：
///   * 只支持**非隔行**、颜色类型 2（RGB）与 6（RGBA）、位深 8 或 16；
///   * 位深 16 一律**按比例取整**降到 8 位（`round(v * 255 / 65535)`）——
///     这一步是真需要的：Flutter 在 **iOS 模拟器**上截出来的是 **16 位 RGBA**
///     （2026-09-30 实测，安卓那边是 8 位），而 App Store 只收 8 位；
///   * 读出来的每像素一律补成 RGBA（颜色类型 2 的 alpha 记 255）；
///   * 写只写颜色类型 2（RGB）或 6（RGBA）、位深 8，filter 一律 0（图是给人和商店看的，
///     压缩率不是这里的目标 —— 1080×2400 的图也就几百 KB）。
///
/// 读 PNG 的过滤器（filter）那 5 种按 PNG 规范实现并在自检里逐种验过：
/// 0 None / 1 Sub / 2 Up / 3 Average / 4 Paeth。
import { readFileSync, writeFileSync } from 'node:fs';
import { deflateSync, inflateSync } from 'node:zlib';

const SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

export function crc32(buf) {
  let crc = 0xffffffff;
  for (const byte of buf) crc = CRC_TABLE[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const t = Buffer.from(type, 'latin1');
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([t, data])));
  return Buffer.concat([len, t, data, crc]);
}

/**
 * 只读 PNG 头（不解压像素）—— 核对宽高/位深/颜色类型时用它，别为一句话解压 1500 万像素。
 * 不是 PNG 时返回 null。返回 `{ width, height, bitDepth, colorType }`。
 */
export function readHeader(path) {
  const b = readFileSync(path);
  if (b.length < 26 || !b.subarray(0, 8).equals(SIGNATURE)) return null;
  if (b.toString('latin1', 12, 16) !== 'IHDR') return null;
  return {
    width: b.readUInt32BE(16),
    height: b.readUInt32BE(20),
    bitDepth: b[24],
    colorType: b[25],
  };
}

/**
 * 读一张 PNG。返回 `{ width, height, colorType, rgba }`，`rgba` 是宽×高×4 的 Buffer。
 * 不满足能力边界（隔行 / 位深不是 8 / 颜色类型不是 2 或 6）时抛错 —— 不猜。
 */
export function readPng(path) {
  const b = readFileSync(path);
  if (!b.subarray(0, 8).equals(SIGNATURE)) throw new Error('不是 PNG（签名不对）');
  let pos = 8;
  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colorType = 0;
  let interlace = 0;
  const idat = [];
  while (pos + 8 <= b.length) {
    const len = b.readUInt32BE(pos);
    const type = b.toString('latin1', pos + 4, pos + 8);
    const data = b.subarray(pos + 8, pos + 8 + len);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colorType = data[9];
      interlace = data[12];
    } else if (type === 'IDAT') {
      idat.push(data);
    } else if (type === 'IEND') {
      break;
    }
    pos += 12 + len;
  }
  if (bitDepth !== 8 && bitDepth !== 16) throw new Error(`只支持 8/16 位深，这张是 ${bitDepth}`);
  if (interlace !== 0) throw new Error('不支持隔行（Adam7）PNG');
  if (colorType !== 2 && colorType !== 6) throw new Error(`只支持颜色类型 2/6，这张是 ${colorType}`);

  const channels = colorType === 6 ? 4 : 3;
  const sampleBytes = bitDepth / 8;
  const raw = inflateSync(Buffer.concat(idat));
  const stride = width * channels * sampleBytes;
  const out = Buffer.alloc(width * height * 4);
  let prev = Buffer.alloc(stride);
  // 16 位按比例取整降 8 位：v16 = 65535 必须正好落到 255（否则"完全不透明"会被误判）
  const to8 = sampleBytes === 2 ? (v) => Math.round((v * 255) / 65535) : (v) => v;
  for (let y = 0; y < height; y += 1) {
    const filter = raw[y * (stride + 1)];
    const line = Buffer.from(raw.subarray(y * (stride + 1) + 1, y * (stride + 1) + 1 + stride));
    unfilter(filter, line, prev, channels * sampleBytes);
    for (let x = 0; x < width; x += 1) {
      const s = x * channels * sampleBytes;
      const d = (y * width + x) * 4;
      const sample = (k) => (sampleBytes === 2 ? line.readUInt16BE(s + k * 2) : line[s + k]);
      out[d] = to8(sample(0));
      out[d + 1] = to8(sample(1));
      out[d + 2] = to8(sample(2));
      out[d + 3] = channels === 4 ? to8(sample(3)) : 255;
    }
    prev = line;
  }
  return { width, height, colorType, bitDepth, rgba: out };
}

/** PNG 的 5 种行过滤器，就地还原成"未过滤"的字节。 */
function unfilter(filter, line, prev, channels) {
  const bpp = channels;
  for (let i = 0; i < line.length; i += 1) {
    const a = i >= bpp ? line[i - bpp] : 0;
    const b = prev[i];
    const c = i >= bpp ? prev[i - bpp] : 0;
    switch (filter) {
      case 0: break;
      case 1: line[i] = (line[i] + a) & 0xff; break;
      case 2: line[i] = (line[i] + b) & 0xff; break;
      case 3: line[i] = (line[i] + ((a + b) >> 1)) & 0xff; break;
      case 4: line[i] = (line[i] + paeth(a, b, c)) & 0xff; break;
      default: throw new Error(`未知的行过滤器 ${filter}`);
    }
  }
}

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

/**
 * 写一张 PNG。`channels` 3（颜色类型 2）或 4（颜色类型 6），`bitDepth` 8 或 16。
 * 位深 16 时把每个 8 位样本按 `v * 257` 展开（PNG 里 8→16 的标准写法）——
 * 自检要造得出"忘了压平"的那种 16 位图。
 */
export function writePng(path, width, height, pixels, channels = 3, bitDepth = 8) {
  if (channels !== 3 && channels !== 4) throw new Error('channels 只能是 3 或 4');
  if (bitDepth !== 8 && bitDepth !== 16) throw new Error('bitDepth 只能是 8 或 16');
  const expected = width * height * channels;
  if (pixels.length !== expected) {
    throw new Error(`像素数不对：宽×高×通道 = ${expected}，实际 ${pixels.length}`);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = bitDepth;
  ihdr[9] = channels === 4 ? 6 : 2; // 颜色类型
  const sampleBytes = bitDepth / 8;
  const stride = width * channels * sampleBytes;
  const raw = Buffer.alloc(height * (stride + 1));
  for (let i = 0; i < width * height * channels; i += 1) {
    if (sampleBytes === 2) raw.writeUInt16BE(pixels[i] * 257, i * 2 + Math.floor(i / (width * channels)) + 1);
  }
  if (sampleBytes === 1) {
    for (let y = 0; y < height; y += 1) {
      raw[y * (stride + 1)] = 0; // filter 0
      pixels.copy(raw, y * (stride + 1) + 1, y * width * channels, (y + 1) * width * channels);
    }
  }
  writeFileSync(path, Buffer.concat([
    SIGNATURE,
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]));
}

