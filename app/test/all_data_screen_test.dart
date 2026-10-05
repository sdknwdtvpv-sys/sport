/// 练了么 · S9「全部数据」界面测试
///
/// 聚合逻辑在 `all_data_test.dart` 里测过了，这里只测"界面有没有把数据摆对地方"。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/progress/all_data_screen.dart';

/// 2026-09-28 是周一
final DateTime kToday = DateTime(2026, 9, 28, 10);

void main() {
  late AppDatabase db;
  late DriftLocalStore store;
  late ExerciseRepository repo;
  String? copied;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLocalStore(db);
    repo = ExerciseRepository(db);
    copied = null;
    await repo.importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
    // 剪贴板是平台通道，测试里要自己接住
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
  });

  tearDown(() => db.close());

  Future<void> saveSet({
    required String id,
    required String exerciseId,
    int reps = 8,
    double? weightKg = 60,
    DateTime? at,
  }) async {
    final DateTime when = at ?? DateTime(2026, 9, 28, 9);
    await store.saveSet(SetRecord(
      id: id,
      workoutId: 'w_${when.day}',
      exerciseId: exerciseId,
      setIndex: 1,
      reps: reps,
      completedAtMs: when.millisecondsSinceEpoch,
      weightKg: weightKg,
    ));
  }

  /// ListView 是懒构建的：没滚到的 widget 根本不存在，find 会直接落空。
  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.dragUntilVisible(
      target,
      find.byType(ListView).first,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pump(WidgetTester tester, {WeightUnit unit = WeightUnit.kg}) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: AllDataScreen(
        store: store,
        repository: repo,
        unit: unit,
        now: kToday,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('没有任何记录时：给出下一步，而不是一片空白',
      (WidgetTester tester) async {
    await pump(tester);

    expect(find.text('全部数据'), findsOneWidget);
    // 库里没有动作历史，所以选择器是空的
    expect(
      tester.widget<Text>(find.byKey(const Key('all-data-exercise-name'))).data,
      '选一个动作',
    );
  });

  testWidgets('有历史时默认选最近练过的动作，并显示历史最佳与趋势',
      (WidgetTester tester) async {
    await saveSet(id: 'a', exerciseId: 'ex_bb_bench_press', reps: 8, weightKg: 60);
    await saveSet(id: 'b', exerciseId: 'ex_bb_bench_press', reps: 5, weightKg: 80,
        at: DateTime(2026, 9, 27, 9));
    await pump(tester);

    expect(
      tester.widget<Text>(find.byKey(const Key('all-data-exercise-name'))).data,
      '杠铃卧推',
      reason: '默认选最近练过的那个',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('all-data-best-weight'))).data,
      '80 kg',
    );
    expect(find.byKey(const Key('all-data-volume-trend')), findsOneWidget);
    // ⚠️ 2026-10-01：维度切换换成"更多"菜单之后首屏高度变了一点，
    // 1RM 那张卡就落到了懒构建的视口之外 —— 不是没渲染，是**没被建出来**。
    // 这条规矩这个文件里早就写着（ListView 懒构建），照它做：先滚到目标再断言。
    await scrollTo(tester, find.byKey(const Key('all-data-1rm-trend')));
    expect(find.byKey(const Key('all-data-1rm-trend')), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('all-data-set-count')));
    expect(tester.widget<Text>(find.byKey(const Key('all-data-set-count'))).data, '2 组');
  });

  testWidgets('单位是 lb 时，这一屏也跟着换算', (WidgetTester tester) async {
    await saveSet(id: 'a', exerciseId: 'ex_bb_bench_press', reps: 8, weightKg: 60);
    await pump(tester, unit: WeightUnit.lb);

    expect(
      tester.widget<Text>(find.byKey(const Key('all-data-best-weight'))).data,
      '132.3 lb',
    );
  });

  testWidgets('自重动作比次数：重量/1RM/容量三行与两张零线图都不出现',
      (WidgetTester tester) async {
    await saveSet(id: 'a', exerciseId: 'ex_pull_up', reps: 12, weightKg: null);
    await pump(tester);

    // 2026-10-01 真机走查改的：以前这三行都在，只是值全是「—」，
    // 下面还叠着"容量趋势 / 1RM 趋势"两条恒为零的平线 —— 白占两屏。
    expect(find.byKey(const Key('all-data-best-weight')), findsNothing,
        reason: '自重动作没有"最大重量"这回事');
    expect(find.byKey(const Key('all-data-best-1rm')), findsNothing);
    expect(find.byKey(const Key('all-data-total-volume')), findsNothing,
        reason: '容量 = 重量 × 次数，自重动作算不出来');
    expect(find.byKey(const Key('all-data-volume-trend')), findsNothing);
    expect(find.byKey(const Key('all-data-1rm-trend')), findsNothing);

    // 该显示的是次数：最佳 + 一条次数趋势
    expect(
      tester.widget<Text>(find.byKey(const Key('all-data-best-reps'))).data,
      '12 次',
    );
    await scrollTo(tester, find.byKey(const Key('all-data-reps-trend')));
    expect(find.byKey(const Key('all-data-reps-trend')), findsOneWidget);
    expect(find.textContaining('自重动作不比容量与 1RM'), findsOneWidget);
  });

  testWidgets('切到「按时间」显示本周 / 本月与月趋势', (WidgetTester tester) async {
    await saveSet(id: 'a', exerciseId: 'ex_bb_bench_press');
    await pump(tester);

    // 2026-10-06：维度切换改回**明面上的分段控件**（一次点击就够）
    expect(find.byKey(const Key('all-data-mode')), findsOneWidget);
    await tester.tap(find.byKey(const Key('seg-按时间看')));
    await tester.pumpAndSettle();

    expect(find.text('本周'), findsOneWidget);
    expect(find.text('本月'), findsOneWidget);
    expect(find.byKey(const Key('all-data-week')), findsOneWidget);
    expect(find.byKey(const Key('all-data-month')), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('all-data-month-trend')));
    expect(find.byKey(const Key('all-data-month-trend')), findsOneWidget);
  });

  testWidgets('导出 CSV：把记录写进剪贴板（单位跟随）', (WidgetTester tester) async {
    await saveSet(id: 'a', exerciseId: 'ex_bb_bench_press');
    await pump(tester, unit: WeightUnit.lb);

    await tester.tap(find.byKey(const Key('all-data-export')));
    await tester.pumpAndSettle();

    expect(copied, isNotNull);
    expect(copied, startsWith('日期,动作,重量lb,次数,容量lb,组序'),
        reason: '表头也要写清楚是哪个单位');
  });

  testWidgets('切换动作会把统计换成那个动作的', (WidgetTester tester) async {
    await saveSet(id: 'a', exerciseId: 'ex_bb_bench_press', weightKg: 60);
    await saveSet(id: 'b', exerciseId: 'ex_pull_up', reps: 12, weightKg: null,
        at: DateTime(2026, 9, 27, 9));
    await pump(tester);

    // 最近练的是卧推（9/28）
    expect(
      tester.widget<Text>(find.byKey(const Key('all-data-exercise-name'))).data,
      '杠铃卧推',
    );

    // 通过选择器换成引体向上
    await tester.tap(find.byKey(const Key('all-data-pick-exercise')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('exercise-search')), '引体');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exercise-ex_pull_up')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('all-data-exercise-name'))).data,
      '引体向上',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('all-data-best-reps'))).data,
      '12 次',
    );
  });
}
