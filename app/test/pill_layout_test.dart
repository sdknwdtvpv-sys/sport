/// 练了么 · 胶囊选项的**尺寸契约**（组件级 + 页面级，2026-10-04）
///
/// **为什么值得单独一个文件**：同一个 bug（胶囊被撑成通栏）在仓库里出现过
/// **三份**——偏好设置的休息时长、计划编辑的组数/次数、新建动作的部位/器械/休息。
/// 三份拷贝、同一个坑、同一个症状（6 个选项各占一整行，半个屏幕没了），
/// 而**没有一行代码报错**：`Container(alignment: ...)` 会撑满拿到的约束，
/// `Wrap` 给的正是**有界宽度**（`Row` / 横向 `ListView` 给的是无界，
/// 所以同一个写法在别处看着是对的 —— 这就是它容易被抄下去的原因）。
///
/// 这一组测试守两层：
///   1. **组件本身**（`core/pills.dart`）：放在 `Wrap` 里必须按内容宽度收缩；
///   2. **真的用它的两个页面**：不只看组件，而是把页面开起来量真实尺寸 ——
///      否则"组件改好了、页面又抄了一遍旧的"仍然绿。
///
/// 文件末尾那两条**对照**测试是刻意保留的：它们渲染的是**旧的错写法**，
/// 断言它**确实**被撑满。没有它们的话，"量出来很窄"可能只是因为量错了地方，
/// 守卫会变成永远绿的摆设。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/pills.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart'
    hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/routine_repository.dart';
import 'package:lianleme/features/exercise/custom_exercise_screen.dart';
import 'package:lianleme/features/routine/routine_screen.dart';

/// 把 [children] 放进一个**固定宽度**的 `Wrap` ——
/// 复刻出当初撑满胶囊的那种约束（有界宽度）。
Future<void> pumpInWrap(WidgetTester tester, List<Widget> children,
    {double width = 360}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: Wrap(
            spacing: Tokens.s2,
            runSpacing: Tokens.s2,
            children: children,
          ),
        ),
      ),
    ),
  ));
}

/// 旧写法（**只出现在对照测试里**）：带 `alignment` 的 Container 会撑满约束。
Widget _legacyStretchingPill(String label, {Key? key}) => GestureDetector(
      key: key,
      onTap: () {},
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
        height: 36,
        decoration: BoxDecoration(
          color: Tokens.surface,
          borderRadius: BorderRadius.circular(Tokens.rPill),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13)),
      ),
    );

void main() {
  group('组件契约', () {
    testWidgets('胶囊在 Wrap 里按内容收缩（不是通栏）', (WidgetTester tester) async {
      await pumpInWrap(tester, <Widget>[
        choicePill(
          key: const Key('probe'),
          label: '90 秒',
          active: false,
          onTap: () {},
        ),
      ]);

      final Size s = tester.getSize(find.byKey(const Key('probe')));
      expect(s.width, lessThan(150),
          reason: '「90 秒」这种短标签不该占掉一整行（Wrap 宽 360）');
      expect(s.height, 36, reason: '高度仍是设计稿上的 36');
    });

    testWidgets('多个胶囊能排在同一行（用户看到的"一行放得下"）',
        (WidgetTester tester) async {
      await pumpInWrap(tester, <Widget>[
        for (int i = 0; i < 3; i++)
          choicePill(
            key: Key('probe-$i'),
            label: <String>['60 秒', '90 秒', '120 秒'][i],
            active: false,
            onTap: () {},
          ),
      ]);

      final Set<double> tops = <double>{
        for (int i = 0; i < 3; i++)
          tester.getTopLeft(find.byKey(Key('probe-$i'))).dy,
      };
      expect(tops.length, 1,
          reason: '三个短胶囊必须同一行 —— 通栏时它们会各占一行');
    });
  });

  group('真的用它的页面', () {
    late AppDatabase db;
    late RoutineRepository routines;
    late ExerciseRepository exercises;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      routines = RoutineRepository(db);
      exercises = ExerciseRepository(db);
      await exercises.importSeed(
        loadJson: () => File('assets/exercises.json').readAsString(),
      );
    });

    tearDown(() => db.close());

    testWidgets('计划编辑：组数/次数胶囊是一行排开的', (WidgetTester tester) async {
      final RoutineData r = await routines.create('推日', nowMs: 1000);
      final RoutineItemData item =
          await routines.addItem(r.id, 'ex_bb_bench_press', nowMs: 1001);

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: RoutineListScreen(
          repository: routines,
          exercises: exercises,
          store: DriftLocalStore(db),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('routine-open-${r.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('routine-item-${item.id}')));
      await tester.pumpAndSettle();

      final double setWidth = tester.getSize(find.byKey(const Key('set-5'))).width;
      expect(setWidth, lessThan(100),
          reason: '组数胶囊只有一个字符，必须是窄的（被撑满时≈整屏宽）');
      expect(
        tester.getTopLeft(find.byKey(const Key('set-3'))).dy,
        tester.getTopLeft(find.byKey(const Key('set-5'))).dy,
        reason: '3 和 5 必须同一行',
      );
    });

    testWidgets('新建动作：部位/器械/休息三组胶囊都不是通栏',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: CustomExerciseScreen(repository: exercises),
      ));
      await tester.pumpAndSettle();

      for (final String key in <String>[
        'custom-muscle-chest',
        'custom-equipment-barbell',
        'custom-rest-90',
      ]) {
        expect(tester.getSize(find.byKey(Key(key))).width, lessThan(160),
            reason: '$key 被撑成通栏了（旧的 Container(alignment:) 写法）');
      }
    });
  });

  group('对照：守卫本身能红', () {
    // 这两条**故意**渲染旧写法。它们绿，说明上面那些"宽度很小"的断言
    // 确实能分辨"收缩"与"撑满"；哪天量法失效，这里会先红。
    testWidgets('旧写法在 Wrap 里确实会被撑满（所以上面的断言有意义）',
        (WidgetTester tester) async {
      await pumpInWrap(tester, <Widget>[_legacyStretchingPill('90 秒', key: const Key('legacy'))]);
      expect(tester.getSize(find.byKey(const Key('legacy'))).width, 360,
          reason: '有界宽度 + alignment ⇒ 撑满；这正是 v1.42.2 修掉的那个 bug');
    });

    testWidgets('旧写法多个胶囊各占一行（用户看到的症状）',
        (WidgetTester tester) async {
      await pumpInWrap(tester, <Widget>[
        for (int i = 0; i < 3; i++)
          _legacyStretchingPill(<String>['60 秒', '90 秒', '120 秒'][i],
              key: Key('legacy-$i')),
      ]);
      final Set<double> tops = <double>{
        for (int i = 0; i < 3; i++)
          tester.getTopLeft(find.byKey(Key('legacy-$i'))).dy,
      };
      expect(tops.length, 3, reason: '每个胶囊各占一行 —— 半个屏幕就是这么没的');
    });
  });
}
