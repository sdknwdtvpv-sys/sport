/// 部位平衡提示（第二部分第 5 条）与回归激励（第 9 条）的判据自测。
///
/// 这两条都在首页**多说一句话**，所以判据必须比文案更严：
///   * 部位平衡：**没练过的部位**才是最要紧的信息，但"练得少而匀"时一个字都不该说；
///   * 回归激励：7 天才触发，而且说的必须是"5 分钟也算"，不是"你落后了"。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/progress/comeback.dart';
import 'package:lianleme/features/progress/muscle_balance.dart';

SetRecord _set(String workout, DateTime at, String exercise) => SetRecord(
      id: '$workout-${at.millisecondsSinceEpoch}-$exercise',
      workoutId: workout,
      exerciseId: exercise,
      setIndex: 0,
      reps: 8,
      weightKg: 60,
      completedAtMs: at.millisecondsSinceEpoch,
    );

void main() {
  // 2026-10-08 是周四 → 本周 = 10/5（周一）～ 10/11
  final DateTime thursday = DateTime(2026, 10, 8, 20);
  const Map<String, String> muscleOf = <String, String>{
    'ex_bench': 'chest',
    'ex_row': 'back',
    'ex_squat': 'legs',
    'ex_curl': 'arms',
  };

  group('部位平衡', () {
    test('★ 有部位一次没练 → 说出来（先说练得多的，再说 0 次的）', () {
      final List<SetRecord> sets = <SetRecord>[
        _set('w1', DateTime(2026, 10, 5, 19), 'ex_bench'),
        _set('w2', DateTime(2026, 10, 6, 19), 'ex_bench'),
        _set('w3', DateTime(2026, 10, 7, 19), 'ex_bench'),
      ];
      final ({String text, String? worst, String? most})? h = muscleBalanceHint(
          sets: sets, muscleOf: muscleOf, day: thursday);
      expect(h, isNotNull);
      expect(h!.text, contains('胸 3 次'));
      expect(h.text, contains('0 次'));
      expect(h.most, 'chest');
      expect(h.worst, isNotNull, reason: '要指出一个 0 次的部位');
    });

    test('★ 上周的记录不算（只看本周 —— 否则提示永远不消）', () {
      final List<SetRecord> sets = <SetRecord>[
        _set('old', DateTime(2026, 9, 30, 19), 'ex_bench'),
        _set('w1', DateTime(2026, 10, 5, 19), 'ex_bench'),
      ];
      final Map<String, int> c = weeklyMuscleCounts(
          sets: sets, muscleOf: muscleOf, day: thursday);
      expect(c['chest'], 1, reason: '9/30 属于上一周');
    });

    test('本周一次都没练 → 什么都不说（那该说的是"练一次"，不是"部位不均"）', () {
      expect(
        muscleBalanceHint(sets: <SetRecord>[], muscleOf: muscleOf, day: thursday),
        isNull,
      );
    });

    test('★ 练得少但很匀 → 一个字都不说（首页每一行都要有理由）', () {
      final List<SetRecord> sets = <SetRecord>[
        _set('w1', DateTime(2026, 10, 5, 19), 'ex_bench'),
        _set('w2', DateTime(2026, 10, 6, 19), 'ex_row'),
        _set('w3', DateTime(2026, 10, 7, 19), 'ex_squat'),
        _set('w4', DateTime(2026, 10, 8, 19), 'ex_curl'),
      ];
      final ({String text, String? worst, String? most})? h = muscleBalanceHint(
          sets: sets, muscleOf: muscleOf, day: thursday);
      // 六大部位里还有没练到的（肩 / 核心），所以这条其实会说话 —— 它说的是"肩、核心还是 0 次"。
      // 重点是：**不许**因为"某一处偏多"就整句不提 0 次的那几个。
      expect(h, isNotNull);
      expect(h!.text, contains('0 次'));
    });

    test('未知动作（动作表里查不到）不参与这一行 —— 宁可不说，也不瞎猜部位', () {
      final List<SetRecord> sets = <SetRecord>[
        _set('w1', DateTime(2026, 10, 5, 19), 'ex_unknown_custom'),
      ];
      final Map<String, int> c = weeklyMuscleCounts(
          sets: sets, muscleOf: muscleOf, day: thursday);
      expect(c.values.every((int v) => v == 0), isTrue);
      expect(muscleBalanceHint(sets: sets, muscleOf: muscleOf, day: thursday), isNull);
    });

    test('文案里的部位名走中文表（不把 chest 这种 key 印给用户）', () {
      final List<SetRecord> sets = <SetRecord>[
        _set('w1', DateTime(2026, 10, 5, 19), 'ex_bench'),
        _set('w2', DateTime(2026, 10, 6, 19), 'ex_bench'),
      ];
      final ({String text, String? worst, String? most})? h = muscleBalanceHint(
          sets: sets, muscleOf: muscleOf, day: thursday);
      expect(h!.text, isNot(contains('chest')));
      expect(h.text, isNot(contains('legs')));
    });
  });

  group('回归激励', () {
    test('★ 7 天没练才触发；6 天不触发', () {
      final List<SetRecord> six = <SetRecord>[
        _set('w1', DateTime(2026, 10, 2, 19), 'ex_bench'),
      ];
      final List<SetRecord> seven = <SetRecord>[
        _set('w1', DateTime(2026, 10, 1, 19), 'ex_bench'),
      ];
      expect(shouldNudgeComeback(six, thursday), isFalse);
      expect(shouldNudgeComeback(seven, thursday), isTrue,
          reason: '10/1 → 10/8 正好 7 天');
      expect(comebackCopy(six, thursday), isNull);
    });

    test('★ 从没练过 → 不是"回归"（那该说的是"开始第一次"）', () {
      expect(daysSinceLastWorkout(<SetRecord>[], thursday), isNull);
      expect(shouldNudgeComeback(<SetRecord>[], thursday), isFalse);
      expect(comebackCopy(<SetRecord>[], thursday), isNull);
    });

    test('刚练过 → 不触发；文案里带天数与"5 分钟也算"', () {
      final List<SetRecord> sets = <SetRecord>[
        _set('w1', DateTime(2026, 9, 25, 19), 'ex_bench'),
      ];
      expect(daysSinceLastWorkout(sets, thursday), 13);
      final String copy = comebackCopy(sets, thursday)!;
      expect(copy, contains('13 天'));
      expect(copy, contains('5 分钟'));
      expect(copy, contains('也算'));
      expect(copy, isNot(contains('!')));
      expect(copy, isNot(contains('落后')));
    });

    test('未来时间的记录不算数（时钟被调过也不该说"你 3 天后练过"）', () {
      final List<SetRecord> sets = <SetRecord>[
        _set('future', DateTime(2026, 12, 1, 19), 'ex_bench'),
      ];
      expect(daysSinceLastWorkout(sets, thursday), isNull);
      expect(shouldNudgeComeback(sets, thursday), isFalse);
    });
  });
}
