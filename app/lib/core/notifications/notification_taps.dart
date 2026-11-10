import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 点了系统通知之后要做什么。
///
/// 计时提醒和好友消息两处都在用同一个通知插件（它是个单例，只记得最后一次初始化时给的回调），
/// 所以点击的处理统一放在这里：两边初始化时都交给 [NotificationTaps.handle]，
/// 真正的跳转由界面层（好友消息的总开关）在启动后挂到 [handler] 上。
class NotificationTaps {
  const NotificationTaps._();

  /// 好友消息通知的 payload 前缀，后面跟好友的用户 id
  static const chatPrefix = 'chat:';

  static String chatPayload(String friendId) => '$chatPrefix$friendId';

  /// 从 payload 里取出好友 id；不是聊天通知返回 null
  static String? chatFriendId(String? payload) {
    if (payload == null || !payload.startsWith(chatPrefix)) return null;
    final id = payload.substring(chatPrefix.length);
    return id.isEmpty ? null : id;
  }

  /// 界面层挂上来的处理函数，参数是通知的 payload
  static void Function(String payload)? handler;

  /// 点击发生时界面还没准备好（刚启动）：先记下，等 [handler] 挂上后补上
  static String? pending;

  static void handle(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    final h = handler;
    if (h == null) {
      pending = payload;
    } else {
      h(payload);
    }
  }

  /// 取走启动前记下的那一次点击
  static String? takePending() {
    final p = pending;
    pending = null;
    return p;
  }
}
