/// 练了么 · 登录会话与账号通道
///
/// 这一份要钉住的是**顺序**与**失败时的行为**，不是"函数返回了什么"：
///
///   * 注册**先在本地算好一切**（含恢复码），再发一次请求；
///   * 登录**先解开账号密钥**，再写本地 —— 解不开就什么也不写（不留半个登录态）；
///   * **离线可用**：`restore()` 只读本地、一个字节都不发；
///   * 登出/注销即便联网失败，**本地也一定清干净**（但要把没吊销掉如实说出来）；
///   * 改口令会换盐、换包裹，而**账号密钥与 account_id 不变**。
///
/// 后半段（"真实链路"）会真的把 `server/backend.mjs` 拉起来，走真 HTTP 注册 → 登录 →
/// 改口令 → 登出 → 注销。假传输只能证明"我们发了什么形状的请求"，只有真后端能证明
/// **两边对得上**（`server/auth.selftest.mjs` 那 38 项是用手写的请求验的，
/// 这一份用的是**客户端真的会发的那套代码**）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/backup/account_login.dart';
import 'package:lianleme/backup/backup_crypto.dart';
import 'package:lianleme/backup/auth_transport.dart';
import 'package:lianleme/backup/login_session.dart';

const String _pw = '正确的马口令 horse-battery-staple';
const String _email = 'Elliot@Example.com';

/// 测试用的便宜 KDF 参数（理由同 `account_login_test.dart`：默认档一次约 0.2 秒，
/// 整套门禁并发跑的时候会把这些用例拖到超时）。真实默认档由**真实链路**那一组验。
///
/// ⚠️ **每一个假传输都要显式带上它**：漏一个就会用默认档（m=64MB, t=3, p=4）真跑 Argon2id，
/// 单跑 0.2 秒看不出来，**整包 1277 条用例并发跑的时候直接撞 30 秒超时**
/// （2026-10-06 切版那一次就是这么红的两条：登出 / 注销）。
const LoginKdf _fast = LoginKdf(memory: 1024, iterations: 1, parallelism: 1);

/// 按真口令把假传输"装配"成一台服务端：盐、包裹、账号 id 都对得上。
Future<({FakeAuthTransport transport, PreparedAccount prepared})> _wired({
  String saltHex = '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
}) async {
  final PreparedAccount prepared = await prepareAccount(
    password: _pw,
    salt: bytesFromHex(saltHex),
    kdf: _fast,
    accountKey: Uint8List.fromList(List<int>.generate(16, (int i) => i * 7 % 256)),
  );
  final FakeAuthTransport transport = FakeAuthTransport(saltHex: saltHex, kdf: _fast.encode())
    ..accountId = prepared.accountId
    ..wrapped = prepared.wrapped;
  return (transport: transport, prepared: prepared);
}

void main() {
  group('登录会话 · 注册', () {
    test('注册先在本地算好，发出去的凭据与本地派生一致，且会话落了盘', () async {
      final FakeAuthTransport fake = FakeAuthTransport(kdf: _fast.encode());
      final InMemorySessionStore store = InMemorySessionStore();
      final LoginSession session = LoginSession(transport: fake, store: store, deviceId: 'dev_1');

      final StoredSession s = await session.register(email: _email, code: '123456', password: _pw);

      expect(fake.calls.first, 'salt:$_email', reason: '第一步必须是取盐');
      expect(fake.calls[1], 'register:$_email:123456');
      expect(s.accountId, await accountIdFromKey(s.accountKey));
      expect(s.token, fake.token);
      expect(store.writes, 1);
      // 恢复码就是从这把账号密钥来的：抄下来就能在别的设备上找回账号
      expect(await accountIdFromRecoveryCode(recoveryCodeFor(s.accountKey)), s.accountId);
    });

    test('老用户"绑邮箱"：用本机已有的账号密钥，恢复码与账号都不变', () async {
      final FakeAuthTransport fake = FakeAuthTransport(kdf: _fast.encode());
      final InMemorySessionStore store = InMemorySessionStore();
      final LoginSession session = LoginSession(transport: fake, store: store);
      final Uint8List existing = Uint8List.fromList(List<int>.generate(16, (int i) => 200 - i));
      final String code = recoveryCodeFor(existing);

      final StoredSession s = await session.bindExisting(
        email: _email, code: '654321', password: _pw, accountKey: existing,
      );

      expect(s.accountKey, existing);
      expect(s.accountId, await accountIdFromRecoveryCode(code));
      expect(recoveryCodeFor(s.accountKey), code, reason: '用户手上那串还是原来那串');
    });

    test('服务端拒绝时把话术带上来（不吞成"未知错误"）', () async {
      final FakeAuthTransport fake = FakeAuthTransport(kdf: _fast.encode())
        ..failWith['register'] = const AuthTransportException('验证码不对或已过期', statusCode: 400);
      final LoginSession session = LoginSession(transport: fake, store: InMemorySessionStore());

      await expectLater(
        () => session.register(email: _email, code: '000000', password: _pw),
        throwsA(isA<LoginFailure>().having((LoginFailure e) => e.message, 'message', '验证码不对或已过期')),
      );
    });

    test('没连上时标成网络问题（界面才知道该说"检查网络"）', () async {
      final FakeAuthTransport fake = FakeAuthTransport(kdf: _fast.encode())
        ..failWith['salt'] = const AuthTransportException('连不上服务器');
      final LoginSession session = LoginSession(transport: fake, store: InMemorySessionStore());

      await expectLater(
        () => session.login(email: _email, password: _pw),
        throwsA(isA<LoginFailure>().having((LoginFailure e) => e.isNetwork, 'isNetwork', isTrue)),
      );
    });
  });

  group('登录会话 · 登录', () {
    test('口令对 → 解出账号密钥，会话落盘', () async {
      final ({FakeAuthTransport transport, PreparedAccount prepared}) wired = await _wired();
      final InMemorySessionStore store = InMemorySessionStore();
      final LoginSession session = LoginSession(
        transport: wired.transport, store: store, deviceId: 'dev_2',
      );

      final StoredSession s = await session.login(email: _email, password: _pw);

      expect(s.accountKey, wired.prepared.accountKey);
      expect(s.accountId, wired.prepared.accountId);
      expect(store.writes, 1);
      expect(wired.transport.calls, <String>['salt:$_email', 'login:$_email']);
    });

    test('口令错 → 抛错，而且**一个字节都没写进本地**（不留半个登录态）', () async {
      final ({FakeAuthTransport transport, PreparedAccount prepared}) wired = await _wired();
      final InMemorySessionStore store = InMemorySessionStore();
      final LoginSession session = LoginSession(transport: wired.transport, store: store);

      await expectLater(
        () => session.login(email: _email, password: '不是这个口令'),
        throwsA(isA<LoginFailure>()),
      );
      expect(store.writes, 0);
      expect(await store.read(), isNull);
    });

    test('服务端把别人的包裹塞给我 → 身份对不上，当场失败', () async {
      final ({FakeAuthTransport transport, PreparedAccount prepared}) wired = await _wired();
      wired.transport.overrideAccountIdOnLogin = 'f' * 64;
      final InMemorySessionStore store = InMemorySessionStore();
      final LoginSession session = LoginSession(transport: wired.transport, store: store);

      await expectLater(() => session.login(email: _email, password: _pw), throwsA(isA<LoginFailure>()));
      expect(store.writes, 0);
    });

    test('服务端没给包裹 → 如实说，不当作登录成功', () async {
      final ({FakeAuthTransport transport, PreparedAccount prepared}) wired = await _wired();
      wired.transport.wrapped = '';
      final LoginSession session = LoginSession(transport: wired.transport, store: InMemorySessionStore());

      await expectLater(
        () => session.login(email: _email, password: _pw),
        throwsA(isA<LoginFailure>().having((LoginFailure e) => e.message, 'message', contains('没有给出账号密钥'))),
      );
    });
  });

  group('登录会话 · 离线与登出', () {
    test('restore 只读本地：一个字节都不发（健身房没信号也能用）', () async {
      final FakeAuthTransport fake = FakeAuthTransport(kdf: _fast.encode());
      final InMemorySessionStore store = InMemorySessionStore();
      final LoginSession session = LoginSession(transport: fake, store: store);
      await session.register(email: _email, code: '123456', password: _pw);
      fake.calls.clear();

      final StoredSession? restored = await session.restore();

      expect(restored, isNotNull);
      expect(fake.calls, isEmpty);
    });

    test('登出：本地清干净；联网失败时如实说"服务端那份没吊销"', () async {
      final FakeAuthTransport fake = FakeAuthTransport(kdf: _fast.encode());
      final InMemorySessionStore store = InMemorySessionStore();
      final LoginSession session = LoginSession(transport: fake, store: store);
      await session.register(email: _email, code: '123456', password: _pw);

      expect(await session.logout(), isNull, reason: '联网正常时不该有警告');
      expect(await store.read(), isNull);
      expect(store.clears, 1);

      // 再登一次，但这次让服务端不可达
      await session.register(email: _email, code: '123456', password: _pw);
      fake.failWith['logout'] = const AuthTransportException('连不上服务器');
      final String? warning = await session.logout();
      expect(warning, isNotNull);
      expect(warning, contains('没连上服务器'));
      expect(await store.read(), isNull, reason: '点了登出就得登出，本地必须清干净');
    });

    test('注销账号：服务端删掉 + 本地清干净；服务端出错也要清本地（并把错抛上来）', () async {
      final FakeAuthTransport fake = FakeAuthTransport(kdf: _fast.encode());
      final InMemorySessionStore store = InMemorySessionStore();
      final LoginSession session = LoginSession(transport: fake, store: store);
      await session.register(email: _email, code: '123456', password: _pw);

      await session.deleteAccount();
      expect(fake.registeredEmail, isNull);
      expect(await store.read(), isNull);

      await session.register(email: _email, code: '123456', password: _pw);
      fake.failWith['deleteAccount'] = const AuthTransportException('服务端出错了（稍后再试）', statusCode: 500);
      await expectLater(() => session.deleteAccount(), throwsA(isA<LoginFailure>()));
      expect(await store.read(), isNull, reason: '拿不到服务端的回话，本地也不该留着登录态');
    });
  });

  group('登录会话 · 改口令', () {
    test('改口令：换盐换包裹，账号密钥与账号 id 不变', () async {
      final ({FakeAuthTransport transport, PreparedAccount prepared}) wired = await _wired();
      final InMemorySessionStore store = InMemorySessionStore();
      final LoginSession session =
          LoginSession(transport: wired.transport, store: store, deviceId: 'dev_3');
      final StoredSession before = await session.login(email: _email, password: _pw);

      const String newPw = '换了一个更长的口令 abcdefg-1234';
      final StoredSession after = await session.changePassword(currentPassword: _pw, newPassword: newPw);

      expect(wired.transport.calls.last, 'changePassword');
      expect(after.saltHex, isNot(before.saltHex), reason: '换口令就换盐');
      expect(after.accountKey, before.accountKey);
      expect(after.accountId, before.accountId);
      expect(after.token, before.token, reason: '当前这台设备不该被自己踢掉');

      // 新口令（＋新盐）能解开服务端手上那份包裹
      final Uint8List unlocked = await unlockAccountKey(
        password: newPw,
        salt: bytesFromHex(after.saltHex),
        wrapped: wired.transport.wrapped,
        accountId: after.accountId,
        kdf: _fast,
      );
      expect(unlocked, before.accountKey);
    });

    test('没登录就改口令 → 如实说', () async {
      final LoginSession session =
          LoginSession(transport: FakeAuthTransport(kdf: _fast.encode()), store: InMemorySessionStore());
      await expectLater(
        () => session.changePassword(currentPassword: _pw, newPassword: 'x' * 12),
        throwsA(isA<LoginFailure>().having((LoginFailure e) => e.message, 'message', '还没登录')),
      );
    });

    test('恢复码抄错时**一个字节都不发出去**，并指出是哪一种错', () async {
      final FakeAuthTransport fake = FakeAuthTransport(kdf: _fast.encode());
      final LoginSession session = LoginSession(transport: fake, store: InMemorySessionStore());
      final String good = recoveryCodeFor(Uint8List.fromList(List<int>.filled(16, 9)));
      final String typo = good.substring(0, 10) + (good[10] == '0' ? '1' : '0') + good.substring(11);

      await expectLater(
        () => session.resetWithRecoveryCode(
              email: _email, code: '123456', password: _pw, recoveryCode: typo,
            ),
        throwsA(isA<LoginFailure>().having((LoginFailure e) => e.message, 'message', contains('抄错'))),
      );
      expect(fake.calls, isEmpty, reason: '本地就能判定的错，不许浪费一次请求');
    });

    test('重置：恢复码 + 验证码 → 新口令，账号密钥还是原来那把', () async {
      final FakeAuthTransport fake = FakeAuthTransport(kdf: _fast.encode());
      final InMemorySessionStore store = InMemorySessionStore();
      final LoginSession session = LoginSession(transport: fake, store: store);
      final Uint8List key = Uint8List.fromList(List<int>.generate(16, (int i) => (i * 31) % 256));
      final String code = recoveryCodeFor(key);

      final StoredSession s = await session.resetWithRecoveryCode(
        email: _email, code: '999999', password: '重置后的新口令 4321', recoveryCode: code,
      );

      expect(s.accountKey, key);
      expect(s.accountId, await accountIdFromRecoveryCode(code));
      expect(fake.calls.last, 'reset:$_email:999999');
    });
  });

  group('服务端还没升级时，要给一句人话（不是 401 的英文原文）', () {
    test('老服务端把 /v1/auth/* 落到鉴权闸门后面 → 回 401「缺少或非法的 Authorization」', () async {
      // 真起一个**假的老服务端**：只回那一句，形状与线上实测到的一模一样
      // （2026-10-06 拿 https://api.elliotli.work/v1/auth/salt 探到的就是它）。
      final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest req) {
        req.response
          ..statusCode = 401
          ..headers.contentType = ContentType.json
          ..write('{"error":"缺少或非法的 Authorization: Bearer"}');
        req.response.close();
      });
      final HttpAuthTransport transport =
          HttpAuthTransport(baseUrl: Uri.parse('http://127.0.0.1:${server.port}'));
      final LoginSession session =
          LoginSession(transport: transport, store: InMemorySessionStore(), deviceId: 'd');

      await expectLater(
        () => session.sendCode(email: 'me@example.com', purpose: 'register'),
        throwsA(isA<LoginFailure>()
            .having((LoginFailure e) => e.message, 'message', contains('服务端要升级'))),
      );
      transport.close();
      await server.close(force: true);
    });
  });

  group('真实链路 · 起来真的后端，走客户端真的会发的那套代码', () {
    void e2e(String name, Future<void> Function() body) =>
        test(name, body, timeout: const Timeout(Duration(seconds: 180)));

    late Process server;
    late Directory tmp;
    late HttpAuthTransport transport;
    final List<String> serverLog = <String>[];
    // ⚠️ 前置条件没满足时 `setUpAll` 会 `fail()`，但 **`tearDownAll` 照样会跑** ——
    // 那时 `transport` 还是未初始化的 late 字段，清理代码会再抛一个
    // LateInitializationError，把真正的原因埋掉（第一版就是这样）。
    bool started = false;

    setUpAll(() async {
      final ProcessResult nodeVersion;
      try {
        nodeVersion = await Process.run('node', <String>['-v']);
      } on ProcessException catch (e) {
        fail('这一组测试需要 node（跑真实的极薄后端）：${e.message}');
      }
      final String v = (nodeVersion.stdout as String).trim();
      final List<int> parts =
          v.replaceFirst('v', '').split('.').map((String x) => int.tryParse(x) ?? 0).toList();
      final int major = parts.isNotEmpty ? parts[0] : 0;
      final int minor = parts.length > 1 ? parts[1] : 0;
      if (major < 22 || (major == 22 && minor < 5)) {
        fail('这一组测试需要 Node ≥ 22.5（服务端用 node:sqlite），当前是 $v。');
      }

      tmp = await Directory.systemTemp.createTemp('lianleme-auth-e2e-');
      server = await Process.start('node', <String>[
        _findBackendScript(),
        '--port', '0',
        '--db', '${tmp.path}/backend.sqlite',
        // 账号体系是可选能力：配了邮件通道（这里是"写文件"）才会开
        '--mail-out', '${tmp.path}/mail.ndjson',
        '--auth-secret', 'e2e-secret',
      ]);
      final Stream<String> out = server.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();
      out.listen(serverLog.add);
      server.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(serverLog.add);

      final String line;
      try {
        line = await out
            .firstWhere((String l) => l.contains('http://127.0.0.1:'))
            .timeout(const Duration(seconds: 30));
      } on TimeoutException {
        fail('极薄后端没起来。它的输出：\n${serverLog.join('\n')}');
      }
      transport = HttpAuthTransport(baseUrl: Uri.parse(RegExp(r'http://127\.0\.0\.1:\d+').firstMatch(line)!.group(0)!));
      started = true;
    });

    tearDownAll(() async {
      if (!started) return;
      transport.close();
      server.kill(ProcessSignal.sigkill);
      await server.exitCode;
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    /// 从服务端写下的邮件里取最后一条验证码（`--mail-out` 模式）
    String lastCode() {
      final List<String> lines =
          File('${tmp.path}/mail.ndjson').readAsStringSync().trim().split('\n');
      final String text = (jsonDecode(lines.last) as Map<String, Object?>)['text']! as String;
      return RegExp(r'验证码是 (\d{6})').firstMatch(text)!.group(1)!;
    }

    e2e('注册 → 登录 → 改口令 → 登出 → 注销（真 HTTP，客户端那套代码）', () async {
      final InMemorySessionStore store = InMemorySessionStore();
      final LoginSession session = LoginSession(
        transport: transport, store: store, deviceId: 'e2e-dev', deviceName: '自检机',
      );
      const String email = 'e2e@example.com';

      await session.sendCode(email: email, purpose: 'register');
      final StoredSession registered =
          await session.register(email: email, code: lastCode(), password: _pw);
      expect(registered.accountId, await accountIdFromKey(registered.accountKey));

      // 另一台设备登录：拿到的是**同一把**账号密钥（这就是"换手机也能接着用"）
      final InMemorySessionStore otherStore = InMemorySessionStore();
      final LoginSession other =
          LoginSession(transport: transport, store: otherStore, deviceId: 'e2e-dev-2');
      final StoredSession loggedIn = await other.login(email: email, password: _pw);
      expect(loggedIn.accountId, registered.accountId);
      expect(loggedIn.accountKey, registered.accountKey);

      // 口令错 → 401，且不带任何可区分"邮箱存不存在"的信息
      await expectLater(
        () => other.login(email: email, password: '错口令 wrong-password'),
        throwsA(isA<LoginFailure>().having((LoginFailure e) => e.message, 'message', contains('邮箱或口令不对'))),
      );

      // 改口令：当前口令错要先被拦住（这是服务端在管）
      await expectLater(
        () => other.changePassword(currentPassword: '不是当前口令', newPassword: '新口令很长 abcdefg1'),
        throwsA(isA<LoginFailure>()),
      );
      const String newPw = '新口令很长 abcdefg1';
      await other.changePassword(currentPassword: _pw, newPassword: newPw);

      // 新口令能登、旧口令不能
      final LoginSession third =
          LoginSession(transport: transport, store: InMemorySessionStore(), deviceId: 'e2e-dev-3');
      expect((await third.login(email: email, password: newPw)).accountId, registered.accountId);
      await expectLater(() => third.login(email: email, password: _pw), throwsA(isA<LoginFailure>()));

      // ⚠️ 改口令的副作用之一是**把别的设备踢掉**：最早那台（`session`）手里的令牌
      // 现在应该已经无效 —— 这是设计（"旧口令可能泄漏"的默认假设），必须验到。
      await expectLater(
        () => session.changePassword(currentPassword: _pw, newPassword: '再来一个 abcdefg2'),
        throwsA(isA<LoginFailure>().having((LoginFailure e) => e.isNetwork, 'isNetwork', isFalse)),
      );

      // 登出之后那个令牌立刻失效（用一个**形状对但不存在**的令牌试注销：要 401，不是 404）
      expect(await third.logout(), isNull);
      await expectLater(
        () => transport.deleteAccount('lm1_${'0' * 64}'),
        throwsA(isA<AuthTransportException>()
            .having((AuthTransportException e) => e.statusCode, 'statusCode', 401)),
      );

      // 注销：用一台**当前有效**的会话。账号 + 备份 + 邮箱绑定一起没（再登录必须失败）
      final LoginSession fresh =
          LoginSession(transport: transport, store: InMemorySessionStore(), deviceId: 'e2e-dev-4');
      await fresh.login(email: email, password: newPw);
      await fresh.deleteAccount();
      await expectLater(() => fresh.login(email: email, password: newPw), throwsA(isA<LoginFailure>()));
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
