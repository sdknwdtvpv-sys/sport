/// 练了么 · 恢复码
///
/// 云备份的账号**不是手机号、不是邮箱**，而是一串用户可以抄在纸上的**恢复码**。
/// 它就是账号的唯一凭据：**丢了就找不回**（服务端只有密钥的哈希，没有明文密钥）。
/// 所以这份代码的全部心思都花在一件事上：**让人抄得对、抄错了能发现**。
///
/// 三条设计取舍：
///
///   1. **Crockford Base32**：字母表去掉了容易混淆的 `I` `L` `O` `U`
///      （`0/O`、`1/I/L` 这两组是手抄错误的重灾区）。解析时还把它们映射回去。
///   2. **带一位校验字符**：抄错一位能被**当场发现**，而不是等到恢复时才发现
///      "恢复码不对" —— 那时用户已经找不到原件了。
///   3. **分组显示**（`XXXXX-XXXXX-…`）：人念、人抄都按 5 个一组，比 27 个连着的字符好抄。
///
/// 长度：16 字节（128 位）随机密钥 → 26 个 Base32 字符 + 1 位校验 = **27 位**。
library;

import 'dart:math';
import 'dart:typed_data';

/// Crockford Base32：去掉了 I L O U
const String kCrockfordAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// 清理用户输入时做的字符映射（大小写、易混字符、分隔符）
const Map<String, String> _confusables = <String, String>{
  'I': '1', 'L': '1', 'O': '0', 'U': 'V',
};

/// 恢复码的长度（不含分隔符）
const int kRecoveryCodeLength = 27;

/// 生成一个新的恢复码。[random] 可注入，测试要确定性。
String generateRecoveryCode([Random? random]) {
  final Random r = random ?? Random.secure();
  final Uint8List key = Uint8List.fromList(
    List<int>.generate(16, (_) => r.nextInt(256)),
  );
  return formatRecoveryCode(encodeRecoveryKey(key));
}

/// 16 字节密钥 → 27 位码（26 位数据 + 1 位校验）
String encodeRecoveryKey(Uint8List key) {
  final StringBuffer bits = StringBuffer();
  for (final int b in key) {
    bits.write(b.toRadixString(2).padLeft(8, '0'));
  }
  final String data = bits.toString();
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < data.length; i += 5) {
    final String chunk = data.substring(i, i + 5 > data.length ? data.length : i + 5);
    final int v = int.parse(chunk.padRight(5, '0'), radix: 2);
    out.write(kCrockfordAlphabet[v]);
  }
  final String body = out.toString();
  return body + _checksumChar(body);
}

/// 27 位码 → 16 字节密钥。校验位不对、或字符不在字母表里 → 抛 [FormatException]。
Uint8List decodeRecoveryKey(String code) {
  final String clean = normalizeRecoveryCode(code);
  if (clean.length != kRecoveryCodeLength) {
    throw FormatException('恢复码应当是 $kRecoveryCodeLength 位，实际 ${clean.length} 位');
  }
  final String body = clean.substring(0, clean.length - 1);
  // 先查字符、再查校验位：字符不在字母表里时，"不认识的字符"比
  // "校验位对不上"对用户更有用（前者一眼能看出是抄串了行）。
  for (final String c in body.split('')) {
    if (kCrockfordAlphabet.indexOf(c) < 0) {
      throw FormatException('恢复码里有不认识的字符：$c');
    }
  }
  if (_checksumChar(body) != clean[clean.length - 1]) {
    throw const FormatException('恢复码校验位对不上 —— 多半是抄错了一位');
  }
  final StringBuffer bits = StringBuffer();
  for (final String c in body.split('')) {
    bits.write(kCrockfordAlphabet.indexOf(c).toRadixString(2).padLeft(5, '0'));
  }
  // 26 位 × 5 bit = 130 bit，只取前 128 bit（16 字节）
  final String data = bits.toString().substring(0, 128);
  return Uint8List.fromList(<int>[
    for (int i = 0; i < 128; i += 8) int.parse(data.substring(i, i + 8), radix: 2),
  ]);
}

/// 校验位：把每位乘上位置权重求和，再映射到字母表。
///
/// 不追求密码学强度 —— 它只要**发现手抄错误**就够了（真正的安全性在 128 位密钥上）。
String _checksumChar(String body) {
  int sum = 0;
  for (int i = 0; i < body.length; i++) {
    sum += kCrockfordAlphabet.indexOf(body[i]) * (i + 1);
  }
  return kCrockfordAlphabet[sum % kCrockfordAlphabet.length];
}

/// 按 5 位一组显示：`XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-XX`
String formatRecoveryCode(String code) {
  final String c = normalizeRecoveryCode(code);
  final List<String> parts = <String>[];
  for (int i = 0; i < c.length; i += 5) {
    parts.add(c.substring(i, i + 5 > c.length ? c.length : i + 5));
  }
  return parts.join('-');
}

/// 把用户输入（可能有空格、小写、连字符、I/L/O 混用）整理成规范形态。
///
/// **解析时宽容**：抄错一个 `I` 和 `1` 不该让人重抄一遍；
/// 但**校验位不放宽** —— 真正的错误必须当场暴露。
String normalizeRecoveryCode(String input) {
  final StringBuffer out = StringBuffer();
  for (final String ch in input.toUpperCase().split('')) {
    if (ch == '-' || ch == ' ' || ch == '\t' || ch == '\n') continue;
    out.write(_confusables[ch] ?? ch);
  }
  return out.toString();
}
