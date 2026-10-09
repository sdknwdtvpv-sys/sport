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

  // ── A4 隐藏徽章（2026-10-06 拍板）──────────────────────────────────
  group('A4 隐藏徽章', () {
    test('藏的是**条件**不是名字：hidden 的都还在，名字与 id 照常', () {
      final List<BadgeStatus> all = badgeStatuses(<SetRecord>[], now: today);
      final List<BadgeStatus> hidden =
          all.where((BadgeStatus b) => b.hidden).toList();
      expect(hidden.length, 4, reason: 'A4 拍板的就是这一小撮，多一枚少一枚都要改文档');
      for (final BadgeStatus b in hidden) {
        expect(b.name.isNotEmpty, isTrue, reason: '${b.id} 名字必须可见 —— 否则用户不知道有这回事');
        expect(b.how.isNotEmpty, isTrue, reason: '解锁之后要讲得明白，不能只有"？？？"');
        expect(b.category, BadgeCategory.explore, reason: '隐藏徽章放在「探索发现」线');
        expect(b.unlocked, isFalse, reason: '空记录下一枚都不该解锁');
      }
    });

    test('★ 隐藏徽章不参与"离你最近的一枚"（那是推荐位，等于预告答案）', () {
      // 构造：一枚隐藏、一枚可见，隐藏那枚进度更高 —— 推荐位必须给可见的那枚
      BadgeStatus mk(String id, int cur, int tgt, {bool hidden = false}) => BadgeStatus(
            id: id,
            name: id,
            how: 'how',
            tier: BadgeTier.common,
            category: BadgeCategory.explore,
            current: cur,
            target: tgt,
            unlocked: false,
            hidden: hidden,
          );
      final BadgeStatus? n = nearestBadge(<BadgeStatus>[
        mk('hidden_one', 9, 10, hidden: true),
        mk('visible_one', 1, 10),
      ]);
      expect(n!.id, 'visible_one');
      // 只剩隐藏徽章没拿 → 如实返回 null（调用方说"全拿到了"，不拿隐藏徽章充数）
      expect(nearestBadge(<BadgeStatus>[mk('hidden_one', 9, 10, hidden: true)]), isNull);
    });

    test('破晓 / 跨零点：按小时判，边界 5 点与 2 点', () {
      final List<SetRecord> at5 = <SetRecord>[
        _set(workout: 'w', at: DateTime(2026, 10, 5, 5)),
      ];
      expect(_find(badgeStatuses(at5, now: today), 'dawn_raider').unlocked, isFalse,
          reason: '5 点整不算"5 点前"');
      final List<SetRecord> at4 = <SetRecord>[
        _set(workout: 'w', at: DateTime(2026, 10, 5, 4, 30)),
      ];
      expect(_find(badgeStatuses(at4, now: today), 'dawn_raider').unlocked, isTrue);

      final List<SetRecord> at2 = <SetRecord>[
        _set(workout: 'w', at: DateTime(2026, 10, 5, 2)),
      ];
      expect(_find(badgeStatuses(at2, now: today), 'midnight_crosser').unlocked, isFalse,
          reason: '2 点整不算"0~2 点之间"');
      final List<SetRecord> at1 = <SetRecord>[
        _set(workout: 'w', at: DateTime(2026, 10, 5, 1, 15)),
      ];
      expect(_find(badgeStatuses(at1, now: today), 'midnight_crosser').unlocked, isTrue);
      // 早上 6 点不是跨零点（"破晓"是 5 点前，"跨零点"是 0~2 点，两枚不许互相顶替）
      expect(_find(badgeStatuses(at4, now: today), 'midnight_crosser').unlocked, isFalse);
    });

    test('老熟人：按**不同日子**算，一天练 20 组也只算一天', () {
      // 同一天同一个动作 20 组
      final List<SetRecord> oneDay = <SetRecord>[
        for (int i = 0; i < 20; i++)
          _set(workout: 'w1', at: DateTime(2026, 10, 5, 9, i), exercise: 'squat'),
      ];
      expect(_find(badgeStatuses(oneDay, now: today), 'same_exercise_days').current, 1);

      // 5 个不同日子 → 解锁
      final List<SetRecord> fiveDays = <SetRecord>[
        for (int d = 0; d < 5; d++)
          _set(workout: 'w$d', at: DateTime(2026, 10, 1 + d, 9), exercise: 'squat'),
      ];
      expect(_find(badgeStatuses(fiveDays, now: today), 'same_exercise_days').unlocked,
          isTrue);
    });

    test('只用自重：**整场**一组重量都没加才算，掺了一组负重就整场不算', () {
      SetRecord bw(String workout, int idx, {double? weight}) => SetRecord(
            id: 'bw-$workout-$idx',
            workoutId: workout,
            exerciseId: 'push_up',
            setIndex: idx,
            weightKg: weight,
            reps: 15,
            completedAtMs: DateTime(2026, 10, 5, 9, idx).millisecondsSinceEpoch,
          );

      final List<SetRecord> allBodyweight = <SetRecord>[
        for (int i = 0; i < 15; i++) bw('w1', i),
      ];
      expect(_find(badgeStatuses(allBodyweight, now: today), 'bodyweight_only').unlocked,
          isTrue);
      expect(
          _find(badgeStatuses(allBodyweight, now: today), 'bodyweight_only').current, 15);

      // 14 组自重 + 1 组负重：**这一场**不算（"只用自重"这四个字不能被一组哑铃改掉）
      final List<SetRecord> contaminated = <SetRecord>[
        for (int i = 0; i < 14; i++) bw('w2', i),
        bw('w2', 99, weight: 10),
      ];
      expect(_find(badgeStatuses(contaminated, now: today), 'bodyweight_only').current, 0);
    });
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

  // ── 徽章扩到 70~80（2026-10-06 拍板）──────────────────────────────
  group('徽章扩容（13 → 73）', () {
    test('★ 总数落在 70~80 之间，四条线各 14+ 枚', () {
      final List<BadgeStatus> all = badgeStatuses(<SetRecord>[], now: today);
      expect(all.length, inInclusiveRange(70, 80),
          reason: '本轮拍板的是 70~80 枚；数字变了要同时改这份文档与四条线的分布');
      for (final BadgeCategory c in BadgeCategory.values) {
        final int n = all.where((BadgeStatus b) => b.category == c).length;
        expect(n, greaterThanOrEqualTo(14),
            reason: '${badgeCategoryLabel(c)}只有 $n 枚 —— 四条线要大致均衡');
      }
    });

    test('★ 稀有度**按难度真实定档**：史诗不许泛滥（不许为了好看全给 epic）', () {
      final List<BadgeStatus> all = badgeStatuses(<SetRecord>[], now: today);
      final int epic = all.where((BadgeStatus b) => b.tier == BadgeTier.epic).length;
      final int common =
          all.where((BadgeStatus b) => b.tier == BadgeTier.common).length;
      expect(epic / all.length, lessThan(0.35),
          reason: '史诗占了 ${(epic / all.length * 100).round()}% —— 那就不叫史诗了');
      expect(common, greaterThan(epic),
          reason: '入门那些必须是最多的：新人要很快拿到第一把');
    });

    test('每条线内部**不许有重名的徽章**（页面上两枚同名 = 用户分不清）', () {
      final List<BadgeStatus> all = badgeStatuses(<SetRecord>[], now: today);
      for (final BadgeCategory c in BadgeCategory.values) {
        final List<String> names = all
            .where((BadgeStatus b) => b.category == c)
            .map((BadgeStatus b) => b.name)
            .toList();
        expect(names.toSet().length, names.length,
            reason: '${badgeCategoryLabel(c)}里有重名：$names');
      }
    });

    test('单次训练的时长 = 这一场最后一组减第一组；只有一组的那场算 0 分钟', () {
      final List<SetRecord> sets = <SetRecord>[
        SetRecord(
          id: 'a',
          workoutId: 'w1',
          exerciseId: 'bench',
          setIndex: 1,
          reps: 8,
          weightKg: 60,
          completedAtMs: DateTime(2026, 10, 5, 9).millisecondsSinceEpoch,
        ),
        SetRecord(
          id: 'b',
          workoutId: 'w1',
          exerciseId: 'bench',
          setIndex: 2,
          reps: 8,
          weightKg: 60,
          completedAtMs: DateTime(2026, 10, 5, 10, 5).millisecondsSinceEpoch,
        ),
      ];
      final List<BadgeStatus> all = badgeStatuses(sets, now: today);
      expect(_find(all, 'long_session').current, 65, reason: '9:00 → 10:05 是 65 分钟');
      expect(_find(all, 'long_session').unlocked, isTrue);
      expect(_find(all, 'short_session').unlocked, isFalse, reason: '65 分钟不是"短促一练"');

      // 只有一组的那种（真实用户的常见情况）：时长为 0，不许算进"短促一练"
      final List<BadgeStatus> one = badgeStatuses(<SetRecord>[sets.first], now: today);
      expect(_find(one, 'long_session').current, 0);
      expect(_find(one, 'short_session').unlocked, isFalse,
          reason: '一组记录算不出时长 —— 不许拿 0 分钟去解锁"短促一练"');
    });

    test('"我回来了"看的是最长空档：断 14 天再回来才算', () {
      List<SetRecord> twoBouts(int gapDays) => <SetRecord>[
            _set(workout: 'w1', at: DateTime(2026, 8, 1, 19)),
            _set(workout: 'w2',
                at: DateTime(2026, 8, 1, 19).add(Duration(days: gapDays))),
          ];
      expect(_find(badgeStatuses(twoBouts(13), now: today), 'comeback').unlocked, isFalse);
      expect(_find(badgeStatuses(twoBouts(14), now: today), 'comeback').unlocked, isTrue);
    });

    test('"一周全勤"按周一起算的那一周数次数；跨周不算同一周', () {
      // 周一 ~ 周日，每天一次 = 7 次（2026-09-28 是周一）
      final List<SetRecord> fullWeek = <SetRecord>[
        for (int i = 0; i < 7; i++)
          _set(workout: 'w$i', at: DateTime(2026, 9, 28 + i, 19)),
      ];
      final BadgeStatus b = _find(badgeStatuses(fullWeek, now: today), 'full_week');
      expect(b.unlocked, isTrue, reason: '同一周里练了 7 次');
      expect(b.current, 7);

      // 6 次就不算（周日那次挪到下一周）
      final List<SetRecord> notQuite = <SetRecord>[
        for (int i = 0; i < 6; i++)
          _set(workout: 'w$i', at: DateTime(2026, 9, 28 + i, 19)),
        _set(workout: 'w6', at: DateTime(2026, 10, 5, 19)),
      ];
      expect(_find(badgeStatuses(notQuite, now: today), 'full_week').current, 6);
    });

    test('"连续四周"要连续 4 周每周 ≥3 练；中间断一周就重数', () {
      // 从 2026-09-07（周一）起，连续 4 周每周一/三/五各一练
      final List<SetRecord> fourWeeks = <SetRecord>[];
      for (int w = 0; w < 4; w++) {
        for (final int d in <int>[0, 2, 4]) {
          fourWeeks.add(
              _set(workout: 'w$w-$d', at: DateTime(2026, 9, 7 + w * 7 + d, 19)));
        }
      }
      expect(
          _find(badgeStatuses(fourWeeks, now: today), 'four_week_streak').unlocked, isTrue);

      // 第 3 周只练 2 次 → 断
      final List<SetRecord> broken = <SetRecord>[];
      for (int w = 0; w < 4; w++) {
        final int n = w == 2 ? 2 : 3;
        for (int i = 0; i < n; i++) {
          broken.add(
              _set(workout: 'w$w-$i', at: DateTime(2026, 9, 7 + w * 7 + i * 2, 19)));
        }
      }
      final BadgeStatus b = _find(badgeStatuses(broken, now: today), 'four_week_streak');
      expect(b.unlocked, isFalse);
      expect(b.current, lessThan(4), reason: '第 3 周不足 3 练之后要从那一周重数');
    });

    test('破纪录次数**自己算**（不读 is_pr）：每超过此前的最大值一次算一次', () {
      final List<SetRecord> sets = <SetRecord>[
        _set(workout: 'w1', at: DateTime(2026, 9, 1, 19), weight: 60),
        _set(workout: 'w2', at: DateTime(2026, 9, 2, 19), weight: 62.5),
        _set(workout: 'w3', at: DateTime(2026, 9, 3, 19), weight: 62.5), // 平了不算
        _set(workout: 'w4', at: DateTime(2026, 9, 4, 19), weight: 65),
      ];
      final BadgeStatus b = _find(badgeStatuses(sets, now: today), 'pr_ten');
      expect(b.current, 2, reason: '60 → 62.5 → 65 是两次破纪录（平一次不算）');
      expect(_find(badgeStatuses(sets, now: today), 'pr_first').unlocked, isTrue);
    });

    test('体重倍数：**没给体重就是 0**，不拿 0 kg 编一个"1 倍体重"', () {
      final List<SetRecord> sets = <SetRecord>[
        _set(workout: 'w1', at: DateTime(2026, 9, 1, 19), weight: 80),
      ];
      expect(_find(badgeStatuses(sets, now: today), 'bench_bodyweight').current, 0);
      expect(
        _find(badgeStatuses(sets, now: today, bodyWeightKg: 80), 'bench_bodyweight')
            .unlocked,
        isTrue,
        reason: '80 kg 单组 = 1 倍体重',
      );
      expect(
        _find(badgeStatuses(sets, now: today, bodyWeightKg: 100), 'bench_bodyweight')
            .current,
        0,
        reason: '100 kg 体重下 80 kg 不到 1 倍',
      );
    });

    test('距离类：有距离的组才认（距离动作的 reps 存的是秒，不许按次数算）', () {
      SetRecord run(int i, double meters) => SetRecord(
            id: 'r$i',
            workoutId: 'w1',
            exerciseId: 'ex_treadmill',
            setIndex: i,
            reps: 1800, // 秒
            distanceM: meters,
            completedAtMs: DateTime(2026, 9, 1, 19, i).millisecondsSinceEpoch,
          );
      final List<SetRecord> sets = <SetRecord>[for (int i = 0; i < 3; i++) run(i, 2000)];
      final List<BadgeStatus> all = badgeStatuses(sets, now: today);
      expect(_find(all, 'cardio_first').unlocked, isTrue);
      expect(_find(all, 'cardio_distance').unlocked, isTrue, reason: '合计 6 km ≥ 5 km');
      expect(_find(all, 'distance_100km').current, 6);
      // 没有距离的记录（普通力量组）不该把 1800 秒当成次数算进有氧
      final List<BadgeStatus> strength = badgeStatuses(
          <SetRecord>[
            _set(workout: 'w1', at: DateTime(2026, 9, 1, 19), reps: 1800)
          ],
          now: today);
      expect(_find(strength, 'cardio_first').unlocked, isFalse);
      expect(_find(strength, 'cardio_ten_sessions').current, 0);
    });

    test('热身组算"练完拉一下"，但不影响"只用自重"（那一场仍然算自重场）', () {
      SetRecord bw(int i, {SetType type = SetType.normal}) => SetRecord(
            id: 'bw$i',
            workoutId: 'w1',
            exerciseId: 'push_up',
            setIndex: i,
            reps: 15,
            setType: type,
            completedAtMs: DateTime(2026, 9, 1, 19, i).millisecondsSinceEpoch,
          );
      final List<SetRecord> sets = <SetRecord>[
        for (int i = 0; i < 15; i++) bw(i),
        bw(99, type: SetType.warmup),
      ];
      final List<BadgeStatus> all = badgeStatuses(sets, now: today);
      expect(_find(all, 'stretch_first').unlocked, isTrue);
      expect(_find(all, 'bodyweight_only').unlocked, isTrue,
          reason: '热身组本来就没有重量，不该把这一场变成"碰过重量"');
    });
  });

  _a1Tests(today);
}

// ── A1 收集线（2026-10-06 拍板）───────────────────────────────────────
void _a1Tests(DateTime today) {
  BadgeStatus mk(BadgeCategory c, String id, {required bool unlocked}) => BadgeStatus(
        id: id,
        name: id,
        how: 'h',
        tier: BadgeTier.common,
        category: c,
        current: unlocked ? 1 : 0,
        target: 1,
        unlocked: unlocked,
      );

  test('A1 线进度：按分类数"已拿 / 全部"，与分组一致', () {
    final List<BadgeStatus> all = badgeStatuses(<SetRecord>[], now: today);
    final List<BadgeLine> lines = badgeLines(all);
    expect(lines.length, BadgeCategory.values.length, reason: '四条线一条都不能少');
    for (final BadgeLine l in lines) {
      final List<BadgeStatus> rows =
          badgeGroups(all)[l.category] ?? <BadgeStatus>[];
      expect(l.total, rows.length);
      expect(l.unlocked, 0, reason: '空记录下一枚都没解锁');
      expect(l.complete, isFalse);
      expect(l.progress, 0);
      expect(l.label, badgeCategoryLabel(l.category));
    }
  });

  test('A1 集齐：**整条线全解锁**才算集齐，差一枚就不算', () {
    // 造一条只有两枚的"线"：锁一枚 → 没集齐；两枚都解锁 → 集齐
    expect(
      completedLines(<BadgeStatus>[
        mk(BadgeCategory.explore, 'a', unlocked: true),
        mk(BadgeCategory.explore, 'b', unlocked: false),
      ]),
      isEmpty,
    );
    final List<BadgeLine> done = completedLines(<BadgeStatus>[
      mk(BadgeCategory.explore, 'a', unlocked: true),
      mk(BadgeCategory.explore, 'b', unlocked: true),
    ]);
    expect(done.length, 1);
    expect(done.first.category, BadgeCategory.explore);
    expect(done.first.complete, isTrue);
    expect(done.first.progress, 1);
  });

  test('A1 线的颜色四条**互不相同**（并排的条要能分辨谁是谁）', () {
    final Set<int> colors = <int>{
      for (final BadgeCategory c in BadgeCategory.values) lineColor(c).toARGB32(),
    };
    expect(colors.length, BadgeCategory.values.length);
  });

  group('newlyUnlockedBadges：这一场挣到了哪几枚（2026-10-10）', () {
    test('差额法：排除刚练完这一场再算一遍，两次之差就是答案', () {
      // 用一条**确定会解锁**的：三天不断（第 3 天那一场才够）。
      // 不写"随便练两场总会挣到什么"—— 同一个动作连练两天可能一枚都不给。
      final List<SetRecord> sets = <SetRecord>[
        _set(workout: 'w1', at: DateTime(2026, 10, 1, 20)),
        _set(workout: 'w2', at: DateTime(2026, 10, 2, 20)),
        _set(workout: 'w3', at: DateTime(2026, 10, 3, 20)),
      ];
      final List<BadgeStatus> fresh = newlyUnlockedBadges(
        sets,
        workoutId: 'w3',
        now: DateTime(2026, 10, 3, 21),
      );
      expect(fresh.map((BadgeStatus b) => b.id), contains('three_day_streak'),
          reason: '第 3 天那一场才够「三天不断」');
      for (final BadgeStatus b in fresh) {
        expect(b.unlocked, isTrue);
        expect(b.id, isNot('first_workout'),
            reason: '首训是 w1 那场挣的，不属于这一场');
      }
    });

    test('什么都没挣到时返回空表（界面那一块整个不出现，不摆"暂无"）', () {
      final List<SetRecord> sets = <SetRecord>[
        _set(workout: 'w1', at: DateTime(2026, 10, 4, 20)),
      ];
      // 把 w1 自己排除之后就没有记录了 —— 全部徽章都是靠它解锁的，
      // 但那不算"这一场新挣到的"（它本来就是这一场）。
      expect(newlyUnlockedBadges(sets, workoutId: 'w999', now: today), isEmpty);
    });

    test('同一份记录算两次结果一样（纯函数，不落库、不看"已读"）', () {
      final DateTime d = DateTime(2026, 10, 4, 20);
      final List<SetRecord> sets = <SetRecord>[
        _set(workout: 'w1', at: d),
        _set(workout: 'w2', at: d.add(const Duration(days: 1))),
      ];
      final List<String> a = newlyUnlockedBadges(sets, workoutId: 'w2', now: today)
          .map((BadgeStatus b) => b.id)
          .toList();
      final List<String> b = newlyUnlockedBadges(sets, workoutId: 'w2', now: today)
          .map((BadgeStatus b) => b.id)
          .toList();
      expect(a, b);
    });
  });
}
