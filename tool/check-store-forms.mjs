#!/usr/bin/env node
/**
 * 练了么 · 商店表单对账（事实源 ↔ Google Play 数据安全 ←→ App Store 隐私标签）
 *
 * **它为什么存在**：两张商店表单都是**提交材料**，填错不是"文案不美"，是**拒审或下架**。
 * 而它们现在只是两份 Markdown，谁也没核过 —— 埋点字段改过好几轮（v1.19 一次补了 9 个事件，
 * 现在 18 个），每一次都可能让某张表**悄悄变成假话**：
 *   * 新字段进了事件，Play 的「健康与健身」那行却没跟着改；
 *   * 某天把匿名统计改成默认开，而两张表还写着"可选 / 关闭即零上报"；
 *   * 有人图省事，把变体 A 的"不收集任何数据"抄成通用答案 ——
 *     而那个答案只对"没编上报地址的包"成立，对配了地址的包就是**假话**。
 *
 * 它核六类事（每条都是一种真会发生的漂移）：
 *   1. **两个变体都在**：A（没编地址的包）与 B（配了地址的包）必须分别成立 ——
 *      因为这个项目的包**确实有两种形态**（编译期开关）；
 *   2. **"不收集"只在变体 A 里说**：绝对化的否定答案不许出现在 A 的小节之外
 *      （抄成通用答案就等于对变体 B 撒谎）；
 *   3. **事实 → 表格**：只要 `privacy-facts.json` 里的事件带某个敏感字段
 *      （`weight_kg` / `reps` / `distance_m`），Play 的「健康与健身」那行就必须出现对应的中文词，
 *      App Store 那张表也必须有 Health & Fitness 那一行；
 *   4. **默认关**：事实源里 `analyticsOptIn.defaultOn === false` ⇒ 两张表都要写出这一点；
 *   5. **公共字段要披露**：事实源的 `commonFields` 里有 `device_id` / `app_version` ⇒
 *      两张表都要提到它们（Play 的「设备或其他 ID」、Apple 的 Device ID）；
 *   6. **不追踪**：事实源 `neverCollected` 里写着"设备广告标识符（无广告 SDK）"⇒
 *      两张表都要写出「无广告 SDK」这一句 —— 它是"Used for Tracking = 否"这句话的依据。
 *
 * 用法：
 *   node tool/check-store-forms.mjs              # 核仓库里那两张表
 *   node tool/check-store-forms.mjs --selftest   # 自检（造几套动过手脚的，验它抓得住）
 *
 * 退出码：任何一项不符 → 1。
 */

import { cpSync, existsSync, mkdtempSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** 事实里的字段 → 商店表格里该出现的词（Play 用中文，Apple 用类别名）。 */
const FIELD_TO_WORD = [
  ['weight_kg', '重量', '训练明细会随埋点出去：set_logged 带 weight_kg'],
  ['reps', '次数', '同上：reps'],
  ['distance_m', '距离', '同上：distance_m'],
];

/**
 * **已经决定过"不需要单独披露"**的事件字段。
 *
 * 为什么要有这份名单：事实源里的字段是"工程侧"的东西（事件字段名），而商店表单是
 * "要披露什么"的东西。两者的对应关系**不能靠猜** —— 所以这里写成显式清单：
 * 新加一个字段（例如哪天真的开始上报 `body_fat`）时，如果它既不在
 * [FIELD_TO_WORD] 里、也不在这份名单里，工具就判红，**逼人做一次决定**：
 * 要么加进上面那张映射（那就得改两张表），要么加进这里（那就等于签字说它不敏感）。
 * 少了这一步，"新字段悄悄进了统计、表单没动"就没人拦得住。
 */
const FIELDS_OK = new Set([
  'add_method', 'auto', 'channel', 'delta_reps', 'delta_weight_kg', 'direction',
  'duration_sec', 'entry', 'error', 'exercise_count', 'exercise_id', 'field', 'from',
  'has_note', 'has_weight', 'is_first_open', 'method', 'ms_since_launch', 'planned_sec',
  'pr_type', 'prev_value', 'reason_code', 'rpe', 'seconds_after_log', 'set_index',
  'set_type', 'skipped', 'source', 'step_index', 'suggested_reps', 'suggested_weight_kg',
  'suggestion_id', 'tap_count', 'tap_kinds', 'to', 'total_sets', 'total_volume_kg',
  'value', 'workout_id',
  // 2026-10-06（P1-1，云备份那 4 个事件）：**决定 = 不敏感，不必单独披露**。
  // 理由逐条写下来，因为这份名单的每一行都等于一句签字：
  //   * `ciphertext_bytes` / `workouts` / `body_synced` —— 都是**数量**（密文多大、
  //     恢复了多少次训练、带回来几条身体数据），是聚合计数，不含任何可识别信息；
  //   * `has_body` —— **布尔**（这次备份里有没有身体数据），与其他 `has_*` 同类
  //     （`has_weight` / `has_note` 早就这么处理了）。
  // ⚠️ 它们与 `weight_kg` 那种"真的把数值发出去"的字段是两回事：一个数字是
  // "有多少条"，另一个数字是"你练了多重"。前者不披露，后者必须披露。
  'ciphertext_bytes', 'has_body', 'workouts', 'body_synced',
]);

/** 事实里的公共字段 → 两张表分别该出现什么。 */
const COMMON_FIELD_WORDS = [
  ['device_id', 'device_id', 'Device ID'],
  ['app_version', 'app_version', 'Product Interaction'],
];

function inspect(root) {
  const problems = [];
  const facts = [];

  const factsPath = join(root, 'docs/privacy-facts.json');
  const playPath = join(root, 'docs/store-listing.md');
  const iosPath = join(root, 'docs/store-listing-ios.md');
  for (const [label, p] of [['privacy-facts.json', factsPath], ['store-listing.md', playPath],
    ['store-listing-ios.md', iosPath]]) {
    if (!existsSync(p)) {
      problems.push(`找不到 docs/${label} —— 对账的任一端没了，这条检查已经失效`);
    }
  }
  if (problems.length) return { problems, facts };

  const data = JSON.parse(readFileSync(factsPath, 'utf8'));
  const play = readFileSync(playPath, 'utf8');
  const ios = readFileSync(iosPath, 'utf8');

  // 事件里出现过的字段（含公共字段）
  const eventFields = new Set();
  for (const e of data.events ?? []) for (const f of e.fields ?? []) eventFields.add(f);
  const commonFields = (data.commonFields ?? []).map((c) => c.name);
  facts.push(`事实源：${(data.events ?? []).length} 个事件 · 公共字段 ${commonFields.length} 个 · `
    + `默认开启统计=${data.analyticsOptIn?.defaultOn}`);

  // ── 1. 两个变体都在，而且各自的标题点明了"这个包配没配地址"
  for (const [label, text] of [['store-listing.md', play], ['store-listing-ios.md', ios]]) {
    // ⚠️ 必须锚在 `### 变体 A：…` 这种**小节标题**上：两份文档的正文里也会提到
    // "变体 A/B"（例如"任一个配了地址 → 用变体 B"），按正文匹配会匹配到那一段。
    const a = /^###\s*变体\s*A[：:](.*)$/m.exec(text);
    const b = /^###\s*变体\s*B[：:](.*)$/m.exec(text);
    if (!a) problems.push(`${label} 里找不到「变体 A」小节 —— 两张商店表单都必须按"配没配地址"分两套`);
    if (!b) problems.push(`${label} 里找不到「变体 B」小节`);
    if (a && !/未配|没配|没编/.test(a[1])) {
      problems.push(`${label} 的变体 A 标题没说清"这个包没配上报地址" —— `
        + '读者会把它当成通用答案（而它对配了地址的包是假话）');
    }
    if (b && !/配了|已配|配过一个|任一个配了/.test(b[1])) {
      problems.push(`${label} 的变体 B 标题没说清"这个包配了地址"`);
    }
  }

  // ── 2. "不收集"这类绝对化答案只许出现在变体 A 的小节里
  const ABSOLUTE = /不收集任何|Data Not Collected|数据只存在设备本地|不发生传输/;
  for (const [label, text] of [['store-listing.md', play], ['store-listing-ios.md', ios]]) {
    const idxB = text.search(/^###\s*变体\s*B/m);
    const idxA = text.search(/^###\s*变体\s*A/m);
    if (idxB < 0 || idxA < 0) continue;
    // 变体 B 之后（到下一个同级标题）不许再出现绝对化的否定答案
    const afterB = text.slice(idxB);
    const nextHeading = afterB.slice(1).search(/\n##\s/);
    const bSection = nextHeading > 0 ? afterB.slice(0, nextHeading + 1) : afterB;
    if (ABSOLUTE.test(bSection)) {
      problems.push(`${label} 的变体 B 小节里出现了绝对化的"不收集/不出设备"答案 —— `
        + '配了地址的包不是这样，这句话会让整张表变成假话');
    }
  }

  // ── 3. 事实里的敏感字段 → Play 的健康与健身那行 + Apple 的类别行
  const playHealth = /健康与健身[^\n]*\|/.test(play)
    ? (play.match(/健康与健身[^\n]*/) ?? [''])[0]
    : '';
  for (const [field, word, why] of FIELD_TO_WORD) {
    if (!eventFields.has(field)) continue;
    if (!playHealth) {
      problems.push(`事件里有 ${field}（${why}），但 store-listing.md 里找不到「健康与健身」那一行`);
      continue;
    }
    if (!playHealth.includes(word)) {
      problems.push(`事件里有 ${field}，Play 的「健康与健身」那行却没写「${word}」—— `
        + '数据安全表填漏一项就是拒审/下架的理由');
    }
  }
  if ([...eventFields].some((f) => FIELD_TO_WORD.some(([k]) => k === f))
    && !/Health & Fitness/.test(ios)) {
    problems.push('play 表有健康数据，但 store-listing-ios.md 里没有 Health & Fitness 那一行 —— '
      + '两张表必须一致');
  }

  // ── 4. 默认关：事实源说了，两张表都得写出来
  if (data.analyticsOptIn?.defaultOn === false) {
    if (!/默认关/.test(play)) {
      problems.push('事实源里匿名统计是**默认关**的，但 store-listing.md 没写这一点 —— '
        + '"可选"这个词必须配一句"默认关"才站得住');
    }
    if (!/默认关闭|默认关/.test(ios)) {
      problems.push('事实源里匿名统计是**默认关**的，但 store-listing-ios.md 没写这一点');
    }
  }

  // ── 5. 公共字段（device_id / app_version）两张表都要披露
  for (const [field, playWord, iosWord] of COMMON_FIELD_WORDS) {
    if (!commonFields.includes(field)) continue;
    if (!play.includes(playWord)) {
      problems.push(`公共字段里有 ${field}，store-listing.md 里却没提「${playWord}」—— `
        + 'Play 的数据安全表要求逐类披露');
    }
    if (!ios.includes(iosWord)) {
      problems.push(`公共字段里有 ${field}，store-listing-ios.md 里却没提「${iosWord}」`);
    }
  }

  // ── 5之六. 标签的**取值**必须与事实一致（不只看类别，还看那两列怎么勾）
  //
  // 为什么单列一条：`check-store-forms` 此前只核"类别在不在、措辞对不对"，
  // 而 App Privacy 与 Play 数据安全表里真正会判错的是**那两列怎么勾**：
  // 「是否与身份关联」「是否用于追踪」「是否共享」。
  //
  // ⚠️ **2026-10-06 前提变了**（账号体系 P1-3）：当时的事实是"没有账号系统"，
  // 所以那两列只能全是「否」。现在有了**可选**的账号，而注册要**邮箱** ——
  // 邮箱就是身份本身，把它填成"否"是**假话**，Apple 那边正是一条拒审理由。
  // 所以判据改成按事实分档（事实在 `privacy-facts.json` 的 `account` 块里）：
  //
  //   * 邮箱那一行：与身份关联 = **是**（邮箱就是账号身份），用于追踪 = 否；
  //   * 其余每一行（匿名 device_id / 使用数据 / 健身数据…）：与身份关联 = 否、用于追踪 = 否；
  //   * 两张表的"是否共享"：一律 否。
  //
  // 判据本身也写成了"读事实"，不是"按字面匹配一句人话" —— 原来那版是从
  // `user_id.why` 里找「恒为 null / 没有账号」，改一句话就整块失效（这次就是它报的警）。
  {
    const collectsEmail = data.account?.collectsEmail === true;
    const noAdSdk = (data.neverCollected ?? []).some((x) => /广告/.test(x));
    const because = `${collectsEmail ? '账号是可选的、注册要邮箱，' : '没有账号系统、'}`
      + `${noAdSdk ? '没有广告 SDK/IDFA' : ''}`;

    // 邮箱那一行必须**存在**（漏了它就等于没申报）；它的列由下面按行判断
    const isEmailRow = (name) => /Contact Info|Email|邮箱/i.test(name);

    const iosRows = ios.split('\n').filter((l) => l.startsWith('| **'));
    for (const row of iosRows) {
      const cells = row.split('|').map((c) => c.trim()).filter(Boolean);
      if (cells.length < 5) continue;
      const emailRow = isEmailRow(cells[0]);
      // 第 3 列：是否与身份关联
      {
        const val = cells[3].replace(/[*\s]/g, '');
        if (emailRow) {
          if (!/^是/.test(val)) {
            problems.push(`store-listing-ios.md 的「${cells[0]}」把「是否与身份关联」填成了`
              + `「${cells[3]}」—— 邮箱就是账号身份，这一列必须是「是」`
              + `（填"否"就是假话，而 Apple 的申报是要签字负责的）`);
          }
        } else if (!/^否/.test(val)) {
          problems.push(`store-listing-ios.md 的「${cells[0]}」把「是否与身份关联」填成了`
            + `「${cells[3]}」—— 事实是${because}，除邮箱之外这一列只能是「否」`);
        }
      }
      // 第 4 列：是否用于追踪（**任何一行都不许填是**：我们没有跨 App 追踪）
      {
        const val = cells[4].replace(/[*\s]/g, '');
        if (!/^否/.test(val)) {
          problems.push(`store-listing-ios.md 的「${cells[0]}」把「是否用于追踪」填成了`
            + `「${cells[4]}」—— 事实是${because}、也不做跨 App 追踪，这一列只能是「否」`);
        }
      }
    }
    if (collectsEmail && !iosRows.some((r) => isEmailRow(r))) {
      problems.push('facts 说账号会收集邮箱，但 store-listing-ios.md 的 App Privacy 表里'
        + '没有邮箱那一行 —— 收集了就要逐个数据类别申报');
    }

    // Play 那张表：第 4 列是「是否共享」（一律 否）
    const playRows = play.split('\n').filter((l) => l.startsWith('| **'));
    for (const row of playRows) {
      const cells = row.split('|').map((c) => c.trim()).filter(Boolean);
      if (cells.length < 6) continue;
      if (!/^否/.test(cells[3].replace(/[*\s]/g, ''))) {
        problems.push(`store-listing.md 的「${cells[0]}」把「是否共享」填成了`
          + `「${cells[3]}」—— 事实是不向第三方共享`);
      }
    }
  }

  // ── 5之七. 商店的**字符上限**是真会拦人的（超一个字都存不进去）
  //
  // 这些数字来自商店自己的表单：App Store 名称/副标题 30、宣传文本 170、关键词 100；
  // Play 短描述 80、长描述 4000。文档里也各自标了上限 —— 两个都核：
  //   ① 文档里写的值和商店真值**是否一致**（写错了会让人按错的字数去改）；
  //   ② 文案**实际长度**有没有超（超了就是粘贴时被打回来）。
  // 计数按"用户会粘贴的样子"：去掉 markdown 的 `**` 与反引号，再算字符数。
  {
    const strip = (t) => t.replace(/\*\*/g, '').replace(/`/g, '').replace(/^>\s?/gm, '').trim();
    const playSection = (title) => {
      const m = play.split(new RegExp(`^##\\s*${title}`, 'm'));
      if (m.length < 2) return null;
      const rest = m[1];
      const cut = rest.search(/\n##\s/);
      return cut > 0 ? rest.slice(0, cut) : rest;
    };
    const quoteOf = (text) => (text ?? '').split('\n')
      .filter((l) => l.trimStart().startsWith('> ')).join('\n');

    // ---- App Store：表格行 + 标签后的引用/反引号
    const iosRow = (label) => {
      const m = ios.split('\n').find((l) => l.startsWith(`| ${label}`));
      if (!m) return null;
      const cells = m.split('|').map((c) => c.trim()).filter(Boolean);
      const declared = /≤\s*(\d+)/.exec(cells[0]);
      return { declared: declared ? Number(declared[1]) : null, value: strip(cells[1] ?? '') };
    };
    const iosAfter = (label) => {
      const lines = ios.split('\n');
      const idx = lines.findIndex((l) => l.includes(`**${label}`) && /≤\s*\d+/.test(l));
      if (idx < 0) return null;
      const declared = Number(/≤\s*(\d+)/.exec(lines[idx])[1]);
      const block = [];
      for (let i = idx + 1; i < lines.length; i += 1) {
        const l = lines[i];
        if (l.trim() === '' || l.startsWith('##')) break;
        block.push(l);
      }
      return { declared, value: strip(block.join('\n')) };
    };

    const checks = [];
    const name = iosRow('应用名称（≤30）') ?? iosRow('应用名称');
    if (name) checks.push(['App Store 应用名称', 30, name]);
    const sub = ios.split('\n').find((l) => l.startsWith('| 副标题'));
    if (sub) {
      const cells = sub.split('|').map((c) => c.trim()).filter(Boolean);
      checks.push(['App Store 副标题', 30,
        { declared: Number(/≤\s*(\d+)/.exec(cells[0])[1]), value: strip(cells[1]) }]);
    }
    const promo = iosAfter('宣传文本（Promotional Text，');
    if (promo) checks.push(['App Store 宣传文本', 170, promo]);
    const kw = iosAfter('关键词（');
    if (kw) checks.push(['App Store 关键词', 100, kw]);
    const shortSec = playSection('二、短描述');
    if (shortSec) {
      checks.push(['Play 短描述', 80,
        { declared: Number(/≤\s*(\d+)/.exec(shortSec)[1]), value: strip(quoteOf(shortSec)) }]);
    }
    const longSec = playSection('三、长描述');
    if (longSec) {
      checks.push(['Play 长描述', 4000,
        { declared: null, value: strip(quoteOf(longSec)) }]);
    }

    for (const [label, real, info] of checks) {
      if (info.declared !== null && info.declared !== real) {
        problems.push(`${label}：文档里写的上限是 ${info.declared}，商店真值是 ${real} —— `
          + '按文档那个数改字数的话，粘贴时还是会被打回来');
      }
      if (info.value.length > real) {
        problems.push(`${label} 有 ${info.value.length} 个字符，超过商店上限 ${real}`
          + `（按"去掉 ** 与反引号后"的实际粘贴长度算）`);
      }
    }
    facts.push(`字符上限：${checks.map(([l, r, i]) => `${l} ${i.value.length}/${r}`).join(' · ')}`);
  }

  // ── 5之八. 商店文案点名的截图，必须在**那一套要上传的图**里
  //
  // "三套里存在"不等于"能上传"：Play 传的是 `screenshots-play/`，App Store 传的是
  // `screenshots-ios/`。文案按文件名点名时，得对着**那一套**核。
  {
    const names = [...new Set((play.match(/\b\d{2}[a-z]?-[a-z0-9-]+\.png\b/g) ?? []))];
    for (const n of names) {
      if (!existsSync(join(root, 'store-assets/screenshots-play', n))) {
        problems.push(`store-listing.md 的文案点名了 ${n}，但它不在 `
          + `store-assets/screenshots-play/（Play 要上传的那一套）里 —— 文案与图对不上`);
      }
    }
    const iosNames = [...new Set((ios.match(/\b\d{2}[a-z]?-[a-z0-9-]+\.png\b/g) ?? []))];
    for (const n of iosNames) {
      if (!existsSync(join(root, 'store-assets/screenshots-ios', n))) {
        problems.push(`store-listing-ios.md 点名了 ${n}，但它不在 `
          + `store-assets/screenshots-ios/（App Store 要上传的那一套）里`);
      }
    }
  }

  // ── 6. 新字段必须做过决定（映射表 / 免披露名单，二选一）
  const mapped = new Set(FIELD_TO_WORD.map(([f]) => f));
  const undecided = [...eventFields]
    .filter((f) => !mapped.has(f) && !FIELDS_OK.has(f) && !commonFields.includes(f));
  if (undecided.length) {
    problems.push(`事实源里出现了没做过披露决定的字段：${undecided.join(', ')} —— `
      + '要么加进 FIELD_TO_WORD 并同步改两张商店表，要么加进 FIELDS_OK（等于签字说它不敏感）');
  }
  facts.push(`字段决定：映射 ${mapped.size} 个 · 免披露名单 ${FIELDS_OK.size} 个 · 未决定 ${undecided.length} 个`);

  // ── 7. "不追踪"的依据那句话必须还在
  const noAdSdk = (data.neverCollected ?? []).some((s) => /广告 SDK|广告标识符/.test(s));
  if (noAdSdk) {
    for (const [label, text] of [['store-listing.md', play], ['store-listing-ios.md', ios]]) {
      if (!/(没有|无)\s*广告\s*SDK/.test(text)) {
        problems.push(`事实源里写着"无广告 SDK"，但 ${label} 里找不到这句 —— `
          + '它是"Used for Tracking = 否"那句话的依据，删了就只剩结论没有理由');
      }
    }
  }

  return { problems, facts };
}

// ───────────────────────────────────────────────────────────── 自检
function selftest() {
  const makeTree = (mutate) => {
    const root = mkdtempSync(join(tmpdir(), 'lianleme-forms-'));
    mkdirSync(join(root, 'docs'), { recursive: true });
    for (const f of ['privacy-facts.json', 'store-listing.md', 'store-listing-ios.md']) {
      cpSync(join(ROOT, 'docs', f), join(root, 'docs', f));
    }
    // 两套要上传的图也要进夹具（空文件即可 —— 那两条规则只看"在不在"）：
    // 少了它们，"文案点名的截图必须在要上传的那一套里"这条会对每个用例都误报。
    for (const dir of ['store-assets/screenshots-play', 'store-assets/screenshots-ios']) {
      mkdirSync(join(root, dir), { recursive: true });
      for (const f of readdirSync(join(ROOT, dir))) {
        writeFileSync(join(root, dir, f), '');
      }
    }
    if (mutate) mutate(root);
    return root;
  };
  const swap = (root, rel, from, to) => {
    const p = join(root, 'docs', rel);
    const s = readFileSync(p, 'utf8');
    if (!s.includes(from)) throw new Error(`自检夹具失效：${rel} 里没有 ${from}`);
    const out = s.split(from).join(to);
    if (out.includes(from)) throw new Error(`自检夹具没换干净：${rel} 里还剩 ${from}`);
    writeFileSync(p, out);
  };

  const cases = [
    ['好的两张表：全绿', null, true, null],
    ['Play 的健康与健身那行漏了「重量」', (r) => swap(r, 'store-listing.md',
      '训练记录：动作、重量、次数、距离、组序、是否热身、完成时间', '训练记录：动作、次数、组序'), false,
      'Play 的「健康与健身」那行却没写「重量」'],
    // 这一条守的是**假阳性**：新加的事件字段若已被覆盖，就不该乱报
    ['事实源加一个字段已被覆盖的事件 → 不该误报', (r) => {
      const p = join(r, 'docs/privacy-facts.json');
      const d = JSON.parse(readFileSync(p, 'utf8'));
      d.events.push({ name: 'body_logged', when: '记体重时', fields: ['reps'] });
      writeFileSync(p, JSON.stringify(d, null, 2));
    }, true, null],
    ['事实源里冒出一个没做过披露决定的字段 → 必须报', (r) => {
      const p = join(r, 'docs/privacy-facts.json');
      const d = JSON.parse(readFileSync(p, 'utf8'));
      d.events.push({ name: 'body_logged', when: '记体重时', fields: ['body_fat'] });
      writeFileSync(p, JSON.stringify(d, null, 2));
    }, false, '没做过披露决定的字段：body_fat'],
    ['把变体 A 的"不收集"抄进了变体 B', (r) => swap(r, 'store-listing.md',
      '另外三个必须如实勾选的项：', '另外三个必须如实勾选的项（数据只存在设备本地）：'), false,
      '变体 B 小节里出现了绝对化'],
    ['事实源改成默认开统计，两张表还写着默认关', (r) => {
      const p = join(r, 'docs/privacy-facts.json');
      const d = JSON.parse(readFileSync(p, 'utf8'));
      d.analyticsOptIn.defaultOn = true;
      writeFileSync(p, JSON.stringify(d, null, 2));
    }, true, null],
    ['Play 表漏了 device_id 这一行', (r) => swap(r, 'store-listing.md',
      '| **设备或其他 ID** | `device_id`', '| **设备或其他 ID** |'), false, '没提「device_id」'],
    ['App Store 表漏了 Device ID 那一行', (r) => swap(r, 'store-listing-ios.md',
      '**Identifiers → Device ID**', '**Identifiers**'), false, '没提「Device ID」'],
    ['两张表里删掉了"无广告 SDK"那句依据', (r) => swap(r, 'store-listing-ios.md',
      '没有广告 SDK、没有 IDFA、不做跨 App 关联', '不做跨 App 关联'), false, '找不到这句'],
    ['变体 B 的标题不再说明"这个包配了地址"', (r) => swap(r, 'store-listing.md',
      '### 变体 B：**配了上报地址的包**（开关打开时）', '### 变体 B：**另一种填法**'), false,
      '变体 B 标题没说清'],
    ['变体 A 的标题没说"这个包没配地址"', (r) => swap(r, 'store-listing.md',
      '### 变体 A：**当前发布的包**（未配上报地址）', '### 变体 A：**推荐的填法**'), false,
      '变体 A 标题没说清'],
    ['文案点名的截图不在要上传的那一套里', (r) => {
      rmSync(join(r, 'store-assets/screenshots-play/04-picker.png'));
    }, false, '不在 store-assets/screenshots-play/'],
    ['短描述写超了（> 80 字）', (r) => {
      const p = join(r, 'docs/store-listing.md');
      const t = readFileSync(p, 'utf8');
      const anchor = '> 不需要注册、没有广告，数据只在你手机上。';
      if (!t.includes(anchor)) throw new Error('自检夹具失效：找不到短描述那段');
      writeFileSync(p, t.replace(anchor, `${anchor}${'多出来的字'.repeat(12)}。`));
    }, false, '超过商店上限 80'],
    ['文档把短描述上限写成 100（商店真值 80）', (r) => swap(r, 'store-listing.md',
      '## 二、短描述（≤ 80 字）', '## 二、短描述（≤ 100 字）'), false, '商店真值是 80'],
    ['App Store 表的"用于追踪"填成了是', (r) => swap(r, 'store-listing-ios.md',
      '| **Health & Fitness → Fitness** | 是 | Analytics | 否 | **否** |',
      '| **Health & Fitness → Fitness** | 是 | Analytics | 否 | **是** |'),
      false, '「是否用于追踪」填成了'],
    // 2026-10-06（账号体系）：**邮箱那一行的"与身份关联"必须是"是"**
    // —— 填"否"是假话，而这是 Apple 那边一条真实的拒审理由。
    ['App Store 表把邮箱那一行的"与身份关联"填成了否', (r) => swap(r, 'store-listing-ios.md',
      '| **Contact Info → Email Address** | **只在用户自己注册账号时** | App Functionality（登录 / 找回口令） | **是**（邮箱就是账号身份） | **否** |',
      '| **Contact Info → Email Address** | **只在用户自己注册账号时** | App Functionality（登录 / 找回口令） | **否** | **否** |'),
      false, '邮箱就是账号身份'],
    // 反过来：**别的行**填成"是"也要拦（否则这次改判据会把原来那条纪律放掉）
    ['App Store 表把 Device ID 那行的"与身份关联"填成了是', (r) => swap(r, 'store-listing-ios.md',
      '| **Identifiers → Device ID** | 是 | Analytics | 否（匿名随机 id，与账号无关，也不发给服务端） | **否** |',
      '| **Identifiers → Device ID** | 是 | Analytics | **是** | **否** |'),
      false, '除邮箱之外这一列只能是'],
    ['Play 表的"是否共享"填成了是', (r) => swap(r, 'store-listing.md',
      '| **应用活动** | 冷启动、进入训练屏、训练结束、休息计时、撤销一组 | 是 | 否 | 可选 |',
      '| **应用活动** | 冷启动、进入训练屏、训练结束、休息计时、撤销一组 | 是 | 是 | 可选 |'),
      false, '「是否共享」填成了'],
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
  console.log('\n✓ 自检通过：漏字段、没做过决定的新字段、把变体 A 的答案抄进 B、'
    + '漏披露 device_id / 删掉"无广告 SDK"、'
    + '**把"关联/追踪/共享"填成"是"**都藏不住（同时不乱报"已覆盖字段"）；');
}

// ───────────────────────────────────────────────────────────────── 跑
if (process.argv.includes('--selftest')) {
  selftest();
} else {
  // `--root=<dir>`：排查/自检用（默认仓库根，与 check-deploy 同一个约定）
  const rootArg = process.argv.find((a) => a.startsWith('--root='));
  const { problems, facts } = inspect(rootArg ? rootArg.slice('--root='.length) : ROOT);
  console.log('商店表单对账（事实源 ↔ Play 数据安全 ↔ App Store 隐私标签）\n');
  for (const f of facts) console.log(`  ${f}`);
  if (problems.length) {
    console.log('');
    for (const p of problems) console.error(`  \x1b[31m✗\x1b[0m ${p}`);
    console.error(`\n✗ ${problems.length} 处对不上 —— 商店表单填错是拒审/下架的理由，不是文案问题`);
    process.exit(1);
  }
  console.log('\n✓ 两张表都与事实源一致：变体结构在、"不收集"没被抄进 B、'
    + '敏感字段都披露了、默认关与不追踪都写了依据');
}
