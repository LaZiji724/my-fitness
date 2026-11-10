package com.hotchicken.my_fitness

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * 前台服务：让应用退到后台后进程仍然存活，好友消息才能继续收到并弹出系统通知。
 * 只显示一条最低优先级的静默通知，可在应用「我的」里关闭，也可以在系统通知设置里关掉这个频道。
 */
class KeepAliveService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "后台接收消息", NotificationManager.IMPORTANCE_MIN)
            channel.description = "保持应用在后台运行，好友发来消息时能及时提醒；可在「我的」里关闭"
            channel.setShowBadge(false)
            manager.createNotificationChannel(channel)
        }

        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pending = PendingIntent.getActivity(
            this, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val icon = resources.getIdentifier("ic_stat_chat", "drawable", packageName)
        builder
            .setContentTitle("我的健身")
            .setContentText("正在后台接收好友消息")
            .setSmallIcon(if (icon != 0) icon else applicationInfo.icon)
            .setContentIntent(pending)
            .setOngoing(true)
            .setShowWhen(false)
        val notification = builder.build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_STICKY
    }

    companion object {
        private const val CHANNEL_ID = "keep_alive"
        private const val NOTIFICATION_ID = 7001
    }
}
