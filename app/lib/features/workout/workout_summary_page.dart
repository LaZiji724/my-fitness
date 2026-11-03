import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/plan/plan_providers.dart';
import 'package:my_fitness/features/plan/plan_widgets.dart';
import 'package:my_fitness/features/workout/workout_math.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

String formatSpan(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h > 0) return '$h小时$m分';
  if (m > 0) return '$m分钟';
  return '${d.inSeconds}秒';
}

String formatVolume(double kg) =>
    kg >= 1000 ? '${(kg / 1000).toStringAsFixed(2)} 吨' : '${kg.round()} kg';

String prLabel(PrKind k) => switch (k) {
      PrKind.weight => '重量纪录',
      PrKind.reps => '次数纪录',
      PrKind.oneRepMax => '1RM 纪录',
    };

/// 训练结束后的总结：时长、总容量、组数，以及本次打破的纪录。
class WorkoutSummaryPage extends ConsumerWidget {
  const WorkoutSummaryPage({super.key, required this.summary});

  final WorkoutSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final byId = ref.watch(exerciseByIdProvider);
    final prs = summary.prs.entries.where((e) => e.value.isNotEmpty).toList();

    // 数字用等宽数字字体放大，单位缩小放在后面：一眼先看到「52」「12.35」「14」
    Widget stat(String text, String label) {
      final m = RegExp(r'^([0-9.]+)\s*(.*)$').firstMatch(text);
      final number = m?.group(1) ?? text;
      final unit = m?.group(2) ?? '';
      return Expanded(
        child: Column(
          children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(text: number, style: AppText.numLarge.copyWith(color: c.onHero)),
                if (unit.isNotEmpty) TextSpan(text: ' $unit', style: AppText.label.copyWith(color: c.onHero2)),
              ]),
              maxLines: 1,
            ),
            const SizedBox(height: 2),
            Text(label, style: AppText.caption.copyWith(color: c.onHero2)),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.pageGutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpace.s16),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                  child: Icon(Icons.local_fire_department_rounded, size: 32, color: c.onAccent),
                ),
              ),
              const SizedBox(height: AppSpace.s16),
              Text('训练完成', style: AppText.titleLarge.copyWith(color: c.text)),
              const SizedBox(height: AppSpace.s4),
              Text(prs.isEmpty ? '这次练得不错，记录已保存' : '破了 ${prs.length} 个动作的纪录，记录已保存',
                  style: AppText.body.copyWith(color: c.text2)),
              const SizedBox(height: AppSpace.s24),
              DecoratedBox(
                decoration: BoxDecoration(color: c.hero, borderRadius: AppRadius.card),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.s20, horizontal: AppSpace.s8),
                  child: Row(
                    children: [
                      stat(formatSpan(summary.duration), '时长'),
                      stat(formatVolume(summary.volume), '总容量'),
                      stat('${summary.setCount}', '完成组数'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.s24),
              if (prs.isNotEmpty) ...[
                Text('本次纪录', style: AppText.titleSmall.copyWith(color: c.text)),
                const SizedBox(height: AppSpace.s12),
                Expanded(
                  child: ListView(
                    children: [
                      for (final e in prs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpace.s8),
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: c.surface, borderRadius: AppRadius.card),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpace.s16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
                                    child: Icon(Icons.emoji_events_rounded, size: 22, color: c.accentText),
                                  ),
                                  const SizedBox(width: AppSpace.s12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(byId[e.key]?.nameZh ?? '动作',
                                            style: AppText.body.copyWith(color: c.text, fontWeight: FontWeight.w600)),
                                        Text(e.value.map(prLabel).join(' · '),
                                            style: AppText.label.copyWith(color: c.accentText)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ] else
                const Spacer(),
              _SaveTemplateButton(workoutId: summary.workoutId),
              const SizedBox(height: AppSpace.s12),
              PressScale(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.buttonLarge)),
                  onPressed: () => context.go('/today'),
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 把这次训练存成模板，下次一键带入同样的动作和组数。
class _SaveTemplateButton extends ConsumerStatefulWidget {
  const _SaveTemplateButton({required this.workoutId});
  final String workoutId;

  @override
  ConsumerState<_SaveTemplateButton> createState() => _SaveTemplateButtonState();
}

class _SaveTemplateButtonState extends ConsumerState<_SaveTemplateButton> {
  bool _saved = false;

  Future<void> _save() async {
    final view = await ref.read(workoutRepositoryProvider).loadWorkout(widget.workoutId);
    if (view == null || !mounted) return;
    final name = await promptName(context,
        title: '存为模板', initial: view.workout.name ?? '', hint: '模板名称，如 推日', confirm: '保存');
    if (name == null || !mounted) return;
    await ref.read(planRepositoryProvider).templateFromWorkout(view, name);
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已存为模板，可在「计划 → 模板」里查看')));
  }

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: OutlinedButton.icon(
        onPressed: _saved ? null : _save,
        icon: Icon(_saved ? Icons.check_rounded : Icons.bookmark_add_outlined),
        label: Text(_saved ? '已存为模板' : '存为模板'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.button)),
      ),
    );
  }
}
