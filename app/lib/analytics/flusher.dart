/// 练了么 · 埋点刷写器
///
/// 规则全部照 `docs/analytics-sdk.md` §5–§6：
///   * 一批最多 100 条
///   * 重试间隔 1s / 4s / 16s（+ 抖动），连续失败 3 次后 parked
///   * 优先级 P0/P1/P2 决定谁先被送出去、谁先被丢
///   * **训练进行中不发** —— 由 [suspend] / [resume] 控制
///
/// 刷写器**自己不 sleep**：它只负责"尝试一次"，什么时候再试交给调用方
/// （[retryDelay] 给出建议）。这样它是纯逻辑，测试里不用等真实时间。
library;

import '../data/db.dart';
import 'outbox.dart';
import 'transport.dart';

/// 事件优先级。数字越小越重要（0 = P0 不可丢）。
///
/// 分级的依据是"丢了之后会不会让人做出错误决策"，不是"重不重要"。
int priorityFor(String event) {
  switch (event) {
    // P0：北极星与漏斗靠它们，丢了指标就失真
    case 'app_open':
    case 'workout_started':
    case 'set_logged':
    case 'workout_finished':
    case 'purchase_completed':
      return 0;

    // P2：辅助分析，可采样
    case 'onboarding_step':
    case 'paywall_viewed':
    case 'share_card_created':
    case 'body_metric_logged':
      return 2;

    // P1：其余（建议采纳、编辑、撤销、PR、休息……）
    default:
      return 1;
  }
}

/// 第 [attempt] 次失败后的建议重试间隔。
///
/// [jitter] 传 0..1 的随机数即可打散同时重试的客户端；
/// **测试传 0，结果完全可预测**。
Duration retryDelay(int attempt, {double jitter = 0}) {
  const List<int> base = <int>[1000, 4000, 16000];
  final int i = attempt.clamp(1, base.length) - 1;
  final int extra = (base[i] * 0.2 * jitter.clamp(0.0, 1.0)).round();
  return Duration(milliseconds: base[i] + extra);
}

enum FlushOutcome {
  /// 送出去了一批
  sent,

  /// 队列里没东西
  empty,

  /// 送失败（已记录失败次数）
  failed,

  /// 训练进行中，被挂起 —— 不是错误，是设计
  suspended,
}

class FlushResult {
  const FlushResult(this.outcome, {this.count = 0, this.nextRetry});

  final FlushOutcome outcome;
  final int count;

  /// failed 时给出的建议等待时长
  final Duration? nextRetry;

  bool get isSuccess => outcome == FlushOutcome.sent || outcome == FlushOutcome.empty;
}

class AnalyticsFlusher {
  AnalyticsFlusher({
    required AppDatabase db,
    required AnalyticsTransport transport,
    AnalyticsOutboxStore? outbox,
    this.batchSize = AnalyticsOutboxStore.maxBatch,
  })  : outbox = outbox ?? AnalyticsOutboxStore(db),
        _transport = transport;

  final AnalyticsOutboxStore outbox;
  final AnalyticsTransport _transport;
  final int batchSize;

  bool _suspended = false;
  int _failStreak = 0;

  /// 训练进行中要挂起：健身房常年弱网，任何网络请求都可能跟"记一组"抢资源
  bool get isSuspended => _suspended;

  void suspend() => _suspended = true;

  void resume() {
    _suspended = false;
    _failStreak = 0;
  }

  /// 尝试送一批。**不抛异常**。
  Future<FlushResult> flushOnce({double jitter = 0}) async {
    if (_suspended) return const FlushResult(FlushOutcome.suspended);

    try {
      final List<AnalyticsEventPayload> batch =
          await outbox.takeBatch(limit: batchSize);
      if (batch.isEmpty) return const FlushResult(FlushOutcome.empty);

      final bool ok = await _transport.send(batch);
      final List<String> ids =
          batch.map((AnalyticsEventPayload e) => e.id).toList();

      if (ok) {
        await outbox.markSent(ids);
        _failStreak = 0;
        return FlushResult(FlushOutcome.sent, count: batch.length);
      }

      await outbox.markFailed(ids, 'transport returned false');
      _failStreak++;
      return FlushResult(
        FlushOutcome.failed,
        count: batch.length,
        nextRetry: retryDelay(_failStreak, jitter: jitter),
      );
    } catch (e) {
      // 连 outbox 都坏了也不能影响功能
      _failStreak++;
      return FlushResult(
        FlushOutcome.failed,
        nextRetry: retryDelay(_failStreak, jitter: jitter),
      );
    }
  }

  /// 冷启动时调用：放行上次 parked 的事件，并清零失败计数
  Future<int> onColdStart() async {
    _failStreak = 0;
    return outbox.resetParked();
  }
}
