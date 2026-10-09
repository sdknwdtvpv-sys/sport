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

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';
import 'streak.dart';

/// 稀有度。分档只影响展示，**不影响解锁判据**。
enum BadgeTier { common, rare, epic }

/// 徽章分类（成就页按它分组，与 `vi/achievement-badges.html` 的分组一致）。
enum BadgeCategory { streak, strength, explore, milestone }

String badgeCategoryLabel(BadgeCategory c) => switch (c) {
      BadgeCategory.streak => '连续打卡',
      BadgeCategory.strength => '力量突破',
      BadgeCategory.explore => '探索发现',
      BadgeCategory.milestone => '里程碑',
    };

/// 三档的颜色。**只新加了一个色**（稀有紫）：普通复用主色、传说复用破纪录的琥珀 ——
/// 否则同一套里会出现两个肉眼分不出的琥珀。
Color badgeTierColor(BadgeTier t) => switch (t) {
      BadgeTier.common => Tokens.accent,
      BadgeTier.rare => Tokens.tierRare,
      BadgeTier.epic => Tokens.pr,
    };

String badgeTierLabel(BadgeTier t) => switch (t) {
      BadgeTier.common => '普通',
      BadgeTier.rare => '稀有',
      BadgeTier.epic => '史诗',
    };

/// **一枚徽章自己的图标**（纯展示，2026-10-05 重绘时加的）。
///
/// 为什么按 `id` 而不是按 `category`：分类只有四个，一组里几枚徽章就会拿到同一个
/// 图形 —— 那正是这次要修的问题（"所有徽章长得一模一样，只有名字和颜色不同"）。
/// `id` 唯一，一枚一个图形；`badges_test.dart` 已经钉了"id 不重复"。
///
/// 兜底给的是一个**中性问号**，不是某个含义明确的图标：新加徽章忘了配图形时，
/// 页面不会崩，也不会假装自己有一枚专属图形（这个仓库最防的就是"看不出来的假话"）。
/// ⚠️ 兜底**必须是任何真徽章都没用到的那个图形**：早先兜底是 `military_tech`，
/// 后来它被"一年不断"拿去当真图形了 —— 于是"有没有人漏配"这件事就再也测不出来
/// （漏配和真配长得一模一样）。`badge_visuals_test.dart` 现在按**未知 id** 取兜底。
///
/// **2026-10-06 扩到 73 枚时定的规矩**（不然这一张表会失控）：
///   * 每条线**只从自己的图标组里取** —— 组内不许重复（`badge_visuals_test.dart` 钉着），
///     跨类的重复允许（一次训练里看不到两条线同时铺满，而"每类内部不撞"才是用户真看得见的）；
///   * **语义优先于省事**：图标要和徽章说的是同一件事（"单次 20 吨"用卡车、"百次训练"用奖章）；
///   * 新加的徽章**必须在下面显式写一行** —— 走兜底就是漏配，测试会红。
IconData badgeIcon(String id) => switch (id) {
      // ── 连续打卡（20 枚）──
      'first_workout' => Icons.local_fire_department,
      'three_day_streak' => Icons.calendar_today,
      'week_streak' => Icons.calendar_month,
      'two_week_streak' => Icons.date_range,
      'month_streak' => Icons.emoji_events,
      'two_month_streak' => Icons.outdoor_grill,
      'hundred_day_streak' => Icons.workspace_premium,
      'year_streak' => Icons.military_tech,
      'comeback' => Icons.replay_circle_filled,
      'early_bird' => Icons.wb_twilight,
      'night_owl' => Icons.nightlight_round,
      'weekend_warrior' => Icons.beach_access,
      'full_week' => Icons.view_week,
      'active_week' => Icons.stacked_bar_chart,
      'short_session' => Icons.timer_outlined,
      'long_session' => Icons.hourglass_bottom,
      'marathon_session' => Icons.timelapse,
      'iron_month' => Icons.calendar_view_month,
      'three_month_iron' => Icons.event_note,
      'four_week_streak' => Icons.sync_alt,
      // ── 力量突破（20 枚）──
      'five_ton' => Icons.fitness_center,
      'ten_ton' => Icons.local_shipping,
      'twenty_ton' => Icons.fire_truck,
      'fifty_ton' => Icons.terrain,
      'hundred_kg' => Icons.monitor_weight,
      'two_hundred_kg' => Icons.scale,
      'ten_ton_total' => Icons.straighten,
      'fifty_ton_total' => Icons.agriculture,
      'hundred_ton_total' => Icons.factory,
      'hundred_ton' => Icons.foundation,
      'pr_first' => Icons.sports_martial_arts,
      'pr_ten' => Icons.star,
      'pr_fifty' => Icons.auto_awesome,
      'pr_hundred' => Icons.diamond,
      'single_exercise_hundred_sets' => Icons.repeat,
      'heavy_reps' => Icons.bolt,
      'volume_pr' => Icons.insights,
      'bench_bodyweight' => Icons.fitness_center_outlined,
      'squat_half_ton' => Icons.expand,
      'heavy_tonnage' => Icons.money,

      // ── 探索发现（19 枚，含 4 枚隐藏）──
      'five_exercises' => Icons.explore,
      'ten_exercises' => Icons.travel_explore,
      'twenty_exercises' => Icons.explore_off,
      'fifty_exercises' => Icons.map,
      'eighty_exercises' => Icons.public,
      'hundred_exercises' => Icons.auto_awesome_motion,
      'cardio_first' => Icons.directions_run,
      'cardio_distance' => Icons.route,
      'cardio_ten_sessions' => Icons.timer,
      'distance_100km' => Icons.linear_scale,
      'stretch_first' => Icons.self_improvement,
      'variety_session' => Icons.shuffle,
      'same_exercise_days' => Icons.replay,
      'bodyweight_only' => Icons.sports_gymnastics,
      'dawn_raider' => Icons.wb_sunny_outlined,
      'midnight_crosser' => Icons.schedule,
      'hundred_workouts_milestone' => Icons.token,
      'new_exercise_ten' => Icons.new_releases,
      'explorer_all' => Icons.flag,

      // ── 里程碑（14 枚）──
      'ten_workouts' => Icons.event_available,
      'twenty_sets' => Icons.view_module,
      'thirty_sets' => Icons.grid_view,
      'forty_sets' => Icons.apps,
      'thirty_min_session' => Icons.av_timer,
      'sixty_min_session' => Icons.alarm,
      'workout_count_50' => Icons.emoji_flags,
      'hundred_workouts' => Icons.view_carousel,
      'workout_count_300' => Icons.assignment_turned_in,
      'workout_count_500' => Icons.verified,
      'sets_total_500' => Icons.widgets,
      'sets_total_2000' => Icons.dashboard,
      'sets_total_5000' => Icons.grid_on,
      'monthly_consistent' => Icons.event_repeat,

      _ => Icons.help_outline,
    };

/// 已解锁徽章的底色：**该档颜色 → 同一档压暗的那一端**（左上 → 右下，
/// 与界面稿 `.badge-icon` 的 `linear-gradient(135deg, …)` 同向）。
///
/// 深端不是新加的色值 —— 直接压暗同一档颜色（HSL 亮度 ×0.62），
/// 所以整个成就页**仍然只有三个色**，没有借渐变偷偷塞进第四个高饱和色。
LinearGradient badgeTierGradient(BadgeTier t) {
  final Color base = badgeTierColor(t);
  final HSLColor hsl = HSLColor.fromColor(base);
  final Color deep =
      hsl.withLightness((hsl.lightness * 0.62).clamp(0.0, 1.0)).toColor();
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[base, deep],
  );
}

/// **离你最近的那一枚**（A2，2026-10-06 用户拍板）。
///
/// 成就页顶部要回答的不是"我拿了多少"，而是"**我今天做什么能再拿一枚**"。
///
/// ⚠️ 排序按**剩余比例**（`current / target` 谁更接近 1），不是按绝对差值 ——
/// "还差 94536 kg"（累计 100 吨）的绝对值远大于"还差 2 次"，但它离得**远得多**。
/// 比例排序还有一个好处：几枚都差"最后一格"时，先推那枚**进度高的**。
///
/// 已解锁的不参与（那是回看，不是目标）。全都解锁了就返回 null —— 调用方要**如实**
/// 显示"全拿到了"，不许随便挑一枚充数。
///
/// ⚠️ **隐藏徽章（A4）也不参与**：它连"怎么拿到"都是"？？？"，摆到最显眼的地方等于
/// 把答案的一半预告出去（"你今天就能拿到这个 —— 但我不告诉你是什么"）。隐藏徽章靠用户
/// 自己撞见，不靠推荐位。
BadgeStatus? nearestBadge(List<BadgeStatus> all) {
  BadgeStatus? best;
  double bestProgress = -1;
  for (final BadgeStatus b in all) {
    if (b.unlocked || b.hidden || b.target <= 0) continue;
    final double p = (b.current / b.target).clamp(0.0, 1.0);
    // 同进度时：先给**档位低**的那枚（更容易拿到，也就更该今天去拿）
    if (p > bestProgress ||
        (p == bestProgress &&
            best != null &&
            b.tier.index < best.tier.index)) {
      best = b;
      bestProgress = p;
    }
  }
  return best;
}

/// 段位（A5）：**徽章总数**映射一个长期段位。
///
/// 判据只有一条：**拿到的枚数**。门槛写成常量表（可单测），七个段位从青铜到传奇 ——
/// 与"稀有度"是两件事：稀有度说"这枚值多少"，段位说"你走到哪了"。
///
/// ⚠️ 不落库、不发货币：段位是**算出来的**，改历史/恢复备份之后它自己就对。
///
/// **门槛为什么这么排**（2026-10-06 徽章扩到 73 枚时重排过一次）：
///   * 前两档必须**很快拿到**：0 → 3 枚，练三五次就有（"青铜 → 白银"是新人第一次升级）；
///   * 中间四档拉成等差，让"每周都在往上走"这件事一直成立；
///   * 顶级（传奇 60 枚）留给一年以上的积累 —— 73 枚里最难的几枚（一年不断、500 次、
///     500 吨）本就落在那个量级，段位和徽章难度要对得上，不能"60 枚全是常识题"。
const List<({String name, int need})> kRanks = <({String name, int need})>[
  (name: '青铜', need: 0),
  (name: '白银', need: 3),
  (name: '黄金', need: 8),
  (name: '铂金', need: 16),
  (name: '钻石', need: 28),
  (name: '大师', need: 42),
  (name: '传奇', need: 60),
];

/// 已解锁 [unlocked] 枚时的段位（取"已经够到"的最高一档）。
({String name, int need}) rankFor(int unlocked) {
  ({String name, int need}) cur = kRanks.first;
  for (final ({String name, int need}) r in kRanks) {
    if (unlocked >= r.need) cur = r;
  }
  return cur;
}

/// 下一段还差几枚；已经是最高段 → null（调用方据此显示"到顶了"，不编下一个目标）。
({String name, int need, int remaining})? nextRank(int unlocked) {
  for (final ({String name, int need}) r in kRanks) {
    if (unlocked < r.need) {
      return (name: r.name, need: r.need, remaining: r.need - unlocked);
    }
  }
  return null;
}

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
    required this.category,
    required this.current,
    required this.target,
    required this.unlocked,
    this.hidden = false,
  });

  final String id;
  final String name;

  /// 怎么拿到它（一句话，写在徽章下面）
  final String how;

  final BadgeTier tier;
  final BadgeCategory category;
  final int current;
  final int target;
  final bool unlocked;

  /// **A4 隐藏徽章**：解锁前条件写"？？？"，解锁后才说明白。
  ///
  /// 名字**照常可见** —— 藏名字的话用户根本不知道有这么回事，那不是隐藏，是不存在；
  /// 藏起来的只有"怎么拿到"。默认 false：新加的徽章不是隐藏的，
  /// 想藏必须在这一行显式写 `hidden: true`（不许靠"忘了写"意外藏起来）。
  final bool hidden;

  /// 0..1 的进度（已解锁恒为 1）
  double get progress =>
      unlocked ? 1 : (target <= 0 ? 0 : (current / target).clamp(0.0, 1.0));
}

/// 算全部徽章（含未解锁的）。
///
/// [now] 传进来是为了**可测**（"早鸟/夜猫"要用小时），不是为了让结果随当前时间漂 ——
/// 除此之外所有判据都只看训练记录本身。
///
/// [bodyWeightKg] **只为"体重倍数"那几枚**（卧推 1× 体重）：它是可选参数，
/// 因为 `badgeStatuses` 的另一个调用点（通知规则）手上没有身体数据 ——
/// 传 null 时那几枚就是"拿不到"，而不是拿 0 kg 去算出一个假的解锁。
/// **这一场训练新挣到的徽章**（2026-10-10）。
///
/// **为什么是"差额"而不是记一个时间戳**：徽章全是**纯函数**（`badgeStatuses` 吃一份
/// 训练记录就能算出全部状态），库里没有任何"解锁事件"的表。要回答"刚才那一下解锁了什么"，
/// 最便宜也最不会出错的办法是：**把刚练完这一场的组排除再算一遍**，两次结果一减就是答案。
/// 引入"已读徽章"表会让这一摊多出一份真相（还得处理导入备份、换设备、清数据）。
///
/// 空列表 = 这场什么都没解锁（界面那一块整个不出现，不是摆一句"暂无"）。
List<BadgeStatus> newlyUnlockedBadges(
  List<SetRecord> allSets, {
  required String workoutId,
  DateTime? now,
  double? bodyWeightKg,
}) {
  final List<BadgeStatus> after =
      badgeStatuses(allSets, now: now, bodyWeightKg: bodyWeightKg);
  final List<SetRecord> before = <SetRecord>[
    for (final SetRecord s in allSets)
      if (s.workoutId != workoutId) s,
  ];
  final Set<String> had = <String>{
    for (final BadgeStatus b
        in badgeStatuses(before, now: now, bodyWeightKg: bodyWeightKg))
      if (b.unlocked) b.id,
  };
  return <BadgeStatus>[
    for (final BadgeStatus b in after)
      if (b.unlocked && !had.contains(b.id)) b,
  ];
}

List<BadgeStatus> badgeStatuses(
  List<SetRecord> sets, {
  DateTime? now,
  double? bodyWeightKg,
}) {
  final DateTime today = now ?? DateTime.now();

  // ── 先把要用的数算一遍（一遍过，别在每个徽章里重扫） ──
  //
  // ⚠️ 这一整个函数**不查动作库**（不拿 equipment / muscle_group / track_type）：
  // 那要调用方多传一份动作表进来，而 `badgeStatuses(sets)` 现在只吃训练记录
  // （通知那一侧也在用它）。判据一律从记录本身算得出来才算数。
  final Set<String> workouts = <String>{};
  final Set<String> exercises = <String>{};
  final Set<int> hours = <int>{};
  final Set<int> workoutDays = <int>{};
  double totalVolume = 0;
  double bestSingleKg = 0;
  double bestWorkoutVolume = 0;
  int bestWorkoutSets = 0;
  int bestReps = 0;
  int distanceSets = 0;
  double totalDistanceM = 0;
  final Map<String, double> volumeByWorkout = <String, double>{};
  final Map<String, int> setsByWorkout = <String, int>{};
  final Map<String, int> startMsByWorkout = <String, int>{};
  final Map<String, int> endMsByWorkout = <String, int>{};
  final Map<String, Set<String>> exercisesByWorkout = <String, Set<String>>{};
  // A4 隐藏徽章 + "老熟人"要用的：同一个动作在哪几个**日子**练过
  final Map<String, Set<int>> daysByExercise = <String, Set<int>>{};
  final Map<String, int> weightedSetsByWorkout = <String, int>{};
  int bodyweightOnlyBestSets = 0;

  for (final SetRecord s in sets) {
    workouts.add(s.workoutId);
    exercises.add(s.exerciseId);
    (exercisesByWorkout[s.workoutId] ??= <String>{}).add(s.exerciseId);
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(s.completedAtMs);
    hours.add(t.hour);
    // 同一天用一个整数表示（年月日）：跨时区/夏令时都不会把两天并成一天
    final int dayKey = t.year * 10000 + t.month * 100 + t.day;
    workoutDays.add(dayKey);
    (daysByExercise[s.exerciseId] ??= <int>{}).add(dayKey);
    totalVolume += s.volume;
    final double? w = s.weightKg;
    if (w != null && w > bestSingleKg) bestSingleKg = w;
    if (w != null && w > 0) {
      weightedSetsByWorkout[s.workoutId] =
          (weightedSetsByWorkout[s.workoutId] ?? 0) + 1;
    }
    if (s.reps > bestReps) bestReps = s.reps;
    // 有距离的组：距离动作的 `reps` 存的是**秒**，所以这一类只按"有没有距离"认
    final double? d = s.distanceM;
    if (d != null && d > 0) {
      distanceSets++;
      totalDistanceM += d;
    }
    final int ms = s.completedAtMs;
    final int? prevStart = startMsByWorkout[s.workoutId];
    if (prevStart == null || ms < prevStart) startMsByWorkout[s.workoutId] = ms;
    final int? prevEnd = endMsByWorkout[s.workoutId];
    if (prevEnd == null || ms > prevEnd) endMsByWorkout[s.workoutId] = ms;
    volumeByWorkout[s.workoutId] = (volumeByWorkout[s.workoutId] ?? 0) + s.volume;
    setsByWorkout[s.workoutId] = (setsByWorkout[s.workoutId] ?? 0) + 1;
  }
  for (final double v in volumeByWorkout.values) {
    if (v > bestWorkoutVolume) bestWorkoutVolume = v;
  }
  for (final int n in setsByWorkout.values) {
    if (n > bestWorkoutSets) bestWorkoutSets = n;
  }
  // 单次训练的时长 = 这一场里最后一组减第一组（不落库，只能这么算）
  int bestWorkoutDurationMin = 0;
  for (final MapEntry<String, int> e in startMsByWorkout.entries) {
    final int? end = endMsByWorkout[e.key];
    if (end == null) continue;
    final int minutes = ((end - e.value) / 60000).floor();
    if (minutes > bestWorkoutDurationMin) bestWorkoutDurationMin = minutes;
  }
  // "整场没碰重量"的最大组数：有负重的那几场先被排除，再取最重的那场
  for (final MapEntry<String, int> e in setsByWorkout.entries) {
    if ((weightedSetsByWorkout[e.key] ?? 0) > 0) continue;
    if (e.value > bodyweightOnlyBestSets) bodyweightOnlyBestSets = e.value;
  }
  // 同一个动作**在不同日子**练过的最多天数（不是组数：一天练 20 组不算 20 天）
  int mostDaysOneExercise = 0;
  for (final Set<int> days in daysByExercise.values) {
    if (days.length > mostDaysOneExercise) mostDaysOneExercise = days.length;
  }
  // 单场里练过的不同动作数最多的一场（"一场练十个动作"）
  int bestVarietyInWorkout = 0;
  for (final Set<String> ids in exercisesByWorkout.values) {
    if (ids.length > bestVarietyInWorkout) bestVarietyInWorkout = ids.length;
  }
  // 单动作历史最多组数（"百组磨一个动作"）
  final Map<String, int> setsByExercise = <String, int>{};
  for (final SetRecord s in sets) {
    setsByExercise[s.exerciseId] = (setsByExercise[s.exerciseId] ?? 0) + 1;
  }
  int mostSetsOneExercise = 0;
  for (final int n in setsByExercise.values) {
    if (n > mostSetsOneExercise) mostSetsOneExercise = n;
  }

  // ── 破纪录次数：**自己算，不读 `is_pr`** ──
  //
  // `is_pr` 那一列在库里（`db.g.dart`），但领域模型 `SetRecord` 上没有这个字段 ——
  // 而这里拿到的正是领域模型。反正"破了几次纪录"本来就该算得出来：
  // 按时间过一遍，每遇到一个比该动作此前最大值更大的重量就记一次。
  int countPrs(List<SetRecord> input) {
    final List<SetRecord> chrono = input
        .where((SetRecord s) => s.weightKg != null && s.weightKg! > 0)
        .toList()
      ..sort((SetRecord a, SetRecord b) => a.completedAtMs.compareTo(b.completedAtMs));
    final Map<String, double> best = <String, double>{};
    int n = 0;
    for (final SetRecord s in chrono) {
      final double w = s.weightKg!;
      final double? prev = best[s.exerciseId];
      if (prev != null && w > prev) n++;
      if (prev == null || w > prev) best[s.exerciseId] = w;
    }
    return n;
  }

  // ── 按"练过的日子"排一遍：最长连续 / 最长空档 / 周末次数 ──
  final List<int> sortedDays = workoutDays.toList()..sort();
  int longestStreak = 0;
  int longestGap = 0;
  int weekendWorkouts = 0;
  int prevKey = -1;
  int run = 0;
  for (final int k in sortedDays) {
    final DateTime d = DateTime(k ~/ 10000, (k ~/ 100) % 100, k % 100);
    if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
      weekendWorkouts++;
    }
    if (prevKey < 0) {
      run = 1;
    } else {
      final DateTime p =
          DateTime(prevKey ~/ 10000, (prevKey ~/ 100) % 100, prevKey % 100);
      final int gap = d.difference(p).inDays;
      run = gap == 1 ? run + 1 : 1;
      if (gap > 1 && gap > longestGap) longestGap = gap;
    }
    if (run > longestStreak) longestStreak = run;
    prevKey = k;
  }

  /// 某一天所在那一周（周一起）里练了几次
  int workoutsInWeekStarting(DateTime monday) {
    final DateTime next = monday.add(const Duration(days: 7));
    int n = 0;
    for (final MapEntry<String, int> e in startMsByWorkout.entries) {
      final DateTime t = DateTime.fromMillisecondsSinceEpoch(e.value);
      if (!t.isBefore(monday) && t.isBefore(next)) n++;
    }
    return n;
  }

  // 一周里最多练了几次（"一周全勤"）；以及**连续几周**每周都 ≥3 练
  int bestWeekWorkouts = 0;
  for (final int k in sortedDays) {
    final DateTime d = DateTime(k ~/ 10000, (k ~/ 100) % 100, k % 100);
    final DateTime monday =
        d.subtract(Duration(days: d.weekday - DateTime.monday));
    final int n = workoutsInWeekStarting(monday);
    if (n > bestWeekWorkouts) bestWeekWorkouts = n;
  }
  int consistentWeekRun = 0;
  if (sortedDays.isNotEmpty) {
    final DateTime first = DateTime(sortedDays.first ~/ 10000,
        (sortedDays.first ~/ 100) % 100, sortedDays.first % 100);
    DateTime cursor = first.subtract(Duration(days: first.weekday - DateTime.monday));
    final DateTime todayMonday = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: today.weekday - DateTime.monday));
    // 从第一周走到**今天所在那周**：哪一周不到 3 练，就从那一周重新数。
    // ⚠️ **今天这一周不算断**（今天可能才周一，这周当然还没练够）——
    // 与"今天还没练不算断签"是同一条纪律：账不该先扣。
    while (!cursor.isAfter(todayMonday)) {
      final bool currentWeek = !cursor.isBefore(todayMonday);
      if (workoutsInWeekStarting(cursor) >= 3) {
        consistentWeekRun++;
      } else if (!currentWeek) {
        consistentWeekRun = 0;
      }
      cursor = cursor.add(const Duration(days: 7));
    }
  }

  // 一个月里最多练了几次（与"连续天数"是两件事：这个是**当月次数**）
  int bestMonthWorkouts = 0;
  {
    final Map<int, int> byMonth = <int, int>{};
    for (final int ms in startMsByWorkout.values) {
      final DateTime t = DateTime.fromMillisecondsSinceEpoch(ms);
      final int key = t.year * 100 + t.month;
      byMonth[key] = (byMonth[key] ?? 0) + 1;
    }
    for (final int n in byMonth.values) {
      if (n > bestMonthWorkouts) bestMonthWorkouts = n;
    }
  }

  // "最近 7 天里第一次练"的动作数（一个动作**最早那天**落在这一周内）
  final DateTime weekAgo = DateTime(today.year, today.month, today.day)
      .subtract(const Duration(days: 6));
  int newExercisesThisWeek = 0;
  for (final Set<int> days in daysByExercise.values) {
    final int earliest = (days.toList()..sort()).first;
    final DateTime t =
        DateTime(earliest ~/ 10000, (earliest ~/ 100) % 100, earliest % 100);
    if (!t.isBefore(weekAgo) && !t.isAfter(today)) newExercisesThisWeek++;
  }

  final int streak = currentStreak(sets, today);
  final int workoutCount = workouts.length;
  final int prCount = countPrs(sets);
  // 体重倍数：没有体重数据就是 0（那几枚不解锁 —— 不拿 0 kg 编一个"1 倍体重"）
  double ratio(double kg, double times) => bodyWeightKg == null || bodyWeightKg <= 0
      ? 0
      : (kg / (bodyWeightKg * times)).floorToDouble();

  BadgeStatus b(
    String id,
    String name,
    String how,
    BadgeTier tier,
    BadgeCategory cat,
    num current,
    int target, {
    bool hidden = false,
  }) {
    final int cur = current.round();
    return BadgeStatus(
      id: id,
      name: name,
      how: how,
      tier: tier,
      category: cat,
      current: cur,
      target: target,
      unlocked: cur >= target,
      hidden: hidden,
    );
  }

  return <BadgeStatus>[
    // ══ 连续打卡（20 枚）══
    // 稀有度总口径：**真的难**才给 epic。所以 epic ≈ 60 天/100 次/100 吨这个量级，
    // 不许为了好看把"14 天"也叫史诗 —— 那会让"史诗"两个字贬值（这一屏最容易犯的错）。
    b('first_workout', '首训', '完成第 1 次训练', BadgeTier.common, BadgeCategory.streak,
        workoutCount, 1),
    b('three_day_streak', '三天不断', '连续打卡 3 天', BadgeTier.common,
        BadgeCategory.streak, streak, 3),
    b('week_streak', '一周不断', '连续打卡 7 天', BadgeTier.common, BadgeCategory.streak,
        streak, 7),
    b('two_week_streak', '两周不断', '连续打卡 14 天', BadgeTier.rare, BadgeCategory.streak,
        streak, 14),
    b('month_streak', '月度铁人', '连续打卡 30 天', BadgeTier.rare, BadgeCategory.streak,
        streak, 30),
    b('two_month_streak', '两月不断', '连续打卡 60 天', BadgeTier.epic, BadgeCategory.streak,
        streak, 60),
    b('hundred_day_streak', '百日坚持', '连续打卡 100 天', BadgeTier.epic,
        BadgeCategory.streak, streak, 100),
    b('year_streak', '一年不断', '连续打卡 365 天', BadgeTier.epic, BadgeCategory.streak,
        streak, 365),
    // "回归"看的是**历史上最长的空档**：断过 14 天又重新练起来 —— 这是要奖励的
    b('comeback', '我回来了', '断 14 天之后重新练起来', BadgeTier.rare, BadgeCategory.streak,
        longestGap, 14),
    b('early_bird', '早鸟', '早上 7 点前练过', BadgeTier.common, BadgeCategory.streak,
        hours.any((int h) => h < 7) ? 1 : 0, 1),
    b('night_owl', '夜猫', '晚上 22 点后练过', BadgeTier.common, BadgeCategory.streak,
        hours.any((int h) => h >= 22) ? 1 : 0, 1),
    b('weekend_warrior', '周末战士', '周末练满 10 次', BadgeTier.rare, BadgeCategory.streak,
        weekendWorkouts, 10),
    b('active_week', '一周三练', '同一周里练满 3 次', BadgeTier.common, BadgeCategory.streak,
        bestWeekWorkouts, 3),
    b('full_week', '一周全勤', '同一周里练了 7 次', BadgeTier.rare, BadgeCategory.streak,
        bestWeekWorkouts, 7),
    b('four_week_streak', '连续四周', '连续 4 周每周至少 3 练', BadgeTier.rare,
        BadgeCategory.streak, consistentWeekRun, 4),
    // 时长是从"这一场最后一组减第一组"算的；只有一组的那一场算 0 分钟，不给这枚
    b('short_session', '短促一练', '一次训练不到 20 分钟', BadgeTier.common,
        BadgeCategory.streak,
        bestWorkoutDurationMin > 0 && bestWorkoutDurationMin < 20 ? 1 : 0, 1),
    b('long_session', '一小时', '单次训练满 60 分钟', BadgeTier.common, BadgeCategory.streak,
        bestWorkoutDurationMin, 60),
    b('marathon_session', '两小时', '单次训练满 120 分钟', BadgeTier.rare,
        BadgeCategory.streak, bestWorkoutDurationMin, 120),
    b('iron_month', '月度 12 练', '一个月里练满 12 次', BadgeTier.rare, BadgeCategory.streak,
        bestMonthWorkouts, 12),
    b('three_month_iron', '月度 30 练', '一个月里练满 30 次', BadgeTier.epic,
        BadgeCategory.streak, bestMonthWorkouts, 30),

    // ══ 力量突破（20 枚）══
    b('five_ton', '单次 5 吨', '单次训练总容量到 5,000 kg', BadgeTier.common,
        BadgeCategory.strength, bestWorkoutVolume.floor(), 5000),
    b('ten_ton', '单次 10 吨', '单次训练总容量到 10,000 kg', BadgeTier.rare,
        BadgeCategory.strength, bestWorkoutVolume.floor(), 10000),
    b('twenty_ton', '单次 20 吨', '单次训练总容量到 20,000 kg', BadgeTier.epic,
        BadgeCategory.strength, bestWorkoutVolume.floor(), 20000),
    b('fifty_ton', '单次 50 吨', '单次训练总容量到 50,000 kg', BadgeTier.epic,
        BadgeCategory.strength, bestWorkoutVolume.floor(), 50000),
    b('hundred_kg', '百公斤俱乐部', '任一动作单组 ≥ 100 kg', BadgeTier.rare,
        BadgeCategory.strength, bestSingleKg.floor(), 100),
    b('two_hundred_kg', '两百公斤', '任一动作单组 ≥ 200 kg', BadgeTier.epic,
        BadgeCategory.strength, bestSingleKg.floor(), 200),
    b('ten_ton_total', '累计 10 吨', '累计容量到 10,000 kg', BadgeTier.common,
        BadgeCategory.strength, totalVolume.floor(), 10000),
    b('fifty_ton_total', '累计 50 吨', '累计容量到 50,000 kg', BadgeTier.rare,
        BadgeCategory.strength, totalVolume.floor(), 50000),
    b('hundred_ton_total', '累计 100 吨', '累计容量到 100,000 kg', BadgeTier.epic,
        BadgeCategory.strength, totalVolume.floor(), 100000),
    b('hundred_ton', '累计 500 吨', '累计容量到 500,000 kg', BadgeTier.epic,
        BadgeCategory.strength, totalVolume.floor(), 500000),
    b('pr_first', '第一次破纪录', '记下第 1 次个人纪录', BadgeTier.common,
        BadgeCategory.strength, prCount, 1),
    b('pr_ten', '十次破纪录', '累计破纪录 10 次', BadgeTier.common, BadgeCategory.strength,
        prCount, 10),
    b('pr_fifty', '五十次破纪录', '累计破纪录 50 次', BadgeTier.rare, BadgeCategory.strength,
        prCount, 50),
    b('pr_hundred', '百次破纪录', '累计破纪录 100 次', BadgeTier.epic, BadgeCategory.strength,
        prCount, 100),
    b('single_exercise_hundred_sets', '百组磨一个动作', '同一个动作累计 100 组',
        BadgeTier.rare, BadgeCategory.strength, mostSetsOneExercise, 100),
    b('heavy_reps', '一组二十次', '单组做到 20 次', BadgeTier.rare, BadgeCategory.strength,
        bestReps, 20),
    b('volume_pr', '单次新高', '单次训练容量超过以往任何一次', BadgeTier.common,
        BadgeCategory.strength, bestWorkoutVolume.floor(), 1),
    // 体重倍数：**没有身体数据时如实停在 0**（不拿 0 kg 编一个"1 倍体重"）
    b('bench_bodyweight', '卧推一倍体重', '单组卧推达到自身体重', BadgeTier.rare,
        BadgeCategory.strength, ratio(bestSingleKg, 1), 1),
    b('squat_half_ton', '单组 500 kg', '任一动作单组 ≥ 500 kg', BadgeTier.epic,
        BadgeCategory.strength, bestSingleKg.floor(), 500),
    b('heavy_tonnage', '单次 30 吨', '单次训练总容量到 30,000 kg', BadgeTier.epic,
        BadgeCategory.strength, bestWorkoutVolume.floor(), 30000),

    // ══ 探索发现（19 枚，含 4 枚隐藏）══
    b('five_exercises', '五个动作', '练过 5 个不同动作', BadgeTier.common,
        BadgeCategory.explore, exercises.length, 5),
    b('ten_exercises', '十个动作', '练过 10 个不同动作', BadgeTier.common,
        BadgeCategory.explore, exercises.length, 10),
    b('twenty_exercises', '二十个动作', '练过 20 个不同动作', BadgeTier.common,
        BadgeCategory.explore, exercises.length, 20),
    b('fifty_exercises', '五十个动作', '练过 50 个不同动作', BadgeTier.rare,
        BadgeCategory.explore, exercises.length, 50),
    b('eighty_exercises', '八十个动作', '练过 80 个不同动作', BadgeTier.epic,
        BadgeCategory.explore, exercises.length, 80),
    b('hundred_exercises', '一百二十个动作', '练过 120 个不同动作', BadgeTier.epic,
        BadgeCategory.explore, exercises.length, 120),
    b('cardio_first', '第一次有氧', '记下第一组距离', BadgeTier.common, BadgeCategory.explore,
        distanceSets > 0 ? 1 : 0, 1),
    b('cardio_distance', '一次五公里', '同一次训练的距离合计到 5 km', BadgeTier.rare,
        BadgeCategory.explore, totalDistanceM >= 5000 ? 1 : 0, 1),
    b('cardio_ten_sessions', '有氧十组', '有距离的记录累计 10 组', BadgeTier.rare,
        BadgeCategory.explore, distanceSets, 10),
    b('distance_100km', '累计 100 公里', '所有距离加起来到 100 km', BadgeTier.epic,
        BadgeCategory.explore, totalDistanceM ~/ 1000, 100),
    b('stretch_first', '练完拉一下', '记过一组热身或拉伸', BadgeTier.common,
        BadgeCategory.explore,
        sets.any((SetRecord s) => s.setType != SetType.normal) ? 1 : 0, 1),
    b('variety_session', '一场十个动作', '单次训练里练过 10 个不同动作', BadgeTier.rare,
        BadgeCategory.explore, bestVarietyInWorkout, 10),
    b('new_exercise_ten', '这周新动作', '最近 7 天里第一次练的动作有 3 个', BadgeTier.rare,
        BadgeCategory.explore, newExercisesThisWeek, 3),
    b('explorer_all', '动作库常客', '练过 30 个不同动作', BadgeTier.rare,
        BadgeCategory.explore, exercises.length, 30),
    b('hundred_workouts_milestone', '一百个动作', '练过 100 个不同动作', BadgeTier.epic,
        BadgeCategory.explore, exercises.length, 100),

    // ── A4 隐藏徽章（四枚，全在「探索发现」线）：解锁前条件是"？？？" ──
    //
    // 为什么是这几条，而不是随便四条：
    //   * 它们都**不是目标**（没人会为了"凌晨练一次"去定计划），所以只能靠撞见 ——
    //     这正是隐藏徽章的用处：让"我居然练到了这个"变成一个能被发现的惊喜；
    //   * 它们都**算得出来**，不需要动作库、不需要新表、不需要埋点（三条红线）；
    //   * 都放在「探索发现」线：与"练没练过什么"同一族，不污染"力量/里程"那两条
    //     —— 那两条的每一枚都该有明确的目标感。
    //
    // ⚠️ 隐藏 ≠ 随便给：`dawn_raider` / `midnight_crosser` 是真少见的时段；
    // `same_exercise_days` 要 5 个不同日子；`bodyweight_only` 要一整场 15 组不碰重量。
    b('dawn_raider', '破晓', '凌晨 5 点前练过一整场', BadgeTier.rare, BadgeCategory.explore,
        hours.any((int h) => h < 5) ? 1 : 0, 1,
        hidden: true),
    b('midnight_crosser', '跨零点', '0 点到 2 点之间记过一组', BadgeTier.rare,
        BadgeCategory.explore, hours.any((int h) => h >= 0 && h < 2) ? 1 : 0, 1,
        hidden: true),
    b('same_exercise_days', '老熟人', '同一个动作在 5 个不同日子练过', BadgeTier.rare,
        BadgeCategory.explore, mostDaysOneExercise, 5,
        hidden: true),
    b('bodyweight_only', '只用自重', '一整场 15 组，一组重量都没加', BadgeTier.epic,
        BadgeCategory.explore, bodyweightOnlyBestSets, 15,
        hidden: true),

    // ══ 里程碑（14 枚）══
    b('ten_workouts', '练满 10 次', '累计完成 10 次训练', BadgeTier.common,
        BadgeCategory.milestone, workoutCount, 10),
    b('workout_count_50', '练满 50 次', '累计完成 50 次训练', BadgeTier.rare,
        BadgeCategory.milestone, workoutCount, 50),
    b('hundred_workouts', '百次训练', '累计完成 100 次训练', BadgeTier.rare,
        BadgeCategory.milestone, workoutCount, 100),
    b('workout_count_300', '三百次训练', '累计完成 300 次训练', BadgeTier.epic,
        BadgeCategory.milestone, workoutCount, 300),
    b('workout_count_500', '五百次训练', '累计完成 500 次训练', BadgeTier.epic,
        BadgeCategory.milestone, workoutCount, 500),
    b('twenty_sets', '一口气 20 组', '单次训练记满 20 组', BadgeTier.common,
        BadgeCategory.milestone, bestWorkoutSets, 20),
    b('thirty_sets', '一口气 30 组', '单次训练记满 30 组', BadgeTier.rare,
        BadgeCategory.milestone, bestWorkoutSets, 30),
    b('forty_sets', '一口气 40 组', '单次训练记满 40 组', BadgeTier.epic,
        BadgeCategory.milestone, bestWorkoutSets, 40),
    b('thirty_min_session', '半小时', '单次训练满 30 分钟', BadgeTier.common,
        BadgeCategory.milestone, bestWorkoutDurationMin, 30),
    b('sixty_min_session', '满一小时', '单次训练满 60 分钟', BadgeTier.rare,
        BadgeCategory.milestone, bestWorkoutDurationMin, 60),
    b('sets_total_500', '总组数 500', '累计记满 500 组', BadgeTier.common,
        BadgeCategory.milestone, sets.length, 500),
    b('sets_total_2000', '总组数 2000', '累计记满 2,000 组', BadgeTier.rare,
        BadgeCategory.milestone, sets.length, 2000),
    b('sets_total_5000', '总组数 5000', '累计记满 5,000 组', BadgeTier.epic,
        BadgeCategory.milestone, sets.length, 5000),
    b('monthly_consistent', '月度 12 练', '一个月里练满 12 次', BadgeTier.common,
        BadgeCategory.milestone, bestMonthWorkouts, 12),
  ];
}

/// 已解锁几枚 / 一共几枚。成就页顶部那一行用它。
({int unlocked, int total}) badgeTally(List<BadgeStatus> list) => (
      unlocked: list.where((BadgeStatus b) => b.unlocked).length,
      total: list.length,
    );

/// 按分类分组（成就页的四个分区就是它）。**保持定义顺序**，
/// 不然每次重建分组顺序都可能变，页面会莫名其妙地抖。
Map<BadgeCategory, List<BadgeStatus>> badgeGroups(List<BadgeStatus> all) {
  final Map<BadgeCategory, List<BadgeStatus>> out =
      <BadgeCategory, List<BadgeStatus>>{};
  for (final BadgeCategory c in BadgeCategory.values) {
    final List<BadgeStatus> rows =
        all.where((BadgeStatus b) => b.category == c).toList();
    if (rows.isNotEmpty) out[c] = rows;
  }
  return out;
}

/// **A1 · 一条收集线**（2026-10-06 拍板）：这条线上拿到几枚、一共几枚、集齐没有。
///
/// 「线进度」与「总进度」是两件事：总数说"我攒了多少"，线说"我在**哪一类**上有断层"。
/// 四条线各有一枚"集齐奖励"（见 [lineColor]），所以线进度必须能被单测。
class BadgeLine {
  const BadgeLine({
    required this.category,
    required this.label,
    required this.unlocked,
    required this.total,
  });

  final BadgeCategory category;
  final String label;
  final int unlocked;
  final int total;

  /// 这一条线**全部**拿到
  bool get complete => total > 0 && unlocked >= total;

  /// 0..1 的线进度（一条线都没有时返回 0，不返回 NaN）
  double get progress => total == 0 ? 0 : (unlocked / total).clamp(0.0, 1.0);
}

/// 四条收集线（顺序与成就页的分区一致）。**算出来的**，不落库。
List<BadgeLine> badgeLines(List<BadgeStatus> all) => <BadgeLine>[
      for (final MapEntry<BadgeCategory, List<BadgeStatus>> e
          in badgeGroups(all).entries)
        BadgeLine(
          category: e.key,
          label: badgeCategoryLabel(e.key),
          unlocked: e.value.where((BadgeStatus b) => b.unlocked).length,
          total: e.value.length,
        ),
    ];

/// 已集齐的那几条线（按分区顺序）。空列表 = 一条都没集齐。
List<BadgeLine> completedLines(List<BadgeStatus> all) =>
    badgeLines(all).where((BadgeLine l) => l.complete).toList();

/// **集齐一条线的展示性奖励用的颜色**（A1）。
///
/// 三条复用已有语义色 —— **不新增第四个高饱和色**（`theme.dart` 那条"三档里只新加一个颜色"
/// 的纪律：同一套界面里多一个近似色，肉眼就分不出谁是谁）：
///   * 连续打卡 → [Tokens.accent]（主色，火焰那一条本来就是热的）；
///   * 力量突破 → [Tokens.tierRare]（紫）；
///   * 里程碑 → [Tokens.pr]（琥珀，奖杯那个色）。
///
/// 第四条（探索发现）用 [Tokens.danger]（红）。它是**唯一一个还没被别的语义占用的**语义色，
/// 而且在这里只做展示（描边 / 图标底色），不参与任何判据与动作 ——
/// 刻意**不往 [Tokens] 里加新常量**：那个文件里每个色都是"一整屏的意思"，
/// 而这条红只属于成就页这四条线。
Color lineColor(BadgeCategory c) => switch (c) {
      BadgeCategory.streak => Tokens.accent,
      BadgeCategory.strength => Tokens.tierRare,
      BadgeCategory.explore => Tokens.danger,
      BadgeCategory.milestone => Tokens.pr,
    };

/// 集齐奖励的**徽记**：一条线集齐了就点亮它自己那个图形。
IconData lineIcon(BadgeCategory c) => switch (c) {
      BadgeCategory.streak => Icons.local_fire_department,
      BadgeCategory.strength => Icons.fitness_center,
      BadgeCategory.explore => Icons.explore,
      BadgeCategory.milestone => Icons.emoji_events,
    };
