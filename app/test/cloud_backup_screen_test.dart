/// 练了么 · 云备份界面
///
/// 这一屏的测试盯的不是"按钮能不能点"，而是**界面有没有撒谎**。三处最容易撒谎的地方：
///
///   1. **"上次备份于…"**：上传失败时如果也记时间，用户会以为数据安全了。
///      所以有一条测试专门造失败，断言时间**没被改**。
///   2. **恢复码只出现一次**：没勾"我抄好了"就不许过去 —— 那串码丢了就真找不回。
///   3. **"关闭"和"注销"不是一件事**：关闭只清本机（云端还在），注销才真删。
///      两条路径分别断言假传输里那份密文**在不在**。
///
/// 另外还守着一条产品级的边界：**没配服务器地址的正式包里，「我」页连入口都没有**。
library;

import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/backup/backup_crypto.dart';
import 'package:lianleme/backup/backup_transport.dart';
import 'package:lianleme/backup/cloud_backup.dart';
import 'package:lianleme/backup/recovery_code.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart'
    hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/backup/cloud_backup_screen.dart';
import 'package:lianleme/features/profile/profile_screen.dart';

/// 一个**校验位正确**的恢复码。
///
/// ⚠️ 别在这里手写一串好看的字符：`decodeRecoveryKey` 会验校验位，
/// 瞎编的码在派生账号时直接抛 `恢复码校验位对不上`（第一次就是这么写的，
/// 被恢复码那一层当场抓住 —— 这个校验位不是装饰）。
String _code() => encodeRecoveryKey(
      Uint8List.fromList(List<int>.generate(16, (int i) => (i * 7 + 3) % 256)),
    );

/// 给人看的那一版（5 位一组）
String _shownCode() => formatRecoveryCode(_code());

/// 当前恢复码对应的 account_id（假传输是按它存东西的）
Future<String?> _idOf(_Harness h) async {
  final BackupAccountData? row = await h.profile.cloudAccount();
  return row == null ? null : accountIdFromRecoveryCode(row.recoveryCode);
}

/// 一条训练 —— 用它来验证"备份出去的确实是库里的东西"
SetRecord _set({String id = 's1', int atMs = 1000000}) => SetRecord(
      id: id,
      workoutId: 'w1',
      exerciseId: 'ex_bb_bench_press',
      setIndex: 1,
      setType: SetType.normal,
      weightKg: 82.5,
      reps: 5,
      completedAtMs: atMs,
    );

class _Harness {
  _Harness(this.db, this.store, this.profile, this.repository, this.transport);

  final AppDatabase db;
  final DriftLocalStore store;
  final ProfileRepository profile;
  final ExerciseRepository repository;
  final FakeBackupTransport transport;

  CloudBackup get cloud => CloudBackup(transport: transport);

  Future<void> dispose() => db.close();
}

Future<_Harness> _harness() async {
  final AppDatabase db = AppDatabase(NativeDatabase.memory());
  final DriftLocalStore store = DriftLocalStore(db);
  return _Harness(
    db,
    store,
    ProfileRepository(db),
    ExerciseRepository(db),
    FakeBackupTransport(),
  );
}

/// 重新挂载。
///
/// `pumpWidget` 同类型组件会**复用 State**（不会重跑 initState），
/// 而"换了台手机"这类场景要的正是重新读一次库。所以先卸载再挂。
Future<void> _remount(WidgetTester tester, Widget w) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(w);
  await tester.pumpAndSettle();
}

/// 「我」页那两段在最底下，而 **ListView 是懒构建的**：没滚到的 widget 根本不存在。
/// （不滚的话 `find.textContaining('数据只存在这台设备上')` 会落空 —— 不是文案错了。）
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.dragUntilVisible(target, find.byType(ListView), const Offset(0, -220));
  await tester.pumpAndSettle();
}

Widget _wrap(_Harness h, {VoidCallback? onDataChanged}) => MaterialApp(
      theme: buildAppTheme(),
      home: CloudBackupScreen(
        store: h.store,
        repository: h.repository,
        profile: h.profile,
        cloud: h.cloud,
        onDataChanged: onDataChanged,
      ),
    );

void main() {
  // 真实 I/O 不能放进 fake clock 的 testWidgets 里（会把测试挂住），所以夹具在 setUp 建。
  late _Harness h;
  setUp(() async => h = await _harness());
  tearDown(() async => h.dispose());


  group('未开启', () {
    testWidgets('只给「开启」和「我有恢复码」，不显示任何恢复码', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(h));
      await tester.pumpAndSettle();

      expect(find.text('还没开启'), findsOneWidget);
      expect(find.byKey(const Key('cloud-enable')), findsOneWidget);
      expect(find.byKey(const Key('cloud-adopt')), findsOneWidget);
      expect(find.byKey(const Key('cloud-upload')), findsNothing);
      expect(find.byKey(const Key('cloud-code')), findsNothing);
      expect(await h.profile.cloudAccount(), isNull);
    });

    testWidgets('点开启先弹说明：说清"服务端看不到内容"和"丢了找不回"',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(h));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-enable')));
      await tester.pumpAndSettle();

      final Finder dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.textContaining('服务端只拿到密文')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.textContaining('丢了')),
        findsOneWidget,
      );

      // 点「先不用」→ 什么都不该发生（连账号都不该建）
      await tester.tap(find.byKey(const Key('cloud-cancel')));
      await tester.pumpAndSettle();
      expect(h.transport.calls, isEmpty, reason: '取消了却还去建了账号');
      expect(await h.profile.cloudAccount(), isNull);
    });
  });

  group('开启：恢复码必须真的被抄下来', () {
    testWidgets('不勾"我抄好了"时「开启」是灰的，勾上才能继续', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(h));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-enable')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-agree')));
      await tester.pumpAndSettle();

      // 恢复码对话框出现，且是一串合法的 27 位码
      expect(find.byKey(const Key('cloud-new-code')), findsOneWidget);
      final String shown = tester
          .widget<SelectableText>(find.byKey(const Key('cloud-new-code')))
          .data!;
      expect(normalizeRecoveryCode(shown).length, kRecoveryCodeLength);
      expect(formatRecoveryCode(normalizeRecoveryCode(shown)), shown,
          reason: '展示的必须是分组写法（5 位一组）');

      // 没勾 → 按钮不可用
      final TextButton ok =
          tester.widget<TextButton>(find.byKey(const Key('cloud-new-ok')));
      expect(ok.onPressed, isNull, reason: '没确认抄下来就允许通过 = 用户可能永远失去数据');

      await tester.tap(find.byKey(const Key('cloud-wrote-check')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-new-ok')));
      await tester.pumpAndSettle();

      final BackupAccountData? row = await h.profile.cloudAccount();
      expect(row, isNotNull);
      expect(row!.recoveryCode, normalizeRecoveryCode(shown));
      expect(formatRecoveryCode(row.recoveryCode), shown);
      // 服务端只该收到 account_id，不该收到恢复码本身
      for (final String call in h.transport.calls) {
        expect(call.contains(row.recoveryCode), isFalse);
      }
    });

    testWidgets('在恢复码那一步选"算了"→ 不落库（不让用户拿到一个打不开的账号）',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(h));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-enable')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-agree')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cloud-new-cancel')));
      await tester.pumpAndSettle();

      expect(await h.profile.cloudAccount(), isNull);
      expect(find.text('还没开启'), findsOneWidget);
    });

    testWidgets('开着的时候显示恢复码与"还没备份过"', (WidgetTester tester) async {
      await h.profile.setCloudAccount(_code(), nowMs: 1);
      await tester.pumpWidget(_wrap(h));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cloud-code')), findsOneWidget);
      expect(find.text(_shownCode()), findsOneWidget);
      expect(find.text('还没备份过'), findsOneWidget);
    });
  });

  group('备份：上传的是密文，而且"上次备份"不许撒谎', () {
    testWidgets('立即备份 → 服务端拿到的是密文，界面报出条数', (WidgetTester tester) async {
      await h.profile.setCloudAccount(_code(), nowMs: 1);
      await h.store.saveSet(_set());
      await tester.pumpWidget(_wrap(h));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cloud-upload')));
      await tester.pumpAndSettle();

      final BackupAccountData? row = await h.profile.cloudAccount();
      final String accountId =
          await accountIdFromRecoveryCode(row!.recoveryCode);
      final String onServer = h.transport.stored[accountId]!;
      expect(onServer, isNotEmpty);
      for (final String secret in <String>['82.5', 'ex_bb_bench_press', 'weight_kg']) {
        expect(onServer.contains(secret), isFalse, reason: '服务器上有明文：$secret');
      }
      expect(find.byKey(const Key('cloud-notice')), findsOneWidget);
      expect(
        tester.widget<Text>(find.descendant(
            of: find.byKey(const Key('cloud-notice')), matching: find.byType(Text))).data,
        contains('1 次训练'),
      );
      // 时间与大小真的落库了
      expect(row.lastUploadAtMs, isNotNull);
      expect(row.lastUploadBytes, greaterThan(0));
    });

    testWidgets('上传失败 → 明确报错，而且**不**改"上次备份于…"', (WidgetTester tester) async {
      await h.profile.setCloudAccount(_code(), nowMs: 1);
      await h.profile.markCloudUpload(4096, nowMs: 5555);
      h.transport.failWith = const BackupTransportException('连不上服务器');

      await tester.pumpWidget(_wrap(h));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-upload')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cloud-error')), findsOneWidget);
      expect(find.textContaining('连不上服务器'), findsOneWidget);
      final BackupAccountData? row = await h.profile.cloudAccount();
      expect(row!.lastUploadAtMs, 5555,
          reason: '失败还改时间 = 界面在撒谎，用户会以为数据安全了');
      expect(
        h.transport.stored[await accountIdFromRecoveryCode(row.recoveryCode)] ?? '',
        isEmpty,
      );
    });
  });

  group('恢复：换手机那条路', () {
    testWidgets('备份 → 清空本机 → 用恢复码取回 → 数据回来了', (WidgetTester tester) async {
      await h.profile.setCloudAccount(_code(), nowMs: 1);
      await h.store.saveSet(_set());
      await tester.pumpWidget(_wrap(h));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-upload')));
      await tester.pumpAndSettle();
      expect(await h.store.allSets(), hasLength(1));

      // 模拟"换了台手机"：本机数据与凭据全清（服务端那份留着）
      await h.store.deleteAllUserData();
      expect(await h.store.allSets(), isEmpty);
      expect(await h.profile.cloudAccount(), isNull);
      final String accountId = h.transport.stored.keys.first;
      expect(h.transport.stored[accountId], isNotEmpty, reason: '云端那份应该还在');

      // 用恢复码接管
      await _remount(tester, _wrap(h));
      await tester.tap(find.byKey(const Key('cloud-adopt')));
      await tester.pumpAndSettle();
      // 故意用小写 + 连字符（用户从纸上抄回来的样子）
      await tester.enterText(
          find.byKey(const Key('cloud-adopt-input')), _shownCode().toLowerCase());
      await tester.tap(find.byKey(const Key('cloud-adopt-ok')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cloud-restore')));
      await tester.pumpAndSettle();

      final List<SetRecord> back = await h.store.allSets();
      expect(back, hasLength(1), reason: '从云端恢复之后本机应该有这条记录');
      expect(back.first.weightKg, 82.5);
      expect(back.first.reps, 5);
    });

    testWidgets('恢复会通知上层刷新（否则首页还显示旧数字）', (WidgetTester tester) async {
      await h.profile.setCloudAccount(_code(), nowMs: 1);
      await h.store.saveSet(_set());
      bool notified = false;
      await tester.pumpWidget(_wrap(h, onDataChanged: () => notified = true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-upload')));
      await tester.pumpAndSettle();
      await h.store.deleteAllUserData();
      await h.profile.setCloudAccount(_code(), nowMs: 1);

      await _remount(tester, _wrap(h, onDataChanged: () => notified = true));
      await tester.tap(find.byKey(const Key('cloud-restore')));
      await tester.pumpAndSettle();
      expect(notified, isTrue);
    });

    testWidgets('云端没有备份时如实说"还没有"，不是一片空白', (WidgetTester tester) async {
      await h.profile.setCloudAccount(_code(), nowMs: 1);
      await tester.pumpWidget(_wrap(h));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-restore')));
      await tester.pumpAndSettle();
      expect(find.textContaining('云端还没有备份'), findsOneWidget);
    });
  });

  group('关闭与注销是两件事', () {
    testWidgets('关闭：只清本机，云端那份还在', (WidgetTester tester) async {
      await h.profile.setCloudAccount(_code(), nowMs: 1);
      await h.store.saveSet(_set());
      await tester.pumpWidget(_wrap(h));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-upload')));
      await tester.pumpAndSettle();
      final String accountId = h.transport.stored.keys.first;

      // 底部的按钮在小画布上要滚一下才点得到（ListView 懒构建）
      await _scrollTo(tester, find.byKey(const Key('cloud-disable')));
      await tester.tap(find.byKey(const Key('cloud-disable')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-disable-ok')));
      await tester.pumpAndSettle();

      expect(await h.profile.cloudAccount(), isNull);
      expect(h.transport.stored[accountId], isNotEmpty,
          reason: '关闭只清本机凭据；云端删了的话，用户就真的取不回来了');
      expect(find.text('还没开启'), findsOneWidget);
    });

    testWidgets('注销：云端那份真的没了', (WidgetTester tester) async {
      await h.profile.setCloudAccount(_code(), nowMs: 1);
      await h.store.saveSet(_set());
      await tester.pumpWidget(_wrap(h));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-upload')));
      await tester.pumpAndSettle();
      final String accountId = h.transport.stored.keys.first;

      await _scrollTo(tester, find.byKey(const Key('cloud-delete')));
      await tester.tap(find.byKey(const Key('cloud-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-delete-ok')));
      await tester.pumpAndSettle();

      expect(h.transport.stored.containsKey(accountId), isFalse);
      expect(await h.profile.cloudAccount(), isNull);
      expect(find.textContaining('已删除'), findsOneWidget);
      // 本机数据不受影响
      expect(await h.store.allSets(), hasLength(1));
    });
  });

  group('云端状态：另一台设备写过，必须看得见', () {
    testWidgets('显示云端的真实状态（大小 / 时间 / 设备数）', (WidgetTester tester) async {
      await h.profile.setCloudAccount(_code(), nowMs: 1);
      await h.store.saveSet(_set());
      await h.cloud.upload(recoveryCode: _code(), plaintext: '{"n":1}');
      h.transport.devices = 2;

      await tester.pumpWidget(_wrap(h));
      await tester.pumpAndSettle();

      final String shown =
          tester.widget<Text>(find.byKey(const Key('cloud-server-state'))).data!;
      expect(shown, startsWith('云端：'));
      expect(shown, contains('2 台设备'));
      expect(shown, contains('·'), reason: '要有大小与时间两段');
    });

    testWidgets('账号在但还没备份 → 说"云端还没有备份"', (WidgetTester tester) async {
      await h.profile.setCloudAccount(_code(), nowMs: 1);
      // 先登记账号（本地那一行不代表服务端认识它）
      await h.cloud.register(_code());
      await tester.pumpWidget(_wrap(h));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('cloud-server-state'))).data,
        '云端还没有备份',
      );
    });

    testWidgets('**服务器上没有这个账号** → 也要说，不能沉默', (WidgetTester tester) async {
      // 只在本地存了恢复码、服务端没有这条记录（被别的设备注销过 / 换了库）
      await h.profile.setCloudAccount(_code(), nowMs: 1);
      await tester.pumpWidget(_wrap(h));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('cloud-server-state'))).data,
        contains('服务器上没有这个账号'),
      );
    });

    testWidgets('取不到 → 说"取不到"，但不影响备份按钮', (WidgetTester tester) async {
      await h.profile.setCloudAccount(_code(), nowMs: 1);
      h.transport.failWith = const BackupTransportException('连不上服务器');

      await tester.pumpWidget(_wrap(h));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('cloud-server-state'))).data,
        '云端状态取不到（离线？）',
      );
      // 顺带告诉你"这一行只是顺带告诉你"：按钮还在，点了会给出真实错误
      expect(find.byKey(const Key('cloud-upload')), findsOneWidget);
    });

    testWidgets('云端比本机记录新 → 警告"可能是另一台设备"', (WidgetTester tester) async {
      await h.profile.setCloudAccount(_code(), nowMs: 1);
      await h.store.saveSet(_set());
      await h.cloud.upload(recoveryCode: _code(), plaintext: '{"n":1}');
      // 本机记录停在"很久以前"，而云端是刚刚 —— 正是另一台设备写过的样子
      await h.profile.markCloudUpload(4096, nowMs: 1000);
      h.transport.updatedAt[(await _idOf(h))!] = DateTime.now().millisecondsSinceEpoch;

      await tester.pumpWidget(_wrap(h));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cloud-newer-warning')), findsOneWidget);
      expect(find.textContaining('覆盖'), findsWidgets);
    });

    testWidgets('就是本机刚备份的（只差几秒）→ **不该**瞎警告', (WidgetTester tester) async {
      await h.profile.setCloudAccount(_code(), nowMs: 1);
      final int now = DateTime.now().millisecondsSinceEpoch;
      // 服务端与本机时钟不可能分秒不差 —— 容忍一分钟，别为几秒钟的偏差吓用户
      await h.profile.markCloudUpload(4096, nowMs: now - 5000);
      final String id = (await _idOf(h))!;
      h.transport.stored[id] = 'x';
      h.transport.updatedAt[id] = now;

      await tester.pumpWidget(_wrap(h));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cloud-newer-warning')), findsNothing);
    });
  });

  group('「删除全部数据」必须问云端那一声（政策承诺过）', () {
    /// 把「我」页挂起来，并先造一份云端备份
    Future<void> pumpProfileWithCloud(WidgetTester tester) async {
      await h.profile.setCloudAccount(_code(), nowMs: 1);
      await h.store.saveSet(_set());
      await h.cloud.upload(recoveryCode: _code(), plaintext: '{"n":1}');
      // ⚠️ 必须套 Scaffold：ProfileScreen 自己返回的是一个 ListView，
      // 没有 Scaffold 时 SnackBar 没有地方画 —— `find.textContaining('已删除…')`
      // 会落空，而你会以为是文案写错了。
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ProfileScreen(
            store: h.store,
            repository: h.repository,
            profile: h.profile,
            cloud: h.cloud,
            cloudBackupAvailable: true,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> tapDeleteAll(WidgetTester tester) async {
      await _scrollTo(tester, find.byKey(const Key('delete-all')));
      await tester.tap(find.byKey(const Key('delete-all')));
      await tester.pumpAndSettle();
    }

    testWidgets('有云备份时多问一句，而且默认就是"也删"', (WidgetTester tester) async {
      await pumpProfileWithCloud(tester);
      expect(h.transport.stored, isNotEmpty);

      await tapDeleteAll(tester);
      final Finder box = find.byKey(const Key('delete-all-cloud'));
      expect(box, findsOneWidget, reason: '政策承诺了要问这一句');
      expect(
        tester.widget<CheckboxListTile>(box).value,
        isTrue,
        reason: '用户说的是"删除全部数据"，云端那份默认就该一起删',
      );

      await tester.tap(find.byKey(const Key('delete-all-confirm')));
      await tester.pumpAndSettle();

      expect(h.transport.stored.values.every((String v) => v.isEmpty), isTrue,
          reason: '云端那份应该真没了');
      expect(await h.profile.cloudAccount(), isNull);
      expect(await h.store.allSets(), isEmpty);
      expect(find.textContaining('与云端备份'), findsOneWidget);
    });

    testWidgets('不勾 → 云端那份留着，本机照样清干净', (WidgetTester tester) async {
      await pumpProfileWithCloud(tester);
      final String accountId = h.transport.stored.keys.first;

      await tapDeleteAll(tester);
      await tester.tap(find.byKey(const Key('delete-all-cloud')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete-all-confirm')));
      await tester.pumpAndSettle();

      expect(h.transport.stored[accountId], isNotEmpty,
          reason: '没勾就不该动云端');
      expect(await h.profile.cloudAccount(), isNull);
      expect(await h.store.allSets(), isEmpty);
      expect(find.textContaining('已删除全部数据'), findsOneWidget);
    });

    testWidgets('云端删失败 → **本机一个字都不删**，并如实报错', (WidgetTester tester) async {
      await pumpProfileWithCloud(tester);
      h.transport.failWith = const BackupTransportException('连不上服务器');

      await tapDeleteAll(tester);
      expect(tester.widget<CheckboxListTile>(
        find.byKey(const Key('delete-all-cloud'))).value, isTrue);

      await tester.tap(find.byKey(const Key('delete-all-confirm')));
      await tester.pumpAndSettle();

      // 关键：删了一半比不删更糟。云端没删掉，本机就必须原封不动 ——
      // 否则本机的恢复码一没，云端那份就永远打不开了。
      expect(await h.store.allSets(), hasLength(1));
      expect(await h.profile.cloudAccount(), isNotNull);
      expect(find.textContaining('没删'), findsOneWidget);
    });

    testWidgets('没有云备份时，弹层保持原样（不出现那个勾选框）', (WidgetTester tester) async {
      await h.store.saveSet(_set());
      // ⚠️ 必须套 Scaffold：ProfileScreen 自己返回的是一个 ListView，
      // 没有 Scaffold 时 SnackBar 没有地方画 —— `find.textContaining('已删除…')`
      // 会落空，而你会以为是文案写错了。
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ProfileScreen(
            store: h.store,
            repository: h.repository,
            profile: h.profile,
            cloud: h.cloud,
            cloudBackupAvailable: true,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tapDeleteAll(tester);
      expect(find.byKey(const Key('delete-all-cloud')), findsNothing);
      await tester.tap(find.byKey(const Key('delete-all-confirm')));
      await tester.pumpAndSettle();
      expect(await h.store.allSets(), isEmpty);
    });
  });

  group('「我」页的入口（决定这个功能到底出不出现在用户面前）', () {
    testWidgets('没配服务器地址 → 连入口都没有，而且不说"不上传"以外的话',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ProfileScreen(
            store: h.store,
            repository: h.repository,
            profile: h.profile,
            cloudBackupAvailable: false,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await _scrollTo(tester, find.byKey(const Key('delete-all')));
      expect(find.byKey(const Key('cloud-backup')), findsNothing);
      expect(find.textContaining('数据只存在这台设备上'), findsOneWidget);
    });

    testWidgets('配了地址 → 入口出现，且「关于」那句改成如实的说法',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ProfileScreen(
            store: h.store,
            repository: h.repository,
            profile: h.profile,
            cloudBackupAvailable: true,
            unit: WeightUnit.kg,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final Finder entry = find.byKey(const Key('cloud-backup'));
      await _scrollTo(tester, entry);
      expect(entry, findsOneWidget);
      // 配了云备份还说"不上传任何人"就是撒谎
      await _scrollTo(tester, find.textContaining('端到端加密'));
      expect(find.textContaining('不上传任何人'), findsNothing);
      expect(find.textContaining('端到端加密'), findsOneWidget);

      // 能进去。测试环境两个编译期开关都没有（`LIANLEME_BACKUP_URL` 与
      // `LIANLEME_BACKUP_DISCLOSED` 都没定义），所以这一屏会**如实**说没配服务器
      // —— 这恰好也是正式包里的样子。
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.text('云备份'), findsWidgets);
      expect(find.text('这个版本没有配备份服务器'), findsOneWidget);
      expect(find.byKey(const Key('cloud-enable')), findsNothing);
    });
  });
}
