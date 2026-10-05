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
  }
}
