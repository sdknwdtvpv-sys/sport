/// 练了么 · **回归激励**（第二部分第 9 条，2026-10-06 用户拍板）
///
/// 一句话：**连续 7 天没练 → 首页那条轻量入口置顶并换文案**。
///
/// 为什么是"轻量入口"而不是主按钮：断了一周的人对"开始今天的训练"是有压力的
/// （那意味着又是一整场）。产品里唯一为这一刻准备的东西就是那条 5 分钟活动。
/// 所以这一刻不该加大按钮的强度，而该把**门槛最低的那条路**挪到最显眼处。
///
/// 与 `streak.dart` 同一条纪律：**算出来的，不落库**（"多久没练"存一份就会和记录不一致）。
///
/// ⚠️ 这里只说事实 + 一句许可（"也算一次"），**不制造愧疚**：
/// 文案里没有感叹号、没有"你已落后"、也没有把天数做成红字。
library;

import '../../domain/models.dart';

/// 触发回归文案的天数阈值。
const int kComebackDays = 7;

/// 距离上一次训练过去了几天（按**本地日**算，不是"距今 24 小时"）。
///
/// 从来没有练过时返回 null —— "0 天没练"与"从没练过"是两件事，
/// 后者该说的是"开始第一次"，不是"回归"。
int? daysSinceLastWorkout(List<SetRecord> sets, DateTime day) {
  if (sets.isEmpty) return null;
  final DateTime today = DateTime(day.year, day.month, day.day);
  DateTime? last;
  for (final SetRecord s in sets) {
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(s.completedAtMs);
    final DateTime d = DateTime(t.year, t.month, t.day);
    if (d.isAfter(today)) continue; // 未来时间的记录不算（时钟偏移）
    if (last == null || d.isAfter(last)) last = d;
  }
  if (last == null) return null;
  return today.difference(last).inDays;
}

/// 要不要把轻量入口置顶并换文案。**7 天没练**是判据。
bool shouldNudgeComeback(List<SetRecord> sets, DateTime day) {
  final int? d = daysSinceLastWorkout(sets, day);
  return d != null && d >= kComebackDays;
}

/// 那一条文案。没有到阈值时返回 null（调用方据此什么都不显示）。
///
/// 三件事缺一不可：**事实**（"已经 9 天没练了"，不修饰）、
/// **许可**（"5 分钟也算一次"，门槛低到不可能失败）、
/// **去路**（"先动一下就好"）。刻意不写"重新开始"——那个词太重。
String? comebackCopy(List<SetRecord> sets, DateTime day) {
  final int? d = daysSinceLastWorkout(sets, day);
  if (d == null || d < kComebackDays) return null;
  return '已经 $d 天没练了 —— 先做 5 分钟活动，也算一次。';
}
