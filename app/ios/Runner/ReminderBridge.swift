import Flutter
import UIKit
import UserNotifications

/// 训练提醒的通道（iOS 侧）。
///
/// 与 Android 那份（`android/.../MainActivity.kt`）是同一组方法名与参数，
/// 也与 `app/lib/features/profile/reminder_bridge.dart` 一一对应。
///
/// 三点与 iOS 有关的事实写在这里，免得下次重新查：
///  * 本地通知**不需要任何 Info.plist 声明**，也不需要联网权限；
///  * 授权是**一次性的**：用户拒绝之后 `requestAuthorization` 不会再弹，
///    只能他自己去系统设置里打开 —— 所以界面上那句提示必须说清这一点；
///  * 排程用 `UNCalendarNotificationTrigger`（绝对时刻），系统会在 App 不运行时到点触发，
///    而且**重装/重启都保留** —— 与 Android 的闹钟不同，这里不需要"开机重排"。
enum ReminderBridge {
  /// ⚠️ 必须与 `reminder_bridge.dart` 里的通道名一致。
  static let channelName = "lianleme/reminder"

  /// 固定标识：同一时刻只该有一条提醒（与 Android 侧"先撤再排"同一个口径）
  private static let requestId = "lianleme.training.reminder"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isAllowed":
        UNUserNotificationCenter.current().getNotificationSettings { settings in
          let ok = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
          DispatchQueue.main.async { result(ok) }
        }
      case "requestPermission":
        UNUserNotificationCenter.current()
          .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { result(granted) }
          }
      case "schedule":
        guard let args = call.arguments as? [String: Any],
              let atMs = (args["atMs"] as? NSNumber)?.doubleValue else {
          result(FlutterError(code: "bad_arguments", message: "schedule 需要 atMs", details: nil))
          return
        }
        schedule(atMs: atMs,
                 title: args["title"] as? String ?? "",
                 body: args["body"] as? String ?? "")
        result(nil)
      case "cancel":
        cancel()
        result(nil)
      case "scheduledAtMs":
        pending { atMs in
          DispatchQueue.main.async { result(atMs) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 排一条：先撤旧的（同 requestId 会被替换），再用日历年月日时分匹配。
  private static func schedule(atMs: Double, title: String, body: String) {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [requestId])

    let date = Date(timeIntervalSince1970: atMs / 1000)
    var comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    comps.second = 0

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    center.add(UNNotificationRequest(identifier: requestId, content: content, trigger: trigger))
  }

  private static func cancel() {
    UNUserNotificationCenter.current()
      .removePendingNotificationRequests(withIdentifiers: [requestId])
  }

  /// 现在排着的那条是什么时候（没有则 nil）。给端到端测试与排查用。
  private static func pending(_ done: @escaping (Int?) -> Void) {
    UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
      guard let req = requests.first(where: { $0.identifier == requestId }),
            let trigger = req.trigger as? UNCalendarNotificationTrigger,
            let date = trigger.nextTriggerDate() else {
        done(nil)
        return
      }
      done(Int(date.timeIntervalSince1970 * 1000))
    }
  }
}
