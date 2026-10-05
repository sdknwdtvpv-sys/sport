package com.sdknwdtvpv.lianleme

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 训练提醒的通道（Android 侧）。
 *
 * 通道名与 `app/lib/features/profile/reminder_bridge.dart` 里的**必须一致**。
 * 与 iOS 那份（`ios/Runner/ReminderBridge.swift`）是同一组方法名与参数。
 */
class MainActivity : FlutterActivity() {
  private var pendingPermissionResult: MethodChannel.Result? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    ReminderScheduler.ensureChannel(this)

    // ── 训练中别让屏幕熄掉（v1.53）────────────────────────────────────────
    // 现场依据：手机架在器械上，每组之间看一眼 —— 屏幕早就黑了，于是每记一组
    // 都要先解锁一次。`FLAG_KEEP_SCREEN_ON` **不是权限**，也不常驻：
    // 训练屏进（awake=true）、离开（awake=false）各自一次，别的地方一律不亮。
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CHANNEL)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "awake" -> {
            val on = call.arguments as? Boolean ?: false
            runOnUiThread {
              if (on) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
              } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
              }
            }
            result.success(null)
          }
          else -> result.notImplemented()
        }
      }

    // ── 休息结束的体外提示（v1.53）────────────────────────────────────────
    // iOS 那边有 Live Activity（锁屏/灵动岛），Android 什么都没有 ——
    // 这条通知是"手机在包里也知道该下一组了"的唯一办法。见 RestCueNotifier 的注释。
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RestCueNotifier.CHANNEL_NAME)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "show" -> {
            val title = call.argument<String>("title") ?: "休息结束"
            val body = call.argument<String>("body") ?: ""
            RestCueNotifier.show(this, title, body)
            result.success(null)
          }
          "cancel" -> {
            RestCueNotifier.cancel(this)
            result.success(null)
          }
          else -> result.notImplemented()
        }
      }

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "isAllowed" -> result.success(hasNotificationPermission())
          "requestPermission" -> requestNotificationPermission(result)
          "schedule" -> {
            val atMs = (call.argument<Number>("atMs"))?.toLong()
            val title = call.argument<String>("title") ?: ""
            val body = call.argument<String>("body") ?: ""
            if (atMs == null) {
              result.error("bad_arguments", "schedule 需要一个 atMs", null)
            } else {
              ReminderScheduler.schedule(this, atMs, title, body)
              result.success(null)
            }
          }
          "cancel" -> {
            ReminderScheduler.cancel(this)
            result.success(null)
          }
          "scheduledAtMs" -> result.success(ReminderScheduler.scheduledAtMs(this))
          else -> result.notImplemented()
        }
      }
  }

  /** API 33 以下没有这个运行时权限：装了就等于允许。 */
  private fun hasNotificationPermission(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
    return ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
      PackageManager.PERMISSION_GRANTED
  }

  /**
   * 只在**用户主动打开提醒开关**时才会走到这里（不在启动时要）。
   *
   * 一次只允许有一个在飞的请求：系统对话框是模态的，重复请求没有意义，
   * 而且 `pendingPermissionResult` 是单值 —— 并发请求会互相覆盖，第二个永远收不到回调。
   */
  private fun requestNotificationPermission(result: MethodChannel.Result) {
    if (hasNotificationPermission()) {
      result.success(true)
      return
    }
    if (pendingPermissionResult != null) {
      result.success(false)
      return
    }
    pendingPermissionResult = result
    ActivityCompat.requestPermissions(
      this,
      arrayOf(Manifest.permission.POST_NOTIFICATIONS),
      REQUEST_CODE,
    )
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray,
  ) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    if (requestCode != REQUEST_CODE) return
    val granted = grantResults.isNotEmpty() &&
      grantResults[0] == PackageManager.PERMISSION_GRANTED
    pendingPermissionResult?.success(granted)
    pendingPermissionResult = null
  }

  companion object {
    private const val CHANNEL = "lianleme/reminder"
    private const val SCREEN_CHANNEL = "lianleme/screen"
    private const val REQUEST_CODE = 4703
  }
}
