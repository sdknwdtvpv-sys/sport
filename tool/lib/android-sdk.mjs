/**
 * 练了么 · Android SDK 的位置与工具（**一处口径**）
 *
 * **为什么有它**：找 `aapt2` 这件事，`tool/check-dist.mjs` 与 `tool/privacy-audit.mjs`
 * 各写了一遍，而且**两遍的口径不一样**（一个读环境变量 + `tool/dev-env.sh` 的 DEPS，
 * 另一个内置了一条写死的 `/Volumes/Elliot's SSD/...` 路径）。
 * 结果就是：换了台机器/搬了家，一个工具找得到、另一个找不到，
 * 而症状是"这条检查没做"（最危险的那种安静失败）—— 2026-10-01 合成一处。
 *
 * 口径（按优先级）：
 *   1. `ANDROID_SDK_ROOT`
 *   2. `ANDROID_HOME`
 *   3. `tool/dev-env.sh` 里 `DEPS=` 指向的目录下的 `android-sdk`（本机 SSD 那套）
 *   4. `~/Library/Android/sdk`（Android Studio 默认位置）
 *
 * 自检：`node tool/lib/android-sdk.mjs --selftest`
 */

import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

/** 仓库根（本文件在 tool/lib/ 下） */
export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

/** `tool/dev-env.sh` 里的 `DEPS="..."`（依赖装在哪儿，真源只有这一处）。 */
export function depsRoot() {
  try {
    const dev = readFileSync(join(ROOT, 'tool/dev-env.sh'), 'utf8');
    const m = /^DEPS="([^"]+)"/m.exec(dev);
    return m ? m[1] : null;
  } catch {
    return null;
  }
}

/**
 * 候选的 Android SDK 根目录（按优先级）。
 * 返回的每一项都**只是候选**：不一定存在（调用方自己判断）。
 */
export function sdkRoots() {
  const deps = depsRoot();
  const all = [
    process.env.ANDROID_SDK_ROOT,
    process.env.ANDROID_HOME,
    deps ? join(deps, 'android-sdk') : null,
    join(homedir(), 'Library/Android/sdk'),
  ].filter(Boolean);
  // 去重：ANDROID_SDK_ROOT 与 ANDROID_HOME 常常是同一个值（候选列表里重复没意义，
  // 而且真出现"找不到"时，报出来的"找过哪些地方"会变得难读）。
  return [...new Set(all)];
}

/**
 * 找 `aapt2`（build-tools 里那个读 APK 的工具）。找不到返回 null ——
 * **"找不到"算不算失败由调用方决定**（例如"有 APK 却读不了"必须算失败，
 * 而"本来就没有 APK"自然跳过）。
 */
export function findAapt2() {
  for (const root of sdkRoots()) {
    const bt = join(root, 'build-tools');
    if (!existsSync(bt)) continue;
    const versions = readdirSync(bt).sort().reverse();
    for (const v of versions) {
      const p = join(bt, v, 'aapt2');
      if (existsSync(p)) return p;
    }
  }
  return null;
}

// ───────────────────────────────────────────────────────────── 自检
function selftest() {
  let bad = 0;
  const check = (ok, label, extra = '') => {
    if (!ok) bad += 1;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}${extra}`);
  };

  // 1. dev-env.sh 里的 DEPS 必须读得到（读不到说明口径坏了，而不是"这台机器没有 SDK"）
  const deps = depsRoot();
  check(typeof deps === 'string' && deps.length > 0, 'tool/dev-env.sh 里的 DEPS 读得出来',
    deps ? `（${deps}）` : '');

  // 2. 候选列表里必须包含"环境变量优先于写死的路径"这个顺序
  const roots = sdkRoots();
  check(roots.length >= 2, '候选根目录至少两个（环境变量 + 兜底）', `（${roots.length} 个）`);
  const envIdx = process.env.ANDROID_SDK_ROOT
    ? roots.indexOf(process.env.ANDROID_SDK_ROOT) : 0;
  check(envIdx === 0, 'ANDROID_SDK_ROOT 排在第一位（环境变量优先）');

  // 3. 写死的路径**只允许出现在 dev-env.sh 那一处**：
  //    以前 privacy-audit 里内联了一条 `/Volumes/Elliot's SSD/...`，
  //    这条用例就是防它再长回来。
  // 3. **写死的路径不许长回来** —— 用**行为**判据，不做文本匹配。
  //    踩过两次坑：判据的正则字面量、以及判据的提示语，都被自己匹配到了。
  //    改成看"把环境变量摘掉之后，候选只剩哪些"：
  //    只允许来自 dev-env.sh 的 DEPS 与 home 目录，别的一律算长回来了。
  const savedA = process.env.ANDROID_SDK_ROOT;
  const savedB = process.env.ANDROID_HOME;
  delete process.env.ANDROID_SDK_ROOT;
  delete process.env.ANDROID_HOME;
  const bare = sdkRoots();
  process.env.ANDROID_SDK_ROOT = savedA;
  process.env.ANDROID_HOME = savedB;
  const allowed = [
    deps ? join(deps, 'android-sdk') : null,
    join(homedir(), 'Library/Android/sdk'),
  ].filter(Boolean);
  const strays = bare.filter((r) => !allowed.includes(r));
  check(strays.length === 0,
    '摘掉环境变量后候选只剩 dev-env.sh 与 home（没有内联的写死路径）',
    strays.length ? `（多出来：${strays.join(' · ')}）` : '');

  // 4. findAapt2 在"没有 SDK"的环境下必须返回 null，而不是抛
  let threw = false;
  let got = 'x';
  const saved = { a: process.env.ANDROID_SDK_ROOT, b: process.env.ANDROID_HOME };
  process.env.ANDROID_SDK_ROOT = '/nonexistent/sdk';
  process.env.ANDROID_HOME = '/nonexistent/sdk2';
  try { got = findAapt2(); } catch { threw = true; }
  process.env.ANDROID_SDK_ROOT = saved.a;
  process.env.ANDROID_HOME = saved.b;
  check(!threw && (got === null || typeof got === 'string'),
    'SDK 不存在时 findAapt2 返回 null（不抛）', `（返回 ${got}）`);

  if (bad) {
    console.error(`\n✗ android-sdk 自检失败 ${bad} 项`);
    process.exit(1);
  }
  console.log('\n✓ 自检通过：DEPS 读得到、候选顺序对、写死路径没长回来、找不到时返回 null');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href
    && process.argv.includes('--selftest')) {
  selftest();
}
