/// 练了么 · **身份：昵称 + 账号 ID**（2026-10-07，v1.60.0，10.7 清单第 7 条）
///
/// 用户原话："现在账户只展示【我】，没办法有用户的名字，很难有身份感。能不能昵称+ID？"
///
/// 这个文件钉三件事，每一件都对应一条**边界**（写在这里，免得以后有人把昵称当账号用）：
///   1. **昵称是纯本地的**：能存能读、空白等于没设（存 null 而不是空串）；
///   2. **昵称不许被别的设置顺手抹掉**（可空列在 insertOnConflictUpdate 里的老坑）；
///   3. **ID 只在登录之后才有**：没登录时界面如实写"还没登录"，**不编一个号**
///      （编出来的号既不是账号也不是设备号，那是假身份）。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/core/units.dart';
import 'package:lianleme/data/db.dart' hide SetRecord, Workout, Exercise, WorkoutItem;
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/profile/identity_screen.dart';

void main() {
  late AppDatabase db;
  late ProfileRepository profile;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    profile = ProfileRepository(db);
  });
  tearDown(() => db.close());

  group('仓库层', () {
    test('没设过 → null（界面据此如实写"还没设昵称"，不编默认名）', () async {
      expect(await profile.nickname(), isNull);
    });

    test('存 / 读：前后空白会被去掉', () async {
      await profile.setNickname('  李松  ', nowMs: 1000);
      expect(await profile.nickname(), '李松');
    });

    test('★ 空白等于没设：存 null 而不是空串（否则界面上会有两种"空"）', () async {
      await profile.setNickname('李松', nowMs: 1000);
      await profile.setNickname('   ', nowMs: 2000);
      expect(await profile.nickname(), isNull);
    });

    test('★ 改别的设置不会把昵称抹掉（可空列的老坑）', () async {
      await profile.setNickname('李松', nowMs: 1000);
      await profile.setUnit(WeightUnit.lb, nowMs: 2000);
      await profile.setAnalyticsEnabled(false, nowMs: 3000);
      await profile.setProgressionMode(ProgressionMode.off, nowMs: 4000);
      expect(await profile.nickname(), '李松',
          reason: '每个 setter 都得把昵称原样带回来 —— 漏一个就是"改一下单位，名字没了"');
    });
  });

  group('账号 ID 的写法', () {
    test('★ 取 account_id 的**前 8 位**十六进制，分组写成 A3F9-21C4', () {
      expect(
        IdentityScreen.shortId(
            'a3f921c4deadbeef00112233445566778899aabbccddeeff00112233445566'),
        'A3F9-21C4',
      );
    });

    test('短于 8 位也不崩（真账号不会，但别让界面抛异常）', () {
      expect(IdentityScreen.shortId('a3f9'), 'A3F9-····');
    });
  });

  group('界面', () {
    Future<void> pumpIdentity(WidgetTester tester, {String? accountId}) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: IdentityScreen(profile: profile, accountId: accountId),
      ));
      // 昵称是异步读出来的：给几帧让 `_load()` 落地即可（不用 pumpAndSettle，
      // 页面里有输入框 —— 聚焦之后光标闪烁会让它永远不 settle）
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('没登录：写"还没登录"，**不给 ID**', (WidgetTester tester) async {
      await pumpIdentity(tester);
      expect(find.text('还没登录'), findsOneWidget);
      expect(find.textContaining('ID 只在登录之后才有'), findsOneWidget);
    });

    testWidgets('登录了：显示那 8 位 + 一句"密钥从不离开这台手机"',
        (WidgetTester tester) async {
      await pumpIdentity(tester, accountId: 'a3f921c4' 'deadbeef');
      expect(find.text('A3F9-21C4'), findsOneWidget);
      expect(find.textContaining('密钥本身从不离开这台手机'), findsOneWidget);
    });

    testWidgets('★ 改昵称：输入 → 保存 → 落库（空着保存 = 清掉昵称）',
        (WidgetTester tester) async {
      await pumpIdentity(tester);
      await tester.enterText(find.byKey(const Key('nickname-field')), '李松');
      await tester.tap(find.byKey(const Key('nickname-save')));
      // ⚠️ 输入框聚焦之后光标一直在闪，`pumpAndSettle` **永远不会 settle**
      // （仓库里早记着这条：cursor blink + pumpAndSettle = 超时）。所以这里按帧数 pump。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(await profile.nickname(), '李松');

      // 清空再存 → 回到"没设过"
      await pumpIdentity(tester);
      await tester.enterText(find.byKey(const Key('nickname-field')), '');
      await tester.tap(find.byKey(const Key('nickname-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(await profile.nickname(), isNull, reason: '空白就是没设过，不存空串');

      // 收尾拆树：输入框的光标动画会一直活着 —— 留着它，下一条测试起来时
      // 会带着一个"没结束的动画"，`pumpAndSettle` 当场超时（这条踩过一次）。
      await tester.pumpWidget(const SizedBox.shrink());
    });

    // ⚠️ 「我」页那两行（昵称 / ID）的界面断言**不在这里**，在 `profile_test.dart`
    // 里 —— 那边已经有一套跑得通的 ProfileScreen 泵法（`pumpProfile`）；
    // 这个文件只负责"仓库层 + 身份页"这一半，免得同一件事有两套泵法。
  });
}
