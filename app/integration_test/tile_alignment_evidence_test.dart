/// 练了么 · **两类列表行对齐的证据图**（VI 计划 T1-8）
///
/// 这一条改的是"列表行的内边距由主题一处说了算"（`theme.dart` 的 `listTileTheme`），
/// 它影响的是**几何**，而几何只能靠图看。所以要拍两张：
///   * ① 「数据与备份」—— `ListTile` 的行；
///   * ② 「全部数据 → 全部记录」—— 自绘的行。
///
/// 两张图回主机之后并排拼成 `docs/images/plan-vi-2026-10-10/m1-tile-alignment.png`。
/// 真正的判据是 `app/test/tile_alignment_test.dart` 里的 `dx` 相等，
/// 这张图是给人看的第二道（量出来的数是 40，两张图量像素也应落在同一点）。
///
/// ⚠️ 两屏都**直接 pump**（不 `app.main()`）：因为这里要的是一份固定的训练记录，
/// 落在真机 DB 里就要先清库、下次再拍又不一样。内存库 + `evidenceSets()` 才是可复现的。
/// 这一段照 `part2_evidence_test.dart` 的写法（`rootBundle` 读种子，不是 `File`）。
///
/// 跑法（模拟器或真机都行）：
///   flutter drive --driver=test_driver/screenshot_driver.dart \
///     --target=integration_test/tile_alignment_evidence_test.dart -d <设备 id>
/// 产物走 `SHOT_DIR`，这一套用**临时目录**（回主机再拼图）：
///   SHOT_DIR=../docs/images/plan-vi-2026-10-10/raw
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
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/profile/settings_home_screen.dart';
import 'package:lianleme/features/progress/all_data_screen.dart';

import 'evidence_sets.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('列表行对齐证据：数据与备份（ListTile） + 全部记录（自绘行）',
      (WidgetTester tester) async {
    Future<void> settle([int ms = 1200]) async {
      await tester.pump(const Duration(milliseconds: 120));
      for (int i = 0; i < ms ~/ 120; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    Future<void> capture(String name) async {
      await binding.takeScreenshot(name).timeout(const Duration(seconds: 15));
      debugPrint('LIANLEME-TILE-SHOT $name');
    }

    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    try {
      final DriftLocalStore store = DriftLocalStore(db);
      for (final SetRecord r in evidenceSets()) {
        await store.saveSet(r);
      }
      final ExerciseRepository repo = ExerciseRepository(db);
      await repo.importSeed(
        loadJson: () => rootBundle.loadString('assets/exercises.json'),
      );
      final ProfileRepository profile = ProfileRepository(db);

      await binding.convertFlutterSurfaceToImage();

      // ① ListTile 的行：设置页 → 数据与备份（走用户真实路径的两个 tap）
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: Scaffold(
          body: SettingsHomeScreen(
              store: store, repository: repo, profile: profile),
        ),
      ));
      await settle(1600);
      // 设置页：行高从 56/72 收到 52/68 的**风险屏**（文案最长的几行都在这儿）——
      // 方案里 T1-8 的风险写着"真机过一遍设置页与数据工具页"，这一张就是那一眼。
      await capture('m1-tile-align-0-settings');
      await tester.tap(find.byKey(const Key('open-data-tools')));
      await settle(1600);
      expect(find.byKey(const Key('export-csv')), findsOneWidget,
          reason: '没进到「数据与备份」—— 这张图就不成立');
      await capture('m1-tile-align-1-data-tools');

      // ② 自绘的行：全部数据（内存库里那 6 周记录）
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: AllDataScreen(
          store: store,
          repository: repo,
          unit: WeightUnit.kg,
          now: DateTime(2026, 9, 28, 10),
        ),
      ));
      await settle(2000);
      await tester.dragUntilVisible(
        find.text('全部记录'),
        find.byType(ListView).first,
        const Offset(0, -220),
      );
      await settle(900);
      expect(find.text('全部记录'), findsOneWidget,
          reason: '没滚到「全部记录」那一区 —— 这张图就不成立');
      await capture('m1-tile-align-2-all-data');

      debugPrint('LIANLEME-TILE-DONE');
    } finally {
      await db.close();
    }
  });
}
