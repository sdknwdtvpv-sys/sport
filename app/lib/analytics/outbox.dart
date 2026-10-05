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
  AnalyticsOutboxStore(this._db, {this.maxRows = defaultMaxRows});

  final AppDatabase _db;

  /// 容量上限：超过就按优先级丢（见 analytics-sdk.md §5）。
  /// 可注入 —— 否则测试溢出策略要插一万条。
  final int maxRows;

  static const int defaultMaxRows = 10000;

  /// 一次最多送多少条
  static const int maxBatch = 100;

  /// 连续失败多少次之后不再自动重试
  static const int maxAttempts = 3;

  int _seq = 0;

  /// 入队。**纯本地写入，绝不联网。**
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
  }

  /// 取一批待发送的：优先级高的先送（0 = P0），同级按时间先进先出。
  /// 已连续失败 3 次的（parked）不再返回 —— 等下次冷启动由 [resetParked] 放出来。
  Future<List<AnalyticsEventPayload>> takeBatch({int limit = maxBatch}) async {
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
