/// 固定训练时段建议（第二部分第 6 条）的判据自测。
///
/// 这一条的风险是"**瞎建议**"：样本太少、或者用户根本练得没规律，
/// 却被建议"定在 19:00" —— 那会让人设一个自己不会练的闹钟，两次之后就把提醒关掉。
/// 所以两条闸门（≥6 次、且那个时段占一半以上）逐条钉住。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/profile/training_time.dart';

SetRecord _set(String workout, DateTime at) => SetRecord(
      id: '$workout-${at.millisecondsSinceEpoch}',
      workoutId: workout,
      exerciseId: 'ex_bb_bench_press',
      setIndex: 0,
      reps: 8,
      weightKg: 60,
      completedAtMs: at.millisecondsSinceEpoch,
    );

void main() {
  test('★ 样本太少（不到 6 次）不给建议 —— 那是噪音，不是习惯', () {
    final List<SetRecord> few = <SetRecord>[
      for (int i = 0; i < 5; i++) _set('w$i', DateTime(2026, 9, 1 + i, 19)),
    ];
    expect(dominantWorkoutHour(few), isNull);
    expect(trainingTimeSuggestion(few), isNull);
  });

  test('★ 没有固定时段（最多的那个点不到一半）也不给建议', () {
    final List<SetRecord> scattered = <SetRecord>[
      _set('w1', DateTime(2026, 9, 1, 7)),
      _set('w2', DateTime(2026, 9, 2, 12)),
      _set('w3', DateTime(2026, 9, 3, 19)),
      _set('w4', DateTime(2026, 9, 4, 7)),
      _set('w5', DateTime(2026, 9, 5, 21)),
      _set('w6', DateTime(2026, 9, 6, 12)),
    ];
    expect(dominantWorkoutHour(scattered), isNull,
        reason: '6 次分成 3 个时段，每个 2 次 —— 说不上"固定"');
  });

  test('★ 明显集中在一个时段 → 给建议，数字与时刻都对', () {
    final List<SetRecord> regular = <SetRecord>[
      for (int i = 0; i < 8; i++) _set('w$i', DateTime(2026, 9, 1 + i, 19, 30)),
      _set('w8', DateTime(2026, 9, 12, 12)),
    ];
    final ({int hour, int count})? d = dominantWorkoutHour(regular);
    expect(d, isNotNull);
    expect(d!.hour, 19);
    expect(d.count, 8);
    final String copy = trainingTimeSuggestion(regular)!;
    expect(copy, contains('19:00'));
    expect(copy, contains('8 次'));
    expect(suggestedReminderMinutes(d.hour), 19 * 60);
  });

  test('一场训练按**第一组**的小时算（练到 21 点结束 ≠ 习惯 21 点开始）', () {
    final List<SetRecord> sets = <SetRecord>[
      for (int i = 0; i < 6; i++) ...<SetRecord>[
        _set('w$i', DateTime(2026, 9, 1 + i, 19, 50)),
        // 同一场练到 20:10（跨了整点）—— 不许因此算成"20 点档"
        _set('w$i', DateTime(2026, 9, 1 + i, 20, 10)),
      ],
    ];
    final ({int hour, int count})? d = dominantWorkoutHour(sets);
    expect(d!.hour, 19, reason: '跨整点的那一场要按开始时间算');
  });

  test('空记录 → 什么都不说', () {
    expect(dominantWorkoutHour(<SetRecord>[]), isNull);
    expect(trainingTimeSuggestion(<SetRecord>[]), isNull);
  });

  test('建议只是"一句话 + 一个时刻"，**不碰任何设置**（点了才写库）', () {
    final List<SetRecord> regular = <SetRecord>[
      for (int i = 0; i < 6; i++) _set('w$i', DateTime(2026, 9, 1 + i, 7, 10)),
    ];
    final ({int hour, int count})? d = dominantWorkoutHour(regular);
    expect(suggestedReminderMinutes(d!.hour), 7 * 60);
    expect(trainingTimeSuggestion(regular), contains('7:00'));
  });
}
