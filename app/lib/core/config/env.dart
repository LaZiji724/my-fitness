/// 编译期配置，通过 `--dart-define-from-file=env.json` 注入（见 env.example.json）。
/// anon key 本身是公开的，安全由数据库 RLS 保证；service_role 密钥绝不放进 App。
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// 用户名映射成虚拟邮箱时使用的域名：alice -> alice@myfit.app。
  /// 若 Supabase 不接受该域名，只需改 env.json，无需改代码。
  static const emailDomain =
      String.fromEnvironment('AUTH_EMAIL_DOMAIN', defaultValue: 'myfit.app');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
