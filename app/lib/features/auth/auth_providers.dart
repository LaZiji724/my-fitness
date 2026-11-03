import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:my_fitness/core/supabase/supabase_providers.dart';
import 'package:my_fitness/features/auth/auth_service.dart';
import 'package:my_fitness/features/auth/avatars.dart';

final authServiceProvider =
    Provider<AuthService>((ref) => AuthService(ref.watch(supabaseClientProvider)));

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseClientProvider).auth.onAuthStateChange,
);

/// 没登录时本地数据使用的占位用户 id（正常使用中登录前进不了主界面，这里只是兜底）。
const kLocalUserId = 'local';

/// 当前登录用户的 id。
///
/// 所有「按用户存取本地数据」的仓库都必须依赖它，而不是在回调里临时读 currentUser：
/// 换账号时它的值一变，依赖它的仓库与数据流就会整体重建，界面立刻改看新账号的数据，
/// 不会继续显示上一个账号缓存下来的查询结果。
/// （令牌自动续期也会触发登录事件，但 id 不变，不会引起重建。）
final currentUserIdProvider = Provider<String>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseClientProvider).auth.currentUser?.id ?? kLocalUserId;
});

/// 当前登录用户的展示信息（来自注册时写入的 user metadata，离线也可用）。
class ProfileSummary {
  const ProfileSummary({
    required this.username,
    required this.displayName,
    required this.avatarKind,
    required this.avatarRef,
  });

  final String username;
  final String displayName;

  /// preset：内置头像；custom：Supabase Storage 里的路径
  final String avatarKind;
  final String avatarRef;

  factory ProfileSummary.fromUser(User user) {
    final m = user.userMetadata ?? const <String, dynamic>{};
    final username = (m['username'] as String?) ?? '';
    return ProfileSummary(
      username: username,
      displayName: (m['display_name'] as String?)?.trim().isNotEmpty == true
          ? m['display_name'] as String
          : username,
      avatarKind: (m['avatar_kind'] as String?) ?? 'preset',
      avatarRef: (m['avatar_ref'] as String?) ?? kDefaultAvatarRef,
    );
  }
}

final profileSummaryProvider = Provider<ProfileSummary?>((ref) {
  ref.watch(authStateProvider); // 登录状态变化时刷新
  final user = ref.watch(supabaseClientProvider).auth.currentUser;
  return user == null ? null : ProfileSummary.fromUser(user);
});
