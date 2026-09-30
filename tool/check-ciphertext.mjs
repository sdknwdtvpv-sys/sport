#!/usr/bin/env node
/**
 * 练了么 · 「服务端手里只有密文」的机器核验
 *
 * **它补的是哪块空白**：2026-09-30 第一次跑通真机云备份端到端之后，我是在宿主端
 * 手工查服务端那份 sqlite 来确认"里面只有密文"的 —— 一次性动作，没有固化成命令，
 * 下一个人（或下一轮的我）没法原样重跑。这条把它变成可重复的核验。
 *
 * 判据（全都不看感觉）：
 *   1. `backups` 里至少有一行（一行都没有 → 你还没跑端到端，别把"空"当成"安全"）；
 *   2. 每个 blob 都能解析成信封 `{v, alg, kdf, nonce, ct, mac}`，且 `alg` 是 AES-256-GCM；
 *   3. `ct` 解 base64 之后**不像 JSON**、可打印字符占比低（随机密文的样子）；
 *   4. 整个 blob（含信封）里**搜不到任何明文记号**（训练明细的字段名与动作名）。
 *
 * 用法：
 *   node tool/check-ciphertext.mjs <服务端的 sqlite 路径>      # 核一份真实的库
 *   node tool/check-ciphertext.mjs <路径> --absent 深蹲,102.5   # 追加你要找的明文记号
 *   node tool/check-ciphertext.mjs --selftest                 # 自检（verify.sh 第 2 层跑这个）
 *
 * 退出码：发现明文 / 结构不对 / 库是空的 → 1。
 *
 * ⚠️ `--selftest` 不是装饰：它**故意造一份含明文的库**，然后要求本脚本报错。
 * 少了这一步，这条检查可能只是"永远打印 ✓"的假守卫。
 */

import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

/** 训练明细里一定会出现的字段名/中文动作名 —— 密文里出现任何一个都说明漏了明文 */
const MARKERS = [
  'weight_kg', 'reps', 'set_logged', 'exercise', 'workout',
  '深蹲', '卧推', '硬拉', '杠铃', '哑铃',
];

function parseArgs(argv) {
  const args = { db: null, absent: [], selftest: argv.includes('--selftest') };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--absent' && argv[i + 1]) args.absent.push(...argv[i + 1].split(','));
    else if (!argv[i].startsWith('--') && !args.db) args.db = argv[i];
  }
  return args;
}

/** 核一份库；返回 { problems: string[], facts: string[] } —— 不打印、不退出，便于自检复用 */
function inspect(dbPath, extraMarkers = []) {
  const problems = [];
  const facts = [];
  if (!existsSync(dbPath)) {
    problems.push(`找不到库：${dbPath}`);
    return { problems, facts };
  }
  const db = new DatabaseSync(dbPath, { readOnly: true });
  let rows;
  try {
    rows = db.prepare('select account_id, bytes, updated_at, blob from backups').all();
  } catch (e) {
    problems.push(`读 backups 表失败：${e.message}（表结构变了？这条检查要跟着改）`);
    return { problems, facts };
  }
  if (!rows.length) {
    problems.push('服务端的 backups 表是**空的** —— 先跑一次云备份端到端，'
      + '别把"没有数据"当成"没有明文"');
    return { problems, facts };
  }
  const markers = [...MARKERS, ...extraMarkers].filter(Boolean);
  for (const row of rows) {
    const raw = Buffer.from(row.blob);
    const text = raw.toString('utf8');
    const id = String(row.account_id).slice(0, 12);

    // ① 明文记号（整包，含信封）
    const hit = markers.filter((m) => text.includes(m));
    if (hit.length) {
      problems.push(`account ${id}… 的密文里出现了明文记号：${hit.join('、')} —— `
        + '服务端不该看到这些');
    }

    // ② 信封结构
    let env = null;
    try {
      env = JSON.parse(text);
    } catch {
      problems.push(`account ${id}… 的 blob 不是合法 JSON 信封（结构变了？）`);
      continue;
    }
    if (!env.alg || !/AES-256-GCM/.test(String(env.alg))) {
      problems.push(`account ${id}… 的 alg 不是 AES-256-GCM（拿到的是 ${env.alg}）—— `
        + '加密算法换了就要重新确认"服务端看不到明文"这件事');
    }
    const ct = env.ct ?? env.ciphertext ?? env.data;
    if (typeof ct !== 'string') {
      problems.push(`account ${id}… 的信封里找不到密文字段（ct）—— 检查要跟着改`);
      continue;
    }

    // ③ 密文本身：不像 JSON、可打印率低
    const bytes = Buffer.from(ct, 'base64');
    const ctText = bytes.toString('utf8');
    if (/^\s*[{[]/.test(ctText)) {
      problems.push(`account ${id}… 的 ct 解出来像 JSON —— 那可能是明文被塞进了 ct`);
    }
    const printable = [...bytes].filter((c) => c >= 32 && c < 127).length / Math.max(bytes.length, 1);
    if (printable > 0.6) {
      problems.push(`account ${id}… 的 ct 可打印字符占比 ${(printable * 100).toFixed(1)}% —— `
        + '不像随机密文（明文/压缩过的明文可能长这样）');
    }
    const ctHit = markers.filter((m) => ctText.includes(m));
    if (ctHit.length) {
      problems.push(`account ${id}… 的 ct 里有明文记号：${ctHit.join('、')}`);
    }

    facts.push(`account ${id}… · ${bytes.length} 字节密文 · alg=${env.alg} · `
      + `可打印率 ${(printable * 100).toFixed(1)}%`);
  }
  return { problems, facts };
}

// ---------------------------------------------------------------- 自检
//
// 故意的：造两份库 —— 一份是"正确的密文"，一份是"漏了明文的密文"。
// 前者必须过、后者必须红。这样 verify.sh 每次跑都在证明"这条检查真的看得见明文"。
function selftest() {
  const dir = mkdtempSync(join(tmpdir(), 'lianleme-cipher-'));
  const mk = (name, makeBlob) => {
    const p = join(dir, name);
    const db = new DatabaseSync(p);
    db.exec('create table backups(account_id text, blob blob, bytes int, updated_at bigint)');
    const blob = makeBlob();
    db.prepare('insert into backups values (?,?,?,?)')
      .run('a'.repeat(64), blob, blob.length, 1700000000000);
    db.close();
    return p;
  };

  // 真密文：随机字节 → base64，装进与真身同构的信封
  const randomCt = Buffer.from(
    Array.from({ length: 512 }, (_, i) => (i * 37 + 11) % 256));
  const good = mk('good.sqlite', () => Buffer.from(JSON.stringify({
    v: 1, alg: 'AES-256-GCM', kdf: 'HKDF-SHA256',
    nonce: randomCt.subarray(0, 12).toString('base64'),
    ct: randomCt.toString('base64'),
    mac: randomCt.subarray(0, 16).toString('base64'),
  }), 'utf8'));

  // 假密文：ct 其实是明文的 base64（里面带动作名与字段名）
  const plain = Buffer.from(JSON.stringify({
    sets: [{ exercise: '杠铃卧推', weight_kg: 102.5, reps: 8, note: '深蹲日' }],
  }), 'utf8');
  const bad = mk('bad.sqlite', () => Buffer.from(JSON.stringify({
    v: 1, alg: 'AES-256-GCM', kdf: 'HKDF-SHA256',
    nonce: randomCt.subarray(0, 12).toString('base64'),
    ct: plain.toString('base64'),
    mac: randomCt.subarray(0, 16).toString('base64'),
  }), 'utf8'));

  // 空库：一行都没有 —— 也必须红（"没有数据"不等于"没有明文"）
  const empty = join(dir, 'empty.sqlite');
  {
    const db = new DatabaseSync(empty);
    db.exec('create table backups(account_id text, blob blob, bytes int, updated_at bigint)');
    db.close();
  }

  const results = [
    ['真密文 → 必须过', inspect(good), false],
    ['假密文（ct 是明文）→ 必须红', inspect(bad), true],
    ['空库 → 必须红', inspect(empty), true],
  ];
  console.log('密文核验自检：');
  let bad2 = 0;
  for (const [label, r, shouldFail] of results) {
    const failed = r.problems.length > 0;
    const ok = failed === shouldFail;
    if (!ok) bad2++;
    console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${label}`
      + (r.problems.length ? `　→ ${r.problems[0]}` : ''));
  }
  rmSync(dir, { recursive: true, force: true });
  if (bad2) {
    console.error(`\n✗ 自检失败 ${bad2} 项 —— 这条检查本身不可信，先修它`);
    process.exit(1);
  }
  console.log('\n✓ 自检通过：密文过得去、明文藏不住、空库也不放过');
}

// ---------------------------------------------------------------- 跑
const args = parseArgs(process.argv.slice(2));
if (args.selftest) {
  selftest();
} else if (!args.db) {
  console.error('用法：node tool/check-ciphertext.mjs <服务端的 sqlite 路径>');
  console.error('      node tool/check-ciphertext.mjs --selftest');
  process.exit(1);
} else {
  const { problems, facts } = inspect(args.db, args.absent);
  console.log(`服务端密文核验　${args.db}\n`);
  for (const f of facts) console.log(`  ${f}`);
  if (problems.length) {
    for (const p of problems) console.error(`  \x1b[31m✗\x1b[0m ${p}`);
    console.error(`\n✗ 有 ${problems.length} 处不对 —— 服务端可能看到了明文`);
    process.exit(1);
  }
  console.log('\n✓ 服务端手里只有密文（信封是协议元数据，内容不可读；也没搜到任何明文记号）');
}
