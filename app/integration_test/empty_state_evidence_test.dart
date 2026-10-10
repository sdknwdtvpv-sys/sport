/// 练了么 · **六处空态的证据图**（VI 计划 T3-2）
///
/// 这一条改的是"空态"这件事本身：16 处空态原来**全部**是"一到两行灰字、无图形、无按钮"。
/// 证据要拍的就是计划里点名的那六处 —— **每处都得看得见图形与那个下一步按钮**：
///   01 首页（一次都没练过）／02 进步页（还没有训练记录）／03 全部数据页（这个动作还没有记录）
///   04 动作库（搜不到）／05 通知中心（还没有消息）／06 计划页（还没有练过）
///
/// ⚠️ 六屏都**直接 pump**（不 `app.main()`）：空态只有在"真的空"的库里才出现，
/// 而真机上那份库迟早会被用脏。内存库 + 固定种子 = 每次出的图一模一样。
///
/// 跑法：
///   SHOT_DIR=../docs/images/plan-vi-2026-10-10/raw flutter drive \
///     --driver=test_driver/screenshot_driver.dart \
///     --target=integration_test/empty_state_evidence_test.dart -d <设备 id>
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/data/db.dart' hide SetRecord, Workout, Exercise, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/notification_repository.dart';
import 'package:lianleme/data/routine_repository.dart';
import 'package:lianleme/features/exercise/exercise_picker_screen.dart';
import 'package:lianleme/features/notifications/notification_center_screen.dart';
import 'package:lianleme/features/progress/all_data_screen.dart';
import 'package:lianleme/features/progress/progress_screen.dart';
import 'package:lianleme/features/routine/plan_screen.dart';
import 'package:lianleme/features/today/today_screen.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('六处空态：每处都有图形 + 一个下一步按钮', (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    try {
      final DriftLocalStore store = DriftLocalStore(db);
      final ExerciseRepository repo = ExerciseRepository(db);
      await repo.importSeed(
        loadJson: () => rootBundle.loadString('assets/exercises.json'),
      );

      Future<void> pumpScreen(Widget home) async {
        // ⚠️ 必须**自己套一层 `Scaffold` 并给底色**：这几屏自己不是 Scaffold，
        // 而 `MaterialApp` 的 home 不会替你铺背景 —— 第一版就是白底浅字
        // （主题里的 `scaffoldBackgroundColor` 没地方生效）。证据图自己也会骗人。
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: Scaffold(backgroundColor: Tokens.bg, body: home),
        ));
        for (int i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 120));
        }
      }

      Future<void> capture(String name) async {
        // 每一屏都得**真的有那颗按钮**才值得拍（图是给人看的，判据在测试里）
        expect(find.byKey(const Key('empty-action')), findsOneWidget,
            reason: '$name 这一屏没有下一步按钮 —— 拍出来就是错的');
        await binding.takeScreenshot(name).timeout(const Duration(seconds: 15));
        debugPrint('LIANLEME-EMPTY-SHOT $name');
      }

      await binding.convertFlutterSurfaceToImage();

      // ── 01 首页：一次都没练过 ────────────────────────────────────────
      await pumpScreen(TodayScreen(
        onStart: () {},
        onOpenLibrary: () {},
        recent: const <({String workoutId, DateTime day, int exercises, int sets, double volume})>[],
      ));
      await capture('m3-empty-01-today');

      // ── 02 进步页：还没有训练记录 ────────────────────────────────────
      await pumpScreen(ProgressScreen(
        store: store,
        repository: repo,
        onOpenToday: () {},
        now: DateTime(2026, 10, 10),
      ));
      await capture('m3-empty-02-progress');

      // ── 03 全部数据页：这个动作还没有记录（先滚到空态那一块）─────────
      await pumpScreen(AllDataScreen(
        store: store,
        repository: repo,
        unit: WeightUnit.kg,
        now: DateTime(2026, 10, 10),
      ));
      await tester.dragUntilVisible(
        find.byKey(const Key('empty-all-data')),
        find.byType(ListView).first,
        const Offset(0, -220),
      );
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      await capture('m3-empty-03-all-data');

      // ── 04 动作库：搜不到 ────────────────────────────────────────────
      await pumpScreen(ExercisePickerScreen(repository: repo));
      await tester.enterText(find.byType(TextField).first, 'zzzz没有这个动作');
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      await capture('m3-empty-04-picker');

      // ── 05 通知中心：还没有消息 ──────────────────────────────────────
      await pumpScreen(NotificationCenterScreen(repository: NotificationRepository(db)));
      await capture('m3-empty-05-notifications');

      // ── 06 计划页：还没有练过（切到「历史」那一段）────────────────────
      await pumpScreen(PlanScreen(
        repository: RoutineRepository(db),
        exercises: repo,
        store: store,
        onBack: () {},
        now: DateTime(2026, 10, 10),
      ));
      // ⚠️ 不用 `tester.tap(Key('seg-历史'))`：iOS 上那个分段控件是**苹果原生的**
      // `UISegmentedControl`（平台视图），Flutter 侧点不到它 —— 走外壳交出来的那个钩子
      // （语义一致：都是"用户点了历史那一段"）。
      debugPlanSegment?.call(2);
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      await capture('m3-empty-06-plan-history');

      debugPrint('LIANLEME-EMPTY-DONE');
    } finally {
      await db.close();
    }
  });
}
