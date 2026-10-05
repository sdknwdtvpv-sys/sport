package com.sdknwdtvpv.lianleme

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build

/**
 * 训练提醒的**排程与取消**（Android 侧）。
 *
 * 设计取舍（写在代码里，免得下一个人以为是偷懒）：
 *  * 用 `setAndAllowWhileIdle`（**非精确**闹钟）而不是 `setExactAndAllowWhileIdle`：
 *    精确闹钟在 Android 12+ 要 `SCHEDULE_EXACT_ALARM`（一个**特殊权限**，商店还要额外说明），
 *    而"提醒你该练了"这件事差几分钟完全没有影响。用非精确闹钟换掉一整个权限面，划算。
 *  * 排程时刻由 **Dart 侧**算好（纯函数、有测试），这里只负责"到点响"。
 *    两个平台各自算一遍时间，迟早会出现"安卓 20:00、iOS 21:00"这种分歧。
 *  * 排程信息落在 SharedPreferences 里，只为了一件事：`scheduledAtMs()` 能被查询 ——
 *    端到端测试要断言"取消干净了"，而系统层面没有公开 API 反查自己的待发闹钟。
 */
object ReminderScheduler {
  const val CHANNEL_ID = "lianleme_training_reminder"
  const val EXTRA_TITLE = "title"
  const val EXTRA_BODY = "body"
  private const val PREFS = "lianleme_reminder"
  private const val KEY_AT = "scheduled_at_ms"
  private const val REQUEST_CODE = 4701

  private fun prefs(context: Context): SharedPreferences =
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  private fun pendingIntent(context: Context, title: String, body: String): PendingIntent {
    val intent = Intent(context, ReminderReceiver::class.java).apply {
      putExtra(EXTRA_TITLE, title)
      putExtra(EXTRA_BODY, body)
    }
    // FLAG_UPDATE_CURRENT：同一个 requestCode 的那条会被新的替换掉
    return PendingIntent.getBroadcast(
      context,
      REQUEST_CODE,
      intent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
  }

  fun schedule(context: Context, atMs: Long, title: String, body: String) {
    val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    val pi = pendingIntent(context, title, body)
    // 先撤掉旧的，再排新的 —— 同一时刻只该有一条提醒
    alarm.cancel(pi)
    alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
    prefs(context).edit().putLong(KEY_AT, atMs).apply()
  }

  fun cancel(context: Context) {
    val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    alarm.cancel(pendingIntent(context, "", ""))
    prefs(context).edit().remove(KEY_AT).apply()
  }

  fun scheduledAtMs(context: Context): Long? {
    val v = prefs(context).getLong(KEY_AT, -1L)
    return if (v > 0) v else null
  }

  /**
   * 通知渠道（API 26+ 必须有渠道，否则通知会被系统**静默丢弃**——不报错、就是不显示）。
   * 重要性用 DEFAULT：提醒要能发出声音/震动，但不需要像来电那样打断。
   */
  fun ensureChannel(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    if (manager.getNotificationChannel(CHANNEL_ID) != null) return
    manager.createNotificationChannel(
      NotificationChannel(
        CHANNEL_ID,
        "训练提醒",
        NotificationManager.IMPORTANCE_DEFAULT,
      ).apply {
        description = "到点了还没练时提醒一次（本地通知，不联网）"
      },
    )
  }
}
