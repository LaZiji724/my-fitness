import 'package:supabase_flutter/supabase_flutter.dart';

/// 增量拉取的游标：按 (updated_at, id) 排序后的最后一行。
/// 同一事务里批量写入的行 updated_at 完全相同，所以必须带上 id 才不会在分页边界漏行。
class SyncCursor {
  const SyncCursor(this.updatedAt, this.id);
  final String updatedAt;
  final String id;

  String encode() => '$updatedAt|$id';

  static SyncCursor? decode(String? s) {
    if (s == null) return null;
    final i = s.lastIndexOf('|');
    if (i <= 0) return null;
    return SyncCursor(s.substring(0, i), s.substring(i + 1));
  }
}

/// 云端的最小接口，方便在测试里换成内存实现。
abstract class SyncRemote {
  /// 按主键 id 插入或更新。
  Future<void> upsert(String table, List<Map<String, dynamic>> rows);

  /// 拉取该用户在游标之后的行，按 (updated_at, id) 升序，最多 [limit] 行。
  Future<List<Map<String, dynamic>>> fetchAfter(
    String table, {
    required String userId,
    SyncCursor? cursor,
    int limit = 500,
  });
}

class SupabaseSyncRemote implements SyncRemote {
  SupabaseSyncRemote(this._client);
  final SupabaseClient _client;

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _client.from(table).upsert(rows, onConflict: 'id');
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAfter(
    String table, {
    required String userId,
    SyncCursor? cursor,
    int limit = 500,
  }) async {
    var q = _client.from(table).select().eq('user_id', userId);
    if (cursor != null) {
      final t = cursor.updatedAt.replaceAll('+00:00', 'Z');
      q = q.or('updated_at.gt.$t,and(updated_at.eq.$t,id.gt.${cursor.id})');
    }
    final rows = await q.order('updated_at', ascending: true).order('id', ascending: true).limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }
}
