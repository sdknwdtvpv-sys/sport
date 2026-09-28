#!/usr/bin/env node
/**
 * 练了么 · 场景级 eval（序列级产品红线）
 *
 * **它补的是哪一块**：`run-tests.mjs` 的向量管**单步正确性** —— 给一个输入，输出对不对。
 * 但用户感受到的不是单步，而是"**连练 12 周之后，这个 App 说的话还讲不讲道理**"。
 * 向量测不出序列问题：每一步都正确的函数，串起来照样可能走成荒谬的轨迹。
 *
 * 所以这里模拟一段**跨周训练史**：把上一步的建议当成用户实际练的内容再喂回去，
 * 然后对整条轨迹断言产品红线（`PRODUCT.md` / `docs/interaction-spec.md`）。
 *
 * **为什么不在 Dart 侧也实现一份运行器**：两套实现的一致性由 `vectors.json` 保证
 * （同一份向量、两个引擎都必须跑通）。场景 eval 验证的是**规则体系的质量**，
 * 不是语言的移植 —— 再写一份 Dart 运行器只是把同一套红线重算一遍，
 * 多出一处会各自漂移的代码。这条取舍是刻意的。
 *
 * 用法：
 *   node engine/run-scenarios.mjs            # 跑全部场景 + 红线
 *   node engine/run-scenarios.mjs -v         # 打印每条轨迹的逐步明细
 *
 * 退出码：任何红线被违反 → 1
 */

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  suggestNext,
  REASON_CODES,
  BODYWEIGHT_REP_CAP_BONUS,
  TIME_CAP_BONUS,
  TIME_STEP_SEC,
} from './progression.mjs';

const ROOT = dirname(fileURLToPath(import.meta.url));
const spec = JSON.parse(readFileSync(join(ROOT, 'scenarios.json'), 'utf8'));
const vectors = JSON.parse(readFileSync(join(ROOT, 'vectors.json'), 'utf8'));
const F = vectors.fixtures;
const verbose = process.argv.includes('-v') || process.argv.includes('--verbose');

const REASON_WIRE = Object.values(REASON_CODES);
/** 理由要"一行放得下"。超过这个长度就该重写文案，而不是缩字号。 */
const REASON_MAX_CHARS = 40;

/** 按时长的动作：数字是秒，不是次数。 */
const isTimeTrack = (t) => t === 'time' || t === 'weight_time';

/** 次数/秒数的上界。**直接引用引擎的常量**，所以常量一改这里就跟着收紧。 */
function capFor(ex, plan) {
  const inc = ex.weight_increment ?? 0;
  if (isTimeTrack(ex.track_type)) {
    return inc === 0
      ? plan.target_reps_high + TIME_CAP_BONUS
      : plan.target_reps_high + TIME_CAP_BONUS;
  }
  return inc === 0
    ? plan.target_reps_high + BODYWEIGHT_REP_CAP_BONUS
    : plan.target_reps_high;
}

// ---------------------------------------------------------------- 用户模型
//
// 刻意**不依赖引擎**：模型描述的是"一个人会怎么练"，而不是"引擎想让他怎么练"。
// 照着引擎输出反推的话，这套 eval 就成了同义反复。

function perform(s, plan, model) {
  const sets = plan.target_sets;
  if (model === 'short') return { reps: s.reps, sets: sets - 1 };
  if (model === 'top') return { reps: plan.target_reps_high, sets };
  if (model === 'below') return { reps: Math.max(1, plan.target_reps_low - 2), sets };
  return { reps: s.reps, sets }; // follow：就按建议做
}

// ---------------------------------------------------------------- 红线检查

function checkTrace(sc, trace) {
  const problems = [];
  const bad = (i, rule, detail) => problems.push(`第 ${i + 1} 次 · ${rule}：${detail}`);

  const ex = F[sc.exercise];
  const plan = F[sc.plan];
  const inc = ex.weight_increment ?? 0;
  const bodyweight = inc === 0;
  const time = isTimeTrack(ex.track_type);
  const cap = capFor(ex, plan);

  let prev = null;
  let deloads = 0;
  let increases = 0;

  for (let i = 0; i < trace.length; i++) {
    const s = trace[i].suggestion;
    const text = String(s.reason_text ?? '');

    if (!text.trim()) bad(i, 'reason_never_empty', '理由为空');
    if (text.length > REASON_MAX_CHARS) bad(i, 'reason_fits_one_line', `${text.length} 字：「${text}」`);
    if (/null|undefined|NaN|Infinity/i.test(text)) bad(i, 'reason_has_no_placeholders', `「${text}」`);
    if (!REASON_WIRE.includes(s.reason_code)) bad(i, 'reason_code_in_enum', String(s.reason_code));

    if (bodyweight && s.weight_kg !== null) {
      bad(i, 'bodyweight_never_gets_weight', `自重动作却给了 ${s.weight_kg}kg`);
    }
    if (bodyweight && s.reason_code === REASON_CODES.LINEAR_PROGRESS) {
      bad(i, 'bodyweight_never_gets_weight', '自重动作返回了 linear_progress');
    }
    if (!bodyweight && !(typeof s.weight_kg === 'number' && s.weight_kg > 0)) {
      bad(i, 'weighted_always_has_weight', `有步长的动作却给了 ${s.weight_kg}`);
    }
    if (s.reps < plan.target_reps_low) {
      bad(i, 'reps_never_below_range', `${s.reps} < 下限 ${plan.target_reps_low}`);
    }
    if (s.reps > cap) {
      bad(i, 'reps_stay_bounded', `${s.reps} > 上界 ${cap}`);
    }
    if (time) {
      // ⚠️ 不能只查一个「次」字：**「第一次练这个动作」里的"次"不是计数单位**。
      // 红线是"按时长动作不能把次数当作要做的量"，所以查的是「数字 + 次」与「次数」。
      // （第一版就是拿 /次/ 查的，结果把两条正确文案判成了违规 —— eval 的第一版
      //   先抓到的往往是 eval 自己的毛病。）
      if (/\d+\s*次/.test(text) || /次数/.test(text)) {
        bad(i, 'time_steps_are_five_seconds', `按时长动作的理由把次数当成了要做的量：「${text}」`);
      }
      if (prev && prev.suggestion.reps !== s.reps && (s.reps - prev.suggestion.reps) % TIME_STEP_SEC !== 0) {
        bad(i, 'time_steps_are_five_seconds',
          `秒数变化 ${prev.suggestion.reps} → ${s.reps} 不是 ${TIME_STEP_SEC} 的倍数`);
      }
    }
    if (s.reason_code === REASON_CODES.DELOAD) deloads++;

    if (prev) {
      const prevS = prev.suggestion;
      if (!bodyweight && s.weight_kg > prevS.weight_kg + 1e-9) {
        const delta = Math.round((s.weight_kg - prevS.weight_kg) * 100) / 100;
        if (delta > inc + 1e-9) {
          bad(i, 'one_step_at_a_time', `一次加了 ${delta}kg，步长只有 ${inc}kg`);
        }
        increases++;
        // 双重渐进的契约：只有"上次做满组数 + 每组都触到区间上限"才允许加重
        const didAllSets = prev.performed.sets >= plan.target_sets;
        const done = prev.performed.reps;
        if (!didAllSets || done < plan.target_reps_high) {
          bad(i, 'increase_only_after_top_reps',
            `上次 ${prev.performed.sets}/${plan.target_sets} 组、每组 ${done}（上限 ${plan.target_reps_high}），仍然加重了`);
        }
      }
      if (!bodyweight && s.weight_kg < prevS.weight_kg - 1e-9) {
        bad(i, 'weight_never_drops', `${prevS.weight_kg}kg → ${s.weight_kg}kg`);
      }
    }

    prev = trace[i];
  }

  return { problems, deloads, increases };
}

// ---------------------------------------------------------------- 跑场景

const results = [];
let totalSteps = 0;

for (const sc of spec.scenarios) {
  const ex = F[sc.exercise];
  const plan = F[sc.plan];
  if (!ex || !plan) {
    results.push({ sc, error: `找不到 fixture：${sc.exercise} / ${sc.plan}` });
    continue;
  }

  const trace = [];
  let lastSession = null;

  for (let i = 0; i < sc.sessions; i++) {
    // "上次练完到现在过了多久"由场景决定：平时按 daysBetween，插休息的那一次按 layoffDays
    const layoff = sc.layoffAt !== undefined && i === sc.layoffAt;
    const daysAgo = layoff ? (sc.layoffDays ?? 25) : (i === 0 ? 0 : sc.daysBetween);

    const s = suggestNext({ exercise: ex, plan, lastSession, profile: {} });
    if (!s) {
      results.push({ sc, error: `第 ${i + 1} 次训练没拿到建议（返回 null）` });
      break;
    }

    const performed = perform(s, plan, sc.model);
    trace.push({ session: i + 1, daysAgo, suggestion: s, performed, layoff });

    // 把这一次"实际练的"变成下一次的 lastSession —— 序列就是这么来的
    lastSession = {
      weight_kg: (ex.weight_increment ?? 0) === 0 ? null : s.weight_kg,
      reps: Array.from({ length: performed.sets }, () => performed.reps),
      daysAgo,
    };
  }
  if (trace.length === 0) continue;

  const { problems, deloads, increases } = checkTrace(sc, trace);

  // 场景自己的结构期望（红线之外的最低要求）
  const exp = sc.expect ?? {};
  if (exp.mustIncreaseWeight && increases === 0) {
    problems.push('场景期望：这段过程里应当至少加重一次，实际一次都没有');
  }
  if (exp.mustNotIncreaseWeight && increases > 0) {
    problems.push(`场景期望：一次都不该加重，实际加重了 ${increases} 次`);
  }
  if (exp.mustTriggerDeload && deloads === 0) {
    problems.push('场景期望：应当触发回归保护，实际一次都没有');
  }

  totalSteps += trace.length;
  results.push({ sc, trace, problems, deloads, increases });
}

// ---------------------------------------------------------------- 报告

const fmt = (s, time) => {
  const w = s.weight_kg === null ? '自重' : `${s.weight_kg}kg`;
  return time ? `${w} × ${s.reps}秒` : `${w} × ${s.reps}`;
};

console.log('练了么 · 场景级 eval（把产品红线写成序列级断言）\n');
for (const r of results) {
  if (r.error) {
    console.log(`✗ ${r.sc.id.padEnd(28)} ${r.error}`);
    continue;
  }
  const time = isTimeTrack(F[r.sc.exercise].track_type);
  const first = r.trace[0].suggestion;
  const last = r.trace[r.trace.length - 1].suggestion;
  console.log(`${r.problems.length ? '✗' : '✓'} ${r.sc.id.padEnd(28)} `
    + `${String(r.trace.length).padStart(2)} 次 · ${fmt(first, time)} → ${fmt(last, time)}`
    + ` · 加重 ${r.increases} 次`
    + (r.deloads ? ` · 回归保护 ${r.deloads} 次` : ''));
  if (verbose) {
    for (const t of r.trace) {
      console.log(`      #${String(t.session).padStart(2)} `
        + `${t.layoff ? `[断练 ${t.daysAgo} 天] ` : ''}`
        + `${fmt(t.suggestion, time)}  ${t.suggestion.reason_text}`);
    }
  }
}

const violations = results.reduce((a, r) => a + (r.problems?.length ?? 0), 0);
if (violations) {
  console.log('');
  for (const r of results) {
    if (!r.problems?.length) continue;
    for (const p of r.problems.slice(0, 8)) console.log(`  ✗ ${r.sc.id} · ${p}`);
    if (r.problems.length > 8) console.log(`  ✗ ${r.sc.id} · ……还有 ${r.problems.length - 8} 条`);
  }
}

console.log(`\n${'─'.repeat(74)}`);
if (violations) {
  console.log(`✗ ${violations} 处红线被违反（${results.length} 个场景 / ${totalSteps} 步）`);
  process.exitCode = 1;
} else {
  const increases = results.reduce((a, r) => a + (r.increases ?? 0), 0);
  const deloads = results.reduce((a, r) => a + (r.deloads ?? 0), 0);
  console.log(`✓ 全部通过：${results.length} 个场景 / ${totalSteps} 步 / ${spec.invariants.length} 条红线`
    + `（累计加重 ${increases} 次、回归保护 ${deloads} 次）`);
}
