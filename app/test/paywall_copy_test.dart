/// 练了么 · 付费墙判据（M1）
///
/// 这一份测的**不是版式好不好看，而是"该说的话有没有说"**：
/// Apple 3.1.2(c) + Schedule 2 §3.8(b) 要的五项（标题 / 时长 / 价格 / 条款链接 /
/// 隐私政策链接），加上审核惯例那四条（24 小时取消、费用计入 Apple ID、未用试用作废、
/// 恢复购买可见），以及一条我们自己的规矩：**价格只能来自商店、不许硬编码**。
///
/// 判据编号对应 `docs/plan-membership-2026-10-10.md` §九 判据 2 与 14。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/billing/entitlement.dart';
import 'package:lianleme/billing/paywall_copy.dart';
import 'package:lianleme/billing/paywall_screen.dart';
import 'package:lianleme/billing/subscription_terms_screen.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/entitlement_repository.dart';

/// 测试用的假商品目录：**价格由测试给**，界面只能照抄 —— 这正是"价格来自商店"的判据形状。
class _FakeCatalog implements PaywallCatalog {
  const _FakeCatalog(this.products);
  final List<UltraProductView> products;
  @override
  Future<List<UltraProductView>> load() async => products;
}

const List<UltraProductView> _kThree = <UltraProductView>[
  UltraProductView(
    id: 'ultra.monthly',
    product: UltraProduct.monthly,
    title: 'Ultra 月订阅',
    duration: '每月',
    priceLabel: '¥18.00',
  ),
  UltraProductView(
    id: 'ultra.yearly',
    product: UltraProduct.yearly,
    title: 'Ultra 年订阅',
    duration: '1 年',
    priceLabel: r'$14.99',
    trialDays: 7,
    recommended: true,
  ),
  UltraProductView(
    id: 'ultra.lifetime',
    product: UltraProduct.lifetime,
    title: 'Ultra 终身',
    duration: '一次性买断',
    priceLabel: '¥198.00',
  ),
];

void main() {
  late AppDatabase db;
  late EntitlementRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = EntitlementRepository(db);
  });
  tearDown(() => db.close());

  Future<void> pumpPaywall(WidgetTester tester, {PaywallCatalog? catalog}) async {
    // ⚠️ **把测试窗口调高**：这一屏是 `ProfileSubPage`（内层是 ListView，**懒构建**），
    // 默认 800×600 放不下"权益清单 + 三档价格 + 说明块 + 三个入口"，
    // 于是下半屏的 key 根本不会被建出来 —— 表现为"产品标题找不到"，
    // 而它在真机上是存在的。要么滚、要么给够高度；给高度更省事也更快。
    tester.view.physicalSize = const Size(500, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: PaywallScreen(
        repository: repo,
        catalog: catalog ?? const _FakeCatalog(_kThree),
        now: () => DateTime(2026, 10, 10, 12),
      ),
    ));
    // ⚠️ **不能用 `pumpAndSettle`**：这一屏加载时会转圈，而转圈是无限动画 ——
    // settle 永远等不到静止（仓库里踩过不止一次，见 `screenshots_test.dart` 文件头）。
    // 改成推进固定时长：足够让 drift 的异步读与 catalog 的 Future 落地。
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  group('Apple 3.1.2(c) 要的五项，逐项断言', () {
    testWidgets('①标题 ②时长 ③价格：三档都在，且**价格是商店给的那个字符串**', (WidgetTester tester) async {
      await pumpPaywall(tester);
      for (final UltraProductView p in _kThree) {
        expect(find.byKey(Key('product-title-${p.product.name}')), findsOneWidget);
        expect(find.byKey(Key('product-price-${p.product.name}')), findsOneWidget);
      }
      // 价格逐字来自 catalog（不是界面自己拼的）
      expect(find.text('¥18.00'), findsOneWidget);
      expect(find.text('\$14.99'), findsOneWidget, reason: '海外价也要照抄商店返回值');
      expect(find.text('¥198.00'), findsOneWidget);
      // 时长与试用写在副标题里
      expect(find.text('1 年 · 前 7 天免费'), findsOneWidget);
      expect(find.text('每月'), findsOneWidget);
    });

    testWidgets('换一个价格 → 界面跟着换（证明它读的是商品对象，不是常量）', (WidgetTester tester) async {
      await pumpPaywall(
        tester,
        catalog: const _FakeCatalog(<UltraProductView>[
          UltraProductView(
            id: 'ultra.monthly',
            product: UltraProduct.monthly,
            title: 'Ultra 月订阅',
            duration: '每月',
            priceLabel: r'US$2.99',
          ),
        ]),
      );
      expect(find.text('US\$2.99'), findsOneWidget);
      expect(find.text('¥18.00'), findsNothing);
    });

    testWidgets('④条款入口 ⑤隐私政策入口：都在这一屏，而且都点得开', (WidgetTester tester) async {
      await pumpPaywall(tester);
      expect(find.byKey(const Key('open-subscription-terms')), findsOneWidget);
      expect(find.byKey(const Key('open-privacy-from-paywall')), findsOneWidget);

      await tester.tap(find.byKey(const Key('open-subscription-terms')));
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(find.byType(SubscriptionTermsScreen), findsOneWidget);
      // 条款正文里那几条与"自动续期/取消/退款"直接相关的，必须真的写着
      expect(find.textContaining('自动续期'), findsWidgets);
      expect(find.textContaining('退款'), findsWidgets);
      expect(find.textContaining('取消'), findsWidgets);
    });
  });

  group('审核惯例那四条（判据 14）', () {
    testWidgets('24 小时取消 / 计入 Apple ID / 试用作废 / 每次扣费前提醒 —— 四条都在说明块里',
        (WidgetTester tester) async {
      await pumpPaywall(tester);
      expect(find.byKey(const Key('ultra-disclosure')), findsOneWidget);
      expect(find.text(PaywallCopy.autoRenew), findsOneWidget);
      expect(find.text(PaywallCopy.chargedToAppleId), findsOneWidget);
      expect(find.text(PaywallCopy.trialForfeited), findsOneWidget);
      expect(find.text(PaywallCopy.renewReminder), findsOneWidget,
          reason: '中国大陆要求每次扣款前显著提醒（《互联网平台价格行为规则》）');
    });

    testWidgets('恢复购买**可见**，管理订阅点得开（并给出自己取消的路径）', (WidgetTester tester) async {
      await pumpPaywall(tester);
      expect(find.byKey(const Key('restore-purchases')), findsOneWidget);
      await tester.tap(find.byKey(const Key('manage-subscription')));
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(find.textContaining('App Store'), findsWidgets);
      expect(find.textContaining('订阅'), findsWidgets);
      await tester.tap(find.byKey(const Key('manage-close')));
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
    });

    testWidgets('终身版的范围写清楚（"终身含无限云"是卖欠条）', (WidgetTester tester) async {
      await pumpPaywall(tester);
      expect(find.byKey(const Key('ultra-lifetime-scope')), findsOneWidget);
      expect(find.textContaining('1 份云备份'), findsWidgets);
    });

    testWidgets('未成年人提示在（《未成年人网络保护条例》第四十四/四十五条）', (WidgetTester tester) async {
      await pumpPaywall(tester);
      expect(find.text(PaywallCopy.minors), findsOneWidget);
    });
  });

  group('拿不到商品时**如实说**（不编价格、不放点了没反应的按钮）', () {
    testWidgets('默认目录（release 在 M1 阶段就是这个）→ 只有一行说明，没有购买按钮', (WidgetTester tester) async {
      await pumpPaywall(tester, catalog: const UnavailablePaywallCatalog());
      expect(find.byKey(const Key('ultra-unavailable')), findsOneWidget);
      expect(find.byKey(const Key('buy-yearly')), findsNothing);
      expect(find.byKey(const Key('ultra-disclosure')), findsNothing,
          reason: '没有价格就没有"续费说明"可言 —— 说明块是为购买服务的');
    });

    testWidgets('★ 扫源码：付费墙里**不许出现写死的货币符号**（价格只能来自商店）',
        (WidgetTester tester) async {
      final String src = File('lib/billing/paywall_screen.dart').readAsStringSync();
      expect(src.contains('¥'), isFalse, reason: '界面代码里出现 ¥ 就意味着价格被写死了');
      expect(src.contains(r'$'), isTrue); // 只是确认文件读到了（Dart 里 $ 到处都是）
    });
  });

  group('状态与降级：每一态都要有**人话**（判据 1 的界面侧）', () {
    test('九种状态各自有一句话，且互不相同', () {
      final Set<String> lines = <String>{};
      for (final UltraState s in UltraState.values) {
        final UltraAccess a = UltraAccess(ultra: false, state: s);
        final String line = PaywallCopy.statusLine(a, expiresOn: '2027 年 1 月 1 日');
        expect(line.trim(), isNotEmpty, reason: '$s 没有文案');
        lines.add(line);
      }
      expect(lines.length, UltraState.values.length, reason: '状态文案不能两条一模一样');
    });

    test('有效与试用都会把"到哪天"写进去（用户最想知道的就这一件事）', () {
      expect(
          PaywallCopy.statusLine(
              const UltraAccess(ultra: true, state: UltraState.active),
              expiresOn: '2027 年 1 月 1 日'),
          contains('2027 年 1 月 1 日'));
      expect(
          PaywallCopy.statusLine(
              const UltraAccess(ultra: true, state: UltraState.trial),
              expiresOn: '2026 年 10 月 17 日'),
          contains('2026 年 10 月 17 日'));
    });

    test('到期/退款那几句必须提"数据没少"或"已停用"（不能只写一个冷冰冰的状态词）', () {
      expect(
          PaywallCopy.statusLine(const UltraAccess(ultra: false, state: UltraState.expired),
              expiresOn: null),
          contains('数据'));
      expect(
          PaywallCopy.statusLine(const UltraAccess(ultra: false, state: UltraState.refunded),
              expiresOn: null),
          contains('退款'));
    });
  });
}
