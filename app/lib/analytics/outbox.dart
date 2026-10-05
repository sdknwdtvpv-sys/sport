/// 练了么 · 埋点 outbox（本地队列）
///
/// 一条铁律：**训练进行中不发任何网络请求**。所以事件先落本地，
/// 由 `AnalyticsFlusher` 在合适的时机批量送出去。
///
/// 与训练数据的同步队列是两条独立通道：埋点丢几条无所谓，
/// 训练数据丢一条都不行 —— 所以优先级、重试、丢弃策略都不一样。
library;

import 'dart:convert';

import 'package:drift/drift.dart';

// db.dart（drift 表）与 models.dart（领域模型）有同名类，这里用不到领域模型。
import '../data/db.dart';

/// 一条待上报的事件
class AnalyticsEventPayload {
  const AnalyticsEventPayload({
    required this.id,
    required this.name,
    required this.props,
    required this.priority,
    required this.createdAt,
  });

  final String id;
  final String name;
  final Map<String, Object?> props;
  final int priority;
  final int createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'event': name,
        'ts': createdAt,
        'priority': priority,
        ...props,
      };
}

class AnalyticsOutboxStore {
  AnalyticsOutboxStore(
    this._db, {
    this.maxRows = defaultMaxRows,
    int Function()? clock,
  }) : _clock = clock ?? _systemNowMs;

  final AppDatabase _db;

  /// 容量上限：超过就按优先级丢（见 analytics-sdk.md §5）。
  /// 可注入 —— 否则测试溢出策略要插一万条。
  final int maxRows;

  static const int defaultMaxRows = 10000;

  /// 一次最多送多少条
  static const int maxBatch = 100;

  /// 连续失败多少次之后不再自动重试
  static const int maxAttempts = 3;

  /// **超龄即丢**：比这还老的事件不再上报（2026-10-05 拍板的 D 方案，`docs/analytics.md` §10）。
  ///
  /// 30 天这个数解决的是两件事，而它们本来是一对矛盾：
  ///   * **不污染当期曲线** —— 三个月前排不出去的事件混进今天的漏斗里，
  ///     分母就错了，而且错得看不出来；
  ///   * **又不至于把"离线一阵子"当成丢失** —— 出差一周、进山跑步、关掉开关几周，
  ///     回来照样上报（30 天里全都留着）。
  static const Duration maxAge = Duration(days: 30);

  /// 「现在」从哪来。**为什么要注入**：超龄判断必须与 `createdAt` 在**同一个时钟域**里做。
  /// 真身用系统时钟；测试里的时间戳是 `1000`、`5000` 这种假值，
  /// 不注入的话它们会全部"超过 30 岁"（1970 年）而被丢掉 —— 那是测试写错，
  /// 不是实现错，所以这里留一个显式的口子，让测试自己说清"现在几点"。
  static int _systemNowMs() => DateTime.now().millisecondsSinceEpoch;

  final int Function() _clock;

  int _seq = 0;

  /// 入队。**纯本地写入，绝不联网。**
  ///
  /// 顺手做一次超龄清理（`docs/analytics.md` §10 的 D 方案）：队列里那些已经
  /// 发不出去的老事件不该继续占着 10000 条的额度，也不该在某次网络恢复时挤进当期曲线。
  /// 用**这一条自己的 `nowMs`** 当"现在"：它就是调用方此刻的时钟，
  /// 于是判断与时间戳永远在同一个时钟域里（测试传假时间也不会误伤）。
  Future<void> enqueue({
    required String name,
    required Map<String, Object?> props,
    required int priority,
    required int nowMs,
  }) async {
    _seq++;
    await _db.into(_db.analyticsOutbox).insert(
          AnalyticsOutboxData(
            id: 'ev_${nowMs}_$_seq',
            name: name,
            payload: jsonEncode(props),
            priority: priority,
            createdAt: nowMs,
            // 第三次踩同一个坑了：withDefault 的列在 Dart 数据类里仍是 required。
            // 这次是 tool/check_drift_params.py 抓到的，没等到你跑测试。
            attempts: 0,
          ),
        );
    await dropExpired(nowMs: nowMs);
  }

  /// **把超过 [maxAge] 的事件从队列里删掉**，返回删掉的条数。
  ///
  /// 边界（有测试钉着）：**整整 30 天还留着，多一毫秒就丢**。
  /// 只在两个地方被调：入队（顺手清）与出队（发之前清）——
  /// 也就是说，一个事件只有两条出路：**被发出去**，或者**被这条规则清掉**；
  /// 超龄的那种永远走不到"被发出去"那一步。
  /// ⚠️ 这是本项目第二处**主动删掉用户数据**的地方（第一处是 `clearAll`），
  /// 所以它的判据必须写死在代码里、而且只按"时间"这一个事实判断。
  Future<int> dropExpired({required int nowMs}) async {
    final int cutoff = nowMs - maxAge.inMilliseconds;
    return (_db.delete(_db.analyticsOutbox)
          ..where((t) => t.createdAt.isSmallerThanValue(cutoff)))
        .go();
  }

  /// 取一批待发送的：优先级高的先送（0 = P0），同级按时间先进先出。
  /// 已连续失败 3 次的（parked）不再返回 —— 等下次冷启动由 [resetParked] 放出来。
  ///
  /// ⚠️ **取之前先丢超龄的**（D 方案）。为什么放在这里而不只放在入队：
  /// 入队那条路只有在"用户还在产生事件"时才会跑；而"离线很久之后第一次回来"
  /// 恰恰是从冷启动走到发送这一段 —— 那一段没有新事件可依赖，
  /// 所以发送前的这一步才是**真正的闸门**（入队那次只是省额度）。
  /// 于是 `takeBatch` **不再是纯读**：它会删掉超龄的行（这一点在
  /// `app/test/home_entry_test.dart` 的注释里也写着，改这句话时两处一起改）。
  Future<List<AnalyticsEventPayload>> takeBatch({int limit = maxBatch}) async {
    await dropExpired(nowMs: _clock());
    final rows = await (_db.select(_db.analyticsOutbox)
          ..where((t) => t.attempts.isSmallerThanValue(maxAttempts))
          ..orderBy([
            (t) => OrderingTerm.asc(t.priority),
            (t) => OrderingTerm.asc(t.createdAt),
          ])
          ..limit(limit))
        .get();

    return rows
        .map((AnalyticsOutboxData r) => AnalyticsEventPayload(
              id: r.id,
              name: r.name,
              props: (jsonDecode(r.payload) as Map<String, dynamic>)
                  .cast<String, Object?>(),
              priority: r.priority,
              createdAt: r.createdAt,
            ))
        .toList();
  }

  Future<void> markSent(List<String> ids) async {
    if (ids.isEmpty) return;
    await (_db.delete(_db.analyticsOutbox)..where((t) => t.id.isIn(ids))).go();
  }

  /// **只读**地取出队列里的全部事件（含 parked 的），按"优先级 + 时间"排好。
  ///
  /// 为什么要有它：「导出统计事件」是**唯一能把 `tap_count` 从设备上取回来的路径**。
  /// 没配上报地址的包里 `_NullTransport` 恒失败，事件只会一直攒在本地 ——
  /// 而 `tap_count` 中位数是"less is more"唯一的客观守卫（`docs/analytics.md` §3）。
  ///
  /// 三个刻意的选择：
  ///   * **不过滤 parked**（连续失败 ≥ 3 次的那些）：它们正是"发不出去"的那批，
  ///     过滤掉等于把最该看的数据藏起来；
  ///   * **也不过滤超龄的**（D 方案那条 30 天的线）：理由与上一条同源 ——
  ///     导出是"看看队列里到底堵着什么"的**诊断**路径，不是发送路径；
  ///     但要知道**它们不会再被发出去**（`takeBatch` 会先把它们删掉）。
  ///     判据在 `docs/analytics.md` §10 的 D 方案。
  ///   * **不删除**（与 `markSent` 是两件事）：导出是只读动作，不改队列状态；
  ///   * 排序与 [takeBatch] 一致，所以"导出的顺序"与"真要发出去的顺序"是同一个。
  Future<List<AnalyticsEventPayload>> peekAll() async {
    final rows = await (_db.select(_db.analyticsOutbox)
          ..orderBy([
            (t) => OrderingTerm.asc(t.priority),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .get();

    return rows
        .map((AnalyticsOutboxData r) => AnalyticsEventPayload(
              id: r.id,
              name: r.name,
              props: (jsonDecode(r.payload) as Map<String, dynamic>)
                  .cast<String, Object?>(),
              priority: r.priority,
              createdAt: r.createdAt,
            ))
        .toList();
  }

  Future<void> markFailed(List<String> ids, String error) async {
    for (final String id in ids) {
      final row = await (_db.select(_db.analyticsOutbox)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) continue;
      await (_db.update(_db.analyticsOutbox)..where((t) => t.id.equals(id)))
          .write(AnalyticsOutboxCompanion(
        attempts: Value<int>(row.attempts + 1),
        lastError: Value<String>(error),
      ));
    }
  }

  /// 下次冷启动时放行之前 parked 的事件（§5：等下次冷启动）
  Future<int> resetParked() async {
    final rows = await (_db.select(_db.analyticsOutbox)
          ..where((t) => t.attempts.isBiggerOrEqualValue(maxAttempts)))
        .get();
    if (rows.isEmpty) return 0;
    await (_db.update(_db.analyticsOutbox)
          ..where((t) => t.attempts.isBiggerOrEqualValue(maxAttempts)))
        .write(const AnalyticsOutboxCompanion(attempts: Value<int>(0)));
    return rows.length;
  }

  Future<int> pending() async {
    final rows = await _db.select(_db.analyticsOutbox).get();
    return rows.length;
  }

  /// 超出上限时丢弃：**低优先级先丢，同级旧的先丢**，返回丢弃条数。
  /// **清空整个队列**（不只是已发送的）。
  ///
  /// 只在一个地方用：`docs/analytics.md` §10 拍板的 **B 方案** ——
  /// 第一次在"配了上报地址的包"里冷启动时，把此前攒下的历史积压丢掉。
  /// 理由：那些事件产生时，用户用的是**不对外发送**的包，我们从没告诉过他它们会被发出去；
  /// 接上地址的那天补传，等于事后改主意。**谁记的谁发。**
  ///
  /// ⚠️ 这是本项目里唯一一处**主动删掉用户数据**的地方，所以它必须由
  /// `AnalyticsMetaRepository.legacyPurgedAt` 保证**只发生一次**，
  /// 而且只在"真的有地址"时发生（没配地址的包继续攒，行为不变）。
  Future<int> clearAll() async {
    return _db.delete(_db.analyticsOutbox).go();
  }

  Future<int> dropOverflow() async {
    final int total = await pending();
    if (total <= maxRows) return 0;
    final int excess = total - maxRows;

    // priority 数字越大优先级越低 → 倒序取，就是"最后该留的"
    final rows = await (_db.select(_db.analyticsOutbox)
          ..orderBy([
            (t) => OrderingTerm.desc(t.priority),
            (t) => OrderingTerm.asc(t.createdAt),
          ])
          ..limit(excess))
        .get();
    await markSent(rows.map((AnalyticsOutboxData r) => r.id).toList());
    return rows.length;
  }
}
