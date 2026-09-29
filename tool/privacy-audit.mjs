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
const MANIFEST = join(ROOT, 'app/android/app/src/main/AndroidManifest.xml');

/** 扫源码里所有 `track('事件名'` —— 这是"客户端到底会发什么"的唯一真源 */
export function scanEmittedEvents(dir) {
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

  // ⑤ 打包后的合并权限（发布前用 --apk 跑）
  if (apkPermissions) {
    const allowed = new Set([
      ...facts.permissions.map((p) => p.name),
      ...(facts.injectedPermissions ?? []),
    ]);
    for (const p of apkPermissions) {
      if (!allowed.has(p)) {
        errors.push(`打包后的 APK 里出现了未披露的权限「${p}」—— `
          + `很可能是某个插件加进来的，必须在政策与隐私事实里说明`);
      }
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
    // 用 aapt2 读合并后的权限（构建工具在 Android SDK 里；找不到就明确跳过）
    const { execFileSync } = await import('node:child_process');
    const sdk = join(process.env.HOME ?? '', 'Library/Android/sdk/build-tools');
    let aapt2 = null;
    if (existsSync(sdk)) {
      const versions = readdirSync(sdk).sort();
      for (const v of versions.reverse()) {
        const cand = join(sdk, v, 'aapt2');
        if (existsSync(cand)) { aapt2 = cand; break; }
      }
    }
    if (!aapt2) {
      console.error('⊘ 找不到 aapt2，跳过打包权限核对（静态对账仍然有效）');
    } else {
      const out = execFileSync(aapt2, ['dump', 'permissions', apk], { encoding: 'utf8' });
      apkPermissions = [...out.matchAll(/uses-permission: name='([^']+)'/g)].map((m) => m[1]);
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
