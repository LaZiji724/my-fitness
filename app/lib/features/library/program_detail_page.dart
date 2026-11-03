import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/library/library_providers.dart';
import 'package:my_fitness/features/library/library_widgets.dart';
import 'package:my_fitness/features/library/program.dart';
import 'package:my_fitness/features/library/program_actions.dart';

const _weekdayShort = ['一', '二', '三', '四', '五', '六', '日'];

/// 计划详情：周数、每周次数、难度、器械、每周安排、课程列表，以及加入 / 添加到日历 / 去训练。
class ProgramDetailPage extends ConsumerWidget {
  const ProgramDetailPage({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final program = ref.watch(programBySlugProvider(slug));
    final loading = ref.watch(programsProvider).isLoading;

    if (program == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: loading
              ? const CircularProgressIndicator()
              : Text('找不到这个计划', style: AppText.body.copyWith(color: c.text2)),
        ),
      );
    }

    final favorites = ref.watch(favoriteProgramIdsProvider).value ?? const <String>{};
    final isFav = favorites.contains(program.id);
    final joined = ref.watch(joinedProgramsProvider).value ?? const <String, String>{};
    final isJoined = joined.containsKey(program.id);
    final done = ref.watch(programCompletedCountsProvider).value?[program.id] ?? 0;

    return Scaffold(
      appBar: AppBar(
        actions: [
          PressScale(
            scale: PressScale.smallScale,
            child: IconButton(
              tooltip: isFav ? '取消收藏' : '收藏',
              icon: Icon(isFav ? Icons.star_rounded : Icons.star_border_rounded, color: isFav ? c.accent : null),
              onPressed: () => ref.read(libraryRepositoryProvider).setFavorite(program.id, !isFav),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, 0, AppSpace.pageGutter, 140),
        children: [
          _Header(program: program, done: done),
          const SizedBox(height: AppSpace.s16),
          Text(program.description, style: AppText.body.copyWith(color: c.text)),
          const SizedBox(height: AppSpace.s12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in program.equipment) InfoPill(e, icon: Icons.fitness_center_rounded),
            for (final s in program.scenes) InfoPill(s, icon: Icons.place_outlined),
            for (final a in program.audiences) InfoPill(a, icon: Icons.person_outline_rounded),
          ]),
          const SizedBox(height: AppSpace.s24),
          Text('每周安排', style: AppText.titleSmall.copyWith(color: c.text)),
          const SizedBox(height: AppSpace.s8),
          _WeekStrip(program: program),
          const SizedBox(height: AppSpace.s24),
          Text('课程（${program.sessions.length} 节）', style: AppText.titleSmall.copyWith(color: c.text)),
          const SizedBox(height: AppSpace.s8),
          for (final s in program.sessions) ...[
            _SessionRow(program: program, session: s),
            const SizedBox(height: AppSpace.s8),
          ],
          const SizedBox(height: AppSpace.s16),
          Text('如何进阶', style: AppText.titleSmall.copyWith(color: c.text)),
          const SizedBox(height: AppSpace.s8),
          DecoratedBox(
            decoration: BoxDecoration(color: c.surface, borderRadius: AppRadius.card),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.cardPadding),
              child: Text(program.progression, style: AppText.body.copyWith(color: c.text2)),
            ),
          ),
          const SizedBox(height: AppSpace.s16),
          Text(
            '计划内容为原创的通用训练安排，请根据自身情况调整重量与强度；有伤病、慢性病或持续疼痛时，请先咨询医生或专业教练。',
            style: AppText.caption.copyWith(color: c.text3),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s8, AppSpace.s8, AppSpace.pageGutter, AppSpace.s8),
            child: Row(
              children: [
                _BarAction(
                  icon: isJoined ? Icons.event_available_rounded : Icons.playlist_add_rounded,
                  label: isJoined ? '已加入' : '加入计划',
                  highlighted: isJoined,
                  onTap: () => joinProgram(context, ref, program),
                ),
                _BarAction(
                  icon: Icons.calendar_month_outlined,
                  label: '添加到日历',
                  onTap: () => addProgramToCalendar(context, ref, program),
                ),
                const SizedBox(width: AppSpace.s8),
                Expanded(
                  child: PressScale(
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.buttonLarge)),
                      onPressed: () => startNextSession(context, ref, program),
                      child: const Text('去训练'),
                    ),
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

/// 底栏左侧的小操作：图标在上、文字在下，给「去训练」主按钮留出宽度。
class _BarAction extends StatelessWidget {
  const _BarAction({required this.icon, required this.label, required this.onTap, this.highlighted = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = highlighted ? c.accentText : c.text;
    return PressScale(
      scale: PressScale.chipScale,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.button,
          child: SizedBox(
            width: 68,
            height: AppSize.buttonLarge,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(height: 2),
                Text(label, style: AppText.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.program, required this.done});
  final Program program;
  final int done;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ProgramCover(
      program: program,
      height: 232,
      iconSize: 170,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (program.isNew) ...[const CoverTag('新上线', filled: true), const SizedBox(width: 6)],
              CoverTag(program.category),
              const Spacer(),
            ]),
            const Spacer(),
            Text(program.name, style: AppText.titleLarge.copyWith(color: c.onHero)),
            const SizedBox(height: 2),
            Text(program.subtitle, style: AppText.label.copyWith(color: c.onHero2)),
            const SizedBox(height: AppSpace.s16),
            Row(
              children: [
                StatBlock(value: '${program.weeks}', unit: '周', label: '计划周期'),
                StatBlock(value: '${program.daysPerWeek}', unit: '练/周', label: '每周次数'),
                StatBlock(value: '${program.minutes}', unit: '分钟', label: '平均每节'),
                StatBlock(value: program.levelText, unit: '', label: '难度'),
              ],
            ),
            if (done > 0) ...[
              const SizedBox(height: AppSpace.s8),
              Text('你已完成 $done 节 · 共 ${program.totalSessions} 节',
                  style: AppText.caption.copyWith(color: c.accentText)),
            ],
          ],
        ),
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.program});
  final Program program;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Column(
              children: [
                Text(_weekdayShort[i], style: AppText.caption.copyWith(color: c.text3)),
                const SizedBox(height: 4),
                Container(
                  height: 40,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: program.schedule[i] == '.' ? c.sunken : c.accentSoft,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: program.schedule[i] == '.'
                      ? Text('休', style: AppText.label.copyWith(color: c.text3))
                      : Text(program.schedule[i], style: AppText.numSmall.copyWith(color: c.accentText)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SessionRow extends ConsumerWidget {
  const _SessionRow({required this.program, required this.session});
  final Program program;
  final ProgramSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return PressScale(
      scale: PressScale.cardScale,
      child: Material(
        color: c.surface,
        borderRadius: AppRadius.card,
        child: InkWell(
          borderRadius: AppRadius.card,
          onTap: () => context.push('/library/${program.slug}/${session.key}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s12, AppSpace.s12, AppSpace.s8, AppSpace.s12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(AppRadius.sm)),
                  child: Text(session.key, style: AppText.numMedium.copyWith(color: c.accentText)),
                ),
                const SizedBox(width: AppSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.name, style: AppText.body.copyWith(color: c.text, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('${session.items.length} 个动作 · ${session.totalSets} 组',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label.copyWith(color: c.text2)),
                      Text(['约 ${session.minutes} 分钟', if (session.focus.isNotEmpty) session.focus].join(' · '),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption.copyWith(color: c.text3)),
                    ],
                  ),
                ),
                PressScale(
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14)),
                    onPressed: () => startProgramSession(context, ref, program, session),
                    child: const Text('练这节'),
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
