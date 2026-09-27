/// 练了么 · 埋点 SDK 骨架
///
/// 业务侧只暴露 5 个方法（与 docs/analytics-sdk.md §2 一致，其中 flushTapCount 改为
/// flushTap 以同时返回 count 与 kinds —— 只看总数无法回答"这些点击花在哪了"）。
///
/// 实现遵循三条红线：
///   1. track() 是纯内存操作，同步返回，绝不抛异常，绝不阻塞 UI
///   2. 训练进行中不发网络请求（真实实现在 Flusher 层保证）
///   3. 埋点异常绝不影响记录功能
library;

import '../domain/tap_meter.dart';

class AnalyticsEvent {
  const AnalyticsEvent(this.name, this.props, {this.offline = false});
  final String name;
  final Map<String, Object?> props;
  final bool offline;
}

abstract class Analytics {
  void track(String event, [Map<String, Object?> props = const <String, Object?>{}]);

  /// 「帮助改进产品」开关。关掉后除崩溃（独立通道）外不得记录任何事件。
  ///
  /// 做成方法而不是可变字段：`NoopAnalytics` 是 const 类，加可变字段会破坏它。
  void setEnabled(bool value);
  void beginSetInteraction();
  void countTap(TapKind kind);
  TapMeterReading flushTap();
  Future<void> flush({bool force = false});
}

/// 收集到内存里，供测试断言真实的埋点载荷。
class RecordingAnalytics implements Analytics {
  final TapMeter _meter = TapMeter();
  final List<AnalyticsEvent> events = <AnalyticsEvent>[];

  /// 与真身一样遵守隐私开关 —— 否则测不到"关掉之后确实不记了"
  bool enabled = true;

  @override
  void setEnabled(bool value) => enabled = value;

  /// 所有 track 调用里抛出的异常计数 —— 用于验证"埋点抛异常不影响记录"。
  int swallowedErrors = 0;

  @override
  void track(String event, [Map<String, Object?> props = const <String, Object?>{}]) {
    if (!enabled) return;
    try {
      events.add(AnalyticsEvent(event, Map<String, Object?>.unmodifiable(props)));
    } catch (_) {
      swallowedErrors++;
    }
  }

  @override
  void beginSetInteraction() => _meter.begin();

  @override
  void countTap(TapKind kind) => _meter.tap(kind);

  @override
  TapMeterReading flushTap() => _meter.flush();

  @override
  Future<void> flush({bool force = false}) async {
    // 骨架实现：不联网。真实实现把事件写入 outbox 后批量上报。
  }

  /// 测试便利方法：按事件名取出全部载荷。
  List<Map<String, Object?>> propsOf(String name) =>
      events.where((e) => e.name == name).map((e) => e.props).toList();

  int countOf(String name) => events.where((e) => e.name == name).length;
}

/// 隐私开关关闭后使用的实现：除了崩溃上报（独立通道），什么都不记。
class NoopAnalytics implements Analytics {
  const NoopAnalytics();

  @override
  void setEnabled(bool value) {}

  @override
  void track(String event, [Map<String, Object?> props = const <String, Object?>{}]) {}

  @override
  void beginSetInteraction() {}

  @override
  void countTap(TapKind kind) {}

  @override
  TapMeterReading flushTap() => const TapMeterReading(0, <TapKind>[]);

  @override
  Future<void> flush({bool force = false}) async {}
}
