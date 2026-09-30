/// 练了么 · 启动冒烟测试
///
/// ⚠️ **这个文件名是刻意占位的。**
/// `flutter create`（阶段 2 补平台目录时跑）默认会生成 `test/widget_test.dart`，
/// 内容是一个引用 `MyApp` 的计数器测试 —— 我们的入口叫 `LianLeMeApp`，
/// 那个文件会让 `flutter test` 直接编译失败。
/// `flutter create` 不覆盖已存在的文件，所以先占住这个名字。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/main.dart';

void main() {
  testWidgets('App 能启动，显示「练」空态', (WidgetTester tester) async {
    // 注入内存库：widget 测试里没有 path_provider 的平台通道，
    // 让 App 自己去 openAppDatabase() 会直接抛错。
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // 预置"已同意隐私政策"：首次启动多了一道同意门（法律要求）。
    // 那道门本身由 privacy_consent_test.dart 覆盖 —— 这里测的是启动冒烟。
    await ProfileRepository(db).setPrivacyConsent(nowMs: 1);
    await tester.pumpWidget(LianLeMeApp(database: db));
    await tester.pumpAndSettle();

    // 空态的主操作，也是全产品唯一的入口
    expect(find.text('开始今天的训练'), findsOneWidget);
    expect(find.byKey(const Key('start-workout')), findsOneWidget);

    // 三个 Tab，封顶就是三个
    expect(find.text('练'), findsOneWidget);
    expect(find.text('进步'), findsOneWidget);
    expect(find.text('我'), findsOneWidget);

    // 必须销毁页面：外壳里有两个埋点上报定时器（冷启动 5 秒 + 前台每 60 秒），
    // 不销毁的话 testWidgets 会因 pending timer 直接判失败。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('同意隐私政策之后，空态不再有任何前置弹窗',
      (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // ⚠️ 这条断言的**前提变了**（2026-09-30）：以前是"启动没有任何前置弹窗"，
    // 现在首次启动**必须有**一道隐私政策同意门（国内商店的硬要求）。
    // 所以改成"同意之后不再有别的门" —— 把变化写在这里，而不是悄悄放宽断言。
    await ProfileRepository(db).setPrivacyConsent(nowMs: 1);
    await tester.pumpWidget(LianLeMeApp(database: db));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('consent-agree')), findsNothing,
        reason: '同意过就不该再弹');
    // 第一屏不应该出现引导、登录、权限之类的东西
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('登录'), findsNothing);
    expect(find.textContaining('注册'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink()); // 同上：销毁定时器
  });
}
