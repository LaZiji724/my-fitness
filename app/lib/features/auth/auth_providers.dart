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
