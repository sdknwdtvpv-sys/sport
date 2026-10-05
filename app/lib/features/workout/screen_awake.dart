/// 练了么 · 训练中**别让屏幕熄掉**（v1.53）
///
/// 现场依据：手机架在器械上、或放在旁边的凳子上，每组之间看一眼 ——
/// 屏幕早就按系统超时黑了，于是每记一组都要先解锁一次。
/// 而组间那 60–90 秒恰恰是 `PRODUCT.md` §1 点名"用户不看手机"的场景。
///
/// 三条口径：
///   * **只在训练屏**亮着：`WorkoutScreen` 进 `initState` 开、`dispose` 关。
///     全局常亮是费电的，也会让"看一眼时间"变成负担。
///   * **失败是静默的**：平台没实现、系统拒绝，都不该影响记组 —— 与
///     `RestActivityBridge` 同一条纪律（少一个常亮，绝不能让训练屏记不了组）。
///   * 不申请任何权限：`FLAG_KEEP_SCREEN_ON` / `isIdleTimerDisabled` 都不是权限，
///     所以政策与商店表单一个字都不用改。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 屏幕常亮的开关。抽成接口是为了能在 widget 测试里换成一个记账的替身
/// （真机上"屏幕到底熄没熄"没法自动断言，但"进训练屏开了、走的时候关了"可以）。
abstract class ScreenAwake {
  /// 训练开始（进训练屏）。
  Future<void> keepOn();

  /// 训练结束 / 离开训练屏。
  Future<void> release();
}

/// 什么都不做。测试与"不关心常亮"的调用点用这个。
class NoopScreenAwake implements ScreenAwake {
  const NoopScreenAwake();

  @override
  Future<void> keepOn() async {}

  @override
  Future<void> release() async {}
}

/// 走平台通道：Android `FLAG_KEEP_SCREEN_ON`、iOS `isIdleTimerDisabled`。
class MethodChannelScreenAwake implements ScreenAwake {
  const MethodChannelScreenAwake();

  /// ⚠️ 必须与 `MainActivity.kt` / `ScreenAwakeBridge.swift` 里的通道名一致。
  static const MethodChannel channel = MethodChannel('lianleme/screen');

  @override
  Future<void> keepOn() => _set(true);

  @override
  Future<void> release() => _set(false);

  Future<void> _set(bool on) async {
    try {
      await channel.invokeMethod<void>('awake', on);
    } on MissingPluginException {
      // 平台没实现（测试环境、老版本包）：静默 —— 记组不受影响
    } on PlatformException catch (e) {
      debugPrint('screen awake 失败（不影响训练）：$e');
    }
  }
}
