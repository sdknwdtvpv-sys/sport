/// 练了么 · 会员（Ultra）权益模型与 debug 开关的判据（M1）
///
/// 判据来自 `docs/plan-membership-2026-10-10.md`：
///   * §4.1 那张**九态状态机**表 —— 这里逐态断言；
///   * §九 判据 1「状态机九态全部有测试」；
///   * §九 判据 13「M1 的假开关不许进 release」—— 最后那两条**扫源码**的测试。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/billing/debug_grant.dart';
import 'package:lianleme/billing/entitlement.dart';

const int _now = 1800000000000; // 固定"现在"，避免测试自己带上时钟依赖
const int _day = 24 * 60 * 60 * 1000;

UltraEntitlement _e({
  UltraProduct product = UltraProduct.yearly,
  UltraSource source = UltraSource.apple,
  int? expiresInDays = 30,
  bool isTrial = false,
  int? graceInDays,
  int? retryInDays,
  int? revokedAtMs,
  int? refundedAtMs,
  int? verifiedDaysAgo,
}) =>
    UltraEntitlement(
      id: 'txn-1',
      product: product,
      source: source,
      purchasedAtMs: _now - 100 * _day,
      expiresAtMs: expiresInDays == null ? null : _now + expiresInDays * _day,
      isTrial: isTrial,
      graceUntilMs: graceInDays == null ? null : _now + graceInDays * _day,
      billingRetryUntilMs: retryInDays == null ? null : _now + retryInDays * _day,
      revokedAtMs: revokedAtMs,
      refundedAtMs: refundedAtMs,
      lastVerifiedAtMs: verifiedDaysAgo == null ? _now : _now - verifiedDaysAgo * _day,
    );

void main() {
  group('方案 §4.1 的九态', () {
    test('没有记录 → none（免费用户）', () {
      final UltraAccess a = resolveUltraAccess(null, _now);
      expect(a.state, UltraState.none);
      expect(a.ultra, isFalse);
      expect(a.msLeft, isNull);
    });

    test('试用期内 → trial，且照给', () {
      final UltraAccess a = resolveUltraAccess(_e(isTrial: true, expiresInDays: 5), _now);
      expect(a.state, UltraState.trial);
      expect(a.ultra, isTrue);
      expect(a.msLeft, 5 * _day);
    });

    test('未到期 → active，且照给', () {
      final UltraAccess a = resolveUltraAccess(_e(expiresInDays: 10), _now);
      expect(a.state, UltraState.active);
      expect(a.ultra, isTrue);
      expect(a.msLeft, 10 * _day);
    });

    test('终身（没有到期时间）→ active，且 msLeft 为空（界面写"终身"而不是"还剩 N 天"）', () {
      final UltraAccess a = resolveUltraAccess(
          _e(product: UltraProduct.lifetime, expiresInDays: null), _now);
      expect(a.state, UltraState.active);
      expect(a.ultra, isTrue);
      expect(a.msLeft, isNull);
    });

    test('到期了但还在宽限期 → grace，**照给**（Apple 要求宽限期内继续给）', () {
      final UltraAccess a = resolveUltraAccess(
          _e(expiresInDays: -1, graceInDays: 5), _now);
      expect(a.state, UltraState.grace);
      expect(a.ultra, isTrue);
      expect(a.msLeft, 5 * _day);
    });

    test('宽限期也过了但在账单重试窗内 → billingRetry，**照给**', () {
      final UltraAccess a = resolveUltraAccess(
          _e(expiresInDays: -10, graceInDays: -3, retryInDays: 20), _now);
      expect(a.state, UltraState.billingRetry);
      expect(a.ultra, isTrue);
      expect(a.msLeft, 20 * _day);
    });

    test('到期且不在任何窗口里 → expired，不给', () {
      final UltraAccess a = resolveUltraAccess(
          _e(expiresInDays: -10, graceInDays: -3, retryInDays: -1), _now);
      expect(a.state, UltraState.expired);
      expect(a.ultra, isFalse);
    });

    test('已退款 → refunded，**立即降级**（哪怕到期时间还没到）', () {
      final UltraAccess a =
          resolveUltraAccess(_e(expiresInDays: 20, refundedAtMs: _now - _day), _now);
      expect(a.state, UltraState.refunded);
      expect(a.ultra, isFalse);
    });

    test('已撤销（家庭共享被撤）→ revoked，**立即降级**', () {
      final UltraAccess a =
          resolveUltraAccess(_e(expiresInDays: 20, revokedAtMs: _now - _day), _now);
      expect(a.state, UltraState.revoked);
      expect(a.ultra, isFalse);
    });

    test('offline-grace：缓存说有效、但超过一天没核实 → 照给 + 打上"未核实"标记', () {
      final UltraAccess a = resolveUltraAccess(_e(expiresInDays: 10, verifiedDaysAgo: 3), _now);
      expect(a.ultra, isTrue, reason: '离线不能把付过费的人锁在门外');
      expect(a.unverified, isTrue);
    });

    test('offline-expired：已经到期、而且很久没核实 → 不给 + 同样打标记', () {
      final UltraAccess a = resolveUltraAccess(_e(expiresInDays: -1, verifiedDaysAgo: 30), _now);
      expect(a.ultra, isFalse);
      expect(a.state, UltraState.expired);
      expect(a.unverified, isTrue);
    });

    test('刚核实过（一天内）不打"未核实"标记', () {
      expect(resolveUltraAccess(_e(expiresInDays: 10, verifiedDaysAgo: 0), _now).unverified,
          isFalse);
    });
  });

  group('挑出最该生效的那一条（同一账号可能有多条）', () {
    test('空 → null', () {
      expect(pickBestEntitlement(<UltraEntitlement>[], _now), isNull);
    });

    test('可用的赢过不可用的（哪怕不可用那条"更贵"）', () {
      final UltraEntitlement live = _e(expiresInDays: 1);
      final UltraEntitlement dead = UltraEntitlement(
        id: 'txn-2',
        product: UltraProduct.lifetime,
        source: UltraSource.apple,
        purchasedAtMs: _now - 10 * _day,
        refundedAtMs: _now - _day,
      );
      expect(pickBestEntitlement(<UltraEntitlement>[dead, live], _now)!.id, live.id);
    });

    test('都可用时：终身赢过"到期更晚"的订阅', () {
      final UltraEntitlement life = UltraEntitlement(
        id: 'life',
        product: UltraProduct.lifetime,
        source: UltraSource.apple,
        purchasedAtMs: _now - _day,
      );
      final UltraEntitlement yearly = _e(expiresInDays: 300);
      expect(pickBestEntitlement(<UltraEntitlement>[yearly, life], _now)!.id, 'life');
    });

    test('都可用时取**到期更晚**的', () {
      final UltraEntitlement a = UltraEntitlement(
          id: 'a',
          product: UltraProduct.monthly,
          source: UltraSource.apple,
          purchasedAtMs: _now,
          expiresAtMs: _now + 5 * _day);
      final UltraEntitlement b = UltraEntitlement(
          id: 'b',
          product: UltraProduct.yearly,
          source: UltraSource.apple,
          purchasedAtMs: _now,
          expiresAtMs: _now + 50 * _day);
      expect(pickBestEntitlement(<UltraEntitlement>[a, b], _now)!.id, 'b');
    });

    test('都不可用时，挑信息量最大的那条（"已退款"要说得出，不能只写"已到期"）', () {
      final UltraEntitlement expired = _e(expiresInDays: -10);
      final UltraEntitlement refunded = UltraEntitlement(
        id: 'refunded',
        product: UltraProduct.yearly,
        source: UltraSource.apple,
        purchasedAtMs: _now - 40 * _day,
        expiresAtMs: _now + 10 * _day,
        refundedAtMs: _now - _day,
      );
      expect(pickBestEntitlement(<UltraEntitlement>[expired, refunded], _now)!.id, 'refunded');
    });
  });

  group('商店/服务端事件怎么改本机这一条', () {
    test('续订：写新的到期时间、关掉试用、清掉宽限与重试窗、刷新核实时间', () {
      final UltraEntitlement e = _e(
        isTrial: true,
        expiresInDays: -1,
        graceInDays: 3,
        retryInDays: 20,
        verifiedDaysAgo: 5,
      );
      final UltraEntitlement after = applyBillingEvent(
        e,
        UltraBillingEvent(UltraEventKind.renewed, expiresAtMs: _now + 365 * _day),
        _now,
      );
      expect(after.expiresAtMs, _now + 365 * _day);
      expect(after.isTrial, isFalse);
      expect(after.graceUntilMs, isNull);
      expect(after.billingRetryUntilMs, isNull);
      expect(after.lastVerifiedAtMs, _now);
      expect(resolveUltraAccess(after, _now).state, UltraState.active);
    });

    test('进入宽限期 / 账单重试：写窗口、窗口内照给，且两者**互斥**（进一个就清另一个）', () {
      final UltraEntitlement e = _e(expiresInDays: -1);
      final UltraEntitlement g = applyBillingEvent(
          e, UltraBillingEvent(UltraEventKind.graceStarted, expiresAtMs: _now + 16 * _day), _now);
      expect(resolveUltraAccess(g, _now).state, UltraState.grace);
      final UltraEntitlement r = applyBillingEvent(g,
          UltraBillingEvent(UltraEventKind.billingRetryStarted, expiresAtMs: _now + 30 * _day), _now);
      expect(resolveUltraAccess(r, _now).state, UltraState.billingRetry,
          reason: '宽限窗必须被清掉，否则"先看宽限"的判定顺序会一直回报 grace');
      expect(r.graceUntilMs, isNull);
      // 反过来也一样
      final UltraEntitlement back = applyBillingEvent(r,
          UltraBillingEvent(UltraEventKind.graceStarted, expiresAtMs: _now + 5 * _day), _now);
      expect(back.billingRetryUntilMs, isNull);
      expect(resolveUltraAccess(back, _now).state, UltraState.grace);
    });

    test('退款事件：立即降级，且之后不会被"续订"洗白（要新记录，不是改这条）', () {
      final UltraEntitlement e = _e(expiresInDays: 20);
      final UltraEntitlement refunded =
          applyBillingEvent(e, const UltraBillingEvent(UltraEventKind.refunded), _now);
      expect(resolveUltraAccess(refunded, _now).ultra, isFalse);
      expect(refunded.isTerminal, isTrue);
    });

    test('只是核实一次：状态不变，只刷新核实时间（离线宽限因此重新计时）', () {
      final UltraEntitlement e = _e(expiresInDays: 10, verifiedDaysAgo: 30);
      expect(resolveUltraAccess(e, _now).unverified, isTrue);
      final UltraEntitlement v = applyBillingEvent(e, const UltraBillingEvent(UltraEventKind.verified), _now);
      expect(resolveUltraAccess(v, _now).unverified, isFalse);
      expect(resolveUltraAccess(v, _now).ultra, isTrue);
    });
  });

  group('M1 的假开关（判据 13：不许进 release）', () {
    test('默认是关的；打开之后在 debug 构建里生效（测试就是 debug 构建）', () {
      expect(debugUltraGranted, isFalse, reason: '默认必须是关的，谁也没买');
      debugSetUltraGranted(true);
      expect(debugUltraGranted, isTrue);
      debugSetUltraGranted(false);
      expect(debugUltraGranted, isFalse);
    });

    test('★ 扫源码：读与写都**必须**包在 assert 里（release 里那两行不存在）', () {
      final String src = File('lib/billing/debug_grant.dart').readAsStringSync();
      // 写：`_granted = value;` 有且仅有一次，且就在 assert 块里
      expect('_granted = value;'.allMatches(src).length, 1,
          reason: '假开关的写入点只允许一处，否则漏一处就漏一处能在 release 生效的路');
      expect(
          RegExp(r'assert\(\(\) \{\s*_granted = value;\s*return true;\s*\}\(\)\);').hasMatch(src),
          isTrue,
          reason: '写入必须包在 assert(() { … }()) 里 —— 否则 release 包里它会真的改状态');
      // 读：也要包在 assert 里（release 里恒为 false，而不是"读一个可变全局"）
      expect(
          RegExp(r'assert\(\(\) \{\s*v = _granted;\s*return true;\s*\}\(\)\);').hasMatch(src),
          isTrue,
          reason: '读取也必须包在 assert 里');
      expect('_granted = true'.allMatches(src).length, 0,
          reason: '不许有任何地方把假开关**默认写成开**');
    });

    test('★ 扫源码：`debugSetUltraGranted` 的调用点不许出现在非 assert 的位置', () {
      // 目前 lib/ 里除了定义处**没有调用点**（M1c 会加一个走查入口，那时它必须包在 assert 里）。
      // 这条测试的作用是：谁哪天在正式代码里直接调它，这里当场红。
      final List<String> offenders = <String>[];
      for (final FileSystemEntity f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('billing/debug_grant.dart')) continue;
        final String text = f.readAsStringSync();
        for (final RegExpMatch m in RegExp(r'debugSetUltraGranted\(').allMatches(text)) {
          final String before = text.substring(0, m.start);
          final int lastAssert = before.lastIndexOf('assert(');
          // assert( 必须**就在这一次调用之前**（同一个语句里），且中间不能再出现 `;`
          final bool wrapped = lastAssert >= 0 && !before.substring(lastAssert).contains(';');
          if (!wrapped) offenders.add('${f.path}：${m.start}');
        }
      }
      expect(offenders, isEmpty,
          reason: '这些地方的假开关没包在 assert 里 —— release 包里就成了"能开会员的后门"');
    });
  });
}
