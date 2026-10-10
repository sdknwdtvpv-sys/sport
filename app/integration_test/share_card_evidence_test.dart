/// 练了么 · **分享卡的缩略图证据**（VI 计划 T3-3）
///
/// 分享卡的全部职能是**获客**，而它几乎总是被压在朋友圈缩略图（约 200pt 宽）里被看到 ——
/// 所以 T3-3 的判据 3 就是"压到 200pt 宽还认不认得出"。
///
/// ⚠️ 为什么这张图要在**模拟器**上拍、而不是在 `flutter test` 里导出：
/// 单元测试环境**没有中文字形**（文字会渲成一个个方框），而这一条要看的恰恰是汉字。
/// 拍法：把 `ShareCard` 居中铺在一屏上，拍整屏，回主机再按卡片位置裁出来并缩到 200pt 宽
/// （卡面 360×520 居中在 440×956 的屏上 → 裁切框是确定的，不需要找边界）。
///
/// 跑法：
///   SHOT_DIR=/tmp/card flutter drive --driver=test_driver/screenshot_driver.dart \
///     --target=integration_test/share_card_evidence_test.dart -d <设备 id>
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/features/summary/share_card.dart';
import 'package:lianleme/features/summary/workout_summary.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('分享卡（标准版 + 打卡版）', (WidgetTester tester) async {
    final WorkoutSummary s = WorkoutSummary(
      workoutId: 'w1',
      totalSets: 12,
      totalVolumeKg: 5400,
      duration: const Duration(minutes: 52),
      exerciseCount: 4,
      prs: const <SetPr>[
        SetPr(
            exerciseId: 'a',
            exerciseName: '杠铃卧推',
            reps: 5,
            previousBest: 100,
            weightKg: 105),
      ],
      distanceM: 0,
      distanceSets: 0,
      cardiovascularLabels: const <String>[],
      startedAtMs: DateTime(2026, 10, 10, 19, 30).millisecondsSinceEpoch,
      unit: WeightUnit.kg,
    );

    await binding.convertFlutterSurfaceToImage();

    Future<void> shot(String name, Widget card) async {
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: Scaffold(backgroundColor: Tokens.bg, body: Center(child: card)),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      await binding.takeScreenshot(name).timeout(const Duration(seconds: 15));
      debugPrint('LIANLEME-CARD-SHOT $name');
    }

    await shot('m3-share-card-standard', ShareCard(summary: s));
    await shot(
      'm3-share-card-streak',
      ShareCard(
        summary: s,
        variant: ShareCardVariant.streak,
        streak: 23,
        ordinal: 41,
      ),
    );
  });
}
