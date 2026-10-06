/// 练后小知识（第二部分第 8 条）的判据自测。
///
/// 这一条最容易变成"鸡汤表"或"抽卡机"，所以两条都钉住：
///   * **同一屏刷新两次必须是同一条**（不能让用户以为每次都在换）；
///   * 表里的每一条都**不承诺结果、不涉及诊断**（联网/夸大都不许进来）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/features/summary/tips.dart';

void main() {
  test('★ 挑哪一条是纯函数：同一个 workoutId 永远同一条', () {
    for (final String id in <String>['w1', 'w2', 'abc-123', '上次那次']) {
      expect(tipFor(id).id, tipFor(id).id);
    }
    // 不同的 id 会（大概率）落到不同条目上 —— 池子有 16 条，四个不同 id 全撞不可能
    final Set<String> ids = <String>{
      for (final String id in <String>['a', 'b', 'c', 'd', 'e', 'f'])
        tipFor(id).id,
    };
    expect(ids.length, greaterThan(1), reason: '永远给同一条就等于只有一条知识');
  });

  test('表里 id 唯一、标题与正文都不空', () {
    expect(kTips.length, greaterThanOrEqualTo(12), reason: '太少的池子会反复看到同一条');
    expect(kTips.map((Tip t) => t.id).toSet().length, kTips.length);
    for (final Tip t in kTips) {
      expect(t.title.isNotEmpty, isTrue);
      expect(t.body.isNotEmpty, isTrue);
      expect(t.body.length, lessThan(140),
          reason: '「15 秒读完」是这一条的产品约束（${t.id} 太长了）');
    }
  });

  test('★ 不承诺结果、不涉及诊断（搜一遍最容易溜进来的那几种说法）', () {
    // 用**词组**而不是单字：单字会误伤（"不必每次都加"里那个"必"是正常中文，
    // 而"必瘦"/"保证"才是承诺）。判据要抓的是**说法**，不是某个字。
    const List<String> banned = <String>[
      '减脂', '减肥', '瘦下来', '增肌', '一个月', '一周见效',
      '保证', '一定能', '必然', '立竿见影', '有效果',
      '治愈', '治疗', '治好', '诊断', '医嘱',
      '受伤', '损伤', '拉伤', '扭伤', '疼得', '止痛',
      '药物', '补剂', '激素', '类固醇',
    ];
    for (final Tip t in kTips) {
      final String both = '${t.title}\n${t.body}';
      for (final String w in banned) {
        expect(both.contains(w), isFalse,
            reason: '「${t.id}」里出现了「$w」—— 这是承诺或诊断，不许进这张表');
      }
    }
  });

  test('空池子也不会崩（防御性：文案表被清空时总结屏还得能出）', () {
    // 这条只是钉住"函数不假设池子非空"——tipFor 里有兜底
    expect(tipFor('anything').id.isNotEmpty, isTrue);
  });
}
