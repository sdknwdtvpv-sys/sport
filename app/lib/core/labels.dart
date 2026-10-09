/// 练了么 · 展示用标签
///
/// 与 `seed/exercises.json` 顶层的 `muscle_groups` / `equipment` 对应。
/// 之所以在客户端内置一份而不是从资源里读：只有 11 个条目，
/// 为它把 metadata 穿过仓库、规划器、页面三层不值得。
/// 真源仍然是 `seed/parts/00-header.json`。
library;

import 'dart:convert';

/// 部位标签。
///
/// 前 6 个是**主部位**（动作库的 `muscle_group` 只取这 6 个），
/// 后面的是**辅助肌群**（`secondary_muscles`）—— 它们是更细的解剖名。
///
/// ⚠️ 这两组都必须齐：2026-09-30 在真机上发现详情页显示的是
/// 「辅助：triceps、front_delts」—— 20 个 key 里 20 个没标签，直接漏出英文。
/// `labels_test.dart` 现在守着"种子里用到的每个 key 都有中文"。
const Map<String, String> kMuscleLabels = <String, String>{
  // 主部位
  'chest': '胸',
  'back': '背',
  'legs': '腿',
  'shoulders': '肩',
  'arms': '手臂',
  'core': '核心',
  // 跨库恢复出来的自定义动作**不知道**它练哪儿（备份里只存了 id→名字）。
  // 与其随便挑一个部位（那会是假话），不如给一个明说的"未分类" —— 它不会落进任何部位筛选，
  // 只在「全部」里出现。见 `ExerciseRepository.restoreFromBackup`。
  'unspecified': '未分类',
  // 辅助肌群（更细）
  'lats': '背阔肌',
  'upper_back': '上背',
  'lower_back': '下背',
  'traps': '斜方肌',
  'biceps': '肱二头',
  'triceps': '肱三头',
  'forearms': '前臂',
  'grip': '握力',
  'abs': '腹直肌',
  'obliques': '腹斜肌',
  'glutes': '臀',
  'quads': '股四头',
  'hamstrings': '腘绳肌',
  'calves': '小腿',
  'hip_flexors': '髂腰肌',
  'adductors': '大腿内收肌',
  'abductors': '臀中肌',
  'front_delts': '三角前束',
  'side_delts': '三角中束',
  'rear_delts': '三角后束',
};

const Map<String, String> kEquipmentLabels = <String, String>{
  'barbell': '杠铃',
  'dumbbell': '哑铃',
  'machine': '器械',
  'cable': '绳索',
  'bodyweight': '自重',
  'band': '弹力带',
  'kettlebell': '壶铃',
  // 同上：恢复出来的自定义动作不知道用什么器械
  'unspecified': '未分类',
};

/// 动作类别（`seed/exercises.json` 的 `category`）。
///
/// `strength` 不在筛选行里露出 —— "力量"是这个 App 的默认语境，
/// 给它一个 chip 只会让筛选行更长。热身与拉伸才是用户会主动找的。
const Map<String, String> kCategoryLabels = <String, String>{
  'strength': '力量',
  'warmup': '热身',
  'cardio': '有氧',
  'stretch': '拉伸',
};

/// 查不到就原样返回 —— 宁可显示英文 key，也不要显示空白
/// **可选的部位**（筛选、新建自定义动作都用它）—— 只有 6 个主部位。
///
/// ⚠️ **别把它换成 `kMuscleLabels.entries`**：那张表里后来加了 20 个
/// **只用于显示**的辅助肌群（背阔肌 / 肱三头 / 三角前束…）。
/// 2026-09-30 就是这么坏的 —— 给详情页补标签时顺手改了 `kMuscleLabels`，
/// 于是：
///   * 选动作页的「部位」筛选从 6 个 chips 变成 24 个
///   * 新建自定义动作页同样变成 24 个，把「器械」区挤出了懒加载范围
///     （`exercise_picker_test` 那条"新建 → 填表 → 保存"当场红了）
/// "显示用的标签"和"可以选的值"是两件事，表也就不该是同一张。
const List<String> kPrimaryMuscleGroups = <String>[
  'chest',
  'back',
  'legs',
  'shoulders',
  'arms',
  'core',
];

/// **细分标签的词表**（2026-10-09，10.9 清单第 7 条）。
///
/// 主部位只有 6 个，而用户嘴里说的是"今天练上胸"——选择器按部位筛只能筛到"胸"。
/// 这一张表是**选择器里那一行细分 chip 的数据源**（动作上存的是标签文本本身，
/// 见 `db.dart` 的 `exercise.sub_tags`）。
///
/// ⚠️ **它与 `seed/build.mjs` 里的 `SUB_TAGS` 必须一致**（那边是种子的校验词表，
/// 写进去的标签只要不属于自己主部位就会让构建失败）。两边不一致的后果是
/// "chip 点下去筛不到任何动作" —— 所以 `seed/build.mjs` 会拿这张表当参照做一次交叉检查。
const Map<String, List<String>> kSubTagsByMuscle = <String, List<String>>{
  'chest': <String>['上胸', '下胸', '中缝'],
  'back': <String>['背阔', '上背', '下背', '斜方'],
  'shoulders': <String>['前束', '中束', '后束'],
  'arms': <String>['肱二头', '肱三头', '前臂'],
  'legs': <String>['股四头', '腘绳', '臀', '小腿', '内收'],
  'core': <String>['上腹', '下腹', '侧腹'],
};

/// 某个主部位有哪些细分标签（没有就空列表）。
List<String> subTagsFor(String muscleGroup) =>
    kSubTagsByMuscle[muscleGroup] ?? const <String>[];

/// 把动作上那一列（JSON 数组文本）解成标签列表。坏数据一律当"没标过"。
List<String> decodeSubTags(String? raw) {
  if (raw == null || raw.isEmpty || raw == '[]') return const <String>[];
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List) return const <String>[];
    return <String>[
      for (final Object? x in decoded)
        if (x is String && x.isNotEmpty) x,
    ];
  } catch (_) {
    // 手改过的库 / 半截数据：不要因为一个字段把整页搜动作搞崩
    return const <String>[];
  }
}

String muscleLabel(String key) => kMuscleLabels[key] ?? key;

String equipmentLabel(String key) => kEquipmentLabels[key] ?? key;

String categoryLabel(String key) => kCategoryLabels[key] ?? key;

/// **重量的口径**（2026-10-08 用户问出来的约定）。
///
/// 原话：「杠铃动作的重量是一个的还是两个的？计算容量的时候怎么算？」
/// —— 这是一个**从没在界面上写清过**的约定，只有种子数据里能推出来：
///
///   * **杠铃**：填**总重**（含杠铃杆）。证据：`杠铃卧推` 的起始建议是 40 kg
///     （= 20 kg 杆 + 两侧各 10 kg），**不是**"每边 40"（那相当于 100 kg，新手不可能）；
///   * **哑铃 / 壶铃**：填**单只**重量。证据：`哑铃卧推` 的起始建议是 12 kg/只；
///   * **容量**（`docs/data-model.md` 的算法）：`Σ 重量 × 次数`，用的就是**你填的那个数** ——
///     所以杠铃是"总重 × 次数"，哑铃是"单只 × 次数"（**没有乘 2**）。
///
/// ⚠️ 哑铃那一半是**已知口径**：两只一起举时真实负荷是两倍，容量因此偏小。
/// 这一条写在 `docs/data-model.md` 里，改它属于"改数据口径"（会动到历史 PR 与图表），
/// 要单独拍板 —— 见 `docs/plan-ux-2026-10-08.md` §二。
///
/// 返回空串表示"这个器械没有单边/总重的歧义"（器械 / 绳索 / 自重 / 弹力带）。
String weightBasisLabel(String equipment) => switch (equipment) {
      'barbell' => '总重（含杠铃杆）',
      'dumbbell' || 'kettlebell' => '单只',
      _ => '',
    };

/// 容量那句口径（只在"有歧义"的器械上显示）。
///
/// ⚠️ 这一句是**给用户看的**，所以里面不许出现 markdown 记号（`**` 那种）——
/// `tool/check-user-text.mjs` 会当场判红。文档里那句可以带格式，界面这句不行。
String volumeBasisLabel(String equipment) {
  final String basis = weightBasisLabel(equipment);
  if (basis.isEmpty) return '';
  return '容量 = 重量 × 次数，按$basis算';
}
