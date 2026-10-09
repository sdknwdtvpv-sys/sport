/// 练了么 · 某个动作的「历史最佳」（2026-10-10）
///
/// 它是训练屏那条对照带的右半边，口径**必须**与「进步」页 PR 墙一致 ——
/// 同一个动作在两张屏上算出不同的"最佳"，用户就会以为有两个纪录。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/best_set.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/domain/models.dart';

SetRecord _set(double? kg, int reps, {int index = 0, SetType type = SetType.normal}) =>
    SetRecord(
      id: 's$index',
      workoutId: 'w1',
      exerciseId: 'ex',
      setIndex: index,
      reps: reps,
      weightKg: kg,
      setType: type,
      completedAtMs: 0,
    );

void main() {
  test('有重量：比**最重那一组**，另算逐组估计的最大 1RM', () {
    // ⚠️ 1RM 要逐组估再取最大：它常常不是"最重那一组"
    // （80 kg × 3 估出来比 82.5 kg × 1 高）。与 progress_data.personalBests 同口径。
    final BestSet? b = bestSetOf(<SetRecord>[
      _set(80, 3, index: 0),
      _set(82.5, 1, index: 1),
    ]);
    expect(b, isNotNull);
    expect(b!.weightKg, 82.5, reason: '最重的那一组');
    expect(b.reps, 1);
    expect(b.oneRm, greaterThan(82.5), reason: '1RM 取的是逐组估计的最大值');
    expect(b.isBodyweight, isFalse);
    expect(b.totalSets, 2);
  });

  test('自重 / 按时长：比最多次数（按时长那些"次"其实是秒，界面负责换单位）', () {
    final BestSet? b = bestSetOf(<SetRecord>[
      _set(null, 12, index: 0),
      _set(null, 9, index: 1),
    ]);
    expect(b!.isBodyweight, isTrue);
    expect(b.reps, 12);
    expect(b.weightKg, isNull);
    expect(bestSetMainLabel(b, unit: WeightUnit.kg), '自重 × 12');
    expect(bestSetMainLabel(b, unit: WeightUnit.kg, trackType: 'time'),
        '自重 × 12 秒');
  });

  test('有氧（记距离）**整个不进来** —— 按自重那条路比会得出"最佳 1800 次"', () {
    expect(
      bestSetOf(<SetRecord>[_set(null, 1800, index: 0)],
          trackType: 'distance_time'),
      isNull,
    );
  });

  test('热身组不算成绩；一组都没有时返回 null（界面不编一个"最佳"）', () {
    expect(bestSetOf(<SetRecord>[]), isNull);
    expect(
      bestSetOf(<SetRecord>[_set(100, 5, type: SetType.warmup)]),
      isNull,
      reason: '只有热身组 = 没有正式成绩',
    );
  });

  test('副标题：能算出 1RM 才念 1RM，算不出来就什么都不念', () {
    final BestSet? withRm = bestSetOf(<SetRecord>[_set(100, 5)]);
    expect(bestSetSubLabel(withRm!, unit: WeightUnit.kg), contains('1RM 预估'));
    final BestSet? noRm = bestSetOf(<SetRecord>[_set(null, 12)]);
    expect(bestSetSubLabel(noRm!, unit: WeightUnit.kg), isNull,
        reason: '自重动作没有可信的 1RM —— 不编一个数字');
  });
}
