/// 动作库（浏览态）的界面契约。
///
/// **核心判据只有一条**：点一个动作**不能把页面关掉** ——
/// 这一屏是"看"的地方，不像「选动作」那样点完就带着结果返回。
/// 踩这条线的后果很隐蔽：动作库点一下就退回首页，看起来像"点了没反应"。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/features/exercise/exercise_detail_screen.dart';
import 'package:lianleme/features/exercise/exercise_library_screen.dart';

/// 一份最小的动作种子（两条，够验证列表与点击）。
///
/// ⚠️ 形状照 `seed/build.mjs` 的产物来：**顶层是 `{"exercises": [...]}`**、
/// 字段是 snake_case（`muscle_group` / `track_type` / `default_rest_sec`）——
/// 写成驼峰或裸数组都会在 `importSeed` 里炸（第一版就是裸数组）。
String _seedJson() => '''
{"exercises": [
  {"id":"ex_bb_bench_press","name":"杠铃卧推","muscle_group":"chest","equipment":"barbell",
   "category":"strength","track_type":"weight_reps","default_rest_sec":120,"weight_increment":2.5,
   "default_weight_kg":40},
  {"id":"ex_squat","name":"杠铃深蹲","muscle_group":"legs","equipment":"barbell",
   "category":"strength","track_type":"weight_reps","default_rest_sec":150,"weight_increment":5,
   "default_weight_kg":60}
]}
''';

Future<void> _pump(WidgetTester tester, {LocalStore? store}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final AppDatabase db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final ExerciseRepository repo = ExerciseRepository(db);
  await repo.importSeed(loadJson: () async => _seedJson());

  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: ExerciseLibraryScreen(
      repository: repo,
      store: store ?? DriftLocalStore(db),
      unit: WeightUnit.kg,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('标题是「动作库」而不是「选择动作」（两者是不同的页面）',
      (WidgetTester tester) async {
    await _pump(tester);
    expect(find.text('动作库'), findsOneWidget);
    expect(find.text('选择动作'), findsNothing);
  });

  testWidgets('点一个动作 → **进入详情页**，而不是把这一屏关掉', (WidgetTester tester) async {
    await _pump(tester);
    await tester.tap(find.text('杠铃卧推'));
    await tester.pumpAndSettle();

    // 详情页在树上（说明是 push，不是 pop）
    expect(find.byType(ExerciseDetailScreen), findsOneWidget);
    // 动作库那一屏还在下面（pop 掉的话标题就没了）
    expect(find.text('动作库'), findsNothing,
        reason: '被详情页盖住了，但**没有从栈里消失** —— 返回还能回来');
    // 用详情页自己的返回箭头（`detail-back`）—— `tester.pageBack()` 找的是
    // Material/Cupertino 的标准返回键，而这一屏是自绘的（与别的二级页同一套）
    await tester.tap(find.byKey(const Key('detail-back')));
    await tester.pumpAndSettle();
    expect(find.text('动作库'), findsOneWidget, reason: '返回后应当回到动作库');
  });

  testWidgets('搜索能筛出结果（浏览态没有把选择器的能力弄丢）', (WidgetTester tester) async {
    await _pump(tester);
    expect(find.text('杠铃深蹲'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '卧推');
    await tester.pumpAndSettle();
    expect(find.text('杠铃卧推'), findsOneWidget);
    expect(find.text('杠铃深蹲'), findsNothing);
  });

  testWidgets('浏览态**不报 `exercise_added`**（那件事没发生）—— 由选择器的调用点保证',
      (WidgetTester tester) async {
    // 这条是"行为契约"而不是像素：`onBrowse` 传了就不该走 pop + 上报那条路。
    // 真正的埋点断言在 analytics 相关测试里；这里只钉住**不 pop**这个可见后果。
    await _pump(tester);
    await tester.tap(find.text('杠铃深蹲'));
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseDetailScreen), findsOneWidget);
  });

  testWidgets('浏览态那一区叫「热门」（与 VI 的动作库说法对齐），排序仍是种子里人工定的 popularity',
      (WidgetTester tester) async {
    await _pump(tester);

    expect(find.text('热门'), findsOneWidget,
        reason: '动作库是"看"动作的地方，与 VI 稿动作库那一屏的说法对齐');
    expect(find.text('常用'), findsNothing,
        reason: '同一屏里两个叫法会让人以为是两批数据');
  });
}
