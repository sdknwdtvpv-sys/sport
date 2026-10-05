#!/usr/bin/env node
/**
 * 练了么 · 「预置 6 周历史」备份文件生成器（零依赖）
 *
 * **它解决什么**：可用性测试要在**全新安装**的机器上给被试一份"练过 6 周"的历史
 * （否则「上次 60kg×10」与「今天建议 62.5kg」两处都没内容，测的就不是同一个产品）。
 * `docs/usability-test.md` §测试环境写着"用一份生成的备份 JSON 就能把 6 周历史灌进去"，
 * **但那份 JSON 全仓不存在，也没有生成器** —— 2026-10-01 才发现。
 * 现场临时手搓的后果：5 个被试拿到的预置数据还不一样，横向对比当场失效。
 *
 * 机制本身早就通了（`app/lib/features/profile/backup.dart` 的粘贴导入，
 * 由 `app/test/backup_test.dart` 的「导回库里」那一组钉着）——**缺的只是这份数据**。
 *
 * 用法：
 *   node tool/preset-history.mjs                 # 打到 stdout（基准日 = 今天）
 *   node tool/preset-history.mjs --write         # 写进 usability/preset-6-weeks.json
 *   node tool/preset-history.mjs --check         # 用文件自己记录的基准日复现它，逐字节比对
 *   node tool/preset-history.mjs --today=2026-10-01   # 指定基准日（可复现）
 *   node tool/preset-history.mjs --selftest      # 自检（确定性 / 不变量 / 真引擎算出来的建议）
 *
 * ## 这份数据不是"随便造六周"，它必须让 T6 那张卡是真的
 *
 * 任务卡 T6 的原话是「App 建议你这次推 **62.5 公斤**，但你想推 60」。
 * 而建议值是引擎算出来的 —— 所以预置数据必须**恰好**让它算出 62.5，否则那张卡
 * 就是一句假话，T6 测的就不是"改建议"而是"被试找不到那个数"。链条是这样扣上的：
 *
 *   1. **今天排课推胸**：`nextMuscleGroup()` 取**最近一次训练**练过的部位
 *      （`LocalStore.recentExerciseIds()` 只看最近那一次），在
 *      `kMuscleRotation = 胸→背→腿→肩→臂→核心` 里找第一个没练的。
 *      ⇒ 所以最近一次训练必须是**腿**（练了腿 → 今天轮到胸）。
 *   2. **胸日第一个动作是杠铃卧推**：按部位取常用度最高的（卧推 popularity 100）。
 *   3. **建议 62.5**：计划器给力量动作的处方是 **3 组 × 8–10 次**（`kDefaultPlan`），
 *      而引擎的双重渐进要求 `minReps >= repsHigh` 才加重
 *      （只做到 8 次会走"先把每组次数补到 9"那一支，建议值仍是 60）。
 *      ⇒ 所以卧推的最后一组数据必须是 **3 组 × 10 次 @ 60kg** → 建议 **62.5kg × 8**。
 *
 * 这三条都由 `invariants()` 断言，而且第 3 条是**直接调真引擎**
 * （`engine/progression.mjs::suggestNext`）算出来的，不是我在这里复述一遍规则 ——
 * 规则一旦改，这份自检立刻红。顺带，任务卡 T4「上周卧推一共推了多少公斤」
 * 的答案也由此确定：**1800 kg**（3×10×60，落在近 7 天窗口内）。
 *
 * ## 为什么所有日期都相对一个「基准日」
 *
 * 历史记录**必须**是最近几天，否则引擎会走"已经有 N 天没练"那条分支（≥21 天），
 * 而不是「上次 3 组全部达标，线性加重 +2.5kg」—— 后者才是这个测试要测的东西。
 * 所以日期要相对"跑测试那天"算。
 *
 * 但**相对今天算**又会让 `--check` 明天就红（每天生成的东西都不一样）。
 * 解法：把**基准日**写进文件的 `exported_at`，`--check` 读出来、
 * 用同一天重新生成、逐字节比对 —— 于是"可复现"与"日期新鲜"两件事同时成立。
 * 现场跑测试前重新 `--write` 一次即可（`--check` 会提醒这份数据放多久了）。
 *
 * ## 时区
 *
 * 所有时刻按**北京时间 19:00 开始训练**生成（内部用 UTC 算术：19:00 CST = 11:00 UTC），
 * 与运行这台机器的时区无关 —— 否则同一份输入在不同机器上会产出不同字节。
 *
 * ## 一条被我自己推翻的约束（留档，免得下次又有人这么写）
 *
 * 写方案时我写过"预置数据不能把首页『上周』数字顶起来"。**那是错的**：
 * 我把它建立在 `app/test/backup_test.dart` 里一句注释上，而那条注释讲的是
 * 那个测试自己的夹具（两次训练里只有一次落在窗口内）。
 * 真实的取舍正好相反 —— 最近一次训练**必须**落在几天内，否则：
 *   ① 引擎走 21 天回归分支，建议卡说的不是"加重"；② 首页写"上周练了 0 次"，
 * 而建议卡却引用着"上次 60kg×10"，两屏自相矛盾，被试会以为 App 坏了。
 * 现在最新一次训练在基准日 **3 天前**，近 7 天窗口里有 **2 次**训练 —— 与现实一致。
 */

import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { suggestNext } from '../engine/progression.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const OUT = 'usability/preset-6-weeks.json';

const DAY = 86400000;
/** 北京时间 19:00 = 11:00 UTC。 */
const START_HOUR_UTC = 11;

/** 与 `app/lib/features/today/today_planner.dart::kMuscleRotation` 同一条。 */
export const ROTATION = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core'];
/** 与 `today_planner.dart::kDefaultPlan` 同一个处方（3 组 8–10 次）。 */
export const DEFAULT_PLAN = { target_sets: 3, target_reps_low: 8, target_reps_high: 10 };

/**
 * 动作表。**`base` 是"最近那一周"的重量**，往过去每周减一个 `step`
 * —— 于是它就是一条干净的线性加重史，引擎看了会给出"下周 +step"的建议。
 * `step` 必须等于种子里该动作的 `weight_increment`（自检会对着种子核）。
 *
 * 次数统一 **10**：计划器的区间是 8–10，只有做满上限引擎才会加重（见文件头）。
 */
const EX = {
  bench: { id: 'ex_bb_bench_press', name: '杠铃卧推', base: 60, step: 2.5, warmup: true },
  incline: { id: 'ex_db_incline_press', name: '上斜哑铃卧推', base: 20, step: 2 },
  row: { id: 'ex_seated_cable_row', name: '坐姿绳索划船', base: 45, step: 2.5 },
  pulldown: { id: 'ex_lat_pulldown', name: '高位下拉', base: 45, step: 2.5 },
  squat: { id: 'ex_bb_squat', name: '杠铃深蹲', base: 75, step: 2.5, warmup: true },
  rdl: { id: 'ex_rdl', name: '罗马尼亚硬拉', base: 62.5, step: 2.5 },
};

/** 推 / 拉 / 腿 三分化：每周三练，顺序固定（同一个部位每周练一次）。 */
const KIND = {
  chest: ['bench', 'incline'],
  back: ['row', 'pulldown'],
  legs: ['squat', 'rdl'],
};

/**
 * 每周三次训练**距基准日的天数**与**部位**（按时间顺序：最早 → 最近）。
 *
 * ⚠️ 顺序是这个文件的灵魂：**最近那一次必须是腿** ——
 * 那样 `nextMuscleGroup()` 才会给出 chest（见文件头第 1 条）。
 * 天数的选择也不是随手写的：7 天前那次落在"近 7 天"窗口**之外**，
 * 5 天与 3 天前那次落在里面（`weekWorkoutCount` 的口径是
 * `[今天 00:00 − 6 天, 明天 00:00)`），于是首页显示「上周练了 2 次」、
 * 而 T4 问的"上周卧推总容量"正好是 5 天前那次：3 × 10 × 60 = **1800 kg**。
 */
const WEEK = [
  { offset: 7, kind: 'back' },
  { offset: 5, kind: 'chest' },
  { offset: 3, kind: 'legs' },
];
const WEEKS = 6;
const NORMAL_SETS = 3;
const REPS = 10;

/** 训练里第一个动作带一组热身（演示热身功能，也贴近真实）。 */
const WARMUP_RATIO = 0.5;

/** 第 w 周（0 = 最近）某个动作的重量。 */
export function weightFor(spec, w) {
  // 浮点噪声：2.5 的减法会出 62.49999999999999，统一按 step 收一下
  return Math.round((spec.base - spec.step * w) / spec.step) * spec.step;
}

/** 基准日的 UTC 0 点（基准日按 UTC 解释 —— 与机器时区无关）。 */
function baseUtcDay(todayStr) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(todayStr);
  if (!m) throw new Error(`--today 要写成 YYYY-MM-DD，收到的是「${todayStr}」`);
  const [, y, mo, d] = m.map(Number);
  const ms = Date.UTC(y, mo - 1, d);
  if (Number.isNaN(ms)) throw new Error(`--today 不是合法日期：${todayStr}`);
  return ms;
}

const pad = (n) => String(n).padStart(2, '0');

function isoDate(ms) {
  const t = new Date(ms);
  return `${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}`;
}

/**
 * 生成备份对象。**纯函数**：同一个 `today` 一定产出同一份东西（这是 `--check` 的地基）。
 */
export function buildPreset(todayStr) {
  const base = baseUtcDay(todayStr);
  const workouts = [];
  let setTotal = 0;
  let warmupTotal = 0;

  for (let w = 0; w < WEEKS; w++) {
    WEEK.forEach((slot, i) => {
      const dayMs = base - (slot.offset + 7 * w) * DAY;
      const startedAt = dayMs + START_HOUR_UTC * 3600000;
      const sets = [];
      // 组完成时间在训练开始后逐组推进，热身组排在最前
      let cursor = startedAt + 5 * 60000;

      KIND[slot.kind].forEach((key, ei) => {
        const spec = EX[key];
        const weight = weightFor(spec, w);
        const entries = [];
        if (spec.warmup && ei === 0) {
          entries.push({
            type: 'warmup',
            weight: Math.round((weight * WARMUP_RATIO) / spec.step) * spec.step,
            reps: REPS,
          });
        }
        for (let s = 0; s < NORMAL_SETS; s++) {
          entries.push({ type: 'normal', weight, reps: REPS });
        }
        entries.forEach((e, si) => {
          sets.push({
            id: `s_preset_${w}_${i}_${key}_${si + 1}`,
            exercise_id: spec.id,
            set_index: si + 1,
            reps: e.reps,
            weight_kg: e.weight,
            distance_m: null,
            set_type: e.type,
            rpe: null,
            completed_at: cursor,
          });
          if (e.type === 'warmup') warmupTotal += 1;
          setTotal += 1;
          cursor += 3 * 60000;
        });
        cursor += 4 * 60000; // 换动作的间隙
      });

      workouts.push({
        id: `w_preset_${w}_${i}`,
        started_at: startedAt,
        ended_at: sets[sets.length - 1].completed_at + 5 * 60000,
        sets,
      });
    });
  }

  const root = {
    app: 'lianleme',
    format: 2,
    // 基准日的 20:00（北京）= 12:00 UTC —— 晚于当天所有训练，早于"第二天"
    exported_at: base + 12 * 3600000,
    unit: 'kg',
    exercise_names: Object.fromEntries(Object.values(EX).map((e) => [e.id, e.name])),
    workouts,
  };
  return { root, stats: { workouts: workouts.length, sets: setTotal, warmups: warmupTotal } };
}

/** 序列化。**必须稳定**：`--check` 逐字节比对。 */
export function serialize(root) {
  return `${JSON.stringify(root)}\n`;
}

// ──────────────────────────────────────────────────────────── 派生事实

const normals = (root) => root.workouts.flatMap((w) => w.sets).filter((s) => s.set_type === 'normal');

/** 近 7 天窗口里的训练次数 —— 与 `progress_data.dart::weekWorkoutCount` 同口径。 */
export function weekWorkoutCount(root) {
  const first = root.exported_at - 7 * DAY;
  const ids = new Set();
  for (const w of root.workouts) {
    for (const s of w.sets) {
      if (s.completed_at >= first && s.completed_at < root.exported_at) ids.add(w.id);
    }
  }
  return ids.size;
}

/** 最近一次训练练到的部位 → 今天该轮到哪个部位（与 `nextMuscleGroup()` 同口径）。 */
export function nextMuscleGroup(root, seedById) {
  const latest = [...root.workouts].sort((a, b) => a.started_at - b.started_at).at(-1);
  const trained = new Set(
    latest.sets
      .filter((s) => s.set_type === 'normal')
      .map((s) => seedById.get(s.exercise_id)?.muscle_group)
      .filter(Boolean),
  );
  return ROTATION.find((g) => !trained.has(g)) ?? ROTATION[0];
}

/** 某个动作在预置数据里"上次"的样子（喂给真引擎用）。 */
export function lastSessionOf(root, exerciseId) {
  const rows = normals(root).filter((s) => s.exercise_id === exerciseId);
  if (!rows.length) return null;
  const lastAt = Math.max(...rows.map((s) => s.completed_at));
  // 同一次训练里的组：按完成时间往回 3 小时内的都算
  const same = rows.filter((s) => s.completed_at <= lastAt && s.completed_at > lastAt - 3 * 3600000);
  return {
    weight_kg: same[0].weight_kg,
    reps: same.map((s) => s.reps),
    daysAgo: Math.round((root.exported_at - lastAt) / DAY),
  };
}

/**
 * 核一遍这份数据**真的能用**。返回问题列表（空 = 通过）。
 *
 * 这里几条都不是形式检查：
 *   * 动作 id 必须在种子里真的存在（拼错了导入后就是一堆 `ex_xxxxxxxx`）；
 *   * 组 id 必须全局唯一（导入是按 id upsert 的，撞了就会静默少几条）；
 *   * 最新一次训练必须在几天内（否则引擎走 21 天回归分支、首页与建议卡互相矛盾）；
 *   * **今天必须轮到胸、且引擎必须算出 62.5** —— 那是任务卡 T6 的原话，
 *     也是**真引擎**（`engine/progression.mjs`）算的，不是我在这里复述规则。
 */
export function invariants(root, seedById) {
  const problems = [];
  const ids = new Set();
  const exIds = new Set();
  let latest = 0;

  for (const w of root.workouts) {
    if (!/^w_/.test(w.id)) problems.push(`训练 id 不像我们的：${w.id}`);
    if (w.started_at >= root.exported_at) problems.push(`${w.id} 的开始时间不在 exported_at 之前`);
    latest = Math.max(latest, w.started_at);
    for (const s of w.sets) {
      if (ids.has(s.id)) problems.push(`组 id 重复：${s.id}`);
      ids.add(s.id);
      exIds.add(s.exercise_id);
      if (s.completed_at >= root.exported_at) problems.push(`${s.id} 的完成时间不在 exported_at 之前`);
      if (!Number.isFinite(s.weight_kg)) problems.push(`${s.id} 没有重量`);
      if (!(s.reps > 0)) problems.push(`${s.id} 的次数不是正数`);
      if (s.set_type !== 'normal' && s.set_type !== 'warmup') problems.push(`${s.id} 的 set_type 不认识：${s.set_type}`);
    }
  }
  for (const id of exIds) {
    if (!seedById.has(id)) problems.push(`动作 id 不在种子里：${id}（导入后会退化成 ex_xxxxxxxx）`);
  }
  for (const [key, spec] of Object.entries(EX)) {
    const mine = normals(root).filter((s) => s.exercise_id === spec.id);
    if (mine.length < NORMAL_SETS) problems.push(`${key}（${spec.id}）只有 ${mine.length} 组正式组，太少`);
    // 步长必须等于种子里的 weight_increment，否则建议出来的值在 App 里点不到
    const seed = seedById.get(spec.id);
    if (seed && seed.weight_increment !== spec.step) {
      problems.push(`${key} 的步长是 ${spec.step}，而种子里 weight_increment 是 ${seed.weight_increment}`);
    }
    // 重量必须是步长的整数倍（否则界面上是个没法用步进按钮对上的数）
    for (const s of mine) {
      if (Math.abs(s.weight_kg / spec.step - Math.round(s.weight_kg / spec.step)) > 1e-9) {
        problems.push(`${s.id} 的重量 ${s.weight_kg} 不是步长 ${spec.step} 的整数倍`);
      }
    }
  }

  const ageDays = Math.round((root.exported_at - latest) / DAY);
  if (ageDays !== 3) {
    problems.push(`最新一次训练距基准日 ${ageDays} 天，应当是 3 天`
      + '（再久一点引擎会走"很久没练"分支，见本文件头注释）');
  }
  if (weekWorkoutCount(root) !== 2) {
    problems.push(`近 7 天里的训练次数是 ${weekWorkoutCount(root)}，应当是 2`);
  }

  // ★ 任务卡 T6 的那条链：今天轮到胸 → 卧推 → 引擎建议 62.5
  const group = nextMuscleGroup(root, seedById);
  if (group !== 'chest') {
    problems.push(`按最近一次训练推算，今天该练的是 ${group} 而不是 chest ——`
      + ' T6 那张卡（"App 建议你这次推 62.5 公斤"）会落空，'
      + '最近一次训练必须是腿（见本文件头第 1 条）');
  }
  const benchSeed = seedById.get(EX.bench.id);
  const lastBench = lastSessionOf(root, EX.bench.id);
  if (!lastBench) {
    problems.push('预置数据里没有卧推记录');
  } else if (benchSeed) {
    const s = suggestNext({ exercise: benchSeed, plan: DEFAULT_PLAN, lastSession: lastBench });
    if (!s || s.weight_kg !== 62.5) {
      problems.push(`真引擎对卧推算出来的是 ${s ? `${s.weight_kg}kg × ${s.reps}` : '空'}，`
        + `而任务卡 T6 写的是 62.5kg ——（上次 ${lastBench.weight_kg}kg × `
        + `${lastBench.reps.join('/')} 次，${lastBench.daysAgo} 天前）`);
    }
    const vol = normals(root)
      .filter((x) => x.exercise_id === EX.bench.id && x.completed_at >= root.exported_at - 7 * DAY)
      .reduce((a, x) => a + x.weight_kg * x.reps, 0);
    if (vol !== 1800) {
      problems.push(`近 7 天卧推总容量是 ${vol}kg，而任务卡 T4 的预期答案是 1800kg`
        + '（3 × 10 × 60）');
    }
  }
  return problems;
}

// ───────────────────────────────────────────────────────────────── 自检
function selftest() {
  const seed = JSON.parse(readFileSync(join(ROOT, 'seed/exercises.json'), 'utf8'));
  const list = seed.exercises ?? seed;
  const seedById = new Map(list.map((e) => [e.id, e]));
  const failures = [];
  const check = (name, ok, detail = '') => {
    if (!ok) failures.push(`${name}${detail ? `：${detail}` : ''}`);
  };

  const a = buildPreset('2026-10-01');
  const b = buildPreset('2026-10-01');
  check('同一个基准日两次生成完全一致（--check 的地基）', serialize(a.root) === serialize(b.root));
  check('换一个基准日则不同', serialize(buildPreset('2026-10-02').root) !== serialize(a.root));

  for (const day of ['2026-10-01', '2026-12-31', '2027-02-28', '2026-01-01']) {
    const p = invariants(buildPreset(day).root, seedById);
    check(`${day} 的不变量全过`, p.length === 0, p.join('；'));
  }

  check(`规模：${WEEKS} 周 × 每周 ${WEEK.length} 练 = ${WEEKS * WEEK.length} 次训练`,
    a.root.workouts.length === WEEKS * WEEK.length, `实际 ${a.root.workouts.length}`);
  check('有热身组（演示热身功能）', a.stats.warmups > 0, `实际 ${a.stats.warmups}`);
  check('★★ 真引擎对卧推算出 62.5kg（任务卡 T6 的原话）',
    (() => {
      const s = suggestNext({
        exercise: seedById.get(EX.bench.id),
        plan: DEFAULT_PLAN,
        lastSession: lastSessionOf(a.root, EX.bench.id),
      });
      return s && s.weight_kg === 62.5;
    })(), JSON.stringify(lastSessionOf(a.root, EX.bench.id)));
  check('今天轮到胸（否则建议卡不是卧推）', nextMuscleGroup(a.root, seedById) === 'chest',
    nextMuscleGroup(a.root, seedById));
  check('近 7 天 2 次训练（首页那句数字与现实一致）', weekWorkoutCount(a.root) === 2,
    `实际 ${weekWorkoutCount(a.root)}`);
  check('T4 的预期答案 1800kg（**只算近 7 天**，这正是 T4 问的"上周"）',
    normals(a.root)
      .filter((x) => x.exercise_id === EX.bench.id && x.completed_at >= a.root.exported_at - 7 * DAY)
      .reduce((acc, x) => acc + x.weight_kg * x.reps, 0) === 1800);
  check('重量随周递增（最近那一周最重）',
    weightFor(EX.bench, 0) === 60 && weightFor(EX.bench, 5) === 47.5,
    `${weightFor(EX.bench, 0)} → ${weightFor(EX.bench, 5)}`);
  check('哑铃步长是 2 不是 2.5（跟着种子走）',
    weightFor(EX.incline, 0) === 20 && weightFor(EX.incline, 5) === 10);
  check('浮点噪声被收掉（不会出 62.49999999999999）',
    String(weightFor(EX.bench, 1)) === '57.5' && String(weightFor(EX.rdl, 2)) === '57.5');

  // 形状：解析器要求这些字段（app/lib/features/profile/backup.dart::parseBackup）
  const first = a.root.workouts[0].sets[0];
  for (const k of ['id', 'exercise_id', 'set_index', 'reps', 'completed_at']) {
    check(`组的必填字段 ${k} 在（解析器缺了会跳过这一组）`, first[k] !== undefined);
  }
  check('顶层带 app/format/workouts（否则导入端直接判"不是备份"）',
    a.root.app === 'lianleme' && a.root.format === 2 && Array.isArray(a.root.workouts));
  check('exercise_names 覆盖用到的全部动作',
    Object.keys(a.root.exercise_names).length === Object.keys(EX).length);

  // 反向：把"最近一次训练"改成胸，今天就不再轮到胸 —— 证明这条断言真的在管事
  const tampered = buildPreset('2026-10-01').root;
  const latest = [...tampered.workouts].sort((x, y) => x.started_at - y.started_at).at(-1);
  latest.sets = latest.sets.map((s) => ({ ...s, exercise_id: EX.bench.id }));
  check('把最近一次训练改成胸 → 不变量必须报错（断言不是摆设）',
    invariants(tampered, seedById).some((p) => p.includes('而不是 chest')));

  if (failures.length) {
    console.error(`✗ 预置历史自检失败 ${failures.length} 项：`);
    for (const f of failures) console.error(`  · ${f}`);
    process.exit(1);
  }
  console.log(`✓ 自检通过：确定性 · 不变量（动作 id 存在 / 组 id 唯一 / 最新 3 天前 / 近 7 天 2 次）`
    + ` · **真引擎算出 62.5kg**（T6）· 今天轮到胸 · T4 答案 1800kg`
    + ` （${a.stats.workouts} 次训练 / ${a.stats.sets} 组，其中热身 ${a.stats.warmups} 组）`);
}

// ───────────────────────────────────────────────────────────────── 跑
const argv = process.argv.slice(2);
if (argv.includes('--selftest')) {
  selftest();
} else {
  const todayArg = argv.find((a) => a.startsWith('--today='));
  const wantWrite = argv.includes('--write');
  const wantCheck = argv.includes('--check');
  const path = join(ROOT, OUT);

  if (wantCheck) {
    let text;
    try {
      text = readFileSync(path, 'utf8');
    } catch {
      console.error(`✗ 读不到 ${OUT} —— 跑 node tool/preset-history.mjs --write 生成它`);
      process.exit(1);
    }
    let committed;
    try {
      committed = JSON.parse(text);
    } catch (e) {
      console.error(`✗ ${OUT} 不是合法 JSON：${e.message}`);
      process.exit(1);
    }
    const baseDate = isoDate(committed.exported_at);
    const fresh = serialize(buildPreset(baseDate).root);
    const seed = JSON.parse(readFileSync(join(ROOT, 'seed/exercises.json'), 'utf8'));
    const seedById = new Map((seed.exercises ?? seed).map((e) => [e.id, e]));
    const problems = invariants(committed, seedById);

    console.log('预置 6 周历史核对（用文件自己记录的基准日复现它）\n');
    console.log(`  基准日：${baseDate} · ${committed.workouts.length} 次训练 · `
      + `${committed.workouts.reduce((a, w) => a + w.sets.length, 0)} 组`);
    if (fresh !== text) {
      console.error('  \x1b[31m✗\x1b[0m 内容与生成器不一致 —— 手改过？'
        + '跑 node tool/preset-history.mjs --write 重新生成');
      process.exit(1);
    }
    if (problems.length) {
      for (const p of problems) console.error(`  \x1b[31m✗\x1b[0m ${p}`);
      process.exit(1);
    }
    const ageDays = Math.round((Date.now() - committed.exported_at) / DAY);
    if (ageDays > 21) {
      console.log(`  \x1b[33m!\x1b[0m 这份数据是 ${ageDays} 天前生成的 —— `
        + '跑测试前请重新 --write 一次，否则引擎会走"很久没练"分支');
    }
    console.log('\n✓ 与生成器逐字节一致，且不变量全过（含真引擎算出的 62.5kg）');
  } else if (todayArg) {
    const today = todayArg.slice('--today='.length);
    const { root, stats } = buildPreset(today);
    if (wantWrite) {
      mkdirSync(dirname(path), { recursive: true });
      writeFileSync(path, serialize(root));
      console.error(`已写入 ${OUT}（基准日 ${today} · ${stats.workouts} 次训练 · ${stats.sets} 组）`);
    } else {
      process.stdout.write(serialize(root));
    }
  } else if (wantWrite) {
    const today = isoDate(Date.now());
    const { root, stats } = buildPreset(today);
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, serialize(root));
    console.error(`已写入 ${OUT}（基准日 ${today} · ${stats.workouts} 次训练 · ${stats.sets} 组）`);
  } else {
    process.stdout.write(serialize(buildPreset(isoDate(Date.now())).root));
  }
}
