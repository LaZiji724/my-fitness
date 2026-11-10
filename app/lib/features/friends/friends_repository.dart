import 'dart:async';
import 'dart:io' show SocketException;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:my_fitness/features/friends/friend_models.dart';

/// 云端推过来的事件。
sealed class FriendEvent {
  const FriendEvent();
}

/// 有人给我发了一条消息
class MessageArrived extends FriendEvent {
  const MessageArrived(this.message);
  final ChatMessage message;
}

/// 好友关系有变化（新申请、被通过、被删除），需要重新拉列表
class FriendshipsChanged extends FriendEvent {
  const FriendshipsChanged();
}

/// 好友功能的全部云端操作。抽成接口，测试和截图里可以换成假的。
abstract class FriendsRepository {
  Future<List<FriendEntry>> overview();
  Future<List<UserCard>> search(String query);

  /// 返回发出后的关系：outgoing（等对方通过）或 friend（对方早就申请过，直接成了）
  Future<FriendRelation> sendRequest(String userId);
  Future<void> accept(String friendshipId);

  /// 拒绝申请、撤回申请、删除好友
  Future<void> remove(String userId);

  /// 最近的消息，按时间从旧到新。[before] 用来往前翻页。
  Future<List<ChatMessage>> messages(String friendId, {DateTime? before, int limit = 50});
  Future<ChatMessage> send({required String id, required String friendId, required String body});
  Future<void> markRead(String friendId);

  Future<FriendCode> createCode();
  Future<UserCard> lookupCode(String code);
  Future<void> addByCode(String code);

  Future<PrivacySettings> loadPrivacy();
  Future<void> savePrivacy(PrivacySettings s);
  Future<FriendActivity> activity(String friendId);

  /// 实时事件。取消订阅即断开。
  Stream<FriendEvent> events();
}

class SupabaseFriendsRepository implements FriendsRepository {
  SupabaseFriendsRepository(this._client, {required String userId}) : _me = userId;

  final SupabaseClient _client;
  final String _me;

  static const _messageColumns = 'id,sender_id,receiver_id,body,created_at';

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      throw translate(e);
    }
  }

  /// 把各种错误翻译成给用户看的中文提示。
  static FriendsException translate(Object e) {
    if (e is FriendsException) return e;
    if (e is PostgrestException) {
      final m = e.message;
      const known = {
        'code_expired': '二维码已过期，请对方刷新后再扫',
        'not_friends': '你们已经不是好友了',
        'invalid_target': '不能添加自己',
        'user_not_found': '没有找到这个人',
        'request_not_found': '这条申请已经处理过了',
        'not_signed_in': '登录已失效，请重新登录',
      };
      for (final k in known.keys) {
        if (m.contains(k)) return FriendsException(known[k]!, code: k);
      }
      if (m.contains('row-level security')) {
        return const FriendsException('你们已经不是好友了，发不出去', code: 'not_friends');
      }
      // 数据库还没升级到 3.1.0（找不到函数或表）
      if (e.code == 'PGRST202' || e.code == 'PGRST205' || e.code == '42883' || e.code == '42P01') {
        return const FriendsException('好友功能暂时不可用，请稍后再试', code: 'not_ready');
      }
      return const FriendsException('操作失败，请稍后重试');
    }
    if (e is SocketException || e is TimeoutException || e is AuthRetryableFetchException) {
      return const FriendsException('网络不可用，请检查网络后重试', code: 'offline');
    }
    final text = e.toString();
    if (text.contains('SocketException') || text.contains('ClientException') || text.contains('Failed host lookup')) {
      return const FriendsException('网络不可用，请检查网络后重试', code: 'offline');
    }
    return const FriendsException('操作失败，请稍后重试');
  }

  List<Map<String, dynamic>> _rows(dynamic data) =>
      (data as List? ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();

  @override
  Future<List<FriendEntry>> overview() => _guard(() async {
        final data = await _client.rpc('friends_overview');
        return _rows(data).map(FriendEntry.fromJson).toList();
      });

  @override
  Future<List<UserCard>> search(String query) => _guard(() async {
        final data = await _client.rpc('search_users', params: {'p_query': query});
        return _rows(data).map(UserCard.fromJson).toList();
      });

  @override
  Future<FriendRelation> sendRequest(String userId) => _guard(() async {
        final data = await _client.rpc('send_friend_request', params: {'p_target': userId});
        return FriendRelation.parse(data as String?);
      });

  @override
  Future<void> accept(String friendshipId) =>
      _guard(() async => await _client.rpc('accept_friend_request', params: {'p_request': friendshipId}));

  @override
  Future<void> remove(String userId) =>
      _guard(() async => await _client.rpc('remove_friend', params: {'p_other': userId}));

  @override
  Future<List<ChatMessage>> messages(String friendId, {DateTime? before, int limit = 50}) => _guard(() async {
        var q = _client
            .from('messages')
            .select(_messageColumns)
            .or('and(sender_id.eq.$_me,receiver_id.eq.$friendId),and(sender_id.eq.$friendId,receiver_id.eq.$_me)');
        if (before != null) q = q.lt('created_at', before.toUtc().toIso8601String());
        final data = await q.order('created_at', ascending: false).limit(limit);
        return _rows(data).map(ChatMessage.fromJson).toList().reversed.toList();
      });

  @override
  Future<ChatMessage> send({required String id, required String friendId, required String body}) => _guard(() async {
        final data = await _client
            .from('messages')
            .insert({'id': id, 'sender_id': _me, 'receiver_id': friendId, 'body': body})
            .select(_messageColumns)
            .single();
        return ChatMessage.fromJson(data);
      });

  @override
  Future<void> markRead(String friendId) =>
      _guard(() async => await _client.rpc('mark_chat_read', params: {'p_friend': friendId}));

  @override
  Future<FriendCode> createCode() => _guard(() async {
        final rows = _rows(await _client.rpc('create_friend_code'));
        if (rows.isEmpty) throw const FriendsException('生成二维码失败，请重试');
        return FriendCode(
          code: rows.first['code'] as String,
          expiresAt: DateTime.parse(rows.first['expires_at'] as String).toLocal(),
        );
      });

  @override
  Future<UserCard> lookupCode(String code) => _guard(() async {
        final rows = _rows(await _client.rpc('lookup_friend_code', params: {'p_code': code}));
        if (rows.isEmpty) throw const FriendsException('二维码已过期，请对方刷新后再扫', code: 'code_expired');
        return UserCard.fromJson(rows.first);
      });

  @override
  Future<void> addByCode(String code) =>
      _guard(() async => await _client.rpc('add_friend_by_code', params: {'p_code': code}));

  @override
  Future<PrivacySettings> loadPrivacy() => _guard(() async {
        final row = await _client.from('privacy_settings').select().eq('user_id', _me).maybeSingle();
        return row == null ? PrivacySettings.defaults : PrivacySettings.fromJson(row);
      });

  @override
  Future<void> savePrivacy(PrivacySettings s) =>
      _guard(() async => await _client.from('privacy_settings').upsert({'user_id': _me, ...s.toJson()}));

  @override
  Future<FriendActivity> activity(String friendId) => _guard(() async {
        final data = await _client.rpc('get_friend_activity', params: {'p_friend': friendId});
        return FriendActivity.fromJson((data as Map).cast<String, dynamic>());
      });

  @override
  Stream<FriendEvent> events() {
    late final StreamController<FriendEvent> controller;
    RealtimeChannel? channel;
    controller = StreamController<FriendEvent>(
      onListen: () {
        channel = _client
            .channel('friends:$_me')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'messages',
              filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'receiver_id', value: _me),
              callback: (payload) {
                try {
                  if (!controller.isClosed) controller.add(MessageArrived(ChatMessage.fromJson(payload.newRecord)));
                } catch (_) {}
              },
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'friendships',
              callback: (_) {
                if (!controller.isClosed) controller.add(const FriendshipsChanged());
              },
            )
            .subscribe();
      },
      onCancel: () {
        final ch = channel;
        channel = null;
        if (ch != null) unawaited(_client.removeChannel(ch).catchError((_) => 'error'));
      },
    );
    return controller.stream;
  }
}
