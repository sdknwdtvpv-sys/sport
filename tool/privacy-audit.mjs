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
  // 为什么单列一条：`analyticsOptIn.defaultOn` 是 `false`（v1.28.0 起，审计 A 的后半段），
  // 而 2026-09-30 一查，**三份对外文档里都还写着"默认开启"** —— 其中最要命的是
  // App Store 的**审核备注**（那段话是逐字粘给审核员的），以及软著说明书。
  // 这三处都不是"措辞不美"：它们是对苹果/对版权局/对用户的**事实陈述**，说反了就是假话。
  //
  // 判据写得能区分"历史注记"与"写反了"：一行同时提到统计开关、又出现"默认开"，
  // **且这一行里没有"默认关"** → 判红。于是"（2026-09-30 由「默认开」改来）"这种注记不会误报，
  // "如果哪天把云备份默认打开"这种假设句也不会（它不提统计开关）。
  {
    const defaultOn = facts.analyticsOptIn?.defaultOn === false;
    if (defaultOn) {
      // ⚠️ **your-todo 与 README 也在名单里**：它们同样对外（一个是你的决策入口，
      // 一个是仓库首页），2026-09-30 就在 your-todo 的"审计当时的实现"那段里
      // 读到"匿名使用统计默认是开的（默认 true）"—— 而那段早已被 v1.28.0 改掉。
      const docs = [
        'docs/privacy-policy.md',
        'docs/privacy-policy.en.md',
        'docs/store-listing.md',
        'docs/store-listing-ios.md',
        'docs/copyright-manual.md',
        'docs/copyright-application.md',
        'docs/your-todo.md',
        'README.md',
      ];
      const switchZh = /(统计|帮助改进产品)/;
      const wrongZh = /默认\s*(?:是|为)?\s*(?:开启|打开|开着|开)/;
      const rightZh = /默认\s*(?:关闭|关|false)/;
      const switchEn = /(analytics|statistics|help improve)/i;
      const wrongEn = /(on by default|enabled by default|default on\b)/i;
      const rightEn = /(off by default|default off|disabled by default)/i;
      for (const rel of docs) {
        const p = join(ROOT, rel);
        if (!existsSync(p)) continue;
        const lines = readFileSync(p, 'utf8').split('\n');
        lines.forEach((line, i) => {
          const isEn = rel.endsWith('.en.md');
          const mentionsSwitch = isEn ? switchEn.test(line) : switchZh.test(line);
          if (!mentionsSwitch) return;
          const wrong = isEn ? wrongEn.test(line) : wrongZh.test(line);
          const right = isEn ? rightEn.test(line) : rightZh.test(line);
          // "默认开" 这三个字也出现在"默认开关"这种词里 —— 那一行只要同时有"默认关"就放过
          if (wrong && !right) {
            errors.push(`${rel}:${i + 1} 把统计开关说成"默认开"了，而事实源里 `
              + '`analyticsOptIn.defaultOn` 是 false —— 这行是对外的事实陈述，说反了就是假话');
          }
        });
      }
    }
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

// ---------------------------------------------------------------- CLI

if (process.argv[1] && process.argv[1].endsWith('privacy-audit.mjs')) {
  const argv = process.argv.slice(2);
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
    const sdkRoots = [
      process.env.ANDROID_SDK_ROOT,
      process.env.ANDROID_HOME,
      "/Volumes/Elliot's SSD/harness-deps/android-sdk",
      join(process.env.HOME ?? '', 'Library/Android/sdk'),
    ].filter(Boolean);
    let aapt2 = null;
    for (const root of sdkRoots) {
      const bt = join(root, 'build-tools');
      if (!existsSync(bt)) continue;
      const versions = readdirSync(bt).sort();
      for (const v of versions.reverse()) {
        const cand = join(bt, v, 'aapt2');
        if (existsSync(cand)) { aapt2 = cand; break; }
      }
      if (aapt2) break;
    }
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
