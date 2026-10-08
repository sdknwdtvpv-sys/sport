/// 练了么 · S12 身体数据测试
///
/// 两块：仓库层的「一天一条」语义，和页面层的录入行为。
/// 「一天一条」是这一项最容易做错的地方 —— 做成"每次新增"的话，
/// 用户补录同一天就会得到两条记录，而界面上只显示一条，另一条静默存在。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/data/body_metric_repository.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/features/body/body_metric_screen.dart';

import 'legacy_db.dart';

void main() {
  late AppDatabase db;
  late BodyMetricRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = BodyMetricRepository(db);
  });

  tearDown(() => db.close());

  group('dayKey', () {
    test('补零到 YYYY-MM-DD', () {
      expect(dayKey(DateTime(2026, 9, 28)), '2026-09-28');
      expect(dayKey(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('用日历日期而不是时间戳（23:50 和次日 00:10 是两天，这是对的）', () {
      expect(dayKey(DateTime(2026, 9, 28, 23, 50)),
          isNot(dayKey(DateTime(2026, 9, 29, 0, 10))));
    });
  });

  group('仓库：一天一条', () {
    test('同一天存两次是改那一条，不是新增', () async {
      await repo.save(date: '2026-09-28', weightKg: 72.5, nowMs: 1000);
      await repo.save(date: '2026-09-28', weightKg: 73.0, nowMs: 2000);

      expect(await repo.count(), 1, reason: '不能变成两条');

      final BodyMetricData? row = await repo.forDate('2026-09-28');
      expect(row!.weightKg, 73.0, reason: '取后写的那次');
      expect(row.updatedAt, 2000);
    });

    test('不同日期各存一条', () async {
      await repo.save(date: '2026-09-27', weightKg: 72.5, nowMs: 1000);
      await repo.save(date: '2026-09-28', weightKg: 73.0, nowMs: 2000);

      expect(await repo.count(), 2);
      expect((await repo.latest())!.date, '2026-09-28', reason: 'latest 取日期最大的');
    });

    test('软删除之后重新录同一天会复活那一条，不产生第二条', () async {
      final BodyMetricData first =
          await repo.save(date: '2026-09-28', weightKg: 72.5, nowMs: 1000);

      await repo.delete(first.id, nowMs: 2000);
      expect(await repo.count(), 0, reason: '删掉之后就不算有效记录');
      expect(await repo.latest(), isNull);

      // 用户改主意了，重新录同一天
      await repo.save(date: '2026-09-28', weightKg: 71.8, nowMs: 3000);

      expect(await repo.count(), 1, reason: '必须是复活，不是新增');
      expect((await repo.forDate('2026-09-28'))!.id, first.id,
          reason: 'id 沿用原来的');
      expect((await repo.latest())!.weightKg, 71.8);
    });

    test('最这一条被删掉后 latest 回退到上一条有效的', () async {
      final BodyMetricData older =
          await repo.save(date: '2026-09-27', weightKg: 72.0, nowMs: 1000);
      final BodyMetricData newer =
          await repo.save(date: '2026-09-28', weightKg: 73.0, nowMs: 2000);
      expect((await repo.latest())!.id, newer.id);

      await repo.delete(newer.id, nowMs: 3000);
      expect((await repo.latest())!.id, older.id);
    });

    test('recent 按日期降序，且不含软删除的', () async {
      await repo.save(date: '2026-09-26', weightKg: 71.0, nowMs: 1000);
      final BodyMetricData mid =
          await repo.save(date: '2026-09-27', weightKg: 72.0, nowMs: 2000);
      await repo.save(date: '2026-09-28', weightKg: 73.0, nowMs: 3000);
      await repo.delete(mid.id, nowMs: 4000);

      final List<BodyMetricData> rows = await repo.recent();
      expect(rows.map((BodyMetricData r) => r.date).toList(),
          <String>['2026-09-28', '2026-09-26']);
    });

    test('只记体脂不记体重也能存（体重列可空）', () async {
      await repo.save(date: '2026-09-28', bodyFatPct: 18.5, nowMs: 1000);

      final BodyMetricData row = (await repo.forDate('2026-09-28'))!;
      expect(row.weightKg, isNull);
      expect(row.bodyFatPct, 18.5);
    });
  });

  group('v1 → v2 迁移（手机上装的是 v1，这步坏了老用户一开就崩）', () {
    test('用 v2 代码打开一个 v1 的库：不崩，且新表可用', () async {
      // 模拟老库：user_version = 1，只有当年那张 exercise 表（没有 body_metric）
      final AppDatabase legacy = AppDatabase(
        NativeDatabase.memory(setup: (dynamic raw) => legacySetup(raw, version: 1)),
      );

      // 打开即触发 onUpgrade。没有 onUpgrade 的话 drift 会直接抛
      // "the schema version changed" 之类的异常，老用户就卡在启动页了。
      final int count = await BodyMetricRepository(legacy).count();
      expect(count, 0, reason: '升级后新表存在且为空');

      // 而且真的能用
      final BodyMetricRepository repo2 = BodyMetricRepository(legacy);
      await repo2.save(date: '2026-09-28', weightKg: 72.5, nowMs: 1);
      expect((await repo2.latest())!.weightKg, 72.5);

      await legacy.close();
    });
  });

  group('S12 页面', () {
    /// 固定"今天"，否则测试会在月初/月末飘
    DateTime fixedNow() => DateTime(2026, 9, 28, 9);

    Future<void> pump(WidgetTester tester,
        {BodyWeightUnit unit = BodyWeightUnit.kg,
        ProfileRepository? profile,
        ValueChanged<BodyWeightUnit>? onUnitChanged}) async {
      // v1.52 这一页长高了一截（顶部摘要卡 + 腰围/肌肉量/身高三个输入框）。
      // 默认 800×600 的测试视口里，靠下的「备注」不会被懒构建的 ListView 建出来，
      // `find.byKey(Key('body-note'))` 于是**找不到**（`Bad state: No element`）——
      // 那不是页面错了，是视口比手机小。这里统一放大到接近真机的逻辑尺寸
      // （400×1200，约等于一台 1080×3240 的机器），组件行为不变。
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      // v1.31.0 起这一页先过**敏感个人信息单独同意**（PIPL 第 29 条）。
      // 本文件测的是单位切换与展示，不测那道门（那道门由 test/body_consent_test.dart 覆盖），
      // 所以传了 profile 就先替用户同意掉 —— 免得每个用例都要写一遍。
      if (profile != null) await profile.setBodyMetricConsent(nowMs: 1);
      await tester.pumpWidget(MaterialApp(
        home: BodyMetricScreen(
          repository: repo,
          clock: fixedNow,
          unit: unit,
          profile: profile,
          onUnitChanged: onUnitChanged,
        ),
      ));
      await tester.pumpAndSettle();
    }

    String weightFieldText(WidgetTester tester) => tester
        .widget<TextField>(find.byKey(const Key('body-weight')))
        .controller!
        .text;

    testWidgets('★ 一周内称第二次 → 友情提醒"一周两次就够"（10.8 清单第 1/4 条）',
        (WidgetTester tester) async {
      // 用户原话：「每天称体重意义不大，如果用户在一周内更新体重两次，弹出友情提醒」
      // + 「按照上面讲的，不建议每天称体重」。
      // 判据：最近 7 天里（含这一次）已经有 ≥ 2 条带体重的记录 → 说一声。
      final DateTime now = fixedNow();
      // 三天前已经称过一次（带上 profile 才会走同意门那套；这里不需要）
      await repo.save(
        date: dayKey(now.subtract(const Duration(days: 3))),
        weightKg: 87.2,
        nowMs: 1000,
      );
      await pump(tester);
      await tester.enterText(find.byKey(const Key('body-weight')), '86.5');
      await tester.pump();
      await tester.tap(find.byKey(const Key('body-save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('weigh-frequency-note')), findsOneWidget,
          reason: '一周里的第二次称重该提醒一句');
      expect(find.textContaining('一周称两次就够'), findsOneWidget);
      // 点掉就走（不拦保存、不改数据）
      await tester.tap(find.byKey(const Key('weigh-frequency-ok')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('weigh-frequency-note')), findsNothing);
      expect(await repo.forDate(dayKey(now)), isNotNull, reason: '这一条照样存进去了');
    });

    testWidgets('★ 一周里只称一次 → 不打扰', (WidgetTester tester) async {
      await pump(tester);
      await tester.enterText(find.byKey(const Key('body-weight')), '86.5');
      await tester.pump();
      await tester.tap(find.byKey(const Key('body-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('weigh-frequency-note')), findsNothing,
          reason: '第一次称重不该被说教');
    });

    testWidgets('单位开关在**本页**，切换后数字实时变（85.5 → 171）',
        (WidgetTester tester) async {
      // 用户的要求："体重的单位切换只能在身体数据里边出现，实时切换、实时数据变动"。
      // 称体重的时候才想起来要按斤看，那时不该退出去到「我」页翻设置。
      await pump(tester);

      await tester.enterText(find.byKey(const Key('body-weight')), '85.5');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('body-unit-jin')));
      await tester.pumpAndSettle();

      // 数字本身跟着换单位：85.5 kg → 171 斤（**不是**留着 85.5 让人以为体重变了）
      expect(weightFieldText(tester), '171');
      expect(find.textContaining('斤'), findsWidgets);

      // 切回来也换回去
      await tester.tap(find.byKey(const Key('body-unit-kg')));
      await tester.pumpAndSettle();
      expect(weightFieldText(tester), '85.5');
    });

    testWidgets('切换会落库并通知上层（否则「进步」页那张卡还按旧单位念）',
        (WidgetTester tester) async {
      late BodyWeightUnit notified;
      await pump(tester,
          profile: ProfileRepository(db),
          onUnitChanged: (BodyWeightUnit u) => notified = u);

      await tester.tap(find.byKey(const Key('body-unit-jin')));
      await tester.pumpAndSettle();

      expect(notified, BodyWeightUnit.jin);
      expect(await ProfileRepository(db).bodyWeightUnit(), BodyWeightUnit.jin);
    });

    testWidgets('输入框空着时切单位不猜（宁可不填，也不凭空造一个数）',
        (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(find.byKey(const Key('body-unit-jin')));
      await tester.pumpAndSettle();

      expect(weightFieldText(tester), '');
    });

    testWidgets('体重单位是斤时：输入按斤、存库存 kg、标签也写斤',
        (WidgetTester tester) async {
      // 用户的要求："体重钉死在千克和斤之间切换"。1 斤 = 500 g。
      await pump(tester, unit: BodyWeightUnit.jin);

      // 标签本身就是一行"体重 + 单位开关"（单位只在**本页**切）
      expect(find.text('体重'), findsOneWidget);
      expect(find.byKey(const Key('body-unit-jin')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('body-weight')), '171');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('body-save')));
      await tester.pumpAndSettle();

      final BodyMetricData row = (await repo.forDate('2026-09-28'))!;
      expect(row.weightKg, 85.5, reason: '171 斤 = 85.5 kg（存储永远 kg）');

      // 最近记录那一行也按斤念。v1.52 起这一页顶部还有一张摘要卡，
      // 它同样按当前单位念，所以「171 斤」会**出现两次**：摘要卡一处 + 最近记录一处。
      // 光数次数没意义，要分别认：少一处就说明有一边还在念 kg。
      expect(
        tester.widget<Text>(find.byKey(const Key('body-summary-weight'))).data,
        '171 斤',
        reason: '摘要卡要跟着单位走',
      );
      expect(find.text('171 斤'), findsNWidgets(2),
          reason: '摘要卡一处 + 最近记录一处');
    });

    testWidgets('斤的上限按斤算（800 斤 = 400 kg），别把 500 斤当合法',
        (WidgetTester tester) async {
      await pump(tester, unit: BodyWeightUnit.jin);
      final Finder save = find.byKey(const Key('body-save'));

      await tester.enterText(find.byKey(const Key('body-weight')), '900');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(save).onPressed, isNull,
          reason: '900 斤 = 450 kg，超出上限');

      await tester.enterText(find.byKey(const Key('body-weight')), '170');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    });

    testWidgets('补录时把已有值按**当前单位**填回来（不是把 kg 塞进斤的框）',
        (WidgetTester tester) async {
      await repo.save(date: '2026-09-28', weightKg: 85.5, nowMs: 1);

      await pump(tester, unit: BodyWeightUnit.jin);

      final TextField field =
          tester.widget<TextField>(find.byKey(const Key('body-weight')));
      expect(field.controller!.text, '171', reason: '85.5 kg 在斤模式下是 171');
    });

    testWidgets('没填有效体重时保存按钮不可用', (WidgetTester tester) async {
      await pump(tester);

      final Finder save = find.byKey(const Key('body-save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await tester.enterText(find.byKey(const Key('body-weight')), 'abc');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(save).onPressed, isNull,
          reason: '非数字不算填了');

      // 明显不合理的值也不接受，避免把 720kg 存进去
      await tester.enterText(find.byKey(const Key('body-weight')), '720');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await tester.enterText(find.byKey(const Key('body-weight')), '72.5');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    });

    testWidgets('填体重 + 备注 → 保存 → 落库', (WidgetTester tester) async {
      await pump(tester);

      await tester.enterText(find.byKey(const Key('body-weight')), '72.5');
      await tester.enterText(find.byKey(const Key('body-note')), '空腹');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('body-save')));
      await tester.pumpAndSettle();

      final BodyMetricData row = (await repo.forDate('2026-09-28'))!;
      expect(row.weightKg, 72.5);
      expect(row.note, '空腹');
      expect(await repo.count(), 1);
    });

    testWidgets('切到已记录的那天会把已有值填回来（补录是"改"不是"重填"）',
        (WidgetTester tester) async {
      await repo.save(date: '2026-09-26', weightKg: 71.2, note: '练后', nowMs: 1);
      await pump(tester);

      // 今天还没记过，输入框应该是空的
      expect(
        tester.widget<TextField>(find.byKey(const Key('body-weight'))).controller!.text,
        '',
      );

      await tester.tap(find.byKey(const Key('body-day-2026-09-26')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byKey(const Key('body-weight'))).controller!.text,
        '71.2',
      );
      expect(
        tester.widget<TextField>(find.byKey(const Key('body-note'))).controller!.text,
        '练后',
      );
    });

    testWidgets('补录同一天不会产生两条', (WidgetTester tester) async {
      await pump(tester);

      await tester.enterText(find.byKey(const Key('body-weight')), '72.5');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('body-save')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('body-weight')), '73.1');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('body-save')));
      await tester.pumpAndSettle();

      expect(await repo.count(), 1);
      expect((await repo.forDate('2026-09-28'))!.weightKg, 73.1);
    });

    testWidgets('日期 chips 里有「今天」', (WidgetTester tester) async {
      await pump(tester);
      expect(find.text('今天'), findsOneWidget);
    });
  });
}
