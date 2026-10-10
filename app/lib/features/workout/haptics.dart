/// 练了么 · 训练屏的**触觉反馈**（v1.53；VI 计划 T2-2 收成一个入口）
///
/// 为什么需要它：健身房是吵的，手机多半架在器械上或放在旁边 ——
/// 「记上了没有」如果只有视觉那一条通道，用户就得低头确认一次。
/// 一次轻震等于一句"记上了"，而且**不用看屏幕**。
///
/// 为什么抽成接口而不是直接在控制器里调 `HapticFeedback`：
/// 控制器是纯 Dart（`flutter/foundation` 那一层），平台通道留在外面才测得动 ——
/// 与 `RestActivityBridge` 同一条理由。默认值是 [NoopHaptics]，
/// 所以测试与其它 20 多个构造点什么都不用改，**生产在 `main.dart` 接上真的那个**。
///
/// ⚠️ **2026-10-10（T2-2）从"四个方法"收成一个 [Haptics.play]**：四个方法各写一遍
/// 意味着"有哪几种反馈"这件事散在接口上，加一档要改接口 + 所有实现 + 所有替身；
/// 现在四档收进 [HapticCue]，替身只要记一串 cue 就能断言"该震的时候震了没有、顺序对不对"。
library;

import 'dart:async';

import 'package:flutter/services.dart';

/// 训练屏需要反馈的**四个时刻**（用户靠在垫子上不看屏幕时要能分开的四种节奏）。
enum HapticCue {
  /// 成功记下一组：**单次中等**。只有真的写进库那一次才算 —— 被挡下的那次不算。
  setLogged,

  /// 组间休息走到 0：**单次重**。那一下通常不看屏幕，靠它把人叫回来。
  restFinished,

  /// 组间休息**还剩 3 秒**（T2-4）：**最轻的一跳**。
  ///
  /// 为什么要它：那 60 秒里用户多半在看器械或手机背面，**"到了"不能是突然的一下** ——
  /// 先给一个最轻的预告，人才来得及放下器械、走回手机前。
  ///
  /// ⚠️ 三条口径（也是它和 [restFinished] 分开的理由）：
  ///   * **只响一次**，不是 3-2-1 三下（三下就是噪音，而且与"到点"抢注意力）；
  ///   * 比 [restFinished] 轻**两档**（`selectionClick` vs `heavyImpact`）——
  ///     两者隔 3 秒，强度差得开才分得清"准备"与"到"；
  ///   * **总时长 ≤ 5 秒的休息不发预告**（本来就没时间预告，发了等于两次提示挤在一起）。
  restPreview,

  /// 计时动作撑到了今天的秒数（v1.53）：**轻-轻两下**。
  ///
  /// 单靠 `HapticFeedback` 的 API 表达不了"节奏"，但"轻-轻"与另外三种
  /// （单次中等 / 单次重 / 最轻一跳）在手上是能分开的。
  targetReached,
}

/// 训练屏需要的触觉反馈。
abstract class Haptics {
  /// 响一下 [cue]。
  Future<void> play(HapticCue cue);

  /// **掐掉还没响的后续动作**（只有 [HapticCue.targetReached] 那种"两下"有后续）。
  ///
  /// 为什么必须有它：两下之间隔着 120ms，而用户可能在这 120ms 里离开训练屏 ——
  /// 那时第二下不该再震（"我已经走了，手机还自己震一下"是最典型的幽灵反馈）。
  /// 这也正是实现里那一下不写成 `Future` 延时的原因：**它不可取消**。
  void cancelPending();
}

/// 什么都不做。测试、以及不关心反馈的调用点用这个。
class NoopHaptics implements Haptics {
  const NoopHaptics();

  @override
  Future<void> play(HapticCue cue) async {}

  @override
  void cancelPending() {}
}

/// 走系统触觉（`HapticFeedback`，Flutter 自带，**零依赖**）。
///
/// ⚠️ 全部都是"尽力而为"：设备没有马达、系统关掉了触觉反馈、
/// 或者平台不支持，这些调用都是**空操作**（返回 null），不会抛。
/// 所以训练屏永远不该等它们 —— 调用点一律 `unawaited`。
///
/// 不是 `const`：它持有"第二下"的定时器（见 [cancelPending]）。
class SystemHaptics implements Haptics {
  SystemHaptics();

  Timer? _secondTap;

  @override
  Future<void> play(HapticCue cue) async {
    switch (cue) {
      case HapticCue.setLogged:
        await HapticFeedback.mediumImpact();
      case HapticCue.restFinished:
        await HapticFeedback.heavyImpact();
      case HapticCue.restPreview:
        // 最轻的一跳（`selectionClick` 是系统里"选中了一格"那种量级）
        await HapticFeedback.selectionClick();
      case HapticCue.targetReached:
        await HapticFeedback.lightImpact();
        // 第二下用 `Timer`，不是 `Future` 延时：
        //   * `Timer` **可以被取消**（`Future` 延时不能）—— 离开训练屏就不该再震；
        //   * 计划的判据 4 也要求这个文件里没有那种延时（那一条是"不可取消"这个
        //     真问题的一个具体名字，不是洁癖）。
        _secondTap?.cancel();
        _secondTap = Timer(const Duration(milliseconds: 120), () {
          _secondTap = null;
          unawaited(HapticFeedback.lightImpact());
        });
    }
  }

  @override
  void cancelPending() {
    _secondTap?.cancel();
    _secondTap = null;
  }
}
