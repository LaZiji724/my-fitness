import 'dart:async';
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
    // 文件名每次都是新的，不需要覆盖（upsert）。upsert 会额外要求「查看」权限，
    // 云端头像桶没给这个权限，之前上传就是被它拒掉的。
    await _client.storage.from(bucket).uploadBinary(
          path,
          png,
          fileOptions: const FileOptions(contentType: 'image/png', upsert: false),
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

/// 换头像失败时给用户看的话：区分「网络不通」和「服务器拒绝」，别一律说成网络问题。
String avatarErrorText(Object error) {
  if (error is TimeoutException) return '上传超时了，请换个网络或稍后再试';
  if (error is StorageException) return '头像没传上去（服务器返回 ${error.statusCode ?? '未知'}：${error.message}）';
  if (error is PostgrestException) return '头像传上去了，但保存资料失败（${error.message}）';
  if (error is AuthException) return '登录状态失效了，请退出后重新登录';
  return '网络不通，请检查网络后重试';
}

final avatarUpdaterProvider = Provider<AvatarUpdater>(
  (ref) => SupabaseAvatarUpdater(ref.watch(supabaseClientProvider)),
);
