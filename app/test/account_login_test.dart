/// 练了么 · 账号登录（邮箱 + 口令 → 密钥）
///
/// 这一层要守住的承诺是**两条同时成立**：
///
///   1. 「服务端永远看不到你的训练明细」—— 所以发出去的两样东西
///      （`authVerifier` / `wrapped`）都**推不出**账号密钥；
///   2. 「换口令不等于换账号」—— 所以账号密钥是随机的、被口令派生的 KEK 包着，
///      改口令只是重包一次，备份与恢复码都不受影响。
///
/// 每条用例都在试图推翻其中一条：换盐、换口令、改密文一个 bit、把 A 的包裹挪给 B、
/// 用不同的 KDF 参数解、以及"老用户把恢复码对应的密钥绑上邮箱之后还能不能登录"。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/backup/account_login.dart';
import 'package:lianleme/backup/backup_crypto.dart';
import 'package:lianleme/backup/recovery_code.dart';

Uint8List _key(int seed) =>
    Uint8List.fromList(List<int>.generate(16, (i) => (seed * 37 + i * 11) % 256));

Uint8List _salt(int seed) =>
    Uint8List.fromList(List<int>.generate(32, (i) => (seed * 13 + i * 7) % 256));

const String _pw = '正确的马口令 horse-battery-staple';

/// **测试用的便宜 KDF 参数**：Argon2id 是**刻意的慢**函数（默认档一次约 0.2 秒），
/// 而这个文件里有十几处派生 —— 用默认档的话，跑整套门禁时这些用例会互相抢 CPU
/// 直到撞上 30 秒超时（2026-10-06 真的撞过一次：单独跑 4 秒，和别的文件一起跑 9 条超时）。
/// 所以只有**一条**用例用真实默认档（证明出货参数真的能用），其余走这个。
const LoginKdf _fast = LoginKdf(memory: 1024, iterations: 1, parallelism: 1);


void main() {
  // Argon2id 是**刻意的慢**函数（一次 ≈ 0.2 秒），所以这一组用例比别处慢几秒。
  group('账号登录 · 口令 → KEK → 账号密钥', () {
    test('同口令同盐，派生是确定的（换台设备也能登进来）', () async {
      final Uint8List key = _key(1);
      final PreparedAccount a = await prepareAccount(
        password: _pw, salt: _salt(9), accountKey: key, nonce: List<int>.filled(12, 3), kdf: _fast,
      );
      final PreparedAccount b = await prepareAccount(
        password: _pw, salt: _salt(9), accountKey: key, nonce: List<int>.filled(12, 3), kdf: _fast,
      );
      expect(a.accountId, b.accountId);
      expect(a.authVerifier, b.authVerifier);
      expect(a.wrapped, b.wrapped);
    });

    test('盐不同 → 认证凭据与包裹都不同，但账号 id 不变（账号密钥才是身份）', () async {
      final Uint8List key = _key(2);
      final PreparedAccount a = await prepareAccount(password: _pw, salt: _salt(1), accountKey: key, kdf: _fast);
      final PreparedAccount b = await prepareAccount(password: _pw, salt: _salt(2), accountKey: key, kdf: _fast);
      expect(a.authVerifier, isNot(b.authVerifier));
      expect(a.wrapped, isNot(b.wrapped));
      expect(a.accountId, b.accountId);
      expect(a.accountId, await accountIdFromKey(key));
    });

    test('口令错 → 解不开，且与"密文被改"是同一种错（不区分原因）', () async {
      final PreparedAccount a = await prepareAccount(password: _pw, salt: _salt(3), accountKey: _key(3), kdf: _fast);
      final String? wrongPw = await _throwsLogin(() => unlockAccountKey(
            password: '不是这个口令', salt: _salt(3), wrapped: a.wrapped, accountId: a.accountId,
          ));
      expect(wrongPw, isNotNull);

      final Map<String, Object?> env = jsonDecode(a.wrapped) as Map<String, Object?>;
      final Uint8List ct = base64.decode(env['ct']! as String);
      ct[0] = ct[0] ^ 1; // 改一个 bit
      env['ct'] = base64.encode(ct);
      final String tampered = jsonEncode(env);
      final String? tamperMsg = await _throwsLogin(() => unlockAccountKey(
            password: _pw, salt: _salt(3), wrapped: tampered, accountId: a.accountId,
          ));
      expect(tamperMsg, isNotNull);
    });

    test('把 A 的包裹挪给 B → 解不开（AAD 绑死了账号）', () async {
      final PreparedAccount a = await prepareAccount(password: _pw, salt: _salt(4), accountKey: _key(4), kdf: _fast);
      final String other = await accountIdFromKey(_key(5));
      final String? msg = await _throwsLogin(() => unlockAccountKey(
            password: _pw, salt: _salt(4), wrapped: a.wrapped, accountId: other,
          ));
      expect(msg, isNotNull);
    });

    test('换 KDF 参数 → 解不开（参数是密钥的一部分，不是可选优化）', () async {
      final PreparedAccount a = await prepareAccount(password: _pw, salt: _salt(6), accountKey: _key(6), kdf: _fast);
      final String? msg = await _throwsLogin(() => unlockAccountKey(
            password: _pw, salt: _salt(6), wrapped: a.wrapped, accountId: a.accountId,
            kdf: const LoginKdf(memory: 2048, iterations: 1, parallelism: 1),
          ));
      expect(msg, isNotNull);
    });

    test('信封里没有明文：既没有账号密钥，也没有口令', () async {
      final Uint8List key = _key(7);
      final PreparedAccount a = await prepareAccount(password: _pw, salt: _salt(7), accountKey: key);
      expect(a.wrapped.contains(base64.encode(key)), isFalse);
      final String hex = key.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(a.wrapped.toLowerCase().contains(hex), isFalse);
      expect(a.wrapped.contains(base64.encode(utf8.encode(_pw))), isFalse);
      expect(a.wrapped.contains(_pw), isFalse);
      // 认证凭据也不许等于账号密钥的哈希（否则服务端能"变成"账号身份）
      expect(a.authVerifier, isNot(a.accountId));
    });

    test('恢复码仍然有效：绑上邮箱之后，那一串还是原来那一串', () async {
      final Uint8List key = _key(8);
      final String code = recoveryCodeFor(key);
      expect(decodeRecoveryKey(code), key);

      // 老用户路径：拿本机恢复码对应的密钥去"绑邮箱"，而不是新建账号
      final PreparedAccount bound = await prepareAccount(
        password: _pw, salt: _salt(8), accountKey: decodeRecoveryKey(code), kdf: _fast,
      );
      expect(bound.recoveryCode, code);
      expect(bound.accountId, await accountIdFromRecoveryCode(code));

      // 而且用口令能把它解回来 —— 与恢复码那条路拿到的是**同一个**账号
      final Uint8List back = await unlockAccountKey(
        password: _pw, salt: _salt(8), wrapped: bound.wrapped, accountId: bound.accountId, kdf: _fast,
      );
      expect(back, key);
    });

    test('解出来的账号密钥能直接解密云备份（与既有链路衔接）', () async {
      final Uint8List key = _key(11);
      final String code = recoveryCodeFor(key);
      final String envelope = await encryptBackup(
        plaintext: '{"workouts":[{"kg":62.5}]}', recoveryCode: code, nonce: List<int>.filled(12, 1),
      );
      final PreparedAccount acct = await prepareAccount(password: _pw, salt: _salt(11), accountKey: key);
      // ⚠️ 这一条**故意用出货的默认档**（`kDefaultLoginKdf`）：别的用例为了跑得快
      // 都用 `_fast`，如果全都用便宜的参数，"真实参数到底能不能用"就没人验了。
      final Uint8List unlocked = await unlockAccountKey(
        password: _pw, salt: _salt(11), wrapped: acct.wrapped, accountId: acct.accountId,
      );
      expect(await decryptBackupWithKey(envelope: envelope, key: unlocked),
          utf8.encode('{"workouts":[{"kg":62.5}]}'));
    });

    test('新建的账号密钥是随机的、长度固定（强度不依赖于口令）', () {
      final Random random = Random(20261006);
      final Set<String> seen = <String>{};
      for (int i = 0; i < 200; i++) {
        final Uint8List key = newAccountKey(random);
        expect(key.length, kAccountKeyLength);
        seen.add(base64.encode(key));
      }
      expect(seen.length, 200);
    });

    test('信封格式不对时报的是格式错，不是"口令不对"（可诊断）', () async {
      final PreparedAccount a = await prepareAccount(password: _pw, salt: _salt(12), accountKey: _key(12), kdf: _fast);
      expect(
        () => unwrapAccountKey(envelope: '不是 JSON', kek: _fakeKek(), accountId: a.accountId),
        throwsA(isA<LoginFormatException>()),
      );
      final Map<String, Object?> env = jsonDecode(a.wrapped) as Map<String, Object?>;
      env['v'] = 99;
      expect(
        () => unwrapAccountKey(envelope: jsonEncode(env), kek: _fakeKek(), accountId: a.accountId),
        throwsA(isA<LoginFormatException>()),
      );
    });
  });

  group('账号登录 · KDF 参数', () {
    test('encode/decode 往返；认不出来就回默认值（不让用户卡在登录页）', () {
      const LoginKdf custom = LoginKdf(memory: 19456, iterations: 2, parallelism: 1);
      final LoginKdf back = LoginKdf.decode(custom.encode());
      expect(back.memory, 19456);
      expect(back.iterations, 2);
      expect(back.parallelism, 1);

      expect(LoginKdf.decode('').memory, kDefaultLoginKdf.memory);
      expect(LoginKdf.decode('不是 JSON').memory, kDefaultLoginKdf.memory);
      expect(LoginKdf.decode('{"alg":"scrypt","n":16384}').memory, kDefaultLoginKdf.memory);
      expect(LoginKdf.decode(null).memory, kDefaultLoginKdf.memory);
    });

    test('默认参数不弱于 OWASP 的最低建议（内存 ≥ 19MB、迭代 ≥ 2）', () {
      expect(kDefaultLoginKdf.memory, greaterThanOrEqualTo(19456));
      expect(kDefaultLoginKdf.iterations, greaterThanOrEqualTo(2));
      expect(kDefaultLoginKdf.hashLength, greaterThanOrEqualTo(32));
    });
  });

  group('账号登录 · 口令强度（本地判断，不联网）', () {
    test('挡住太短的、纯数字的、重复字符的、常见口令与应用名', () {
      expect(PasswordPolicy.check('abc123'), isNotNull);
      expect(PasswordPolicy.check('123456789012'), isNotNull);
      expect(PasswordPolicy.check('aaaaaaaaaa'), isNotNull);
      expect(PasswordPolicy.check('password123'), isNotNull);
      expect(PasswordPolicy.check('PASSWORD123'), isNotNull, reason: '大小写不敏感');
      expect(PasswordPolicy.check('lianleme-good'), isNotNull);
      expect(PasswordPolicy.check('练了么-abcdefg'), isNotNull);
      expect(PasswordPolicy.check('a' * (PasswordPolicy.maxLength + 1)), isNotNull);
    });

    test('放行正常的口令', () {
      expect(PasswordPolicy.check('正确的马口令 horse-battery-staple'), isNull);
      expect(PasswordPolicy.check('Tr0ub4dour&3x'), isNull);
    });

    test('强度提示只是提示（不拦），按口径分三档', () {
      // 口径：长度 ≥12 / 大小写齐 / 有数字 / 有符号 各 1 分；0–1 弱、2 中、≥3 强
      expect(PasswordPolicy.strength('short'), 0, reason: '不够 8 位');
      expect(PasswordPolicy.strength('abcdefghij'), 0, reason: '10 位全小写：0 分');
      expect(PasswordPolicy.strength('Abcdefghij'), 0, reason: '大小写齐但没数字没符号：1 分');
      expect(PasswordPolicy.strength('Abcdefghij1'), 1, reason: '大小写 + 数字：2 分');
      expect(PasswordPolicy.strength('Abcdefghij1!'), 2, reason: '＋符号：3 分');
      expect(PasswordPolicy.strength('Abcdefghijkl1'), 2, reason: '够长 + 大小写 + 数字：3 分');
    });
  });
}

/// 一个不花钱的假 KEK：只用来验"信封格式错误"那两条（它们在校验密钥之前就返回了）。
SecretKey _fakeKek() => SecretKey(List<int>.filled(32, 7));

/// 期望抛 [LoginDecryptException]；抛了就返回消息，没抛返回 null（而不是让 Argon2id 白跑）。
Future<String?> _throwsLogin(Future<void> Function() body) async {
  try {
    await body();
    return null;
  } on LoginDecryptException catch (e) {
    return e.message;
  }
}
