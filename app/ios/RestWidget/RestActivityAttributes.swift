import ActivityKit
import Foundation

/// 组间休息的 Live Activity **数据模型**。
///
/// ⚠️ **这个文件同时属于两个 target**（宿主 App `Runner` 与扩展 `RestWidget`）：
/// ActivityKit 要求宿主与扩展**编译同一份 attributes 类型**，否则
/// `Activity.request` 会以"找不到那个类型"失败。它是刻意重复编译的，
/// 不是漏配 —— 改它的时候两边会一起变。
///
/// 最低系统：**iOS 16.2**（`ActivityContent` 是 16.2 才有的；16.1 只有旧的
/// `request(contentState:)`，用它就得吃一条 deprecated 警告 —— 项目选择不用弃用 API，
/// 而 16.1 只活了两个月，代价可以忽略）。
///
/// 为什么不把倒计时整场每秒写进 state：**锁屏上的倒计时由系统自己走**
/// （`Text(timerInterval:)`），我们只在"开始休息 / 结束休息"时各更新一次。
/// 这样既不费电，也不需要后台刷新 —— 组间那 60 秒里 App 可能已经被系统挂起。
@available(iOS 16.2, *)
public struct RestActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    /// 休息结束时刻。界面用 `Text(timerInterval:)` 渲染成走动的倒计时。
    public var endAt: Date
    /// 下一组练什么，如 "62.5 kg × 8"（自重动作是 "自重 × 8"）
    public var nextLabel: String
    /// 第几组（1 起）
    public var setIndex: Int
    /// 这个动作一共几组
    public var totalSets: Int

    public init(endAt: Date, nextLabel: String, setIndex: Int, totalSets: Int) {
      self.endAt = endAt
      self.nextLabel = nextLabel
      self.setIndex = setIndex
      self.totalSets = totalSets
    }
  }

  /// 动作名。整场休息里不变，所以放 attributes（放 state 会平白多一次更新）。
  public var exerciseName: String

  public init(exerciseName: String) {
    self.exerciseName = exerciseName
  }
}
