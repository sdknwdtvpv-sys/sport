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
  }
}
