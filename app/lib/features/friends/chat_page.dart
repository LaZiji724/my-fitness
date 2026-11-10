import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/app_ui.dart';
import 'package:my_fitness/core/widgets/avatar_view.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/auth/avatars.dart';
import 'package:my_fitness/features/friends/emoji_panel.dart';
import 'package:my_fitness/features/friends/friend_models.dart';
import 'package:my_fitness/features/friends/friend_widgets.dart';
import 'package:my_fitness/features/friends/friends_providers.dart';

/// 和一个好友的聊天。输入栏参照微信：中间输入框，右侧表情，有字时右侧换成「发送」。
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, required this.friendId, this.cameFrom});
  final String friendId;

  /// 是从哪一页来的（从好友列表或通知进来为 null）
  final FriendPage? cameFrom;

  void _toActivity(BuildContext context) =>
      switchFriendPage(context, friendId, from: FriendPage.chat, cameFrom: cameFrom);

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _emoji = false;
  bool _hasText = false;
  int _lastCount = 0;
  late final ActiveChatNotifier _active;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _active = ref.read(activeChatProvider.notifier);
    Future.microtask(() => _active.set(widget.friendId));
    _text.addListener(() {
      final has = _text.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    _focus.addListener(() {
      if (_focus.hasFocus && _emoji) setState(() => _emoji = false);
    });
    _scroll.addListener(() {
      // reverse 列表：滚到顶端（最旧）时往前翻页
      if (_scroll.hasClients && _scroll.position.pixels > _scroll.position.maxScrollExtent - 200) {
        ref.read(chatControllerProvider(widget.friendId).notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Future.microtask(() => _active.set(null));
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(chatControllerProvider(widget.friendId).notifier).reload();
    }
  }

  void _toggleEmoji() {
    if (_emoji) {
      setState(() => _emoji = false);
      _focus.requestFocus();
    } else {
      _focus.unfocus();
      setState(() => _emoji = true);
    }
  }

  void _send() {
    final text = _text.text;
    if (text.trim().isEmpty) return;
    HapticFeedback.selectionClick();
    _text.clear();
    ref.read(chatControllerProvider(widget.friendId).notifier).send(text);
    _toBottom();
  }

  void _toBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0, duration: AppMotion.standard, curve: AppMotion.curve);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final friends = ref.watch(friendsControllerProvider);
    final entry = friends.byUser(widget.friendId);
    final chat = ref.watch(chatControllerProvider(widget.friendId));
    final isFriend = entry?.relation == FriendRelation.friend;
    final loadedList = friends.loaded;

    // 有新消息时，如果本来就在底部附近就跟着滚下去
    if (chat.messages.length != _lastCount) {
      final grew = chat.messages.length > _lastCount;
      _lastCount = chat.messages.length;
      if (grew && _scroll.hasClients && _scroll.position.pixels < 160) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
      }
    }
    ref.listen(chatControllerProvider(widget.friendId), (prev, next) {
      final err = next.error;
      if (err != null && err != prev?.error) {
        showFriendToast(context, err);
        ref.read(chatControllerProvider(widget.friendId).notifier).clearError();
      }
    });

    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      canPop: !_emoji,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _emoji) setState(() => _emoji = false);
      },
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          titleSpacing: 0,
          title: GestureDetector(
            onTap: entry == null ? null : () => widget._toActivity(context),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                if (entry != null) ...[UserAvatar(entry.user, size: 32), const SizedBox(width: AppSpace.s8)],
                Flexible(
                  child: Text(entry?.user.displayName ?? '聊天',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.titleSmall.copyWith(color: c.text)),
                ),
              ],
            ),
          ),
          actions: [
            if (entry != null)
              Padding(
                padding: const EdgeInsets.only(right: AppSpace.s12),
                child: RoundIconButton(
                  icon: AppIcons.barbell,
                  tooltip: '查看最近运动',
                  onPressed: () => widget._toActivity(context),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(child: _MessageList(state: chat, friendId: widget.friendId, friend: entry?.user, me: ref.watch(profileSummaryProvider), controller: _scroll, onRetry: (m) {
              ref.read(chatControllerProvider(widget.friendId).notifier).retry(m);
            }, onReload: () => ref.read(chatControllerProvider(widget.friendId).notifier).reload())),
            if (loadedList && !isFriend)
              _Notice(text: '你们已经不是好友了，不能再发消息')
            else
              _InputBar(
                controller: _text,
                focusNode: _focus,
                hasText: _hasText,
                emojiOpen: _emoji,
                onToggleEmoji: _toggleEmoji,
                onSend: _send,
              ),
            if (_emoji && !keyboard) EmojiPanel(controller: _text),
            if (!_emoji && !keyboard) const SafeArea(top: false, child: SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpace.s16),
        decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line, width: 1))),
        child: Text(text, textAlign: TextAlign.center, style: AppText.label.copyWith(color: c.text3)),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.hasText,
    required this.emojiOpen,
    required this.onToggleEmoji,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasText;
  final bool emojiOpen;
  final VoidCallback onToggleEmoji;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line, width: 1))),
      child: SafeArea(
        top: false,
        bottom: keyboard || emojiOpen ? false : false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.s12, AppSpace.s8, AppSpace.s8, AppSpace.s8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  decoration: BoxDecoration(color: c.sunken, borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 2000,
                    textInputAction: TextInputAction.newline,
                    keyboardType: TextInputType.multiline,
                    style: AppText.body.copyWith(color: c.text),
                    decoration: InputDecoration(
                      hintText: '发消息',
                      counterText: '',
                      filled: false,
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: 11),
                      hintStyle: AppText.body.copyWith(color: c.text3),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.s4),
              PressScale(
                scale: PressScale.smallScale,
                child: Tooltip(
                  message: emojiOpen ? '键盘' : '表情',
                  child: InkResponse(
                    onTap: onToggleEmoji,
                    radius: 24,
                    child: SizedBox.square(
                      dimension: 44,
                      child: Icon(emojiOpen ? AppIcons.keyboard : AppIcons.emoji, size: 28, color: c.text),
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: AppMotion.fast,
                curve: AppMotion.curve,
                alignment: Alignment.centerRight,
                child: hasText
                    ? Padding(
                        padding: const EdgeInsets.only(left: AppSpace.s4),
                        child: PressScale(
                          scale: PressScale.chipScale,
                          child: FilledButton(
                            onPressed: onSend,
                            style: const ButtonStyle(
                              minimumSize: WidgetStatePropertyAll(Size(60, 44)),
                              padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: AppSpace.s16)),
                            ),
                            child: const Text('发送'),
                          ),
                        ),
                      )
                    : const SizedBox(height: 44),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 把消息拼成带时间分隔的列表。列表是倒着排的（最新的在底部，输入时贴着输入栏）。
class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.state,
    required this.friendId,
    required this.friend,
    required this.me,
    required this.controller,
    required this.onRetry,
    required this.onReload,
  });

  final ChatState state;
  final String friendId;

  /// 对方 / 我自己：头像用
  final UserCard? friend;
  final ProfileSummary? me;
  final ScrollController controller;
  final void Function(ChatMessage) onRetry;
  final VoidCallback onReload;

  /// 相隔超过这么久的两条消息之间插一条时间
  static const _gap = Duration(minutes: 5);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final messages = state.messages;
    if (state.loading && messages.isEmpty) {
      return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (messages.isEmpty) {
      return EmptyState(
        icon: AppIcons.chat,
        title: state.error == null ? '打个招呼吧' : '聊天记录没加载出来',
        hint: state.error ?? '聊天记录保留 90 天',
        action: state.error == null ? null : SmallNeutralButton(label: '再试一次', onPressed: onReload),
      );
    }
    final now = DateTime.now();
    final reversed = messages.reversed.toList();
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: ListView.builder(
        controller: controller,
        reverse: true,
        padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s12, AppSpace.pageGutter, AppSpace.s12),
        itemCount: reversed.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == reversed.length) {
            return const Padding(
              padding: EdgeInsets.all(AppSpace.s16),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            );
          }
          final m = reversed[i];
          final older = i + 1 < reversed.length ? reversed[i + 1] : null;
          final showTime = older == null || m.createdAt.difference(older.createdAt) > _gap;
          final mine = m.senderId != friendId;
          // 连着发的几条，只在最上面（最早）的一条旁边显示头像；
          // 对方发了一条之后我再发（或反过来），或者中间隔了一段时间，就在新一组的第一条上重新显示。
          final groupStart = older == null || showTime || older.senderId != m.senderId;
          final avatar = mine
              ? AvatarView(kind: me?.avatarKind ?? 'preset', avatarRef: me?.avatarRef ?? kDefaultAvatarRef, size: _Bubble.avatarSize)
              : AvatarView(kind: friend?.avatarKind ?? 'preset', avatarRef: friend?.avatarRef ?? kDefaultAvatarRef, size: _Bubble.avatarSize);
          return Column(
            children: [
              if (showTime)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.s12),
                  child: Text(chatTimeLabel(m.createdAt, now), style: AppText.caption.copyWith(color: c.text3)),
                ),
              _Bubble(message: m, mine: mine, avatar: groupStart ? avatar : null, groupStart: groupStart && older != null && !showTime, onRetry: () => onRetry(m)),
            ],
          );
        },
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine, required this.avatar, required this.groupStart, required this.onRetry});

  final ChatMessage message;
  final bool mine;

  /// 这一组第一条才有头像，其余只留一块同样宽的空位，让气泡左右对齐
  final Widget? avatar;

  /// 紧挨着上一组（中间没有时间分隔）的新一组：上面多留一点空隙
  final bool groupStart;
  final VoidCallback onRetry;

  static const double avatarSize = 36;
  static const double avatarGap = AppSpace.s8;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maxWidth = (MediaQuery.sizeOf(context).width - AppSpace.pageGutter * 2 - avatarSize - avatarGap) * 0.8;
    final failed = message.status == MessageStatus.failed;
    final sending = message.status == MessageStatus.sending;

    // 我发的：墨色实底（深色模式下是亮的）；对方发的：白卡片 + 发丝边。炭火橙留给发送按钮和未读。
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? c.text : c.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(AppRadius.lg - 4),
          topRight: const Radius.circular(AppRadius.lg - 4),
          bottomLeft: Radius.circular(mine ? AppRadius.lg - 4 : 6),
          bottomRight: Radius.circular(mine ? 6 : AppRadius.lg - 4),
        ),
        border: mine ? null : Border.all(color: c.border, width: AppStroke.hairline),
      ),
      child: Opacity(
        opacity: sending ? 0.6 : 1,
        child: SelectableText(
          message.body,
          style: AppText.body.copyWith(color: mine ? c.bg : c.text, height: 1.4),
        ),
      ),
    );

    final slot = SizedBox(width: avatarSize, child: avatar);
    return Padding(
      padding: EdgeInsets.only(top: groupStart ? 10 : 3, bottom: 3),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine) ...[slot, const SizedBox(width: avatarGap)],
          if (mine && failed) ...[
            PressScale(
              scale: PressScale.smallScale,
              child: Tooltip(
                message: '发送失败，点一下重发',
                child: InkResponse(
                  onTap: onRetry,
                  radius: 22,
                  child: SizedBox.square(dimension: 36, child: Icon(AppIcons.warnSmall, size: 20, color: c.danger)),
                ),
              ),
            ),
          ],
          Flexible(child: bubble),
          if (mine) ...[const SizedBox(width: avatarGap), slot],
        ],
      ),
    );
  }
}
