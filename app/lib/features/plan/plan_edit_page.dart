import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/app_ui.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/plan/plan_providers.dart';
import 'package:my_fitness/features/plan/plan_repository.dart';
import 'package:my_fitness/features/plan/plan_widgets.dart';

/// 编辑计划：改名、循环天数、每一天练哪个模板，并可设为当前计划。
class PlanEditPage extends ConsumerWidget {
  const PlanEditPage({super.key, required this.planId});
  final String planId;

  Future<void> _pickTemplate(BuildContext context, WidgetRef ref, PlanView plan, int dayIndex) async {
    final templates = ref.read(templatesProvider).value ?? const <TemplateView>[];
    final current = plan.dayAt(dayIndex)?.templateId;
    final repo = ref.read(planRepositoryProvider);
    final c = context.colors;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(AppSpace.s20, AppSpace.s4, AppSpace.s20, AppSpace.s20),
            children: [
              Text('第 ${dayIndex + 1} 天练什么', style: AppText.titleMedium.copyWith(color: c.text)),
              const SizedBox(height: AppSpace.s12),
              _Choice(
                label: '休息',
                selected: current == null,
                onTap: () async {
                  await repo.setPlanDay(plan.plan.id, dayIndex, null);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
              for (final t in templates)
                _Choice(
                  label: t.template.name,
                  sub: '${t.exercises.length} 个动作',
                  selected: current == t.template.id,
                  onTap: () async {
                    await repo.setPlanDay(plan.plan.id, dayIndex, t.template.id);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
              if (templates.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.s12),
                  child: Text('还没有模板，先去「计划 → 模板」新建一个', style: AppText.label.copyWith(color: c.text3)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final repo = ref.watch(planRepositoryProvider);
    final async = ref.watch(plansProvider);
    final templates = ref.watch(templatesProvider).value ?? const <TemplateView>[];
    final plan = async.value?.where((p) => p.plan.id == planId).firstOrNull;

    if (plan == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: async.isLoading
              ? const CircularProgressIndicator()
              : Text('计划不存在', style: AppText.body.copyWith(color: c.text2)),
        ),
      );
    }

    String nameOf(int i) {
      final tid = plan.dayAt(i)?.templateId;
      if (tid == null) return '休息';
      return templates.where((t) => t.template.id == tid).firstOrNull?.template.name ?? '休息';
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () async {
            final name = await promptName(context, title: '重命名计划', initial: plan.plan.name);
            if (name != null) await repo.renamePlan(planId, name);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(plan.plan.name, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Icon(AppIcons.editSmall, size: 16, color: c.text3),
            ],
          ),
        ),
        actions: [
          PressScale(
            child: PopupMenuButton<String>(
              tooltip: '更多',
              icon: const Icon(AppIcons.more),
              onSelected: (v) async {
                if (v == 'delete') {
                  final ok = await confirmDialog(context,
                      title: '删除计划', message: '删除「${plan.plan.name}」？已完成的训练记录不受影响。', confirm: '删除');
                  if (!ok) return;
                  await repo.deletePlan(planId);
                  if (context.mounted) context.pop();
                }
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('删除计划'))],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, 160),
        children: [
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.cardPadding, vertical: 6),
            child: StepperField(
              label: '几天一循环',
              value: plan.plan.cycleDays,
              min: 1,
              max: 28,
              unit: ' 天',
              onChanged: (v) => repo.setCycleDays(planId, v),
            ),
          ),
          const SizedBox(height: AppSpace.s32),
          const SectionTitle('每天练什么'),
          const SizedBox(height: AppSpace.s12),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < plan.plan.cycleDays; i++) ...[
                  if (i > 0) const HairDivider(indent: 80),
                  PressScale(
                    scale: PressScale.cardScale,
                    child: InkWell(
                      onTap: () => _pickTemplate(context, ref, plan, i),
                      child: SizedBox(
                        height: 56,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpace.cardPadding),
                          child: Row(
                            children: [
                              SizedBox(width: 64, child: Text('第 ${i + 1} 天', style: AppText.label.copyWith(color: c.text3))),
                              Expanded(
                                child: Text(
                                  nameOf(i),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.body.copyWith(
                                    color: plan.dayAt(i)?.templateId == null ? c.text3 : c.text,
                                    fontWeight: plan.dayAt(i)?.templateId == null ? FontWeight.w400 : FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(AppIcons.chevronRight, size: 14, color: c.text3),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        child: plan.plan.isActive
            ? PressScale(
                child: ElevatedButton(
                  style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size.fromHeight(AppSize.buttonLarge))),
                  onPressed: () => repo.deactivatePlan(planId),
                  child: const Text('当前计划，点击停用'),
                ),
              )
            : PressScale(
                child: FilledButton(
                  style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size.fromHeight(AppSize.buttonLarge))),
                  onPressed: () => repo.activatePlan(planId),
                  child: const Text('设为当前计划（从今天开始）'),
                ),
              ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap, this.sub});
  final String label;
  final String? sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.s8),
      child: AppCard(
        color: selected ? c.surface : c.bg,
        radius: AppRadius.md,
        borderColor: selected ? c.text : null,
        borderWidth: selected ? 1.5 : AppStroke.hairline,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppText.body.copyWith(color: c.text, fontWeight: FontWeight.w600)),
                  if (sub != null) Text(sub!, style: AppText.label.copyWith(color: c.text2)),
                ],
              ),
            ),
            if (selected) Icon(AppIcons.check, size: 18, color: c.text),
          ],
        ),
      ),
    );
  }
}
