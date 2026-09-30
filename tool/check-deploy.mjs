#!/usr/bin/env node
/**
 * 练了么 · 部署包核对（`server/deploy/` 里那五样东西彼此对不对、与代码对不对）
 *
 * **它为什么存在**：这一包里全是**配置文本** —— systemd 单元、Caddyfile、安装脚本、README。
 * 它们的错法有个共同点：**平时完全看不出来**，只在部署那一刻才炸（或者更糟：不炸，
 * 但把承诺违背了）。而配置文本是这个仓库里最容易悄悄漂的一类东西：
 * 端口改一处、域名换一行、脚本换个文件名，四份文件立刻互相矛盾，谁也不会发现。
 *
 * 它核六件事（每一条都对应一种"真会发生"的漂移）：
 *   1. **端口一致**：`install.sh` 的默认端口 → 单元里的 `--port` → Caddyfile 的路由，
 *      三处必须是同一组数字（拿 install.sh 的默认值把模板渲染出来再比，不比字面量）；
 *   2. **入口存在**：单元里 `ExecStart` 指的 `.mjs` 在仓库里真的有（改名/搬家会红）；
 *   3. **与客户端对账**：README 教用户编的那两个 `--dart-define`
 *      （`LIANLEME_BACKUP_URL` / `LIANLEME_ANALYTICS_URL`）必须与 `app/lib` 里
 *      `String.fromEnvironment(...)` 的字面量**逐字相同** —— 否则照 README 做出来的包
 *      会静默地把云备份关掉（这正是本项目最怕的那种"看起来配好了"）；
 *   4. **加固没被删**：两个单元必须还有 `NoNewPrivileges` / `ProtectSystem=strict` /
 *      `ReadWritePaths` / `CapabilityBoundingSet=`，且**不是以 root 跑**；
 *   5. **不许开访问日志**：`Caddyfile` 里出现 `log` 指令就红 —— 政策写着"不做 IP 记录"，
 *      而 Caddy 的 access log 会把客户端 IP 写进磁盘（承诺与配置必须一致）；
 *   6. **安装脚本的底线**：`set -euo pipefail`、支持 `--dry-run`、没给域名就拒绝执行。
 *
 * 用法：
 *   node tool/check-deploy.mjs               # 核仓库里的部署包
 *   node tool/check-deploy.mjs --selftest    # 自检（造几套动过手脚的，验它抓得住）
 *
 * 退出码：任何一项不符 → 1。
 */

import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

const ARTIFACTS = [
  'install.sh',
  'lianleme-backend.service',
  'lianleme-collector.service',
  'Caddyfile',
  'README.md',
];

/** 从 install.sh 里抠出默认值 —— 端口/路径的真源就是它，别在检查里再写一遍常量。 */
function installDefaults(src) {
  const pick = (name, fallback) => {
    const m = src.match(new RegExp(`^${name}="\\$\\{${name}:-([^}]*)\\}"`, 'm'));
    return m ? m[1] : fallback;
  };
  return {
    APP_DIR: pick('APP_DIR', '/opt/lianleme'),
    DATA_DIR: pick('DATA_DIR', '/var/lib/lianleme'),
    SVC_USER: pick('SVC_USER', 'lianleme'),
    BACKEND_PORT: pick('BACKEND_PORT', '8790'),
    COLLECTOR_PORT: pick('COLLECTOR_PORT', '8787'),
  };
}

/** 把模板里的 __X__ 换掉（与 install.sh 的 sed 同一套替换规则）。 */
function render(tpl, vars) {
  return tpl
    .replaceAll('__APP_DIR__', vars.APP_DIR)
    .replaceAll('__DATA_DIR__', vars.DATA_DIR)
    .replaceAll('__USER__', vars.SVC_USER)
    .replaceAll('__BACKEND_PORT__', vars.BACKEND_PORT)
    .replaceAll('__COLLECTOR_PORT__', vars.COLLECTOR_PORT)
    .replaceAll('__DOMAIN__', 'api.example.com')
    .replaceAll('__NODE__', vars.NODE ?? '/usr/bin/node');
}

const HARDENING = [
  'NoNewPrivileges=true',
  'ProtectSystem=strict',
  'ReadWritePaths=',
  'CapabilityBoundingSet=',
  'PrivateTmp=true',
];

function inspect(root) {
  const problems = [];
  const facts = [];
  const deploy = join(root, 'server/deploy');

  const read = (rel) => {
    const p = join(deploy, rel);
    if (!existsSync(p)) {
      problems.push(`server/deploy/${rel} 不存在 —— 部署包缺文件`);
      return null;
    }
    return readFileSync(p, 'utf8');
  };

  const install = read('install.sh');
  const backendUnit = read('lianleme-backend.service');
  const collectorUnit = read('lianleme-collector.service');
  const caddy = read('Caddyfile');
  const readme = read('README.md');
  if (problems.length) return { problems, facts };

  // ── 6. 安装脚本的底线
  if (!/^set -euo pipefail$/m.test(install)) {
    problems.push('install.sh 少了 `set -euo pipefail` —— 中间一步失败会继续往下跑，'
      + '留下"半装好"的服务器');
  }
  if (!install.includes('--dry-run')) {
    problems.push('install.sh 不支持 --dry-run —— 部署前没法先看一眼它要做什么');
  }
  if (!/^if \[ -z "\$DOMAIN" \]/m.test(install)) {
    problems.push('install.sh 没有"没给域名就退出"那条 —— 猜域名会把 HTTPS 配成一半');
  }
  try {
    execFileSync('bash', ['-n', join(deploy, 'install.sh')], { stdio: 'pipe' });
  } catch (e) {
    problems.push(`install.sh 语法不过（bash -n）：${String(e.stderr ?? e).trim().split('\n')[0]}`);
  }

  // ── 1. 端口一致：渲染出来再比
  const d = installDefaults(install);
  const renderVars = { APP_DIR: d.APP_DIR, DATA_DIR: d.DATA_DIR, SVC_USER: d.SVC_USER,
    BACKEND_PORT: d.BACKEND_PORT, COLLECTOR_PORT: d.COLLECTOR_PORT };
  const bUnit = render(backendUnit, renderVars);
  const cUnit = render(collectorUnit, renderVars);
  const caddyR = render(caddy, renderVars);
  facts.push(`默认：backend ${d.BACKEND_PORT} · collector ${d.COLLECTOR_PORT} · `
    + `用户 ${d.SVC_USER} · 数据 ${d.DATA_DIR}`);

  if (!bUnit.includes(`--port ${d.BACKEND_PORT}`)) {
    problems.push(`后端单元里的 --port 与 install.sh 的默认端口 ${d.BACKEND_PORT} 不一致`);
  }
  if (!cUnit.includes(`--port ${d.COLLECTOR_PORT}`)) {
    problems.push(`收集端单元里的 --port 与 install.sh 的默认端口 ${d.COLLECTOR_PORT} 不一致`);
  }
  const eventsRoute = caddyR.match(/handle \/v1\/events\* \{\s*reverse_proxy ([^;\s]+)/);
  const apiRoute = caddyR.match(/handle \/v1\/\* \{\s*reverse_proxy ([^;\s]+)/);
  if (!eventsRoute) {
    problems.push('Caddyfile 里找不到 `/v1/events` 的路由 —— 埋点会打到备份服务上');
  } else if (eventsRoute[1] !== `127.0.0.1:${d.COLLECTOR_PORT}`) {
    problems.push(`Caddyfile 的 /v1/events 指向 ${eventsRoute[1]}，`
      + `collector 实际在 127.0.0.1:${d.COLLECTOR_PORT}`);
  }
  if (!apiRoute) {
    problems.push('Caddyfile 里找不到 `/v1/*` 的路由 —— 备份接口没人转发');
  } else if (apiRoute[1] !== `127.0.0.1:${d.BACKEND_PORT}`) {
    problems.push(`Caddyfile 的 /v1/* 指向 ${apiRoute[1]}，`
      + `backend 实际在 127.0.0.1:${d.BACKEND_PORT}`);
  }
  if (!/^__DOMAIN__ \{$/m.test(caddy)) {
    problems.push('Caddyfile 的站点块不是从域名开始的 —— 没有它 Caddy 不会申请 HTTPS');
  }

  // ── 2. ExecStart 指的入口真的在
  for (const [name, unit] of [['backend', bUnit], ['collector', cUnit]]) {
    const m = unit.match(/^ExecStart=.*?\s(\S+\.mjs)\s/m);
    if (!m) {
      problems.push(`${name} 单元的 ExecStart 里找不到 .mjs 入口`);
      continue;
    }
    const rel = m[1].replace(`${d.APP_DIR}/`, '');
    if (!existsSync(join(root, 'server', rel.replace(/^server\//, '')))) {
      problems.push(`${name} 单元要跑 ${rel}，但仓库里没有这个文件`);
    }
  }

  // ── 4. 加固
  for (const [name, unit] of [['backend', bUnit], ['collector', cUnit]]) {
    for (const h of HARDENING) {
      if (!unit.includes(h)) problems.push(`${name} 单元少了加固项 ${h}`);
    }
    const u = unit.match(/^User=(.+)$/m);
    if (!u) problems.push(`${name} 单元没写 User= —— 默认会以 root 跑`);
    else if (u[1] === 'root') problems.push(`${name} 单元以 root 跑 —— 不该如此`);
  }

  // ── 5. 不许开访问日志（政策写着"不做 IP 记录"）
  if (/^\s*log(\s|$)/m.test(caddy)) {
    problems.push('Caddyfile 里出现了 `log` 指令 —— 它会把客户端 IP 写进磁盘，'
      + '而政策承诺"不做 IP 记录"（要加日志先改政策与 privacy-facts）');
  }

  // ── 7. 占位符覆盖：模板里用到的每一个 __X__，install.sh 的 sed 都得替换它
  //
  // 这条是"部署时才炸"的典型：单元里加了一个新占位符、忘了在 sed 里加一条，
  // 结果 /etc/systemd/system 里躺着一行 `ExecStart=__NODE__ ...`，systemd 报的错
  // 跟真正的原因（少一条 sed）隔了十万八千里。
  const tplFiles = { 'lianleme-backend.service': backendUnit,
    'lianleme-collector.service': collectorUnit, Caddyfile: caddy };
  const tokens = new Set();
  for (const [name, text] of Object.entries(tplFiles)) {
    for (const m of text.matchAll(/__([A-Z_]+)__/g)) tokens.add(m[1]);
    const rendered = render(text, renderVars);
    const left = rendered.match(/__[A-Z_]+__/g);
    if (left) {
      problems.push(`${name} 渲染后仍残留占位符 ${[...new Set(left)].join(', ')} `
        + '—— install.sh 的 sed 漏了它');
    }
  }
  for (const t of tokens) {
    if (!install.includes(`__${t}__`)) {
      problems.push(`模板里用了 __${t}__，但 install.sh 里找不到对它的替换 —— `
        + '装完会留下一行字面量占位符');
    }
  }
  facts.push(`占位符 ${tokens.size} 个，install.sh 全部覆盖`);

  // ── 3. 与客户端对账（三个 dart-define 必须逐字相同）
  //
  // ⚠️ 为什么是**三个**：云备份要「地址 + 显式声明」两个开关同时给，入口才出现
  // （`backup_config.dart` 故意让失败往"关闭"那边倒）。部署文档只教地址的话，
  // 照它做出来的包"界面有入口、政策说没有这条通道"—— 那是 `privacy-audit` 的
  // 硬门禁明确反对的组合，这一轮它当场抓住了这条。
  // 第三个字段是**客户端读取它用的那个 API**：地址是 String.fromEnvironment，
  // 而"是否声明"是 bool.fromEnvironment —— 写成一个模子会误报（第一版就是这么错的，
  // 真跑当场就红了：它去代码里找 String.fromEnvironment('...DISCLOSED')）。
  const defines = [
    ['LIANLEME_BACKUP_URL', 'app/lib/backup/backup_config.dart', 'String.fromEnvironment'],
    ['LIANLEME_BACKUP_DISCLOSED', 'app/lib/backup/backup_config.dart', 'bool.fromEnvironment'],
    ['LIANLEME_ANALYTICS_URL', 'app/lib/main.dart', 'String.fromEnvironment'],
  ];
  for (const [name, src, api] of defines) {
    const p = join(root, src);
    if (!existsSync(p)) {
      problems.push(`对账失败：找不到 ${src}（检查本身失效了，别当成通过）`);
      continue;
    }
    const code = readFileSync(p, 'utf8');
    if (!code.includes(`${api}('${name}')`)) {
      problems.push(`客户端 ${src} 里没有 ${api}('${name}') —— `
        + 'README 教的编译参数在代码里不存在，照做会静默失效');
    }
    if (!readme.includes(name)) {
      problems.push(`部署 README 没写 ${name} —— 部署完没人知道客户端要编什么地址`);
    }
  }
  if (!/22\.5/.test(readme)) {
    problems.push('部署 README 没写 Node 22.5+ 这条前提（服务端用 node:sqlite）');
  }
  // 启用云备份还要同时翻政策那一页 —— 少了这句，部署的人会直接出一个
  // "界面有入口、政策说没有"的包（privacy-audit 会红，但那时包已经发出去了）
  if (!readme.includes('enabledInDistributedBuild')) {
    problems.push('部署 README 没写"发版前要把 cloudBackup.enabledInDistributedBuild '
      + '翻成 true 并同步改政策"这一步 —— 漏了它就会出一个政策自相矛盾的包');
  }
  if (!install.includes('LIANLEME_BACKUP_DISCLOSED')) {
    problems.push('install.sh 收尾没提 LIANLEME_BACKUP_DISCLOSED —— 只给地址的包'
      + '云备份入口不会出现（照它做等于白配）');
  }

  return { problems, facts };
}

// ───────────────────────────────────────────────────────────── 自检
function selftest() {
  const realDeploy = join(ROOT, 'server/deploy');
  const realFiles = {
    'app/lib/backup/backup_config.dart': join(ROOT, 'app/lib/backup/backup_config.dart'),
    'app/lib/main.dart': join(ROOT, 'app/lib/main.dart'),
  };

  const makeTree = (mutate) => {
    const root = mkdtempSync(join(tmpdir(), 'lianleme-deploy-'));
    mkdirSync(join(root, 'server'), { recursive: true });
    cpSync(realDeploy, join(root, 'server/deploy'), { recursive: true });
    // 单元里 ExecStart 指的入口也要在夹具里，否则每一条用例都会红在"入口不存在"上 ——
    // 那样"变异红了"就不是因为被测的那条守卫生效（假通过）。
    for (const f of ['backend.mjs', 'backend-store.mjs', 'collector.mjs']) {
      cpSync(join(ROOT, 'server', f), join(root, 'server', f));
    }
    for (const [rel, src] of Object.entries(realFiles)) {
      mkdirSync(dirname(join(root, rel)), { recursive: true });
      cpSync(src, join(root, rel));
    }
    if (mutate) mutate(root);
    return root;
  };

  const edit = (root, rel, from, to) => {
    const p = join(root, 'server/deploy', rel);
    const s = readFileSync(p, 'utf8');
    if (!s.includes(from)) throw new Error(`自检夹具失效：${rel} 里没有 ${from}`);
    writeFileSync(p, s.replace(from, to));
  };

  /// 把某个记号**整份文件里全部**换掉，并断言它真的没了。
  ///
  /// 为什么需要它：README/脚本里同一个记号往往出现两次（命令块一次、说明文字一次），
  /// 只换第一处的话，被检查的那句话还在，于是"变异"其实没发生 ——
  /// 自检会红在一个假的原因上。这个陷阱这一天里踩了三次。
  const editAll = (root, rel, from, to) => {
    const p = join(root, 'server/deploy', rel);
    const s = readFileSync(p, 'utf8');
    if (!s.includes(from)) throw new Error(`自检夹具失效：${rel} 里没有 ${from}`);
    const out = s.split(from).join(to);
    if (out.includes(from)) throw new Error(`自检夹具没换干净：${rel} 里还剩 ${from}`);
    writeFileSync(p, out);
  };

  // 每条都带"必须因为它自己那条而红"的判据：只验"红了"是不够的 ——
  // 变异体红了却红在别的原因上，等于那条守卫根本没被测到。
  const cases = [
    ['好的部署包：全绿', null, true, null],
    ['Caddyfile 的收集端路由指错端口', (r) => edit(r, 'Caddyfile',
      'reverse_proxy 127.0.0.1:__COLLECTOR_PORT__', 'reverse_proxy 127.0.0.1:__BACKEND_PORT__'),
      false, 'Caddyfile 的 /v1/events 指向'],
    ['Caddyfile 开了访问日志（违背"不做 IP 记录"）', (r) => edit(r, 'Caddyfile',
      '\tencode zstd gzip', '\tencode zstd gzip\n\tlog'), false, '出现了 `log` 指令'],
    ['后端单元少了 ProtectSystem=strict', (r) => edit(r, 'lianleme-backend.service',
      'ProtectSystem=strict', 'ProtectSystem=full'), false, '少了加固项 ProtectSystem=strict'],
    // ⚠️ 只改 ExecStart 那一处：单元里 Documentation= 那行也含同样的路径，
    // 改中注释行等于没变异（第一版就是这么写的，于是"变异红了"变成"其实没红"）
    ['单元里的入口文件名写错', (r) => edit(r, 'lianleme-backend.service',
      '__NODE__ __APP_DIR__/server/backend.mjs', '__NODE__ __APP_DIR__/server/backend-v2.mjs'),
      false, '但仓库里没有这个文件'],
    // 同理：install.sh 的**注释里**也写着 `set -euo pipefail`，所以按行锚定改真指令
    ['install.sh 少了 set -euo pipefail', (r) => edit(r, 'install.sh',
      '\nset -euo pipefail\n', '\nset -u\n'), false, '少了 `set -euo pipefail`'],
    ['README 少写一个 dart-define', (r) => editAll(r, 'README.md',
      'LIANLEME_ANALYTICS_URL', 'ANALYTICS_URL'), false, '没写 LIANLEME_ANALYTICS_URL'],
    ['README 少写"声明"那个开关（只给地址会给出自相矛盾的包）', (r) => editAll(r, 'README.md',
      'LIANLEME_BACKUP_DISCLOSED', 'BACKUP_FLAG'), false, '没写 LIANLEME_BACKUP_DISCLOSED'],
    ['README 少写政策翻转那一步', (r) => editAll(r, 'README.md',
      'enabledInDistributedBuild', 'cloudBackupOn'), false, 'enabledInDistributedBuild'],
    ['install.sh 收尾漏了声明开关', (r) => editAll(r, 'install.sh',
      'LIANLEME_BACKUP_DISCLOSED', 'BACKUP_FLAG'), false, '没提 LIANLEME_BACKUP_DISCLOSED'],
    // 同理：文件头的用法注释里也有这个名字，要改的是真正那段 String.fromEnvironment
    ['客户端改了 define 名字（对账必须红）', (r) => {
      const p = join(r, 'app/lib/backup/backup_config.dart');
      writeFileSync(p, readFileSync(p, 'utf8').replace(
        "String.fromEnvironment('LIANLEME_BACKUP_URL')",
        "String.fromEnvironment('LIANLEME_BACKUP_BASE')"));
    }, false, '编译参数在代码里不存在'],
    ['单元以 root 跑', (r) => edit(r, 'lianleme-backend.service', 'User=__USER__', 'User=root'),
      false, '以 root 跑'],
    ['模板加了新占位符但 sed 没跟上', (r) => edit(r, 'lianleme-collector.service',
      '--out __DATA_DIR__', '--out __EVENTS_DIR__'), false, '__EVENTS_DIR__'],
  ];

  let bad = 0;
  for (const [label, mutate, wantGreen, expect] of cases) {
    const root = makeTree(mutate);
    const { problems } = inspect(root);
    const green = problems.length === 0;
    let ok = green === wantGreen;
    let why = green ? '' : `　→ ${problems[0].slice(0, 66)}`;
    if (ok && !wantGreen && expect && !problems.some((p) => p.includes(expect))) {
      ok = false;
      why = `　→ 红了，但不是因为「${expect}」（红在：${problems[0].slice(0, 50)}）`;
    }
    if (!ok) bad += 1;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}${why}`);
    rmSync(root, { recursive: true, force: true });
  }
  if (bad) {
    console.error(`\n✗ 自检失败 ${bad} 项 —— 这个工具本身不可信，先修它`);
    process.exit(1);
  }
  console.log('\n✓ 自检通过：每一条变异都**因为它们自己那条**而红（端口写错、开了访问日志、'
    + '加固被删、入口改名、脚本少了 -e、README 漏 define / 漏声明开关 / 漏政策那一步、'
    + '客户端改名）');
}

// ───────────────────────────────────────────────────────────────── 跑
if (process.argv.includes('--selftest')) {
  selftest();
} else {
  // `--root=<dir>`：给自检/排查用（默认是仓库根）
  const rootArg = process.argv.find((a) => a.startsWith('--root='));
  const { problems, facts } = inspect(rootArg ? rootArg.slice('--root='.length) : ROOT);
  console.log('部署包核对\n');
  for (const f of facts) console.log(`  ${f}`);
  if (problems.length) {
    console.log('');
    for (const p of problems) console.error(`  \x1b[31m✗\x1b[0m ${p}`);
    console.error(`\n✗ ${problems.length} 处不对 —— 配置文本的漂移只在部署那一刻才炸`);
    process.exit(1);
  }
  console.log('\n✓ 端口一致、入口存在、与客户端的 dart-define 逐字对得上、'
    + '加固没被删、没开访问日志');
}
