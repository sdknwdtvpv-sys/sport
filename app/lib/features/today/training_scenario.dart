/// 练了么 · **在哪儿练**（2026-10-09，第二份 docx 第 4 条）
///
/// 用户原话：「计划里面，有些不在健身房练的。能否前置选择下在什么场景练，
/// 然后匹配对应的动作和计划」。
///
/// 现状（改之前）：`planToday` 只按**部位**挑动作，完全不看器械 ——
/// 于是常年在家练的人被排到「器械推胸」「绳索夹胸」，到了地方才发现做不了。
///
/// 这个文件是那条规则的**唯一出处**（纯数据 + 纯函数，有单测）：
/// 场景 → 允许的器械集合。挑选动作那条链（`ExerciseRepository.search` 的
/// `equipmentIn`）只认这个集合，不认识"场景"这个词 —— 于是将来加场景
/// 只是往这张表里加一行，不会牵动挑选逻辑。
library;

/// 三个场景。**默认是健身房** —— 老库升上来（`training_scenario` 为 null）时
/// 走的正是"全部器械"，与这一版之前的行为**逐条一致**（没有悄悄改老用户的东西）。
enum TrainingScenario {
  /// 器械齐全（默认）：与这一版之前完全一样。
  gym('gym', '健身房', '器械齐全，什么都能练'),

  /// 家里：一对哑铃 / 弹力带 / 壶铃 + 自重。**不含杠铃与器械** ——
  /// 家里有深蹲架的人会自己改成"健身房"，而把杠铃排给没杠铃的人是更常见的错。
  home('home', '家里', '哑铃 / 弹力带 / 壶铃 + 自重'),

  /// 徒手：出差、酒店、户外。只有自重动作。
  bodyweight('bodyweight', '徒手', '出差、户外：只用自重');

  const TrainingScenario(this.wire, this.label, this.hint);

  /// 落库用的字符串（`user_profile.training_scenario`）
  final String wire;

  /// 界面上那一格的字
  final String label;

  /// 点开时的一句说明（界面上做副标题/提示）
  final String hint;

  static TrainingScenario fromWire(String? w) => switch (w) {
        'home' => TrainingScenario.home,
        'bodyweight' => TrainingScenario.bodyweight,
        _ => TrainingScenario.gym,
      };

  /// 这个场景允许的器械（与 `seed/build.mjs` 的 `EQUIPMENT` 词表同一套字）。
  ///
  /// ⚠️ 与器械筛选（选择器里那一行 chip）是**同一条判据**：那边是用户当场挑一个器械，
  /// 这边是"这个场景下哪些器械算数"—— 两边都落到 `search(equipmentIn: …)`。
  Set<String> get equipment => switch (this) {
        TrainingScenario.gym => const <String>{
            'barbell',
            'dumbbell',
            'machine',
            'cable',
            'kettlebell',
            'band',
            'bodyweight',
          },
        TrainingScenario.home => const <String>{
            'dumbbell',
            'kettlebell',
            'band',
            'bodyweight',
          },
        TrainingScenario.bodyweight => const <String>{'bodyweight'},
      };
}
