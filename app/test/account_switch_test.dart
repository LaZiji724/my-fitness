import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/core/db/database_provider.dart';
import 'package:my_fitness/core/supabase/supabase_providers.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/plan/plan_providers.dart';
import 'package:my_fitness/features/sync/sync_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 测试里用来模拟「当前登录的是谁」。
class _FakeUser extends Notifier<String> {
  @override
  String build() => 'u1';
  void set(String id) => state = id;
}

final _fakeUserProvider = NotifierProvider<_FakeUser, String>(_FakeUser.new);

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      // 只构造、不联网；currentUserIdProvider 被下面换成假用户
      supabaseClientProvider.overrideWithValue(SupabaseClient('https://example.supabase.co', 'test-key')),
      currentUserIdProvider.overrideWith((ref) => ref.watch(_fakeUserProvider)),
    ]);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// 数据流是异步推送的：等到当前值满足条件（最多约 2 秒）再返回，超时就返回最后一次的值让断言报错。
  Future<T> settled<T>(T Function() read, bool Function(T) ok) async {
    var v = read();
    for (var i = 0; i < 200 && !ok(v); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      v = read();
    }
    return v;
  }

  List<String> templateNowOf() =>
      [for (final t in container.read(templatesProvider).value ?? const []) t.template.name];

  Future<List<String>> templatesShow(List<String> want) =>
      settled(templateNowOf, (v) => v.length == want.length && v.every(want.contains));

  Future<List<String>> plansShow(List<String> want) => settled(
      () => [for (final p in container.read(plansProvider).value ?? const []) p.plan.name],
      (v) => v.length == want.length && v.every(want.contains));

  test('换账号后，模板 / 计划列表立刻改看新账号的数据，而不是缓存着上一个账号的', () async {
    final sub1 = container.listen(templatesProvider, (_, _) {});
    final sub2 = container.listen(plansProvider, (_, _) {});
    addTearDown(sub1.close);
    addTearDown(sub2.close);

    final repo1 = container.read(planRepositoryProvider);
    await repo1.createTemplate('u1 模板');
    await repo1.createPlan('u1 计划', 7);
    expect(await templatesShow(['u1 模板']), ['u1 模板']);
    expect(await plansShow(['u1 计划']), ['u1 计划']);

    container.read(_fakeUserProvider.notifier).set('u2');
    final repo2 = container.read(planRepositoryProvider);
    expect(identical(repo1, repo2), isFalse);
    expect(await templatesShow([]), isEmpty);
    expect(await plansShow([]), isEmpty);

    await repo2.createTemplate('u2 模板');
    expect(await templatesShow(['u2 模板']), ['u2 模板']);

    container.read(_fakeUserProvider.notifier).set('u1');
    expect(await templatesShow(['u1 模板']), ['u1 模板']);
    expect(await plansShow(['u1 计划']), ['u1 计划']);
  });

  test('同步服务也跟着账号走：写入的数据归当前账号', () async {
    final s1 = container.read(syncServiceProvider);
    container.read(_fakeUserProvider.notifier).set('u2');
    final s2 = container.read(syncServiceProvider);
    expect(identical(s1, s2), isFalse);

    await container.read(planRepositoryProvider).createTemplate('u2 模板');
    expect(await s2.hasDirty(), isTrue);
    expect(await s1.hasDirty(), isFalse);
  });
}
