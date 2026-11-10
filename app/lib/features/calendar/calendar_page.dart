import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/app_ui.dart';
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
            PageHeader(
              title: '日历',
              trailing: [
                PressScale(
                  child: OutlinedButton(
                    onPressed: _today,
                    style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                    child: const Text('回到今天'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s8),
            AppCard(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${_month.year}年${_month.month}月', style: AppText.titleMedium.copyWith(color: c.text)),
                              Text(metaLine(['${inMonth.length} 次', formatVolume(monthVolume)]), style: AppText.label.copyWith(color: c.text2)),
                            ],
                          ),
                        ),
                        PressScale(
                          scale: PressScale.smallScale,
                          child: IconButton(tooltip: '上个月', onPressed: () => _shift(-1), icon: const Icon(AppIcons.chevronLeft, size: 16)),
                        ),
                        PressScale(
                          scale: PressScale.smallScale,
                          child: IconButton(tooltip: '下个月', onPressed: () => _shift(1), icon: const Icon(AppIcons.chevronRight, size: 16)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.s12),
                  Row(
                    children: [
                      for (final d in const ['一', '二', '三', '四', '五', '六', '日'])
                        Expanded(child: Center(child: Text(d, style: AppText.caption.copyWith(color: c.text3)))),
                    ],
                  ),
                  const SizedBox(height: AppSpace.s8),
            _Grid(
              cells: monthCells(_month),
              today: today,
              selected: _selected,
              onPick: (d) => setState(() => _selected = d),
              trainedFor: (d) => byDay.containsKey(dateKeyOf(d)),
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
                  const SizedBox(height: AppSpace.s8),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: HairDivider()),
                  const SizedBox(height: AppSpace.s12),
                  if (tags.isEmpty)
                    // 没有启用计划：不显示部位图例，提示去启用计划
                    Row(
                      key: const Key('calendar-no-plan-hint'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(AppIcons.calendar, size: 16, color: c.text3),
                        const SizedBox(width: 6),
                        Text('启用计划以显示每日训练任务', style: AppText.caption.copyWith(color: c.text3)),
                      ],
                    )
                  else
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 16,
                      runSpacing: 8,
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
                              const SizedBox(width: 6),
                              Text(t.name, style: AppText.caption.copyWith(color: c.text2)),
                            ],
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.s32),
            SectionTitle(formatMd(_selected)),
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
    required this.trainedFor,
  });

  final List<DateTime?> cells;
  final DateTime today;
  final DateTime selected;
  final ValueChanged<DateTime> onPick;
  final List<Color> Function(DateTime) dotsFor;
  /// 计划里这天要练但还没练：返回标签色（画成空心圈）；不用练返回 null。
  final Color? Function(DateTime) plannedFor;
  /// 这天是否练过（连续天数要跨月、跨行算，所以对任意日期都能回答）。
  final bool Function(DateTime) trainedFor;

  static const double _cellHeight = 56;
  static const double _radius = AppRadius.md;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // 点选的格子用墨色实心，和「练过」的淡橙、「今天」的橙圈都分得开
    final selectedFill = c.text;
    final rows = cells.length ~/ 7;
    return Column(
      children: [
        for (var r = 0; r < rows; r++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _buildRow(context, c, selectedFill, [for (var i = 0; i < 7; i++) cells[r * 7 + i]]),
          ),
      ],
    );
  }

  Widget _buildRow(BuildContext context, AppColors c, Color selectedFill, List<DateTime?> week) {
    final trained = [for (final d in week) d != null && trainedFor(d)];
    // 同一行里相邻的练过的天连成一段：段首、段尾、这一段在本行的格数
    final segStart = List<bool>.filled(7, false);
    final segEnd = List<bool>.filled(7, false);
    final segLen = List<int>.filled(7, 0);
    for (var i = 0; i < 7; i++) {
      if (!trained[i]) continue;
      segStart[i] = i == 0 || !trained[i - 1];
      segEnd[i] = i == 6 || !trained[i + 1];
    }
    for (var i = 0; i < 7; i++) {
      if (!segStart[i]) continue;
      var j = i;
      while (j < 6 && trained[j + 1]) {
        j++;
      }
      segLen[j] = j - i + 1; // 记在段尾，段尾格负责写「连续N天」
    }

    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Builder(builder: (_) {
              final d = week[i];
              if (d == null) return const SizedBox(height: _cellHeight);
              final isSel = dateKeyOf(d) == dateKeyOf(selected);
              final isToday = dateKeyOf(d) == dateKeyOf(today);
              final dots = dotsFor(d);
              final plannedColor = plannedFor(d);
              final streak = segEnd[i] && segLen[i] >= 2 ? streakLength(d, trainedFor) : 0;
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
                    child: SizedBox(
                      height: _cellHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // 底层：练过的天淡橙色底框；相邻天之间不留缝，只有两端是圆角，连成长框
                          if (trained[i])
                            Positioned.fill(
                              child: Container(
                                margin: EdgeInsets.only(left: segStart[i] ? 1 : 0, right: segEnd[i] ? 1 : 0),
                                decoration: BoxDecoration(
                                  color: c.accentSoft,
                                  borderRadius: BorderRadius.horizontal(
                                    left: Radius.circular(segStart[i] ? _radius : 0),
                                    right: Radius.circular(segEnd[i] ? _radius : 0),
                                  ),
                                ),
                              ),
                            ),
                          // 点选的框（更深）和今天的描边
                          if (isSel || isToday)
                            Positioned.fill(
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                decoration: BoxDecoration(
                                  color: isSel ? selectedFill : null,
                                  borderRadius: BorderRadius.circular(_radius),
                                  border: isToday ? Border.all(color: c.accent, width: 1.5) : null,
                                ),
                              ),
                            ),
                          Positioned.fill(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${d.day}',
                                    style: AppText.numSmall.copyWith(
                                      color: isSel ? c.bg : (isToday ? c.accentText : c.text),
                                      fontWeight: isToday || isSel || trained[i] ? FontWeight.w700 : FontWeight.w500,
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
                          // 连续两天以上：长框右上角写小字（选中这格时让给墨色格子）
                          if (streak >= 2 && !isSel)
                            Positioned(
                              top: 4,
                              right: 8,
                              width: 96,
                              child: Text(
                                '连续$streak天',
                                key: Key('calendar-streak-${dateKeyOf(d)}'),
                                textAlign: TextAlign.right,
                                softWrap: false,
                                style: AppText.caption.copyWith(height: 1, color: c.accentText, fontWeight: FontWeight.w600),
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
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(w.name ?? '自由训练', style: AppText.titleSmall.copyWith(color: c.text))),
              Text(formatClock(w.startedAt), style: AppText.numSmall.copyWith(color: c.text3, fontWeight: FontWeight.w500)),
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
          const SizedBox(height: AppSpace.s16),
          const HairDivider(),
          const SizedBox(height: AppSpace.s8),
          for (final b in view.exercises) _ExerciseLine(block: b, exercise: byId[b.exercise.exerciseId]),
        ],
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
          Text(label, style: AppText.caption.copyWith(color: c.text3)),
          const SizedBox(height: 2),
          Text(value, style: AppText.numMedium.copyWith(color: c.text)),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(exercise?.nameZh ?? '动作', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label.copyWith(color: c.text)),
          ),
          const SizedBox(width: AppSpace.s12),
          Text('${done.length} 组', style: AppText.label.copyWith(color: c.text3)),
          if (best.isNotEmpty) ...[
            const SizedBox(width: AppSpace.s12),
            SizedBox(
              width: 88,
              child: Text(best, textAlign: TextAlign.right, style: AppText.label.copyWith(color: c.text2, fontWeight: FontWeight.w500)),
            ),
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
        ? AppIcons.calendarOff
        : rest
            ? AppIcons.rest
            : AppIcons.barbell;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: c.text.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Icon(icon, size: 22, color: planned ? c.text : c.text3),
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
    );
  }
}
