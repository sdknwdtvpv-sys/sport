/// 练了么 · 休息结束的**体外提示**（Android，v1.53）
///
/// 现场依据：iOS 那边早就有 Live Activity（锁屏/灵动岛上的倒计时），
/// **Android 什么都没有** —— 手机一锁屏，休息还剩多久没有任何地方看得见，
/// 用户只能盯着屏幕。这一条把"休息结束"发成本地通知，锁屏上就能看到。
///
/// 三条口径：
///   * **只在 Android 上有意义**：iOS 有 Live Activity 了，再来一条通知是重复打扰 ——
///     iOS 侧显式实现成空操作（不是"忘了做"，见 `AppDelegate.swift` 的注释）。
///   * **不排闹钟、不申请新权限**：Dart 那边的休息计时器到点直接让原生发一条通知。
///     代价写清楚：**App 进程被杀掉时不会响**（那是"到点响铃"级别的要求，
///     要 `SCHEDULE_EXACT_ALARM` 那种特殊权限，为一条休息提示不值得）。
///   * **没授权就静默什么都不发生**（Android 13+ 用户没给通知权限时）。
///     这里刻意**不弹权限框**：权限只在用户主动打开「训练提醒」时请求过一次，
///     训练中途弹框会打断训练 —— 那比少一条提示糟糕得多。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 休息结束的体外提示。
abstract class RestCue {
  /// 休息到点了：发一条通知（标题 + 下一组要练什么）。
  Future<void> show({required String title, required String body});

  /// 撤掉那条通知（用户跳过休息、离开训练屏、或开始下一次休息）。
  Future<void> cancel();
}

/// 什么都不做（测试、以及 iOS）。
class NoopRestCue implements RestCue {
  const NoopRestCue();

  @override
  Future<void> show({required String title, required String body}) async {}

  @override
  Future<void> cancel() async {}
}

/// 走平台通道（Android 侧发本地通知）。
class MethodChannelRestCue implements RestCue {
  const MethodChannelRestCue();

  /// ⚠️ 必须与 `MainActivity.kt` 里的通道名一致。
  static const MethodChannel channel = MethodChannel('lianleme/rest_cue');

  @override
  Future<void> show({required String title, required String body}) =>
      _invoke('show', <String, Object?>{'title': title, 'body': body});

  @override
  Future<void> cancel() => _invoke('cancel', null);

  Future<void> _invoke(String method, Object? args) async {
    try {
      await channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // iOS 与测试环境：静默（那边有 Live Activity / 不需要）
    } on PlatformException catch (e) {
      debugPrint('休息提示失败（不影响训练）：$e');
    }
  }
}
