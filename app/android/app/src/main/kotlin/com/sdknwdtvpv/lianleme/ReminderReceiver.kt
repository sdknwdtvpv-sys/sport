package com.sdknwdtvpv.lianleme

import android.Manifest
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * 到点了：发一条**本地通知**。
 *
 * 内容由 Dart 侧在排程时就写好并存在 Intent 里 —— 这个 receiver 不做任何判断，
 * 也就不需要在响的时候唤醒 App 或读数据库（那会让"提醒"依赖 App 进程活着）。
 */
class ReminderReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    // Android 13+ 没给通知权限时，发出去也只会被系统丢掉 —— 那就别发
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
      ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
      PackageManager.PERMISSION_GRANTED
    ) {
      return
    }

    ReminderScheduler.ensureChannel(context)
    val title = intent.getStringExtra(ReminderScheduler.EXTRA_TITLE) ?: "今天还没练"
    val body = intent.getStringExtra(ReminderScheduler.EXTRA_BODY) ?: ""

    // 点通知就打开 App（不是开一个新的 Activity 实例：launchMode 是 singleTop）
    val open = Intent(context, MainActivity::class.java).apply {
      flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
    }
    val tapIntent = PendingIntent.getActivity(
      context,
      0,
      open,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    val notification = NotificationCompat.Builder(context, ReminderScheduler.CHANNEL_ID)
      .setSmallIcon(R.mipmap.ic_launcher)
      .setContentTitle(title)
      .setContentText(body)
      .setStyle(NotificationCompat.BigTextStyle().bigText(body))
      // ⚠️ **必须在锁屏上看得见**（2026-10-04 真机验出来的）：
      // `NotificationCompat` 默认是 `VISIBILITY_PRIVATE`，安全锁屏下**整条都不显示** ——
      // 真机上就是"锁屏只有系统那条，我们那条不见了"。而"提醒"的全部价值就是
      // 用户没打开 App 时也能看见，所以显式声明 PUBLIC。
      //
      // 内容里没有任何个人信息（"今天还没练"+"打开就是今天的安排"），
      // 被人瞥一眼也不泄露什么 —— 这也是敢用 PUBLIC 的前提。
      .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
      .setAutoCancel(true)
      .setContentIntent(tapIntent)
      .build()

    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    manager.notify(NOTIFICATION_ID, notification)
  }

  companion object {
    /** 固定 id：提醒是"当前状态"而不是"一条条消息"，同时只该存在一条 */
    const val NOTIFICATION_ID = 4702
  }
}
