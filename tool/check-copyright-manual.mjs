#!/usr/bin/env node
/**
 * 练了么 · 软著说明书核对（**提交材料**说的和仓库事实 / 交付的界面图是不是一致）
 *
 * **它为什么存在**（`docs/feature-backlog.md` 第 13 项）：
 * `docs/copyright-manual.md` 是**要交给中国版权保护中心**的材料（国内商店也把它当资质），
 * 但它有两类漂移此前没有任何守卫盯着：
 *
 *   1. **第四节配的界面图**：说明书点名 8 屏，图来自 `store-assets/screenshots/`。
 *      图重拍/改名/加减张数之后，说明书会**指向一张不存在的图** —— 而生成 PDF 的工具
 *      不会报错（浏览器遇到加载失败的 `<img>` 就是一张破图），于是**提交当天**才发现。
 *      `check-screenshots.mjs` 管的是三套图本身（齐/尺寸/不夹带），
 *      `check-doc-paths.mjs` 只认行内代码里的路径（不认 markdown 图片引用）——
 *      所以这一块是真的没人管。
 *
 *   2. **它对"当前发布的包"的数据流描述**：这些由一个**编译期开关**决定
 *      （`docs/privacy-facts.json` 的 `cloudBackup` / `analyticsOptIn` / `healthSync`）。
 *      2026-10-04/05 起正式包就配了服务器地址，而说明书写着
 *      "当前发布版本**不含任何上报地址**""**当前发布的包没有配服务器地址**、
 *      界面上不会出现这个入口""这个版本里的数据一条都不会上传" ——
 *      **提交材料里的话与要发布的包相反**，这是"申报不实"那一类问题，
 *      而且只有在审核/比对时才疼。同理，开关反过来（未启用）时说明书也得写"未提供"，
 *      不能留着"已启用"的说法。
 *
 * 另外两条顺手钉住的规矩：
 *   * **别在提交材料里抄截图重出的日期/版本** —— 那个事实的真源是 `docs/screenshots.md`，
 *     抄一份就多一处会过期的（本文件原来那句"2026-10-05 在 v1.53.0 上重出"已经过期两轮）；
 *   * 说明书必须给读者一个**指向《隐私政策》的指针**（详细口径以政策为准，说明书不复述第二份）。
 *
 * 判据（都从仓库现算，不写死文档里的值）：
 *   ① 第四节引用的每个 `store-assets/screenshots/*.png` 必须真的存在；
 *      "本文第四节引用了其中 N 屏"的 N == 实际引用行数；
 *      提到 `store-assets/screenshots` 的行里写的"N 张" == 那套图的实际张数；
 *   ② 云备份/匿名统计/健康库三个开关按 `privacy-facts.json` 的**方向**判：
 *      启用了 → 说明书里不许出现"没有地址/入口不出现/一条都不会上传"，且必须写明
 *      默认关闭、端到端加密、服务端只有密文；未启用 → 必须写"未提供"那一句；
 *   ③ 说明书里出现"在 vX.Y.Z 上重出" → 红（截图的事以 screenshots.md 为准）。
 *
 * 用法：
 *   node tool/check-copyright-manual.mjs              # 核仓库里的说明书
 *   node tool/check-copyright-manual.mjs --selftest   # 自检（造几份动过手脚的，验它抓得住）
 *
 * 退出码：任何一处对不上 → 1。
 */

import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const MANUAL = 'docs/copyright-manual.md';
const FACTS = 'docs/privacy-facts.json';
const SHOTS = 'store-assets/screenshots';

/**
 * **当前包没配地址**这一类说法（云备份已在正式包里启用时，它们就是假话）。
 * 每一条都写清"为什么现在是假的"，因为这条清单等于一句签字。
 */
const NO_ADDRESS_CLAIMS = [
  ['不含任何上报地址', '正式包从 v1.43.0 起就配了两个地址（备份 + 统计，见 release-checklist §9 的出包命令）'],
  ['当前发布的包没有配服务器地址', '正式包从 v1.43.0 起就配了 `--dart-define=LIANLEME_BACKUP_URL`，'
    + '并且按 `tool/privacy-audit.mjs` 第 ⑧ 条的规矩同时给了 `--dart-define=LIANLEME_BACKUP_DISCLOSED`'
    + '（两个开关缺一不可，见 release-checklist §9）'],
  ['数据一条都不会上传', '统计默认开着；用户打开云备份后备份也会以密文离机 —— "一条都不会上传"只对没配地址的自编包成立'],
];

/** 云备份启用时，提交材料里必须能读到的三件事（少一件就是披露不全）。 */
const CLOUD_ENABLED_MUST = [
  ['端到端加密', '备份内容离开设备，必须说明它是端到端加密的（服务端解不开）'],
  ['默认关闭', '云备份是用户自己开的可选功能，不打开就不上传 —— 这一句不能漏'],
  ['服务端只有密文', '要如实说清服务端手里是什么（Apple 的"算不算收集"就取决于这句）'],
];

/** 说明书里提到截图张数的那一行才看数字（避免把别的"N 张"卷进来）。 */
function countShotClaims(manual) {
  const out = [];
  for (const line of manual.split('\n')) {
    if (!line.includes('store-assets/screenshots')) continue;
    for (const m of line.matchAll(/(\d+)\s*张/g)) out.push(Number(m[1]));
  }
  return out;
}

function inspect(root) {
  const problems = [];
  const facts = [];

  const manualPath = join(root, MANUAL);
  if (!existsSync(manualPath)) {
    return { problems: [`找不到 ${MANUAL} —— 核对的一端没了`], facts };
  }
  const manual = readFileSync(manualPath, 'utf8');
  let pf;
  try {
    pf = JSON.parse(readFileSync(join(root, FACTS), 'utf8'));
  } catch (e) {
    return { problems: [`读不了 ${FACTS}（事实源结构变了？）：${e.message}`], facts };
  }

  const shotDir = join(root, SHOTS);
  let shots = null;
  try {
    shots = readdirSync(shotDir).filter((f) => f.toLowerCase().endsWith('.png')).sort();
  } catch { /* 下面报 */ }
  if (!shots) {
    return { problems: [`找不到 ${SHOTS}/ —— 软著说明书的界面图来自它，这套图没了材料就交不了`], facts };
  }
  facts.push(`界面图：${SHOTS}/ 里 ${shots.length} 张`);

  // ── ① 第四节配的图：在不在、几屏、多少张
  const refs = [...manual.matchAll(/!\[[^\]]*\]\((?:\.\.\/)?store-assets\/([^/)]+)\/([^)/]+\.png)\)/g)]
    .map((m) => ({ set: m[1], file: m[2] }));
  if (!refs.length) {
    problems.push(`${MANUAL} 里找不到界面图引用（\`![](...)\`）—— 措辞/排版变了？检查要跟着改`);
  }
  for (const r of refs) {
    if (r.set !== 'screenshots') {
      problems.push(`${MANUAL} 的配图引自 store-assets/${r.set}/ —— 软著交的是国内那套 `
        + `（${SHOTS}/），别拿别的套图凑（尺寸/用途都不一样）`);
      continue;
    }
    if (!existsSync(join(shotDir, r.file))) {
      problems.push(`${MANUAL} 第四节点了 ${r.file}，但 ${SHOTS}/ 里没有这张 —— `
        + '图改名/重拍时说明书没跟上，提交的 PDF 里会是一张破图（生成工具不会报错）');
    }
  }
  facts.push(`第四节点名 ${refs.length} 屏`);

  const claimedScreens = /本文第四节引用了其中\s*(\d+)\s*屏/.exec(manual);
  if (!claimedScreens) {
    problems.push(`${MANUAL} 里找不到「本文第四节引用了其中 N 屏」—— 措辞变了？守卫要跟着改，`
      + '否则"配了几屏"这件事又回到没人核');
  } else if (Number(claimedScreens[1]) !== refs.length) {
    problems.push(`${MANUAL} 说第四节引用了 ${claimedScreens[1]} 屏，实际有 ${refs.length} 个带图的行 —— `
      + '提交材料里的数字必须对得上');
  }

  for (const n of countShotClaims(manual)) {
    if (n !== shots.length) {
      problems.push(`${MANUAL} 写着「${n} 张」，而 ${SHOTS}/ 实际有 ${shots.length} 张 —— `
        + '截图重出后忘了改这一句，提交材料就会说错交付物。可改成指向 docs/screenshots.md');
    }
  }

  // ── ② 三个编译期开关：提交材料里的说法必须与事实源同向
  const cb = pf.cloudBackup;
  if (!cb || typeof cb.enabledInDistributedBuild !== 'boolean') {
    problems.push(`${FACTS} 的 cloudBackup.enabledInDistributedBuild 读不到 —— 这条检查已经失效，别当成通过`);
  } else if (cb.enabledInDistributedBuild) {
    facts.push('事实源：云备份在正式包里**已启用**');
    for (const [needle, why] of NO_ADDRESS_CLAIMS) {
      if (manual.includes(needle)) {
        problems.push(`${MANUAL} 还写着「${needle}」—— ${why}。`
          + '提交材料里的话与要发布的包相反，是"申报不实"那一类问题');
      }
    }
    for (const [needle, why] of CLOUD_ENABLED_MUST) {
      if (!manual.includes(needle)) {
        problems.push(`${MANUAL} 里没有「${needle}」—— 云备份已在正式包里启用，${why}`);
      }
    }
  } else {
    facts.push('事实源：云备份在正式包里**未启用**');
    const stmt = cb.disabledStatement?.zh;
    if (!stmt) {
      problems.push('cloudBackup 未启用时 disabledStatement.zh 必须写清那句 —— 事实源结构变了');
    } else if (!manual.includes(stmt)) {
      problems.push(`${MANUAL} 里没有「${stmt}」—— 事实源说这一版没启用云备份，`
        + '提交材料就要写同一句（否则读者以为这份说明书讲的是另一个包）');
    }
  }

  const opt = pf.analyticsOptIn;
  if (typeof opt?.defaultOn !== 'boolean') {
    problems.push(`${FACTS} 的 analyticsOptIn.defaultOn 读不到 —— 统计默认值这一条检查已经失效`);
  } else {
    // 与 `check-store-forms.mjs` 同一条判据：**只看提到统计开关的那一行**。
    // 拿整篇去 grep"默认关"会被"云备份默认关闭"蒙过去（那说的是另一个开关）。
    const want = opt.defaultOn ? /默认开/ : /默认关/;
    const other = opt.defaultOn ? /默认关/ : /默认开/;
    const switchRe = /(统计|帮助改进产品|匿名)/;
    const saysIt = manual.split('\n').some((line) => switchRe.test(line) && want.test(line) && !other.test(line));
    if (!saysIt) {
      problems.push(`事实源里匿名统计是**默认${opt.defaultOn ? '开' : '关'}**的，但 ${MANUAL}`
        + '提到统计开关的那一行都没写这一点 —— 提交材料要说明"用户拿到手时它是开是关"');
    }
    facts.push(`事实源：匿名统计默认${opt.defaultOn ? '开' : '关'}`);
  }

  const hs = pf.healthSync;
  if (!hs || typeof hs.enabledInDistributedBuild !== 'boolean') {
    problems.push(`${FACTS} 的 healthSync.enabledInDistributedBuild 读不到 —— 这条检查已经失效`);
  } else if (hs.enabledInDistributedBuild) {
    if (!manual.includes('系统健康库')) {
      problems.push(`${MANUAL} 没提「系统健康库」—— 这一版会从系统健康库读体成分，`
        + '说明书必须写清数据来源（它不来自用户填写，而是另一个 App 写下的记录）');
    }
    if (!manual.includes('只读')) {
      problems.push(`${MANUAL} 里没有「只读」—— 健康库只读、不写回，这一条不能漏`);
    }
    facts.push('事实源：从系统健康库读取**已启用**');
  } else {
    const stmt = hs.disabledStatement?.zh;
    if (!stmt) {
      problems.push('healthSync 未启用时 disabledStatement.zh 必须写清那句 —— 事实源结构变了');
    } else if (!manual.includes(stmt)) {
      problems.push(`${MANUAL} 里没有「${stmt}」—— 事实源说这一版不读健康库，提交材料不要写超前`);
    }
  }

  // 给读者的指针：详细口径以《隐私政策》为准（说明书不复述第二份会漂的文本）
  if (!/《隐私政策》/.test(manual)) {
    problems.push(`${MANUAL} 里没有一处指向《隐私政策》—— 提交材料要说明详细口径在哪，`
      + '否则将来政策改了，读者会拿这份说明书当唯一事实');
  }

  // ── ③ 别在提交材料里抄"截图重出的日期/版本"（真源 docs/screenshots.md）
  if (/在\s*v\d+\.\d+\.\d+\s*上重出/.test(manual)) {
    problems.push(`${MANUAL} 里抄了界面图"在哪一版上重出" —— 那个事实的真源是 docs/screenshots.md；`
      + '抄一份就多一处会过期的（这句已经过期两轮），改成指向那份文档');
  }
  if (!manual.includes('screenshots.md')) {
    problems.push(`${MANUAL} 里没有指向 docs/screenshots.md 的指针 —— 截图怎么重出、重出到哪一版以那份为准`);
  }

  return { problems, facts };
}

// ───────────────────────────────────────────────────────────── 自检
//
// 每个用例都是**一种真会发生过的漂移**：图改名 / 图删了 / 张数写旧 / 屏数写旧 /
// 开关翻转后说明书没跟 / 把过期版本抄回来。
function selftest() {
  // 夹具里的“截图”只要**文件名**（这条守卫不读像素 —— 尺寸/齐/不夹带是 check-screenshots 的事）。
  // 名单从真目录读：截图套增删之后自检不该红在一个"夹具写死"的假原因上。
  const shotNames = readdirSync(join(ROOT, SHOTS))
    .filter((f) => f.toLowerCase().endsWith('.png'))
    .map((f) => f.replace(/\.png$/i, ''));
  if (!shotNames.length) throw new Error('自检夹具失效：真仓库的 store-assets/screenshots/ 里没有 PNG');

  const makeTree = (mutate) => {
    const root = mkdtempSync(join(tmpdir(), 'lianleme-copy-manual-'));
    mkdirSync(join(root, 'docs'), { recursive: true });
    mkdirSync(join(root, SHOTS), { recursive: true });
    for (const f of ['privacy-facts.json']) {
      writeFileSync(join(root, 'docs', f), readFileSync(join(ROOT, 'docs', f)));
    }
    // 说明书用**真文件**当基线（现状必须绿）；img 的图片路径在夹具里也照写，文件用空占位
    writeFileSync(join(root, MANUAL), readFileSync(join(ROOT, MANUAL)));
    for (const n of shotNames) writeFileSync(join(root, SHOTS, `${n}.png`), '');
    if (mutate) mutate(root);
    return root;
  };
  const swap = (root, rel, from, to) => {
    const p = join(root, rel);
    const s = readFileSync(p, 'utf8');
    if (!s.includes(from)) throw new Error(`自检夹具失效：${rel} 里没有「${from}」`);
    const out = s.split(from).join(to);
    if (out.includes(from)) throw new Error(`自检夹具没换干净：${rel} 里还剩「${from}」`);
    writeFileSync(p, out);
  };
  const factsEdit = (root, fn) => {
    const p = join(root, FACTS);
    const d = JSON.parse(readFileSync(p, 'utf8'));
    fn(d);
    writeFileSync(p, JSON.stringify(d, null, 2));
  };

  const cases = [
    ['修好之后的真说明书 → 绿', null, true, null],
    ['配图文件被改名/删掉 → 必须报（提交的 PDF 里会是一张破图）',
      (r) => rmSync(join(r, SHOTS, '07-summary.png')), false, '破图'],
    ['第四节点名了一张不存在的图（重拍时改了文件名）', (r) => swap(r, MANUAL,
      'screenshots/01-home.png', 'screenshots/01-home-v2.png'), false, '破图'],
    ['"引用了几屏"与实际配图行数对不上', (r) => {
      // 删掉一整行带图的表格行，但**不动**"引用了其中 N 屏"那句话 —— 两处就对不上了。
      // 删哪一屏也现算：取文档里第一个图片引用行。
      const p = join(r, MANUAL);
      const lines = readFileSync(p, 'utf8').split('\n');
      const idx = lines.findIndex((l) => l.startsWith('| ![') && l.includes('screenshots/'));
      if (idx < 0) throw new Error('自检夹具失效：说明书第四节里没有图片行');
      lines.splice(idx, 1);
      writeFileSync(p, lines.join('\n'));
    }, false, '引用了'],
    ['截图张数写旧了（重出后少了/多了一张）', (r) => {
      const claimed = /那一套共\s*(\d+)\s*张/.exec(readFileSync(join(r, MANUAL), 'utf8'));
      if (!claimed) throw new Error('自检夹具失效：说明书里没有「那一套共 N 张」');
      swap(r, MANUAL, `那一套共 ${claimed[1]} 张`, `那一套共 ${Number(claimed[1]) + 1} 张`);
    }, false, '实际有'],
    ['把"当前发布版本不含任何上报地址"抄回来 → 必须报',
      (r) => swap(r, MANUAL, '详细口径见随包发布的', '当前发布版本**不含任何上报地址**，详细口径按《隐私政策》执行'),
      false, '不含任何上报地址'],
    ['云备份开关翻成未启用，说明书还写着"已配好服务端地址" → 必须报', (r) => factsEdit(r, (d) => {
      d.cloudBackup.enabledInDistributedBuild = false;
    }), false, '本版本未提供云备份'],
    ['统计默认值翻向而说明书没跟（默认开写成默认关）', (r) => {
      swap(r, MANUAL, '**默认开启**，用户可在「我 → 隐私与关于」',
        '**默认关闭**，用户可在「我 → 隐私与关于」');
      // 正文里还有一处"默认开着"（"数据默认只在本机"那条），一起改掉才构成
      // "整份说明书都写成了默认关" 的负向现场；只改一处的话另一处会替它说对。
      const p = join(r, MANUAL);
      writeFileSync(p, readFileSync(p, 'utf8').replaceAll('**默认开着**', '**默认关闭**'));
    }, false, '是**默认开**的'],
    ['把"在哪一版上重出"抄回说明书 → 必须报（那是 screenshots.md 的事）', (r) => swap(r, MANUAL,
      '重出时间与版本以', '2026-10-05 在 v1.53.0 上重出'), false, '真源是 docs/screenshots.md'],
    ['健康库启用但说明书没写"系统健康库" → 必须报', (r) => {
      const p = join(r, MANUAL);
      writeFileSync(p, readFileSync(p, 'utf8').split('系统健康库').join('体成分来源'));
    }, false, '系统健康库'],
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
      why = `　→ 红了，但不是因为「${expect}」（红在：${problems[0].slice(0, 48)}）`;
    }
    if (!ok) bad += 1;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}${why}`);
    rmSync(root, { recursive: true, force: true });
  }
  if (bad) {
    console.error(`\n✗ 自检失败 ${bad} 项 —— 这个工具本身不可信，先修它`);
    process.exit(1);
  }
  console.log('\n✓ 自检通过：配图被改名/删掉、屏数与张数写旧、'
    + '开关翻转后说明书没跟、把过期版本抄回来都藏不住');
}

// ───────────────────────────────────────────────────────────────── 跑
if (process.argv.includes('--selftest')) {
  selftest();
} else {
  const rootArg = process.argv.find((a) => a.startsWith('--root='));
  const { problems, facts } = inspect(rootArg ? rootArg.slice('--root='.length) : ROOT);
  console.log('软著说明书核对（提交材料 ↔ 事实源 ↔ 交付的界面图）\n');
  for (const f of facts) console.log(`  ${f}`);
  if (problems.length) {
    console.log('');
    for (const p of problems) console.error(`  \x1b[31m✗\x1b[0m ${p}`);
    console.error(`\n✗ ${problems.length} 处对不上 —— 说明书是提交材料，别把"与包相反的话"交上去`);
    process.exit(1);
  }
  console.log('\n✓ 说明书里的界面图与数据流说法都与仓库一致（配图在交付套里、开关方向没写反）');
}
