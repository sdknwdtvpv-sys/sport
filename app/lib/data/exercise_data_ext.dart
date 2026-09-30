/// 练了么 · `ExerciseData` 上两个 JSON 文本列的读取
///
/// drift 表里 `aliases` 与 `secondaryMuscles` 存的是 **JSON 数组字符串**
/// （`'["bp","卧推"]'`），不是列表 —— 因为 SQLite 没有数组类型，
/// 而这两列又只是一串标签，单开一张关联表不划算。
///
/// 之前没有任何界面用到它们（搜索是拿 `LIKE` 直接在字符串上匹配的），
/// 动作详情页是第一个消费者，所以把"怎么读"收在这里一处，
/// 而不是在每个界面里各写一遍 `jsonDecode` + try。
///
/// **坏了就当空**：这两列只是展示用的标签，解析失败不该让详情页打不开 ——
/// 用户点进来是为了看"这个动作怎么做"，那是一定要能看到的。
library;

import 'dart:convert';

import 'db.dart' show ExerciseData;

extension ExerciseDataLists on ExerciseData {
  /// 别名（"也叫：bp / 卧推"）。解析不出来就是空列表。
  List<String> get aliasList => _jsonList(aliases);

  /// 辅助肌群。同上。
  List<String> get secondaryMuscleList => _jsonList(secondaryMuscles);
}

List<String> _jsonList(String raw) {
  final String s = raw.trim();
  if (s.isEmpty || s == '[]') return const <String>[];
  try {
    final Object? decoded = jsonDecode(s);
    if (decoded is! List) return const <String>[];
    return decoded
        .whereType<String>()
        .map((String e) => e.trim())
        .where((String e) => e.isNotEmpty)
        .toList();
  } catch (_) {
    // 手改过库、或老数据里存了别的格式 —— 当作没有别名，不抛
    return const <String>[];
  }
}
