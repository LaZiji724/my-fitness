import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/core/db/database_provider.dart';
import 'package:my_fitness/core/supabase/supabase_providers.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_repository.dart';
import 'package:my_fitness/features/workout/workout_math.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return WorkoutRepository(
    ref.watch(appDatabaseProvider),
    userId: () => client.auth.currentUser?.id ?? 'local',
  );
});

/// 进行中的训练；没有则为 null。
final activeWorkoutProvider = StreamProvider<WorkoutView?>(
  (ref) => ref.watch(workoutRepositoryProvider).watchActive(),
);

/// 内置动作按 id 索引，训练页用它显示名称和图片。
final exerciseByIdProvider = Provider<Map<String, Exercise>>((ref) {
  final all = ref.watch(exercisesProvider).value ?? const <Exercise>[];
  return {for (final e in all) e.id: e};
});

typedef ExerciseInWorkout = ({String exerciseId, String workoutId});

/// 该动作上一次练的组（用于“上次”列）。
final lastPerformanceProvider =
    FutureProvider.family<List<WorkoutSet>, ExerciseInWorkout>((ref, key) {
  return ref
      .watch(workoutRepositoryProvider)
      .lastPerformance(key.exerciseId, excludeWorkoutId: key.workoutId);
});

/// 该动作的历史最佳（用于 PR 判定）。
final bestBeforeProvider =
    FutureProvider.family<ExerciseBest, ExerciseInWorkout>((ref, key) {
  return ref
      .watch(workoutRepositoryProvider)
      .bestBefore(key.exerciseId, excludeWorkoutId: key.workoutId);
});

/// 组间休息倒计时。只存结束时刻，界面每秒自行刷新。
class RestState {
  const RestState({required this.endsAt, required this.totalSec});
  final DateTime endsAt;
  final int totalSec;

  int remainingSec(DateTime now) {
    final ms = endsAt.difference(now).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }
}

class RestTimerNotifier extends Notifier<RestState?> {
  @override
  RestState? build() => null;

  void start(int seconds, {DateTime? now}) {
    state = RestState(
      endsAt: (now ?? DateTime.now()).add(Duration(seconds: seconds)),
      totalSec: seconds,
    );
  }

  void adjust(int deltaSec) {
    final s = state;
    if (s == null) return;
    state = RestState(
      endsAt: s.endsAt.add(Duration(seconds: deltaSec)),
      totalSec: (s.totalSec + deltaSec).clamp(5, 3600),
    );
  }

  void skip() => state = null;
}

final restTimerProvider =
    NotifierProvider<RestTimerNotifier, RestState?>(RestTimerNotifier.new);

const int kDefaultRestSec = 90;
