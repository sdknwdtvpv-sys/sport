import Flutter
import UIKit

/// 练了么 · iOS 26 的「液态玻璃」（`UIGlassEffect`）—— Dart → `UiKitView` → 真材质。
///
/// ## 为什么自己写，不引 `native_liquid_glass` / `liquid_glass_renderer`
///
/// 与本仓库一贯做法一致（通知、Live Activity、休息提示都是自己写的桥）：**多一个直接依赖
/// 就多一条要维护、要如实说明的东西** —— 政策 §三之五的 SDK 表、两张商店表单、
/// `privacy-facts.json`、164 号文的双清单，一处都不能少。而我们需要的只有"一块玻璃"。
/// 真材质就三行 UIKit：`UIGlassEffect(style:)` + `UIVisualEffectView`。
///
/// ## 事实（本机 Xcode 27.0 / iPhoneSimulator27.0.sdk 的 `UIGlassEffect.h` 实读）
///
/// * `UIGlassEffect : UIVisualEffect`，`API_AVAILABLE(ios(26.0))`、visionOS/watchOS 不可用；
///   有 `+effectWithStyle:`（`.regular` / `.clear`）、`isInteractive`、`tintColor`；
/// * 圆角走 `UIView.cornerConfiguration`（`UICornerConfiguration`），不是 `layer.cornerRadius`；
/// * `UIGlassContainerEffect` 是"把多块玻璃合成一块"的**容器** —— 听起来正是我们要的，
///   但 2026-10-06 实测**它会把叠在一起的两块玻璃抹平成一块**（选中胶囊的亮边和凸起全没了）。
///   所以本桥**不用它**：底托与选中胶囊是两块各自独立的玻璃（证据见下面第 3 条）。
///
/// ## 两条**不能靠猜**的规矩（2026-10-06 的 spike 实测，证据在 `docs/images/glass-spike-*.png`）
///
/// 1. **玻璃必须背后有东西可折射**：纯炭黑 `#101014` 上 `.regular` 会变成**一块浅灰板**
///    （比屏幕上所有东西都亮、抢视线）。所以 Dart 侧默认给 `.clear` + 极淡的 tint，
///    并且要求调用方**在玻璃背后垫一层内容/纹理**（`GlassSurface.backdrop`）。
/// 2. **iOS 26 以下没有玻璃**：`.systemUltraThinMaterial` 那条分支是"退回"，不是"等价物"——
///    本机只有 iOS 27 运行时，**这一支没有在真机上验过**（写在文档里，别当成已验）。
/// 3. **要"看得见"的选中胶囊，就别用 `UIGlassContainerEffect`**（2026-10-06 真机反馈 + spike
///    对比，证据 `docs/images/glass-probe-segment-variants.png`）：真机上用户的原话是
///    "切 tab 的时候完全感觉不到玻璃的感觉"。原因是那两块玻璃**互相叠着**（胶囊整块在底托里面），
///    容器把它们当成一块 → 合成后**没有内部亮边、没有凸起**，屏幕上就是一条平的玻璃带。
///    同一组参数只把容器去掉（其余不动），胶囊立刻变成一块**有亮边的凸起玻璃**。
///    代价：切换时不再有"融合"的形变（苹果自己的分段控件也是"一块独立的选中玻璃"）。
/// 4. **按压反馈要我们自己通报**：平台视图在 Flutter 内容**下面**，手指落在上面那层标签/图标上，
///    UIKit 拿不到触摸 —— 所以 `UIGlassEffect.isInteractive` 那套"果冻"反应**触发不了**。
///    替代做法：Dart 侧 `GlassSegmented` 用 `Listener` 盯着指针，把"按在第几格/松开了"
///    通过通道发过来，原生演形变与提亮（`press` / `release` 两个方法）。观感一致、又不动
///    点击与旁白那条链路。
/// 5. **左右拖页面时胶囊要跟手**：外壳在 iOS 上用 `PageView`（可拖），`PageController`
///    每帧把"当前停在第几页"（小数）发过来（`setIndexFraction`），胶囊就跟着手指滑 ——
///    这是"丝滑"的来源。拖动期间不做动画（动画由手指给）。
enum GlassBridge {
  /// ⚠️ 必须与 `app/lib/core/glass_surface.dart` 里的 viewType 一致。
  static let viewType = "lianleme/glass"

  /// 「底托 + 选中胶囊」那一个：分段控件 / 底栏用它（两块**独立**玻璃，见文件顶部第 3 条）。
  /// ⚠️ 与 `app/lib/core/glass_segmented.dart` 里的必须逐字一致。
  static let segmentedViewType = "lianleme/glass_segmented"

  /// **开关**：直接用系统的 `UISwitch` —— iOS 26 上它自带液态玻璃（用户 2026-10-06 的
  /// 备忘条第 3 条："开关按钮没有上苹果的原生玻璃效果"）。自己拿 UIView 仿一个是最下策：
  /// 材质、按压回弹、旁白全都要重写，而且永远差一点。
  /// ⚠️ 与 `app/lib/core/glass_switch.dart` 里的必须逐字一致。
  static let switchViewType = "lianleme/switch"

  /// ⚠️ 与 `ReminderBridge` 那批"通道桥"的签名不同：platform view 要的是 **registrar**
  /// （注册 factory 用它），不是 messenger —— 拿 messenger 注册不出 platform view 来。
  static func register(registrar: FlutterPluginRegistrar) {
    registrar.register(GlassViewFactory(messenger: registrar.messenger()), withId: viewType)
    registrar.register(
      GlassSegmentedViewFactory(messenger: registrar.messenger()), withId: segmentedViewType)
    registrar.register(
      GlassSwitchViewFactory(messenger: registrar.messenger()), withId: switchViewType)
  }
}

/// **一块底托 + 一块"选中胶囊"**：两块**各自独立**的 `UIGlassEffect`
/// （**故意不进 `UIGlassContainerEffect`** —— 那个会把它们抹平成一块，见文件顶部第 3 条）。
/// 胶囊比底托往里缩 `pillInset`（默认 5pt），于是它有**自己的一圈亮边**，看得出是"凸起来的一块"。
///
/// 为什么把几何放在**原生侧**算（而不是从 Dart 每帧传坐标）：
///   * 滑动在 UIView 动画里跑（最接近系统行为，也不用每帧过一次通道）；
///   * 所以要求**条目等宽** —— 这是这个效果的代价，Dart 那边把分段控件改成等分。
///
/// 标签与图标仍然是 **Flutter 画的**（盖在平台视图上面）：这一层只负责"玻璃"。
class GlassSegmentedViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger; super.init() }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    GlassSegmentedPlatformView(
      frame: frame,
      viewId: viewId,
      messenger: messenger,
      args: args as? [String: Any] ?? [:]
    )
  }
}

extension Array {
  /// 越界就 nil（`labels` / `icons` 的条数与 count 不必逐字对齐）
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

/// 宿主：`UiKitView` 的 frame 是 **Flutter 布局时**才定的，所以不能只在 init 里画一次 ——
/// 由它接管 `layoutSubviews`，尺寸一变就重新摆两块玻璃。
/// （不直接继承 `UIVisualEffectView`：苹果不建议继承它，而且我们只需要一层壳。）
final class GlassHostView: UIView {
  var onLayout: ((CGRect) -> Void)?
  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?(bounds)
  }
}

class GlassSegmentedPlatformView: NSObject, FlutterPlatformView {
  private let host = GlassHostView()
  private let base: UIVisualEffectView
  private let pill: UIVisualEffectView
  /// **第二颗水滴**：手指按住某一格时，在那儿冒出来的一小块玻璃。
  /// 它和 `pill` 在**同一个 `UIGlassContainerEffect` 里** —— 两滴靠近时苹果会把它们
  /// **融成一滴**（中间长出一道"脖子"），这才是用户要的"两滴水滴融合"。
  private let drop: UIVisualEffectView
  /// 只装 `pill` + `drop` 的容器。⚠️ **底托（base）故意不在里面**：
  /// 底托把整个胶囊包住，把它也放进去的话三块会被抹平成一坨（见文件头第 3 条）。
  private let glassBox: UIVisualEffectView
  private let count: Int
  private var index: Int
  private let radius: CGFloat
  private let pillInset: CGFloat
  /// 按住时**每边**比平时再鼓出来多少 pt（默认 14）—— 参考图里那个"圆按钮"的幅度。
  private let pressBulge: CGFloat
  /// 手指左右拖动页面时，胶囊的**连续位置**（0 = 第一格，2.4 = 第二格往右 40%）。
  /// 由 Dart 侧的 `PageController` 每帧喂进来 —— 于是胶囊是**跟着手指滑**的，不是跳过去的。
  private var dragFraction: CGFloat?

  // ── 原生文案（2026-10-06 加）────────────────────────────────────────────
  //
  // ⚠️ **为什么格子里的字必须由原生画**：玻璃会**折射它背后的东西**，而 Flutter 那一层画的字
  // 恰好就在玻璃背后（iOS 的平台视图永远盖在 Flutter 内容之上），于是屏幕上同时出现**两份字**：
  // 一份是 Flutter 画的（清晰、位置对），一份是玻璃把同一份字**折射**出来的（错位、发虚）——
  // 用户看到的就是「重量单位这里显示 bug」。把字画在玻璃**里面**（同一个平台视图、玻璃之上）
  // 就没有第二份可折射。顺带：SF Symbol 比 Material 图标更像苹果（底栏那五个）。
  private let labelsBox = UIView()
  private var itemViews: [UIView] = []
  private var itemLabels: [UILabel] = []
  private var itemIcons: [UIImageView] = []
  private var iconNames: [String] = []
  private var selectedColor: UIColor = .white

  // ── 正中那颗"凸起"（2026-10-08，v1.61.0）────────────────────────────────
  //
  // 起因是用户 10.8 清单第 1 条：「tab 栏的训练 玻璃效果 bug」——
  // v1.60.0 我把那颗圆画在 **Flutter 层**（底栏的 `Stack` 顶部），而 iOS 的平台视图
  // **永远盖在 Flutter 内容之上**（上面那段注释已经写死了这条），于是圆落在玻璃**背后**，
  // 被折射成一层发灰的虚影（截图里圆是半透明的、下面还浮着一层淡淡的「训练」）。
  //
  // 修法：这一层是"玻璃**之上**"的那一层（`labelsBox`），把圆画在这里就不会被折射。
  // 它在玻璃**里面**、不能超出平台视图的边界（iOS 平台视图是一张按 bounds 裁好的纹理），
  // 所以 iOS 上它是"实心强调圆"，而不是 Android 那种"凸出上沿 10pt"——
  // 两者是**同一个意图、各自贴合本端材质**的做法，差异写在 `docs/screens.md`。
  private var emphasisIndex: Int = -1
  private var emphasisColor: UIColor?
  private var emphasisIconColor: UIColor?
  /// 被点亮那一格的图标大小（2026-10-09，10.9 清单第 2b 条）。
  /// 不去画圆之后，"中间那格与别人不同"就只剩大小与颜色两个手段 —— 而这个大小
  /// 只有原生能改（字与图标都画在玻璃**之上**）。0 = 与其余几格一样大。
  private var emphasisIconSize: CGFloat = 0
  private let emphasisCircle = UIView()
  private var unselectedColor: UIColor = .gray
  private var labelFontSize: CGFloat = 12
  private var iconSize: CGFloat = 22
  private let channel: FlutterMethodChannel

  /// 按下时手指所在的那一格（`nil` = 没在按）。
  private var pressedIndex: Int?
  /// 手指在这一层里的位置（跟着手指走的那颗水滴用它定位）。
  private var pressX: CGFloat?
  /// 第二颗水滴现在该不该露面（按住另一格时露面；按当前这一格只鼓包、不冒水滴）。
  private var dropVisible = false
  /// 手指已经抬了、但"换哪一格"的消息可能还在路上 —— 水滴先留着，
  /// 等 `setIndex` 来了就**跟着胶囊一起"融"到新那一格**去。
  private var releasedAt: Date?
  private var dropHideTimer: Timer?
  /// 换"按下/松开"的样子：iOS 26 上改的是玻璃的染色，26 以下只能改底色。
  private let applyPressLook: (Bool) -> Void

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger, args: [String: Any]) {
    count = max(1, (args["count"] as? NSNumber)?.intValue ?? 1)
    index = min(max(0, (args["index"] as? NSNumber)?.intValue ?? 0), count - 1)
    radius = CGFloat((args["radius"] as? NSNumber)?.doubleValue ?? 0)
    pillInset = CGFloat((args["pillInset"] as? NSNumber)?.doubleValue ?? 5)
    pressBulge = CGFloat((args["pressBulge"] as? NSNumber)?.doubleValue ?? 14)

    // ⚠️ `style` 必须真的读（`regular` / `clear`）：Dart 那边有调用方（卡片平底上的那两行
    // 单位）**故意**要 `.clear` —— 平底上 `.regular` 会变成一块灰板。写死 `.regular`
    // 会让那个参数**静默失效**（界面变灰、没有任何报错）—— 这类"参数漂了"的坑本仓库吃过。
    let isClearStyle = (args["style"] as? String) == "clear"
    // ⚠️ 胶囊默认 `clear` 而不是跟底托一样：两块 `.regular` 叠在一起 = **双重磨砂**，
    // 那颗鼓起来的玻璃就成了"奶白疙瘩"，一点都不透（2026-10-06 真机反馈原话：
    // "通透度太差了 完全不是透明的"）。`.clear` 叠在磨砂底托上仍然透得过去 ——
    // 逐行对比见 `docs/images/glass-probe-press-variants.png` 的第 2/3 行。
    let isClearPill = ((args["pillStyle"] as? String) ?? "clear") == "clear"

    // ⚠️ 两块玻璃先落在**局部变量**上再赋给属性：`applyPressLook` 这个闭包要用到它们，
    // 而"在 init 里捕获 self 的属性"会报 *capture of 'self' before all members are initialized*
    // （2026-10-06 真被编译器挡下来过一次）。
    let baseView: UIVisualEffectView
    let pillView: UIVisualEffectView
    let dropView: UIVisualEffectView
    let boxView: UIVisualEffectView
    let pressLook: (Bool) -> Void

    if #available(iOS 26.0, *) {
      let style: UIGlassEffect.Style = isClearStyle ? .clear : .regular
      let baseEffect = UIGlassEffect(style: style)
      if let hex = args["baseTint"] as? String, let c = GlassPlatformView.color(hex) {
        baseEffect.tintColor = c
      }
      baseView = UIVisualEffectView(effect: baseEffect)

      let pillEffect = UIGlassEffect(style: isClearPill ? .clear : .regular)
      // tint 可以**完全不给**（= 全透明的玻璃）：用户 2026-10-06 明确要这个
      // （"鼓起来那一块能不能做成全透明的"）。给了就按给的染色，没给就一点都不染 ——
      // 那时"选中的是谁"只靠图标/文字的颜色与那颗玻璃的边缘高光来说话。
      let normalTint: UIColor? = (args["pillTint"] as? String)
        .flatMap { GlassPlatformView.color($0) }
        .flatMap { $0.cgColor.alpha > 0 ? $0 : nil }
      if let t = normalTint { pillEffect.tintColor = t }
      pillView = UIVisualEffectView(effect: pillEffect)

      // 第二颗水滴：跟胶囊同一套材质（通透的那一套）
      let dropEffect = UIGlassEffect(style: isClearPill ? .clear : .regular)
      if let t = normalTint { dropEffect.tintColor = t }
      dropView = UIVisualEffectView(effect: dropEffect)

      // 装这两滴的容器 —— "融合"这件事只能由它给。`spacing` = 多近开始融：
      // **相邻两格**（比如胶囊在「训练」、手指按在「进步」）两颗圆滴的边缘相距 ~22pt，
      // 所以这里给 34pt，够它们在中间长出一根"脖子"（真的像两滴水融在一起）。
      let boxEffect = UIGlassContainerEffect()
      boxEffect.spacing = 34
      boxView = UIVisualEffectView(effect: boxEffect)

      // 按下 = **只微微提亮**（×1.15）：提亮不是靠刷白 —— 刷白就成奶白色、就不透了。
      // "鼓起来"这件事交给大小与弹簧去表达（用户 2026-10-06 的反馈）。
      // 全透明（没给 tint）时按下不动颜色：那时"鼓起来"是唯一的语言。
      if let t = normalTint {
        let pressedTint = t.withAlphaComponent(min(1, t.cgColor.alpha * 1.15))
        pressLook = { down in pillEffect.tintColor = down ? pressedTint : t }
      } else {
        pressLook = { _ in }
      }
    } else {
      // iOS 26 以下：没有玻璃，退回一层毛玻璃（**这一支没在真机上验过**）
      baseView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
      pillView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
      dropView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
      boxView = UIVisualEffectView(effect: nil)
      pressLook = { [weak pillView] down in
        pillView?.backgroundColor = UIColor.white.withAlphaComponent(down ? 0.30 : 0.12)
      }
    }
    base = baseView
    pill = pillView
    drop = dropView
    glassBox = boxView
    applyPressLook = pressLook

    channel = FlutterMethodChannel(
      name: "lianleme/glass_segmented/\(viewId)", binaryMessenger: messenger)

    super.init()

    host.frame = frame
    // ⚠️ **两块玻璃各自独立、不进 `UIGlassContainerEffect`**（2026-10-06 实测改的）：
    // 容器会把"互相叠着的两块玻璃"合成一块 —— 选中胶囊的亮边与凸起**整块消失**
    // （底托 + 胶囊完全同高时更彻底：屏幕上什么都看不出来）。
    // 证据图 `docs/images/glass-probe-segment-variants.png` 的 D 行（容器）与 A/B 行（独立）对比。
    // 代价：切换时不再有"融合"的形变 —— 苹果自己的分段控件也是"独立的一块选中玻璃"。
    host.addSubview(base)
    // 两滴玻璃进容器；底托留在容器外面（理由见属性那一段注释）
    glassBox.contentView.addSubview(pill)
    glassBox.contentView.addSubview(drop)
    drop.isHidden = true
    host.addSubview(glassBox)
    host.onLayout = { [weak self] bounds in
      guard let self else { return }
      self.layout(false)   // 尺寸变化时不要动画，否则每次布局都在滑
    }
    // ── 原生文案：玻璃之上的那一层 ──
    let labelStrings = (args["labels"] as? [String]) ?? []
    iconNames = (args["icons"] as? [String]) ?? []
    selectedColor = (args["selectedColor"] as? String)
      .flatMap { GlassPlatformView.color($0) } ?? .white
    unselectedColor = (args["unselectedColor"] as? String)
      .flatMap { GlassPlatformView.color($0) } ?? .gray
    emphasisIndex = (args["emphasisIndex"] as? NSNumber)?.intValue ?? -1
    emphasisColor = (args["emphasisColor"] as? String)
      .flatMap { GlassPlatformView.color($0) }
    emphasisIconColor = (args["emphasisIconColor"] as? String)
    emphasisIconSize = CGFloat((args["emphasisIconSize"] as? NSNumber)?.doubleValue ?? 0)
      .flatMap { GlassPlatformView.color($0) }
    labelFontSize = CGFloat((args["labelFontSize"] as? NSNumber)?.doubleValue ?? 12)
    iconSize = CGFloat((args["iconSize"] as? NSNumber)?.doubleValue ?? 22)
    labelsBox.frame = frame
    labelsBox.backgroundColor = .clear
    labelsBox.isUserInteractionEnabled = false
    if !labelStrings.isEmpty || !iconNames.isEmpty {
      buildItems(labelStrings)
      // 正中那颗圆：**先插进 labelsBox**（所以它在图标/文字下面），
      // 而 labelsBox 整层在玻璃之上 —— 两件事缺一不可。
      //
      // ⚠️ 2026-10-09（10.9 清单第 2b 条）：Dart 那边**不再传 emphasisColor**，
      // 所以这一段现在不会执行 —— 中间那格改成"大一号 + 强调色"的线性图标
      // （`emphasisIconSize`）。这里保留这条分支的理由：圆是原生的能力，
      // 哪天想换回"实心圆 + 深墨图标"只需在 Dart 传回颜色，不用改原生。
      if emphasisIndex >= 0, emphasisIndex < count, emphasisColor != nil {
        // 直径与 Android 那颗对齐（`AppTabBar.centerCircleSize = 36` = iconSize + 14）——
        // 两端是同一颗圆，只有"谁来画"不同。2026-10-08 第二遍：底栏加高到 68，
        // 圆不再顶出上沿（用户原话："不要让中间突出去一截了"）；
        // ⚠️ 一开始给的是 iconSize + 18（40），而胶囊上沿离栏顶还有 5pt 内缩 ——
        // 40 那颗正好**贴着胶囊上沿**，看着像被切了一刀。36 给两端都留出呼吸。
        let d = iconSize + 14
        emphasisCircle.frame = CGRect(x: 0, y: 0, width: d, height: d)
        emphasisCircle.backgroundColor = emphasisColor
        emphasisCircle.layer.cornerRadius = d / 2
        emphasisCircle.isUserInteractionEnabled = false
        labelsBox.insertSubview(emphasisCircle, at: 0)
      }
      host.addSubview(labelsBox)   // 加在玻璃**之上**
    }

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "setIndex":
        let i = (call.arguments as? [String: Any]).flatMap { ($0["index"] as? NSNumber)?.intValue }
        self.setIndex(i ?? 0, animated: true)
        result(nil)
      // 按下/松开：Dart 那边（`GlassSegmented` 的 `Listener`）替我们盯着手指 ——
      // 平台视图在 Flutter 内容**下面**，手指落在上面那层标签上，UIKit 拿不到触摸，
      // 所以"交互玻璃"的手感只能由 Dart 通报、原生演（形变与染色都在下面这一层做）。
      case "press":
        let args = call.arguments as? [String: Any]
        let i = args.flatMap { ($0["index"] as? NSNumber)?.intValue }
        let x = args.flatMap { ($0["x"] as? NSNumber)?.doubleValue }
        self.setPressed(i, x.map { CGFloat($0) }, animated: true)
        result(nil)
      case "pressMove":
        let x = (call.arguments as? [String: Any])
          .flatMap { ($0["x"] as? NSNumber)?.doubleValue }
        self.movePress(x.map { CGFloat($0) })
        result(nil)
      case "release":
        self.setPressed(nil, nil, animated: true)
        result(nil)
      // 手指左右拖页面：胶囊**跟着手指连续滑**（不跳格）。拖动期间用 `layout(false)` ——
      // 动画由手指给，这里再补一层弹簧就是抖。
      case "setIndexFraction":
        let f = (call.arguments as? [String: Any])
          .flatMap { ($0["index"] as? NSNumber)?.doubleValue }
        self.dragFraction = f.map { CGFloat($0) }
        self.layout(false)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView { host }

  // ── 原生文案的三个小函数 ────────────────────────────────────────────────

  /// 每格一个视图：底栏是"图标 + 文字"竖排，分段控件只有一个字。
  private func buildItems(_ strings: [String]) {
    for i in 0..<count {
      let label = UILabel()
      label.text = i < strings.count ? strings[i] : nil
      label.textAlignment = .center
      label.numberOfLines = 1
      itemLabels.append(label)

      if !iconNames.isEmpty {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.image = symbol(iconNames[safe: i], selected: i == index, index: i)
        itemIcons.append(iv)
        let stack = UIStackView(arrangedSubviews: [iv, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        itemViews.append(stack)
      } else {
        itemViews.append(label)
      }
      labelsBox.addSubview(itemViews[i])
    }
    applyColors()
  }

  /// SF Symbol（选中时用粗一号 —— 苹果自己的底栏就是这么做的）。
  /// SF Symbol。`index` 传了而且正好是被点亮那一格 → 用 `emphasisIconSize`
  /// （比其余几格大一号；0 表示没设，就用普通大小）。
  private func symbol(_ name: String?, selected: Bool, index: Int = -1) -> UIImage? {
    guard let name else { return nil }
    let size = (index >= 0 && index == emphasisIndex && emphasisIconSize > 0)
      ? emphasisIconSize : iconSize
    let conf = UIImage.SymbolConfiguration(
      pointSize: size, weight: selected ? .semibold : .regular)
    return UIImage(systemName: name, withConfiguration: conf)
  }

  private func layoutItems(in bounds: CGRect) {
    guard !itemViews.isEmpty else { return }
    labelsBox.frame = bounds
    let w = bounds.width / CGFloat(count)
    for i in 0..<count {
      let cell = CGRect(x: w * CGFloat(i), y: 0, width: w, height: bounds.height)
      let v = itemViews[i]
      if let stack = v as? UIStackView {
        // ⚠️ **不许用 `sizeToFit()`**：对 UIStackView 它算出的是零尺寸（它不是普通视图，
        // 布局要问 Auto Layout）—— 症状是**整格什么都不显示**（底栏那 5 个图标+文字全没了，
        // 而单位行那种单个 UILabel 的反而正常）。这就是 2026-10-06 那次回归的根因。
        let fit = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        stack.bounds = CGRect(origin: .zero, size: fit)
        stack.center = CGPoint(x: cell.midX, y: cell.midY)

        // 正中那颗圆：**用几何算出来**，不要读 `itemIcons[i].center` ——
        // ⚠️ 第一次就是这么写的，结果圆被画到了图标**上方**、底部还被切掉一截：
        // UIStackView 里的子视图由 Auto Layout 落位，而这一行跑的时候它**还没布局完**，
        // 读到的 center 接近 (0,0)。换成"格子中心 − 半个 stack 高 + 半个图标高"就与
        // 图标中心严格重合（栈是竖直的：图标在上、文字在下，间距 4）。
        if i == emphasisIndex, emphasisCircle.superview != nil {
          emphasisCircle.center = CGPoint(
            x: cell.midX,
            y: cell.midY - fit.height / 2 + iconSize / 2)
        }
      } else {
        v.frame = cell
        if i == emphasisIndex, emphasisCircle.superview != nil {
          emphasisCircle.center = CGPoint(x: cell.midX, y: cell.midY)
        }
      }
    }
  }

  /// 选中项：字色 + 图标粗细都换一档（与胶囊滑到哪一格无关，只看"选中"）。
  private func applyColors() {
    for i in 0..<itemLabels.count {
      let on = i == index
      itemLabels[i].font = .systemFont(ofSize: labelFontSize,
                                       weight: on ? .semibold : .regular)
      itemLabels[i].textColor = on ? selectedColor : unselectedColor
      if i < itemIcons.count {
        itemIcons[i].image = symbol(iconNames[safe: i], selected: on, index: i)
        // ⚠️ SF Symbol 是**模板图**：不显式给 tintColor 它会用系统蓝（默认 tint），
        // 于是底栏图标是蓝的而字是橙的 —— 2026-10-06 实拍抓到。
        var tint = on ? selectedColor : unselectedColor
        // 正中那颗：深墨压在强调色圆上（与主按钮同一套），否则橙底橙图标看不清
        if i == emphasisIndex, let ink = emphasisIconColor { tint = ink }
        itemIcons[i].tintColor = tint
      }
    }
  }

  /// 一格的中心 x（水滴没收到手指坐标时用它兜底）。
  private func cellCenter(_ i: Int, in bounds: CGRect) -> CGFloat {
    let w = bounds.width / CGFloat(count)
    return w * (CGFloat(i) + 0.5)
  }

  /// 胶囊（原来那颗"选中的水滴"）该在哪。
  ///
  /// * 手指在拖页面（`dragFraction`）→ 用那个**小数**位置，于是它跟着手指滑；
  /// * 按住的是**当前这一格** → 往外鼓 `pressBulge`（Q 弹 + 超出边界）；
  /// * 按住的是**别的格** → 胶囊**不动**（在那一格冒出来的是第二颗水滴，两滴会融在一起）。
  private func pillFrame(in bounds: CGRect) -> CGRect {
    let w = bounds.width / CGFloat(count)
    let i: CGFloat = dragFraction ?? CGFloat(index)
    let bulging = pressedIndex == index && pressedIndex != nil
    let inset = bulging ? pillInset - pressBulge : pillInset
    return CGRect(x: w * i + inset,
                  y: inset,
                  width: w - inset * 2,
                  height: bounds.height - inset * 2)
  }

  /// **第二颗水滴**：按住别的那一格时，在手指下面冒出来的那一小块。
  ///
  /// 它和胶囊同高（于是是一颗圆滴），中心跟着手指走、并夹在底栏里面 ——
  /// 两滴的距离进了容器的 `spacing`，苹果就会在中间长出一道"脖子"，像两滴水融在一起。
  private func dropFrame(in bounds: CGRect) -> CGRect {
    let h = bounds.height - pillInset * 2
    let x = pressX ?? cellCenter(pressedIndex ?? index, in: bounds)
    let clamped = min(max(x - h / 2, 1), bounds.width - h - 1)
    return CGRect(x: clamped, y: pillInset, width: h, height: h)
  }

  private func layout(_ animated: Bool) {
    let bounds = host.bounds
    let pillTarget = pillFrame(in: bounds)
    let dropTarget = dropFrame(in: bounds)
    base.frame = bounds
    glassBox.frame = bounds

    if #available(iOS 26.0, *) {
      // 圆角一律走 `cornerConfiguration`（用 layer.cornerRadius 会少一道玻璃边缘高光）
      base.cornerConfiguration = .corners(radius: .fixed(radius))
      pill.cornerConfiguration = .capsule()
      drop.cornerConfiguration = .capsule()
    } else {
      base.layer.cornerRadius = radius
      base.layer.cornerCurve = .continuous
      base.clipsToBounds = true
      for v in [pill, drop] {
        v.layer.cornerRadius = pillTarget.height / 2
        v.layer.cornerCurve = .continuous
        v.clipsToBounds = true
      }
    }

    applyPressLook(pressedIndex != nil)
    layoutItems(in: bounds)
    applyColors()
    // 水滴要露面的**那一刻**不能有"从 0 蹦出来"的跳变：先摆好位置再显示
    if dropVisible && drop.isHidden {
      drop.frame = dropTarget
      drop.isHidden = false
    }
    if !dropVisible && !drop.isHidden {
      drop.isHidden = true
    }

    if animated {
      // 按下要"Q弹"（阻尼小 + 初速大 → 真的会过冲再收），松手也要有一点点回弹。
      let down = pressedIndex != nil
      UIView.animate(
        withDuration: down ? 0.42 : 0.5,
        delay: 0,
        usingSpringWithDamping: down ? 0.32 : 0.62,
        initialSpringVelocity: down ? 1.0 : 0.35,
        options: [.allowUserInteraction, .beginFromCurrentState]
      ) {
        self.pill.frame = pillTarget
        if self.dropVisible { self.drop.frame = dropTarget }
      }
    } else {
      pill.frame = pillTarget
      if dropVisible { drop.frame = dropTarget }
    }
  }

  private func setIndex(_ i: Int, animated: Bool) {
    index = min(max(0, i), count - 1)
    applyColors()        // 选中那一格的字/图标换色（底栏是橙色 + 粗一号）
    dragFraction = nil   // 拖完了：交回"整格"这条轨道
    // 手指刚抬、消息才到：这时**两滴一起滑到新那一格**，落到一起之后再收掉水滴 ——
    // 于是看起来就是"两滴融成了一滴"（而不是"一滴消失、另一滴跳过去"）。
    if dropVisible && releasedAt != nil {
      let bounds = host.bounds
      dropVisible = true
      let target = dropFrameForCell(index, in: bounds)
      UIView.animate(
        withDuration: 0.5, delay: 0,
        usingSpringWithDamping: 0.72, initialSpringVelocity: 0.3,
        options: [.allowUserInteraction, .beginFromCurrentState]
      ) {
        self.pill.frame = self.pillFrame(in: bounds)
        self.drop.frame = target
      } completion: { _ in
        self.drop.isHidden = true
        self.dropVisible = false
      }
      releasedAt = nil
      return
    }
    layout(animated)
  }

  /// 让水滴落到某一格的**中心**（收尾那一趟用）。
  private func dropFrameForCell(_ i: Int, in bounds: CGRect) -> CGRect {
    let h = bounds.height - pillInset * 2
    let w = bounds.width / CGFloat(count)
    let x = w * CGFloat(i) + (w - h) / 2
    return CGRect(x: x, y: pillInset, width: h, height: h)
  }

  /// `nil` = 松开（回到当前选中项）。
  private func setPressed(_ i: Int?, _ x: CGFloat?, animated: Bool) {
    pressedIndex = i.map { min(max(0, $0), count - 1) }
    pressX = x
    if pressedIndex == nil {
      // 松开：先别急着收水滴 —— "换到哪一格"的消息可能下一帧才到，
      // 到了就让它跟胶囊一起融过去（见 setIndex）。没人来就自己淡出（= 两滴分开）。
      releasedAt = Date()
      dropHideTimer?.invalidate()
      dropHideTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: false) { [weak self] _ in
        guard let self, self.releasedAt != nil else { return }
        self.releasedAt = nil
        self.dropVisible = false
        UIView.animate(withDuration: 0.18) { self.drop.alpha = 0 } completion: { _ in
          self.drop.isHidden = true
          self.drop.alpha = 1
        }
      }
    } else {
      releasedAt = nil
      dropHideTimer?.invalidate()
      dropHideTimer = nil
      drop.alpha = 1
      // 按住**当前这一格** → 不冒水滴，改成把胶囊鼓起来（Q 弹 + 超出边界）
      dropVisible = pressedIndex != index
    }
    layout(animated)
  }

  /// 手指在底栏上横向移动：水滴跟着手指走，按住的那一格也跟着换。
  private func movePress(_ x: CGFloat?) {
    guard pressedIndex != nil, let x else { return }
    pressX = x
    let w = host.bounds.width / CGFloat(count)
    guard w > 0 else { return }
    let i = min(max(0, Int(x / w)), count - 1)
    if i != pressedIndex {
      pressedIndex = i
      dropVisible = i != index
      releasedAt = nil
      dropHideTimer?.invalidate()
      drop.alpha = 1
    }
    layout(false)   // 跟手：动画由手指给
  }
}

/// 参数：`style`=regular|clear、`radius`=圆角、`tint`=`#RRGGBB(AA)`、`interactive`=是否可交互。
class GlassViewFactory: NSObject, FlutterPlatformViewFactory {
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
    GlassPlatformView(frame: frame, args: args as? [String: Any] ?? [:])
  }
}

class GlassPlatformView: NSObject, FlutterPlatformView {
  private let visual: UIVisualEffectView

  init(frame: CGRect, args: [String: Any]) {
    let radius = CGFloat((args["radius"] as? NSNumber)?.doubleValue ?? 0)
    let wantsClear = (args["style"] as? String) == "clear"
    let interactive = (args["interactive"] as? Bool) ?? false
    let tint = (args["tint"] as? String).flatMap(GlassPlatformView.color)

    if #available(iOS 26.0, *) {
      let effect = UIGlassEffect(style: wantsClear ? .clear : .regular)
      effect.isInteractive = interactive
      if let tint { effect.tintColor = tint }
      let view = UIVisualEffectView(effect: effect)
      // 圆角用 iOS 26 的新写法（`cornerConfiguration`），不是 layer.cornerRadius ——
      // 玻璃材质的圆角由它负责，用 layer 那套玻璃边缘会缺一道高光。
      view.cornerConfiguration = .corners(radius: .fixed(radius))
      self.visual = view
    } else {
      // iOS 26 以下：**退回**系统材质（不是液态玻璃）。这一支没在真机上验过。
      let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
      view.layer.cornerRadius = radius
      view.layer.cornerCurve = .continuous
      view.clipsToBounds = true
      self.visual = view
    }
    super.init()
    _ = frame
  }

  func view() -> UIView { visual }

  /// `#RRGGBB` / `#RRGGBBAA` → `UIColor`。写错了就当没给（不 crash、不猜）。
  static func color(_ hex: String) -> UIColor? {
    var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    if s.count == 6 { s += "FF" }
    guard s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
    return UIColor(
      red: CGFloat((v >> 24) & 0xFF) / 255,
      green: CGFloat((v >> 16) & 0xFF) / 255,
      blue: CGFloat((v >> 8) & 0xFF) / 255,
      alpha: CGFloat(v & 0xFF) / 255
    )
  }
}

// MARK: - 开关（iOS 26 的液态玻璃开关就是系统 UISwitch 本身）

class GlassSwitchViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger; super.init() }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64,
              arguments args: Any?) -> FlutterPlatformView {
    GlassSwitchView(frame: frame, viewId: viewId, messenger: messenger,
                    args: args as? [String: Any] ?? [:])
  }
}

class GlassSwitchView: NSObject, FlutterPlatformView {
  private let host = GlassHostView()
  private let toggle = UISwitch()
  private let channel: FlutterMethodChannel
  /// 正在被 Flutter 侧同步值：这时不要回发 `changed`，否则来回弹（经典回声）
  private var applyingFromDart = false

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger, args: [String: Any]) {
    channel = FlutterMethodChannel(
      name: "lianleme/switch/\(viewId)", binaryMessenger: messenger)
    super.init()

    toggle.isOn = (args["value"] as? Bool) ?? false
    if let hex = args["onColor"] as? String, let c = GlassPlatformView.color(hex) {
      toggle.onTintColor = c   // iOS 26 上系统会按玻璃自己调，给了也只是"尽量"
    }
    toggle.addTarget(self, action: #selector(valueChanged), for: .valueChanged)

    host.frame = frame
    host.backgroundColor = .clear
    host.addSubview(toggle)
    host.onLayout = { [weak self] bounds in
      guard let self else { return }
      self.toggle.sizeToFit()
      self.toggle.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "setValue":
        let v = (call.arguments as? [String: Any]).flatMap { $0["value"] as? Bool } ?? false
        if self.toggle.isOn != v {
          self.applyingFromDart = true
          self.toggle.setOn(v, animated: false)
          self.applyingFromDart = false
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView { host }

  @objc private func valueChanged() {
    guard !applyingFromDart else { return }
    channel.invokeMethod("changed", arguments: ["value": toggle.isOn])
  }
}
