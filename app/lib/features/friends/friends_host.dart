import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/app/router.dart';
import 'package:my_fitness/core/notifications/keep_alive.dart';
import 'package:my_fitness/core/notifications/notification_avatar.dart';
import 'package:my_fitness/core/notifications/notification_taps.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/friends/friend_models.dart';
import 'package:my_fitness/features/friends/friend_widgets.dart';
import 'package:my_fitness/features/friends/friends_providers.dart';

/// 退到后台时，用系统通知提醒新消息：标题是对方的名字，内容是消息，带上对方的圆形头像；
/// 点一下通知直接进入和他的聊天。抽成接口方便测试替换。
abstract class ChatNotifier {
  Future<void> show({
    required int id,
    required String friendId,
    required String title,
    required String body,
    String avatarKind = 'preset',
    String avatarRef = 'avatar_01',
  });
  Future<void> cancelAll();

  /// 应用是被点通知启动起来的话，返回对应的好友 id（否则 null）
  Future<String?> launchedFromChat();
}

class LocalChatNotifier implements ChatNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _init;

  /// 每个好友最近几条没处理的消息，用来拼成一条「会话式」通知
  final Map<int, List<Message>> _history = {};

  static const _channel = 'chat_message';

  Future<bool> _ensureInit() => _init ??= () async {
        try {
          await _plugin.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
            ),
            onDidReceiveNotificationResponse: NotificationTaps.handle,
          );
          return true;
        } catch (e) {
          debugPrint('消息通知初始化失败：$e');
          return false;
        }
      }();

  @override
  Future<void> show({
    required int id,
    required String friendId,
    required String title,
    required String body,
    String avatarKind = 'preset',
    String avatarRef = 'avatar_01',
  }) async {
    if (!await _ensureInit()) return;
    try {
      final png = await NotificationAvatar.circlePng(avatarKind, avatarRef);
      final payload = NotificationTaps.chatPayload(friendId);

      // 安卓：会话样式——头像、名字、消息内容，同一个人连着发多条会叠在同一条通知里
      final sender = Person(
        name: title,
        key: friendId,
        important: true,
        icon: png == null ? null : ByteArrayAndroidIcon(png),
      );
      final history = _history.putIfAbsent(id, () => []);
      history.add(Message(body, DateTime.now(), sender));
      if (history.length > 6) history.removeAt(0);

      final iosAvatar = png == null ? null : await NotificationAvatar.asFile(avatarKind, avatarRef, png);
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channel,
          '好友消息',
          channelDescription: '好友发来新消息时提醒',
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_chat',
          category: AndroidNotificationCategory.message,
          visibility: NotificationVisibility.private,
          largeIcon: png == null ? null : ByteArrayAndroidBitmap(png),
          styleInformation: MessagingStyleInformation(
            const Person(name: '我'),
            messages: List.of(history),
            groupConversation: false,
          ),
          autoCancel: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: false,
          presentBanner: false,
          presentList: false,
          presentSound: false,
          threadIdentifier: friendId,
          attachments: iosAvatar == null ? null : [DarwinNotificationAttachment(iosAvatar)],
        ),
      );
      await _plugin.show(id: id, title: title, body: body, notificationDetails: details, payload: payload);
    } catch (e) {
      debugPrint('消息通知失败：$e');
    }
  }

  @override
  Future<void> cancelAll() async {
    _history.clear();
    if (!await _ensureInit()) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  @override
  Future<String?> launchedFromChat() async {
    if (!await _ensureInit()) return null;
    try {
      final d = await _plugin.getNotificationAppLaunchDetails();
      if (d?.didNotificationLaunchApp != true) return null;
      return NotificationTaps.chatFriendId(d!.notificationResponse?.payload);
    } catch (_) {
      return null;
    }
  }
}

final chatNotifierProvider = Provider<ChatNotifier>((ref) => LocalChatNotifier());

/// 新消息提醒的总开关，包在整个应用外面：
/// 前台时顶部滑下来一张提示卡（点一下进入聊天）；退到后台时发系统通知。
/// 正在看那个人的聊天页时不打扰。
class FriendsHost extends ConsumerStatefulWidget {
  const FriendsHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<FriendsHost> createState() => _FriendsHostState();
}

class _FriendsHostState extends ConsumerState<FriendsHost> with WidgetsBindingObserver {
  StreamSubscription<ChatMessage>? _sub;
  Timer? _hide;
  _Toast? _toast;
  bool _background = false;
  bool _notificationAsked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationTaps.handler = _onNotificationTap;
  }

  /// 点了系统通知：是好友消息就直接进入和他的聊天
  void _onNotificationTap(String payload) {
    final friendId = NotificationTaps.chatFriendId(payload);
    if (friendId == null || !mounted) return;
    if (ref.read(currentUserIdProvider) == kLocalUserId) return;
    ref.read(routerProvider).push('/friends/chat/$friendId');
  }

  /// 登录后补上「点通知才把应用启动起来」的那一次点击
  Future<void> _openLaunchChat() async {
    final id = await ref.read(chatNotifierProvider).launchedFromChat() ?? NotificationTaps.chatFriendId(NotificationTaps.takePending());
    if (id == null || !mounted) return;
    ref.read(routerProvider).push('/friends/chat/$id');
  }

  @override
  void dispose() {
    if (NotificationTaps.handler == _onNotificationTap) NotificationTaps.handler = null;
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _hide?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bg = state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    if (bg == _background) return;
    _background = bg;
    if (!bg) {
      ref.read(chatNotifierProvider).cancelAll();
      ref.read(friendsControllerProvider.notifier).refresh();
    }
  }

  void _listen() {
    _sub?.cancel();
    _sub = ref.read(friendsControllerProvider.notifier).incomingMessages.listen(_onMessage);
  }

  void _onMessage(ChatMessage m) {
    if (!mounted) return;
    if (ref.read(activeChatProvider) == m.senderId) return;
    final entry = ref.read(friendsControllerProvider).byUser(m.senderId);
    if (entry == null) return;
    final preview = m.body.replaceAll('\n', ' ');
    if (_background) {
      ref.read(chatNotifierProvider).show(
            id: m.senderId.hashCode & 0x7fffffff,
            friendId: m.senderId,
            title: entry.user.displayName,
            body: preview,
            avatarKind: entry.user.avatarKind,
            avatarRef: entry.user.avatarRef,
          );
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _toast = _Toast(entry.user, preview));
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 4), _dismiss);
  }

  void _dismiss() {
    if (mounted && _toast != null) setState(() => _toast = null);
  }

  /// 安卓：登录着并且开着「后台接收消息」时，让前台服务保活；否则关掉
  bool? _keepingAlive;
  void _syncKeepAlive() {
    final keep = ref.read(keepAliveProvider);
    if (!keep.supported) return;
    final loggedIn = ref.read(currentUserIdProvider) != kLocalUserId;
    final enabled = ref.read(backgroundMessagesProvider).value ?? true;
    final want = loggedIn && enabled;
    if (_keepingAlive == want) return;
    _keepingAlive = want;
    if (want) {
      keep.start();
    } else {
      keep.stop();
    }
  }

  Future<void> _askNotificationOnce() async {
    if (_notificationAsked) return;
    _notificationAsked = true;
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      if (defaultTargetPlatform == TargetPlatform.android) {
        await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        await plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, sound: true);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUserIdProvider);
    ref.listen(backgroundMessagesProvider, (_, _) => _syncKeepAlive());
    if (uid == kLocalUserId) {
      _sub?.cancel();
      _sub = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncKeepAlive());
      return widget.child;
    }
    // 保持好友总管一直在后台运行；账号变了就重新接上
    ref.watch(friendsControllerProvider.select((s) => s.loaded));
    if (_sub == null) {
      _listen();
      // 登录后第一次，顺便问一下通知权限（之后系统不会再重复问）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _askNotificationOnce();
        _openLaunchChat();
        _syncKeepAlive();
      });
    }
    ref.listen(currentUserIdProvider, (prev, next) {
      if (prev != next) {
        _sub?.cancel();
        _sub = null;
        setState(() => _toast = null);
      }
    });

    final toast = _toast;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: IgnorePointer(
            ignoring: toast == null,
            child: SafeArea(
              bottom: false,
              child: AnimatedSwitcher(
                duration: AppMotion.emphasized,
                switchInCurve: AppMotion.curve,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => SlideTransition(
                  position: Tween(begin: const Offset(0, -1.2), end: Offset.zero).animate(anim),
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: toast == null
                    ? const SizedBox.shrink(key: ValueKey('none'))
                    : _ToastCard(
                        key: ValueKey(toast),
                        toast: toast,
                        onTap: () {
                          _dismiss();
                          ref.read(routerProvider).push('/friends/chat/${toast.user.id}');
                        },
                        onDismiss: _dismiss,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Toast {
  _Toast(this.user, this.body);
  final UserCard user;
  final String body;
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({super.key, required this.toast, required this.onTap, required this.onDismiss});

  final _Toast toast;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.s12, AppSpace.s8, AppSpace.s12, 0),
      child: Dismissible(
        key: ValueKey(toast),
        direction: DismissDirection.up,
        onDismissed: (_) => onDismiss(),
        child: PressScale(
          scale: PressScale.cardScale,
          child: Material(
            color: c.hero,
            elevation: 8,
            shadowColor: const Color(0x66000000),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              side: BorderSide(color: c.onHero.withValues(alpha: 0.08), width: AppStroke.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.s12),
                child: Row(
                  children: [
                    UserAvatar(toast.user, size: 40),
                    const SizedBox(width: AppSpace.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(toast.user.displayName,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label.copyWith(color: c.onHero, fontWeight: FontWeight.w700)),
                          Text(toast.body, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label.copyWith(color: c.onHero2)),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpace.s8),
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
