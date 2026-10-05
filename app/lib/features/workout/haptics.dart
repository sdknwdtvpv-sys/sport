/// 练了么 · 训练屏的**触觉反馈**（v1.53）
///
/// 为什么需要它：健身房是吵的，手机多半架在器械上或放在旁边 ——
/// 「记上了没有」如果只有视觉那一条通道，用户就得低头确认一次。
/// 一次轻震等于一句"记上了"，而且**不用看屏幕**。
///
/// 为什么抽成接口而不是直接在控制器里调 `HapticFeedback`：
/// 控制器是纯 Dart（`flutter/foundation` 那一层），平台通道留在外面才测得动 ——
/// 与 `RestActivityBridge` 同一条理由。默认值是 [NoopHaptics]，
/// 所以测试与其它 20 多个构造点什么都不用改，**生产在 `main.dart` 接上真的那个**。
library;

import 'package:flutter/services.dart';

/// 训练屏需要反馈的两个时刻。
abstract class Haptics {
  /// 成功记下一组。**只有真的写进库那一次**才算 —— 被挡下的那次不算。
  Future<void> setLogged();

  /// 组间休息走到 0。比记一组的反馈更重一点：那一下通常不看屏幕，靠它把人叫回来。
  Future<void> restFinished();

  /// 计时动作撑到了今天的秒数（v1.53）。
  ///
  /// 用**两下轻震**这个独立的"花样"：它既不是"记上了"（那一下是单次中等），
  /// 也不是"休息结束"（单次重震）—— 用户靠在垫子上不看屏幕时，
  /// 三种节奏要分得出来："到点了，可以放下了" / "记上了" / "该下一组了"。
  Future<void> targetReached();
}

/// 什么都不做。测试、以及不关心反馈的调用点用这个。
class NoopHaptics implements Haptics {
  const NoopHaptics();

  @override
  Future<void> setLogged() async {}

  @override
  Future<void> restFinished() async {}

  @override
  Future<void> targetReached() async {}
}

/// 走系统触觉（`HapticFeedback`，Flutter 自带，**零依赖**）。
///
/// ⚠️ 两个都是"尽力而为"：设备没有马达、系统关掉了触觉反馈、
/// 或者平台不支持，这些调用都是**空操作**（返回 null），不会抛。
/// 所以训练屏永远不该等它们 —— 调用点一律 `unawaited`。
class SystemHaptics implements Haptics {
  const SystemHaptics();

  @override
  Future<void> setLogged() => HapticFeedback.mediumImpact();

  @override
  Future<void> restFinished() => HapticFeedback.heavyImpact();

  @override
  Future<void> targetReached() async {
    // 两下轻震（中间隔 120ms）—— 单靠 API 表达不了"节奏"，
    // 但"轻-轻"与另外两种（单次中等 / 单次重）在手上是能分开的。
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await HapticFeedback.lightImpact();
  }
}
