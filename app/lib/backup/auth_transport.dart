/// 练了么 · 账号的网络通道（注册 / 登录 / 验证码 / 改口令 / 重置 / 注销）
///
/// 与 `backup_transport.dart` 同一套约定，**故意不抽公共基类**（两条通道的错误话术不同：
/// 备份那条说"服务端上没有这个账号"，登录这条得说"邮箱或口令不对"）：
///
///   * **失败一律抛** [AuthTransportException]，不返回 `false`。把失败做成返回值，
///     早晚会有人在调用点忘记看 —— 而登录失败装作成功，用户会以为"登进去了"。
///   * **只依赖 `dart:io` 的 HttpClient**，不引 `http` 包。
///   * **可以注入 HttpClient 与超时**，所以能用假传输把界面测出真行为。
///   * **404 不是错误**（"这个账号还没绑邮箱"是一种合法答案），由各方法自己解释。
///
/// ⚠️ 这个文件**不发口令**：它只发 `authVerifier` 与 `wrapped`（都不是口令派生的可逆值）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 通道层的错误。`statusCode == null` 表示**根本没连上**（网络/超时/证书）。
class AuthTransportException implements Exception {
  const AuthTransportException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// 没连上（可以提示"检查网络"），而不是服务端明确拒绝
  bool get isNetwork => statusCode == null;

  @override
  String toString() => 'AuthTransportException($statusCode): $message';
}

/// `POST /v1/auth/salt` 的答案：这个邮箱的 KDF 盐与参数（**不是秘密**）。
class AuthSalt {
  const AuthSalt({required this.saltHex, required this.kdf});

  final String saltHex;

  /// 服务端原样保管的 KDF 参数（JSON 字符串）；认不出来时由算法层回落到默认值
  final String kdf;
}

/// 注册/登录/重置之后服务端给的东西。
class AuthSessionPayload {
  const AuthSessionPayload({
    required this.accountId,
    required this.token,
    this.wrapped,
    this.saltHex,
    this.kdf,
  });

  final String accountId;

  /// 会话令牌（64 位十六进制）—— 之后的备份、注销都带它
  final String token;

  /// 被 KEK 包起来的账号密钥（注册时不回，登录/重置时回）
  final String? wrapped;
  final String? saltHex;
  final String? kdf;
}

abstract class AuthTransport {
  /// 取这个邮箱的盐（不存在的邮箱也会回一个形状一样的假盐）
  Future<AuthSalt> salt({required String email});

  /// 发验证码。[purpose] 是 `register` 或 `reset`
  Future<void> sendCode({required String email, required String purpose});

  Future<AuthSessionPayload> register({
    required String email,
    required String code,
    required String authVerifier,
    required String wrapped,
    required String accountId,
    required String saltHex,
    required String kdf,
    String? deviceId,
    String? deviceName,
  });

  Future<AuthSessionPayload> login({
    required String email,
    required String authVerifier,
    String? deviceId,
    String? deviceName,
  });

  /// 忘口令：验证码 + **恢复码算出来的 accountId** → 设新口令
  Future<AuthSessionPayload> reset({
    required String email,
    required String code,
    required String accountId,
    required String authVerifier,
    required String wrapped,
    required String saltHex,
    required String kdf,
    String? deviceId,
  });

  Future<void> changePassword({
    required String token,
    required String currentAuthVerifier,
    required String authVerifier,
    required String wrapped,
    required String saltHex,
    required String kdf,
  });

  Future<void> logout(String token);

  /// 注销账号：账号 + 云端备份 + 邮箱绑定一起删（合规要求）
  Future<void> deleteAccount(String token);
}

/// 32 字节的假盐（64 个十六进制字符）—— 写成字面量，因为常量里不能做字符串乘法
const String _fakeSaltHex =
    '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';

/// 内存假传输：给界面与会话逻辑的测试用。可以一键让某个方法失败。
class FakeAuthTransport implements AuthTransport {
  FakeAuthTransport({this.saltHex = _fakeSaltHex, this.kdf = '{"alg":"argon2id"}'});

  String saltHex;
  String kdf;

  /// 每次调用记一笔：`方法名 + 关键参数`（断言"一个字节都没发出去"时要用）
  final List<String> calls = <String>[];

  /// 让某个方法抛错（键是方法名）；`null` = 不失败
  final Map<String, AuthTransportException> failWith = <String, AuthTransportException>{};

  /// 服务端"记得"的包裹与凭据：登录时用它判断口令对不对
  String? registeredEmail;
  String accountId = 'a' * 64;
  String wrapped = 'wrapped-stub';
  /// 令牌形状与服务端一致（`lm1_` + 64 位十六进制）—— 形状对不上，测试就测不出真问题
  String token = 'lm1_${'a' * 64}';

  /// 让 register/login 返回别的 accountId（测"服务端把别人的包裹塞给我"）
  String? overrideAccountIdOnLogin;

  void _maybeFail(String method) {
    final AuthTransportException? e = failWith[method];
    if (e != null) throw e;
  }

  @override
  Future<AuthSalt> salt({required String email}) async {
    calls.add('salt:$email');
    _maybeFail('salt');
    return AuthSalt(saltHex: saltHex, kdf: kdf);
  }

  @override
  Future<void> sendCode({required String email, required String purpose}) async {
    calls.add('code:$email:$purpose');
    _maybeFail('sendCode');
  }

  @override
  Future<AuthSessionPayload> register({
    required String email,
    required String code,
    required String authVerifier,
    required String wrapped,
    required String accountId,
    required String saltHex,
    required String kdf,
    String? deviceId,
    String? deviceName,
  }) async {
    calls.add('register:$email:$code');
    _maybeFail('register');
    registeredEmail = email;
    this.accountId = accountId;
    this.wrapped = wrapped;
    return AuthSessionPayload(accountId: accountId, token: token);
  }

  @override
  Future<AuthSessionPayload> login({
    required String email,
    required String authVerifier,
    String? deviceId,
    String? deviceName,
  }) async {
    calls.add('login:$email');
    _maybeFail('login');
    return AuthSessionPayload(
      accountId: overrideAccountIdOnLogin ?? accountId,
      token: token,
      wrapped: wrapped,
      saltHex: saltHex,
      kdf: kdf,
    );
  }

  @override
  Future<AuthSessionPayload> reset({
    required String email,
    required String code,
    required String accountId,
    required String authVerifier,
    required String wrapped,
    required String saltHex,
    required String kdf,
    String? deviceId,
  }) async {
    calls.add('reset:$email:$code');
    _maybeFail('reset');
    this.wrapped = wrapped;
    return AuthSessionPayload(accountId: accountId, token: token, wrapped: wrapped);
  }

  @override
  Future<void> changePassword({
    required String token,
    required String currentAuthVerifier,
    required String authVerifier,
    required String wrapped,
    required String saltHex,
    required String kdf,
  }) async {
    calls.add('changePassword');
    _maybeFail('changePassword');
    this.wrapped = wrapped;
  }

  @override
  Future<void> logout(String token) async {
    calls.add('logout');
    _maybeFail('logout');
  }

  @override
  Future<void> deleteAccount(String token) async {
    calls.add('deleteAccount');
    _maybeFail('deleteAccount');
    registeredEmail = null;
  }
}

/// 真身：走 HTTPS 打 `server/auth.mjs` 的那几个接口。
class HttpAuthTransport implements AuthTransport {
  HttpAuthTransport({required this.baseUrl, HttpClient? client, this.timeout = const Duration(seconds: 20)})
      : _client = client ?? HttpClient();

  final Uri baseUrl;
  final HttpClient _client;
  final Duration timeout;

  /// 关掉底下的连接池。测试里必须调 —— 不关的话 HTTP keep-alive 会让测试进程
  /// 挂着不退出（`cloud_backup_test` 那边是同一条理由）。
  void close() => _client.close(force: true);

  @override
  Future<AuthSalt> salt({required String email}) async {
    final Map<String, Object?> body = await _json(
      'POST',
      '/v1/auth/salt',
      payload: <String, Object?>{'email': email},
    );
    final Object? salt = body['salt'];
    final Object? kdf = body['kdf'];
    if (salt is! String || kdf is! String) {
      throw const AuthTransportException('服务端没有给出盐（版本对不上？）');
    }
    return AuthSalt(saltHex: salt, kdf: kdf);
  }

  @override
  Future<void> sendCode({required String email, required String purpose}) async {
    await _json('POST', '/v1/auth/code', payload: <String, Object?>{'email': email, 'purpose': purpose});
  }

  @override
  Future<AuthSessionPayload> register({
    required String email,
    required String code,
    required String authVerifier,
    required String wrapped,
    required String accountId,
    required String saltHex,
    required String kdf,
    String? deviceId,
    String? deviceName,
  }) async {
    final Map<String, Object?> body = await _json('POST', '/v1/auth/register', payload: <String, Object?>{
      'email': email,
      'code': code,
      'verifier': authVerifier,
      'wrapped': wrapped,
      'account_id': accountId,
      'salt': saltHex,
      'kdf': kdf,
      'device_id': deviceId,
      'device_name': deviceName,
    });
    return _session(body);
  }

  @override
  Future<AuthSessionPayload> login({
    required String email,
    required String authVerifier,
    String? deviceId,
    String? deviceName,
  }) async {
    final Map<String, Object?> body = await _json('POST', '/v1/auth/login', payload: <String, Object?>{
      'email': email,
      'verifier': authVerifier,
      'device_id': deviceId,
      'device_name': deviceName,
    });
    return _session(body);
  }

  @override
  Future<AuthSessionPayload> reset({
    required String email,
    required String code,
    required String accountId,
    required String authVerifier,
    required String wrapped,
    required String saltHex,
    required String kdf,
    String? deviceId,
  }) async {
    final Map<String, Object?> body = await _json('POST', '/v1/auth/reset', payload: <String, Object?>{
      'email': email,
      'code': code,
      'account_id': accountId,
      'verifier': authVerifier,
      'wrapped': wrapped,
      'salt': saltHex,
      'kdf': kdf,
      'device_id': deviceId,
    });
    return _session(body);
  }

  @override
  Future<void> changePassword({
    required String token,
    required String currentAuthVerifier,
    required String authVerifier,
    required String wrapped,
    required String saltHex,
    required String kdf,
  }) async {
    await _json('POST', '/v1/auth/change-password', token: token, payload: <String, Object?>{
      'current_verifier': currentAuthVerifier,
      'verifier': authVerifier,
      'wrapped': wrapped,
      'salt': saltHex,
      'kdf': kdf,
    });
  }

  @override
  Future<void> logout(String token) async {
    await _json('POST', '/v1/auth/logout', token: token, payload: const <String, Object?>{});
  }

  @override
  Future<void> deleteAccount(String token) async {
    await _json('DELETE', '/v1/account', token: token);
  }

  AuthSessionPayload _session(Map<String, Object?> body) {
    final Object? accountId = body['account_id'];
    final Object? token = body['token'];
    if (accountId is! String || token is! String) {
      throw const AuthTransportException('服务端没有给出账号或令牌（版本对不上？）');
    }
    return AuthSessionPayload(
      accountId: accountId,
      token: token,
      wrapped: body['wrapped'] as String?,
      saltHex: body['salt'] as String?,
      kdf: body['kdf'] as String?,
    );
  }

  Future<Map<String, Object?>> _json(
    String method,
    String path, {
    Map<String, Object?>? payload,
    String? token,
  }) async {
    final HttpClientRequest req = await _client
        .openUrl(method, baseUrl.resolve(path))
        .timeout(timeout, onTimeout: () => throw const AuthTransportException('连接超时'));
    req.headers.contentType = ContentType.json;
    if (token != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (payload != null) req.write(jsonEncode(payload));
    final HttpClientResponse res = await req.close().timeout(
          timeout,
          onTimeout: () => throw const AuthTransportException('服务端没有响应'),
        );
    final String text = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AuthTransportException(_explain(res.statusCode, text), statusCode: res.statusCode);
    }
    if (text.isEmpty) return <String, Object?>{};
    try {
      final Object? decoded = jsonDecode(text);
      return decoded is Map<String, Object?> ? decoded : <String, Object?>{};
    } on FormatException {
      throw AuthTransportException('服务端返回了看不懂的内容', statusCode: res.statusCode);
    }
  }

  /// 把状态码翻译成人话。**不带服务端内部细节**（那些进日志，不进界面）。
  String _explain(int status, String body) {
    String detail = '';
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<String, Object?> && decoded['error'] is String) {
        detail = decoded['error']! as String;
      }
    } on FormatException {
      detail = '';
    }
    switch (status) {
      case 400:
        return detail.isEmpty ? '请求不对（验证码或参数）' : detail;
      case 401:
        return detail.isEmpty ? '邮箱或口令不对' : detail;
      case 404:
        return '这一步在服务端上还没有（服务端版本旧了？）';
      case 409:
        return detail.isEmpty ? '这个邮箱已经注册过了' : detail;
      case 413:
        return '内容太大了';
      case 429:
        return detail.isEmpty ? '操作太频繁，请稍后再试' : detail;
      case 502:
        return detail.isEmpty ? '验证码没发出去，请稍后再试' : detail;
      default:
        if (status >= 500) return '服务端出错了（稍后再试）';
        return '请求失败（$status）';
    }
  }
}
