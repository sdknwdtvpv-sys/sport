#!/usr/bin/env node
/**
 * 练了么 · 规则引擎测试跑分器
 *
 *   用法：node engine/run-tests.mjs
 *
 * 把 engine/vectors.json 里的规范向量喂给 engine/progression.mjs，
 * 逐条断言，并额外检查三条跨用例的硬红线（invariants）。
 * 任何失败都以非 0 退出码结束。
 *
 * Flutter/Dart 端移植后，应当让 Dart 实现产出同样的结果再跑一次本脚本的断言逻辑
 * （或把本脚本改为通过 stdin 读取 Dart 输出），端口才算完成。
 */
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { suggestNext, estimate1RM, REASON_CODES } from './progression.mjs';

const ROOT = dirname(fileURLToPath(import.meta.url));
const spec = JSON.parse(readFileSync(join(ROOT, 'vectors.json'), 'utf8'));

const F = spec.fixtures;
const failures = [];
const passes = [];
/** 收集所有实际输出，用于跑跨用例红线 */
const observed = [];

const eq = (a, b) => (Number.isNaN(a) && Number.isNaN(b)) || a === b;

for (const v of spec.vectors) {
  const input = {
    exercise: typeof v.input.exercise === 'string' ? F[v.input.exercise] : v.input.exercise,
    plan: typeof v.input.plan === 'string' ? F[v.input.plan] : v.input.plan,
    lastSession: v.input.lastSession ?? null,
    profile: v.input.profile ?? {},
    overrides: v.input.overrides ?? [],
  };

  let actual;
  let thrown = null;
  try {
    actual = suggestNext(input);
  } catch (e) {
    thrown = e;
  }

  const problems = [];
  if (thrown) {
    problems.push(`抛出异常：${thrown.message}`);
  } else if (v.expect === null) {
    if (actual !== null) problems.push(`期望 null，实际 ${JSON.stringify(actual)}`);
  } else if (actual === null || actual === undefined) {
    problems.push(`期望一条建议，实际 ${actual}`);
  } else {
    const e = v.expect;
    if (!eq(actual.weight_kg, e.weight_kg)) problems.push(`weight_kg 期望 ${e.weight_kg}，实际 ${actual.weight_kg}`);
    if (!eq(actual.reps, e.reps)) problems.push(`reps 期望 ${e.reps}，实际 ${actual.reps}`);
    if (actual.reason_code !== e.reason_code) problems.push(`reason_code 期望 ${e.reason_code}，实际 ${actual.reason_code}`);
    if (e.text_includes && !String(actual.reason_text ?? '').includes(e.text_includes)) {
      problems.push(`reason_text 未包含「${e.text_includes}」，实际「${actual.reason_text}」`);
    }
    if (typeof actual.reason_text !== 'string' || !actual.reason_text.trim()) {
      problems.push('reason_text 为空');
    }
    if (!Object.values(REASON_CODES).includes(actual.reason_code)) {
      problems.push(`reason_code 不在枚举内：${actual.reason_code}`);
    }
  }

  if (problems.length) failures.push({ v, problems, actual });
  else passes.push(v);
  observed.push({ v, actual, input });
}

// ---------- 跨用例硬红线 ----------

const invariantResults = [];

// 红线 1：任何非 null 的建议都必须能自我解释
const mute = observed.filter((o) => o.actual && !String(o.actual.reason_text ?? '').trim());
invariantResults.push({
  id: 'every_suggestion_explains_itself',
  ok: mute.length === 0,
  detail: mute.length ? mute.map((o) => o.v.id).join(', ') : `${observed.filter((o) => o.actual).length} 条建议全部带理由`,
});

// 红线 2：自重动作永不 linear_progress
const bwBad = observed.filter(
  (o) => o.actual && o.input.exercise.weight_increment === 0 && o.actual.reason_code === REASON_CODES.LINEAR_PROGRESS,
);
invariantResults.push({
  id: 'bodyweight_never_linear_progress',
  ok: bwBad.length === 0,
  detail: bwBad.length ? bwBad.map((o) => o.v.id).join(', ') : '自重动作全部走加次数路径',
});

// 红线 2 推论：自重动作重量恒为 null
const bwWeight = observed.filter(
  (o) => o.actual && o.input.exercise.weight_increment === 0 && o.actual.weight_kg !== null,
);
invariantResults.push({
  id: 'bodyweight_never_returns_weight',
  ok: bwWeight.length === 0,
  detail: bwWeight.length ? bwWeight.map((o) => o.v.id).join(', ') : '自重动作重量全部为 null',
});

// 红线 3：辅助自重的推进方向只允许**减**助力，永远不许加
//
// 这一条是 2026-09-29 修的那个反向 bug 的门闩：辅助引体走的是"负重"分支时，
// "达标 → +5kg" 意味着**给你更多助力**，用户越练越轻松而系统以为在进步。
// 判据：任何 assisted 用例的下一组助力都不能比上一组**更大**（0 是地板）。
const assBad = observed.filter((o) => {
  if (!o.actual || o.input.exercise.track_type !== 'assisted_reps') return false;
  const last = o.input.lastSession?.weight_kg;
  if (typeof last !== 'number') return false;
  return Number(o.actual.weight_kg) > last;
});
invariantResults.push({
  id: 'assisted_never_increases_assistance',
  ok: assBad.length === 0,
  detail: assBad.length
    ? assBad.map((o) => `${o.v.id}(${o.input.lastSession.weight_kg} → ${o.actual.weight_kg})`).join(', ')
    : '辅助动作的助力只减不增（0 为地板）',
});

// ---------- 1RM 估算边界（用例同样来自 vectors.json，与 Dart 端共用一份规格） ----------

for (const c of spec.oneRmCases) {
  const got = estimate1RM(c.weight_kg, c.reps);
  const ok = eq(got, c.expect);
  const id = `estimate1RM(${c.weight_kg}, ${c.reps})`;
  invariantResults.push({ id, ok, detail: ok ? c.desc : `期望 ${c.expect}，实际 ${got}` });
  if (!ok) failures.push({ v: { id, desc: c.desc }, problems: [`期望 ${c.expect}，实际 ${got}`] });
}

// ---------- 输出 ----------

const line = '─'.repeat(72);
console.log(line);
console.log(`规则引擎测试：${spec.vectors.length} 条向量 + ${invariantResults.length} 条不变量检查`);
console.log(line);

if (failures.length) {
  console.log(`\n✗ ${failures.length} 项失败：\n`);
  for (const f of failures) {
    console.log(`  ✗ ${f.v.id}  —— ${f.v.desc ?? ''}`);
    for (const p of f.problems) console.log(`      ${p}`);
  }
} else {
  console.log(`\n✓ ${passes.length} 条向量全部通过\n`);
}

const badInv = invariantResults.filter((r) => !r.ok);
console.log('不变量检查：');
for (const r of invariantResults) console.log(`  ${r.ok ? '✓' : '✗'} ${r.id} —— ${r.detail}`);

// 覆盖率视角：按 reason_code 统计
const byCode = {};
for (const o of observed) {
  if (o.actual) byCode[o.actual.reason_code] = (byCode[o.actual.reason_code] ?? 0) + 1;
}
console.log('\nreason_code 覆盖：' + Object.entries(byCode).map(([k, n]) => `${k} ${n}`).join(' · '));

const total = spec.vectors.length + invariantResults.length;
const failedTotal = failures.length + badInv.length;
console.log(`\n${line}`);
console.log(failedTotal === 0 ? `✓ 全部通过（${total}/${total}）` : `✗ 失败 ${failedTotal}/${total}`);
console.log(line);

process.exit(failedTotal === 0 ? 0 : 1);
