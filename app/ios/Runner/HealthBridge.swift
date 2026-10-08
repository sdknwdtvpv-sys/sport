import Flutter
import HealthKit
import UIKit

/// 从**系统健康库**读体成分（iOS 侧 = HealthKit）。
///
/// 与 Android 那份（`android/.../HealthBridge.kt`）是同一组方法名与参数，
/// 也与 `app/lib/health/health_bridge.dart` 一一对应。
///
/// 五件与 HealthKit 有关、下次一定会重新查的事实，写在这里：
///
///  * **只读，不写**：`requestAuthorization(toShare: [], read: ...)` —— toShare 传空数组，
///    我们连"写"的授权都不申请（`NSHealthUpdateUsageDescription` 也**故意不写**）。
///    政策里承诺的就是"只读"，代码这一层要对得上。
///  * **读权限查不出来**：Apple 有意不给"读"的授权状态查询（`authorizationStatus`
///    只对"写"有意义，且读权限为了不泄露用户是否在用某个 App，一律返回 notDetermined）。
///    所以通道里没有 `hasPermission` —— 只有"请求一次"和"读到什么就是什么"。
///  * `requestAuthorization` 的回调 `success` 的含义是**"这次请求处理完了"**，
///    **不是"用户同意了"**。用户拒绝时我们照样拿到 success，然后是空结果。
///  * **体脂率要乘 100**：`HKUnit.percent()` 返回的是 0–1 的比例（0.18 = 18%），
///    而库里（与界面上）存的是百分数。这个转换错了会得到"0.18% 的体脂"。
///  * **模拟器上通常没有健康数据**（`isHealthDataAvailable()` 为真，但库里是空的），
///    所以这条只能在真机上验收 —— 判据写在 `docs/plan-health-sync.md` §四。
enum HealthBridge {
  /// ⚠️ 必须与 `health_bridge.dart` 里的通道名一致。
  static let channelName = "lianleme/health"

  /// 往里看多少天由 Dart 侧传进来（默认 180）—— 这里是兜底值，两侧口径要一致。
  private static let defaultDays = 180

  /// 只读这三样。心率 / 睡眠 / 运动**一律不申请**（`docs/plan-health-sync.md` §二那张表）。
  private static var readTypes: Set<HKObjectType> {
    var types = Set<HKObjectType>()
    if let mass = HKQuantityType.quantityType(forIdentifier: .bodyMass) { types.insert(mass) }
    if let fat = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) { types.insert(fat) }
    if let height = HKQuantityType.quantityType(forIdentifier: .height) { types.insert(height) }
    return types
  }

  private static let store = HKHealthStore()

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isAvailable":
        result(HKHealthStore.isHealthDataAvailable())

      case "requestPermission":
        // 没有健康库时不要去请求（在 iPad 上会直接失败）
        guard HKHealthStore.isHealthDataAvailable() else {
          result(false)
          return
        }
        store.requestAuthorization(toShare: [], read: readTypes) { success, error in
          if let error = error {
            // 不把错误抛给界面：Dart 侧统一按"授权那一步没走完"处理，
            // 界面上的说法是"没读成"，而不是一条英文的 HealthKit 报错。
            NSLog("HealthKit requestAuthorization 失败：\(error.localizedDescription)")
          }
          DispatchQueue.main.async { result(success) }
        }

      case "readBodyComposition":
        let args = call.arguments as? [String: Any]
        let days = (args?["days"] as? NSNumber)?.intValue ?? defaultDays
        read(days: days, result: result)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 读最近 `days` 天的体重 / 体脂率 / 身高，**每一条测量各自一条样本**。
  ///
  /// 分组（"同一天取最新"）不在这里做 —— 那是 `health_sync.dart` 的活，
  /// 这一层只负责"把系统里的数按原样交出去"。
  private static func read(days: Int, result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else {
      result([Any]())
      return
    }
    let end = Date()
    let start = Calendar.current.date(byAdding: .day, value: -max(days, 1), to: end) ?? end
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

    let group = DispatchGroup()
    var samples: [[String: Any]] = []
    let lock = NSLock()
    var failure: Error?

    func append(_ rows: [[String: Any]]) {
      lock.lock()
      samples.append(contentsOf: rows)
      lock.unlock()
    }

    func quantityType(_ id: HKQuantityTypeIdentifier) -> HKQuantityType? {
      HKQuantityType.quantityType(forIdentifier: id)
    }

    /// 一个类型一次查询：按结束时间倒序取回来，逐条换算成我们那三种单位。
    func query(
      _ id: HKQuantityTypeIdentifier,
      unit: HKUnit,
      scale: Double,
      key: String
    ) {
      guard let type = quantityType(id) else { return }
      group.enter()
      let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
      let q = HKSampleQuery(
        sampleType: type, predicate: predicate,
        limit: HKObjectQueryNoLimit, sortDescriptors: sort
      ) { _, results, error in
        defer { group.leave() }
        if let error = error {
          lock.lock(); failure = error; lock.unlock()
          return
        }
        guard let quantities = results as? [HKQuantitySample] else { return }
        append(quantities.map { sample in
          [
            "atMs": Int(sample.endDate.timeIntervalSince1970 * 1000),
            key: sample.quantity.doubleValue(for: unit) * scale,
          ]
        })
      }
      store.execute(q)
    }

    query(.bodyMass, unit: HKUnit.gramUnit(with: .kilo), scale: 1, key: "weightKg")
    // ⚠️ percent() 是 0–1 的比例 → ×100 才是百分数（见文件头那条）
    query(.bodyFatPercentage, unit: HKUnit.percent(), scale: 100, key: "bodyFatPct")
    query(.height, unit: HKUnit.meterUnit(with: .centi), scale: 1, key: "heightCm")

    group.notify(queue: DispatchQueue.main) {
      if let error = failure, samples.isEmpty {
        // 读失败与"健康库里没有数据"是两件事，但都只能给出"没有"——
        // 这里至少把原因留在系统日志里，别让它静默消失。
        NSLog("HealthKit 查询失败：\(error.localizedDescription)")
      }
      result(samples)
    }
  }
}
