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
import 'analytics_context.dart';
import 'outbox.dart';

class OutboxAnalytics implements Analytics {
  OutboxAnalytics({
    required AnalyticsOutboxStore outbox,
    required AnalyticsContext context,
    bool Function()? offline,
    int Function()? clock,
  })  : _outbox = outbox,
        _context = context,
        _offline = offline ?? (() => false),
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AnalyticsOutboxStore _outbox;

  /// 公共字段（`device_id` / `session_id` / `app_version`…）。
  ///
  /// **必填，不给缺省** —— 有意的：漏接它的后果是"北极星算不出来"，
  /// 而那是一个只有到了看板阶段才会发现的窟窿。编译期逼着接，比事后查便宜。
  final AnalyticsContext _context;

  /// 事件发生时是否离线。真身传 `syncQueue.offline`。
  final bool Function() _offline;

  final int Function() _clock;

  /// TapMeter 是"当前这一组的交互计数"。放这里而不是全局，
  /// 因为一次只有一屏在记录（控制器是顺序创建的）。
  final TapMeter _meter = TapMeter();

  /// 「帮助改进产品」开关。关掉后除崩溃（独立通道）外一律不记。
  ///
  /// **默认 false —— 失败要往"关"那边倒**（2026-09-30，审计 A 的后半段）。
  /// 库里那一列的默认值也是关；但那是"数据"，这是"内存里的对象"：
  /// 万一启动时忘了把库里的值同步进来（这个 bug 真发生过 —— 只改默认值没接线，
  /// 结果是"开关显示关着、实际上还在收集"），这里必须是关的，一条都不该记。
  bool enabled = false;

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
      unawaited(_enqueueWithCommon(event, props));
    } catch (_) {
      swallowedErrors++;
    }
  }

  /// 补上公共字段再入队。
  ///
  /// **公共字段排在后面**：万一调用方也传了 `is_offline` 之类，以公共层为准 ——
  /// 否则同一个字段会有两种来源，早晚对不上（`docs/analytics.md` §2.1 说它是"自动附带"）。
  Future<void> _enqueueWithCommon(
      String event, Map<String, Object?> props) async {
    final int now = _clock();
    Map<String, Object?> common = const <String, Object?>{};
    try {
      common = await _context.commonProps(offline: _offline());
    } catch (_) {
      // 取不到公共字段也要把事件送出去 —— 少几个字段比丢整条事件好。
      // （比如数据库临时出问题；埋点永远不该因为自己坏掉而吃掉数据。）
      swallowedErrors++;
    }
    await _outbox.enqueue(
      name: event,
      props: <String, Object?>{...props, ...common},
      priority: priorityFor(event),
      nowMs: now,
    );
  }

  @override
  void beginSetInteraction() => _meter.begin();

  @override
  void ensureSetInteraction() => _meter.ensure();

  @override
  void countTap(TapKind kind) => _meter.tap(kind);

  @override
  TapMeterReading flushTap() => _meter.flush();

  /// 真身由刷写器负责，这里不重复实现
  @override
  Future<void> flush({bool force = false}) async {}
}
