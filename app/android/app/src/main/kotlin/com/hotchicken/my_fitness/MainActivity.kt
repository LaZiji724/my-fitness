package com.hotchicken.my_fitness

import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    // 组间休息 / 动作计时结束的铃声（应用在前台时由这里放；后台由带同一铃声的通知来响）。
    // 走「媒体」音频通道：音量跟媒体音量，手机调成静音 / 振动也能听到（媒体音量为 0 则没法响，这是系统限制）。
    // 放之前向系统申请「短暂、可压低」的音频焦点：正在放的音乐会被自动压低音量，
    // 提示音播完后释放焦点，原来的音乐恢复原音量，不会被打断。
    private var bellPlayer: MediaPlayer? = null
    private var focusRequest: AudioFocusRequest? = null
    private val focusListener = AudioManager.OnAudioFocusChangeListener { }

    // 比平时放媒体小一点点
    private val bellVolume = 0.75f

    private fun bellAttrs(): AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    private fun requestBellFocus(audio: AudioManager) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                    .setAudioAttributes(bellAttrs())
                    .setWillPauseWhenDucked(false)
                    .setOnAudioFocusChangeListener(focusListener)
                    .build()
                focusRequest = req
                audio.requestAudioFocus(req)
            } else {
                @Suppress("DEPRECATION")
                audio.requestAudioFocus(
                    focusListener,
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
                )
            }
        } catch (e: Exception) {
            // 焦点申请失败也照样放铃声，只是不压低别的声音
        }
    }

    private fun abandonBellFocus() {
        try {
            val audio = getSystemService(AUDIO_SERVICE) as AudioManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                focusRequest?.let { audio.abandonAudioFocusRequest(it) }
            } else {
                @Suppress("DEPRECATION")
                audio.abandonAudioFocus(focusListener)
            }
        } catch (e: Exception) {
        }
        focusRequest = null
    }

    private fun releaseBell() {
        bellPlayer?.release()
        bellPlayer = null
        abandonBellFocus()
    }

    private fun ringBell(): Boolean {
        return try {
            releaseBell()
            val audio = getSystemService(AUDIO_SERVICE) as AudioManager
            requestBellFocus(audio)
            val player = MediaPlayer.create(this, R.raw.rest_bell, bellAttrs(), audio.generateAudioSessionId())
            if (player == null) {
                abandonBellFocus()
                return false
            }
            player.setVolume(bellVolume, bellVolume)
            player.setOnCompletionListener {
                it.release()
                if (bellPlayer === it) {
                    bellPlayer = null
                    abandonBellFocus() // 释放焦点，被压低的音乐自动恢复
                }
            }
            bellPlayer = player
            player.start()
            true
        } catch (e: Exception) {
            abandonBellFocus()
            false
        }
    }

    override fun onDestroy() {
        releaseBell()
        super.onDestroy()
    }

    // 后台接收好友消息：启停前台服务、检查 / 申请「忽略电池优化」（不被省电策略掐网）
    private fun configureKeepAlive(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.hotchicken.my_fitness/keep_alive")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        try {
                            val intent = Intent(this, KeepAliveService::class.java)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "stop" -> {
                        try {
                            stopService(Intent(this, KeepAliveService::class.java))
                        } catch (e: Exception) {
                        }
                        result.success(true)
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        val pm = getSystemService(POWER_SERVICE) as PowerManager
                        result.success(
                            Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                                pm.isIgnoringBatteryOptimizations(packageName)
                        )
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName")
                                )
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                                result.success(true)
                            } catch (e2: Exception) {
                                result.success(false)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // 应用内更新：检查「安装未知应用」权限、跳到授权页、调起系统安装器覆盖安装
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        configureKeepAlive(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.hotchicken.my_fitness/bell")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ring" -> result.success(ringBell())
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.hotchicken.my_fitness/installer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> {
                        val ok = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls()
                        result.success(ok)
                    }
                    "openInstallSettings" -> {
                        try {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("settings", e.message, null)
                        }
                    }
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("args", "missing path", null)
                        } else {
                            try {
                                val uri = FileProvider.getUriForFile(
                                    this, "$packageName.updatefileprovider", File(path)
                                )
                                val intent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(uri, "application/vnd.android.package-archive")
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                startActivity(intent)
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("install", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
