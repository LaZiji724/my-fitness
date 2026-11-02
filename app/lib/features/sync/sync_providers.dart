import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, PostgrestException;

import 'package:my_fitness/core/db/database_provider.dart';
import 'package:my_fitness/core/supabase/supabase_providers.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/sync/sync_remote.dart';
import 'package:my_fitness/features/sync/sync_service.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SyncService(
    ref.watch(appDatabaseProvider),
    SupabaseSyncRemote(client),
    userId: () => client.auth.currentUser?.id ?? 'local',
  );
});

enum SyncPhase { idle, syncing, error }

class SyncStatus {
  const SyncStatus({this.phase = SyncPhase.idle, this.lastSync, this.error, this.pending = false});
  final SyncPhase phase;
  final DateTime? lastSync;

  /// 给人看的错误说明（已翻成中文）
  final String? error;

  /// 本地还有没推上去的改动
  final bool pending;

  SyncStatus copyWith({SyncPhase? phase, DateTime? lastSync, String? error, bool? pending, bool clearError = false}) =>
      SyncStatus(
        phase: phase ?? this.phase,
        lastSync: lastSync ?? this.lastSync,
        error: clearError ? null : (error ?? this.error),
        pending: pending ?? this.pending,
      );
}

/// 把同步过程中的各种异常翻成能看懂的中文。
String describeSyncError(Object e) {
  if (e is SocketException || e is TimeoutException || e is HttpException) {
    return '网络不可用，联网后会自动重试';
  }
  if (e is PostgrestException) {
    if (e.code == '23503') return '云端还没有动作库数据，请先按 README 上传动作库';
    if (e.code == '42501' || e.code == 'PGRST301' || e.code == '401') return '登录已失效，请退出后重新登录';
    if (e.code == '42P01' || e.code == 'PGRST205') return '云端数据库还没建表，请先执行 supabase 迁移';
    return '云端返回错误（${e.code ?? e.message}）';
  }
  if (e is AuthException) return '登录已失效，请退出后重新登录';
  final s = e.toString();
  if (s.contains('SocketException') || s.contains('ClientException') || s.contains('Failed host lookup')) {
    return '网络不可用，联网后会自动重试';
  }
  return '同步失败，稍后会重试';
}

/// 自动同步：启动时、本地数据改动 3 秒后、回到前台时、每 5 分钟各检查一次，
/// 只有确实有待推送的改动或到了定时拉取时才会联网。
class SyncController extends Notifier<SyncStatus> {
  Timer? _debounce;
  Timer? _periodic;
  StreamSubscription<Set<TableUpdate>>? _sub;

  @override
  SyncStatus build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _periodic?.cancel();
      _sub?.cancel();
    });
    final service = ref.watch(syncServiceProvider);
    final db = ref.watch(appDatabaseProvider);
    // 登录成功（含换账号）后马上同步一次
    ref.listen(authStateProvider, (_, next) {
      if (next.value?.session != null) requestSync();
    });

    _sub = db
        .tableUpdates(TableUpdateQuery.onAllTables([for (final t in service.tables) t.table]))
        .listen((_) => _schedule(const Duration(seconds: 3)));
    _periodic = Timer.periodic(const Duration(minutes: 5), (_) => requestSync());
    Future.microtask(() async {
      state = state.copyWith(lastSync: await service.lastSyncAt());
      await requestSync();
    });
    return const SyncStatus();
  }

  bool get _signedIn => ref.read(supabaseClientProvider).auth.currentUser != null;

  void _schedule(Duration d) {
    _debounce?.cancel();
    _debounce = Timer(d, () async {
      // 拉取下来的数据不是「待推送」，不会因此再触发一轮联网
      if (await ref.read(syncServiceProvider).hasDirty()) await requestSync();
    });
  }

  /// 立即同步一次（已有一轮在跑时复用）。
  Future<void> requestSync() async {
    if (!_signedIn || state.phase == SyncPhase.syncing) return;
    final service = ref.read(syncServiceProvider);
    state = state.copyWith(phase: SyncPhase.syncing, clearError: true);
    try {
      await service.syncNow();
      state = SyncStatus(phase: SyncPhase.idle, lastSync: await service.lastSyncAt(), pending: await service.hasDirty());
    } catch (e) {
      state = SyncStatus(
        phase: SyncPhase.error,
        lastSync: state.lastSync,
        error: describeSyncError(e),
        pending: await service.hasDirty(),
      );
    }
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(SyncController.new);
