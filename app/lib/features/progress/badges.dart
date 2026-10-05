/// 练了么 · **成就徽章**（2026-10-05，新 VI 的「成就」那一屏）
///
/// **全部是算出来的，不落库** —— 和 `streak.dart` 同一条理由：存一份解锁状态，
/// 它就会和训练记录不一致（改历史、导入备份、跨时区、换设备恢复……），
/// 而"过期状态比没有状态更坏"是这个仓库的底线。
///
/// 代价也要说清楚：每次进成就页都要**把全部组记录过一遍**（O(n)）。
/// 以这个 App 的量级（一次训练 24 组、一年 300 次 ≈ 7200 条）这不是问题；
/// 真到了几万条，再考虑缓存 —— 但那时也该先把"历史"分页，而不是先存徽章。
///
/// 三档稀有度（VI 的稿子里就是三档）：普通 / 稀有 / 史诗。分档只影响徽章底色，
/// **判据本身不掺水**：史诗就是真的难。
library;

import '../../domain/models.dart';
import 'streak.dart';

/// 稀有度。分档只影响展示，不影响解锁判据。
enum BadgeTier { common, rare, epic }

String badgeTierLabel(BadgeTier t) => switch (t) {
      BadgeTier.common => '普通',
      BadgeTier.rare => '稀有',
      BadgeTier.epic => '史诗',
    };

/// 一枚徽章的定义 + 当前进度。
///
/// [current] / [target] 是给进度条用的 —— **未解锁的徽章也要能看出"还差多少"**，
/// 否则那一格只是一块灰，用户不知道自己离它多远。
class BadgeStatus {
  const BadgeStatus({
    required this.id,
    required this.name,
    required this.how,
    required this.tier,
    required this.current,
    required this.target,
    required this.unlocked,
  });

  final String id;
  final String name;

  /// 怎么拿到它（一句话，写在徽章下面）
  final String how;

  final BadgeTier tier;
  final int current;
  final int target;
  final bool unlocked;

  /// 0..1 的进度（已解锁恒为 1）
  double get progress =>
      unlocked ? 1 : (target <= 0 ? 0 : (current / target).clamp(0.0, 1.0));
}

/// 算全部徽章（含未解锁的）。
///
/// [now] 传进来是为了**可测**（"早鸟/夜猫"要用小时），不是为了让结果随当前时间漂 ——
/// 除此之外所有判据都只看训练记录本身。
List<BadgeStatus> badgeStatuses(List<SetRecord> sets, {DateTime? now}) {
  final DateTime today = now ?? DateTime.now();

  // ── 先把要用的数算一遍（一遍过，别在每个徽章里重扫） ──
  final Set<String> workouts = <String>{};
  final Set<String> exercises = <String>{};
  final Set<int> hours = <int>{};
  double totalVolume = 0;
  double bestSingleKg = 0;
  double bestWorkoutVolume = 0;
  int bestWorkoutSets = 0;
  final Map<String, double> volumeByWorkout = <String, double>{};
  final Map<String, int> setsByWorkout = <String, int>{};
  final Set<String> muscles = <String>{};

  for (final SetRecord s in sets) {
    workouts.add(s.workoutId);
    exercises.add(s.exerciseId);
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(s.completedAtMs);
    hours.add(t.hour);
    totalVolume += s.volume;
    final double? w = s.weightKg;
    if (w != null && w > bestSingleKg) bestSingleKg = w;
    volumeByWorkout[s.workoutId] = (volumeByWorkout[s.workoutId] ?? 0) + s.volume;
    setsByWorkout[s.workoutId] = (setsByWorkout[s.workoutId] ?? 0) + 1;
  }
  for (final double v in volumeByWorkout.values) {
    if (v > bestWorkoutVolume) bestWorkoutVolume = v;
  }
  for (final int n in setsByWorkout.values) {
    if (n > bestWorkoutSets) bestWorkoutSets = n;
  }

  final int streak = currentStreak(sets, today);
  final int workoutCount = workouts.length;

  BadgeStatus b(
    String id,
    String name,
    String how,
    BadgeTier tier,
    int current,
    int target,
  ) =>
      BadgeStatus(
        id: id,
        name: name,
        how: how,
        tier: tier,
        current: current,
        target: target,
        unlocked: current >= target,
      );

  return <BadgeStatus>[
    // ── 普通 ──
    b('first_workout', '首训', '完成第 1 次训练', BadgeTier.common, workoutCount, 1),
    b('ten_workouts', '练满 10 次', '累计完成 10 次训练', BadgeTier.common, workoutCount, 10),
    b('five_ton', '单次 5 吨', '单次训练总容量到 5,000 kg', BadgeTier.common,
        bestWorkoutVolume.floor(), 5000),
    b('twenty_exercises', '二十个动作', '练过 20 个不同动作', BadgeTier.common,
        exercises.length, 20),
    b('twenty_sets', '一口气 20 组', '单次训练记满 20 组', BadgeTier.common,
        bestWorkoutSets, 20),
    b('early_bird', '早鸟', '早上 7 点前练过', BadgeTier.common,
        hours.any((int h) => h < 7) ? 1 : 0, 1),
    b('night_owl', '夜猫', '晚上 22 点后练过', BadgeTier.common,
        hours.any((int h) => h >= 22) ? 1 : 0, 1),

    // ── 稀有 ──
    b('week_streak', '一周不断', '连续打卡 7 天', BadgeTier.rare, streak, 7),
    b('hundred_kg', '百公斤俱乐部', '任一动作单组 ≥ 100 kg', BadgeTier.rare,
        bestSingleKg.floor(), 100),
    b('ten_ton', '单次 10 吨', '单次训练总容量到 10,000 kg', BadgeTier.rare,
        bestWorkoutVolume.floor(), 10000),

    // ── 史诗 ──
    b('month_streak', '月度铁人', '连续打卡 30 天', BadgeTier.epic, streak, 30),
    b('hundred_workouts', '百次训练', '累计完成 100 次训练', BadgeTier.epic, workoutCount, 100),
    b('hundred_ton', '累计 100 吨', '累计容量到 100,000 kg', BadgeTier.epic,
        totalVolume.floor(), 100000),
  ];
}

/// 已解锁几枚 / 一共几枚。成就页顶部那一行用它。
({int unlocked, int total}) badgeTally(List<BadgeStatus> list) => (
      unlocked: list.where((BadgeStatus b) => b.unlocked).length,
      total: list.length,
    );
