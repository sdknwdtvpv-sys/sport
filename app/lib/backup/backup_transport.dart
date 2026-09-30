/// 练了么 · 云备份的传输层
///
/// 和埋点传输层（`analytics/transport.dart`）长得像，但**失败处理恰好相反**：
///
///   * 埋点送不出去 → 静默丢弃（绝不能影响任何功能）
///   * 备份送不出去 → **必须让用户看见**（他以为数据已经安全了，其实没有）
///
/// 所以这里的方法**会抛** [BackupTransportException]，而不是返回 false。
/// 这是有意的：把失败做成返回值，早晚会有人在调用点忘记看。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 备份传输失败。[statusCode] 为 null 表示压根没连上（断网、超时、地址不对）。
class BackupTransportException implements Exception {
  const BackupTransportException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// 是不是"网络问题"（可以重试／换个网络）
  bool get isNetwork => statusCode == null;

  @override
  String toString() => 'BackupTransportException($message'
      '${statusCode == null ? '' : ' · HTTP $statusCode'})';
}

/// 云端那份备份的**元信息**：多大、什么时候更新的、有几台设备登记过。
///
/// **刻意不含内容** —— 想知道里面是什么就得 GET `/v1/backup` 把密文整包拉下来。
/// 界面上"云端：3.2 MB · 09-30 12:31"这一行只需要元信息，
/// 而它同时也是"这台设备之外有没有人写过"的唯一线索。
class CloudBackupInfo {
  const CloudBackupInfo({
    required this.bytes,
    required this.updatedAtMs,
    required this.devices,
  });

  /// 密文字节数（0 = 云端还没有备份）
  final int bytes;

  /// 服务端记的最后更新时间。**null = 还没备份过**
  final int? updatedAtMs;

  /// 登记过的设备数（这个数据我们不细究，只用来判断"是不是只有我"）
  final int devices;

  /// 云端到底有没有东西
  bool get hasBackup => updatedAtMs != null;
}

abstract class BackupTransport {
  /// 创建账号（幂等：已存在也算成功）。[accountId] 由恢复码导出，服务端只认这一串。
  Future<void> createAccount(String accountId);

  /// 上传密文信封，返回服务端记录的字节数。
  Future<int> putBackup({required String accountId, required String envelope});

  /// 取回密文信封。账号还没有备份时返回 null（404 不算错误）。
  Future<String?> getBackup(String accountId);

  /// 注销：账号、设备、备份一起删。
  Future<void> deleteAccount(String accountId);

  /// 问一下云端那份现在是什么状态（只读）。**账号不存在 → null**（不是错误）。
  Future<CloudBackupInfo?> backupInfo(String accountId);
}

/// 测试用：全内存，可以一键让它失败。
class FakeBackupTransport implements BackupTransport {
  FakeBackupTransport({this.failWith});

  /// 非 null 时所有方法都抛这个错
  BackupTransportException? failWith;

  /// account_id → 密文信封
  final Map<String, String> stored = <String, String>{};

  /// account_id → 服务端记的 updated_at。测试可以直接改大它，
  /// 模拟"**另一台设备刚备份过**"（那是这个字段唯一的用途）。
  final Map<String, int> updatedAt = <String, int>{};

  /// 登记过的设备数（默认 1）
  int devices = 1;

  final List<String> calls = <String>[];

  @override
  Future<void> createAccount(String accountId) async {
    calls.add('create:$accountId');
    if (failWith != null) throw failWith!;
    stored.putIfAbsent(accountId, () => '');
  }

  @override
  Future<int> putBackup({
    required String accountId,
    required String envelope,
  }) async {
    calls.add('put:$accountId');
    if (failWith != null) throw failWith!;
    stored[accountId] = envelope;
    final int bytes = utf8.encode(envelope).length;
    updatedAt[accountId] = DateTime.now().millisecondsSinceEpoch;
    return bytes;
  }

  @override
  Future<CloudBackupInfo?> backupInfo(String accountId) async {
    calls.add('info:$accountId');
    if (failWith != null) throw failWith!;
    if (!stored.containsKey(accountId)) return null;
    final int? at = updatedAt[accountId];
    return CloudBackupInfo(
      bytes: at == null ? 0 : utf8.encode(stored[accountId]!).length,
      updatedAtMs: at,
      devices: devices,
    );
  }

  @override
  Future<String?> getBackup(String accountId) async {
    calls.add('get:$accountId');
    if (failWith != null) throw failWith!;
    final String? envelope = stored[accountId];
    if (envelope == null || envelope.isEmpty) return null;
    return envelope;
  }

  @override
  Future<void> deleteAccount(String accountId) async {
    calls.add('delete:$accountId');
    if (failWith != null) throw failWith!;
    stored.remove(accountId);
    updatedAt.remove(accountId);
  }
}

/// 真身：说 `server/backend.mjs` 的那套接口。
///
/// 只用 `dart:io`，不引入 http 包 —— 这个项目只依赖了必需的东西。
/// 生产必须走 HTTPS：凭据（account_id）在 Authorization 头里。
class HttpBackupTransport implements BackupTransport {
  HttpBackupTransport({
    required this.baseUrl,
    HttpClient? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? HttpClient();

  /// 形如 `https://api.lianleme.app`（不带尾斜杠）
  final Uri baseUrl;
  final Duration timeout;
  final HttpClient _client;

  Uri _url(String path) => baseUrl.replace(path: path);

  @override
  Future<void> createAccount(String accountId) async {
    await _json('POST', '/v1/account', accountId, <String, Object?>{
      'account_id': accountId,
    }, accept: <int>[200, 201]);
  }

  @override
  Future<int> putBackup({
    required String accountId,
    required String envelope,
  }) async {
    final Map<String, Object?> body = await _json(
      'PUT',
      '/v1/backup',
      accountId,
      null,
      raw: envelope,
      contentType: 'application/octet-stream',
      accept: <int>[200],
    );
    final Object? bytes = body['bytes'];
    return bytes is int ? bytes : utf8.encode(envelope).length;
  }

  @override
  Future<String?> getBackup(String accountId) async {
    final HttpClientResponse res = await _send(
      'GET',
      '/v1/backup',
      accountId,
      body: null,
      contentType: null,
    );
    if (res.statusCode == 404) {
      await res.drain<void>();
      return null;
    }
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw BackupTransportException('取回备份失败', statusCode: res.statusCode);
    }
    return res.transform(utf8.decoder).join();
  }

  @override
  Future<void> deleteAccount(String accountId) async {
    await _json('DELETE', '/v1/account', accountId, null, accept: <int>[200]);
  }

  @override
  Future<CloudBackupInfo?> backupInfo(String accountId) async {
    final Map<String, Object?>? decoded = await _jsonOrNull(
      'GET',
      '/v1/account/me',
      accountId,
      accept404: true,
    );
    if (decoded == null) return null;
    final Object? bytes = decoded['bytes'];
    final Object? updatedAt = decoded['updatedAt'];
    final Object? devices = decoded['devices'];
    return CloudBackupInfo(
      bytes: bytes is int ? bytes : 0,
      updatedAtMs: updatedAt is int ? updatedAt : null,
      devices: devices is int ? devices : 1,
    );
  }

  void close() => _client.close(force: true);

  Future<Map<String, Object?>> _json(
    String method,
    String path,
    String accountId,
    Map<String, Object?>? body, {
    String? raw,
    String? contentType,
    required List<int> accept,
  }) async {
    final HttpClientResponse res = await _send(
      method,
      path,
      accountId,
      body: raw ?? (body == null ? null : jsonEncode(body)),
      contentType: contentType ?? (body == null ? null : 'application/json'),
    );
    final String text = await res.transform(utf8.decoder).join();
    if (!accept.contains(res.statusCode)) {
      throw BackupTransportException(
        _explain(res.statusCode, text),
        statusCode: res.statusCode,
      );
    }
    if (text.isEmpty) return const <String, Object?>{};
    final Object? decoded = jsonDecode(text);
    return decoded is Map<String, Object?> ? decoded : const <String, Object?>{};
  }

  /// 和 [_json] 一样，但**404 返回 null 而不是抛** —— "账号不存在"在业务上是
  /// 一种正常答案（恢复码抄错了、或者对面已经注销了），不该长成异常。
  Future<Map<String, Object?>?> _jsonOrNull(
    String method,
    String path,
    String accountId, {
    bool accept404 = false,
  }) async {
    final HttpClientResponse res =
        await _send(method, path, accountId, body: null, contentType: null);
    final String text = await res.transform(utf8.decoder).join();
    if (res.statusCode == 404 && accept404) return null;
    if (res.statusCode != 200) {
      throw BackupTransportException(_explain(res.statusCode, text),
          statusCode: res.statusCode);
    }
    if (text.isEmpty) return const <String, Object?>{};
    final Object? decoded = jsonDecode(text);
    return decoded is Map<String, Object?> ? decoded : const <String, Object?>{};
  }

  Future<HttpClientResponse> _send(
    String method,
    String path,
    String accountId, {
    required String? body,
    required String? contentType,
  }) async {
    try {
      final HttpClientRequest req = await _client.openUrl(method, _url(path));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accountId');
      if (contentType != null) {
        req.headers.set(HttpHeaders.contentTypeHeader, contentType);
      }
      if (body != null) req.write(body);
      return await req.close().timeout(timeout);
    } on TimeoutException {
      throw const BackupTransportException('连接超时 —— 检查一下网络');
    } on SocketException catch (e) {
      throw BackupTransportException('连不上服务器：${e.osError?.message ?? e.message}');
    } on HandshakeException {
      throw const BackupTransportException('安全连接失败（证书问题）');
    } on HttpException catch (e) {
      throw BackupTransportException('请求失败：${e.message}');
    }
  }

  /// 只把用户能理解的信息回给界面，**不带服务端内部细节**
  String _explain(int status, String body) {
    switch (status) {
      case 400:
        return '服务器说这份备份不合法';
      case 401:
        return '恢复码对不上这台服务器上的账号';
      case 403:
        return '服务器拒绝了这个请求';
      case 413:
        return '备份太大了，服务器不收';
      case 429:
        return '请求太频繁，过一会儿再试';
      default:
        if (status >= 500) return '服务器出错了（$status）';
        return '服务器返回了 $status';
    }
  }
}
