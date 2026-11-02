import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/avatar_view.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/calendar/calendar_math.dart';
import 'package:my_fitness/features/plan/plan_providers.dart';
import 'package:my_fitness/features/plan/plan_repository.dart';
import 'package:my_fitness/features/sync/sync_chip.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';
import 'package:my_fitness/features/workout/workout_summary_page.dart';

String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 5) return '夜深了';
  if (h < 11) return '早上好';
  if (h < 14) return '中午好';
  if (h < 18) return '下午好';
  return '晚上好';
}

/// 「训练」分栏首页：今日计划、开始训练、近 7 天概况与最近训练。
class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  Future<void> _startBlank(BuildContext context, WidgetRef ref) async {
    await ref.read(workoutRepositoryProvider).startWorkout();
    if (context.mounted) context.push('/workout');
  }

  Future<void> _startTemplate(BuildContext context, WidgetRef ref, String templateId, {String? planId}) async {
    await ref
        .read(planRepositoryProvider)
        .startFromTemplate(ref.read(workoutRepositoryProvider), templateId,
            planId: planId, exercises: ref.read(exerciseByIdProvider));
    if (context.mounted) context.push('/workout');
  }

  Future<void> _pickTemplate(BuildContext context, WidgetRef ref) async {
    final templates = ref.read(templatesProvider).value ?? const <TemplateView>[];
    final c = context.colors;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(AppSpace.s20, AppSpace.s8, AppSpace.s20, AppSpace.s20),
            children: [
              Text('从模板开始', style: AppText.titleMedium.copyWith(color: c.text)),
              const SizedBox(height: AppSpace.s8),
              if (templates.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.s16),
                  child: Text('还没有模板，去「计划 → 模板」新建一个', style: AppText.body.copyWith(color: c.text2)),
                ),
              for (final t in templates)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.template.name, style: AppText.body.copyWith(color: c.text, fontWeight: FontWeight.w600)),
                  subtitle: Text('${t.exercises.length} 个动作', style: AppText.label.copyWith(color: c.text2)),
                  enabled: t.exercises.isNotEmpty,
                  onTap: () => Navigator.pop(ctx, t.template.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && context.mounted) await _startTemplate(context, ref, picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final profile = ref.watch(profileSummaryProvider);
    final active = ref.watch(activeWorkoutProvider).value;
    final entry = ref.watch(todayPlanProvider);
    final today = ref.watch(todayProvider);
    final completed = ref.watch(completedWorkoutsProvider).value ?? const <WorkoutView>[];

    final weekStart = DateTime(today.year, today.month, today.day - 6);
    final recent = completed.where((w) => !w.workout.startedAt.isBefore(weekStart)).toList();
    final days = recent.map((w) => w.workout.localDate).toSet();
    final weekVol = recent.fold<double>(0, (s, w) => s + w.volume);
    final weekSets = recent.fold<int>(0, (s, w) => s + w.setCount);
    final weekMin = recent.fold<int>(0, (s, w) => s + (w.workout.endedAt?.difference(w.workout.startedAt).inMinutes ?? 0));

    final tpl = entry?.template;
    final tplSets = tpl?.exercises.fold<int>(0, (n, e) => n + e.targetSets) ?? 0;

    String heroLabel;
    String heroTitle;
    String heroSub;
    String buttonText;
    VoidCallback onStart;
    if (active != null) {
      heroLabel = '训练进行中';
      heroTitle = active.workout.name ?? '自由训练';
      heroSub = '已添加 ${active.exercises.length} 个动作，点击继续';
      buttonText = '继续训练';
      onStart = () => context.push('/workout');
    } else if (tpl != null) {
      heroLabel = '今日计划 · ${entry!.plan.plan.name}';
      heroTitle = tpl.template.name;
      heroSub = '${tpl.exercises.length} 个动作 · $tplSets 组';
      buttonText = '开始训练';
      onStart = () => _startTemplate(context, ref, tpl.template.id, planId: entry.plan.plan.id);
    } else if (entry != null) {
      heroLabel = '今日计划 · ${entry.plan.plan.name}';
      heroTitle = '今天休息';
      heroSub = '恢复也是训练的一部分，想练也可以随时开始';
      buttonText = '开始空白训练';
      onStart = () => _startBlank(context, ref);
    } else {
      heroLabel = '今日训练';
      heroTitle = '自由训练';
      heroSub = '想练什么就练什么，也可以在「计划」里安排';
      buttonText = '开始训练';
      onStart = () => _startBlank(context, ref);
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.pageGutter),
          children: [
            Row(
              children: [
                Semantics(
                  button: true,
                  label: '我的',
                  child: GestureDetector(
                    onTap: () => context.push('/me'),
                    child: AvatarView(
                      kind: profile?.avatarKind ?? 'preset',
                      avatarRef: profile?.avatarRef ?? 'avatar_01',
                      size: 44,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${greetingFor(DateTime.now())}，${profile?.displayName ?? ''}',
                          style: AppText.titleMedium.copyWith(color: c.text), overflow: TextOverflow.ellipsis),
                      Text(formatMd(today), style: AppText.label.copyWith(color: c.text2)),
                    ],
                  ),
                ),
                const SyncChip(),
              ],
            ),
            const SizedBox(height: AppSpace.s24),
            DecoratedBox(
              decoration: BoxDecoration(color: c.hero, borderRadius: AppRadius.card),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(heroLabel, style: AppText.label.copyWith(color: c.onHero2)),
                    const SizedBox(height: AppSpace.s8),
                    Text(heroTitle, style: AppText.titleMedium.copyWith(color: c.onHero)),
                    const SizedBox(height: AppSpace.s4),
                    Text(heroSub, style: AppText.body.copyWith(color: c.onHero2)),
                    const SizedBox(height: AppSpace.s16),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.buttonLarge)),
                      onPressed: onStart,
                      child: Text(buttonText),
                    ),
                  ],
                ),
              ),
            ),
            if (active == null) ...[
              const SizedBox(height: AppSpace.s12),
              Row(
                children: [
                  if (tpl != null || entry != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _startBlank(context, ref),
                        child: const Text('空白训练'),
                      ),
                    ),
                    const SizedBox(width: AppSpace.s12),
                  ],
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickTemplate(context, ref),
                      child: const Text('从模板开始'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpace.s24),
            Row(
              children: [
                Text('近 7 天', style: AppText.titleSmall.copyWith(color: c.text)),
                const SizedBox(width: AppSpace.s8),
                Text('练了 ${days.length} 天', style: AppText.label.copyWith(color: c.text2)),
              ],
            ),
            const SizedBox(height: AppSpace.s12),
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: _WeekDot(
                      date: DateTime(today.year, today.month, today.day - 6 + i),
                      trained: days.contains(dateKeyOf(DateTime(today.year, today.month, today.day - 6 + i))),
                      isToday: i == 6,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.s16),
            DecoratedBox(
              decoration: BoxDecoration(color: c.surface, borderRadius: AppRadius.card),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.cardPadding),
                child: Row(
                  children: [
                    _Metric(value: (weekVol / 1000).toStringAsFixed(1), unit: '吨', label: '容量'),
                    _Metric(value: '$weekSets', unit: '组', label: '组数'),
                    _Metric(value: (weekMin / 60).toStringAsFixed(1), unit: '小时', label: '时长'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.s24),
            Row(
              children: [
                Text('最近训练', style: AppText.titleSmall.copyWith(color: c.text)),
                const Spacer(),
                TextButton(onPressed: () => context.go('/calendar'), child: const Text('全部记录')),
              ],
            ),
            if (completed.isEmpty)
              DecoratedBox(
                decoration: BoxDecoration(color: c.surface, borderRadius: AppRadius.card),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.cardPadding),
                  child: Center(child: Text('还没有训练记录，开始你的第一次吧', style: AppText.body.copyWith(color: c.text2))),
                ),
              ),
            for (final w in completed.take(3)) ...[
              _RecentRow(view: w),
              const SizedBox(height: AppSpace.s8),
            ],
          ],
        ),
      ),
    );
  }
}

class _WeekDot extends StatelessWidget {
  const _WeekDot({required this.date, required this.trained, required this.isToday});
  final DateTime date;
  final bool trained;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        Text(weekdayNames[date.weekday - 1].substring(1), style: AppText.caption.copyWith(color: c.text3)),
        const SizedBox(height: 6),
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: trained ? c.accent : c.sunken,
            border: isToday && !trained ? Border.all(color: c.accent, width: 1.5) : null,
          ),
          child: Text('${date.day}',
              style: AppText.numSmall.copyWith(color: trained ? c.onAccent : c.text2, fontSize: 15)),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.unit, required this.label});
  final String value;
  final String unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: value, style: AppText.numMedium.copyWith(color: c.text)),
            TextSpan(text: ' $unit', style: AppText.caption.copyWith(color: c.text3)),
          ])),
          Text(label, style: AppText.caption.copyWith(color: c.text3)),
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.view});
  final WorkoutView view;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = view.workout;
    final d = parseLocalDate(w.localDate);
    final minutes = w.endedAt == null ? 0 : w.endedAt!.difference(w.startedAt).inMinutes;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, borderRadius: AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.cardPadding),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Column(
                children: [
                  Text('${d.month}月', style: AppText.caption.copyWith(color: c.text3)),
                  Text('${d.day}', style: AppText.numMedium.copyWith(color: c.text)),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(w.name ?? '自由训练', style: AppText.body.copyWith(color: c.text, fontWeight: FontWeight.w600)),
                  Text('$minutes 分钟 · ${formatVolume(view.volume)} · ${view.setCount} 组',
                      style: AppText.label.copyWith(color: c.text2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

DateTime parseLocalDate(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}
