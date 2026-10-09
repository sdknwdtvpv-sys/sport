#!/usr/bin/env node
/**
 * 练了么 · 隐私政策对账（**让政策不是一份写完就烂的文件**）
 *
 * **它解决什么**：隐私政策最容易烂掉的方式是「代码变了、文档没变」，而且**没有任何东西会报错**。
 * 2026-09-29 就真发生过：埋点补了 5 个事件与 7 个公共字段（含 `device_id`），
 * 而政策正文还写着"只产生 4 类事件" —— 那是最该披露的东西。
 *
 * 这个脚本把三份东西对起来：
 *   ① 代码实际会做的事（扫 `track('...')` 与 analytics_context 的字段、读 AndroidManifest）
 *   ② `docs/privacy-facts.json`（单一事实源）
 *   ③ `docs/privacy-policy.md` 的正文（给人看的）
 *
 * 用法：
 *   node tool/privacy-audit.mjs                  # 静态对账（verify.sh 会跑这一档）
 *   node tool/privacy-audit.mjs --apk <apk>      # 再对一次**打包后**的合并权限（发布前跑）
 *   node tool/privacy-audit.mjs --json           # 机器可读
 *
 * 退出码：对不上 → 1。**这一条是硬门禁**：加了一个新埋点字段却不在政策里写清楚，不许合并。
 */

import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { findAapt2, sdkRoots as sdkRootsList } from './lib/android-sdk.mjs';
import { isHistorical } from './lib/docs.mjs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const FACTS = join(ROOT, 'docs/privacy-facts.json');
const POLICY = join(ROOT, 'docs/privacy-policy.md');
// 英文版也是**要发布**的那份（Google Play 用它）。2026-09-30 发现它已经漂了：
// 写着"339 个动作"和"4 个埋点事件"，而事实是 351 与 9 —— 中文版对、英文版过期，
// 而当时的检查只读中文版，所以两边不一致这件事**没有任何东西会发现**。
const POLICY_EN = join(ROOT, 'docs/privacy-policy.en.md');
const MANIFEST = join(ROOT, 'app/android/app/src/main/AndroidManifest.xml');

/** 内置动作库到底有多少个 —— 政策里写了"（N 个动作）"，那个 N 必须是真的。
 *  从种子读，不写死：动作数会变，写死只会变成第二处会过期的地方。 */
function countSeedExercises() {
  const seed = JSON.parse(readFileSync(join(ROOT, 'seed/exercises.json'), 'utf8'));
  return (seed.exercises ?? seed).length;
}

/** 扫源码里所有 `track('事件名'` —— 这是"客户端到底会发什么"的唯一真源 */export function scanEmittedEvents(dir) {
  const out = new Set();
  const walk = (d) => {
    for (const f of readdirSync(d)) {
      const p = join(d, f);
      if (existsSync(p) && readdirSync && statIsDir(p)) walk(p);
      else if (f.endsWith('.dart')) {
        const src = readFileSync(p, 'utf8');
        for (const m of src.matchAll(/track\(\s*'([a-z_]+)'/g)) out.add(m[1]);
      }
    }
  };
  walk(dir);
  return [...out].sort();
}

function statIsDir(p) {
  try {
    return readdirSync(p) !== undefined;
  } catch {
    return false;
  }
}

/** 从 analytics_context.dart 里抠出公共字段名（`'name':` 形式的键） */
export function scanCommonFields(file) {
  const src = readFileSync(file, 'utf8');
  const keys = new Set();
  for (const m of src.matchAll(/^\s*'([a-z_]+)':/gm)) keys.add(m[1]);
  return [...keys].sort();
}

/** 读我们自己 manifest 里声明的权限（插件合并进来的要 `--apk` 才看得到） */
export function scanManifestPermissions(xml) {
  const out = [];
  for (const m of xml.matchAll(/<uses-permission\s+([^/>]+)\/>/g)) {
    const attrs = m[1];
    const name = /android:name="([^"]+)"/.exec(attrs)?.[1];
    const max = /android:maxSdkVersion="(\d+)"/.exec(attrs)?.[1];
    if (name) out.push({ name, maxSdkVersion: max ? Number(max) : null });
  }
  return out;
}

/**
 * 「身体数据」字段 ↔ 政策正文 ↔ `db.dart` 的**双向**对账。
 *
 * 抽成纯函数只为一件事：能喂**故意写坏**的输入进去自检（`node tool/privacy-audit.mjs --selftest`）。
 * 一个从没抓住过东西的守卫等于没有 —— 这条规则自己就踩过这个坑（政策正文里"默认关"
 * 那句话在别处出现过，于是规则一路绿灯，见 CHANGELOG 2026-09-30）。
 *
 * @param {{fields?: object, policy: string, enText: string, dbSrc: string}} input
 * @returns {string[]} 错误（空数组 = 通过）
 */
/**
 * 对外文档里"统计开关默认值"的说法有没有写反。
 *
 * 为什么抽成纯函数：这一条**以前没有自检**（而且只在 `defaultOn === false` 时才跑）——
 * "只在某一个方向上生效的守卫"静默失效起来毫无痕迹。2026-10-07 默认值翻向时顺手补上：
 * 判据本体不再依赖事实源的方向，两个方向各有自检用例。
 *
 * 判据：
 *   * 只有**提到统计开关**的行才看（中英各一套词）；
 *   * `defaultOn=true` 时"默认关闭/默认关着"是写反了；`defaultOn=false` 时反过来；
 *   * 一行里若同时给出了正确说法（"（由「默认关闭」改来）"这种注记），一律放过；
 *   * 本来就是历史叙述的行放过（`isHistorical`，与另外两个 check-doc-* 共用一份判据）；
 *   * **"默认开关"这个说法不算表态**（它说的是那个开关本身）—— 用负向断言排掉。
 */
export function checkAnalyticsDefaultDocs({ defaultOn, docs }) {
  const errors = [];
  const switchZh = /(统计|帮助改进产品)/;
  const saysOnZh = /默认\s*(?:是|为)?\s*(?:开启|打开|开着|开(?!关))/;
  const saysOffZh = /默认\s*(?:是|为)?\s*(?:关闭|关着|关(?!闭))/;
  const switchEn = /(analytics|statistics|help improve)/i;
  const saysOnEn = /(on by default|enabled by default|default on\b)/i;
  const saysOffEn = /(off by default|default off|disabled by default)/i;
  for (const { rel, text } of docs) {
    const isEn = rel.endsWith('.en.md');
    text.split('\n').forEach((line, i) => {
      const mentions = isEn ? switchEn.test(line) : switchZh.test(line);
      if (!mentions) return;
      const onM = (isEn ? saysOnEn : saysOnZh).exec(line);
      const offM = (isEn ? saysOffEn : saysOffZh).exec(line);
      // 写反了的那个说法，就是判红的位置（也是"历史窗口"要看的那一处）
      const wrongM = defaultOn ? offM : onM;
      const rightM = defaultOn ? onM : offM;
      if (!wrongM || rightM) return;
      // ⚠️ 窗口判据，不是整行判据：`isHistorical` 看的是**这处说法前后 40 字**。
      // 这里踩过一次（自检当场抓到）：your-todo 里那行很长，"（当时是 schema v13…）"
      // 离"默认关闭"好几十字远 —— 按整行判会把当期说法一起放过（那正是 2026-09-30
      // 在 check-doc-versions 里踩过的同一个坑，两份守卫共用这一份判据）。
      if (isHistorical(line, wrongM.index, wrongM[0].length)) return;
      errors.push(`${rel}:${i + 1} 把统计开关说成"默认${defaultOn ? '关' : '开'}"了，`
        + `而事实源里 \`analyticsOptIn.defaultOn\` 是 ${defaultOn} —— `
        + '这行是对外的事实陈述，说反了就是假话');
    });
  }
  return errors;
}

export function checkSensitiveFields({ fields, policy, enText, dbSrc }) {
  const errors = [];
  if (!fields) {
    return ['privacy-facts.json 的 sensitiveLocal 少了 fields —— '
      + '「身体数据」有哪些字段必须显式列出来，否则新加字段没人拦'];
  }
  for (const f of fields.zh ?? []) {
    if (!policy.includes(f)) {
      errors.push(`身体数据字段「${f}」写进了库，但中文政策正文里没有它`
        + '（收集了没说 = 政策失实）');
    }
  }
  for (const f of fields.en ?? []) {
    // 英文**不区分大小写**：同一句里「Body weight」在句首会大写、在句中是小写，
    // 按字面比会为一个大写字母误报（自检里当场抓到过一次 —— 那就是这条规则的价值）。
    if (!enText.toLowerCase().includes(f.toLowerCase())) {
      errors.push(`身体数据字段「${f}」的中文政策点了名，但英文政策里没有它`
        + '（英文版也是要发布的那一份）');
    }
  }
  for (const c of fields.columns ?? []) {
    if (!new RegExp(`get ${c.column}\\b`).test(dbSrc)) {
      errors.push(`政策承诺了身体数据字段「${c.zh}」，但 app/lib/data/db.dart 里`
        + `找不到那一列（${c.column}）—— 政策与库已经对不上`);
    }
  }
  // 反向：库里有身高这一列，政策也要点到名（身高不在 columns 里，
  // 因为它不进 body_metric，而是 user_profile.height_cm，单独查一次）。
  if (/get heightCm\b/.test(dbSrc) && !(fields.zh ?? []).includes('身高')) {
    errors.push('db.dart 里有 heightCm（身高），但 sensitiveLocal.fields.zh 没列它 —— '
      + '库里存了、政策没写，就是"收集了没说"');
  }
  return errors;
}

export function audit({ root = ROOT, apkPermissions = null } = {}) {
  const facts = JSON.parse(readFileSync(FACTS, 'utf8'));
  const policy = readFileSync(POLICY, 'utf8');
  const emitted = scanEmittedEvents(join(root, 'app/lib'));
  const common = scanCommonFields(join(root, 'app/lib/analytics/analytics_context.dart'));
  const manifest = scanManifestPermissions(readFileSync(MANIFEST, 'utf8'));

  const errors = [];
  const warnings = [];

  // ① 代码发了、但事实源里没有的事件 —— 这是最该拦的一种
  const factEvents = new Set(facts.events.map((e) => e.name));
  for (const e of emitted) {
    if (!factEvents.has(e)) {
      errors.push(`客户端会发「${e}」，但 docs/privacy-facts.json 里没有它 —— `
        + `新埋点必须在隐私政策里披露`);
    }
  }
  // 反向：事实源里有、代码却不发（政策说了做不到的事，同样是错）
  for (const e of factEvents) {
    if (!emitted.includes(e)) {
      errors.push(`隐私事实里写了「${e}」，但客户端根本不发它 —— 政策不该比代码说得更多`);
    }
  }

  // ② 公共字段
  const factFields = new Set(facts.commonFields.map((f) => f.name));
  for (const f of common) {
    if (!factFields.has(f)) {
      errors.push(`每个事件都会带上「${f}」，但它不在隐私事实里 —— `
        + `device_id 这类字段必须写明`);
    }
  }
  for (const f of factFields) {
    if (!common.includes(f)) {
      errors.push(`隐私事实里写了公共字段「${f}」，但代码里并不存在`);
    }
  }

  // ③ 权限：manifest 里声明的必须都在事实源里，且 maxSdkVersion 要对得上
  for (const p of manifest) {
    const known = facts.permissions.find((x) => x.name === p.name);
    if (!known) {
      errors.push(`manifest 声明了权限「${p.name}」，但隐私事实里没有 —— 权限必须披露`);
      continue;
    }
    if (known.maxSdkVersion !== p.maxSdkVersion) {
      errors.push(`权限「${p.name}」的 maxSdkVersion：代码是 ${p.maxSdkVersion}，`
        + `隐私事实写的是 ${known.maxSdkVersion}`);
    }
  }

  // ④ 事实源里的每一条都要在**政策正文**里出现（正文是给人看的）
  const mustAppear = [
    ...facts.events.map((e) => e.name),
    ...facts.commonFields.map((f) => f.name),
    ...facts.permissions.map((p) => p.name.split('.').pop()),
  ];
  const missingInText = mustAppear.filter((n) => !policy.includes(n));
  if (missingInText.length) {
    errors.push(`这些名字没有出现在 docs/privacy-policy.md 正文里：${missingInText.join('、')}`);
  }
  // 政策里明说的"不收集"清单也必须还在（删掉一条就是改承诺）
  for (const n of facts.neverCollected) {
    // 取第一个关键词（顿号/括号前的部分）—— 按字数切片切出来的不是词，
    // 那样写出来的检查永远匹配不上，只会一直报警告（然后被人忽略）。
    const key = n.split(/[、（]/)[0];
    if (!policy.includes(key)) {
      warnings.push(`政策正文里找不到「不收集」条目：${n}`);
    }
  }

  // ⑤ 英文版同样要发布，所以同样要核：标识符不能少，数字不能过期。
  if (existsSync(POLICY_EN)) {
    const policyEn = readFileSync(POLICY_EN, 'utf8');
    const missingEn = mustAppear.filter((n) => !policyEn.includes(n));
    if (missingEn.length) {
      errors.push(`这些名字没有出现在 docs/privacy-policy.en.md（要发布的英文版）里：`
        + missingEn.join('、'));
    }

    // 数字类断言：中文与英文都必须与事实源/种子一致。
    // 只查**政策自己声明的口径数字**，不查正文里顺口提到的别的数字。
    const exerciseCount = countSeedExercises();
    const numericChecks = [
      { label: '埋点事件数', src: policy, re: /(\d+)\s*类事件/, want: facts.events.length },
      { label: '埋点事件数（英文）', src: policyEn, re: /(\d+)\s+analytics events/i, want: facts.events.length },
      { label: '动作库数量', src: policy, re: /（(\d+)\s*个动作）/, want: exerciseCount },
      { label: '动作库数量（英文）', src: policyEn, re: /\((\d+)\s+exercises\)/, want: exerciseCount },
    ];
    for (const c of numericChecks) {
      const m = c.re.exec(c.src);
      if (!m) {
        warnings.push(`${c.label}：政策里没找到可核对的数字（措辞变了？检查要跟着改）`);
        continue;
      }
      if (Number(m[1]) !== c.want) {
        errors.push(`${c.label}：政策写的是 ${m[1]}，实际是 ${c.want}`);
      }
    }
  }

  // ⑤ 权限名字必须出现在两版政策里。
  //
  // 为什么连 implied 也要查：`READ_EXTERNAL_STORAGE` 是系统因 WRITE 隐含授予的，
  // 它**会出现在 API ≤29 老系统的权限列表里**。只在 facts 里登记、政策里不提，
  // 等于"机器知道、用户看不到" —— 那正是隐私政策最不该有的状态。
  if (existsSync(POLICY_EN)) {
    const policyEnText = readFileSync(POLICY_EN, 'utf8');
    for (const perm of [...facts.permissions, ...(facts.impliedPermissions ?? [])]) {
      // 政策正文里可能写全名，也可能在句子里用短名（`READ_EXTERNAL_STORAGE`）——
      // 所以要求写在 `policyPhrase` 里，别让检查去猜措辞（猜错就会一直误报，然后被忽略）。
      const phrase = perm.policyPhrase ?? perm.name;
      if (!policy.includes(phrase)) {
        errors.push(`政策正文里没有提到权限「${phrase}」（隐私事实里登记了它）`);
      }
      if (!policyEnText.includes(phrase)) {
        errors.push(`英文政策里没有提到权限「${phrase}」`);
      }
    }
  }

  // ⑤之五 第三方依赖（SDK）清单：**装进包里的每个直接依赖都要在政策里出现**。
  //
  // 为什么要有这一条：国内商店明确要求把第三方 SDK 集中展示、写清名称/功能/怎么处理个人信息
  // （小米《隐私政策不合规的问题解析和修改指引》）。而"加一个新依赖"这件事在本仓库里
  // 太容易了 —— pubspec 加一行就完事，政策没人会想起来改。所以让它变成一条能跑的命令：
  // 直接从 `app/pubspec.yaml` 读运行时依赖，逐个要求在政策的"第三方依赖清单"那一段里出现。
  {
    const pubspec = readFileSync(join(ROOT, 'app/pubspec.yaml'), 'utf8');
    // 只取 `dependencies:` 段（dev 依赖不进包，所以不要求在清单里）
    const lines = pubspec.split('\n');
    const start = lines.findIndex((l) => l.startsWith('dependencies:'));
    const deps = [];
    for (let i = start + 1; i >= 0 && i < lines.length; i++) {
      const line = lines[i];
      if (!/^\s/.test(line) && line.trim() !== '') break;
      const m = line.match(/^ {2}([a-z0-9_]+):/);
      if (m && m[1] !== 'flutter') deps.push(m[1]);
    }

    // 清单那一段：中文按 `## 三之五、第三方依赖（SDK）清单` 起、到下一个 `## ` 止
    const sectionOf = (text, head) => {
      const i = text.indexOf(head);
      if (i < 0) return null;
      const rest = text.slice(i + head.length);
      const j = rest.indexOf('\n## ');
      return j < 0 ? rest : rest.slice(0, j);
    };
    const zhList = sectionOf(policy, '第三方依赖（SDK）清单');
    const enList = existsSync(POLICY_EN)
      ? sectionOf(readFileSync(POLICY_EN, 'utf8'), 'Third-party dependencies (SDK list)')
      : '';

    if (!zhList) {
      errors.push('政策正文里找不到「第三方依赖（SDK）清单」那一段 —— '
        + '国内商店要求集中展示第三方 SDK（措辞变了？检查要跟着改）');
    } else {
      for (const d of deps) {
        // 用反引号包起来的包名，避免误匹配（例如 gal 会出现在别的词里）
        if (!zhList.includes('`' + d + '`')) {
          errors.push(`直接依赖「${d}」没有出现在政策的第三方依赖清单里 `
            + '（加了依赖就要在政策里写清楚它是干什么的、会不会收集信息）');
        }
      }
      if (enList) {
        for (const d of deps) {
          if (!enList.includes('`' + d + '`')) {
            errors.push(`直接依赖「${d}」没有出现在英文政策的 SDK 清单里`);
          }
        }
      }
    }
  }

  // ⑥ 云备份：能力已经写进代码，但**当前发布配置下没有启用**。
  //
  // 为什么值得单独一条：这是本项目第一个"数据可能离开设备"的功能，
  // 而它的开关是**编译期**的（--dart-define=LIANLEME_BACKUP_URL）。
  // 门禁看不到你打算怎么打包，所以这里的 `enabledInDistributedBuild` 是面镜子：
  //   * false → 政策里必须写明"本版本未提供云备份"（说了"不上传"就必须真的没这条通道）
  //   * true  → 政策里必须逐条披露离开设备的东西
  // 两个方向都查，改哪边忘了另一边都会红。**故意不查代码里有没有那个地址**：
  // 代码里恒有（默认空串），查它等于空转。
  {
    const cb = facts.cloudBackup;
    if (!cb) {
      errors.push('privacy-facts.json 少了 cloudBackup —— 云备份会（在启用后）把数据送出设备，'
        + '这条数据流向必须显式声明，不能靠"默认关着"含糊过去');
    } else {
      const policyEnText = existsSync(POLICY_EN) ? readFileSync(POLICY_EN, 'utf8') : '';
      if (cb.enabledInDistributedBuild === true) {
        for (const phrase of cb.enabledPhrases?.zh ?? []) {
          if (!policy.includes(phrase)) {
            errors.push(`云备份已启用，但政策正文里没有「${phrase}」`);
          }
        }
        for (const phrase of cb.enabledPhrases?.en ?? []) {
          if (!policyEnText.includes(phrase)) {
            errors.push(`云备份已启用，但英文政策里没有「${phrase}」`);
          }
        }
      } else {
        const zh = cb.disabledStatement?.zh;
        const en = cb.disabledStatement?.en;
        if (!zh || !en) {
          errors.push('cloudBackup 没启用时，必须在 disabledStatement 里写清中英各自那句话');
        } else {
          if (!policy.includes(zh)) {
            errors.push(`云备份当前未启用，政策正文必须写明「${zh}」——`
              + `否则读者会以为这份政策的"不上传"覆盖了一个其实存在的通道`);
          }
          if (!policyEnText.includes(en)) {
            errors.push(`云备份当前未启用，英文政策必须写明「${en}」`);
          }
        }
      }
    }
  }

  // ⑰ 账号体系（2026-10-06，P1-3）：**邮箱是这套应用里唯一一件可识别个人信息**，
  // 而它的形态是"可选" —— 这两件事都必须同时写在政策里，否则会落到两种谎话之一：
  // 「我们不要邮箱」（其实注册时要）或者「你必须注册」（其实是可选的）。
  //
  // 为什么用"事实里写的说法"而不是在这里硬编码句子：与云备份那条同源 ——
  // 换句子时先改 facts，政策跟着改，两边对不上就红。
  {
    const acc = facts.account;
    if (!acc) {
      errors.push('privacy-facts.json 少了 account —— 账号体系会把邮箱（可识别个人信息）'
        + '送到服务端，这条数据流向必须显式声明');
    } else {
      const policyEnText = existsSync(POLICY_EN) ? readFileSync(POLICY_EN, 'utf8') : '';
      if (acc.collectsEmail === true) {
        for (const phrase of acc.policyPhrases?.zh ?? []) {
          if (!policy.includes(phrase)) errors.push(`账号体系会收集邮箱，但政策正文里没有「${phrase}」`);
        }
        for (const phrase of acc.policyPhrases?.en ?? []) {
          if (!policyEnText.includes(phrase)) errors.push(`账号体系会收集邮箱，但英文政策里没有「${phrase}」`);
        }
        // 可选性也必须写出来：审核与用户都会问"不注册能不能用"
        if (acc.optional === true) {
          if (!acc.policyPhrases?.zh?.some((x) => /不注册/.test(x))) {
            errors.push('account 声明是"可选"的，policyPhrases.zh 里就必须有一句写明"不注册也能用"');
          }
        }
      }
      // 生成物：应用内的收集清单必须真的写到邮箱（164 号文要的是"收集了什么都写下来"）
      const list = join(ROOT, 'app/assets/collection-list.txt');
      if (existsSync(list)) {
        const text = readFileSync(list, 'utf8');
        if (acc.collectsEmail === true && !text.includes('邮箱')) {
          errors.push('app/assets/collection-list.txt 里没有"邮箱" —— 收集清单漏了它会与政策矛盾'
            + '（它由 node tool/gen-privacy-page.mjs 生成，改完源再重出）');
        }
      }
      // 商店表单：邮箱那一行必须存在（check-store-forms 会核它的列怎么填）
      // ⚠️ 判据要**具体到那一行**：文件里本来就有"联系邮箱"（客服联系方式），
      // 只搜"邮箱"两个字会被它蒙过去（第一版就是这么写的，加完还是绿的）。
      const iosListing = join(ROOT, 'docs/store-listing-ios.md');
      if (acc.collectsEmail === true && existsSync(iosListing)
        && !/Contact Info[^\n]*Email/i.test(readFileSync(iosListing, 'utf8'))) {
        errors.push('docs/store-listing-ios.md 的 App Privacy 表里没有「Contact Info → Email」那一行 ——'
          + 'Apple 要求逐个数据类别申报，收集了就要写');
      }
      const playListing = join(ROOT, 'docs/store-listing.md');
      if (acc.collectsEmail === true && existsSync(playListing)
        && !/个人信息[^\n]*邮箱/.test(readFileSync(playListing, 'utf8'))) {
        errors.push('docs/store-listing.md 的数据安全表里没有「个人信息 → 邮箱」那一行');
      }
    }
  }

  // ⑦ 打包后的合并权限（发布前用 --apk 跑）
  if (apkPermissions) {
    const allowed = new Set([
      ...facts.permissions.map((p) => p.name),
      ...(facts.injectedPermissions ?? []),
      // implied（系统因别的权限隐含授予的）也算已披露 —— 但必须在事实源里有一条，
      // 不能靠"反正没人声明"糊过去。
      ...(facts.impliedPermissions ?? []).map((p) => p.name),
    ]);
    for (const p of apkPermissions) {
      if (!allowed.has(p)) {
        errors.push(`打包后的 APK 里出现了未披露的权限「${p}」—— `
          + `插件加的、或系统隐含授予的，都必须在政策与隐私事实里说明`);
      }
    }
  }

  // ⑨ 「匿名统计默认关」必须**三处一致**：事实源、代码里的默认值、中英政策正文。
  //
  // 这是审计 A 的后半段：非必需的收集要用户**主动**开启。它天然容易烂 ——
  // 改代码不改政策、或改政策不改代码，两边看起来都"没问题"。所以横着查。
  {
    const opt = facts.analyticsOptIn;
    if (!opt) {
      errors.push('privacy-facts.json 少了 analyticsOptIn —— 匿名统计是「非必需」的收集，'
        + '它的默认值（开/关）必须显式声明，不能靠代码默认值含糊过去');
    } else {
      const dbSrc = readFileSync(join(ROOT, 'app/lib/data/db.dart'), 'utf8');
      const m = dbSrc.match(
        /analyticsEnabled\s*=>\s*boolean\(\)\.withDefault\(\s*const Constant\((true|false)\)/);
      if (!m) {
        errors.push('app/lib/data/db.dart 里找不到 analyticsEnabled 的默认值 —— '
          + '这条跨文件检查已经失效，别当成通过');
      } else if ((m[1] === 'true') !== opt.defaultOn) {
        errors.push(`匿名统计：事实源写的是 defaultOn=${opt.defaultOn}，`
          + `而代码里的默认值是 ${m[1]} —— 两者必须一致`);
      }
      const enText = existsSync(POLICY_EN) ? readFileSync(POLICY_EN, 'utf8') : '';
      for (const phrase of opt.policyPhrases?.zh ?? []) {
        if (!policy.includes(phrase)) {
          errors.push(`匿名统计默认关：政策正文里没有「${phrase}」`);
        }
      }
      for (const phrase of opt.policyPhrases?.en ?? []) {
        if (!enText.includes(phrase)) {
          errors.push(`匿名统计默认关：英文政策里没有「${phrase}」`);
        }
      }
    }
  }

  // ⑩ 敏感个人信息的**单独同意**：政策说法 + 代码里那条记录，两头都要在。
  //
  // 体重是医疗健康类的敏感个人信息（PIPL 第 29 条要求单独同意）。这一条**天生容易烂**：
  // 代码里加了个新页面、忘了写政策；或政策写了、代码里那道门被删掉。所以横着查。
  {
    const sl = facts.sensitiveLocal;
    if (!sl) {
      errors.push('privacy-facts.json 少了 sensitiveLocal —— 体重属于敏感个人信息，'
        + '它的"单独同意"必须显式声明，不能靠默认值含糊过去');
    } else {
      const dbSrc = readFileSync(join(ROOT, 'app/lib/data/db.dart'), 'utf8');
      if (!/IntColumn get bodyMetricConsentAtMs\b/.test(dbSrc)) {
        errors.push('政策声明了体重要单独同意，但 app/lib/data/db.dart 里找不到那条记录'
          + '（bodyMetricConsentAtMs）—— 这条跨文件检查已经失效，别当成通过');
      }
      const screenPath = join(ROOT, 'app/lib/features/body/body_metric_screen.dart');
      const screenSrc = existsSync(screenPath) ? readFileSync(screenPath, 'utf8') : '';
      if (!/Key\('body-consent-agree'\)/.test(screenSrc)) {
        errors.push('「身体数据」页里找不到单独同意那道门（body-consent-agree）—— '
          + '政策承诺了"第一次进入时单独征求同意"，代码里就必须有它');
      }
      // PIPL 第 15 条：给了同意就得给**撤回**的路。政策里现在写了"随时可以撤回"，
      // 所以这一条是"政策说法 ↔ 代码有没有那个入口"的对账 —— 少一个就是空承诺。
      if (!/Key\('body-revoke'\)/.test(screenSrc)) {
        errors.push('政策里承诺了"随时可以撤回同意"，但「身体数据」页里找不到撤回入口'
          + "（Key('body-revoke')）—— 撤回权不能只写在政策里");
      }
      const repoPath = join(ROOT, 'app/lib/data/profile_repository.dart');
      const repoSrc = existsSync(repoPath) ? readFileSync(repoPath, 'utf8') : '';
      if (!/Future<void> clearBodyMetricConsent\(/.test(repoSrc)) {
        errors.push('找不到 clearBodyMetricConsent —— 撤回入口必须真的能把同意清掉，'
          + '否则用户点了"撤回"而同意还在（这一条是真会骗人的那种 bug）');
      } else if (!/UserProfileCompanion\(/.test(repoSrc)) {
        errors.push('clearBodyMetricConsent 没有用 Companion 写 null —— drift 对 DataClass 是 '
          + 'nullToAbsent，那样写出来是"点了撤回，同意还在"（负向测试验过）');
      }
      const enText = existsSync(POLICY_EN) ? readFileSync(POLICY_EN, 'utf8') : '';
      for (const phrase of sl.policyPhrases?.zh ?? []) {
        if (!policy.includes(phrase)) {
          errors.push(`敏感个人信息单独同意：政策正文里没有「${phrase}」`);
        }
      }
      for (const phrase of sl.policyPhrases?.en ?? []) {
        if (!enText.includes(phrase)) {
          errors.push(`敏感个人信息单独同意：英文政策里没有「${phrase}」`);
        }
      }

      // v1.52 起「身体数据」不止体重：腰围 / 肌肉量 / 身高都进了库。
      // 这一类漂移最隐蔽 —— 功能加了、政策表格那一格没改，于是"收集了没说"。
      // 所以**双向**对账：政策正文里必须点到每一列的名字，db.dart 里也必须真有那一列，
      // 少一头都报错（删了列却留着政策、或加了列忘了政策，两种都是错的）。
      // 规则抽在下面那个纯函数里，为的是能喂假输入自检（`--selftest`）。
      errors.push(...checkSensitiveFields({
        fields: sl.fields, policy, enText, dbSrc,
      }));
    }
  }

  // ⑩之六 「从系统健康库读取」（2026-10-09）：政策说法 ↔ 代码里那道门 ↔ **只读不写**。
  //
  // 这一条与上面那条⑩是**两道不同的门**（见 privacy-facts.json 的 healthSync._why）：
  // ⑩管的是"把体重记在本机"，这条管的是"去读系统健康库里别人写下的记录"。
  // 它比⑩还多一层风险：**政策说只读，代码却申请了写**——那种不一致用户看不出来，
  // 审核也未必抓，但它让政策正文变成一句假话。所以两头都查，包括"不该出现的东西不许出现"。
  {
    const hs = facts.healthSync;
    if (!hs) {
      errors.push('privacy-facts.json 少了 healthSync —— '
        + '这一版开始会去读系统健康库，那就必须在事实源里显式声明（读哪些、默认关、单独同意）');
    } else if (hs.enabledInDistributedBuild) {
      if (!policy.includes('系统健康库') && !POLICY_EN.includes('health')) {
        errors.push('这一版接了系统健康库，但中英政策里一个字都没提 —— 收集了没说是最不能接受的一种');
      }
      const enLower = (existsSync(POLICY_EN) ? readFileSync(POLICY_EN, 'utf8') : '').toLowerCase();
      for (const phrase of hs.enabledPhrases?.zh ?? []) {
        if (!policy.includes(phrase)) {
          errors.push(`健康库同步：政策正文里没有「${phrase}」`);
        }
      }
      for (const phrase of hs.enabledPhrases?.en ?? []) {
        if (!enLower.includes(phrase.toLowerCase())) {
          errors.push(`健康库同步：英文政策里没有「${phrase}」`);
        }
      }
      for (const phrase of hs.policyPhrases?.zh ?? []) {
        if (!policy.includes(phrase)) {
          errors.push(`健康库同步（单独同意）：政策正文里没有「${phrase}」`);
        }
      }
      for (const phrase of hs.policyPhrases?.en ?? []) {
        if (!enLower.includes(phrase.toLowerCase())) {
          errors.push(`健康库同步（单独同意）：英文政策里没有「${phrase}」`);
        }
      }
      // 逐项点名"读的是哪三样"（"收集了没说"的另一种形式：读的类型比政策写的多）
      for (const t of hs.reads?.zh ?? []) {
        if (!policy.includes(t)) errors.push(`健康库同步：政策正文里没有点名读「${t}」`);
      }
      for (const t of hs.reads?.en ?? []) {
        if (!enLower.includes(t.toLowerCase())) {
          errors.push(`健康库同步：英文政策里没有点名读「${t}」`);
        }
      }

      // 代码那一半：那道同意、那条撤回、那个桥、以及"读之前先看同意"
      const dbSrc = readFileSync(join(ROOT, 'app/lib/data/db.dart'), 'utf8');
      if (!/IntColumn get healthConsentAtMs\b/.test(dbSrc)) {
        errors.push('政策声明了"读系统健康库要单独同意"，但 db.dart 里找不到那条记录'
          + '（healthConsentAtMs）—— 这条跨文件检查已经失效，别当成通过');
      }
      const screenPath = join(ROOT, 'app/lib/features/body/body_metric_screen.dart');
      const screenSrc = existsSync(screenPath) ? readFileSync(screenPath, 'utf8') : '';
      if (!/Key\('health-consent-agree'\)/.test(screenSrc)) {
        errors.push('「身体数据」页里找不到健康库那道单独同意（health-consent-agree）—— '
          + '政策承诺了要单独征求同意，代码里就必须有它');
      }
      if (!/Key\('health-revoke'\)/.test(screenSrc)) {
        errors.push('政策里承诺了"随时可以撤回同意"，但页面上找不到健康库那条撤回入口'
          + "（Key('health-revoke')）—— 撤回权不能只写在政策里");
      }
      const repoPath = join(ROOT, 'app/lib/data/profile_repository.dart');
      const repoSrc = existsSync(repoPath) ? readFileSync(repoPath, 'utf8') : '';
      if (!/Future<void> clearHealthConsent\(/.test(repoSrc)) {
        errors.push('找不到 clearHealthConsent —— 撤回入口必须真的能把同意清掉');
      } else if (!/UserProfileCompanion\(/.test(repoSrc)) {
        errors.push('clearHealthConsent 没有用 Companion 写 null —— drift 对 DataClass 是 '
          + 'nullToAbsent，那样写出来是"点了撤回，同意还在"');
      }
      const bridgePath = join(ROOT, 'app/lib/health/health_bridge.dart');
      if (!existsSync(bridgePath)) {
        errors.push('政策说会从系统健康库读，但 app/lib/health/health_bridge.dart 不存在');
      } else if (!/MethodChannel\('lianleme\/health'\)/.test(readFileSync(bridgePath, 'utf8'))) {
        errors.push("health_bridge.dart 里的通道名不是 'lianleme/health' —— "
          + '平台那一端的实现会对不上（通道名对不上时是**静默**降级成"没有健康库"，最难查）');
      }
      const servicePath = join(ROOT, 'app/lib/health/health_sync.dart');
      const serviceSrc = existsSync(servicePath) ? readFileSync(servicePath, 'utf8') : '';
      if (!/healthConsentAtMs\(\)/.test(serviceSrc)) {
        errors.push('health_sync.dart 里没有"先把那道同意读出来再决定读不读"这一步 —— '
          + '政策承诺的是"不同意就一个字节都不读"，这句承诺由这里兑现');
      }

      // **只读不写**：政策这么写，代码就不许申请写权限。两头都查 ——
      // iOS 侧 toShare 必须是空数组，Info.plist 里不许出现"写"的用法说明。
      const swiftPath = join(ROOT, 'app/ios/Runner/HealthBridge.swift');
      const swiftSrc = existsSync(swiftPath) ? readFileSync(swiftPath, 'utf8') : '';
      if (!swiftSrc) {
        errors.push('docs 说 iPhone 上能读系统健康库，但 app/ios/Runner/HealthBridge.swift 不存在');
      } else if (!/toShare:\s*\[\]/.test(swiftSrc)) {
        errors.push('HealthBridge.swift 的 requestAuthorization 没有把 toShare 写成空数组 —— '
          + '政策写的是"只读不写"，代码里申请写权限就是另一回事了');
      }
      const plistPath = join(ROOT, 'app/ios/Runner/Info.plist');
      const plistSrc = existsSync(plistPath) ? readFileSync(plistPath, 'utf8') : '';
      // ⚠️ 判据要认**真的 plist 键**，不是"这个字符串出现过" ——
      // Info.plist 里那段注释正是在解释"为什么我们**不**写这一条"，
      // 用纯字符串匹配会把那条解释本身判成违规（第一次跑就踩了）。
      if (/<key>\s*NSHealthUpdateUsageDescription\s*<\/key>/.test(plistSrc)) {
        errors.push('Info.plist 里出现了 NSHealthUpdateUsageDescription（写回健康库的用法说明）—— '
          + '政策承诺的是"只读、不写回"，写了这一条就是在向用户申请一件我们不做的事');
      }
      // **Android 那半边同一句话**：只读。两条都查 ——
      // Kotlin 里不许出现 `WRITE_`（写入权限/写入路径），manifest 里也不许声明写权限。
      // 2026-10-09 加：Android 走的是**平台自带的 Health Connect**（不用 Jetpack 那个库，
      // 它要求 minSdk 26），所以这里核的是 `HealthConnectApi34.kt` 与 `AndroidManifest.xml`。
      const ktPath = join(ROOT, 'app/android/app/src/main/kotlin/com/sdknwdtvpv/lianleme/HealthConnectApi34.kt');
      const ktSrc = existsSync(ktPath) ? readFileSync(ktPath, 'utf8') : '';
      if (!ktSrc) {
        errors.push('这一版两端都接了系统健康库，但 app/android/.../HealthConnectApi34.kt 不存在');
      } else if (/"android\.permission\.health\.WRITE_|permission\.health\.WRITE_/.test(ktSrc)) {
        errors.push('HealthConnectApi34.kt 里出现了 WRITE_ 权限 —— 政策写的是"只读不写回"');
      }
      const androidManifest = join(ROOT, 'app/android/app/src/main/AndroidManifest.xml');
      const manifestSrc = existsSync(androidManifest) ? readFileSync(androidManifest, 'utf8') : '';
      if (/android\.permission\.health\.WRITE_/.test(manifestSrc)) {
        errors.push('AndroidManifest.xml 里声明了 android.permission.health.WRITE_* —— '
          + '政策承诺的是"只读、不写回"');
      }
      for (const perm of ['READ_WEIGHT', 'READ_BODY_FAT', 'READ_HEIGHT']) {
        if (!manifestSrc.includes(`android.permission.health.${perm}`)) {
          errors.push(`AndroidManifest.xml 里没有声明 android.permission.health.${perm} —— `
            + '没声明就拿不到那个读权限（而政策说我们会读）');
        }
      }
      if (!/<key>\s*NSHealthShareUsageDescription\s*<\/key>/.test(plistSrc)) {
        errors.push('Info.plist 里没有 NSHealthShareUsageDescription —— '
          + '没有它，iOS 上请求读健康数据会直接失败（而政策说我们会读）');
      }
    } else if (hs.disabledStatement) {
      // 没接这一版的包：政策必须写明"本版本没有从系统健康库读取"，
      // 否则用户会以为"没看到入口"是自己没找到。
      if (!policy.includes(hs.disabledStatement.zh)) {
        errors.push(`政策里没有写明「${hs.disabledStatement.zh}」`
          + '（这一版的包并没有从系统健康库读取的能力）');
      }
      const enLower = (existsSync(POLICY_EN) ? readFileSync(POLICY_EN, 'utf8') : '').toLowerCase();
      if (!enLower.includes(String(hs.disabledStatement.en).toLowerCase())) {
        errors.push(`英文政策里没有写明「${hs.disabledStatement.en}」`);
      }
    }
  }

  // ⑪ 「导出统计事件」：政策说法 ↔ 代码里真的有那个出口，两头都要在。
  //
  // 为什么单列一条：这个入口把**埋点事件原样交给用户**，是唯一能把 `tap_count`
  // 从设备上取回来的路径（没配上报地址的包里事件根本没出口）。它有两个"看起来正常
  // 但其实是假话"的失败方式：① 政策写了、代码里没有那个入口；② 代码里有入口，
  // 但它拿到的是"要发出去的那批"而不是"全部"（parked 的那些恰恰是最该看的）。
  {
    const ex = facts.localAnalyticsExport;
    if (!ex) {
      errors.push('privacy-facts.json 少了 localAnalyticsExport —— '
        + '「导出统计事件」会把埋点事件原样交给用户（含匿名设备标识），必须显式声明');
    } else {
      const screenPath = join(ROOT, 'app/lib/features/profile/privacy_about_screen.dart');
      const screenSrc = existsSync(screenPath) ? readFileSync(screenPath, 'utf8') : '';
      if (!/Key\('analytics-export'\)/.test(screenSrc)) {
        errors.push('政策承诺了「导出统计事件」，但 app/lib/features/profile/privacy_about_screen.dart '
          + "里找不到那个入口（Key('analytics-export')）—— 这条跨文件检查已经失效，别当成通过");
      }
      // "开关关着时入口不出现"是政策里明写的一句，所以代码里那道门必须在
      if (!/_analyticsEnabled\s*&&\s*widget\.loadEvents\s*!=\s*null/.test(screenSrc)) {
        errors.push('政策写了「开关关着时这个入口不出现」，但代码里找不到那道门'
          + '（`_analyticsEnabled && widget.loadEvents != null`）—— '
          + '关着时还可能露出来的入口，就是"点进去必然是空的"那种按钮');
      }
      const outboxPath = join(ROOT, 'app/lib/analytics/outbox.dart');
      const outboxSrc = existsSync(outboxPath) ? readFileSync(outboxPath, 'utf8') : '';
      if (!/Future<List<AnalyticsEventPayload>> peekAll\(/.test(outboxSrc)) {
        errors.push('找不到 AnalyticsOutboxStore.peekAll() —— 导出的只读出口必须存在'
          + '（而且要包含 parked 的事件：那批正是发不出去的）');
      }
      const enText = existsSync(POLICY_EN) ? readFileSync(POLICY_EN, 'utf8') : '';
      for (const phrase of ex.policyPhrases?.zh ?? []) {
        if (!policy.includes(phrase)) {
          errors.push(`导出统计事件：政策正文里没有「${phrase}」`);
        }
      }
      for (const phrase of ex.policyPhrases?.en ?? []) {
        if (!enText.includes(phrase)) {
          errors.push(`导出统计事件：英文政策里没有「${phrase}」`);
        }
      }
    }
  }

  // ⑩之三 交给用户看的文本里**不许留"给我们自己看的说明"**
  //
  // 为什么单列一条：政策正文里那些"（上架时替换为实际日期）"是我们写给自己的待办，
  // 而生成物（`app/assets/privacy-policy.txt`、商店页 HTML）是**用户会读到**的。
  // 2026-09-30 在真机上翻政策时当场看见那一句 —— 它就是这么漏出去的。
  // 源码（docs/*.md）里的 `<!-- 内部 -->` 块允许写这类话，所以**只扫生成物**。
  {
    // 这张表是按"真机上真的漏出去过的东西"长的，不是拍脑袋：
    //   * `上架时替换` —— 政策里那句「（上架时替换为实际日期）」；
    //   * `由仓库自动生成` / `生成物` / `请勿手改` —— 收集清单开头那三句
    //     （2026-09-30 在真机上翻这一页时当场看见）。
    // 以后每在真机上抓到一次，就把那个词加进来 —— 这样同类问题只会漏一次。
    const MARKERS = ['上架时替换', '待填', '占位', 'to be filled in', 'TODO', 'FIXME',
      '由仓库自动生成', '生成物', '请勿手改', '不要手改'];
    const generated = [
      ['app/assets/privacy-policy.txt', join(ROOT, 'app/assets/privacy-policy.txt')],
      ['app/assets/collection-list.txt', join(ROOT, 'app/assets/collection-list.txt')],
      ['store-assets/privacy/index.html', join(ROOT, 'store-assets/privacy/index.html')],
      ['store-assets/privacy/en.html', join(ROOT, 'store-assets/privacy/en.html')],
    ];
    for (const [label, p] of generated) {
      if (!existsSync(p)) continue;
      const text = readFileSync(p, 'utf8');
      for (const m of MARKERS) {
        if (text.includes(m)) {
          errors.push(`${label} 里出现了「${m}」—— 那是写给我们自己的说明，`
            + '而这份文本是给用户看的（真机上翻政策时就会读到它）');
        }
      }
    }
  }

  // ⑩之四 事实源说的默认值，**对外文档一个字都不许写反**
  //
  // 为什么单列一条：`analyticsOptIn.defaultOn` 是"对外那一半"的锚，与 `db.dart` 那一列的
  // 默认值、政策正文三方对账。2026-09-30 一查（当时事实是"关"），**三份对外文档里都还写着
  // "默认开启"** —— 其中最要命的是 App Store 的**审核备注**（那段话是逐字粘给审核员的），
  // 以及软著说明书。这三处都不是"措辞不美"：它们是对苹果/对版权局/对用户的**事实陈述**。
  //
  // ⚠️ **2026-10-07：这个默认值翻成了"开"**（用户拍板，见 `docs/plan-ux-2026-10-07.md` §三·9），
  // 于是这条判据**也翻了个方向** —— 谁再把对外文本写成"默认关闭"就要判红。
  // 方向只有一个来源（`analyticsOptIn.defaultOn`），所以下次再翻也不会两边打架。
  //
  // 判据本体抽成了纯函数（`checkAnalyticsDefaultDocs`）：**这一条以前没有自检**，
  // 而"只在某一个方向上才跑"的守卫最容易静默失效 —— 现在两个方向都有自检用例。
  {
    // ⚠️ **your-todo 与 README 也在名单里**：它们同样对外（一个是决策入口，
    // 一个是仓库首页），2026-09-30 就在 your-todo 的"审计当时的实现"那段里
    // 读到过与事实相反的说法。
    const docs = [
      'docs/privacy-policy.md',
      'docs/privacy-policy.en.md',
      'docs/store-listing.md',
      'docs/store-listing-ios.md',
      'docs/copyright-manual.md',
      'docs/copyright-application.md',
      'docs/your-todo.md',
      'README.md',
      // ⚠️ 2026-10-07 补进来的两份：它们同样在"陈述现状"（release-checklist 是交付核验表、
      // analytics-sdk 是给未来的自己看的口径），却一直没人核这两处的默认值说法 ——
      // 翻默认值这一趟，正好在它们里面各读到一句过期的"默认关"。
      'docs/release-checklist.md',
      'docs/analytics-sdk.md',
    ];
    const loaded = [];
    for (const rel of docs) {
      const p = join(ROOT, rel);
      if (existsSync(p)) loaded.push({ rel, text: readFileSync(p, 'utf8') });
    }
    errors.push(...checkAnalyticsDefaultDocs({
      defaultOn: facts.analyticsOptIn?.defaultOn === true,
      docs: loaded,
    }));
  }

  // ⑪ 中英两版政策的**结构**必须一一对应（2026-09-30 补）
  //
  // 为什么单列一条：这份政策有中英两份**正文**，它们靠"同源生成"只保证了渲染方式一致，
  // **内容结构**谁都没对过。事实驱动的名字（事件/字段/权限/SDK）已经各查一遍了，
  // 但"某一版多了一整节"这种漂移没人拦。而这恰好是本项目反复踩的那类坑。
  //
  // 编号约定：中文「三之五」= 3.5、「五之二」= 5.2（同一个约定，两份必须一致）。
  {
    const CN = { '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9, '十': 10 };
    const tokens = (text, level) => {
      const out = [];
      const re = new RegExp(`^#{${level}} (.+)$`, 'gm');
      for (const m of text.matchAll(re)) {
        const head = m[1].trim();
        const cn = head.match(/^([一二三四五六七八九十])(?:之([一二三四五六七八九十]))?[、.]/);
        if (cn) {
          out.push(cn[2] ? `${CN[cn[1]]}.${CN[cn[2]]}` : String(CN[cn[1]]));
          continue;
        }
        const num = head.match(/^(\d+(?:\.\d+)?)[.\s]/);
        if (num) {
          out.push(num[1]);
          continue;
        }
        const app = head.match(/^(?:附录|Appendix)\s*([AB])/i);
        if (app) out.push(`APPENDIX_${app[1].toUpperCase()}`);
      }
      return out;
    };
    const zhText = readFileSync(POLICY, 'utf8');
    const enText2 = existsSync(POLICY_EN) ? readFileSync(POLICY_EN, 'utf8') : '';
    if (!enText2) {
      errors.push('英文版政策不存在 —— 它是要发布的那一份，不能只有中文');
    } else {
      for (const level of [2, 3]) {
        const a = tokens(zhText, level);
        const b = tokens(enText2, level);
        if (a.length !== b.length) {
          errors.push(`政策中英两版的 h${level} 小节数不一致（中文 ${a.length} / 英文 ${b.length}）——`
            + ' 加/删小节要两边一起改（编号约定见 tool/privacy-audit.mjs 这一节）');
        }
        const onlyZh = a.filter((x) => !b.includes(x));
        const onlyEn = b.filter((x) => !a.includes(x));
        if (onlyZh.length || onlyEn.length) {
          errors.push(`政策中英两版的小节编号对不上：只有中文有 [${onlyZh.join('、')}]；`
            + `只有英文有 [${onlyEn.join('、')}]`);
        }
      }
    }
  }

  // ⑧ 「怎么开云备份」这件事，教一半比不教更危险
  //
  // 云备份现在是**两个**编译期开关：地址 + 「政策已按启用态改写」的声明。
  // 只写地址的教程会把人引到一个**应用与自己的政策互相矛盾**的包上
  // （界面有入口、政策说"本版本未提供"）。所以：任何地方提到地址开关，就必须同时
  // 提到那个声明开关。CHANGELOG 是历史记录，不改也不查。
  {
    const SCAN_DIRS = ['app', 'docs', 'tool', 'server'];
    const URL_KEY = 'LIANLEME_BACKUP_URL';
    const ACK_KEY = 'LIANLEME_BACKUP_DISCLOSED';
    const skipFile = (rel) => rel === 'CHANGELOG.md' || rel.includes('CHANGELOG');
    const walk = (dir, out = []) => {
      for (const e of readdirSync(dir, { withFileTypes: true })) {
        if (e.name === 'build' || e.name === '.dart_tool' || e.name === 'node_modules'
          || e.name === '.pub-cache' || e.name === 'data') continue;
        const full = join(dir, e.name);
        if (e.isDirectory()) walk(full, out);
        else if (/\.(md|dart|mjs|js|sh|ya?ml|txt|html)$/.test(e.name)) out.push(full);
      }
      return out;
    };
    let scanned = 0;
    let withUrl = 0;
    for (const dir of SCAN_DIRS) {
      const abs = join(ROOT, dir);
      if (!existsSync(abs)) continue;
      for (const file of walk(abs)) {
        const rel = relative(ROOT, file);
        if (skipFile(rel)) continue;
        // 别把自己算进去：这个文件里就写着 URL_KEY 这串字面量，
        // 算进去的话下面的"真空哨兵"永远不会触发（负向验证时抓到过）。
        if (rel === 'tool/privacy-audit.mjs') continue;
        scanned++;
        const text = readFileSync(file, 'utf8');
        if (!text.includes(URL_KEY)) continue;
        withUrl++;
        if (!text.includes(ACK_KEY)) {
          errors.push(`${rel}：写了云备份的地址开关（${URL_KEY}），却没写还要 `
            + `${ACK_KEY} —— 照着它打出来的包会出现"界面有云备份入口、政策却说`
            + `本版本未提供"的自相矛盾。要么补上这个声明开关，要么别在这里给命令`);
        }
      }
    }
    if (withUrl === 0) {
      errors.push(`扫了 ${scanned} 个文件，一个都没提到 ${URL_KEY} —— 这条检查`
        + `大概是失效了（措辞变了？），别让它变成真空哨兵`);
    }
  }

  return { emitted, common, manifest, errors, warnings, apkPermissions };
}

// ---------------------------------------------------------------- 自检

/**
 * 自检：拿**真文件**当基线（现状必须 0 错），再逐个把关键处改坏，看它抓不抓得住。
 *
 * 为什么这条规则要自检：它是"政策 ↔ 库"的横切检查，写错了会**静默通过** ——
 * 而静默通过的政策检查比没有更坏（会让人以为已经核过了）。这五种坏法各对应一次
 * 真实可能发生的漂移：加字段忘改中文政策 / 忘改英文政策 / 忘改库 / 库加了列而
 * fields 没列它 / fields 整个丢了。
 */
function selftest() {
  const facts = JSON.parse(readFileSync(FACTS, 'utf8'));
  const fields = facts.sensitiveLocal?.fields;
  const policy = readFileSync(POLICY, 'utf8');
  const enText = readFileSync(POLICY_EN, 'utf8');
  const dbSrc = readFileSync(join(ROOT, 'app/lib/data/db.dart'), 'utf8');
  const err = (o) => checkSensitiveFields({ fields, policy, enText, dbSrc, ...o });

  const cases = [
    ['现状（真文件）不该有错', err({}), 0],
    ['中文政策漏了「腰围」要报', err({ policy: policy.split('腰围').join('围度') }), 1],
    // ⚠️ 替换必须是**不区分大小写**的：审计本身比对英文政策就是大小写无关的
    // （理由见 `checkSensitiveFields` 里那条注释 —— 同一个词句首会大写）。
    // 2026-10-09 抓到：政策里出现了一处句首的「Waist」之后，这条自检的
    // `split('waist')` 只换掉了小写的那些，剩下大写的那处让审计照样过 ——
    // 于是"自检说抓得住"变成了一句谎话（这正是自检要防的那种事）。
    ['英文政策漏了 waist 要报',
      err({ enText: enText.replace(/waist/gi, 'girth') }), 1],
    ['库里没有 waistCm 要报',
      err({ dbSrc: dbSrc.split('get waistCm').join('get waistCmX') }), 1],
    ['fields 整个丢了要报', err({ fields: undefined }), 1],
    ['库里身高没在 fields 里点名要报',
      err({ fields: { ...fields, zh: fields.zh.filter((f) => f !== '身高') } }), 1],
  ];

  let bad = 0;
  for (const [name, got, want] of cases) {
    const ok = want === 0 ? got.length === 0 : got.length >= 1;
    if (!ok) bad += 1;
    console.log(`${ok ? '✓' : '✗'} ${name}（错 ${got.length} 条，期望 ${want === 0 ? '0' : '≥1'}）`);
    if (!ok) for (const e of got) console.log(`    · ${e}`);
  }

  // ⚠️ ⑩之四（对外文档里的默认值说法）**以前没有自检** —— 2026-10-07 补上。
  // 它以前只在 `defaultOn === false` 那个方向上跑，而"只在某个方向生效的守卫"
  // 一旦方向翻过来就会静默变成一条空规则（那正是它最危险的失败方式）。
  // 所以下面**两个方向都有用例**，外加三条"不该误报"的（历史注记 / 正确说法 / "默认开关"）。
  const d = (defaultOn, text, rel = 'docs/x.md') =>
    checkAnalyticsDefaultDocs({ defaultOn, docs: [{ rel, text }] });
  // ⚠️ 窗口宽度是 40 字：**远处的"当时"不算历史标记**（自检里当场抓到过一次），
  // 所以这里造一件真事：把"当时"用 60 个字的填充推开，它必须**照报**。
  const farAway = '匿名统计默认关闭。' + '填充'.repeat(31) + '当时是另一套规定。';
  const docCases = [
    ['默认开 + 文档写"默认关闭" → 抓得住',
      d(true, '匿名统计开关**默认关闭**，只有你主动打开才会收集'), 1],
    ['默认开 + 文档写"默认开启，随时能关" → 不该误报',
      d(true, '它默认开启，不要的话随时可以关掉'), 0],
    ['默认开 + 历史注记（"由「默认关闭」改来"）→ 不该误报',
      d(true, '（2026-10-07 由「默认关闭」改来，当时是审计判定）'), 0],
    ['默认关 + 文档写"默认开启" → 抓得住（老方向不能丢）',
      d(false, '匿名统计默认开启'), 1],
    ['默认关 + 文档写"默认关闭" → 不该误报',
      d(false, '这个开关默认关闭，要用户自己去打开'), 0],
    ['"默认开关"这个说法不算表态 → 不该误报',
      d(true, '隐私开关默认开关状态见设置页'), 0],
    ['英文版写 on by default 而事实是关 → 抓得住',
      d(false, 'Usage analytics is on by default.', 'docs/x.en.md'), 1],
    ['英文版写 off by default 而事实是开 → 抓得住',
      d(true, 'Usage analytics is off by default.', 'docs/x.en.md'), 1],
    ['"当时"离得太远（>40 字窗口）→ 仍然要报（窗口判据的回归用例）',
      d(true, farAway), 1],
  ];
  let bad2 = 0;
  for (const [name, got, want] of docCases) {
    const ok = want === 0 ? got.length === 0 : got.length >= 1;
    if (!ok) bad2 += 1;
    console.log(`${ok ? '✓' : '✗'} ${name}（错 ${got.length} 条，期望 ${want === 0 ? '0' : '≥1'}）`);
    if (!ok) for (const e of got) console.log(`    · ${e}`);
  }

  if (bad || bad2) {
    console.error(`\n✗ 隐私政策对账自检失败：${bad + bad2}/${cases.length + docCases.length} 条没抓住`);
    process.exit(1);
  }
  console.log(`隐私政策对账自检通过（${cases.length + docCases.length} 条：政策漏字段 / 英文版漏 / `
    + '库没列 / fields 丢了 / 身高未点名 / **统计默认值两个方向 + 三条不该误报** 都抓得住）');
  process.exit(0);
}

// ---------------------------------------------------------------- CLI

if (process.argv[1] && process.argv[1].endsWith('privacy-audit.mjs')) {
  const argv = process.argv.slice(2);
  if (argv.includes('--selftest')) selftest();
  const argOf = (n, d) => {
    const i = argv.indexOf(n);
    return i >= 0 && argv[i + 1] ? argv[i + 1] : d;
  };

  let apkPermissions = null;
  const apk = argOf('--apk', null);
  if (apk) {
    // 用 aapt2 读合并后的权限。
    //
    // ⚠️ 这里原本只找 `~/Library/Android/sdk` —— 2026-09-30 依赖搬去 SSD 之后，
    // 那个路径**已经不存在了**，于是 `--apk` 这档检查**静默变成空转**：
    // 打印一行 "找不到 aapt2，跳过"，然后照常退出 0。
    // 而政策附录 B 恰恰教用户用这条命令去核"打包后的合并权限"——
    // 结果就是 `READ_EXTERNAL_STORAGE`（gal 带的）谁都没发现，是我手工 aapt2 才翻出来的。
    // 所以现在：① 按 ANDROID_SDK_ROOT 找；② **既然你明确要了 --apk，找不到就不是跳过而是报错**。
    const { execFileSync } = await import('node:child_process');
    // aapt2 的查找口径只有一处（tool/lib/android-sdk.mjs）——
    // 以前这里内联了一条写死的 `/Volumes/...` 路径，而 check-dist 走的是另一套，
    // 于是"换了台机器，一个找得到、另一个找不到"（2026-10-01 合成一处）。
    const sdkRoots = sdkRootsList();
    const aapt2 = findAapt2();
    if (!aapt2) {
      console.error('✗ 你要了 --apk，但找不到 aapt2 —— **这不是"跳过"，是这条检查没做**。');
      console.error('  设好 ANDROID_SDK_ROOT（或装上 Android SDK build-tools）再跑。');
      console.error(`  找过：${sdkRoots.join(' · ')}`);
      process.exit(1);
    } else {
      // ⚠️ 用 badging 而不是 `dump permissions`：后者**不报 implied 权限**。
      // 2026-09-30 就是这么漏掉的：`READ_EXTERNAL_STORAGE` 不是谁声明的，
      // 而是"声明了 WRITE_EXTERNAL_STORAGE"之后 Android 在 API ≤29 上隐含授予的，
      // 只有 badging 会打出 `uses-implied-permission ... reason='requested WRITE...'`。
      // 而它**会出现在老系统的权限列表里** —— 政策里不写就是漏披露。
      const out = execFileSync(aapt2, ['dump', 'badging', apk], { encoding: 'utf8' });
      apkPermissions = [...out.matchAll(/^uses-(?:implied-)?permission: name='([^']+)'/gm)]
        .map((m) => m[1]);
    }
  }

  const r = audit({ apkPermissions });

  if (argv.includes('--json')) {
    console.log(JSON.stringify(r, null, 2));
  } else {
    console.log('隐私政策对账（代码 ↔ 隐私事实 ↔ 政策正文）\n');
    console.log(`  客户端会发的事件 ${r.emitted.length} 个`);
    console.log(`  每个事件都带的公共字段 ${r.common.length} 个`);
    console.log(`  manifest 声明的权限 ${r.manifest.length} 条`);
    if (r.apkPermissions) console.log(`  打包后合并权限 ${r.apkPermissions.length} 条`);
    console.log('');
  }

  for (const w of r.warnings) console.error(`⚠️ ${w}`);
  if (r.errors.length) {
    console.error(`✗ 对不上 ${r.errors.length} 处：`);
    for (const e of r.errors) console.error(`  · ${e}`);
    process.exit(1);
  }
  console.log('✓ 对得上：代码发的每一条都在政策里写清楚了，政策也没写代码做不到的事');
}
