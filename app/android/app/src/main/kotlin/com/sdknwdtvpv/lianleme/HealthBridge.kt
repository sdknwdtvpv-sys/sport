package com.sdknwdtvpv.lianleme

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 从**系统健康库**读体成分（Android 侧 = Health Connect）。
 *
 * 通道名与 `app/lib/health/health_bridge.dart` 里的**必须一致**，
 * 方法与参数也与 iOS 那份（`ios/Runner/HealthBridge.swift`）一一对应：
 * `isAvailable` / `requestPermission` / `readBodyComposition`。
 *
 * 三条与 Android 有关、下次一定会重新查的事实：
 *
 *  * **只读**：申请的是 `android.permission.health.READ_WEIGHT` / `READ_BODY_FAT` /
 *    `READ_HEIGHT` 三个**读**权限，`WRITE_*` 一个都不申请、也没有任何写入代码 ——
 *    政策里承诺的是"只读、不写回"。
 *  * **权限名是 `READ_BODY_FAT`，不是 `READ_BODY_FAT_PERCENTAGE`**
 *    （2026-10-09 直接从 `android-36/android.jar` 的 `HealthPermissions` 里读出来的）。
 *    施工单 §三② 原来写的那一个名字在平台上**根本不存在**，照它写会永远拿不到授权。
 *  * **只有 Android 14+ 能读**（平台自带的 Health Connect）。13 及以下要装那个独立 App、
 *    还得抬 `minSdk` 到 26 才能用 Jetpack 库 —— 那是产品决定，见 `docs/plan-health-sync.md` §七。
 *    所以这里 `isAvailable` 返回 false 时，界面上的入口**根本不出现**（不给做不到的承诺）。
 */
object HealthBridge {

  const val CHANNEL_NAME = "lianleme/health"

  /** 与 Dart 侧 `readBodyComposition(days:)` 的兜底值一致。 */
  private const val DEFAULT_DAYS = 180

  /** 只读这三样。心率 / 睡眠 / 运动**一律不申请**。 */
  private val READ_PERMISSIONS = arrayOf(
    "android.permission.health.READ_WEIGHT",
    "android.permission.health.READ_BODY_FAT",
    "android.permission.health.READ_HEIGHT",
  )

  /** 与提醒那条通道的 `REQUEST_CODE`（4703）必须不同 —— 见 `MainActivity` 的分发。 */
  const val REQUEST_CODE = 4711

  private var pendingResult: MethodChannel.Result? = null

  /** 这台设备上到底能不能读：Android 14+ **并且**系统里真的有 Health Connect 模块。 */
  fun isAvailable(context: Context): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return false
    // ⚠️ 这一行是**唯一**会去加载 `HealthConnectApi34` 的地方（那个类整份都标着 @RequiresApi(34)）——
    // `&&` 的短路保证了老设备上它连类都不会被解析。
    return HealthConnectApi34.manager(context) != null
  }

  fun register(messenger: BinaryMessenger, activity: Activity) {
    MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
      handle(activity, call, result)
    }
  }

  private fun handle(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "isAvailable" -> result.success(isAvailable(activity))

      "requestPermission" -> requestPermission(activity, result)

      "readBodyComposition" -> {
        if (!isAvailable(activity)) {
          result.success(emptyList<Map<String, Any?>>())
          return
        }
        val days = (call.argument<Number>("days"))?.toInt() ?: DEFAULT_DAYS
        val main = Handler(Looper.getMainLooper())
        HealthConnectApi34.read(activity, days) { samples ->
          // ⚠️ 查询在别的线程上回来，而 Flutter 的 result 必须在主线程调
          main.post { result.success(samples) }
        }
      }

      else -> result.notImplemented()
    }
  }

  /**
   * 拉起授权。返回值 = "授权那一步走完了"，**不是**"拿到读权限了" ——
   * 与 iOS 那份同一个口径（那里 `requestAuthorization` 的 success 也是这个意思）。
   * 用户拒绝时这里是 `false`，Dart 侧会如实说"没读成"，而不是"健康库里没有数据"。
   */
  private fun requestPermission(activity: Activity, result: MethodChannel.Result) {
    if (!isAvailable(activity)) {
      result.success(false)
      return
    }
    if (allGranted(activity)) {
      result.success(true)
      return
    }
    // 系统对话框是模态的，一次只允许一个在飞（与提醒那条通道同一个理由）
    if (pendingResult != null) {
      result.success(false)
      return
    }
    pendingResult = result
    ActivityCompat.requestPermissions(activity, READ_PERMISSIONS, REQUEST_CODE)
  }

  private fun allGranted(context: Context): Boolean = READ_PERMISSIONS.all {
    ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
  }

  /**
   * `MainActivity.onRequestPermissionsResult` 会转到这里。
   *
   * 返回 true = 这次结果是我们这条通道的（调用方别再往下判别的 REQUEST_CODE）。
   */
  fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean {
    if (requestCode != REQUEST_CODE) return false
    val granted = grantResults.isNotEmpty() &&
      grantResults.all { it == PackageManager.PERMISSION_GRANTED }
    pendingResult?.success(granted)
    pendingResult = null
    return true
  }
}
