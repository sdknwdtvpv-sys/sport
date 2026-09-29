/// 练了么 · 埋点的公共字段（`docs/analytics.md` §2.1）
///
/// **这个文件补的是一个真实的窟窿**：在此之前 `OutboxAnalytics.track()` 只把调用方
/// 传进来的 props 原样入队 —— `device_id` / `session_id` / `app_version` / `platform` /
/// `schema_version` / `is_offline` 一个都没有。后果不是"报表难看"，而是：
///
///   * **北极星算不出来** —— 它的分母是"首次 `app_open` 的设备（按 `device_id` 去重）"，
///     没有 `device_id` 就没有分母
///   * **漏斗没法按设备归因** —— 谁在 24 小时内完成了训练，认不出是同一个人
///   * **发布门禁没法比版本** —— "`tap_count` 不高于上一版"需要 `app_version`
///
/// 所以这一层不是"锦上添花的字段"，是那份指标定义**能不能被算出来**的前提。
library;

import 'dart:math';

import '../data/analytics_meta_repository.dart';
import '../data/db.dart' show AnalyticsMetaData;
import '../core/app_info.dart';

/// 事件 schema 版本。**只增不改**（`docs/analytics.md` §2.1）。
/// 加字段 / 改字段含义时 +1，历史事件不变。
const int kAnalyticsSchemaVersion = 1;

/// 会话超时：30 分钟无事件即新会话（`docs/analytics.md` §2.1）。
const Duration kSessionTimeout = Duration(minutes: 30);

/// 公共字段的来源。
abstract class AnalyticsContext {
  /// 取当前应该附带的公共字段。
  ///
  /// [offline] 由调用方给（它来自同步队列的实时状态，不属于这里的职责）。
  Future<Map<String, Object?>> commonProps({required bool offline});
}

/// 真身：设备 ID / 会话 ID 落在 `analytics_meta` 表里。
class DeviceAnalyticsContext implements AnalyticsContext {
  DeviceAnalyticsContext({
    required AnalyticsMetaRepository repository,
    required String Function() platform,
    this.appVersion = kAppVersion,
  })  : _repo = repository,
        _platform = platform;

  final AnalyticsMetaRepository _repo;

  /// `android` / `ios`。注入而不是直接读 `Platform.isAndroid` ——
  /// 这样测试不用碰平台通道，而且桌面/CI 上跑也不会报出个 `macos` 往上送。
  final String Function() _platform;

  final String appVersion;

  @override
  Future<Map<String, Object?>> commonProps({required bool offline}) async {
    final AnalyticsMetaData row = await _repo.ensure();
    return <String, Object?>{
      'schema_version': kAnalyticsSchemaVersion,
      'device_id': row.deviceId,
      'session_id': row.sessionId,
      'user_id': null, // 游客态也上报（否则北极星分母缺失），但绝不带可识别信息
      'app_version': appVersion,
      'platform': _platform(),
      'is_offline': offline,
    };
  }
}

/// 测试用：字段固定、可注入，不碰数据库。
class FakeAnalyticsContext implements AnalyticsContext {
  FakeAnalyticsContext({
    this.deviceId = 'dev_test',
    this.sessionId = 'sess_test',
    this.appVersion = '0.0.0-test',
    this.platform = 'android',
    this.schemaVersion = kAnalyticsSchemaVersion,
  });

  final String deviceId;
  final String sessionId;
  final String appVersion;
  final String platform;
  final int schemaVersion;

  @override
  Future<Map<String, Object?>> commonProps({required bool offline}) async =>
      <String, Object?>{
        'schema_version': schemaVersion,
        'device_id': deviceId,
        'session_id': sessionId,
        'user_id': null,
        'app_version': appVersion,
        'platform': platform,
        'is_offline': offline,
      };
}

/// 生成一个匿名 ID（32 位十六进制）。
///
/// **不引入 uuid 依赖**：这个 ID 只需要"够随机、不与任何东西关联"，
/// 15 个随机字节足够（碰撞概率与 UUIDv4 同级）。依赖越少越好是这个项目的一贯取舍。
String newAnonymousId(Random random) {
  final StringBuffer b = StringBuffer();
  for (int i = 0; i < 16; i++) {
    b.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}
