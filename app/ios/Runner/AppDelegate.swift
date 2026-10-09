import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // 组间休息的 Live Activity：Dart → MethodChannel → ActivityKit。
    // 从 pluginRegistry 取 registrar 是拿 binaryMessenger 的标准做法
    // （我们不是插件，所以自己注册一个通道）。
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RestActivityBridge") {
      RestActivityBridge.register(messenger: registrar.messenger())
    }
    // 训练提醒：Dart → MethodChannel → UNUserNotificationCenter
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ReminderBridge") {
      ReminderBridge.register(messenger: registrar.messenger())
    }
    // 训练中别让屏幕熄掉（v1.53）：Dart → MethodChannel → isIdleTimerDisabled。
    // 顺带把 `lianleme/rest_cue` 也在这里注册成**空操作** ——
    // 那边有 Live Activity 就够了，但通道得有实现，否则 Dart 侧收到
    // MissingPluginException，看起来像"忘了做"。
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ScreenAwakeBridge") {
      ScreenAwakeBridge.register(messenger: registrar.messenger())
    }
    // iOS 26 的液态玻璃（2026-10-06）：Dart → UiKitView → UIGlassEffect（真材质）。
    // ⚠️ 这是**唯一一个收 registrar 而不是 messenger 的桥** —— platform view 的 factory
    // 只能通过 registrar 注册（见 GlassBridge.swift 顶部那段注释）。
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GlassBridge") {
      GlassBridge.register(registrar: registrar)
    }
    // **苹果原生的 `UITabBar`**（2026-10-09，用户：「我想要苹果原生的 uitabbar」）：
    // Dart → UiKitView → 系统那个真的 UITabBar（外观走 UITabBarAppearance）。
    // ⚠️ 与 GlassBridge 一样，platform view 的 factory 只能通过 registrar 注册。
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NativeTabBarBridge") {
      NativeTabBarBridge.register(registrar: registrar)
    }
    // 从系统健康库读体成分（2026-10-09）：Dart → MethodChannel → HealthKit。
    // ⚠️ **只读不写**（`requestAuthorization(toShare: [], read: ...)`）——
    // 政策里承诺的就是这一条，别再顺手把"写"的授权也申请上。
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HealthBridge") {
      HealthBridge.register(messenger: registrar.messenger())
    }
  }
}
