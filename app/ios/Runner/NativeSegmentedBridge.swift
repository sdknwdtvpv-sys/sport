import Flutter
import UIKit

/// 练了么 · **苹果原生的 `UISegmentedControl`**（2026-10-09）
///
/// 用户看完底栏换成真 `UITabBar` 之后问：「其他的切换选项能不能也做成这个效果呢，
/// 比如说像周 月 年的那个调整」。所以这里给"三选一 / 两选一"这类**分段切换器**
/// 也接上系统控件：`UISegmentedControl` 就是 UIKit 里与 `UITabBar` 同级的那件东西 ——
/// iOS 26 上它自带液态玻璃底托与选中胶囊，选中动画、长按、无障碍都是系统的。
///
/// ## 用它的地方（Dart 侧 `ViSegmented` 的 iOS 分支）
///
///   * 「进步」页的 **周 / 月 / 年**；
///   * 「数据」页的 **按动作看 / 按时间看**；
///   * 「计划」页的 **本周 / 模板库 / 历史**；
///   * 「身体数据」页趋势卡的指标切换；
///   * 分享卡预览的浅色 / 深色。
///
/// ⚠️ **不**做成原生的是什么（有意）：动作选择器里那些**筛选胶囊**
/// （部位 / 器械 / 类型 / 细分标签）—— 那是"8 个里挑一个 + 全部"，是标签云不是分段控件；
/// `UISegmentedControl` 塞 8 段会挤成一排小字。它们保持 Flutter 的胶囊。
///
/// ## 与底栏那块（`NativeTabBarBridge.swift`）同一套规矩
///
/// * 触摸归**原生**（Dart 侧给 `EagerGestureRecognizer`）—— 真控件自己处理点选；
/// * 选中变化由这里 `invokeMethod("onChanged")` 回给 Dart，Dart 那边是唯一真源；
/// * 等宽：`apportionsSegmentWidthsByContent = false`，宽度由 **Dart 给**（`itemWidth × 段数`）
///   —— 原生按内容撑开的话，同一行里的别的元素会跟着跳。
enum NativeSegmentedBridge {
  static let viewType = "lianleme/native_segmented"

  static func register(registrar: FlutterPluginRegistrar) {
    registrar.register(
      NativeSegmentedFactory(messenger: registrar.messenger()),
      withId: viewType
    )
  }
}

final class NativeSegmentedFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    NativeSegmentedPlatformView(
      frame: frame,
      viewId: viewId,
      messenger: messenger,
      args: args as? [String: Any] ?? [:]
    )
  }
}

final class NativeSegmentedPlatformView: NSObject, FlutterPlatformView {
  private let container = UIView()
  private let control: UISegmentedControl
  private let channel: FlutterMethodChannel

  init(
    frame: CGRect,
    viewId: Int64,
    messenger: FlutterBinaryMessenger,
    args: [String: Any]
  ) {
    control = UISegmentedControl(items: args["labels"] as? [String] ?? [])
    channel = FlutterMethodChannel(
      name: "lianleme/native_segmented/\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    container.backgroundColor = .clear

    // 等宽：原生按内容撑开的话，同一行里的别的元素会跟着跳（见文件头那条）
    control.apportionsSegmentWidthsByContent = false
    control.addTarget(
      self,
      action: #selector(onChange),
      for: .valueChanged
    )
    apply(args)

    control.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(control)
    NSLayoutConstraint.activate([
      control.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      control.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      control.centerYAnchor.constraint(equalTo: container.centerYAnchor),
    ])

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      let map = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "setSelected":
        let i = (map["index"] as? NSNumber)?.intValue ?? -1
        if i >= 0 && i < self.control.numberOfSegments {
          self.control.selectedSegmentIndex = i
        }
        result(nil)
      case "setSpec":
        // 段数/文字变了（例：「身体数据」页撤销授权后可选指标少了几个）——
        // 只改 `selectedSegmentIndex` 不够，得把整块重建。
        self.apply(map)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 把一份 spec（`labels` / `selectedIndex` / 两个颜色 / 字号）套到控件上。
  ///
  /// 初始化与 `setSpec` 走同一条路：同一份参数从两条路进来，行为必须一样。
  private func apply(_ args: [String: Any]) {
    if let labels = args["labels"] as? [String], labels.count > 0 {
      let changed = labels.count != control.numberOfSegments
        || (0..<labels.count).contains { control.titleForSegment(at: $0) != labels[$0] }
      if changed {
        control.removeAllSegments()
        for (i, label) in labels.enumerated() {
          control.insertSegment(withTitle: label, at: i, animated: false)
        }
      }
    }

    // ⚠️ **不设** `selectedSegmentTintColor`：iOS 26 那个"选中胶囊"是系统玻璃自己画的，
    // 盖一个纯色上去就把玻璃替掉了（那正是用户要的观感）。
    let fontSize = (args["fontSize"] as? NSNumber)?.doubleValue ?? 12
    if let unselected = Self.color(args["unselectedColor"]) {
      control.setTitleTextAttributes(
        [
          .foregroundColor: unselected,
          .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
        ],
        for: .normal
      )
    }
    if let selected = Self.color(args["selectedColor"]) {
      control.setTitleTextAttributes(
        [
          .foregroundColor: selected,
          .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
        ],
        for: .selected
      )
    }

    let initial = (args["selectedIndex"] as? NSNumber)?.intValue ?? 0
    if initial >= 0 && initial < control.numberOfSegments {
      control.selectedSegmentIndex = initial
    }
  }

  func view() -> UIView { container }

  /// 用户点了某一段 → 回给 Dart（真源在 Dart，这里只报告"点了哪一段"）。
  @objc private func onChange() {
    channel.invokeMethod("onChanged", arguments: ["index": control.selectedSegmentIndex])
  }

  /// `#RRGGBB` / `#RRGGBBAA` → UIColor（与 `GlassBridge` / `NativeTabBarBridge` 同一套）
  private static func color(_ raw: Any?) -> UIColor? {
    guard let s = raw as? String else { return nil }
    var hex = s.trimmingCharacters(in: .whitespaces)
    if hex.hasPrefix("#") { hex.removeFirst() }
    guard hex.count == 6 || hex.count == 8,
          let value = UInt64(hex, radix: 16) else { return nil }
    let hasAlpha = hex.count == 8
    let r = CGFloat((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
    let g = CGFloat((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
    let b = CGFloat((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
    let a = hasAlpha ? CGFloat(value & 0xFF) / 255 : 1
    return UIColor(red: r, green: g, blue: b, alpha: a)
  }
}
