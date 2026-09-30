/// 练了么 · 展示用标签
///
/// 与 `seed/exercises.json` 顶层的 `muscle_groups` / `equipment` 对应。
/// 之所以在客户端内置一份而不是从资源里读：只有 11 个条目，
/// 为它把 metadata 穿过仓库、规划器、页面三层不值得。
/// 真源仍然是 `seed/parts/00-header.json`。
library;

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

String muscleLabel(String key) => kMuscleLabels[key] ?? key;

String equipmentLabel(String key) => kEquipmentLabels[key] ?? key;

String categoryLabel(String key) => kCategoryLabels[key] ?? key;
