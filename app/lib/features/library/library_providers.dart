import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/db/database_provider.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/library/library_repository.dart';
import 'package:my_fitness/features/library/program.dart';

final programSourceProvider = Provider<ProgramSource>((ref) => const AssetProgramSource());

/// 全部内置计划（按内容顺序）。
final programsProvider = FutureProvider<List<Program>>((ref) => ref.watch(programSourceProvider).loadAll());

final programBySlugProvider = Provider.family<Program?, String>((ref, slug) {
  final all = ref.watch(programsProvider).value;
  return all?.where((p) => p.slug == slug).firstOrNull;
});

final libraryRepositoryProvider = Provider<ProgramLibraryRepository>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  return ProgramLibraryRepository(
    ref.watch(appDatabaseProvider),
    userId: () => uid,
  );
});

final favoriteProgramIdsProvider = StreamProvider<Set<String>>(
  (ref) => ref.watch(libraryRepositoryProvider).watchFavoriteIds(),
);

/// 计划 id → 已完成节数。
final programCompletedCountsProvider = StreamProvider<Map<String, int>>(
  (ref) => ref.watch(libraryRepositoryProvider).watchCompletedCounts(),
);

/// 计划库计划 id → 「我的计划」id（已加入的）。
final joinedProgramsProvider = StreamProvider<Map<String, String>>(
  (ref) => ref.watch(libraryRepositoryProvider).watchJoined(),
);

class LibraryFilterNotifier extends Notifier<LibraryFilter> {
  @override
  LibraryFilter build() => const LibraryFilter();

  void setCategory(LibraryCategory c) => state = state.copyWith(category: c);
  void setFrequency(FrequencyBand? v) => state = state.copyWith(frequency: v);
  void setLevel(int? v) => state = state.copyWith(level: v);
  void setScene(String? v) => state = state.copyWith(scene: v);
  void setAudience(String? v) => state = state.copyWith(audience: v);
  void setQuery(String v) => state = state.copyWith(query: v);
  void clearAdvanced() => state = state.copyWith(frequency: null, level: null, scene: null, audience: null);
  void reset() => state = const LibraryFilter();
}

final libraryFilterProvider = NotifierProvider<LibraryFilterNotifier, LibraryFilter>(LibraryFilterNotifier.new);

/// 当前筛选结果。
final filteredProgramsProvider = Provider<List<Program>>((ref) {
  final all = ref.watch(programsProvider).value ?? const <Program>[];
  final fav = ref.watch(favoriteProgramIdsProvider).value ?? const <String>{};
  return filterPrograms(all, ref.watch(libraryFilterProvider), fav);
});
