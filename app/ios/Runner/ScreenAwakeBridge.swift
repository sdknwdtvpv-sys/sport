import Flutter
import UIKit

/// Dart ↔ 「训练中别让屏幕熄掉」的桥（v1.53）。
///
/// 现场依据：手机架在器械上、或放在旁边凳子上，每组之间看一眼 —— 屏幕早就按
/// 系统超时黑了，于是每记一组都要先解锁一次。而组间那 60–90 秒恰恰是
/// `PRODUCT.md` §1 点名"用户不看手机"的场景。
///
/// 三条口径：
///  * 只有训练屏会开它（`workout_screen.dart` 进 initState 开、dispose 关）——
///    全局 `isIdleTimerDisabled` 是费电的；
///  * 它不是权限，所以政策与商店表单一个字都不用改；
///  * 失败静默：少一个常亮绝不能让训练屏记不了组。
enum ScreenAwakeBridge {
  /// ⚠️ 必须与 `app/lib/features/workout/screen_awake.dart` 里的通道名一致。
  static let channelName = "lianleme/screen"

  /// 组间休息的体外提示（`lianleme/rest_cue`）。
  ///
  /// **iOS 上显式实现成空操作**：这边已经有 Live Activity —— 锁屏与灵动岛上就有
  /// 倒计时和"下一组练什么"，再来一条通知是重复打扰。写成空操作是为了
  /// **不用 MissingPluginException 表达"我们决定不做"**（那看起来像漏了）。
  static let restCueChannelName = "lianleme/rest_cue"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "awake":
        let on = (call.arguments as? Bool) ?? false
        DispatchQueue.main.async {
          UIApplication.shared.isIdleTimerDisabled = on
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let restCue = FlutterMethodChannel(name: restCueChannelName, binaryMessenger: messenger)
    restCue.setMethodCallHandler { call, result in
      // show / cancel 都当作成功 —— 见上面那段"为什么 iOS 上是空操作"
      result(nil)
    }
  }
}
