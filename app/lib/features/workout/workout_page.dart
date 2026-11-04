import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/core/notifications/reminder_scheduler.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_image.dart';
import 'package:my_fitness/features/exercises/exercise_prefs.dart';
import 'package:my_fitness/features/workout/number_pad_sheet.dart';
import 'package:my_fitness/features/workout/set_timer.dart';
import 'package:my_fitness/features/workout/workout_math.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

/// 训练进行中：逐组记录、完成后自动开始休息计时。
/// 设计原则：单手操作、大按钮、少输入——新加的组自动带入上次的重量和次数。
class WorkoutPage extends ConsumerWidget {
  const WorkoutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final async = ref.watch(activeWorkoutProvider);
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('训练加载失败', style: AppText.body.copyWith(color: c.danger))),
        data: (view) {
          if (view == null) return const _NoActiveWorkout();
          return _WorkoutBody(view: view);
        },
      ),
    );
  }
}

class _NoActiveWorkout extends StatelessWidget {
  const _NoActiveWorkout();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('没有进行中的训练', style: AppText.titleSmall.copyWith(color: c.text)),
            const SizedBox(height: AppSpace.s16),
            SizedBox(
              width: 200,
              child: PressScale(child: ElevatedButton(onPressed: () => context.go('/today'), child: const Text('回到首页'))),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutBody extends ConsumerWidget {
  const _WorkoutBody({required this.view});
  final WorkoutView view;

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(workoutRepositoryProvider);
    final incomplete = view.exercises.fold<int>(0, (n, b) => n + b.sets.where((s) => !s.completed).length);
    final done = view.exercises.fold<int>(0, (n, b) => n + b.sets.where((s) => s.completed).length);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(done == 0 ? '还没有完成任何一组' : '结束这次训练？'),
        content: Text(done == 0
            ? '现在结束，这次训练不会被保存。'
            : incomplete > 0
                ? '还有 $incomplete 组没完成，结束后会被丢弃。'
                : '已完成全部 $done 组。'),
        actions: [
          PressScale(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('继续练'))),
          if (done == 0)
            PressScale(
              child: TextButton(
                onPressed: () => Navigator.pop(ctx, 'discard'),
                style: TextButton.styleFrom(foregroundColor: context.colors.danger),
                child: const Text('放弃训练'),
              ),
            )
          else
            PressScale(child: TextButton(onPressed: () => Navigator.pop(ctx, 'finish'), child: const Text('结束并保存'))),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    ref.read(restTimerProvider.notifier).skip();
    ref.read(setTimerProvider.notifier).cancel();
    if (choice == 'discard') {
      await repo.discardWorkout(view.workout.id);
      if (context.mounted) context.go('/today');
      return;
    }
    final summary = await repo.finishWorkout(view.workout.id);
    if (!context.mounted) return;
    if (summary == null) {
      context.go('/today');
    } else {
      context.go('/workout/summary', extra: summary);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final byId = ref.watch(exerciseByIdProvider);
    final hasSections = view.exercises.any((b) => b.exercise.section != 'main');
    final totalSets = view.exercises.fold<int>(0, (n, b) => n + b.sets.length);
    final doneSets = view.exercises.fold<int>(0, (n, b) => n + b.sets.where((s) => s.completed).length);

    return Stack(
      children: [
        SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, 240),
            children: [
              _Header(view: view, onFinish: () => _finish(context, ref)),
              const SizedBox(height: AppSpace.s8),
              _ProgressRow(done: doneSets, total: totalSets),
              if (ref.watch(reminderPermissionProvider) == false) const _NotifyHint(),
              const SizedBox(height: AppSpace.s12),
              for (final (i, block) in view.exercises.indexed) ...[
                if (hasSections && (i == 0 || view.exercises[i - 1].exercise.section != block.exercise.section))
                  _SectionLabel(WorkoutSection.fromKey(block.exercise.section)),
                _ExerciseCard(
                  key: ValueKey(block.exercise.id),
                  workoutId: view.workout.id,
                  block: block,
                  exercise: byId[block.exercise.exerciseId],
                ),
                const SizedBox(height: AppSpace.s12),
              ],
              PressScale(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/workout/pick'),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('添加动作'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.button)),
                ),
              ),
              if (view.exercises.isEmpty) ...[
                const SizedBox(height: AppSpace.s24),
                Center(
                  child: Text('从动作库里选第一个动作开始吧',
                      style: AppText.label.copyWith(color: c.text3)),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _Dock(view: view),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ 顶部

class _Header extends StatelessWidget {
  const _Header({required this.view, required this.onFinish});
  final WorkoutView view;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          PressScale(
            scale: PressScale.smallScale,
            child: IconButton(
              tooltip: '收起',
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
              onPressed: () => context.canPop() ? context.pop() : context.go('/today'),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(view.workout.name ?? '自由训练',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.titleSmall.copyWith(color: c.text)),
                _ElapsedAndVolume(view: view),
              ],
            ),
          ),
          PressScale(
            child: TextButton(
              onPressed: onFinish,
              style: TextButton.styleFrom(
                backgroundColor: c.accentSoft,
                foregroundColor: c.accentText,
                minimumSize: const Size(64, 38),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
              ),
              child: const Text('结束'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ElapsedAndVolume extends StatelessWidget {
  const _ElapsedAndVolume({required this.view});
  final WorkoutView view;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
      builder: (context, _) {
        final elapsed = DateTime.now().difference(view.workout.startedAt);
        return Text.rich(
          TextSpan(children: [
            TextSpan(
                text: formatDuration(elapsed.isNegative ? Duration.zero : elapsed),
                style: AppText.numSmall.copyWith(color: c.text)),
            TextSpan(text: '  · 容量 ', style: AppText.label.copyWith(color: c.text2)),
            TextSpan(text: formatWeight(view.volume), style: AppText.numSmall.copyWith(color: c.text)),
            TextSpan(text: ' kg', style: AppText.label.copyWith(color: c.text2)),
          ]),
        );
      },
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 6,
              backgroundColor: c.sunken,
              color: c.accent,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text.rich(TextSpan(children: [
          TextSpan(text: '$done', style: AppText.numSmall.copyWith(color: c.text)),
          TextSpan(text: ' / $total 组', style: AppText.caption.copyWith(color: c.text2, fontSize: 12)),
        ])),
      ],
    );
  }
}

/// 通知权限被拒绝时的提醒：退到后台就收不到计时结束的弹窗了。
class _NotifyHint extends StatelessWidget {
  const _NotifyHint();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.s8),
      child: Row(
        children: [
          Icon(Icons.notifications_off_outlined, size: 16, color: c.text3),
          const SizedBox(width: 6),
          Expanded(
            child: Text('通知权限没开，退到后台或熄屏时不会弹窗提醒。可在手机的系统设置里打开。',
                key: const Key('notify-hint'), style: AppText.caption.copyWith(color: c.text3, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ 动作卡片

class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({super.key, required this.workoutId, required this.block, required this.exercise});

  final String workoutId;
  final ExerciseBlock block;
  final Exercise? exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final repo = ref.read(workoutRepositoryProvider);
    final key = (exerciseId: block.exercise.exerciseId, workoutId: workoutId);
    final last = ref.watch(lastPerformanceProvider(key)).value ?? const <WorkoutSet>[];
    final best = ref.watch(bestBeforeProvider(key)).value ?? ExerciseBest.none;
    final tracking = exercise?.trackingType ?? TrackingType.weightReps;
    final restSec = block.exercise.restSec ?? kDefaultRestSec;

    final hasPr = block.sets.any((s) => detectPr(
          best,
          SetEntry(weightKg: s.weightKg, reps: s.reps, kind: s.kind, completed: s.completed),
        ).isNotEmpty);

    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox.square(
                  dimension: 52,
                  child: exercise == null
                      ? DecoratedBox(
                          decoration: BoxDecoration(color: c.sunken, borderRadius: BorderRadius.circular(12)),
                          child: Icon(Icons.fitness_center, color: c.text3),
                        )
                      : ExerciseImage(exercise: exercise!, radius: 12, cacheWidth: 160),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(exercise?.nameZh ?? '未知动作',
                          style: AppText.titleMedium.copyWith(color: c.text, fontSize: 18)),
                      Text(
                        exercise == null
                            ? ''
                            : '${exercise!.primaryMuscles.map(muscleZh).join('·')} · ${exercise!.equipmentGroup.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.label.copyWith(color: c.text2),
                      ),
                    ],
                  ),
                ),
                if (hasPr) const _PrTag(),
                PressScale(
                  child: PopupMenuButton<String>(
                    tooltip: '动作选项',
                    icon: Icon(Icons.more_horiz_rounded, color: c.text2),
                    onSelected: (v) async {
                      if (v == 'remove') {
                        ref.read(setTimerProvider.notifier).cancel();
                        repo.removeExercise(block.exercise.id);
                      } else if (v == 'time' || v == 'reps') {
                        final ex = exercise;
                        if (ex == null) return;
                        final timed = v == 'time';
                        ref.read(setTimerProvider.notifier).cancel();
                        await ref
                            .read(exercisePrefsRepositoryProvider)
                            .setTracking(ex, timed ? TrackingType.duration : ex.repsVariant);
                        await repo.retargetSets(block.exercise.id,
                            timed: timed, seconds: ex.defaultSeconds, reps: ex.defaultReps);
                      } else if (v.startsWith('section:')) {
                        repo.setSection(block.exercise.id, v.substring(8));
                      }
                    },
                    itemBuilder: (_) => [
                      if (exercise?.canSwitchTracking ?? false)
                        PopupMenuItem(
                          value: exercise!.isTimed ? 'reps' : 'time',
                          child: Text(exercise!.isTimed ? '改为按次数记录' : '改为按时间记录'),
                        ),
                      for (final sec in WorkoutSection.values)
                        if (sec.key != block.exercise.section)
                          PopupMenuItem(value: 'section:${sec.key}', child: Text('移到「${sec.label}」')),
                      const PopupMenuItem(value: 'remove', child: Text('删除这个动作')),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _InfoChip(last.isEmpty ? '上次 · 暂无记录' : '上次 · ${last.map(_setText).join(' · ')}'),
                _InfoChip('休息 $restSec 秒'),
              ],
            ),
            if (block.exercise.note != null && block.exercise.note!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('要点：${block.exercise.note}', style: AppText.label.copyWith(color: c.text2)),
            ],
            const SizedBox(height: 10),
            _SetsHeader(tracking: tracking),
            const SizedBox(height: 4),
            for (var i = 0; i < block.sets.length; i++) ...[
              _SetRow(
                key: ValueKey(block.sets[i].id),
                number: i + 1,
                set: block.sets[i],
                previous: i < last.length ? last[i] : null,
                tracking: tracking,
                restSec: restSec,
                best: best,
                label: '${exercise?.nameZh ?? '动作'} 第 ${i + 1} 组',
                onRemove: () {
                  ref.read(setTimerProvider.notifier).cancel(setId: block.sets[i].id);
                  repo.removeSet(block.sets[i].id);
                },
              ),
              const SizedBox(height: 4),
            ],
            Center(
              child: PressScale(
                child: TextButton.icon(
                  onPressed: () => repo.addSet(block.exercise.id),
                  icon: Icon(Icons.add_rounded, size: 18, color: c.text2),
                  label: Text('添加一组', style: AppText.label.copyWith(color: c.text2)),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _setText(WorkoutSet s) {
    if (s.durationSec != null && s.weightKg == null) return '${s.durationSec}秒';
    final w = formatWeight(s.weightKg);
    return w.isEmpty ? '${s.reps ?? '-'}' : '$w×${s.reps ?? '-'}';
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.sunken, borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(text, style: AppText.caption.copyWith(color: c.text2, fontSize: 12)),
      ),
    );
  }
}

class _PrTag extends StatelessWidget {
  const _PrTag();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(color: c.hero, borderRadius: BorderRadius.circular(AppRadius.xs)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          child: Text('PR', style: AppText.caption.copyWith(color: c.accentText, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 组记录

const _colSet = 34.0;
const _colWeight = 72.0;
const _colReps = 64.0;
const _colCheck = 44.0;
const _colStart = 56.0;

class _SetsHeader extends StatelessWidget {
  const _SetsHeader({required this.tracking});
  final TrackingType tracking;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = AppText.caption.copyWith(color: c.text3, fontSize: 12);
    final isDuration = tracking == TrackingType.duration;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          SizedBox(width: _colSet, child: Center(child: Text('组', style: style))),
          const SizedBox(width: 8),
          Expanded(child: Text('上次', style: style)),
          const SizedBox(width: 8),
          if (!isDuration) ...[
            SizedBox(width: _colWeight, child: Center(child: Text('公斤', style: style))),
            const SizedBox(width: 8),
          ],
          SizedBox(width: _colReps, child: Center(child: Text(isDuration ? '秒' : '次数', style: style))),
          const SizedBox(width: 8),
          if (isDuration) ...[
            SizedBox(width: _colStart, child: Center(child: Text('计时', style: style))),
            const SizedBox(width: 8),
          ],
          SizedBox(width: _colCheck, child: Center(child: Text('完成', style: style))),
        ],
      ),
    );
  }
}

class _SetRow extends ConsumerWidget {
  const _SetRow({
    super.key,
    required this.number,
    required this.set,
    required this.previous,
    required this.tracking,
    required this.restSec,
    required this.best,
    required this.label,
    required this.onRemove,
  });

  final int number;
  final WorkoutSet set;
  final WorkoutSet? previous;
  final TrackingType tracking;
  final int restSec;
  final ExerciseBest best;

  /// 通知文字里用的名称，例如「平板支撑 第 2 组」。
  final String label;
  final VoidCallback onRemove;

  bool get _isDuration => tracking == TrackingType.duration;

  Future<void> _editWeight(BuildContext context, WidgetRef ref) async {
    final v = await showNumberPad(
      context,
      title: '重量',
      unit: 'kg',
      hint: '单位：公斤',
      initial: set.weightKg ?? previous?.weightKg,
      decimal: true,
      steps: const [2.5, 5],
    );
    if (v == null) return;
    await ref.read(workoutRepositoryProvider).updateSet(set.id, weightKg: v);
  }

  Future<void> _editReps(BuildContext context, WidgetRef ref) async {
    final v = await showNumberPad(
      context,
      title: _isDuration ? '时长' : '次数',
      unit: _isDuration ? '秒' : '次',
      hint: _isDuration ? '单位：秒' : '',
      initial: (_isDuration ? set.durationSec : set.reps)?.toDouble() ?? (_isDuration ? previous?.durationSec : previous?.reps)?.toDouble(),
      steps: _isDuration ? const [5, 15] : const [1],
    );
    if (v == null) return;
    final repo = ref.read(workoutRepositoryProvider);
    if (_isDuration) {
      await repo.updateSet(set.id, durationSec: v.round());
    } else {
      await repo.updateSet(set.id, reps: v.round());
    }
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(workoutRepositoryProvider);
    if (set.completed) {
      await repo.setCompleted(set.id, false);
      return;
    }
    final missingReps = _isDuration ? set.durationSec == null : set.reps == null;
    final missingWeight = tracking == TrackingType.weightReps && set.weightKg == null;
    if (missingReps || missingWeight) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(missingWeight ? '先填重量和次数' : '先填次数')));
      return;
    }
    final pr = detectPr(best, SetEntry(weightKg: set.weightKg, reps: set.reps, kind: set.kind, completed: true));
    if (pr.isNotEmpty) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.mediumImpact();
    }
    ref.read(setTimerProvider.notifier).cancel(setId: set.id);
    await repo.setCompleted(set.id, true);
    ref.read(restTimerProvider.notifier).start(restSec);
  }

  void _startTimer(BuildContext context, WidgetRef ref) {
    final seconds = set.durationSec;
    if (seconds == null || seconds <= 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('先设置时长')));
      return;
    }
    HapticFeedback.mediumImpact();
    ref.read(setTimerProvider.notifier).start(
          setId: set.id,
          label: label,
          seconds: seconds,
          restSec: restSec,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final done = set.completed;
    // 这一组正在倒数时才不为空
    final timer = ref.watch(setTimerProvider.select((t) => t?.setId == set.id ? t : null));
    final warm = set.kind == 'warmup';
    final repo = ref.read(workoutRepositoryProvider);
    final cellBg = done ? c.accentSoft : c.sunken;
    final cellFg = done ? c.accentText : c.text;

    Widget cell(String text, VoidCallback onTap, double width, String label) => SizedBox(
          width: width,
          height: AppSize.setCellH,
          child: PressScale(
            scale: PressScale.chipScale,
            child: Semantics(
              button: true,
              label: label,
              child: Material(
                color: cellBg,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: onTap,
                  child: Center(
                    child: Text(text.isEmpty ? '—' : text,
                        style: AppText.numMedium.copyWith(color: text.isEmpty ? c.text3 : cellFg)),
                  ),
                ),
              ),
            ),
          ),
        );

    final weightText = tracking == TrackingType.bodyweightReps && set.weightKg == null ? '自重' : formatWeight(set.weightKg);
    final repsText = _isDuration ? (set.durationSec?.toString() ?? '') : (set.reps?.toString() ?? '');
    final prevText = previous == null
        ? '—'
        : _isDuration
            ? '${previous!.durationSec ?? '-'}秒'
            : (previous!.weightKg == null ? '${previous!.reps ?? '-'}' : '${formatWeight(previous!.weightKg)}×${previous!.reps ?? '-'}');

    return SizedBox(
      height: AppSize.setRow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            SizedBox(
              width: _colSet,
              child: PressScale(
                child: PopupMenuButton<String>(
                  tooltip: '第 $number 组选项',
                  padding: EdgeInsets.zero,
                  onSelected: (v) {
                    if (v == 'remove') {
                      onRemove();
                    } else {
                      repo.updateSet(set.id, kind: v);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'normal', child: Text('正式组')),
                    PopupMenuItem(value: 'warmup', child: Text('热身组')),
                    PopupMenuItem(value: 'drop', child: Text('递减组')),
                    PopupMenuItem(value: 'failure', child: Text('力竭组')),
                    PopupMenuItem(value: 'remove', child: Text('删除这一组')),
                  ],
                  child: Center(
                    child: Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: warm ? c.warmupBg : (done ? c.accent : c.sunken),
                      ),
                      child: Text(
                        warm ? 'W' : '$number',
                        style: AppText.numSmall.copyWith(
                            color: warm ? c.warmupFg : (done ? c.onAccent : c.text2)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(prevText, maxLines: 1, style: AppText.numSmall.copyWith(color: c.text3, fontSize: 16)),
            ),
            const SizedBox(width: 8),
            if (!_isDuration) ...[
              cell(weightText, () => _editWeight(context, ref), _colWeight, '第 $number 组重量'),
              const SizedBox(width: 8),
            ],
            if (timer != null)
              _RunningCell(timer: timer, width: _colReps, label: '第 $number 组倒计时')
            else
              cell(repsText, () => _editReps(context, ref), _colReps, '第 $number 组${_isDuration ? '时长' : '次数'}'),
            const SizedBox(width: 8),
            if (_isDuration) ...[
              _TimerButton(
                width: _colStart,
                running: timer != null,
                done: done,
                onStart: () => _startTimer(context, ref),
                onStop: () => ref.read(setTimerProvider.notifier).cancel(setId: set.id),
              ),
              const SizedBox(width: 8),
            ],
            SizedBox(
              width: _colCheck,
              height: AppSize.setCheck,
              child: PressScale(
                scale: PressScale.smallScale,
                child: Semantics(
                  button: true,
                  label: done ? '取消完成第 $number 组' : '完成第 $number 组',
                  child: Material(
                    color: done ? c.accent : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: done ? BorderSide.none : BorderSide(color: c.line, width: 1.5),
                    ),
                    child: InkWell(
                      customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onTap: () => _toggle(context, ref),
                      child: Icon(Icons.check_rounded, color: done ? c.onAccent : c.text3),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 倒数中的时间格：时间固定不可再调，读秒递减，归零显示「完成」。
class _RunningCell extends ConsumerWidget {
  const _RunningCell({required this.timer, required this.width, required this.label});
  final SetTimerState timer;
  final double width;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final clock = ref.read(clockProvider);
    return SizedBox(
      width: width,
      height: AppSize.setCellH,
      child: DecoratedBox(
        decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(AppRadius.sm)),
        child: StreamBuilder<int>(
          stream: Stream.periodic(const Duration(milliseconds: 250), (i) => i),
          builder: (context, _) {
            final left = timer.remainingSec(clock());
            return Semantics(
              label: label,
              child: Center(
                child: Text(left == 0 ? '完成' : '$left',
                    key: const Key('set-timer-remaining'),
                    style: AppText.numMedium.copyWith(color: c.onAccent)),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 「开始 / 停止 / 完成」按钮：放在时间格和打勾之间。
class _TimerButton extends StatelessWidget {
  const _TimerButton({
    required this.width,
    required this.running,
    required this.done,
    required this.onStart,
    required this.onStop,
  });
  final double width;
  final bool running;
  final bool done;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = done ? '完成' : (running ? '停止' : '开始');
    final VoidCallback? onTap = done ? null : (running ? onStop : onStart);
    return SizedBox(
      width: width,
      height: AppSize.setCellH,
      child: PressScale(
        scale: PressScale.chipScale,
        child: Material(
          color: done ? Colors.transparent : (running ? c.sunken : c.accentSoft),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: onTap,
            child: Center(
              child: Text(text,
                  key: Key('set-timer-button-$text'),
                  style: AppText.label.copyWith(
                    color: done ? c.text3 : (running ? c.text2 : c.accentText),
                    fontWeight: FontWeight.w700,
                  )),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 底部休息坞

class _Dock extends ConsumerStatefulWidget {
  const _Dock({required this.view});
  final WorkoutView view;

  @override
  ConsumerState<_Dock> createState() => _DockState();
}

class _DockState extends ConsumerState<_Dock> {
  DateTime? _alertedFor; // 已提醒过的休息结束时刻，避免重复震动

  /// 下一组：按动作顺序找第一个没完成的组。
  ({ExerciseBlock block, WorkoutSet set, int number})? _nextSet() {
    for (final b in widget.view.exercises) {
      for (var i = 0; i < b.sets.length; i++) {
        if (!b.sets[i].completed) return (block: b, set: b.sets[i], number: i + 1);
      }
    }
    return null;
  }

  Future<void> _completeNext() async {
    final next = _nextSet();
    if (next == null) {
      context.push('/workout/pick');
      return;
    }
    final repo = ref.read(workoutRepositoryProvider);
    final s = next.set;
    final ex = ref.read(exerciseByIdProvider)[next.block.exercise.exerciseId];
    final tracking = ex?.trackingType ?? TrackingType.weightReps;
    final isDuration = tracking == TrackingType.duration;
    final missingReps = isDuration ? s.durationSec == null : s.reps == null;
    final missingWeight = tracking == TrackingType.weightReps && s.weightKg == null;
    if (missingReps || missingWeight) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('先填第 ${next.number} 组的${missingWeight ? '重量和次数' : '次数'}')));
      return;
    }
    final best = await ref.read(bestBeforeProvider(
            (exerciseId: next.block.exercise.exerciseId, workoutId: widget.view.workout.id))
        .future);
    final pr = detectPr(best, SetEntry(weightKg: s.weightKg, reps: s.reps, kind: s.kind, completed: true));
    pr.isNotEmpty ? HapticFeedback.heavyImpact() : HapticFeedback.mediumImpact();
    ref.read(setTimerProvider.notifier).cancel(setId: s.id);
    await repo.setCompleted(s.id, true);
    ref.read(restTimerProvider.notifier).start(next.block.exercise.restSec ?? kDefaultRestSec);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rest = ref.watch(restTimerProvider);
    final next = _nextSet();
    final label = next == null ? '添加动作' : '完成第 ${next.number} 组';

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.26],
          colors: [c.bg.withValues(alpha: 0), c.bg],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 28, 12, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(color: c.hero, borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (rest == null)
                    SizedBox(
                      height: 36,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text('完成一组后自动开始组间休息',
                              style: AppText.label.copyWith(color: c.onHero2)),
                        ),
                      ),
                    )
                  else
                    StreamBuilder<int>(
                      stream: Stream.periodic(const Duration(milliseconds: 250), (i) => i),
                      builder: (context, _) {
                        final left = rest.remainingSec(ref.read(clockProvider)());
                        if (left == 0 && _alertedFor != rest.endsAt) {
                          _alertedFor = rest.endsAt;
                          HapticFeedback.vibrate();
                        }
                        return _RestRow(rest: rest, left: left);
                      },
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: AppSize.buttonLarge,
                    child: PressScale(
                      child: FilledButton.icon(
                        onPressed: _completeNext,
                        icon: Icon(next == null ? Icons.add_rounded : Icons.check_rounded),
                        label: Text(label),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(AppSize.buttonLarge),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          textStyle: AppText.button.copyWith(fontSize: 17),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RestRow extends ConsumerWidget {
  const _RestRow({required this.rest, required this.left});
  final RestState rest;
  final int left;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final notifier = ref.read(restTimerProvider.notifier);
    final over = left == 0;
    final pct = rest.totalSec == 0 ? 0.0 : (left / rest.totalSec).clamp(0.0, 1.0);

    Widget chip(String text, VoidCallback onTap, {bool numeric = true}) => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: PressScale(
            scale: PressScale.chipScale,
            child: Material(
              color: c.hero2,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onTap,
                child: SizedBox(
                  height: 36,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      child: Text(text,
                          style: (numeric ? AppText.numSmall : AppText.label.copyWith(fontWeight: FontWeight.w600))
                              .copyWith(color: c.onHero)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    return Column(
      children: [
        SizedBox(
          height: 36,
          child: Row(
            children: [
              const SizedBox(width: 6),
              if (over)
                Text('休息结束，开始下一组', style: AppText.body.copyWith(color: c.onHero2, fontSize: 14))
              else ...[
                Text('组间休息', style: AppText.label.copyWith(color: c.onHero2)),
                const SizedBox(width: 10),
                Text(formatDuration(Duration(seconds: left)),
                    key: const Key('rest-remaining'),
                    style: AppText.numLarge.copyWith(color: c.onHero, fontSize: 30, height: 1)),
              ],
              const Spacer(),
              if (!over) ...[
                chip('−15', () => notifier.adjust(-15)),
                chip('+15', () => notifier.adjust(15)),
              ],
              chip(over ? '关闭' : '跳过', notifier.skip, numeric: false),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: over ? 0 : pct,
            minHeight: 4,
            backgroundColor: c.hero2,
            color: c.accent,
          ),
        ),
      ],
    );
  }
}

/// 训练页的分区小标题：热身、正式训练、放松。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.section);
  final WorkoutSection section;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.s8),
      child: Text(section.label, style: AppText.label.copyWith(color: c.text2, fontWeight: FontWeight.w700)),
    );
  }
}
