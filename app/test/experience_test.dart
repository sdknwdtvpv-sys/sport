/// 轻量等级 / 经验（第二部分第 7 条）的判据自测。
///
/// 口径只有一条：**累计组数**。这里钉的是门槛表本身：
/// 升序、从 0 开始、到顶返回 null（**不编**下一个目标）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/features/progress/experience.dart';

void main() {
  test('门槛升序、从 0 开始（不然会出现"永远到不了的等级"）', () {
    for (int i = 1; i < kExperienceThresholds.length; i++) {
      expect(kExperienceThresholds[i].at,
          greaterThan(kExperienceThresholds[i - 1].at));
    }
    expect(kExperienceThresholds.first.at, 0);
  });

  test('等级与下一级算得对（边界：刚好到门槛、差一组）', () {
    expect(experienceFor(0).level, 1);
    expect(experienceFor(0).title, '起步');
    expect(experienceFor(99).level, 1);
    expect(experienceFor(99).toNext, 1);
    expect(experienceFor(100).level, 2);
    expect(experienceFor(100).toNext, 200);
    expect(experienceFor(150).progress, closeTo(50 / 200, 0.001));
  });

  test('★ 到顶之后**不编**下一个目标（nextAt = null、进度画满）', () {
    final ExperienceInfo info = experienceFor(999999);
    expect(info.isMax, isTrue);
    expect(info.nextAt, isNull);
    expect(info.toNext, 0);
    expect(info.progress, 1);
    expect(experienceHint(info), contains('最高等级'));
  });

  test('负数当 0（脏数据不该把进度算成 NaN 或负）', () {
    expect(experienceFor(-5).sets, 0);
    expect(experienceFor(-5).progress, 0);
  });

  test('提示文案带上下一个称号（用户要知道"到哪儿算升"）', () {
    expect(experienceHint(experienceFor(0)), contains('上量'));
    expect(experienceHint(experienceFor(0)), contains('100'));
  });
}
