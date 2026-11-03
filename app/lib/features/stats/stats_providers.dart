import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/core/db/database_provider.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/stats/body_repository.dart';
import 'package:my_fitness/features/stats/stats_math.dart';

final bodyRepositoryProvider = Provider<BodyRepository>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  return BodyRepository(
    ref.watch(appDatabaseProvider),
    userId: () => uid,
  );
});

final bodyMetricsProvider = StreamProvider<List<BodyMetric>>(
  (ref) => ref.watch(bodyRepositoryProvider).watchAll(),
);

class StatsView {
  const StatsView({required this.range, required this.anchor});
  final StatRange range;

  /// 当前区间里的任意一天（用来定位是哪一周/月/年）
  final DateTime anchor;

  StatsView copyWith({StatRange? range, DateTime? anchor}) =>
      StatsView(range: range ?? this.range, anchor: anchor ?? this.anchor);

  StatWindow get window => windowFor(range, anchor);
}

class StatsViewNotifier extends Notifier<StatsView> {
  @override
  StatsView build() => StatsView(range: StatRange.week, anchor: DateTime.now());

  void setRange(StatRange r) => state = state.copyWith(range: r);

  void shift(int delta) {
    final next = shiftWindow(state.range, state.window, delta);
    state = state.copyWith(anchor: next.start);
  }

  void reset(DateTime today) => state = state.copyWith(anchor: today);
}

final statsViewProvider = NotifierProvider<StatsViewNotifier, StatsView>(StatsViewNotifier.new);

final trendMetricProvider = NotifierProvider<TrendMetricNotifier, TrendMetric>(TrendMetricNotifier.new);

class TrendMetricNotifier extends Notifier<TrendMetric> {
  @override
  TrendMetric build() => TrendMetric.volume;
  void set(TrendMetric m) => state = m;
}
