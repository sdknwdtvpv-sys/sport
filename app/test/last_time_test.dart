/// 练了么 · 「上次练了多少」那一行（v1.53）
///
/// 这一行有两个消费方：今日建议页的证据链与**训练屏**新加的那行。实现只有一份
/// （`core/last_time.dart`），所以测试也只需要在这里把口径钉死 —— 两处都不会各说各的。
///
/// 守四件事：
///   1. **没历史就返回 null**（界面整个不出现，不编一个"上次"出来）；
///   2. 各组次数不一样时说"最少 N 次"，**不说"× N 次"** —— 后者是假话；
///   3. 距离动作念里程 + 时长，而不是"自重 × 3000"；
///   4. 单位（kg / 斤 / lb）跟着用户的选择走。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/last_time.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/domain/models.dart';

void main() {
  test('没练过 → null（界面那一行不出现，不编）', () {
    expect(lastTimeLabel(null, unit: WeightUnit.kg, trackType: 'weight_reps'), isNull);
    expect(
      lastTimeLabel(const LastSession(reps: <int>[]),
          unit: WeightUnit.kg, trackType: 'weight_reps'),
      isNull,
      reason: '一次都没完成（reps 为空）也算没历史',
    );
  });

  test('力量动作：上次 3 组 · 45 kg × 10 次', () {
    expect(
      lastTimeLabel(
        const LastSession(weightKg: 45, reps: <int>[10, 10, 10]),
        unit: WeightUnit.kg,
        trackType: 'weight_reps',
      ),
      '上次 3 组 · 45 kg × 10 次',
    );
  });

  test('各组次数不一样时说「最少」——说「× 8 次」是假话', () {
    expect(
      lastTimeLabel(
        const LastSession(weightKg: 45, reps: <int>[5, 8, 8]),
        unit: WeightUnit.kg,
        trackType: 'weight_reps',
      ),
      '上次 3 组 · 45 kg × 最少 5 次',
    );
  });

  test('自重动作念「自重」，不念 0 kg', () {
    expect(
      lastTimeLabel(
        const LastSession(reps: <int>[12, 12]),
        unit: WeightUnit.kg,
        trackType: 'reps_only',
      ),
      '上次 2 组 · 自重 × 12 次',
    );
  });

  test('计时动作的数字是秒', () {
    expect(
      lastTimeLabel(
        const LastSession(reps: <int>[30, 45]),
        unit: WeightUnit.kg,
        trackType: 'time',
      ),
      '上次 2 组 · 自重 × 最少 30 秒',
    );
  });

  test('距离动作念里程 + 时长，不是「自重 × 3000」', () {
    expect(
      lastTimeLabel(
        const LastSession(reps: <int>[1800], distances: <double?>[5000]),
        unit: WeightUnit.kg,
        trackType: 'distance_time',
      ),
      '上次 1 组 · 5.00 公里 · 30:00',
    );
  });

  test('距离动作没有距离数据 → null（宁可不念，也不编一个里程）', () {
    expect(
      lastTimeLabel(
        const LastSession(reps: <int>[1800]),
        unit: WeightUnit.kg,
        trackType: 'distance_time',
      ),
      isNull,
    );
  });

  test('单位跟着用户的选择走（训练重量只有 kg / lb —— 斤是体重的单位，不在这里）', () {
    expect(
      lastTimeLabel(
        const LastSession(weightKg: 45, reps: <int>[10]),
        unit: WeightUnit.kg,
        trackType: 'weight_reps',
      ),
      '上次 1 组 · 45 kg × 10 次',
    );
    expect(
      lastTimeLabel(
        const LastSession(weightKg: 45, reps: <int>[10]),
        unit: WeightUnit.lb,
        trackType: 'weight_reps',
      ),
      '上次 1 组 · 99.2 lb × 10 次',
      reason: '45 kg = 99.2 lb；存储永远是 kg，只是念法跟着单位走',
    );
  });
}
