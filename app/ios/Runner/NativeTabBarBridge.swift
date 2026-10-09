import Flutter
import UIKit

/// 练了么 · **苹果原生的 `UITabBar`**（2026-10-09，用户：「我想要苹果原生的 uitabbar」）
///
/// ## 它是干什么的
///
/// 底栏从"自己画一块 `UIGlassEffect` 玻璃 + 原生的字/图标"换成**系统那个真的
/// `UITabBar` 控件**：外观走 `UITabBarAppearance`（用户在 10.9 发来的
/// `StellarTabBar.swift` 用的正是这套 API），触摸、无障碍（VoiceOver 会念"标签页"）、
/// 长按自定义、以及 iOS 26 自带的新材质，都由系统负责 —— 我们不再自己画。
///
/// ## 三条边界（写清楚，免得下次误以为能拿更多）
///
/// 1. **它只是一个 `UITabBar`，不是 `UITabBarController`**。
///    iOS 26 那个**浮动胶囊 + 滚动自动收起 + `contentLayoutGuide`** 长在
///    `UITabBarController` 上（`tabBarMinimizeBehavior` / `contentLayoutGuide` /
///    `bottomAccessory`，全部 `API_AVAILABLE(ios(26.0))`，本机 iPhoneOS27.0.sdk 实读）。
///    要用上那些，得把外壳整个换成 UIKit 的 `UITabBarController` 并且**每个 tab 一个
///    FlutterView** —— 而本 App 刻意是"一个引擎、一份外壳状态"（`_todayPlan` / `_allSets` /
///    跨 tab 拖动都在 Dart 那一层），那是另一个量级的改动。所以这一版拿到的是
///    **苹果原生的控件与外观**，不是"浮动那一版"。
/// 2. **五个 Tab 在系统控件里是一视同仁的** —— 我们原来那颗"正中放大 + 强调色"
///    （v1.66.0 第 2b 条）在原生控件里没有对应 API：`UITabBarItem` 没有"某一格更大"。
///    所以中间那格从此与另外四格同规格；要保住强调，只能回到"自己画"。
/// 3. **拖动跟手（`dragIndex`）也没有了**：原生 tab bar 的选中是**离散**的，
///    没法让它的选中胶囊跟着手指连续移动。页面照样能左右拖（那是 Flutter 的
///    `PageView`），但底栏是"松手后跳过去"。
///
/// ## 触摸怎么走（这一条最容易接错）
///
/// 原来那块玻璃平台视图是"**触摸穿透**"的：Dart 侧在它上面盖了五块透明热区，
/// 因为玻璃本身不接触摸。**原生 `UITabBar` 自己接触摸** —— 所以 iOS 上**不能**再盖热区，
/// 否则 Flutter 的 `GestureDetector` 会把点击吃掉、系统控件永远收不到。
/// 选中变化由这里主动 `invokeMethod("onTabSelected")` 回给 Dart。
///
/// 通道名 `lianleme/native_tab_bar`（与 Dart 侧 `native_tab_bar.dart` 一一对应）。
enum NativeTabBarBridge {
  static let viewType = "lianleme/native_tab_bar"

  static func register(registrar: FlutterPluginRegistrar) {
    registrar.register(
      NativeTabBarFactory(messenger: registrar.messenger()),
      withId: viewType
    )
  }
}

final class NativeTabBarFactory: NSObject, FlutterPlatformViewFactory {
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
    NativeTabBarPlatformView(
      frame: frame,
      viewId: viewId,
      messenger: messenger,
      args: args as? [String: Any] ?? [:]
    )
  }
}

final class NativeTabBarPlatformView: NSObject, FlutterPlatformView, UITabBarDelegate {
  private let container = UIView()
  private let bar = UITabBar()
  private let channel: FlutterMethodChannel
  private var labels: [String] = []
  private var icons: [String] = []

  init(
    frame: CGRect,
    viewId: Int64,
    messenger: FlutterBinaryMessenger,
    args: [String: Any]
  ) {
    channel = FlutterMethodChannel(
      name: "lianleme/native_tab_bar/\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    labels = (args["labels"] as? [String]) ?? []
    icons = (args["icons"] as? [String]) ?? []
    let selectedColor = Self.color(args["selectedColor"]) ?? .label
    let unselectedColor = Self.color(args["unselectedColor"]) ?? .secondaryLabel

    container.backgroundColor = .clear
    bar.delegate = self
    bar.translatesAutoresizingMaskIntoConstraints = false

    // ── 外观：`UITabBarAppearance`（用户发来的 StellarTabBar 用的就是这一套）──
    //
    // ⚠️ 两条**必须**一起设（Stellar 那份文件里踩过的坑，注释写得对）：
    //   * `standardAppearance` 与 `scrollEdgeAppearance` 都要给，否则滚到顶/到底时外观会跳变；
    //   * 这里**不**用 `configureWithOpaqueBackground()`：我们要的是 iOS 26 那个材质本身，
    //     写死一个不透明底色就把它盖掉了（那正是用户发来的文件里"透出来"那条教训的**反向**
    //     用法 —— 他们那边要的是"别透"，我们这边要的是"就用系统的"）。
    let appearance = UITabBarAppearance()
    appearance.configureWithDefaultBackground()
    appearance.shadowColor = Self.color(args["hairline"])

    let item = UITabBarItemAppearance()
    item.configureWithDefault(for: .stacked)
    item.normal.iconColor = unselectedColor
    item.normal.titleTextAttributes = [.foregroundColor: unselectedColor]
    item.selected.iconColor = selectedColor
    item.selected.titleTextAttributes = [.foregroundColor: selectedColor]
    appearance.stackedLayoutAppearance = item
    appearance.inlineLayoutAppearance = item
    appearance.compactInlineLayoutAppearance = item

    bar.standardAppearance = appearance
    bar.scrollEdgeAppearance = appearance

    // ── 五个 Tab（SF Symbol + 中文标签，与 Dart 侧 `AppTabBar.tabs` 同序）──
    var items: [UITabBarItem] = []
    for (i, label) in labels.enumerated() {
      // ⚠️ `[safe:]` 是 `GlassBridge.swift` 里那个**模块级**的 Array 扩展 ——
      // 不要在这里再定义一份（Swift 会报 Invalid redeclaration，模拟器构建当场抓到）
      let image = icons[safe: i].flatMap { UIImage(systemName: $0) }
      items.append(UITabBarItem(title: label, image: image, tag: i))
    }
    bar.setItems(items, animated: false)
    let initial = (args["selectedIndex"] as? NSNumber)?.intValue ?? 0
    if initial >= 0 && initial < items.count {
      bar.selectedItem = items[initial]
    }

    container.addSubview(bar)
    NSLayoutConstraint.activate([
      bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      bar.topAnchor.constraint(equalTo: container.topAnchor),
      bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "setSelected":
        let i = (call.arguments as? [String: Any])
          .flatMap { ($0["index"] as? NSNumber)?.intValue } ?? 0
        if i >= 0 && i < self.bar.items?.count ?? 0 {
          self.bar.selectedItem = self.bar.items?[i]
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView { container }

  // MARK: - UITabBarDelegate

  /// 用户点了某一格 → 回给 Dart（外壳负责换页、并把选中状态同步回来）。
  ///
  /// ⚠️ **不要在这里自己改 `selectedItem`**：真源在 Dart（`_tab`），
  /// 两边各改一次就会出现"底栏显示第 2 个、内容却是第 3 个"那种错位。
  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    channel.invokeMethod("onTabSelected", arguments: ["index": item.tag])
  }

  // MARK: - 工具

  /// `#RRGGBB` / `#RRGGBBAA` → UIColor（与 `GlassBridge` 里那个同名方法同一套写法）
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
