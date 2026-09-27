/// 练了么 · 真身埋点实现
///
/// 与 `RecordingAnalytics`（测试用，只存内存）不同，这个把事件写进本地 outbox，
/// 由 `AnalyticsFlusher` 择机批量送出。
///
/// 三条不可破的规矩：
///   1. `track()` **同步返回**，绝不 await 网络、绝不抛异常
///   2. 训练进行中不发请求 —— 由刷写器挂起保证，与这里无关
///   3. 关掉隐私开关后除崩溃外什么都不记
library;

import 'dart:async';

import '../domain/tap_meter.dart';
import 'analytics.dart';
import 'flusher.dart';
import 'outbox.dart';

class OutboxAnalytics implements Analytics {
  OutboxAnalytics({
    required AnalyticsOutboxStore outbox,
    int Function()? clock,
  })  : _outbox = outbox,
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AnalyticsOutboxStore _outbox;
  final int Function() _clock;

  /// TapMeter 是"当前这一组的交互计数"。放这里而不是全局，
  /// 因为一次只有一屏在记录（控制器是顺序创建的）。
  final TapMeter _meter = TapMeter();

  /// 「帮助改进产品」开关。关掉后除崩溃（独立通道）外一律不记。
  bool enabled = true;

  @override
  void setEnabled(bool value) => enabled = value;

  /// 被吞掉的异常数 —— 用于验证"埋点坏了不影响功能"
  int swallowedErrors = 0;

  @override
  void track(String event, [Map<String, Object?> props = const <String, Object?>{}]) {
    if (!enabled) return;
    try {
      // 刻意不 await：埋点绝不能阻塞 UI。
      // enqueue 的 _seq++ 在第一个 await 之前执行，所以并发调用也不会撞 id。
      unawaited(_outbox.enqueue(
        name: event,
        props: props,
        priority: priorityFor(event),
        nowMs: _clock(),
      ));
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

  /// 真身由刷写器负责，这里不重复实现
  @override
  Future<void> flush({bool force = false}) async {}
}
