/// 成就徽章的口径自测。
///
/// 这些数字会直接印在「成就」页上，而且是**最容易变成假话**的那类
/// （存一份解锁状态就一定会和训练记录不一致）。它们现在全是算出来的，
/// 所以判据必须逐条钉死 —— 尤其是**边界**（差一点就不该解锁）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/progress/badges.dart';

SetRecord _set({
  required String workout,
  required DateTime at,
  double weight = 60,
  int reps = 8,
  String exercise = 'bench',
  SetType type = SetType.normal,
}) =>
    SetRecord(
      id: '$workout-$exercise-${at.millisecondsSinceEpoch}-$reps',
      workoutId: workout,
      exerciseId: exercise,
      setIndex: 0,
      weightKg: weight,
      reps: reps,
      setType: type,
      completedAtMs: at.millisecondsSinceEpoch,
    );

BadgeStatus _find(List<BadgeStatus> all, String id) =>
    all.firstWhere((BadgeStatus b) => b.id == id);

void main() {
  final DateTime today = DateTime(2026, 10, 5, 20);

  test('一条记录都没有：全部未解锁，且进度是 0 / N（不是 NaN）', () {
    final List<BadgeStatus> all = badgeStatuses(<SetRecord>[], now: today);
    expect(all.every((BadgeStatus b) => !b.unlocked), isTrue);
    expect(all.every((BadgeStatus b) => b.progress == 0), isTrue);
    expect(badgeTally(all).unlocked, 0);
    expect(all.length, badgeTally(all).total);
  });

  test('首训：练过一次就解锁（边界：0 次不解锁）', () {
    expect(_find(badgeStatuses(<SetRecord>[], now: today), 'first_workout').unlocked, isFalse);
    final List<SetRecord> one = <SetRecord>[
      _set(workout: 'w1', at: DateTime(2026, 10, 5, 9)),
    ];
    expect(_find(badgeStatuses(one, now: today), 'first_workout').unlocked, isTrue);
  });

  test('练满 10 次：按 workoutId 去重（一次记 24 组也只算一次）', () {
    final List<SetRecord> sets = <SetRecord>[];
    for (int w = 1; w <= 9; w++) {
      for (int i = 0; i < 3; i++) {
        sets.add(_set(workout: 'w$w', at: DateTime(2026, 9, 1 + w), reps: 5 + i));
      }
    }
    expect(_find(badgeStatuses(sets, now: today), 'ten_workouts').unlocked, isFalse,
        reason: '9 次就是 9 次，组数多不算');
    sets.add(_set(workout: 'w10', at: DateTime(2026, 9, 20)));
    expect(_find(badgeStatuses(sets, now: today), 'ten_workouts').unlocked, isTrue);
  });

  test('百公斤俱乐部：看**单组最重**，不是总容量（边界 99 与 100）', () {
    final List<SetRecord> light = <SetRecord>[
      _set(workout: 'w1', at: DateTime(2026, 10, 4), weight: 99),
      _set(workout: 'w1', at: DateTime(2026, 10, 4, 10), weight: 99, exercise: 'squat'),
    ];
    expect(_find(badgeStatuses(light, now: today), 'hundred_kg').unlocked, isFalse);
    final List<SetRecord> heavy = <SetRecord>[
      _set(workout: 'w1', at: DateTime(2026, 10, 4), weight: 100),
    ];
    final BadgeStatus b = _find(badgeStatuses(heavy, now: today), 'hundred_kg');
    expect(b.unlocked, isTrue);
    expect(b.current, 100);
    expect(b.progress, 1);
  });

  test('单次 5 吨：看**单次最高**，不是累计（两次各 3 吨不解锁）', () {
    final List<SetRecord> sets = <SetRecord>[
      // 每次：10 组 × 100 kg × 3 次 = 3000 kg
      for (int i = 0; i < 10; i++)
        _set(workout: 'w1', at: DateTime(2026, 10, 1, 9), weight: 100, reps: 3, exercise: 'e$i'),
      for (int i = 0; i < 10; i++)
        _set(workout: 'w2', at: DateTime(2026, 10, 2, 9), weight: 100, reps: 3, exercise: 'e$i'),
    ];
    final BadgeStatus b = _find(badgeStatuses(sets, now: today), 'five_ton');
    expect(b.current, 3000, reason: '单次最高是 3000，不是累计 6000');
    expect(b.unlocked, isFalse);
    expect(b.progress, closeTo(0.6, 0.001));
  });

  test('累计 100 吨：这个是**累计**（两次各 3 吨 = 6 吨）', () {
    final List<SetRecord> sets = <SetRecord>[
      for (int i = 0; i < 10; i++)
        _set(workout: 'w1', at: DateTime(2026, 10, 1, 9), weight: 100, reps: 3, exercise: 'e$i'),
      for (int i = 0; i < 10; i++)
        _set(workout: 'w2', at: DateTime(2026, 10, 2, 9), weight: 100, reps: 3, exercise: 'e$i'),
    ];
    expect(_find(badgeStatuses(sets, now: today), 'hundred_ton').current, 6000);
  });

  test('一周不断：连续 7 天解锁，中间断一天只数到断点（与首页同一口径）', () {
    final List<SetRecord> seven = <SetRecord>[
      for (int d = 0; d < 7; d++)
        _set(workout: 'w$d', at: DateTime(2026, 9, 29 + d, 9)),
    ];
    expect(_find(badgeStatuses(seven, now: today), 'week_streak').unlocked, isTrue);

    final List<SetRecord> broken = <SetRecord>[
      for (int d = 0; d < 7; d++)
        if (d != 3) _set(workout: 'w$d', at: DateTime(2026, 9, 29 + d, 9)),
    ];
    final BadgeStatus b = _find(badgeStatuses(broken, now: today), 'week_streak');
    expect(b.unlocked, isFalse);
    // d=3 → 9/29+3 = 10/2 缺席；从今天（10/5）往前数：10/5、10/4、10/3 都在，
    // 到 10/2 断掉 → 连续 3 天
    expect(b.current, 3, reason: '10/2 缺席 → 只连到 10/3 为止三天');
  });

  test('早鸟 / 夜猫：按**组完成时刻**的小时判，边界 7 点与 22 点', () {
    final List<SetRecord> at7 = <SetRecord>[
      _set(workout: 'w', at: DateTime(2026, 10, 5, 7)),
    ];
    expect(_find(badgeStatuses(at7, now: today), 'early_bird').unlocked, isFalse,
        reason: '7 点整不算"7 点前"');
    final List<SetRecord> at6 = <SetRecord>[
      _set(workout: 'w', at: DateTime(2026, 10, 5, 6, 59)),
    ];
    expect(_find(badgeStatuses(at6, now: today), 'early_bird').unlocked, isTrue);

    final List<SetRecord> at22 = <SetRecord>[
      _set(workout: 'w', at: DateTime(2026, 10, 5, 22)),
    ];
    expect(_find(badgeStatuses(at22, now: today), 'night_owl').unlocked, isTrue);
  });

  test('二十个动作：按 exerciseId 去重', () {
    final List<SetRecord> sets = <SetRecord>[
      for (int i = 0; i < 20; i++)
        _set(workout: 'w1', at: DateTime(2026, 10, 5, 9), exercise: 'ex$i'),
      // 同一个动作多记几组不该多算
      _set(workout: 'w1', at: DateTime(2026, 10, 5, 10), exercise: 'ex0'),
    ];
    expect(_find(badgeStatuses(sets, now: today), 'twenty_exercises').current, 20);
  });

  test('稀有度三档都在，而且每枚都有"怎么拿到"的说明', () {
    final List<BadgeStatus> all = badgeStatuses(<SetRecord>[], now: today);
    expect(all.map((BadgeStatus b) => b.tier).toSet(),
        <BadgeTier>{BadgeTier.common, BadgeTier.rare, BadgeTier.epic});
    expect(all.every((BadgeStatus b) => b.how.isNotEmpty), isTrue);
    expect(all.every((BadgeStatus b) => b.name.isNotEmpty), isTrue);
    // id 不许重复（重复了就是同一枚徽章挂两次，页面上看不出来）
    expect(all.map((BadgeStatus b) => b.id).toSet().length, all.length);
  });

  test('已解锁的徽章进度恒为 1（哪怕 current 超过 target）', () {
    final List<SetRecord> many = <SetRecord>[
      for (int i = 0; i < 12; i++) _set(workout: 'w$i', at: DateTime(2026, 9, 20 + i)),
    ];
    final BadgeStatus b = _find(badgeStatuses(many, now: today), 'ten_workouts');
    expect(b.current, 12);
    expect(b.unlocked, isTrue);
    expect(b.progress, 1);
  });
}
