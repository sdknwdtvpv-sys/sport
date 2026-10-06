/// 练了么 · 账号页（登录 / 注册 / 找回 / 改口令 / 注销）
///
/// 这一份钉的是**用户能看到的那些事**，不是函数返回值：
///
///   * 未登录时页面必须自己说清"不登录也能用全部功能"（否则这道门看起来像闸门）；
///   * 注册成功后**恢复码只显示这一次**，而且**不勾"我抄好了"就过不去**；
///   * 本机已经有云备份账号时，注册**绑的是那个账号**（恢复码与云端那份都不作废）；
///   * 口令错的提示用服务端那句话，不是"未知错误"；
///   * **注销要二次确认**；
///   * **离线可用**：已经登录的人在没信号时打开这一页，照样看得见"已登录"，且一个字节都不发。
library;

import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/backup/account_login.dart';
import 'package:lianleme/backup/auth_transport.dart';
import 'package:lianleme/backup/backup_crypto.dart';
import 'package:lianleme/backup/login_session.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/features/account/account_screen.dart';
import 'package:lianleme/features/profile/profile_screen.dart';

/// 测试用的便宜 KDF 参数（默认档一次约 0.2 秒，并发跑整套门禁时会拖到超时）
const LoginKdf _fast = LoginKdf(memory: 1024, iterations: 1, parallelism: 1);

class _Harness {
  _Harness(this.db, this.profile, this.transport, this.store, this.session, this.local, this.exercises);

  final AppDatabase db;
  final ProfileRepository profile;
  final DriftLocalStore local;
  final ExerciseRepository exercises;
  final FakeAuthTransport transport;
  final InMemorySessionStore store;
  final LoginSession session;

  Widget wrap() => MaterialApp(
        theme: buildAppTheme(),
        home: AccountScreen(session: session, profile: profile),
      );

  void dispose() => db.close();
}

Future<_Harness> _harness() async {
  final AppDatabase db = AppDatabase(NativeDatabase.memory());
  final FakeAuthTransport transport = FakeAuthTransport(kdf: _fast.encode());
  final InMemorySessionStore store = InMemorySessionStore();
  return _Harness(
    db,
    ProfileRepository(db),
    transport,
    store,
    LoginSession(transport: transport, store: store, deviceId: 't-dev'),
    DriftLocalStore(db),
    ExerciseRepository(db),
  );
}

Future<void> _type(WidgetTester tester, Key key, String text) async {
  await tester.enterText(find.byKey(key), text);
  await tester.pump();
}

/// **不用 `pumpAndSettle`** —— 这一套用例第一次跑就卡在这里，两个原因叠在一起：
///
///   1. 输入框拿到焦点之后光标会**一直闪**（每 500ms 一帧），`pumpAndSettle` 会一路泵到
///      它自己的 10 分钟超时（表现是"测试挂了"，而不是失败）；
///   2. 口令派生是真的异步工作（Argon2id），`pumpAndSettle` 只看帧、**不给真异步留时间**，
///      于是它会在"还没开始注册"的状态下就返回（第一版就是这么误判的：断言找不到恢复码）。
///
/// 所以这里改成"给真异步留时间 + 有限次泵帧"。
Future<void> _settle(WidgetTester tester, {int rounds = 12}) async {
  for (int i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// 泵到某个东西出现为止（最多 [rounds] 轮），比"睡固定时间"稳。
Future<void> _settleUntil(WidgetTester tester, Finder target, {int rounds = 60}) async {
  for (int i = 0; i < rounds; i++) {
    if (target.evaluate().isNotEmpty) break;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pump();
  await _settle(tester);
}

/// 点一下，然后等某个结果出现（注册/登录这种要等真异步的用它）
Future<void> _tapAndWait(WidgetTester tester, Key key, Finder target) async {
  await tester.tap(find.byKey(key));
  await tester.pump();
  await _settleUntil(tester, target);
}

void main() {
  late _Harness h;
  setUp(() async => h = await _harness());
  tearDown(() => h.dispose());

  group('未登录', () {
    testWidgets('页面自己说清"不登录也能用"，并给两条路', (WidgetTester tester) async {
      await tester.pumpWidget(h.wrap());
      await _settle(tester);

      expect(find.textContaining('不登录照样能用全部功能'), findsOneWidget);
      expect(find.textContaining('口令不会离开这台手机'), findsOneWidget);
      expect(find.byKey(const Key('account-register')), findsOneWidget);
      expect(find.byKey(const Key('account-login')), findsOneWidget);
    });
  });

  group('注册', () {
    testWidgets('邮箱 → 验证码 → 口令 → 出恢复码，且不勾"抄好了"就过不去',
        (WidgetTester tester) async {
      await tester.pumpWidget(h.wrap());
      await _settle(tester);
      await _tap(tester, const Key('account-register'));

      await _type(tester, const Key('account-email'), 'new@example.com');
      await _tap(tester, const Key('account-send-code'));
      expect(h.transport.calls, contains('code:new@example.com:register'));
      expect(find.textContaining('验证码已经发出'), findsOneWidget);

      await _type(tester, const Key('account-code'), '123456');
      await _type(tester, const Key('account-password'), '正确的马口令 horse-battery-staple');
      await _tapAndWait(tester, const Key('account-submit'), find.byKey(const Key('account-done')));

      // 恢复码只显示这一次
      final Finder code = find.byKey(const Key('account-recovery-code'));
      expect(code, findsOneWidget);
      final String shown = tester.widget<SelectableText>(code).data!;
      expect(shown.replaceAll('-', '').length, 27);
      // 它就是账号密钥：算出来的 accountId 必须与会话里的那个一致
      final StoredSession session = (await h.store.read())!;
      expect(await accountIdFromKey(session.accountKey), session.accountId);
      expect(shown.replaceAll('-', ''), recoveryCodeFor(session.accountKey).replaceAll('-', ''));

      // 没勾"抄好了"时，完成按钮是禁用的
      final FilledButton done = tester.widget<FilledButton>(find.byKey(const Key('account-done')));
      expect(done.onPressed, isNull, reason: '不勾就不许过 —— 这一步之后恢复码不再完整显示');
      await _tap(tester, const Key('account-wrote-check'));
      final FilledButton after = tester.widget<FilledButton>(find.byKey(const Key('account-done')));
      expect(after.onPressed, isNotNull);
      await _tap(tester, const Key('account-done'));
      expect(find.byKey(const Key('account-current-email')), findsOneWidget);
    });

    testWidgets('本机已有云备份账号 → 注册绑的是**那个**账号，恢复码不变', (WidgetTester tester) async {
      // 造一个"老用户"：本机已经有恢复码（云备份账号）
      final Uint8List key = Uint8List.fromList(List<int>.generate(16, (int i) => (i * 17) % 256));
      final String existing = recoveryCodeFor(key);
      await h.profile.setCloudAccount(existing, nowMs: 1000);
      h.transport.accountId = await accountIdFromKey(key);

      await tester.pumpWidget(h.wrap());
      await _settle(tester);
      await _tap(tester, const Key('account-register'));
      await _type(tester, const Key('account-email'), 'old@example.com');
      await _tap(tester, const Key('account-send-code'));
      await _type(tester, const Key('account-code'), '654321');
      await _type(tester, const Key('account-password'), '正确的马口令 horse-battery-staple');
      await _tapAndWait(tester, const Key('account-submit'), find.byKey(const Key('account-done')));

      final StoredSession? session = await h.store.read();
      expect(session!.accountKey, key, reason: '绑的是原来那把密钥，不新建');
      expect(session.accountId, await accountIdFromRecoveryCode(existing));
      // 绑的是老账号 → 不需要再抄一次恢复码，直接能完成
      expect(find.byKey(const Key('account-recovery-code')), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(const Key('account-done'))).onPressed, isNotNull);
    });
  });

  group('登录', () {
    testWidgets('口令错 → 显示服务端那句话，且不留登录态', (WidgetTester tester) async {
      final Uint8List key = Uint8List.fromList(List<int>.filled(16, 3));
      // ⚠️ `prepareAccount` 要走真的 Argon2id —— 在 `testWidgets` 的假异步时钟里
      // 直接 await 它会**永远不返回**（这套用例第二次跑就卡在这一条上）。
      // 真异步必须放进 `tester.runAsync`。
      final PreparedAccount prepared = (await tester.runAsync(() => prepareAccount(
            password: '正确的马口令 horse-battery-staple',
            salt: bytesFromHex(h.transport.saltHex),
            kdf: _fast,
            accountKey: key,
          )))!;
      h.transport
        ..accountId = prepared.accountId
        ..wrapped = prepared.wrapped;

      await tester.pumpWidget(h.wrap());
      await _settle(tester);
      await _tap(tester, const Key('account-login'));
      await _type(tester, const Key('account-email'), 'me@example.com');
      await _type(tester, const Key('account-password'), '不是这个口令');
      await _tapAndWait(tester, const Key('account-submit'), find.byKey(const Key('account-error')));

      expect(find.byKey(const Key('account-error')), findsOneWidget);
      expect(await h.store.read(), isNull, reason: '失败不留半个登录态');
    });

    testWidgets('口令对 → 显示邮箱', (WidgetTester tester) async {
      final Uint8List key = Uint8List.fromList(List<int>.filled(16, 5));
      final PreparedAccount prepared = (await tester.runAsync(() => prepareAccount(
            password: '正确的马口令 horse-battery-staple',
            salt: bytesFromHex(h.transport.saltHex),
            kdf: _fast,
            accountKey: key,
          )))!;
      h.transport
        ..accountId = prepared.accountId
        ..wrapped = prepared.wrapped;

      await tester.pumpWidget(h.wrap());
      await _settle(tester);
      await _tap(tester, const Key('account-login'));
      await _type(tester, const Key('account-email'), 'me@example.com');
      await _type(tester, const Key('account-password'), '正确的马口令 horse-battery-staple');
      await _tapAndWait(tester, const Key('account-submit'), find.byKey(const Key('account-current-email')));

      expect(find.byKey(const Key('account-error')), findsNothing);
      expect(find.text('me@example.com'), findsOneWidget);
    });
  });

  group('离线与注销', () {
    testWidgets('已经登录的人离线打开这一页：看得见邮箱，且一个字节都不发', (WidgetTester tester) async {
      final Uint8List key = Uint8List.fromList(List<int>.filled(16, 9));
      await h.store.write(StoredSession(
        token: 'lm1_${'a' * 64}',
        email: 'offline@example.com',
        accountId: await accountIdFromKey(key),
        accountKey: key,
        saltHex: h.transport.saltHex,
        kdf: _fast.encode(),
        loginAtMs: 1000,
      ));
      h.transport.failWith['salt'] = const AuthTransportException('连不上服务器');

      await tester.pumpWidget(h.wrap());
      await _settle(tester);

      expect(find.text('offline@example.com'), findsOneWidget);
      expect(h.transport.calls, isEmpty, reason: 'restore 只读本地');
    });

    testWidgets('注销必须二次确认；确认后清干净', (WidgetTester tester) async {
      final Uint8List key = Uint8List.fromList(List<int>.filled(16, 11));
      await h.store.write(StoredSession(
        token: 'lm1_${'b' * 64}',
        email: 'bye@example.com',
        accountId: await accountIdFromKey(key),
        accountKey: key,
        saltHex: h.transport.saltHex,
        kdf: _fast.encode(),
        loginAtMs: 1000,
      ));

      await tester.pumpWidget(h.wrap());
      await _settle(tester);
      await _tap(tester, const Key('account-delete'));
      expect(find.byKey(const Key('account-delete-confirm')), findsOneWidget);
      // 先"算了"
      await _tap(tester, const Key('account-delete-cancel'));
      expect(await h.store.read(), isNotNull, reason: '没确认就不许删');
      expect(h.transport.calls, isEmpty);

      await _tap(tester, const Key('account-delete'));
      await _tap(tester, const Key('account-delete-confirm'));
      expect(h.transport.calls, contains('deleteAccount'));
      expect(await h.store.read(), isNull);
      expect(find.byKey(const Key('account-register')), findsOneWidget, reason: '回到未登录态');
    });

    testWidgets('登出：本地清了，但云端那份还在（文案上分开）', (WidgetTester tester) async {
      final Uint8List key = Uint8List.fromList(List<int>.filled(16, 13));
      await h.store.write(StoredSession(
        token: 'lm1_${'c' * 64}',
        email: 'out@example.com',
        accountId: await accountIdFromKey(key),
        accountKey: key,
        saltHex: h.transport.saltHex,
        kdf: _fast.encode(),
        loginAtMs: 1000,
      ));

      await tester.pumpWidget(h.wrap());
      await _settle(tester);
      expect(find.textContaining('云端那份还在'), findsOneWidget);
      await _tap(tester, const Key('account-logout'));
      expect(h.transport.calls, contains('logout'));
      expect(await h.store.read(), isNull);
    });
  });

  group('找回与改口令', () {
    testWidgets('恢复码抄错 → 本地就拦下来，一个字节都不发', (WidgetTester tester) async {
      await tester.pumpWidget(h.wrap());
      await _settle(tester);
      await _tap(tester, const Key('account-login'));
      await _tap(tester, const Key('account-forgot'));

      await _type(tester, const Key('account-recovery-input'), 'ABCDE-FGHJK-LMNPQ-RSTUV-WXYZ2-34568');
      await _type(tester, const Key('account-email'), 'me@example.com');
      await _tap(tester, const Key('account-send-code'));
      h.transport.calls.clear();
      await _type(tester, const Key('account-code'), '111111');
      await _type(tester, const Key('account-password'), '新的马口令 horse-battery-staple');
      await _tapAndWait(tester, const Key('account-submit'), find.byKey(const Key('account-error')));

      expect(find.byKey(const Key('account-error')), findsOneWidget);
      expect(find.textContaining('恢复码'), findsWidgets);
    });

    testWidgets('改口令：当前口令错要如实报，对了就提示其他设备已失效', (WidgetTester tester) async {
      final Uint8List key = Uint8List.fromList(List<int>.filled(16, 17));
      await h.store.write(StoredSession(
        token: 'lm1_${'d' * 64}',
        email: 'pw@example.com',
        accountId: await accountIdFromKey(key),
        accountKey: key,
        saltHex: h.transport.saltHex,
        kdf: _fast.encode(),
        loginAtMs: 1000,
      ));
      h.transport.failWith['changePassword'] =
          const AuthTransportException('当前口令不对', statusCode: 401);

      await tester.pumpWidget(h.wrap());
      await _settle(tester);
      await _tap(tester, const Key('account-change-password'));
      await _type(tester, const Key('account-current-password'), '错的口令');
      await _type(tester, const Key('account-new-password'), '新的马口令 horse-battery-staple');
      await _tapAndWait(tester, const Key('account-submit'), find.byKey(const Key('account-error')));
      expect(find.byKey(const Key('account-error')), findsOneWidget);
      expect(find.text('当前口令不对'), findsOneWidget);
    });
  });

  group('入口（决定这个功能到底出不出现在用户面前）', () {
    Future<void> openDataTools(WidgetTester tester) async {
      final Finder entry = find.byKey(const Key('open-data-tools'));
      await tester.dragUntilVisible(entry, find.byType(ListView), const Offset(0, -220));
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
    }

    testWidgets('没配服务器地址 → 连入口都没有', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ProfileScreen(
            store: h.local,
            repository: h.exercises,
            profile: h.profile,
            cloudBackupAvailable: false,
            account: h.session,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await openDataTools(tester);
      expect(find.byKey(const Key('account')), findsNothing);
    });

    testWidgets('配了地址 → 入口出现，点进去是账号页', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ProfileScreen(
            store: h.local,
            repository: h.exercises,
            profile: h.profile,
            cloudBackupAvailable: true,
            account: h.session,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await openDataTools(tester);

      final Finder entry = find.byKey(const Key('account'));
      await tester.dragUntilVisible(entry, find.byType(ListView), const Offset(0, -220));
      await tester.pumpAndSettle();
      expect(entry, findsOneWidget);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.text('注册一个账号'), findsOneWidget);
    });
  });
}
