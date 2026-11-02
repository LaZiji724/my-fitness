import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_image.dart';
import 'package:my_fitness/features/exercises/exercise_repository.dart';
import 'package:my_fitness/features/exercises/exercises_page.dart';
import 'package:my_fitness/features/plan/plan_providers.dart';
import 'package:my_fitness/features/plan/plan_widgets.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';

const kTemplateDefaultRest = 90;

String describeTemplateExercise(TemplateExercise e) {
  final reps = e.repsMin == null
      ? ''
      : (e.repsMax == null || e.repsMax == e.repsMin ? ' · ${e.repsMin} 次' : ' · ${e.repsMin}–${e.repsMax} 次');
  return '${e.targetSets} 组$reps · 休息 ${e.restSec ?? kTemplateDefaultRest} 秒';
}

/// 编辑模板：改名、调整每个动作的组数/次数/休息，直接用它开始训练。
class TemplateEditPage extends ConsumerWidget {
  const TemplateEditPage({super.key, required this.templateId});
  final String templateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final repo = ref.watch(planRepositoryProvider);
    final async = ref.watch(templatesProvider);
    final byId = ref.watch(exerciseByIdProvider);
    final view = async.value?.where((t) => t.template.id == templateId).firstOrNull;

    if (view == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: async.isLoading
              ? const CircularProgressIndicator()
              : Text('模板不存在', style: AppText.body.copyWith(color: c.text2)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () async {
            final name = await promptName(context, title: '重命名模板', initial: view.template.name);
            if (name != null) await repo.renameTemplate(templateId, name);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(view.template.name, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              Icon(Icons.edit_outlined, size: 18, color: c.text3),
            ],
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (v) async {
              if (v == 'delete') {
                final ok = await confirmDialog(context,
                    title: '删除模板', message: '删除「${view.template.name}」？计划里用到它的天会变成休息日。', confirm: '删除');
                if (!ok) return;
                await repo.deleteTemplate(templateId);
                if (context.mounted) context.pop();
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('删除模板'))],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, 160),
        children: [
          if (view.exercises.isEmpty)
            const EmptyCard(title: '还没有动作', hint: '点下面的「添加动作」从动作库里选'),
          for (final e in view.exercises) ...[
            _ExerciseRow(entry: e, exercise: byId[e.exerciseId]),
            const SizedBox(height: AppSpace.s8),
          ],
          const SizedBox(height: AppSpace.s8),
          OutlinedButton.icon(
            onPressed: () => context.push('/template/$templateId/pick'),
            icon: const Icon(Icons.add_rounded),
            label: const Text('添加动作'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.button)),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, AppSpace.s12),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.buttonLarge)),
            onPressed: view.exercises.isEmpty
                ? null
                : () async {
                    await repo.startFromTemplate(ref.read(workoutRepositoryProvider), templateId);
                    if (context.mounted) context.go('/workout');
                  },
            child: const Text('用这个模板开始训练'),
          ),
        ),
      ),
    );
  }
}

class _ExerciseRow extends ConsumerWidget {
  const _ExerciseRow({required this.entry, required this.exercise});
  final TemplateExercise entry;
  final Exercise? exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Material(
      color: c.surface,
      borderRadius: AppRadius.card,
      child: InkWell(
        borderRadius: AppRadius.card,
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _ConfigSheet(entry: entry, name: exercise?.nameZh ?? '动作'),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s12),
          child: Row(
            children: [
              SizedBox(
                width: AppSize.exerciseThumb,
                child: exercise == null
                    ? const SizedBox.shrink()
                    : ExerciseImage(exercise: exercise!, cacheWidth: 160, radius: AppRadius.md - 4),
              ),
              const SizedBox(width: AppSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(exercise?.nameZh ?? '未知动作',
                        style: AppText.body.copyWith(color: c.text, fontWeight: FontWeight.w600)),
                    Text(describeTemplateExercise(entry), style: AppText.label.copyWith(color: c.text2)),
                  ],
                ),
              ),
              IconButton(
                tooltip: '移除动作',
                onPressed: () => ref.read(planRepositoryProvider).removeTemplateExercise(entry.id),
                icon: Icon(Icons.close_rounded, color: c.text3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfigSheet extends ConsumerStatefulWidget {
  const _ConfigSheet({required this.entry, required this.name});
  final TemplateExercise entry;
  final String name;

  @override
  ConsumerState<_ConfigSheet> createState() => _ConfigSheetState();
}

class _ConfigSheetState extends ConsumerState<_ConfigSheet> {
  late int sets = widget.entry.targetSets;
  late int repsMin = widget.entry.repsMin ?? 8;
  late int repsMax = widget.entry.repsMax ?? 12;
  late int rest = widget.entry.restSec ?? kTemplateDefaultRest;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final repo = ref.read(planRepositoryProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.s20, AppSpace.s8, AppSpace.s20, AppSpace.s20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.name, style: AppText.titleMedium.copyWith(color: c.text)),
            const SizedBox(height: AppSpace.s8),
            StepperField(
              label: '组数',
              value: sets,
              max: 20,
              unit: ' 组',
              onChanged: (v) {
                setState(() => sets = v);
                repo.updateTemplateExercise(widget.entry.id, targetSets: v);
              },
            ),
            StepperField(
              label: '次数下限',
              value: repsMin,
              max: 100,
              unit: ' 次',
              onChanged: (v) {
                setState(() {
                  repsMin = v;
                  if (repsMax < v) repsMax = v;
                });
                repo.updateTemplateExercise(widget.entry.id, repsMin: v, repsMax: repsMax);
              },
            ),
            StepperField(
              label: '次数上限',
              value: repsMax,
              max: 100,
              unit: ' 次',
              onChanged: (v) {
                setState(() {
                  repsMax = v;
                  if (repsMin > v) repsMin = v;
                });
                repo.updateTemplateExercise(widget.entry.id, repsMin: repsMin, repsMax: v);
              },
            ),
            StepperField(
              label: '组间休息',
              value: rest,
              min: 0,
              max: 600,
              step: 15,
              unit: ' 秒',
              onChanged: (v) {
                setState(() => rest = v);
                repo.updateTemplateExercise(widget.entry.id, restSec: v);
              },
            ),
            const SizedBox(height: AppSpace.s12),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.button)),
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 给模板挑动作：复用动作库页面，选中后加入模板并返回。
class TemplatePickPage extends ConsumerStatefulWidget {
  const TemplatePickPage({super.key, required this.templateId});
  final String templateId;

  @override
  ConsumerState<TemplatePickPage> createState() => _TemplatePickPageState();
}

class _TemplatePickPageState extends ConsumerState<TemplatePickPage> {
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
        await ref.read(planRepositoryProvider).addTemplateExercise(widget.templateId, exercise.id);
        if (context.mounted) context.pop();
      },
    );
  }
}
