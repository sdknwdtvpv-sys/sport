/// 练了么 · 训练结束提醒的文案（纯函数）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/features/profile/next_training_copy.dart';

void main() {
  test('有下次部位：说人话，且带一个"点开就能开始"的落点', () {
    final (String, String)? c = nextTrainingReminderCopy('back');
    expect(c, isNotNull);
    expect(c!.$1, '明天该练背了');
    expect(c.$2, contains('点开直接开始'));
  });

  test('没有下次部位 → null（宁可不排，也不编一个部位出来）', () {
    expect(nextTrainingReminderCopy(null), isNull);
    expect(nextTrainingReminderCopy(''), isNull);
  });

  test('不催：文案里不出现"还没练"这类话（那是训练提醒那条的活）', () {
    final (String, String)? c = nextTrainingReminderCopy('legs');
    expect(c!.$1.contains('还没'), isFalse);
    expect(c.$2.contains('还没'), isFalse);
  });

  test('排在下一次那个时刻：今天还没到就今天，过了就明天', () {
    // 2026-10-05 10:00，用户设的是 20:00 → 今天 20:00
    final int now1 = DateTime(2026, 10, 5, 10).millisecondsSinceEpoch;
    expect(nextTrainingReminderAt(nowMs: now1, minutesOfDay: 20 * 60),
        DateTime(2026, 10, 5, 20).millisecondsSinceEpoch);

    // 2026-10-05 21:30 → 明天 20:00
    final int now2 = DateTime(2026, 10, 5, 21, 30).millisecondsSinceEpoch;
    expect(nextTrainingReminderAt(nowMs: now2, minutesOfDay: 20 * 60),
        DateTime(2026, 10, 6, 20).millisecondsSinceEpoch);

    // 刚好整点：**不能**排在同一时刻（否则会立刻响一次）
    final int now3 = DateTime(2026, 10, 5, 20).millisecondsSinceEpoch;
    expect(nextTrainingReminderAt(nowMs: now3, minutesOfDay: 20 * 60),
        DateTime(2026, 10, 6, 20).millisecondsSinceEpoch);
  });

  test('越界的设置值被夹在一天之内（不炸，也不排到后天去）', () {
    final int now = DateTime(2026, 10, 5, 8).millisecondsSinceEpoch;
    // 9999 分钟 = 166 小时 39 分 → 小时夹到 23、分钟留 39（实现如此，判据只钉"还在今天"）
    final DateTime big = DateTime.fromMillisecondsSinceEpoch(
        nextTrainingReminderAt(nowMs: now, minutesOfDay: 9999));
    expect(big.day, 5);
    expect(big.hour, 23);
    // 负数进 Dart 的 `%` 会回到正区间（-5 % 60 == 55）→ 变成 0:55；
    // 而 0:55 在 08:00 之前已经过了，于是排到**明天** 0:55 —— 这是对的（下一个还没到的时刻）
    final DateTime neg = DateTime.fromMillisecondsSinceEpoch(
        nextTrainingReminderAt(nowMs: now, minutesOfDay: -5));
    expect(neg.hour, 0);
    expect(neg.minute, 55);
    expect(neg.day, 6);
  });
}
