import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_image.dart';
import 'package:my_fitness/features/library/library_providers.dart';
import 'package:my_fitness/features/library/program.dart';
import 'package:my_fitness/features/library/program_actions.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';

/// 单节课详情：完整动作链（热身组、次数 / 时间 / 距离目标、休息秒数），可直接开始这一节。
class SessionDetailPage extends ConsumerWidget {
  const SessionDetailPage({super.key, required this.slug, required this.sessionKey});
  final String slug;
  final String sessionKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final program = ref.watch(programBySlugProvider(slug));
    final session = program?.sessionByKey(sessionKey);
    final byId = ref.watch(exerciseByIdProvider);

    if (program == null || session == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('找不到这节课', style: AppText.body.copyWith(color: c.text2))),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(session.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, 140),
        children: [
          Text(program.name, style: AppText.label.copyWith(color: c.text2)),
          const SizedBox(height: 2),
          Text('第 ${session.key} 节 · ${session.focus}', style: AppText.titleMedium.copyWith(color: c.text)),
          const SizedBox(height: AppSpace.s4),
          Text('${session.items.length} 个动作 · ${session.totalSets} 组 · 约 ${session.minutes} 分钟',
              style: AppText.label.copyWith(color: c.text2)),
          const SizedBox(height: AppSpace.s16),
          for (var i = 0; i < session.items.length; i++) ...[
            if (session.items.any((x) => x.section != 'main') &&
                (i == 0 || session.items[i - 1].section != session.items[i].section))
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.s8, bottom: AppSpace.s8),
                child: Text(WorkoutSection.fromKey(session.items[i].section).label,
                    style: AppText.label.copyWith(color: c.text2, fontWeight: FontWeight.w700)),
              ),
            _ChainRow(index: i + 1, item: session.items[i], exercise: byId[session.items[i].exerciseId]),
            const SizedBox(height: AppSpace.s8),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, AppSpace.s12),
          child: PressScale(
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.buttonLarge)),
              onPressed: () => startProgramSession(context, ref, program, session),
              child: const Text('开始这节训练'),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChainRow extends StatelessWidget {
  const _ChainRow({required this.index, required this.item, required this.exercise});
  final int index;
  final ProgramItem item;
  final Exercise? exercise;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ex = exercise;
    return PressScale(
      scale: PressScale.cardScale,
      child: Material(
        color: c.surface,
        borderRadius: AppRadius.card,
        child: InkWell(
          borderRadius: AppRadius.card,
          onTap: ex == null ? null : () => context.push('/exercise/${ex.slug}'),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.s12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Text('$index', style: AppText.numMedium.copyWith(color: c.text3)),
                ),
                if (ex != null && ex.imageCount > 0) ...[
                  SizedBox(width: AppSize.exerciseThumb, child: ExerciseImage(exercise: ex, cacheWidth: 160, radius: AppRadius.md - 4)),
                  const SizedBox(width: AppSpace.s12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ex?.nameZh ?? '未知动作', style: AppText.body.copyWith(color: c.text, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(describeItemTarget(item), style: AppText.label.copyWith(color: c.accentText)),
                      if (item.warmupSets > 0) ...[
                        const SizedBox(height: 4),
                        DecoratedBox(
                          decoration: BoxDecoration(color: c.warmupBg, borderRadius: BorderRadius.circular(AppRadius.xs)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Text('先做 ${item.warmupSets} 组热身',
                                style: AppText.caption.copyWith(color: c.warmupFg, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                      if (item.note != null) ...[
                        const SizedBox(height: 4),
                        Text(item.note!, style: AppText.label.copyWith(color: c.text2)),
                      ],
                    ],
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
