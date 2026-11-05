#!/usr/bin/env node
/**
 * 练了么 · 自建兑换码（M3）：**码的生成/校验 + 运营 CLI**
 *
 * 设计：`docs/plan-membership-2026-10-10.md` §6.2 / §6.4 / §6.5。三条硬规矩：
 *
 *   1. **码形状**：`LMU-XXXXX-XXXXX-XXXXX-XXXXX`，`Crockford Base32`（去掉 I/L/O/U 易混字符），
 *      20 个字符里 **19 个数据字符（95 bit）+ 1 位校验位**，≥ 80 bit 熵；
 *   2. **库里只存 SHA-256**：明文只在 `generate` 那一刻出现在 CSV/终端里；
 *      `billing.mjs` 核销时也只拿哈希去查（服务端日志里不会有明文码）；
 *   3. **运营工具不暴露 HTTP**：只在本机用 `--db` 指库跑（生产在服务器上跑同一条命令）。
 *
 * 用法（与方案 §6.5 一致）：
 *   node server/redeem-admin.mjs generate --kind year --count 100 --expire 2028-10-10 \
 *        --batch 2026-launch --out codes.csv
 *   node server/redeem-admin.mjs revoke --batch 2026-launch
 *   node server/redeem-admin.mjs revoke --code LMU-...
 *   node server/redeem-admin.mjs lookup --account <account_id>
 *   node server/redeem-admin.mjs batches
 *
 * ⚠️ `--db` 默认 `server/data/billing.sqlite`（与 `backend.mjs` 的 `--billing-db` 默认值一致）；
 * 生产上要指到 `/var/lib/lianleme/billing.sqlite`。
 */

import { createHash, randomBytes } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { createBillingStore, REDEEM_KINDS } from './billing-store.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** Crockford Base32：`0-9` + 去掉 I/L/O/U 的字母（易混字符不出现）。 */
export const CODE_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

export const CODE_PREFIX = 'LMU';
/** 20 个刻度：19 个随机数据字符 + 1 位校验位（95 bit 熵 ≥ 80 bit）。 */
export const CODE_BODY_LEN = 20;
const DATA_LEN = CODE_BODY_LEN - 1;

/** 规范化后的码（含 `LMU` 前缀、去掉分隔符）形状。 */
export const CODE_RE = /^LMU[0-9A-HJKMNP-TV-Z]{20}$/;

/**
 * 把用户输入规范化成**唯一形式**：
 *   * 大写；
 *   * 去掉空格/短横线（允许用户抄成 `lmu xxxxx ...`）；
 *   * Crockford 的易混映射：`O→0`、`I/L→1`、`U→V`（**前缀 `LMU` 本身不动**）；
 *   * 校验前缀、长度、字母表；不合格返回 `null`（不抛，调用方给 400）。
 */
export function normalizeRedeemCode(input) {
  const raw = String(input ?? '').trim().toUpperCase().replace(/[^0-9A-Z]/g, '');
  if (!raw.startsWith(CODE_PREFIX)) return null;
  const body = raw.slice(CODE_PREFIX.length)
    .replace(/O/g, '0')
    .replace(/[IL]/g, '1')
    .replace(/U/g, 'V');
  const normalized = CODE_PREFIX + body;
  if (!CODE_RE.test(normalized)) return null;
  return normalized;
}

/** 校验位：对前 19 位做加权和（权重 = 位置+1）再 mod 32，取字母表里那一位。 */
export function checkChar(dataChars) {
  let sum = 0;
  for (let i = 0; i < dataChars.length; i += 1) {
    const v = CODE_ALPHABET.indexOf(dataChars[i]);
    if (v < 0) throw new Error(`非法字符：${dataChars[i]}`);
    sum += (i + 1) * v;
  }
  return CODE_ALPHABET[sum % CODE_ALPHABET.length];
}

/**
 * 生成一个码（明文）。默认用 `node:crypto` 的安全随机数；
 * 自检可注入确定性 random 源（只为验证形状/校验位，不用于生产）。
 */
export function generateRedeemCode(random = randomBytes) {
  const bytes = random(32);
  let data = '';
  for (let i = 0; i < DATA_LEN; i += 1) {
    // 256 / 32 = 8 —— 取模无偏，满足均匀分布。
    data += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length];
  }
  const canonical = CODE_PREFIX + data + checkChar(data);
  return formatRedeemCode(canonical);
}

/** 规范化文本 → 展示形状（`LMU-XXXXX-XXXXX-XXXXX-XXXXX`）。 */
export function formatRedeemCode(normalized) {
  const n = normalizeRedeemCode(normalized) ?? normalized;
  const body = n.slice(CODE_PREFIX.length);
  const groups = [];
  for (let i = 0; i < body.length; i += 5) groups.push(body.slice(i, i + 5));
  return `${CODE_PREFIX}-${groups.join('-')}`;
}

/** 校验一个规范化码：形状 + 校验位。 */
export function isValidRedeemCode(normalized) {
  if (!normalized || !CODE_RE.test(normalized)) return false;
  const body = normalized.slice(CODE_PREFIX.length);
  return checkChar(body.slice(0, DATA_LEN)) === body[DATA_LEN];
}

/** 规范化码 → 入库用的 SHA-256（服务端只存这个）。 */
export function hashRedeemCode(normalized) {
  return createHash('sha256').update(normalized, 'utf8').digest('hex');
}

// ───────────────────────────────────────────────────────── CLI（不暴露 HTTP）
const isMain = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];

function argOf(argv, name, fallback = null) {
  const i = argv.indexOf(name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : fallback;
}

function usage() {
  console.log(`练了么 · 兑换码运营工具（不暴露 HTTP，只在本机/服务器上跑）

用法：
  node server/redeem-admin.mjs generate --kind year --count 100 --expire 2028-10-10 --batch <批次名> [--out codes.csv]
  node server/redeem-admin.mjs revoke --batch <批次名>
  node server/redeem-admin.mjs revoke --code LMU-XXXXX-XXXXX-XXXXX-XXXXX
  node server/redeem-admin.mjs lookup --account <account_id>
  node server/redeem-admin.mjs batches

选项：
  --kind     month | quarter | year | lifetime（默认 year）
  --days     自定义天数（覆盖 --kind；lifetime 不接受）
  --expire   码本身的失效日（YYYY-MM-DD；默认不过期）
  --batch    批次名（必填；用于整批作废/统计）
  --out      生成的 CSV 写到哪（默认 stdout；'-' 也是 stdout）
  --db       库路径（默认 server/data/billing.sqlite；生产指 /var/lib/lianleme/billing.sqlite）
`);
}

async function main(argv) {
  const cmd = argv[0];
  const dbPath = argOf(argv, '--db', join(ROOT, 'server/data/billing.sqlite'));
  const store = createBillingStore({ path: dbPath });
  try {
    if (cmd === 'generate') {
      const kind = argOf(argv, '--kind', 'year');
      if (!(kind in REDEEM_KINDS)) throw new Error(`--kind 只能是 ${Object.keys(REDEEM_KINDS).join(' / ')}`);
      const count = Number(argOf(argv, '--count', '100'));
      if (!Number.isInteger(count) || count <= 0 || count > 25000) {
        throw new Error('--count 必须是 1..25000 的整数');
      }
      const batch = argOf(argv, '--batch', null);
      if (!batch) throw new Error('generate 必须给 --batch（整批作废/统计都靠它）');
      const daysArg = argOf(argv, '--days', null);
      const days = daysArg === null ? REDEEM_KINDS[kind] : Number(daysArg);
      if (kind === 'lifetime' && daysArg !== null) throw new Error('lifetime 码不接受 --days');
      if (days !== null && (!Number.isInteger(days) || days <= 0)) throw new Error('--days 必须是正整数');
      const expireRaw = argOf(argv, '--expire', null);
      let expireAt = null;
      if (expireRaw) {
        const d = new Date(`${expireRaw}T00:00:00Z`);
        if (Number.isNaN(d.getTime())) throw new Error(`--expire 格式不对：${expireRaw}（要 YYYY-MM-DD）`);
        expireAt = d.getTime();
      }
      const out = argOf(argv, '--out', '-');
      const codes = [];
      const rows = [];
      for (let i = 0; i < count; i += 1) {
        const plain = generateRedeemCode();
        const normalized = normalizeRedeemCode(plain);
        if (!normalized || !isValidRedeemCode(normalized)) throw new Error('生成器产出了非法码（不该发生）');
        codes.push(plain);
        rows.push({ codeHash: hashRedeemCode(normalized), kind, days, batch, expireAt });
      }
      const inserted = store.insertCodes(rows);
      const csv = ['code,batch,kind,days,expire_at']
        .concat(codes.map((c) => `${c},${batch},${kind},${days ?? ''},${expireRaw ?? ''}`))
        .join('\n') + '\n';
      if (out === '-' || out === null) process.stdout.write(csv);
      else {
        const { writeFileSync } = await import('node:fs');
        writeFileSync(out, csv, 'utf8');
        console.log(`✓ 生成 ${count} 个码（入库 ${inserted} 个），CSV 写到 ${out}`);
      }
      console.log(`  批次：${batch} · 档位：${kind}（${days ?? '终身'}）· 码失效：${expireRaw ?? '不过期'}`);
      console.log('  ⚠️ 明文只在这个文件里；库里只有 SHA-256。发完请妥善保管/删除 CSV。');
      return 0;
    }
    if (cmd === 'revoke') {
      const batch = argOf(argv, '--batch', null);
      const codeArg = argOf(argv, '--code', null);
      if (!batch && !codeArg) throw new Error('revoke 需要 --batch 或 --code');
      if (codeArg) {
        const n = normalizeRedeemCode(codeArg);
        if (!n || !isValidRedeemCode(n)) throw new Error('--code 形状/校验位不对（输入时打错了吗？）');
        const removed = store.revokeUnused({ codeHash: hashRedeemCode(n) });
        console.log(`✓ 作废未核销的码：${removed} 行`);
        return 0;
      }
      const removed = store.revokeUnused({ batch });
      console.log(`✓ 批次 ${batch}：作废未核销的码 ${removed} 行（已核销的不动）`);
      return 0;
    }
    if (cmd === 'lookup') {
      const account = argOf(argv, '--account', null);
      if (!account) throw new Error('lookup 需要 --account');
      const current = store.currentFor(account);
      const rows = store.listByAccount(account);
      console.log(`账号 ${account}：当前状态 ${current.status}`);
      if (current.row) console.log(`  最该生效：${JSON.stringify(current.row)}`);
      console.log(`  权益行：${rows.length}`);
      for (const r of rows) console.log(`  - ${JSON.stringify(r)}`);
      return 0;
    }
    if (cmd === 'batches') {
      const rows = store.listBatches();
      if (!rows.length) { console.log('（还没有任何批次）'); return 0; }
      for (const r of rows) console.log(`${r.batch}\t总 ${r.total}\t已核销 ${r.used}\t未核销 ${r.total - r.used}`);
      return 0;
    }
    usage();
    return cmd ? 1 : 0;
  } finally {
    store.close();
  }
}

if (isMain) {
  // main 里用了 await import('node:fs')：包一层 async IIFE（其余分支同步返回码）。
  (async () => {
    try {
      process.exit(await main(process.argv.slice(2)));
    } catch (e) {
      console.error(`✗ ${e?.message ?? e}`);
      process.exit(1);
    }
  })();
}
