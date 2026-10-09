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
import { SUB_TAGS, subTagsFor } from './sub-tags.mjs';
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
// 细分标签（2026-10-09，10.9 清单第 7 条「按肌群细分搜动作」）：
// **词表与规则都在 `seed/sub-tags.mjs`**（那边还解释了为什么必须共享 ——
// `04-from-upstream.json` 是生成物，手写进去的标签会被下一次生成冲掉）。
// 这里只负责"给每个动作打上 + 校验 + 打印覆盖率"。
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

// ---------- 1.5 细分标签：按规则打上（先打标，再校验）----------
//
// ⚠️ **不读 parts 文件里手写的 `sub_tags`**：04-from-upstream.json 是生成物，
// 手写的那一份会在下一次 `add-upstream-exercises.mjs` 生成时被冲掉，
// 于是"本地能过、CI 红"。规则是唯一来源，覆盖不到的地方留空（宁可没有也不猜）。
for (const e of exercises) {
  const tags = subTagsFor(e);
  if (tags.length > 0) e.sub_tags = tags;
  else delete e.sub_tags;
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
    // 热身/拉伸：time。有氧还有第二种诚实形态：distance_time（记距离）。
    const okTrack = e.category === 'cardio'
      ? (e.track_type === 'time' || e.track_type === 'distance_time')
      : e.track_type === 'time';
    if (!okTrack) {
      errors.push(`${at}：${e.category} 必须按秒或按距离记`
        + `（track_type=time${e.category === 'cardio' ? ' 或 distance_time' : ''}），`
        + `当前是 ${e.track_type}`);
    }
    if (e.weight_increment !== 0 || e.default_weight_kg !== null) {
      errors.push(`${at}：${e.category} 不该有重量（weight_increment=${e.weight_increment}, `
        + `default_weight_kg=${e.default_weight_kg}）`);
    }
  }
  if (e.track_type === 'weight_time' && e.weight_increment === 0) {
    errors.push(`${at}：weight_time 必须是有重量的动作（weight_increment 不能为 0）`);
  }
  // distance_time（跑步机/划船机/跳绳/农夫行走）现在是**支持的**：
  //   存储：set_record.distance_m；引擎：对它们**不给推进建议**（返回 null）。
  // 上一版这里是一条 error（"引擎还没有这个规则，别让它进库"）——
  // 那条规则守的是"不能对一次跑步说'再加 8 次'"，而那个位置现在由引擎的第 0.5 步守着
  // （见 engine/progression.mjs，有两条向量证明）。
  //
  // 但有一条**会让人困惑**的组合值得发警告：category=strength 的距离动作
  // （农夫行走）不会被「今天练什么」推荐 —— 推荐只会开"3 组 × 8–10 次 / 30–45 秒"，
  // 开不出"走 20 米"。不是错，是还没做距离处方。

  // 动作说明：null 是允许的（内容债，覆盖率工具会算），但**写了就得是能看的一行**。
  if (e.instructions !== undefined && e.instructions !== null) {
    if (typeof e.instructions !== 'string' || !e.instructions.trim()) {
      errors.push(`${at}：instructions 写了但为空 —— 要么别写，要么写成一句人话`);
    } else if (e.instructions.length > 80) {
      errors.push(`${at}：instructions 长 ${e.instructions.length} 字，超过 80`
        + `（选择器那一行放不下；要点不是教程）`);
    } else if (e.instructions !== e.instructions.trim()) {
      errors.push(`${at}：instructions 首尾有空白`);
    }
  }

  // 距离处方：`distance_time` 必须有"每组多少米"（否则处方开不出来，
  // 而引擎又不会替它编一个 —— 5 公里跑与 20 米农夫行走差两个数量级）。
  const targetDist = e.default_target_distance_m;
  if (e.track_type === 'distance_time') {
    if (!(targetDist > 0)) {
      errors.push(`${at}：distance_time 必须有 default_target_distance_m（每组多少米）`);
    }
  } else if (targetDist !== undefined && targetDist !== null) {
    errors.push(`${at}：只有 distance_time 才该有 default_target_distance_m`);
  }

  if (e.track_type === 'assisted_reps') {
    // 推进方向**已实现**（2026-09-29）：达标 → **减**助力，掉组 → 保持。
    // 但那条分支的前提是"助力确实是一个要记的量"：increment 为 0 会被引擎当成自重动作，
    // 于是用户看到的是「自重 × 8」而不是「助力 30kg × 8」—— 分支根本进不去。
    if (!(e.weight_increment > 0)) {
      errors.push(`${at}：assisted_reps 必须有助力步长（weight_increment > 0），`
        + `否则会被当成自重动作，"减助力"那条分支永远走不到`);
    }
  }
  for (const m of e.secondary_muscles ?? []) {
    if (!SECONDARY_OK.has(m)) errors.push(`${at}：secondary_muscles 非法「${m}」`);
    if (m === e.muscle_group) warnings.push(`${at}：次要部位与主部位重复（${m}）`);
  }
  // 细分标签：数组、非空、**必须属于这个动作的主部位**、不重复。
  const subTags = e.sub_tags;
  if (subTags !== undefined && subTags !== null) {
    if (!Array.isArray(subTags)) {
      errors.push(`${at}：sub_tags 必须是数组`);
    } else {
      const allowed = SUB_TAGS[e.muscle_group] ?? [];
      for (const t of subTags) {
        if (typeof t !== 'string' || !t.trim()) errors.push(`${at}：sub_tags 里有空值`);
        else if (!allowed.includes(t)) {
          errors.push(`${at}：sub_tags 里的「${t}」不属于 ${e.muscle_group}`
            + `（该部位的词表：${allowed.join(' / ')}）`);
        }
      }
      if (new Set(subTags).size !== subTags.length) errors.push(`${at}：sub_tags 有重复`);
      if (subTags.length > 0 && e.category !== 'strength') {
        errors.push(`${at}：${e.category} 类动作不该有 sub_tags（细分标签只给力量动作）`);
      }
    }
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

// ---------- 2.5 交叉检查：选择器那一行 chip 的词表要和这里一致 ----------
//
// 客户端把同一份词表写在 `app/lib/core/labels.dart` 的 `kSubTagsByMuscle` 里
// （选择器要用它画 chip）。两边不一致的后果很具体：chip 点下去**筛不到任何动作**，
// 而门禁全绿 —— 所以在这里当场把它抓住。
{
  const labelsPath = join(ROOT, '..', 'app', 'lib', 'core', 'labels.dart');
  let dart = '';
  try {
    dart = readFileSync(labelsPath, 'utf8');
  } catch (e) {
    warnings.push(`读不到 ${labelsPath}，跳过了细分标签的交叉检查`);
  }
  if (dart) {
    for (const [group, tags] of Object.entries(SUB_TAGS)) {
      for (const t of tags) {
        if (!dart.includes(`'${t}'`)) {
          errors.push(`细分标签「${t}」（${group}）在 seed/build.mjs 里有，`
            + `但 app/lib/core/labels.dart 的 kSubTagsByMuscle 里没有 —— `
            + '选择器会画不出这个 chip（两处必须一致）');
        }
      }
    }
  }
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
  'default_target_distance_m', 'instructions', 'sub_tags', 'is_builtin', 'popularity', 'created_at',
  'updated_at', 'deleted_at',
];

const rowOf = (e) =>
  '  (' +
  [
    q(e.id), q(e.name), q(e.name_en),
    q(JSON.stringify(e.aliases ?? [])),
    q(e.muscle_group),
    q(JSON.stringify(e.secondary_muscles ?? [])),
    q(e.equipment), q(e.category), q(e.track_type),
    qn(e.default_rest_sec), qn(e.default_weight_kg), qn(e.weight_increment),
    qn(e.default_target_distance_m ?? null), q(e.instructions ?? null),
    q(JSON.stringify(e.sub_tags ?? [])), qn(e.is_builtin ?? 1),
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
const strength = exercises.filter((e) => e.category === 'strength');
const tagged = strength.filter((e) => Array.isArray(e.sub_tags) && e.sub_tags.length > 0);
console.log(`  细分标签（上胸/中缝…）：${tagged.length}/${strength.length} 个力量动作有标签`
  + `（没有标签的动作只能在「部位」那一层被筛到）`);
if (warnings.length) {
  console.log(`\n⚠ ${warnings.length} 条提示：\n` + warnings.map((s) => '  · ' + s).join('\n'));
}
console.log('\n  已写入 seed/exercises.json、seed/exercises.sql、app/assets/exercises.json');
