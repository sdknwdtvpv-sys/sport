/// 练了么 · 账号登录（邮箱 + 口令 → 密钥）
///
/// **这个文件回答一个问题：口令怎么变成密钥，而服务端为什么还是读不到数据。**
///
/// ## 密钥结构
///
/// ```
/// 口令 + 盐（服务端发放，不是秘密）
///        │  Argon2id
///        ▼
///       KEK ──HKDF(info="lianleme/auth/v1")──→ 认证凭据（发给服务端，用来证明"我是这个人"）
///        │
///        └────HKDF(info="lianleme/wrap/v1")──→ 包裹密钥
///                                                 │  AES-256-GCM
///                                                 ▼
///                          账号密钥（16 字节随机）──→ wrapped（发给服务端保管的**密文**）
///                                                 │
///                                                 ├─ SHA-256 → account_id（老规矩，没变）
///                                                 └─ HKDF(info="lianleme/backup/v1") → DEK（老规矩，没变）
/// ```
///
/// 三个"为什么"：
///
///   1. **口令永不出设备**：发出去的只有 `authVerifier`（从 KEK 单向派生）与 `wrapped`（密文）。
///      服务端两样都拿不到账号密钥：HKDF 单向、AEAD 解不开。
///   2. **认证凭据与数据密钥域分离**（两个不同的 `info`）：否则"服务端能认证你"就等于
///      "服务端能解密你的备份" —— 那正是这条设计要避免的。
///   3. **为什么现在需要"被包裹的密钥"这一层**（`backup_crypto.dart` 的文件头当年写过
///      "不需要"）：因为那时换密钥 = 换账号，而**加了口令之后，换口令不能等于换账号** ——
///      口令只是包着账号密钥的那层壳。改口令 = 重新包一次，备份一个字节都不用重加密。
///      恢复码（= 账号密钥本身）因此**永远有效**，它是口令的上一级。
///
/// ## 诚实写在代码里的残余风险
///
/// `account_id = SHA-256(账号密钥)` 仍然要发给服务端；而账号密钥是被口令派生出来的 KEK
/// 包着的。所以**拿到库的一方可以离线爆破弱口令**：口令一旦被猜出，KEK 就出来，
/// `wrapped` 就被解开，备份就没了。这条风险**不是实现缺陷，是"口令登录 + 端到端加密"
/// 这对组合的固有代价**（要消掉它得上 PAKE/SRP，代价是一套自研协议，见方案 §三）。
/// 我们能做的是：Argon2id 参数按"最慢可接受的设备时间"定（见 [kDefaultLoginKdf] 与
/// 方案 §七 的基准数），并在客户端挡掉最弱的那批口令（[PasswordPolicy]）。
///
/// ⚠️ 这个文件**不许 import flutter**：它是纯 Dart 的，这样 `dart analyze` 与
/// 领域层那套（`dart app/tool/...`）都能在**没有 Flutter 工具链**的环境里验证它。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'backup_crypto.dart';
import 'recovery_code.dart';

/// 口令派生 KEK 的参数。
///
/// **这些数字是一代定死的**：换参数 = 老用户登不进来（除非带着旧参数重试），
/// 所以它们会跟着账号一起存在服务端（`kdf` 字段，服务端只保管、不参与计算）。
///
/// 取值理由（2026-10-06 实测，见方案 §七 B 期）：`m=64MB, t=3, p=4` 在开发机上
/// **中位 174 ms**（纯 Dart，JIT；手机 AOT 会慢一些但仍在可接受区间）。
/// 降低它不是"优化"，是**降低离线爆破的代价**。
class LoginKdf {
  const LoginKdf({
    this.memory = 65536,
    this.iterations = 3,
    this.parallelism = 4,
    this.hashLength = 32,
    this.version = 19,
  });

  /// 内存块数（单位是 1KB 的块）—— 65536 = 64 MB
  final int memory;

  /// 迭代遍数
  final int iterations;

  /// 并行度
  final int parallelism;

  /// 输出长度（字节）
  final int hashLength;

  /// Argon2 版本（RFC 9106 是 19）
  final int version;

  /// 存进服务端的形状（服务端不认识这些数字的含义，只负责原样还给我们）。
  Map<String, Object> toJson() => <String, Object>{
        'alg': 'argon2id',
        'm': memory,
        't': iterations,
        'p': parallelism,
        'v': version,
      };

  String encode() => jsonEncode(toJson());

  /// 解析服务端还回来的 `kdf` 字符串。**认不出来就用默认值**（不抛错）：
  /// 这里抛错只会让用户卡在登录页，而"用默认参数试一次"最多是登不进去。
  static LoginKdf decode(String? raw) {
    if (raw == null || raw.isEmpty) return kDefaultLoginKdf;
    try {
      final Object? parsed = jsonDecode(raw);
      if (parsed is! Map<String, Object?>) return kDefaultLoginKdf;
      if (parsed['alg'] != 'argon2id') return kDefaultLoginKdf;
      return LoginKdf(
        memory: (parsed['m'] as num?)?.toInt() ?? kDefaultLoginKdf.memory,
        iterations: (parsed['t'] as num?)?.toInt() ?? kDefaultLoginKdf.iterations,
        parallelism: (parsed['p'] as num?)?.toInt() ?? kDefaultLoginKdf.parallelism,
        version: (parsed['v'] as num?)?.toInt() ?? kDefaultLoginKdf.version,
      );
    } on FormatException {
      return kDefaultLoginKdf;
    }
  }
}

/// 一期的参数（与 `server/auth.mjs` 的 `DEFAULT_KDF` 必须一致 —— 那边只在
/// "这个邮箱还没注册"时用来凑形状，真值以客户端为准）。
const LoginKdf kDefaultLoginKdf = LoginKdf();

/// 认证凭据的 HKDF 上下文
const String kAuthVerifierInfo = 'lianleme/auth/v1';

/// 包裹账号密钥的 HKDF 上下文
const String kWrapInfo = 'lianleme/wrap/v1';

/// 包裹信封的 AAD 前缀（绑死"这坨密文属于哪个账号"）
const String kWrapAadPrefix = 'lianleme/wrap/v1:';

/// 包裹信封的版本
const int kLoginEnvelopeVersion = 1;

/// 账号密钥长度（字节）。与恢复码同源：16 字节 = 128 位随机。
const int kAccountKeyLength = 16;

/// 盐的长度（字节）
const int kLoginSaltLength = 32;

/// 解不开包裹（口令错、密文被改、账号对不上）
class LoginDecryptException implements Exception {
  const LoginDecryptException(this.message);

  final String message;

  @override
  String toString() => 'LoginDecryptException: $message';
}

/// 包裹信封格式不对（不是我们写的 JSON、版本不认识、字段缺失）
class LoginFormatException implements Exception {
  const LoginFormatException(this.message);

  final String message;

  @override
  String toString() => 'LoginFormatException: $message';
}

/// 生成一个新的账号密钥（**不是**口令派生出来的，是随机数）。
///
/// 这一点很关键：它保证"账号密钥的强度 = 128 位随机"，与口令强弱无关 ——
/// 口令弱只会让**包裹层**被爆破，而包裹层是这道门唯一的弱点（见文件头）。
Uint8List newAccountKey([Random? random]) {
  final Random r = random ?? Random.secure();
  return Uint8List.fromList(List<int>.generate(kAccountKeyLength, (_) => r.nextInt(256)));
}

/// 账号密钥 → 恢复码（27 位，用户抄在纸上的那一串）
String recoveryCodeFor(Uint8List accountKey) =>
    formatRecoveryCode(encodeRecoveryKey(accountKey));

/// 口令 + 盐 → KEK
Future<SecretKey> deriveLoginKek({
  required String password,
  required List<int> salt,
  LoginKdf kdf = kDefaultLoginKdf,
}) async {
  final Argon2id argon = Argon2id(
    memory: kdf.memory,
    iterations: kdf.iterations,
    parallelism: kdf.parallelism,
    hashLength: kdf.hashLength,
  );
  return argon.deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
}

/// KEK → 认证凭据（64 位十六进制字符串，发给服务端）
Future<String> authVerifierFromKek(SecretKey kek) async {
  final Hkdf hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final SecretKeyData key = await hkdf.deriveKey(
    secretKey: kek,
    info: utf8.encode(kAuthVerifierInfo),
  );
  final StringBuffer out = StringBuffer();
  for (final int b in key.bytes) {
    out.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

/// KEK → 包裹密钥
Future<SecretKey> _wrapKeyFromKek(SecretKey kek) async {
  final Hkdf hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final SecretKeyData key = await hkdf.deriveKey(
    secretKey: kek,
    info: utf8.encode(kWrapInfo),
  );
  return SecretKey(key.bytes);
}

List<int> _wrapAad(String accountId) => utf8.encode('$kWrapAadPrefix$accountId');

/// 把账号密钥包起来，返回可以直接存到服务端的信封 JSON（**不含任何明文**）。
///
/// [nonce] 仅供测试注入；生产必须每次随机（GCM 下 nonce 复用是致命的）。
Future<String> wrapAccountKey({
  required Uint8List accountKey,
  required SecretKey kek,
  required String accountId,
  List<int>? nonce,
}) async {
  final AesGcm algorithm = AesGcm.with256bits();
  final SecretKey wrapKey = await _wrapKeyFromKek(kek);
  final SecretBox box = await algorithm.encrypt(
    accountKey,
    secretKey: wrapKey,
    nonce: nonce ?? algorithm.newNonce(),
    aad: _wrapAad(accountId),
  );
  return jsonEncode(<String, Object>{
    'v': kLoginEnvelopeVersion,
    'alg': 'AES-256-GCM',
    'kdf': 'HKDF-SHA256',
    'nonce': base64.encode(box.nonce),
    'ct': base64.encode(box.cipherText),
    'mac': base64.encode(box.mac.bytes),
  });
}

/// 解开包裹，拿回账号密钥。
///
/// 两种失败都抛 [LoginDecryptException]，且**无法区分**（口令错 / 密文被改 / 账号对不上）——
/// 认证失败就是认证失败，不该给攻击者额外信息。
///
/// 解开之后还会**核一次身份**：`SHA-256(账号密钥)` 必须等于 [accountId]。
/// 这条检查防的是"服务端把别人的 wrapped 塞给我" —— 那样算出来的账号 id 会不一样，
/// 于是当场失败，而不是让我拿着别人的密钥去写坏两边的备份。
Future<Uint8List> unwrapAccountKey({
  required String envelope,
  required SecretKey kek,
  required String accountId,
}) async {
  final Map<String, Object?> parsed;
  try {
    final Object? decoded = jsonDecode(envelope);
    if (decoded is! Map<String, Object?>) {
      throw const LoginFormatException('账号密钥信封不是一个 JSON 对象');
    }
    parsed = decoded;
  } on FormatException catch (e) {
    throw LoginFormatException('账号密钥信封不是合法 JSON：${e.message}');
  }

  final Object? version = parsed['v'];
  if (version != kLoginEnvelopeVersion) {
    throw LoginFormatException('不认识的账号密钥信封版本：$version');
  }
  final Uint8List nonce = _field(parsed, 'nonce');
  final Uint8List cipherText = _field(parsed, 'ct');
  final Uint8List mac = _field(parsed, 'mac');

  final AesGcm algorithm = AesGcm.with256bits();
  final SecretKey wrapKey = await _wrapKeyFromKek(kek);
  final List<int> clear;
  try {
    clear = await algorithm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: wrapKey,
      aad: _wrapAad(accountId),
    );
  } on SecretBoxAuthenticationError {
    throw const LoginDecryptException('口令不对，或者这坨密文不是这个账号的');
  }
  final Uint8List key = Uint8List.fromList(clear);
  if (key.length != kAccountKeyLength) {
    throw const LoginFormatException('账号密钥长度不对');
  }
  if (await accountIdFromKey(key) != accountId) {
    throw const LoginDecryptException('解出来的账号密钥与这个账号对不上');
  }
  return key;
}

/// 取一个 base64 字段（空串合法 —— 见 `backup_crypto.dart` 里同名函数的注释）
Uint8List _field(Map<String, Object?> parsed, String name) {
  final Object? raw = parsed[name];
  if (raw is! String) {
    throw LoginFormatException('账号密钥信封缺少字段 $name');
  }
  try {
    return base64.decode(raw);
  } on FormatException {
    throw LoginFormatException('账号密钥信封字段 $name 不是合法 base64');
  }
}

/// 注册时要发给服务端的一整套东西（口令与 KEK **不在里面**）
class PreparedAccount {
  const PreparedAccount({
    required this.accountKey,
    required this.accountId,
    required this.recoveryCode,
    required this.authVerifier,
    required this.wrapped,
  });

  /// 账号密钥（16 字节）—— 留在设备上，解云备份要用它
  final Uint8List accountKey;

  /// 64 位十六进制，服务端拿到的身份
  final String accountId;

  /// 27 位恢复码（给用户抄的那一串）
  final String recoveryCode;

  /// 发给服务端的认证凭据
  final String authVerifier;

  /// 发给服务端保管的密文（被 KEK 包起来的账号密钥）
  final String wrapped;
}

/// **一站式**：口令 + 盐 → 一整套注册材料。
///
/// [accountKey] 可注入（"老用户绑邮箱"就是这么用的：把本机恢复码对应的密钥拿进来包一次，
/// 而不是新建一个账号 —— 那样历史数据、恢复码、云备份都不作废）。
Future<PreparedAccount> prepareAccount({
  required String password,
  required List<int> salt,
  LoginKdf kdf = kDefaultLoginKdf,
  Uint8List? accountKey,
  Random? random,
  List<int>? nonce,
}) async {
  final Uint8List key = accountKey ?? newAccountKey(random);
  final SecretKey kek = await deriveLoginKek(password: password, salt: salt, kdf: kdf);
  final String accountId = await accountIdFromKey(key);
  return PreparedAccount(
    accountKey: key,
    accountId: accountId,
    recoveryCode: recoveryCodeFor(key),
    authVerifier: await authVerifierFromKek(kek),
    wrapped: await wrapAccountKey(accountKey: key, kek: kek, accountId: accountId, nonce: nonce),
  );
}

/// **一站式**：登录。口令 + 盐 + 服务端给的 `wrapped` → 账号密钥。
Future<Uint8List> unlockAccountKey({
  required String password,
  required List<int> salt,
  required String wrapped,
  required String accountId,
  LoginKdf kdf = kDefaultLoginKdf,
}) async {
  final SecretKey kek = await deriveLoginKek(password: password, salt: salt, kdf: kdf);
  return unwrapAccountKey(envelope: wrapped, kek: kek, accountId: accountId);
}

/// 口令强度的**本地**判断。
///
/// **为什么不联网查"这个口令有没有泄漏过"**：那要把口令的哈希（或前缀）发给第三方，
/// 而这个 App 的全部卖点就是"数据不出设备"。本地这份表只能挡住最弱的一批，
/// 它是一条**体验与常识**的防线，不是安全边界（真正的边界是 Argon2id 的代价）。
class PasswordPolicy {
  /// 最短长度。8 位是常见下限；不加"必须含大小写数字"那种规矩 ——
  /// 那类规矩会把用户推向 `Password1!` 这种更差的选择。
  static const int minLength = 8;

  /// 最长长度：Argon2id 的代价随输入线性增长，超长口令会让登录页卡死（自伤）。
  static const int maxLength = 128;

  /// 常见弱口令（**故意保持很短**：它只是"最弱的一批"，不是字典）
  static const Set<String> common = <String>{
    '12345678', '123456789', '1234567890', 'password', 'password1', 'password123',
    'qwertyui', 'qwerty123', 'abc12345', '11111111', '00000000', '88888888',
    'iloveyou', 'sunshine', 'princess', 'football', 'baseball', 'welcome1',
    'admin123', 'letmein1', 'monkey123', 'dragon123', 'master123', 'shadow123',
    'woaini1314', '5201314520', 'a1234567', 'aa123456', 'abcd1234', 'abc123456',
    'wang1234', 'zhang123', 'li123456', 'lianleme', 'lianleme1', 'lianleme123',
    '练了么123', 'woaini123', '5201314a', 'zxcvbnm1', 'asdfghj1', '1qaz2wsx',
  };

  /// 返回 `null` 表示可以；否则返回一句给用户看的原因（中文、不含 markdown）。
  static String? check(String password) {
    if (password.length < minLength) return '口令至少 $minLength 位';
    if (password.length > maxLength) return '口令太长了（最多 $maxLength 位）';
    final String lower = password.toLowerCase();
    if (common.contains(lower)) return '这个口令太常见了，换一个';
    if (RegExp(r'^(.)\1*$').hasMatch(password)) return '别用同一个字符重复';
    if (RegExp(r'^\d+$').hasMatch(password)) return '别只用数字';
    if (lower.contains('lianleme') || password.contains('练了么')) {
      return '口令里别放应用名';
    }
    return null;
  }

  /// 给界面用的强度提示（**只是提示**，不拦）。
  ///
  /// 打分口径（写在这里，免得以后各处各说一套）：
  /// 长度 ≥ 12 记 1 分、同时有大小写记 1 分、有数字记 1 分、有符号记 1 分；
  /// **0–1 分 = 弱(0) / 2 分 = 中(1) / ≥3 分 = 强(2)**。
  /// 它故意比 [check] 严：`check` 是"能不能用"，这里是"要不要再想一下"。
  static int strength(String password) {
    if (password.length < minLength) return 0;
    int score = 0;
    if (password.length >= 12) score += 1;
    if (RegExp(r'[a-z]').hasMatch(password) && RegExp(r'[A-Z]').hasMatch(password)) score += 1;
    if (RegExp(r'\d').hasMatch(password)) score += 1;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score += 1;
    if (score >= 3) return 2;
    if (score >= 2) return 1;
    return 0;
  }
}
