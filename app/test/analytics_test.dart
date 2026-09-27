/// 练了么 · 埋点上报测试（outbox / 刷写器 / 传输层）
///
/// 这一层的每条规则都对应 `docs/analytics-sdk.md` 的一节，
/// 所以每条规则都该有一条测试 —— 不然那份文档就只是散文。
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/flusher.dart';
import 'package:lianleme/analytics/outbox.dart';
import 'package:lianleme/analytics/transport.dart';
import 'package:lianleme/data/db.dart';

void main() {
  late AppDatabase db;
  late AnalyticsOutboxStore outbox;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    outbox = AnalyticsOutboxStore(db);
  });

  tearDown(() => db.close());

  Future<void> put(String name, {int priority = 1, int at = 1000}) =>
      outbox.enqueue(name: name, props: <String, Object?>{'x': 1}, priority: priority, nowMs: at);

  group('事件优先级（§6）', () {
    test('P0：北极星与漏斗靠它们，不可丢', () {
      for (final String e in <String>[
        'app_open',
        'workout_started',
        'set_logged',
        'workout_finished',
        'purchase_completed',
      ]) {
        expect(priorityFor(e), 0, reason: '$e 应该是 P0');
      }
    });

    test('P2：辅助分析', () {
      for (final String e in <String>[
        'onboarding_step',
        'paywall_viewed',
        'share_card_created',
        'body_metric_logged',
      ]) {
        expect(priorityFor(e), 2, reason: '$e 应该是 P2');
      }
    });

    test('其余默认 P1', () {
      for (final String e in <String>[
        'suggestion_shown',
        'suggestion_accepted',
        'set_edited',
        'set_undone',
        'pr_achieved',
        'rest_skipped',
      ]) {
        expect(priorityFor(e), 1, reason: '$e 应该是 P1');
      }
    });

    test('没列举过的新事件也不会掉进 P0', () {
      expect(priorityFor('some_future_event'), 1);
    });
  });

  group('重试间隔（§5：1s / 4s / 16s + 抖动）', () {
    test('三次的基准值', () {
      expect(retryDelay(1).inMilliseconds, 1000);
      expect(retryDelay(2).inMilliseconds, 4000);
      expect(retryDelay(3).inMilliseconds, 16000);
    });

    test('超过三次沿用最大值（不该无限增长）', () {
      expect(retryDelay(4).inMilliseconds, 16000);
      expect(retryDelay(99).inMilliseconds, 16000);
    });

    test('抖动最多 +20%，且 jitter=0 时完全可预测', () {
      expect(retryDelay(1, jitter: 0).inMilliseconds, 1000);
      expect(retryDelay(1, jitter: 1).inMilliseconds, 1200);
      expect(retryDelay(2, jitter: 1).inMilliseconds, 4800);
    });
  });

  group('outbox（§4）', () {
    test('入队与计数', () async {
      expect(await outbox.pending(), 0);
      await put('set_logged', priority: 0);
      await put('suggestion_shown');
      expect(await outbox.pending(), 2);
    });

    test('取批次：优先级高的先出，同级先进先出', () async {
      await put('p2', priority: 2, at: 1000);
      await put('p1_late', priority: 1, at: 3000);
      await put('p1_early', priority: 1, at: 2000);
      await put('p0', priority: 0, at: 4000);

      final List<AnalyticsEventPayload> batch = await outbox.takeBatch();
      expect(batch.map((AnalyticsEventPayload e) => e.name).toList(),
          <String>['p0', 'p1_early', 'p1_late', 'p2']);
    });

    test('取批次受 limit 限制', () async {
      for (int i = 0; i < 5; i++) {
        await put('e$i', at: 1000 + i);
      }
      expect((await outbox.takeBatch(limit: 3)).length, 3);
    });

    test('payload 原样解析回来（中文与数字都不能坏）', () async {
      await outbox.enqueue(
        name: 'set_logged',
        props: <String, Object?>{'exercise_id': 'ex_bb_bench_press', 'tap_count': 1, 'tap_kinds': <String>['big_button']},
        priority: 0,
        nowMs: 1000,
      );
      final AnalyticsEventPayload e = (await outbox.takeBatch()).single;
      expect(e.props['exercise_id'], 'ex_bb_bench_press');
      expect(e.props['tap_count'], 1);
      expect(e.props['tap_kinds'], <String>['big_button']);
    });

    test('发送成功后从队列删除', () async {
      await put('set_logged', priority: 0);
      final List<AnalyticsEventPayload> batch = await outbox.takeBatch();
      await outbox.markSent(batch.map((AnalyticsEventPayload e) => e.id).toList());
      expect(await outbox.pending(), 0);
    });

    test('失败会累加 attempts，连续 3 次后不再被取出（parked）', () async {
      await put('set_logged', priority: 0);

      for (int i = 0; i < 3; i++) {
        final List<AnalyticsEventPayload> batch = await outbox.takeBatch();
        expect(batch.length, 1, reason: '第 ${i + 1} 次还能取出来');
        await outbox.markFailed(batch.map((AnalyticsEventPayload e) => e.id).toList(), 'boom');
      }

      expect(await outbox.takeBatch(), isEmpty, reason: '连续 3 次失败后应该 parked');
      expect(await outbox.pending(), 1, reason: 'parked 不等于丢弃，还在队列里');
    });

    test('冷启动会放行 parked 的事件（§5）', () async {
      await put('set_logged', priority: 0);
      for (int i = 0; i < 3; i++) {
        final List<AnalyticsEventPayload> b = await outbox.takeBatch();
        await outbox.markFailed(b.map((AnalyticsEventPayload e) => e.id).toList(), 'boom');
      }

      expect(await outbox.resetParked(), 1);
      expect((await outbox.takeBatch()).length, 1, reason: '放行之后又能取了');
    });

    test('溢出时先丢低优先级，同级先丢旧的（§5）', () async {
      final AnalyticsOutboxStore small = AnalyticsOutboxStore(db, maxRows: 3);
      await small.enqueue(name: 'p0_old', props: <String, Object?>{}, priority: 0, nowMs: 1000);
      await small.enqueue(name: 'p1_mid', props: <String, Object?>{}, priority: 1, nowMs: 2000);
      await small.enqueue(name: 'p2_new', props: <String, Object?>{}, priority: 2, nowMs: 3000);
      await small.enqueue(name: 'p1_new', props: <String, Object?>{}, priority: 1, nowMs: 4000);

      expect(await small.pending(), 4);
      expect(await small.dropOverflow(), 1, reason: '超出 1 条');

      final List<String> left = (await small.takeBatch())
          .map((AnalyticsEventPayload e) => e.name)
          .toList();
      expect(left, <String>['p0_old', 'p1_mid', 'p1_new'],
          reason: '被丢的应该是 P2（优先级最低）');
    });

    test('没超上限时不动队列', () async {
      final AnalyticsOutboxStore small = AnalyticsOutboxStore(db, maxRows: 3);
      await small.enqueue(name: 'a', props: <String, Object?>{}, priority: 0, nowMs: 1000);
      expect(await small.dropOverflow(), 0);
      expect(await small.pending(), 1);
    });
  });

  group('刷写器（§5）', () {
    test('队列空时什么都不做', () async {
      final AnalyticsFlusher f =
          AnalyticsFlusher(db: db, transport: FakeAnalyticsTransport(), outbox: outbox);
      final FlushResult r = await f.flushOnce();
      expect(r.outcome, FlushOutcome.empty);
      expect(r.isSuccess, isTrue);
    });

    test('成功时送出并清空', () async {
      await put('set_logged', priority: 0);
      await put('suggestion_shown');
      final FakeAnalyticsTransport t = FakeAnalyticsTransport();
      final AnalyticsFlusher f = AnalyticsFlusher(db: db, transport: t, outbox: outbox);

      final FlushResult r = await f.flushOnce();
      expect(r.outcome, FlushOutcome.sent);
      expect(r.count, 2);
      expect(t.allReceived.length, 2);
      expect(await outbox.pending(), 0);
    });

    test('一次最多送 batchSize 条（§5：≤100）', () async {
      for (int i = 0; i < 7; i++) {
        await put('e$i', at: 1000 + i);
      }
      final FakeAnalyticsTransport t = FakeAnalyticsTransport();
      final AnalyticsFlusher f =
          AnalyticsFlusher(db: db, transport: t, outbox: outbox, batchSize: 3);

      await f.flushOnce();
      expect(t.received.single.length, 3);
      expect(await outbox.pending(), 4);
    });

    test('失败时给出重试间隔，事件留在队列里', () async {
      await put('set_logged', priority: 0);
      final AnalyticsFlusher f = AnalyticsFlusher(
          db: db, transport: FakeAnalyticsTransport(succeed: false), outbox: outbox);

      final FlushResult r = await f.flushOnce();
      expect(r.outcome, FlushOutcome.failed);
      expect(r.nextRetry, const Duration(milliseconds: 1000));
      expect(await outbox.pending(), 1);
    });

    test('训练进行中挂起 —— 不发任何请求（红线）', () async {
      await put('set_logged', priority: 0);
      final FakeAnalyticsTransport t = FakeAnalyticsTransport();
      final AnalyticsFlusher f = AnalyticsFlusher(db: db, transport: t, outbox: outbox);

      f.suspend();
      final FlushResult r = await f.flushOnce();

      expect(r.outcome, FlushOutcome.suspended);
      expect(t.received, isEmpty, reason: '挂起期间一次网络请求都不该发');
      expect(await outbox.pending(), 1, reason: '事件还在，恢复后照常送');

      f.resume();
      expect((await f.flushOnce()).outcome, FlushOutcome.sent);
    });

    test('冷启动放行 parked 并清零失败计数', () async {
      await put('set_logged', priority: 0);
      final AnalyticsFlusher f = AnalyticsFlusher(
          db: db, transport: FakeAnalyticsTransport(succeed: false), outbox: outbox);
      for (int i = 0; i < 3; i++) {
        await f.flushOnce();
      }
      expect((await f.flushOnce()).outcome, FlushOutcome.empty, reason: '已 parked');

      expect(await f.onColdStart(), 1);
      expect(await outbox.pending(), 1);
    });
  });

  group('HTTP 传输层', () {
    test('把事件 POST 出去（本地环回服务器验证）', () async {
      final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      final List<String> bodies = <String>[];
      server.listen((HttpRequest req) async {
        bodies.add(await utf8.decoder.bind(req).join());
        req.response.statusCode = 200;
        await req.response.close();
      });

      final HttpAnalyticsTransport t = HttpAnalyticsTransport(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/analytics/batch'),
      );
      addTearDown(t.close);

      final bool ok = await t.send(<AnalyticsEventPayload>[
        const AnalyticsEventPayload(
          id: 'e1',
          name: 'set_logged',
          props: <String, Object?>{'tap_count': 1},
          priority: 0,
          createdAt: 1000,
        ),
      ]);

      expect(ok, isTrue);
      expect(bodies.length, 1);
      expect(bodies.single, contains('"event":"set_logged"'));
      expect(bodies.single, contains('"tap_count":1'));
      expect(bodies.single, contains('"ts":1000'));
    });

    test('服务端 500 → 返回 false，不抛异常', () async {
      final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((HttpRequest req) async {
        await req.drain<void>();
        req.response.statusCode = 500;
        await req.response.close();
      });

      final HttpAnalyticsTransport t = HttpAnalyticsTransport(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/x'),
      );
      addTearDown(t.close);

      expect(await t.send(<AnalyticsEventPayload>[
        const AnalyticsEventPayload(id: 'e1', name: 'x', props: <String, Object?>{}, priority: 1, createdAt: 1),
      ]), isFalse);
    });

    test('连不上 → 返回 false，不抛异常', () async {
      // 先占一个端口再关掉，确保这个端口没人监听
      final HttpServer tmp = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final int deadPort = tmp.port;
      await tmp.close(force: true);

      final HttpAnalyticsTransport t = HttpAnalyticsTransport(
        endpoint: Uri.parse('http://127.0.0.1:$deadPort/x'),
        timeout: const Duration(milliseconds: 500),
      );
      addTearDown(t.close);

      expect(await t.send(<AnalyticsEventPayload>[
        const AnalyticsEventPayload(id: 'e1', name: 'x', props: <String, Object?>{}, priority: 1, createdAt: 1),
      ]), isFalse);
    });

    test('空批次直接成功，不发请求', () async {
      final HttpAnalyticsTransport t = HttpAnalyticsTransport(
        endpoint: Uri.parse('http://127.0.0.1:1/x'),
      );
      addTearDown(t.close);
      expect(await t.send(<AnalyticsEventPayload>[]), isTrue);
    });
  });
}
