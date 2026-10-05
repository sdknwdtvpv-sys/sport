/// 练了么 · outbox 的**超龄即丢**（`docs/analytics.md` §10 的 D 方案，2026-10-05 拍板）
///
/// **它守的是什么**：没配地址（或一直连不上）的包**不会丢事件，只会一直攒**
/// （上限 10000 条）。于是有两条互相拉扯的要求：
///   * 三个月前排不出去的事件混进今天的漏斗里 → **分母就错了，而且错得看不出来**；
///   * 但"出差一周、进山跑步、把开关关了几周"回来之后照常上报 —— 这是正常使用，不是异常。
///
/// 拍板结论（2026-10-05，你选的 **D**）：**超过 30 天就丢**。两条都满足：
/// 30 天里的事件一条不动，超过 30 天的一条不发。
///
/// ⚠️ 它与 B 方案（`analytics_legacy_purge_test.dart`）**不是同一件事**，别混：
///   * B 管**出身** —— "配了地址的包第一次冷启动，丢掉接入前攒的"（只发生一次）；
///   * D 管**年龄** —— "任何事件超过 30 天就不发"（一直都在）。
///
/// 时间戳全是相对的（相对 [base]），不依赖机器时钟 —— 这一层的"现在"是注入的。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/outbox.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, UserProfile, Workout, WorkoutItem;

const int kDay = 24 * 60 * 60 * 1000;

void main() {
  /// "现在"。所有事件都相对它来记，于是"30 天"这条线是可断言的。
  final int base = DateTime(2026, 10, 5, 12).millisecondsSinceEpoch;

  late AppDatabase db;
  late AnalyticsOutboxStore outbox;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    // 假时钟 = "现在"。outbox 的超龄判断拿它去和 createdAt 比。
    outbox = AnalyticsOutboxStore(db, clock: () => base);
  });
  tearDown(() => db.close());

  Future<void> put(String name, {required int at}) => outbox.enqueue(
        name: name,
        props: <String, Object?>{'x': 1},
        priority: 0,
        nowMs: at,
      );

  test('★ 超过 30 天的事件不会被发出去（而且真的从队列里清掉了）', () async {
    await put('old', at: base - 31 * kDay);
    await put('fresh', at: base - 1 * kDay);

    final List<AnalyticsEventPayload> batch = await outbox.takeBatch();

    expect(batch.map((AnalyticsEventPayload e) => e.name).toList(), <String>['fresh'],
        reason: '31 天前那条不许发给服务端 —— 那是当期曲线里的噪声');
    expect(await outbox.pending(), 1,
        reason: '清掉而不是"跳过"：留着它会一直占额度、每次取批次都要再判一次');
  });

  test('★ 边界：整整 30 天还留着，多一毫秒就丢', () async {
    await put('exactly30', at: base - 30 * kDay);
    await put('just_over', at: base - 30 * kDay - 1);

    final List<AnalyticsEventPayload> batch = await outbox.takeBatch();

    expect(batch.map((AnalyticsEventPayload e) => e.name).toList(),
        <String>['exactly30'],
        reason: '判据是"早于 cutoff"而不是"不晚于" —— 差 1 毫秒就换一边，所以这条要有');
  });

  test('★ 「离线一周照样上报」：7 天前记的照发（D 的关键承诺）', () async {
    await put('week_old', at: base - 7 * kDay);
    expect((await outbox.takeBatch()).single.name, 'week_old',
        reason: '出差/断网/关掉开关几周，回来仍然要发 —— 只有"太久"才丢');
  });

  test('入队时顺手清理：老事件不该继续占着 10000 条的额度', () async {
    await put('ancient', at: base - 200 * kDay);
    expect(await outbox.pending(), 1,
        reason: '入队那一刻用的"现在"是这一条自己的时间戳（200 天前），所以它还活着');

    // 回到"现在"再记一条 → 入队时按当前的"现在"清一次
    // （真身里 enqueue 的 nowMs 就是此刻的系统时钟）
    await put('now', at: base);
    expect(await outbox.pending(), 1, reason: '200 天前那条被顺手清掉了');
  });

  test('没有超龄的 → 一条都不动（不误伤）', () async {
    await put('a', at: base - 2 * kDay);
    await put('b', at: base);
    final int dropped = await outbox.dropExpired(nowMs: base);
    expect(dropped, 0);
    expect(await outbox.pending(), 2);
  });

  test('parked 的超龄事件同样会被清掉（"发不出去"不该变成"永远留着"）', () async {
    await put('parked_old', at: base - 40 * kDay);
    // 用一把"40 天前"的时钟把这条打成 parked（这一步本身不能被超龄清掉）
    final AnalyticsOutboxStore past =
        AnalyticsOutboxStore(db, clock: () => base - 40 * kDay);
    final AnalyticsEventPayload e = (await past.takeBatch()).single;
    for (int i = 0; i < AnalyticsOutboxStore.maxAttempts; i++) {
      await past.markFailed(<String>[e.id], 'boom');
    }
    expect(await outbox.pending(), 1, reason: '先确认它真的躺在队列里');

    expect(await outbox.takeBatch(), isEmpty);
    expect(await outbox.pending(), 0, reason: '超龄的 parked 事件也在清理范围内');
  });

  test('导出口径：只读的 peekAll **不删**，但要知道那些超龄的不会再被发出去', () async {
    await put('old', at: base - 45 * kDay);
    expect((await outbox.peekAll()).length, 1,
        reason: '导出是诊断路径：队列里堵着什么都要看得见');
    expect(await outbox.pending(), 1, reason: 'peekAll 绝不改队列状态');

    await outbox.takeBatch();
    expect(await outbox.peekAll(), isEmpty, reason: '发送路径清掉之后，导出里也就没了');
  });
}
