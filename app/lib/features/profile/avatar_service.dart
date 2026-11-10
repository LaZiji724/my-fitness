import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:my_fitness/core/supabase/supabase_providers.dart';

/// 更换头像。抽成接口是为了测试里换成假的，不去连云端。
abstract class AvatarUpdater {
  /// 改用内置头像（[ref] 形如 avatar_03）。
  Future<void> setPreset(String ref);

  /// 上传自己的头像（已经裁成正方形的 PNG）。
  Future<void> setCustom(Uint8List png);
}

class SupabaseAvatarUpdater implements AvatarUpdater {
  SupabaseAvatarUpdater(this._client);

  final SupabaseClient _client;

  static const bucket = 'avatars';

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('未登录');
    return id;
  }

  @override
  Future<void> setPreset(String ref) async {
    final old = _currentCustomPath();
    await _save('preset', ref);
    await _removeQuietly(old);
  }

  @override
  Future<void> setCustom(Uint8List png) async {
    final uid = _uid;
    final old = _currentCustomPath();
    // 每次换新文件名：地址变了，别人和本机的图片缓存才会跟着刷新
    final path = '$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.png';
    await _client.storage.from(bucket).uploadBinary(
          path,
          png,
          fileOptions: const FileOptions(contentType: 'image/png', upsert: true),
        );
    await _save('custom', path);
    if (old != path) await _removeQuietly(old);
  }

  /// 当前用的是自己上传的头像时，返回它在 Storage 里的路径。
  String? _currentCustomPath() {
    final m = _client.auth.currentUser?.userMetadata ?? const <String, dynamic>{};
    return m['avatar_kind'] == 'custom' ? m['avatar_ref'] as String? : null;
  }

  /// 同时写资料表（好友看的是它）和登录信息里的资料（本机立刻刷新用的是它）。
  Future<void> _save(String kind, String ref) async {
    final uid = _uid;
    await _client.from('profiles').update({'avatar_kind': kind, 'avatar_ref': ref}).eq('id', uid);
    await _client.auth.updateUser(UserAttributes(data: {'avatar_kind': kind, 'avatar_ref': ref}));
  }

  Future<void> _removeQuietly(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      await _client.storage.from(bucket).remove([path]);
    } catch (_) {
      // 旧图删不掉不影响使用
    }
  }
}

final avatarUpdaterProvider = Provider<AvatarUpdater>(
  (ref) => SupabaseAvatarUpdater(ref.watch(supabaseClientProvider)),
);
