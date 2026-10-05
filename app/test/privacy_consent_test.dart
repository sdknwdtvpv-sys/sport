/// 练了么 · 首次启动的隐私政策同意
///
/// 这一屏是**法律要求**（国内商店：首次运行须以弹窗等明显方式提示并征得同意；
/// 同意/拒绝按钮语义明确；不得默认勾选；**同意之前不得收集任何个人信息** ——
/// 小米《隐私政策不合规的问题解析和修改指引》，规则来源国信办秘字〔2019〕191 号）。
///
/// 所以这里的断言不止"界面长什么样"：
///   1. **没见过同意时，主界面一个像素都不渲染**（不能先给用户用、再补问）
///   2. **同意之前埋点一条都不许入队** —— 用 outbox 的行数当证据
///      （`app_open` 是启动就会记的事件，所以"库里有 0 行"就是"没开始收集"）
///   3. 拒绝有明确出路（再看政策 / 退出），不装死也不假装能用
///   4. 同意状态落库，重启不再问
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/features/onboarding/intro_carousel_screen.dart';
import 'package:lianleme/features/onboarding/privacy_consent_screen.dart';
import 'package:lianleme/features/profile/privacy_policy_screen.dart';
import 'package:lianleme/main.dart';

/// outbox 里现在有几条事件（= 有没有开始收集）
Future<int> _queued(AppDatabase db) async {
  final List<AnalyticsOutboxData> rows =
      await db.select(db.analyticsOutbox).get();
  return rows.length;
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// 起来之后等一小会儿，让"读同意状态 → 渲染"这条异步链走完。
  ///
  /// ⚠️ 不能 `pumpAndSettle`：外壳里有常驻的埋点定时器（冷启动 5 秒 + 前台每 60 秒），
  /// 永远等不到"静止"。这个坑本项目踩过多次，一律改成定长推进。
  Future<void> settle(WidgetTester tester, [int ms = 1200]) async {
    final DateTime end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  Future<void> boot(WidgetTester tester) async {
    await tester.pumpWidget(LianLeMeApp(database: db));
    await settle(tester);
  }

  /// 销毁页面：外壳里挂着定时器，不销毁 testWidgets 会因 pending timer 判失败
  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester, 200);
  }

  testWidgets('没同意过：**主界面根本不渲染**，只有同意门', (WidgetTester tester) async {
    await boot(tester);

    expect(find.byType(PrivacyConsentScreen), findsOneWidget);
    expect(find.byKey(const Key('consent-agree')), findsOneWidget);
    expect(find.byKey(const Key('consent-refuse')), findsOneWidget);
    // 两个按钮就是同意/拒绝，**没有勾选框** —— 也就没有"默认勾选"这回事
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    // 主界面不该提前出现
    expect(find.byKey(const Key('start-workout')), findsNothing);
    expect(find.text('开始今天的训练'), findsNothing);

    await teardown(tester);
  });

  testWidgets('**同意之前一条事件都不许入队**（拿 outbox 行数当证据）',
      (WidgetTester tester) async {
    await boot(tester);
    expect(find.byType(PrivacyConsentScreen), findsOneWidget);
    expect(await _queued(db), 0,
        reason: '还没同意就开始记事件 = 违规收集（哪怕事件只落在本地）');

    await teardown(tester);
  });

  testWidgets('把开关打开（库里的值）→ 冷启动才真的开始记 —— 启动必须同步用户的选择',
      (WidgetTester tester) async {
    // 这一条守的是 2026-09-30 改默认值时差点漏掉的那根线：库里那一列的默认值改成"关"
    // 之后，若启动时不把**用户的选择**同步进 analytics 对象，就会出现两种最坏情况之一 ——
    // 要么开关显示关着却还在收集，要么开了却一直不发。所以先写 true，看它认不认。
    await ProfileRepository(db).setPrivacyConsent(nowMs: 1);
    await ProfileRepository(db).setAnalyticsEnabled(true, nowMs: 2);
    await boot(tester);
    await settle(tester, 1500);

    expect(await _queued(db), greaterThan(0),
        reason: '库里是开着的 → 冷启动就该开始记（启动时同步了用户的选择）');

    await teardown(tester);
  });

  testWidgets('点了「同意并继续」：落库 + 放行主界面 + **默认仍然一条都不记**',
      (WidgetTester tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const Key('consent-agree')));
    await settle(tester, 1500);

    expect(find.byType(PrivacyConsentScreen), findsNothing);
    // 2026-10-05：同意之后紧接着是**首启引导**（3 屏卖点），跳过才落到主界面 ——
    // 顺序是"同意门 → 引导页 → 主界面"，见 `docs/screens.md` 与引导页的四条约束。
    expect(find.byType(IntroCarouselScreen), findsOneWidget, reason: '引导页就在同意门之后');
    await tester.tap(find.byKey(const Key('intro-skip')));
    await settle(tester, 400);
    expect(find.byType(IntroCarouselScreen), findsNothing);
    expect(find.byKey(const Key('start-workout')), findsOneWidget);
    expect(await ProfileRepository(db).privacyConsentAtMs(), isNotNull,
        reason: '同意状态必须落库，否则下次冷启动又弹');
    // 同意 = 同意那份**政策**；它**不等于**同意匿名统计。
    // 统计是非必需的收集，默认关，要用户自己去「我」页打开（审计 A 的后半段）。
    // 所以这里的期望是 0 —— 而且这比原来那条断言更硬：
    // 顺序错了（先收集后征求同意）会红，把"同意"当成"同意统计"也会红。
    expect(await _queued(db), 0,
        reason: '同意之后仍然一条都不记：匿名统计默认关');
    expect(await ProfileRepository(db).analyticsEnabled(), isFalse,
        reason: '默认关是库里的默认值，不是界面上的假象');

    await teardown(tester);
  });

  testWidgets('已经同意过：不再弹（重启不该反复问）', (WidgetTester tester) async {
    await ProfileRepository(db).setPrivacyConsent(nowMs: 1);
    await boot(tester);
    expect(find.byType(PrivacyConsentScreen), findsNothing);
    expect(find.byKey(const Key('start-workout')), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('点「不同意」：**照样能用**（离线），但一条都不收集', (WidgetTester tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const Key('consent-refuse')));
    await settle(tester, 1500);

    // 191 号文四.2 禁止"因不同意收集非必要信息而拒绝提供业务功能" ——
    // 所以拒绝之后必须能进 App，而不是被请出去。
    expect(find.byType(PrivacyConsentScreen), findsNothing, reason: '拒绝之后要放行');
    // 拒绝收集也照样给他看引导页：它讲的是"这 App 怎么用"，不是"请同意收集"
    expect(find.byType(IntroCarouselScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('intro-skip')));
    await settle(tester, 400);
    expect(find.byKey(const Key('start-workout')), findsOneWidget,
        reason: '本地记录不需要联网与权限，拒绝的代价只是没有匿名统计');
    expect(find.byKey(const Key('consent-exit')), findsNothing,
        reason: '不该再有"退出练了么"那条路');

    // 但**不收集**：outbox 一条都没有，且同意状态没有被写成"同意过"
    expect(await _queued(db), 0, reason: '拒绝了就更不该收集');
    expect(await ProfileRepository(db).privacyConsentAtMs(), isNull,
        reason: '拒绝不能写成同意 —— 那是撒谎');
    expect(await ProfileRepository(db).privacyDeclinedAtMs(), isNotNull,
        reason: '要记住他拒绝过，否则每次冷启动都再问一遍（那是骚扰）');

    await teardown(tester);
  });

  testWidgets('拒绝过之后：不再弹门，但仍然不收集', (WidgetTester tester) async {
    await ProfileRepository(db).setPrivacyDeclined(nowMs: 1);
    await boot(tester);

    expect(find.byType(PrivacyConsentScreen), findsNothing);
    expect(find.byKey(const Key('start-workout')), findsOneWidget);
    expect(await _queued(db), 0, reason: '拒绝过就永远不启动埋点');
    await teardown(tester);
  });

  testWidgets('从同意门能读到隐私政策全文，回来还在原地', (WidgetTester tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const Key('consent-read-policy')));
    await settle(tester, 1500);

    expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
    // 正文是异步读资产的，等它出来（不能 pumpAndSettle：加载时有转圈动画）
    for (int i = 0;
        i < 30 && find.byKey(const Key('privacy-text')).evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('privacy-text')), findsOneWidget);

    await tester.tap(find.byKey(const Key('privacy-back')));
    await settle(tester, 900);
    expect(find.byKey(const Key('consent-agree')), findsOneWidget,
        reason: '看完政策应当回到同意门，而不是被放行');
    expect(await ProfileRepository(db).privacyConsentAtMs(), isNull);

    await teardown(tester);
  });
}
