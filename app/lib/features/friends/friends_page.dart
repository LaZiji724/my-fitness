import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/app_ui.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/friends/friend_models.dart';
import 'package:my_fitness/features/friends/friend_widgets.dart';
import 'package:my_fitness/features/friends/friends_providers.dart';

/// 「好友」分栏：好友申请、好友列表，右上角是隐私设置和添加好友。
class FriendsPage extends ConsumerWidget {
  const FriendsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(friendsControllerProvider);
    final friends = s.friends;
    final incoming = s.incoming;
    final outgoing = s.outgoing;
    final empty = friends.isEmpty && incoming.isEmpty && outgoing.isEmpty;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(friendsControllerProvider.notifier).refresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, AppSpace.s24),
            children: [
              PageHeader(
                title: '好友',
                trailing: [
                  AppChip(
                    label: '隐私设置',
                    leading: AppIcons.privacySmall,
                    height: 40,
                    onTap: () => context.push('/friends/privacy'),
                  ),
                  const SizedBox(width: AppSpace.s8),
                  RoundIconButton(
                    icon: AppIcons.userAdd,
                    tooltip: '添加好友',
                    onPressed: () => showAddFriendSheet(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.s12),
              if (!s.loaded && s.error == null)
                const Padding(
                  padding: EdgeInsets.only(top: 96),
                  child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                )
              else if (!s.loaded)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: EmptyState(
                    icon: AppIcons.cloudOff,
                    title: '好友列表没加载出来',
                    hint: s.error,
                    action: SmallNeutralButton(
                      label: '再试一次',
                      onPressed: () => ref.read(friendsControllerProvider.notifier).refresh(),
                    ),
                  ),
                )
              else if (empty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: EmptyState(
                    icon: AppIcons.friends,
                    title: '还没有好友',
                    hint: '搜索用户名或昵称，或者当面扫一扫',
                    action: PressScale(
                      child: FilledButton(
                        style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(160, AppSize.button))),
                        onPressed: () => showAddFriendSheet(context),
                        child: const Text('添加好友'),
                      ),
                    ),
                  ),
                )
              else ...[
                if (incoming.isNotEmpty) ...[
                  SectionTitle('新的朋友', trailing: UnreadBadge(incoming.length)),
                  const SizedBox(height: AppSpace.s12),
                  _Group(children: [for (final e in incoming) _IncomingRow(entry: e)]),
                  const SizedBox(height: AppSpace.s24),
                ],
                if (friends.isNotEmpty) ...[
                  SectionTitle('我的好友', trailing: Text('${friends.length} 位', style: AppText.label.copyWith(color: context.colors.text3))),
                  const SizedBox(height: AppSpace.s12),
                  _Group(children: [for (final e in friends) _FriendRow(entry: e)]),
                  const SizedBox(height: AppSpace.s24),
                ],
                if (outgoing.isNotEmpty) ...[
                  const SectionTitle('等待对方通过'),
                  const SizedBox(height: AppSpace.s12),
                  _Group(children: [for (final e in outgoing) _OutgoingRow(entry: e)]),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 一张卡片里的若干行，行与行之间一条发丝线（从文字起始处开始）。
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const HairDivider(indent: 76),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.user, required this.subtitle, this.trailing, this.onTap, this.subtitleStrong = false});

  final UserCard user;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool subtitleStrong;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.cardPadding, vertical: AppSpace.s12),
      child: Row(
        children: [
          UserAvatar(user, size: 48),
          const SizedBox(width: AppSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.displayName,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body.copyWith(color: c.text, fontWeight: FontWeight.w600)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label.copyWith(color: subtitleStrong ? c.text : c.text2, fontWeight: subtitleStrong ? FontWeight.w500 : FontWeight.w400)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: AppSpace.s12), trailing!],
        ],
      ),
    );
    if (onTap == null) return row;
    return PressScale(scale: PressScale.cardScale, child: InkWell(onTap: onTap, child: row));
  }
}

class _FriendRow extends ConsumerWidget {
  const _FriendRow({required this.entry});
  final FriendEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final body = entry.lastBody?.replaceAll('\n', ' ');
    final preview = body == null ? '@${entry.user.username}' : (entry.lastFromMe ? '我：$body' : body);
    return _PersonRow(
      user: entry.user,
      subtitle: preview,
      subtitleStrong: entry.unread > 0,
      onTap: () => showFriendSheet(context, entry),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (entry.lastAt != null) Text(listTimeLabel(entry.lastAt!, DateTime.now()), style: AppText.caption.copyWith(color: c.text3)),
          if (entry.unread > 0) ...[const SizedBox(height: AppSpace.s4), UnreadBadge(entry.unread)],
        ],
      ),
    );
  }
}

class _IncomingRow extends ConsumerStatefulWidget {
  const _IncomingRow({required this.entry});
  final FriendEntry entry;

  @override
  ConsumerState<_IncomingRow> createState() => _IncomingRowState();
}

class _IncomingRowState extends ConsumerState<_IncomingRow> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && done != null) showFriendToast(context, done);
    } catch (e) {
      if (mounted) showFriendError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final ctrl = ref.read(friendsControllerProvider.notifier);
    return _PersonRow(
      user: e.user,
      subtitle: '想加你为好友',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SmallNeutralButton(label: '忽略', onPressed: _busy ? null : () => _run(() => ctrl.remove(e.user.id))),
          const SizedBox(width: AppSpace.s8),
          SmallPrimaryButton(
            label: '通过',
            busy: _busy,
            onPressed: () => _run(() => ctrl.accept(e), done: '已和 ${e.user.displayName} 成为好友'),
          ),
        ],
      ),
    );
  }
}

class _OutgoingRow extends ConsumerWidget {
  const _OutgoingRow({required this.entry});
  final FriendEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _PersonRow(
      user: entry.user,
      subtitle: '@${entry.user.username}',
      trailing: SmallNeutralButton(
        label: '撤回',
        onPressed: () async {
          try {
            await ref.read(friendsControllerProvider.notifier).remove(entry.user.id);
          } catch (e) {
            if (context.mounted) showFriendError(context, e);
          }
        },
      ),
    );
  }
}

/// 点一个好友弹出的卡片：头像、名字，两个按钮「聊天」和「最近运动」。
Future<void> showFriendSheet(BuildContext context, FriendEntry entry) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => _FriendSheet(entry: entry),
  );
}

class _FriendSheet extends ConsumerWidget {
  const _FriendSheet({required this.entry});
  final FriendEntry entry;

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: '删除好友？',
        message: '删除后你们的聊天记录会一起清空，双方也不能再查看对方的运动记录。',
        actions: [
          AppDialogAction('取消', onPressed: () => Navigator.pop(ctx, false)),
          AppDialogAction('删除', kind: AppDialogActionKind.danger, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final ctrl = ref.read(friendsControllerProvider.notifier);
    Navigator.pop(context);
    try {
      await ctrl.remove(entry.user.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('已删除 ${entry.user.displayName}')));
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final u = entry.user;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.s20, AppSpace.s4, AppSpace.s20, AppSpace.s12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(u, size: 72, ring: true),
            const SizedBox(height: AppSpace.s12),
            Text(u.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.titleMedium.copyWith(color: c.text)),
            const SizedBox(height: 2),
            Text(metaLine(['@${u.username}', friendSinceLabel(entry.since, DateTime.now())]),
                style: AppText.label.copyWith(color: c.text3)),
            const SizedBox(height: AppSpace.s24),
            Row(
              children: [
                Expanded(
                  child: PressScale(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        context.push('/friends/activity/${u.id}');
                      },
                      child: const _IconLabel(AppIcons.barbell, '最近运动'),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.s12),
                Expanded(
                  child: PressScale(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(context);
                        context.push('/friends/chat/${u.id}');
                      },
                      child: const _IconLabel(AppIcons.chat, '聊天'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s8),
            TextButton(
              onPressed: () => _confirmRemove(context, ref),
              style: TextButton.styleFrom(foregroundColor: c.text3, textStyle: AppText.label),
              child: const Text('删除好友'),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconLabel extends StatelessWidget {
  const _IconLabel(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 20), const SizedBox(width: AppSpace.s8), Text(label)],
    );
  }
}

/// 右上角「添加好友」：选搜索、扫一扫，或者出示我的二维码。
Future<void> showAddFriendSheet(BuildContext context) {
  final router = GoRouter.of(context);
  return showModalBottomSheet<void>(
    context: context,
    builder: (ctx) {
      final c = ctx.colors;
      void go(String path) {
        Navigator.pop(ctx);
        router.push(path);
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.s20, AppSpace.s4, AppSpace.s20, AppSpace.s20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('添加好友', style: AppText.titleMedium.copyWith(color: c.text)),
              const SizedBox(height: AppSpace.s12),
              AppCard(
                color: c.bg,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    SettingRow(icon: AppIcons.search, title: '搜索', subtitle: '输入对方的用户名或昵称', onTap: () => go('/friends/search')),
                    const HairDivider(indent: 50),
                    SettingRow(icon: AppIcons.scan, title: '扫一扫', subtitle: '扫对方的二维码，直接成为好友', onTap: () => go('/friends/scan')),
                    const HairDivider(indent: 50),
                    SettingRow(icon: AppIcons.qrCode, title: '我的二维码', subtitle: '给对方扫，10 分钟内有效', onTap: () => go('/friends/qr')),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
