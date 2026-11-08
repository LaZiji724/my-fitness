import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/plan/plan_widgets.dart' show EmptyCard, EstimateHint;
import 'package:my_fitness/features/plan/plan_estimate.dart';
import 'package:my_fitness/features/plan/plan_providers.dart';
import 'package:my_fitness/features/plan/template_edit_page.dart';
import 'package:my_fitness/features/plan/today_overrides.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';

/// 首页今日计划卡片点开的预览：样式和模板页一样，但这里的改动只作用于今天这次训练，
/// 记在本机、当天有效，不会改动模板，也不会影响计划里其他天用同一个模板。
class TodayPreviewPage extends ConsumerWidget {
  const TodayPreviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final base = ref.watch(todayPlanProvider)?.template;
    final view = ref.watch(todayEffectiveTemplateProvider);
    final byId = ref.watch(exerciseByIdProvider);
    final today = ref.watch(todayProvider);

    if (base == null || view == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('今天没有训练计划', style: AppText.body.copyWith(color: c.text2))),
      );
    }

    final repo = ref.watch(todayOverridesRepositoryProvider);
    final edits = ref.watch(todayEditsProvider(base.template.id)).value ?? const TodayEdits();

    return Scaffold(
      appBar: AppBar(title: Text(view.template.name, overflow: TextOverflow.ellipsis)),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, 0),
            sliver: SliverList.list(children: [
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.s12),
                child: Text('点右边的小笔调整运动量，点 ✕ 去掉今天不练的动作，长按卡片上下拖动可以排序。'
                    '这些只影响今天这次训练，不会改动模板。',
                    style: AppText.label.copyWith(color: c.text2)),
              ),
              if (view.exercises.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpace.s8),
                  child: EmptyCard(title: '今天的动作都去掉了', hint: '点下面的「恢复为模板原来的量」找回'),
                ),
            ]),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageGutter),
            sliver: ReorderableExerciseSliver(
              entries: view.exercises,
              onReorder: (order) => repo.reorder(today, base.template.id, order,
                  currentSections: {for (final e in view.exercises) e.id: e.section}),
              cardBuilder: (e) => TemplateExerciseCard(
                entry: e,
                exercise: byId[e.exerciseId],
                onRemove: () => repo.remove(today, base.template.id, e.id),
                onEdit: () => showDoseSheet(
                  context,
                  todayOnly: true,
                  entry: e,
                  exercise: byId[e.exerciseId],
                  update: ({targetSets, repsMin, repsMax, restSec, warmupSets, targetDurationSec, clearDuration = false, section}) =>
                      repo.save(
                        today,
                        base.template.id,
                        e.id,
                        DoseOverride(
                          targetSets: targetSets,
                          repsMin: repsMin,
                          repsMax: repsMax,
                          restSec: restSec,
                          warmupSets: warmupSets,
                          targetDurationSec: targetDurationSec,
                          clearDuration: clearDuration,
                          section: section,
                        ),
                      ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, 0, AppSpace.pageGutter, 120),
            sliver: SliverToBoxAdapter(
              child: edits.isEmpty
                  ? null
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: PressScale(
                        child: TextButton(
                          onPressed: () => repo.clear(today, base.template.id),
                          child: const Text('恢复为模板原来的量'),
                        ),
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
                          await startTodayPlan(ref);
                          if (context.mounted) context.go('/workout');
                        },
                  child: const Text('开始训练'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
