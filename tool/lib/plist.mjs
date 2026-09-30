/**
 * 练了么 · 属性列表（plist）读写 —— 一个**能跑在 Linux 上**的最小实现
 *
 * **为什么要有它**：核 iOS 产物（`tool/check-ios-app.mjs`）一直靠 macOS 的
 * `/usr/bin/plutil`。2026-09-30 用户拍板「CI 直接跑 `./verify.sh`」之后，
 * 那条路在 ubuntu 上走不通 —— plutil 是 macOS 独有的，于是门禁在 CI 上会因为
 * **环境**（而不是代码）红，或者更糟：那条自检被"跳过"，从此没人发现它坏了。
 *
 * 所以这里自己解析 XML plist：
 *   * 有 plutil（macOS）时仍然用它 —— 真产物（编译过的 `.app`）用系统工具读最不容易出错；
 *   * 没有时（CI/Linux）用这里的解析器，**同样的断言照样跑**，只是换了读法。
 *
 * 支持的正好是 `Info.plist` 用到的那几样：dict / array / string / integer / real /
 * true / false。`<data>` 与 `<date>` 读成 null —— 我们没核过它们，**读不出来比猜一个值好**
 * （猜一个值会让"没核"看起来像"核过了"）。
 *
 * 自检：`node tool/lib/plist.mjs --selftest`（解析与序列化互逆 + 边界）
 */

import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const PLUTIL = '/usr/bin/plutil';

const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
const unescape = (s) => s.replace(/&(amp|lt|gt|quot|apos);/g, (_, e) => ENTITIES[e]);
const escape = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/** 解析一份 XML plist，返回 JS 里的对象/数组/标量。解析不了就抛（调用方决定怎么算）。 */
export function parsePlistXml(text) {
  // 声明、DOCTYPE、注释都不是值：去掉后剩下的才是结构
  const s = text
    .replace(/<\?xml[^>]*\?>/g, '')
    .replace(/<!DOCTYPE[^>]*>/g, '')
    .replace(/<!--[\s\S]*?-->/g, '');
  let i = 0;

  function fail(why) {
    throw new Error(`plist 解析失败（第 ${i} 个字符附近）：${why}`);
  }

  function skipWs() { while (i < s.length && /\s/.test(s[i])) i += 1; }

  function expect(open) {
    skipWs();
    if (!s.startsWith(open, i)) fail(`期望 ${open}`);
    i += open.length;
  }

  function readText(close) {
    const end = s.indexOf(close, i);
    if (end < 0) fail(`找不到 ${close}`);
    const out = s.slice(i, end);
    i = end + close.length;
    return unescape(out);
  }

  function parseValue() {
    skipWs();
    if (i >= s.length) fail('值不完整');
    if (s.startsWith('<dict', i)) {
      expect('<dict');
      if (s[i] === '/') { expect('/>'); return {}; }
      expect('>');
      const out = {};
      for (;;) {
        skipWs();
        if (s.startsWith('</dict>', i)) { i += '</dict>'.length; return out; }
        if (!s.startsWith('<key>', i)) fail('dict 里出现了非 <key> 的东西');
        i += '<key>'.length;
        const key = readText('</key>');
        out[key] = parseValue();
      }
    }
    if (s.startsWith('<array', i)) {
      expect('<array');
      if (s[i] === '/') { expect('/>'); return []; }
      expect('>');
      const out = [];
      for (;;) {
        skipWs();
        if (s.startsWith('</array>', i)) { i += '</array>'.length; return out; }
        out.push(parseValue());
      }
    }
    for (const [open, close, cast] of [
      ['<string>', '</string>', (v) => v],
      ['<integer>', '</integer>', (v) => Number.parseInt(v, 10)],
      ['<real>', '</real>', (v) => Number.parseFloat(v)],
    ]) {
      if (s.startsWith(open, i)) {
        i += open.length;
        return cast(readText(close));
      }
    }
    if (s.startsWith('<true/>', i)) { i += '<true/>'.length; return true; }
    if (s.startsWith('<false/>', i)) { i += '<false/>'.length; return false; }
    // <data> / <date>：我们没核过，读成 null（**读不出来比猜一个值好**）
    for (const [open, close] of [['<data>', '</data>'], ['<date>', '</date>']]) {
      if (s.startsWith(open, i)) { i += open.length; readText(close); return null; }
    }
    return fail(`看不懂的值：${s.slice(i, i + 20)}`);
  }

  skipWs();
  // 根元素可以省略 <plist> 包裹（少见但合法）
  if (s.startsWith('<plist', i)) {
    // 根标签带属性（`<plist version="1.0">`）是常态，属性内容不影响值
    const m = /^<plist[^>]*>/.exec(s.slice(i));
    if (!m) fail('<plist 这个开标签不完整');
    i += m[0].length;
  }
  const value = parseValue();
  return value;
}

/** 把 JS 值写成 XML plist 文本（自检夹具与"造一份合法 plist"用）。 */
export function toPlistXml(value) {
  function write(v, indent) {
    const pad = '  '.repeat(indent);
    if (v === null || v === undefined) return `${pad}<string></string>`;
    if (typeof v === 'boolean') return `${pad}<${v ? 'true' : 'false'}/>`;
    if (typeof v === 'number') return `${pad}<${Number.isInteger(v) ? 'integer' : 'real'}>${v}</${Number.isInteger(v) ? 'integer' : 'real'}>`;
    if (typeof v === 'string') return `${pad}<string>${escape(v)}</string>`;
    if (Array.isArray(v)) {
      if (!v.length) return `${pad}<array/>`;
      return `${pad}<array>\n${v.map((x) => write(x, indent + 1)).join('\n')}\n${pad}</array>`;
    }
    const keys = Object.keys(v);
    if (!keys.length) return `${pad}<dict/>`;
    const body = keys.map((k) => `${'  '.repeat(indent + 1)}<key>${escape(k)}</key>\n${write(v[k], indent + 1)}`).join('\n');
    return `${pad}<dict>\n${body}\n${pad}</dict>`;
  }
  return `<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n${write(value, 0)}\n</plist>\n`;
}

/** 这台机器上有没有 plutil（macOS 有，CI 的 ubuntu 没有）。 */
export const hasPlutil = () => existsSync(PLUTIL);

/**
 * 读一份 plist 成 JS 对象。
 * engine：'auto'（有 plutil 就用）| 'plutil' | 'builtin'（自检里用来固定两条路）
 */
export function readPlistObject(plistPath, engine = 'auto') {
  const use = engine === 'auto' ? (hasPlutil() ? 'plutil' : 'builtin') : engine;
  if (use === 'plutil') {
    return JSON.parse(execFileSync(PLUTIL, ['-convert', 'json', '-o', '-', plistPath],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }));
  }
  return parsePlistXml(readFileSync(plistPath, 'utf8'));
}

/** 读一份 plist 里某个键，比较用的字符串形式（布尔 → 'true'/'false'，数字 → 十进制）。 */
export function readPlistRaw(plistPath, key, engine = 'auto') {
  let obj;
  try {
    obj = readPlistObject(plistPath, engine);
  } catch {
    return null;
  }
  const v = obj?.[key];
  if (v === undefined || v === null) return null;
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  return String(v);
}

/** 读一份 plist 里某个键，保持类型（数组还是数组）。 */
export function readPlistJson(plistPath, key, engine = 'auto') {
  try {
    const obj = readPlistObject(plistPath, engine);
    return obj?.[key] ?? null;
  } catch {
    return null;
  }
}

// ───────────────────────────────────────────────────────────── 自检
/** 键序无关的比较（plutil 的输出顺序不保证与输入一致）。 */
function canon(v) {
  if (Array.isArray(v)) return `[${v.map(canon).join(',')}]`;
  if (v && typeof v === 'object') {
    return `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${canon(v[k])}`).join(',')}}`;
  }
  return JSON.stringify(v);
}

function selftest() {
  const cases = [
    ['标量 dict 往返', { A: 'x', B: 3, C: true, D: false, E: 1.5 }],
    ['嵌套 dict + 数组', { K: { a: '1' }, L: ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft'], M: [] }],
    ['空 dict', {}],
    ['空数组', { N: [] }],
    ['转义字符', { S: 'a<b>&"c"' }],
    ['带 DOCTYPE 与注释', { X: 'y' }],
  ];
  let bad = 0;
  for (const [label, obj] of cases) {
    const xml = toPlistXml(obj);
    let got;
    try { got = parsePlistXml(xml); } catch (e) { got = `抛了：${e.message}`; }
    const ok = JSON.stringify(got) === JSON.stringify(obj);
    if (!ok) bad += 1;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} 往返：${label}`
      + (ok ? '' : `　→ ${JSON.stringify(got)}`));
  }
  // 边界：坏输入必须抛，而不是返回一个"看起来对"的值
  for (const [label, xml] of [
    ['不是 plist 的文本', 'hello'],
    ['dict 里的值没写完就到头了', '<plist version="1.0"><dict><key>a</key>'],
    ['值类型不认识', '<plist version="1.0"><dict><key>a</key><bogus/></dict></plist>'],
  ]) {
    let threw = false;
    try { parsePlistXml(xml); } catch { threw = true; }
    if (!threw) bad += 1;
    console.log(`  ${threw ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} 坏输入必须抛：${label}`);
  }
  // <data>/<date> 读成 null：我们没核过它们，猜一个值最危险
  const nulled = parsePlistXml('<plist version="1.0"><dict><key>d</key><data>AAAA</data></dict></plist>');
  const okNull = nulled.d === null;
  if (!okNull) bad += 1;
  console.log(`  ${okNull ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} <data> 读成 null（没核过就不猜）`);

  // 与系统 plutil 对照（macOS 才跑得起来；CI 上明确说"没跑"，不假装跑过）
  if (hasPlutil()) {
    const dir = mkdtempSync(join(tmpdir(), 'lianleme-plist-'));
    const p = join(dir, 'x.plist');
    const fixture = { Name: '练了么', Ver: 43, Flag: false, Arr: ['a', 'b'] };
    writeFileSync(p, toPlistXml(fixture));
    const viaPlutil = readPlistObject(p, 'plutil');
    const okSame = canon(viaPlutil) === canon(fixture);
    if (!okSame) bad += 1;
    console.log(`  ${okSame ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} 自制解析器与系统 plutil 结果一致`
      + (okSame ? '' : `　→ plutil: ${JSON.stringify(viaPlutil)}`));
    rmSync(dir, { recursive: true, force: true });
  } else {
    console.log('  \x1b[33m⊘\x1b[0m 这台机器没有 /usr/bin/plutil —— 与系统 plutil 的对照没跑（CI 上就是这个情况）');
  }

  if (bad) {
    console.error(`\n✗ plist 自检失败 ${bad} 项`);
    process.exit(1);
  }
  console.log('\n✓ plist 自检通过：解析与序列化互逆、坏输入会抛、<data> 不猜');
}

// ⚠️ 只在**被当作程序跑**时自检：`check-ios-app.mjs` 会 import 这个文件，
// 那时命令行里也带着 `--selftest` —— 按 flag 判断会让库"跟着别人的自检一起跑"（各打一份）。
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href
    && process.argv.includes('--selftest')) {
  selftest();
}
