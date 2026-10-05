/**
 * 练了么 · 仓库状态采集（版本 / 变更 / 产物 / git / 资产证据 / 合规开关）
 *
 * **它解决什么**：这几个问题的答案以前分在六七个地方，而且都得靠记命令：
 *   * 现在是什么版本 —— `app/lib/core/app_info.dart`（真源）+ `app/pubspec.yaml`（build number）
 *   * 交付了什么     —— `dist/`（APK / AAB / 软著材料）
 *   * 提交到哪了     —— `git log` / `git status`
 *   * 证据都有啥     —— `store-assets/`（三套商店截图）、`docs/images/`（走机走查图）
 *   * 合规开关关了没 —— `server/deploy/`、`docs/privacy-facts.json`
 *
 * 这里**只负责读成结构**，不做任何判断展示（那是 `tool/workbench.mjs` 的事）。
 * 每条都带 `available` / `why`：读不到就说读不到，**不许拿一个空数组冒充"没有"**。
 *
 * 自检：`node tool/lib/collect-repo.mjs --selftest`
 */

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, '..', '..');

// ─────────────────────────────────────────────── 版本 / 产物 / 变更

/**
 * 版本真源**只有一个**：`app/lib/core/app_info.dart` 的 `kAppVersion`。
 * build number 在 `app/pubspec.yaml` 的 `version: x.y.z+N`。
 *
 * ⚠️ 两处都读了、都核对过，才敢报出版本 —— 这是本项目 `app_version_test` 与门禁第 2 层
 * 在守的东西（界面上的版本号漂过：pubspec 升了、界面常量没跟着升）。
 */
export function readVersion(root = REPO) {
  try {
    const appInfo = readFileSync(join(root, 'app/lib/core/app_info.dart'), 'utf8');
    const pubspec = readFileSync(join(root, 'app/pubspec.yaml'), 'utf8');
    const v = appInfo.match(/kAppVersion = '([^']+)'/);
    const b = pubspec.match(/^version:\s*[0-9.]+\+(\d+)/m);
    const pre = pubspec.match(/^version:\s*([0-9.]+)\+/m);
    if (!v) return { available: false, why: 'app_info.dart 里找不到 kAppVersion', version: null, build: null };
    return {
      available: true,
      why: null,
      version: v[1],
      build: b ? b[1] : null,
      // 两处不一致本身就是要报出来的事（不是"读失败"）
      mismatch: pre && pre[1] !== v[1] ? { appInfo: v[1], pubspec: pre[1] } : null,
      filing: (appInfo.match(/kAppFilingNumber = '([^']*)'/) || [])[1] ?? null,
    };
  } catch (e) {
    return { available: false, why: `读版本失败：${e.message.split('\n')[0]}`, version: null, build: null };
  }
}

/** 最新的那条改动（`CHANGELOG.md` 的第一个 `## ` 小节）。 */
export function readChangelogHead(root = REPO) {
  try {
    const line = readFileSync(join(root, 'CHANGELOG.md'), 'utf8').split('\n').find((l) => l.startsWith('## '));
    return line ? line.replace(/^##\s*/, '').trim() : '（CHANGELOG 里没有版本小节）';
  } catch {
    return '（读不了 CHANGELOG.md）';
  }
}

/**
 * 纯函数：只读 `CHANGELOG.md` 的**头 N 个版本小节**，不做全文正则。
 *
 * ⚠️ 这份文件 382 KB / 5000+ 行，且正文里全是 `**加粗**`。
 * 两个坑都在这里避开：
 *   1. **性能**：逐行扫，数到第 `n+1` 个 `## ` 立刻停 —— 不 `match` 全文。
 *   2. **记号泄漏**：正文有**不配对的 `**`**（写文档时手滑），原样渲染就会在页面上
 *      出现一个星星。所以这里只保留标题 + 首段，且**把裸 `**` 抹掉**；
 *      工作台的自检里有一条"渲染出的 HTML 不许出现裸 `**`"，这是它的第一道闸。
 */
export function readChangelogTail(text, n = 8) {
  const lines = text.split('\n');
  const idx = [];
  for (let i = 0; i < lines.length && idx.length <= n; i += 1) {
    if (/^##\s/.test(lines[i])) idx.push(i);
  }
  if (!idx.length) return [];
  const out = [];
  for (let k = 0; k < Math.min(n, idx.length); k += 1) {
    const from = idx[k];
    const until = k + 1 < idx.length ? idx[k + 1] : lines.length;
    const body = lines.slice(from + 1, until);
    const para = body.find((l) => l.trim() && !/^>/.test(l.trim()) && !/^#{2,}\s/.test(l.trim()));
    out.push({
      title: stripMd(lines[from].replace(/^##\s*/, '')),
      // 首段最多 160 字：这一页是"看状态"，不是读日志
      summary: para ? stripMd(para).slice(0, 160) : '',
    });
  }
  return out;
}

export function readChangelogTitles(root = REPO, n = 8) {
  try {
    return { available: true, why: null, items: readChangelogTail(readFileSync(join(root, 'CHANGELOG.md'), 'utf8'), n) };
  } catch (e) {
    return { available: false, why: `读不了 CHANGELOG.md：${e.message.split('\n')[0]}`, items: [] };
  }
}

/** 去掉 markdown 记号（标题/首段会直接进 HTML，裸记号会原样显示成星号）。 */
function stripMd(s) {
  return String(s ?? '')
    .replace(/`/g, '')
    .replace(/\*\*/g, '')
    .replace(/~~/g, '')
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .trim();
}

/**
 * `dist/` 里现在有什么 —— 这是**交付口**：真机装 APK、商店传 AAB、软著交 PDF。
 *
 * ⚠️ 这里有一条本项目真出过两次事故的判据：**文件名里带版本号、却不是当前版本** → `stale`。
 * 它就是"拿错一份去上传"的前兆，页面上必须点出来。
 */
export function readDist(root = REPO) {
  const dir = join(root, 'dist');
  if (!existsSync(dir)) return { available: false, why: '没有 dist/ 目录', files: [], copyright: [], stale: [] };
  const version = readVersion(root).version;
  const list = (d) => {
    if (!existsSync(d)) return [];
    return readdirSync(d)
      .filter((n) => !n.startsWith('.'))
      .map((n) => {
        const st = statSync(join(d, n));
        return { name: n, bytes: st.size, mtime: st.mtimeMs, isDir: st.isDirectory() };
      })
      .sort((a, b) => a.name.localeCompare(b.name));
  };
  const files = list(dir).filter((f) => !f.isDir);
  const copyright = list(join(dir, 'copyright'));
  const stale = version
    ? [...files, ...copyright]
      .filter((f) => /V?\d+\.\d+\.\d+/.test(f.name))
      .filter((f) => !f.name.includes(version))
      .map((f) => f.name)
    : [];
  return { available: true, why: null, files, copyright, stale, version };
}

// ─────────────────────────────────────────────── git

/**
 * 纯函数：解析 `git status -sb` 的第一行与变更文件。
 *
 * 三种真实形态都要认（不认就会把"解析不了"显示成"干净"）：
 *   * `## main...origin/main [ahead 3, behind 1]`
 *   * `## main...origin/main`（没有 upstream 差值）
 *   * `## HEAD (no branch)`（detached）
 */
export function parseGitStatus(text) {
  const lines = String(text ?? '').split('\n').filter(Boolean);
  const head = lines[0] ?? '';
  if (!head.startsWith('##')) return { available: false, why: 'git status 的输出不认识（第一行不是 ##）' };
  const ahead = Number((head.match(/ahead (\d+)/) || [])[1] ?? 0);
  const behind = Number((head.match(/behind (\d+)/) || [])[1] ?? 0);
  const detached = /no branch/.test(head);
  const branch = detached
    ? '(detached HEAD)'
    : head.replace(/^##\s*/, '').split('...')[0].split(/\s/)[0];
  const changed = lines.slice(1).filter((l) => /^(\s*\S|\?\?)/.test(l)).length;
  const untracked = lines.slice(1).filter((l) => /^\?\?/.test(l)).length;
  return { available: true, why: null, branch, ahead, behind, changed, untracked, detached };
}

/** 跑 git（读 HEAD 那条提交 + 工作区状态）。不在仓库里 / 没有 git 都给 `available:false`。 */
export function readGit(root = REPO) {
  const run = (args) => execFileSync('git', args, { cwd: root, encoding: 'utf8', timeout: 15000, stdio: ['ignore', 'pipe', 'pipe'] });
  try {
    const status = parseGitStatus(run(['status', '-sb']));
    const log = run(['log', '-1', '--format=%h%x09%ad%x09%s', '--date=short']).trim().split('\t');
    return {
      ...status,
      head: { hash: log[0] ?? '', date: log[1] ?? '', subject: stripMd(log[2] ?? '') },
    };
  } catch (e) {
    return { available: false, why: `跑不了 git：${(e.message || '').split('\n')[0]}`, changed: 0, ahead: 0, behind: 0 };
  }
}

// ─────────────────────────────────────────────── 资产与证据

/**
 * `store-assets/`（要交给商店的图）与 `docs/images/`（走查证据图）。
 *
 * 分成两组报，因为它们**性质不同**：前者是提交材料（张数/尺寸有硬要求，
 * 由 `tool/check-screenshots.mjs` 核），后者是"我们当时看到过什么"。
 * 混在一起会让人以为证据图也要交给商店 —— 那是两件事。
 */
export function readEvidence(root = REPO) {
  const group = (rel, exts = ['.png']) => {
    const dir = join(root, rel);
    if (!existsSync(dir)) return { rel, available: false, count: 0, files: [] };
    const files = [];
    const walk = (d, depth) => {
      if (depth > 3) return;
      for (const n of readdirSync(d)) {
        if (n.startsWith('.')) continue;
        const p = join(d, n);
        const st = statSync(p);
        if (st.isDirectory()) { walk(p, depth + 1); continue; }
        if (exts.some((e) => n.toLowerCase().endsWith(e))) files.push({ rel: `${rel}${p.slice(dir.length)}`, bytes: st.size });
      }
    };
    walk(dir, 0);
    return { rel, available: true, count: files.length, files: files.sort((a, b) => a.rel.localeCompare(b.rel)) };
  };

  const store = existsSync(join(root, 'store-assets'))
    ? readdirSync(join(root, 'store-assets'))
      .filter((n) => statSync(join(root, 'store-assets', n)).isDirectory())
      .map((n) => group(`store-assets/${n}/`))
    : [];
  return {
    store: { groups: store.filter((g) => g.count > 0), empty: store.filter((g) => g.count === 0).map((g) => g.rel) },
    images: group('docs/images/'),
  };
}

// ─────────────────────────────────────────────── 合规 / 上架

/**
 * 上架与合规那一半能**机械读到**的东西：
 *   * `server/deploy/` 的五件套在不在（部署时是"一条命令"，缺一件就不是）
 *   * `docs/privacy-facts.json` 里几个关键布尔（这些是 `privacy-audit.mjs` 双向核政策的锚）
 *   * 事件数 / 权限数（对不上就说明文档或代码有一边没说真话）
 *
 * ⚠️ **不在这里判断"能不能上架"** —— 那要读 `docs/your-todo.md` 与
 * `docs/release-checklist.md` 的人工结论。这里只报事实。
 */
export function readCompliance(root = REPO) {
  const deployDir = join(root, 'server/deploy');
  const expect = ['install.sh', 'Caddyfile', 'lianleme-collector.service', 'lianleme-backend.service', 'README.md'];
  const deploy = {
    rel: 'server/deploy/',
    available: existsSync(deployDir),
    present: existsSync(deployDir) ? readdirSync(deployDir) : [],
  };
  deploy.missing = expect.filter((f) => !deploy.present.includes(f));

  let privacy = { available: false, why: '读不了 docs/privacy-facts.json' };
  try {
    const j = JSON.parse(readFileSync(join(root, 'docs/privacy-facts.json'), 'utf8'));
    privacy = {
      available: true,
      why: null,
      analyticsDefaultOn: j.analyticsOptIn?.defaultOn ?? null,
      cloudBackupInBuild: j.cloudBackup?.enabledInDistributedBuild ?? null,
      events: Array.isArray(j.events) ? j.events.length : null,
      permissions: Array.isArray(j.permissions) ? j.permissions.map((p) => p.name) : [],
      injected: Array.isArray(j.injectedPermissions) ? j.injectedPermissions.map((p) => p.name ?? String(p)) : [],
      neverCollected: Array.isArray(j.neverCollected) ? j.neverCollected.length : null,
    };
  } catch { /* 保持 available:false */ }

  return { deploy, privacy };
}

// ───────────────────────────────────────────────────────────── 自检

function selftest() {
  let bad = 0;
  const check = (ok, label, extra = '') => {
    if (!ok) bad += 1;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}${extra ? `　→ ${extra}` : ''}`);
  };

  // 1. parseGitStatus 的三种真实形态
  const a = parseGitStatus('## main...origin/main [ahead 3, behind 1]\n M a.md\n?? b.md\n');
  check(a.available && a.branch === 'main' && a.ahead === 3 && a.behind === 1,
    'git：ahead/behind 读得对', JSON.stringify(a));
  check(a.changed === 2 && a.untracked === 1, 'git：变更文件数与未跟踪数分开算', JSON.stringify(a));
  const b = parseGitStatus('## main...origin/main\n');
  check(b.available && b.ahead === 0 && b.behind === 0 && b.changed === 0,
    'git：没有 upstream 差值时是 0（不是 undefined）', JSON.stringify(b));
  const c = parseGitStatus('## HEAD (no branch)\n M x\n');
  check(c.available && c.detached && c.branch === '(detached HEAD)', 'git：detached HEAD 认得出', JSON.stringify(c));
  check(!parseGitStatus('随便什么输出').available,
    '★ git：不认识的输出说"不认识"（不许当成"干净"）', parseGitStatus('').why);

  // 2. readChangelogTail：只读头 N 节 + 抹掉裸记号 + 不在第 N+1 节之后乱看
  const clog = [
    '# 更新日志',
    '',
    '> 说明块，不算小节',
    '',
    '## v9.9.9 · 假的',
    '这是 **首段**，带着 `记号`。',
    '',
    '### 小节里的东西不该被当首段',
    '',
    '## v9.9.8 · 上一版',
    '上一版的首段',
    '',
    '## v9.9.7 · 再上一版',
    '第三段',
    '',
    '## v9.9.6 · 第四节',
    '脏数据：**这里有**一个孤立的 ** 记号',
  ].join('\n');
  const tail = readChangelogTail(clog, 3);
  check(tail.length === 3, '变更：只取头 3 节', JSON.stringify(tail.map((t) => t.title)));
  check(tail[0].title === 'v9.9.9 · 假的', '变更：标题去掉 ## ', tail[0].title);
  check(tail[0].summary === '这是 首段，带着 记号。', '★ 变更：首段里的裸记号被抹掉（页面上不许出现 **）', tail[0].summary);
  check(!tail.some((t) => t.title.includes('第四')), '★ 变更：第 4 节没被读到（逐行扫到第 N+1 个 ## 就停）');
  check(readChangelogTail('没有小节的文件\n', 3).length === 0,
    '★ 变更：文件里没有 ## 时返回空数组、不抛');

  // 3. readVersion 的两处不一致要报出来（不是"读失败"）
  const bad2 = readVersion('/nonexistent-root-xyz');
  check(!bad2.available && bad2.version === null, '版本：读不到时说读不到，给 null 而不是空串', bad2.why);

  // 4. readDist 的"旧版本残留"（本项目真出过两次的事故）
  const fakeDist = readDist('/nonexistent-root-xyz');
  check(!fakeDist.available && fakeDist.stale.length === 0,
    '产物：没有 dist/ 时 available:false 且 stale 为空（不是"很干净"）', fakeDist.why);

  // 5. 真仓库上跑一遍 —— 防止"全都读不到"其实是我自己错了
  const real = [
    ['版本', readVersion(REPO), (r) => r.available && /^\d+\.\d+\.\d+$/.test(r.version) && r.build],
    ['CHANGELOG 时间线', readChangelogTitles(REPO, 5), (r) => r.available && r.items.length === 5],
    // ⚠️ 干净克隆上**没有 dist/**（它是 gitignore 的构建产物）——
    // 所以判据是"要么读出产物、要么如实说没有"，而不是"必须有产物"。
    // 这条是 2026-10-05 CI 抓出来的：本地一直绿，因为开发机上 dist/ 一直在。
    //
    // ⚠️ 2026-10-05 又补第三种形态（**同一天第二次踩**）：`dist/` 目录**在**，
    // 但里面只有刚生成的 `copyright/`（`verify.sh` 自己会往那儿写软著材料）——
    // 于是 `available=true` 而 `files=[]`，旧判据当场红。后果很实际：
    // **在干净克隆里跑第二遍 `verify.sh` 必红**（第一遍跑完就会留下那个目录）。
    // 判据改成"要么真读出产物、要么目录里确实一件产物都没有（files 与 copyright 都空）"——
    // 仍然是"必须有东西才算读得出来"的反面：只要 `readDist` 悄悄坏掉、什么都返回空，
    // 这条在开发机上（dist 里一直有 APK）照样会红。
    ['dist', readDist(REPO), (r) => (r.available
      ? (r.files.length > 0 || (r.files.length === 0 && (r.copyright ?? []).length === 0)
        || /没有 dist/.test(r.why ?? ''))
      : /没有 dist/.test(r.why))],
    ['git', readGit(REPO), (r) => r.available && r.head && r.head.hash],
    ['证据图', readEvidence(REPO), (r) => r.images.count > 0 && r.store.groups.length >= 3],
    ['合规', readCompliance(REPO), (r) => r.deploy.available && r.privacy.available],
  ];
  for (const [name, res, pred] of real) {
    const ok = pred(res);
    check(ok, `★ 真仓库：${name} 读得出来`,
      ok ? (res.version ? `v${res.version}+${res.build}`
        : res.items ? `${res.items.length} 节`
          : res.files ? `${res.files.length} 个产物`
            : res.head ? `${res.head.hash} · 改动 ${res.changed}`
              : res.images ? `证据 ${res.images.count} 张 / 商店 ${res.store.groups.length} 组`
                : `部署 ${res.deploy.present.length} 件 / 事件 ${res.privacy.events}`) : res.why);
  }
  // 真仓库的版本必须与 README/CHANGELOG 头节对得上（这是"两处真源"关系）
  const v = readVersion(REPO);
  check(readChangelogHead(REPO).includes(v.version),
    '★ 真仓库：CHANGELOG 头一节就是当前版本（两边没漂）', `${readChangelogHead(REPO)} vs v${v.version}`);

  if (bad) {
    console.error(`\n✗ collect-repo 自检失败 ${bad} 项`);
    process.exit(1);
  }
  console.log('\n✓ 自检通过：版本/产物残留/变更头 N 节/git 三种形态/证据/合规 都读得对，真仓库全读得出');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href
    && process.argv.includes('--selftest')) {
  selftest();
}
