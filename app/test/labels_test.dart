/// 练了么 · 标签完整性（内容侧守卫）
///
/// **为什么值得单开一条测试**：标签缺失不会崩、不会有异常，只会**漏出英文 key**。
/// 2026-09-30 在真机走查时才发现动作详情页显示「辅助：triceps、front_delts」——
/// 24 个辅助肌群 key 里有 20 个没有中文标签，而当时没有任何东西会红。
///
/// 这条测试的数据源是**种子本身**：以后加动作、加新肌群 key 却忘了配标签，它会红。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/labels.dart';

void main() {
  late List<Map<String, dynamic>> exercises;

  setUpAll(() {
    final Map<String, dynamic> json =
        jsonDecode(File('assets/exercises.json').readAsStringSync())
            as Map<String, dynamic>;
    exercises = (json['exercises'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
  });

  test('种子里用到的每个主部位都有中文标签', () {
    final Set<String> used = <String>{
      for (final Map<String, dynamic> e in exercises) e['muscle_group'] as String,
    };
    final List<String> missing =
        used.where((String k) => muscleLabel(k) == k).toList()..sort();
    expect(missing, isEmpty, reason: '这些部位没有中文标签：$missing');
  });

  test('种子里用到的每个辅助肌群都有中文标签（真机上漏过英文）', () {
    final Set<String> used = <String>{
      for (final Map<String, dynamic> e in exercises)
        ...((e['secondary_muscles'] as List<dynamic>?) ?? const <dynamic>[])
            .cast<String>(),
    };
    expect(used, isNotEmpty, reason: '一个都没有的话这条测试是空转');
    final List<String> missing =
        used.where((String k) => muscleLabel(k) == k).toList()..sort();
    expect(missing, isEmpty, reason: '这些辅助肌群没有中文标签：$missing');
  });

  test('种子里用到的每个器械都有中文标签', () {
    final Set<String> used = <String>{
      for (final Map<String, dynamic> e in exercises) e['equipment'] as String,
    };
    final List<String> missing =
        used.where((String k) => equipmentLabel(k) == k).toList()..sort();
    expect(missing, isEmpty, reason: '这些器械没有中文标签：$missing');
  });

  test('种子里用到的每个类别都有中文标签', () {
    final Set<String> used = <String>{
      for (final Map<String, dynamic> e in exercises) e['category'] as String,
    };
    final List<String> missing =
        used.where((String k) => categoryLabel(k) == k).toList()..sort();
    expect(missing, isEmpty, reason: '这些类别没有中文标签：$missing');
  });

  test('"可选的部位"与"显示用的标签"是两张表：可选只有 6 个主部位', () {
    expect(kPrimaryMuscleGroups.length, 6);
    expect(kPrimaryMuscleGroups.toSet().length, 6, reason: '不许有重复');
    for (final String k in kPrimaryMuscleGroups) {
      expect(muscleLabel(k), isNot(k), reason: '$k 没有中文标签');
    }
    // 标签表**必须比可选表大**：它还要装辅助肌群（背阔肌/肱三头/三角前束…）。
    // 如果哪天两者相等，说明有人又把辅助肌群从标签表里删了，或者把可选表
    // 换成了 kMuscleLabels.entries（2026-09-30 的回归就是这样来的：
    // 选动作页的部位筛选从 6 个 chips 变成 24 个，新建动作页还把器械区挤出屏幕）。
    expect(kMuscleLabels.length, greaterThan(kPrimaryMuscleGroups.length),
        reason: '标签表里应当还包含只用于显示的辅助肌群');
  });

  test('可选部位与种子的主部位完全一致（不多不少）', () {
    final Set<String> seedGroups = <String>{
      for (final Map<String, dynamic> e in exercises) e['muscle_group'] as String,
    };
    expect(seedGroups, kPrimaryMuscleGroups.toSet(),
        reason: '种子里的部位集合和可选列表必须一致，否则筛选会漏或有多余项');
  });
}
