package com.sdknwdtvpv.lianleme

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * 「休息结束」那条**体外提示**（Android 侧，v1.53）。
 *
 * 与训练提醒的区别（刻意分成两件事）：
 *  * 提醒是**排给未来的**（AlarmManager + 广播接收器，`ReminderScheduler`）；
 *  * 这条是**当下就发**的：Dart 那边的休息计时器到点，直接让这里发一条通知。
 *    所以它不排闹钟、不要任何新权限，也不写 SharedPreferences。
 *
 * 两条如实记下的边界：
 *   * **App 进程被杀掉时不会响** —— 到点响铃要做到那个程度得用精确闹钟
 *     （Android 12+ 的 `SCHEDULE_EXACT_ALARM` 是个特殊权限），
 *     为一条休息提示换一整个权限面不值得；
 *   * **用户没给通知权限时静默无事发生**（Android 13+）。这里刻意不弹权限框：
 *     权限只在用户主动打开「训练提醒」时请求过一次，训练中途弹框会打断训练。
 */
object RestCueNotifier {
  /** ⚠️ 必须与 `rest_cue.dart` 的通道名一致。 */
  const val CHANNEL_NAME = "lianleme/rest_cue"

  private const val NOTIFICATION_CHANNEL_ID = "lianleme_rest_cue"
  private const val NOTIFICATION_ID = 4704

  fun show(context: Context, title: String, body: String) {
    ensureChannel(context)
    val openApp = PendingIntent.getActivity(
      context,
      0,
      Intent(context, MainActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
      },
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
    val notification = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
      .setSmallIcon(R.mipmap.ic_launcher)
      .setContentTitle(title)
      .setContentText(body)
      .setPriority(NotificationCompat.PRIORITY_HIGH)
      .setCategory(NotificationCompat.CATEGORY_STOPWATCH)
      .setAutoCancel(true)
      .setContentIntent(openApp)
      .build()
    // 没授权时 notify 会静默丢弃（不抛）—— 那正是这里想要的行为
    NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
  }

  fun cancel(context: Context) {
    NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
  }

  /**
   * 通知渠道：重要性 HIGH（休息结束那一下**要能出声/震动** ——
   * 手机在包里、用户在数次数，DEFAULT 太容易被忽略）。
   * 与训练提醒分开两条渠道：用户可以只关掉其中一条。
   */
  private fun ensureChannel(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    if (manager.getNotificationChannel(NOTIFICATION_CHANNEL_ID) != null) return
    manager.createNotificationChannel(
      NotificationChannel(
        NOTIFICATION_CHANNEL_ID,
        "组间休息",
        NotificationManager.IMPORTANCE_HIGH,
      ).apply {
        description = "组间休息结束时提示一下（本地通知，不联网、不上传任何东西）"
      },
    )
  }
}
