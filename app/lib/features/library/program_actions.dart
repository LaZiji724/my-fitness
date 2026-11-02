import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/features/library/library_providers.dart';
import 'package:my_fitness/features/library/library_repository.dart';
import 'package:my_fitness/features/library/program.dart';
import 'package:my_fitness/features/plan/plan_providers.dart';
import 'package:my_fitness/features/plan/plan_widgets.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';

/// 直接练这一节（不加入计划）。已有进行中的训练时，先问是继续还是放弃重来。
Future<void> startProgramSession(
  BuildContext context,
  WidgetRef ref,
  Program program,
  ProgramSession session,
) async {
  final workouts = ref.read(workoutRepositoryProvider);
  final active = await workouts.activeWorkout();
  if (active != null) {
    if (!context.mounted) return;
    final goOn = await confirmDialog(context,
        title: '已有进行中的训练', message: '先完成或放弃当前这次训练，才能开始新的一节。要回去继续吗？', confirm: '继续训练');
    if (goOn && context.mounted) context.go('/workout');
    return;
  }
  await ref.read(libraryRepositoryProvider).startSession(workouts, program, session);
  if (context.mounted) context.go('/workout');
}

/// 「去训练」：按已完成的节数轮转到下一节。
Future<void> startNextSession(BuildContext context, WidgetRef ref, Program program) async {
  final counts = await ref.read(libraryRepositoryProvider).watchCompletedCounts().first;
  final next = ProgramLibraryRepository.nextSession(program, counts[program.id] ?? 0);
  if (next == null || !context.mounted) return;
  await startProgramSession(context, ref, program, next);
}

/// 加入「我的计划」。已经加入过就提示并带去计划页。
Future<void> joinProgram(BuildContext context, WidgetRef ref, Program program) async {
  final repo = ref.read(libraryRepositoryProvider);
  final joined = ref.read(joinedProgramsProvider).value ?? const <String, String>{};
  if (joined.containsKey(program.id)) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('已经在「我的计划」里了'),
        action: SnackBarAction(label: '去看看', onPressed: () => context.go('/plan')),
      ));
    return;
  }
  await repo.join(program);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('已加入「${program.name}」，课程已生成为模板'),
      action: SnackBarAction(label: '去看看', onPressed: () => context.go('/plan')),
    ));
}

/// 「添加到日历」：选开始日期，把计划设为当前计划，日历与首页按周安排显示每天练什么。
Future<void> addProgramToCalendar(BuildContext context, WidgetRef ref, Program program) async {
  final today = ref.read(todayProvider);
  final picked = await showDatePicker(
    context: context,
    initialDate: today,
    firstDate: today.subtract(const Duration(days: 30)),
    lastDate: today.add(const Duration(days: 365)),
    helpText: '选择开始的那一周',
    confirmText: '确定',
    cancelText: '取消',
  );
  if (picked == null || !context.mounted) return;

  final plans = ref.read(plansProvider).value ?? const [];
  final joined = ref.read(joinedProgramsProvider).value ?? const <String, String>{};
  final currentActive = plans.where((p) => p.plan.isActive).firstOrNull;
  final alreadyActive = currentActive != null && currentActive.plan.id == joined[program.id];
  if (currentActive != null && !alreadyActive) {
    final ok = await confirmDialog(context,
        title: '替换当前计划',
        message: '现在的当前计划是「${currentActive.plan.name}」，添加后「${program.name}」会成为当前计划（原计划保留在「我的计划」里）。',
        confirm: '替换');
    if (!ok || !context.mounted) return;
  }
  await ref.read(libraryRepositoryProvider).join(program, activate: true, startFrom: picked);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('已添加到日历：从 ${picked.month} 月 ${picked.day} 日所在的周开始，按周一至周日安排'),
      action: SnackBarAction(label: '看日历', onPressed: () => context.go('/calendar')),
    ));
}
