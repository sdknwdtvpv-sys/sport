/// 测试用**假服务端计费 API + 假会话存储**（M4a）
///
/// 让"上送 JWS / 服务端为准 / 失败回退 / 兑换状态码"全部可测，且**不联网**。
library;

import 'dart:typed_data';

import 'package:lianleme/backup/login_session.dart';
import 'package:lianleme/billing/billing_server.dart';

/// 内存会话：默认"没登录"；[loggedIn] 造一个已登录的。
class FakeSessionStore implements SessionStore {
  FakeSessionStore({this.session});

  StoredSession? session;

  factory FakeSessionStore.loggedIn({
    String token = 'lm1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    String accountId = 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
  }) =>
      FakeSessionStore(
        session: StoredSession(
          token: token,
          email: 'tester@example.com',
          accountId: accountId,
          accountKey: Uint8List.fromList(List<int>.filled(16, 7)),
          saltHex: '00' * 32,
          kdf: '{"alg":"argon2id"}',
          loginAtMs: 1760000000000,
        ),
      );

  @override
  Future<StoredSession?> read() async => session;

  @override
  Future<void> write(StoredSession value) async => session = value;

  @override
  Future<void> clear() async => session = null;
}

/// 服务端给的一条权益（默认：生产环境的年订阅、30 天后到期）。
ServerEntitlement serverEntitlement({
  String status = 'active',
  String? product = 'com.sdknwdtvpv.lianleme.ultra.yearly',
  String? source = 'apple',
  String? environment = 'Production',
  int? expiresAtMs,
  int? revokedAtMs,
  int? refundedAtMs,
  int? updatedAtMs,
}) =>
    ServerEntitlement(
      status: status,
      product: product,
      source: source,
      environment: environment,
      expiresAtMs: expiresAtMs,
      revokedAtMs: revokedAtMs,
      refundedAtMs: refundedAtMs,
      updatedAtMs: updatedAtMs,
    );

/// 假服务端：记录调用、可排定返回/抛错。
class FakeBillingServerApi implements BillingServerApi {
  ServerEntitlement fetchResponse = serverEntitlement(status: 'none', product: null);
  ServerEntitlement verifyResponse = serverEntitlement(expiresAtMs: 1800000000000);
  ServerEntitlement redeemResponse = serverEntitlement(
    product: 'redeem',
    source: 'redeem',
    environment: null,
    expiresAtMs: 1800000000000,
  );

  BillingServerException? fetchError;
  BillingServerException? verifyError;
  BillingServerException? redeemError;

  final List<String> calls = <String>[];
  final List<String> verifiedJws = <String>[];
  final List<String> redeemedCodes = <String>[];
  bool closed = false;

  @override
  Future<ServerEntitlement> fetchEntitlement(String token) async {
    calls.add('fetch:$token');
    if (fetchError != null) throw fetchError!;
    return fetchResponse;
  }

  @override
  Future<ServerEntitlement> verifyTransaction({
    required String token,
    required String signedTransaction,
  }) async {
    calls.add('verify');
    verifiedJws.add(signedTransaction);
    if (verifyError != null) throw verifyError!;
    return verifyResponse;
  }

  @override
  Future<ServerEntitlement> redeemCode({required String token, required String code}) async {
    calls.add('redeem');
    redeemedCodes.add(code);
    if (redeemError != null) throw redeemError!;
    return redeemResponse;
  }

  @override
  void close() => closed = true;
}
