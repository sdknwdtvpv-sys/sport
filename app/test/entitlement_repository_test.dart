/// 练了么 · 会员权益仓储的判据（M1）
///
/// 这一层只回答一件事：**纯函数算出来的结论，与库里存的那一行，是不是同一件事**。
/// 所以这里测的是往返（写进去 → 读出来 → 判定），而不是重测状态机
/// （状态机在 `entitlement_test.dart` 里已经逐态测过了）。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/billing/entitlement.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/entitlement_repository.dart';

const int _now = 1800000000000;
const int _day = 24 * 60 * 60 * 1000;

void main() {
  late AppDatabase db;
  late EntitlementRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = EntitlementRepository(db);
  });
  tearDown(() => db.close());

  test('空库 = 免费用户（没有任何记录，也不报错）', () async {
    expect(await repo.best(_now), isNull);
    final UltraAccess a = await repo.access(_now);
    expect(a.state, UltraState.none);
    expect(a.ultra, isFalse);
  });

  test('写进去再读出来：字段一个不丢（含"终身"那个 null 到期时间）', () async {
    await repo.upsert(const UltraEntitlement(
      id: 'apple-1',
      product: UltraProduct.lifetime,
      source: UltraSource.apple,
      purchasedAtMs: _now - _day,
      lastVerifiedAtMs: _now,
    ));
    final UltraEntitlement? got = await repo.best(_now);
    expect(got, isNotNull);
    expect(got!.id, 'apple-1');
    expect(got.product, UltraProduct.lifetime);
    expect(got.source, UltraSource.apple);
    expect(got.expiresAtMs, isNull, reason: '终身 = 没有到期时间，别在往返里被写成某个默认值');
    expect(got.isLifetime, isTrue);
    expect((await repo.access(_now)).state, UltraState.active);
  });

  test('同一条交易写两次是幂等的（主键是交易号，不是自增）', () async {
    const UltraEntitlement e = UltraEntitlement(
      id: 'apple-1',
      product: UltraProduct.yearly,
      source: UltraSource.apple,
      purchasedAtMs: _now - _day,
      expiresAtMs: _now + 30 * _day,
    );
    await repo.upsert(e);
    await repo.upsert(e.copyWith(lastVerifiedAtMs: _now));
    final List<UltraEntitlement> all = await repo.all();
    expect(all.length, 1, reason: '重复核实不能长出第二条权益');
    expect(all.single.lastVerifiedAtMs, _now, reason: '后写的那次应当覆盖前一次');
  });

  test('多条并存时，读出来的"最该生效的那条"与纯函数的判定一致', () async {
    await repo.upsert(const UltraEntitlement(
      id: 'refunded',
      product: UltraProduct.yearly,
      source: UltraSource.apple,
      purchasedAtMs: _now - 40 * _day,
      expiresAtMs: _now + 10 * _day,
      refundedAtMs: _now - _day,
    ));
    await repo.upsert(UltraEntitlement(
      id: 'active',
      product: UltraProduct.monthly,
      source: UltraSource.google,
      purchasedAtMs: _now - _day,
      expiresAtMs: _now + 20 * _day,
      lastVerifiedAtMs: _now,
    ));
    expect((await repo.best(_now))!.id, 'active');
    expect((await repo.access(_now)).ultra, isTrue);
  });

  test('退款那条即使"到期时间还没到"也不给权益（仓储层不能把它算进来）', () async {
    await repo.upsert(const UltraEntitlement(
      id: 'refunded-only',
      product: UltraProduct.yearly,
      source: UltraSource.apple,
      purchasedAtMs: _now - 40 * _day,
      expiresAtMs: _now + 100 * _day,
      refundedAtMs: _now - _day,
    ));
    final UltraAccess a = await repo.access(_now);
    expect(a.ultra, isFalse);
    expect(a.state, UltraState.refunded,
        reason: '界面要能如实写"已退款"，而不是干巴巴一句"已到期"');
  });

  test('计费流水：写得进、读得出，且新的在前（客服排查要靠它）', () async {
    await repo.logEvent('renewed', atMs: _now - 2 * _day, detail: 'ultra.yearly');
    await repo.logEvent('verified', atMs: _now);
    final List<BillingEventData> events = await repo.recentEvents();
    expect(events.length, 2);
    expect(events.first.kind, 'verified', reason: '新的在前');
    expect(events.last.detail, 'ultra.yearly');
  });

  test('clear() 把两张表都清空（"删除全部数据"走的就是它）', () async {
    await repo.upsert(const UltraEntitlement(
      id: 'apple-1',
      product: UltraProduct.monthly,
      source: UltraSource.apple,
      purchasedAtMs: _now,
      expiresAtMs: _now + _day,
    ));
    await repo.logEvent('renewed', atMs: _now);
    await repo.clear();
    expect(await repo.all(), isEmpty);
    expect(await repo.recentEvents(), isEmpty);
    expect((await repo.access(_now)).state, UltraState.none);
  });
}
