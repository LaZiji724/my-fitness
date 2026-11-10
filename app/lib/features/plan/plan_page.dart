import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/app_ui.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/core/widgets/swipe_to_delete.dart';
import 'package:my_fitness/features/plan/plan_math.dart';
import 'package:my_fitness/features/plan/plan_estimate.dart';
import 'package:my_fitness/features/plan/plan_providers.dart';
import 'package:my_fitness/features/plan/plan_repository.dart';
import 'package:my_fitness/features/plan/plan_widgets.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercises_page.dart' show ExercisesBody;
import 'package:my_fitness/features/library/library_providers.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';

const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

/// 「计划」分栏：计划（N 天一循环）、动作库（所有动作）和模板（一次训练的动作清单）。
class PlanPage extends ConsumerStatefulWidget {
  const PlanPage({super.key, this.initialTab = 0});

  /// 0 计划，1 动作库，2 模板
  final int initialTab;

  static const tabLabels = ['计划', '动作库', '模板'];

  /// 地址里 `?tab=` 的写法转成分栏序号：plan / exercises / templates
  static int tabFromQuery(String? q) => switch (q) {
        'exercises' => 1,
        'templates' => 2,
        _ => 0,
      };

  @override
  ConsumerState<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends ConsumerState<PlanPage> {
  late int _tab = widget.initialTab;

  @override
  void didUpdateWidget(PlanPage old) {
    super.didUpdateWidget(old);
    if (old.initialTab != widget.initialTab) _tab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    const gutter = EdgeInsets.symmetric(horizontal: AppSpace.pageGutter);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, 0),
              child: PageHeader(title: '计划'),
            ),
            const SizedBox(height: AppSpace.s8),
            Padding(
              padding: gutter,
              child: SegmentTabs(labels: PlanPage.tabLabels, index: _tab, onChanged: (i) => setState(() => _tab = i)),
            ),
            const SizedBox(height: AppSpace.s16),
            Expanded(
              child: _tab == 1
                  ? const Padding(padding: gutter, child: ExercisesBody())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, 0, AppSpace.pageGutter, AppSpace.s32),
                      children: [if (_tab == 0) const _PlansTab() else const _TemplatesTab()],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 计划

class _PlansTab extends ConsumerWidget {
  const _PlansTab();

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(planRepositoryProvider);
    final result = await promptNewPlan(context);
    if (result == null) return;
    final id = await repo.createPlan(result.name, result.days);
    if (context.mounted) context.push('/plan/$id');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final plans = ref.watch(plansProvider).value ?? const <PlanView>[];
    final templates = ref.watch(templatesProvider).value ?? const <TemplateView>[];
    final today = ref.watch(todayProvider);
    final active = plans.where((p) => p.plan.isActive).firstOrNull;
    final others = plans.where((p) => !p.plan.isActive).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _LibraryEntry(),
        const SizedBox(height: AppSpace.s12),
        if (active != null)
          _ActivePlanCard(plan: active, templates: templates, today: today)
        else
          const EmptyCard(title: '还没有当前计划', hint: '新建一个计划，首页会按它安排每天练什么', icon: AppIcons.calendar),
        const SizedBox(height: AppSpace.s32),
        SectionTitle('我的计划', trailing: Text('${plans.length} 个', style: AppText.label.copyWith(color: c.text3))),
        const SizedBox(height: AppSpace.s12),
        for (final p in others) ...[
          _PlanRow(plan: p),
          const SizedBox(height: AppSpace.s8),
        ],
        const SizedBox(height: AppSpace.s4),
        PressScale(
          child: OutlinedButton.icon(
            onPressed: () => _create(context, ref),
            icon: const Icon(AppIcons.plus, size: 16),
            label: const Text('新建计划'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.button)),
          ),
        ),
      ],
    );
  }
}

/// 计划库入口：不用自己编排，直接选内置计划。
class _LibraryEntry extends ConsumerWidget {
  const _LibraryEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final count = ref.watch(programsProvider).value?.length;
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: () => context.push('/library'),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: c.hero, borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Icon(AppIcons.library, color: c.onHero, size: 24),
          ),
          const SizedBox(width: AppSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('计划库', style: AppText.titleSmall.copyWith(color: c.text)),
                Text(
                  count == null ? '内置训练计划，一键加入' : '$count 个内置计划，增肌、减脂、塑形都有',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label.copyWith(color: c.text2),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.s8),
          Icon(AppIcons.chevronRight, size: 14, color: c.text3),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _ActivePlanCard extends ConsumerWidget {
  const _ActivePlanCard({required this.plan, required this.templates, required this.today});

  final PlanView plan;
  final List<TemplateView> templates;
  final DateTime today;

  String _nameOf(PlanDay? d) {
    if (d?.templateId == null) return '休';
    final t = templates.where((t) => t.template.id == d!.templateId).firstOrNull;
    return t?.template.name ?? '休';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final idx = planDayIndex(startDate: plan.plan.startDate, cycleDays: plan.plan.cycleDays, date: today);
    final todayName = _nameOf(plan.dayAt(idx));
    final rest = plan.dayAt(idx)?.templateId == null;

    return HeroCard(
      onTap: () => context.push('/plan/${plan.plan.id}'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle)),
              const SizedBox(width: AppSpace.s8),
              Text('当前计划', style: AppText.label.copyWith(color: c.onHero2)),
              const Spacer(),
              Text('编辑', style: AppText.label.copyWith(color: c.onHero2)),
              const SizedBox(width: 2),
              Icon(AppIcons.chevronRight, size: 12, color: c.onHero2),
            ],
          ),
          const SizedBox(height: AppSpace.s12),
          Text(plan.plan.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.titleLarge.copyWith(color: c.onHero)),
          const SizedBox(height: AppSpace.s4),
          Text(
            metaLine(['${plan.plan.cycleDays} 天一循环', '今天是第 ${idx + 1} 天', rest ? '今天休息' : '今天练 $todayName']),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.label.copyWith(color: c.onHero2),
          ),
          const SizedBox(height: AppSpace.s20),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(child: _DayChip(date: today.add(Duration(days: i)), isToday: i == 0, name: _dayName(i, idx))),
            ],
          ),
        ],
      ),
    );
  }

  String _dayName(int offset, int todayIdx) {
    final d = plan.dayAt((todayIdx + offset) % plan.plan.cycleDays);
    final n = _nameOf(d);
    return n.length > 2 ? n.substring(0, 2) : n;
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.date, required this.isToday, required this.name});
  final DateTime date;
  final bool isToday;
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rest = name == '休';
    return Column(
      children: [
        Text(_weekdays[date.weekday - 1],
            style: AppText.caption.copyWith(color: isToday ? c.onHero : c.onHero2, fontWeight: isToday ? FontWeight.w700 : FontWeight.w400)),
        const SizedBox(height: 8),
        Container(
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isToday ? c.accent : (rest ? Colors.transparent : c.hero2),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: rest && !isToday ? Border.all(color: c.onHero.withValues(alpha: 0.10), width: 1) : null,
          ),
          child: Text(name,
              maxLines: 1,
              style: AppText.caption.copyWith(
                color: isToday ? c.onAccent : (rest ? c.onHero2 : c.onHero),
                fontWeight: FontWeight.w700,
              )),
        ),
      ],
    );
  }
}

class _PlanRow extends ConsumerWidget {
  const _PlanRow({required this.plan});
  final PlanView plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final used = plan.days.where((d) => d?.templateId != null).length;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      onTap: () => context.push('/plan/${plan.plan.id}'),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.plan.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.titleSmall.copyWith(color: c.text)),
                Text(metaLine(['${plan.plan.cycleDays} 天一循环', '训练 $used 天']), style: AppText.label.copyWith(color: c.text2)),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.s8),
          PressScale(
            child: OutlinedButton(
              onPressed: () => ref.read(planRepositoryProvider).activatePlan(plan.plan.id),
              child: const Text('设为当前'),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ 模板

class _TemplatesTab extends ConsumerWidget {
  const _TemplatesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templatesProvider).value ?? const <TemplateView>[];
    final byId = ref.watch(exerciseByIdProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (templates.isEmpty)
          const EmptyCard(title: '还没有模板', hint: '模板是一次训练的动作清单，开始训练时一键带入'),
        if (templates.isEmpty) const SizedBox(height: AppSpace.s8),
        for (final t in templates) ...[
          SwipeToDelete(
            key: ValueKey(t.template.id),
            onDelete: () => ref.read(planRepositoryProvider).deleteTemplate(t.template.id),
            child: _TemplateCard(view: t, byId: byId),
          ),
          const SizedBox(height: AppSpace.s8),
        ],
        const SizedBox(height: AppSpace.s8),
        PressScale(
          child: OutlinedButton.icon(
            onPressed: () async {
              final name = await promptName(context, title: '新建模板', hint: '模板名称，如 推日', confirm: '创建');
              if (name == null || !context.mounted) return;
              final id = await ref.read(planRepositoryProvider).createTemplate(name);
              if (context.mounted) context.push('/template/$id');
            },
            icon: const Icon(AppIcons.plus, size: 16),
            label: const Text('新建模板'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.button)),
          ),
        ),
      ],
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.view, required this.byId});
  final TemplateView view;
  final Map<String, Exercise> byId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sets = view.exercises.fold<int>(0, (n, e) => n + e.targetSets);
    final est = estimateLabel(view.exercises, byId);
    final names = view.exercises.map((e) => byId[e.exerciseId]?.nameZh).whereType<String>().take(4).join('、');
    return AppCard(
      onTap: () => context.push('/template/${view.template.id}'),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(view.template.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.titleSmall.copyWith(color: c.text)),
                const SizedBox(height: 2),
                Text(metaLine(['${view.exercises.length} 个动作', '$sets 组', est]), style: AppText.label.copyWith(color: c.text2)),
                if (names.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.s8),
                  Text(names, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.label.copyWith(color: c.text3)),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpace.s12),
          Icon(AppIcons.chevronRight, size: 14, color: c.text3),
        ],
      ),
    );
  }
}
