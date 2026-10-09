/// 练了么 · **系统健康库**的桥（iOS HealthKit / Android Health Connect）
///
/// 两端都接了：iOS 走 HealthKit（`ios/Runner/HealthBridge.swift`），
/// **Android 走平台自带的 Health Connect，只有 14+ 能用**
/// （`android/.../HealthConnectApi34.kt`；为什么不用 Jetpack 那个库，那份文件头写了）。
///
/// 这个文件只做一件事：把"从系统健康库读体成分"变成三个 Dart 方法。
/// 具体怎么读由平台那两份实现负责（`ios/Runner/HealthBridge.swift`、
/// `android/app/src/main/kotlin/.../HealthBridge.kt`），形状照仓库里已有的桥
/// （`features/profile/reminder_bridge.dart`、`features/workout/screen_awake.dart`）：
/// 一个接口 + 一个空实现 + 一个通道实现，平台没实现时**静默退化**、不抛给界面。
///
/// ⚠️ 三件必须记住的事：
///   1. **它一个字都不写回健康库**（`docs/plan-health-sync.md` §二：先只读不双向）；
///   2. 读权限的状态在 iOS 上**查不出来**（Apple 故意不给"读"的授权状态查询，
///      `authorizationStatus` 只对"写"有意义）—— 所以这里没有 `hasPermission()`，
///      只有"请求一次"和"读到什么就是什么"；
///   3. 空列表是**正常结果**（健康库里就是没数据、或者用户没允许读），不是错误。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 健康库里的一条体成分样本。**只读的五样东西**：时间 + 体重 + 体脂率 + 身高 + 腰围。
///
/// 别的类型（心率 / 睡眠 / 运动）我们**不读也不申请** —— 这一条写在
/// `docs/plan-health-sync.md` §二那张表里，政策正文也是这么承诺的。
class HealthSample {
  const HealthSample({
    required this.atMs,
    this.weightKg,
    this.bodyFatPct,
    this.heightCm,
    this.waistCm,
  });

  /// 采样时刻（毫秒时间戳）。归属哪一天由调用方按**本地日**算。
  final int atMs;
  final double? weightKg;
  final double? bodyFatPct;
  final double? heightCm;

  /// 腰围（cm）。2026-10-09（10.9 清单第 9 条）：与另外三样同一道同意门、
  /// 同一次读取 —— 它在两端都算"体成分"这一类（HealthKit 的 waistCircumference /
  /// Health Connect 的 WaistCircumferenceRecord）。
  final double? waistCm;

  bool get hasContent =>
      weightKg != null ||
      bodyFatPct != null ||
      heightCm != null ||
      waistCm != null;
}

/// 系统健康库的读接口。
abstract class HealthBridge {
  /// 这台设备现在能不能**读**系统健康库。
  ///
  /// 两端的答案不一样，而且都是真的：
  ///   * iOS：`HKHealthStore.isHealthDataAvailable()`（iPad 上没有"健康"App → false）；
  ///   * Android：**只有 14+ 且系统里真有 Health Connect 模块才是 true** ——
  ///     13 及以下要装那个独立 App、还得抬 minSdk 到 26 走 Jetpack 库，那是产品决定，
  ///     见 `docs/plan-health-sync.md` §七。
  /// 界面上那个入口**只在它为 true 时出现**（`body_metric_screen.dart` 的 `_healthAvailable`）。
  Future<bool> isAvailable();

  /// 拉起系统授权弹窗。返回值 = "弹窗走完了、可以试着读"，**不是**"读权限拿到了"
  /// （iOS 读权限查不出来，理由见文件头）。用户拒绝时真实结果是"读到空列表"。
  Future<bool> requestPermission();

  /// 读最近 [days] 天的体成分样本（新的在前）。空列表是正常结果。
  Future<List<HealthSample>> readBodyComposition({int days = 180});
}

/// 平台没实现时的空实现：什么都不读、什么都不返回。
///
/// 与 `NoopReminder` 同一个用途 —— 让"这台设备/这个环境没有这个能力"变成
/// **安静的降级**，而不是一个 MissingPluginException。
class NoopHealthBridge implements HealthBridge {
  const NoopHealthBridge();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<List<HealthSample>> readBodyComposition({int days = 180}) async =>
      const <HealthSample>[];
}

/// 走平台通道的实现。通道名 `lianleme/health`，方法名见下面三个 `invokeMethod`。
class MethodChannelHealthBridge implements HealthBridge {
  const MethodChannelHealthBridge();

  static const MethodChannel channel = MethodChannel('lianleme/health');

  /// "这台设备有没有健康库"最多等这么久。
  ///
  /// ⚠️ 为什么需要它：这一问是在**页面加载时**发的，而它前面挂着一个转圈 ——
  /// 平台那端要是永远不回话（引擎卡住、通道名对不上又没抛异常这类），
  /// 用户看到的就是**永远转下去的身体数据页**。宁可 5 秒后答"读不到"（入口不出现），
  /// 也不要赌平台一定会回话。
  /// ⚠️ `requestPermission` **故意没有超时**：那一步是在等用户点系统弹窗，
  /// 用户想看多久就看多久，替它设超时反而是错的。
  static const Duration _probeTimeout = Duration(seconds: 5);

  @override
  Future<bool> isAvailable() async {
    try {
      return await channel
              .invokeMethod<bool>('isAvailable')
              .timeout(_probeTimeout) ??
          false;
    } on TimeoutException {
      return false;
    } on MissingPluginException {
      // 平台没实现（单元测试、还没接这一端的旧包）：当成"没有健康库"
      return false;
    } on PlatformException catch (e) {
      debugPrint('健康库 isAvailable 失败：$e');
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      return await channel.invokeMethod<bool>('requestPermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('健康库 requestPermission 失败：$e');
      return false;
    }
  }

  @override
  Future<List<HealthSample>> readBodyComposition({int days = 180}) async {
    try {
      final List<Object?>? raw = await channel
          .invokeMethod<List<Object?>>(
            'readBodyComposition',
            <String, Object?>{'days': days},
          )
          // 读本身可能慢（上百条样本），但也不该无限等 —— 半分钟还没回来就如实说"没读到"
          .timeout(const Duration(seconds: 30));
      if (raw == null) return const <HealthSample>[];
      final List<HealthSample> out = <HealthSample>[];
      for (final Object? item in raw) {
        if (item is! Map) continue;
        final Object? at = item['atMs'];
        if (at is! num) continue;
        out.add(HealthSample(
          atMs: at.toInt(),
          weightKg: (item['weightKg'] as num?)?.toDouble(),
          bodyFatPct: (item['bodyFatPct'] as num?)?.toDouble(),
          heightCm: (item['heightCm'] as num?)?.toDouble(),
          waistCm: (item['waistCm'] as num?)?.toDouble(),
        ));
      }
      return out;
    } on TimeoutException {
      return const <HealthSample>[];
    } on MissingPluginException {
      return const <HealthSample>[];
    } on PlatformException catch (e) {
      debugPrint('健康库 readBodyComposition 失败：$e');
      return const <HealthSample>[];
    }
  }
}
