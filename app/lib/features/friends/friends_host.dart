import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/app/router.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/friends/friend_models.dart';
import 'package:my_fitness/features/friends/friend_widgets.dart';
import 'package:my_fitness/features/friends/friends_providers.dart';

/// 退到后台时，用系统通知提醒新消息。抽成接口方便测试替换。
abstract class ChatNotifier {
  Future<void> show({required int id, required String title, required String body});
  Future<void> cancelAll();
}

class LocalChatNotifier implements ChatNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _init;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'chat_message',
      '好友消息',
      channelDescription: '好友发来新消息时提醒',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
    ),
    iOS: DarwinNotificationDetails(presentAlert: false, presentBanner: false, presentList: false, presentSound: false),
  );

  Future<bool> _ensureInit() => _init ??= () async {
        try {
          await _plugin.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
            ),
          );
          return true;
        } catch (e) {
          debugPrint('消息通知初始化失败：$e');
          return false;
        }
      }();

  @override
  Future<void> show({required int id, required String title, required String body}) async {
    if (!await _ensureInit()) return;
    try {
      await _plugin.show(id: id, title: title, body: body, notificationDetails: _details);
    } catch (e) {
      debugPrint('消息通知失败：$e');
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!await _ensureInit()) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
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
  }

  @override
  void dispose() {
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
      ref.read(chatNotifierProvider).show(id: m.senderId.hashCode & 0x7fffffff, title: entry.user.displayName, body: preview);
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
    if (uid == kLocalUserId) {
      _sub?.cancel();
      _sub = null;
      return widget.child;
    }
    // 保持好友总管一直在后台运行；账号变了就重新接上
    ref.watch(friendsControllerProvider.select((s) => s.loaded));
    if (_sub == null) {
      _listen();
      // 登录后第一次，顺便问一下通知权限（之后系统不会再重复问）
      WidgetsBinding.instance.addPostFrameCallback((_) => _askNotificationOnce());
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
