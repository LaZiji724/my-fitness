import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:my_fitness/core/notifications/notification_taps.dart';

/// 本地定时提醒：应用退到后台或熄屏后，系统会在指定时刻弹出通知。
/// 抽成接口是为了测试里可以换成假的，不去碰系统插件。
abstract class ReminderScheduler {
  /// 申请通知权限（Android 13+ 与 iOS 会弹系统对话框）。返回是否已允许。
  Future<bool> requestPermission();

  /// 在 [at] 时刻弹出通知；同一个 [id] 重复调用会覆盖上一次。
  /// [bell] 为 true 时用休息结束的铃声（安卓走闹钟音量，静音模式下也会响）。
  /// 成功返回 null，失败返回原因。
  Future<String?> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    bool bell = false,
  });

  /// 取消某一个还没触发的提醒。
  Future<void> cancel(int id);

  /// 取消所有还没触发的提醒，并清掉通知栏里已显示的。
  Future<void> cancelAll();
}

/// 提醒编号：动作计时与组间休息各占一个。
const int kSetTimerReminderId = 1001;
const int kRestReminderId = 1002;

/// 基于 flutter_local_notifications 的实现。
/// 所有调用都吞掉异常：提醒是锦上添花，失败不能影响训练记录。
class LocalNotificationScheduler implements ReminderScheduler {
  LocalNotificationScheduler([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<bool>? _init;

  static const _channelId = 'timer_done';
  static const _channelName = '计时提醒';
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: '动作计时和组间休息结束时提醒',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      autoCancel: true,
    ),
    // 应用在前台时 iOS 不显示横幅/通知列表（界面里自己有读秒和震动）；
    // 退到后台或熄屏时系统照常弹出。这几个选项只管「前台时怎么展示」。
    iOS: DarwinNotificationDetails(
      presentAlert: false,
      presentBanner: false,
      presentList: false,
      presentSound: true,
      presentBadge: false,
    ),
  );

  /// 休息结束：单独一个通知渠道，带铃声。
  /// 安卓的渠道一旦建好，声音就改不了了，所以铃声用新的渠道 id，不去改原来的 timer_done。
  /// 声音走「闹钟」用途：手机调成静音 / 振动时也会响（和闹钟一样，跟闹钟音量走）。
  static const _bellChannelId = 'rest_bell';
  static const _bellDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _bellChannelId,
      '休息结束铃声',
      channelDescription: '组间休息结束时响铃提醒',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('rest_bell'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      autoCancel: true,
    ),
    // iOS 在前台也会放这个铃声（presentSound），所以应用开着的时候休息结束也会响
    iOS: DarwinNotificationDetails(
      presentAlert: false,
      presentBanner: false,
      presentList: false,
      presentSound: true,
      presentBadge: false,
      sound: 'rest_bell.wav',
    ),
  );

  Future<bool> _ensureInit() => _init ??= () async {
        try {
          await _plugin.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              // 权限在需要时再申请，不在启动时弹窗
              iOS: DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
              ),
            ),
            onDidReceiveNotificationResponse: NotificationTaps.handle,
          );
          return true;
        } catch (e) {
          debugPrint('通知初始化失败：$e');
          return false;
        }
      }();

  @override
  Future<bool> requestPermission() async {
    if (!await _ensureInit()) return false;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final android = _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
          final granted = await android?.requestNotificationsPermission();
          return granted ?? false;
        case TargetPlatform.iOS:
          final ios = _plugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
          final granted = await ios?.requestPermissions(alert: true, sound: true);
          return granted ?? false;
        default:
          return false;
      }
    } catch (e) {
      debugPrint('申请通知权限失败：$e');
      return false;
    }
  }

  @override
  Future<String?> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    bool bell = false,
  }) async {
    if (!await _ensureInit()) return '通知组件初始化失败';
    try {
      var mode = AndroidScheduleMode.inexactAllowWhileIdle;
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        // 精确闹钟：熄屏、Doze 下也能准点；没有权限时退而求其次用不精确模式
        if (await android?.canScheduleExactNotifications() ?? false) {
          mode = AndroidScheduleMode.exactAllowWhileIdle;
        }
      }
      await _plugin.zonedSchedule(
        id: id,
        // 只表示一个绝对时刻，用 UTC 即可，不依赖手机时区数据库
        scheduledDate: tz.TZDateTime.from(at, tz.UTC),
        notificationDetails: bell ? _bellDetails : _details,
        androidScheduleMode: mode,
        title: title,
        body: body,
      );
      return null;
    } catch (e) {
      debugPrint('安排提醒失败：$e');
      return '$e';
    }
  }

  @override
  Future<void> cancel(int id) async {
    if (!await _ensureInit()) return;
    try {
      await _plugin.cancel(id: id);
    } catch (e) {
      debugPrint('取消提醒失败：$e');
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!await _ensureInit()) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('取消提醒失败：$e');
    }
  }
}

final reminderSchedulerProvider =
    Provider<ReminderScheduler>((ref) => LocalNotificationScheduler());

/// 通知权限状态：null=还没问过，true=已允许，false=被拒绝。
class ReminderPermissionNotifier extends Notifier<bool?> {
  @override
  bool? build() => null;
  void set(bool? v) => state = v;
}

final reminderPermissionProvider =
    NotifierProvider<ReminderPermissionNotifier, bool?>(ReminderPermissionNotifier.new);
