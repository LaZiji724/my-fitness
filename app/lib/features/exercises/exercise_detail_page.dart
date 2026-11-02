import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_image.dart';
import 'package:my_fitness/features/exercises/exercise_prefs.dart';
import 'package:my_fitness/features/exercises/exercise_repository.dart';

/// 动作详情：起止两张图、基本信息、目标肌群、要领。
/// 历史记录与进步曲线在训练记录（M3）和数据（M5）完成后接入。
class ExerciseDetailPage extends ConsumerWidget {
  const ExerciseDetailPage({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final async = ref.watch(exercisesProvider);
    return Scaffold(
      appBar: AppBar(),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text('动作库加载失败', style: AppText.body.copyWith(color: c.danger))),
        data: (all) {
          final matches = all.where((e) => e.slug == slug);
          if (matches.isEmpty) {
            return Center(child: Text('找不到这个动作', style: AppText.body.copyWith(color: c.text2)));
          }
          return _Body(exercise: matches.first);
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.exercise});
  final Exercise exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final e = exercise;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, 0, AppSpace.pageGutter, AppSpace.s32),
      children: [
        if (e.imageCount > 0)
          SizedBox(
            height: 160,
            child: Row(
              children: [
                for (var i = 0; i < e.imageCount; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpace.s8),
                  Expanded(child: ExerciseImage(exercise: e, index: i, radius: AppRadius.md, cacheWidth: 600)),
                ],
              ],
            ),
          ),
        const SizedBox(height: AppSpace.s16),
        Text(e.nameZh, style: AppText.titleLarge.copyWith(color: c.text)),
        if (e.nameEn != null) ...[
          const SizedBox(height: AppSpace.s4),
          Text(e.nameEn!, style: AppText.label.copyWith(color: c.text3)),
        ],
        const SizedBox(height: AppSpace.s16),
        Wrap(
          spacing: AppSpace.s8,
          runSpacing: AppSpace.s8,
          children: [
            if (e.kind != ExerciseKind.strength) _Tag(e.kind.label),
            if (e.region != null) _Tag(e.region!.label),
            _Tag(e.bodyPart.label),
            _Tag(e.equipmentGroup.label),
            if (e.perSide) const _Tag('左右各做'),
          ],
        ),
        if (e.canSwitchTracking) ...[
          const SizedBox(height: AppSpace.s16),
          _TrackingSwitch(exercise: e),
        ],
        if (_dose(e) != null) ...[
          const SizedBox(height: AppSpace.s16),
          _Section(title: '建议量', child: Text(_dose(e)!, style: AppText.body.copyWith(color: c.text))),
        ],
        const SizedBox(height: AppSpace.s24),
        _Section(
          title: '主要肌群',
          child: Text(
            e.primaryMuscles.isEmpty ? '—' : e.primaryMuscles.map(muscleZh).join('、'),
            style: AppText.body.copyWith(color: c.text),
          ),
        ),
        if (e.secondaryMuscles.isNotEmpty) ...[
          const SizedBox(height: AppSpace.s16),
          _Section(
            title: '次要肌群',
            child: Text(
              e.secondaryMuscles.map(muscleZh).join('、'),
              style: AppText.body.copyWith(color: c.text),
            ),
          ),
        ],
        const SizedBox(height: AppSpace.s16),
        _Section(
          title: '动作要领',
          child: Text(
            e.instructionsZh ?? '要领说明会在后续版本补充。',
            style: AppText.body.copyWith(color: e.instructionsZh == null ? c.text3 : c.text),
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.sunken, borderRadius: BorderRadius.circular(AppRadius.full)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(text, style: AppText.label.copyWith(color: c.text)),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, borderRadius: AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppText.label.copyWith(color: c.text2)),
            const SizedBox(height: AppSpace.s8),
            child,
          ],
        ),
      ),
    );
  }
}


/// 建议量文案：「2 组 × 30 秒（每侧）」。没有建议量时返回 null。
String? _dose(Exercise e) {
  final sets = e.defaultSets;
  final amount = e.isTimed
      ? (e.defaultSeconds == null ? null : '${e.defaultSeconds} 秒')
      : (e.defaultReps == null ? null : '${e.defaultReps} 次');
  if (sets == null && amount == null) return null;
  final parts = [
    if (sets != null) '$sets 组',
    ?amount,
  ];
  return parts.join(' × ') + (e.perSide ? '（每侧）' : '');
}

/// 「按次数 / 按时间」切换：每个动作都能选，选择会记在账号里并同步到其他设备。
class _TrackingSwitch extends ConsumerWidget {
  const _TrackingSwitch({required this.exercise});
  final Exercise exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final timed = exercise.isTimed;
    return _Section(
      title: '记录方式',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('按次数')),
                ButtonSegment(value: true, label: Text('按时间')),
              ],
              selected: {timed},
              onSelectionChanged: (v) {
                final next = v.first ? TrackingType.duration : exercise.repsVariant;
                ref.read(exercisePrefsRepositoryProvider).setTracking(exercise, next);
              },
            ),
          ),
          const SizedBox(height: AppSpace.s8),
          Text(
            timed ? '训练时每组记录坚持的秒数' : '训练时每组记录完成的次数',
            style: AppText.caption.copyWith(color: c.text3),
          ),
        ],
      ),
    );
  }
}
