#!/usr/bin/env node
/**
 * 练了么 · 从上游补库（生成 `seed/parts/04-from-upstream.json`）
 *
 * **做的是什么**：把上游 `bryllim/workout-guide` 里我们还没有的动作补进动作库。
 * 上游给得出英文名 / 动作类型 / 器械 / 肌群；**给不出中文名** ——
 * 所以中文名与别名由人写在 `seed/upstream-zh-names.json`，本脚本只把其余字段**按规则推导**。
 *
 * 字段推导规则（都写在下面代码里，可复核）：
 *   id                 ← 上游 slug（`exercise-goblet-squat` → `ex_goblet_squat`）
 *   muscle_group       ← 上游 primaryMuscle 映射到我们的 6 值
 *   secondary_muscles  ← 上游 secondaryMuscles，经同义词表映射；与主肌群相同则丢弃
 *   equipment          ← 上游 16 值映射到我们的 7 值（单杠/墙/毛巾/门框/箱/凳/椅/瑞士球 → 自重）
 *   track_type         ← 上游 exerciseType（duration → time、bodyweight_reps → reps_only…）
 *   default_rest_sec   ← 复合 120 / 孤立 90 / 核心 60 / 自重与时长 60
 *   default_weight_kg  ← 按器械给新手起点（杠铃 20 / 哑铃 8 / 器械 20 / 绳索 10 / 壶铃 12）
 *   weight_increment   ← 按器械（与 seed/build.mjs 的期望一致）
 *   popularity         ← 统一 20（"补库、未人工排过"档），见下方注释
 *
 * **不补的五类**（每一类都在报告里点名 + 数数，不静默丢）：
 *   1. 有氧机（`equipment = Cardio`）—— 跑步机/划船机/椭圆机…，我们库是**力量组**的库，
 *      而且引擎只有 `distance_time` 的词表、没有它的推进规则
 *   2. 按时长的体能动作（`duration` 且上游次肌群带 `Cardio`）—— 开合跳/高抬腿/平板开合跳…
 *      同一把尺子：上游自己标了 Cardio 的就不进力量库
 *      （⚠️ 只对 `duration` 生效 —— 壶铃摆荡 / 波比跳的次肌群里也有 Cardio，但它们是力量动作）
 *   3. 拉伸（`isStretch = true`）—— 拉伸是产品里的**另一个功能**（我们没有热身/放松流程），
 *      混进动作库的后果是「今天练什么」会推荐「门框胸部拉伸 × 3 组」
 *   4. 与我们已有动作**语义重复**的 —— 列在中文名表的 `skip` 里
 *   5. 已有对应（精确同名或人工确认过）的
 *
 * 用法：
 *   node tool/add-upstream-exercises.mjs           # 生成 seed/parts/04-from-upstream.json
 *   node tool/add-upstream-exercises.mjs --check   # 只查有没有漂移（verify.sh 第 1 层会跑）
 *
 * 退出码：--check 且输出不一致 → 1；有上游动作既没名字也没说明为什么不补 → 1
 */

import { readFileSync, writeFileSync, existsSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = join(ROOT, 'seed/parts/04-from-upstream.json');
const checkOnly = process.argv.includes('--check');

const snapshot = JSON.parse(readFileSync(join(ROOT, 'seed/upstream-workout-guide.json'), 'utf8'));
const upstream = snapshot.exercises;
const zh = JSON.parse(readFileSync(join(ROOT, 'seed/upstream-zh-names.json'), 'utf8')).names;
const confirmed = JSON.parse(readFileSync(join(ROOT, 'seed/upstream-confirmed.json'), 'utf8'));

/**
 * "我们已有什么" —— **只能读手工维护的 parts（01/02/03），不能读 build 出来的
 * `seed/exercises.json`**。
 *
 * 踩过的坑：一开始读的是 `seed/exercises.json`，而那个文件是 build.mjs 把
 * parts（含本脚本产出的 04）合并出来的 —— 于是第二轮跑就成了自证：
 * "04 里的动作在 exercises.json 里都有 → 没有要补的 → 输出 0 个"，
 * 把上一轮的成果**清空**。`--check` 也就永远不可能绿。
 * 真源是 parts 目录本身；04 是产物，读它等于读自己的输出。
 */
const partsDir = join(ROOT, 'seed/parts');
const ours = readdirSync(partsDir)
  .filter((f) => f.endsWith('.json'))
  // 00 是元数据（且形状是 [[k,v]]，不是动作对象）
  .filter((f) => !f.startsWith('00-'))
  // 04 是本脚本自己的产物 —— 排除掉才是真正的"上游之外的库"
  .filter((f) => f !== '04-from-upstream.json')
  .flatMap((f) => JSON.parse(readFileSync(join(partsDir, f), 'utf8')))
  .filter((e) => e && typeof e === 'object' && typeof e.id === 'string');

const TYPE_MAP = {
  weight_reps: 'weight_reps',
  bodyweight_reps: 'reps_only',
  duration: 'time',
  assisted_bodyweight: 'assisted_reps',
};
const GROUP_OF = {
  chest: 'chest', back: 'back', lats: 'back', upperback: 'back', lowerback: 'back',
  triceps: 'arms', biceps: 'arms', forearms: 'arms',
  shoulders: 'shoulders', reardelts: 'shoulders',
  core: 'core',
  // 上游的 Mobility **不是肌群**，是"活动度"这个类别，且这 4 条全是拉伸。
  // 以前把它映射成 core，于是「猫牛式」以核心动作的身份进了动作库 —— 那是编的。
  // 现在不映射：真的漏进来会在下面 problems 里报错。
  quads: 'legs', hamstrings: 'legs', glutes: 'legs', legs: 'legs', calves: 'legs',
  adductors: 'legs', hips: 'legs', posteriorchain: 'legs',
};
/** 上游 16 值器械 → 我们的 7 值。单杠/墙/毛巾/门框/箱/凳/椅/瑞士球都是**道具**，负载仍是自重。 */
const EQUIP_MAP = {
  barbell: 'barbell', dumbbell: 'dumbbell', machine: 'machine', cable: 'cable',
  bodyweight: 'bodyweight', resistanceband: 'band', kettlebell: 'kettlebell',
  pullupbar: 'bodyweight', wall: 'bodyweight', towel: 'bodyweight', doorway: 'bodyweight',
  box: 'bodyweight', bench: 'bodyweight', chair: 'bodyweight', stabilityball: 'bodyweight',
  plate: 'barbell', // 杠铃片属于杠铃家族
  // 注意：这里**没有** `cardio`。上游把有氧机的器械标成 Cardio，而我们在选动作时
  // 就按"有氧机不进力量库"排除掉了（见下面规则 1），所以走到这里就说明有漏网的，
  // 让它报错比给它编一个器械值诚实。
};
const MUSCLE_SYNONYM = {
  shoulders: 'front_delts', reardelts: 'rear_delts', upperback: 'upper_back',
  lowerback: 'lower_back', groin: 'adductors', legs: 'quads', back: 'lats',
  hips: 'glutes', // 上游的 Hips 我们细化成了 glutes / hip_flexors，取最近的一个
};
/** 我们的次肌群词表（读 00-header 的声明，不猜）。上游有、我们词表里没有的一律**丢弃**。 */
const header = JSON.parse(readFileSync(join(ROOT, 'seed/parts/00-header.json'), 'utf8'));
const ALLOWED_MUSCLES = new Set([
  ...Object.keys(header.fine_muscles ?? {}),
  ...Object.keys(header.muscle_groups ?? {}),
]);
const WEIGHT_BY_EQUIP = { barbell: 20, dumbbell: 8, machine: 20, cable: 10, kettlebell: 12 };
const INCREMENT_BY_EQUIP = { barbell: 2.5, dumbbell: 2, cable: 2.5, machine: 5, kettlebell: 4 };

const norm = (s) => String(s ?? '').toLowerCase().replace(/[^a-z0-9]/g, '');

/** 休息时长：跟着"这个动作有多费"走。 */
function restFor(trackType, group) {
  if (trackType !== 'weight_reps') return 60;
  if (group === 'core') return 60;
  if (group === 'legs' || group === 'back' || group === 'chest') return 120;
  return 90;
}

// ---------------------------------------------------------------- 选出要补的

const ourNamesEn = new Set(ours.map((o) => norm(o.name_en)));
const confirmedNames = new Set(Object.values(confirmed.confirmed));
const ourIds = new Set(ours.map((o) => o.id));

const skipped = [];   // {name, why}
const missing = [];   // 既没名字、也没说明为什么不补 —— 会直接报错

/**
 * 上游自己给出的"这不是力量动作"的标记。**用它的标记，不猜**（猜的那一版漏了 25 个）。
 * 返回理由字符串；不是力量动作就返回 null。
 */
function notStrengthReason(u) {
  if (norm(u.equipment) === 'cardio') {
    return '有氧机：器械就是 Cardio（跑步机/划船机/椭圆机…），我们库是力量组的库';
  }
  // ⚠️ 只对 duration 生效：壶铃摆荡 / 波比跳的次肌群里也有 Cardio，
  //    但它们是力量动作（weight_reps / bodyweight_reps），不能一起扫掉。
  if (u.exerciseType === 'duration'
      && u.secondaryMuscles.some((m) => norm(m) === 'cardio')) {
    return '按时长的体能动作：上游次肌群就标着 Cardio（开合跳/高抬腿/跳绳…）';
  }
  if (u.isStretch === true) {
    return '拉伸：产品里没有热身/放松流程，混进库里会被当成"某个部位的动作"推荐';
  }
  if (norm(u.primaryMuscle) === 'mobility') {
    return '活动度：上游的 Mobility 不是肌群，我们 6 个部位里没有它的位置';
  }
  return null;
}

const toAdd = [];

for (const u of upstream) {
  if (ourNamesEn.has(norm(u.name)) || confirmedNames.has(u.name)) continue; // 已有对应
  const entry = zh[u.name];
  if (entry?.skip) { skipped.push({ name: u.name, why: entry.skip, kind: 'human' }); continue; }
  const notStrength = notStrengthReason(u);
  if (notStrength) { skipped.push({ name: u.name, why: notStrength, kind: 'rule' }); continue; }
  if (u.exerciseType === 'distance_duration') {
    skipped.push({
      name: u.name,
      why: '有氧：引擎还没有 distance_time 的推进规则',
      kind: 'rule',
    });
    continue;
  }
  if (!entry?.name) { missing.push(u.name); continue; }
  toAdd.push({ u, entry });
}

if (missing.length) {
  console.error(`✗ 有 ${missing.length} 个上游动作既没中文名、也没说明为什么不补：`);
  for (const m of missing) console.error(`  · ${m}`);
  console.error('  在 seed/upstream-zh-names.json 里给它们起名，或写 skip 说明理由。');
  process.exit(1);
}

// 反向检查：中文名表里的条目有没有**用不上**的。
// 两类用不上：给被规则扫掉的动作用了名（说明作者不知道那条被扫了），
// 或者上游快照里根本没有这个名字（拼错了）。死配置会让人以为库里真有这个动作。
{
  const added = new Set(toAdd.map(({ u }) => u.name));
  const skippedNames = new Set(skipped.map((s) => s.name));
  const upstreamNames = new Set(upstream.map((u) => u.name));
  const dead = Object.keys(zh).filter(
    (k) => !added.has(k) && !skippedNames.has(k) && upstreamNames.has(k),
  );
  if (dead.length) {
    console.warn(`⚠ 中文名表里有 ${dead.length} 条用不上（这些动作已被规则排除）：`);
    console.warn('  ' + dead.join('、'));
    console.warn('  要么删掉它们，要么改规则把它放进来 —— 留着会让人以为库里真有。');
  }
  const typo = Object.keys(zh).filter((k) => !upstreamNames.has(k));
  if (typo.length) {
    console.error(`✗ 中文名表里有 ${typo.length} 个名字在上游快照里找不到（拼错了？）：`);
    for (const t of typo) console.error(`  · ${t}`);
    process.exit(1);
  }
}

// ---------------------------------------------------------------- 推字段

const items = [];
const problems = [];
const droppedMuscles = [];
for (const { u, entry } of toAdd) {
  const id = `ex_${u.id.replace(/^exercise-/, '').replace(/-/g, '_')}`;
  if (ourIds.has(id)) problems.push(`${u.name}：生成的 id「${id}」与已有动作冲突`);
  const group = GROUP_OF[norm(u.primaryMuscle)];
  if (!group) problems.push(`${u.name}：上游 primaryMuscle「${u.primaryMuscle}」映射不到我们的 6 值部位`);
  const equipment = EQUIP_MAP[norm(u.equipment)];
  if (!equipment) problems.push(`${u.name}：上游 equipment「${u.equipment}」映射不到我们的器械值`);
  const trackType = TYPE_MAP[u.exerciseType];
  if (!trackType) problems.push(`${u.name}：上游 exerciseType「${u.exerciseType}」映射不到 track_type`);
  if (group && equipment && trackType) {
    const secondary = [];
    for (const m of u.secondaryMuscles) {
      const t = MUSCLE_SYNONYM[norm(m)] ?? norm(m);
      if (t === group || secondary.includes(t)) continue;
      // 上游会拿"非肌肉"当次肌群用：mobility（拉伸）、cardio（体能）——
      // 它们在我们的词表里没有位置，也不该有（次肌群是给肌群热力图用的）。
      // 直说丢掉了什么，比塞一个假肌肉进去诚实。
      if (!ALLOWED_MUSCLES.has(t)) {
        droppedMuscles.push({ exercise: u.name, muscle: t });
        continue;
      }
      secondary.push(t);
    }
    const isWeighted = equipment !== 'bodyweight' && equipment !== 'band';
    items.push({
      id,
      name: entry.name,
      name_en: u.name,
      aliases: entry.aliases ?? [],
      muscle_group: group,
      secondary_muscles: secondary,
      equipment,
      track_type: trackType,
      default_rest_sec: restFor(trackType, group),
      default_weight_kg: isWeighted ? WEIGHT_BY_EQUIP[equipment] : null,
      weight_increment: isWeighted ? INCREMENT_BY_EQUIP[equipment] : 0,
      is_builtin: 1,
      // 统一 20：它们是**补库、还没人工排过常用度**的动作。
      //
      // 后果要说准（以前这里写的是"不会挤进「今天练什么」"，那只对默认路径成立）：
      // 「今天练什么」走 `repo.search(muscleGroup: g, limit: count)`，SQL 是
      // `ORDER BY popularity DESC, name ASC`，所以
      //   · 默认 count=3 → 只要该部位有 3 个常用度更高的动作，它们就进不来 ✓
      //   · 但「换一批」用 limit=60 取回整组再跳过已推荐的 → 常用度排完就会轮到它们
      //   · 单元的 count=60（把整组都取回来）也会取到它们
      // 也就是说：**20 是"排在最后"，不是"永不出现"**。真要做到后者得引入
      // "是否进推荐池"的字段（S11 计划模板的活儿），不是靠一个数字。
      popularity: 20,
    });
  }
}
if (problems.length) {
  console.error('✗ 推导字段时发现问题：\n' + problems.map((p) => '  · ' + p).join('\n'));
  process.exit(1);
}

// 中文名不能与我们已有的重复（否则选择器里会出现两个同名动作）
const ourNamesZh = new Map(ours.map((o) => [o.name, o.id]));
const dupes = items.filter((i) => ourNamesZh.has(i.name));
if (dupes.length) {
  console.error('✗ 中文名与我们已有动作重复：');
  for (const d of dupes) console.error(`  · 「${d.name}」（${d.name_en}）与 ${ourNamesZh.get(d.name)} 重名`);
  console.error('  要么在 seed/upstream-zh-names.json 里改名，要么标 skip 说明它其实是同一个动作。');
  process.exit(1);
}
const seenZh = new Set();
for (const i of items) {
  if (seenZh.has(i.name)) {
    console.error(`✗ 本批内部中文名重复：「${i.name}」`);
    process.exit(1);
  }
  seenZh.add(i.name);
}

items.sort((a, b) => a.id.localeCompare(b.id));
const text = JSON.stringify(items, null, 2) + '\n';

if (checkOnly) {
  const old = existsSync(OUT) ? readFileSync(OUT, 'utf8') : '';
  if (old !== text) {
    console.error('✗ seed/parts/04-from-upstream.json 与上游快照/中文名表不一致，'
      + '跑 `node tool/add-upstream-exercises.mjs` 重新生成');
    process.exitCode = 1;
  } else {
    console.log(`✓ 补库文件与上游快照一致（${items.length} 个动作）`);
  }
} else {
  writeFileSync(OUT, text, 'utf8');
  console.log(`✓ 已生成 seed/parts/04-from-upstream.json：补 ${items.length} 个动作`);
  const byType = {};
  for (const i of items) byType[i.track_type] = (byType[i.track_type] ?? 0) + 1;
  console.log('  按类型：', JSON.stringify(byType));
  const byEq = {};
  for (const i of items) byEq[i.equipment] = (byEq[i.equipment] ?? 0) + 1;
  console.log('  按器械：', JSON.stringify(byEq));
  const dropTags = {};
  for (const d of droppedMuscles) dropTags[d.muscle] = (dropTags[d.muscle] ?? 0) + 1;
  if (Object.keys(dropTags).length) {
    console.log(`  丢弃的上游次肌群标签（我们词表里没有，也不该有）：`
      + Object.entries(dropTags).map(([k, v]) => `${k}×${v}`).join(' '));
  }
  console.log(`  不补的 ${skipped.length} 个：`);
  // 规则排除的按理由归堆 + **点名**（用户要能看见到底是哪些被扫掉了，
  // 不然"这一轮补了 153 个"是个没法复核的数字）；人工 skip 的逐条带理由列出来。
  const byRule = new Map();
  for (const s of skipped) {
    if (s.kind !== 'rule') continue;
    if (!byRule.has(s.why)) byRule.set(s.why, []);
    byRule.get(s.why).push(s.name);
  }
  for (const [why, names] of byRule) {
    console.log(`    · ${why} —— ${names.length} 个`);
    console.log(`      ${names.join('、')}`);
  }
  const humans = skipped.filter((s) => s.kind === 'human');
  if (humans.length) {
    console.log(`    · 人工在中文名表里标了 skip —— ${humans.length} 个`);
    for (const h of humans) console.log(`      ${h.name}：${h.why}`);
  }
}
