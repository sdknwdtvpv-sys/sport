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
/** 按时长动作每次推进多少秒 */
export const TIME_STEP_SEC = 5;
/** 按时长动作的上限 = 目标区间上限 + 该值（秒） */
export const TIME_CAP_BONUS = 15;
/** 连续手改达到此次数后，不再自作主张 */
export const OVERRIDE_MIN_COUNT = 3;

/**
 * 消除浮点噪声（保留两位小数）。
 *
 * ⚠️ 原注释举的例子是错的：`60.1 + 2.5` 在 IEEE754 下**正好等于 62.6**，
 * 并不产生噪声。实测 0.1–400 kg、步长 2 / 2.5 / 5 的整个范围内，
 * 单次加法的结果都是正确舍入的（变异测试把这个"等价变异体"暴露了出来：
 * 去掉 round2，没有任何一条测试会红 —— 因为没有可泄漏的输入）。
 *
 * 它真正非它不可的地方是**除法**：`estimate1RM` 里的 `weight × (1 + reps/30)`。
 * 重量路径上保留它属于防御性写法（将来若有 lb→kg 之类的换算会产生更多小数位）。
 */
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

  // 0.5) **有氧不给推进建议**（distance_time：跑步机/划船机/跳绳/农夫行走）。
  //
  // 这是产品决策，不是偷懒：我们没有用户的有氧目标（减脂？耐力？间歇？），
  // 在这种前提下说"上次 5 公里 → 这次 5.25 公里（+5%）"是**假精确** ——
  // 而力量动作可以这么推，是因为"多举一点"本身就是目标。
  //
  // 为什么必须在这里挡、不能只靠 UI 不显示：
  // 不挡的话 distance_time 会掉进下面的**次数分支**（它不是 time），
  // 于是引擎会对一次 5 公里跑说"每组次数补到 10 次" —— 那是直接说错话。
  // 宁可返回 null（"不给建议"这条路径 UI 早就有），也不编一个数出来。
  const trackEarly = exercise.track_type ?? 'weight_reps';
  if (trackEarly === 'distance_time') return null;

  const inc = exercise.weight_increment ?? 0;
  const isBodyweight = inc === 0; // 由数据层不变量保证：inc === 0 ⟺ default_weight_kg === null
  // 按时长的动作（平板支撑 / 侧平板）：track_type 决定这个数字是**秒**而不是次数。
  // 缺省 weight_reps —— 老 fixture 与老数据的行为完全不变（向后兼容）。
  const track = exercise.track_type ?? 'weight_reps';
  const isTime = track === 'time' || track === 'weight_time';
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
        ? (isTime
          ? '第一次练这个动作，先记录你能坚持的秒数'
          : '第一次练这个动作，先记录你能完成的次数')
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

  // 4) 按时长的动作：这个量是**秒**不是次数，推进方式是加秒数。
  //    没有这一支，平板支撑会被按"次数"往上加，还会说出
  //    「自重已完成 30 次，建议加负重」这种让用户一眼看出不懂健身的话。
  if (isTime) {
    const keepW = isBodyweight ? null : round2(lastW);
    if (completed < sets) {
      return {
        weight_kg: keepW, reps: repsLow,
        reason_code: REASON_CODES.HOLD,
        reason_text: `上次只完成 ${completed} 组（计划 ${sets} 组），先把组数补满`,
      };
    }
    const cap = repsHigh + TIME_CAP_BONUS;
    if (minReps >= cap) {
      if (isBodyweight) {
        return {
          weight_kg: null, reps: cap,
          reason_code: REASON_CODES.ADD_REP,
          reason_text: `已能坚持 ${minReps} 秒，建议加负重`,
        };
      }
      // 负重时长（负重平板）：它是有重量的，到时长上限就直接加重
      return {
        weight_kg: round2(lastW + inc), reps: repsLow,
        reason_code: REASON_CODES.LINEAR_PROGRESS,
        reason_text: `已能坚持 ${minReps} 秒（上限 ${cap} 秒），加重 +${inc}kg`,
      };
    }
    const nextTime = Math.min(minReps + TIME_STEP_SEC, cap);
    return {
      weight_kg: keepW, reps: nextTime,
      reason_code: REASON_CODES.ADD_REP,
      reason_text: minReps >= repsHigh
        ? `时长已达目标上限，按秒推进：${minReps} → ${nextTime} 秒`
        : `按秒推进：${minReps} → ${nextTime} 秒`,
    };
  }

  // 5) 自重动作：唯一可行的推进方式是加次数
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

  // 6) 组数没做满 → 先补组数，不加重量
  if (completed < sets) {
    return {
      weight_kg: round2(lastW), reps: repsLow,
      reason_code: REASON_CODES.HOLD,
      reason_text: `上次只完成 ${completed} 组（计划 ${sets} 组），先把组数补满`,
    };
  }

  // 7) 全部达标 → 双重渐进的"加重量"分支
  if (minReps >= repsHigh) {
    return {
      weight_kg: round2(lastW + inc), reps: repsLow,
      reason_code: REASON_CODES.LINEAR_PROGRESS,
      reason_text: `上次 ${completed} 组全部达标，线性加重 +${inc}kg`,
    };
  }

  // 8) 有组掉到区间下限以下 → 保持重量（不加重也不降重，先看是不是偶发）
  if (minReps < repsLow) {
    return {
      weight_kg: round2(lastW), reps: repsLow,
      reason_code: REASON_CODES.HOLD,
      reason_text: `上次有组掉到 ${minReps} 次，先保持重量`,
    };
  }

  // 9) 中间态 → 重量不变，加次数
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
