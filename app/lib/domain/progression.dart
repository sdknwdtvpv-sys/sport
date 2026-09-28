/// 练了么 · 渐进建议引擎（Dart 实现）
///
/// **这是 `engine/progression.mjs` 的移植版，两者必须行为一致。**
/// 一致性由 `app/test/progression_vectors_test.dart` 保证：它读取仓库根目录的
/// `engine/vectors.json`（与 JS 端同一份文件，不复制），逐条比对。
///
/// 移植时踩到的第一个坑：Dart 打印 double 会输出 `2.0`，而 JS 输出 `2`，
/// 直接影响 reasonText 里的「+2kg」。所以下面所有数字都过 `_fmt`。
library;

import 'dart:math' as math;

import 'models.dart';

/// 超过这个天数没练该动作，触发回归保护。
const int kStaleDays = 21;

/// 自重动作次数上限 = 目标区间上限 + 该值。
const int kBodyweightRepCapBonus = 5;

/// 按时长动作每次推进多少秒。
const int kTimeStepSec = 5;

/// 按时长动作的上限 = 目标区间上限 + 该值（秒）。
const int kTimeCapBonus = 15;

/// 连续手改达到此次数后，不再自作主张。
const int kOverrideMinCount = 3;

/// 消除浮点噪声（保留两位小数）。
///
/// ⚠️ 原注释举的例子是错的：`60.1 + 2.5` 在 IEEE754 下**正好等于 62.6**。
/// 实测 0.1–400 kg、步长 2 / 2.5 / 5 全范围内单次加法都是正确舍入的
/// （变异测试暴露了这个等价变异体：去掉 `_round2`，没有一条测试会红）。
/// 它真正非它不可的地方是**除法** —— `estimate1RM` 里的 `weight × (1 + reps/30)`。
double _round2(double n) => (n * 100).round() / 100;

/// 模仿 JS 的数字字面量输出：2.5 → "2.5"，2.0 → "2"，5.0 → "5"。
/// 这是 JS/Dart 跨语言一致性最容易漏的一处。
String _fmt(double n) {
  if (n == n.roundToDouble()) return n.toInt().toString();
  return n.toString();
}

class _Preferred {
  const _Preferred(this.weightKg, this.reps, this.count);
  final double weightKg;
  final int reps;
  final int count;
}

/// 用户是否已连续多次把同一动作手改成同一个值。
_Preferred? _preferredOverride(List<ManualOverride> overrides) {
  if (overrides.length < kOverrideMinCount) return null;
  final head = overrides.first;
  var count = 0;
  for (final o in overrides) {
    if (o.weightKg == head.weightKg && o.reps == head.reps) {
      count++;
    } else {
      break;
    }
  }
  return count >= kOverrideMinCount ? _Preferred(head.weightKg, head.reps, count) : null;
}

/// 给出下一组的建议。返回 null 表示"不给建议"（用户关闭了建议）。
///
/// 判定顺序**不可调整**，每一步都有对应的测试向量：
///   off → 用户偏好 → 零历史 → 长期未练 → **按时长分支** → 自重分支 → 组数不足 → 达标加重 → 掉组保持 → 加次数
Suggestion? suggestNext({
  required ExerciseSpec exercise,
  required PlanTarget plan,
  LastSession? lastSession,
  UserProfile profile = const UserProfile(),
  List<ManualOverride> overrides = const <ManualOverride>[],
}) {
  // 0) 用户关掉了建议：直接闭嘴，这是设置项赋予的权利
  if (profile.progressionMode == ProgressionMode.off) return null;

  final inc = exercise.weightIncrement;
  final isBodyweight = exercise.isBodyweight;
  // 按时长的动作：这个数字是**秒**不是次数。缺省 weight_reps，行为向后兼容。
  final isTime = exercise.isTime;
  final sets = plan.targetSets;
  final repsLow = plan.targetRepsLow;
  final repsHigh = plan.targetRepsHigh;

  // 1) 用户连续手改 ≥3 次 → 沿用他的值（先于一切自动判断）
  final pref = _preferredOverride(overrides);
  if (pref != null) {
    return Suggestion(
      weightKg: pref.weightKg,
      reps: pref.reps,
      reasonCode: ReasonCode.userPreferred,
      reasonText: '按你最近 ${pref.count} 次手动设置的重量',
    );
  }

  // 2) 该动作零历史 → 动作库起始重量
  if (lastSession == null) {
    return Suggestion(
      weightKg: isBodyweight ? null : (exercise.defaultWeightKg ?? plan.targetWeightKg),
      reps: repsLow,
      reasonCode: ReasonCode.firstTime,
      reasonText: isBodyweight
          ? (isTime
              ? '第一次练这个动作，先记录你能坚持的秒数'
              : '第一次练这个动作，先记录你能完成的次数')
          : '第一次练这个动作，先从这个重量开始',
    );
  }

  final completed = lastSession.completedSets;
  final minReps = lastSession.minReps;
  final lastW = lastSession.weightKg ?? 0;
  final days = lastSession.daysAgo;

  // 3) 长期未练 → 回归保护。先于一切进度判断：三周前的数据不足以支撑加重
  if (days >= kStaleDays) {
    return Suggestion(
      weightKg: isBodyweight ? null : _round2(lastW),
      reps: repsLow,
      reasonCode: ReasonCode.deload,
      reasonText: '已经有 $days 天没练这个动作，先按上次重量找回感觉',
    );
  }

  // 4) 按时长的动作：这个量是**秒**不是次数，推进方式是加秒数。
  //    没有这一支，平板支撑会被按"次数"往上加，还会说出
  //    「自重已完成 30 次，建议加负重」这种让用户一眼看出不懂健身的话。
  if (isTime) {
    final double? keepW = isBodyweight ? null : _round2(lastW);
    if (completed < sets) {
      return Suggestion(
        weightKg: keepW,
        reps: repsLow,
        reasonCode: ReasonCode.hold,
        reasonText: '上次只完成 $completed 组（计划 $sets 组），先把组数补满',
      );
    }
    final int cap = repsHigh + kTimeCapBonus;
    if (minReps >= cap) {
      if (isBodyweight) {
        return Suggestion(
          weightKg: null,
          reps: cap,
          reasonCode: ReasonCode.addRep,
          reasonText: '已能坚持 $minReps 秒，建议加负重',
        );
      }
      // 负重时长（负重平板）：它是有重量的，到时长上限就直接加重
      return Suggestion(
        weightKg: _round2(lastW + inc),
        reps: repsLow,
        reasonCode: ReasonCode.linearProgress,
        reasonText: '已能坚持 $minReps 秒（上限 $cap 秒），加重 +${_fmt(inc)}kg',
      );
    }
    final int nextTime = math.min(minReps + kTimeStepSec, cap);
    return Suggestion(
      weightKg: keepW,
      reps: nextTime,
      reasonCode: ReasonCode.addRep,
      reasonText: minReps >= repsHigh
          ? '时长已达目标上限，按秒推进：$minReps → $nextTime 秒'
          : '按秒推进：$minReps → $nextTime 秒',
    );
  }

  // 5) 自重动作：唯一可行的推进方式是加次数
  if (isBodyweight) {
    if (completed < sets) {
      return Suggestion(
        weightKg: null,
        reps: repsLow,
        reasonCode: ReasonCode.hold,
        reasonText: '上次只完成 $completed 组（计划 $sets 组），先把组数补满',
      );
    }
    final cap = repsHigh + kBodyweightRepCapBonus;
    if (minReps >= cap) {
      return Suggestion(
        weightKg: null,
        reps: cap,
        reasonCode: ReasonCode.addRep,
        reasonText: '自重已完成 $minReps 次，建议加负重',
      );
    }
    final next = math.min(minReps + (minReps >= repsHigh ? 2 : 1), cap);
    return Suggestion(
      weightKg: null,
      reps: next,
      reasonCode: ReasonCode.addRep,
      reasonText: minReps >= repsHigh
          ? '次数已到上限，先加到 $next 次，之后考虑负重'
          : '自重动作先加次数：$minReps → $next 次',
    );
  }

  // 6) 组数没做满 → 先补组数，不加重量
  if (completed < sets) {
    return Suggestion(
      weightKg: _round2(lastW),
      reps: repsLow,
      reasonCode: ReasonCode.hold,
      reasonText: '上次只完成 $completed 组（计划 $sets 组），先把组数补满',
    );
  }

  // 7) 全部达标 → 双重渐进的"加重量"分支
  if (minReps >= repsHigh) {
    return Suggestion(
      weightKg: _round2(lastW + inc),
      reps: repsLow,
      reasonCode: ReasonCode.linearProgress,
      reasonText: '上次 $completed 组全部达标，线性加重 +${_fmt(inc)}kg',
    );
  }

  // 8) 有组掉到区间下限以下 → 保持重量（不加重也不降重，先看是不是偶发）
  if (minReps < repsLow) {
    return Suggestion(
      weightKg: _round2(lastW),
      reps: repsLow,
      reasonCode: ReasonCode.hold,
      reasonText: '上次有组掉到 $minReps 次，先保持重量',
    );
  }

  // 9) 中间态 → 重量不变，加次数
  final next = math.min(minReps + 1, repsHigh);
  return Suggestion(
    weightKg: _round2(lastW),
    reps: next,
    reasonCode: ReasonCode.addRep,
    reasonText: '上次差一点达标，先把每组次数补到 $next',
  );
}

/// 估算 1RM（Epley）。仅在 reps ≤ 12 时可信，超出返回 null —— 高次数下的估算会误导用户。
double? estimate1RM(double? weightKg, int? reps) {
  if (weightKg == null || reps == null) return null;
  if (weightKg <= 0 || reps <= 0 || reps > 12) return null;
  return _round2(weightKg * (1 + reps / 30));
}
