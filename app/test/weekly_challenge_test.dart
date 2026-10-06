/// A3 每周挑战的判据自测（2026-10-06 拍板）。
///
/// 这一套最容易出的三种错（都会让用户觉得"这游戏在骗我"）：
///   1. **同一周换了一枚**（那就不叫"每周挑战"了，叫"每次打开都变"）；
///   2. **跨周不换**（上周已完成的挑战这周还是"已完成"，稀缺感没了）；
///   3. **把上周的记录算进本周**（"过期作废"就成了假话）。
/// 三条都逐条钉在这里。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/progress/weekly_challenge.dart';

SetRecord _set({
  required String workout,
  required DateTime at,
  String exercise = 'ex_bb_bench_press',
  int reps = 8,
  double? distanceM,
}) =>
    SetRecord(
      id: '$workout-${at.millisecondsSinceEpoch}-$exercise',
      workoutId: workout,
      exerciseId: exercise,
      setIndex: 0,
      reps: reps,
      distanceM: distanceM,
      completedAtMs: at.millisecondsSinceEpoch,
    );

void main() {
  // 2026-10-05 是周一（这一周：10/5 ~ 10/11）
  final DateTime monday = DateTime(2026, 10, 5, 19);

  group('周序号与取模', () {
    test('同一周内任何一天拿到的是同一枚（周一起算，周日仍属本周）', () {
      final List<String> ids = <String>[
        for (int d = 0; d < 7; d++)
          weeklySpec(DateTime(2026, 10, 5 + d, 9)).id,
      ];
      expect(ids.toSet().length, 1, reason: '周一到周日的七天必须是同一枚');
      // 周日 10/11 的"下一周"是 10/12
      expect(weeklySpec(DateTime(2026, 10, 11, 23)).id,
          weeklySpec(DateTime(2026, 10, 5, 1)).id);
      expect(weeklySpec(DateTime(2026, 10, 12, 1)).id,
          isNot(weeklySpec(DateTime(2026, 10, 11, 23)).id),
          reason: '跨到下周必须换一枚');
    });

    test('周序号只增不减（跨年不会回头 —— 回头会让通知去重键撞上）', () {
      int prev = weekIndex(DateTime(2026, 12, 28));
      for (int d = 1; d <= 40; d++) {
        final int now = weekIndex(DateTime(2026, 12, 28).add(Duration(days: d * 7)));
        expect(now, greaterThan(prev));
        prev = now;
      }
    });

    test('剩余天数：周一 7 天、周日 1 天（含今天）', () {
      expect(daysLeftInWeek(DateTime(2026, 10, 5)), 7);
      expect(daysLeftInWeek(DateTime(2026, 10, 11)), 1);
    });

    test('连续几周拿到的是不同枚（池子轮着来，不会连着两周同一枚）', () {
      final List<String> ids = <String>[
        for (int w = 0; w < weeklyPool().length; w++)
          weeklySpec(DateTime(2026, 10, 5).add(Duration(days: w * 7))).id,
      ];
      expect(ids.toSet().length, ids.length, reason: '一个池子周期内不许重复');
    });
  });

  group('判定只吃本周记录', () {
    test('★ 上周的记录不算进本周（过期就是过期）', () {
      final List<SetRecord> lastWeek = <SetRecord>[
        _set(workout: 'w1', at: DateTime(2026, 9, 28, 19)), // 上周一
        _set(workout: 'w2', at: DateTime(2026, 9, 30, 19)),
        _set(workout: 'w3', at: DateTime(2026, 10, 2, 19)),
      ];
      final WeeklyChallenge c = weeklyChallenge(lastWeek, monday);
      expect(c.current, 0, reason: '上周练了三次，本周进度必须是 0');
      expect(c.done, isFalse);
    });

    test('本周日的 23:59 还算本周；下周一 00:00 就不算了', () {
      final List<SetRecord> sets = <SetRecord>[
        _set(workout: 'w1', at: DateTime(2026, 10, 11, 23, 59)),
        _set(workout: 'w2', at: DateTime(2026, 10, 12, 0, 0)),
      ];
      final WeeklyChallenge c = weeklyChallenge(sets, DateTime(2026, 10, 11, 23));
      final int total = c.spec.rule(<SetRecord>[
        _set(workout: 'w1', at: DateTime(2026, 10, 11, 23, 59)),
      ]);
      expect(c.current, total, reason: '只有 10/11 那一组属于本周');
    });

    test('进度封顶到 target（不会出现"45 / 40 组"这种越界进度）', () {
      final List<SetRecord> many = <SetRecord>[
        for (int i = 0; i < 60; i++)
          _set(workout: 'w${i ~/ 4}', at: monday.add(Duration(minutes: i))),
      ];
      final WeeklyChallenge c = weeklyChallenge(many, monday);
      expect(c.current, lessThanOrEqualTo(c.spec.target));
      expect(c.progress, lessThanOrEqualTo(1.0));
      expect(c.done, isTrue);
    });
  });

  group('池子里每一条都真的能在一周内做完', () {
    // 每条挑战都用"一份七天的常规训练"去打一遍 —— 不是为了证明用户一定做得到，
    // 而是为了让"target 是不是写得太离谱"有一个能跑的检查（比如手滑写成 400 组）。
    //
    // 这份"常规一周"要能同时覆盖池子里的**每一条**（跑出误报就得先想想是数据不对还是挑战不对）：
    //   * 四天（周一 / 二 / 三 / 四），**每天上午 + 晚上各一场** → 一天两练、练 4 天、场上限 6 组；
    //   * 每场 6 组，推 / 蹲轮着 → 上肢、下肢、单组 ≥8 次、一场 10 组（两场并起来算一场？不 ——
    //     "一场 10 组"由单场 6 组打不到，所以其中三天各再补一场 10 组的短课）；
    //   * 晚上那场附带一组跑步机 → 有氧那一枚。
    final List<SetRecord> aNormalWeek = <SetRecord>[
      for (int d = 0; d < 4; d++) ...<SetRecord>[
        // 上午：6 组推
        for (int i = 0; i < 6; i++)
          _set(
            workout: 'w$d-am',
            at: DateTime(2026, 10, 5 + d, 9).add(Duration(minutes: i)),
            exercise: i.isEven ? 'ex_bb_bench_press' : 'ex_bb_row',
          ),
        // 晚上：10 组蹲 + 一组跑步机（单场 11 组 → 覆盖"一场 10 组"）
        for (int i = 0; i < 10; i++)
          _set(
            workout: 'w$d-pm',
            at: DateTime(2026, 10, 5 + d, 19).add(Duration(minutes: i)),
            exercise: 'ex_bb_squat',
          ),
        _set(
          workout: 'w$d-pm',
          at: DateTime(2026, 10, 5 + d, 19, 30),
          exercise: 'ex_running',
          reps: 1200,
          distanceM: 3000,
        ),
      ],
    ];

    test('★ 一周四练（每天 10 组）足以完成池子里的每一条', () {
      for (final WeeklyChallengeSpec spec in weeklyPool()) {
        expect(spec.rule(aNormalWeek), greaterThanOrEqualTo(spec.target),
            reason: '「${spec.name}」用一周四练做不完（target=${spec.target}）—— '
                '一周内做不完的挑战是坏挑战');
      }
    });

    test('什么都不做 → 每一条都是 0（没有"白送"的挑战）', () {
      for (final WeeklyChallengeSpec spec in weeklyPool()) {
        expect(spec.rule(<SetRecord>[]), 0, reason: '「${spec.name}」空记录下不是 0');
      }
    });

    test('池子里 id 不重复、文案都不为空', () {
      final List<WeeklyChallengeSpec> pool = weeklyPool();
      expect(pool.map((WeeklyChallengeSpec s) => s.id).toSet().length, pool.length);
      for (final WeeklyChallengeSpec s in pool) {
        expect(s.name.isNotEmpty, isTrue);
        expect(s.how.isNotEmpty, isTrue);
        expect(s.target, greaterThan(0));
      }
    });
  });

  _homeLineTests();
}

// ── 首页那一行（第二部分第 3 条"一处实现两处用"）────────────────────

void _homeLineTests() {
  WeeklyChallenge mk({
    required int current,
    required int target,
    required int daysLeft,
    String name = '本周练 3 次',
    String unit = '次',
  }) =>
      WeeklyChallenge(
        spec: WeeklyChallengeSpec(
          id: 'x',
          name: name,
          how: 'h',
          unit: unit,
          target: target,
          rule: (List<SetRecord> s) => 0,
        ),
        current: current,
        daysLeft: daysLeft,
        weekStart: DateTime(2026, 10, 5),
      );

  test('★ 没做完时给一行：挑战名 + 进度 + 还剩几天（与成就页同一份实现）', () {
    final String? line = weeklyChallengeLine(
        mk(current: 1, target: 3, daysLeft: 5));
    expect(line, isNotNull);
    expect(line, contains('本周练 3 次'));
    expect(line, contains('1 / 3次'));
    expect(line, contains('还剩 5 天'));
  });

  test('★ 本周已经做完了 → 首页**不说**（成就页里仍然写着"本周已完成"）', () {
    expect(weeklyChallengeLine(mk(current: 3, target: 3, daysLeft: 4)), isNull);
  });

  test('★ 只剩今天（周日）→ 首页不说（提示一个马上过期的东西没有意义）', () {
    expect(weeklyChallengeLine(mk(current: 0, target: 3, daysLeft: 1)), isNull);
    expect(weeklyChallengeLine(mk(current: 0, target: 3, daysLeft: 2)), isNotNull,
        reason: '还剩两天还来得及');
  });
}
