/// 练了么 · 云备份加密
///
/// **这一层的唯一目的：让服务端永远看不到用户的训练明细和体重。**
///
/// 备份走的是极薄后端（`server/backend.mjs`），它只会拿到一坨
/// `base64` 密文和一个 `account_id`。解密所需的全部秘密都在用户手上
/// ——也就是那串 27 位恢复码。服务端就算被拖库、被要求配合，也只能交出密文。
///
/// ## 密钥结构
///
/// ```
/// 恢复码（16 字节随机密钥）
///        │  HKDF-SHA256(info = "lianleme/backup/v1")
///        ▼
///      DEK（32 字节，AES-256-GCM）
/// ```
///
/// **为什么没有"被包裹的 DEK"这一层？** 常见做法是 `KEK` 包裹一个随机 `DEK`，
/// 以便换密码时不必重加密数据。但我们的 `account_id = SHA-256(恢复码)`：
/// 换恢复码就等于换账号，旧备份本来就不该再用 —— 包裹层换来的唯一好处
/// 在这里是个伪需求，而它要多存一个 `wrapped_key` 字段、多一层出错的可能。
///
/// > ⚠️ **2026-10-06 起这句话只对"只有恢复码"的时代成立**：加了口令登录之后，
/// > **换口令不能等于换账号**，所以账号密钥确实多了一层"被 KEK 包起来"的壳
/// > （`wrapped`）—— 但那一层是**登录层**的事，见 `account_login.dart`；
/// > 这个文件里 DEK 的推导**一个字节都没变**。
///
/// ## AAD 绑定账号
///
/// GCM 的附加认证数据里放了 `版本 + account_id`。这样**把 A 的备份挪给 B 用**
/// 会直接认证失败 —— 服务端（或中间人）无法拿一份合法密文冒充另一份。
///
/// 安全性的下限就是恢复码本身的强度：128 位随机，穷举不可行。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'recovery_code.dart';

/// 信封版本。以后换算法时靠它分流。
const int kBackupEnvelopeVersion = 1;

/// HKDF 的上下文串：把这份密钥的用途钉死在"云备份"上
const String _hkdfInfo = 'lianleme/backup/v1';

/// AAD 前缀
const String _aadPrefix = 'lianleme/backup/v1:';

/// AES-GCM 标准随机数长度
const int kBackupNonceLength = 12;

/// AES-GCM 认证标签长度
const int kBackupMacLength = 16;

/// 解密失败（密文被改、恢复码不对、账号对不上）
class BackupDecryptException implements Exception {
  const BackupDecryptException(this.message);

  final String message;

  @override
  String toString() => 'BackupDecryptException: $message';
}

/// 信封格式不对（不是我们写的 JSON、版本不认识、字段缺失）
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => 'BackupFormatException: $message';
}

/// 恢复码 → 账号 id（64 位十六进制）。
///
/// **服务端拿到的就是这个**：它反推不出恢复码（SHA-256 单向），
/// 也就无法解密任何一份备份。同一串恢复码在任何设备上算出的 id 都相同，
/// 这就是"换手机也能找回"的全部机制。
Future<String> accountIdFromRecoveryCode(String recoveryCode) {
  final Uint8List key = decodeRecoveryKey(recoveryCode);
  return accountIdFromKey(key);
}

/// 16 字节密钥 → 账号 id
Future<String> accountIdFromKey(Uint8List key) async {
  final List<int> digest = (await Sha256().hash(key)).bytes;
  final StringBuffer out = StringBuffer();
  for (final int b in digest) {
    out.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

/// 恢复码 → AES-256-GCM 数据密钥
Future<SecretKey> deriveBackupKey(String recoveryCode) async {
  final Uint8List key = decodeRecoveryKey(recoveryCode);
  return deriveBackupKeyFromKey(key);
}

/// 16 字节密钥 → AES-256-GCM 数据密钥
Future<SecretKey> deriveBackupKeyFromKey(Uint8List key) async {
  final Hkdf hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final SecretKeyData dek = await hkdf.deriveKey(
    secretKey: SecretKey(key),
    info: utf8.encode(_hkdfInfo),
  );
  return SecretKey(dek.bytes);
}

/// 附加认证数据：版本 + 账号 id，绑死"这份密文属于谁"
List<int> _aadFor(String accountId) =>
    utf8.encode('$_aadPrefix$accountId');

/// 加密一份备份。[plaintext] 通常是 `encodeBackup()` 产出的 JSON 字符串。
///
/// 返回可以直接 POST 给后端的信封 JSON。**不含任何明文**。
/// [nonce] 仅供测试注入；生产环境必须每次随机（GCM 下 nonce 复用是致命的）。
Future<String> encryptBackup({
  required String plaintext,
  required String recoveryCode,
  List<int>? nonce,
}) async {
  final Uint8List key = decodeRecoveryKey(recoveryCode);
  return encryptBackupWithKey(
    plaintext: utf8.encode(plaintext),
    key: key,
    nonce: nonce,
  );
}

/// 用原始 16 字节密钥加密（给已经解出密钥的调用方用，避免重复解析恢复码）。
Future<String> encryptBackupWithKey({
  required List<int> plaintext,
  required Uint8List key,
  List<int>? nonce,
}) async {
  final String accountId = await accountIdFromKey(key);
  final AesGcm algorithm = AesGcm.with256bits();
  final SecretKey dek = await deriveBackupKeyFromKey(key);
  final SecretBox box = await algorithm.encrypt(
    plaintext,
    secretKey: dek,
    nonce: nonce ?? algorithm.newNonce(),
    aad: _aadFor(accountId),
  );
  return jsonEncode(<String, Object>{
    'v': kBackupEnvelopeVersion,
    'alg': 'AES-256-GCM',
    'kdf': 'HKDF-SHA256',
    'nonce': base64.encode(box.nonce),
    'ct': base64.encode(box.cipherText),
    'mac': base64.encode(box.mac.bytes),
  });
}

/// 解一封备份，返回原始 JSON 字符串。
///
/// 恢复码不对、密文被动过、账号对不上 —— 这三种情况都会抛
/// [BackupDecryptException]，且**无法区分**（这是有意的：认证失败就是认证失败，
/// 不该给攻击者额外信息）。
Future<String> decryptBackup({
  required String envelope,
  required String recoveryCode,
}) async {
  final Uint8List key = decodeRecoveryKey(recoveryCode);
  final List<int> clear = await decryptBackupWithKey(
    envelope: envelope,
    key: key,
  );
  return utf8.decode(clear);
}

/// 用原始 16 字节密钥解密
Future<Uint8List> decryptBackupWithKey({
  required String envelope,
  required Uint8List key,
}) async {
  final Map<String, Object?> parsed;
  try {
    final Object? decoded = jsonDecode(envelope);
    if (decoded is! Map<String, Object?>) {
      throw const BackupFormatException('备份信封不是一个 JSON 对象');
    }
    parsed = decoded;
  } on FormatException catch (e) {
    throw BackupFormatException('备份信封不是合法 JSON：${e.message}');
  }

  final Object? version = parsed['v'];
  if (version != kBackupEnvelopeVersion) {
    throw BackupFormatException('不认识的备份版本：$version');
  }
  final Uint8List nonce = _field(parsed, 'nonce');
  if (nonce.length != kBackupNonceLength) {
    throw BackupFormatException('nonce 长度应当是 $kBackupNonceLength 字节');
  }
  final Uint8List cipherText = _field(parsed, 'ct');
  final Uint8List mac = _field(parsed, 'mac');
  if (mac.length != kBackupMacLength) {
    throw BackupFormatException('MAC 长度应当是 $kBackupMacLength 字节');
  }

  final String accountId = await accountIdFromKey(key);
  final AesGcm algorithm = AesGcm.with256bits();
  final SecretKey dek = await deriveBackupKeyFromKey(key);
  try {
    final List<int> clear = await algorithm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: dek,
      aad: _aadFor(accountId),
    );
    return Uint8List.fromList(clear);
  } on SecretBoxAuthenticationError {
    throw const BackupDecryptException('恢复码不对，或者备份内容被改动过');
  }
}

/// 取一个 base64 字段。
///
/// **空串是合法的**：GCM 是流式加密，明文为空时密文长度也是 0。
/// 早先这里把空串当成"字段缺失"，结果空备份直接被判成格式错误 —— 是往返用例
/// 里的空串把它抓出来的。字段是否缺失看 key 在不在，不看长度。
Uint8List _field(Map<String, Object?> parsed, String name) {
  final Object? raw = parsed[name];
  if (raw is! String) {
    throw BackupFormatException('备份信封缺少字段 $name');
  }
  try {
    return base64.decode(raw);
  } on FormatException {
    throw BackupFormatException('备份信封字段 $name 不是合法 base64');
  }
}
