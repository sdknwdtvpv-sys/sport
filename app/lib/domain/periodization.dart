/// 练了么 · **周期化计划 v1 的口径**（Ultra 权益 10，纯函数）
///
/// 设计（唯一出处）：`docs/plan-periodization-2026-11-06.md`。
/// 这里只有三种东西：加重/deload 的算术、周窗与完成判定、计划 JSON 的编解码。
/// **UI 里不许再算一遍** —— 否则"卡上写 102.5，训练屏按 100 起"这类错一定会出现。
library;

import 'dart:convert';

import '../core/units.dart' show formatDateSortable;

import 'models.dart' show SetRecord, SetType;

/// 计划状态。`completed` = 走完最后一周；`archived` = 被新计划替换/用户手动归档。
enum PeriodPlanStatus {
  active,
  completed,
  archived;

  static PeriodPlanStatus fromWire(String w) => switch (w) {
        'active' => active,
        'completed' => completed,
        _ => archived,
      };

  String get wire => name;
}

/// 一条课表项（某一周某一天的某个动作）。
class PeriodSessionSpec {
  const PeriodSessionSpec({
    required this.week,
    required this.day,
    required this.position,
    required this.exerciseId,
    this.targetSets = 3,
    this.repsLow = 8,
    this.repsHigh = 10,
    this.targetWeightKg,
  });

  final int week; // 1-based
  final int day; // 1-based
  final int position;
  final String exerciseId;
  final int targetSets;
  final int repsLow;
  final int repsHigh;

  /// null = 自重/按时长，**不加重**（不编重量）。
  final double? targetWeightKg;

  PeriodSessionSpec copyWith({
    int? week,
    int? day,
    int? position,
    int? targetSets,
    int? repsLow,
    int? repsHigh,
    double? targetWeightKg,
    bool clearTargetWeight = false,
  }) =>
      PeriodSessionSpec(
        week: week ?? this.week,
        day: day ?? this.day,
        position: position ?? this.position,
        exerciseId: exerciseId,
        targetSets: targetSets ?? this.targetSets,
        repsLow: repsLow ?? this.repsLow,
        repsHigh: repsHigh ?? this.repsHigh,
        targetWeightKg: clearTargetWeight ? null : (targetWeightKg ?? this.targetWeightKg),
      );
}

/// 一份计划的完整快照（仓储/JSON/UI 共用这一种形状，避免三处各有一个"计划"对象）。
class PeriodPlanSnapshot {
  const PeriodPlanSnapshot({
    required this.id,
    required this.name,
    required this.weeks,
    required this.daysPerWeek,
    required this.startDate,
    required this.currentWeek,
    required this.status,
    required this.sessions,
  });

  final String id;
  final String name;
  final int weeks;
  final int daysPerWeek;

  /// 第 1 周第 1 天（本地日，只取年月日）。
  final DateTime startDate;
  final int currentWeek;
  final PeriodPlanStatus status;
  final List<PeriodSessionSpec> sessions;

  PeriodPlanSnapshot copyWith({
    int? currentWeek,
    PeriodPlanStatus? status,
    List<PeriodSessionSpec>? sessions,
  }) =>
      PeriodPlanSnapshot(
        id: id,
        name: name,
        weeks: weeks,
        daysPerWeek: daysPerWeek,
        startDate: startDate,
        currentWeek: currentWeek ?? this.currentWeek,
        status: status ?? this.status,
        sessions: sessions ?? this.sessions,
      );

  List<PeriodSessionSpec> sessionsOfWeek(int week) =>
      sessions.where((PeriodSessionSpec s) => s.week == week).toList(growable: false)
        ..sort((PeriodSessionSpec a, PeriodSessionSpec b) {
          final int d = a.day.compareTo(b.day);
          return d != 0 ? d : a.position.compareTo(b.position);
        });

  int get totalSessions => sessions.length;
}

/// 允许的模板（与设计文档 §二 一致；`daysPerWeek` 由模板给出）。
const List<({int weeks, int daysPerWeek, String name})> kPeriodizationTemplates =
    <({int weeks, int daysPerWeek, String name})>[
  (weeks: 4, daysPerWeek: 3, name: '4 周入门'),
  (weeks: 6, daysPerWeek: 3, name: '6 周标准'),
  (weeks: 8, daysPerWeek: 4, name: '8 周进阶'),
];

/// 重量步进：v1 全计划统一 2.5 kg（自定义步进留给 v2；与训练屏的默认步进同量级）。
const double kPeriodizationWeightStepKg = 2.5;

/// 每周完成阈值：**≥ 80% 的计划项**（向上取整）。
const double kPeriodizationWeekThreshold = 0.8;

/// deload 周：每第 4 周（4/8 周计划的 W4/W8，6 周计划的 W4）。
bool isDeloadWeek(int week) => week > 0 && week % 4 == 0;

/// 四舍五入到 [step] 的步进（2.5 kg 是器械现实里最常见的加片粒度）。
double roundToStep(double value, double step) {
  if (step <= 0) return value;
  return (value / step).round() * step;
}

/// **某周目标重量**（null = 自重/按时长，永远 null）。
///
/// 普通周：在"无 deload 的正常进度"上每周 +max(2.5, 2.5%)；
/// deload 周：显示同一正常进度值的 90%（向 2.5 kg 步进取整），**不改变下周的正常进度**。
/// 于是 deload 之后一周回到正常线继续涨，而不是从 90% 往上爬。
double? targetWeightForWeek(double? baseWeightKg, int week) {
  if (baseWeightKg == null || baseWeightKg <= 0) return null;
  double normal = baseWeightKg;
  for (int w = 2; w <= week; w += 1) {
    final double pct = normal * 0.025;
    final double inc = pct < kPeriodizationWeightStepKg
        ? kPeriodizationWeightStepKg
        : roundToStep(pct, kPeriodizationWeightStepKg);
    normal += inc;
  }
  if (isDeloadWeek(week)) {
    return roundToStep(normal * 0.9, kPeriodizationWeightStepKg);
  }
  return normal;
}

/// 第 [week] 周的课表（目标重量按周重算；组数/次数不变）。
List<PeriodSessionSpec> sessionsForWeek(PeriodPlanSnapshot plan, int week) {
  final List<PeriodSessionSpec> base =
      plan.sessions.where((PeriodSessionSpec s) => s.week == 1).toList(growable: false);
  final List<PeriodSessionSpec> out = <PeriodSessionSpec>[];
  for (final PeriodSessionSpec s in base) {
    out.add(PeriodSessionSpec(
      week: week,
      day: s.day,
      position: s.position,
      exerciseId: s.exerciseId,
      targetSets: s.targetSets,
      repsLow: s.repsLow,
      repsHigh: s.repsHigh,
      targetWeightKg: targetWeightForWeek(s.targetWeightKg, week),
    ));
  }
  return out;
}

/// 周窗：`[startDate + 7*(week-1), startDate + 7*week)`（本地日，左闭右开）。
({DateTime start, DateTime end}) periodWeekWindow(DateTime startDate, int week) {
  final DateTime base = DateTime(startDate.year, startDate.month, startDate.day);
  return (start: base.add(Duration(days: 7 * (week - 1))), end: base.add(Duration(days: 7 * week)));
}

/// 某周完成了多少项（一项 = 某天某动作；本周内至少一条正式组即算完成）。
class PeriodWeekCompletion {
  const PeriodWeekCompletion({
    required this.total,
    required this.done,
    required this.required,
  });

  final int total;
  final int done;

  /// 达标所需的最小项数 = `ceil(total × 0.8)`。
  final int required;

  bool get isComplete => total > 0 && done >= required;

  int get missing => isComplete ? 0 : (required - done);
}

PeriodWeekCompletion evaluateWeekCompletion({
  required PeriodPlanSnapshot plan,
  required int week,
  required List<SetRecord> sets,
}) {
  final List<PeriodSessionSpec> target = plan.sessionsOfWeek(week);
  final ({DateTime start, DateTime end}) win = periodWeekWindow(plan.startDate, week);
  final int startMs = win.start.millisecondsSinceEpoch;
  final int endMs = win.end.millisecondsSinceEpoch;
  final Set<String> loggedExercises = <String>{
    for (final SetRecord s in sets)
      if (s.setType == SetType.normal && s.completedAtMs >= startMs && s.completedAtMs < endMs)
        s.exerciseId,
  };
  int done = 0;
  for (final PeriodSessionSpec t in target) {
    if (loggedExercises.contains(t.exerciseId)) done += 1;
  }
  final int required = target.isEmpty ? 0 : (target.length * kPeriodizationWeekThreshold).ceil();
  return PeriodWeekCompletion(total: target.length, done: done, required: required);
}

/// 推进判定的结果（纯值；仓储负责写库）。
class PeriodAdvanceResult {
  const PeriodAdvanceResult({required this.currentWeek, required this.status, required this.completion});

  final int currentWeek;
  final PeriodPlanStatus status;
  final PeriodWeekCompletion completion;

  bool get advanced => completion.isComplete;
}

/// 打开计划时算"现在应该在第几周"。
///
/// * 本周没练满 → **不推进**（返回原周；不惩罚、不删数据）；
/// * 本周练满且不是最后一周 → `currentWeek + 1`；
/// * 最后一周练满 → `status = completed`。
PeriodAdvanceResult advanceAfterWeek({
  required PeriodPlanSnapshot plan,
  required List<SetRecord> sets,
}) {
  if (plan.status != PeriodPlanStatus.active) {
    return PeriodAdvanceResult(
      currentWeek: plan.currentWeek,
      status: plan.status,
      completion: const PeriodWeekCompletion(total: 0, done: 0, required: 0),
    );
  }
  final PeriodWeekCompletion c =
      evaluateWeekCompletion(plan: plan, week: plan.currentWeek, sets: sets);
  if (!c.isComplete) {
    return PeriodAdvanceResult(currentWeek: plan.currentWeek, status: plan.status, completion: c);
  }
  if (plan.currentWeek >= plan.weeks) {
    return PeriodAdvanceResult(currentWeek: plan.currentWeek, status: PeriodPlanStatus.completed, completion: c);
  }
  return PeriodAdvanceResult(currentWeek: plan.currentWeek + 1, status: PeriodPlanStatus.active, completion: c);
}

// ────────────────────────────────────────────── JSON 导入/导出（v1）

/// 计划 JSON 的当前版本。**加字段/改语义时必须 +1**，并同时改本文件与设计文档。
const int kPeriodPlanJsonVersion = 1;

class PeriodPlanParseResult {
  const PeriodPlanParseResult._({this.plan, this.error});

  final PeriodPlanSnapshot? plan;
  final String? error;

  bool get ok => plan != null;
}

String _dateKey(DateTime d) => formatDateSortable(d);

PeriodPlanParseResult parsePeriodPlanJson(String text) {
  Object? raw;
  try {
    raw = jsonDecode(text);
  } catch (_) {
    return const PeriodPlanParseResult._(error: '不是合法的 JSON 文件。');
  }
  if (raw is! Map<String, Object?>) {
    return const PeriodPlanParseResult._(error: '计划文件的顶层必须是一个对象。');
  }
  final String? unknownTop = _rejectUnknown(raw, <String>{'version', 'plan'}, '');
  if (unknownTop != null) return PeriodPlanParseResult._(error: unknownTop);
  final int? version = _asInt(raw['version']);
  if (version == null) return const PeriodPlanParseResult._(error: '缺少字段：version。');
  if (version != kPeriodPlanJsonVersion) {
    return PeriodPlanParseResult._(
        error: '这份计划来自更新版本（v$version），当前版本（v$kPeriodPlanJsonVersion）读不了。');
  }
  final Object? p = raw['plan'];
  if (p is! Map<String, Object?>) {
    return const PeriodPlanParseResult._(error: '缺少字段：plan（应当是一个对象）。');
  }
  final Set<String> planKeys = <String>{
    'name', 'weeks', 'days_per_week', 'start_date', 'current_week', 'status', 'sessions',
  };
  final String? unknownPlan = _rejectUnknown(p, planKeys, 'plan.');
  if (unknownPlan != null) return PeriodPlanParseResult._(error: unknownPlan);

  final String? name = p['name'] is String && (p['name'] as String).trim().isNotEmpty
      ? (p['name'] as String).trim()
      : null;
  if (name == null) return const PeriodPlanParseResult._(error: '缺少字段：plan.name。');
  final int? weeks = _asInt(p['weeks']);
  final int? days = _asInt(p['days_per_week']);
  if (weeks == null) return const PeriodPlanParseResult._(error: '缺少字段：plan.weeks。');
  if (days == null) return const PeriodPlanParseResult._(error: '缺少字段：plan.days_per_week。');
  if (!<int>{4, 6, 8}.contains(weeks)) {
    return const PeriodPlanParseResult._(error: 'plan.weeks 只能是 4 / 6 / 8。');
  }
  if (days != 3 && days != 4) {
    return const PeriodPlanParseResult._(error: 'plan.days_per_week 只能是 3 / 4。');
  }
  final DateTime? start = _parseDate(p['start_date']);
  if (start == null) {
    return const PeriodPlanParseResult._(error: 'plan.start_date 必须是 YYYY-MM-DD。');
  }
  final int? currentWeek = _asInt(p['current_week']);
  if (currentWeek == null || currentWeek < 1 || currentWeek > weeks) {
    return PeriodPlanParseResult._(
        error: 'plan.current_week 必须在 1..$weeks 之间。');
  }
  final String statusWire = p['status'] is String ? p['status'] as String : '';
  if (!<String>{'active', 'completed', 'archived'}.contains(statusWire)) {
    return const PeriodPlanParseResult._(error: 'plan.status 只能是 active / completed / archived。');
  }
  final Object? sessionRaw = p['sessions'];
  if (sessionRaw is! List || sessionRaw.isEmpty) {
    return const PeriodPlanParseResult._(error: 'plan.sessions 不能为空。');
  }
  final Set<String> seen = <String>{};
  final List<PeriodSessionSpec> sessions = <PeriodSessionSpec>[];
  for (int i = 0; i < sessionRaw.length; i += 1) {
    final Object? item = sessionRaw[i];
    if (item is! Map<String, Object?>) {
      return PeriodPlanParseResult._(error: '第 ${i + 1} 条课表不是对象。');
    }
    const Set<String> keys = <String>{
      'week', 'day', 'position', 'exercise_id', 'target_sets', 'reps_low', 'reps_high', 'target_weight_kg',
    };
    final String? unknown = _rejectUnknown(item, keys, 'plan.sessions[$i].');
    if (unknown != null) return PeriodPlanParseResult._(error: unknown);
    final int? w = _asInt(item['week']);
    final int? d = _asInt(item['day']);
    final int? pos = _asInt(item['position']);
    final String? ex = item['exercise_id'] is String && (item['exercise_id'] as String).isNotEmpty
        ? item['exercise_id'] as String
        : null;
    final int? sets = _asInt(item['target_sets']);
    final int? low = _asInt(item['reps_low']);
    final int? high = _asInt(item['reps_high']);
    if (w == null || d == null || pos == null || ex == null || sets == null || low == null || high == null) {
      return PeriodPlanParseResult._(error: '第 ${i + 1} 条课表缺少字段。');
    }
    if (w < 1 || w > weeks) {
      return PeriodPlanParseResult._(error: '第 ${i + 1} 条课表的 week 超出 1..$weeks。');
    }
    if (d < 1 || d > days) {
      return PeriodPlanParseResult._(error: '第 ${i + 1} 条课表的 day 超出 1..$days。');
    }
    if (pos < 0) {
      return PeriodPlanParseResult._(error: '第 ${i + 1} 条课表的 position 不能为负。');
    }
    if (sets < 1 || sets > 10) {
      return PeriodPlanParseResult._(error: '第 ${i + 1} 条课表的 target_sets 必须在 1..10。');
    }
    if (low < 1 || high < low || high > 600) {
      return PeriodPlanParseResult._(error: '第 ${i + 1} 条课表的次数范围不合法。');
    }
    double? weight;
    final Object? wr = item['target_weight_kg'];
    if (wr != null) {
      final num? n = wr is num ? wr : num.tryParse('$wr');
      if (n == null || n <= 0) {
        return PeriodPlanParseResult._(error: '第 ${i + 1} 条课表的 target_weight_kg 必须大于 0（自重请写 null）。');
      }
      weight = n.toDouble();
    }
    final String key = '$w/$d/$pos';
    if (!seen.add(key)) {
      return PeriodPlanParseResult._(error: '课表里有重复的位置：第 $w 周第 $d 天 position=$pos。');
    }
    sessions.add(PeriodSessionSpec(
      week: w,
      day: d,
      position: pos,
      exerciseId: ex,
      targetSets: sets,
      repsLow: low,
      repsHigh: high,
      targetWeightKg: weight,
    ));
  }

  return PeriodPlanParseResult._(
    plan: PeriodPlanSnapshot(
      id: '', // 导入时由仓储重新生成
      name: name,
      weeks: weeks,
      daysPerWeek: days,
      startDate: start,
      currentWeek: currentWeek,
      status: PeriodPlanStatus.fromWire(statusWire),
      sessions: sessions,
    ),
  );
}

String encodePeriodPlanJson(PeriodPlanSnapshot plan) {
  final Map<String, Object?> json = <String, Object?>{
    'version': kPeriodPlanJsonVersion,
    'plan': <String, Object?>{
      'name': plan.name,
      'weeks': plan.weeks,
      'days_per_week': plan.daysPerWeek,
      'start_date': _dateKey(plan.startDate),
      'current_week': plan.currentWeek,
      'status': plan.status.wire,
      'sessions': <Object?>[
        for (final PeriodSessionSpec s in plan.sessions)
          <String, Object?>{
            'week': s.week,
            'day': s.day,
            'position': s.position,
            'exercise_id': s.exerciseId,
            'target_sets': s.targetSets,
            'reps_low': s.repsLow,
            'reps_high': s.repsHigh,
            'target_weight_kg': s.targetWeightKg,
          },
      ],
    },
  };
  return const JsonEncoder.withIndent('  ').convert(json);
}

String? _rejectUnknown(Map<String, Object?> map, Set<String> allowed, String prefix) {
  for (final String k in map.keys) {
    if (!allowed.contains(k)) return '拒绝未知字段：$prefix$k';
  }
  return null;
}

int? _asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));

DateTime? _parseDate(Object? v) {
  if (v is! String) return null;
  final RegExp re = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  final RegExpMatch? m = re.firstMatch(v);
  if (m == null) return null;
  final int y = int.parse(m.group(1)!);
  final int mo = int.parse(m.group(2)!);
  final int d = int.parse(m.group(3)!);
  final DateTime dt = DateTime(y, mo, d);
  // 拒绝 2026-02-30 这类"解析了但不存在"的日期（DateTime 会自动滚到 3 月）
  if (dt.year != y || dt.month != mo || dt.day != d) return null;
  return dt;
}
