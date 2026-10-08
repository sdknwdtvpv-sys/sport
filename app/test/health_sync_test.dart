/// 练了么 · 从系统健康库读体成分（`docs/plan-health-sync.md`）
///
/// 这个文件守三件事，每一件都是"错了会出事"的那种：
///   1. **读之前先看那道单独同意** —— 没同意时**桥一次都不能被调用**（PIPL 第 29 条：
///      同意范围到哪，处理就到哪）；
///   2. **合并规则**：我们自己记的字段一个都不许被覆盖，那天只有系统有才新建、且**留痕**；
///   3. **平台桥的降级**：平台没实现时安静地当"没有健康库"，不把异常抛到界面上。
library;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/features/body/body_metric_screen.dart';
import 'package:lianleme/data/body_metric_repository.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/health/health_bridge.dart';
import 'package:lianleme/health/health_sync.dart';

/// 记录"被调用了几次"的假桥 —— 合规那几条断言全靠它。
class FakeHealthBridge implements HealthBridge {
  FakeHealthBridge({
    this.available = true,
    this.permission = true,
    this.samples = const <HealthSample>[],
  });

  bool available;
  bool permission;
  List<HealthSample> samples;

  int availabilityChecks = 0;
  int permissionRequests = 0;
  int reads = 0;
  int lastReadDays = 0;

  @override
  Future<bool> isAvailable() async {
    availabilityChecks++;
    return available;
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permission;
  }

  @override
  Future<List<HealthSample>> readBodyComposition({int days = 180}) async {
    reads++;
    lastReadDays = days;
    return samples;
  }
}

/// 一条样本的时间戳：用**本地时间**造，免得测试在时区边界上翻车。
int atMs(int y, int m, int d, [int hour = 9]) =>
    DateTime(y, m, d, hour).millisecondsSinceEpoch;

void main() {
  late AppDatabase db;
  late BodyMetricRepository body;
  late ProfileRepository profile;
  late FakeHealthBridge bridge;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    body = BodyMetricRepository(db);
    profile = ProfileRepository(db);
    bridge = FakeHealthBridge();
  });

  tearDown(() => db.close());

  // ───────────────────────────────────────────────────────────── 合并规则
  group('按天合并（我们的字段不覆盖）', () {
    test('我们本来没有那天 → 新建一条，并写上来源', () async {
      final HealthMergeReport r = await body.mergeHealthDays(
        <HealthDayValues>[
          const HealthDayValues(date: '2026-10-01', weightKg: 72.5),
        ],
        nowMs: 1000,
      );
      expect(r.created, 1);
      expect(r.touched, 1);

      final BodyMetricData? row = await body.forDate('2026-10-01');
      expect(row!.weightKg, 72.5);
      expect(row.bodyFatPct, isNull,
          reason: '系统没给体脂，就不许编一个出来');
      expect(row.note, kHealthNote,
          reason: '来源必须留痕：用户撤了权限之后，回头看这行字才知道这个数不是自己称的');
    });

    test('那天我们自己记过 → 体重一个字都不动，只补我们缺的体脂', () async {
      await body.save(date: '2026-10-02', weightKg: 80.0, nowMs: 500);
      final HealthMergeReport r = await body.mergeHealthDays(
        <HealthDayValues>[
          const HealthDayValues(
              date: '2026-10-02', weightKg: 72.5, bodyFatPct: 18.0),
        ],
        nowMs: 1000,
      );
      expect(r.created, 0);
      expect(r.filled, 1);

      final BodyMetricData row = (await body.forDate('2026-10-02'))!;
      expect(row.weightKg, 80.0, reason: '我们自己称的 80.0 不许被健康库的 72.5 盖掉');
      expect(row.bodyFatPct, 18.0, reason: '我们缺体脂，这个该补上');
    });

    test('我们两个字段都有 → 一个字不动（计进 unchanged）', () async {
      await body.save(
          date: '2026-10-03', weightKg: 80.0, bodyFatPct: 20.0, nowMs: 500);
      final HealthMergeReport r = await body.mergeHealthDays(
        <HealthDayValues>[
          const HealthDayValues(
              date: '2026-10-03', weightKg: 72.5, bodyFatPct: 18.0),
        ],
        nowMs: 1000,
      );
      expect(r.unchanged, 1);
      expect(r.touched, 0);

      final BodyMetricData row = (await body.forDate('2026-10-03'))!;
      expect(row.weightKg, 80.0);
      expect(row.bodyFatPct, 20.0);
      expect(row.updatedAt, 500, reason: '"没动"要能从库里看出来，而不是靠界面说');
    });

    test('用户的备注不被覆盖（包括我们自己的来源那句话也不许盖掉他写的东西）', () async {
      await body.save(date: '2026-10-04', weightKg: 80.0, note: '空腹', nowMs: 500);
      await body.mergeHealthDays(
        <HealthDayValues>[
          const HealthDayValues(date: '2026-10-04', bodyFatPct: 19.0),
        ],
        nowMs: 1000,
      );
      final BodyMetricData row = (await body.forDate('2026-10-04'))!;
      expect(row.note, '空腹', reason: '备注是用户自己写的，合并凭什么改它');
      expect(row.bodyFatPct, 19.0);
    });

    test('被用户删掉的那天**不复活**，计进 skipped', () async {
      final BodyMetricData saved =
          await body.save(date: '2026-10-05', weightKg: 80.0, nowMs: 500);
      await body.delete(saved.id, nowMs: 600);

      final HealthMergeReport r = await body.mergeHealthDays(
        <HealthDayValues>[
          const HealthDayValues(date: '2026-10-05', weightKg: 72.5),
        ],
        nowMs: 1000,
      );
      expect(r.skipped, 1, reason: '用户删过的东西，不许借"同步"复活');
      expect(await body.count(), 0);
      final BodyMetricData row = (await body.forDate('2026-10-05'))!;
      expect(row.deletedAt, isNotNull);
      expect(row.weightKg, 80.0, reason: '连值都不许改');
    });

    test('系统那天什么都没有（只有日期的空壳）→ 不建空记录', () async {
      final HealthMergeReport r = await body.mergeHealthDays(
        <HealthDayValues>[const HealthDayValues(date: '2026-10-06')],
        nowMs: 1000,
      );
      expect(r.skipped, 1);
      expect(await body.count(), 0);
    });

    test('一批里同一天不会撞 id（多天一起进来）', () async {
      final HealthMergeReport r = await body.mergeHealthDays(
        <HealthDayValues>[
          const HealthDayValues(date: '2026-10-07', weightKg: 71.0),
          const HealthDayValues(date: '2026-10-08', weightKg: 70.5),
          const HealthDayValues(date: '2026-10-09', weightKg: 70.0),
        ],
        nowMs: 1000,
      );
      expect(r.created, 3);
      expect(await body.count(), 3,
          reason: '一批里 nowMs 是同一个值 —— id 必须带上日期，否则三条撞成一条');
    });
  });

  // ───────────────────────────────────────────────────────────── 服务
  group('服务：先看同意，再去读', () {
    test('**没有单独同意 → 一个字节都不读**（桥一次都没被调用）', () async {
      final HealthSyncService sync = HealthSyncService(
        bridge: bridge,
        bodyMetrics: body,
        profile: profile,
      );
      final HealthSyncOutcome out = await sync.sync();

      expect(out.status, HealthSyncStatus.noConsent);
      expect(bridge.availabilityChecks, 0,
          reason: '连"有没有健康库"都不该问 —— 那也是一次平台交互');
      expect(bridge.permissionRequests, 0);
      expect(bridge.reads, 0, reason: '这条是整个合规面的底线');
    });

    test('同意过、但这台设备没有健康库 → unavailable', () async {
      await profile.setHealthConsent(nowMs: 1);
      bridge.available = false;
      final HealthSyncOutcome out = await HealthSyncService(
        bridge: bridge,
        bodyMetrics: body,
        profile: profile,
      ).sync();

      expect(out.status, HealthSyncStatus.unavailable);
      expect(bridge.permissionRequests, 0);
      expect(bridge.reads, 0);
    });

    test('授权那一步没走完 → denied（不当成"没有数据"）', () async {
      await profile.setHealthConsent(nowMs: 1);
      bridge.permission = false;
      final HealthSyncOutcome out = await HealthSyncService(
        bridge: bridge,
        bodyMetrics: body,
        profile: profile,
      ).sync();

      expect(out.status, HealthSyncStatus.denied);
      expect(bridge.reads, 0,
          reason: '没授权就不该去读 —— 读也是白读，还会让人以为"健康库是空的"');
    });

    test('能读但健康库里没有体成分 → empty（这是正常结果，不是失败）', () async {
      await profile.setHealthConsent(nowMs: 1);
      final HealthSyncOutcome out = await HealthSyncService(
        bridge: bridge,
        bodyMetrics: body,
        profile: profile,
      ).sync();

      expect(out.status, HealthSyncStatus.empty);
      expect(await body.count(), 0);
    });

    test('按本地日分组，每个字段取那天**最新**的一个值', () async {
      await profile.setHealthConsent(nowMs: 1);
      bridge.samples = <HealthSample>[
        // 同一天三条：体重在傍晚又量了一次、体脂只有早上那条有
        HealthSample(atMs: atMs(2026, 10, 1, 7), weightKg: 72.5, bodyFatPct: 18.0),
        HealthSample(atMs: atMs(2026, 10, 1, 19), weightKg: 72.0),
        HealthSample(atMs: atMs(2026, 10, 1, 12)),
        HealthSample(atMs: atMs(2026, 9, 30, 8), weightKg: 73.0),
      ];
      final HealthSyncOutcome out = await HealthSyncService(
        bridge: bridge,
        bodyMetrics: body,
        profile: profile,
      ).sync();

      expect(out.status, HealthSyncStatus.imported);
      expect(out.samples, 4);
      expect(out.report!.created, 2);

      final BodyMetricData first = (await body.forDate('2026-10-01'))!;
      expect(first.weightKg, 72.0, reason: '取那天最新的 72.0，不是早上那条 72.5');
      expect(first.bodyFatPct, 18.0, reason: '那天只有早上那条有体脂 —— 按字段各取最新');
      expect((await body.forDate('2026-09-30'))!.weightKg, 73.0);
    });

    test('身高只在档案里**空着**的时候才补', () async {
      await profile.setHealthConsent(nowMs: 1);
      bridge.samples = <HealthSample>[
        HealthSample(atMs: atMs(2026, 10, 1), weightKg: 72.0, heightCm: 178.0),
      ];
      final HealthSyncOutcome first = await HealthSyncService(
        bridge: bridge,
        bodyMetrics: body,
        profile: profile,
      ).sync();
      expect(first.heightFilledCm, 178.0);
      expect(await profile.heightCm(), 178.0);

      // 用户自己改成了 180，下一次同步不许把它改回 178
      await profile.setHeightCm(180);
      bridge.samples = <HealthSample>[
        HealthSample(atMs: atMs(2026, 10, 2), heightCm: 178.0),
      ];
      final HealthSyncOutcome second = await HealthSyncService(
        bridge: bridge,
        bodyMetrics: body,
        profile: profile,
      ).sync();
      expect(second.heightFilledCm, isNull);
      expect(await profile.heightCm(), 180.0,
          reason: '用户自己量过的身高优先于健康库里那个旧值');
    });

    test('撤回同意之后，再同步就不读了', () async {
      await profile.setHealthConsent(nowMs: 1);
      await profile.clearHealthConsent(nowMs: 2);
      final HealthSyncOutcome out = await HealthSyncService(
        bridge: bridge,
        bodyMetrics: body,
        profile: profile,
      ).sync();

      expect(out.status, HealthSyncStatus.noConsent);
      expect(bridge.reads, 0);
    });
  });

  // ───────────────────────────────────────────────────────────── 两道门
  group('两道单独同意各管各的', () {
    test('撤回健康库那道，不影响身体数据那道（反过来也一样）', () async {
      await profile.setBodyMetricConsent(nowMs: 11);
      await profile.setHealthConsent(nowMs: 22);
      await profile.clearHealthConsent(nowMs: 33);
      expect(await profile.healthConsentAtMs(), isNull);
      expect(await profile.bodyMetricConsentAtMs(), 11,
          reason: '撤回一个不等于撤回另一个 —— 两件事、两个目的，不能互相顶替');

      await profile.setHealthConsent(nowMs: 44);
      await profile.clearBodyMetricConsent(nowMs: 55);
      expect(await profile.bodyMetricConsentAtMs(), isNull);
      expect(await profile.healthConsentAtMs(), 44,
          reason: '反过来也一样');
    });

    test('别的设置不会把我们那道同意抹掉（可空列在 upsert 里会被写成 null）', () async {
      // 这条守的是 `profile_repository.dart` 里那 10 个 UserProfileData 站点：
      // 每个 setter 都必须把已有字段原样带回去，漏一个新的可空列就"改个昵称，
      // 健康库那道同意就没了"—— 而那种 bug 在界面上完全看不出来。
      await profile.setHealthConsent(nowMs: 22);
      await profile.setNickname('李松', nowMs: 100);
      await profile.setUnit(WeightUnit.lb, nowMs: 101);
      await profile.setHeightCm(180, nowMs: 102);
      await profile.setAnalyticsEnabled(false, nowMs: 103);

      expect(await profile.healthConsentAtMs(), 22);
      expect(await profile.bodyMetricConsentAtMs(), isNull,
          reason: '没同意过的那些仍然是 null —— 不许被顺手写成别的');
    });
  });

  // ───────────────────────────────────────────────────────────── 平台桥
  group('平台桥', () {
    test('平台没实现（MissingPluginException）→ 安静地当"没有健康库"', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannelHealthBridge.channel,
              (MethodCall call) async => throw MissingPluginException('没有实现'));
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannelHealthBridge.channel, null));

      const MethodChannelHealthBridge b = MethodChannelHealthBridge();
      expect(await b.isAvailable(), isFalse);
      expect(await b.requestPermission(), isFalse);
      expect(await b.readBodyComposition(), isEmpty);
    });

    test('解析平台返回的样本（坏数据要被跳过，不是崩掉）', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannelHealthBridge.channel,
              (MethodCall call) async {
        expect(call.method, 'readBodyComposition');
        expect((call.arguments as Map<Object?, Object?>)['days'], 180);
        return <Object?>[
          <String, Object?>{'atMs': 1000, 'weightKg': 72.5, 'bodyFatPct': 18.0},
          <String, Object?>{'atMs': 2000, 'weightKg': 71.0, 'heightCm': 178.0},
          // 没有时间戳的那条要被跳过
          <String, Object?>{'weightKg': 99.0},
          'not a map',
        ];
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannelHealthBridge.channel, null));

      const MethodChannelHealthBridge b = MethodChannelHealthBridge();
      final List<HealthSample> got = await b.readBodyComposition();
      expect(got.length, 2);
      expect(got.first.weightKg, 72.5);
      expect(got.first.bodyFatPct, 18.0);
      expect(got[1].heightCm, 178.0);
    });
  });

  // ───────────────────────────────────────────────────────────── 页面
  group('身体数据页那个入口', () {
    /// 把这一页立起来（先过"身体数据"那道门，否则进来先弹的是那一个）。
    Future<void> pumpPage(WidgetTester tester, {HealthBridge? bridge}) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await profile.setBodyMetricConsent(nowMs: 1);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: BodyMetricScreen(
          repository: body,
          profile: profile,
          unit: BodyWeightUnit.kg,
          healthBridge: bridge,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('安卓上这个入口**根本不出现**（那一端还没接，不给做不到的承诺）',
        (WidgetTester tester) async {
      // 测试环境默认就是 android。⚠️ **故意不传桥** —— 这条测的就是
      // "没传桥时按平台决定"，传了假桥就把被测的那段绕过去了。
      await pumpPage(tester);
      expect(find.byKey(const Key('health-sync-entry')), findsNothing);
    });

    testWidgets('iPhone 上出现入口；点它先弹单独同意，拒绝就一个字节都不读',
        (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await pumpPage(tester, bridge: bridge);

      expect(find.byKey(const Key('health-sync-entry')), findsOneWidget);
      await tester.tap(find.byKey(const Key('health-sync-entry')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('health-consent')), findsOneWidget);
      // 说明里不许出现 markdown 星号（Text 不渲染 markdown，用户会看到星号）
      final Text note = tester.widget<Text>(find.byKey(const Key('health-consent')));
      expect(note.data, isNot(contains('*')));
      expect(note.data, contains('敏感个人信息'));
      // 只读、不写回、不上传、随时可撤 —— 四句话必须都在
      expect(note.data, contains('只读'));
      expect(note.data, contains('不写回'));
      expect(note.data, contains('不上传'));
      expect(note.data, contains('撤回'));

      await tester.tap(find.byKey(const Key('health-consent-decline')));
      await tester.pumpAndSettle();

      expect(bridge.availabilityChecks, 0, reason: '拒绝之前不该碰平台');
      expect(bridge.reads, 0);
      expect(await profile.healthConsentAtMs(), isNull);

      // 撤回入口也不该出现（没什么可撤回的）
      expect(find.byKey(const Key('health-revoke')), findsNothing);
      // ⚠️ 必须在**用例体里**改回 null：框架在用例体结束时就校验，
      // 放 tearDown 里已经太晚（会报 "foundation debug variable was changed"）。
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('同意之后：读一次、并进来、如实报数，并出现撤回入口',
        (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      bridge.samples = <HealthSample>[
        HealthSample(atMs: atMs(2026, 9, 20), weightKg: 73.0, bodyFatPct: 19.5),
      ];
      await pumpPage(tester, bridge: bridge);
      // 页面上的"今天"是真实时间，用不到 —— 只断言那条被并进来的记录
      await tester.tap(find.byKey(const Key('health-sync-entry')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('health-consent-agree')));
      await tester.pumpAndSettle();

      expect(await profile.healthConsentAtMs(), isNotNull);
      expect(bridge.reads, 1);

      final Text result = tester.widget<Text>(find.byKey(const Key('health-result')));
      expect(result.data, contains('新记了 1 天'));
      expect(result.data, isNot(contains('*')));

      await tester.tap(find.byKey(const Key('health-result-ok')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('health-revoke')), findsOneWidget);
      final BodyMetricData row = (await body.forDate('2026-09-20'))!;
      expect(row.weightKg, 73.0);
      expect(row.note, kHealthNote);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('撤回：清掉同意、不再读，数据一条不删', (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await profile.setHealthConsent(nowMs: 5);
      await body.save(date: '2026-09-19', weightKg: 74.0, nowMs: 1);
      await pumpPage(tester, bridge: bridge);

      await tester.dragUntilVisible(
        find.byKey(const Key('health-revoke')),
        find.byKey(const Key('body-scroll')),
        const Offset(0, -200),
      );
      await tester.tap(find.byKey(const Key('health-revoke')));
      await tester.pumpAndSettle();

      final Text note = tester.widget<Text>(find.byKey(const Key('health-revoke-note')));
      expect(note.data, contains('不会被删掉'));

      await tester.tap(find.byKey(const Key('health-revoke-yes')));
      await tester.pumpAndSettle();

      expect(await profile.healthConsentAtMs(), isNull);
      expect(await body.count(), 1, reason: '撤回的是同意，不是数据');
      expect(find.byKey(const Key('health-revoke')), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
