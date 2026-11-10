import 'dart:async';

import 'package:my_fitness/features/friends/friend_models.dart';
import 'package:my_fitness/features/friends/friends_repository.dart';

/// 内存里的假云端：测试和截图用，行为尽量贴近真实的数据库函数。
class FakeFriendsRepository implements FriendsRepository {
  FakeFriendsRepository({
    this.me = 'me',
    List<UserCard>? users,
    List<FriendEntry>? entries,
    Map<String, List<ChatMessage>>? chats,
    this.privacy = PrivacySettings.defaults,
    this.activities = const {},
  })  : users = users ?? [],
        entries = entries ?? [],
        chats = chats ?? {};

  final String me;
  final List<UserCard> users;
  final List<FriendEntry> entries;
  final Map<String, List<ChatMessage>> chats;
  PrivacySettings privacy;
  final Map<String, FriendActivity> activities;

  final events$ = StreamController<FriendEvent>.broadcast();

  /// 模拟断网
  bool offline = false;
  String? codeOwner;
  final List<String> sentRequests = [];
  final List<String> removed = [];
  final List<String> readChats = [];
  int codesCreated = 0;
  DateTime? codeExpiry;

  void _check() {
    if (offline) throw const FriendsException('网络不可用，请检查网络后重试', code: 'offline');
  }

  @override
  Future<List<FriendEntry>> overview() async {
    _check();
    return List.of(entries);
  }

  @override
  Future<List<UserCard>> search(String query) async {
    _check();
    final q = query.trim().replaceFirst('@', '').toLowerCase();
    if (q.isEmpty) return [];
    return users
        .where((u) => u.id != me && (u.username.toLowerCase().contains(q) || u.displayName.toLowerCase().contains(q)))
        .toList();
  }

  @override
  Future<FriendRelation> sendRequest(String userId) async {
    _check();
    sentRequests.add(userId);
    final u = users.firstWhere((u) => u.id == userId);
    final existing = entries.where((e) => e.user.id == userId).toList();
    if (existing.isNotEmpty && existing.first.relation == FriendRelation.incoming) {
      entries.removeWhere((e) => e.user.id == userId);
      entries.add(FriendEntry(friendshipId: 'f-$userId', user: u.withRelation(FriendRelation.friend), since: DateTime.now()));
      return FriendRelation.friend;
    }
    entries.add(FriendEntry(friendshipId: 'f-$userId', user: u.withRelation(FriendRelation.outgoing), since: DateTime.now()));
    return FriendRelation.outgoing;
  }

  @override
  Future<void> accept(String friendshipId) async {
    _check();
    final i = entries.indexWhere((e) => e.friendshipId == friendshipId);
    final e = entries[i];
    entries[i] = FriendEntry(friendshipId: e.friendshipId, user: e.user.withRelation(FriendRelation.friend), since: DateTime.now());
  }

  @override
  Future<void> remove(String userId) async {
    _check();
    removed.add(userId);
    entries.removeWhere((e) => e.user.id == userId);
    chats.remove(userId);
  }

  @override
  Future<List<ChatMessage>> messages(String friendId, {DateTime? before, int limit = 50}) async {
    _check();
    var list = List.of(chats[friendId] ?? const <ChatMessage>[])..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (before != null) list = list.where((m) => m.createdAt.isBefore(before)).toList();
    return list.length > limit ? list.sublist(list.length - limit) : list;
  }

  @override
  Future<ChatMessage> send({required String id, required String friendId, required String body}) async {
    _check();
    final isFriend = entries.any((e) => e.user.id == friendId && e.relation == FriendRelation.friend);
    if (!isFriend) throw const FriendsException('你们已经不是好友了，发不出去', code: 'not_friends');
    final m = ChatMessage(id: id, senderId: me, receiverId: friendId, body: body, createdAt: DateTime.now());
    chats.putIfAbsent(friendId, () => []).add(m);
    return m;
  }

  @override
  Future<void> markRead(String friendId) async => readChats.add(friendId);

  @override
  Future<FriendCode> createCode() async {
    _check();
    codesCreated++;
    final expiry = codeExpiry ?? DateTime.now().add(const Duration(minutes: 10));
    codeOwner = me;
    return FriendCode(code: codesCreated.toRadixString(16).padLeft(32, '0'), expiresAt: expiry);
  }

  @override
  Future<UserCard> lookupCode(String code) async {
    _check();
    if (code != 'a' * 32 && code != 'b' * 32) {
      throw const FriendsException('二维码已过期，请对方刷新后再扫', code: 'code_expired');
    }
    final u = users.firstWhere((u) => u.id == (code == 'a' * 32 ? 'u-scan' : 'me'));
    final known = entries.where((e) => e.user.id == u.id).toList();
    return u.id == me ? u.withRelation(FriendRelation.self) : (known.isEmpty ? u : u.withRelation(known.first.relation));
  }

  @override
  Future<void> addByCode(String code) async {
    _check();
    final u = users.firstWhere((u) => u.id == 'u-scan');
    entries.removeWhere((e) => e.user.id == u.id);
    entries.add(FriendEntry(friendshipId: 'f-${u.id}', user: u.withRelation(FriendRelation.friend), since: DateTime.now()));
  }

  @override
  Future<PrivacySettings> loadPrivacy() async {
    _check();
    return privacy;
  }

  @override
  Future<void> savePrivacy(PrivacySettings s) async {
    _check();
    privacy = s;
  }

  @override
  Future<FriendActivity> activity(String friendId) async {
    _check();
    final a = activities[friendId];
    if (a == null) throw const FriendsException('你们已经不是好友了', code: 'not_friends');
    return a;
  }

  @override
  Stream<FriendEvent> events() => events$.stream;

  /// 模拟好友发来一条消息（对方先写进库，再推给我）
  void incoming(String fromId, String body, {DateTime? at}) {
    final m = ChatMessage(
      id: 'in-${chats[fromId]?.length ?? 0}-$fromId-$body',
      senderId: fromId,
      receiverId: me,
      body: body,
      createdAt: at ?? DateTime.now(),
    );
    chats.putIfAbsent(fromId, () => []).add(m);
    final i = entries.indexWhere((e) => e.user.id == fromId);
    if (i >= 0) {
      final e = entries[i];
      entries[i] = e.copyWith(lastBody: body, lastAt: m.createdAt, lastFromMe: false, unread: e.unread + 1);
    }
    events$.add(MessageArrived(m));
  }
}
