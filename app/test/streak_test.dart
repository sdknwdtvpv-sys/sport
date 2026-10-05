/// 「连续打卡天数」的口径自测。
///
/// 这个数字会直接印在首页上，而且是**最容易变成假话**的那种数字
/// （存一份就会和训练记录不一致）。它现在完全是算出来的，所以口径必须钉死。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/progress/progress_data.dart';
import 'package:lianleme/features/progress/streak.dart';

SetRecord _set(String id, DateTime at, {SetType type = SetType.normal}) => SetRecord(
      id: id,
      workoutId: 'w-$id',
      exerciseId: 'bench',
      setIndex: 0,
      weightKg: 60,
      reps: 8,
      setType: type,
      completedAtMs: at.millisecondsSinceEpoch,
    );

void main() {
  final DateTime today = DateTime(2026, 10, 5, 20);

  test('今天练过 → 从今天往前数连续天数', () {
    final List<SetRecord> sets = <SetRecord>[
      _set('a', DateTime(2026, 10, 5, 9)),
      _set('b', DateTime(2026, 10, 4, 9)),
      _set('c', DateTime(2026, 10, 3, 9)),
    ];
    expect(currentStreak(sets, today), 3);
  });

  test('今天还没练 → 从昨天数（今天没过完，账不该先扣）', () {
    final List<SetRecord> sets = <SetRecord>[
      _set('b', DateTime(2026, 10, 4, 9)),
      _set('c', DateTime(2026, 10, 3, 9)),
    ];
    expect(currentStreak(sets, today), 2);
  });

  test('中间断了一天 → 只数到断点', () {
    final List<SetRecord> sets = <SetRecord>[
      _set('a', DateTime(2026, 10, 5, 9)),
      _set('b', DateTime(2026, 10, 4, 9)),
      // 10/3 没练
      _set('d', DateTime(2026, 10, 2, 9)),
    ];
    expect(currentStreak(sets, today), 2);
  });

  test('一次都没练 → 0（不是 1，也不是崩）', () {
    expect(currentStreak(<SetRecord>[], today), 0);
  });

  test('昨天的也算"还没断"，但前天练过、昨天没练 → 归零', () {
    expect(currentStreak(<SetRecord>[_set('b', DateTime(2026, 10, 4, 9))], today), 1);
    expect(currentStreak(<SetRecord>[_set('c', DateTime(2026, 10, 3, 9))], today), 0);
  });

  test('只有热身组不算练过（与提醒、周次数同一口径）', () {
    final List<SetRecord> sets = <SetRecord>[
      _set('a', DateTime(2026, 10, 5, 9), type: SetType.warmup),
      _set('b', DateTime(2026, 10, 4, 9)),
    ];
    expect(currentStreak(sets, today), 1, reason: '今天只有热身 → 从昨天数，得 1');
  });

  test('同一天多组只算一天', () {
    final List<SetRecord> sets = <SetRecord>[
      _set('a', DateTime(2026, 10, 5, 9)),
      _set('a2', DateTime(2026, 10, 5, 10)),
      _set('a3', DateTime(2026, 10, 5, 11)),
    ];
    expect(currentStreak(sets, today), 1);
  });

  test('里程碑：下一档与还差几天，到顶返回 null / 0', () {
    expect(nextStreakMilestone(0), 7);
    expect(nextStreakMilestone(7), 30);
    expect(daysToNextMilestone(3), 4);
    expect(daysToNextMilestone(7), 23);
    expect(nextStreakMilestone(400), isNull);
    expect(daysToNextMilestone(400), 0);
  });

  test('文案：0 天不说"0 天"（那读起来像"你什么都没有"）', () {
    expect(streakCopy(0), contains('就开始记'));
    expect(streakCopy(3), contains('再坚持 4 天'));
    expect(streakCopy(400), contains('习惯'));
  });

  test('最近训练：按最后一次的时间倒序，动作数去重、容量求和', () {
    final List<SetRecord> sets = <SetRecord>[
      SetRecord(id: '1', workoutId: 'w1', exerciseId: 'bench', setIndex: 0, weightKg: 60, reps: 8, completedAtMs: DateTime(2026, 10, 1, 9).millisecondsSinceEpoch),
      SetRecord(id: '2', workoutId: 'w1', exerciseId: 'fly', setIndex: 1, weightKg: 20, reps: 10, completedAtMs: DateTime(2026, 10, 1, 9, 30).millisecondsSinceEpoch),
      SetRecord(id: '3', workoutId: 'w2', exerciseId: 'squat', setIndex: 0, weightKg: 100, reps: 5, completedAtMs: DateTime(2026, 10, 3, 9).millisecondsSinceEpoch),
    ];
    final List<({String workoutId, DateTime day, int exercises, int sets, double volume})> r =
        recentWorkouts(sets);
    expect(r.length, 2);
    expect(r.first.workoutId, 'w2', reason: '更晚的那次排前面');
    expect(r.first.exercises, 1);
    expect(r.first.volume, 500);
    expect(r.last.workoutId, 'w1');
    expect(r.last.exercises, 2);
    expect(r.last.volume, 60 * 8 + 20 * 10);
    expect(recentWorkouts(sets, limit: 1).length, 1);
    expect(recentWorkouts(<SetRecord>[]), isEmpty);
  });
}
