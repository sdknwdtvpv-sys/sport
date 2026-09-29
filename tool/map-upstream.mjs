#!/usr/bin/env node
/**
 * 练了么 · 上游动作库映射（生成 `docs/exercise-mapping.md`）
 *
 * **它解决什么**：我们的种子有 318 个动作（165 手工 + 153 补库），上游 `bryllim/workout-guide` 有 302 个。
 * 名字能精确对上的只有 85 个 —— 剩下的 80 个里，大部分只是**命名习惯不同**。
 * 这份表给**人**逐条复核用：工具只给候选与相似度，**不下结论**
 * （`Romanian Deadlift` 与 `Deadlift` 名字极近但是两个动作，自动接受等于往动作库里灌错数据）。
 *
 * 人工复核的结论落在 `seed/upstream-confirmed.json`（来自 `docs/exercise-mapping-review.md`）：
 * 本工具消费它，把"已确认"移出待办、把"否掉"连同理由留档，
 * 并把**两件仍需决策的事**算出来摆在最后：
 *   1. 上游提到、我们词表里根本没有的次肌群标签（要扩词表才能补）
 *   2. 主肌群归类与上游不一致的动作（改它会改变"今天练什么"的部位轮转）
 *
 * 用法：
 *   node tool/map-upstream.mjs            # 重新生成 docs/exercise-mapping.md
 *   node tool/map-upstream.mjs --check    # 只查有没有漂移，不写文件（verify.sh 第 1 层会跑）
 *
 * 输入：seed/upstream-workout-guide.json（上游元数据快照，MIT，不含插画）
 *       seed/exercises.json（我们的种子，构建产物）
 *       seed/upstream-confirmed.json（人工复核结论）
 *
 * 退出码：--check 且输出与磁盘不一致 → 1
 */

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = join(ROOT, 'docs/exercise-mapping.md');
const checkOnly = process.argv.includes('--check');

const snapshot = JSON.parse(readFileSync(join(ROOT, 'seed/upstream-workout-guide.json'), 'utf8'));
const upstream = snapshot.exercises;
const ours = JSON.parse(readFileSync(join(ROOT, 'seed/exercises.json'), 'utf8')).exercises;
const review = JSON.parse(readFileSync(join(ROOT, 'seed/upstream-confirmed.json'), 'utf8'));
// 「按上游补了什么次肌群」由本工具自己算 —— 不另存一份 JSON：
// 孤儿数据文件没人管就会漂移，而这些事实完全可以从种子 + 上游快照重新算出来。

/** 上游 exerciseType → 我们的 track_type（本次工作的核心产出）。 */
const TYPE_MAP = {
  weight_reps: 'weight_reps',
  bodyweight_reps: 'reps_only',
  duration: 'time',
  distance_duration: 'distance_time',
  assisted_bodyweight: 'assisted_reps',
};
/** 上游次肌群 → 我们的同义标签（只列明确的同义，别的算"词表缺值"）。 */
const MUSCLE_SYNONYM = {
  shoulders: 'front_delts', reardelts: 'rear_delts', upperback: 'upper_back',
  lowerback: 'lower_back', groin: 'adductors', legs: 'quads', back: 'lats',
  // ⚠️ 这张表必须与 tool/add-upstream-exercises.mjs 的一致。
  // 少了 hips→glutes 的那一版会报出"假缺口"：我们明明给动作打了 glutes
  // （补库脚本按同义词转过了），映射表却只认 hips，于是这里说"词表里没有"。
  hips: 'glutes',
};
/** 上游 primaryMuscle → 我们的 6 值部位（用于查归类分歧）。 */
const GROUP_OF = {
  chest: 'chest', back: 'back', lats: 'back', upperback: 'back', lowerback: 'back',
  triceps: 'arms', biceps: 'arms', forearms: 'arms',
  shoulders: 'shoulders', reardelts: 'shoulders',
  core: 'core', mobility: 'core',
  quads: 'legs', hamstrings: 'legs', glutes: 'legs', legs: 'legs', calves: 'legs',
  adductors: 'legs', hips: 'legs', posteriorchain: 'legs',
};

const norm = (s) => String(s ?? '').toLowerCase().replace(/[^a-z0-9]/g, '');
const tokens = (s) => new Set(String(s ?? '').toLowerCase().replace(/[^a-z0-9 ]/g, ' ').split(' ').filter(Boolean));
function jaccard(a, b) {
  const A = tokens(a), B = tokens(b);
  if (!A.size && !B.size) return 0;
  let inter = 0;
  for (const t of A) if (B.has(t)) inter++;
  return inter / (A.size + B.size - inter);
}

// ---------------------------------------------------------------- 分类
//
// 一条硬规矩：复核文件里写的 id / 上游名必须真实存在。
// 写错一个字母就静静什么都不发生，是这类"人写的数据文件"最常见的失败方式。

const byUpstreamName = new Map(upstream.map((u) => [u.name, u]));
const byId = new Map(ours.map((o) => [o.id, o]));
const problems = [];
for (const [id, name] of Object.entries(review.confirmed)) {
  if (!byId.has(id)) problems.push(`confirmed 里的 \`${id}\` 在种子里不存在`);
  if (!byUpstreamName.has(name)) problems.push(`confirmed 里 ${id} 指向的上游动作「${name}」不存在`);
}
for (const [id, v] of Object.entries(review.rejected)) {
  if (!byId.has(id)) problems.push(`rejected 里的 \`${id}\` 在种子里不存在`);
  if (!byUpstreamName.has(v.upstream)) problems.push(`rejected 里 ${id} 的上游动作「${v.upstream}」不存在`);
}
if (problems.length) {
  console.error('✗ 复核结论引用了不存在的东西：\n' + problems.map((p) => '  · ' + p).join('\n'));
  process.exit(1);
}

const exactByNorm = new Map(upstream.map((u) => [norm(u.name), u]));

/**
 * 我们的次肌群词表 —— **读 `00-header.json` 的声明，而不是"哪些标签被用过"**。
 * 两者不等价：刚声明、还没用上的标签（本次扩的 chest/upper_back/grip）如果按"被用过"算，
 * 就会得出"词表里没有它"的荒谬结论，于是永远补不上（踩过这个死循环）。
 */
const header = JSON.parse(readFileSync(join(ROOT, 'seed/parts/00-header.json'), 'utf8'));
const ourSecondaryVocab = new Set([
  ...Object.keys(header.fine_muscles ?? {}),
  ...Object.keys(header.muscle_groups ?? {}),
]);

const matchedExact = [];   // 英文名精确命中
const unmatched = [];      // 未命中
for (const o of ours) {
  const u = exactByNorm.get(norm(o.name_en));
  if (u) matchedExact.push({ o, u }); else unmatched.push(o);
}

/** 未命中里，相似度 ≥ 0.5 的候选（与复核文件的候选集合同口径）。 */
function candidatesFor(o) {
  return upstream
    .map((u) => ({ u, score: jaccard(o.name_en, u.name) }))
    .sort((a, b) => b.score - a.score || a.u.name.localeCompare(b.u.name))[0];
}
const candidates = unmatched
  .map((o) => ({ o, top: candidatesFor(o) }))
  .filter((c) => c.top.score >= 0.5);

const confirmedIds = Object.keys(review.confirmed);
const rejectedIds = Object.keys(review.rejected);
const pendingCandidates = candidates.filter(
  (c) => !confirmedIds.includes(c.o.id) && !rejectedIds.includes(c.o.id));

/** 全部"有上游对应"的动作：精确命中 + 人工确认。字段对照都基于这个集合。 */
const linked = [
  ...matchedExact,
  ...confirmedIds.map((id) => ({ o: byId.get(id), u: byUpstreamName.get(review.confirmed[id]) })),
];

/** 上游次肌群比我们多、且那个标签我们词表里已经有的部分（就是实际补上的那些）。 */
const secondaryAdds = {};
for (const { o, u } of linked) {
  const have = new Set(o.secondary_muscles.map(norm));
  const add = [];
  for (const m of u.secondaryMuscles) {
    const k = norm(m);
    const t = MUSCLE_SYNONYM[k] ?? k;
    if (have.has(k) || have.has(norm(t))) continue;
    if (t === o.muscle_group) continue;   // 与主肌群重复没有信息量（build.mjs 也会警告）
    if (ourSecondaryVocab.has(t) && !add.includes(t)) add.push(t);
  }
  if (add.length) secondaryAdds[o.id] = add;
}

const typeFixes = linked
  .map(({ o, u }) => ({ o, u, want: TYPE_MAP[u.exerciseType] }))
  .filter((f) => f.want !== f.o.track_type);

/** 主肌群归类分歧。**已拍板保留我们归类的**不算分歧（结论在 upstream-confirmed.json）。 */
const groupKept = review.primary_muscle_kept ?? {};
/** 热身/拉伸的归类分歧：**不影响部位轮转**（category 已把它们挡在推荐之外），
 *  所以不算"待拍板"，但要列出来给人复核。 */
const warmupStretchGroups = linked
  .map(({ o, u }) => ({ o, u, mapped: GROUP_OF[norm(u.primaryMuscle)] }))
  .filter((c) => c.o.category && c.o.category !== 'strength')
  .filter((c) => c.mapped !== c.o.muscle_group);
const groupConflicts = linked
  .map(({ o, u }) => ({ o, u, mapped: GROUP_OF[norm(u.primaryMuscle)] }))
  .filter((c) => c.mapped && c.mapped !== c.o.muscle_group)
  .filter((c) => (c.o.category ?? 'strength') === 'strength')
  .filter((c) => {
    if (!groupKept[c.o.id]) return true;
    // 留档的结论要真的还成立：上游改了 primaryMuscle、或我们改了归类，就该重新看一遍
    if (groupKept[c.o.id].ours !== c.o.muscle_group) return true;
    if (groupKept[c.o.id].upstream !== c.u.primaryMuscle) return true;
    return false;
  });

/** 上游提到、我们词表里没有的次肌群标签（要扩词表才能补）。**已拍板不扩的**不算待决策。 */
const vocabKept = review.vocab_not_extended ?? {};
const vocabGaps = new Map();
for (const { o, u } of linked) {
  const have = new Set(o.secondary_muscles.map(norm));
  for (const m of u.secondaryMuscles) {
    const k = norm(m);
    const t = MUSCLE_SYNONYM[k] ?? k;
    if (have.has(k) || have.has(norm(t))) continue;
    if (ourSecondaryVocab.has(t)) continue;
    if (vocabKept[t]) continue; // 已拍板：这个词表不扩
    if (!vocabGaps.has(t)) vocabGaps.set(t, []);
    vocabGaps.get(t).push(o.id);
  }
}

// ---------------------------------------------------------------- 生成

const L = [];
const P = (s = '') => L.push(s);

P('# 上游动作库映射（活文档）');
P('');
P('> **这不是结论，是一张给人过的候选表。** 工具只给候选与相似度；');
P('> `Romanian Deadlift` 与 `Deadlift` 名字极近但是两个动作 —— 自动接受这类猜测');
P('> 等于往动作库里灌错数据，而动作库是产品资产。');
P('>');
P('> **人工复核的结论已经落进 `seed/upstream-confirmed.json`**（复核过程见');
P(`> \`${review._review}\`），本文件由它驱动：已确认的移出待办、否掉的连理由留档。`);
P('>');
P(`> 由 \`node tool/map-upstream.mjs\` 生成。上游快照 = \`bryllim/workout-guide\` @`
  + ` \`${snapshot._provenance.commit.slice(0, 8)}\`（MIT，**不含插画**）。`);
P('');
P('## 总览');
P('');
P('| 项 | 数量 |');
P('|---|---|');
P(`| 我们的动作 | ${ours.length} |`);
P(`| 上游动作 | ${upstream.length} |`);
P(`| **有上游对应**（精确命中 ${matchedExact.length} + 人工确认 ${confirmedIds.length}） | **${linked.length}** |`);
P(`| 已复核：确认一致 | ${confirmedIds.length} |`);
P(`| 已复核：命名相近但动作不同 | ${rejectedIds.length} |`);
P(`| 待人工复核的候选（相似度 ≥ 0.5） | ${pendingCandidates.length} |`);
P(`| 未命中且相似度 < 0.5（自行维护） | ${unmatched.length - candidates.length} |`);
P(`| 上游有、我们没有 | ${upstream.length - linked.length} |`);
P('');
P(`## 一、有上游对应、但类型标错的动作${typeFixes.length ? '' : '（当前为空 ✅）'}`);
P('');
if (!typeFixes.length) {
  P('没有 —— 种子的 `track_type` 与上游逐条一致。（这条曾经有 26 处，2026-09-29 修完。）');
} else {
  P('| 我们的 id | 中文名 | 现在 | **应为** | 上游 exerciseType |');
  P('|---|---|---|---|---|');
  for (const f of typeFixes.sort((a, b) => a.want.localeCompare(b.want) || a.o.id.localeCompare(b.o.id))) {
    P(`| \`${f.o.id}\` | ${f.o.name} | \`${f.o.track_type}\` | **\`${f.want}\`** | \`${f.u.exerciseType}\` |`);
  }
}
P('');
P(`## 二、已复核确认（${confirmedIds.length} 个）：上游同一个动作，字段可借`);
P('');
P('| 我们的 id | 我们的英文名 | 上游动作 | 上游器械 | 相似度 | 按上游补了什么 |');
P('|---|---|---|---|---|---|');
for (const id of confirmedIds.sort()) {
  const o = byId.get(id);
  const u = byUpstreamName.get(review.confirmed[id]);
  const score = matchedExact.some((m) => m.o.id === id) ? '精确同名' : jaccard(o.name_en, u.name).toFixed(2);
  const gains = [];
  if (TYPE_MAP[u.exerciseType] !== o.track_type) gains.push(`\`track_type\` → \`${TYPE_MAP[u.exerciseType]}\``);
  if (u.equipment.toLowerCase() !== o.equipment) gains.push(`\`equipment\` → ${u.equipment}`);
  if (secondaryAdds[id]) gains.push(`次肌群 + ${secondaryAdds[id].map((m) => `\`${m}\``).join(' ')}`);
  P(`| \`${id}\` | ${o.name_en} | ${u.name} | ${u.equipment} | ${score} | ${gains.join('；') || '（已一致，无需补）'} |`);
}
P('');
P('> **绝大多数「已一致」是有意义的结论，不是空转**：它们的 `track_type` 与 `equipment`');
P('> 本来就对 —— 类型词表能表达的维度，在第 26 处修正时已经全部对齐。');
P('');
P(`## 三、已复核：命名相近但动作不同（${rejectedIds.length} 个，不再重新纠结）`);
P('');
P('| 我们的 id | 我们的英文名 | 曾被误指的上游动作 | 为什么不是同一个 |');
P('|---|---|---|---|');
for (const id of rejectedIds.sort()) {
  const o = byId.get(id);
  const v = review.rejected[id];
  P(`| \`${id}\` | ${o.name_en} | ${v.upstream} | ${v.reason} |`);
}
P('');
if (pendingCandidates.length) {
  P(`## 四、待人工复核的候选（${pendingCandidates.length} 个，相似度 ≥ 0.5）`);
  P('');
  P('| 我们的 id | 中文名 | 英文名 | 最相近的上游动作 | 相似度 | 上游类型 | 上游器械 |');
  P('|---|---|---|---|---|---|---|');
  for (const { o, top } of pendingCandidates.sort((a, b) => b.top.score - a.top.score)) {
    P(`| \`${o.id}\` | ${o.name} | ${o.name_en} | ${top.u.name} | ${top.score.toFixed(2)} | \`${top.u.exerciseType}\` | ${top.u.equipment} |`);
  }
  P('');
} else {
  P('## 四、待人工复核的候选：**已清空 ✅**');
  P('');
  P('相似度 ≥ 0.5 的候选已全部被复核过（确认或否掉）。');
  P('');
}
const groupKeptRows = Object.entries(groupKept);
const vocabKeptRows = Object.entries(vocabKept);
const stillPending = vocabGaps.size + groupConflicts.length;

P(`## 五、仍需人工拍板的事：${stillPending ? `**${stillPending} 项**` : '**已清空 ✅**'}`);
P('');
P(`### 5.1 上游提到、我们词表里没有的次肌群标签（${vocabGaps.size} 个标签）`);
P('');
if (!vocabGaps.size) {
  P('（无）');
} else {
  P(`这些标签上游在用、我们的 ${ourSecondaryVocab.size} 值词表里没有。**补它们要先决定扩不扩词表** ——`);
  P('扩了以后 `docs/data-model.md` 与 `app/lib/core/labels.dart` 都要跟着改。');
  P('');
  P('| 上游标签 | 涉及我们的动作数 | 例 |');
  P('|---|---|---|');
  for (const [label, ids] of [...vocabGaps.entries()].sort((a, b) => b[1].length - a[1].length)) {
    P(`| \`${label}\` | ${ids.length} | ${ids.slice(0, 4).map((i) => `\`${i}\``).join(' ')} |`);
  }
}
if (vocabKeptRows.length) {
  P('');
  P(`**已拍板不扩的（${vocabKeptRows.length} 个，结论留档）：**`);
  P('');
  for (const [label, v] of vocabKeptRows) {
    P(`- \`${label}\`（上游用在 ${v.count} 个动作上）—— ${v.reason}`);
  }
}
P('');
P(`### 5.2 主肌群归类与上游不一致（${groupConflicts.length} 个）`);
P('');
P('**改这些会改变"今天练什么"的部位轮转**（部位轮转按 `muscle_group` 走），所以是产品决策：');
P('');
if (!groupConflicts.length) {
  P('（无）');
} else {
  P('| 我们的 id | 我们 | 上游 primaryMuscle | 按映射会归到 |');
  P('|---|---|---|---|');
  for (const c of groupConflicts.sort((a, b) => a.o.id.localeCompare(b.o.id))) {
    P(`| \`${c.o.id}\` | ${c.o.muscle_group} | ${c.u.primaryMuscle} | ${c.mapped} |`);
  }
}
if (warmupStretchGroups.length) {
  P('');
  P(`**热身与拉伸的归类（${warmupStretchGroups.length} 个，不影响轮转，列出来供复核）：**`);
  P('');
  P('它们不参与"今天练哪个部位"的轮转（`category` 已经把推荐挡掉了），');
  P('所以归到哪一组都不改变推荐结果 —— 只影响按部位筛选时能不能找到。');
  P('逐条的中文名与归类写在 `seed/upstream-zh-names.json`。');
  P('');
  P('| 我们的 id | 我们 | 上游 primaryMuscle |');
  P('|---|---|---|');
  for (const c of warmupStretchGroups.sort((a, b) => a.o.id.localeCompare(b.o.id))) {
    P(`| \`${c.o.id}\` | ${c.o.muscle_group}（${c.o.category}） | ${c.u.primaryMuscle} |`);
  }
}
if (groupKeptRows.length) {
  P('');
  P(`**已拍板保留我们归类的（${groupKeptRows.length} 个，结论留档）：**`);
  P('');
  P('| 我们的 id | 我们 | 上游 primaryMuscle | 为什么不改 |');
  P('|---|---|---|---|');
  for (const [id, v] of groupKeptRows) {
    P(`| \`${id}\` | ${v.ours} | ${v.upstream} | ${v.reason} |`);
  }
}
P('');
const addTotal = Object.values(secondaryAdds).reduce((a, v) => a + v.length, 0);
P(`## 六、次肌群对齐情况（还差 ${Object.keys(secondaryAdds).length} 个动作 / ${addTotal} 个标签）`);
P('');
P('这是一份**实时差异**：上游 `secondaryMuscles` 列出、而我们没有的标签 ——');
P('只统计"我们词表里已经有、只是没打在这个动作上"的那部分（需要新词表的见 5.1）。');
P('');
if (!addTotal) {
  P('**当前为 0：已对齐。** 上游列出的次肌群，要么我们本来就有，要么是词表缺值（5.1）。');
  P('');
  P('> 2026-09-29 这一轮补了 51 个动作 / 59 个标签（**纯增量**，我们更细的标签如');
  P('> `front_delts` 一律保留），过程记在 `CHANGELOG.md`。之后每改种子都重新算一次，');
  P('> 有差异就会出现在下表里。');
} else {
  P('| 我们的 id | 还差 |');
  P('|---|---|');
}
for (const [id, ms] of Object.entries(secondaryAdds).sort()) {
  P(`| \`${id}\` | ${ms.map((m) => `\`${m}\``).join(' ')} |`);
}
P('');
P(`## 七、上游有、我们没有（可选补库）`);
P('');
const oursNames = new Set(ours.map((o) => norm(o.name_en)));
const onlyUpstream = upstream.filter((u) => !oursNames.has(norm(u.name)) && !Object.values(review.confirmed).includes(u.name));
const byType = new Map();
for (const u of onlyUpstream) {
  if (!byType.has(u.exerciseType)) byType.set(u.exerciseType, []);
  byType.get(u.exerciseType).push(u.name);
}
P('| 上游类型 | 数量 | 例 |');
P('|---|---|---|');
for (const [t, names] of [...byType.entries()].sort((a, b) => b[1].length - a[1].length)) {
  P(`| \`${t}\` | ${names.length} | ${names.slice(0, 6).join(', ')} |`);
}
const stretches = upstream.filter((u) => u.isStretch).map((u) => u.name);
P('');
P(`其中 **${stretches.length} 个是拉伸动作**（上游 \`isStretch: true\`）—— 我们种子里一个都没有：`);
P('');
P(`> ${stretches.join(', ')}`);
P('');
P('---');
P('');
P('## 八、改完之后怎么跑');
P('');
P('```bash');
P('node tool/map-upstream.mjs            # 改了种子或复核结论之后重新生成本文');
P('node tool/map-upstream.mjs --check    # verify.sh 第 1 层会跑：过期就红');
P('```');
P('');
P('复核结论写在 `seed/upstream-confirmed.json`：确认项进 `confirmed`，否掉项进 `rejected`（带理由）。');
P('写错 id 或上游名会**直接报错退出**，不会静静什么都不发生。');
P('');

const text = L.join('\n');

if (checkOnly) {
  const old = existsSync(OUT) ? readFileSync(OUT, 'utf8') : '';
  if (old !== text) {
    console.error('✗ docs/exercise-mapping.md 与当前种子/复核结论不一致，跑 `node tool/map-upstream.mjs` 重新生成');
    process.exitCode = 1;
  } else {
    console.log('✓ docs/exercise-mapping.md 与种子、复核结论一致');
  }
} else {
  writeFileSync(OUT, text, 'utf8');
  console.log('✓ 已生成 docs/exercise-mapping.md');
  console.log(`  有对应 ${linked.length}（精确 ${matchedExact.length} + 确认 ${confirmedIds.length}）`
    + ` / 已否掉 ${rejectedIds.length} / 待复核 ${pendingCandidates.length}`
    + ` / 类型待改 ${typeFixes.length} / 待决策：词表 ${vocabGaps.size} 项、主肌群 ${groupConflicts.length} 项`);
}
