import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/app_ui.dart';
import 'package:my_fitness/core/widgets/avatar_view.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/calendar/calendar_math.dart';
import 'package:my_fitness/features/plan/plan_estimate.dart';
import 'package:my_fitness/features/plan/plan_providers.dart';
import 'package:my_fitness/features/plan/plan_repository.dart';
import 'package:my_fitness/features/plan/today_overrides.dart';
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
    if (planId != null) {
      // 今日计划：按「模板 + 今天预览里的修改」开始
      await startTodayPlan(ref);
    } else {
      await ref
          .read(planRepositoryProvider)
          .startFromTemplate(ref.read(workoutRepositoryProvider), templateId, exercises: ref.read(exerciseByIdProvider));
    }
    if (context.mounted) context.push('/workout');
  }

  /// 同一天内继续一次已经结束的训练：之前的动作和组数都保留，计时接着走。
  Future<void> _resume(BuildContext context, WidgetRef ref, String workoutId) async {
    final w = await ref.read(workoutRepositoryProvider).resumeWorkout(workoutId);
    if (w == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('现在没法继续这次训练')));
      }
      return;
    }
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
            padding: const EdgeInsets.fromLTRB(AppSpace.s20, AppSpace.s4, AppSpace.s20, AppSpace.s20),
            children: [
              Text('从模板开始', style: AppText.titleMedium.copyWith(color: c.text)),
              const SizedBox(height: AppSpace.s12),
              if (templates.isEmpty)
                const EmptyState(icon: AppIcons.navPlan, title: '还没有模板', hint: '去「计划 → 模板」新建一个', compact: true),
              for (final t in templates) ...[
                AppCard(
                  color: c.bg,
                  radius: AppRadius.md,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  onTap: t.exercises.isEmpty ? null : () => Navigator.pop(ctx, t.template.id),
                  child: Opacity(
                    opacity: t.exercises.isEmpty ? 0.5 : 1,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.template.name, style: AppText.body.copyWith(color: c.text, fontWeight: FontWeight.w600)),
                              Text('${t.exercises.length} 个动作', style: AppText.label.copyWith(color: c.text2)),
                            ],
                          ),
                        ),
                        Icon(AppIcons.chevronRight, size: 14, color: c.text3),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.s8),
              ],
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

    // 最近训练分成「今天」和「过去」：只有今天的才能继续
    final todayKey = dateKeyOf(today);
    final todays = completed.where((w) => w.workout.localDate == todayKey).toList();
    final past = completed.where((w) => w.workout.localDate != todayKey).toList();

    final weekStart = DateTime(today.year, today.month, today.day - 6);
    final recent = completed.where((w) => !w.workout.startedAt.isBefore(weekStart)).toList();
    final days = recent.map((w) => w.workout.localDate).toSet();
    final weekVol = recent.fold<double>(0, (s, w) => s + w.volume);
    final weekSets = recent.fold<int>(0, (s, w) => s + w.setCount);
    final weekMin = recent.fold<int>(0, (s, w) => s + (w.workout.endedAt?.difference(w.workout.startedAt).inMinutes ?? 0));

    // 今天实际要练的量：模板 + 首页预览里对今天的修改
    final tpl = ref.watch(todayEffectiveTemplateProvider);
    final tplSets = tpl?.exercises.fold<int>(0, (n, e) => n + e.targetSets) ?? 0;
    final byId = ref.watch(exerciseByIdProvider);
    // 今日计划卡片里预览前几个动作，开练前心里有数
    final preview = active == null && tpl != null
        ? tpl.exercises.map((e) => byId[e.exerciseId]?.nameZh).whereType<String>().take(4).join('、')
        : '';

    String heroLabel;
    String heroTitle;
    String? heroSub;
    // 有今日模板时，用三个数字代替一句话：动作数、组数、预估分钟
    var heroStats = const <(String, String)>[];
    String buttonText;
    VoidCallback onStart;
    // 除了按钮，点卡片其他地方进入今日预览（有今日模板、且还没开始训练时）
    final canPreview = active == null && tpl != null;
    if (active != null) {
      heroLabel = '训练进行中';
      heroTitle = active.workout.name ?? '自由训练';
      heroSub = '已添加 ${active.exercises.length} 个动作';
      buttonText = '继续训练';
      onStart = () => context.push('/workout');
    } else if (tpl != null) {
      heroLabel = metaLine(['今日计划', entry!.plan.plan.name]);
      heroTitle = tpl.template.name;
      if (tpl.exercises.isEmpty) {
        // 在预览里把今天的动作都去掉了：只能空白开练，点卡片进预览可以恢复
        heroSub = '今天的动作都去掉了，进预览可以恢复';
        buttonText = '开始空白训练';
        onStart = () => _startBlank(context, ref);
      } else {
        final minutes = estimateTemplateMinutes(tpl.exercises, byId);
        heroSub = null;
        heroStats = [
          ('${tpl.exercises.length}', '个动作'),
          ('$tplSets', '组'),
          if (minutes > 0) ('$minutes', '分钟'),
        ];
        buttonText = '开始训练';
        onStart = () => _startTemplate(context, ref, tpl.template.id, planId: entry.plan.plan.id);
      }
    } else if (entry != null) {
      heroLabel = metaLine(['今日计划', entry.plan.plan.name]);
      heroTitle = '今天休息';
      heroSub = '恢复也是训练的一部分';
      buttonText = '开始空白训练';
      onStart = () => _startBlank(context, ref);
    } else {
      heroLabel = '今日训练';
      heroTitle = '自由训练';
      heroSub = '想练什么就练什么';
      buttonText = '开始训练';
      onStart = () => _startBlank(context, ref);
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, AppSpace.s24),
          children: [
            SizedBox(
              height: AppSize.pageHeader,
              child: Row(
                children: [
                  PressScale(
                    scale: PressScale.chipScale,
                    child: Semantics(
                      button: true,
                      label: '我的',
                      child: GestureDetector(
                        onTap: () => context.push('/me'),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.text.withValues(alpha: 0.12), width: 1)),
                          child: AvatarView(
                            kind: profile?.avatarKind ?? 'preset',
                            avatarRef: profile?.avatarRef ?? 'avatar_01',
                            size: 40,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.s12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(formatMd(today), style: AppText.caption.copyWith(color: c.text3)),
                        Text('${greetingFor(DateTime.now())}，${profile?.displayName ?? ''}',
                            style: AppText.titleSmall.copyWith(color: c.text), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SyncChip(),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.s12),
            HeroCard(
              onTap: canPreview ? () => context.push('/today/preview') : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: AppSpace.s8),
                      Expanded(
                        child: Text(heroLabel,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label.copyWith(color: c.onHero2)),
                      ),
                      if (canPreview) ...[
                        Text('预览', style: AppText.label.copyWith(color: c.onHero2)),
                        const SizedBox(width: 2),
                        Icon(AppIcons.chevronRight, size: 12, color: c.onHero2),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpace.s12),
                  Text(heroTitle,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.titleLarge.copyWith(color: c.onHero)),
                  if (heroSub != null) ...[
                    const SizedBox(height: AppSpace.s4),
                    Text(heroSub, style: AppText.label.copyWith(color: c.onHero2)),
                  ],
                  if (heroStats.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.s16),
                    Row(
                      children: [
                        for (var i = 0; i < heroStats.length; i++) ...[
                          if (i > 0) ...[
                            Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 16), color: c.onHero.withValues(alpha: 0.12)),
                          ],
                          Text.rich(TextSpan(children: [
                            TextSpan(text: heroStats[i].$1, style: AppText.numLarge.copyWith(color: c.onHero, height: 1)),
                            TextSpan(text: ' ${heroStats[i].$2}', style: AppText.caption.copyWith(color: c.onHero2)),
                          ])),
                        ],
                      ],
                    ),
                  ],
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.s12),
                    Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.label.copyWith(color: c.onHero2)),
                  ],
                  const SizedBox(height: AppSpace.s20),
                  PressScale(
                    child: FilledButton(
                      style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size.fromHeight(AppSize.buttonLarge))),
                      onPressed: onStart,
                      child: Text(buttonText),
                    ),
                  ),
                ],
              ),
            ),
            if (active == null) ...[
              const SizedBox(height: AppSpace.s12),
              Row(
                children: [
                  if (tpl != null || entry != null) ...[
                    Expanded(
                      child: PressScale(
                        child: ElevatedButton(
                          onPressed: () => _startBlank(context, ref),
                          child: const Text('空白训练'),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.s12),
                  ],
                  Expanded(
                    child: PressScale(
                      child: ElevatedButton(
                        onPressed: () => _pickTemplate(context, ref),
                        child: const Text('从模板开始'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpace.s32),
            SectionTitle('近 7 天', trailing: Text('练了 ${days.length} 天', style: AppText.label.copyWith(color: c.text2))),
            const SizedBox(height: AppSpace.s12),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
                    child: Row(
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
                  ),
                  const HairDivider(),
                  Padding(
                    padding: const EdgeInsets.all(AppSpace.cardPadding),
                    child: Row(
                      children: [
                        _Metric(value: (weekVol / 1000).toStringAsFixed(1), unit: '吨', label: '容量'),
                        _Metric(value: '$weekSets', unit: '组', label: '组数'),
                        _Metric(value: (weekMin / 60).toStringAsFixed(1), unit: '小时', label: '时长'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.s32),
            SectionTitle(
              '最近训练',
              trailing: PressScale(
                child: TextButton(
                  onPressed: () => context.go('/calendar'),
                  style: TextButton.styleFrom(foregroundColor: c.text2, padding: const EdgeInsets.only(left: 12, right: 4)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [const Text('全部记录'), const SizedBox(width: 2), Icon(AppIcons.chevronRight, size: 12, color: c.text3)],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.s4),
            if (completed.isEmpty)
              const AppCard(
                padding: EdgeInsets.zero,
                child: EmptyState(icon: AppIcons.barbell, title: '还没有训练记录', hint: '开始你的第一次吧', compact: true),
              ),
            if (todays.isNotEmpty) ...[
              _GroupTitle(text: '今天', count: todays.length),
              _RecentGroup(children: [
                for (final w in todays)
                  _RecentRow(
                    view: w,
                    // 正在训练时首页上方已经是「继续训练」，这里不再重复给入口
                    onContinue: active == null ? () => _resume(context, ref, w.workout.id) : null,
                  ),
              ]),
            ],
            if (past.isNotEmpty) ...[
              if (todays.isNotEmpty) const SizedBox(height: AppSpace.s12),
              const _GroupTitle(text: '过去'),
              _RecentGroup(children: [for (final w in past.take(3)) _RecentRow(view: w)]),
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
    // 练过的天是墨色实心；今天用橙色（没练是橙圈，练了是橙色实心）
    final fill = trained ? (isToday ? c.accent : c.text) : Colors.transparent;
    final fg = trained ? (isToday ? c.onAccent : c.bg) : (isToday ? c.accentText : c.text2);
    return Column(
      children: [
        Text(weekdayNames[date.weekday - 1].substring(1),
            style: AppText.caption.copyWith(color: isToday ? c.text : c.text3, fontWeight: isToday ? FontWeight.w700 : FontWeight.w400)),
        const SizedBox(height: 8),
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fill,
            border: trained
                ? null
                : Border.all(color: isToday ? c.accent : c.text.withValues(alpha: 0.10), width: isToday ? 1.5 : 1),
          ),
          child: Text('${date.day}', style: AppText.numSmall.copyWith(color: fg)),
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
          Text(label, style: AppText.caption.copyWith(color: c.text3)),
          const SizedBox(height: 2),
          Text.rich(TextSpan(children: [
            TextSpan(text: value, style: AppText.numMedium.copyWith(color: c.text)),
            TextSpan(text: ' $unit', style: AppText.caption.copyWith(color: c.text3)),
          ])),
        ],
      ),
    );
  }
}

/// 「最近训练」里的分组小标题：今天 / 过去。
class _GroupTitle extends StatelessWidget {
  const _GroupTitle({required this.text, this.count});
  final String text;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.s4, AppSpace.s4, AppSpace.s4, AppSpace.s8),
      child: Row(
        children: [
          Text(text, style: AppText.caption.copyWith(color: c.text3, fontWeight: FontWeight.w600)),
          if (count != null && count! > 1) ...[
            const SizedBox(width: AppSpace.s8),
            Text('$count 次', style: AppText.caption.copyWith(color: c.text3)),
          ],
        ],
      ),
    );
  }
}

/// 一组训练记录放进同一张卡片，行与行之间用发丝线隔开。
class _RecentGroup extends StatelessWidget {
  const _RecentGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const HairDivider(indent: 72),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.view, this.onContinue});
  final WorkoutView view;

  /// 不为空时右侧显示小「继续」按钮（只有今天的训练才有）
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = view.workout;
    final d = parseLocalDate(w.localDate);
    final minutes = w.endedAt == null ? 0 : w.endedAt!.difference(w.startedAt).inMinutes;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.cardPadding, vertical: AppSpace.s12),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Text('${d.day}', style: AppText.numMedium.copyWith(color: c.text, height: 1.1)),
                Text('${d.month}月', style: AppText.caption.copyWith(color: c.text3)),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.name ?? '自由训练',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body.copyWith(color: c.text, fontWeight: FontWeight.w600)),
                Text(metaLine(['$minutes 分钟', formatVolume(view.volume), '${view.setCount} 组']),
                    style: AppText.label.copyWith(color: c.text2)),
              ],
            ),
          ),
          if (onContinue != null) ...[
            const SizedBox(width: AppSpace.s12),
            PressScale(
              scale: PressScale.chipScale,
              child: TextButton(
                onPressed: onContinue,
                style: TextButton.styleFrom(
                  backgroundColor: c.accentSoft,
                  foregroundColor: c.accentText,
                  minimumSize: const Size(60, AppSize.buttonSmall),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
                  tapTargetSize: MaterialTapTargetSize.padded,
                  shape: const StadiumBorder(),
                  textStyle: AppText.label.copyWith(fontWeight: FontWeight.w700),
                ),
                child: const Text('继续'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

DateTime parseLocalDate(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}
