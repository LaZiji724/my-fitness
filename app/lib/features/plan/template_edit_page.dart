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
import 'package:my_fitness/features/plan/plan_repository.dart' show sortedBySection;
import 'package:my_fitness/features/exercises/exercise_prefs.dart';
import 'package:my_fitness/features/plan/plan_widgets.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';

const kTemplateDefaultRest = 90;

String describeTemplateExercise(TemplateExercise e) {
  final String target;
  if (e.targetDurationSec != null) {
    final s = e.targetDurationSec!;
    target = ' · ${s >= 60 && s % 60 == 0 ? '${s ~/ 60} 分钟' : '$s 秒'}';
  } else if (e.repsMin == null) {
    target = '';
  } else if (e.repsMax == null || e.repsMax == e.repsMin) {
    target = ' · ${e.repsMin} 次';
  } else {
    target = ' · ${e.repsMin}–${e.repsMax} 次';
  }
  final warm = e.warmupSets > 0 ? ' · 热身 ${e.warmupSets} 组' : '';
  return '${e.targetSets} 组$target$warm · 休息 ${e.restSec ?? kTemplateDefaultRest} 秒';
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
          for (final (i, e) in sortedBySection(view.exercises, (e) => e.section, (e) => e.position).indexed) ...[
            if (view.exercises.any((x) => x.section != 'main') &&
                (i == 0 || sortedBySection(view.exercises, (x) => x.section, (x) => x.position)[i - 1].section != e.section))
              _SectionLabel(WorkoutSection.fromKey(e.section)),
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
                    await repo.startFromTemplate(ref.read(workoutRepositoryProvider), templateId,
                        exercises: byId);
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
          builder: (_) => _ConfigSheet(
            entry: entry,
            name: exercise?.nameZh ?? '动作',
            timed: exercise?.trackingType == TrackingType.duration,
            exercise: exercise,
          ),
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
  const _ConfigSheet({required this.entry, required this.name, this.timed = false, this.exercise});
  final Exercise? exercise;
  final TemplateExercise entry;
  final String name;

  /// 按时间记录的动作（有氧、拉伸、平板支撑）：配置每组时长，而不是次数。
  final bool timed;

  @override
  ConsumerState<_ConfigSheet> createState() => _ConfigSheetState();
}

class _ConfigSheetState extends ConsumerState<_ConfigSheet> {
  late int sets = widget.entry.targetSets;
  late int repsMin = widget.entry.repsMin ?? 8;
  late int repsMax = widget.entry.repsMax ?? 12;
  late int rest = widget.entry.restSec ?? kTemplateDefaultRest;
  late int warmup = widget.entry.warmupSets;
  late int duration = widget.entry.targetDurationSec ?? 30;

  late bool _timed = widget.timed || widget.entry.targetDurationSec != null;
  late String section = widget.entry.section;

  /// 切换「按次数 / 按时间」：记到账号偏好里，并把这个模板动作的目标换成对应的量。
  Future<void> _setTimed(bool timed) async {
    final ex = widget.exercise;
    final repo = ref.read(planRepositoryProvider);
    setState(() => _timed = timed);
    if (ex != null) {
      await ref.read(exercisePrefsRepositoryProvider).setTracking(ex, timed ? TrackingType.duration : ex.repsVariant);
    }
    if (timed) {
      setState(() => duration = widget.entry.targetDurationSec ?? ex?.defaultSeconds ?? 30);
      await repo.updateTemplateExercise(widget.entry.id, targetDurationSec: duration);
    } else {
      setState(() {
        repsMin = ex?.defaultReps ?? repsMin;
        repsMax = ex?.defaultReps ?? repsMax;
      });
      await repo.updateTemplateExercise(widget.entry.id, clearDuration: true, repsMin: repsMin, repsMax: repsMax);
    }
  }

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
            if (widget.exercise?.canSwitchTracking ?? false) ...[
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('按次数')),
                    ButtonSegment(value: true, label: Text('按时间')),
                  ],
                  selected: {_timed},
                  onSelectionChanged: (v) => _setTimed(v.first),
                ),
              ),
              const SizedBox(height: AppSpace.s8),
            ],
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final sec in WorkoutSection.values) ButtonSegment(value: sec.key, label: Text(sec.label)),
                ],
                selected: {section},
                onSelectionChanged: (v) {
                  setState(() => section = v.first);
                  repo.updateTemplateExercise(widget.entry.id, section: v.first);
                },
              ),
            ),
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
            if (!_timed) ...[
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
            ] else
              StepperField(
                label: '每组时长',
                value: duration,
                min: 5,
                max: 3600,
                step: duration >= 120 ? 60 : 5,
                unit: ' 秒',
                onChanged: (v) {
                  setState(() => duration = v);
                  repo.updateTemplateExercise(widget.entry.id, targetDurationSec: v);
                },
              ),
            if (!_timed)
              StepperField(
                label: '热身组',
                value: warmup,
                min: 0,
                max: 10,
                unit: ' 组',
                onChanged: (v) {
                  setState(() => warmup = v);
                  repo.updateTemplateExercise(widget.entry.id, warmupSets: v);
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
        await ref.read(planRepositoryProvider).addTemplateExercise(widget.templateId, exercise.id, exercise: exercise);
        if (context.mounted) context.pop();
      },
    );
  }
}

/// 模板 / 训练里的分区小标题：热身、正式训练、放松。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.section);
  final WorkoutSection section;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.s8, bottom: AppSpace.s8),
      child: Text(section.label, style: AppText.label.copyWith(color: c.text2, fontWeight: FontWeight.w700)),
    );
  }
}
