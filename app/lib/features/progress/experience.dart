/// 练了么 · **轻量等级 / 经验**（第二部分第 7 条，2026-10-06 用户拍板）
///
/// 「我」页一条进度：**总组数**映射一个长期等级。
///
/// ⚠️ 与 `level.dart` 的 Lv 是**两件事，刻意都留着**：
///   * `level.dart` 的 Lv 只看**训练次数**（"你练了多少次"），门槛密在前期 ——
///     新手要很快尝到升级；它回答的是"我还是新人吗"。
///   * 这里的经验看**总组数**（"你到底做了多少组"），门槛是等差/缓增的 ——
///     它回答的是"我累积了多少工作量"。
///   两条都算得出来、都不落库，而且都**不发任何可消费的东西**（第二条红线：
///   不发虚拟货币）。所以它叫"经验"，不叫"积分"——名字本身就该说清它不是货币。
///
/// 为什么不合并成一个等级：一个是"次数"，一个是"组数"，而这两个数在真实记录里
/// 会明显分叉（每次都练 30 组的人，组数涨得比次数快得多）。合并就得挑一个，
/// 而被丢掉的那个恰好是某类用户最在意的那个。
library;

/// 一级的门槛（**累计组数**）与称号。
///
/// 排法的理由：100 组 ≈ 一个新人的头几周；1000 组 ≈ 半年；3500 组 ≈ 一两年。
/// **缓增而不是陡增**：经验的作用是"一直看得见自己在涨"，陡增会让中段彻底没反馈。
const List<({int at, String title})> kExperienceThresholds =
    <({int at, String title})>[
  (at: 0, title: '起步'),
  (at: 100, title: '上量'),
  (at: 300, title: '打底'),
  (at: 600, title: '扎实'),
  (at: 1000, title: '千组'),
  (at: 1800, title: '稳厚'),
  (at: 3000, title: '三千组'),
  (at: 5000, title: '老手'),
  (at: 8000, title: '深水区'),
];

/// 经验信息：几级、称号、累计组数、下一级门槛。
class ExperienceInfo {
  const ExperienceInfo({
    required this.level,
    required this.title,
    required this.sets,
    required this.nextAt,
  });

  /// 从 1 开始（Lv.1）
  final int level;
  final String title;

  /// 累计组数（算出来的那个数）
  final int sets;

  /// 下一级的门槛；**到顶为 null**（不是 0，也不是自己）
  final int? nextAt;

  bool get isMax => nextAt == null;

  /// 距下一级还差几组
  int get toNext => nextAt == null ? 0 : nextAt! - sets;

  /// 当前级别内的进度 0..1（到顶恒为 1）
  double get progress {
    if (nextAt == null) return 1;
    final int base = kExperienceThresholds[level - 1].at;
    final int span = nextAt! - base;
    if (span <= 0) return 1;
    return ((sets - base) / span).clamp(0.0, 1.0);
  }
}

/// 按累计组数算经验等级。
ExperienceInfo experienceFor(int sets) {
  final int n = sets < 0 ? 0 : sets;
  int idx = 0;
  for (int i = 0; i < kExperienceThresholds.length; i++) {
    if (n >= kExperienceThresholds[i].at) idx = i;
  }
  final bool max = idx == kExperienceThresholds.length - 1;
  return ExperienceInfo(
    level: idx + 1,
    title: kExperienceThresholds[idx].title,
    sets: n,
    nextAt: max ? null : kExperienceThresholds[idx + 1].at,
  );
}

/// 卡片上那一行（"还差 N 组到<下一级>"；到顶就如实说到顶）。
String experienceHint(ExperienceInfo info) {
  if (info.isMax) return '累计 ${info.sets} 组 —— 已经是最高等级';
  return '还差 ${info.toNext} 组到「${kExperienceThresholds[info.level].title}」';
}
