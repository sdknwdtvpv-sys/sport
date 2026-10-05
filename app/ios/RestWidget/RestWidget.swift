import ActivityKit
import SwiftUI
import WidgetKit

/// 组间休息的 Live Activity：锁屏 + 灵动岛。
///
/// 它服务的是 `PRODUCT.md` §1 里唯一被点名要设计好的场景 —— **组间那 60 秒**。
/// 那个场景里用户**恰恰不看手机**（手机扣在器械上/在包里），所以"锁屏上就能看到
/// 还剩多久、下一组练什么"是这个功能存在的全部理由：让人不必点亮屏幕再找 App。
struct RestActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RestActivityAttributes.self) { context in
      // ── 锁屏（以及通知中心）─────────────────────────────────
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text("组间休息")
            .font(.caption2)
            .foregroundStyle(.secondary)
          // 系统自己走的倒计时：不需要我们每秒刷新（也就不需要后台权限）
          Text(timerInterval: Date.now...context.state.endAt, countsDown: true)
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .monospacedDigit()
        }
        Spacer(minLength: 8)
        VStack(alignment: .trailing, spacing: 2) {
          Text(context.attributes.exerciseName)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
          Text("下一组 \(context.state.nextLabel)")
            .font(.headline)
            .lineLimit(1)
          Text("第 \(context.state.setIndex)/\(context.state.totalSets) 组")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      .padding(14)
      .activityBackgroundTint(Color.black.opacity(0.6))
      .activitySystemActionForegroundColor(Color.green)
    } dynamicIsland: { context in
      DynamicIsland {
        // ── 长按展开 ────────────────────────────────────────
        DynamicIslandExpandedRegion(.leading) {
          Text(context.attributes.exerciseName)
            .font(.caption)
            .lineLimit(1)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text("第 \(context.state.setIndex)/\(context.state.totalSets) 组")
            .font(.caption)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(timerInterval: Date.now...context.state.endAt, countsDown: true)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .monospacedDigit()
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text("下一组 \(context.state.nextLabel)")
            .font(.caption)
        }
      } compactLeading: {
        // ── 灵动岛左侧：一个秒表图标（不塞数字，那里放不下）────────
        Image(systemName: "timer")
      } compactTrailing: {
        Text(timerInterval: Date.now...context.state.endAt, countsDown: true)
          .monospacedDigit()
          .frame(maxWidth: 44)
      } minimal: {
        Image(systemName: "timer")
      }
      .keylineTint(Color.green)
    }
  }
}
