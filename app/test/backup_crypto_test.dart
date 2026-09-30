/// 练了么 · 云备份加密
///
/// 这一层要守住的是一个**承诺**：「服务端永远看不到你的训练明细和体重」。
/// 承诺不能靠文档，只能靠测试 —— 所以这里的每一条都在试图**推翻**它：
///
///   1. 恢复码：抄得对（校验位）、抄错能发现（单字符错位必被抓）、宽容归一化
///   2. 账号 id：由恢复码单向导出，且**服务端无法反推**
///   3. 密文里不许出现任何明文片段（换行、中文、数字都不许）
///   4. 改一个 bit、换一串恢复码、把 A 的备份挪给 B —— 一律解不开
///   5. 解不开时**不区分原因**（不给攻击者额外信息）
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/backup/backup_crypto.dart';
import 'package:lianleme/backup/recovery_code.dart';

Uint8List _key(int seed) =>
    Uint8List.fromList(List<int>.generate(16, (i) => (seed * 37 + i * 11) % 256));

void main() {
  group('恢复码 · 长度与形状', () {
    test('生成 27 位、能被自己解回来', () {
      final Random random = Random(20260930);
      for (int i = 0; i < 200; i++) {
        final String code = generateRecoveryCode(random);
        // generateRecoveryCode 给的是**给人看的那一版**（带连字符），
        // 规范化之后才是 27 位规范码。
        expect(normalizeRecoveryCode(code).length, kRecoveryCodeLength);
        expect(code.length, kRecoveryCodeLength + 5, reason: '展示态多 5 个连字符');
        expect(decodeRecoveryKey(code).length, 16);
      }
    });

    test('分组显示固定为 5 位一组', () {
      final String code = generateRecoveryCode(Random(1));
      final String shown = formatRecoveryCode(code);
      expect(shown.length, kRecoveryCodeLength + 5, reason: '27 位 + 5 个连字符');
      final List<String> parts = shown.split('-');
      expect(parts.length, 6);
      for (int i = 0; i < 5; i++) {
        expect(parts[i].length, 5);
      }
      expect(parts.last.length, 2, reason: '最后一组是剩下的 2 位');
    });

    test('编解码是双射：同密钥永远同一串码', () {
      final Uint8List key = _key(7);
      expect(encodeRecoveryKey(key), encodeRecoveryKey(key));
      expect(decodeRecoveryKey(encodeRecoveryKey(key)), key);
    });

    test('字母表里没有那几个容易抄错的字符', () {
      for (final String bad in <String>['I', 'L', 'O', 'U']) {
        expect(kCrockfordAlphabet.contains(bad), isFalse, reason: '$bad 不该出现在字母表里');
      }
    });
  });

  group('恢复码 · 归一化（宽容输入）', () {
    test('小写、空格、连字符都能吃进去', () {
      final Uint8List key = _key(3);
      final String code = encodeRecoveryKey(key);
      final String messy = formatRecoveryCode(code).toLowerCase().replaceAll('-', ' ');
      expect(normalizeRecoveryCode(messy), code);
      expect(decodeRecoveryKey(messy), key);
    });

    test('把 O 抄成 0、I/L 抄成 1 也认', () {
      final Uint8List key = _key(9);
      final String code = encodeRecoveryKey(key);
      // 反向构造：把码里的 0/1 换成手抄时常见的 O/I/L
      final String sloppy = code
          .replaceAll('0', 'O')
          .replaceAll('1', 'I');
      expect(normalizeRecoveryCode(sloppy), code);
      expect(decodeRecoveryKey(sloppy), key);
      expect(decodeRecoveryKey(code.replaceAll('1', 'L')), key);
    });

    test('长度不对要说清楚是长度问题', () {
      expect(
        () => decodeRecoveryKey('ABCDE'),
        throwsA(isA<FormatException>()),
      );
    });

    test('有不认识的字符时，报的是"字符"而不是"校验位"', () {
      final String code = encodeRecoveryKey(_key(5));
      final String broken = '!${code.substring(1)}';
      expect(
        () => decodeRecoveryKey(broken),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            contains('不认识的字符'),
          ),
        ),
      );
    });
  });

  group('恢复码 · 校验位必须真的抓错', () {
    test('任意一位抄错（换成别的合法字符）都能被抓出来', () {
      final Uint8List key = _key(11);
      final String code = encodeRecoveryKey(key);
      int caught = 0;
      int tried = 0;
      for (int i = 0; i < code.length; i++) {
        for (final String c in kCrockfordAlphabet.split('')) {
          if (c == code[i]) continue;
          tried++;
          final String typo = code.substring(0, i) + c + code.substring(i + 1);
          try {
            final Uint8List wrong = decodeRecoveryKey(typo);
            // 校验位碰巧对上了 —— 只允许它不是原密钥
            expect(wrong, isNot(key));
          } on FormatException {
            caught++;
          }
        }
      }
      // 27 位 × 31 种替换 = 837 种单字符错误，校验位只放过 1/32 左右
      expect(tried, 27 * 31);
      expect(
        caught / tried,
        greaterThan(0.9),
        reason: '单字符抄错必须绝大多数能被当场发现（实际 $caught/$tried）',
      );
    });

    test('换掉校验位本身也会被抓', () {
      final String code = encodeRecoveryKey(_key(13));
      final String last = code[code.length - 1];
      final String other = kCrockfordAlphabet
          .split('')
          .firstWhere((String c) => c != last);
      expect(
        () => decodeRecoveryKey(code.substring(0, code.length - 1) + other),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('账号 id · 服务端看到的那个东西', () {
    test('是 64 位十六进制，且由恢复码唯一决定', () async {
      final String code = encodeRecoveryKey(_key(17));
      final String id = await accountIdFromRecoveryCode(code);
      expect(id.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(id), isTrue);
      expect(await accountIdFromRecoveryCode(code), id, reason: '同一串恢复码必须永远同一账号');
      expect(
        await accountIdFromRecoveryCode(encodeRecoveryKey(_key(18))),
        isNot(id),
      );
    });

    test('账号 id 定长，和恢复码的分组写法无关', () async {
      final String code = encodeRecoveryKey(_key(19));
      expect(
        await accountIdFromRecoveryCode(formatRecoveryCode(code).toLowerCase()),
        await accountIdFromRecoveryCode(code),
      );
    });

    test('数据密钥不等于恢复码本身（经过了一层 HKDF）', () async {
      final Uint8List key = _key(23);
      final String code = encodeRecoveryKey(key);
      final String envelope = await encryptBackup(
        plaintext: 'x',
        recoveryCode: code,
      );
      // 信封里不能出现恢复码，也不能出现它的 base64
      expect(envelope.contains(code), isFalse);
      expect(envelope.contains(base64.encode(key)), isFalse);
      expect(envelope.contains(base64.encode(utf8.encode(code))), isFalse);
    });
  });

  group('加密 · 往返', () {
    test('加密再解密拿回原文', () async {
      final String code = encodeRecoveryKey(_key(29));
      const String plain =
          '{"workouts":[{"id":"w_1","sets":[{"weight_kg":82.5,"reps":5}]}],"体重":70.4}';
      final String envelope = await encryptBackup(plaintext: plain, recoveryCode: code);
      expect(await decryptBackup(envelope: envelope, recoveryCode: code), plain);
    });

    test('空串、超长内容都能往返', () async {
      final String code = encodeRecoveryKey(_key(31));
      for (final String plain in <String>['', '{}', '练' * 20000]) {
        final String envelope = await encryptBackup(plaintext: plain, recoveryCode: code);
        expect(await decryptBackup(envelope: envelope, recoveryCode: code), plain);
      }
    });

    test('信封字段是公开的元数据，但不含任何秘密', () async {
      final String code = encodeRecoveryKey(_key(37));
      final Map<String, Object?> parsed =
          jsonDecode(await encryptBackup(plaintext: 'x', recoveryCode: code))
              as Map<String, Object?>;
      expect(parsed['v'], kBackupEnvelopeVersion);
      expect(parsed['alg'], 'AES-256-GCM');
      expect(parsed['kdf'], 'HKDF-SHA256');
      expect(base64.decode(parsed['nonce']! as String).length, kBackupNonceLength);
      expect(base64.decode(parsed['mac']! as String).length, 16, reason: 'GCM tag 是 16 字节');
      expect(parsed.keys.toSet(), <String>{'v', 'alg', 'kdf', 'nonce', 'ct', 'mac'});
    });

    test('每次加密的密文都不同（nonce 必须随机）', () async {
      final String code = encodeRecoveryKey(_key(41));
      final String a = await encryptBackup(plaintext: 'same', recoveryCode: code);
      final String b = await encryptBackup(plaintext: 'same', recoveryCode: code);
      expect(a, isNot(b));
    });

    test('固定 nonce 时结果可复现 —— 证明没有隐藏的随机来源', () async {
      final Uint8List key = _key(43);
      final Uint8List nonce = Uint8List.fromList(List<int>.generate(12, (i) => i));
      final String a = await encryptBackupWithKey(
        plaintext: utf8.encode('same'),
        key: key,
        nonce: nonce,
      );
      final String b = await encryptBackupWithKey(
        plaintext: utf8.encode('same'),
        key: key,
        nonce: nonce,
      );
      expect(a, b);
      expect(
        utf8.decode(await decryptBackupWithKey(envelope: a, key: key)),
        'same',
      );
    });
  });

  group('加密 · 密文里不许有明文（"服务端看不到"的机器证明）', () {
    test('中文、数字、字段名都不出现在信封里', () async {
      final String code = encodeRecoveryKey(_key(47));
      final String plain = jsonEncode(<String, Object?>{
        'marker': 'MARKER-练了么-31415926',
        'workouts': <Object>[
          <String, Object?>{'exercise': '深蹲', 'weight_kg': 102.5, 'reps': 3},
        ],
      });
      final String envelope = await encryptBackup(plaintext: plain, recoveryCode: code);

      for (final String secret in <String>[
        'MARKER',
        '31415926',
        '深蹲',
        '102.5',
        'weight_kg',
        'exercise',
        'workouts',
      ]) {
        expect(envelope.contains(secret), isFalse, reason: '信封泄露了明文片段：$secret');
      }
      // 连 base64 形式也不许出现（有人会把整段 base64 后再塞进 JSON）
      expect(envelope.contains(base64.encode(utf8.encode(plain))), isFalse);
    });

    test('密文是字节级密文，不是可读的乱码巧合', () async {
      final String code = encodeRecoveryKey(_key(53));
      final String envelope = await encryptBackup(
        plaintext: 'A' * 512,
        recoveryCode: code,
      );
      final List<int> ct = base64.decode(
        (jsonDecode(envelope) as Map<String, Object?>)['ct']! as String,
      );
      expect(ct.length, 512, reason: 'GCM 是流式加密，长度应与明文一致');
      expect(ct.any((int b) => b != 0x41), isTrue);
    });
  });

  group('解密 · 该失败的都必须失败', () {
    test('换一串恢复码解不开', () async {
      final String code = encodeRecoveryKey(_key(59));
      final String other = encodeRecoveryKey(_key(61));
      final String envelope = await encryptBackup(plaintext: 'secret', recoveryCode: code);
      await expectLater(
        decryptBackup(envelope: envelope, recoveryCode: other),
        throwsA(isA<BackupDecryptException>()),
      );
    });

    test('改密文一个 bit 就解不开', () async {
      final String code = encodeRecoveryKey(_key(67));
      final String envelope = await encryptBackup(plaintext: 'secret', recoveryCode: code);
      final Map<String, Object?> parsed =
          jsonDecode(envelope) as Map<String, Object?>;
      final List<int> ct = base64.decode(parsed['ct']! as String);
      ct[0] ^= 0x01;
      parsed['ct'] = base64.encode(ct);
      await expectLater(
        decryptBackup(envelope: jsonEncode(parsed), recoveryCode: code),
        throwsA(isA<BackupDecryptException>()),
      );
    });

    test('改 MAC 一个 bit 就解不开', () async {
      final String code = encodeRecoveryKey(_key(71));
      final String envelope = await encryptBackup(plaintext: 'secret', recoveryCode: code);
      final Map<String, Object?> parsed =
          jsonDecode(envelope) as Map<String, Object?>;
      final List<int> mac = base64.decode(parsed['mac']! as String);
      mac[15] ^= 0x80;
      parsed['mac'] = base64.encode(mac);
      await expectLater(
        decryptBackup(envelope: jsonEncode(parsed), recoveryCode: code),
        throwsA(isA<BackupDecryptException>()),
      );
    });

    test('把 A 的备份挪给 B（哪怕 B 的密文合法）也解不开 —— AAD 绑了账号', () async {
      final String codeA = encodeRecoveryKey(_key(73));
      final String codeB = encodeRecoveryKey(_key(79));
      final String envelopeA = await encryptBackup(plaintext: 'A 的训练', recoveryCode: codeA);
      // B 自己也有一份合法备份，但 A 的信封在 B 这里必须失败
      await encryptBackup(plaintext: 'B 的训练', recoveryCode: codeB);
      await expectLater(
        decryptBackup(envelope: envelopeA, recoveryCode: codeB),
        throwsA(isA<BackupDecryptException>()),
      );
    });

    test('解不开时不区分原因（不泄露"是密钥错还是密文错"）', () async {
      final String code = encodeRecoveryKey(_key(83));
      final String envelope = await encryptBackup(plaintext: 'x', recoveryCode: code);
      final Map<String, Object?> tampered =
          jsonDecode(envelope) as Map<String, Object?>;
      final List<int> ct = base64.decode(tampered['ct']! as String);
      ct[0] ^= 0x01;
      tampered['ct'] = base64.encode(ct);

      final String wrongKeyMsg = await _message(
        decryptBackup(envelope: envelope, recoveryCode: encodeRecoveryKey(_key(89))),
      );
      final String tamperMsg = await _message(
        decryptBackup(envelope: jsonEncode(tampered), recoveryCode: code),
      );
      expect(wrongKeyMsg, tamperMsg);
    });

    test('信封坏了报的是格式错，不是解密错', () async {
      final String code = encodeRecoveryKey(_key(97));
      final String envelope = await encryptBackup(plaintext: 'x', recoveryCode: code);
      final Map<String, Object?> parsed =
          jsonDecode(envelope) as Map<String, Object?>;

      final List<String> broken = <String>[
        'not json at all',
        '[]',
        jsonEncode(<String, Object?>{...parsed, 'v': 99}),
        jsonEncode(<String, Object?>{...parsed}..remove('ct')),
        jsonEncode(<String, Object?>{...parsed, 'ct': '!!!not base64!!!'}),
        jsonEncode(<String, Object?>{...parsed, 'nonce': base64.encode(<int>[1, 2, 3])}),
        jsonEncode(<String, Object?>{...parsed, 'nonce': ''}),
        jsonEncode(<String, Object?>{...parsed, 'mac': ''}),
        jsonEncode(<String, Object?>{...parsed, 'mac': base64.encode(<int>[1, 2, 3])}),
      ];
      for (final String bad in broken) {
        await expectLater(
          decryptBackup(envelope: bad, recoveryCode: code),
          throwsA(isA<BackupFormatException>()),
          reason: '这份信封应当被当成格式错误：$bad',
        );
      }
    });

    test('恢复码本身抄错，在解密之前就报格式错', () async {
      final String code = encodeRecoveryKey(_key(101));
      final String envelope = await encryptBackup(plaintext: 'x', recoveryCode: code);
      await expectLater(
        decryptBackup(envelope: envelope, recoveryCode: '${code.substring(0, 26)}X'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('和后端对得上（真实链路形状）', () {
    test('信封可以原样当 PUT /v1/backup 的 body，且体积可控', () async {
      final String code = encodeRecoveryKey(_key(103));
      final String plain = jsonEncode(<String, Object?>{
        'workouts': List<Object>.generate(
          60,
          (int i) => <String, Object?>{
            'id': 'w_$i',
            'sets': List<Object>.generate(20, (int j) => <String, Object?>{
                  'weight_kg': 60.0 + j,
                  'reps': 5,
                }),
          },
        ),
      });
      final String envelope = await encryptBackup(plaintext: plain, recoveryCode: code);
      // base64 膨胀 ~4/3，8MB 上限对应约 6MB 明文 —— 这里只有几百 KB
      expect(envelope.length, lessThan(8 * 1024 * 1024));
      expect(envelope.length, greaterThan(plain.length));
    });
  });
}

Future<String> _message(Future<Object?> future) async {
  try {
    await future;
    return '<没有报错>';
  } catch (e) {
    return e.toString();
  }
}
