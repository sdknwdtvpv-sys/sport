/// 练了么 · **等级 Lv**（2026-10-05，新 VI 的「我」页头部）
///
/// 和连续打卡、徽章同一条规矩：**算出来的，不落库**。存一个 `level` 列，
/// 它就会在改历史 / 导入备份 / 换设备恢复之后和训练记录不一致 ——
/// 而"过期状态比没有状态更坏"是这个仓库的底线。
///
/// 判据只有**训练次数**一件事，理由：
///   * 容量受动作影响太大（深蹲一次 5 吨、卷腹一次 0.3 吨），拿它当等级会让
///     "练什么"比"练多久"更决定等级；
///   * 次数是用户自己一眼能数出来的数 —— 等级要让人觉得**可解释**，
///     不然它就只是个随机的数字。
///
/// ⚠️ **门槛表是产品决定，不是物理常数**（看 `_thresholds`）。改它 = 改每个人看到的等级，
/// 所以只留这一处。名字里带"铁人/传说"这种词是刻意的：等级要有画面感才有人追。
library;

/// 一级的门槛（训练次数）与称号。
///
/// 为什么这么排：前几级密（新手要**很快**尝到升级）、后面越来越疏
/// （老手的一次升级应该是几个月的坚持，不是两周）。
const List<({int at, String title})> kLevelThresholds = <({int at, String title})>[
  (at: 0, title: '新手上路'),
  (at: 5, title: '开始上道'),
  (at: 15, title: '稳定期'),
  (at: 30, title: '习惯养成'),
  (at: 60, title: '力量进阶者'),
  (at: 120, title: '老铁'),
  (at: 250, title: '铁人'),
  (at: 500, title: '传说'),
];

/// 等级信息：当前几级、称号、距离下一级还差多少。
class LevelInfo {
  const LevelInfo({
    required this.level,
    required this.title,
    required this.workouts,
    required this.nextAt,
  });

  /// 从 1 开始（Lv.1）
  final int level;
  final String title;

  /// 累计训练次数（算出来的那个数）
  final int workouts;

  /// 下一级的门槛；**已经到顶时为 null**（不是 0，也不是自己）
  final int? nextAt;

  /// 已到顶
  bool get isMax => nextAt == null;

  /// 距离下一级还差几次
  int get toNext => nextAt == null ? 0 : nextAt! - workouts;

  /// 当前级别内的进度 0..1（到顶恒为 1）
  double get progress {
    if (nextAt == null) return 1;
    final int base = kLevelThresholds[level - 1].at;
    final int span = nextAt! - base;
    if (span <= 0) return 1;
    return ((workouts - base) / span).clamp(0.0, 1.0);
  }
}

/// 按累计训练次数算等级。
LevelInfo levelFor(int workouts) {
  final int n = workouts < 0 ? 0 : workouts;
  int idx = 0;
  for (int i = 0; i < kLevelThresholds.length; i++) {
    if (n >= kLevelThresholds[i].at) idx = i;
  }
  final bool max = idx == kLevelThresholds.length - 1;
  return LevelInfo(
    level: idx + 1,
    title: kLevelThresholds[idx].title,
    workouts: n,
    nextAt: max ? null : kLevelThresholds[idx + 1].at,
  );
}

/// 「Lv.5 · 力量进阶者」。
String levelLabel(LevelInfo info) => 'Lv.${info.level} · ${info.title}';

/// 一行说明（到顶时不说"还差 0 次"）。
String levelHint(LevelInfo info) =>
    info.isMax ? '已经是最高等级' : '还差 ${info.toNext} 次训练升到 Lv.${info.level + 1}';
