/// 练了么 · 云备份（账号 + 上传 + 找回）
///
/// 这一份测试要证明的是**产品承诺**，不是代码行为：
///
///   * 账号是一串恢复码，不是手机号 —— 不需要任何个人信息就能建号
///   * 恢复码抄错一位，**一个字节都不会发到服务器**
///   * 服务器上那坨东西里**搜不到**任何训练明细或体重（连数据库文件本身也搜不到）
///   * 拿别人的恢复码来取 → 拿不到任何东西（不是"解不开"，是"根本没这个账号"）
///
/// 后半段（"真实链路"）会**真的把 `server/backend.mjs` 拉起来**，
/// 用真实 HTTP 走一遍，然后直接翻它的 sqlite 文件找明文。
/// 假传输只能证明我们发了什么，只有真后端能证明**存下来的是什么**。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/backup/backup_crypto.dart';
import 'package:lianleme/backup/backup_transport.dart';
import 'package:lianleme/backup/cloud_backup.dart';
import 'package:lianleme/backup/recovery_code.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/profile/backup.dart';

/// 明文里放几个好认的记号，一会儿要在服务端的字节里搜它们
const String _marker = 'MARKER-lianleme-31415926';
const String _payload = '{"version":1,"workouts":[{"id":"w_1",'
    '"exercise_name":"深蹲","sets":[{"weight_kg":102.5,"reps":3}]}],'
    '"body":{"weight_kg":70.4},"marker":"$_marker"}';

void main() {
  group('账号 · 一串恢复码就是全部', () {
    test('新账号：恢复码 + 服务端 id，且只有 id 发出去', () async {
      final FakeBackupTransport fake = FakeBackupTransport();
      final CloudBackup cloud = CloudBackup(transport: fake);

      final CloudAccount account = await cloud.createAccount(Random(2026));

      expect(normalizeRecoveryCode(account.recoveryCode).length, kRecoveryCodeLength);
      expect(account.accountId.length, 64);
      expect(account.displayCode, contains('-'));
      expect(fake.calls, <String>['create:${account.accountId}']);
      // 恢复码本身绝不能出现在任何一次调用里
      for (final String call in fake.calls) {
        expect(call.contains(account.recoveryCode), isFalse);
      }
      // 账号 id 必须真的是恢复码的哈希
      expect(await accountIdFromRecoveryCode(account.recoveryCode), account.accountId);
    });

    test('同一串恢复码登记两次是幂等的（换手机时就靠这个）', () async {
      final FakeBackupTransport fake = FakeBackupTransport();
      final CloudBackup cloud = CloudBackup(transport: fake);
      final CloudAccount a = await cloud.createAccount(Random(7));
      final CloudAccount b = await cloud.register(a.recoveryCode);

      expect(b.accountId, a.accountId);
      expect(b.recoveryCode, a.recoveryCode);
      expect(fake.calls.length, 2);
    });

    test('恢复码抄错一位 → 本地就报错，网络一次都没碰', () async {
      final FakeBackupTransport fake = FakeBackupTransport();
      final CloudBackup cloud = CloudBackup(transport: fake);
      final CloudAccount account = await cloud.createAccount(Random(11));
      fake.calls.clear();

      final String typo = '${account.recoveryCode.substring(0, 26)}X';
      await expectLater(cloud.register(typo), throwsA(isA<FormatException>()));
      await expectLater(
        cloud.upload(recoveryCode: typo, plaintext: 'x'),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        cloud.download(typo),
        throwsA(isA<FormatException>()),
      );
      // 这一行是重点：**误删别人的账号**在本地就被拦住了
      await expectLater(
        cloud.deleteAccount(typo),
        throwsA(isA<FormatException>()),
      );
      expect(fake.calls, isEmpty, reason: '抄错一位不该产生任何网络请求');
    });
  });

  group('上传 / 找回 · 假传输（能看清每一步发了什么）', () {
    test('上传的密文里搜不到明文，但能原样找回', () async {
      final FakeBackupTransport fake = FakeBackupTransport();
      final CloudBackup cloud = CloudBackup(transport: fake);
      final CloudAccount account = await cloud.createAccount(Random(13));

      final BackupUploadResult result = await cloud.upload(
        recoveryCode: account.recoveryCode,
        plaintext: _payload,
      );

      final String onServer = fake.stored[account.accountId]!;
      expect(onServer, result.envelope);
      for (final String secret in <String>[
        _marker,
        '深蹲',
        '102.5',
        'weight_kg',
        '31415926',
      ]) {
        expect(onServer.contains(secret), isFalse, reason: '服务器上有明文：$secret');
      }
      expect(result.bytes, utf8.encode(onServer).length);
      expect(await cloud.download(account.recoveryCode), _payload);
    });

    test('还没上传过 → null（不是错误）', () async {
      final FakeBackupTransport fake = FakeBackupTransport();
      final CloudBackup cloud = CloudBackup(transport: fake);
      final CloudAccount account = await cloud.createAccount(Random(17));
      expect(await cloud.download(account.recoveryCode), isNull);
    });

    test('别人的恢复码取不到我们的东西 —— 是"没有这个账号"，不是"解不开"', () async {
      final FakeBackupTransport fake = FakeBackupTransport();
      final CloudBackup cloud = CloudBackup(transport: fake);
      final CloudAccount mine = await cloud.createAccount(Random(19));
      final CloudAccount other = await cloud.createAccount(Random(23));
      await cloud.upload(recoveryCode: mine.recoveryCode, plaintext: _payload);

      expect(await cloud.download(other.recoveryCode), isNull);
      expect(fake.stored.containsKey(mine.accountId), isTrue);
    });

    test('上传能重复覆盖（同一账号只有一份最新备份）', () async {
      final FakeBackupTransport fake = FakeBackupTransport();
      final CloudBackup cloud = CloudBackup(transport: fake);
      final CloudAccount account = await cloud.createAccount(Random(29));

      await cloud.upload(recoveryCode: account.recoveryCode, plaintext: '第一版');
      await cloud.upload(recoveryCode: account.recoveryCode, plaintext: '第二版');

      expect(await cloud.download(account.recoveryCode), '第二版');
      expect(fake.stored.length, 1);
    });

    test('网络失败会**抛出来**（备份失败绝不能静默 —— 这与埋点相反）', () async {
      final FakeBackupTransport fake = FakeBackupTransport();
      final CloudBackup cloud = CloudBackup(transport: fake);
      final CloudAccount account = await cloud.createAccount(Random(31));

      fake.failWith = const BackupTransportException('连不上服务器');
      await expectLater(
        cloud.upload(recoveryCode: account.recoveryCode, plaintext: _payload),
        throwsA(isA<BackupTransportException>()),
      );
      await expectLater(
        cloud.download(account.recoveryCode),
        throwsA(isA<BackupTransportException>()),
      );
      expect(fake.failWith!.isNetwork, isTrue, reason: '没有状态码就是网络问题');
    });

    test('注销会连备份一起删掉', () async {
      final FakeBackupTransport fake = FakeBackupTransport();
      final CloudBackup cloud = CloudBackup(transport: fake);
      final CloudAccount account = await cloud.createAccount(Random(37));
      await cloud.upload(recoveryCode: account.recoveryCode, plaintext: _payload);

      await cloud.deleteAccount(account.recoveryCode);

      expect(fake.stored.containsKey(account.accountId), isFalse);
      expect(fake.calls.last, 'delete:${account.accountId}');
    });

    test('恢复码是真正的随机 —— 连开 200 个账号不重样', () async {
      final CloudBackup cloud = CloudBackup(transport: FakeBackupTransport());
      final Set<String> ids = <String>{};
      final Random random = Random(20260930);
      for (int i = 0; i < 200; i++) {
        ids.add((await cloud.createAccount(random)).accountId);
      }
      expect(ids.length, 200);
    });
  });

  group('真实链路 · 起来真的后端，翻它的数据库找明文', () {
    // 真后端 + 真 HTTP 比纯内存测试慢（起进程、建库、落盘），
    // 给足时间；`group` 本身在 flutter_test 里不收 timeout，所以逐条挂。
    void e2e(String name, Future<void> Function() body) =>
        test(name, body, timeout: const Timeout(Duration(seconds: 120)));

    late Process server;
    late Directory tmp;
    late HttpBackupTransport transport;
    late Uri baseUrl;

    /// 服务端自己的输出，失败时打出来当诊断
    final List<String> serverLog = <String>[];

    setUpAll(() async {
      // 先把**前置条件**查清楚再起服务端。
      //
      // 没有这一步的话，"Node 太旧"会长成"端口等不到"的样子：服务端 import
      // `node:sqlite` 失败直接退出，测试在 30 秒超时后报"极薄后端没起来"，
      // 看起来像备份功能坏了。CI 上（没装够新的 Node）就会踩这个。
      final ProcessResult nodeVersion;
      try {
        nodeVersion = await Process.run('node', <String>['-v']);
      } on ProcessException catch (e) {
        // `fail()` 的返回类型是 Never，所以这后面不需要 return（写了反而是死代码）
        fail('这一组测试需要 node（跑真实的极薄后端）：${e.message}');
      }
      final String v = (nodeVersion.stdout as String).trim();
      final List<int> parts = v
          .replaceFirst('v', '')
          .split('.')
          .map((String x) => int.tryParse(x) ?? 0)
          .toList();
      final int major = parts.isNotEmpty ? parts[0] : 0;
      final int minor = parts.length > 1 ? parts[1] : 0;
      if (major < 22 || (major == 22 && minor < 5)) {
        fail('这一组测试需要 Node ≥ 22.5（服务端用 node:sqlite），当前是 $v。'
            'CI 的 app job 里要有 actions/setup-node（见 .github/workflows/ci.yml）。');
      }

      final String script = _findBackendScript();
      tmp = await Directory.systemTemp.createTemp('lianleme-e2e-');
      server = await Process.start('node', <String>[
        script,
        '--port', '0',
        '--db', '${tmp.path}/backend.sqlite',
      ]);

      // ⚠️ 两个坑，都是踩过才知道的：
      //   1. `firstWhere` 拿到第一行后会**取消**管道订阅；node 下次往 stdout
      //      写东西就会收到 EPIPE，**整个进程直接死掉** —— 表现是第一个请求
      //      "Connection reset by peer"、之后全部 "Connection refused"。
      //      所以这里用广播流 + 一个**永不取消**的订阅把管道一直抽干。
      //   2. stderr 也必须读，否则 ExperimentalWarning 之类写满缓冲区同样会卡住。
      final Stream<String> out = server.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();
      out.listen(serverLog.add);
      server.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(serverLog.add);

      final String line;
      try {
        // 服务端会把内核挑中的真实端口打在启动那几行里
        line = await out
            .firstWhere((String l) => l.contains('http://127.0.0.1:'))
            .timeout(const Duration(seconds: 30));
      } on TimeoutException {
        fail('极薄后端没起来。它的输出：\n${serverLog.join('\n')}');
      }
      baseUrl = Uri.parse(
        RegExp(r'http://127\.0\.0\.1:\d+').firstMatch(line)!.group(0)!,
      );
      transport = HttpBackupTransport(baseUrl: baseUrl);
    });

    tearDownAll(() async {
      transport.close();
      server.kill(ProcessSignal.sigkill);
      await server.exitCode;
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    e2e('建号 → 上传 → 找回：走真实 HTTP，一个字节都不差', () async {
      final CloudBackup cloud = CloudBackup(transport: transport);
      final CloudAccount account = await cloud.createAccount(Random(41));

      final BackupUploadResult up = await cloud.upload(
        recoveryCode: account.recoveryCode,
        plaintext: _payload,
      );
      expect(up.bytes, utf8.encode(up.envelope).length);

      final String? back = await cloud.download(account.recoveryCode);
      expect(back, _payload, reason: '存进去的和取出来的必须是同一份明文');
    });

    e2e('磁盘上的数据库文件里搜不到明文', () async {
      // 这是"服务端看不到"最硬的证据：不解密、不看协议，直接搜字节。
      //
      // ⚠️ 而"搜不到明文"这种断言**天生可能是空的**（万一备份根本没落盘呢）。
      // 所以先做**阳性对照**：确认密文本身确实躺在文件里，再确认明文不在。
      final CloudBackup cloud = CloudBackup(transport: transport);
      final CloudAccount account = await cloud.createAccount(Random(97));
      final BackupUploadResult up = await cloud.upload(
        recoveryCode: account.recoveryCode,
        plaintext: _payload,
      );

      final File db = File('${tmp.path}/backend.sqlite');
      expect(db.existsSync(), isTrue);
      final List<int> bytes = db.readAsBytesSync();
      expect(bytes.length, greaterThan(0));
      final String asLatin1 = latin1.decode(bytes, allowInvalid: true);

      // 阳性对照：密文（ct 字段那一长串 base64）必须在文件里
      final Map<String, Object?> envelope =
          jsonDecode(up.envelope) as Map<String, Object?>;
      final String ct = envelope['ct']! as String;
      expect(
        asLatin1.contains(ct),
        isTrue,
        reason: '阳性对照失败：密文压根没落盘，下面的"搜不到明文"就不算数',
      );

      // 阴性：明文一个片段都不许在
      for (final String secret in <String>[
        _marker,
        'MARKER',
        'weight_kg',
        '102.5',
        '31415926',
        '深蹲',
      ]) {
        expect(
          asLatin1.contains(secret),
          isFalse,
          reason: '数据库文件里有明文：$secret',
        );
      }
    });

    e2e('没备份过的账号 → null；别人的恢复码 → 也是 null', () async {
      final CloudBackup cloud = CloudBackup(transport: transport);
      final CloudAccount fresh = await cloud.createAccount(Random(43));
      expect(await cloud.download(fresh.recoveryCode), isNull);

      final CloudAccount mine = await cloud.createAccount(Random(47));
      await cloud.upload(recoveryCode: mine.recoveryCode, plaintext: _payload);
      final CloudAccount other = await cloud.createAccount(Random(53));
      expect(await cloud.download(other.recoveryCode), isNull);
    });

    e2e('真后端上注销 → 备份真的没了', () async {
      final CloudBackup cloud = CloudBackup(transport: transport);
      final CloudAccount account = await cloud.createAccount(Random(59));
      await cloud.upload(recoveryCode: account.recoveryCode, plaintext: _payload);
      expect(await cloud.download(account.recoveryCode), isNotNull);

      await cloud.deleteAccount(account.recoveryCode);

      expect(await cloud.download(account.recoveryCode), isNull);
    });

    e2e('备份是"整包覆盖"：上传两次，取回的是后一次', () async {
      final CloudBackup cloud = CloudBackup(transport: transport);
      final CloudAccount account = await cloud.createAccount(Random(61));
      await cloud.upload(recoveryCode: account.recoveryCode, plaintext: '{"n":1}');
      await cloud.upload(recoveryCode: account.recoveryCode, plaintext: '{"n":2}');
      expect(await cloud.download(account.recoveryCode), '{"n":2}');
    });

    e2e('服务端被换了一份密文（换给同一账号）→ 解密失败，能发现', () async {
      final CloudBackup cloud = CloudBackup(transport: transport);
      final CloudAccount account = await cloud.createAccount(Random(67));
      await cloud.upload(recoveryCode: account.recoveryCode, plaintext: _payload);

      // 攻击者/服务端拿到密文后改一位再放回去
      final String envelope = (await transport.getBackup(account.accountId))!;
      final Map<String, Object?> parsed =
          jsonDecode(envelope) as Map<String, Object?>;
      final List<int> ct = base64.decode(parsed['ct']! as String);
      ct[0] ^= 0x01;
      parsed['ct'] = base64.encode(ct);
      await transport.putBackup(
        accountId: account.accountId,
        envelope: jsonEncode(parsed),
      );

      await expectLater(
        cloud.download(account.recoveryCode),
        throwsA(isA<BackupDecryptException>()),
      );
    });

    e2e('真实备份载荷（encodeBackup 的产物）可以整个走一遍云备份', () async {
      final CloudBackup cloud = CloudBackup(transport: transport);
      final CloudAccount account = await cloud.createAccount(Random(71));

      // 这是 app 里"导出备份"用的那个编码器 —— 云端用的就是它的产物
      final String payload = encodeBackup(
        workouts: const <Workout>[],
        exerciseNames: const <String, String>{'ex_bb_bench_press': '卧推'},
        nowMs: 1760000000000,
      );
      await cloud.upload(recoveryCode: account.recoveryCode, plaintext: payload);

      final String? back = await cloud.download(account.recoveryCode);
      expect(back, payload);
      final BackupParse parsed = parseBackup(back!);
      expect(parsed.ok, isTrue);
    });
  });
}

/// 从 `app/` 往上找到 `server/backend.mjs`（测试的工作目录是包根目录）
String _findBackendScript() {
  Directory dir = Directory.current;
  for (int i = 0; i < 6; i++) {
    final String candidate = '${dir.path}/server/backend.mjs';
    if (File(candidate).existsSync()) return candidate;
    final Directory parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('找不到 server/backend.mjs（当前目录：${Directory.current.path}）');
}
