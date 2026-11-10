import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/app_ui.dart';
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
              icon: Icon(isFav ? AppIcons.starOn : AppIcons.star, color: isFav ? c.accent : null),
              onPressed: () => ref.read(libraryRepositoryProvider).setFavorite(program.id, !isFav),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s4, AppSpace.pageGutter, 140),
        children: [
          _Header(program: program, done: done),
          const SizedBox(height: AppSpace.s16),
          Text(program.description, style: AppText.body.copyWith(color: c.text, height: 1.7)),
          const SizedBox(height: AppSpace.s12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in program.equipment) InfoPill(e),
            for (final s in program.scenes) InfoPill(s),
            for (final a in program.audiences) InfoPill(a),
          ]),
          const SizedBox(height: AppSpace.s32),
          const SectionTitle('每周安排'),
          const SizedBox(height: AppSpace.s12),
          AppCard(padding: const EdgeInsets.fromLTRB(8, 12, 8, 12), child: _WeekStrip(program: program)),
          const SizedBox(height: AppSpace.s32),
          SectionTitle('课程', trailing: Text('${program.sessions.length} 节', style: AppText.label.copyWith(color: c.text3))),
          const SizedBox(height: AppSpace.s12),
          for (final s in program.sessions) ...[
            _SessionRow(program: program, session: s),
            const SizedBox(height: AppSpace.s8),
          ],
          const SizedBox(height: AppSpace.s24),
          const SectionTitle('如何进阶'),
          const SizedBox(height: AppSpace.s12),
          AppCard(child: Text(program.progression, style: AppText.body.copyWith(color: c.text2, height: 1.7))),
          const SizedBox(height: AppSpace.s16),
          Text(
            '计划内容为原创的通用训练安排，请根据自身情况调整重量与强度；有伤病、慢性病或持续疼痛时，请先咨询医生或专业教练。',
            style: AppText.caption.copyWith(color: c.text3),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(color: c.bg, border: Border(top: BorderSide(color: c.line, width: 1))),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s8, AppSpace.s12, AppSpace.pageGutter, AppSpace.s12),
            child: Row(
              children: [
                _BarAction(
                  icon: isJoined ? AppIcons.calendarOk : AppIcons.listAdd,
                  label: isJoined ? '已加入' : '加入计划',
                  highlighted: isJoined,
                  onTap: () => joinProgram(context, ref, program),
                ),
                _BarAction(
                  icon: AppIcons.calendar,
                  label: '添加到日历',
                  onTap: () => addProgramToCalendar(context, ref, program),
                ),
                const SizedBox(width: AppSpace.s8),
                Expanded(
                  child: PressScale(
                    child: FilledButton(
                      style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size.fromHeight(AppSize.buttonLarge))),
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
    final color = highlighted ? c.text : c.text2;
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
            width: 72,
            height: AppSize.buttonLarge,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(height: 4),
                Text(label, style: AppText.caption.copyWith(color: color, fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500, height: 1.2)),
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
      height: 248,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (program.isNew) ...[const CoverTag('新上线', filled: true), const SizedBox(width: 8)],
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
              Text(metaLine(['你已完成 $done 节', '共 ${program.totalSessions} 节']),
                  style: AppText.caption.copyWith(color: c.accent, fontWeight: FontWeight.w700)),
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
                const SizedBox(height: 8),
                Container(
                  height: 40,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: program.schedule[i] == '.' ? Colors.transparent : c.text,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: program.schedule[i] == '.' ? Border.all(color: c.text.withValues(alpha: 0.10), width: 1) : null,
                  ),
                  child: program.schedule[i] == '.'
                      ? Text('休', style: AppText.caption.copyWith(color: c.text3))
                      : Text(program.schedule[i], style: AppText.numSmall.copyWith(color: c.bg)),
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
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: () => context.push('/library/${program.slug}/${session.key}'),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.text, borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Text(session.key, style: AppText.numMedium.copyWith(color: c.bg)),
          ),
          const SizedBox(width: AppSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body.copyWith(color: c.text, fontWeight: FontWeight.w600)),
                Text(metaLine(['${session.items.length} 个动作', '${session.totalSets} 组', '约 ${session.minutes} 分钟']),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label.copyWith(color: c.text2)),
                if (session.focus.isNotEmpty)
                  Text(session.focus, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption.copyWith(color: c.text3)),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.s8),
          PressScale(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
              onPressed: () => startProgramSession(context, ref, program, session),
              child: const Text('练这节'),
            ),
          ),
        ],
      ),
    );
  }
}
