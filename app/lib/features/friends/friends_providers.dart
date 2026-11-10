import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:my_fitness/core/supabase/supabase_providers.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/friends/friend_models.dart';
import 'package:my_fitness/features/friends/friends_repository.dart';

final friendsRepositoryProvider = Provider<FriendsRepository>((ref) {
  return SupabaseFriendsRepository(ref.watch(supabaseClientProvider), userId: ref.watch(currentUserIdProvider));
});

/// 实时通道偶尔会断，所以再加一层定时刷新兜底。
const kFriendsPollInterval = Duration(seconds: 20);

class FriendsState {
  const FriendsState({this.entries = const [], this.loaded = false, this.error});

  final List<FriendEntry> entries;

  /// 至少成功拉到过一次
  final bool loaded;
  final String? error;

  List<FriendEntry> get friends {
    final list = entries.where((e) => e.relation == FriendRelation.friend).toList();
    // 最近聊过的排前面，没聊过的按成为好友的时间
    list.sort((a, b) => (b.lastAt ?? b.since).compareTo(a.lastAt ?? a.since));
    return list;
  }

  List<FriendEntry> get incoming =>
      entries.where((e) => e.relation == FriendRelation.incoming).toList()..sort((a, b) => b.since.compareTo(a.since));

  List<FriendEntry> get outgoing =>
      entries.where((e) => e.relation == FriendRelation.outgoing).toList()..sort((a, b) => b.since.compareTo(a.since));

  /// 底栏角标：未读消息数 + 待处理的好友申请数
  int get badge => friends.fold<int>(0, (n, e) => n + e.unread) + incoming.length;

  FriendEntry? byUser(String userId) {
    for (final e in entries) {
      if (e.user.id == userId) return e;
    }
    return null;
  }
}

/// 现在正开着和谁的聊天页（开着的时候新消息不弹窗、不计未读）。
class ActiveChatNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? friendId) => state = friendId;
}

final activeChatProvider = NotifierProvider<ActiveChatNotifier, String?>(ActiveChatNotifier.new);

/// 好友、申请、未读数的总管。应用启动后一直在后台运行：
/// 订阅实时事件，定时刷新兜底，有新消息时往 [incomingMessages] 里发一条（弹窗和聊天页都听它）。
class FriendsController extends Notifier<FriendsState> {
  late FriendsRepository _repo;
  String _me = kLocalUserId;
  final _incoming = StreamController<ChatMessage>.broadcast();

  /// 每个好友最后一条「已经提醒过」的来信时间，用来给定时刷新去重
  final Map<String, DateTime> _seen = {};
  bool _busy = false;
  bool _again = false;

  Stream<ChatMessage> get incomingMessages => _incoming.stream;

  bool get _active => _me != kLocalUserId;

  @override
  FriendsState build() {
    _me = ref.watch(currentUserIdProvider);
    _repo = ref.watch(friendsRepositoryProvider);
    _seen.clear();
    if (!_active) return const FriendsState();

    final sub = _repo.events().listen(_onEvent, onError: (_) {});
    final timer = Timer.periodic(kFriendsPollInterval, (_) {
      if (_foreground) refresh();
    });
    ref.onDispose(() {
      sub.cancel();
      timer.cancel();
    });
    Future.microtask(refresh);
    return const FriendsState();
  }

  bool get _foreground {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed || s == AppLifecycleState.inactive;
  }

  void _onEvent(FriendEvent e) {
    switch (e) {
      case FriendshipsChanged():
        refresh();
      case MessageArrived(:final message):
        _handleIncoming(message);
    }
  }

  void _handleIncoming(ChatMessage m) {
    final entry = state.byUser(m.senderId);
    final last = _seen[m.senderId];
    if (last != null && !m.createdAt.isAfter(last)) return; // 已经提醒过
    _seen[m.senderId] = m.createdAt;
    if (entry == null) {
      refresh();
    } else {
      final reading = ref.read(activeChatProvider) == m.senderId;
      _replace(entry.copyWith(
        lastBody: m.body,
        lastAt: m.createdAt,
        lastFromMe: false,
        unread: reading ? 0 : entry.unread + 1,
      ));
    }
    _incoming.add(m);
  }

  void _replace(FriendEntry next) {
    state = FriendsState(
      entries: [for (final e in state.entries) e.friendshipId == next.friendshipId ? next : e],
      loaded: state.loaded,
    );
  }

  /// 重新拉一遍好友总览。
  Future<void> refresh() async {
    if (!_active) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      final list = await _repo.overview();
      if (!ref.mounted) return;
      final first = !state.loaded;
      final reading = ref.read(activeChatProvider);
      final fresh = <ChatMessage>[];
      for (final e in list) {
        final at = e.lastAt;
        if (e.relation != FriendRelation.friend || at == null || e.lastFromMe) continue;
        final last = _seen[e.user.id];
        if (!first && e.unread > 0 && (last == null || at.isAfter(last))) {
          // 实时通道漏掉的消息：补一条提醒（内容用总览里的最后一条）
          fresh.add(ChatMessage(
            id: 'poll-${e.user.id}-${at.microsecondsSinceEpoch}',
            senderId: e.user.id,
            receiverId: _me,
            body: e.lastBody ?? '',
            createdAt: at,
          ));
        }
        if (last == null || at.isAfter(last)) _seen[e.user.id] = at;
      }
      state = FriendsState(
        entries: [for (final e in list) e.user.id == reading && e.unread > 0 ? e.copyWith(unread: 0) : e],
        loaded: true,
      );
      for (final m in fresh) {
        _incoming.add(m);
      }
    } catch (e) {
      if (!ref.mounted) return;
      state = FriendsState(entries: state.entries, loaded: state.loaded, error: SupabaseFriendsRepository.translate(e).message);
    } finally {
      _busy = false;
      if (_again && ref.mounted) {
        _again = false;
        unawaited(refresh());
      }
    }
  }

  Future<FriendRelation> sendRequest(String userId) async {
    final r = await _repo.sendRequest(userId);
    unawaited(refresh());
    return r;
  }

  Future<void> accept(FriendEntry e) async {
    await _repo.accept(e.friendshipId);
    await refresh();
  }

  Future<void> remove(String userId) async {
    await _repo.remove(userId);
    if (!ref.mounted) return;
    state = FriendsState(entries: state.entries.where((e) => e.user.id != userId).toList(), loaded: state.loaded);
    unawaited(refresh());
  }

  Future<void> addByCode(String code) async {
    await _repo.addByCode(code);
    await refresh();
  }

  /// 进入聊天页或在聊天页里收到新消息：未读清零。
  void markRead(String friendId) {
    final entry = state.byUser(friendId);
    if (entry != null && entry.unread > 0) _replace(entry.copyWith(unread: 0));
    _repo.markRead(friendId).catchError((_) {});
  }

  /// 我发出了一条消息：更新列表里的预览。
  void noteSent(ChatMessage m) {
    final entry = state.byUser(m.receiverId);
    if (entry != null) _replace(entry.copyWith(lastBody: m.body, lastAt: m.createdAt, lastFromMe: true));
  }
}

final friendsControllerProvider = NotifierProvider<FriendsController, FriendsState>(FriendsController.new);

/// 底栏「好友」上的角标数字。
final friendsBadgeProvider = Provider<int>((ref) => ref.watch(friendsControllerProvider).badge);

/// 一页聊天记录的条数
const kChatPageSize = 40;

class ChatState {
  const ChatState({this.messages = const [], this.loading = true, this.hasMore = false, this.loadingMore = false, this.error});

  /// 从旧到新
  final List<ChatMessage> messages;
  final bool loading;
  final bool hasMore;
  final bool loadingMore;
  final String? error;

  ChatState copyWith({List<ChatMessage>? messages, bool? loading, bool? hasMore, bool? loadingMore, String? error, bool clearError = false}) =>
      ChatState(
        messages: messages ?? this.messages,
        loading: loading ?? this.loading,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
      );
}

/// 和某一个好友的聊天。
class ChatController extends Notifier<ChatState> {
  ChatController(this.friendId);
  final String friendId;

  late FriendsRepository _repo;
  late String _me;
  static const _uuid = Uuid();

  @override
  ChatState build() {
    _repo = ref.watch(friendsRepositoryProvider);
    _me = ref.watch(currentUserIdProvider);
    final friends = ref.read(friendsControllerProvider.notifier);
    final sub = friends.incomingMessages.listen((m) {
      if (m.senderId != friendId) return;
      if (m.id.startsWith('poll-')) {
        _load(); // 定时刷新补上的提醒没有真实 id，重新拉一遍最新的
      } else {
        _merge([m]);
      }
      friends.markRead(friendId);
    });
    ref.onDispose(sub.cancel);
    Future.microtask(_load);
    return const ChatState();
  }

  void _merge(List<ChatMessage> incoming) {
    final byId = {for (final m in state.messages) m.id: m};
    for (final m in incoming) {
      byId[m.id] = m;
    }
    final list = byId.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    state = state.copyWith(messages: list);
  }

  Future<void> _load() async {
    try {
      final list = await _repo.messages(friendId, limit: kChatPageSize);
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, hasMore: state.hasMore || list.length >= kChatPageSize, clearError: true);
      _merge(list);
      ref.read(friendsControllerProvider.notifier).markRead(friendId);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, error: SupabaseFriendsRepository.translate(e).message);
    }
  }

  Future<void> reload() {
    state = state.copyWith(loading: state.messages.isEmpty, clearError: true);
    return _load();
  }

  /// 往前翻更早的消息。
  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore || state.messages.isEmpty) return;
    state = state.copyWith(loadingMore: true);
    try {
      final older = await _repo.messages(friendId, before: state.messages.first.createdAt, limit: kChatPageSize);
      if (!ref.mounted) return;
      state = state.copyWith(loadingMore: false, hasMore: older.length >= kChatPageSize);
      _merge(older);
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(loadingMore: false);
    }
  }

  /// 发送一条消息：先显示在界面上，再发到云端；失败的可以点一下重发。
  Future<void> send(String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final draft = ChatMessage(
      id: _uuid.v4(),
      senderId: _me,
      receiverId: friendId,
      body: body.length > 2000 ? body.substring(0, 2000) : body,
      createdAt: DateTime.now(),
      status: MessageStatus.sending,
    );
    _merge([draft]);
    await _deliver(draft);
  }

  Future<void> retry(ChatMessage m) async {
    if (m.status != MessageStatus.failed) return;
    final again = m.withStatus(MessageStatus.sending, createdAt: DateTime.now());
    _merge([again]);
    await _deliver(again);
  }

  Future<void> _deliver(ChatMessage draft) async {
    try {
      final sent = await _repo.send(id: draft.id, friendId: friendId, body: draft.body);
      if (!ref.mounted) return;
      _merge([sent]);
      ref.read(friendsControllerProvider.notifier).noteSent(sent);
    } catch (e) {
      if (!ref.mounted) return;
      _merge([draft.withStatus(MessageStatus.failed)]);
      state = state.copyWith(error: SupabaseFriendsRepository.translate(e).message);
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
}

final chatControllerProvider =
    NotifierProvider.autoDispose.family<ChatController, ChatState, String>(ChatController.new);

/// 我的隐私设置。
class PrivacyController extends AsyncNotifier<PrivacySettings> {
  @override
  Future<PrivacySettings> build() => ref.watch(friendsRepositoryProvider).loadPrivacy();

  /// 改一项就存一次；存失败则退回原样并抛出错误给界面提示。
  Future<void> save(PrivacySettings next) async {
    final prev = state.value;
    state = AsyncData(next);
    try {
      await ref.read(friendsRepositoryProvider).savePrivacy(next);
    } catch (e) {
      if (ref.mounted && prev != null) state = AsyncData(prev);
      rethrow;
    }
  }
}

final privacyControllerProvider =
    AsyncNotifierProvider.autoDispose<PrivacyController, PrivacySettings>(PrivacyController.new);

/// 好友公开给我的运动记录。
final friendActivityProvider = FutureProvider.autoDispose.family<FriendActivity, String>(
  (ref, friendId) => ref.watch(friendsRepositoryProvider).activity(friendId),
);
