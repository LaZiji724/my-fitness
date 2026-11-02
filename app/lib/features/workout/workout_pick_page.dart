import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    return ExercisesPage(
      onPick: (exercise) async {
        final workout = ref.read(activeWorkoutProvider).value;
        if (workout != null) {
          await ref
              .read(workoutRepositoryProvider)
              .addExercise(
                workout.workout.id,
                exercise.id,
                defaultSets: exercise.defaultSets ?? 3,
                defaultReps: exercise.defaultReps,
                defaultDurationSec: exercise.defaultSeconds,
                tracking: exercise.trackingType,
                fallbackReps: exercise.defaultReps,
                fallbackSeconds: exercise.defaultSeconds,
              );
        }
        if (context.mounted) context.pop();
      },
    );
  }
}
