/**
 * 练了么 · 动作的**细分标签**（2026-10-09，10.9 清单第 7 条）
 *
 * 规则只有一处（这个文件），两个地方用它：
 *   * `seed/build.mjs` —— 构建动作库时给每个动作打上、并**校验**；
 *   * `tool/add-upstream-exercises.mjs` —— 从上游补库时给新动作打上。
 *
 * 为什么必须共享而不是各写一份：`seed/parts/04-from-upstream.json` 是**生成物**
 * （由补库工具按上游快照重新生成），往那份文件里手写 `sub_tags` 会在下一次生成时
 * 被冲掉 —— 而"生成物与生成器不一致"在门禁里是硬红（`add-upstream-exercises --check`）。
 *
 * ## 三条纪律
 *   1. **只给 `category === 'strength'` 的动作打**（热身/拉伸谈"上胸"没有意义）；
 *   2. **每个标签必须属于它自己的主部位**（"上胸"不能出现在背的动作上）——
 *      筛出来错的东西比没有标签更糟；
 *   3. **宁可没有也不要猜**：规则匹配不到就留空。标签是内容债，
 *      覆盖率由 `seed/build.mjs` 每次构建打印出来。
 *
 * ## 规则怎么写的（可复核）
 *
 * 只看 **名字 + 别名 + 英文名**（`name` / `aliases` / `name_en`），**不看说明** ——
 * 说明是散文，拿它做分类会写出不可复现的规则（同一句话改个逗号，分类就变了）。
 * 每条规则都是一句"名字里真的出现了那个词"，例如 `上斜` → 上胸、`侧平举` → 中束。
 */

/** 词表：每个主部位允许哪些标签。**客户端的 chip 必须与它一致**（`app/lib/core/labels.dart`）。 */
export const SUB_TAGS = {
  chest: ['上胸', '下胸', '中缝'],
  back: ['背阔', '上背', '下背', '斜方'],
  shoulders: ['前束', '中束', '后束'],
  arms: ['肱二头', '肱三头', '前臂'],
  legs: ['股四头', '腘绳', '臀', '小腿', '内收'],
  core: ['上腹', '下腹', '侧腹'],
};

/**
 * 规则：`[正则, 标签, 限定主部位]`。**顺序有意义**（同一个动作命中多条时按顺序累加）。
 *
 * ⚠️ 改这里等于改数据：加一条规则会让一批动作换上标签，而标签参与搜索与筛选 ——
 * 改完请跑 `node seed/build.mjs` 看覆盖率与提示。
 */
export const SUB_TAG_RULES = [
  // 胸
  [/上斜|斜上|incline/i, '上胸', 'chest'],
  [/下斜|decline/i, '下胸', 'chest'],
  [/夹胸|飞鸟|蝴蝶|十字|绳索夹|pec.?deck|fly|crossover/i, '中缝', 'chest'],
  // 背
  [/引体|下拉|直臂|pullover|lat/i, '背阔', 'back'],
  [/划船|row/i, '背阔', 'back'],
  [/面拉|face.?pull|上背|高位划船|反向划船/i, '上背', 'back'],
  [/山羊|挺身|硬拉|俯身|下背|lower.?back|good.?morning|罗马椅/i, '下背', 'back'],
  [/耸肩|shrug|斜方/i, '斜方', 'back'],
  // 肩
  [/前平举|front.?raise|阿诺德|推举|press/i, '前束', 'shoulders'],
  [/侧平举|侧举|lateral.?raise|侧卧.*举/i, '中束', 'shoulders'],
  [/反向飞鸟|俯身飞鸟|后束|rear.?delt|面拉|face.?pull/i, '后束', 'shoulders'],
  // 手臂
  [/弯举|curl|锤式|集中弯举/i, '肱二头', 'arms'],
  [/臂屈伸|下压|窄距|三头|skull|kickback|俯身臂屈伸|pushdown/i, '肱三头', 'arms'],
  [/腕|握力|前臂|forearm|wrist/i, '前臂', 'arms'],
  // 腿
  [/深蹲|腿举|腿屈伸|箭步|蹲|squat|lunge|leg.?press|extension|哈克|hack/i, '股四头', 'legs'],
  [/腿弯举|腘绳|罗马尼亚|直腿硬拉|早安|hamstring|leg.?curl|rdl/i, '腘绳', 'legs'],
  [/臀|髋|hip|glute|蚌式|后踢|桥/i, '臀', 'legs'],
  [/提踵|小腿|calf/i, '小腿', 'legs'],
  [/内收|adduct/i, '内收', 'legs'],
  // 核心
  [/卷腹|仰卧起坐|crunch|sit.?up/i, '上腹', 'core'],
  [/举腿|悬垂|反向卷腹|leg.?raise|抬腿/i, '下腹', 'core'],
  [/侧屈|俄罗斯转体|侧平板|斜肌|oblique|twist|侧桥/i, '侧腹', 'core'],
];

/**
 * 人工修正：规则会看走眼的地方（key = 动作 id，value = 最终标签，`[]` 表示"确实不该有"）。
 *
 * 为什么留这个口子：规则只看名字，而有些名字里有词、动作其实不是那个意思
 * （或反过来）。**改这里比改规则安全** —— 一条规则改动会牵动一批动作，
 * 而这里是逐个动作点名。目前是空的（规则跑出来的 230/318 我抽查过一轮）。
 */
export const SUB_TAG_OVERRIDES = {
  // 例：'ex_xxx': ['上胸'],
};

/** 这个动作该有哪些细分标签（按规则算，再套人工修正）。 */
export function subTagsFor(exercise) {
  const id = exercise.id;
  if (Object.prototype.hasOwnProperty.call(SUB_TAG_OVERRIDES, id)) {
    return [...SUB_TAG_OVERRIDES[id]];
  }
  // 只给力量动作打标签
  if ((exercise.category ?? 'strength') !== 'strength') return [];
  const group = exercise.muscle_group;
  const allowed = SUB_TAGS[group] ?? [];
  const text = [
    exercise.name ?? '',
    (exercise.aliases ?? []).join(' '),
    exercise.name_en ?? '',
  ].join(' ').toLowerCase();

  const out = [];
  for (const [re, tag, only] of SUB_TAG_RULES) {
    if (only !== group) continue;
    if (out.includes(tag)) continue;
    if (re.test(text)) out.push(tag);
  }
  // 规则与词表不一致时**宁可丢掉**（校验会另外把这种情况判红，见 build.mjs）
  return out.filter((t) => allowed.includes(t));
}
