#!/usr/bin/env node
/**
 * 练了么 · 上游动作库映射（生成 `docs/exercise-mapping.md`）
 *
 * **它解决什么**：我们的种子有 165 个动作，上游 `bryllim/workout-guide` 有 302 个。
 * 名字能精确对上的只有 85 个 —— 剩下的 80 个里，大部分只是**命名习惯不同**
 * （`Chest Press Machine` vs `Machine Chest Press`），少数是真的没有对应。
 * 这份表就是给**人**逐条复核用的：工具只给候选与相似度，**不下结论**。
 *
 * 为什么不下结论：`Romanian Deadlift` 和 `Deadlift` 名字极近，但是两个动作。
 * 自动接受这一类猜测，等于往动作库里灌错数据 —— 而动作库是产品资产。
 *
 * 用法：
 *   node tool/map-upstream.mjs            # 重新生成 docs/exercise-mapping.md
 *   node tool/map-upstream.mjs --check    # 只看有没有漂移，不写文件（CI 可跑）
 *
 * 输入：
 *   seed/upstream-workout-guide.json   —— 上游元数据快照（只留字段，不含插画）
 *   seed/exercises.json                —— 我们的种子（构建产物）
 *
 * 退出码：--check 且输出与磁盘不一致 → 1
 */

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = join(ROOT, 'docs/exercise-mapping.md');
const checkOnly = process.argv.includes('--check');

const upstream = JSON.parse(readFileSync(join(ROOT, 'seed/upstream-workout-guide.json'), 'utf8'));
const ours = JSON.parse(readFileSync(join(ROOT, 'seed/exercises.json'), 'utf8')).exercises;

/** 上游 exerciseType → 我们的 track_type（这套映射是本次工作的核心产出）。 */
const TYPE_MAP = {
  weight_reps: 'weight_reps',
  bodyweight_reps: 'reps_only',
  duration: 'time',
  distance_duration: 'distance_time',
  assisted_bodyweight: 'assisted_reps',
};

/** 只保留字母数字：`Chest Press Machine` → `chestpressmachine`。 */
const norm = (s) => String(s ?? '').toLowerCase().replace(/[^a-z0-9]/g, '');

/** 词集合的 Jaccard 相似度：给"命名习惯不同"的候选打分。 */
const tokens = (s) => new Set(String(s ?? '').toLowerCase().replace(/[^a-z0-9 ]/g, ' ').split(' ').filter(Boolean));
function jaccard(a, b) {
  const A = tokens(a), B = tokens(b);
  if (!A.size && !B.size) return 0;
  let inter = 0;
  for (const t of A) if (B.has(t)) inter++;
  return inter / (A.size + B.size - inter);
}

const byName = new Map();
for (const e of upstream.exercises) byName.set(norm(e.name), e);

// ---------------------------------------------------------------- 分类

const matched = [];       // 精确命中
const unmatched = [];     // 未命中
for (const o of ours) {
  const u = byName.get(norm(o.name_en));
  if (u) matched.push({ o, u });
  else unmatched.push(o);
}

/** 未命中里，为每个动作找相似度最高的上游候选（含分数）。 */
function candidatesFor(o) {
  const scored = upstream.exercises
    .map((u) => ({ u, score: jaccard(o.name_en, u.name) }))
    .sort((a, b) => b.score - a.score || a.u.name.localeCompare(b.u.name));
  return scored.slice(0, 3).filter((c) => c.score > 0);
}

const strong = [];   // ≥ 0.5：很可能只是命名习惯不同
const weak = [];     // < 0.5：很可能真的没有对应
for (const o of unmatched) {
  const top = candidatesFor(o)[0];
  if (top && top.score >= 0.5) strong.push({ o, top });
  else weak.push({ o, top });
}

const typeFixes = [];
for (const { o, u } of matched) {
  const want = TYPE_MAP[u.exerciseType];
  if (want !== o.track_type) typeFixes.push({ o, u, want });
}

// ---------------------------------------------------------------- 生成

const L = [];
L.push('# 上游动作库映射（待人工复核）');
L.push('');
L.push('> **这不是结论，是一张给人过的候选表。** 工具只给候选与相似度；');
L.push('> `Romanian Deadlift` 与 `Deadlift` 名字极近但是两个动作 —— 自动接受这类猜测');
L.push('> 等于往动作库里灌错数据，而动作库是产品资产。');
L.push('>');
L.push(`> 由 \`node tool/map-upstream.mjs\` 生成，输入是 \`seed/upstream-workout-guide.json\``);
L.push(`> （上游 \`bryllim/workout-guide\` @ \`${upstream._provenance.commit.slice(0, 8)}\` 的元数据快照，MIT，不含插画）。`);
L.push('');
L.push('## 总览');
L.push('');
L.push('| 项 | 数量 |');
L.push('|---|---|');
L.push(`| 我们的动作 | ${ours.length} |`);
L.push(`| 上游动作 | ${upstream.exercises.length} |`);
L.push(`| **英文名精确命中** | **${matched.length}**（${Math.round((matched.length / ours.length) * 100)}%） |`);
L.push(`| 未命中：疑似只是命名不同（相似度 ≥ 0.5） | ${strong.length} |`);
L.push(`| 未命中：疑似真的没有对应（< 0.5） | ${weak.length} |`);
L.push(`| 上游有、我们没有 | ${upstream.exercises.length - matched.length} |`);
L.push('');
L.push('## 一、已命中、但类型标错的动作（可直接改，有上游依据）');
L.push('');
if (!typeFixes.length) {
  L.push('（没有 —— 种子的 `track_type` 与上游一致）');
} else {
  L.push('| 我们的 id | 中文名 | 英文名 | 现在 | **应为** | 上游 exerciseType |');
  L.push('|---|---|---|---|---|---|');
  for (const f of typeFixes.sort((a, b) => a.want.localeCompare(b.want) || a.o.id.localeCompare(b.o.id))) {
    L.push(`| \`${f.o.id}\` | ${f.o.name} | ${f.o.name_en} | \`${f.o.track_type}\` | **\`${f.want}\`** | \`${f.u.exerciseType}\` |`);
  }
}
L.push('');
L.push('## 二、未命中：候选映射（相似度 ≥ 0.5，**待人工确认**）');
L.push('');
L.push('| 我们的 id | 中文名 | 英文名 | 最相近的上游动作 | 相似度 | 上游类型 | 上游器械 |');
L.push('|---|---|---|---|---|---|---|');
for (const { o, top } of strong.sort((a, b) => b.top.score - a.top.score || a.o.id.localeCompare(b.o.id))) {
  L.push(`| \`${o.id}\` | ${o.name} | ${o.name_en} | ${top.u.name} | ${top.score.toFixed(2)} | \`${top.u.exerciseType}\` | ${top.u.equipment} |`);
}
L.push('');
L.push('## 三、未命中且相似度低（< 0.5）—— 很可能上游真没有');
L.push('');
L.push('这些动作**我们自己维护**：上游没有对应，也就没有类型/器械/肌群可借。');
L.push('');
L.push('| 我们的 id | 中文名 | 英文名 | 最近的候选（若有） | 相似度 |');
L.push('|---|---|---|---|---|');
for (const { o, top } of weak.sort((a, b) => a.o.id.localeCompare(b.o.id))) {
  L.push(`| \`${o.id}\` | ${o.name} | ${o.name_en} | ${top ? top.u.name : '—'} | ${top ? top.score.toFixed(2) : '—'} |`);
}
L.push('');
L.push('## 四、上游有、我们没有（可选补库）');
L.push('');
const oursNames = new Set(ours.map((o) => norm(o.name_en)));
const onlyUpstream = upstream.exercises.filter((u) => !oursNames.has(norm(u.name)));
const byType = new Map();
for (const u of onlyUpstream) {
  if (!byType.has(u.exerciseType)) byType.set(u.exerciseType, []);
  byType.get(u.exerciseType).push(u.name);
}
L.push('| 上游类型 | 数量 | 例 |');
L.push('|---|---|---|');
for (const [t, names] of [...byType.entries()].sort((a, b) => b[1].length - a[1].length)) {
  L.push(`| \`${t}\` | ${names.length} | ${names.slice(0, 6).join(', ')} |`);
}
const stretches = upstream.exercises.filter((u) => u.isStretch).map((u) => u.name);
L.push('');
L.push(`其中 **${stretches.length} 个是拉伸动作**（上游 \`isStretch: true\`）—— 我们种子里一个都没有：`);
L.push('');
L.push(`> ${stretches.join(', ')}`);
L.push('');
L.push('---');
L.push('');
L.push('## 五、复核完之后怎么用');
L.push('');
L.push('1. **第一节**可以直接改种子（有上游依据，不需要人判断）：改 `seed/parts/*.json` 的 `track_type`。');
L.push('2. **第二节**逐行确认 → 确认后可以借上游的 `exerciseType` / `equipment` / `primaryMuscle` 补我们缺的字段；');
L.push('   不确认就留在表里，别猜。');
L.push('3. **第三节**说明这些动作得自己维护（上游帮不上）。');
L.push('4. **第四节**是"要不要补库"的产品决策：有氧与拉伸目前是整块空白。');
L.push('');

const text = L.join('\n');

if (checkOnly) {
  const old = existsSync(OUT) ? readFileSync(OUT, 'utf8') : '';
  if (old !== text) {
    console.error('✗ docs/exercise-mapping.md 与当前种子/上游快照不一致，跑 `node tool/map-upstream.mjs` 重新生成');
    process.exitCode = 1;
  } else {
    console.log('✓ docs/exercise-mapping.md 与种子一致');
  }
} else {
  writeFileSync(OUT, text, 'utf8');
  console.log(`✓ 已生成 docs/exercise-mapping.md`);
  console.log(`  命中 ${matched.length} / 待改类型 ${typeFixes.length} / 候选待确认 ${strong.length} / 疑似无对应 ${weak.length}`);
}
