/// 练了么 · **徽章重设计那批的证据图**（A2 离你最近的一枚 / A5 段位）
///
/// 与 `v152_evidence_test.dart` 同一个定位：**不是商店素材，是验证证据**，
/// 产物进 `docs/images/`（那一目录不参与 `tool/check-screenshots.mjs` 的核对），
/// 命名统一 `badge-20261006-*`。
///
/// **为什么不去驱动真机的真实库**（这是本轮唯一值得解释的取舍）：
/// A2/A5 要看的恰恰是"**练到一半**"的状态 —— 顶部那块"离你最近的一枚"要有进度可画、
/// 段位条要有"还差 N 枚"。真机那份库里的数据不由我控制（清一次库就得重新攒），
/// 而 `docs/images/memo-20261006-*.png` 那批的教训是"图里是什么，取决于设备当时的状态"。
/// 所以这里**自带一份固定的训练记录**，在内存库里建好，再把**真身那一屏**（同一个
/// `AchievementsScreen`、同一个主题、同一份 `AppTheme`）画出来截图。
/// 图里的每一个数字都能在这份记录上复算出来。
///
/// 跑法（在 `app/` 下，iOS 模拟器 `lianleme-69`）：
///     SHOT_DIR=../docs/images flutter drive \
///       --driver=test_driver/screenshot_driver.dart \
///       --target=integration_test/badge_redesign_evidence_test.dart -d <UDID>
///
/// ⚠️ iOS 模拟器截出来的 PNG 是 **16 位 RGBA**；证据图不要求压平（那不是商店那两套），
/// 但如果要让它在 `docs/` 里小一点，可以顺手过一遍 `node tool/flatten-png.mjs`。
/// 判据是最后那行 `LIANLEME-EVIDENCE-SUMMARY`：**失败 0 步**才算过。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/progress/achievements_screen.dart';

import 'evidence_sets.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final List<String> shot = <String>[];
  final List<String> failed = <String>[];

  testWidgets('A2 / A5 证据图（徽章重设计）', (WidgetTester tester) async {
    /// 推进固定时长（不用 `pumpAndSettle`：App 里有常驻计时器，永远静止不了）。
    Future<void> settle([int ms = 1200]) async {
      final DateTime end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    Future<void> capture(String name) async {
      try {
        await binding.takeScreenshot(name).timeout(const Duration(seconds: 15));
        shot.add(name);
        debugPrint('LIANLEME-EVIDENCE $name');
      } catch (e) {
        failed.add('$name: $e');
        debugPrint('LIANLEME-EVIDENCE-FAIL $name — $e');
      }
    }

    final List<SetRecord> sets = evidenceSets();

    // ── A2「离你最近的一枚」（成就页顶部）──────────────────────────────
    try {
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: AchievementsScreen(sets: sets),
      ));
      await settle(1600);
      expect(find.byKey(const Key('nearest-badge')), findsOneWidget,
          reason: 'A2 那块卡没画出来 —— 这张图就没有意义了');
      await capture('badge-20261006-a2-nearest');
      // 再把「探索发现」那一段展开再拍一张：一张图里同时留下"分区怎么排 + 折叠按钮"
      // 与 A4 的隐藏徽章（它们在这个分区的末尾，条件写着"？？？"）
      //
      // ⚠️ 这一屏是 ListView（**懒构建**）：折叠按钮在第一屏之下，不滚过去它根本不存在 ——
      // 第一次跑就栽在这儿（`ensureVisible` 对"还没建出来"的 widget 无能为力，
      // 报的是"一个都没找到"）。老规矩：`dragUntilVisible`。
      final Finder toggle = find.byKey(const Key('badge-section-toggle-explore'));
      await tester.dragUntilVisible(
          toggle, find.byType(ListView), const Offset(0, -260));
      await settle(700);
      await tester.tap(toggle);
      await settle(900);
      await tester.dragUntilVisible(
          toggle, find.byType(ListView), const Offset(0, -260));
      await settle(700);
      await capture('badge-20261006-a4-collapse');
    } catch (e) {
      failed.add('a2: $e');
      debugPrint('LIANLEME-EVIDENCE-STEP-FAIL a2 — $e');
    }

    // ── A5 段位（2026-10-10 起在**成就页**，不再在「我」页）──────────────
    //
    // ⚠️ 这一张原来拍的是「我」页那张三行进度卡的第二行（`rank-card`）。
    // 用户 10.10 的设计评审之后「我」只留一条进度（等级），段位（本来就是
    // "按已解锁枚数分档"）搬进了成就页 —— 所以这一张改成在成就页上拍，
    // 抓的仍然是同一行数字（`rank-name` / `rank-next`）。
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    try {
      final DriftLocalStore store = DriftLocalStore(db);
      for (final SetRecord r in sets) {
        await store.saveSet(r);
      }
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: AchievementsScreen(sets: sets),
      ));
      await settle(2000);
      expect(find.byKey(const Key('rank-name')), findsOneWidget,
          reason: '段位那一行没画出来 —— 这张图就没有意义了');
      debugPrint('LIANLEME-EVIDENCE-RANK '
          '${tester.widget<Text>(find.byKey(const Key('rank-name'))).data} / '
          '${tester.widget<Text>(find.byKey(const Key('rank-next'))).data}');
      await capture('badge-20261006-a5-rank');
    } catch (e) {
      failed.add('a5: $e');
      debugPrint('LIANLEME-EVIDENCE-STEP-FAIL a5 — $e');
    } finally {
      await db.close();
    }

    debugPrint('LIANLEME-EVIDENCE-SUMMARY 成功 ${shot.length} 张（${shot.join(',')}）'
        ' · 失败 ${failed.length} 步 ${failed.isEmpty ? '' : ':: ${failed.join(' | ')}'}');
  });
}
