import 'package:flutter_test/flutter_test.dart';
import 'package:my_fitness/app/router.dart';

void main() {
  test('未登录一律去登录页，注册页除外', () {
    expect(authRedirect(loggedIn: false, location: '/today'), '/login');
    expect(authRedirect(loggedIn: false, location: '/me'), '/login');
    expect(authRedirect(loggedIn: false, location: '/login'), isNull);
    expect(authRedirect(loggedIn: false, location: '/register'), isNull);
  });

  test('已登录不再停留在登录/注册页', () {
    expect(authRedirect(loggedIn: true, location: '/login'), '/today');
    expect(authRedirect(loggedIn: true, location: '/register'), '/today');
    expect(authRedirect(loggedIn: true, location: '/stats'), isNull);
  });
}
