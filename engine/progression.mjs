/**
 * 练了么 · 渐进建议引擎（规范参考实现）
 *
 * 这是规则引擎的**唯一权威定义**。Flutter 端移植后必须通过同一套测试向量
 * （engine/vectors.json），端口才算完成——见 engine/run-tests.mjs。
 *
 * 设计红线（违反即视为 bug，测试里有强制断言）：
 *   1. 每个非 null 的建议都必须带非空 reason_text，且能在一行内放下。解释不了的建议不许出现。
 *   2. 自重动作（weight_increment === 0）永远不返回 linear_progress，也不允许"回落次数"。
 *   3. 建议永远可一键采纳、随时手改，不存在不可撤销的自动化。
 *   4. 不把用户拉回整数网格：加重 = 用户实际重量 + 步长，系统不擅自改重量。
 *
 * 单位：重量一律 kg（REAL），次数为整数。
 */

/** 建议理由的粗粒度枚举。UI 依据它做埋点拆分，reason_text 才是给人看的。 */
export const REASON_CODES = Object.freeze({
  FIRST_TIME: 'first_time',           // 该动作零历史
  LINEAR_PROGRESS: 'linear_progress', // 全部达标 → 加重
  HOLD: 'hold',                       // 保持重量（掉组 / 组数不足）
  ADD_REP: 'add_rep',                 // 重量不变，加次数（双重渐进的中间态；自重动作的唯一路径）
  DELOAD: 'deload',                   // 长期未练后的回归保护（当前实现为保持重量，不降重）
  USER_PREFERRED: 'user_preferred',   // 用户连续手改 ≥3 次，沿用他的值
});

/** 超过这个天数没练该动作，触发回归保护 */
export const STALE_DAYS = 21;
/** 自重动作次数上限 = 目标区间上限 + 该值 */
export const BODYWEIGHT_REP_CAP_BONUS = 5;
/** 连续手改达到此次数后，不再自作主张 */
export const OVERRIDE_MIN_COUNT = 3;

/** 消除浮点噪声：60.1 + 2.5 = 62.60000000000001 → 62.6 */
const round2 = (n) => Math.round(n * 100) / 100;

/**
 * 用户是否已连续多次把同一动作手改成同一个值。
 * overrides 由调用方按动作过滤好，最新在前：[{ weight_kg, reps }, ...]
 */
function preferredOverride(overrides) {
  if (!Array.isArray(overrides) || overrides.length < OVERRIDE_MIN_COUNT) return null;
  const head = overrides[0];
  if (!head || head.weight_kg === undefined || head.reps === undefined) return null;
  let count = 0;
  for (const o of overrides) {
    if (o.weight_kg === head.weight_kg && o.reps === head.reps) count += 1;
    else break;
  }
  return count >= OVERRIDE_MIN_COUNT ? { weight_kg: head.weight_kg, reps: head.reps, count } : null;
}

/**
 * 给出下一组的建议。
 *
 * @param {object}   input
 * @param {object}   input.exercise     动作库条目，至少含 { id, weight_increment, default_weight_kg }
 * @param {object}   input.plan         计划项 { target_sets, target_reps_low, target_reps_high, target_weight_kg? }
 * @param {object?}  input.lastSession  上次同动作表现 { weight_kg, reps: number[], daysAgo }
 *                                      reps 必须**只含正式组**（调用方过滤掉热身组）；无历史传 null
 * @param {object?}  input.profile      用户画像 { progression_mode: 'double' | 'linear' | 'off' }
 * @param {object[]?} input.overrides   该动作最近的手改记录，最新在前
 * @returns {{weight_kg: number|null, reps: number, reason_code: string, reason_text: string} | null}
 *          返回 null 表示"不给建议"（用户关闭了建议）
 */
export function suggestNext(input) {
  const { exercise, plan, lastSession = null, profile = {}, overrides = [] } = input ?? {};
  if (!exercise || !plan) throw new Error('suggestNext: 缺少 exercise 或 plan');

  // 0) 用户关掉了建议：直接闭嘴，这是设置项赋予的权利
  if (profile.progression_mode === 'off') return null;

  const inc = exercise.weight_increment ?? 0;
  const isBodyweight = inc === 0; // 由数据层不变量保证：inc === 0 ⟺ default_weight_kg === null
  const sets = plan.target_sets;
  const repsLow = plan.target_reps_low;
  const repsHigh = plan.target_reps_high;

  // 1) 用户连续手改 ≥3 次 → 沿用他的值（先于一切自动判断）
  const pref = preferredOverride(overrides);
  if (pref) {
    return {
      weight_kg: pref.weight_kg,
      reps: pref.reps,
      reason_code: REASON_CODES.USER_PREFERRED,
      reason_text: `按你最近 ${pref.count} 次手动设置的重量`,
    };
  }

  // 2) 该动作零历史 → 动作库起始重量
  if (!lastSession) {
    return {
      weight_kg: isBodyweight ? null : (exercise.default_weight_kg ?? plan.target_weight_kg ?? null),
      reps: repsLow,
      reason_code: REASON_CODES.FIRST_TIME,
      reason_text: isBodyweight
        ? '第一次练这个动作，先记录你能完成的次数'
        : '第一次练这个动作，先从这个重量开始',
    };
  }

  const reps = Array.isArray(lastSession.reps) ? lastSession.reps : [];
  const completed = reps.length;
  const minReps = completed ? Math.min(...reps) : 0;
  const lastW = lastSession.weight_kg ?? 0;
  const days = lastSession.daysAgo ?? 0;

  // 3) 长期未练 → 回归保护。先于一切进度判断：三周前的数据不足以支撑加重
  if (days >= STALE_DAYS) {
    return {
      weight_kg: isBodyweight ? null : round2(lastW),
      reps: repsLow,
      reason_code: REASON_CODES.DELOAD,
      reason_text: `已经有 ${days} 天没练这个动作，先按上次重量找回感觉`,
    };
  }

  // 4) 自重动作：唯一可行的推进方式是加次数
  if (isBodyweight) {
    if (completed < sets) {
      return {
        weight_kg: null, reps: repsLow,
        reason_code: REASON_CODES.HOLD,
        reason_text: `上次只完成 ${completed} 组（计划 ${sets} 组），先把组数补满`,
      };
    }
    const cap = repsHigh + BODYWEIGHT_REP_CAP_BONUS;
    if (minReps >= cap) {
      return {
        weight_kg: null, reps: cap,
        reason_code: REASON_CODES.ADD_REP,
        reason_text: `自重已完成 ${minReps} 次，建议加负重`,
      };
    }
    const next = Math.min(minReps + (minReps >= repsHigh ? 2 : 1), cap);
    return {
      weight_kg: null, reps: next,
      reason_code: REASON_CODES.ADD_REP,
      reason_text: minReps >= repsHigh
        ? `次数已到上限，先加到 ${next} 次，之后考虑负重`
        : `自重动作先加次数：${minReps} → ${next} 次`,
    };
  }

  // 5) 组数没做满 → 先补组数，不加重量
  if (completed < sets) {
    return {
      weight_kg: round2(lastW), reps: repsLow,
      reason_code: REASON_CODES.HOLD,
      reason_text: `上次只完成 ${completed} 组（计划 ${sets} 组），先把组数补满`,
    };
  }

  // 6) 全部达标 → 双重渐进的"加重量"分支
  if (minReps >= repsHigh) {
    return {
      weight_kg: round2(lastW + inc), reps: repsLow,
      reason_code: REASON_CODES.LINEAR_PROGRESS,
      reason_text: `上次 ${completed} 组全部达标，线性加重 +${inc}kg`,
    };
  }

  // 7) 有组掉到区间下限以下 → 保持重量（不加重也不降重，先看是不是偶发）
  if (minReps < repsLow) {
    return {
      weight_kg: round2(lastW), reps: repsLow,
      reason_code: REASON_CODES.HOLD,
      reason_text: `上次有组掉到 ${minReps} 次，先保持重量`,
    };
  }

  // 8) 中间态 → 重量不变，加次数
  const next = Math.min(minReps + 1, repsHigh);
  return {
    weight_kg: round2(lastW), reps: next,
    reason_code: REASON_CODES.ADD_REP,
    reason_text: `上次差一点达标，先把每组次数补到 ${next}`,
  };
}

/** 估算 1RM（Epley）。仅在 reps ≤ 12 时可信，超出返回 null —— 高次数下的估算会误导用户。 */
export function estimate1RM(weightKg, reps) {
  if (!Number.isFinite(weightKg) || !Number.isFinite(reps)) return null;
  if (weightKg <= 0 || reps <= 0 || reps > 12) return null;
  return round2(weightKg * (1 + reps / 30));
}
