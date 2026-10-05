#!/usr/bin/env node
/**
 * 练了么 · **工作台**（把"现在到底什么状态"收进一页）
 *
 * **它解决什么**：这些答案以前散在十几份文档 + 十几个命令 + 七八个目录里 ——
 * 版本在 `app_info.dart`、产物在 `dist/`、文档漂没漂要记住跑哪十几个守卫、
 * 真机装的是哪版要开终端敲 `adb`、埋点要 `node tool/analytics-report.mjs`、
 * "卡在你那边"在 `docs/your-todo.md`、"还剩什么"在 `release-checklist.md` /
 * `feature-backlog.md` / `ROADMAP.md` / `decision-index.md`。
 * 每次想知道"现在什么状态"都要翻一遍，而且**翻到的还可能是过期的**。
 *
 * 这个文件把那些**当场读一遍**，渲染成一页，并且**把数据来源写在脸上**：
 * 是真实用户数据、还是只有样例、还是这台机器压根连不上设备 —— 不许含糊。
 *
 * 用法：
 *   node tool/workbench.mjs                       # 一次性快照（终端打摘要）
 *   node tool/workbench.mjs --serve               # 本地工作台 http://127.0.0.1:3081（推荐）
 *   node tool/workbench.mjs --serve --port 3099
 *   node tool/workbench.mjs --out dashboard.html  # 落一个自包含 HTML（不启服务）
 *   node tool/workbench.mjs --data path/to/jsonl  # 指定埋点数据目录（默认 server/data）
 *   node tool/workbench.mjs --json                # 机器可读（给别的脚本用）
 *   node tool/workbench.mjs --selftest            # 自检（喂假仓库，验它算得对、也验它会说实话）
 *
 * **四条刻意的约束**（都不是技术限制，是产品判断）：
 *   1. **只监听 `127.0.0.1`，只读本机文件，不联网、不上传、没有鉴权。**
 *      它看的是你自己的开发机。把开发机的东西暴露到局域网上不是"方便"，是事故 ——
 *      所以**没有** `--host` 这种选项，也不打算加。
 *   2. **默认只跑"快守卫"**（十几秒内出结果的那批）。六层门禁要几分钟，
 *      放进页面刷新路径上会让这一页变得没人愿意开 —— 门禁有自己的按钮。
 *   3. **每个数字都带来源与时间。** 算不出来的显式标 `⊘`，
 *      业务指标（DAU/留存/崩溃率）**一格数字都不许画** ——
 *      一个会撒谎的看板比没有看板更坏。
 *   4. **不写回任何仓库文件。** 待办的勾选只存在你这个浏览器里（localStorage），
 *      服务端没有任何写文件的接口。看板要是能改仓库，"看到的"和"真的"就会开始分叉。
 *
 * 结构：采集逻辑分在 `tool/lib/collect-docs.mjs`（五份文档）与
 * `tool/lib/collect-repo.mjs`（版本/产物/git/资产/合规），本文件负责聚合、渲染、服务、自检。
 */

import { spawn, execFileSync } from 'node:child_process';
import { createServer } from 'node:http';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { buildReport, readEvents } from './analytics-report.mjs';
import {
  readRoadmapStages, readReleaseChecklist, readFeatureBacklog, readDecisionIndex, readTodos,
} from './lib/collect-docs.mjs';
import {
  readVersion, readChangelogHead, readChangelogTitles, readDist, readGit, readEvidence, readCompliance,
} from './lib/collect-repo.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const DEFAULT_PORT = 3081;

// ──────────────────────────────────────────────────────────── 采集：对账（快守卫）

/**
 * 只跑"快"的那批：文档 / 产物 / 文案对账。每一项都**必须能自己说清为什么存在**，
 * 因为工作台上它就是一格 ✓/✗ —— 说不清的守卫不该出现在这里，也不该存在。
 */
export const FAST_GUARDS = [
  ['check-doc-versions.mjs', '文档里的版本说法'],
  ['check-doc-facts.mjs', '文档里的数字说法'],
  ['check-doc-tables.mjs', '文档表格完整性'],
  ['check-doc-paths.mjs', '文档里的路径引用'],
  ['check-changelog.mjs', 'CHANGELOG 结构'],
  ['check-user-text.mjs', '界面文案（内部话/记号）'],
  ['check-store-forms.mjs', '商店表单对账'],
  ['check-screenshots.mjs', '三套商店截图'],
  ['check-dist.mjs', '交付目录'],
  ['check-guards-wired.mjs', '守卫接线'],
  ['check-ci.mjs', 'CI↔门禁'],
  ['check-deploy.mjs', '部署包'],
];

/**
 * 跑一个守卫，永远返回结果（超时/崩溃都算结果，不算异常）。
 *
 * ⚠️ `FAST_GUARDS` 里写的是**文件名**（显示用），路径要补上 `tool/` —— 第一版漏了这一步，
 * 13 个守卫**全部**报红，报的还是一句没头没脑的 `Node.js v22.22.2`（那是 node 找不到模块
 * 时崩掉的最后一行）。教训：**并发跑一堆外部命令时，"全部失败"要么是真塌了，
 * 要么是它自己路径拼错了** —— 页面把这种情况显示成"13/13 都没过"，看的人会去查文档，
 * 而真相在工作台自己的代码里。自检里因此加了一条：拿真文件跑一次，必须能跑起来。
 */
export function runGuard(rel, root = ROOT, timeoutMs = 30000) {
  const started = Date.now();
  try {
    const out = execFileSync('node', [join(root, 'tool', rel)], { cwd: root, encoding: 'utf8', timeout: timeoutMs, stdio: ['ignore', 'pipe', 'pipe'] });
    return { rel, ok: true, ms: Date.now() - started, detail: lastMeaningfulLine(out) };
  } catch (e) {
    const text = `${e.stdout || ''}${e.stderr || ''}`;
    const timedOut = e.killed || e.signal === 'SIGTERM';
    return {
      rel, ok: false, ms: Date.now() - started,
      detail: timedOut ? `超时（${timeoutMs / 1000}s）—— 它不该这么慢` : firstProblemLine(text),
    };
  }
}

/** 输出里第一行"问题"（✗ 开头那行），没有就退回最后一行有内容的话。 */
export function firstProblemLine(text) {
  const lines = String(text ?? '').split('\n').map((l) => l.replace(/\u001b\[[0-9;]*m/g, '').trim()).filter(Boolean);
  const bad = lines.find((l) => l.startsWith('✗') || l.includes('✗'));
  return bad || lines[lines.length - 1] || '（没有任何输出 —— 这也算异常）';
}

function lastMeaningfulLine(text) {
  const lines = String(text ?? '').split('\n').map((l) => l.replace(/\u001b\[[0-9;]*m/g, '').trim()).filter(Boolean);
  return lines[lines.length - 1] || '✓';
}

/** 跑 `copyright-pdf --check-docs`：它不在 `check-*.mjs` 命名里，但同样是"对账"。 */
export function runCopyrightCheck(root = ROOT) {
  try {
    const out = execFileSync('node', [join(root, 'tool/copyright-pdf.mjs'), '--check-docs'], { cwd: root, encoding: 'utf8', timeout: 60000 });
    return { rel: 'copyright-pdf.mjs --check-docs', ok: true, ms: 0, detail: lastMeaningfulLine(out) };
  } catch (e) {
    return { rel: 'copyright-pdf.mjs --check-docs', ok: false, ms: 0, detail: firstProblemLine(`${e.stdout || ''}${e.stderr || ''}`) };
  }
}

// ──────────────────────────────────────────────────────────── 采集：真机

function which(bin) {
  try {
    return execFileSync('bash', ['-lc', `command -v ${bin}`], { encoding: 'utf8' }).trim() || null;
  } catch { return null; }
}

function adbPath() {
  if (process.env.LIANLEME_ADB && existsSync(process.env.LIANLEME_ADB)) return process.env.LIANLEME_ADB;
  const fromPath = which('adb');
  if (fromPath) return fromPath;
  for (const p of [
    "/Volumes/Elliot's SSD/harness-deps/android-sdk/platform-tools/adb",
    join(process.env.HOME || '', 'Library/Android/sdk/platform-tools/adb'),
  ]) if (existsSync(p)) return p;
  return null;
}

/** 安卓真机：连着的设备 + 上面装的**我们那个包**的版本。连不上就说连不上。 */
export function readAndroid() {
  const adb = adbPath();
  if (!adb) return { available: false, why: '找不到 adb（设 LIANLEME_ADB 或 source tool/dev-env.sh）', devices: [] };
  try {
    const out = execFileSync(adb, ['devices'], { encoding: 'utf8', timeout: 15000 });
    const serials = out.split('\n').slice(1).map((l) => l.split('\t')).filter((p) => p[1] && p[1].trim() === 'device').map((p) => p[0].trim());
    const devices = serials.map((serial) => {
      try {
        const dumpsys = execFileSync(adb, ['-s', serial, 'shell', 'dumpsys', 'package', 'com.sdknwdtvpv.lianleme'], { encoding: 'utf8', timeout: 15000 });
        const vc = dumpsys.match(/versionCode=(\d+)/);
        const vn = dumpsys.match(/versionName=([\w.\-]+)/);
        // ⚠️ `dumpsys` 命令**跑成功**不等于这个包装着 —— 没装时它照样返回 0，
        // 只是输出里写着 "Unable to find package"。第一版把"跑成功"当成"装了"，
        // 于是在没装 App 的模拟器上渲染出「装着 ()」+「≠ 当前版本」这种胡话。
        const installed = Boolean(vn);
        return { serial, version: vn ? vn[1] : null, code: vc ? vc[1] : null, installed };
      } catch {
        return { serial, version: null, code: null, installed: false };
      }
    });
    return { available: true, why: null, devices, adb };
  } catch (e) {
    return { available: false, why: `adb 跑不起来：${(e.message || '').split('\n')[0]}`, devices: [] };
  }
}

/**
 * iOS 真机：`devicectl` 列出的已连接设备。
 *
 * ⚠️ 第一版解析的是**表格文本**（按 2 个以上空格切列），结果把连着的 iPhone 读成 0 台 ——
 * `devicectl` 的表里 Hostname 一列**经常是空的**，空列在按空白切分时会被吃掉，
 * 于是 `connected` 从第 4 列跑到了第 3 列，判断全错。**表格是给人看的，不是给程序看的**：
 * 改用 `--json-output`（结构化输出），解析逻辑抽成 [`parseIosJson`] 以便自检钉住这个坑。
 */
export function parseIosJson(raw) {
  const data = JSON.parse(raw);
  const devices = data?.result?.devices ?? [];
  return devices
    .map((d) => ({
      name: d?.deviceProperties?.name ?? '(无名)',
      udid: d?.identifier ?? '',
      // ⚠️ 机型在 `hardwareProperties.marketingName`（第一版取的是**不存在**的
      // `deviceProperties.modelIdentifier`，页面上就渲染成了一段空白 + 一个孤零零的「· iOS 27.2」）。
      model: d?.hardwareProperties?.marketingName ?? d?.hardwareProperties?.productType ?? '',
      os: d?.deviceProperties?.osVersionNumber ?? '',
      connected: (d?.connectionProperties?.tunnelState ?? '') === 'connected',
    }))
    .filter((d) => d.connected);
}

export function readIos() {
  if (!which('xcrun')) return { available: false, why: '这台机器没有 xcrun（非 macOS）', devices: [] };
  const tmp = join(tmpdir(), `lianleme-devices-${process.pid}.json`);
  try {
    execFileSync('xcrun', ['devicectl', 'list', 'devices', '--json-output', tmp, '--quiet'], { encoding: 'utf8', timeout: 25000 });
    return { available: true, why: null, devices: parseIosJson(readFileSync(tmp, 'utf8')) };
  } catch (e) {
    return { available: false, why: `devicectl 跑不起来：${(e.message || '').split('\n')[0]}`, devices: [] };
  } finally {
    try { rmSync(tmp, { force: true }); } catch { /* 清不掉就算了 */ }
  }
}

// ──────────────────────────────────────────────────────────── 采集：埋点

/**
 * 埋点看板。**关键不是算得快，是标签打得准**：
 *   * 目录不存在 / 没数据 → `empty`
 *   * 只有 `server/data` 里那份样例（本仓库自带的 3 条）→ `sample`
 *   * 有真机导出的事件（别的目录）→ `live`
 * 一个会撒谎的看板比没有看板更坏 —— 这三种状态在页面上**必须肉眼可分**。
 */
export function readAnalytics(dataDir, root = ROOT) {
  const events = existsSync(dataDir) ? readEvents(dataDir) : [];
  const report = buildReport(events);
  const files = existsSync(dataDir) ? readdirSync(dataDir).filter((n) => n.endsWith('.jsonl')) : [];

  // ⚠️ 判"这批是不是真人"只靠文件名与目录位置 —— 这是个**保守**的判据，故意宁可错杀：
  //   * 文件名里带 sample/demo/fixture → 样例；
  //   * 就是仓库自带那个样例目录（`server/data`）→ 样例；
  //   * 其余（比如部署后的 /var/lib/lianleme、或你 --data 指的真机导出目录）→ 真实。
  // 反过来的错（把真人数据当样例）只是少看一个数；而**把样例当真人**会让整页看板撒谎 ——
  // 所以这里不许用"事件条数多不多"这种猜法（第一版就是这么写的，3 条以上就当真，
  // 结果一份手工投递的测试数据会被显示成"真实用户"）。
  const SAMPLE_RE = /sample|demo|fixture/i;
  const isRepoFixture = resolve(dataDir) === resolve(join(root, 'server/data'));
  const namedSample = files.some((f) => SAMPLE_RE.test(f));
  let source = 'empty';
  if (report.events > 0) source = namedSample || isRepoFixture ? 'sample' : 'live';
  return {
    dir: dataDir, files, source, report,
    eventNames: [...new Set(events.map((e) => e.event).filter(Boolean))].sort(),
    why: namedSample ? '文件名里带 sample/demo/fixture' : (isRepoFixture ? '这是仓库自带的样例目录 server/data' : null),
  };
}

// ──────────────────────────────────────────── 业务指标：**只有占位，一格数字都不画**

/**
 * 线上业务指标的**声明式占位**。
 *
 * 现状必须先说清楚：**后端没部署，一个真实用户的事件都没有** ——
 * 所以 DAU / 留存 / 崩溃率 / 同步失败率这四格，**现在一个都算不出来**。
 *
 * 这一页的规矩是：**算不出来就写"⊘ 待接入" + 还差什么，绝不画 0、绝不画平线、绝不估。**
 * 一个会撒谎的看板比没有看板更坏 —— 尤其是这四个数，它们正是最容易被拿来"感觉一下"的数。
 *
 * 每条都写清 `requires`（要哪个埋点事件）与 `needs`（还差什么非代码的东西），
 * 所以接上后端的那一刻，这四格会自己亮起来，不需要回来改这一页。
 */
export const OPS_METRICS = [
  {
    key: 'dau', label: '日活 DAU',
    requires: ['app_open'],
    needs: '至少两天的真实事件（还要有一个真的收集端在跑）',
    why: '分母是"当天有 app_open 的设备"。没有后端就没有"当天"这件事。',
  },
  {
    key: 'retention_d1', label: '次日留存',
    requires: ['app_open'],
    needs: '同一台设备的跨天事件（D1 也开了 App）',
    why: '要跨天才有 D1。单台设备、单天数据算不出来。',
  },
  {
    key: 'crash_rate', label: '崩溃率',
    requires: ['app_crash'],
    needs: '客户端崩溃事件 —— 埋点字典里现在没有这一类',
    why: '不是"没数据"，是还没埋：要先在客户端加崩溃上报，再谈率。',
  },
  {
    key: 'sync_fail', label: '同步失败率（云备份）',
    requires: ['sync_failed'],
    needs: '真实同步链路 —— 该事件按设计有意不上报',
    why: '没有真实同步就不该有这个名字；发了就是编数据（见 docs/feature-backlog.md 第五节）。',
  },
];

/** 算这一格现在是"待接入"还是"有数"。返回 `{ key,state,detail }`，**永远不返回数字**。 */
export function opsStatus(a) {
  return OPS_METRICS.map((m) => {
    if (a.source === 'empty') return { key: m.key, state: 'waiting', detail: '还没有任何事件' };
    if (a.source === 'sample') return { key: m.key, state: 'waiting', detail: '样例数据不参与业务指标（它不是真人）' };
    const missing = m.requires.filter((e) => !a.eventNames.includes(e));
    if (missing.length) return { key: m.key, state: 'waiting', detail: `客户端还没有发 ${missing.join(' / ')} 事件` };
    return { key: m.key, state: 'ready', detail: '口径与数据都到位了，但工作台还没实现这一格的计算' };
  });
}

/**
 * CLI 摘要行。**抽成函数是为了能被自检** —— 2026-10-05 在这里抓到过一次
 * "工具自己在撒谎"：页面那段已经改成"看不到线上"了，**CLI 这行还硬编码写着
 * 「业务指标：4 格全部 ⊘ 待接入（还没有后端）」**，而后端当天已经上线。
 * 所以现在这行也走 `opsStatus()` 的口径，并照样声明"看不到线上"。
 */
export function summaryLines(state) {
  const v = state.version;
  const ops = opsStatus(state.analytics);
  const ready = ops.filter((o) => o.state === 'ready').length;
  const why = [...new Set(ops.filter((o) => o.state !== 'ready').map((o) => o.detail))];
  const lines = [];
  lines.push(`练了么 · 工作台快照\u3000v${v.version} (${v.build})`);
  lines.push(`  对账：${state.gates.guards.length - state.gates.failed}/${state.gates.guards.length} 通过`
    + (state.gates.failed ? `（${state.gates.guards.filter((g) => !g.ok).map((g) => g.rel).join(', ')}）` : ''));
  lines.push(`  最新改动：${state.changelog}`);
  if (state.git.available) lines.push(`  git：${state.git.head?.hash} · 工作区 ${state.git.changed} 个文件未提交`);
  lines.push(`  路线图：${state.roadmap.available ? `${state.roadmap.stages.filter((s) => s.status === 'done').length}/${state.roadmap.stages.length} 阶段完成` : `⊘ ${state.roadmap.why}`}`);
  lines.push(`  上架清单：${state.checklist.available ? `${state.checklist.totals.done}/${state.checklist.totals.total} 项完成` : `⊘ ${state.checklist.why}`}`);
  lines.push(`  卡在你那边：${state.todos.available ? `${state.todos.open.length} 件` : state.todos.why}`);
  lines.push(`  埋点：${SOURCE_LABEL[state.analytics.source][0]} · ${state.analytics.report.events} 条事件 / ${state.analytics.report.devices} 台设备`);
  lines.push(`  业务指标：${ready}/${ops.length} 格有数`
    + (ready === ops.length ? '' : ` · 其余的还差：${why.join('；')}`));
  lines.push('  （线上收集端在不在跑，这一页看不到 —— 自己验：curl -fsS https://<你的域名>/healthz）');
  lines.push(`  真机：安卓 ${state.devices.android.available ? `${state.devices.android.devices.length} 台` : state.devices.android.why}`
    + ` · iOS ${state.devices.ios.available ? `${state.devices.ios.devices.length} 台` : state.devices.ios.why}`);
  lines.push('  （要看页面：node tool/workbench.mjs --serve）');
  return lines;
}

// ──────────────────────────────────────────────────────────── 汇总

export function collect(opts = {}) {
  const root = opts.root || ROOT;
  const dataDir = opts.dataDir || join(root, 'server/data');
  const started = Date.now();
  const guards = opts.skipGuards ? [] : FAST_GUARDS.map(([rel]) => runGuard(rel, root)).concat([runCopyrightCheck(root)]);
  const state = {
    generatedAt: Date.now(),
    elapsedMs: 0,
    root,
    version: readVersion(root),
    changelog: readChangelogHead(root),
    changelogTail: readChangelogTitles(root, 8),
    dist: readDist(root),
    git: opts.skipGit ? { available: false, why: '已跳过' } : readGit(root),
    gates: { guards, failed: guards.filter((g) => !g.ok).length },
    devices: {
      android: opts.skipDevices ? { available: false, why: '已跳过', devices: [] } : readAndroid(),
      ios: opts.skipDevices ? { available: false, why: '已跳过', devices: [] } : readIos(),
    },
    analytics: readAnalytics(dataDir, root),
    todos: readTodos(root),
    roadmap: readRoadmapStages(root),
    checklist: readReleaseChecklist(root),
    backlog: readFeatureBacklog(root),
    decisions: readDecisionIndex(root),
    evidence: readEvidence(root),
    compliance: readCompliance(root),
  };
  state.elapsedMs = Date.now() - started;
  return state;
}

// ──────────────────────────────────────────────────────────── 渲染

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const kb = (n) => (n >= 1024 * 1024 ? `${(n / 1024 / 1024).toFixed(1)} MB` : `${(n / 1024).toFixed(0)} KB`);
const clock = (ms) => new Date(ms).toLocaleString('zh-CN', { hour12: false });
const pct = (v) => (v === null || v === undefined ? '—' : `${(v * 100).toFixed(1)}%`);

/**
 * ⚠️ 渲染进 HTML 的**每一句话**都要过这里一次。
 *
 * 为什么：`Text` / HTML **都不渲染 markdown** —— 写了 `**` 用户就真的看到星号。
 * 这条规矩是从 App 那边学来的（`tool/check-user-text.mjs` 的第一条），
 * 工作台第一版就犯过这个错（页面上印出「下面这些数**不代表任何真实用户**」）。
 * 自检里有一条硬断言：**渲染出的 HTML 里不许出现裸 `**`**。
 *
 * ⚠️ 文档里真的有不配对的 `**` —— 例如 `release-checklist.md` 的
 * 「4.5 ⛔ 云备份开关：一旦配上，政策**必须**同步改写」。
 * 所以**凡是文档来的标题/正文**，渲染前一律 `plain()`，不能只 `esc()`。
 */
export function plain(s) {
  return String(s ?? '')
    .replace(/\*\*/g, '')
    .replace(/~~/g, '')
    .replace(/`/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

/** 行内代码（`code`）渲染 —— 命令要能一眼看出来它是命令。 */
const code = (s) => `<code>${esc(s)}</code>`;

function card(id, title, body, note) {
  return `<section class="card" id="${esc(id)}" data-title="${esc(plain(title))}">
    <h2><a class="anchor" href="#${esc(id)}">#</a>${esc(title)}</h2>
    ${note ? `<p class="note">${note}</p>` : ''}${body}</section>`;
}

/** 进度条：`done/total`，没有条目时返回一句实话而不是一条 0% 的空条。 */
function bar(done, total, label = '') {
  if (!total) return '<div class="dim">没有可数的条目</div>';
  const w = Math.max(1, Math.round((done / total) * 100));
  return `<div class="bar"><div class="bar-fill" style="width:${w}%"></div></div>
    <div class="dim small">${esc(label)}${done} / ${total}${done === total ? ' · 全绿' : ''}</div>`;
}

/** 一条"解析不了"的实情（**不画假的进度条**，这是本页的规矩）。 */
const cannot = (why) => `<div class="warn">解析不了：${esc(plain(why))}<div class="dim small">这一格宁可空着，也不画一个猜出来的数。</div></div>`;

const CHECK_NOTE = '勾选只存在<strong>这个浏览器</strong>里（localStorage），<strong>不写回仓库任何文件</strong> —— 所以它不会和文档说两套话。文档里已经真的做完（划掉）的条目是禁用的。';

/**
 * 可勾选清单。
 *
 * ⚠️ **纯前端 + localStorage，服务端没有任何写文件的接口。**
 * 键：`<group>.<key>`，整张 map 存在 `lianleme.wb.checks` 里。
 * 页面上必须把这件事说明白（"只存在这个浏览器里，不写回仓库"）——
 * 否则人会以为勾了就等于改了文档，而下次刷新看到的又是原样。
 */
function checkList(group, items, opts = {}) {
  if (!items.length) return '<div class="dim">这一节里没有条目</div>';
  // 组名会变成 data-group，并且是 localStorage 键的前缀，所以必须过 plain()：
  // 文档标题里本来就带 ** 加粗（ROADMAP「（**最划算**）」、checklist「政策**必须**同步改写」），
  // 不归一化就两头都错 —— 星号漏到页面上显示，** 还被写进了键名。
  const g = plain(group);
  const rows = items.map((it, i) => {
    const key = `${g}.${it.key ?? i}`;
    const extra = opts.extra ? opts.extra(it) : '';
    return `<label class="li${it.done ? ' struck' : ''}">
      <input type="checkbox" data-ck="${esc(key)}"${it.done ? ' disabled' : ''}>
      <span class="li-text">${esc(plain(it.text))}</span>${extra}</label>`;
  }).join('');
  return `<div class="list" data-group="${esc(g)}">${rows}</div>`;
}

function versionBlock(s) {
  const v = s.version;
  if (!v.available) return cannot(v.why);
  const g = s.git;
  const rows = [
    `<tr><td class="k">App 版本</td><td class="mono big-num">${esc(v.version)} (${esc(v.build ?? '?')})</td><td class="dim">真源 ${code('app/lib/core/app_info.dart')} + ${code('app/pubspec.yaml')}</td></tr>`,
    `<tr><td class="k">最新改动</td><td colspan="2">${esc(plain(s.changelog))}</td></tr>`,
    `<tr><td class="k">备案号</td><td colspan="2">${v.filing ? esc(v.filing) : '<span class="dim">空（未备案）</span>'}</td></tr>`,
  ];
  if (g && g.available) {
    rows.push(`<tr><td class="k">git</td><td colspan="2"><span class="mono">${esc(g.head?.hash ?? '')}</span>
      <span class="dim">· ${esc(g.head?.date ?? '')} · ${esc(plain(g.head?.subject ?? ''))}</span>
      <div class="dim small">分支 ${esc(g.branch)} · 已提交未推送 ${g.ahead} / 落后 ${g.behind} ·
      <b class="${g.changed ? 'warn-ink' : ''}">工作区有 ${g.changed} 个文件改动未提交</b>${g.untracked ? `（其中未跟踪 ${g.untracked}）` : ''}</div></td></tr>`);
  } else {
    rows.push(`<tr><td class="k">git</td><td colspan="2" class="warn-ink">${esc(plain(g?.why ?? '读不到'))}</td></tr>`);
  }
  if (v.mismatch) {
    rows.push(`<tr><td colspan="3"><div class="warn">两处版本不一致：界面常量写 ${esc(v.mismatch.appInfo)}，pubspec 写 ${esc(v.mismatch.pubspec)} —— 这正是门禁第 2 层守着的那个坑</div></td></tr>`);
  }
  const stale = s.dist.stale ?? [];
  const staleRow = stale.length
    ? `<div class="warn">${code('dist/')} 里有<strong>不是当前版本</strong>的残留：${esc(stale.join(' · '))}<div class="dim small">这是本项目最容易出的事故（"拿错一份去上传"）—— 要么删掉，要么明确知道你为什么留着。</div></div>`
    : '<p class="note">交付目录里没有旧版本残留 ✓</p>';
  return `<table class="kv">${rows.join('')}</table>${staleRow}`;
}

function roadmapBlock(r) {
  if (!r.available) return cannot(r.why);
  const badge = { done: 'ok', partial: 'warn', paused: 'dim', todo: 'todo', unknown: 'dim' };
  const label = { done: '已完成', partial: '就差一步', paused: '已推后', todo: '未开始', unknown: '状态读不出' };
  const rows = r.stages.map((s) => `<tr>
    <td class="mono">${esc(s.n)}</td>
    <td>${esc(s.name)}<div class="dim small">${esc(s.statusText)}</div></td>
    <td><span class="pill ${badge[s.status] ?? 'dim'}">${esc(label[s.status] ?? s.status)}</span></td>
    <td class="dim">${esc(s.owner)}</td></tr>`).join('');
  const done = r.stages.filter((s) => s.status === 'done').length;
  return `${bar(done, r.stages.length, '阶段完成　')}
    <table class="grid"><tr><th>#</th><th>阶段</th><th>状态</th><th>卡在谁那</th></tr>${rows}</table>`;
}

function guardsBlock(g) {
  const rows = g.guards.map((x) => `<tr>
    <td class="mark ${x.ok ? 'ok' : 'bad'}">${x.ok ? '✓' : '✗'}</td>
    <td class="mono">${esc(x.rel)}</td>
    <td class="${x.ok ? 'dim' : 'bad'}">${esc(plain(x.detail))}</td>
    <td class="dim num">${(x.ms / 1000).toFixed(1)}s</td></tr>`).join('');
  const pass = g.guards.length - g.failed;
  return `<p class="big-num ${g.failed ? 'bad' : 'ok'}">${pass} / ${g.guards.length} 通过</p>
    <table class="grid"><tr><th></th><th>守卫</th><th>它说了什么</th><th>耗时</th></tr>${rows}</table>`;
}

function deviceBlock(state) {
  const a = state.devices.android;
  const i = state.devices.ios;
  const rows = [];
  if (!a.available) rows.push(`<div class="warn">Android：${esc(plain(a.why))}</div>`);
  else if (!a.devices.length) rows.push('<div class="warn">Android：adb 在，但<strong>没有连着的设备</strong></div>');
  else for (const d of a.devices) {
    const match = d.installed && d.version === state.version.version;
    const isEmu = /^emulator-/.test(d.serial);
    rows.push(`<div class="dev"><span class="pill ${match ? 'ok' : 'dim'}">${esc(d.serial)}</span>
      <span>${d.installed ? `装着 <b>${esc(d.version)} (${esc(d.code)})</b>` : '没装这个包'}</span>
      ${isEmu ? '<span class="dim">模拟器</span>' : ''}
      ${d.installed && !match ? `<span class="bad">≠ 当前 v${esc(state.version.version ?? '?')}</span>` : ''}</div>`);
  }
  if (!i.available) rows.push(`<div class="warn">iOS：${esc(plain(i.why))}</div>`);
  else if (!i.devices.length) rows.push('<div class="warn">iOS：没连着设备（插线 + 信任此电脑）</div>');
  else for (const d of i.devices) rows.push(`<div class="dev"><span class="pill ok">${esc(d.name)}</span><span>${esc(d.model)}${d.os ? ` · iOS ${esc(d.os)}` : ''} · 已连接</span></div>`);
  rows.push(`<p class="note">iOS 那台装的是哪一版，工作台看不到（${code('devicectl')} 没有"列已装 App"的子命令）—— 跑 ${code('tool/ios-device-run.sh')} 时终端会打出来。</p>`);
  return rows.join('');
}

const SOURCE_LABEL = {
  live: ['真实数据', 'ok', '这批来自实际收集到的事件（后端 / 真机导出）'],
  sample: ['样例数据 —— 不是真实用户', 'warn', '这是仓库自带的样例（server/data），一个真实用户都没有'],
  empty: ['没有数据', 'dim', '还没有任何事件。要看真实数据：先接后端，或从真机「导出统计事件」'],
};

function analyticsBlock(a) {
  const [label, cls, why] = SOURCE_LABEL[a.source];
  const r = a.report;
  const fbar = (name, value, target) => {
    const w = value === null || value === undefined ? 0 : Math.max(1, Math.min(100, value * 100));
    const tw = target === null || target === undefined ? null : Math.max(1, Math.min(100, target * 100));
    const hit = target !== null && target !== undefined && value !== null && value !== undefined && value >= target;
    return `<div class="funnel">
      <div class="fl"><span>${esc(name)}</span><span class="${hit ? 'ok' : 'dim'}">${pct(value)}${target !== null && target !== undefined ? ` <span class="dim">/ 目标 ${pct(target)}</span>` : ''}</span></div>
      <div class="track"><div class="fill ${hit ? 'good' : ''}" style="width:${w}%"></div>${tw ? `<div class="target" style="left:${tw}%"></div>` : ''}</div>
    </div>`;
  };
  const taps = r.tapCount ?? {};
  const tapRows = Object.keys(taps).sort().map((v) => `<tr><td class="mono">${esc(v)}</td><td class="num">${taps[v].n}</td><td class="num">${taps[v].median ?? '—'}</td><td class="num">${taps[v].p90 ?? '—'}</td></tr>`).join('');
  const notComputable = (r.antiMetrics.not_computable || []).map((x) => `<li class="dim">⊘ ${esc(plain(x))}</li>`).join('');
  return `
    <div class="banner ${cls}"><span class="dot ${cls}"></span><b>${esc(label)}</b>
      <span class="dim">· ${esc(why)}${a.why ? `（判据：${esc(a.why)}）` : ''}</span></div>
    <p class="note">数据目录 ${code(a.dir)} · ${a.files.length} 个 jsonl · <b>${r.events}</b> 条事件 / <b>${r.devices}</b> 台设备${a.eventNames.length ? ` · 事件种类 ${a.eventNames.length}` : ''}</p>
    ${a.source === 'sample' ? '<div class="warn">下面这些数<strong>不代表任何真实用户</strong>，只用来证明"口径算得出来"。</div>' : ''}
    ${a.source === 'empty' ? '<div class="warn">还没有数据 —— 所以下面每一格都是空的（不是 0）。这正是"接上之前"该有的样子，别把它当成"指标很差"。</div>' : ''}
    <div class="hero"><div class="hero-k">北极星 · 首次训练完成率</div>
      <div class="hero-v">${pct(r.northStar.rate)}</div>
      <div class="dim small">分母 ${r.northStar.denominator} 台有 app_open 的设备 · 目标 ≥ 55%</div></div>
    <h3>转化漏斗</h3>
    ${fbar('app_open', 1, null)}
    ${fbar('workout_started', r.funnel.workout_started, r.funnel.targets.workout_started)}
    ${fbar('first_set_logged', r.funnel.first_set_logged, r.funnel.targets.first_set_logged)}
    ${fbar('workout_finished', r.funnel.workout_finished, r.funnel.targets.workout_finished)}
    <h3>tap_count（发布门禁：中位数 / P90 不得高于上一版）</h3>
    ${tapRows ? `<table class="grid"><tr><th>版本</th><th>n</th><th>中位数</th><th>P90</th></tr>${tapRows}</table>` : '<div class="dim">还没有 set_logged 事件</div>'}
    <h3>反指标</h3>
    <div>训练中途流失率 <b>${pct(r.antiMetrics.abandoned_rate)}</b></div>
    <ul class="tight">${notComputable}</ul>`;
}

/** 业务指标那四格：**永远只有占位，一格数字都不许有**。 */
function opsBlock(a, repo) {
  const st = opsStatus(a);
  // ⚠️ 2026-10-04 验收时抓到的真问题：这段原来硬编码写着「收集端没部署」——
  // 而**收集端当天已经部署了**（`https://api.elliotli.work/healthz` 返回 ok）。
  // 一个"看不见线上"的工具却在替线上断言，正好踩中这个项目最在意的那类错
  // （过期状态比没有状态更坏）。改成：**只说自己验得到的事**，
  // 验不到的（线上收集端在不在跑）明说"看不到"并给出**一条自己能跑的命令**。
  const cloudOn = repo?.privacy?.cloudBackupInBuild === true;
  const facts = [
    '本页读到的这批事件里，<strong>一个真实用户的事件都没有</strong>（这一条是事实，不是估计）',
    cloudOn
      ? '客户端的包里<strong>已经</strong>编入服务器地址（<code>docs/privacy-facts.json</code>：cloudBackup.enabledInDistributedBuild = true）'
      : '客户端<strong>还没有</strong>编入服务器地址（<code>docs/privacy-facts.json</code>：cloudBackup.enabledInDistributedBuild ≠ true）'
        + ' —— 所以就算有人在用，事件也发不出来',
    '<strong>线上收集端在不在跑，这一页看不到</strong>（它只读本机、不联网）——'
      + '自己验一条：<code>curl -fsS https://&lt;你的域名&gt;/healthz</code>',
  ];
  const items = OPS_METRICS.map((m) => {
    const s = st.find((x) => x.key === m.key);
    return `<div class="ops ${s.state === 'ready' ? 'ready' : ''}">
      <div class="ops-label">${esc(m.label)}</div>
      <div class="ops-val">⊘ 待接入</div>
      <div class="dim small">${esc(s.detail)}</div>
      <div class="dim small">还需要：${esc(plain(m.needs))}</div>
      <details><summary class="dim small">为什么算不出来</summary><div class="dim small">${esc(plain(m.why))}</div></details>
    </div>`;
  }).join('');
  return `<div class="warn">这四格<strong>现在一个数都没有</strong> —— 不是"指标很差"，是<strong>还没有真实用户的数据</strong>：
    <ul class="tight">${facts.map((f) => `<li>${f}</li>`).join('')}</ul>
    两条都到位之后，这四格会自己亮起来。</div>
    <div class="ops-grid">${items}</div>
    <p class="note">刻意<strong>不画 0、不画平线、不画估值</strong>：这四个数最容易被拿来"感觉一下"，而一个会撒谎的看板比没有看板更坏。</p>`;
}

function todoBlock(t) {
  if (!t.available) return cannot(t.why);
  const secs = t.sections.map((s) => {
    if (!s.header || !s.header.length) return `<h3>${esc(plain(s.title))}</h3><div class="dim">${esc(plain(s.note ?? '这一节没有表'))}</div>`;
    const byId = new Map(s.items.map((x) => [x.id, x]));
    const items = s.items.map((it) => ({ key: it.id, text: `${it.id ? `${it.id}. ` : ''}${it.title}`, done: it.done }));
    const extra = (it) => {
      const raw = byId.get(it.key);
      if (!raw) return '';
      const cols = raw.cells.slice(2).map(plain).filter(Boolean);
      return cols.length ? `<div class="dim small">${esc(cols.join(' · '))}</div>` : '';
    };
    const left = s.items.filter((x) => !x.done).length;
    return `<h3>${esc(plain(s.title))} <span class="dim small">${left} 件没做 / 共 ${s.items.length}</span></h3>${checkList(`todo:${s.title}`, items, { extra })}`;
  }).join('');
  const mine = t.mine.length
    ? `<h3>我这边会做的（${t.mineOpen.length} 件进行中 / 共 ${t.mine.length}）<span class="dim small">不占你的时间</span></h3>
       ${checkList('todo:mine', t.mine.map((x, i) => ({ key: i, text: x.text, done: x.done })))}`
    : '';
  return `<p class="big-num ${t.open.length ? 'warn-ink' : 'ok'}">${t.open.length} 件卡在你那边</p>
    <p class="note">判据：本仓库的写法是<strong>做完了就划掉而不是删掉</strong>（划掉保留了"这件事曾经存在"），
      所以<strong>标题里还有删除线 = 已完成</strong>。${CHECK_NOTE}</p>
    ${secs}${mine}`;
}

function checklistBlock(c) {
  if (!c.available) return cannot(c.why);
  const secs = c.sections.map((s) => `
    <div class="sec">
      <h3>${s.hard ? '<span class="hard">⛔</span> ' : ''}${esc(plain(s.title))}
        <span class="dim small">${s.done} / ${s.total}</span></h3>
      ${s.items.length ? bar(s.done, s.total) : ''}
      ${checkList(`checklist:${s.title}`, s.items.map((x, i) => ({ key: i, text: x.text, done: x.done })))}
    </div>`).join('');
  const hardLeft = c.sections.filter((s) => s.hard && s.done < s.total).length;
  return `<p class="big-num ${hardLeft ? 'warn-ink' : 'ok'}">${c.totals.done} / ${c.totals.total} 项已完成</p>
    <p class="note"><span class="hard">⛔</span> = 硬门槛（这一步不过就上不了架）。还剩 <b>${hardLeft}</b> 个硬门槛节没走完。${CHECK_NOTE}</p>
    ${secs}`;
}

function backlogBlock(b) {
  if (!b.available) return cannot(b.why);
  const secs = b.sections.map((s) => {
    const title = `<h3>${esc(plain(s.title))} <span class="dim small">${s.kind === 'prose' ? '正文节' : `${s.done} / ${s.items.length} 已完成`}</span></h3>`;
    if (s.kind === 'prose') return `${title}<div class="dim">${esc(plain(s.note || '（这一节是叙述，没有可勾的条目）'))}</div>`;
    return `${title}${checkList(`backlog:${s.title}`, s.items.map((x, i) => ({ key: i, text: x.text, done: x.done })))}`;
  }).join('');
  return `<p class="note">这一份是<strong>功能/产品层面</strong>的待办；"卡在你那边"的资质与密钥在上一张卡 —— 两份各管一摊，不抄同一批事实。${CHECK_NOTE}</p>${secs}`;
}

function decisionsBlock(d) {
  if (!d.available) return cannot(d.why);
  const groups = d.groups.map((g) => {
    if (!g.rows.length) return `<h3>${esc(plain(g.title))} <span class="dim small">这一组没有表</span></h3>`;
    const byName = new Map(g.rows.map((r) => [r.name, r]));
    const items = g.rows.map((r) => ({ key: r.name, text: r.name, done: false }));
    const extra = (it) => {
      const row = byName.get(it.key);
      return row ? `<div class="dim small">触发条件：${esc(row.cond)}${row.src ? ` · 出处：${esc(row.src)}` : ''}</div>` : '';
    };
    return `<h3>${esc(plain(g.title))} <span class="dim small">${g.rows.length} 条</span></h3>${checkList(`dec:${g.title}`, items, { extra })}`;
  }).join('');
  return `<p class="note">这一页的价值不在条目本身（它自己写着"只做索引、不复制正文"），而在于<strong>分组</strong>：
    A 是"条件到了就能做"、B 是"价值判断上否掉的" —— 混成一列就等于把这份文档扔了。</p>${groups}`;
}

function evidenceBlock(e, live) {
  const thumb = (rel) => (live
    ? `<a href="/asset?f=${encodeURIComponent(rel)}" target="_blank"><img loading="lazy" src="/asset?f=${encodeURIComponent(rel)}" alt="${esc(rel)}" title="${esc(rel)}"></a>`
    : `<span class="thumb-ph dim">${esc(rel.split('/').pop())}</span>`);
  const groups = e.store.groups.map((g) => `
    <h3>${esc(g.rel)} <span class="dim small">${g.count} 张</span></h3>
    <div class="thumbs">${g.files.map((f) => thumb(f.rel)).join('')}</div>`).join('');
  const imgs = e.images;
  const shown = imgs.files.slice(0, 24);
  return `<p class="note">两组东西<strong>性质不同</strong>：${code('store-assets/')} 是要交给商店的提交材料（张数与尺寸有硬要求，由 ${code('tool/check-screenshots.mjs')} 核）；
     ${code('docs/images/')} 是"我们当时看到过什么"的走查证据图（不用交给任何人）。</p>
    ${groups || '<div class="dim">store-assets 里没有图片</div>'}
    <h3>${esc(imgs.rel)} <span class="dim small">${imgs.count} 张</span></h3>
    ${shown.length
      ? `<div class="thumbs">${shown.map((f) => thumb(f.rel)).join('')}</div>
         <div class="dim small">${live ? `页面里只放了前 ${shown.length} 张` : '静态快照模式只列文件名、不内联图片'}（共 ${imgs.count} 张），${live ? '点开可看原图。' : ''}</div>`
      : '<div class="dim">没有图</div>'}`;
}

function complianceBlock(c) {
  const d = c.deploy;
  const p = c.privacy;
  const deployLine = d.available
    ? `${d.present.length} 件${d.missing.length ? ` · <span class="bad">缺：${esc(d.missing.join(' / '))}</span>` : ' · 齐'}`
    : '<span class="bad">没有 server/deploy/ 目录</span>';
  const privacyRows = p.available ? [
    `<tr><td class="k">匿名统计默认</td><td><span class="pill ${p.analyticsDefaultOn ? 'warn' : 'ok'}">${p.analyticsDefaultOn ? '默认开（危险）' : '默认关 ✓'}</span></td><td class="dim">政策与代码双向核对由 ${code('tool/privacy-audit.mjs')} 做</td></tr>`,
    `<tr><td class="k">云备份进包了吗</td><td><span class="pill ${p.cloudBackupInBuild ? 'warn' : 'ok'}">${p.cloudBackupInBuild ? '是（政策必须同步改写）' : '否 ✓'}</span></td><td class="dim">编译期开关；false 时包里连入口都不出现</td></tr>`,
    `<tr><td class="k">埋点事件数</td><td class="mono">${p.events ?? '—'}</td><td class="dim">与政策正文逐条对账</td></tr>`,
    `<tr><td class="k">声明权限</td><td class="mono">${p.permissions.length} 条</td><td class="dim">${esc(p.permissions.join(' · '))}</td></tr>`,
  ].join('') : '';
  return `<table class="kv">
      <tr><td class="k">部署包</td><td colspan="2">${code('server/deploy/')} ${deployLine}<div class="dim small">服务器一旦买好，这一步是"一条命令"</div></td></tr>
    </table>
    <h3>隐私事实（政策 ↔ 代码的对账锚）</h3>
    ${p.available ? `<table class="kv">${privacyRows}</table>` : `<div class="warn">${esc(plain(p.why))}</div>`}
    <p class="note">这一格只报<strong>事实</strong>，不判"能不能上架" —— 那个结论要读 ${code('docs/your-todo.md')} 与 ${code('docs/release-checklist.md')} 里的人工结论。</p>`;
}

function changelogBlock(t) {
  if (!t.available) return cannot(t.why);
  if (!t.items.length) return '<div class="dim">CHANGELOG 里没有版本小节</div>';
  return `<ol class="timeline">${t.items.map((x) => `<li><div class="tl-t mono">${esc(x.title)}</div>
    ${x.summary ? `<div class="dim small">${esc(x.summary)}</div>` : ''}</li>`).join('')}</ol>
    <p class="note">只读头部 ${t.items.length} 节（不读全文：这份文件 380 KB 上下，而且正文里不配对的记号会漏到页面上）。</p>`;
}

function distBlock(s) {
  const d = s.dist;
  if (!d.available) return cannot(d.why);
  const rows = (list) => (list.length
    ? list.map((f) => `<tr><td class="mono">${esc(f.name)}</td><td class="num">${f.isDir ? '' : kb(f.bytes)}</td><td class="dim">${clock(f.mtime)}</td></tr>`).join('')
    : '<tr><td class="dim" colspan="3">空</td></tr>');
  return `<h3>${code('dist/')}</h3>
    <table class="grid"><tr><th>文件</th><th>大小</th><th>时间</th></tr>${rows(d.files)}</table>
    <h3>${code('dist/copyright/')}</h3>
    <table class="grid"><tr><th>文件</th><th>大小</th><th>时间</th></tr>${rows(d.copyright)}</table>`;
}

export function renderHtml(state, { gateLog = null, live = true } = {}) {
  const v = state.version;
  const guardBad = state.gates.failed;
  const stale = state.dist.stale ?? [];
  const dirty = state.git?.available ? state.git.changed : 0;
  // 总健康灯：判据写在这里，免得以后各人心里一杆秤
  const light = (guardBad || stale.length) ? 'bad' : (dirty ? 'warn' : 'ok');
  const lightText = (guardBad || stale.length)
    ? `有问题：${guardBad ? `${guardBad} 个守卫没过` : ''}${guardBad && stale.length ? ' · ' : ''}${stale.length ? '交付目录有旧版本残留' : ''}`
    : (dirty ? `可推进：工作区有 ${dirty} 个文件未提交` : '干净');

  const nav = [
    ['version', '版本'], ['roadmap', '路线图'], ['todos', '待办'], ['checklist', '上架清单'],
    ['guards', '对账'], ['gate', '门禁'], ['metrics', '指标'], ['backlog', '功能待办'],
    ['decisions', '决策'], ['devices', '真机'], ['compliance', '合规'], ['evidence', '证据'],
    ['changelog', '变更'], ['artifacts', '产物'],
  ].map(([id, label]) => `<a href="#${id}">${esc(label)}</a>`).join('');

  return `<!DOCTYPE html>
<html lang="zh-CN" data-theme="light"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>练了么 · 工作台 v${esc(v.version ?? '?')}</title>
<style>
  :root{
    color-scheme: light;
    --bg:#FBFAF7; --surface:#FFFFFF; --elevated:#F3F1EC; --line:#E7E4DD;
    --text:#1A1A1A; --text-2:#6B6B6B; --text-3:#9A9A9A;
    --accent:#2F6B4F; --accent-soft:#EAF2ED;
    --ok:#2E7D5B; --warn:#B07A1E; --warn-soft:#FBF3E2; --danger:#C0392B; --danger-soft:#FBEDEA;
    --radius:14px; --shadow:0 1px 2px rgba(0,0,0,.05), 0 6px 20px rgba(0,0,0,.04);
  }
  [data-theme="dark"]{
    color-scheme: dark;
    --bg:#0F1113; --surface:#17191C; --elevated:#202327; --line:#2B2F34;
    --text:#ECEFF1; --text-2:#A8B0B6; --text-3:#6E767C;
    --accent:#7FB98F; --accent-soft:#1B2620;
    --ok:#6FBF95; --warn:#D9A441; --warn-soft:#241E12; --danger:#E06C5E; --danger-soft:#241614;
    --shadow:none;
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--text);
    font:14px/1.65 -apple-system,BlinkMacSystemFont,"PingFang SC","Noto Sans CJK SC",system-ui,sans-serif;}
  .num,.mono,.big-num,.hero-v{font-variant-numeric:tabular-nums}
  .mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12.5px}
  header{position:sticky;top:0;z-index:9;background:var(--bg);border-bottom:1px solid var(--line);padding:14px 24px 10px}
  h1{margin:0 0 2px;font-size:20px;letter-spacing:.3px}
  h1 .dot{width:10px;height:10px;border-radius:50%;display:inline-block;margin-right:8px;vertical-align:middle}
  h2{margin:0 0 10px;font-size:15px}
  h3{margin:16px 0 6px;font-size:13px;color:var(--text-2);font-weight:600}
  .sub{color:var(--text-3);font-size:12.5px}
  main{padding:16px 24px 60px;max-width:1180px;margin:0 auto}
  .card{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);
    padding:16px 18px;margin:0 0 14px;box-shadow:var(--shadow)}
  .anchor{color:var(--line);text-decoration:none;margin-right:6px;font-weight:400}
  .anchor:hover{color:var(--accent)}
  .grid{width:100%;border-collapse:collapse}
  .grid th{text-align:left;color:var(--text-3);font-weight:500;font-size:12px;padding:2px 8px 6px 0}
  .grid td{padding:5px 8px 5px 0;border-top:1px solid var(--line);vertical-align:top}
  .kv{width:100%;border-collapse:collapse}
  .kv td{padding:6px 8px 6px 0;border-top:1px solid var(--line);vertical-align:top}
  .kv .k{color:var(--text-3);width:120px}
  .mark{width:22px;font-weight:700}
  .ok{color:var(--ok)} .bad{color:var(--danger)} .dim{color:var(--text-3)}
  .warn-ink{color:var(--warn)}
  .small{font-size:12px} .num{text-align:right;white-space:nowrap}
  code{background:var(--elevated);padding:1px 5px;border-radius:5px;font-size:12px;
    font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
  .note{color:var(--text-3);font-size:12px;margin:4px 0 10px}
  .warn{background:var(--danger-soft);border-left:3px solid var(--danger);padding:8px 12px;
    border-radius:8px;margin:8px 0;font-size:13px}
  .banner{display:flex;align-items:center;gap:8px;background:var(--elevated);border:1px solid var(--line);
    border-radius:10px;padding:8px 12px;margin:6px 0 10px;flex-wrap:wrap}
  .banner.ok{border-color:var(--ok)} .banner.warn{border-color:var(--warn)}
  .dot{width:9px;height:9px;border-radius:50%;display:inline-block}
  .dot.ok{background:var(--ok)} .dot.warn{background:var(--warn)} .dot.bad{background:var(--danger)} .dot.dim{background:var(--text-3)}
  .dev{display:flex;gap:10px;align-items:center;padding:5px 0;border-top:1px solid var(--line);flex-wrap:wrap}
  .pill{background:var(--elevated);border-radius:999px;padding:1px 9px;font-size:12px;white-space:nowrap}
  .pill.ok{color:var(--ok);background:var(--accent-soft)}
  .pill.warn{color:var(--warn);background:var(--warn-soft)}
  .pill.todo,.pill.dim{color:var(--text-3)}
  .big-num{font-size:26px;font-weight:700;margin:6px 0}
  .hero{margin:10px 0 4px}
  .hero-k{color:var(--text-3);font-size:12px}
  .hero-v{font-size:38px;font-weight:700;color:var(--accent);line-height:1.15}
  .funnel{margin:7px 0}
  .fl{display:flex;justify-content:space-between;font-size:12.5px}
  .track{position:relative;height:8px;background:var(--elevated);border-radius:999px;overflow:hidden}
  .fill{height:100%;background:var(--text-3);border-radius:999px}
  .fill.good{background:var(--ok)}
  .target{position:absolute;top:-2px;width:2px;height:12px;background:var(--text);opacity:.55}
  ul.tight{margin:4px 0 0;padding-left:18px}
  ul.tight li{font-size:12.5px}
  .bar{height:8px;background:var(--elevated);border-radius:999px;overflow:hidden;margin:4px 0 2px}
  .bar-fill{height:100%;background:var(--accent);border-radius:999px}
  .list{display:flex;flex-direction:column;gap:1px}
  .li{display:flex;gap:9px;align-items:flex-start;padding:5px 0;border-top:1px solid var(--line);cursor:pointer;flex-wrap:wrap}
  .li input{margin-top:4px;flex:0 0 auto;accent-color:var(--accent)}
  .li-text{flex:1 1 auto;min-width:60%}
  .li.struck .li-text{color:var(--text-3);text-decoration:line-through}
  .li .dim.small{flex:0 0 100%;margin-left:25px}
  .sec{margin-bottom:10px}
  .hard{color:var(--danger)}
  .timeline{margin:6px 0;padding-left:20px}
  .timeline li{margin:0 0 8px}
  .tl-t{font-weight:600}
  .thumbs{display:flex;flex-wrap:wrap;gap:6px;margin:6px 0}
  .thumbs img{width:78px;height:auto;border-radius:6px;border:1px solid var(--line);display:block}
  .thumb-ph{width:78px;height:40px;border-radius:6px;border:1px dashed var(--line);
    display:flex;align-items:center;justify-content:center;font-size:9px;overflow:hidden}
  .ops-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px;margin:10px 0}
  .ops{border:1px dashed var(--line);border-radius:12px;padding:10px 12px;background:var(--surface)}
  .ops.ready{border-style:solid;border-color:var(--ok)}
  .ops-label{font-size:12px;color:var(--text-3)}
  .ops-val{font-size:19px;font-weight:700;color:var(--text-3);margin:2px 0 4px}
  details summary{cursor:pointer;margin-top:4px}
  a{color:var(--accent)}
  .row{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
  button{background:var(--surface);color:var(--text);border:1px solid var(--line);border-radius:9px;
    padding:6px 12px;font-size:13px;cursor:pointer;font-family:inherit}
  button:hover{border-color:var(--text-3)}
  button:disabled{opacity:.5;cursor:default}
  input[type=search]{background:var(--surface);color:var(--text);border:1px solid var(--line);
    border-radius:9px;padding:6px 10px;font-size:13px;font-family:inherit;width:170px}
  nav{display:flex;gap:2px;flex-wrap:wrap;margin-top:8px}
  nav a{color:var(--text-2);text-decoration:none;font-size:12.5px;padding:3px 9px;border-radius:8px}
  nav a:hover{background:var(--elevated);color:var(--text)}
  pre{background:var(--elevated);border:1px solid var(--line);border-radius:10px;padding:12px;
    max-height:340px;overflow:auto;font-size:12px;margin:8px 0 0;white-space:pre-wrap}
  footer{color:var(--text-3);font-size:12px;padding:0 24px 40px;max-width:1180px;margin:0 auto}
  .hide{display:none !important}
  .cp{font-size:11px;padding:2px 7px;margin-left:4px;border-radius:7px}
</style></head>
<body>
<header>
  <h1><span class="dot ${light}"></span>练了么 <span style="color:var(--accent)">工作台</span>
    <span class="dim" style="font-size:14px;font-weight:400">v${esc(v.version ?? '?')} (${esc(v.build ?? '?')})</span></h1>
  <div class="sub">生成于 ${clock(state.generatedAt)} · 采集耗时 ${(state.elapsedMs / 1000).toFixed(1)}s ·
    <span class="${guardBad ? 'bad' : 'ok'}">对账 ${state.gates.guards.length - guardBad}/${state.gates.guards.length} 通过</span> ·
    <span class="${light === 'bad' ? 'bad' : (light === 'warn' ? 'warn-ink' : 'ok')}">${esc(lightText)}</span></div>
  <div class="row" style="margin-top:8px">
    <button onclick="location.search='?fresh=1'">重新采集</button>
    ${live ? '<button id="gatebtn" onclick="runGate()">跑六层门禁（几分钟）</button>'
    : `<span class="dim small">静态快照里跑不了门禁。要跑：</span>${code('./verify.sh')}<button class="cp" onclick="cp(this,'./verify.sh')">复制</button>`}
    <input type="search" id="q" placeholder="筛选卡片…" oninput="filterCards()">
    <button id="themebtn" onclick="toggleTheme()">暗色</button>
    <span class="dim small" id="ckmsg"></span>
    <span class="dim small" id="gatemsg"></span>
  </div>
  <nav>${nav}</nav>
</header>
<main>
  ${card('version', '现在是什么版本', versionBlock(state),
    `版本真源只有一个：${code('app/lib/core/app_info.dart')}；build number 在 ${code('app/pubspec.yaml')}。`)}
  ${card('roadmap', '路线图进度', roadmapBlock(state.roadmap),
    `来自 ${code('ROADMAP.md')} 的「一眼看懂」表 —— 它是那一页唯一的事实源。`)}
  ${card('todos', '卡在你那边的事', todoBlock(state.todos),
    `来自 ${code('docs/your-todo.md')}：二/三/四节是"必须你本人办"的，五节是"我这边会做的"，两者刻意分开。`)}
  ${card('checklist', '上架清单', checklistBlock(state.checklist),
    `来自 ${code('docs/release-checklist.md')} 的勾选项 —— 这是"能不能上架"最接近真实的一张清单。`)}
  ${card('guards', '对账（文档 / 产物 / 文案有没有漂）', guardsBlock(state.gates),
    '这些是<strong>快守卫</strong>（十几秒内出结果），每次刷新都当场重跑 —— 不是缓存的旧结论。六层门禁请点上面的按钮。')}
  ${card('gate', '门禁（六层）', `<div id="gateout">${gateLog
    ? `<pre>${esc(gateLog)}</pre>`
    : '<div class="dim">还没在工作台里跑过。点上面的「跑六层门禁」—— 输出会实时出现在这里（跑完刷新页面看「对账」那一栏）。</div>'}</div>`,
    `真正的发布判据永远是 ${code('./verify.sh')} 全绿；这张卡只是让你不用切终端。`)}
  ${card('metrics', '指标：埋点口径 + 业务（待接入）', `${analyticsBlock(state.analytics)}
    <h3>线上业务指标 —— 待接入</h3>${opsBlock(state.analytics, state.compliance)}`,
    `口径与 ${code('tool/analytics-report.mjs')} 是<strong>同一份实现</strong>（复用它，不重写）—— 所以页面上和命令行上永远不会是两个数。`)}
  ${card('backlog', '功能待办（不占你的时间）', backlogBlock(state.backlog),
    `来自 ${code('docs/feature-backlog.md')}。`)}
  ${card('decisions', '决策索引', decisionsBlock(state.decisions),
    `来自 ${code('docs/decision-index.md')}。`)}
  ${card('devices', '真机', deviceBlock(state),
    '这一格答的是"我手上这台机现在装的是哪一版" —— 与当前版本不一致时会点出来。')}
  ${card('compliance', '上架与合规开关', complianceBlock(state.compliance),
    `部署包在 ${code('server/deploy/')}；隐私事实在 ${code('docs/privacy-facts.json')}。`)}
  ${card('evidence', '资产与证据', evidenceBlock(state.evidence, live),
    live ? '缩略图点开看原图。' : '静态快照模式只列文件名，不内联图片。')}
  ${card('changelog', '变更时间线', changelogBlock(state.changelogTail), '')}
  ${card('artifacts', '产物', distBlock(state),
    `交付口：真机装 APK、商店传 AAB、软著交 PDF。文件名带版本号却不是当前版本 → 会被「版本」那张卡点出来。`)}
</main>
<footer>
  <b>这一页是什么、不是什么</b>：它<strong>只读本机文件</strong>、只监听 ${code('127.0.0.1')}、不联网、不上传、没有鉴权。
  它<strong>不是</strong>线上监控 —— 崩溃率 / DAU / 留存那几个数要等后端真的部署（那之前，埋点只能靠
  "我 → 隐私与关于 → 导出统计事件"从真机导出）。算不出来的地方它写 ${code('⊘')}，<strong>不画 0、不画平线</strong>。
  <br><br>
  <b>想让埋点变成真实数据，两条路</b>：① 部署收集端（${code('server/deploy/README.md')}），客户端配上报地址后自动上报；
  ② 从真机「导出统计事件」把 jsonl 放进一个目录，再 ${code('node tool/workbench.mjs --data 那个目录')}。
  两种数据在「指标」那张卡上<strong>一眼可分</strong>（看来源标签）。
  <br><br>
  <b>它不会改你的仓库</b>：勾选只写在这个浏览器的 localStorage 里，服务端没有任何写文件的接口。
</footer>
<script>
const CK_KEY = 'lianleme.wb.checks';
function loadChecks(){
  try { return JSON.parse(localStorage.getItem(CK_KEY) || '{}'); } catch (e) { return {}; }
}
function saveChecks(m){ try { localStorage.setItem(CK_KEY, JSON.stringify(m)); } catch (e) {} }
function ckCount(){
  const m = loadChecks();
  const boxes = document.querySelectorAll('input[data-ck]:not([disabled])');
  let n = 0;
  boxes.forEach(function(b){ if (m[b.dataset.ck]) n += 1; });
  const el = document.getElementById('ckmsg');
  if (el) el.textContent = boxes.length ? ('本机已勾 ' + n + ' / ' + boxes.length) : '';
}
function initChecks(){
  const m = loadChecks();
  document.querySelectorAll('input[data-ck]').forEach(function(b){
    if (b.disabled) return;
    b.checked = !!m[b.dataset.ck];
    b.addEventListener('change', function(){
      const mm = loadChecks();
      if (b.checked) mm[b.dataset.ck] = 1; else delete mm[b.dataset.ck];
      saveChecks(mm); ckCount();
    });
  });
  ckCount();
}
function toggleTheme(){
  const cur = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
  document.documentElement.dataset.theme = cur;
  try { localStorage.setItem('lianleme.wb.theme', cur); } catch (e) {}
  const b = document.getElementById('themebtn');
  if (b) b.textContent = cur === 'dark' ? '浅色' : '暗色';
}
function initTheme(){
  let t = null;
  try { t = localStorage.getItem('lianleme.wb.theme'); } catch (e) {}
  if (!t) t = (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) ? 'dark' : 'light';
  document.documentElement.dataset.theme = t;
  const b = document.getElementById('themebtn');
  if (b) b.textContent = t === 'dark' ? '浅色' : '暗色';
}
function filterCards(){
  const q = (document.getElementById('q').value || '').trim().toLowerCase();
  document.querySelectorAll('main .card').forEach(function(c){
    const hit = !q || (c.dataset.title || '').toLowerCase().includes(q) || c.textContent.toLowerCase().includes(q);
    c.classList.toggle('hide', !hit);
  });
}
function cp(btn, text){
  const done = function(){ const o = btn.textContent; btn.textContent = '已复制'; setTimeout(function(){ btn.textContent = o; }, 1200); };
  if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done, done);
  else {
    const t = document.createElement('textarea'); t.value = text; document.body.appendChild(t); t.select();
    try { document.execCommand('copy'); } catch (e) {}
    document.body.removeChild(t); done();
  }
}
async function runGate(){
  const msg = document.getElementById('gatemsg');
  const btn = document.getElementById('gatebtn');
  if (!location.protocol.startsWith('http')) { msg.textContent = '要跑门禁请用 --serve 模式打开这一页'; return; }
  btn.disabled = true; msg.textContent = '已启动…';
  try {
    const r = await fetch('/gate', { method: 'POST' });
    msg.textContent = r.ok ? '正在跑（输出在「门禁」卡里）' : ('启动失败：' + (await r.text()));
  } catch (e) { msg.textContent = '启动失败：' + e.message; btn.disabled = false; return; }
  poll();
}
async function poll(){
  const out = document.getElementById('gateout');
  const msg = document.getElementById('gatemsg');
  const btn = document.getElementById('gatebtn');
  try {
    const t = await (await fetch('/gate/log')).text();
    out.innerHTML = '<pre>' + t.replace(/[&<>]/g, function(c){ return {'&':'&amp;','<':'&lt;','>':'&gt;'}[c]; }) + '</pre>';
    const s = await (await fetch('/gate/status')).text();
    msg.textContent = s;
    if (!s.startsWith('done') && !s.startsWith('failed') && !s.startsWith('idle')) setTimeout(poll, 1500);
    else { btn.disabled = false; if (s !== 'idle') msg.textContent = s + '（刷新页面看「对账」那栏）'; }
  } catch (e) { setTimeout(poll, 2500); }
}
initTheme(); initChecks();
</script>
</body></html>`;
}

// ──────────────────────────────────────────────────────────── 服务

/** 这一页只监听 127.0.0.1、只读本机、**没有任何写文件的接口**。 */
export function createWorkbenchServer({ root, dataDir, port }) {
  const gate = { proc: null, status: 'idle', log: '', startedAt: 0, code: null };
  let allowedAssets = new Set();
  const refreshAssets = (ev) => {
    allowedAssets = new Set([
      ...[].concat(...ev.store.groups.map((g) => g.files.map((f) => f.rel))),
      ...ev.images.files.map((f) => f.rel),
    ]);
  };

  const server = createServer((req, res) => {
    const url = new URL(req.url, 'http://127.0.0.1');
    const send = (statusCode, body, type = 'text/html; charset=utf-8') => {
      res.writeHead(statusCode, { 'content-type': type, 'cache-control': 'no-store' });
      res.end(body);
    };
    try {
      if (req.method === 'POST' && url.pathname === '/gate') {
        if (gate.proc) return send(409, `已经在跑了（${gate.status}）`, 'text/plain; charset=utf-8');
        gate.status = 'running'; gate.log = ''; gate.startedAt = Date.now(); gate.code = null;
        gate.proc = spawn(join(root, 'verify.sh'), { cwd: root, env: process.env });
        const onData = (b) => { gate.log += b.toString(); if (gate.log.length > 400000) gate.log = gate.log.slice(-300000); };
        gate.proc.stdout.on('data', onData);
        gate.proc.stderr.on('data', onData);
        gate.proc.on('close', (c) => {
          gate.code = c;
          gate.status = c === 0 ? 'done ✓ 门禁全绿' : `failed ✗ 退出码 ${c}`;
          gate.proc = null;
        });
        return send(200, 'started', 'text/plain; charset=utf-8');
      }
      if (url.pathname === '/gate/log') return send(200, gate.log || '（还没有输出）', 'text/plain; charset=utf-8');
      if (url.pathname === '/gate/status') return send(200, gate.status, 'text/plain; charset=utf-8');
      if (url.pathname === '/healthz') return send(200, 'ok', 'text/plain; charset=utf-8');
      // 图片：**白名单**，只放行"这一页自己扫到的那些 .png"（防目录穿越）
      if (url.pathname === '/asset') {
        const f = url.searchParams.get('f') || '';
        if (!allowedAssets.has(f)) return send(403, '不在白名单里', 'text/plain; charset=utf-8');
        const p = join(root, f);
        if (!existsSync(p)) return send(404, '没有这个文件', 'text/plain; charset=utf-8');
        res.writeHead(200, { 'content-type': 'image/png', 'cache-control': 'max-age=60' });
        return res.end(readFileSync(p));
      }

      // 每次请求**重新采集**（这一页的全部价值就是"当场读一遍"）
      const state = collect({ root, dataDir });
      refreshAssets(state.evidence);
      if (url.pathname === '/json') return send(200, JSON.stringify(state, replacerJson, 2), 'application/json; charset=utf-8');
      return send(200, renderHtml(state, { gateLog: gate.log || (gate.status === 'running' ? '正在跑…' : null), live: true }));
    } catch (e) {
      return send(500, `工作台自己炸了：${esc(e.stack || e.message)}`);
    }
  });
  // 刻意只监听回环地址：把开发机的状态暴露到局域网不是"方便"，是事故
  server.on('error', (e) => { console.error(`✗ 起不来：${e.message}`); });
  return server;
}

const replacerJson = (k, v) => (typeof v === 'bigint' ? Number(v) : v);

// ──────────────────────────────────────────────────────────── 自检

export function selftest() {
  let bad = 0;
  const check = (label, cond, why = '') => {
    if (!cond) bad += 1;
    console.log(`  ${cond ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}${cond ? '' : `　→ ${why}`}`);
  };
  const root = mkdtempSync(join(tmpdir(), 'lianleme-wb-'));
  try {
    // 造一棵迷你的假仓库：只放"采集要读的东西"
    mkdirSync(join(root, 'app/lib/core'), { recursive: true });
    mkdirSync(join(root, 'dist/copyright'), { recursive: true });
    mkdirSync(join(root, 'docs'), { recursive: true });
    mkdirSync(join(root, 'server/data'), { recursive: true });
    mkdirSync(join(root, 'store-assets/screenshots'), { recursive: true });
    writeFileSync(join(root, 'app/lib/core/app_info.dart'), "const String kAppVersion = '9.9.9';\nconst String kAppFilingNumber = '';\n");
    writeFileSync(join(root, 'app/pubspec.yaml'), 'name: x\nversion: 9.9.9+42\n');
    writeFileSync(join(root, 'CHANGELOG.md'), '# 更新日志\n\n## v9.9.9 · 假的\n\n正文\n');
    writeFileSync(join(root, 'dist/练了么-v9.9.9.apk'), 'x');
    writeFileSync(join(root, 'dist/练了么-v1.0.0.apk'), 'x');           // 旧版本残留，必须被抓到
    writeFileSync(join(root, 'dist/copyright/练了么-源程序-V9.9.9.pdf'), 'x');
    writeFileSync(join(root, 'docs/your-todo.md'), [
      '# 待办', '', '## 二、必须你本人办的', '',
      '| # | 事项 | 为什么必须你来 | 卡住什么 | 备注 |',
      '|---|---|---|---|---|',
      '| 1 | **要你做的甲** | 因为实名 | 上架 | — |',
      '| 2 | ~~**已经做完的乙**~~ ✅ 你已做完 | 原因 | 已做完 | — |',
      '| 3 | **要你做的丙** | 因为付款 | 700/年 | — |', '',
      '## 三、需要你拍板的技术选择', '',
      '| # | 选择 | 为什么问你 | 我的建议 |',
      '|---|---|---|---|',
      '| 1 | **拍板的事** | 我不能替你决定 | 当天 |', '',
      '## 五、我这边接下来会做的', '',
      '- 一件还没做的事', '',
    ].join('\n'));
    writeFileSync(join(root, 'docs/release-checklist.md'), [
      '# 清单', '', '## 1. ⛔ 真机验证', '', '- [x] 已做完', '- [ ] 没做完', '',
      '## 2. 发布签名', '', '- [ ] 生成 keystore', '',
    ].join('\n'));
    writeFileSync(join(root, 'docs/feature-backlog.md'), [
      '# 待办', '', '## 一、现在就能做', '',
      '| # | 决定 | 现状 |', '|---|---|---|', '| 1 | 还没做 | 待定 |', '',
    ].join('\n'));
    writeFileSync(join(root, 'docs/decision-index.md'), [
      '# 索引', '', '## A. 有解禁条件的', '',
      '| 能力 | 触发条件 | 出处 |', '|---|---|---|', '| Watch | DAU 稳定 | x.md |', '',
    ].join('\n'));
    // ★ 标题里带不配对的 ** —— 真文档就有一个（release-checklist 的 4.5 节）。
    //   渲染层只 esc 不 plain 的话，页面上就会印出星号。
    writeFileSync(join(root, 'ROADMAP.md'), [
      '# 路线图', '', '## 一眼看懂', '',
      '| # | 阶段 | 状态 | 卡在谁那 |', '|---|---|---|---|',
      '| **0** | 钉住工程 | ✅ 完成 | — |',
      '| **3** | 政策**必须**同步改写 | ⬜ 未开始 | 只能人做 |', '',
    ].join('\n'));
    writeFileSync(join(root, 'docs/privacy-facts.json'), JSON.stringify({
      analyticsOptIn: { defaultOn: false }, cloudBackup: { enabledInDistributedBuild: false },
      events: [{}, {}], permissions: [{ name: 'android.permission.INTERNET' }], injectedPermissions: [],
      neverCollected: [{}],
    }));
    mkdirSync(join(root, 'server/deploy'), { recursive: true });
    for (const f of ['install.sh', 'Caddyfile', 'lianleme-collector.service', 'lianleme-backend.service', 'README.md']) {
      writeFileSync(join(root, 'server/deploy', f), 'x');
    }
    writeFileSync(join(root, 'server/data/events-sample.jsonl'),
      ['{"event":"app_open","device_id":"d1","version":"9.9.9","ts":1}',
        '{"event":"workout_started","device_id":"d1","version":"9.9.9","ts":2}',
        '{"event":"set_logged","device_id":"d1","app_version":"9.9.9","tap_count":4,"ts":3}'].join('\n') + '\n');

    const v = readVersion(root);
    check('版本从 app_info + pubspec 读出来', v.version === '9.9.9' && v.build === '42', JSON.stringify(v));
    check('CHANGELOG 头一行读出来', readChangelogHead(root) === 'v9.9.9 · 假的', readChangelogHead(root));

    const d = readDist(root);
    check('dist 列出文件', d.files.length === 2, JSON.stringify(d.files.map((f) => f.name)));
    check('★ 旧版本残留会被点名（这是最容易出的事故）',
      d.stale.length === 1 && d.stale[0] === '练了么-v1.0.0.apk', JSON.stringify(d.stale));

    const t = readTodos(root);
    check('待办解析：二/三 两节被算进来、五节单独走',
      t.items.length === 4, JSON.stringify(t.items.map((i) => `${i.id}:${i.title}`)));
    check('★ 划掉的（已做完）不算"卡在你那边"',
      t.open.length === 3 && !t.open.some((i) => i.title.includes('乙')), JSON.stringify(t.open.map((i) => i.title)));
    check('五节进 mine，不混进"卡你"', t.mine.length === 1 && t.mineOpen.length === 1, JSON.stringify(t.mine));

    const a = readAnalytics(join(root, 'server/data'), root);
    check('★ 只有样例数据时必须自报家门是 sample（会撒谎的看板比没有更坏）', a.source === 'sample', a.source);
    check('埋点：事件数与设备数算得对', a.report.events === 3 && a.report.devices === 1, JSON.stringify({ e: a.report.events, d: a.report.devices }));
    check('埋点：北极星分母是"有 app_open 的设备"', a.report.northStar.denominator === 1, JSON.stringify(a.report.northStar));
    check('埋点：tap_count 按版本分组', a.report.tapCount['9.9.9']?.median === 4, JSON.stringify(a.report.tapCount));

    // ★ 判据必须**保守**：宁可信其有。第一版按"条数 > 3 就算真实"，
    // 于是一份手工投递的测试数据会被显示成"真实用户"—— 一页看板撒的谎，比少看一个数坏得多。
    const lookReal = join(root, 'look-real');
    mkdirSync(lookReal, { recursive: true });
    writeFileSync(join(lookReal, 'events-2026-01-01.jsonl'),
      new Array(9).fill(0).map((_, i) => JSON.stringify({ event: 'app_open', device_id: 'd' + i, ts: 1, app_version: '9.9.9' })).join('\n') + '\n');
    check('★ 一个"看着像真的"的目录（文件名没有 sample、事件还不少）→ 算真实数据',
      readAnalytics(lookReal, root).source === 'live', readAnalytics(lookReal, root).source);
    check('★ 仓库自带的样例目录 → 永远算样例（不看条数）',
      readAnalytics(join(root, 'server/data'), root).source === 'sample');

    const emptyA = readAnalytics(join(root, 'nope'), root);
    check('没有数据目录时是 empty 而不是崩', emptyA.source === 'empty' && emptyA.report.events === 0, emptyA.source);

    const state = {
      generatedAt: Date.now(), elapsedMs: 12, root,
      version: v, changelog: readChangelogHead(root),
      changelogTail: { available: true, why: null, items: [{ title: 'v9.9.9 · 假的', summary: '正文' }] },
      dist: d,
      git: { available: true, branch: 'main', ahead: 0, behind: 0, changed: 3, untracked: 1, head: { hash: 'abc1234', date: '2026-01-01', subject: '假的提交' } },
      gates: { guards: [{ rel: 'check-x.mjs', ok: false, ms: 900, detail: '✗ 假的失败' }], failed: 1 },
      devices: {
        android: { available: true, devices: [{ serial: 'S', version: '1.0.0', code: '1', installed: true }] },
        ios: { available: false, why: '没有 xcrun', devices: [] },
      },
      analytics: a, todos: t,
      roadmap: readRoadmapStages(root), checklist: readReleaseChecklist(root),
      backlog: readFeatureBacklog(root), decisions: readDecisionIndex(root),
      evidence: readEvidence(root), compliance: readCompliance(root),
    };
    const html = renderHtml(state);
    check('HTML 里带上了版本号', html.includes('9.9.9 (42)'), '没渲染版本');
    check('★ 埋点不是真实数据时，页面必须出现警示', html.includes('样例数据 —— 不是真实用户'), '没警示');
    check('★ 真机装的版本与当前不一致时要点出来', html.includes('≠ 当前 v9.9.9'), '没对比版本');
    check('★ 旧版本残留要在页面上有话说', html.includes('拿错一份去上传'), '没提示残留');
    check('HTML 是自包含的（没有外链脚本/样式）', !/<script[^>]+src=|<link[^>]+stylesheet/.test(html), '有外链');
    // ★ 这条规矩是从 app 那边学来的（`tool/check-user-text.mjs` 第一条）：`Text`/HTML **都不渲染 markdown**，
    // 写了 `**` 用户就真的看到星号。工作台第一版就犯了这个错（"下面这些数**不代表任何真实用户**"）。
    // 失败时把"漏在哪"直接贴出来：这条断言是全局的（任何来源都拦），只说布尔值的话
    // 就得去翻几十 KB 的 HTML 才能定位 —— 第一版就是这么栽的。
    const bareAt = html.indexOf('**');
    check('★ 工作台 HTML 里不许出现裸的 markdown 记号 **', bareAt === -1,
      bareAt === -1 ? '' : `在第 ${bareAt} 字节处：…${html.slice(Math.max(0, bareAt - 45), bareAt + 45).replace(/\s+/g, ' ')}…`);
    check('★ 文档标题里不配对的 ** 也不许漏到页面上（ROADMAP 夹具里故意放了一个）',
      html.includes('政策必须同步改写') && !html.includes('政策**必须**同步改写'), '文档标题的记号漏了');
    check('★ 组名（data-group / localStorage 键）也要是纯文本，不许把 ** 写进键名',
      !/data-(group|ck)="[^"]*\*\*/.test(html), '键名里混进了 markdown 记号');

    const emptyHtml = renderHtml({
      ...state,
      analytics: { ...a, source: 'empty', eventNames: [], report: buildReport([]) },
    });
    check('★ 没有数据时不许说"这些数不代表真实用户"（那时根本没有数）',
      !emptyHtml.includes('不代表任何真实用户') && emptyHtml.includes('还没有数据'), '空状态的措辞不对');

    // ★ 业务指标占位：一个字都不许算出来，更不许画 0 或平线
    const opsHtml = opsBlock(a);
    const opsVals = [...opsHtml.matchAll(/<div class="ops-val">([^<]*)<\/div>/g)].map((m) => m[1]);
    check('★ 业务指标（DAU/留存/崩溃率/同步失败率）四格全部是「⊘ 待接入」',
      opsVals.length === OPS_METRICS.length && opsVals.every((x) => x === '⊘ 待接入'), JSON.stringify(opsVals));
    check('★ 业务指标里不许出现任何百分号（画了百分比就是撒谎）', !opsHtml.includes('%'), '出现 % 了');
    check('★ 业务指标里不许出现数字型读数', !/<div class="ops-val">[^<]*\d[^<]*<\/div>/.test(opsHtml), 'ops-val 里有数字');
    check('★ 同步失败率要写明"按设计有意不上报"（这是事实，不是缺数据）',
      opsHtml.includes('按设计有意不上报'), '没写清');
    check('★ 没有后端时四格都要说清"还需要什么"',
      (opsHtml.match(/还需要：/g) || []).length === OPS_METRICS.length, (opsHtml.match(/还需要：/g) || []).length + ' 处');
    // ★ 2026-10-04 验收抓到的真问题：这段文案原来硬编码断言「收集端没部署」，
    // 而当天收集端**已经部署**了（api.elliotli.work/healthz 返回 ok）。
    // 工作台不联网、看不到线上 —— 那就**不许替线上断言**，只能说自己验得到的 + 给一条人能跑的命令。
    check('★ 不许断言线上收集端在不在跑（它看不到）—— 要写"看不到"并给出验证命令',
      !/收集端没部署|收集端没在跑|还没有后端/.test(opsHtml) && opsHtml.includes('看不到')
        && opsHtml.includes('curl -fsS https://'),
      '还在替线上断言');
    const opsNoCloud = opsBlock(a, { privacy: { available: true, cloudBackupInBuild: false } });
    check('★ 业务指标那段里不许出现反引号（HTML 不渲染 markdown，用户会看到 `` ）',
      !opsHtml.includes('`'), '有反引号');
    check('★ 客户端没编入地址时，四格那段要如实说"还没编入"（而不是笼统的"没有后端"）',
      opsNoCloud.includes('还没有') && opsNoCloud.includes('cloudBackup.enabledInDistributedBuild'),
      '没按事实说话');
    const opsCloud = opsBlock(a, { privacy: { available: true, cloudBackupInBuild: true } });
    check('★ 客户端已编入地址时，那段要改成"已经"（同一段文案必须跟着事实走）',
      opsCloud.includes('已经') && !opsCloud.includes('还没有</strong>编入'), '没跟着事实走');

    // ★ 2026-10-05：同一条规矩要管到 **CLI 摘要**——页面改了，命令行那行还硬编码写着
    //   「业务指标：4 格全部 ⊘ 待接入（还没有后端）」，而后端那天早上就上线了。
    const slEmpty = summaryLines({
      ...state, analytics: { ...a, source: 'empty', eventNames: [], report: buildReport([]) },
    }).join('\n');
    check('★ CLI 摘要里也不许替线上断言（"还没有后端"/"收集端没部署"一律不许出现）',
      !/还没有后端|收集端没部署|收集端没在跑/.test(slEmpty), '命令行又在替线上断言');
    check('★ CLI 摘要要声明"线上看不到"并给出那条 curl',
      slEmpty.includes('看不到') && slEmpty.includes('curl -fsS https://'), '没写清');
    check('★ CLI 摘要里的业务指标必须说出**真实原因**（空数据时是"还没有任何事件"）',
      slEmpty.includes('业务指标：0/') && slEmpty.includes('还没有任何事件'),
      slEmpty.split('\n').find((l) => l.includes('业务指标')));

    // ★ 待办只读：页面要说明白、服务端不许有写文件的接口
    check('★ 待办勾选说明写在页面上（"不写回仓库任何文件"）', html.includes('不写回仓库任何文件'), '没说明');
    check('★ 勾选走 localStorage', html.includes('localStorage') && html.includes('data-ck='), '没有本地存储');
    const src = readFileSync(fileURLToPath(import.meta.url), 'utf8');
    const srvBody = src.slice(src.indexOf('export function createWorkbenchServer'), src.indexOf('const replacerJson ='));
    check('★ 服务端没有任何写文件的接口（createWorkbenchServer 段里不许出现 writeFileSync / appendFile）',
      !/writeFileSync|appendFileSync|createWriteStream/.test(srvBody), '服务端能写文件');

    // ★ 解析不了时不许画假的进度条
    const broken = renderHtml({
      ...state,
      roadmap: { available: false, why: '找不到「一眼看懂」表', stages: [] },
      checklist: { available: false, why: '找不到编号节', sections: [], totals: { done: 0, total: 0 } },
    });
    check('★ 路线图解析不了时写"解析不了"，不画假进度',
      broken.includes('解析不了') && broken.includes('也不画一个猜出来的数'), '没诚实标出');
    check('★ 两处解析失败都要各自标出来（不是整页崩掉）',
      (broken.match(/解析不了/g) || []).length >= 2, '只标了一处');

    // ★ 静态快照模式：门禁按钮要降级成可复制命令
    const staticHtml = renderHtml(state, { live: false });
    check('★ --out 静态模式：门禁按钮降级成可复制的命令',
      !staticHtml.includes('id="gatebtn"') && staticHtml.includes('./verify.sh'), '没降级');

    // ★ 浅色 + 暗色两套主题都要在（IDE 是浅色，但夜里可能想切暗）
    check('★ HTML 同时含浅色 token 与 [data-theme="dark"] 覆盖块',
      staticHtml.includes('data-theme="dark"') && staticHtml.includes('--bg:#FBFAF7'), '主题不全');

    // ★ 这个坑真踩过：`devicectl` 的表格里 Hostname 可能是空的，按空白切列会把
    // `connected` 读错位置 —— 于是连着的 iPhone 被算成 0 台。改用结构化输出后有这条钉着。
    const iosFixture = JSON.stringify({ result: { devices: [
      { identifier: 'UDID-1', deviceProperties: { name: '李松的iPhone', osVersionNumber: '27.2' }, hardwareProperties: { marketingName: 'iPhone 17 Pro', productType: 'iPhone18,1' }, connectionProperties: { tunnelState: 'connected' } },
      { identifier: 'UDID-2', deviceProperties: { name: '旧机', modelIdentifier: 'iPhone14,2', osVersionNumber: '17.0' }, connectionProperties: { tunnelState: 'disconnected' } },
    ] } });
    const iosDevices = parseIosJson(iosFixture);
    check('★ iOS 设备解析（只算 connected；不再按表格切列）',
      iosDevices.length === 1 && iosDevices[0].name === '李松的iPhone' && iosDevices[0].os === '27.2',
      JSON.stringify(iosDevices));
    check('★ iOS 机型取 hardwareProperties（取错了会渲染成一段空白 + 「· iOS 27.2」）',
      iosDevices[0].model === 'iPhone 17 Pro', JSON.stringify(iosDevices[0]));

    const notInstalled = renderHtml({ ...state, devices: { ...state.devices,
      android: { available: true, devices: [{ serial: 'emulator-5554', version: null, code: null, installed: false }] } } });
    check('★ 安卓没装包时不许渲染成「装着 ()」，也不许比版本',
      notInstalled.includes('没装这个包') && !notInstalled.includes('装着 <b> ()'), '没装包的渲染有问题');
    check('★ 模拟器要标出来（它和真机混在一起会让人误判"装了几台机"）',
      notInstalled.includes('模拟器'), '没标模拟器');

    check('渲染出来的失败守卫是红的', html.includes('mark bad'), '失败守卫没标红');
    check('★ git 读不到时页面要如实说，不许当成"干净"',
      renderHtml({ ...state, git: { available: false, why: '跑不了 git' } }).includes('跑不了 git'), '没如实说');

    // ⚠️ 2026-10-04 真踩过：`FAST_GUARDS` 里是裸文件名，`join(root, rel)` 少了 `tool/` ——
    // 于是 13 个守卫**全部**报红（报的还是没头没脑的 "Node.js v22.22.2"）。
    // 这条自检在**真仓库**上跑一次真守卫：路径拼错 / node 起不来 / 工具被改名，都会在这里红。
    const real = runGuard('check-doc-versions.mjs', ROOT);
    check('★ 拿真仓库跑一次真守卫（防止"全部失败"其实是路径拼错）',
      real.ok && !/Node\.js v/.test(real.detail), `${real.detail}`);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
  if (bad) {
    console.error(`\n✗ 自检失败 ${bad} 项 —— 工作台本身不可信，先修它`);
    process.exit(1);
  }
  console.log('\n✓ 自检通过（版本/产物残留/待办/埋点自报家门/业务占位不撒谎/只读/真机解析/真守卫都算得对）');
}

// ──────────────────────────────────────────────────────────── CLI

if (process.argv[1] && process.argv[1].endsWith('workbench.mjs')) {
  const argv = process.argv.slice(2);
  const argOf = (n, d) => { const i = argv.indexOf(n); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };
  const root = resolve(argOf('--root', ROOT));
  const dataDir = resolve(argOf('--data', join(root, 'server/data')));
  const port = Number(argOf('--port', DEFAULT_PORT));

  if (argv.includes('--selftest')) {
    selftest();
  } else if (argv.includes('--serve')) {
    const server = createWorkbenchServer({ root, dataDir, port });
    server.listen(port, '127.0.0.1', () => {
      console.log(`练了么 · 工作台　http://127.0.0.1:${port}/`);
      console.log('  只监听 127.0.0.1 · 只读本机文件 · 不联网 · 每次刷新当场重新采集');
      console.log('  不会改你的仓库：勾选只写在这个浏览器里');
      console.log(`  埋点数据目录：${dataDir}`);
    });
  } else {
    const state = collect({ root, dataDir });
    const html = renderHtml(state, { live: false });
    const out = argOf('--out', null);
    if (out) { writeFileSync(resolve(out), html); console.log(`✓ 已写出 ${resolve(out)}`); }
    if (argv.includes('--json')) {
      console.log(JSON.stringify(state, replacerJson, 2));
    } else if (!out) {
      for (const line of summaryLines(state)) console.log(line);
    }
  }
}
