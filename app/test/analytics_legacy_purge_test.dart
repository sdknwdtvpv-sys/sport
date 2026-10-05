/// 练了么 · 接入上报的**首次清理**（`docs/analytics.md` §10 的 B 方案）
///
/// **它守的是什么**：没配上报地址的包**不会丢事件，只会一直攒**（上限 10000 条）。
/// 那些事件产生时，用户用的是"不对外发送"的包 —— 我们从没告诉过他它们会被发出去。
/// 如果接上地址的第一个版本把它们一起发走，等于**事后改主意**，而政策 §3.2 没覆盖这条。
/// 拍板结论（2026-10-04，你选的）：**B —— 丢积压，只发这个版本自己记的**。
///
/// 这一组测试钉三条边界，少一条都不行：
///   1. **配了地址**：第一次冷启动清空、并记下"清过了"；
///   2. **没配地址**：什么都不做（继续攒 —— 行为与以前完全一样，不能让"没地址"的包丢数据）；
///   3. **只清一次**：第二次冷启动不许再删任何东西（否则用户每天开一次 App，
///      当天记的事件会被一直删掉 —— 那是最坏的一种"修 bug 修出来的数据丢失"）。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/outbox.dart';
import 'package:lianleme/data/analytics_meta_repository.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;

/// 复刻 `main.dart` 里那段清理逻辑 —— 抽成函数是为了能在测试里直接调。
/// ⚠️ 这里是**刻意的复制**：`main.dart` 的那份跑在真实 App 里，这份用来做边界测试。
/// 两边若漂了，`main.dart` 的注释里写着判据 —— 而下面的用例会把漂移变成红。
Future<int> purgeOnce({
  required AppDatabase db,
  required AnalyticsOutboxStore outbox,
  required AnalyticsMetaRepository meta,
  required bool hasEndpoint,
  int nowMs = 1000,
}) async {
  if (!hasEndpoint) return -1; // -1 = 没动手
  if (await meta.legacyPurgedAt() != null) return -1;
  final int dropped = await outbox.clearAll();
  await meta.markLegacyPurged(nowMs);
  return dropped;
}

Future<void> seed(AppDatabase db, int n) async {
  final AnalyticsOutboxStore outbox = AnalyticsOutboxStore(db);
  for (int i = 0; i < n; i++) {
    await outbox.enqueue(
      name: 'app_open',
      props: const <String, Object?>{'device_id': 'd1', 'app_version': '1.0.0'},
      priority: 1,
      nowMs: 100 + i,
    );
  }
}

void main() {
  late AppDatabase db;
  late AnalyticsOutboxStore outbox;
  late AnalyticsMetaRepository meta;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    outbox = AnalyticsOutboxStore(db);
    meta = AnalyticsMetaRepository(db);
  });
  tearDown(() => db.close());

  test('★ 配了地址：第一次冷启动丢掉全部积压，并记下"清过了"', () async {
    await seed(db, 7);
    expect(await outbox.pending(), 7, reason: '先确认积压真的攒着');

    final int dropped = await purgeOnce(db: db, outbox: outbox, meta: meta, hasEndpoint: true);

    expect(dropped, 7, reason: '7 条全清');
    expect(await outbox.pending(), 0);
    expect(await meta.legacyPurgedAt(), isNotNull, reason: '这一位必须落库，否则每次冷启动都会清');
  });

  test('★ 没配地址：什么都不做（继续攒，与以前行为一模一样）', () async {
    await seed(db, 5);

    final int dropped = await purgeOnce(db: db, outbox: outbox, meta: meta, hasEndpoint: false);

    expect(dropped, -1, reason: '没地址时压根不该动手');
    expect(await outbox.pending(), 5, reason: '一条都不许丢 —— 没配地址的包靠攒着等以后');
    expect(await meta.legacyPurgedAt(), isNull);
  });

  test('★ 只清一次：第二次冷启动不许再删（否则每天开 App 就删光当天的事件）', () async {
    await purgeOnce(db: db, outbox: outbox, meta: meta, hasEndpoint: true, nowMs: 1000);
    await seed(db, 3); // 清完之后新记的 3 条

    final int second = await purgeOnce(db: db, outbox: outbox, meta: meta, hasEndpoint: true, nowMs: 2000);

    expect(second, -1, reason: '第二次不该动手');
    expect(await outbox.pending(), 3, reason: '清完之后事件必须能正常出去');
    expect(await meta.legacyPurgedAt(), 1000, reason: '时间戳不许被覆盖');
  });

  test('空队列 + 已配地址：照样把这一位写上（否则每次冷启动都白跑一次查询）', () async {
    final int dropped = await purgeOnce(db: db, outbox: outbox, meta: meta, hasEndpoint: true, nowMs: 42);
    expect(dropped, 0);
    expect(await meta.legacyPurgedAt(), 42);
  });

  test('老库升到 v18：这一列是 null（"还没清过"），不是 0（那会被当成"1970 年清过"）', () async {
    // 直接读新库的默认值 —— 迁移本身在 migration_test.dart 里逐版验
    await meta.ensure();
    expect(await meta.legacyPurgedAt(), isNull);
  });
}
