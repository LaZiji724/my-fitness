import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/library/library_providers.dart';
import 'package:my_fitness/features/library/library_widgets.dart';
import 'package:my_fitness/features/library/program.dart';
import 'package:my_fitness/features/plan/plan_widgets.dart';

/// 计划库：左侧分类、顶部四个筛选（频率 / 难度 / 场景 / 人群）、计划封面卡列表。
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  bool _searching = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final filter = ref.watch(libraryFilterProvider);
    final async = ref.watch(programsProvider);
    final notifier = ref.read(libraryFilterProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                onChanged: notifier.setQuery,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(hintText: '搜索计划，如 减脂、臀、肩颈', border: InputBorder.none),
              )
            : const Text('计划库'),
        actions: [
          IconButton(
            tooltip: _searching ? '关闭搜索' : '搜索',
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching) {
                _search.clear();
                notifier.setQuery('');
              }
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('计划库加载失败', style: AppText.body.copyWith(color: c.danger))),
        data: (all) => Column(
          children: [
            _FilterBar(all: all, filter: filter),
            const SizedBox(height: AppSpace.s8),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CategoryRail(selected: filter.isSearching ? null : filter.category),
                  Expanded(child: _ProgramList(filter: filter)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 筛选条

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.all, required this.filter});
  final List<Program> all;
  final LibraryFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(libraryFilterProvider.notifier);
    final scenes = {for (final p in all) ...p.scenes}.toList();
    final audiences = {for (final p in all) ...p.audiences}.toList();

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageGutter),
        children: [
          _FilterChip(
            label: filter.frequency?.label ?? '频率',
            active: filter.frequency != null,
            onTap: () => _pick<FrequencyBand>(context,
                title: '训练频率',
                options: FrequencyBand.values,
                labelOf: (b) => b.label,
                current: filter.frequency,
                onSelected: n.setFrequency),
          ),
          _FilterChip(
            label: filter.level == null ? '难度' : levelLabel(filter.level!),
            active: filter.level != null,
            onTap: () => _pick<int>(context,
                title: '难度',
                options: const [1, 2, 3],
                labelOf: levelLabel,
                current: filter.level,
                onSelected: n.setLevel),
          ),
          _FilterChip(
            label: filter.scene ?? '场景',
            active: filter.scene != null,
            onTap: () => _pick<String>(context,
                title: '训练场景', options: scenes, labelOf: (s) => s, current: filter.scene, onSelected: n.setScene),
          ),
          _FilterChip(
            label: filter.audience ?? '人群',
            active: filter.audience != null,
            onTap: () => _pick<String>(context,
                title: '适合人群',
                options: audiences,
                labelOf: (s) => s,
                current: filter.audience,
                onSelected: n.setAudience),
          ),
          if (filter.hasAdvancedFilter)
            TextButton(onPressed: n.clearAdvanced, child: const Text('清除筛选')),
        ],
      ),
    );
  }

  Future<void> _pick<T>(
    BuildContext context, {
    required String title,
    required List<T> options,
    required String Function(T) labelOf,
    required T? current,
    required ValueChanged<T?> onSelected,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final c = ctx.colors;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s20, AppSpace.s8, AppSpace.s20, AppSpace.s20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.titleMedium.copyWith(color: c.text)),
                const SizedBox(height: AppSpace.s12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _OptionChip(
                      label: '不限',
                      selected: current == null,
                      onTap: () {
                        onSelected(null);
                        Navigator.pop(ctx);
                      },
                    ),
                    for (final o in options)
                      _OptionChip(
                        label: labelOf(o),
                        selected: o == current,
                        onTap: () {
                          onSelected(o);
                          Navigator.pop(ctx);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: Semantics(
          button: true,
          selected: active,
          child: Material(
            color: active ? c.accentSoft : c.surface,
            shape: StadiumBorder(side: BorderSide(color: active ? c.accent : c.line)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: SizedBox(
                height: AppSize.chip,
                child: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label,
                          style: AppText.label.copyWith(
                              color: active ? c.accentText : c.text, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                      Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: active ? c.accentText : c.text3),
                    ],
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

class _OptionChip extends StatelessWidget {
  const _OptionChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? c.text : c.sunken,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: SizedBox(
            height: AppSize.chip + 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                widthFactor: 1,
                child: Text(label,
                    style: AppText.body.copyWith(
                        color: selected ? c.bg : c.text, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 左侧分类栏

class _CategoryRail extends ConsumerWidget {
  const _CategoryRail({required this.selected});
  final LibraryCategory? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return SizedBox(
      width: 84,
      child: ListView(
        padding: const EdgeInsets.only(left: AppSpace.s8, bottom: AppSpace.s24),
        children: [
          for (final cat in LibraryCategory.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Semantics(
                button: true,
                selected: cat == selected,
                child: Material(
                  color: cat == selected ? c.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => ref.read(libraryFilterProvider.notifier).setCategory(cat),
                    child: SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          Container(
                            width: 3,
                            height: 20,
                            margin: const EdgeInsets.only(left: 2, right: 6),
                            decoration: BoxDecoration(
                              color: cat == selected ? c.accent : Colors.transparent,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              cat.label,
                              style: AppText.label.copyWith(
                                color: cat == selected ? c.text : c.text2,
                                fontSize: 14,
                                fontWeight: cat == selected ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ 列表

class _ProgramList extends ConsumerWidget {
  const _ProgramList({required this.filter});
  final LibraryFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final items = ref.watch(filteredProgramsProvider);
    final favorites = ref.watch(favoriteProgramIdsProvider).value ?? const <String>{};
    final counts = ref.watch(programCompletedCountsProvider).value ?? const <String, int>{};
    final joined = ref.watch(joinedProgramsProvider).value ?? const <String, String>{};

    final title = filter.isSearching ? '搜索结果' : filter.category.label;

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.s8, 0, AppSpace.pageGutter, AppSpace.s32),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.s8, left: 2),
          child: Text('$title · ${items.length} 个计划', style: AppText.caption.copyWith(color: c.text3)),
        ),
        if (items.isEmpty)
          EmptyCard(
            title: filter.category == LibraryCategory.favorites && !filter.isSearching ? '还没有收藏' : '没有符合条件的计划',
            hint: filter.category == LibraryCategory.favorites && !filter.isSearching
                ? '在计划详情页点右上角的星标，就会收藏到这里'
                : filter.category == LibraryCategory.newest && !filter.hasAdvancedFilter && !filter.isSearching
                    ? '暂时没有新上线的计划，看看其他分类吧'
                    : '换个筛选条件，或者清除筛选再试试',
          ),
        for (final p in items) ...[
          ProgramCard(
            program: p,
            completed: counts[p.id] ?? 0,
            joined: joined.containsKey(p.id),
            favorite: favorites.contains(p.id),
            onTap: () => context.push('/library/${p.slug}'),
          ),
          const SizedBox(height: AppSpace.s12),
        ],
      ],
    );
  }
}
