import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_detail_page.dart';
import 'package:my_fitness/features/exercises/exercise_repository.dart';
import 'package:my_fitness/features/exercises/exercises_page.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';

/// 训练中「添加动作」：复用动作库页面，选中后加入当前训练并返回。
class WorkoutPickPage extends ConsumerStatefulWidget {
  const WorkoutPickPage({super.key});

  @override
  ConsumerState<WorkoutPickPage> createState() => _WorkoutPickPageState();
}

class _WorkoutPickPageState extends ConsumerState<WorkoutPickPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(exerciseFilterProvider.notifier).reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 点动作先看详情，在详情里设好模块、计量方式、组数、次数 / 秒数、负重，再点「添加动作」才加入
    return ExercisesPage(
      onPick: (exercise) => context.push('/workout/pick/${exercise.slug}'),
    );
  }
}

/// 训练中挑动作时看到的动作详情：设好运动量后点「添加动作」，加入当前训练并一路返回到训练页。
class WorkoutPickDetailPage extends ConsumerWidget {
  const WorkoutPickDetailPage({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ExerciseDetailPage(
      slug: slug,
      onAdd: (exercise, dose) async {
        final workout = ref.read(activeWorkoutProvider).value;
        if (workout != null) {
          await ref.read(workoutRepositoryProvider).addExercise(
                workout.workout.id,
                exercise.id,
                section: dose.section.key,
                defaultSets: dose.sets,
                exactSets: true,
                explicitDose: true,
                defaultReps: dose.timed ? null : dose.reps,
                defaultDurationSec: dose.timed ? dose.seconds : null,
                defaultWeightKg: dose.weightKg,
                tracking: dose.timed ? TrackingType.duration : exercise.repsVariant,
                fallbackReps: exercise.defaultReps,
                fallbackSeconds: exercise.defaultSeconds,
              );
        }
        if (!context.mounted) return;
        final router = GoRouter.of(context);
        router.pop(); // 详情页
        router.pop(); // 选动作页
      },
    );
  }
}
