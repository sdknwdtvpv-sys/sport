/// 练了么 · 服务端计费客户端（M4a）：**把 M3 的服务端权益接进客户端**
///
/// 施工图：`docs/plan-membership-2026-10-10.md` §4（权益的真相在哪）、§8.1、§9 判据 4/12。
/// 这一层的职责只有三条：
///
///   1. **上送交易、以服务端为准**：iOS 购买/恢复成功后，把 StoreKit 2 的
///      `verificationData.serverVerificationData`（JWS）发给 `POST /v1/billing/verify`；
///      成功就用服务端返回的到期时间/环境覆盖本地估算。
///   2. **拉取权益、只延长不缩短**：启动与登录后 `GET /v1/billing/entitlement`，
///      按服务端状态合并进 `EntitlementRepository` —— 退款/撤销**立即降级**，
///      离线/未登录/失败则**保留本地**（离线可用是红线）。
///   3. **自建兑换码**：非 iOS 渠道把码发到 `POST /v1/billing/redeem`（iOS 不提供入口）。
///
/// 三条纪律：
///
///   * **不阻塞购买结果**：服务端慢/挂了/没登录，购买仍按本地成功返回，只在
///     `lastServerError` 里留一句可读原因（绝不把"已经扣款"说成失败）。
///   * **不留脏状态**：服务端失败不写半条权益；兑换失败也不改本地。
///   * **不记录凭据**：日志/事件里只有状态与商品，没有 JWS、没有码、没有令牌。
///
/// ⚠️ **M4c（开放购买）必须一起改政策**：这一版代码已经能把购买凭据上送服务端，
/// 但发版开关（`kUltraReleased == false`）仍然关着、用户买不到，且正式包没有配
/// 服务器地址（`cloudBackupBaseUrl == null`）→ 不会发任何请求，政策 §2.5 仍成立。
/// 开放购买时要按 `docs/privacy-facts.json` 的 `purchases` 与政策 §2.5 一起改。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

import '../backup/backup_config.dart';
import '../backup/login_session.dart';
import '../data/entitlement_repository.dart';
import 'billing_client.dart' show ultraProductForStoreId;
import 'entitlement.dart';

/// 服务端返回的一条权益（**服务端为准**的那份）。
class ServerEntitlement {
  const ServerEntitlement({
    required this.status,
    this.product,
    this.source,
    this.environment,
    this.expiresAtMs,
    this.revokedAtMs,
    this.refundedAtMs,
    this.updatedAtMs,
  });

  /// `none | active | expired | refunded | revoked`
  final String status;

  /// 商店商品 ID（三个 Ultra 之一），或兑换码的 `redeem`。
  final String? product;

  /// `apple | google | redeem`
  final String? source;

  /// `Sandbox | Production`（兑换码为 null）
  final String? environment;

  final int? expiresAtMs;
  final int? revokedAtMs;
  final int? refundedAtMs;
  final int? updatedAtMs;

  bool get isActive => status == 'active';

  static ServerEntitlement? fromApi(Object? raw) {
    if (raw is! Map) return null;
    final Object? status = raw['status'];
    if (status is! String) return null;
    final Object? ent = raw['entitlement'];
    if (ent == null) return ServerEntitlement(status: status);
    if (ent is! Map) return null;
    int? asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));
    String? asString(Object? v) => v is String && v.isNotEmpty ? v : null;
    return ServerEntitlement(
      status: status,
      product: asString(ent['product']),
      source: asString(ent['source']),
      environment: asString(ent['environment']),
      expiresAtMs: asInt(ent['expires_at']),
      revokedAtMs: asInt(ent['revoked_at']),
      refundedAtMs: asInt(ent['refunded_at']),
      updatedAtMs: asInt(ent['updated_at']),
    );
  }
}

/// 服务端调用失败。**message 是给人看的中文**；原始细节放 [detail]（不展示）。
class BillingServerException implements Exception {
  const BillingServerException(
    this.message, {
    this.statusCode,
    this.code,
    this.detail,
    this.retryAfterSec,
  });

  final String message;
  final int? statusCode;

  /// 服务端错误码（`sandbox_not_allowed` / `used` / `rate_limited` …）
  final String? code;
  final String? detail;

  /// 429 时服务端 `Retry-After` 的秒数（没有就是 null）
  final int? retryAfterSec;

  bool get isNetwork => statusCode == null;

  @override
  String toString() => 'BillingServerException($message'
      '${statusCode == null ? '' : ' · HTTP $statusCode'}${code == null ? '' : ' · $code'})';
}

/// 服务端 API 的可注入抽象（生产 = [HttpBillingServerApi]，测试 = 假实现）。
abstract class BillingServerApi {
  /// `GET /v1/billing/entitlement`（需要会话令牌）。没有权益 → `status = none`。
  Future<ServerEntitlement> fetchEntitlement(String token);

  /// `POST /v1/billing/verify`（body：`{"signedTransaction": JWS}`）。
  Future<ServerEntitlement> verifyTransaction({
    required String token,
    required String signedTransaction,
  });

  /// `POST /v1/billing/redeem`（body：`{"code": "…"}`）。
  Future<ServerEntitlement> redeemCode({required String token, required String code});

  void close();
}

/// 真实现：`dart:io`，**不引第三方 HTTP 包**（与云备份/账号传输层同一套写法）。
class HttpBillingServerApi implements BillingServerApi {
  HttpBillingServerApi({
    required this.baseUrl,
    HttpClient? client,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? HttpClient();

  final Uri baseUrl;
  final Duration timeout;
  final HttpClient _client;

  Uri _url(String path) => baseUrl.replace(path: path);

  @override
  Future<ServerEntitlement> fetchEntitlement(String token) async {
    final Map<String, Object?> body =
        await _json('GET', '/v1/billing/entitlement', token: token, accept: <int>[200]);
    return ServerEntitlement.fromApi(body) ?? const ServerEntitlement(status: 'none');
  }

  @override
  Future<ServerEntitlement> verifyTransaction({
    required String token,
    required String signedTransaction,
  }) async {
    final Map<String, Object?> body = await _json(
      'POST',
      '/v1/billing/verify',
      token: token,
      body: <String, Object?>{'signedTransaction': signedTransaction},
      accept: <int>[200],
    );
    return ServerEntitlement.fromApi(body) ?? const ServerEntitlement(status: 'none');
  }

  @override
  Future<ServerEntitlement> redeemCode({required String token, required String code}) async {
    final Map<String, Object?> body = await _json(
      'POST',
      '/v1/billing/redeem',
      token: token,
      body: <String, Object?>{'code': code},
      accept: <int>[200],
    );
    return ServerEntitlement.fromApi(body) ?? const ServerEntitlement(status: 'none');
  }

  @override
  void close() => _client.close(force: true);

  Future<Map<String, Object?>> _json(
    String method,
    String path, {
    required String token,
    Map<String, Object?>? body,
    required List<int> accept,
  }) async {
    try {
      final HttpClientRequest req = await _client
          .openUrl(method, _url(path))
          .timeout(timeout);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      req.headers.contentType = ContentType.json;
      if (body != null) req.write(jsonEncode(body));
      final HttpClientResponse res = await req.close().timeout(timeout);
      final String text = await res.transform(utf8.decoder).join().timeout(timeout);
      Map<String, Object?>? decoded;
      try {
        final Object? raw = jsonDecode(text);
        if (raw is Map) decoded = raw.cast<String, Object?>();
      } catch (_) {
        decoded = null;
      }
      if (accept.contains(res.statusCode)) return decoded ?? <String, Object?>{};
      throw BillingServerException(
        _readable(decoded?['error'], res.statusCode),
        statusCode: res.statusCode,
        code: decoded?['code']?.toString(),
        retryAfterSec: int.tryParse(res.headers.value(HttpHeaders.retryAfterHeader) ?? ''),
      );
    } on BillingServerException {
      rethrow;
    } on TimeoutException {
      throw const BillingServerException('连接服务器超时，先按本机记录显示。');
    } on SocketException catch (e) {
      throw BillingServerException('连不上服务器，先按本机记录显示。', detail: e.message);
    } on HttpException catch (e) {
      throw BillingServerException('和服务器通信失败，先按本机记录显示。', detail: e.message);
    } catch (e) {
      debugPrint('billing server request failed: ${e.runtimeType}');
      throw const BillingServerException('服务器请求失败，先按本机记录显示。');
    }
  }

  static String _readable(Object? error, int status) =>
      error is String && error.trim().isNotEmpty ? error : '服务器返回 HTTP $status';
}

/// 一次同步/上送的结果（**只用于可读提示，不影响购买是否成功**）。
enum ServerSyncStatus { synced, notLoggedIn, offline, rejected, none, skipped }

class ServerSyncResult {
  const ServerSyncResult(this.status, {this.message, this.entitlement});

  final ServerSyncStatus status;

  /// 可直接给用户看的一句（成功时为 null；失败时如实说明"先按本机记录显示"）。
  final String? message;

  /// 合并后本机最该生效的那条权益（没有就是 null）。
  final UltraEntitlement? entitlement;

  bool get ok => status == ServerSyncStatus.synced;
}

/// 兑换结果（四个状态码对应四句人话，**不糊成"兑换失败"**）。
enum RedeemStatus { success, notLoggedIn, invalidCode, notFound, used, expired, rateLimited, offline }

class RedeemResult {
  const RedeemResult(this.status, {this.message, this.entitlement, this.retryAfterSec});

  final RedeemStatus status;
  final String? message;
  final UltraEntitlement? entitlement;
  final int? retryAfterSec;

  bool get ok => status == RedeemStatus.success;
}

/// **服务端计费客户端**：把 API、会话令牌、本机权益仓储拼起来。
///
/// 它不持有界面状态，也不缓存"现在该给不给 Ultra" —— 那是 `EntitlementRepository.access()`
/// 的事；这里只负责**把服务端那份写进本机**（或失败时什么都不做）。
class BillingServerClient {
  BillingServerClient({
    required this.api,
    required this.sessionStore,
    required this.repository,
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 8),
  }) : _now = now ?? DateTime.now;

  final BillingServerApi api;
  final SessionStore sessionStore;
  final EntitlementRepository repository;
  final Duration timeout;
  final DateTime Function() _now;

  int get _nowMs => _now().millisecondsSinceEpoch;

  /// 最近一次服务端同步失败的可读原因（成功/没登录时为 null）。
  String? lastServerError;

  /// 最近一次服务端明确告诉我们的环境（Production / Sandbox；只记录，不落库）。
  String? lastEnvironment;

  Future<String?> _token() async {
    try {
      return (await sessionStore.read())?.token;
    } catch (_) {
      return null;
    }
  }

  /// 启动 / 登录后拉权益并合并。**没登录、没网、服务端挂了都不抛**。
  Future<ServerSyncResult> syncFromServer() async {
    final String? token = await _token();
    if (token == null || token.isEmpty) {
      return const ServerSyncResult(ServerSyncStatus.notLoggedIn);
    }
    try {
      final ServerEntitlement server =
          await api.fetchEntitlement(token).timeout(timeout);
      lastServerError = null;
      lastEnvironment = server.environment;
      if (server.status == 'none' || server.product == null) {
        await _log('server_none');
        return ServerSyncResult(ServerSyncStatus.none, entitlement: await repository.best(_nowMs));
      }
      // 后台同步：「只延长不缩短」（本地估算可能比服务端更晚，不缩短）。
      final UltraEntitlement? merged = await _apply(server);
      return ServerSyncResult(ServerSyncStatus.synced, entitlement: merged);
    } on BillingServerException catch (e) {
      lastServerError = e.message;
      return ServerSyncResult(
        e.statusCode == 401 ? ServerSyncStatus.notLoggedIn : ServerSyncStatus.offline,
        message: e.message,
        entitlement: await repository.best(_nowMs),
      );
    } catch (e) {
      lastServerError = '服务器同步失败，先按本机记录显示。';
      return ServerSyncResult(ServerSyncStatus.offline,
          message: lastServerError, entitlement: await repository.best(_nowMs));
    }
  }

  /// 上送一笔 iOS 交易（StoreKit 2 JWS）。服务端失败**不抛、不阻挡购买结果**。
  Future<ServerSyncResult> submitPurchase(String signedTransaction) async {
    if (signedTransaction.trim().isEmpty) {
      return const ServerSyncResult(ServerSyncStatus.skipped);
    }
    final String? token = await _token();
    if (token == null || token.isEmpty) {
      return const ServerSyncResult(ServerSyncStatus.notLoggedIn);
    }
    try {
      final ServerEntitlement server = await api
          .verifyTransaction(token: token, signedTransaction: signedTransaction)
          .timeout(timeout);
      lastServerError = null;
      lastEnvironment = server.environment;
      // 上送是**服务端为准**：服务端给的到期时间是真实值，哪怕比本地估算短。
      final UltraEntitlement? merged = await _apply(server, authoritative: true);
      return ServerSyncResult(ServerSyncStatus.synced, entitlement: merged);
    } on BillingServerException catch (e) {
      lastServerError = e.message;
      final ServerSyncStatus status = switch (e.statusCode) {
        401 => ServerSyncStatus.notLoggedIn,
        400 => e.code == 'sandbox_not_allowed'
            ? ServerSyncStatus.rejected
            : ServerSyncStatus.rejected,
        _ => ServerSyncStatus.offline,
      };
      return ServerSyncResult(status, message: e.message);
    } catch (e) {
      debugPrint('billing verify failed: ${e.runtimeType}');
      lastServerError = '购买已在本机生效；服务端同步失败，先按本机记录显示。';
      return ServerSyncResult(ServerSyncStatus.offline, message: lastServerError);
    }
  }

  /// 自建兑换码核销（非 iOS 渠道）。成功才写权益；失败给**准确状态**。
  Future<RedeemResult> redeem(String code) async {
    final String? token = await _token();
    if (token == null || token.isEmpty) {
      return const RedeemResult(RedeemStatus.notLoggedIn, message: '兑换需要先登录（设置 → 数据与备份 → 账号）。');
    }
    try {
      final ServerEntitlement server =
          await api.redeemCode(token: token, code: code).timeout(timeout);
      lastServerError = null;
      lastEnvironment = server.environment;
      // 兑换也是服务端为准（它刚写的那条权益）。
      final UltraEntitlement? merged = await _apply(server, authoritative: true);
      return RedeemResult(RedeemStatus.success, entitlement: merged, message: '兑换成功，Ultra 已开通。');
    } on BillingServerException catch (e) {
      lastServerError = e.message;
      switch (e.statusCode) {
        case 401:
          return const RedeemResult(RedeemStatus.notLoggedIn,
              message: '兑换需要先登录（设置 → 数据与备份 → 账号）。');
        case 404:
          return RedeemResult(RedeemStatus.notFound, message: e.message);
        case 409:
          return RedeemResult(RedeemStatus.used, message: e.message);
        case 410:
          return RedeemResult(RedeemStatus.expired, message: e.message);
        case 429:
          return RedeemResult(RedeemStatus.rateLimited,
              message: e.message, retryAfterSec: e.retryAfterSec);
        case 400:
          return RedeemResult(RedeemStatus.invalidCode, message: e.message);
        default:
          return RedeemResult(RedeemStatus.offline, message: e.message);
      }
    } catch (e) {
      debugPrint('billing redeem failed: ${e.runtimeType}');
      lastServerError = '兑换请求失败，请稍后再试。';
      return RedeemResult(RedeemStatus.offline, message: lastServerError);
    }
  }

  void close() => api.close();

  // ── 合并规则 ────────────────────────────────────────────────────────
  //
  //  * **active**：只延长不缩短（服务端到期更晚才更新；终身赢过有期限）；
  //    本地已有终态（退款/撤销）时**新建一行**，绝不把终态复活；
  //  * **refunded / revoked**：立即给本地对应行打上终态时间（降级）；
  //  * **expired**：以服务端到期为准（可以缩短 —— 服务端说失效了就是失效了）；
  //  * **none / 未知**：不动本地（离线时服务端没记录不代表该删本机权益）。
  Future<UltraEntitlement?> _apply(ServerEntitlement server, {bool authoritative = false}) async {
    final UltraProduct? product = _mapProduct(server.product);
    if (product == null) {
      await _log('server_unknown_product:${server.product}');
      return repository.best(_nowMs);
    }
    final UltraSource source = _mapSource(server.source);
    final int at = _nowMs;
    final List<UltraEntitlement> all = await repository.all();
    final List<UltraEntitlement> candidates = all
        .where((UltraEntitlement e) => e.source == source && e.product == product)
        .toList(growable: false);

    switch (server.status) {
      case 'active':
        final UltraEntitlement? existing = _bestCandidate(candidates);
        final UltraEntitlement merged;
        if (existing == null) {
          merged = UltraEntitlement(
            id: _serverId(server, at),
            product: product,
            source: source,
            purchasedAtMs: server.updatedAtMs ?? at,
            expiresAtMs: server.expiresAtMs,
            lastVerifiedAtMs: at,
          );
        } else if (authoritative) {
          // 刚上送的交易：服务端那份就是真实值（可能比本地估算短）。
          merged = existing.copyWith(
            expiresAtMs: server.expiresAtMs,
            clearExpiresAt: server.expiresAtMs == null,
            lastVerifiedAtMs: at,
          );
        } else {
          // 后台同步：「只延长不缩短」；null = 终身（最大）。
          final bool lifetime = server.expiresAtMs == null || existing.expiresAtMs == null;
          final int? expiry = lifetime
              ? null
              : (server.expiresAtMs! > existing.expiresAtMs!
                  ? server.expiresAtMs
                  : existing.expiresAtMs);
          merged = existing.copyWith(
            expiresAtMs: expiry,
            clearExpiresAt: lifetime,
            lastVerifiedAtMs: at,
          );
        }
        await repository.upsert(merged);
        await _log('server_sync:active${_envSuffix(server)}');
        return repository.best(at);

      case 'refunded':
      case 'revoked':
        final List<UltraEntitlement> live =
            candidates.where((UltraEntitlement e) => !e.isTerminal).toList(growable: false);
        if (live.isEmpty) {
          await repository.upsert(UltraEntitlement(
            id: _serverId(server, at),
            product: product,
            source: source,
            purchasedAtMs: server.updatedAtMs ?? at,
            expiresAtMs: server.expiresAtMs,
            revokedAtMs: server.status == 'revoked' ? (server.revokedAtMs ?? at) : null,
            refundedAtMs: server.status == 'refunded' ? (server.refundedAtMs ?? at) : null,
            lastVerifiedAtMs: at,
          ));
        } else {
          for (final UltraEntitlement e in live) {
            await repository.upsert(e.copyWith(
              revokedAtMs: server.status == 'revoked' ? (server.revokedAtMs ?? at) : null,
              refundedAtMs: server.status == 'refunded' ? (server.refundedAtMs ?? at) : null,
              lastVerifiedAtMs: at,
            ));
          }
        }
        await _log('server_sync:${server.status}${_envSuffix(server)}');
        return repository.best(at);

      case 'expired':
        for (final UltraEntitlement e in candidates.where((UltraEntitlement e) => !e.isTerminal)) {
          await repository.upsert(e.copyWith(
            expiresAtMs: server.expiresAtMs ?? at,
            lastVerifiedAtMs: at,
          ));
        }
        await _log('server_sync:expired${_envSuffix(server)}');
        return repository.best(at);

      default:
        await _log('server_sync:${server.status}');
        return repository.best(at);
    }
  }

  static UltraEntitlement? _bestCandidate(List<UltraEntitlement> list) {
    UltraEntitlement? best;
    for (final UltraEntitlement e in list) {
      if (e.isTerminal) continue;
      if (best == null) {
        best = e;
      } else if (best.expiresAtMs == null) {
        continue; // 终身已经最大
      } else if (e.expiresAtMs == null ||
          (e.expiresAtMs != null && e.expiresAtMs! > best.expiresAtMs!)) {
        best = e;
      }
    }
    return best;
  }

  static UltraProduct? _mapProduct(String? product) {
    if (product == null) return null;
    final UltraProduct? byStoreId = ultraProductForStoreId(product);
    if (byStoreId != null) return byStoreId;
    if (product == 'redeem') {
      // 兑换码在服务端只记天数、不记档位；本机显示用（到期以服务端 expires_at 为准）。
      return UltraProduct.yearly;
    }
    return null;
  }

  static UltraSource _mapSource(String? source) {
    switch (source) {
      case 'apple':
        return UltraSource.apple;
      case 'google':
        return UltraSource.google;
      case 'redeem':
        return UltraSource.redeemCode;
      default:
        return UltraSource.apple;
    }
  }

  static String _serverId(ServerEntitlement s, int at) =>
      'server:${s.source ?? 'unknown'}:${s.product ?? 'unknown'}:${s.updatedAtMs ?? at}';

  static String _envSuffix(ServerEntitlement s) =>
      s.environment == null ? '' : ' env=${s.environment}';

  Future<void> _log(String kind) => repository.logEvent(kind, atMs: _nowMs);
}

/// 生产装配：**同一个后端**（云备份/账号/计费都在 `/v1/*` 下），所以复用
/// `LIANLEME_BACKUP_URL`；编译期还要同时给 `LIANLEME_BACKUP_DISCLOSED=true`（政策已按
/// "启用云备份"改写过的显式声明）—— 少任何一个，[cloudBackupBaseUrl] 都是 null，
/// 客户端纯本地（离线红线，且不会发出任何请求）。
///
/// ⚠️ 这里刻意复用云备份那个 URL 与"政策已披露"开关：M4a 还不是正式售卖版本，
/// 正式开放购买（M4c）时要重新审视这两个开关与政策 §2.5 的关系。
BillingServerClient? billingServerClientFromConfig({
  required EntitlementRepository repository,
  required SessionStore sessionStore,
  DateTime Function()? now,
  Duration timeout = const Duration(seconds: 8),
}) {
  final Uri? base = cloudBackupBaseUrl;
  if (base == null) return null;
  return BillingServerClient(
    api: HttpBillingServerApi(baseUrl: base, timeout: timeout),
    sessionStore: sessionStore,
    repository: repository,
    now: now,
    timeout: timeout,
  );
}
