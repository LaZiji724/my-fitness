import 'package:flutter_test/flutter_test.dart';
import 'package:my_fitness/features/auth/auth_service.dart';
import 'package:my_fitness/features/auth/validators.dart';

void main() {
  group('用户名校验', () {
    test('合法用户名', () {
      for (final ok in ['abc', 'alice_01', 'A1b', '  Bob_2  ', 'a' * 20]) {
        expect(AuthValidators.username(ok), isNull, reason: ok);
      }
    });
    test('非法用户名', () {
      for (final bad in ['', 'ab', 'a' * 21, 'has space', '中文名', 'a-b', 'a@b']) {
        expect(AuthValidators.username(bad), isNotNull, reason: bad);
      }
    });
    test('归一化为小写并映射成虚拟邮箱', () {
      expect(AuthValidators.normalizeUsername('  Alice_01 '), 'alice_01');
      expect(AuthService.emailFor('Alice_01'), 'alice_01@myfit.app');
    });
  });

  group('密码与昵称校验', () {
    test('新密码至少 8 位', () {
      expect(AuthValidators.newPassword('1234567'), isNotNull);
      expect(AuthValidators.newPassword('12345678'), isNull);
      expect(AuthValidators.newPassword(''), isNotNull);
    });
    test('登录密码只要求非空', () {
      expect(AuthValidators.loginPassword(''), isNotNull);
      expect(AuthValidators.loginPassword('x'), isNull);
    });
    test('昵称最多 20 字', () {
      expect(AuthValidators.displayName('铁' * 20), isNull);
      expect(AuthValidators.displayName('铁' * 21), isNotNull);
    });
  });

  test('错误信息翻译成中文', () {
    expect(AuthService.messageFor(const AuthSetupException('x')), 'x');
    expect(AuthService.messageFor(StateError('boom')), '操作失败，请稍后重试');
  });
}
