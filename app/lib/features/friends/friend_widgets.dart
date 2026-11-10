import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/avatar_view.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/friends/friend_models.dart';
import 'package:my_fitness/features/friends/friends_repository.dart';

/// 好友的两个页面：聊天、运动记录。两页顶部都有按钮互相跳转。
///
/// 从好友列表进到其中一页后，再点按钮去另一页：另一页压在上面；
/// 在另一页里再点回来，则是直接退回下面那一页，而不是再压一层新的。
/// 这样不管来回点多少次，页面栈最多只有「好友列表、一页、另一页」三层，连按两次返回就一定退出这位好友。
enum FriendPage { chat, activity }

/// 在 [from] 这一页里点「去 [to] 页」。[cameFrom] 是进入 [from] 时的上一页（从列表进来为 null）。
void switchFriendPage(BuildContext context, String friendId, {required FriendPage from, required FriendPage? cameFrom}) {
  final to = from == FriendPage.chat ? FriendPage.activity : FriendPage.chat;
  if (cameFrom == to && context.canPop()) {
    context.pop();
    return;
  }
  final path = to == FriendPage.chat ? '/friends/chat/$friendId' : '/friends/activity/$friendId';
  context.push(path, extra: from);
}

/// 用户头像，外面一圈很淡的细线（和首页左上角头像同款）。
class UserAvatar extends StatelessWidget {
  const UserAvatar(this.user, {super.key, this.size = 48, this.ring = false});

  final UserCard user;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final avatar = AvatarView(kind: user.avatarKind, avatarRef: user.avatarRef, size: size);
    if (!ring) return avatar;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: context.colors.text.withValues(alpha: 0.12), width: 1),
      ),
      child: avatar,
    );
  }
}

/// 未读数角标：炭火橙小胶囊。超过 99 显示 99+。
class UnreadBadge extends StatelessWidget {
  const UnreadBadge(this.count, {super.key});
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(AppRadius.full)),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: AppText.numSmall.copyWith(fontSize: 14, height: 1, color: c.onAccent),
      ),
    );
  }
}

/// 行内的小号主按钮（「添加」「通过」）。
class SmallPrimaryButton extends StatelessWidget {
  const SmallPrimaryButton({super.key, required this.label, required this.onPressed, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      scale: PressScale.chipScale,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(64, AppSize.buttonSmall)),
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: AppSpace.s16)),
          textStyle: WidgetStatePropertyAll(TextStyle(fontFamily: AppText.sans, fontSize: 14, fontWeight: FontWeight.w700, height: 1.2)),
        ),
        child: busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : Text(label),
      ),
    );
  }
}

/// 行内的小号次要按钮（「忽略」「撤回」）。
class SmallNeutralButton extends StatelessWidget {
  const SmallNeutralButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      scale: PressScale.chipScale,
      child: ElevatedButton(
        onPressed: onPressed,
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(64, AppSize.buttonSmall)),
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: AppSpace.s16)),
          textStyle: WidgetStatePropertyAll(TextStyle(fontFamily: AppText.sans, fontSize: 14, fontWeight: FontWeight.w600, height: 1.2)),
        ),
        child: Text(label),
      ),
    );
  }
}

/// 底部弹出一句提示。
void showFriendToast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// 把错误翻译成一句人话再提示。
void showFriendError(BuildContext context, Object error) =>
    showFriendToast(context, SupabaseFriendsRepository.translate(error).message);

String _two(int v) => v.toString().padLeft(2, '0');

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// 好友列表右侧的时间：今天显示时刻，昨天显示「昨天」，更早显示日期。
String listTimeLabel(DateTime t, DateTime now) {
  if (_sameDay(t, now)) return '${_two(t.hour)}:${_two(t.minute)}';
  if (_sameDay(t, DateTime(now.year, now.month, now.day - 1))) return '昨天';
  if (t.year == now.year) return '${t.month}月${t.day}日';
  return '${t.year}年${t.month}月';
}

/// 聊天里的时间分隔：「14:32」「昨天 14:32」「11月3日 14:32」。
String chatTimeLabel(DateTime t, DateTime now) {
  final clock = '${_two(t.hour)}:${_two(t.minute)}';
  if (_sameDay(t, now)) return clock;
  if (_sameDay(t, DateTime(now.year, now.month, now.day - 1))) return '昨天 $clock';
  if (t.year == now.year) return '${t.month}月${t.day}日 $clock';
  return '${t.year}年${t.month}月${t.day}日 $clock';
}

/// 「成为好友 12 天」。
String friendSinceLabel(DateTime since, DateTime now) {
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(since.year, since.month, since.day)).inDays;
  return days <= 0 ? '今天成为好友' : '成为好友 $days 天';
}
