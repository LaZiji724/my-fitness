import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/app_ui.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_image.dart';
import 'package:my_fitness/features/exercises/exercise_repository.dart';

/// 选择动作页：顶部带返回，点动作回调而不是进详情。
/// 平时的动作库已并入「计划」页的「动作库」分栏（见 [ExercisesBody]）。
///
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
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: AppSize.pageHeader,
                child: Row(
                  children: [
                    if (onPick != null) ...[
                      RoundIconButton(tooltip: '返回', icon: AppIcons.back, onPressed: () => context.pop()),
                      const SizedBox(width: AppSpace.s12),
                    ],
                    Text(onPick != null ? '选择动作' : '动作',
                        style: (onPick != null ? AppText.titleMedium : AppText.titleLarge).copyWith(color: c.text)),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.s8),
              Expanded(child: ExercisesBody(onPick: onPick)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 动作库的内容：搜索框 + 左侧部位栏 + 动作网格。
/// 既用在「选择动作」页里，也放在「计划」页的「动作库」分栏下。
/// 自己不带页面外壳和标题，外面要给它一个确定的高度（放进 Expanded）。
class ExercisesBody extends ConsumerWidget {
  const ExercisesBody({super.key, this.onPick});

  final ValueChanged<Exercise>? onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final filter = ref.watch(exerciseFilterProvider);
    final async = ref.watch(exercisesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                  width: 56,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: AppSpace.s24),
                    children: [
                      for (final p in ExercisesPage._parts)
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
                const SizedBox(width: 12),
                Expanded(child: _Results(all: all, filter: filter, onPick: onPick)),
              ],
            ),
          ),
        ),
      ],
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
      style: AppText.body.copyWith(color: c.text),
      decoration: InputDecoration(
        hintText: '搜索动作，如 卧推、深蹲',
        filled: true,
        fillColor: c.surface,
        prefixIcon: Icon(AppIcons.searchSmall, size: 18, color: c.text3),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.button,
          borderSide: BorderSide(color: c.border, width: AppStroke.hairline),
        ),
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
      padding: const EdgeInsets.only(bottom: 4),
      child: PressScale(
        scale: PressScale.chipScale,
        child: Semantics(
          button: true,
          selected: selected,
          child: Material(
            color: selected ? c.text : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: onTap,
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(
                    label,
                    style: AppText.label.copyWith(
                      color: selected ? c.bg : c.text2,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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

class _Results extends ConsumerStatefulWidget {
  const _Results({required this.all, required this.filter, this.onPick});

  final List<Exercise> all;
  final ExerciseFilter filter;
  final ValueChanged<Exercise>? onPick;

  @override
  ConsumerState<_Results> createState() => _ResultsState();
}

class _ResultsState extends ConsumerState<_Results> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final all = widget.all;
    final filter = widget.filter;
    final onPick = widget.onPick;
    // 点左侧部位、顶部筛选或搜索后，右侧动作列表回到顶部。
    ref.listen<ExerciseFilter>(exerciseFilterProvider, (prev, next) {
      if (prev != null && _scroll.hasClients && _scroll.offset != 0) _scroll.jumpTo(0);
    });
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

    // 筛选条和数量固定在上方，只有下面的动作网格滑动。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              if (warm) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
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
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
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
                  spacing: 8,
                  runSpacing: 8,
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
              Text(metaLine([title, '${counts[EquipmentGroup.all] ?? 0} 个动作']), style: AppText.caption.copyWith(color: c.text3)),
              const SizedBox(height: AppSpace.s12),
            ],
        ),
        Expanded(
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
        if (items.isEmpty)
          SliverToBoxAdapter(
            child: AppCard(
              padding: EdgeInsets.zero,
              child: EmptyState(icon: AppIcons.search, title: '没有找到动作', hint: '换个关键词，或者切换左侧的部位试试', compact: true),
            ),
          )
        else
          // 格子高度按「图片高 + 两行名字 + 一行小字」算出来，不靠固定比例，窄屏宽屏都不会挤出去
          SliverLayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              final tileW = (constraints.crossAxisExtent - gap) / 2;
              // 搜索结果里 1:1 和 4:3 的图可能混在一起，按最高的那种留位置
              final ratio = items.fold<double>(items.first.imageRatio, (m, e) => e.imageRatio < m ? e.imageRatio : m);
              final imageH = tileW / ratio;
              return SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: gap,
                  mainAxisExtent: imageH + _ExerciseTile.textBlockHeight,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) => _ExerciseTile(exercise: items[i], onPick: onPick),
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpace.s24)),
            ],
          ),
        ),
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
    return Semantics(
      button: true,
      selected: selected,
      child: AppChip(label: label, selected: selected, onTap: onTap, height: 32),
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({required this.exercise, this.onPick});
  final Exercise exercise;
  final ValueChanged<Exercise>? onPick;

  /// 图片下面那块文字的高度：间距 8 + 名字两行（14 × 1.3 × 2）+ 间距 2 + 小字一行（12 × 1.4），向上取整
  static const double textBlockHeight = 64;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressScale(
      scale: PressScale.cardScale,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => onPick != null ? onPick!(exercise) : context.push('/exercise/${exercise.slug}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: c.border, width: AppStroke.hairline),
              ),
              child: ExerciseImage(exercise: exercise, cacheWidth: 360),
            ),
            const SizedBox(height: 8),
            Text(
              exercise.nameZh,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(color: c.text, fontWeight: FontWeight.w600, height: 1.3),
            ),
            const SizedBox(height: 2),
            Text(_subtitle(exercise), style: AppText.caption.copyWith(color: c.text3)),
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
  return metaLine(parts);
}
