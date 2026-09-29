#!/usr/bin/env node
/**
 * 练了么 · 动作库构建脚本
 *
 *   用法：node seed/build.mjs
 *
 * 作用：
 *   1. 合并 seed/parts/*.json（00 为元数据，其余为动作数组）
 *   2. 校验：字段完整性、id/名称唯一、枚举合法性、加重步长与起始重量的一致性
 *   3. 输出 seed/exercises.json（每行一个动作，便于 diff）
 *   4. 输出 seed/exercises.sql（可直接喂给 SQLite，字段与 docs/data-model.md 一致）
 *
 * 任何校验失败都会以非 0 退出码结束，不产生输出文件。
 */
import { readFileSync, writeFileSync, readdirSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = dirname(fileURLToPath(import.meta.url));
const PARTS = join(ROOT, 'parts');

/** 固定时间戳（2026-01-01T00:00:00Z），保证种子数据可复现 */
const SEED_TS = 1767225600000;

// 主部位：6 个粗粒度分组，驱动「部位轮转」与容量分布
const MUSCLE_GROUPS = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core'];

// 次要部位：细粒度词汇，用于肌群热力图与恢复建议。
// 允许比主部位更细（卧推主部位 chest，次要 triceps / front_delts），
// 但不该比主部位更粗——写 'arms' 没有信息量。
const FINE_MUSCLES = [
  'triceps', 'biceps', 'forearms',
  'lats', 'traps', 'lower_back',
  'front_delts', 'side_delts', 'rear_delts',
  'quads', 'hamstrings', 'glutes', 'calves', 'adductors', 'abductors',
  'abs', 'obliques', 'hip_flexors',
  // 2026-09-29 按上游补的三个（上游用它们，我们的词表里没有）：
  //   chest       —— 大肌群也会出现在"次要"位置（负重双杠、倒立撑、前平举）
  //   upper_back  —— 我们原来只有 lats/traps，装不下"上背"这个整体
  //   grip        —— 硬拉、悬垂类动作的握力
  'chest', 'upper_back', 'grip',
];
const SECONDARY_OK = new Set([...MUSCLE_GROUPS, ...FINE_MUSCLES]);
// 2026-09-29 按上游补两个：弹力带与壶铃都是**独立器械**，
// 硬塞进 dumbbell 会直接写成错数据（上游有 19 个弹力带动作）。
const EQUIPMENT = ['barbell', 'dumbbell', 'machine', 'cable', 'bodyweight', 'band', 'kettlebell'];
// 怎么记这个动作（docs/data-model.md）。time/weight_time 的数字是**秒**不是次数。
// 这两个值是 2026-09-29 按上游 exerciseType 补齐的：
//   distance_time   ← 上游 distance_duration（有氧：跑/走/骑行/划船…）
//   assisted_reps   ← 上游 assisted_bodyweight（辅助引体之类，"重量"是助力）
// 动作类别：**决定它会不会进「今天练什么」的推荐**（推荐只从 strength 里挑）。
//   2026-09-29 新增。热身与拉伸上一轮被整类排除在库外，理由是"会被当成某个部位的动作推荐" ——
//   理由对、解法错：正确解法是给它们一个类别，让推荐按类别过滤，而不是让库里没有它们。
const CATEGORIES = ['strength', 'warmup', 'cardio', 'stretch'];
const TRACK_TYPES = [
  'weight_reps', 'reps_only', 'time', 'weight_time', 'distance_time', 'assisted_reps',
];
const REST_MIN = 30;
const REST_MAX = 300;

// ---------- 1. 合并 ----------

const files = readdirSync(PARTS).filter((f) => f.endsWith('.json')).sort();
let meta = {};
const exercises = [];

for (const f of files) {
  const data = JSON.parse(readFileSync(join(PARTS, f), 'utf8'));
  if (Array.isArray(data)) {
    exercises.push(...data);
  } else {
    const { exercises: _ignored, ...rest } = data;
    meta = { ...meta, ...rest };
  }
}

// ---------- 2. 校验 ----------

const errors = [];
const warnings = [];
const seenId = new Map();
const seenName = new Map();

for (const [i, e] of exercises.entries()) {
  const at = `#${i + 1} ${e.id ?? '(缺 id)'}`;

  for (const k of ['id', 'name', 'muscle_group', 'equipment', 'category', 'track_type', 'default_rest_sec', 'weight_increment', 'popularity']) {
    if (e[k] === undefined || e[k] === null) errors.push(`${at}：缺少必填字段 ${k}`);
  }
  if (seenId.has(e.id)) errors.push(`${at}：id 重复，与「${seenId.get(e.id)}」冲突`);
  else seenId.set(e.id, e.name);
  if (seenName.has(e.name)) errors.push(`${at}：名称重复，与 ${seenName.get(e.name)} 冲突`);
  else seenName.set(e.name, e.id);

  if (!MUSCLE_GROUPS.includes(e.muscle_group)) errors.push(`${at}：muscle_group 非法「${e.muscle_group}」`);
  if (!EQUIPMENT.includes(e.equipment)) errors.push(`${at}：equipment 非法「${e.equipment}」`);
  // track_type 以前只校验"字段存在"，值写错也照样过。它现在真的会改变行为
  // （time/weight_time 的数字是**秒**，引擎会走加秒数分支），所以必须卡住。
  if (!TRACK_TYPES.includes(e.track_type)) errors.push(`${at}：track_type 非法「${e.track_type}」`);
  if (!CATEGORIES.includes(e.category)) errors.push(`${at}：category 非法「${e.category}」`);
  // 热身 / 有氧 / 拉伸都不是"力量组"：它们按秒记、没有重量。
  // 写成 weight_reps + 步长 2.5 的后果很具体 —— 引擎会给「站姿股四头肌拉伸」建议加重。
  if (e.category !== 'strength') {
    if (e.track_type !== 'time') {
      errors.push(`${at}：${e.category} 必须按秒记（track_type=time），当前是 ${e.track_type}`);
    }
    if (e.weight_increment !== 0 || e.default_weight_kg !== null) {
      errors.push(`${at}：${e.category} 不该有重量（weight_increment=${e.weight_increment}, `
        + `default_weight_kg=${e.default_weight_kg}）`);
    }
  }
  if (e.track_type === 'weight_time' && e.weight_increment === 0) {
    errors.push(`${at}：weight_time 必须是有重量的动作（weight_increment 不能为 0）`);
  }
  // distance_time 目前**只有词表、没有引擎支持**：有氧的推进规则（配速/距离/时长）
  // 还没设计，引擎会把它当成次数动作去推 —— 所以这里直接报错，
  // 而不是等它在真机上说出"跑步再加 8 次"这种话。
  if (e.track_type === 'distance_time') {
    errors.push(`${at}：distance_time 只保留词表，暂不支持写进种子`
      + `（要加有氧，先把引擎的推进规则补齐）`);
  }
  if (e.track_type === 'assisted_reps') {
    warnings.push(`${at}：assisted_reps 的推进方向还没实现对 —— `
      + `引擎现在按负重推进，等于"加重 = 加助力 = 更轻松"。见 docs/data-model.md 的已知限制`);
  }
  for (const m of e.secondary_muscles ?? []) {
    if (!SECONDARY_OK.has(m)) errors.push(`${at}：secondary_muscles 非法「${m}」`);
    if (m === e.muscle_group) warnings.push(`${at}：次要部位与主部位重复（${m}）`);
  }
  if (typeof e.name_en !== 'string' || !e.name_en) errors.push(`${at}：缺少 name_en`);
  if (!Array.isArray(e.aliases)) errors.push(`${at}：aliases 必须是数组`);

  const rest = e.default_rest_sec;
  if (!Number.isFinite(rest) || rest < REST_MIN || rest > REST_MAX) {
    errors.push(`${at}：default_rest_sec=${rest} 超出 ${REST_MIN}-${REST_MAX}`);
  }

  // 核心不变量：加重步长为 0 ⟺ 没有起始重量（自重动作），规则引擎据此切到"加次数"推进
  const inc = e.weight_increment;
  const bodyweightMode = inc === 0;
  if (bodyweightMode !== (e.default_weight_kg === null)) {
    errors.push(`${at}：weight_increment=0 必须与 default_weight_kg=null 同时出现（当前 inc=${inc}, weight=${e.default_weight_kg}）`);
  }
  if (!Number.isFinite(inc) || inc < 0) errors.push(`${at}：weight_increment 必须 >= 0`);

  const EQUIPMENT_INCREMENT = { barbell: 2.5, dumbbell: 2, cable: 2.5, machine: 5, kettlebell: 4 };
  const expect = EQUIPMENT_INCREMENT[e.equipment];
  if (!bodyweightMode && expect !== undefined && inc !== expect) {
    warnings.push(`${at}：${e.equipment} 的加重步长通常为 ${expect}，当前为 ${inc}`);
  }
  if (!bodyweightMode && e.default_weight_kg <= 0) errors.push(`${at}：default_weight_kg 必须为正数或 null`);
}

if (errors.length) {
  console.error(`✗ 校验失败，共 ${errors.length} 处错误：\n` + errors.map((s) => '  · ' + s).join('\n'));
  process.exit(1);
}

// ---------- 3. 输出 exercises.json ----------

const out = { ...meta, count: exercises.length };
const head = JSON.stringify(out, null, 2).slice(0, JSON.stringify(out, null, 2).lastIndexOf('}')).replace(/\s*$/, '');
const body = exercises.map((e) => '    ' + JSON.stringify(e)).join(',\n');
const json = `${head},\n  "exercises": [\n${body}\n  ]\n}\n`;
writeFileSync(join(ROOT, 'exercises.json'), json, 'utf8');

// ---------- 4. 输出 exercises.sql ----------

const q = (v) => (v === null || v === undefined ? 'NULL' : `'${String(v).replace(/'/g, "''")}'`);
const qn = (v) => (v === null || v === undefined ? 'NULL' : String(v));

const COLS = [
  'id', 'name', 'name_en', 'aliases', 'muscle_group', 'secondary_muscles', 'equipment',
  'category', 'track_type', 'default_rest_sec', 'default_weight_kg', 'weight_increment',
  'is_builtin', 'popularity', 'created_at', 'updated_at', 'deleted_at',
];

const rowOf = (e) =>
  '  (' +
  [
    q(e.id), q(e.name), q(e.name_en),
    q(JSON.stringify(e.aliases ?? [])),
    q(e.muscle_group),
    q(JSON.stringify(e.secondary_muscles ?? [])),
    q(e.equipment), q(e.category), q(e.track_type),
    qn(e.default_rest_sec), qn(e.default_weight_kg), qn(e.weight_increment), qn(e.is_builtin ?? 1),
    qn(e.popularity), qn(SEED_TS), qn(SEED_TS), 'NULL',
  ].join(', ') +
  ')';

const CHUNK = 20;
const stmts = [];
for (let i = 0; i < exercises.length; i += CHUNK) {
  const rows = exercises.slice(i, i + CHUNK).map(rowOf).join(',\n');
  stmts.push(`INSERT INTO exercise\n  (${COLS.join(', ')})\nVALUES\n${rows};`);
}

const sql = `-- 练了么 · 内置动作库种子数据（自动生成，请勿手改）
-- 修改请编辑 seed/parts/*.json 后重新运行：node seed/build.mjs
-- 动作总数：${exercises.length}
-- 生成时间戳：${SEED_TS}（固定值，保证可复现）

BEGIN TRANSACTION;

-- 幂等：只清理内置动作，用户自定义动作（is_builtin = 0）与其历史记录不受影响
DELETE FROM exercise WHERE is_builtin = 1;

${stmts.join('\n\n')}

COMMIT;

-- 自检：执行后应各返回 ${exercises.length}
--   SELECT COUNT(*) FROM exercise WHERE is_builtin = 1;
--   SELECT muscle_group, COUNT(*) FROM exercise WHERE is_builtin = 1 GROUP BY muscle_group;
`;
writeFileSync(join(ROOT, 'exercises.sql'), sql, 'utf8');

// ---------- 5. 同步一份到 app/assets/ ----------
// Flutter 只能打包**包目录内**的资源，而动作库的唯一真源是 seed/parts/*.json。
// 所以在这里生成，避免同一份数据两处维护。
// 产物提交进仓库（App 构建不需要 node），由 CI 的 contracts job 校验它与 parts 一致
// —— 跟 exercises.sql 是同一套做法。
const assetDir = join(ROOT, '..', 'app', 'assets');
mkdirSync(assetDir, { recursive: true });
writeFileSync(join(assetDir, 'exercises.json'), json, 'utf8');

// ---------- 6. 摘要 ----------

const byGroup = {};
const byEquip = {};
for (const e of exercises) {
  byGroup[e.muscle_group] = (byGroup[e.muscle_group] ?? 0) + 1;
  byEquip[e.equipment] = (byEquip[e.equipment] ?? 0) + 1;
}
const label = (g) => meta.muscle_groups?.[g] ?? g;
const elabel = (g) => meta.equipment?.[g] ?? g;

console.log(`✓ 动作库构建完成：${exercises.length} 个动作，${new Set(exercises.map((e) => e.name)).size} 个唯一名称`);
console.log('  按部位：' + MUSCLE_GROUPS.map((g) => `${label(g)} ${byGroup[g] ?? 0}`).join(' · '));
console.log('  按器械：' + EQUIPMENT.map((g) => `${elabel(g)} ${byEquip[g] ?? 0}`).join(' · '));
console.log('  自重动作（走"加次数"推进）：' + exercises.filter((e) => e.weight_increment === 0).length);
const byCat = {};
for (const e of exercises) byCat[e.category] = (byCat[e.category] ?? 0) + 1;
console.log('  按类别：' + CATEGORIES.map((c) => `${c} ${byCat[c] ?? 0}`).join(' · ')
  + '（只有 strength 会进「今天练什么」）');
if (warnings.length) {
  console.log(`\n⚠ ${warnings.length} 条提示：\n` + warnings.map((s) => '  · ' + s).join('\n'));
}
console.log('\n  已写入 seed/exercises.json、seed/exercises.sql、app/assets/exercises.json');
