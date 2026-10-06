/// 练了么 · 登录会话（把"网络 / 密钥 / 本地存下来的那份"三件事拼起来）
///
/// 这一层负责的是**顺序**，而顺序错了就是安全问题：
///
///   1. 先拿盐（服务端给的，不是秘密）→ 派生 KEK → 认证明文（`authVerifier`）与包裹密钥；
///   2. 注册时**先本地算好一切**（包括恢复码），再发一次请求；
///   3. 登录时**先解开 `wrapped` 拿到账号密钥**，再写本地会话 ——
///      解不开就什么都不写，绝不留下"半个登录态"；
///   4. 登出即便联网失败，**本地也一定清干净**（用户点了登出就得登出），
///      但要把"服务端那边没吊销掉"如实告诉界面（[logout] 返回一句警告或 null）。
///
/// ## 会话存了什么、为什么这些东西能存
///
/// `token`（60 天有效的凭据）、`email`、`accountId`、**账号密钥**、盐与 KDF 参数。
/// 账号密钥落盘听起来吓人，但**今天的恢复码就是同一把密钥**（`backup_account.recovery_code`
/// 一直是明文存的）—— 这一层没有让它变得更差，只是换了个位置。
/// 真要与"设备被拿走"对抗，得引 `flutter_secure_storage`（Keychain/Keystore 两套原生代码），
/// 那是**另一件事**，方案里记着（`docs/plan-account-login.md` §六）。
///
/// ## 离线优先
///
/// [restore] **只读本地、不联网**：健身房没信号时，已登录的人必须照常能用。
/// 服务器挂了、网断了，都不该把已经登录的人挡在门外 —— 这条是产品承诺（方案 §二-2）。
library;

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'account_login.dart';
import 'auth_transport.dart';
import 'backup_config.dart';
import 'recovery_code.dart';

/// 本地存下来的那份登录态。
class StoredSession {
  const StoredSession({
    required this.token,
    required this.email,
    required this.accountId,
    required this.accountKey,
    required this.saltHex,
    required this.kdf,
    required this.loginAtMs,
  });

  final String token;
  final String email;
  final String accountId;

  /// 账号密钥（16 字节）—— 云备份那条链要的就是它
  final Uint8List accountKey;

  /// 派生 KEK 用的盐（改口令时要拿它算"当前口令的凭据"）
  final String saltHex;

  /// KDF 参数（服务端给的 JSON 字符串）
  final String kdf;

  final int loginAtMs;

  StoredSession copyWith({String? token, String? saltHex, String? kdf, int? loginAtMs}) => StoredSession(
        token: token ?? this.token,
        email: email,
        accountId: accountId,
        accountKey: accountKey,
        saltHex: saltHex ?? this.saltHex,
        kdf: kdf ?? this.kdf,
        loginAtMs: loginAtMs ?? this.loginAtMs,
      );
}

/// 会话的落盘接口。真身落在本机 drift 库里（下一批接），测试用内存实现。
abstract class SessionStore {
  Future<StoredSession?> read();

  Future<void> write(StoredSession session);

  Future<void> clear();
}

/// 内存实现：给测试用（也方便"离线仍可用"那类用例，不需要数据库）
class InMemorySessionStore implements SessionStore {
  StoredSession? _session;

  int writes = 0;
  int clears = 0;

  @override
  Future<StoredSession?> read() async => _session;

  @override
  Future<void> write(StoredSession session) async {
    writes += 1;
    _session = session;
  }

  @override
  Future<void> clear() async {
    clears += 1;
    _session = null;
  }
}

/// 登录失败时给界面看的东西：一句人话 + 是不是"没连上"（决定要不要提示检查网络）
class LoginFailure implements Exception {
  const LoginFailure(this.message, {this.isNetwork = false});

  final String message;
  final bool isNetwork;

  @override
  String toString() => 'LoginFailure: $message';
}

class LoginSession {
  LoginSession({
    required this.transport,
    required this.store,
    this.deviceId,
    this.deviceName,
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AuthTransport transport;
  final SessionStore store;
  final String? deviceId;
  final String? deviceName;
  final int Function() _clock;

  /// 从编译期配置造一个**真身**（没配服务器地址就返回 null）。
  ///
  /// ⚠️ **复用云备份那两个 dart-define**（`LIANLEME_BACKUP_URL` 与 `LIANLEME_BACKUP_DISCLOSED`），
  /// 不新增第四个：服务端同一台机器上同时提供 `/v1/backup` 与 `/v1/auth/*`，
  /// 而 `tool/check-deploy.mjs` 会把"客户端用到的每个 dart-define"与部署文档逐字对账 ——
  /// 多一个开关就多一处会对不上的地方（方案 §六 把这条写成了纪律）。
  static LoginSession? fromConfig({
    required SessionStore store,
    String? deviceId,
    String? deviceName,
    int Function()? clock,
  }) {
    final Uri? configured = cloudBackupBaseUrl;
    if (configured == null) return null;
    // 只要 origin：配置里那一串是完整的 `/v1/backup` 地址
    final Uri origin = Uri.parse('${configured.scheme}://${configured.authority}');
    return LoginSession(
      transport: HttpAuthTransport(baseUrl: origin),
      store: store,
      deviceId: deviceId,
      deviceName: deviceName,
      clock: clock,
    );
  }

  /// 只读本地会话。**不联网** —— 已经登录的人在没信号的地方照样能用。
  Future<StoredSession?> restore() => store.read();

  /// 发验证码（`register` 或 `reset`）
  Future<void> sendCode({required String email, required String purpose}) =>
      _guard(() => transport.sendCode(email: email, purpose: purpose));

  /// 在本地就把恢复码验一遍：**抄错了不该发出任何一个字节**（与云备份同一条纪律）
  static Uint8List accountKeyFromRecoveryCode(String recoveryCode) {
    try {
      return decodeRecoveryKey(recoveryCode);
    } on FormatException catch (e) {
      throw LoginFailure('恢复码抄错了：${e.message}');
    }
  }

  /// 注册一个新账号。**本地先生成账号密钥与恢复码**，再发一次请求。
  Future<StoredSession> register({
    required String email,
    required String code,
    required String password,
  }) =>
      _create(email: email, code: code, password: password, accountKey: null, reset: false);

  /// 老用户：把**本机已有的账号密钥**绑上邮箱（数据、恢复码、云备份都不作废）。
  Future<StoredSession> bindExisting({
    required String email,
    required String code,
    required String password,
    required Uint8List accountKey,
  }) =>
      _create(email: email, code: code, password: password, accountKey: accountKey, reset: false);

  Future<StoredSession> _create({
    required String email,
    required String code,
    required String password,
    required Uint8List? accountKey,
    required bool reset,
  }) async {
    final AuthSalt salt = await _saltOf(email);
    final LoginKdf kdf = LoginKdf.decode(salt.kdf);
    final Uint8List saltBytes = bytesFromHex(salt.saltHex);
    final PreparedAccount prepared = await prepareAccount(
      password: password,
      salt: saltBytes,
      kdf: kdf,
      accountKey: accountKey,
    );

    if (reset) {
      final AuthSessionPayload payload = await _guard(() => transport.reset(
            email: email,
            code: code,
            accountId: prepared.accountId,
            authVerifier: prepared.authVerifier,
            wrapped: prepared.wrapped,
            saltHex: salt.saltHex,
            kdf: salt.kdf,
            deviceId: deviceId,
          ));
      return _persist(
        email: email,
        accountId: payload.accountId,
        token: payload.token,
        accountKey: prepared.accountKey,
        saltHex: salt.saltHex,
        kdf: salt.kdf,
      );
    }

    final AuthSessionPayload payload = await _guard(() => transport.register(
          email: email,
          code: code,
          authVerifier: prepared.authVerifier,
          wrapped: prepared.wrapped,
          accountId: prepared.accountId,
          saltHex: salt.saltHex,
          kdf: salt.kdf,
          deviceId: deviceId,
          deviceName: deviceName,
        ));
    return _persist(
      email: email,
      accountId: payload.accountId,
      token: payload.token,
      accountKey: prepared.accountKey,
      saltHex: salt.saltHex,
      kdf: salt.kdf,
    );
  }

  /// 登录：拿盐 → 派生 → 服务端认证 → **解开包裹** → 才写本地
  Future<StoredSession> login({required String email, required String password}) async {
    final AuthSalt salt = await _saltOf(email);
    final LoginKdf kdf = LoginKdf.decode(salt.kdf);
    final Uint8List saltBytes = bytesFromHex(salt.saltHex);
    final DerivedLoginKeys kek = await deriveKekFor(password: password, salt: saltBytes, kdf: kdf);

    final AuthSessionPayload payload = await _guard(() => transport.login(
          email: email,
          authVerifier: kek.authVerifier,
          deviceId: deviceId,
          deviceName: deviceName,
        ));

    final String? wrapped = payload.wrapped;
    if (wrapped == null || wrapped.isEmpty) {
      throw const LoginFailure('服务端没有给出账号密钥（版本对不上？）');
    }
    final Uint8List accountKey;
    try {
      accountKey = await unwrapAccountKey(envelope: wrapped, kek: kek.kek, accountId: payload.accountId);
    } on LoginDecryptException catch (e) {
      // 口令与"服务端给的包裹"必须对得上；对不上就当口令错 —— 不写本地、不留半个登录态。
      throw LoginFailure(e.message);
    } on LoginFormatException catch (e) {
      throw LoginFailure('账号密钥解不开：${e.message}');
    }

    return _persist(
      email: email,
      accountId: payload.accountId,
      token: payload.token,
      accountKey: accountKey,
      saltHex: payload.saltHex ?? salt.saltHex,
      kdf: payload.kdf ?? salt.kdf,
    );
  }

  /// 忘口令：**恢复码 + 邮箱验证码 → 设一个新口令**（恢复码是口令的上一级）
  Future<StoredSession> resetWithRecoveryCode({
    required String email,
    required String code,
    required String password,
    required String recoveryCode,
  }) {
    final Uint8List accountKey = accountKeyFromRecoveryCode(recoveryCode);
    return _create(email: email, code: code, password: password, accountKey: accountKey, reset: true);
  }

  /// 改口令：先验当前口令 → 换包裹 → **服务端会踢掉其他设备**。
  /// 盐是每次重新随机的（换口令就换盐，老盐不再有用）。
  Future<StoredSession> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final StoredSession? current = await restore();
    if (current == null) throw const LoginFailure('还没登录');

    final LoginKdf kdf = LoginKdf.decode(current.kdf);
    final Uint8List currentSalt = bytesFromHex(current.saltHex);
    final DerivedLoginKeys old = await deriveKekFor(password: currentPassword, salt: currentSalt, kdf: kdf);

    final Uint8List newSalt = newLoginSalt();
    final String newSaltHex = hexOf(newSalt);
    final PreparedAccount prepared = await prepareAccount(
      password: newPassword,
      salt: newSalt,
      kdf: kdf,
      accountKey: current.accountKey,
    );

    await _guard(() => transport.changePassword(
          token: current.token,
          currentAuthVerifier: old.authVerifier,
          authVerifier: prepared.authVerifier,
          wrapped: prepared.wrapped,
          saltHex: newSaltHex,
          kdf: kdf.encode(),
        ));
    final StoredSession updated = current.copyWith(saltHex: newSaltHex, kdf: kdf.encode(), loginAtMs: _clock());
    await store.write(updated);
    return updated;
  }

  /// 登出。**本地一定清干净**；返回一句警告（服务端没吊销掉）或 null。
  Future<String?> logout() async {
    final StoredSession? current = await restore();
    await store.clear();
    if (current == null) return null;
    try {
      await transport.logout(current.token);
      return null;
    } on AuthTransportException catch (e) {
      return e.isNetwork
          ? '这台设备已经登出，但没连上服务器 —— 那台令牌要到过期才会失效'
          : '这台设备已经登出，但服务器拒绝了这次吊销（${e.message}）';
    }
  }

  /// 注销账号：账号 + 云端备份 + 邮箱绑定一起删。**本地也一定清干净**。
  Future<void> deleteAccount() async {
    final StoredSession? current = await restore();
    if (current == null) return;
    try {
      await _guard(() => transport.deleteAccount(current.token));
    } finally {
      await store.clear();
    }
  }

  /// 拿盐（网络）。**不存在的邮箱也会回盐**，所以这里不区分"注册过没有"。
  Future<AuthSalt> _saltOf(String email) =>
      _guard(() => transport.salt(email: email));

  Future<StoredSession> _persist({
    required String email,
    required String accountId,
    required String token,
    required Uint8List accountKey,
    required String saltHex,
    required String kdf,
  }) async {
    final StoredSession session = StoredSession(
      token: token,
      email: email,
      accountId: accountId,
      accountKey: accountKey,
      saltHex: saltHex,
      kdf: kdf,
      loginAtMs: _clock(),
    );
    await store.write(session);
    return session;
  }

  /// 把通道异常翻成人话（`AuthTransportException` → [LoginFailure]），
  /// 这样界面只需要认一种错误类型。**服务端给的话术优先**（它更具体）。
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on AuthTransportException catch (e) {
      throw LoginFailure(e.message, isNetwork: e.isNetwork);
    }
  }
}

/// `deriveLoginKek` + `authVerifierFromKek` 一起算出来的两样东西。
class DerivedLoginKeys {
  const DerivedLoginKeys({required this.kek, required this.authVerifier});

  final SecretKey kek;
  final String authVerifier;
}

/// 一次派生，两样都用（口令只算一遍 Argon2id —— 慢函数别算两次）。
Future<DerivedLoginKeys> deriveKekFor({
  required String password,
  required List<int> salt,
  LoginKdf kdf = kDefaultLoginKdf,
}) async {
  final SecretKey kek = await deriveLoginKek(password: password, salt: salt, kdf: kdf);
  return DerivedLoginKeys(kek: kek, authVerifier: await authVerifierFromKek(kek));
}
