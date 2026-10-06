/// 练了么 · **周报 / 月报**（第二部分第 1 条，2026-10-06 用户拍板）
///
/// **每周一进首页时一张可分享的总结卡**：本地生成，不上传、不联网、不需要任何权限
/// （分享沿用现有那套"抓成 PNG / 落剪贴板"，见 `features/summary/share_card.dart`）。
///
/// 三件事在这里定死，页面只负责画：
///   1. **算哪一周**：上一个完整的周（周一 00:00 ～ 本周一 00:00）。
///      用"上一个完整周"而不是"最近 7 天"：周报的日期范围必须**固定**
///      （"最近 7 天"每天都在变，今天写的"上周练了 4 次"明天就对不上了）。
///   2. **什么时候给看**：`shouldShowWeeklyReport()` —— 只在**周一 / 周二**出现，
///      而且上一周至少练过一次。**一周只提示两天**：周报是"回顾"，天天顶在首页就成了广告。
///   3. **一句人话**：`headline`。数字谁都会算，"这句话"才是用户会看的那一行。
///
/// ⚠️ 与徽章、连续天数同一条底线：**全部算出来，不落库**。存一份"上周报告"
/// 就会在改历史 / 导入备份 / 换设备之后和记录不一致。
library;

import '../../domain/models.dart';
import 'badges.dart';
import 'weekly_challenge.dart';

/// 一份"某一周"的总结。
class WeeklyReport {
  const WeeklyReport({
    required this.start,
    required this.end,
    required this.sessions,
    required this.activeDays,
    required this.totalSets,
    required this.volumeKg,
    required this.durationMin,
    required this.exerciseCount,
    required this.distanceM,
    required this.prs,
    required this.badgesUnlocked,
    required this.bestDayVolumeKg,
  });

  /// 这一周的起止（周一 00:00 ～ 下周一 00:00，本地时间）
  final DateTime start;
  final DateTime end;

  /// 练了几次（按 workoutId 去重）
  final int sessions;

  /// 有几天练了
  final int activeDays;

  final int totalSets;
  final double volumeKg;
  final int durationMin;

  /// 这一周练过几个不同动作
  final int exerciseCount;

  final double distanceM;

  /// 这一周**刷新过**的个人纪录：`(动作名, 成绩文案)`
  final List<({String name, String detail})> prs;

  /// 这一周新解锁了几枚徽章
  final int badgesUnlocked;

  /// 单日最高容量（"最猛的那天"）
  final double bestDayVolumeKg;

  /// 这一周什么都练过没有
  bool get isEmpty => sessions == 0;

  /// 显示用的日期范围，如「9 月 28 日 – 10 月 4 日」。
  ///
  /// 结束日显示成**周日**（`end` 是下周一 00:00，直接显示会写成"10 月 5 日"，
  /// 而那一周的最后一天是 10 月 4 日 —— 差一天就是假话）。
  String get rangeLabel {
    final DateTime last = end.subtract(const Duration(days: 1));
    return '${start.month} 月 ${start.day} 日 – ${last.month} 月 ${last.day} 日';
  }

  /// 那一行"人话"。**没有训练就如实说没事**，不硬凑一句鼓励
  /// （"上周休息了一整周"也是一种事实，编一句"下周加油"只会显得敷衍）。
  String get headline {
    if (isEmpty) return '上周没练。这周随时可以重新开始。';
    if (sessions >= 5) return '上周练了 $sessions 次 —— 这是很扎实的一周。';
    if (activeDays >= 4) return '上周有 $activeDays 天在练，节奏稳。';
    if (prs.isNotEmpty) return '上周破了自己 ${prs.length} 次纪录。';
    if (badgesUnlocked > 0) return '上周拿到了 $badgesUnlocked 枚新徽章。';
    return '上周练了 $sessions 次，保持住。';
  }

  /// 一句话的数字行（分享卡与卡片正文都用它，避免两处口径不一致）
  String get statsLine {
    final List<String> parts = <String>[
      '$sessions 次训练',
      '$activeDays 天',
      '$totalSets 组',
      '${(volumeKg / 1000).toStringAsFixed(1)} 吨',
    ];
    if (durationMin > 0) parts.add('$durationMin 分钟');
    return parts.join(' · ');
  }

  /// 这一周能不能分享（没练过的一周不值得做成卡）
  bool get shareable => !isEmpty;

  /// 转成分享卡的形状。
  ///
  /// **复用现有的 `ShareCard`**（同一棵树、同一套固定尺寸），只是把"一次训练"的
  /// 数字换成"一周"的 —— 所以 `exerciseCount` 是**这一周练过几个动作**，
  /// `prs` 是这一周刷新的纪录。**为它做第二套分享卡是不划算的**：
  /// 用户看到的会是两种长相的卡，而后端（抓图 / 存相册 / 剪贴板）一模一样。
  Map<String, Object?> toShareArgs() => <String, Object?>{
        'sessions': sessions,
        'activeDays': activeDays,
        'totalSets': totalSets,
        'volumeKg': volumeKg,
        'durationMin': durationMin,
        'prs': prs.length,
        'badges': badgesUnlocked,
        'range': rangeLabel,
      };
}

/// 算 [day] **上一个完整周**（周一 00:00 ～ 本周一 00:00）的报告。
WeeklyReport weeklyReportFor(List<SetRecord> sets, DateTime day) {
  final DateTime thisMonday = weekBounds(day).start;
  final DateTime start = thisMonday.subtract(const Duration(days: 7));
  final DateTime end = thisMonday;

  final List<SetRecord> week = <SetRecord>[
    for (final SetRecord s in sets)
      if (!DateTime.fromMillisecondsSinceEpoch(s.completedAtMs).isBefore(start) &&
          DateTime.fromMillisecondsSinceEpoch(s.completedAtMs).isBefore(end))
        s,
  ];

  final Set<String> workoutIds = <String>{};
  final Set<int> days = <int>{};
  final Set<String> exerciseIds = <String>{};
  final Map<String, int> firstMs = <String, int>{};
  final Map<String, int> lastMs = <String, int>{};
  final Map<int, double> volumeByDay = <int, double>{};
  double volume = 0;
  double distance = 0;
  for (final SetRecord s in week) {
    workoutIds.add(s.workoutId);
    exerciseIds.add(s.exerciseId);
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(s.completedAtMs);
    days.add(t.year * 10000 + t.month * 100 + t.day);
    volume += s.volume;
    volumeByDay[t.year * 10000 + t.month * 100 + t.day] =
        (volumeByDay[t.year * 10000 + t.month * 100 + t.day] ?? 0) + s.volume;
    if ((s.distanceM ?? 0) > 0) distance += s.distanceM!;
    final int? f = firstMs[s.workoutId];
    if (f == null || s.completedAtMs < f) firstMs[s.workoutId] = s.completedAtMs;
    final int? l = lastMs[s.workoutId];
    if (l == null || s.completedAtMs > l) lastMs[s.workoutId] = s.completedAtMs;
  }
  int durationMin = 0;
  for (final MapEntry<String, int> e in firstMs.entries) {
    final int? last = lastMs[e.key];
    if (last == null) continue;
    durationMin += ((last - e.value) / 60000).round();
  }
  double bestDay = 0;
  for (final double v in volumeByDay.values) {
    if (v > bestDay) bestDay = v;
  }

  // 这一周**刷新**的纪录：只比"这一周之前的全部记录"，本周内的先后不算 ——
  // 否则同一周里练两次，第二次必然"比上一次高"，那不是破纪录，是热身。
  final List<({String name, String detail})> prs =
      _weekPrs(sets: sets, start: start, end: end, exerciseNames: const <String, String>{});

  // 这一周新解锁了几枚徽章：拿"这一周之前的记录"算一遍，两边的差就是新拿到的。
  final List<BadgeStatus> now = badgeStatuses(sets);
  final List<BadgeStatus> before = badgeStatuses(<SetRecord>[
    for (final SetRecord s in sets)
      if (DateTime.fromMillisecondsSinceEpoch(s.completedAtMs).isBefore(start)) s,
  ]);
  final Set<String> nowOn = <String>{
    for (final BadgeStatus b in now)
      if (b.unlocked) b.id,
  };
  final Set<String> beforeOn = <String>{
    for (final BadgeStatus b in before)
      if (b.unlocked) b.id,
  };
  final int newBadges = nowOn.difference(beforeOn).length;

  return WeeklyReport(
    start: start,
    end: end,
    sessions: workoutIds.length,
    activeDays: days.length,
    totalSets: week.length,
    volumeKg: volume,
    durationMin: durationMin,
    exerciseCount: exerciseIds.length,
    distanceM: distance,
    prs: prs,
    badgesUnlocked: newBadges,
    bestDayVolumeKg: bestDay,
  );
}

/// 这一周刷新的纪录。
///
/// 判据：某组**比这一周之前该动作的历史最好成绩**更好。
/// 没有重量的动作比**次数**（引体向上的纪录不可能是公斤）—— 与
/// `progress_data.dart` 的 `personalBests` 同一条口径。
/// 动作名暂时用 id 兜底（`exerciseNames` 为空时）：周报不能因为"查不到名字"就不出。
List<({String name, String detail})> _weekPrs({
  required List<SetRecord> sets,
  required DateTime start,
  required DateTime end,
  required Map<String, String> exerciseNames,
}) {
  final Map<String, double> previousBest = <String, double>{};
  for (final SetRecord s in sets) {
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(s.completedAtMs);
    if (!t.isBefore(start)) continue; // 只看这一周之前的
    final double v = _prValue(s);
    final double? prev = previousBest[s.exerciseId];
    if (prev == null || v > prev) previousBest[s.exerciseId] = v;
  }

  final Map<String, SetRecord> bestInWeek = <String, SetRecord>{};
  for (final SetRecord s in sets) {
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(s.completedAtMs);
    if (t.isBefore(start) || !t.isBefore(end)) continue;
    final SetRecord? cur = bestInWeek[s.exerciseId];
    if (cur == null || _prValue(s) > _prValue(cur)) bestInWeek[s.exerciseId] = s;
  }

  final List<({String name, String detail})> out =
      <({String name, String detail})>[];
  bestInWeek.forEach((String id, SetRecord s) {
    final double? prev = previousBest[id];
    final double v = _prValue(s);
    if (prev == null || v <= prev) return; // 没超过之前的最好 → 不算破纪录
    final String name = exerciseNames[id] ?? id;
    final bool bodyweight = s.weightKg == null || s.weightKg! <= 0;
    out.add((
      name: name,
      detail: bodyweight
          ? '${s.reps} 次（上次最好 ${prev.round()} 次）'
          : '${_kg(s.weightKg!)} kg（上次最好 ${_kg(prev)} kg）',
    ));
  });
  // 稳定顺序：按动作 id 排，免得每次重建顺序都变（列表在界面上会抖）
  out.sort((({String name, String detail}) a,
          ({String name, String detail}) b) =>
      a.name.compareTo(b.name));
  return out;
}

double _prValue(SetRecord s) =>
    (s.weightKg == null || s.weightKg! <= 0) ? s.reps.toDouble() : s.weightKg!;

String _kg(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

/// **周报该不该出现在首页**。
///
/// 两条都要成立：
///   1. 今天是**周一或周二**（周报是"刚过去那一周"的回顾，只在这两天提示；
///      天天顶在首页就成了广告 —— 而"一周只提示两天"也让它有了一点稀缺感）；
///   2. 上一周**至少练过一次**（一次都没练的那一周没什么可回顾的，
///      硬推一张"你上周练了 0 次"的卡只会让人关掉这个功能）。
///
/// ⚠️ 这是**纯函数**，所以"周一给看、周三不给看"这件事能被单测钉住，
/// 不必去改系统时钟。
bool shouldShowWeeklyReport(List<SetRecord> sets, DateTime day) {
  if (day.weekday != DateTime.monday && day.weekday != DateTime.tuesday) {
    return false;
  }
  return !weeklyReportFor(sets, day).isEmpty;
}

/// 周报的**标题日期**（"9 月 28 日 – 10 月 4 日"这种）已经由 [WeeklyReport.rangeLabel] 给。
/// 这个函数只用来给分享卡一张"这一周"的封面数字：本周是本年第几周 ——
/// 用它当 `ShareCard.ordinal`（那一行"第 N 周"），比"第 1 次训练"更贴切。
int weekOrdinal(DateTime day) {
  final DateTime first = DateTime(day.year, 1, 1);
  final int firstWeek = weekIndex(first);
  return weekIndex(day) - firstWeek + 1;
}
