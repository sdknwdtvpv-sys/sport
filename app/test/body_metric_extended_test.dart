/// 身体数据扩展（腰围 / 肌肉量 / BMI）的界面与迁移契约（v1.52）。
///
/// 这一版**动了既有表**（`body_metric` 加两列、`user_profile` 加身高），
/// 而且这些字段属**敏感个人信息** —— 所以测试要盯着两件事：
///   ① 老库升上来不崩、新列可用（迁移那条在 migration_test 里，这里测录入与展示）；
///   ② **没填的数不许编**：腰围空着就空着，身高没填就不显示 BMI。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/data/body_metric_repository.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/features/body/body_metric_screen.dart';

Future<void> _pump(
  WidgetTester tester,
  BodyMetricRepository repo,
  ProfileRepository profile,
) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // 先过"敏感信息单独同意"那道门
  await profile.setBodyMetricConsent(nowMs: 1);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: BodyMetricScreen(repository: repo, profile: profile, unit: BodyWeightUnit.kg),
  ));
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late BodyMetricRepository repo;
  late ProfileRepository profile;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = BodyMetricRepository(db);
    profile = ProfileRepository(db);
  });
  tearDown(() => db.close());

  test('仓库层：腰围与肌肉量存得下、读得回，且**没填就是 null**（不是 0）', () async {
    await repo.save(date: '2026-10-05', weightKg: 72.5, waistCm: 82, muscleMassKg: 34.2);
    final BodyMetricData row = (await repo.forDate('2026-10-05'))!;
    expect(row.waistCm, 82);
    expect(row.muscleMassKg, 34.2);

    await repo.save(date: '2026-10-06');
    final BodyMetricData blank = (await repo.forDate('2026-10-06'))!;
    expect(blank.waistCm, isNull);
    expect(blank.muscleMassKg, isNull);
  });

  test('身高存在 profile 里（不是每日指标），存取一致', () async {
    expect(await profile.heightCm(), isNull, reason: '没填过就是 null');
    await profile.setHeightCm(175);
    expect(await profile.heightCm(), 175);
    // 存身高不能把别的设置抹掉（drift 整行 upsert 的老坑）
    await profile.setPrivacyConsent(nowMs: 1);
    await profile.setHeightCm(176);
    expect(await profile.privacyConsentAtMs(), isNotNull, reason: '同意状态被抹掉了');
    expect(await profile.heightCm(), 176);
  });

  testWidgets('表单里有腰围 / 肌肉量 / 身高三个输入框', (WidgetTester tester) async {
    await _pump(tester, repo, profile);
    expect(find.byKey(const Key('body-waist')), findsOneWidget);
    expect(find.byKey(const Key('body-muscle')), findsOneWidget);
    expect(find.byKey(const Key('body-height')), findsOneWidget);
  });

  testWidgets('录入之后摘要块出现，BMI 算得出来（体重+身高都填了）',
      (WidgetTester tester) async {
    await _pump(tester, repo, profile);
    await tester.enterText(find.byKey(const Key('body-weight')), '70');
    await tester.enterText(find.byKey(const Key('body-height')), '175');
    await tester.enterText(find.byKey(const Key('body-waist')), '82');
    await tester.enterText(find.byKey(const Key('body-muscle')), '34');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('body-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('body-summary')), findsOneWidget);
    expect(find.byKey(const Key('body-tile-BMI')), findsOneWidget);
    expect(find.textContaining('22.9'), findsWidgets, reason: '70 / 1.75² = 22.86');
    expect(find.byKey(const Key('body-tile-腰围')), findsOneWidget);
    expect(find.byKey(const Key('body-tile-肌肉量')), findsOneWidget);
    expect(await profile.heightCm(), 175);
  });

  testWidgets('**不填身高就不显示 BMI 分数**（只提示"填上身高就能算"）',
      (WidgetTester tester) async {
    await _pump(tester, repo, profile);
    await tester.enterText(find.byKey(const Key('body-weight')), '70');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('body-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('body-summary')), findsOneWidget);
    final Text hint = tester.widget<Text>(find.byKey(const Key('body-bmi-hint')));
    expect(hint.data, contains('身高'));
    expect(hint.data, isNot(contains('·')), reason: '没有 BMI 就不该有"22.9 · 正常"那种句子');
  });

  testWidgets('没记过的项不摆格子（空格子会让人以为"记过但丢了"）',
      (WidgetTester tester) async {
    await _pump(tester, repo, profile);
    await tester.enterText(find.byKey(const Key('body-weight')), '70');
    await tester.enterText(find.byKey(const Key('body-height')), '175');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('body-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('body-tile-BMI')), findsOneWidget);
    expect(find.byKey(const Key('body-tile-腰围')), findsNothing);
    expect(find.byKey(const Key('body-tile-肌肉量')), findsNothing);
    expect(find.byKey(const Key('body-tile-体脂率')), findsNothing);
  });

  // ── 趋势（v1.52）────────────────────────────────────────────────────
  //
  // 纯计算那半边在 `test/body_trend_test.dart`；这里只守"什么时候出现、出现的是谁"。

  testWidgets('只记过一天 → **不出现趋势卡**（一个点连不成线，画出来是假的）',
      (WidgetTester tester) async {
    await repo.save(date: '2026-09-28', weightKg: 72, nowMs: 1);
    await _pump(tester, repo, profile);

    expect(find.byKey(const Key('body-trend')), findsNothing,
        reason: '两次以下画不出趋势，宁可不出现');
  });

  testWidgets('记到两次以上 → 出趋势卡，切换器只列画得出的指标，图与首尾差都在',
      (WidgetTester tester) async {
    await repo.save(date: '2026-09-26', weightKg: 73, waistCm: 81, nowMs: 1);
    await repo.save(date: '2026-09-27', weightKg: 72.5, nowMs: 2);
    await repo.save(date: '2026-09-28', weightKg: 72, nowMs: 3);
    await _pump(tester, repo, profile);

    expect(find.byKey(const Key('body-trend')), findsOneWidget);
    expect(find.byKey(const Key('body-trend-chart')), findsOneWidget);

    // 腰围只记过一次 —— 切换器里不该有它（列了就是"点了没反应"的假入口）
    expect(find.text('体重'), findsWidgets);
    expect(
      tester.widget<Text>(find.byKey(const Key('body-trend-delta'))).data,
      '-1.0 kg',
      reason: '73 → 72 是掉了 1 kg，方向与单位都要对',
    );
    expect(find.byKey(const Key('body-trend-hint')), findsOneWidget);
  });
}
