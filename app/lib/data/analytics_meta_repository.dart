/// 练了么 · 埋点的本机身份与会话（`analytics_meta` 表）
///
/// 一行数据，三种身份：设备（`device_id`）、会话（`session_id`）、首次启动（`first_open_at`）。
///
/// **三件事的规矩**（都来自 `docs/analytics.md`）：
///   1. `device_id` 随机生成、与任何账号信息无关；同一台设备**永远不变**
///   2. `session_id` 30 分钟无事件就换一个 —— 会话是"这一段使用"，不是"这一次安装"
///   3. `first_open_at` 只在**第一次**写；`app_open.is_first_open` 就是"写之前它还是 null"
///
/// 这个仓库里"每次都把旧值原样带回去"的写法（见 ProfileRepository）容易漏列，
/// 所以这里刻意**只暴露语义动作**（[ensure] / [markFirstOpen]），不暴露"写一行"，
/// 调用方没法把别的字段写坏。
library;

import 'dart:math';

import 'package:drift/drift.dart' show InsertMode;

import '../analytics/analytics_context.dart';
import 'db.dart';

class AnalyticsMetaRepository {
  AnalyticsMetaRepository(this._db, {Random? random, int Function()? clock})
      : _random = random ?? Random(),
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase _db;
  final Random _random;
  final int Function() _clock;

  static const String _localId = 'local';

  /// 读这一行；没有就建（首次启动）。**会话过期的判断也在这里** ——
  /// 会话只该在"取公共字段"这一条路上推进，别处推容易漏。
  Future<AnalyticsMetaData> ensure() async {
    final int now = _clock();
    AnalyticsMetaData? row = await _row();
    if (row == null) {
      // ⚠️ 这里原来是 `return _write(...)` —— **并发下有真 bug**（真机抓到的）：
      // 冷启动时可能有两个事件同时要公共字段，两个 ensure() 都看到"还没有这一行"，
      // 于是各自生成一个 device_id：行里留最后一个，而**两条事件各带一个**。
      // 后果是北极星分母凭空多出台设备，而且没有任何东西会报错。
      //
      // 改成"**插入或忽略 + 回读**"：谁先写谁赢，两个调用方拿到的是同一行。
      // 输的那一方浪费一个随机数，无所谓；拿到不一致的身份才是问题。
      await _db.into(_db.analyticsMeta).insert(
            AnalyticsMetaData(
              id: _localId,
              deviceId: newAnonymousId(_random),
              sessionId: newAnonymousId(_random),
              sessionLastAt: now,
              firstOpenAt: null,
              updatedAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      row = await _row();
      if (row == null) {
        // 理论上到不了这里（要么插入成功、要么主键冲突）。真到了就抛，
        // 让上层把它记成 swallowedErrors —— 宁可这次事件少个字段，
        // 也不要给设备编一个假身份。
        throw StateError('analytics_meta 写入后读不回来');
      }
    }
    final bool expired = now - row.sessionLastAt > kSessionTimeout.inMilliseconds;
    return _write(
      deviceId: row.deviceId,
      sessionId: expired ? newAnonymousId(_random) : row.sessionId,
      sessionLastAt: now,
      firstOpenAt: row.firstOpenAt,
    );
  }

  /// 本设备是不是**第一次**打开（`app_open.is_first_open`）。
  ///
  /// 注意它读的是"当前还没记过首启时间"，所以调用顺序是：
  /// 先问 [isFirstOpen]，再在 `app_open` 入队之后调 [markFirstOpen]。
  Future<bool> isFirstOpen() async => (await _row())?.firstOpenAt == null;

  /// 记下首次启动时间。**只写一次**（已经写过就不动）。
  Future<void> markFirstOpen({int? atMs}) async {
    final AnalyticsMetaData row = await ensure();
    if (row.firstOpenAt != null) return;
    await _write(
      deviceId: row.deviceId,
      sessionId: row.sessionId,
      sessionLastAt: row.sessionLastAt,
      firstOpenAt: atMs ?? _clock(),
    );
  }

  Future<AnalyticsMetaData?> _row() => (_db.select(_db.analyticsMeta)
        ..where((t) => t.id.equals(_localId)))
      .getSingleOrNull();

  Future<AnalyticsMetaData> _write({
    required String deviceId,
    required String sessionId,
    required int sessionLastAt,
    required int? firstOpenAt,
  }) async {
    final AnalyticsMetaData data = AnalyticsMetaData(
      id: _localId,
      deviceId: deviceId,
      sessionId: sessionId,
      sessionLastAt: sessionLastAt,
      firstOpenAt: firstOpenAt,
      updatedAt: sessionLastAt,
    );
    await _db.into(_db.analyticsMeta).insertOnConflictUpdate(data);
    return data;
  }
}
