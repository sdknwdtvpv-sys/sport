import ActivityKit
import Flutter
import UIKit

/// Dart ↔ Live Activity 的桥。
///
/// **业务逻辑不在这里**：休息状态只有一份真相 —— `workout_controller.dart` 里的
/// `_restEndsAtMs`。这边只做两件事：把 Dart 给的"休息到几点"摆到锁屏上，以及撤掉它。
/// 倒计时由系统按 `endAt` 自己走（见 `RestActivityAttributes`），
/// 所以 App 被挂起时锁屏上的数字照样准 —— 这正是这个功能的意义。
enum RestActivityBridge {
  /// ⚠️ 必须与 `app/lib/features/workout/rest_activity.dart` 里的通道名一致。
  static let channelName = "lianleme/rest_activity"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "start":
        guard #available(iOS 16.2, *) else {
          // 老系统：静默成功（Dart 那边也不需要知道 —— 没有 Live Activity 不是错误）
          result(nil)
          return
        }
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "bad_arguments",
                              message: "start 需要一个字典", details: nil))
          return
        }
        Task {
          await start(args)
          await MainActor.run { result(nil) }
        }
      case "end":
        guard #available(iOS 16.2, *) else {
          result(nil)
          return
        }
        Task {
          await endAll()
          await MainActor.run { result(nil) }
        }
      case "activeCount":
        // 给端到端测试用的内省（也顺手回答了排查时的第一个问题：
        // "锁屏上为什么没有" —— 是没开成，还是开了但没显示）。
        guard #available(iOS 16.2, *) else {
          result(0)
          return
        }
        result(Activity<RestActivityAttributes>.activities.count)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  @available(iOS 16.2, *)
  private static func start(_ args: [String: Any]) async {
    // 同一时刻只留一条：Dart 每次开始休息都会调一次 start，
    // 不去重的话"连记三组"就会在锁屏上叠三条。
    await endAll()

    let endAtMs = (args["endAtMs"] as? NSNumber)?.doubleValue ?? 0
    let attributes = RestActivityAttributes(
      exerciseName: args["exerciseName"] as? String ?? ""
    )
    let state = RestActivityAttributes.ContentState(
      endAt: Date(timeIntervalSince1970: endAtMs / 1000),
      nextLabel: args["nextLabel"] as? String ?? "",
      setIndex: (args["setIndex"] as? NSNumber)?.intValue ?? 1,
      totalSets: (args["totalSets"] as? NSNumber)?.intValue ?? 1
    )
    do {
      // staleDate = 休息结束时刻：过了那一刻，系统会把这条标记成"过期"——
      // 万一 App 在后台被系统清掉了（没人来调 end），锁屏上那条也不会一直
      // 假装还有人在休息。
      _ = try Activity.request(
        attributes: attributes,
        content: ActivityContent(state: state, staleDate: state.endAt),
        pushType: nil
      )
      NSLog("LIANLEME-REST-ACTIVITY started")
    } catch {
      // 静默失败：锁屏上少一个倒计时，不该影响记录训练
      NSLog("LIANLEME-REST-ACTIVITY start failed: \(error)")
    }
  }

  @available(iOS 16.2, *)
  private static func endAll() async {
    for activity in Activity<RestActivityAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }
}
