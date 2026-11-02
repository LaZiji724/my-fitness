/// 注册 / 登录表单校验。规则与数据库约束一致：
/// profiles.username ~ '^[a-z0-9_]{3,20}$'。
abstract final class AuthValidators {
  static final RegExp _usernameRe = RegExp(r'^[a-z0-9_]{3,20}$');

  static String normalizeUsername(String raw) => raw.trim().toLowerCase();

  static String? username(String? value) {
    final s = normalizeUsername(value ?? '');
    if (s.isEmpty) return '请输入用户名';
    if (!_usernameRe.hasMatch(s)) return '3–20 位小写字母、数字或下划线';
    return null;
  }

  static String? loginPassword(String? value) {
    if (value == null || value.isEmpty) return '请输入密码';
    return null;
  }

  static String? newPassword(String? value) {
    if (value == null || value.isEmpty) return '请输入密码';
    if (value.length < 8) return '密码至少 8 位';
    return null;
  }

  static String? displayName(String? value) {
    if ((value ?? '').trim().length > 20) return '昵称最多 20 个字';
    return null;
  }
}
