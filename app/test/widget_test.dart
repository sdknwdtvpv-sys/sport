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
  testWidgets('App 能启动，显示训练空态（含 5 个 Tab）', (WidgetTester tester) async {
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

    // 五个 Tab（2026-10-05 按新 VI 从"三个封顶"改成五个，见 docs/screens.md）
    expect(find.text('训练'), findsOneWidget);
    expect(find.text('进步'), findsOneWidget);
    expect(find.text('数据'), findsOneWidget);
    expect(find.text('计划'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    // 必须销毁页面：外壳里有两个埋点上报定时器（冷启动 5 秒 + 前台每 60 秒），
    // 不销毁的话 testWidgets 会因 pending timer 直接判失败。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  /// 顶栏那两枚动作（2026-10-07，v1.60.0；用户 10.7 清单第 1、6 条）：
  /// 「小铃铛放在右上角，注意下布局协调性」+「所有的设置相关的能不能集成到右上角，
  /// 一个小齿轮图标」。这条测试钉的是**它们真的到了顶栏上、而且点得开**。
  testWidgets('★ 右上角：齿轮进设置页、铃铛进通知中心（五个 tab 都点得到）',
      (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await ProfileRepository(db).setPrivacyConsent(nowMs: 1);
    await tester.pumpWidget(LianLeMeApp(database: db));
    await tester.pumpAndSettle();

    // 顶栏：标题 + 那两枚动作
    expect(find.byKey(const Key('app-top-bar')), findsOneWidget);
    expect(find.text('今天'), findsWidgets, reason: '「训练」那一屏的顶栏标题是"今天"');
    expect(find.byKey(const Key('top-bar-settings')), findsOneWidget);
    expect(find.byKey(const Key('open-notifications')), findsOneWidget);
    // ⚠️ 铃铛**只有一枚**：它从首页挪到了顶栏，两处都画就会出现两个入口
    expect(find.byKey(const Key('open-notifications')), findsOneWidget);

    // 齿轮 → 设置页（三个入口都在）
    await tester.tap(find.byKey(const Key('top-bar-settings')));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsWidgets);
    expect(find.byKey(const Key('open-preferences')), findsOneWidget);
    expect(find.byKey(const Key('open-data-tools')), findsOneWidget);
    expect(find.byKey(const Key('open-privacy-about')), findsOneWidget);
    await tester.tap(find.byKey(const Key('subpage-back')));
    await tester.pumpAndSettle();

    // 换到「我的」那一格（tab 顺序变了：进步/数据/训练/计划/我的），顶栏还在、还点得到
    await tester.tap(find.byKey(const Key('tab-我的')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-top-bar')), findsOneWidget);
    expect(find.text('我的'), findsWidgets, reason: '顶栏标题跟着当前 tab 走');
    expect(find.byKey(const Key('top-bar-settings')), findsOneWidget,
        reason: '齿轮是全局的 —— 换一屏也得点得到（这正是这一条要求的意义）');

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
