/// 练了么 · 埋点上报的传输层
///
/// 把"怎么送出去"抽出来，刷写逻辑就能在测试里用假传输完整覆盖 ——
/// 而真实的 HTTP 实现也能靠**本地起一个 HttpServer** 来验证，
/// 不需要真的联网、不需要后端就位。
library;

import 'dart:convert';
import 'dart:io';

import 'outbox.dart';

abstract class AnalyticsTransport {
  /// 送一批事件。返回 true 表示服务端已接收。
  ///
  /// 实现**不得抛异常** —— 埋点失败绝不能影响任何功能。
  Future<bool> send(List<AnalyticsEventPayload> batch);
}

/// 测试用：可控成功 / 失败，并记下收到的每一批
class FakeAnalyticsTransport implements AnalyticsTransport {
  FakeAnalyticsTransport({this.succeed = true});

  bool succeed;

  /// 收到的批次（每次 send 追加一条）
  final List<List<AnalyticsEventPayload>> received = <List<AnalyticsEventPayload>>[];

  /// 所有收到过的事件，按顺序摊平
  List<AnalyticsEventPayload> get allReceived =>
      received.expand((List<AnalyticsEventPayload> b) => b).toList();

  @override
  Future<bool> send(List<AnalyticsEventPayload> batch) async {
    received.add(batch);
    return succeed;
  }
}

/// 真身：POST 一个 JSON 到 [endpoint]。
///
/// **2026-09-30 已在真机上端到端验证过**（Redmi flourite → `adb reverse` → 本机收集端）：
/// 9 次冷启动收到 9 条 `app_open`、1 台设备、无重复投递；
/// 反向对照（不带地址的正式包）发出 0 条。做法与结果见 `docs/analytics.md` §10。
/// 在此之前这里写的是"没有后端，只在本地环回服务器上验证过"—— 那句话已经过期了。
class HttpAnalyticsTransport implements AnalyticsTransport {
  HttpAnalyticsTransport({
    required this.endpoint,
    HttpClient? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? HttpClient();

  final Uri endpoint;
  final Duration timeout;
  final HttpClient _client;

  @override
  Future<bool> send(List<AnalyticsEventPayload> batch) async {
    if (batch.isEmpty) return true;
    try {
      final HttpClientRequest req = await _client.postUrl(endpoint);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(<String, Object?>{
        'events': batch.map((AnalyticsEventPayload e) => e.toJson()).toList(),
      }));
      final HttpClientResponse res = await req.close().timeout(timeout);
      // 一定要把响应体读完，否则连接不会释放
      await res.drain<void>();
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      // 网络错、超时、序列化错 —— 一律当作"没送成功"，绝不向上抛
      return false;
    }
  }

  void close() => _client.close(force: true);
}
