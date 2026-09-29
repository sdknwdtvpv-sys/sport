/// 练了么 · 展示用标签
///
/// 与 `seed/exercises.json` 顶层的 `muscle_groups` / `equipment` 对应。
/// 之所以在客户端内置一份而不是从资源里读：只有 11 个条目，
/// 为它把 metadata 穿过仓库、规划器、页面三层不值得。
/// 真源仍然是 `seed/parts/00-header.json`。
library;

const Map<String, String> kMuscleLabels = <String, String>{
  'chest': '胸',
  'back': '背',
  'legs': '腿',
  'shoulders': '肩',
  'arms': '手臂',
  'core': '核心',
};

const Map<String, String> kEquipmentLabels = <String, String>{
  'barbell': '杠铃',
  'dumbbell': '哑铃',
  'machine': '器械',
  'cable': '绳索',
  'bodyweight': '自重',
  'band': '弹力带',
  'kettlebell': '壶铃',
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
String muscleLabel(String key) => kMuscleLabels[key] ?? key;

String equipmentLabel(String key) => kEquipmentLabels[key] ?? key;

String categoryLabel(String key) => kCategoryLabels[key] ?? key;
