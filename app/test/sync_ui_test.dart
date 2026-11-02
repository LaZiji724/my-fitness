import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/sync/sync_chip.dart';
import 'package:my_fitness/features/sync/sync_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Fixed extends SyncController {
  _Fixed(this.status);
  final SyncStatus status;
  int calls = 0;
  @override
  SyncStatus build() => status;
  @override
  Future<void> requestSync() async => calls++;
}

void main() {
  test('相对时间', () {
    final now = DateTime(2026, 11, 2, 18, 30);
    expect(formatAgo(DateTime(2026, 11, 2, 18, 29, 40), now), '刚刚');
    expect(formatAgo(DateTime(2026, 11, 2, 18, 15), now), '15 分钟前');
    expect(formatAgo(DateTime(2026, 11, 2, 9, 5), now), '今天 09:05');
    expect(formatAgo(DateTime(2026, 10, 28, 20, 0), now), '10月28日 20:00');
  });

  test('同步错误翻成中文，联网问题与权限问题分开', () {
    expect(describeSyncError(const SocketException('x')), contains('网络'));
    expect(describeSyncError(TimeoutException('x')), contains('网络'));
    expect(describeSyncError(const PostgrestException(message: 'fk', code: '23503')), contains('动作库'));
    expect(describeSyncError(const PostgrestException(message: 'rls', code: '42501')), contains('重新登录'));
    expect(describeSyncError(const PostgrestException(message: 'no table', code: '42P01')), contains('迁移'));
    expect(describeSyncError(const AuthException('expired')), contains('重新登录'));
    expect(describeSyncError(Exception('boom')), contains('稍后'));
  });

  for (final (status, label) in [
    (SyncStatus(lastSync: DateTime(2026, 11, 2)), '已同步'),
    (const SyncStatus(), '未同步'),
    (SyncStatus(lastSync: DateTime(2026, 11, 2), pending: true), '待同步'),
    (const SyncStatus(phase: SyncPhase.syncing), '同步中'),
    (const SyncStatus(phase: SyncPhase.error, error: '网络不可用'), '同步失败'),
  ]) {
    testWidgets('同步标签：$label，点击触发同步', (tester) async {
      final fake = _Fixed(status);
      await tester.pumpWidget(ProviderScope(
        overrides: [syncControllerProvider.overrideWith(() => fake)],
        child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: Center(child: SyncChip()))),
      ));
      expect(find.text(label), findsOneWidget);
      await tester.tap(find.text(label));
      expect(fake.calls, 1);
    });
  }
}
