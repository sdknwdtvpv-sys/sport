/// 练了么 · 云备份（把三块拼起来：恢复码 + 加密 + 传输）
///
/// 这一层是**产品语义**所在，也是整套方案里最关键的一句话：
///
/// > 账号就是那串恢复码。没有手机号、没有邮箱、没有密码。
///
/// 由此推出两个必须让用户知道的后果（界面要写清楚，不能藏在文档里）：
///
///   1. **恢复码丢了就真找不回** —— 服务端只有 `SHA-256(恢复码)`，
///      没有任何办法帮你恢复。所以界面上必须反复提醒抄下来。
///   2. **换恢复码 = 换账号**：新码算出的 `account_id` 不同，
///      旧备份仍然躺在服务器上，但**用新码打不开**（AAD 绑定账号）。
///
/// 这里的顺序也是刻意的：**先在本地校验恢复码，再碰网络**。
/// 抄错一位的用户不该先等一次网络往返、再看到一句"服务器返回 401"。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'backup_config.dart';
import 'backup_crypto.dart';
import 'backup_transport.dart';
import 'recovery_code.dart';

/// 一个云备份账号 = 一串恢复码 + 服务端认的 id
class CloudAccount {
  const CloudAccount({required this.recoveryCode, required this.accountId});

  /// 规范形态（27 位，无连字符）。展示时用 [displayCode]。
  final String recoveryCode;

  /// 64 位十六进制 —— 服务端能看到的全部
  final String accountId;

  /// 给人看的那一版（5 位一组）
  String get displayCode => formatRecoveryCode(recoveryCode);

  @override
  String toString() => 'CloudAccount($accountId)';
}

/// 上传结果
class BackupUploadResult {
  const BackupUploadResult({required this.bytes, required this.envelope});

  /// 服务端记录的密文字节数
  final int bytes;

  /// 发出去的信封（测试与日志用，**不含明文**）
  final String envelope;

  @override
  String toString() => 'BackupUploadResult($bytes 字节密文)';
}

class CloudBackup {
  CloudBackup({required this.transport});

  final BackupTransport transport;

  /// 按**编译期配置**建一个真身；没配服务器地址就是 null。
  ///
  /// 为什么集中在这里：屏幕与「删除全部数据」都要用它，各写一遍
  /// （`HttpBackupTransport(baseUrl: cloudBackupBaseUrl!)`）迟早会有一处忘了判空。
  static CloudBackup? fromConfig() {
    final Uri? base = cloudBackupBaseUrl;
    if (base == null) return null;
    return CloudBackup(transport: HttpBackupTransport(baseUrl: base));
  }

  /// 新开一个云备份账号。
  ///
  /// [random] 可注入（测试要确定性）。返回的恢复码**只在这一次出现过**，
  /// 服务端从始至终没见过它。
  Future<CloudAccount> createAccount([Random? random]) async {
    final String code = normalizeRecoveryCode(generateRecoveryCode(random));
    return register(code);
  }

  /// 把手上的恢复码登记到服务端（幂等）。
  ///
  /// 恢复码抄错一位 → 在这里就抛 [FormatException]，
  /// **一个字节都不会发出去**。
  Future<CloudAccount> register(String recoveryCode) async {
    final Uint8List key = decodeRecoveryKey(recoveryCode);
    final String accountId = await accountIdFromKey(key);
    await transport.createAccount(accountId);
    return CloudAccount(
      recoveryCode: encodeRecoveryKey(key),
      accountId: accountId,
    );
  }

  /// 加密并上传。[plaintext] 是 `encodeBackup()` 产出的 JSON。
  ///
  /// 返回的信封可以直接给服务端 —— 它就是服务端能拿到的全部内容。
  Future<BackupUploadResult> upload({
    required String recoveryCode,
    required String plaintext,
  }) async {
    final Uint8List key = decodeRecoveryKey(recoveryCode);
    final String accountId = await accountIdFromKey(key);
    final String envelope = await encryptBackupWithKey(
      plaintext: utf8.encode(plaintext),
      key: key,
    );
    final int bytes = await transport.putBackup(
      accountId: accountId,
      envelope: envelope,
    );
    return BackupUploadResult(bytes: bytes, envelope: envelope);
  }

  /// 拉回并解密。服务端还没有备份时返回 null。
  ///
  /// 密文被改过、或恢复码不是这个账号的 → 抛 [BackupDecryptException]。
  Future<String?> download(String recoveryCode) async {
    final Uint8List key = decodeRecoveryKey(recoveryCode);
    final String accountId = await accountIdFromKey(key);
    final String? envelope = await transport.getBackup(accountId);
    if (envelope == null) return null;
    final List<int> clear = await decryptBackupWithKey(
      envelope: envelope,
      key: key,
    );
    return utf8.decode(clear);
  }

  /// 注销账号：账号、设备、备份一起删。
  ///
  /// 恢复码先本地校验，所以抄错码不会误删别人的账号。
  Future<void> deleteAccount(String recoveryCode) async {
    final Uint8List key = decodeRecoveryKey(recoveryCode);
    await transport.deleteAccount(await accountIdFromKey(key));
  }
}
