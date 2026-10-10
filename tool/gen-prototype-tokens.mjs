#!/usr/bin/env node
/**
 * 练了么 · **原型的 `:root` 由 `theme.dart` 生成**（2026-10-10，VI 计划 T1-6）
 *
 * **它为什么存在**：`app/lib/core/theme.dart` 的文件头上写着一条契约 ——
 *「与 `docs/interaction-spec.md` §2–§4 和 `prototype/index.html` 的 CSS 变量一一对应。
 *   改这里之前先改规格 —— **三处必须同时一致**。」
 *
 * 而这条契约**从来没有守卫**，于是它漂了（2026-10-10 实测）：
 *   * `prototype/index.html` 的 `--elevated` 是冷蓝灰 `#1F1F24`（真值 `#24201C` 暖黑）；
 *   * `--pr` 是旧的琥珀 `#F5C451`（真值 `#FBBF24`）；
 *   * `--r-card` 是 `20px`（真值 `12px`，而且它被 9 处引用）。
 * 原型是"界面稿"的延伸，设计师照着它改、评审照着它看 —— **它偏 8 个色的距离，
 * 比代码里偏一个值更贵**，因为看到它的人会以为是准的。
 *
 * 所以：**原型的 `:root` 改成生成的**。手改会被 `--check` 打回（与
 * `tool/gen-privacy-page.mjs` 完全同一个模式）。
 *
 * ## 用法
 *   node tool/gen-prototype-tokens.mjs            # 生成（就地改写两份原型）
 *   node tool/gen-prototype-tokens.mjs --check    # 只比对，漂了就退出 1（门禁跑这个）
 *
 * ## 口径（三件必须说清，否则下一个人会猜）
 *   1. **真源只有一处**：`app/lib/core/theme.dart`。这个脚本**不做任何"智能取值"** ——
 *      解析不到就报错退出，绝不用默认值兜底（兜底会让漂移变成静默的）。
 *   2. **字号 / 行高不在生成范围内**：`theme.dart` 今天**没有字阶令牌**（那是 VI 计划
 *      批次 1 的 T1-3）—— 所以那几行按下面的 `FONT_BLOCK` 常量原样写回；
 *      等 `theme.dart` 有了 `fs*` / `lh*` 令牌，改这个常量即可（TODO 写在那一行旁边）。
 *   3. **两份原型的变量命名不同**，所以有一张显式映射表（`FILES[].map`）：
 *      每一条都是"theme 里的名字 → 该文件里的名字"，**没有映射的变量不生成**
 *      （例如 `index.html` 里没有 `--success`，就不硬塞一个进去 —— 原型只画它要画的东西）。
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const THEME = join(ROOT, 'app/lib/core/theme.dart');

/** 生成块的开始/结束标记（放在原型文件里，用来定位要替换的那一段）。 */
const BEGIN = '  /* ⚠️ 这一段由 `tool/gen-prototype-tokens.mjs` 从 `app/lib/core/theme.dart` 生成 —— 手改会被门禁打回 */';
const END = '  /* ── 生成块结束 ── */';

/**
 * 字号 / 行高（**暂时不由 theme 生成**，见文件头口径 2）。
 * 改动这里等于改原型的字阶 —— 但要先确认 `docs/interaction-spec.md` §3 的字阶表同步了。
 */
const FONT_BLOCK = [
  '  --fs-display:44px; --lh-display:48px;',
  '  --fs-title:28px;   --lh-title:34px;',
  '  --fs-headline:20px;--lh-headline:26px;',
  '  --fs-body:17px;    --lh-body:24px;',
  '  --fs-sub:15px;     --lh-sub:21px;',
  '  --fs-cap:13px;     --lh-cap:18px;',
  '  --fs-micro:11px;   --lh-micro:14px;',
];

/**
 * 要生成的文件 + 命名映射。
 *
 * `map` 的键是 `theme.dart` 里的常量名，值是 `[变量名, 注释]`（注释可为空）。
 * `rgba` 表示这一条在 theme 里是**半透明白**（`Color(0x0FFFFFFF)` 这种），
 * 要还原成 CSS 的 `rgba(255,255,255,α)` —— 直接写 `#0FFFFFFF` 在浏览器里是错的。
 */
const FILES = [
  {
    path: 'prototype/index.html',
    style: 'multi', // 一行一个变量（index.html 原本就是这种排版，保留它的可读性）
    map: {
      bg: ['--bg', '页面底色'],
      surface: ['--surface', '卡片'],
      elevated: ['--elevated', '抬升表面：弹层、输入'],
      hair: ['--hair', '页面级长分隔（最弱一级）'],
      field: ['--field', '输入框 / 未选中胶囊的抬升底'],
      lift: ['--lift', '卡片里抬起来的材料（进度槽 / 锁态徽章）'],
      sheet: ['--sheet', '弹层底（对话框 / 底弹层 / SnackBar）'],
      inkOnSuccess: ['--ink-on-success', '成功色上的字'],
      line: ['--line', '卡片描边 / 卡片内行分隔'],
      lineStrong: ['--line-strong', '功能性边界：输入框、未选中胶囊、分段控件'],
      text: ['--text', ''],
      text2: ['--text-2', ''],
      text3: ['--text-3', ''],
      accent: ['--accent', '主操作：记录一组'],
      accentPress: ['--accent-press', ''],
      accentInk: ['--accent-ink', 'accent 上的文字（6.06:1）'],
      pr: ['--pr', 'PR / 破纪录'],
      danger: ['--danger', ''],
    },
    spacing: true,
    radius: true,
    sizes: [['hPrimary', '--h-primary', '主按钮高度，单手可达的硬约束']],
    extra: ['  --safe-bottom:34px;    /* home indicator（原型自己用的，不从 theme 来） */'],
  },
  {
    path: 'prototype/ref-3tab-2026-10-10.html',
    style: 'packed', // 一行塞两三个（这份稿子原本就是这种排版）
    map: {
      bg: ['--bg', ''],
      surface: ['--surface', ''],
      elevated: ['--elev', ''],
      hair: ['--hair', ''],
      field: ['--field', ''],
      lift: ['--lift', ''],
      sheet: ['--sheet', ''],
      line: ['--line', ''],
      lineStrong: ['--line2', ''],
      text: ['--t1', ''],
      text2: ['--t2', ''],
      text3: ['--t3', ''],
      accent: ['--accent', ''],
      accentInk: ['--ink', ''],
      success: ['--ok', ''],
      pr: ['--pr', ''],
      tierRare: ['--rare', ''],
    },
    spacing: false,
    radius: false,
    sizes: [],
    extra: [],
  },
];

/** `Color(0xFFRRGGBB)` / `Color(0xAARRGGBB)` → `#RRGGBB`；半透明白单独走 rgba。 */
function parseColor(raw) {
  const m = /^Color\(0x([0-9A-Fa-f]{8})\)$/.exec(raw);
  if (!m) return null;
  const argb = m[1];
  const a = argb.slice(0, 2).toUpperCase();
  const rgb = argb.slice(2).toUpperCase();
  if (a === 'FF') return { css: `#${rgb}` };
  // theme 里只有"半透明白"这一类 alpha 色（line / lineStrong），其余全是不透明
  if (rgb === 'FFFFFF') {
    const alpha = (parseInt(a, 16) / 255).toFixed(2).replace(/0$/, '');
    return { css: `rgba(255,255,255,${alpha})` };
  }
  return null;
}

function readTheme() {
  const src = readFileSync(THEME, 'utf8');
  // ① 先收字面量色值
  const colors = {};
  for (const m of src.matchAll(/static const Color (\w+) = (Color\(0x[0-9A-Fa-f]{8}\));/g)) {
    const parsed = parseColor(m[2]);
    if (parsed) colors[m[1]] = parsed.css;
  }
  // ② 再解**别名**（`static const Color field = lift;`）——
  //    `theme.dart` 里有刻意的别名（`field` 就是 `lift`：同一种材料只该有一个值）。
  //    解析不到别名就交给下面的"不做兜底"报错，绝不静默跳过。
  const aliases = {};
  for (const m of src.matchAll(/static const Color (\w+) = (\w+);/g)) {
    aliases[m[1]] = m[2];
  }
  for (const [name, target] of Object.entries(aliases)) {
    if (!colors[name] && colors[target]) colors[name] = colors[target];
  }
  const nums = {};
  for (const m of src.matchAll(/static const double (\w+) = ([0-9.]+);/g)) {
    nums[m[1]] = m[2];
  }
  return { colors, nums, src };
}

/** 生成一份文件里的 `:root{ … }` 内容（行数组，不含 `:root{` 与 `}`）。 */
function buildBlock(file, theme) {
  const lines = [BEGIN];
  const colorLines = [];
  for (const [key, def] of Object.entries(file.map)) {
    const [name, comment, kind] = def;
    let value = theme.colors[key];
    if (!value) {
      throw new Error(
        `✗ theme.dart 里没有 ${key}（或不是 Color(0x…)) —— 生成器不做兜底，` +
        `要么改映射表、要么把这个常量补进 theme.dart`,
      );
    }
    if (kind === 'rgba' && !value.startsWith('rgba(')) {
      throw new Error(`✗ ${key} 在 theme.dart 里不是半透明白（得到 ${value}）—— 映射表里的 'rgba' 要改`);
    }
    const pad = ' '.repeat(Math.max(1, 24 - name.length - value.length));
    colorLines.push(comment ? `  ${name}:${value};${pad}/* ${comment} */` : `  ${name}:${value};`);
  }
  if (file.style === 'multi') {
    if (file.map.bg) lines.push('  /* 背景 · 前景 · 强调（值来自 theme.dart） */');
    lines.push(...colorLines);
  } else {
    // packed：把颜色两三个挤一行（这份稿子原本就这么排）
    let buf = '';
    const packed = [];
    colorLines.forEach((line, i) => {
      const noComment = line.replace(/\/\*.*?\*\//g, '').trim();
      buf += (buf ? ' ' : '  ') + noComment;
      if ((i + 1) % 3 === 0 || i === colorLines.length - 1) {
        packed.push(buf);
        buf = '';
      }
    });
    lines.push(...packed);
  }
  if (file.spacing) {
    const s = ['s1', 's2', 's3', 's4', 's5', 's6', 's8']
      .map((k) => `--${k}:${theme.nums[k]}px;`)
      .join(' ');
    lines.push('', `  /* 间距 */`, `  ${s}`);
  }
  if (file.radius) {
    const r = [
      ['rCard', '--r-card'],
      ['rSheet', '--r-sheet'],
      ['rPill', '--r-pill'],
    ]
      .map(([k, name]) => `${name}:${theme.nums[k]}px;`)
      .join(' ');
    lines.push('', `  /* 圆角 */`, `  ${r}`);
  }
  lines.push('', '  /* 字号 / 行高 */', ...FONT_BLOCK);
  if (file.sizes.length) {
    lines.push('', '  /* 关键尺寸 */');
    for (const [key, name, comment] of file.sizes) {
      lines.push(`  ${name}:${theme.nums[key]}px;${comment ? `     /* ${comment} */` : ''}`);
    }
  }
  if (file.extra.length) lines.push(...file.extra);
  lines.push(END);
  return lines.join('\n');
}

/** 把生成块塞进文件（替换标记之间的内容；没有标记就替换整个 `:root{}`）。 */
function rewrite(original, block) {
  const b = original.indexOf(BEGIN);
  const e = original.indexOf(END);
  if (b >= 0 && e > b) {
    return original.slice(0, b) + block + original.slice(e + END.length);
  }
  // 首次：把原来的 `:root{ … }` 整段换掉（两份原型的写法都匹配这个正则）
  const m = /:root\{[\s\S]*?\n[ \t]*\}/.exec(original);
  if (!m) throw new Error('✗ 找不到 `:root{ … }` —— 原型文件结构变了，改这个脚本');
  return original.slice(0, m.index) + `:root{\n${block}\n}` + original.slice(m.index + m[0].length);
}

function main() {
  const check = process.argv.includes('--check');
  const theme = readTheme();
  const drifts = [];
  for (const file of FILES) {
    const p = join(ROOT, file.path);
    const original = readFileSync(p, 'utf8');
    const next = rewrite(original, buildBlock(file, theme));
    if (next === original) continue;
    if (check) {
      drifts.push(file.path);
    } else {
      writeFileSync(p, next);
      console.log(`✓ 已生成 ${file.path}`);
    }
  }
  if (check) {
    if (drifts.length) {
      console.error('✗ 原型的 :root 与 theme.dart 不一致（跑 node tool/gen-prototype-tokens.mjs 修复）：');
      for (const d of drifts) console.error(`    · ${d}`);
      process.exit(1);
    }
    // 自检：真源里的关键值必须真的解析到了（否则"零漂移"可能只是两边都空）
    for (const key of ['bg', 'surface', 'elevated', 'text3', 'accent', 'accentInk', 'pr']) {
      if (!theme.colors[key]) {
        console.error(`✗ 没解析到 theme.dart 的 ${key} —— 生成器失效了（它不该静默通过）`);
        process.exit(1);
      }
    }
    if (theme.nums.rCard !== '12') {
      console.error(`✗ 没解析到 rCard=12（得到 ${theme.nums.rCard}）—— 生成器失效了`);
      process.exit(1);
    }
    console.log('✓ 原型的 :root 与 theme.dart 一致（两份都核过）');
  }
}

main();
