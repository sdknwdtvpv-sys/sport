/// 组间休息的 **Live Activity**（iOS 锁屏 / 灵动岛）。
///
/// 它服务的是 `PRODUCT.md` §1 里唯一被点名要设计好的场景 —— **组间那 60 秒**：
/// 那个场景里用户**恰恰不看手机**（手机扣在器械上、或在包里），
/// 所以"锁屏上就能看到还剩多久、下一组练什么"就是这个功能的全部价值。
///
/// 三条设计约束：
///   1. **倒计时不在 Dart 里推**：Dart 只告诉系统"休息到几点结束"，
///      锁屏上那串数字由系统自己走（`Text(timerInterval:)`）——
///      否则 App 一被系统挂起，锁屏上的数字就冻住了，比不显示更糟；
///   2. **休息状态只有一份真相**：仍然是 `workout_controller` 里的 `_restEndsAtMs`，
///      这里只是把那个事实**广播**出去，不持有任何状态；
///   3. **失败必须是静默的**：Android 上没有这个东西、iOS 16.2 以下也没有 ——
///      锁屏上少一个倒计时，绝不该让训练屏记不了组（那才是北极星指标）。
library;

import 'package:flutter/services.dart';

/// 一条休息要显示的全部内容。
class RestActivityInfo {
  const RestActivityInfo({
    required this.exerciseName,
    required this.nextLabel,
    required this.setIndex,
    required this.totalSets,
    required this.endAtMs,
  });

  /// 动作名，如「杠铃卧推」
  final String exerciseName;

  /// 下一组练什么，如「62.5 kg × 8」——就是大按钮上那行字（同一个来源）
  final String nextLabel;

  /// 第几组（1 起）
  final int setIndex;

  final int totalSets;

  /// 休息**结束时刻**（毫秒时间戳）。系统据此自己走倒计时。
  final int endAtMs;
}

/// 交给平台去显示/撤下那条 Live Activity。
///
/// 抽成接口的理由与 `Analytics` 一样：**要能在测试里断言"什么时候该开始、什么时候该撤"**，
/// 而不是等装到手机上才发现"跳过休息之后锁屏上还挂着一条"。
abstract class RestActivityBridge {
  Future<void> start(RestActivityInfo info);
  Future<void> end();

  /// 现在系统里挂着几条（平台不支持时恒 0）。
  ///
  /// 加它只为一件事：**端到端测试要能断言"真的开出来了"**。
  /// 只看日志断言不了"跳过之后撤下了没有"，而"撤下"恰恰是最容易漏的那一半。
  Future<int> activeCount();
}

/// 什么都不做：Android、iOS 16.2 以下、以及所有测试都用它。
class NoopRestActivity implements RestActivityBridge {
  const NoopRestActivity();

  @override
  Future<void> start(RestActivityInfo info) async {}

  @override
  Future<void> end() async {}

  @override
  Future<int> activeCount() async => 0;
}

/// 真身：走 MethodChannel 交给 iOS 侧（`ActivityKit`）。
///
/// 通道名与 Swift 那边**必须一致**：`app/ios/Runner/RestActivityBridge.swift`。
class MethodChannelRestActivity implements RestActivityBridge {
  const MethodChannelRestActivity();

  static const MethodChannel channel = MethodChannel('lianleme/rest_activity');

  @override
  Future<void> start(RestActivityInfo info) => _invoke('start', <String, Object?>{
        'exerciseName': info.exerciseName,
        'nextLabel': info.nextLabel,
        'setIndex': info.setIndex,
        'totalSets': info.totalSets,
        'endAtMs': info.endAtMs,
      });

  @override
  Future<void> end() => _invoke('end', null);

  @override
  Future<int> activeCount() async {
    try {
      return await channel.invokeMethod<int>('activeCount') ?? 0;
    } catch (_) {
      return 0; // 平台没有 / 老系统 → 0 条，不是错误
    }
  }

  /// **绝不抛异常**（见文件头第 3 条）。缺平台实现（Android / 单元测试 /
  /// 老系统）时 `MissingPluginException` 是正常情况，不是错误。
  Future<void> _invoke(String method, Object? args) async {
    try {
      await channel.invokeMethod<void>(method, args);
    } catch (_) {
      // 静默：锁屏上少一个倒计时，不该影响记录训练
    }
  }
}
