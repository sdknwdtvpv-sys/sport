/// 练了么 · 动作选择页 widget 测试
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/features/exercise/exercise_picker_screen.dart';

void main() {
  late AppDatabase db;
  late ExerciseRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = ExerciseRepository(db);
    await repo.importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
  });

  tearDown(() => db.close());

  Future<void> pumpPicker(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ExercisePickerScreen(repository: repo)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('默认按常用度列出动作', (WidgetTester tester) async {
    await pumpPicker(tester);

    expect(find.byKey(const Key('exercise-search')), findsOneWidget);
    // popularity 100 的杠铃卧推应该在最前面那批里
    expect(find.text('杠铃卧推'), findsOneWidget);
  });

  testWidgets('搜索同时匹配名称与别名', (WidgetTester tester) async {
    await pumpPicker(tester);

    await tester.enterText(find.byKey(const Key('exercise-search')), 'bp');
    await tester.pumpAndSettle();

    expect(find.text('杠铃卧推'), findsOneWidget, reason: 'bp 是它的别名');
    expect(find.text('杠铃深蹲'), findsNothing, reason: '深蹲不该被 bp 搜出来');
  });

  testWidgets('别名也能搜到名字里没有这个词的动作', (WidgetTester tester) async {
    await pumpPicker(tester);

    await tester.enterText(find.byKey(const Key('exercise-search')), '法式卧推');
    await tester.pumpAndSettle();

    expect(find.text('仰卧臂屈伸'), findsOneWidget,
        reason: '「法式卧推」是仰卧臂屈伸的别名');
  });

  testWidgets('点击动作会把它作为路由结果返回', (WidgetTester tester) async {
    ExerciseData? picked;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked = await Navigator.of(ctx).push<ExerciseData>(
                    MaterialPageRoute<ExerciseData>(
                      builder: (_) => ExercisePickerScreen(repository: repo),
                    ),
                  );
                },
                child: const Text('开始'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('exercise-search')), 'rdl');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exercise-ex_rdl')));
    await tester.pumpAndSettle();

    expect(picked?.id, 'ex_rdl');
  });

  testWidgets('搜不到时给明确空状态，而不是一片空白', (WidgetTester tester) async {
    await pumpPicker(tester);

    await tester.enterText(find.byKey(const Key('exercise-search')), 'zzzzzz');
    await tester.pumpAndSettle();

    expect(find.textContaining('没找到'), findsOneWidget);
  });
}
