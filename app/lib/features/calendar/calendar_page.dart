import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/calendar/calendar_math.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/plan/part_colors.dart';
import 'package:my_fitness/features/plan/plan_providers.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';
import 'package:my_fitness/features/workout/workout_summary_page.dart';

/// 「日历」分栏：按月看训练记录，点某天看当天的训练明细。
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final t = ref.read(todayProvider);
    _month = DateTime(t.year, t.month);
    _selected = t;
  }

  void _shift(int delta) => setState(() => _month = DateTime(_month.year, _month.month + delta));

  void _today() {
    final t = ref.read(todayProvider);
    setState(() {
      _month = DateTime(t.year, t.month);
      _selected = t;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = ref.watch(todayProvider);
    final all = ref.watch(completedWorkoutsProvider).value ?? const <WorkoutView>[];
    final byId = ref.watch(exerciseByIdProvider);
    final plans = ref.watch(plansProvider).value ?? const [];
    final templates = ref.watch(templatesProvider).value ?? const [];

    final byDay = <String, List<WorkoutView>>{};
    for (final w in all) {
      byDay.putIfAbsent(w.workout.localDate, () => []).add(w);
    }
    final monthKey = '${_month.year.toString().padLeft(4, '0')}-${_month.month.toString().padLeft(2, '0')}';
    final inMonth = all.where((w) => w.workout.localDate.startsWith(monthKey)).toList();
    final monthVolume = inMonth.fold<double>(0, (s, w) => s + w.volume);

    Set<BodyPart> partsOf(List<WorkoutView> ws) => {
          for (final w in ws)
            for (final b in w.exercises)
              if (byId[b.exercise.exerciseId] != null) byId[b.exercise.exerciseId]!.bodyPart,
        };

    final selectedWorkouts = byDay[dateKeyOf(_selected)] ?? const <WorkoutView>[];
    final selectedPlan = planEntryFor(_selected, plans, templates);

    // 标签文字和颜色都来自当前计划里每天安排的模板：改模板名、换每天的安排，日历立刻跟着变。
    final tags = planTags(plans, templates, byId);
    final tagByName = {for (final t in tags) t.name: partColor(c, t.part)};
    final tagById = {for (final t in tags) t.id: partColor(c, t.part)};

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, AppSpace.s32),
          children: [
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  Text('日历', style: AppText.titleLarge.copyWith(color: c.text)),
                  const Spacer(),
                  PressScale(child: TextButton(onPressed: _today, child: const Text('回到今天'))),
                ],
              ),
            ),
            Row(
              children: [
                PressScale(scale: PressScale.smallScale, child: IconButton(tooltip: '上个月', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded))),
                Expanded(
                  child: Column(
                    children: [
                      Text('${_month.year}年${_month.month}月', style: AppText.titleSmall.copyWith(color: c.text)),
                      Text('${inMonth.length} 次 · ${formatVolume(monthVolume)}',
                          style: AppText.label.copyWith(color: c.text2)),
                    ],
                  ),
                ),
                PressScale(scale: PressScale.smallScale, child: IconButton(tooltip: '下个月', onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right_rounded))),
              ],
            ),
            const SizedBox(height: AppSpace.s8),
            Row(
              children: [
                for (final d in const ['一', '二', '三', '四', '五', '六', '日'])
                  Expanded(child: Center(child: Text(d, style: AppText.label.copyWith(color: c.text3)))),
              ],
            ),
            const SizedBox(height: AppSpace.s4),
            _Grid(
              cells: monthCells(_month),
              today: today,
              selected: _selected,
              onPick: (d) => setState(() => _selected = d),
              dotsFor: (d) {
                final ws = byDay[dateKeyOf(d)];
                if (ws == null) return const [];
                final colors = <Color>[];
                void add(Color col) {
                  if (!colors.contains(col)) colors.add(col);
                }
                for (final w in ws) {
                  final tagColor = tagByName[w.workout.name];
                  if (tagColor != null) {
                    add(tagColor);
                  } else {
                    for (final p in partsOf([w])) {
                      add(partColor(c, p));
                    }
                  }
                }
                return colors.take(3).toList();
              },
              plannedFor: (d) {
                if (d.isBefore(today) || byDay.containsKey(dateKeyOf(d))) return null;
                final e = planEntryFor(d, plans, templates);
                if (e == null || e.isRest) return null;
                return tagById[e.template!.template.id] ?? c.text3;
              },
            ),
            const SizedBox(height: AppSpace.s12),
            if (tags.isEmpty)
              // 没有启用计划：不显示部位图例，提示去启用计划
              Row(
                key: const Key('calendar-no-plan-hint'),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: c.danger, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('启用计划以显示每日训练任务', style: AppText.label.copyWith(color: c.text2)),
                ],
              )
            else
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 14,
                runSpacing: 6,
                children: [
                  // 图例就是计划里每天练的模板名
                  for (final t in tags)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: partColor(c, t.part), shape: BoxShape.circle)),
                        const SizedBox(width: 5),
                        Text(t.name, style: AppText.label.copyWith(color: c.text2)),
                      ],
                    ),
                ],
              ),
            const SizedBox(height: AppSpace.s24),
            Text(formatMd(_selected), style: AppText.titleSmall.copyWith(color: c.text)),
            const SizedBox(height: AppSpace.s12),
            if (selectedWorkouts.isEmpty)
              _EmptyDay(
                planned: selectedPlan != null && !_selected.isBefore(today),
                text: selectedPlan != null && !_selected.isBefore(today)
                    ? (selectedPlan.isRest ? '计划：休息' : '计划：${selectedPlan.template!.template.name}')
                    : '这天没有训练记录',
                rest: selectedPlan?.isRest ?? false,
              )
            else
              for (final w in selectedWorkouts) ...[
                _WorkoutCard(view: w, byId: byId),
                const SizedBox(height: AppSpace.s12),
              ],
          ],
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.cells,
    required this.today,
    required this.selected,
    required this.onPick,
    required this.dotsFor,
    required this.plannedFor,
  });

  final List<DateTime?> cells;
  final DateTime today;
  final DateTime selected;
  final ValueChanged<DateTime> onPick;
  final List<Color> Function(DateTime) dotsFor;
  /// 计划里这天要练但还没练：返回标签色（画成空心圈）；不用练返回 null。
  final Color? Function(DateTime) plannedFor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = cells.length ~/ 7;
    return Column(
      children: [
        for (var r = 0; r < rows; r++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Builder(builder: (_) {
                      final d = cells[r * 7 + i];
                      if (d == null) return const SizedBox(height: 50);
                      final isSel = dateKeyOf(d) == dateKeyOf(selected);
                      final isToday = dateKeyOf(d) == dateKeyOf(today);
                      final dots = dotsFor(d);
                      final plannedColor = plannedFor(d);
                      return PressScale(
                        scale: PressScale.chipScale,
                        child: Semantics(
                          button: true,
                          excludeSemantics: true,
                          selected: isSel,
                          label: '${d.month}月${d.day}日${dots.isNotEmpty ? '，有训练' : ''}',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onPick(d),
                            child: Container(
                              height: 50,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: isSel ? c.accentSoft : Colors.transparent,
                                borderRadius: BorderRadius.circular(14),
                                border: isToday && !isSel ? Border.all(color: c.accent, width: 1.5) : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${d.day}',
                                    style: AppText.numSmall.copyWith(
                                      fontSize: 18,
                                      color: isSel ? c.accentText : c.text,
                                      fontWeight: isToday || isSel ? FontWeight.w700 : FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    height: 6,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        for (final col in dots)
                                          Container(
                                            width: 6,
                                            height: 6,
                                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                            decoration: BoxDecoration(color: col, shape: BoxShape.circle),
                                          ),
                                        if (dots.isEmpty && plannedColor != null)
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(color: plannedColor, width: 1.2),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({required this.view, required this.byId});
  final WorkoutView view;
  final Map<String, Exercise> byId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = view.workout;
    final minutes = w.endedAt == null ? 0 : w.endedAt!.difference(w.startedAt).inMinutes;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, borderRadius: AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(w.name ?? '自由训练', style: AppText.titleSmall.copyWith(color: c.text))),
                Text(formatClock(w.startedAt), style: AppText.label.copyWith(color: c.text3)),
              ],
            ),
            const SizedBox(height: AppSpace.s12),
            Row(
              children: [
                _Stat('$minutes', '分钟'),
                _Stat(formatVolume(view.volume), '容量'),
                _Stat('${view.setCount}', '组数'),
              ],
            ),
            const Divider(height: AppSpace.s24),
            for (final b in view.exercises) _ExerciseLine(block: b, exercise: byId[b.exercise.exerciseId]),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppText.numMedium.copyWith(color: c.text)),
          Text(label, style: AppText.caption.copyWith(color: c.text3)),
        ],
      ),
    );
  }
}

class _ExerciseLine extends StatelessWidget {
  const _ExerciseLine({required this.block, required this.exercise});
  final ExerciseBlock block;
  final Exercise? exercise;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = block.sets.where((s) => s.completed && s.kind != 'warmup').toList();
    var best = '';
    if (done.isNotEmpty) {
      final top = done.reduce((a, b) => (b.weightKg ?? 0) > (a.weightKg ?? 0) ? b : a);
      final kg = top.weightKg;
      best = kg != null && kg > 0
          ? '${kg == kg.roundToDouble() ? kg.toInt() : kg} kg × ${top.reps ?? 0}'
          : (top.reps != null ? '${top.reps} 次' : '${top.durationSec ?? 0} 秒');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(exercise?.nameZh ?? '动作', style: AppText.body.copyWith(color: c.text))),
          Text('${done.length} 组', style: AppText.label.copyWith(color: c.text3)),
          if (best.isNotEmpty) ...[
            const SizedBox(width: AppSpace.s12),
            Text(best, style: AppText.label.copyWith(color: c.text2)),
          ],
        ],
      ),
    );
  }
}

/// 选中日没有训练记录时的提示：有计划就显示当天安排，否则一句空状态。
class _EmptyDay extends StatelessWidget {
  const _EmptyDay({required this.planned, required this.text, required this.rest});
  final bool planned;
  final String text;
  final bool rest;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final icon = !planned
        ? Icons.event_busy_outlined
        : rest
            ? Icons.self_improvement_rounded
            : Icons.fitness_center_rounded;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, borderRadius: AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.cardPadding),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: planned && !rest ? c.accentSoft : c.sunken,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, size: 20, color: planned && !rest ? c.accentText : c.text3),
            ),
            const SizedBox(width: AppSpace.s12),
            Expanded(
              child: Text(text,
                  style: AppText.body.copyWith(
                    color: planned ? c.text : c.text2,
                    fontWeight: planned ? FontWeight.w600 : FontWeight.w400,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}
