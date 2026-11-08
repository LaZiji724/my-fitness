import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_image.dart';
import 'package:my_fitness/features/exercises/exercise_prefs.dart';
import 'package:my_fitness/features/exercises/exercise_repository.dart';
import 'package:my_fitness/features/plan/plan_widgets.dart' show StepperField, WeightField;
import 'package:my_fitness/features/workout/workout_math.dart' show formatWeight;

/// 动作详情：起止两张图、基本信息、目标肌群、要领。
/// 历史记录与进步曲线在训练记录（M3）和数据（M5）完成后接入。
///
/// 传入 [onAdd] 时（给模板 / 当前训练挑动作）图片下方多一块「加入设置」和「添加动作」按钮：
/// 可以改放进哪个模块（热身 / 正式训练 / 拉伸放松）、按次数还是按时间、组数、次数或秒数、负重，点了按钮才真正加入。
class ExerciseDetailPage extends ConsumerWidget {
  const ExerciseDetailPage({super.key, required this.slug, this.onAdd});

  final String slug;

  /// 点「添加动作」时调用，带上在详情页里设好的运动量；为空则不显示按钮。
  final Future<void> Function(Exercise exercise, ExerciseDose dose)? onAdd;

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
          return _Body(exercise: matches.first, onAdd: onAdd);
        },
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.exercise, this.onAdd});
  final Exercise exercise;
  final Future<void> Function(Exercise exercise, ExerciseDose dose)? onAdd;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  late ExerciseDose _setup = ExerciseDose.initial(widget.exercise);
  bool _adding = false;

  /// 在「按次数 / 按时间」之间切换：和动作库里的开关一样记到账号里，下次这个动作也是这个方式。
  Future<void> _setTimed(bool timed) async {
    final e = widget.exercise;
    setState(() => _setup = _setup.copyWith(timed: timed));
    await ref.read(exercisePrefsRepositoryProvider).setTracking(e, timed ? TrackingType.duration : e.repsVariant);
  }

  Future<void> _add() async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      await widget.onAdd!(widget.exercise, _setup);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = widget.exercise;
    final onAdd = widget.onAdd;
    final list = ListView(
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
        if (onAdd != null) ...[
          const SizedBox(height: AppSpace.s16),
          _DosePanel(
            exercise: e,
            dose: _setup,
            onChanged: (d) => setState(() => _setup = d),
            onTimedChanged: _setTimed,
          ),
        ],
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
        // 添加动作时「按次数 / 按时间」已经在上面的加入设置里，不再重复显示
        if (e.canSwitchTracking && onAdd == null) ...[
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
    if (onAdd == null) return list;
    // 「添加动作」固定在底部，设置项再长也不用滚到最下面才能点
    return Column(
      children: [
        Expanded(child: list),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, AppSpace.s12),
            child: PressScale(
              child: FilledButton.icon(
                onPressed: _adding ? null : _add,
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加动作'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.button)),
              ),
            ),
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


/// 添加动作时的「加入设置」：放进哪个模块、按次数还是按时间、组数、次数或秒数、负重。
class _DosePanel extends StatelessWidget {
  const _DosePanel({
    required this.exercise,
    required this.dose,
    required this.onChanged,
    required this.onTimedChanged,
  });

  final Exercise exercise;
  final ExerciseDose dose;
  final ValueChanged<ExerciseDose> onChanged;
  final ValueChanged<bool> onTimedChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final canWeight = exercise.kind == ExerciseKind.strength;
    return _Section(
      title: '加入设置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('放进哪个模块', style: AppText.body.copyWith(color: c.text)),
          const SizedBox(height: AppSpace.s8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<WorkoutSection>(
              showSelectedIcon: false,
              segments: [
                for (final sec in WorkoutSection.values)
                  ButtonSegment(value: sec, label: Text(sec == WorkoutSection.cooldown ? '拉伸放松' : sec.label)),
              ],
              selected: {dose.section},
              onSelectionChanged: (v) => onChanged(dose.copyWith(section: v.first)),
            ),
          ),
          if (exercise.canSwitchTracking) ...[
            const SizedBox(height: AppSpace.s16),
            Text('怎么计量', style: AppText.body.copyWith(color: c.text)),
            const SizedBox(height: AppSpace.s8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('按数量（次数）')),
                  ButtonSegment(value: true, label: Text('按时间')),
                ],
                selected: {dose.timed},
                onSelectionChanged: (v) => onTimedChanged(v.first),
              ),
            ),
          ],
          const SizedBox(height: AppSpace.s8),
          StepperField(
            label: '组数',
            value: dose.sets,
            max: 20,
            unit: ' 组',
            onChanged: (v) => onChanged(dose.copyWith(sets: v)),
          ),
          if (dose.timed)
            StepperField(
              label: '每组时间',
              value: dose.seconds,
              min: 5,
              max: 3600,
              step: dose.seconds >= 120 ? 60 : 5,
              unit: ' 秒',
              onChanged: (v) => onChanged(dose.copyWith(seconds: v)),
            )
          else
            StepperField(
              label: '每组次数',
              value: dose.reps,
              max: 100,
              unit: ' 次',
              onChanged: (v) => onChanged(dose.copyWith(reps: v)),
            ),
          if (canWeight)
            WeightField(
              value: dose.weightKg,
              onChanged: (v) => onChanged(v == null ? dose.copyWith(clearWeight: true) : dose.copyWith(weightKg: v)),
            ),
          Text(
            _summary(exercise, dose),
            style: AppText.caption.copyWith(color: c.text3),
          ),
        ],
      ),
    );
  }
}

String _summary(Exercise e, ExerciseDose d) {
  final side = e.perSide ? '，左右各做' : '';
  final load = d.weightKg == null ? '' : '，负重 ${formatWeight(d.weightKg)} kg';
  final amount = d.timed ? '${d.seconds} 秒' : '${d.reps} 次';
  return '${d.sets} 组 × $amount$side$load · 放进「${d.section.label}」';
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
