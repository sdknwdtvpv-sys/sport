/// 练了么 · **两类列表行的文字在同一列**（VI 计划 T1-8）
///
/// **为什么要有它**：全仓有两种"列表行" ——
///   * Material 的 `ListTile`（26 处：设置、数据与备份、计划模板…），
///   * 自绘的行（`all_data_screen._recordRow` 这种）。
///
/// 前者曾经在 15 个地方各自写 `contentPadding: …s4`（16pt），后者按 20pt 排 ——
/// 于是同一台手机上，「数据与备份」的行文字在 x=36，「全部记录」的行文字在 x=20，
/// **两个都在说"记录"的列表，文字差 16pt**。这一条把那个数交给 `theme.dart` 一处说，
/// 并且用几何断言钉住：**两条链路量出来的 dx 必须相等**。
///
/// 为什么不用"看起来对齐了"当判据：截图是人眼比对的，改完 theme 之后没人会再比一次；
/// 而 `tester.getTopLeft(...).dx` 每次都会比。
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/data/db.dart' hide SetRecord, Workout, Exercise, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/profile/settings_home_screen.dart';
import 'package:lianleme/features/progress/all_data_screen.dart';

/// 手机几何（逻辑像素 390 × 844，iPhone 14/15 那一档）。
/// **必须在手机宽度下量**：800×600 的默认测试窗口宽到不会换行，
/// 那样量出来的对齐在真机上不成立。
const Size kPhone = Size(390, 844);

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late AppDatabase db;
  late DriftLocalStore store;
  late ExerciseRepository repo;
  late ProfileRepository profile;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftLocalStore(db);
    repo = ExerciseRepository(db);
    profile = ProfileRepository(db);
    await repo.importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
  });

  tearDown(() => db.close());

  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = kPhone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// 「数据与备份」第一行（`ListTile`）标题的左边缘。
  Future<double> listTileRowDx(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SettingsHomeScreen(store: store, repository: repo, profile: profile),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-data-tools')));
    await tester.pumpAndSettle();
    // 「导出全部记录」是第一区里的行（`open-body-metric` 只在有身体数据时才在）
    await tester.dragUntilVisible(
      find.text('导出全部记录'),
      find.byType(ListView).first,
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();
    return tester.getTopLeft(find.text('导出全部记录')).dx;
  }

  /// 「全部记录」里一行（自绘行）日期那一格的左边缘。
  Future<double> selfDrawnRowDx(WidgetTester tester) async {
    // ⚠️ 换一棵树之前必须先把它**拆掉**：`pumpWidget` 遇到同类型的根 widget
    // （`MaterialApp` → `MaterialApp`）会复用 Element 树，于是 Navigator 的路由栈
    // 也一起活着 —— 上一段推上去的「数据与备份」会仍然压在顶上，量到的是它的 dx
    // （`profile_structure_test.dart` 开头也踩过同一个坑）。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await store.saveSet(SetRecord(
      id: 'a',
      workoutId: 'w1',
      exerciseId: 'ex_bb_bench_press',
      setIndex: 1,
      reps: 8,
      weightKg: 60,
      setType: SetType.normal,
      completedAtMs: DateTime(2026, 9, 28, 9).millisecondsSinceEpoch,
    ));
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: AllDataScreen(
        store: store,
        repository: repo,
        unit: WeightUnit.kg,
        now: DateTime(2026, 9, 28, 10),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('9/28'),
      find.byType(ListView).first,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    return tester.getTopLeft(find.text('9/28')).dx;
  }

  testWidgets('数据与备份与全部记录的列表行文字左边缘相等', (WidgetTester tester) async {
    usePhone(tester);
    final double tileDx = await listTileRowDx(tester);

    // 两次 pump 之间要把上一棵树的尺寸影响清掉：同一个 tester 连续 pump 是允许的，
    // 但 `saveSet` 会改变数据，所以第二段必须重新 pump（这里就是重 pump）。
    final double rowDx = await selfDrawnRowDx(tester);

    expect(tileDx, 20 + Tokens.s5,
        reason: 'ListTile 行文字 = 屏边距 s5 + 主题的 contentPadding s5');
    expect(rowDx, 20 + Tokens.s5,
        reason: '自绘行 = 屏边距 s5 + `_card` 自己的内边距 s5');
    expect(tileDx, rowDx,
        reason: '两类列表行的文字必须在同一列：ListTile=$tileDx、自绘=$rowDx');
  });

  testWidgets('反向自检：把主题的 contentPadding 拿掉，两条链路就不再相等',
      (WidgetTester tester) async {
    usePhone(tester);
    // 这是一条**故意破坏**的对照：默认 `ListTile`（无 listTileTheme）是 16。
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: const Scaffold(
        body: ListTile(title: Text('身体数据')),
      ),
    ));
    await tester.pumpAndSettle();
    final double bare = tester.getTopLeft(find.text('身体数据')).dx;
    expect(bare, isNot(20 + Tokens.s5),
        reason: '没有主题时的 ListTile 内边距不是 s5 —— 这条断言证明上面量到的值来自主题');
  });
}
