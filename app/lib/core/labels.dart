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
};

/// 查不到就原样返回 —— 宁可显示英文 key，也不要显示空白
String muscleLabel(String key) => kMuscleLabels[key] ?? key;

String equipmentLabel(String key) => kEquipmentLabels[key] ?? key;
