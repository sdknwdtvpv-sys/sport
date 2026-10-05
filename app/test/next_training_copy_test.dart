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
}
