/// 练了么 · 同步队列（outbox）
///
/// 训练数据与埋点是**两条独立的通道**：本文件负责训练数据（训练/组记录），
/// 埋点上报见 `lib/analytics/analytics.dart`。两者都遵守同一条红线：
/// **训练进行中不发任何网络请求。**
library;

enum SyncOutcome { ok, offline, failed }

class OutboxItem {
  const OutboxItem({
    required this.id,
    required this.entity,
    required this.payload,
    required this.priority,
  });

  final String id;
  final String entity;
  final Map<String, Object?> payload;

  /// 0 = P0 不可丢（训练数据）；1 = P1；2 = P2
  final int priority;
}

abstract class SyncQueue {
  int get pending;
  bool get offline;
  set offline(bool value);
  void enqueue(String entity, Map<String, Object?> payload, {int priority = 0});
  Future<SyncOutcome> flush();
}

class InMemorySyncQueue implements SyncQueue {
  final List<OutboxItem> _items = <OutboxItem>[];

  /// 队列内容的只读视图。**给测试用**：断言 payload 里到底带了哪些字段
  /// （比如有氧的 `distance_m`）—— 只数 pending 的话"字段漏了"根本测不出来。
  List<OutboxItem> get items => List<OutboxItem>.unmodifiable(_items);

  int _seq = 0;

  @override
  bool offline = false;

  /// 抛出的同步失败次数，供测试与可观测性使用。
  int flushAttempts = 0;

  @override
  int get pending => _items.length;

  @override
  void enqueue(String entity, Map<String, Object?> payload, {int priority = 0}) {
    _seq++;
    _items.add(OutboxItem(
      id: 'ob_$_seq',
      entity: entity,
      payload: payload,
      priority: priority,
    ));
  }

  @override
  Future<SyncOutcome> flush() async {
    flushAttempts++;
    if (offline) return SyncOutcome.offline; // 队列保留，一条不丢
    if (_items.isEmpty) return SyncOutcome.ok;
    _items.clear();
    return SyncOutcome.ok;
  }
}
