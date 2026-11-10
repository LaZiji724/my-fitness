import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/app_ui.dart';
import 'package:my_fitness/features/friends/friend_models.dart';
import 'package:my_fitness/features/friends/friend_widgets.dart';
import 'package:my_fitness/features/friends/friends_providers.dart';
import 'package:my_fitness/features/friends/friends_repository.dart';

/// 按用户名或昵称搜索用户，发好友申请。
class FriendSearchPage extends ConsumerStatefulWidget {
  const FriendSearchPage({super.key});

  @override
  ConsumerState<FriendSearchPage> createState() => _FriendSearchPageState();
}

class _FriendSearchPageState extends ConsumerState<FriendSearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  List<UserCard>? _results;
  String? _error;
  bool _loading = false;
  final Set<String> _busy = {};
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.isEmpty) {
      _seq++;
      setState(() {
        _query = '';
        _results = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    final seq = ++_seq;
    setState(() {
      _query = q;
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref.read(friendsRepositoryProvider).search(q);
      if (!mounted || seq != _seq) return;
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = SupabaseFriendsRepository.translate(e).message;
        _loading = false;
      });
    }
  }

  void _setRelation(String userId, FriendRelation r) {
    setState(() {
      _results = [for (final u in _results ?? const <UserCard>[]) u.id == userId ? u.withRelation(r) : u];
    });
  }

  Future<void> _add(UserCard u) async {
    setState(() => _busy.add(u.id));
    try {
      final r = await ref.read(friendsControllerProvider.notifier).sendRequest(u.id);
      if (!mounted) return;
      _setRelation(u.id, r);
      showFriendToast(context, r == FriendRelation.friend ? '已和 ${u.displayName} 成为好友' : '申请已发送，等对方通过');
    } catch (e) {
      if (mounted) showFriendError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(u.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final results = _results;

    Widget body;
    if (_query.isEmpty) {
      body = const EmptyState(icon: AppIcons.search, title: '找到你的朋友', hint: '输入对方的用户名或昵称，不用输全');
    } else if (_error != null && results == null) {
      body = EmptyState(
        icon: AppIcons.cloudOff,
        title: '搜索没成功',
        hint: _error,
        action: SmallNeutralButton(label: '再试一次', onPressed: () => _search(_query)),
      );
    } else if (results == null) {
      body = const Padding(
        padding: EdgeInsets.only(top: 64),
        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    } else if (results.isEmpty) {
      body = const EmptyState(icon: AppIcons.user, title: '没有找到这个人', hint: '检查一下用户名或昵称有没有输错');
    } else {
      body = AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < results.length; i++) ...[
              if (i > 0) const HairDivider(indent: 76),
              _ResultRow(user: results[i], busy: _busy.contains(results[i].id), onAdd: () => _add(results[i])),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('搜索用户')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, AppSpace.s32),
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: _onChanged,
            onSubmitted: (v) {
              _debounce?.cancel();
              if (v.trim().isNotEmpty) _search(v.trim());
            },
            textInputAction: TextInputAction.search,
            style: AppText.body.copyWith(color: c.text),
            decoration: InputDecoration(
              hintText: '用户名或昵称',
              filled: true,
              fillColor: c.surface,
              prefixIcon: Icon(AppIcons.searchSmall, size: 18, color: c.text3),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.button,
                borderSide: BorderSide(color: c.border, width: AppStroke.hairline),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.s16),
          body,
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.user, required this.busy, required this.onAdd});

  final UserCard user;
  final bool busy;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Widget action = switch (user.relation) {
      FriendRelation.none => SmallPrimaryButton(label: '添加', busy: busy, onPressed: onAdd),
      FriendRelation.incoming => SmallPrimaryButton(label: '通过', busy: busy, onPressed: onAdd),
      FriendRelation.outgoing => const AppTag('已申请'),
      FriendRelation.friend => const AppTag('已是好友'),
      FriendRelation.self => const SizedBox.shrink(),
    };
    return Padding(
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
                Text('@${user.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label.copyWith(color: c.text2)),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.s12),
          action,
        ],
      ),
    );
  }
}
