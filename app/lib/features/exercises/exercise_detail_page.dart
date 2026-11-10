import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/app_ui.dart';
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
///
/// 传入 [editing] 时（看模板 / 首页预览里已有的动作）是同一块设置，但没有「添加动作」，每次改动立刻保存。
class ExerciseDetailPage extends ConsumerWidget {
  const ExerciseDetailPage({super.key, required this.slug, this.onAdd, this.editing});

  final String slug;

  /// 点「添加动作」时调用，带上在详情页里设好的运动量；为空则不显示按钮。
  final Future<void> Function(Exercise exercise, ExerciseDose dose)? onAdd;

  /// 修改已有动作的设置；和 [onAdd] 不会同时用。
  final DoseEditing? editing;

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
          return _Body(exercise: matches.first, onAdd: onAdd, editing: editing);
        },
      ),
    );
  }
}

/// 修改模板（或今天这次训练）里已有动作的设置：详情页里的设置块改一下就保存，不用点按钮。
class DoseEditing {
  const DoseEditing({
    required this.initial,
    required this.onChanged,
    required this.hint,
    this.repsRange = false,
  });

  /// 打开时动作当前的设置。
  final ExerciseDose initial;

  /// 改动后调用：带上改之前和改之后的设置，由调用方只保存变了的几项。
  final Future<void> Function(ExerciseDose previous, ExerciseDose next) onChanged;

  /// 设置块标题下的一行说明，例如「改动自动保存到模板」。
  final String hint;

  /// 模板里这个动作的次数是个范围（如 8–12）时为真：分别调下限和上限，不会被压成一个数。
  final bool repsRange;
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.exercise, this.onAdd, this.editing});
  final Exercise exercise;
  final Future<void> Function(Exercise exercise, ExerciseDose dose)? onAdd;
  final DoseEditing? editing;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  late ExerciseDose _setup = widget.editing?.initial ?? ExerciseDose.initial(widget.exercise);
  bool _adding = false;

  /// 打开时次数是范围就一直按范围显示，调到上下限相等也不会中途换样子。
  late final bool _repsRange = widget.editing?.repsRange ?? false;

  /// 设置有改动：先更新界面，修改已有动作时再立刻保存。
  void _changed(ExerciseDose next) {
    final previous = _setup;
    setState(() => _setup = next);
    widget.editing?.onChanged(previous, next);
  }

  /// 在「按次数 / 按时间」之间切换：和动作库里的开关一样记到账号里，下次这个动作也是这个方式。
  Future<void> _setTimed(bool timed) async {
    final e = widget.exercise;
    _changed(_setup.copyWith(timed: timed));
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
    final editing = widget.editing;
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s4, AppSpace.pageGutter, AppSpace.s32),
      children: [
        if (e.imageCount > 0)
          SizedBox(
            height: 168,
            child: Row(
              children: [
                for (var i = 0; i < e.imageCount; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpace.s8),
                  Expanded(child: ExerciseImage(exercise: e, index: i, radius: AppRadius.md, cacheWidth: 600)),
                ],
              ],
            ),
          ),
        if (onAdd != null || editing != null) ...[
          const SizedBox(height: AppSpace.s16),
          _DosePanel(
            exercise: e,
            dose: _setup,
            onChanged: _changed,
            onTimedChanged: _setTimed,
            editing: editing,
            repsRange: _repsRange,
          ),
        ],
        const SizedBox(height: AppSpace.s24),
        Text(e.nameZh, style: AppText.titleLarge.copyWith(color: c.text)),
        if (e.nameEn != null) ...[
          const SizedBox(height: 2),
          Text(e.nameEn!, style: AppText.label.copyWith(color: c.text3)),
        ],
        const SizedBox(height: AppSpace.s12),
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
        // 添加 / 修改动作时「按次数 / 按时间」已经在上面的设置里，不再重复显示
        if (e.canSwitchTracking && onAdd == null && editing == null) ...[
          const SizedBox(height: AppSpace.s16),
          _TrackingSwitch(exercise: e),
        ],
        if (_dose(e) != null) ...[
          const SizedBox(height: AppSpace.s16),
          _Section(title: '建议量', child: Text(_dose(e)!, style: AppText.body.copyWith(color: c.text))),
        ],
        const SizedBox(height: AppSpace.s16),
        _Section(
          title: '主要肌群',
          child: Text(
            e.primaryMuscles.isEmpty ? '—' : e.primaryMuscles.map(muscleZh).join('、'),
            style: AppText.body.copyWith(color: c.text),
          ),
        ),
        if (e.secondaryMuscles.isNotEmpty) ...[
          const SizedBox(height: AppSpace.s12),
          _Section(
            title: '次要肌群',
            child: Text(
              e.secondaryMuscles.map(muscleZh).join('、'),
              style: AppText.body.copyWith(color: c.text),
            ),
          ),
        ],
        const SizedBox(height: AppSpace.s12),
        _Section(
          title: '动作要领',
          child: Text(
            e.instructionsZh ?? '要领说明会在后续版本补充。',
            style: AppText.body.copyWith(color: e.instructionsZh == null ? c.text3 : c.text, height: 1.7),
          ),
        ),
      ],
    );
    if (onAdd == null) return list;
    // 「添加动作」固定在底部，设置项再长也不用滚到最下面才能点
    return Column(
      children: [
        Expanded(child: list),
        BottomActionBar(
          child: PressScale(
            child: FilledButton.icon(
              onPressed: _adding ? null : _add,
              icon: const Icon(AppIcons.plus, size: 18),
              label: const Text('添加动作'),
              style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size.fromHeight(AppSize.buttonLarge))),
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
  Widget build(BuildContext context) => AppTag(text, color: context.colors.text);
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.caption.copyWith(color: c.text3, fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpace.s8),
          child,
        ],
      ),
    );
  }
}

/// 动作的设置块：放进哪个模块、按次数还是按时间、组数、次数或秒数、负重。
/// 添加动作时叫「加入设置」；修改模板里已有的动作时还多出热身组和组间休息。
class _DosePanel extends StatelessWidget {
  const _DosePanel({
    required this.exercise,
    required this.dose,
    required this.onChanged,
    required this.onTimedChanged,
    this.editing,
    this.repsRange = false,
  });

  final Exercise exercise;
  final ExerciseDose dose;
  final ValueChanged<ExerciseDose> onChanged;
  final ValueChanged<bool> onTimedChanged;
  final DoseEditing? editing;
  final bool repsRange;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final canWeight = exercise.kind == ExerciseKind.strength || dose.weightKg != null;
    final editing = this.editing;
    final isEditing = editing != null;
    return _Section(
      title: isEditing ? '动作设置' : '加入设置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isEditing) ...[
            Text(editing.hint, style: AppText.label.copyWith(color: c.text)),
            const SizedBox(height: AppSpace.s16),
          ],
          Text(isEditing ? '所在模块' : '放进哪个模块', style: AppText.label.copyWith(color: c.text2)),
          const SizedBox(height: AppSpace.s8),
          AppSegmented<WorkoutSection>(
            values: WorkoutSection.values,
            labels: [for (final sec in WorkoutSection.values) sec == WorkoutSection.cooldown ? '拉伸放松' : sec.label],
            selected: dose.section,
            onChanged: (v) => onChanged(dose.copyWith(section: v)),
          ),
          if (exercise.canSwitchTracking) ...[
            const SizedBox(height: AppSpace.s16),
            Text('怎么计量', style: AppText.label.copyWith(color: c.text2)),
            const SizedBox(height: AppSpace.s8),
            AppSegmented<bool>(
              values: const [false, true],
              labels: const ['按数量（次数）', '按时间'],
              selected: dose.timed,
              onChanged: onTimedChanged,
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
          else if (isEditing && repsRange) ...[
            StepperField(
              label: '次数下限',
              value: dose.reps,
              max: 100,
              unit: ' 次',
              onChanged: (v) => onChanged(dose.copyWith(reps: v, repsMax: (dose.repsMax ?? v) < v ? v : null)),
            ),
            StepperField(
              label: '次数上限',
              value: dose.repsMax ?? dose.reps,
              max: 100,
              unit: ' 次',
              onChanged: (v) => onChanged(v < dose.reps ? dose.copyWith(reps: v, repsMax: v) : dose.copyWith(repsMax: v)),
            ),
          ] else
            StepperField(
              label: '每组次数',
              value: dose.reps,
              max: 100,
              unit: ' 次',
              // 修改已有动作时上限跟着一起变，不会留下一个比下限小的上限
              onChanged: (v) => onChanged(dose.copyWith(reps: v, repsMax: isEditing ? v : null)),
            ),
          if (canWeight)
            WeightField(
              value: dose.weightKg,
              onChanged: (v) => onChanged(v == null ? dose.copyWith(clearWeight: true) : dose.copyWith(weightKg: v)),
            ),
          if (isEditing) ...[
            if (!dose.timed)
              StepperField(
                label: '热身组',
                value: dose.warmupSets ?? 0,
                min: 0,
                max: 10,
                unit: ' 组',
                onChanged: (v) => onChanged(dose.copyWith(warmupSets: v)),
              ),
            StepperField(
              label: '组间休息',
              value: dose.restSec ?? 90,
              min: 0,
              max: 600,
              step: 15,
              unit: ' 秒',
              onChanged: (v) => onChanged(dose.copyWith(restSec: v)),
            ),
          ],
          const SizedBox(height: AppSpace.s8),
          Text(
            _summary(exercise, dose, adding: !isEditing),
            style: AppText.caption.copyWith(color: c.text3),
          ),
        ],
      ),
    );
  }
}

String _summary(Exercise e, ExerciseDose d, {required bool adding}) {
  final side = e.perSide ? '，左右各做' : '';
  final load = d.weightKg == null ? '' : '，负重 ${formatWeight(d.weightKg)} kg';
  final upper = d.repsMax;
  final reps = upper != null && upper != d.reps ? '${d.reps}–$upper' : '${d.reps}';
  final amount = d.timed ? '${d.seconds} 秒' : '$reps 次';
  return '${d.sets} 组 × $amount$side$load，${adding ? '放进' : '在'}「${d.section.label}」';
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
          AppSegmented<bool>(
            values: const [false, true],
            labels: const ['按次数', '按时间'],
            selected: timed,
            onChanged: (v) {
              final next = v ? TrackingType.duration : exercise.repsVariant;
              ref.read(exercisePrefsRepositoryProvider).setTracking(exercise, next);
            },
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
