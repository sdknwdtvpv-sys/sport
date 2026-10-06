/// 练了么 · **A3 每周挑战**（2026-10-06 用户拍板）
///
/// **每周一枚、同一周内所有人看到的是同一枚、跨周自动换、过期不补** —— 这三句话决定了
/// 实现只有一种写法：**全部由「周序号」纯函数推导，一个字节都不落库**。
///
/// 为什么坚持不落库（与徽章、连续天数同一条理由）：
///   * 存一张"本周挑战"表，它就会和训练记录不一致 —— 改历史、导入备份、跨时区、换设备恢复，
///     总有一条路能让"你已经拿到的挑战"变成假话；
///   * 而且"上周的挑战"必须**真的消失**（稀缺感的来源）。落库就得写清理逻辑，
///     而清理逻辑是那种"平时都对、跨年那次错"的东西。
///
/// 判定口径：**只统计本周内（周一起）的训练记录**，用现有的 `SetRecord.completedAtMs`。
/// 过期之后 `weekDone` 自然变回 false —— 不补、不留痕。
library;

import '../../domain/models.dart';

/// 一枚"一周内做得到"的挑战。
///
/// [rule] 是纯函数：给"这一周的记录"，返回 0..[target] 的进度。
/// 写成函数而不是"一个数"：这样加新挑战时不必碰统计口径，判据也各自能单测。
class WeeklyChallengeSpec {
  const WeeklyChallengeSpec({
    required this.id,
    required this.name,
    required this.how,
    required this.unit,
    required this.target,
    required this.rule,
  });

  final String id;
  final String name;

  /// 一句话说清怎么完成（成就页那行小字）
  final String how;

  /// 进度的单位（"次" / "天" / "组"）
  final String unit;

  final int target;

  /// 这一周的进度（0..target）。**只吃本周的记录** —— 调用方负责筛。
  final int Function(List<SetRecord> weekSets) rule;
}

/// 一周的起止（周一 00:00 ～ 下周一 00:00，本地时间）。
///
/// 与 `progress_data.dart` 的 `weekWorkoutCount`、计划屏的"本周"同一口径：
/// **周一起算**（`DateTime.monday`），不是周日 —— 全仓库只有一个"一周"的定义。
({DateTime start, DateTime end}) weekBounds(DateTime day) {
  final DateTime monday = DateTime(day.year, day.month, day.day)
      .subtract(Duration(days: day.weekday - DateTime.monday));
  return (start: monday, end: monday.add(const Duration(days: 7)));
}

/// **周序号**：从 1970-01-05（那是个周一）起数到今天这周是第几周。
///
/// 用它而不是 `year*53+week` 那种"年内周号"：后者跨年时会**回头**
/// （第 1 周比第 52 周小），于是"同一周同一枚"成立，但"跨周换一枚"会在元旦那天
/// 换回几个月前的挑战 —— 而且通知的去重键也会撞。从固定纪元起数就没有这个问题：
/// 序号只增不减。
int weekIndex(DateTime day) {
  final DateTime monday = weekBounds(day).start;
  final DateTime epoch = DateTime(1970, 1, 5); // 周一
  return monday.difference(epoch).inDays ~/ 7;
}

/// 这一周还剩几天（**含今天**）。周一 = 7，周日 = 1，周一早上看到的"剩余 7 天"是对的。
int daysLeftInWeek(DateTime day) =>
    7 - (day.weekday - DateTime.monday);

/// 候选池：**都能在一周内达成**（这是入选的唯一标准 —— 一周做不完的挑战是坏挑战：
/// 它只会让用户觉得"反正拿不到"）。
///
/// 顺序**有意义**：`weeklyChallenge` 按周序号取模，所以这张表的顺序决定了
/// "连着几周会拿到什么"。刻意把"练 3 天"排在最前（最容易的那枚开局），
/// 而且相邻两项性质不同（次数 / 天数 / 单次强度 / 部位），不会连着两周是同一类。
List<WeeklyChallengeSpec> weeklyPool() => <WeeklyChallengeSpec>[
      WeeklyChallengeSpec(
        id: 'week_three_sessions',
        name: '本周练 3 次',
        how: '本周完成 3 次训练',
        unit: '次',
        target: 3,
        rule: (List<SetRecord> s) => s.map((SetRecord e) => e.workoutId).toSet().length,
      ),
      WeeklyChallengeSpec(
        id: 'week_four_days',
        name: '本周练满 4 天',
        how: '本周有 4 天记过训练',
        unit: '天',
        target: 4,
        rule: (List<SetRecord> s) => s
            .map((SetRecord e) {
              final DateTime t =
                  DateTime.fromMillisecondsSinceEpoch(e.completedAtMs);
              return t.year * 10000 + t.month * 100 + t.day;
            })
            .toSet()
            .length,
      ),
      WeeklyChallengeSpec(
        id: 'week_total_sets',
        name: '本周 40 组',
        how: '本周累计记满 40 组',
        unit: '组',
        target: 40,
        rule: (List<SetRecord> s) => s.length,
      ),
      WeeklyChallengeSpec(
        id: 'week_upper_sets',
        name: '本周上肢 3 次',
        how: '本周练到 3 次上肢动作（推 / 拉 / 胸 / 肩 / 手臂）',
        unit: '次',
        target: 3,
        rule: (List<SetRecord> s) =>
            s.where((SetRecord e) => _isUpperBody(e.exerciseId)).length,
      ),
      WeeklyChallengeSpec(
        id: 'week_single_8_reps',
        name: '本周单组 8 次',
        how: '本周任意一组做到 8 次以上',
        unit: '次',
        target: 1,
        rule: (List<SetRecord> s) =>
            s.any((SetRecord e) => e.reps >= 8) ? 1 : 0,
      ),
      WeeklyChallengeSpec(
        id: 'week_cardio',
        name: '本周一次有氧',
        how: '本周记下一组有距离的训练',
        unit: '次',
        target: 1,
        rule: (List<SetRecord> s) => s
            .where((SetRecord e) => (e.distanceM ?? 0) > 0)
            .length,
      ),
      WeeklyChallengeSpec(
        id: 'week_legs',
        name: '本周练腿 2 次',
        how: '本周练到 2 次下肢动作（蹲 / 腿 / 臀 / 小腿）',
        unit: '次',
        target: 2,
        rule: (List<SetRecord> s) =>
            s.where((SetRecord e) => _isLowerBody(e.exerciseId)).length,
      ),
      WeeklyChallengeSpec(
        id: 'week_ten_sets_session',
        name: '本周一场 10 组',
        how: '本周任意一次训练记满 10 组',
        unit: '组',
        target: 10,
        rule: (List<SetRecord> s) {
          final Map<String, int> byWorkout = <String, int>{};
          for (final SetRecord e in s) {
            byWorkout[e.workoutId] = (byWorkout[e.workoutId] ?? 0) + 1;
          }
          int best = 0;
          for (final int n in byWorkout.values) {
            if (n > best) best = n;
          }
          return best;
        },
      ),
      WeeklyChallengeSpec(
        id: 'week_two_workouts_one_day',
        name: '本周一天两练',
        how: '同一天完成 2 次训练',
        unit: '次',
        target: 2,
        rule: (List<SetRecord> s) {
          final Map<int, Set<String>> byDay = <int, Set<String>>{};
          for (final SetRecord e in s) {
            final DateTime t =
                DateTime.fromMillisecondsSinceEpoch(e.completedAtMs);
            (byDay[t.year * 10000 + t.month * 100 + t.day] ??= <String>{})
                .add(e.workoutId);
          }
          int best = 0;
          for (final Set<String> ids in byDay.values) {
            if (ids.length > best) best = ids.length;
          }
          return best;
        },
      ),
    ];

/// **本周那一枚**（由 [weekIndex] 取模选出：同一周所有人一样，跨周自动换）。
///
/// 全解锁之后再回到第一枚 —— 池子只有 9 枚，第 10 周会重新从"本周练 3 次"开始。
/// 这是刻意的：挑战的价值是"**这一周**有点事做"，不是"集齐一套"（那是徽章的活）。
WeeklyChallengeSpec weeklySpec(DateTime day) {
  final List<WeeklyChallengeSpec> pool = weeklyPool();
  final int idx = weekIndex(day) % pool.length;
  // Dart 的 % 对正数返回正数，但 weekIndex 在 1970 之前会是负数 —— 兜一下，
  // 免得某个"系统时间被调回 1969"的极端情况把下标搞成负数（那会直接抛下标越界）。
  return pool[(idx + pool.length) % pool.length];
}

/// 这一周的挑战 + 进度 + 到期还剩几天。
class WeeklyChallenge {
  const WeeklyChallenge({
    required this.spec,
    required this.current,
    required this.daysLeft,
    required this.weekStart,
  });

  final WeeklyChallengeSpec spec;

  /// 本周已经做到多少（已封顶到 target）
  final int current;

  /// 本周还剩几天（含今天）
  final int daysLeft;

  /// 这一周的周一（成就页那行"本周"要显示日期时用它）
  final DateTime weekStart;

  bool get done => current >= spec.target;

  /// 0..1 的进度
  double get progress =>
      spec.target <= 0 ? 0 : (current / spec.target).clamp(0.0, 1.0);
}

/// 算出**这一周**的挑战状况。**只看本周的记录**：[sets] 传全量也没关系，
/// 这个函数自己按 [weekBounds] 筛（调用方不必先筛——少一处口径就少一处不一致）。
WeeklyChallenge weeklyChallenge(List<SetRecord> sets, DateTime day) {
  final ({DateTime start, DateTime end}) w = weekBounds(day);
  final List<SetRecord> weekSets = <SetRecord>[
    for (final SetRecord s in sets)
      if (!DateTime.fromMillisecondsSinceEpoch(s.completedAtMs).isBefore(w.start) &&
          DateTime.fromMillisecondsSinceEpoch(s.completedAtMs).isBefore(w.end))
        s,
  ];
  final WeeklyChallengeSpec spec = weeklySpec(day);
  final int raw = spec.rule(weekSets);
  return WeeklyChallenge(
    spec: spec,
    current: raw < 0 ? 0 : (raw > spec.target ? spec.target : raw),
    daysLeft: daysLeftInWeek(day),
    weekStart: w.start,
  );
}

// ── 部位判定：**按动作 id 里的词根**，不查动作库 ──
//
// 为什么不查 `ExerciseRepository`：徽章那一摊（`badges.dart`）已经定过同一条规矩 ——
// `badgeStatuses(sets)` 只吃训练记录，不额外要一份动作表；每周挑战如果非要动作库，
// 它就没法在通知规则、纯函数测试里用同一个入口。
//
// 代价说清楚：这只看 **id 里有没有那个词根**（种子数据的 id 是英文动作名，
// 如 `ex_bb_bench_press`）。用户自建的动作、id 里不含这些词的，就**不算**上肢/下肢 ——
// 宁可少数一次，也不去猜（"猜"会让同一份记录在徽章和挑战里出现两种口径）。
// 这也是为什么这两枚挑战给的是"3 次 / 2 次"这种**够低**的门槛：口径保守，门槛就得更松。
const List<String> _upperRoots = <String>[
  'bench', 'press', 'fly', 'push', 'pull', 'row', 'curl', 'dip', 'raise',
  'lat', 'shrug', 'triceps', 'biceps', 'chest', 'shoulder', 'deltoid', 'pec',
];

const List<String> _lowerRoots = <String>[
  'squat', 'lunge', 'leg', 'calf', 'hip', 'glute', 'deadlift', 'rdl',
  'step_up', 'hamstring', 'quad',
];

bool _isUpperBody(String exerciseId) {
  final String id = exerciseId.toLowerCase();
  return _upperRoots.any(id.contains);
}

bool _isLowerBody(String exerciseId) {
  final String id = exerciseId.toLowerCase();
  return _lowerRoots.any(id.contains);
}

/// **首页那一行**（A3 的第二处落点 / 第二部分第 3 条"一处实现两处用"）。
///
/// 为什么不直接把成就页那块卡搬过来：那一块是给"我想看看这周有什么挑战"的人看的
/// （含怎么算、还剩几天、进度条）；而首页要回答的是"**今天要做什么**"，
/// 挑战只是"这周顺便做到什么"。所以首页给**一行**：挑战名 + 进度就够了。
///
/// 什么时候**不**说（首页每一行都必须有它的理由）：
///   * 这周**已经做完了** → 那一行只会占地方（成就页里仍然能看到"本周已完成"）；
///   * 这一周**只剩下今天**（周日）→ 提示一个马上过期的东西没有意义，
///     不如让它安静地过去（下周一自然换一枚新的）。
///
/// 返回 null = 首页不显示这一行。
String? weeklyChallengeLine(WeeklyChallenge c) {
  if (c.done) return null;
  if (c.daysLeft <= 1) return null;
  return '本周挑战：${c.spec.name} · ${c.current} / ${c.spec.target}${c.spec.unit}'
      '（还剩 ${c.daysLeft} 天）';
}
