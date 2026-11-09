import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_detail_page.dart';
import 'package:my_fitness/features/exercises/exercise_image.dart';
import 'package:my_fitness/features/exercises/exercise_repository.dart';
import 'package:my_fitness/features/exercises/exercises_page.dart';
import 'package:my_fitness/features/plan/plan_estimate.dart';
import 'package:my_fitness/features/plan/plan_providers.dart';
import 'package:my_fitness/features/plan/plan_repository.dart' show PlanRepository, TemplateView, sortedBySection;
import 'package:my_fitness/features/plan/today_overrides.dart';
import 'package:my_fitness/features/exercises/exercise_prefs.dart';
import 'package:my_fitness/features/plan/plan_widgets.dart';
import 'package:my_fitness/features/workout/workout_math.dart' show formatWeight;
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
  final load = e.targetWeightKg == null ? '' : ' · ${formatWeight(e.targetWeightKg)} kg';
  return '${e.targetSets} 组$target$load$warm · 休息 ${e.restSec ?? kTemplateDefaultRest} 秒';
}

/// 编辑模板：改名、调整每个动作的组数/次数/休息，直接用它开始训练。
class TemplateEditPage extends ConsumerStatefulWidget {
  const TemplateEditPage({super.key, required this.templateId});
  final String templateId;

  @override
  ConsumerState<TemplateEditPage> createState() => _TemplateEditPageState();
}

class _TemplateEditPageState extends ConsumerState<TemplateEditPage> {
  String get templateId => widget.templateId;

  @override
  void initState() {
    super.initState();
    // 每次进入模板编辑都从默认的部位 / 器械开始；
    // 编辑期间连续「添加动作」则一直停在上次选的部位和标签（选动作页自己不重置）。
    Future.microtask(() {
      if (mounted) ref.read(exerciseFilterProvider.notifier).reset();
    });
  }

  @override
  Widget build(BuildContext context) {
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
          PressScale(
            child: PopupMenuButton<String>(
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
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, 0),
            sliver: SliverList.list(children: [
              if (view.exercises.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpace.s8),
                  child: EmptyCard(title: '还没有动作', hint: '点下面的「添加动作」从动作库里选'),
                ),
              if (view.exercises.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.s8),
                  child: Text('长按动作卡片，上下拖动就能排序。', style: AppText.label.copyWith(color: c.text2)),
                ),
            ]),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageGutter),
            sliver: ReorderableExerciseSliver(
              entries: view.exercises,
              onReorder: (order) => repo.reorderTemplateExercises(templateId, order),
              cardBuilder: (e) => TemplateExerciseCard(
                entry: e,
                exercise: byId[e.exerciseId],
                onOpen: () => context.push('/template/$templateId/exercise/${e.id}'),
                onEdit: () => showDoseSheet(
                  context,
                  entry: e,
                  exercise: byId[e.exerciseId],
                  update: templateDoseUpdater(repo, e.id),
                ),
                onRemove: () => repo.removeTemplateExercise(e.id),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, 0, AppSpace.pageGutter, 160),
            sliver: SliverToBoxAdapter(
              child: PressScale(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/template/$templateId/pick'),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('添加动作'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.button)),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, AppSpace.s12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EstimateHint(label: estimateLabel(view.exercises, byId)),
              PressScale(
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
            ],
          ),
        ),
      ),
    );
  }
}

/// 拖动排好后的一个位置：哪个动作、落在哪个分区（热身 / 正式训练 / 放松）。
typedef ExerciseSlot = ({String id, String section});

/// 模板 / 首页预览里的动作列表（放在 CustomScrollView 里）：分区标题 + 动作卡片，
/// 长按卡片就能拖动排序，拖过分区标题就换到那个分区。
///
/// 松手后先在本地立刻排好（动画不回弹），再通过 [onReorder] 交给调用方保存。
class ReorderableExerciseSliver extends StatefulWidget {
  const ReorderableExerciseSliver({super.key, required this.entries, required this.cardBuilder, required this.onReorder});
  final List<TemplateExercise> entries;
  final Widget Function(TemplateExercise) cardBuilder;
  final void Function(List<ExerciseSlot> order) onReorder;

  @override
  State<ReorderableExerciseSliver> createState() => _ReorderableExerciseSliverState();
}

/// 列表里的一行：分区标题或动作卡片。
class _Row {
  const _Row.header(this.section) : entry = null;
  const _Row.card(TemplateExercise this.entry) : section = null;
  final String? section;
  final TemplateExercise? entry;
}

class _ReorderableExerciseSliverState extends State<ReorderableExerciseSliver> {
  late List<_Row> _rows = _build(widget.entries);

  static List<_Row> _build(List<TemplateExercise> entries) {
    final sorted = sortedBySection(entries, (e) => e.section, (e) => e.position);
    final hasSections = entries.any((x) => x.section != 'main');
    return [
      for (final (i, e) in sorted.indexed) ...[
        if (hasSections && (i == 0 || sorted[i - 1].section != e.section)) _Row.header(e.section),
        _Row.card(e),
      ],
    ];
  }

  @override
  void didUpdateWidget(ReorderableExerciseSliver old) {
    super.didUpdateWidget(old);
    // 数据真的变了（改了运动量、删了动作、云端同步）才重排；只是重建界面时保留刚拖好的顺序
    if (!listEquals(old.entries, widget.entries)) _rows = _build(widget.entries);
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex == oldIndex) return; // onReorderItem 已经按「先拿掉再插入」修正过下标
    final rows = [..._rows];
    rows.insert(newIndex, rows.removeAt(oldIndex));

    // 每张卡片属于它上面最近的分区标题；拖到第一个标题上面就归第一个分区
    var section = rows.firstWhere((r) => r.section != null, orElse: () => const _Row.header('main')).section!;
    final order = <ExerciseSlot>[];
    for (final r in rows) {
      if (r.section != null) {
        section = r.section!;
      } else {
        order.add((id: r.entry!.id, section: section));
      }
    }
    setState(() => _rows = rows);
    widget.onReorder(order);
  }

  Widget _proxy(Widget child, int index, Animation<double> animation) => AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(animation.value);
          return Transform.scale(
            scale: 1 + 0.03 * t,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: AppRadius.card,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22 * t), blurRadius: 16 * t, offset: Offset(0, 6 * t))],
              ),
              child: child,
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    return SliverReorderableList(
      itemCount: _rows.length,
      onReorderStart: (_) => HapticFeedback.mediumImpact(),
      onReorderEnd: (_) => HapticFeedback.lightImpact(),
      onReorderItem: _onReorder,
      proxyDecorator: _proxy,
      itemBuilder: (context, i) {
        final r = _rows[i];
        final e = r.entry;
        if (e == null) {
          // 分区标题不能拖，但可以被卡片挤开 / 作为落点
          return _SectionLabel(WorkoutSection.fromKey(r.section!), key: ValueKey('section-${r.section}'));
        }
        return ReorderableDelayedDragStartListener(
          key: ValueKey('exercise-${e.id}'),
          index: i,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.s8),
            child: widget.cardBuilder(e),
          ),
        );
      },
    );
  }
}

/// 小铅笔图标（SVG 线条风格），颜色跟随主题。
class PencilIcon extends StatelessWidget {
  const PencilIcon({super.key, required this.color, this.size = 20});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hex = (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#$hex" '
      'stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M17 3a2.828 2.828 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3z"/></svg>',
      width: size,
      height: size,
    );
  }
}

/// 动作卡片：点卡片看动作详情（和动作库里一样）；右侧小笔改运动量；[onRemove] 不为空时再显示 ✕。
class TemplateExerciseCard extends StatelessWidget {
  const TemplateExerciseCard({
    super.key,
    required this.entry,
    required this.exercise,
    required this.onEdit,
    this.onOpen,
    this.onRemove,
  });
  final TemplateExercise entry;
  final Exercise? exercise;
  final VoidCallback onEdit;

  /// 点卡片本体：打开可以直接改设置的动作详情；不传就只看普通的动作详情。
  final VoidCallback? onOpen;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ex = exercise;
    final name = ex?.nameZh ?? '未知动作';
    return PressScale(
      scale: PressScale.cardScale,
      child: Material(
        color: c.surface,
        borderRadius: AppRadius.card,
        child: InkWell(
          borderRadius: AppRadius.card,
          onTap: ex == null ? null : (onOpen ?? () => context.push('/exercise/${ex.slug}')),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.s12),
            child: Row(
              children: [
                SizedBox(
                  width: AppSize.exerciseThumb,
                  child: ex == null ? const SizedBox.shrink() : ExerciseImage(exercise: ex, cacheWidth: 160, radius: AppRadius.md - 4),
                ),
                const SizedBox(width: AppSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: AppText.body.copyWith(color: c.text, fontWeight: FontWeight.w600)),
                      Text(describeTemplateExercise(entry), style: AppText.label.copyWith(color: c.text2)),
                    ],
                  ),
                ),
                PressScale(
                  scale: PressScale.smallScale,
                  child: IconButton(
                    tooltip: '编辑 $name',
                    onPressed: onEdit,
                    icon: PencilIcon(color: c.text2),
                  ),
                ),
                if (onRemove != null)
                  PressScale(
                    scale: PressScale.smallScale,
                    child: IconButton(
                      tooltip: '移除动作',
                      onPressed: onRemove,
                      icon: Icon(Icons.close_rounded, color: c.text3),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 改运动量时把「改了哪几项」交给调用方保存：模板页写进模板，首页预览只记到今天这次训练。
typedef DoseUpdater = Future<void> Function({
  int? targetSets,
  int? repsMin,
  int? repsMax,
  int? restSec,
  int? warmupSets,
  int? targetDurationSec,
  bool clearDuration,
  String? section,
  double? targetWeightKg,
  bool clearWeight,
});

/// 模板页的保存方式：改了哪几项就写进模板里的这个动作。
DoseUpdater templateDoseUpdater(PlanRepository repo, String entryId) => ({
      targetSets,
      repsMin,
      repsMax,
      restSec,
      warmupSets,
      targetDurationSec,
      clearDuration = false,
      section,
      targetWeightKg,
      clearWeight = false,
    }) =>
        repo.updateTemplateExercise(entryId,
            targetSets: targetSets,
            repsMin: repsMin,
            repsMax: repsMax,
            restSec: restSec,
            warmupSets: warmupSets,
            targetDurationSec: targetDurationSec,
            clearDuration: clearDuration,
            section: section,
            targetWeightKg: targetWeightKg,
            clearWeight: clearWeight);

/// 首页预览的保存方式：改动只记到今天这次训练（本机、当天有效），不动模板。
DoseUpdater todayDoseUpdater(TodayOverridesRepository repo, DateTime today, String templateId, String entryId) => ({
      targetSets,
      repsMin,
      repsMax,
      restSec,
      warmupSets,
      targetDurationSec,
      clearDuration = false,
      section,
      targetWeightKg,
      clearWeight = false,
    }) =>
        repo.save(
          today,
          templateId,
          entryId,
          DoseOverride(
            targetSets: targetSets,
            repsMin: repsMin,
            repsMax: repsMax,
            restSec: restSec,
            warmupSets: warmupSets,
            targetDurationSec: targetDurationSec,
            clearDuration: clearDuration,
            section: section,
            targetWeightKg: targetWeightKg,
            clearWeight: clearWeight,
          ),
        );

/// 动作详情里的设置改了之后，把「前后差别」换成「改了哪几项」交给 [update] 保存，没动的项不会被覆盖
/// （比如次数范围 8–12 只要没碰次数就保持原样）。
Future<void> saveDoseChange(DoseUpdater update, ExerciseDose before, ExerciseDose after) async {
  if (after.section != before.section) await update(section: after.section.key);
  if (after.sets != before.sets) await update(targetSets: after.sets);
  if (after.timed != before.timed) {
    if (after.timed) {
      await update(targetDurationSec: after.seconds);
    } else {
      await update(clearDuration: true, repsMin: after.reps, repsMax: after.repsMax ?? after.reps);
    }
  } else if (after.timed) {
    if (after.seconds != before.seconds) await update(targetDurationSec: after.seconds);
  } else if (after.reps != before.reps || after.repsMax != before.repsMax) {
    await update(repsMin: after.reps, repsMax: after.repsMax ?? after.reps);
  }
  if (after.weightKg != before.weightKg) {
    await (after.weightKg == null ? update(clearWeight: true) : update(targetWeightKg: after.weightKg));
  }
  final warmup = after.warmupSets;
  if (warmup != null && warmup != before.warmupSets) await update(warmupSets: warmup);
  final rest = after.restSec;
  if (rest != null && rest != before.restSec) await update(restSec: rest);
}

/// 点模板页 / 首页预览里的动作卡片打开的详情：和「添加动作」页是同一块设置，只是没有「添加动作」按钮，
/// 改动马上保存（模板页写进模板，首页预览只记到今天这次训练）。
class TemplateEntryDetailPage extends ConsumerWidget {
  const TemplateEntryDetailPage({super.key, required this.entryId, this.templateId, this.todayOnly = false});

  final String entryId;

  /// 模板页打开时是这个模板的 id；首页预览打开（[todayOnly]）时不用传。
  final String? templateId;
  final bool todayOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final byId = ref.watch(exerciseByIdProvider);
    final TemplateView? view;
    String? baseTemplateId = templateId;
    if (todayOnly) {
      view = ref.watch(todayEffectiveTemplateProvider);
      baseTemplateId = ref.watch(todayPlanProvider)?.template?.template.id;
    } else {
      view = ref.watch(templatesProvider).value?.where((t) => t.template.id == templateId).firstOrNull;
    }
    final entry = view?.exercises.where((e) => e.id == entryId).firstOrNull;
    final ex = entry == null ? null : byId[entry.exerciseId];
    if (entry == null || ex == null || baseTemplateId == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('找不到这个动作', style: AppText.body.copyWith(color: c.text2))),
      );
    }

    final DoseUpdater update;
    if (todayOnly) {
      final repo = ref.watch(todayOverridesRepositoryProvider);
      final today = ref.watch(todayProvider);
      update = todayDoseUpdater(repo, today, baseTemplateId, entryId);
    } else {
      update = templateDoseUpdater(ref.watch(planRepositoryProvider), entryId);
    }

    final reps = entry.repsMin ?? entry.repsMax ?? ex.defaultReps ?? 10;
    return ExerciseDetailPage(
      slug: ex.slug,
      editing: DoseEditing(
        initial: ExerciseDose(
          section: WorkoutSection.fromKey(entry.section),
          timed: ex.isTimed || entry.targetDurationSec != null,
          sets: entry.targetSets,
          reps: reps,
          repsMax: entry.repsMax ?? reps,
          seconds: entry.targetDurationSec ?? ex.defaultSeconds ?? 30,
          weightKg: entry.targetWeightKg,
          restSec: entry.restSec ?? kTemplateDefaultRest,
          warmupSets: entry.warmupSets,
        ),
        repsRange: entry.repsMin != null && entry.repsMax != null && entry.repsMin != entry.repsMax,
        hint: todayOnly ? '只改今天这次训练，不会改动模板' : '改动自动保存到模板',
        onChanged: (before, after) => saveDoseChange(update, before, after),
      ),
    );
  }
}

/// 弹出运动量编辑面板。[todayOnly] 为真时是首页预览里的「只改今天」模式。
Future<void> showDoseSheet(
  BuildContext context, {
  required TemplateExercise entry,
  required Exercise? exercise,
  required DoseUpdater update,
  bool todayOnly = false,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ConfigSheet(
        entry: entry,
        name: exercise?.nameZh ?? '动作',
        timed: exercise?.trackingType == TrackingType.duration,
        exercise: exercise,
        update: update,
        todayOnly: todayOnly,
      ),
    );

class _ConfigSheet extends ConsumerStatefulWidget {
  const _ConfigSheet({
    required this.entry,
    required this.name,
    required this.update,
    this.timed = false,
    this.exercise,
    this.todayOnly = false,
  });
  final Exercise? exercise;
  final DoseUpdater update;

  /// 首页预览里打开：只改今天这次训练，不动模板，也不切换动作的记录方式。
  final bool todayOnly;
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
  late double? weight = widget.entry.targetWeightKg;

  late bool _timed = widget.timed || widget.entry.targetDurationSec != null;
  late String section = widget.entry.section;

  /// 切换「按次数 / 按时间」：记到账号偏好里，并把这个模板动作的目标换成对应的量。
  Future<void> _setTimed(bool timed) async {
    final ex = widget.exercise;
    final update = widget.update;
    setState(() => _timed = timed);
    if (ex != null) {
      await ref.read(exercisePrefsRepositoryProvider).setTracking(ex, timed ? TrackingType.duration : ex.repsVariant);
    }
    if (timed) {
      setState(() => duration = widget.entry.targetDurationSec ?? ex?.defaultSeconds ?? 30);
      await update(targetDurationSec: duration);
    } else {
      setState(() {
        repsMin = ex?.defaultReps ?? repsMin;
        repsMax = ex?.defaultReps ?? repsMax;
      });
      await update(clearDuration: true, repsMin: repsMin, repsMax: repsMax);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final update = widget.update;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.s20, AppSpace.s8, AppSpace.s20, AppSpace.s20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.name, style: AppText.titleMedium.copyWith(color: c.text)),
            if (widget.todayOnly) ...[
              const SizedBox(height: AppSpace.s4),
              Text('只改今天这次训练，不会改动模板', style: AppText.label.copyWith(color: c.text2)),
            ],
            const SizedBox(height: AppSpace.s8),
            if (!widget.todayOnly && (widget.exercise?.canSwitchTracking ?? false)) ...[
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
                  update(section: v.first);
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
                update(targetSets: v);
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
                update(repsMin: v, repsMax: repsMax);
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
                update(repsMin: repsMin, repsMax: v);
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
                  update(targetDurationSec: v);
                },
              ),
            if (widget.exercise?.kind == ExerciseKind.strength || weight != null)
              WeightField(
                value: weight,
                onChanged: (v) {
                  setState(() => weight = v);
                  v == null ? update(clearWeight: true) : update(targetWeightKg: v);
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
                  update(warmupSets: v);
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
                update(restSec: v);
              },
            ),
            const SizedBox(height: AppSpace.s12),
            PressScale(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.button)),
                onPressed: () => Navigator.pop(context),
                child: const Text('完成'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 给模板挑动作：复用动作库页面，选中后加入模板并返回。
///
/// 点动作不会直接加入，而是先打开动作详情（和动作库一样），在详情里点「添加动作」才加入。
/// 筛选（部位、器械）保存在 [exerciseFilterProvider] 里，加完回到模板再点「添加动作」仍停在原处；
/// 退出模板编辑页后下次进入由 [TemplateEditPage] 重置。
class TemplatePickPage extends ConsumerWidget {
  const TemplatePickPage({super.key, required this.templateId});
  final String templateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ExercisesPage(
      onPick: (exercise) => context.push('/template/$templateId/pick/${exercise.slug}'),
    );
  }
}

/// 给模板挑动作时看到的动作详情：图片下方有「添加动作」，点了加入模板，并一路返回到模板页。
class TemplatePickDetailPage extends ConsumerWidget {
  const TemplatePickDetailPage({super.key, required this.templateId, required this.slug});
  final String templateId;
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ExerciseDetailPage(
      slug: slug,
      onAdd: (exercise, dose) async {
        await ref
            .read(planRepositoryProvider)
            .addTemplateExercise(templateId, exercise.id, exercise: exercise, dose: dose);
        if (!context.mounted) return;
        final router = GoRouter.of(context);
        router.pop(); // 详情页
        router.pop(); // 选动作页
      },
    );
  }
}

/// 模板 / 训练里的分区小标题：热身、正式训练、放松。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.section, {super.key});
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
