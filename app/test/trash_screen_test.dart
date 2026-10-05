/// 练了么 · 回收站那一屏（2026-10-04）
///
/// 数据层的行为在 `local_store_contract_test.dart`（两个实现同跑），这里只守界面：
///   * 空态**说清这里什么时候会有东西**（不是一句"暂无数据"）；
///   * 列出来的组**认得出是哪一组**（动作名 + 重量 × 次数）；
///   * 点「恢复」真的把它放回去（并且通知上层刷新 —— 否则进步页的数字不会变）。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/profile/trash_screen.dart';

void main() {
  late AppDatabase db;
  late DriftLocalStore store;
  late ExerciseRepository repo;
  int restored = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLocalStore(db);
    repo = ExerciseRepository(db);
    restored = 0;
    await repo.importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TrashScreen(
        store: store,
        repository: repo,
        onRestored: () => restored++,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> log(String id, {int setIndex = 1, double weight = 60}) async {
    await store.saveWorkout(Workout(id: 'w1', startedAtMs: 1000));
    await store.saveSet(SetRecord(
      id: id,
      workoutId: 'w1',
      exerciseId: 'ex_bb_bench_press',
      setIndex: setIndex,
      reps: 8,
      weightKg: weight,
      completedAtMs: 1000 + setIndex,
    ));
  }

  testWidgets('空态说清这里什么时候会有东西', (WidgetTester tester) async {
    await pump(tester);

    expect(find.textContaining('这里空着'), findsOneWidget);
    expect(find.textContaining('长按'), findsOneWidget,
        reason: '要告诉用户"哪种操作会让东西落到这儿"（长按撤销），否则他不知道这里有什么用');
  });

  testWidgets('★ 列出删掉的组（认得出是哪一组），点恢复它回到训练里',
      (WidgetTester tester) async {
    await log('s1');
    await store.deleteSet('s1');
    await pump(tester);

    // 动作名 + 重量 × 次数 —— 只说"一条记录"是认不出来的
    expect(find.text('杠铃卧推 60 kg × 8'), findsOneWidget);

    await tester.tap(find.byKey(const Key('restore-s1')));
    await tester.pumpAndSettle();

    expect(restored, 1, reason: '恢复之后要通知上层刷新（进步页/首页的数字会变）');
    expect(await store.allSets(), hasLength(1), reason: '真的回到库里了');
    expect(await store.deletedSets(), isEmpty, reason: '界面也应当空了');
    expect(find.textContaining('这里空着'), findsOneWidget);
  });
}
