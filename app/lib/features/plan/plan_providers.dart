import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/db/database_provider.dart';
import 'package:my_fitness/core/supabase/supabase_providers.dart';
import 'package:my_fitness/features/plan/plan_math.dart';
import 'package:my_fitness/features/plan/plan_repository.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

final planRepositoryProvider = Provider<PlanRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return PlanRepository(
    ref.watch(appDatabaseProvider),
    userId: () => client.auth.currentUser?.id ?? 'local',
  );
});

final templatesProvider = StreamProvider<List<TemplateView>>(
  (ref) => ref.watch(planRepositoryProvider).watchTemplates(),
);

final plansProvider = StreamProvider<List<PlanView>>(
  (ref) => ref.watch(planRepositoryProvider).watchPlans(),
);

/// 计划在某一天的安排。
class PlanEntry {
  const PlanEntry({
    required this.plan,
    required this.dayIndex,
    required this.template,
  });

  final PlanView plan;

  /// 0 起始
  final int dayIndex;

  /// 为 null 表示休息日
  final TemplateView? template;

  bool get isRest => template == null;
}

/// 当前计划在 [date] 这天的安排；没有当前计划时为 null。
PlanEntry? planEntryFor(DateTime date, List<PlanView> plans, List<TemplateView> templates) {
  final active = plans.where((p) => p.plan.isActive).firstOrNull;
  if (active == null) return null;
  final idx = planDayIndex(
    startDate: active.plan.startDate,
    cycleDays: active.plan.cycleDays,
    date: date,
  );
  final tid = active.dayAt(idx)?.templateId;
  final tpl = tid == null ? null : templates.where((t) => t.template.id == tid).firstOrNull;
  return PlanEntry(plan: active, dayIndex: idx, template: tpl);
}

/// 今天的日期（本地）。单独做成 provider 方便测试覆盖。
final todayProvider = Provider<DateTime>((ref) => dateOnly(DateTime.now()));

final todayPlanProvider = Provider<PlanEntry?>((ref) {
  final plans = ref.watch(plansProvider).value;
  final templates = ref.watch(templatesProvider).value;
  if (plans == null || templates == null) return null;
  return planEntryFor(ref.watch(todayProvider), plans, templates);
});

/// 全部已完成的训练，最新在前。数据量对个人使用很小，首页、日历、统计共用。
final completedWorkoutsProvider = StreamProvider<List<WorkoutView>>(
  (ref) => ref.watch(workoutRepositoryProvider).watchCompleted(),
);
