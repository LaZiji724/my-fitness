import 'dart:io' show SocketException;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:my_fitness/core/config/env.dart';
import 'package:my_fitness/features/auth/validators.dart';

/// 用户名 + 密码登录。Supabase Auth 只认邮箱，所以把用户名映射成
/// 一个不对外收信的虚拟邮箱：alice -> alice@myfit.app。
/// 需要在 Supabase 后台关闭 Confirm email，否则注册后无法直接登录。
class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  static String emailFor(String username) =>
      '${AuthValidators.normalizeUsername(username)}@${Env.emailDomain}';

  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      email: emailFor(username),
      password: password,
    );
  }

  Future<void> signUp({
    required String username,
    required String password,
    required String displayName,
    required String avatarRef,
  }) async {
    final name = AuthValidators.normalizeUsername(username);
    final res = await _client.auth.signUp(
      email: emailFor(name),
      password: password,
      data: {
        'username': name,
        'display_name': displayName.trim().isEmpty ? name : displayName.trim(),
        'avatar_ref': avatarRef,
      },
    );
    if (res.session == null) {
      // 邮箱确认没关：账号建了但没有会话。
      throw const AuthSetupException('请先在 Supabase 后台关闭 “Confirm email”');
    }
  }

  Future<void> signOut() => _client.auth.signOut();

  /// 把各种错误翻译成给用户看的中文提示。
  static String messageFor(Object error) {
    if (error is AuthSetupException) return error.message;
    if (error is SocketException || error is AuthRetryableFetchException) {
      return '网络不可用，请检查网络后重试';
    }
    if (error is AuthApiException) {
      final m = error.message.toLowerCase();
      if (m.contains('invalid login')) return '用户名或密码错误';
      if (m.contains('already registered') ||
          m.contains('already been registered') ||
          m.contains('database error')) {
        return '这个用户名已被占用，换一个试试';
      }
      if (m.contains('at least')) return '密码太短，至少 8 位';
      if (m.contains('rate limit') || m.contains('too many')) {
        return '操作太频繁，请稍后再试';
      }
    }
    return '操作失败，请稍后重试';
  }
}

class AuthSetupException implements Exception {
  const AuthSetupException(this.message);
  final String message;
  @override
  String toString() => message;
}
