import SwiftUI
import WidgetKit

/// 这个扩展的入口。
///
/// 目前只有一个 widget：**组间休息的 Live Activity**。
/// 之所以从第一天就单独一个 target（而不是"以后再加"）：Live Activity 必须活在扩展里，
/// 而扩展一旦进包，`tool/check-ios-app.mjs` 就多了一条"扩展真的在包里、且声明了
/// Live Activity"的硬要求 —— 见 `docs/plan-scene-and-return.md`。
@main
struct RestWidgetBundle: WidgetBundle {
  var body: some Widget {
    RestActivityWidget()
  }
}
