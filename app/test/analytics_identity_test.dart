/// 练了么 · 埋点的公共字段与漏斗起点
///
/// **这个文件补的是一个会让人白干一场的窟窿**：上报管线（outbox / 批量 / 退避 /
/// 训练期挂起 / 本地环回 HTTP 测试）早就写完了，但客户端**只发 6 个事件**，
/// 而 `docs/analytics.md` 定义了 31 个。最要命的是：
///
///   * `app_open` **从来没发过** → 北极星的分母是空的
///   * `workout_finished` **从来没发过** → 北极星的分子也是空的
///   * 公共字段（`device_id` / `session_id` / `app_version` / `platform` / `is_offline`）
///     一个都没带 → 就算发了，也认不出"这是同一台设备"
///
/// 也就是说：**指标定义早就写死了，但没有任何数据能算出它**。
/// 这一类窟窿的特征是"测试全绿"—— 所以这里测的不是"字段拼得对不对"，
/// 而是"**北极星那条链路真的能算出来吗**"。
library;

import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/analytics_context.dart';
import 'package:lianleme/analytics/outbox.dart';
import 'package:lianleme/analytics/outbox_analytics.dart';
import 'package:lianleme/core/app_info.dart';
import 'package:lianleme/data/analytics_meta_repository.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;

const int _minute = 60 * 1000;

/// 固定种子的随机数：设备 ID 的断言不能靠"看起来像随机"。
Random _seeded() => Random(42);

void main() {
  late AppDatabase db;
  late AnalyticsMetaRepository meta;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    meta = AnalyticsMetaRepository(db, random: _seeded(), clock: () => 1000);
  });

  tearDown(() => db.close());

  group('本机身份：设备 / 会话 / 首次启动', () {
    test('设备 ID 生成一次就不再变（换会话也不行）', () async {
      final AnalyticsMetaData first = await meta.ensure();
      expect(first.deviceId, hasLength(32));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(first.deviceId), isTrue,
          reason: '匿名 ID 只该是十六进制，别混进可识别信息');

      await meta.ensure(); // 30 分钟内
      final AnalyticsMetaData later = await meta.ensure();
      expect(later.deviceId, first.deviceId, reason: '设备 ID 是设备的，不是会话的');
    });

    test('30 分钟无事件 → 换会话；设备 ID 不变', () async {
      int now = 1000;
      final AnalyticsMetaRepository repo =
          AnalyticsMetaRepository(db, random: _seeded(), clock: () => now);

      final AnalyticsMetaData a = await repo.ensure();
      now += 29 * _minute;
      final AnalyticsMetaData same = await repo.ensure();
      expect(same.sessionId, a.sessionId, reason: '29 分钟还算同一段使用');

      // ⚠️ 上一句的 ensure() 已经把"最后一次事件时间"推到了那一刻，
      // 所以要再往后走**超过 30 分钟**才算会话过期（第一版这里只加了 2 分钟，
      // 于是测的是"没过期"，自然红）。
      now += 31 * _minute;
      final AnalyticsMetaData rotated = await repo.ensure();
      expect(rotated.sessionId, isNot(a.sessionId));
      expect(rotated.deviceId, a.deviceId);
    });

    test('is_first_open 只在第一次为 true，markFirstOpen 之后永远是 false', () async {
      expect(await meta.isFirstOpen(), isTrue);
      await meta.markFirstOpen();
      expect(await meta.isFirstOpen(), isFalse);
      // 重复调用不能把首启时间改掉（那会让"首次 24h"窗口一直往后推）
      await meta.markFirstOpen(atMs: 999999);
      expect((await meta.ensure()).firstOpenAt, 1000);
    });

    test('升级上来的老库：这张表是空的 → 升级用户算"新设备"', () async {
      // 这是有意的语义：v1–v6 从来没有过设备 ID，所以那一版的用户
      // 从装上新版这一刻起才算"首次"。想改这个语义就得先有历史数据，没有就没有。
      expect(await meta.isFirstOpen(), isTrue);
    });
  });

  group('公共字段（docs/analytics.md §2.1）', () {
    test('每个事件都自动带上七个字段，且调用方传的同名字段被覆盖', () async {
      final OutboxAnalytics analytics = OutboxAnalytics(
        outbox: AnalyticsOutboxStore(db),
        context: DeviceAnalyticsContext(
          repository: meta,
          platform: () => 'android',
        ),
        offline: () => true,
        clock: () => 5000,
      );

      // 调用方故意也传一个 is_offline（客户端以前就是各处自己传的）——
      // 公共层必须赢，否则同一个字段两个来源，早晚对不上。
      analytics.track('set_logged', <String, Object?>{
        'reps': 8,
        'is_offline': false,
      });
      await Future<void>.delayed(Duration.zero);

      final List<AnalyticsEventPayload> rows = await AnalyticsOutboxStore(db).takeBatch();
      final AnalyticsEventPayload e = rows.single;
      expect(e.name, 'set_logged');
      expect(e.props['reps'], 8);
      expect(e.props['schema_version'], kAnalyticsSchemaVersion);
      expect(e.props['device_id'], hasLength(32));
      expect(e.props['session_id'], hasLength(32));
      expect(e.props['app_version'], kAppVersion);
      expect(e.props['platform'], 'android');
      expect(e.props['is_offline'], isTrue, reason: '以公共层为准');
      expect(e.props.containsKey('user_id'), isTrue);
      expect(e.props['user_id'], isNull, reason: '游客态也要上报，但带 null');
    });

    test('取不到公共字段时**事件照样送出去**（少字段好过丢事件）', () async {
      final OutboxAnalytics analytics = OutboxAnalytics(
        outbox: AnalyticsOutboxStore(db),
        context: _BrokenContext(),
        clock: () => 5000,
      );

      analytics.track('set_logged', <String, Object?>{'reps': 8});
      await Future<void>.delayed(Duration.zero);

      final List<AnalyticsEventPayload> rows = await AnalyticsOutboxStore(db).takeBatch();
      expect(rows.single.name, 'set_logged');
      expect(rows.single.props['reps'], 8);
      expect(rows.single.props.containsKey('device_id'), isFalse);
    });

    test('公共字段为空时也不影响隐私开关（关掉就一条都不记）', () async {
      final OutboxAnalytics analytics = OutboxAnalytics(
        outbox: AnalyticsOutboxStore(db),
        context: FakeAnalyticsContext(),
        clock: () => 5000,
      )..setEnabled(false);

      analytics.track('set_logged', <String, Object?>{'reps': 8});
      await Future<void>.delayed(Duration.zero);

      expect(await AnalyticsOutboxStore(db).takeBatch(), isEmpty);
    });
  });
}

/// 故意炸掉的 context：验证"埋点自己坏了不能吃掉事件"。
class _BrokenContext implements AnalyticsContext {
  @override
  Future<Map<String, Object?>> commonProps({required bool offline}) async =>
      throw StateError('数据库挂了');
}
