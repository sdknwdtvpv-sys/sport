/// 训练提醒的**平台桥**：把"几点提醒"交给系统去排程与显示。
///
/// 为什么自己写、不引通知插件（2026-10-04）：我们需要的只是"在某个时刻弹一条本地通知"，
/// 而 `flutter_local_notifications` 会带进 `timezone`（还要自己初始化时区数据）、
/// Android 的 desugaring 配置、以及一整套我们不会用的能力（重复/周期/通知分组…）。
/// 本项目的规矩是**依赖只允许必要**，而这里真正必要的只有两件事：
/// 排一个闹钟、显示一条通知 —— 两个平台各自的系统 API 各写几十行就够。
///
/// 另一条同样硬的理由：每多一个第三方 SDK，政策里的依赖表 + 两张商店表单 +
/// 隐私事实表就要多一条要维护、要如实说明的东西。
library;

import 'package:flutter/services.dart';

/// 排给系统的提醒。
class ReminderRequest {
  const ReminderRequest({
    required this.atMs,
    required this.title,
    required this.body,
  });

  /// 什么时候响（毫秒时间戳，本地时区的绝对时刻）
  final int atMs;
  final String title;
  final String body;
}

abstract class ReminderBridge {
  /// 系统层面允不允许发通知。
  /// Android 13+ 与 iOS 都要先问过用户；**默认关着**就是这里的正常状态。
  Future<bool> isAllowed();

  /// 向系统要权限（Android 13+ 会弹一次系统对话框；iOS 会弹一次授权）。
  /// 返回用户最终的选择。**只在用户主动打开提醒开关时调** —— 不在启动时要。
  Future<bool> requestPermission();

  /// 排一条提醒（会先取消旧的：同一时刻只该有一条）。
  Future<void> schedule(ReminderRequest request);

  /// 取消所有已排的提醒。
  Future<void> cancel();

  /// 现在排着的那条在什么时候（没有则 null）。
  /// 端到端测试与"到底排上了没有"用 —— 只看日志是断言不了"取消干净了"的。
  Future<int?> scheduledAtMs();
}

/// 什么都不做：单元测试、以及平台没有实现时用。
class NoopReminder implements ReminderBridge {
  const NoopReminder();

  @override
  Future<bool> isAllowed() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> schedule(ReminderRequest request) async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<int?> scheduledAtMs() async => null;
}

/// 真身：走 MethodChannel（Swift / Kotlin 各一份实现）。
class MethodChannelReminder implements ReminderBridge {
  const MethodChannelReminder();

  static const MethodChannel channel = MethodChannel('lianleme/reminder');

  @override
  Future<bool> isAllowed() async {
    try {
      return await channel.invokeMethod<bool>('isAllowed') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      return await channel.invokeMethod<bool>('requestPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> schedule(ReminderRequest request) async {
    try {
      await channel.invokeMethod<void>('schedule', <String, Object?>{
        'atMs': request.atMs,
        'title': request.title,
        'body': request.body,
      });
    } catch (_) {
      // 静默：排不上提醒，不该影响记录训练
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await channel.invokeMethod<void>('cancel');
    } catch (_) {
      // 同上
    }
  }

  @override
  Future<int?> scheduledAtMs() async {
    try {
      return await channel.invokeMethod<int>('scheduledAtMs');
    } catch (_) {
      return null;
    }
  }
}
