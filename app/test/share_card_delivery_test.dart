/// 练了么 · 分享卡交付测试
///
/// 「生成图片」在 `share_card_test.dart` 里验证（PNG 魔数、尺寸、倍率）。
/// 这里验证的是**抓到之后交给了谁、传了什么** —— 所以 `capture` 与 `exporter`
/// 两个边界都被换成了假的：真身一个依赖引擎异步、一个依赖平台通道，
/// 在 widget 测试里都跑不了。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/summary/share_card_exporter.dart';
import 'package:lianleme/features/summary/share_card_preview_screen.dart';
import 'package:lianleme/features/summary/workout_summary.dart';
import 'package:lianleme/features/summary/workout_summary_screen.dart';

/// 假字节：只要能验"原样传下去了"就够，不需要真 PNG。
final Uint8List _fakePng = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);

class _FakeExporter implements ShareCardExporter {
  final List<Uint8List> shared = <Uint8List>[];
  final List<Uint8List> saved = <Uint8List>[];
  String? lastName;

  /// 相册权限是否给了 —— 用来验证"被拒时不能假装成功"
  bool grantAccess = true;

  @override
  Future<void> shareToSystem(Uint8List png,
      {String fileName = 'lianleme'}) async {
    shared.add(png);
    lastName = fileName;
  }

  @override
  Future<bool> saveToGallery(Uint8List png,
      {String fileName = 'lianleme'}) async {
    saved.add(png);
    lastName = fileName;
    return grantAccess;
  }
}

WorkoutSummary _summary() => WorkoutSummary(
      workoutId: 'w1',
      totalSets: 12,
      totalVolumeKg: 5400,
      duration: const Duration(minutes: 52),
      exerciseCount: 4,
      prs: const <SetPr>[],
      startedAtMs: DateTime(2026, 9, 28, 19, 30).millisecondsSinceEpoch,
    );

Future<void> _pumpPreview(
  WidgetTester tester,
  _FakeExporter exporter,
) async {
  await tester.pumpWidget(MaterialApp(
    home: ShareCardPreviewScreen(
      summary: _summary(),
      exporter: exporter,
      capture: (GlobalKey _) async => _fakePng,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('预览页会先把卡片画出来（分享前看不到内容是很糟的体验）',
      (WidgetTester tester) async {
    await _pumpPreview(tester, _FakeExporter());

    expect(find.byKey(const Key('share-card')), findsOneWidget);
    expect(find.text('训练完成'), findsOneWidget);
    expect(find.text('2026 年 9 月 28 日'), findsOneWidget);
  });

  testWidgets('点「分享」：把抓到的字节原样交给分享通道，文件名带日期',
      (WidgetTester tester) async {
    final _FakeExporter ex = _FakeExporter();
    await _pumpPreview(tester, ex);

    await tester.tap(find.byKey(const Key('share-card-share')));
    await tester.pumpAndSettle();

    expect(ex.shared, hasLength(1));
    expect(ex.shared.single, _fakePng, reason: '必须是刚抓到的那份字节');
    expect(ex.lastName, 'lianleme_20260928', reason: '文件名带日期，相册里认得出来');
  });

  testWidgets('点「存相册」成功时如实说成功', (WidgetTester tester) async {
    final _FakeExporter ex = _FakeExporter();
    await _pumpPreview(tester, ex);

    await tester.tap(find.byKey(const Key('share-card-save')));
    await tester.pumpAndSettle();

    expect(ex.saved, hasLength(1));
    expect(ex.saved.single, _fakePng);
    expect(find.text('已存进相册'), findsOneWidget);
  });

  testWidgets('相册权限被拒时不假装成功（必须如实告诉用户）',
      (WidgetTester tester) async {
    final _FakeExporter ex = _FakeExporter()..grantAccess = false;
    await _pumpPreview(tester, ex);

    await tester.tap(find.byKey(const Key('share-card-save')));
    await tester.pumpAndSettle();

    expect(ex.saved, hasLength(1), reason: '尝试过了');
    expect(find.text('已存进相册'), findsNothing);
    expect(find.textContaining('没有相册权限'), findsOneWidget);
  });

  testWidgets('分享失败不崩，只给一条提示（用户刚练完，最不该看到崩溃）',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ShareCardPreviewScreen(
        summary: _summary(),
        exporter: _ThrowingExporter(),
        capture: (GlobalKey _) async => _fakePng,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('share-card-share')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '不能把异常抛出去');
    expect(find.textContaining('没成功'), findsOneWidget);
  });

  group('S7 的入口', () {
    late AppDatabase db;
    late DriftLocalStore store;
    late ExerciseRepository repo;
    late SummaryService service;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      store = DriftLocalStore(db);
      repo = ExerciseRepository(db);
      service = SummaryService(store: store, repository: repo);
      await repo.importSeed(
        loadJson: () => File('assets/exercises.json').readAsString(),
      );
    });

    tearDown(() => db.close());

    Future<void> pumpSummary(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: WorkoutSummaryScreen(
          service: service,
          workoutId: 'w1',
          exporter: _FakeExporter(),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('有记录时显示「分享训练卡」，点进去是预览页',
        (WidgetTester tester) async {
      // 训练行也必须落库：SummaryService.build 走的是 loadWorkout，
      // 只写 set_record 的话它根本找不到这次训练（这个坑数据层注释里记过）
      await store.saveWorkout(Workout(id: 'w1', startedAtMs: 1000));
      await store.saveSet(SetRecord(
        id: 's1',
        workoutId: 'w1',
        exerciseId: 'ex_bb_bench_press',
        setIndex: 1,
        reps: 8,
        completedAtMs: 2000,
        weightKg: 60,
      ));
      await pumpSummary(tester);

      expect(find.byKey(const Key('summary-share')), findsOneWidget);

      await tester.tap(find.byKey(const Key('summary-share')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('share-card')), findsOneWidget);
    });

    testWidgets('一次都没练时不显示分享入口（没有可分享的东西）',
        (WidgetTester tester) async {
      await pumpSummary(tester);

      expect(find.byKey(const Key('summary-share')), findsNothing);
      expect(find.textContaining('这次没有记录到任何一组'), findsOneWidget);
    });
  });
}

class _ThrowingExporter implements ShareCardExporter {
  @override
  Future<void> shareToSystem(Uint8List png,
          {String fileName = 'lianleme'}) async =>
      throw StateError('模拟分享通道失败');

  @override
  Future<bool> saveToGallery(Uint8List png,
          {String fileName = 'lianleme'}) async =>
      throw StateError('模拟相册写入失败');
}
