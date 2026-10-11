/// 练了么 · 动作插图（RepDB）的四条判据
///
/// **为什么这些要写成测试而不是留在注释里**：插图这件事的失败方式全是"静默"的 ——
/// 清单与文件对不上、署名被删、图片路径写错、许可原文丢了，**没有一条会让 App 崩**。
/// 它们只会让"我们以为有的授权"或"用户以为有的图"变成假的。
///
/// 判据：
///   1. 清单本身自洽：每条的 repdb id 唯一、路径在 assets/repdb-art/ 下；
///   2. **清单里每一个路径都真的存在**（在 `app/` 目录下按文件系统核）——
///      这是"打包了却读不到图"唯一的机械守卫（pubspec 漏声明由 Node 守卫核）；
///   3. 逐字署名 [kRepdbAttribution] 没有被改写；
///   4. 详情页：有图就画图、没图就什么都不画（**不许因为少一张图而崩或空一块**）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/icon_spec.dart';
import 'package:lianleme/data/db.dart' show ExerciseData;
import 'package:lianleme/data/repdb_art.dart';
import 'package:lianleme/features/exercise/exercise_detail_screen.dart';

/// 造一条最小的动作数据（只有详情页用得到的字段）
ExerciseData _exercise(String id) => ExerciseData(
      id: id,
      name: '杠铃卧推',
      nameEn: 'Barbell Bench Press',
      aliases: '[]',
      muscleGroup: 'chest',
      secondaryMuscles: '[]',
      equipment: 'barbell',
      category: 'strength',
      trackType: 'weight_reps',
      defaultRestSec: 120,
      defaultWeightKg: 40,
      weightIncrement: 2.5,
      instructions: '肩胛后收贴凳，杠铃落在乳头附近。',
      subTags: '[]',
      isBuiltin: true,
      popularity: 100,
      createdAt: 0,
      updatedAt: 0,
    );

Future<Map<String, dynamic>> _manifest() async =>
    jsonDecode(File('assets/repdb-art.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('★ 清单自洽：每个动作一条、repdb id 不重复、路径都在 assets/repdb-art/ 下', () async {
    final Map<String, dynamic> m = await _manifest();
    expect(m['attribution'], kRepdbAttribution,
        reason: '清单里的署名必须与代码里的常量逐字相同');
    final List<dynamic> rows = m['exercises'] as List<dynamic>;
    expect(rows.length, greaterThan(100),
        reason: '匹配到的动作太少，八成是映射表被清过 —— 少于 100 条不正常');

    final Set<String> ourIds = <String>{};
    final Set<String> repdbIds = <String>{};
    for (final dynamic r in rows) {
      final Map<String, dynamic> row = r as Map<String, dynamic>;
      final String id = row['id'] as String;
      final String repdb = row['repdb'] as String;
      expect(ourIds.add(id), isTrue, reason: '我们的动作 id 重复：$id');
      // 一个 RepDB 动作只能配我们一个动作：一张图配两个动作必然有一边是错的
      expect(repdbIds.add(repdb), isTrue, reason: 'RepDB id「$repdb」被两个动作共用');
      final List<String> paths = <String>[
        for (final String k in <String>['start', 'peak', 'main'])
          if (row[k] != null) row[k] as String,
      ];
      expect(paths, isNotEmpty, reason: '$id 一条图都没有');
      for (final String p in paths) {
        expect(p, startsWith('assets/repdb-art/'),
            reason: '$id 的图片路径「$p」不在 assets/repdb-art/ 下');
        expect(p.contains('premium'), isFalse,
            reason: '$id 指向了付费档预览图（许可第 6 条：一字节都不许进包）');
      }
    }
  });

  test('★ 清单里每个路径都真的存在（"打包了却读不到图"的唯一机械守卫）', () async {
    final Map<String, dynamic> m = await _manifest();
    final List<String> missing = <String>[];
    for (final dynamic r in m['exercises'] as List<dynamic>) {
      final Map<String, dynamic> row = r as Map<String, dynamic>;
      for (final String k in <String>['start', 'peak', 'main']) {
        final Object? p = row[k];
        if (p is! String) continue;
        if (!File(p).existsSync()) missing.add('$p（${row['id']}）');
      }
    }
    expect(missing, isEmpty,
        reason: '清单引用了不存在的图片 —— 跑 `node tool/vendor-repdb-art.mjs` 重新生成：\n'
            '${missing.take(10).join('\n')}');
  });

  test('★ 逐字署名没被改写（许可证第 2 条要求的原文）', () {
    expect(kRepdbAttribution, 'Exercise data by RepDB (repdb.co)');
  });

  test('★ 清单解析：一份最小清单能读出主图/第二姿势，坏数据降级成空而不抛', () {
    final RepdbArtCatalog c = RepdbArtCatalog.fromJson(<String, dynamic>{
      'exercises': <dynamic>[
        <String, dynamic>{
          'id': 'ex_a',
          'repdb': 'a',
          'start': 'assets/repdb-art/a-start.webp',
          'peak': 'assets/repdb-art/a-peak.webp',
        },
        <String, dynamic>{'id': 'ex_b', 'repdb': 'b', 'main': 'assets/repdb-art/b-main.webp'},
        // 坏数据：没有图 / 缺 id / 字段类型不对 —— 都要被跳过，不能抛
        <String, dynamic>{'id': 'ex_c', 'repdb': 'c'},
        <String, dynamic>{'repdb': 'd', 'main': 'assets/repdb-art/d-main.webp'},
        <String, dynamic>{'id': 'ex_e', 'repdb': 'e', 'main': 42},
      ],
    });
    expect(c.count, 2);
    final ExerciseArt a = c.forExercise('ex_a')!;
    expect(a.hero, 'assets/repdb-art/a-peak.webp', reason: '主图优先顶峰');
    expect(a.hasSecondPose, isTrue);
    expect(a.secondPose, 'assets/repdb-art/a-start.webp');
    expect(c.forRepdbId('b')!.hero, 'assets/repdb-art/b-main.webp');
    expect(c.forExercise('ex_c'), isNull);
    expect(c.forExercise('ex_e'), isNull);
    // 空清单 / 结构不对的清单：返回空，不抛
    expect(RepdbArtCatalog.fromJson(<String, dynamic>{}).count, 0);
    expect(RepdbArtCatalog.fromJson(<String, dynamic>{'exercises': 'nope'}).count, 0);
  });

  testWidgets('★ 详情页：有插图就画，且角上标着 AI 生成；切姿势能换图', (WidgetTester tester) async {
    final RepdbArtCatalog catalog = RepdbArtCatalog.fromJson(<String, dynamic>{
      'exercises': <dynamic>[
        <String, dynamic>{
          'id': 'ex_bb_bench_press',
          'repdb': 'bench-press',
          'start': 'assets/repdb-art/bench-press-start.webp',
          'peak': 'assets/repdb-art/bench-press-peak.webp',
        },
      ],
    });
    RepdbArt.debugSet(catalog);
    addTearDown(() => RepdbArt.debugSet(null));

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: ExerciseDetailScreen(exercise: _exercise('ex_bb_bench_press')),
    ));
    await tester.pump();

    expect(find.byKey(const Key('detail-art')), findsOneWidget);
    expect(find.byKey(const Key('detail-art-image')), findsOneWidget);
    // AI 生成标注是合规要求（《人工智能生成合成内容标识办法》），不是排版细节
    expect(find.byKey(const Key('detail-art-caption')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('detail-art-caption'))).data,
      contains('AI 生成'),
    );

    // 切换姿势：默认是顶峰（hero），点一下换成起始。
    // `ensureVisible` 是必需的：详情页是个 ListView，插图在它下面 ——
    // 不滚到可见位置的话 tap 会落在别的 widget 上（`warnIfMissed` 会警告，但不失败）。
    expect(find.text('看起始姿势'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('detail-art-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('detail-art-toggle')));
    await tester.pump();
    expect(find.text('看顶峰姿势'), findsOneWidget);
    // 图本身是 Image.asset，路径跟着换（测试环境没有真 asset，会走占位分支 —— 正好也验了不崩）
    expect(tester.takeException(), isNull);
  });

  testWidgets('★ 详情页：没有插图时不许画空框、也不许崩', (WidgetTester tester) async {
    RepdbArt.debugSet(RepdbArtCatalog.empty);
    addTearDown(() => RepdbArt.debugSet(null));

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: ExerciseDetailScreen(exercise: _exercise('ex_nobody_has_this')),
    ));
    await tester.pump();

    expect(find.byKey(const Key('detail-art')), findsNothing,
        reason: '没有图就不该画出插图块（空框比没有更糟）');
    // 文字说明照旧在 —— 插图没了不该影响这一屏的主要功能
    expect(find.byKey(const Key('detail-instructions')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('★ 图片文件缺失时不白屏（文件被删/清单漂了都走占位）', (WidgetTester tester) async {
    final RepdbArtCatalog catalog = RepdbArtCatalog.fromJson(<String, dynamic>{
      'exercises': <dynamic>[
        <String, dynamic>{'id': 'ex_x', 'repdb': 'x', 'peak': 'assets/repdb-art/does-not-exist.webp'},
      ],
    });
    RepdbArt.debugSet(catalog);
    addTearDown(() => RepdbArt.debugSet(null));

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: ExerciseDetailScreen(exercise: _exercise('ex_x')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 占位图形（不是崩、也不是白屏）
    expect(find.byIcon(iconOf('imageMissing')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('★ 素材目录里不许有付费档预览图（许可第 6 条）', () {
    final Directory dir = Directory('assets/repdb-art');
    expect(dir.existsSync(), isTrue, reason: 'assets/repdb-art 不在 —— 插图没生成');
    final List<String> bad = <String>[
      for (final FileSystemEntity e in dir.listSync())
        if (e is File && RegExp('premium|sample', caseSensitive: false).hasMatch(e.path))
          e.path,
    ];
    expect(bad, isEmpty, reason: '付费档预览图仅限评估，不得进包：${bad.join(', ')}');
  });

  test('★ 整体体积在预算内（超了说明有人把原图塞进来了）', () {
    // 320px 重编码后 426 张约 2.8MB；留一倍余量到 6MB 就够 ——
    // 一旦有人误把 512px 原图拷进来（约 8MB）会当场红。
    const int budgetBytes = 6 * 1024 * 1024;
    int total = 0;
    for (final FileSystemEntity e in Directory('assets/repdb-art').listSync()) {
      if (e is File) total += e.lengthSync();
    }
    expect(total, lessThan(budgetBytes),
        reason: '插图合计 ${(total / 1024 / 1024).toStringAsFixed(2)} MB，超预算 —— '
            '检查是不是把 512px 原图拷进来了（应当用 tool/vendor-repdb-art.mjs 生成 320px）');
    expect(total, greaterThan(1024 * 1024),
        reason: '插图合计只有 ${(total / 1024).toStringAsFixed(0)} KB —— 是不是全被清空了');
  });

  test('★ 详情页里插图用的是语义图标表的占位（不许写死 Icons.*）', () {
    // icon_spec_test 守的是"尺寸只有 4 档"，这一条守的是"占位图形也走语义表"，
    // 否则 `Icons.image_not_supported_outlined` 会成为一个没人管的孤儿字形。
    final String src =
        File('lib/features/exercise/exercise_detail_screen.dart').readAsStringSync();
    expect(src.contains("iconOf('imageMissing')"), isTrue);
    expect(src.contains('Icons.image_not_supported'), isFalse);
  });
}
