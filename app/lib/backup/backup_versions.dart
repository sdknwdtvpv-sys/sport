/// 练了么 · 云备份多版本 API（M4b / Sprint 6 客户端）
///
/// 服务端口径见 `docs/backend-design.md` §十；这一层只做三件事：
///
///   * `GET /v1/billing/backups` 列版本（不含 blob）—— **只有 Ultra 才看得见多份**；
///   * `GET /v1/backup/versions/:seq` 取某一版的**密文信封**（解密仍在客户端做）；
///   * `POST /v1/billing/backups/restore` 把某一版设为云端最新（**幂等**）。
///
/// 三条边界：
///   1. 这些端点要**会话令牌**（`auth_session.token`），不是设备凭据 `account_id`；
///   2. **没有权益时不发请求** —— 页面在这一层之前就判掉了（免费用户不碰网络）；
///   3. 服务端按自己的权益判配额；这里的 `ultra` 只是拿来显示/防呆，**不作为授权依据**。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../backup/backup_config.dart';
import '../backup/login_session.dart';

/// 一个备份版本（**不含内容**）。
class CloudBackupVersion {
  const CloudBackupVersion({
    required this.seq,
    required this.bytes,
    required this.createdAtMs,
    required this.isLatest,
  });

  final int seq;
  final int bytes;
  final int createdAtMs;
  final bool isLatest;
}

/// 服务端算出来的配额（只用于界面提示，**授权以服务端为准**）。
class BackupVersionLimits {
  const BackupVersionLimits({
    required this.maxVersions,
    required this.maxBlobBytes,
    required this.maxTotalBytes,
  });

  final int maxVersions;
  final int maxBlobBytes;
  final int maxTotalBytes;
}

class BackupVersionList {
  const BackupVersionList({required this.ultra, required this.versions, required this.limits});

  final bool ultra;
  final List<CloudBackupVersion> versions;
  final BackupVersionLimits limits;
}

/// 版本 API 的可读错误（`statusCode` 为 null = 没连上/超时）。
class BackupVersionException implements Exception {
  const BackupVersionException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isNetwork => statusCode == null;
  bool get isNotLoggedIn => statusCode == 401;
  bool get needsUltra => statusCode == 403;

  @override
  String toString() => 'BackupVersionException($message'
      '${statusCode == null ? '' : ' · HTTP $statusCode'})';
}

/// 可注入抽象：生产 = [HttpBackupVersionApi]；测试 = 假实现（不联网）。
abstract class BackupVersionApi {
  Future<BackupVersionList> list();

  /// 返回**密文信封**（与 `PUT /v1/backup` 时上传的字符串同一形态），解密在客户端。
  Future<String> download(int seq);

  /// 把某一版设为云端最新（幂等）。
  Future<void> restore(int seq);

  void close();
}

/// 真实现：`dart:io`，零新依赖。
class HttpBackupVersionApi implements BackupVersionApi {
  HttpBackupVersionApi({
    required this.baseUrl,
    required this.tokenProvider,
    HttpClient? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? HttpClient();

  final Uri baseUrl;

  /// 每次请求前取一次会话令牌（登录状态可能在这中间变）。
  final Future<String?> Function() tokenProvider;
  final Duration timeout;
  final HttpClient _client;

  Uri _url(String path) => baseUrl.replace(path: path);

  Future<String> _token() async {
    final String? t = await tokenProvider();
    if (t == null || t.isEmpty) {
      throw const BackupVersionException('云备份多版本需要先登录（设置 → 数据与备份 → 账号）。', statusCode: 401);
    }
    return t;
  }

  @override
  Future<BackupVersionList> list() async {
    final String token = await _token();
    final String text = await _request('GET', '/v1/billing/backups', token: token);
    final Map<String, Object?> body = _decodeJson(text);
    final List<CloudBackupVersion> versions = ((body['versions'] as List<Object?>?) ?? <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) => CloudBackupVersion(
              seq: _asInt(m['seq']) ?? 0,
              bytes: _asInt(m['bytes']) ?? 0,
              createdAtMs: _asInt(m['created_at']) ?? 0,
              isLatest: m['is_latest'] == true,
            ))
        .where((CloudBackupVersion v) => v.seq > 0)
        .toList(growable: false);
    final Map<Object?, Object?> limits = (body['limits'] as Map<Object?, Object?>?) ?? const <Object?, Object?>{};
    return BackupVersionList(
      ultra: body['ultra'] == true,
      versions: versions,
      limits: BackupVersionLimits(
        maxVersions: _asInt(limits['max_versions']) ?? 1,
        maxBlobBytes: _asInt(limits['max_blob_bytes']) ?? 8 * 1024 * 1024,
        maxTotalBytes: _asInt(limits['max_total_bytes']) ?? 8 * 1024 * 1024,
      ),
    );
  }

  @override
  Future<String> download(int seq) async {
    final String token = await _token();
    return _request('GET', '/v1/backup/versions/$seq', token: token);
  }

  @override
  Future<void> restore(int seq) async {
    final String token = await _token();
    await _request(
      'POST',
      '/v1/billing/backups/restore',
      token: token,
      body: <String, Object?>{'seq': seq},
    );
  }

  @override
  void close() => _client.close(force: true);

  Future<String> _request(
    String method,
    String path, {
    required String token,
    Map<String, Object?>? body,
  }) async {
    try {
      final HttpClientRequest req = await _client.openUrl(method, _url(path)).timeout(timeout);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final HttpClientResponse res = await req.close().timeout(timeout);
      final String text = await res.transform(utf8.decoder).join().timeout(timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) return text;
      String message = switch (res.statusCode) {
        401 => '登录状态已失效，请重新登录后再看备份历史。',
        403 => '云备份多版本是 Ultra 权益；当前只保留最新 1 份。',
        404 => '这个备份版本不存在（可能已被清理）。',
        413 => '备份太大，超过了当前档位的单份上限。',
        409 => '账号云备份空间不够了（超过总配额）。',
        _ => '服务器返回 HTTP ${res.statusCode}',
      };
      try {
        final Object? decoded = jsonDecode(text);
        if (decoded is Map && decoded['error'] is String) message = decoded['error'] as String;
      } catch (_) {
        // 保留上面那句兜底
      }
      throw BackupVersionException(message, statusCode: res.statusCode);
    } on BackupVersionException {
      rethrow;
    } on TimeoutException {
      throw const BackupVersionException('连接服务器超时，先按本机记录显示。');
    } on SocketException {
      throw const BackupVersionException('连不上服务器，先按本机记录显示。');
    } on HttpException {
      throw const BackupVersionException('和服务器通信失败，先按本机记录显示。');
    } catch (e) {
      throw BackupVersionException('备份历史请求失败：${e.runtimeType}');
    }
  }

  static Map<String, Object?> _decodeJson(String text) {
    try {
      final Object? raw = jsonDecode(text);
      if (raw is Map) return raw.cast<String, Object?>();
    } catch (_) {
      // 落到下面统一抛
    }
    throw const BackupVersionException('服务器返回的不是预期的 JSON。');
  }

  static int? _asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));
}

/// 生产装配：没配服务器地址（正式包）或没登录时返回 null。
///
/// 页面在"没有权益"时**连这个方法都不该调** —— 免费用户不该因为这一屏产生网络请求。
BackupVersionApi? backupVersionsFromConfig({required SessionStore sessionStore}) {
  final Uri? base = cloudBackupBaseUrl;
  if (base == null) return null;
  return HttpBackupVersionApi(
    baseUrl: base,
    tokenProvider: () async => (await sessionStore.read())?.token,
  );
}
