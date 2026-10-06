/// 连续保护 / 补签（第二部分第 2 条）的判据自测。
///
/// 这一条动的是**连续天数** —— 产品里唯一会归零的数字。所以四条闸门逐条钉：
/// 每周一次、代价是本周练过、**恰好断一天**、断点之后真的练过。
/// 少任何一条，补签就会从"防断"变成"发安慰奖"。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/progress/streak_protection.dart';

SetRecord _set(DateTime at, {String workout = 'w'}) => SetRecord(
      id: '$workout-${at.millisecondsSinceEpoch}',
      workoutId: '$workout-${at.year}${at.month}${at.day}',
      exerciseId: 'ex_bb_bench_press',
      setIndex: 0,
      reps: 8,
      weightKg: 60,
      completedAtMs: at.millisecondsSinceEpoch,
    );

void main() {
  // 2026-10-08 是周四；本周 = 10/5（周一）～ 10/11
  final DateTime thursday = DateTime(2026, 10, 8, 20);

  group('连续天数（含保护）', () {
    test('★ 被补的那一天**撑住链**、也计 1 天 —— 所以界面必须交代"其中 N 天是补签"', () {
      // 10/6、10/7 练了；10/5 断（补了）；10/8 今天还没练
      final List<SetRecord> sets = <SetRecord>[
        _set(DateTime(2026, 10, 6, 19)),
        _set(DateTime(2026, 10, 7, 19)),
      ];
      final Set<String> prot = <String>{dayKey(DateTime(2026, 10, 5))};
      expect(streakWithProtection(sets, prot, thursday), 3,
          reason: '10/5 被补 → 链从 10/5 连到 10/7（今天没练也算上）');
      expect(protectedDaysInStreak(sets, prot, thursday), 1);
      expect(
        streakLabelWithProtection(3, 1),
        '已连续打卡 3 天（其中 1 天是补签）',
        reason: '不说"其中几天是补签"就是假话',
      );
      expect(streakLabelWithProtection(3, 0), '已连续打卡 3 天');
    });

    test('没补签时与 `streak.dart` 完全一致（这条功能不许偷偷改口径）', () {
      final List<SetRecord> sets = <SetRecord>[
        _set(DateTime(2026, 10, 6, 19)),
        _set(DateTime(2026, 10, 7, 19)),
      ];
      expect(streakWithProtection(sets, <String>{}, thursday), 2);
      // 断一天就归零（没有保护）
      expect(
        streakWithProtection(<SetRecord>[_set(DateTime(2026, 10, 6, 19))],
            <String>{}, thursday),
        0,
      );
    });

    test('今天还没练不算断（与首页那条纪律同一条）', () {
      final List<SetRecord> sets = <SetRecord>[_set(DateTime(2026, 10, 7, 19))];
      expect(streakWithProtection(sets, <String>{}, thursday), 1);
    });

    test('只数当前这条链里的补签天数（上个月补的不算进来）', () {
      final List<SetRecord> sets = <SetRecord>[
        _set(DateTime(2026, 10, 7, 19)),
        _set(DateTime(2026, 10, 6, 19)),
        _set(DateTime(2026, 10, 5, 19)),
      ];
      final Set<String> prot = <String>{
        dayKey(DateTime(2026, 10, 5)), // 本次链内
        dayKey(DateTime(2026, 9, 20)), // 上个月，早就不在链里了
      };
      expect(streakWithProtection(sets, prot, thursday), 3);
      expect(protectedDaysInStreak(sets, prot, thursday), 1,
          reason: '9/20 那次补签不该被算进"这 3 天里有 1 天"');
    });
  });

  group('能不能补签（四条闸门）', () {
    // 一个"昨天断了、前天练了"的典型局面
    List<SetRecord> typical() => <SetRecord>[
          _set(DateTime(2026, 10, 6, 19)),
          _set(DateTime(2026, 10, 5, 19)), // 本周一练过 → 代价已付
        ];

    test('★ 典型局面能给补签，而且要补的是**昨天**', () {
      final StreakProtectionOffer? o =
          protectionOffer(typical(), <String>{}, thursday);
      expect(o, isNotNull);
      expect(o!.day, DateTime(2026, 10, 7));
      expect(o.label, contains('昨天'));
      expect(o.label, contains('10 月 7 日'));
    });

    test('★ 这一周已经补过一次 → 不再给（每周一次）', () {
      final Set<String> used = <String>{dayKey(DateTime(2026, 10, 5))};
      expect(protectionOffer(typical(), used, thursday), isNull);
      // 换到下一周（10/12 周一）就又有额度了
      expect(
        protectionOffer(
          <SetRecord>[_set(DateTime(2026, 10, 12, 19))],
          used,
          DateTime(2026, 10, 14, 20),
        ),
        isNotNull,
      );
    });

    test('★ 本周一次都没练 → 不给（代价没付：白送的保护没有意义）', () {
      final List<SetRecord> noWeekTraining = <SetRecord>[
        _set(DateTime(2026, 9, 30, 19)), // 上周练的
      ];
      expect(protectionOffer(noWeekTraining, <String>{}, thursday), isNull);
    });

    test('★ 昨天与前天**都断了** → 不给（补一天也接不上，那会变成空话）', () {
      final List<SetRecord> twoGaps = <SetRecord>[
        _set(DateTime(2026, 10, 5, 19)), // 本周一练过（代价付了），但那之后就没练过
      ];
      // 10/7 与 10/6 都断 → 两个洞，拒
      expect(protectionOffer(twoGaps, <String>{}, thursday), isNull);
    });

    test('前天断了、昨天练了 → 补的是**前天**（洞在哪就补哪）', () {
      final List<SetRecord> gapBefore = <SetRecord>[
        _set(DateTime(2026, 10, 7, 19)), // 昨天练了
        _set(DateTime(2026, 10, 5, 19)), // 前天（10/6）断了
      ];
      final StreakProtectionOffer? o =
          protectionOffer(gapBefore, <String>{}, thursday);
      expect(o, isNotNull);
      expect(o!.day, DateTime(2026, 10, 6));
      expect(o.label, contains('前天'));
    });

    test('★ 断点之后没练过 → 不给（三个月没来的人不该被建议"补昨天"）', () {
      final List<SetRecord> stale = <SetRecord>[
        _set(DateTime(2026, 10, 5, 19)), // 本周一练过（代价付了）
        _set(DateTime(2026, 10, 4, 19)),
      ];
      // 10/6、10/7 连断两天 → 上面那条闸门先挡住；单独看"之后没练"这一条：
      final List<SetRecord> onlyMonday = <SetRecord>[
        _set(DateTime(2026, 10, 5, 19)),
      ];
      expect(protectionOffer(stale, <String>{}, thursday), isNull);
      expect(protectionOffer(onlyMonday, <String>{}, thursday), isNull,
          reason: '10/6、10/7 都断了 —— 链回不来');
    });

    test('今天练过了、昨天断了 → **照样能给**（链还接得上）', () {
      final List<SetRecord> trainedToday = <SetRecord>[
        _set(DateTime(2026, 10, 8, 19)), // 今天
        _set(DateTime(2026, 10, 6, 19)),
        _set(DateTime(2026, 10, 5, 19)),
      ];
      final StreakProtectionOffer? o =
          protectionOffer(trainedToday, <String>{}, thursday);
      expect(o, isNotNull, reason: '今天练了，但昨天那个洞还在');
      expect(o!.day, DateTime(2026, 10, 7));
    });

    test('★ 断点之后一直没练（今天也没练）→ 不给：那是"回来了"才谈得上的事', () {
      // 10/5 练过（本周代价已付），10/6 也练了；10/7 断、今天还没练
      // —— 这种局面其实**不该**直接拒：晚上打开 App 正是它。所以这里换一个
      // 真正该拒的：断点不是昨天（10/6 断），而今天也没练。
      final List<SetRecord> stale = <SetRecord>[
        _set(DateTime(2026, 10, 5, 19)),
        _set(DateTime(2026, 10, 8, 12)), // 今天练了 → 断点是 10/6、10/7？不行
      ];
      // 三天窗口（10/8、10/7、10/6）里没练的是 10/7 与 10/6 两天 → 断太多，拒
      expect(protectionOffer(stale, <String>{}, thursday), isNull);
    });

    test('连着两天都练了 → 没有洞，不给', () {
      final List<SetRecord> noGap = <SetRecord>[
        _set(DateTime(2026, 10, 7, 19)),
        _set(DateTime(2026, 10, 6, 19)),
        _set(DateTime(2026, 10, 5, 19)),
      ];
      expect(protectionOffer(noGap, <String>{}, thursday), isNull);
    });
  });

  group('仓库口径的小工具', () {
    test('dayKey 是本地日、补零（排障时要能人肉读）', () {
      expect(dayKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(dayKey(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('热身组不算"这天练过"（与 streak / 提醒同一口径）', () {
      final SetRecord warmup = SetRecord(
        id: 'x',
        workoutId: 'w',
        exerciseId: 'ex_bb_bench_press',
        setIndex: 0,
        reps: 8,
        completedAtMs: DateTime(2026, 10, 7, 19).millisecondsSinceEpoch,
        setType: SetType.warmup,
      );
      expect(trainedOn(<SetRecord>[warmup], DateTime(2026, 10, 7)), isFalse);
    });

    test('usedThisWeek 按**周一起算**（与周报 / 每周挑战同一个"一周"）', () {
      // 10/4（周日）补的属于上一周；10/5（周一）之后才占本周额度
      expect(
        usedThisWeek(<String>{'2026-10-04'}, thursday),
        isFalse,
        reason: '10/4 是上周日',
      );
      expect(usedThisWeek(<String>{'2026-10-05'}, thursday), isTrue);
      expect(usedThisWeek(<String>{'2026-10-11'}, thursday), isTrue,
          reason: '周日仍属本周');
    });
  });
}
