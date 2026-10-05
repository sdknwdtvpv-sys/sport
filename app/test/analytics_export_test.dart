/// 练了么 · 「导出统计事件」这一条路
///
/// **为什么它值得一整个测试文件**：这是**唯一**能把 `tap_count` 从设备上取回来的路径。
/// 没配上报地址的包里 `_NullTransport` 恒失败，事件只会在本地越攒越多 ——
/// 而 `ROADMAP.md` 阶段 3（"带手机去健身房真的练一次"）唯一能产出的客观数字就是它。
/// 这条路径坏了不会有人立刻发现：**界面看起来完全正常，只是导出来的东西不对**。
///
/// 四层都要守住：
///   1. **格式**：导出的每一行就是上报时会发出去的那一份（含 `tap_count` / `tap_kinds`），
///      所以它能直接喂给 `tool/analytics-report.mjs`；
///   2. **范围**：`peekAll()` 必须**包含 parked 的**（连续失败 ≥ 3 次）——
///      那正是"发不出去"的那批，过滤掉等于把最该看的数据藏起来；且它**不删**队列；
///   3. **门禁**：开关关着时入口不存在（关着时本来没在收集，按钮必然是空的）；
///   4. **诚实**：零事件时不导出空文件，而是如实说"还没有攒下事件"。
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/analytics.dart';
import 'package:lianleme/analytics/analytics_export.dart';
import 'package:lianleme/analytics/outbox.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/features/profile/backup_exporter.dart';
import 'package:lianleme/features/profile/privacy_about_screen.dart';

/// 把"交出去的东西"记下来 —— 插件调用在 widget 测试里验证不了，
/// 但"点了导出之后到底交出去了什么"完全可以验证。
class _RecordingExporter implements BackupExporter {
  String? content;
  String? fileName;
  int calls = 0;

  @override
  Future<void> shareBackup(String json, {required String fileName}) async {
    calls++;
    content = json;
    this.fileName = fileName;
  }
}

/// 一条事件的 props 至少要有这几个公共字段（`docs/analytics.md` §2.1）
Map<String, Object?> _props({int tap = 1}) => <String, Object?>{
      'device_id': 'dev_test',
      'session_id': 'sess_1',
      'app_version': '1.36.0',
      'schema_version': 15,
      'tap_count': tap,
      'tap_kinds': <String>['nav', 'big_button'],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('JSONL 口径（导出物就是上报物）', () {
    test('一行一条；每行都是合法 JSON，且含 tap_count / tap_kinds', () {
      final String out = buildEventsJsonl(<AnalyticsEventPayload>[
        const AnalyticsEventPayload(
          id: 'e1',
          name: 'set_logged',
          props: <String, Object?>{'tap_count': 2, 'tap_kinds': <String>['nav', 'big_button']},
          priority: 0,
          createdAt: 1000,
        ),
        const AnalyticsEventPayload(
          id: 'e2',
          name: 'app_open',
          props: <String, Object?>{'is_first_open': true},
          priority: 0,
          createdAt: 2000,
        ),
      ]);

      final List<String> lines =
          out.trim().split('\n').where((String l) => l.isNotEmpty).toList();
      expect(lines.length, 2, reason: '两条事件就是两行');

      final Map<String, dynamic> first =
          jsonDecode(lines[0]) as Map<String, dynamic>;
      // 与 AnalyticsEventPayload.toJson() 同一份形状
      expect(first['id'], 'e1');
      expect(first['event'], 'set_logged');
      expect(first['ts'], 1000);
      expect(first['priority'], 0);
      expect(first['tap_count'], 2, reason: 'tap_count 必须在 —— 它是这个出口存在的理由');
      expect(first['tap_kinds'], <String>['nav', 'big_button']);

      expect((jsonDecode(lines[1]) as Map<String, dynamic>)['event'], 'app_open');
    });

    test('零事件 → 空字符串（调用方据此不导出空文件）', () {
      expect(buildEventsJsonl(<AnalyticsEventPayload>[]), '');
    });

    test('文件名带日期，扩展名是 .jsonl（一行一条，不是 JSON 数组）', () {
      final int ms = DateTime(2026, 10, 3, 21, 0).millisecondsSinceEpoch;
      expect(eventsFileName(ms), '练了么-埋点-2026-10-03.jsonl');
    });

    test('EventsExport 的空态与文案一致', () {
      const EventsExport empty = EventsExport(jsonl: '', count: 0);
      expect(empty.isEmpty, isTrue);
      const EventsExport one = EventsExport(jsonl: 'x\n', count: 1);
      expect(one.isEmpty, isFalse);
      expect(one.summary, '已导出 1 条统计事件');
    });
  });

  group('peekAll()：队列的唯一出口', () {
    late AppDatabase db;
    late AnalyticsOutboxStore outbox;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      // ⚠️ 假时钟是**必须**的（2026-10-05 加 D 方案之后）：outbox 里有"超过 30 天就丢"
      // 这条规则，它拿 `clock()` 去和 `createdAt` 比；而这组用例的时间戳是 10–300
      // （1970 年），不注入就会全部被当成超龄事件清掉 —— 那是测试时钟没对齐。
      outbox = AnalyticsOutboxStore(db, clock: () => 1000);
    });
    tearDown(() => db.close());

    test('按"优先级 + 时间"取全量，且不删除任何东西', () async {
      await outbox.enqueue(name: 'p2_late', props: _props(), priority: 2, nowMs: 200);
      await outbox.enqueue(name: 'p0_early', props: _props(), priority: 0, nowMs: 100);
      await outbox.enqueue(name: 'p0_late', props: _props(), priority: 0, nowMs: 300);

      final List<AnalyticsEventPayload> all = await outbox.peekAll();
      expect(all.map((AnalyticsEventPayload e) => e.name).toList(),
          <String>['p0_early', 'p0_late', 'p2_late']);

      // 导出是只读动作：导完队列还是满的（可以再导一次，内容只会更多）
      expect(await outbox.pending(), 3);
      expect((await outbox.peekAll()).length, 3);
    });

    test('★ parked 的事件（连续失败 3 次）**也在**导出里 —— 那正是发不出去的那批', () async {
      await outbox.enqueue(name: 'set_logged', props: _props(tap: 3), priority: 0, nowMs: 10);
      await outbox.enqueue(name: 'set_logged', props: _props(tap: 1), priority: 0, nowMs: 20);

      // 把第一条打成 parked（连续失败 3 次）
      final List<AnalyticsEventPayload> batch = await outbox.takeBatch();
      final String parkedId = batch.first.id;
      for (int i = 0; i < AnalyticsOutboxStore.maxAttempts; i++) {
        await outbox.markFailed(<String>[parkedId], 'boom');
      }

      // takeBatch 不再返回它（等下次冷启动 resetParked）
      expect((await outbox.takeBatch()).map((AnalyticsEventPayload e) => e.id),
          isNot(contains(parkedId)));
      // 但导出必须能看见它
      expect((await outbox.peekAll()).map((AnalyticsEventPayload e) => e.id),
          contains(parkedId));
    });
  });

  group('「隐私与关于」屏上的入口', () {
    late AppDatabase db;
    late ProfileRepository profile;
    late RecordingAnalytics analytics;
    late _RecordingExporter exporter;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      profile = ProfileRepository(db);
      analytics = RecordingAnalytics();
      exporter = _RecordingExporter();
    });
    tearDown(() => db.close());

    Future<void> pumpScreen(
      WidgetTester tester, {
      required Future<List<AnalyticsEventPayload>> Function()? loadEvents,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: PrivacyAboutScreen(
          profile: profile,
          analytics: analytics,
          loadEvents: loadEvents,
          backupExporter: exporter,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('开关关着 → 没有导出入口（关着时本来就没在收集）',
        (WidgetTester tester) async {
      await profile.setAnalyticsEnabled(false);
      await pumpScreen(tester,
          loadEvents: () async => <AnalyticsEventPayload>[]);

      expect(find.byKey(const Key('analytics-export')), findsNothing);
      expect(find.byKey(const Key('analytics-switch')), findsOneWidget);
    });

    testWidgets('开关开着 → 入口出现；点了它交出去的是 JSONL 文件',
        (WidgetTester tester) async {
      await profile.setAnalyticsEnabled(true);
      final List<AnalyticsEventPayload> events = <AnalyticsEventPayload>[
        const AnalyticsEventPayload(
          id: 'e1',
          name: 'set_logged',
          props: <String, Object?>{'tap_count': 1},
          priority: 0,
          createdAt: 1000,
        ),
      ];
      await pumpScreen(tester, loadEvents: () async => events);

      final Finder entry = find.byKey(const Key('analytics-export'));
      expect(entry, findsOneWidget, reason: '开关开着时必须有这个出口');

      await tester.tap(entry);
      await tester.pumpAndSettle();

      expect(exporter.calls, 1);
      expect(exporter.fileName, endsWith('.jsonl'));
      expect(exporter.fileName, startsWith('练了么-埋点-'));
      final List<String> lines = (exporter.content ?? '')
          .trim()
          .split('\n')
          .where((String l) => l.isNotEmpty)
          .toList();
      expect(lines.length, 1);
      expect((jsonDecode(lines.first) as Map<String, dynamic>)['tap_count'], 1);
    });

    testWidgets('零事件 → **不**导出空文件，如实说"还没有攒下事件"',
        (WidgetTester tester) async {
      await profile.setAnalyticsEnabled(true);
      await pumpScreen(tester,
          loadEvents: () async => <AnalyticsEventPayload>[]);

      await tester.tap(find.byKey(const Key('analytics-export')));
      await tester.pumpAndSettle();

      expect(exporter.calls, 0, reason: '空文件没有任何用处，还会让收件人以为导出成功');
      expect(find.textContaining('还没有攒下事件'), findsOneWidget);
    });

    testWidgets('没注入 loadEvents → 即使开关开着也不出现入口（点了会报错的按钮比没有更糟）',
        (WidgetTester tester) async {
      await profile.setAnalyticsEnabled(true);
      await pumpScreen(tester, loadEvents: null);

      expect(find.byKey(const Key('analytics-export')), findsNothing);
    });

    testWidgets('★ 导出这个动作本身**不上报**（否则要再写一条政策披露）',
        (WidgetTester tester) async {
      await profile.setAnalyticsEnabled(true);
      await pumpScreen(tester, loadEvents: () async => <AnalyticsEventPayload>[
            const AnalyticsEventPayload(
              id: 'e1',
              name: 'set_logged',
              props: <String, Object?>{},
              priority: 0,
              createdAt: 1,
            ),
          ]);

      analytics.events.clear();
      await tester.tap(find.byKey(const Key('analytics-export')));
      await tester.pumpAndSettle();

      expect(analytics.events, isEmpty,
          reason: '导出既不是"发送"也不是"收集"，不该留下任何事件');
      expect(exporter.calls, 1);
    });
  });
}
