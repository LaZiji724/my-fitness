import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_image.dart';
import 'package:my_fitness/features/exercises/exercise_repository.dart';

/// 「动作」分栏：左侧部位、顶部搜索、器械筛选、两列动作网格。
///
/// 传入 [onPick] 时进入「选择动作」模式：顶部带返回，点动作回调而不是进详情。
class ExercisesPage extends ConsumerWidget {
  const ExercisesPage({super.key, this.onPick});

  final ValueChanged<Exercise>? onPick;

  /// 左侧部位栏。「收藏」与「自定义」等本地数据库接入后再加。
  static const _parts = [
    BodyPart.chest,
    BodyPart.back,
    BodyPart.shoulders,
    BodyPart.arms,
    BodyPart.legs,
    BodyPart.glutes,
    BodyPart.core,
    BodyPart.cardio,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final filter = ref.watch(exerciseFilterProvider);
    final async = ref.watch(exercisesProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    if (onPick != null)
                      PressScale(
                        scale: PressScale.smallScale,
                        child: IconButton(
                          tooltip: '返回',
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                    Text(onPick != null ? '选择动作' : '动作',
                        style: AppText.titleLarge.copyWith(color: c.text)),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.s12),
              _SearchField(
                initial: filter.query,
                onChanged: ref.read(exerciseFilterProvider.notifier).setQuery,
              ),
              const SizedBox(height: AppSpace.s12),
              Expanded(
                child: async.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text('动作库加载失败', style: AppText.body.copyWith(color: c.danger)),
                  ),
                  data: (all) => Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 60,
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: AppSpace.s24),
                          children: [
                            for (final p in _parts)
                              _CategoryButton(
                                label: p.label,
                                selected: !filter.isSearching && filter.tab == ExerciseTab.part && p == filter.bodyPart,
                                onTap: () => ref.read(exerciseFilterProvider.notifier).setBodyPart(p),
                              ),
                            _CategoryButton(
                              label: '激活',
                              selected: !filter.isSearching && filter.tab == ExerciseTab.activation,
                              onTap: () => ref.read(exerciseFilterProvider.notifier).setTab(ExerciseTab.activation),
                            ),
                            _CategoryButton(
                              label: '拉伸',
                              selected: !filter.isSearching && filter.tab == ExerciseTab.stretch,
                              onTap: () => ref.read(exerciseFilterProvider.notifier).setTab(ExerciseTab.stretch),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: _Results(all: all, filter: filter, onPick: onPick)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.initial, required this.onChanged});
  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: '搜索动作，如 卧推、深蹲',
        filled: true,
        fillColor: c.surface,
        prefixIcon: Icon(Icons.search_rounded, color: c.text3),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: PressScale(
        scale: PressScale.chipScale,
        child: Semantics(
          button: true,
          selected: selected,
          child: Material(
            color: selected ? c.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(
                    label,
                    style: AppText.body.copyWith(
                      color: selected ? c.text : c.text2,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.all, required this.filter, this.onPick});

  final List<Exercise> all;
  final ExerciseFilter filter;
  final ValueChanged<Exercise>? onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final items = filterExercises(all, filter);
    final counts = equipmentCounts(all, filter);
    final groups = [
      for (final g in EquipmentGroup.values)
        if (g == EquipmentGroup.all || (counts[g] ?? 0) > 0) g,
    ];
    final warm = filter.isWarmupTab;
    final regions = warm ? regionCounts(all, filter) : const <ExerciseRegion, int>{};
    final kinds = filter.tab == ExerciseTab.activation
        ? const [ExerciseKind.activation, ExerciseKind.dynamicWarmup]
        : const [ExerciseKind.stretch, ExerciseKind.foam];
    final title = filter.isSearching
        ? '搜索结果'
        : switch (filter.tab) {
            ExerciseTab.part => filter.bodyPart.label,
            ExerciseTab.activation => '激活热身',
            ExerciseTab.stretch => '拉伸放松',
          };

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (warm) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _EquipmentChip(
                      label: '全部',
                      selected: filter.kind == null,
                      onTap: () => ref.read(exerciseFilterProvider.notifier).setKind(null),
                    ),
                    for (final k in kinds)
                      _EquipmentChip(
                        label: k.label,
                        selected: filter.kind == k,
                        onTap: () => ref.read(exerciseFilterProvider.notifier).setKind(k),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _EquipmentChip(
                      label: '全部部位',
                      selected: filter.region == null,
                      onTap: () => ref.read(exerciseFilterProvider.notifier).setRegion(null),
                    ),
                    for (final r in ExerciseRegion.values)
                      if ((regions[r] ?? 0) > 0)
                        _EquipmentChip(
                          label: r.label,
                          selected: filter.region == r,
                          onTap: () => ref.read(exerciseFilterProvider.notifier).setRegion(r),
                        ),
                  ],
                ),
              ] else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final g in groups)
                      _EquipmentChip(
                        label: g.label,
                        selected: g == filter.equipment,
                        onTap: () => ref.read(exerciseFilterProvider.notifier).setEquipment(g),
                      ),
                  ],
                ),
              const SizedBox(height: AppSpace.s12),
              Text('$title · ${counts[EquipmentGroup.all] ?? 0} 个动作',
                  style: AppText.caption.copyWith(color: c.text3)),
              const SizedBox(height: AppSpace.s12),
            ],
          ),
        ),
        if (items.isEmpty)
          SliverToBoxAdapter(
            child: DecoratedBox(
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.s24, horizontal: AppSpace.s16),
                child: Column(
                  children: [
                    Text('没有找到动作', style: AppText.titleSmall.copyWith(color: c.text)),
                    const SizedBox(height: AppSpace.s8),
                    Text('换个关键词，或者切换左侧的部位试试',
                        textAlign: TextAlign.center,
                        style: AppText.label.copyWith(color: c.text2)),
                  ],
                ),
              ),
            ),
          )
        else
          SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 10,
              // 激活 / 拉伸的图是 4:3，格子更矮
              childAspectRatio: warm ? 0.76 : 0.74,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => _ExerciseTile(exercise: items[i], onPick: onPick),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpace.s24)),
      ],
    );
  }
}

class _EquipmentChip extends StatelessWidget {
  const _EquipmentChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressScale(
      scale: PressScale.chipScale,
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? c.text : c.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: SizedBox(
              height: 32,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    label,
                    style: AppText.label.copyWith(
                      color: selected ? c.bg : c.text,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({required this.exercise, this.onPick});
  final Exercise exercise;
  final ValueChanged<Exercise>? onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressScale(
      scale: PressScale.cardScale,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onPick != null ? onPick!(exercise) : context.push('/exercise/${exercise.slug}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExerciseImage(exercise: exercise, cacheWidth: 360),
            const SizedBox(height: 6),
            Text(
              exercise.nameZh,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(color: c.text, fontWeight: FontWeight.w600, fontSize: 14, height: 1.3),
            ),
            const SizedBox(height: 2),
            Text(_subtitle(exercise),
                style: AppText.caption.copyWith(color: c.text3, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// 动作卡片的小字：力量动作显示器械；激活 / 拉伸显示类型与区域，按时间的再带上默认秒数。
String _subtitle(Exercise e) {
  if (e.kind == ExerciseKind.strength || e.kind == ExerciseKind.cardio) return e.equipmentGroup.label;
  final parts = <String>[e.kind.label, if (e.region != null) e.region!.label];
  return parts.join(' · ');
}
