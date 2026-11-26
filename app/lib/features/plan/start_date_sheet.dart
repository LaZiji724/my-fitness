import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/app_ui.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/plan/plan_math.dart';
import 'package:my_fitness/features/plan/plan_providers.dart';
import 'package:my_fitness/features/plan/plan_repository.dart';

/// 开始日期最多往前、往后各选几天。
const startDateRangeDays = 7;

const _weekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/// 「11月26日 周三」。
String startDateLabel(DateTime d) =>
    '${d.month}月${d.day}日 ${_weekdayNames[d.weekday - 1]}';

/// 与今天相差几天的说法：今天、昨天、明天、3 天前、5 天后。
String startDateRelative(DateTime d, DateTime today) {
  final diff = _daysBetween(today, d);
  if (diff == 0) return '今天';
  if (diff == -1) return '昨天';
  if (diff == 1) return '明天';
  return diff < 0 ? '${-diff} 天前' : '$diff 天后';
}

int _daysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// 选「计划开始日期」的底部弹层：今天前后各 [startDateRangeDays] 天，每个日期都带周几。
///
/// 点「确定」返回选中的日期（只含年月日）；点取消或遮罩返回 null。
/// [alignToMonday] 为真时（计划库里按「周一到周日」排的计划），会提示实际从所选日期所在周的周一开始。
Future<DateTime?> showStartDateSheet(
  BuildContext context, {
  required DateTime today,
  String? planName,
  bool alignToMonday = false,
  String confirmLabel = '确定',
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => StartDateSheet(
      today: dateOnly(today),
      planName: planName,
      alignToMonday: alignToMonday,
      confirmLabel: confirmLabel,
    ),
  );
}

/// 「设为当前计划」：先弹出开始日期弹层，确定后把计划设为当前并从所选日期开始。
/// 计划库里的计划按周一至周日排，实际从所选日期所在周的周一开始。
Future<void> activatePlanWithStartDate(
  BuildContext context,
  WidgetRef ref,
  PlanView plan,
) async {
  final fromProgram = plan.plan.sourceProgramId != null;
  final picked = await showStartDateSheet(
    context,
    today: ref.read(todayProvider),
    planName: plan.plan.name,
    alignToMonday: fromProgram,
    confirmLabel: '设为当前计划',
  );
  if (picked == null) return;
  await ref
      .read(planRepositoryProvider)
      .activatePlan(plan.plan.id, startFrom: picked);
  if (!context.mounted) return;
  final start = fromProgram ? mondayOf(picked) : picked;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text('已设为当前计划：从 ${startDateLabel(start)} 开始')),
    );
}

class StartDateSheet extends StatefulWidget {
  const StartDateSheet({
    super.key,
    required this.today,
    this.planName,
    this.alignToMonday = false,
    this.confirmLabel = '确定',
  });

  final DateTime today;
  final String? planName;
  final bool alignToMonday;
  final String confirmLabel;

  @override
  State<StartDateSheet> createState() => _StartDateSheetState();
}

class _StartDateSheetState extends State<StartDateSheet> {
  static const _columns = 5;
  late DateTime _selected = widget.today;

  DateTime _dayAt(int offset) => DateTime(
    widget.today.year,
    widget.today.month,
    widget.today.day + offset,
  );

  void _pick(DateTime d) {
    if (d == _selected) return;
    HapticFeedback.selectionClick();
    setState(() => _selected = d);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final days = [
      for (var i = -startDateRangeDays; i <= startDateRangeDays; i++) _dayAt(i),
    ];
    final rows = (days.length / _columns).ceil();
    final monday = mondayOf(_selected);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.s20,
            AppSpace.s4,
            AppSpace.s20,
            AppSpace.s20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '计划开始日期',
                style: AppText.titleMedium.copyWith(color: c.text),
              ),
              const SizedBox(height: 2),
              Text(
                widget.planName == null
                    ? '今天前后各 $startDateRangeDays 天内任选'
                    : '「${widget.planName}」· 今天前后各 $startDateRangeDays 天内任选',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(color: c.text2),
              ),
              const SizedBox(height: AppSpace.s16),
              _SummaryCard(date: _selected, today: widget.today),
              const SizedBox(height: AppSpace.s16),
              for (var r = 0; r < rows; r++) ...[
                if (r > 0) const SizedBox(height: AppSpace.s8),
                Row(
                  children: [
                    for (var k = 0; k < _columns; k++) ...[
                      if (k > 0) const SizedBox(width: AppSpace.s8),
                      Expanded(
                        child: r * _columns + k < days.length
                            ? _DayCell(
                                date: days[r * _columns + k],
                                today: widget.today,
                                selected: days[r * _columns + k] == _selected,
                                showMonth:
                                    r * _columns + k == 0 ||
                                    days[r * _columns + k].day == 1,
                                onTap: () => _pick(days[r * _columns + k]),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ],
              AnimatedSize(
                duration: AppMotion.standard,
                curve: AppMotion.curve,
                alignment: Alignment.topCenter,
                child: widget.alignToMonday
                    ? Padding(
                        padding: const EdgeInsets.only(top: AppSpace.s12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(
                                AppIcons.calendar,
                                size: 14,
                                color: c.text3,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '这个计划按周一至周日排课，从 ${startDateLabel(monday)} 起算第 1 周',
                                style: AppText.caption.copyWith(
                                  color: c.text2,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              const SizedBox(height: AppSpace.s20),
              Row(
                children: [
                  Expanded(
                    child: PressScale(
                      child: ElevatedButton(
                        style: const ButtonStyle(
                          minimumSize: WidgetStatePropertyAll(
                            Size.fromHeight(AppSize.button),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.s12),
                  Expanded(
                    flex: 2,
                    child: PressScale(
                      child: FilledButton(
                        style: const ButtonStyle(
                          minimumSize: WidgetStatePropertyAll(
                            Size.fromHeight(AppSize.button),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context, _selected),
                        child: Text(widget.confirmLabel),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶部的墨色大卡：当前选中的那天，大字显示「11月26日」和周几。
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.date, required this.today});
  final DateTime date;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final relative = startDateRelative(date, today);
    return Semantics(
      liveRegion: true,
      label: '已选 ${startDateLabel(date)}，$relative',
      child: ExcludeSemantics(
        child: HeroCard(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '从这天开始',
                      style: AppText.caption.copyWith(color: c.onHero2),
                    ),
                    const SizedBox(height: 4),
                    AnimatedSwitcher(
                      duration: AppMotion.fast,
                      switchInCurve: AppMotion.curve,
                      transitionBuilder: (child, anim) =>
                          FadeTransition(opacity: anim, child: child),
                      child: FittedBox(
                        key: ValueKey(date),
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '${date.month}',
                              style: AppText.numLarge.copyWith(color: c.onHero),
                            ),
                            Text(
                              ' 月 ',
                              style: AppText.label.copyWith(color: c.onHero2),
                            ),
                            Text(
                              '${date.day}',
                              style: AppText.numLarge.copyWith(color: c.onHero),
                            ),
                            Text(
                              ' 日',
                              style: AppText.label.copyWith(color: c.onHero2),
                            ),
                            const SizedBox(width: AppSpace.s12),
                            Text(
                              _weekdayNames[date.weekday - 1],
                              style: AppText.titleSmall.copyWith(
                                color: c.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: c.onHero.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  relative,
                  style: AppText.label.copyWith(
                    color: c.onHero,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 日期格：上面周几、中间日、下面「今天」或月份。选中是墨色实心，今天带橙色标记。
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.today,
    required this.selected,
    required this.showMonth,
    required this.onTap,
  });
  final DateTime date;
  final DateTime today;
  final bool selected;
  final bool showMonth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isToday = date == today;
    final isPast = date.isBefore(today);
    final weekend = date.weekday >= DateTime.saturday;
    final fg = selected ? c.bg : (isPast ? c.text2 : c.text);
    final sub = selected ? c.bg.withValues(alpha: 0.7) : c.text3;

    final String? foot = isToday ? '今天' : (showMonth ? '${date.month}月' : null);

    return Semantics(
      button: true,
      selected: selected,
      label: '${startDateLabel(date)}，${startDateRelative(date, today)}',
      onTap: onTap,
      child: ExcludeSemantics(
        child: PressScale(
          scale: PressScale.chipScale,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.curve,
            decoration: BoxDecoration(
              color: selected ? c.text : c.bg,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: selected
                    ? Colors.transparent
                    : (isToday ? c.accent : c.border),
                width: isToday && !selected ? 1.5 : 1,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: onTap,
                child: SizedBox(
                  height: 72,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _weekdayNames[date.weekday - 1],
                        style: AppText.caption.copyWith(
                          color: selected
                              ? sub
                              : (weekend ? c.accentText : c.text3),
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      Text(
                        '${date.day}',
                        style: AppText.numMedium.copyWith(
                          color: fg,
                          height: 1.15,
                        ),
                      ),
                      SizedBox(
                        height: 14,
                        child: foot == null
                            ? null
                            : Text(
                                foot,
                                style: AppText.caption.copyWith(
                                  fontSize: 10,
                                  height: 1.4,
                                  color: selected
                                      ? sub
                                      : (isToday ? c.accentText : c.text3),
                                  fontWeight: isToday
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
