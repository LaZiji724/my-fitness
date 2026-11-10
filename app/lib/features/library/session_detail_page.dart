import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/app_ui.dart';
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
          Text(metaLine([program.name, '第 ${session.key} 节']), style: AppText.label.copyWith(color: c.text3)),
          const SizedBox(height: 2),
          Text(session.focus.isEmpty ? session.name : session.focus, style: AppText.titleMedium.copyWith(color: c.text)),
          const SizedBox(height: AppSpace.s4),
          Text(metaLine(['${session.items.length} 个动作', '${session.totalSets} 组', '约 ${session.minutes} 分钟']),
              style: AppText.label.copyWith(color: c.text2)),
          const SizedBox(height: AppSpace.s20),
          for (var i = 0; i < session.items.length; i++) ...[
            if (session.items.any((x) => x.section != 'main') &&
                (i == 0 || session.items[i - 1].section != session.items[i].section))
              Padding(
                padding: const EdgeInsets.fromLTRB(4, AppSpace.s8, 4, AppSpace.s8),
                child: Text(WorkoutSection.fromKey(session.items[i].section).label,
                    style: AppText.label.copyWith(color: c.text2, fontWeight: FontWeight.w700)),
              ),
            _ChainRow(index: i + 1, item: session.items[i], exercise: byId[session.items[i].exerciseId]),
            const SizedBox(height: AppSpace.s8),
          ],
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        child: PressScale(
          child: FilledButton(
            style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size.fromHeight(AppSize.buttonLarge))),
            onPressed: () => startProgramSession(context, ref, program, session),
            child: const Text('开始这节训练'),
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
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: ex == null ? null : () => context.push('/exercise/${ex.slug}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ex != null && ex.imageCount > 0) ...[
            SizedBox(width: AppSize.exerciseThumb, child: ExerciseImage(exercise: ex, cacheWidth: 160, radius: AppRadius.sm)),
            const SizedBox(width: AppSpace.s12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ex?.nameZh ?? '未知动作', style: AppText.body.copyWith(color: c.text, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(describeItemTarget(item), style: AppText.label.copyWith(color: c.text2)),
                if (item.warmupSets > 0) ...[
                  const SizedBox(height: 8),
                  AppTag('先做 ${item.warmupSets} 组热身', color: c.warmupFg, background: c.warmupBg),
                ],
                if (item.note != null) ...[
                  const SizedBox(height: 4),
                  Text(item.note!, style: AppText.label.copyWith(color: c.text3)),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpace.s8),
          Text('$index'.padLeft(2, '0'), style: AppText.numSmall.copyWith(color: c.text3, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
