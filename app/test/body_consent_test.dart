/// 练了么 · 身体数据的**单独同意**（PIPL 第 29 条，敏感个人信息）
///
/// **为什么必须有这一条**：`docs/tech-decisions.md` 的合规第 2 条自己写着
/// 「健康数据属敏感个人信息，**单独同意**」—— 而体重就是健康数据。
/// 首次启动那道同意门征求的是**政策总同意**，法律上**不等于**单独同意。
/// 所以「身体数据」这一页在第一次进入时单独问一次、单独落库（schema v14）。
///
/// 这一组守三件事：
///   1. 没单独同意过 → 进这一页先弹说明，**不读也不写**；
///   2. 点「先不用」→ 退出这一页，库里没有同意记录、也没有任何体重数据；
///   3. 同意之后 → 同意时刻落库、说明不再出现、页面正常可用；
///   4. 老库（v13）升上来是 null —— 老用户也会被问一次（他们当初同意的是政策）。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/data/body_metric_repository.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/features/body/body_metric_screen.dart';

import 'legacy_db.dart';

void main() {
  group('页面上的单独同意', () {
    late AppDatabase db;
    late BodyMetricRepository repo;
    late ProfileRepository profile;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = BodyMetricRepository(db);
      profile = ProfileRepository(db);
    });
    tearDown(() => db.close());

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: BodyMetricScreen(
          repository: repo,
          profile: profile,
          clock: () => DateTime(2026, 9, 28, 9),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('没单独同意过：先弹说明，且拒绝之前不写任何东西',
        (WidgetTester tester) async {
      await pump(tester);

      expect(find.byKey(const Key('body-consent')), findsOneWidget,
          reason: '体重是敏感个人信息，必须单独征求一次同意');
      expect(find.byKey(const Key('body-consent-agree')), findsOneWidget);
      expect(find.byKey(const Key('body-consent-decline')), findsOneWidget);
      expect(await profile.bodyMetricConsentAtMs(), isNull,
          reason: '光弹出说明还不算同意');
      expect(await repo.count(), 0, reason: '还没同意就不该有任何体重数据');

      // 给用户看的字里不许出现 markdown 记号（`Text` 不渲染 markdown，用户会看到星号）。
      // 这条是真机截图抓出来的 —— 单测只看 key，看不见字形。
      final String body =
          tester.widget<Text>(find.byKey(const Key('body-consent'))).data!;
      expect(body.contains('**'), isFalse,
          reason: '弹层正文里出现了 ** —— 那是 markdown 记号，用户会直接看到星号');
      expect(body.contains('敏感个人信息'), isTrue);
    });

    testWidgets('点「先不用」：退出这一页，库里仍然什么都没有',
        (WidgetTester tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('body-consent-decline')));
      await tester.pumpAndSettle();

      expect(await profile.bodyMetricConsentAtMs(), isNull,
          reason: '拒绝不能变成"默认同意"');
      expect(await repo.count(), 0);
      expect(find.byKey(const Key('body-consent')), findsNothing,
          reason: '拒了之后不该反复弹（这一页已经退出去了）');
    });

    testWidgets('同意之后：同意时刻落库、说明不再出现、页面可用',
        (WidgetTester tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('body-consent-agree')));
      await tester.pumpAndSettle();

      expect(await profile.bodyMetricConsentAtMs(), isNotNull,
          reason: '单独同意必须落库，否则每次进来都问一遍');
      expect(find.byKey(const Key('body-consent')), findsNothing);
      expect(find.byKey(const Key('body-weight')), findsOneWidget,
          reason: '同意之后页面要能用');

      // 真的能记一条
      await tester.enterText(find.byKey(const Key('body-weight')), '72.5');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('body-save')));
      await tester.pumpAndSettle();
      expect(await repo.count(), 1);
    });

    testWidgets('已经同意过：不再弹（重启/再进都不该反复问）',
        (WidgetTester tester) async {
      await profile.setBodyMetricConsent(nowMs: 111);
      await pump(tester);

      expect(find.byKey(const Key('body-consent')), findsNothing);
      expect(await profile.bodyMetricConsentAtMs(), 111,
          reason: '不该被覆写');
    });

    testWidgets('同意这件事不碰别的设置（每个 setter 都要原样带回其它字段）',
        (WidgetTester tester) async {
      await profile.setUnit(WeightUnit.lb, nowMs: 1000);
      await profile.setAnalyticsEnabled(true, nowMs: 1000);
      await profile.setPrivacyConsent(nowMs: 1000);

      await profile.setBodyMetricConsent(nowMs: 2000);

      expect(await profile.bodyMetricConsentAtMs(), 2000);
      expect(await profile.unit(), WeightUnit.lb, reason: '单位不能被抹掉');
      expect(await profile.analyticsEnabled(), isTrue, reason: '统计开关不能被抹掉');
      expect(await profile.privacyConsentAtMs(), 1000, reason: '政策总同意不能被抹掉');
    });
  });

  group('迁移', () {
    test('v13 的库升到 v14：多出"身体数据单独同意"列，老库是 null（所以老用户会被问一次）',
        () async {
      final AppDatabase legacy = AppDatabase(
        NativeDatabase.memory(setup: (dynamic raw) {
          legacySetup(raw, version: 13);
          raw.execute(legacySeedProfileSql); // 里面 unit_pref = 'lb'
          raw.execute(legacySeedExerciseSql);
        }),
      );
      // 打开即触发 onUpgrade
      expect(await ProfileRepository(legacy).bodyMetricConsentAtMs(), isNull,
          reason: '老用户当初同意的是政策，不是"处理敏感个人信息"这件事本身 —— '
              '所以这一列必须留空，让他们下次进来时被单独问一次');

      await ProfileRepository(legacy).setBodyMetricConsent(nowMs: 555);
      expect(await ProfileRepository(legacy).bodyMetricConsentAtMs(), 555);
      expect(await ProfileRepository(legacy).unit(), WeightUnit.lb,
          reason: '迁移与写入都不能把已有的设置抹掉');

      final cols = await legacy
          .customSelect("SELECT name FROM pragma_table_info('user_profile')")
          .get();
      expect(cols.map((r) => r.read<String>('name')),
          contains('body_metric_consent_at_ms'));

      await legacy.close();
    });

    test('老库里**没有** body_metric_consent_at_ms —— fixture 本身也要守着', () async {
      // 防"有人把 fixture 改成当前 schema"，那样上面那条迁移测试就变成空转
      late List<String> colsBefore;
      final AppDatabase legacy = AppDatabase(
        NativeDatabase.memory(setup: (dynamic raw) {
          legacySetup(raw, version: 13);
          colsBefore = raw
              .select("SELECT name FROM pragma_table_info('user_profile')")
              .map<String>((row) => row['name'] as String)
              .toList();
        }),
      );
      await ProfileRepository(legacy).bodyMetricConsentAtMs(); // 打开库
      expect(colsBefore, isNot(contains('body_metric_consent_at_ms')),
          reason: 'v13 的老库不该有这一列，否则迁移测试是空转');
      await legacy.close();
    });
  });
}
