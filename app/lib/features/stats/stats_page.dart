import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/plan/plan_providers.dart';
import 'package:my_fitness/features/stats/muscle_figure.dart';
import 'package:my_fitness/features/stats/stats_math.dart';
import 'package:my_fitness/features/stats/stats_providers.dart';
import 'package:my_fitness/features/workout/number_pad_sheet.dart';
import 'package:my_fitness/features/workout/workout_math.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

/// 「数据」分栏：区间概览、肌肉热度、趋势、对比、个人纪录、体重。
class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final view = ref.watch(statsViewProvider);
    final today = ref.watch(todayProvider);
    final all = ref.watch(completedWorkoutsProvider).value ?? const <WorkoutView>[];
    final byId = ref.watch(exerciseByIdProvider);
    final range = view.range;
    final window = view.window;
    final prev = shiftWindow(range, window, -1);
    final now = inWindow(all, window);
    final before = inWindow(all, prev);
    final k = kpisFor(now);
    final kPrev = kpisFor(before);
    // 下一段的第一天不晚于今天才允许翻过去
    final canGoNext = !window.end.isAfter(today);
    final notifier = ref.read(statsViewProvider.notifier);

    final muscle = muscleSets(now, byId);
    final weekly = regionWeeklySets(muscle, window.days);
    final parts = partSets(now, byId);
    final partsPrev = partSets(before, byId);
    final insight = insightFor(parts, days: window.days);

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
                  Text('数据', style: AppText.titleLarge.copyWith(color: c.text)),
                  const Spacer(),
                  _RangeTabs(value: range, onChanged: notifier.setRange),
                ],
              ),
            ),
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  IconButton(tooltip: '上一段', onPressed: () => notifier.shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => notifier.reset(today),
                      child: Center(
                        child: Text(windowLabel(range, window),
                            style: AppText.titleSmall.copyWith(color: c.text)),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '下一段',
                    onPressed: canGoNext ? () => notifier.shift(1) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.s8),
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent: 124,
              ),
              children: [
                _KpiCard(label: '训练次数', value: '${k.count}', unit: '次', delta: deltaText(k.count, kPrev.count)),
                _KpiCard(
                  label: '总容量',
                  value: k.volume >= 1000 ? (k.volume / 1000).toStringAsFixed(1) : '${k.volume.round()}',
                  unit: k.volume >= 1000 ? '吨' : 'kg',
                  delta: deltaText(k.volume, kPrev.volume),
                ),
                _KpiCard(label: '完成组数', value: '${k.sets}', unit: '组', delta: deltaText(k.sets, kPrev.sets)),
                _KpiCard(
                  label: '训练时长',
                  value: (k.minutes / 60).toStringAsFixed(1),
                  unit: '小时',
                  delta: deltaText(k.minutes, kPrev.minutes),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sectionGap),
            _Card(
              title: '肌肉部位',
              trailing: '主要肌肉每组计 1，次要计 0.5',
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(children: [
                        MuscleFigure(front: true, weeklySets: weekly, height: 280),
                        Text('正面', style: AppText.label.copyWith(color: c.text3)),
                      ]),
                      Column(children: [
                        MuscleFigure(front: false, weeklySets: weekly, height: 280),
                        Text('背面', style: AppText.label.copyWith(color: c.text3)),
                      ]),
                    ],
                  ),
                  const SizedBox(height: AppSpace.s12),
                  _HeatLegend(range: range),
                  const SizedBox(height: AppSpace.s12),
                  _MuscleList(muscle: muscle),
                  if (insight != null) ...[
                    const SizedBox(height: AppSpace.s12),
                    DecoratedBox(
                      decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpace.s12),
                        child: Row(
                          children: [
                            Icon(Icons.lightbulb_outline_rounded, size: 18, color: c.accentText),
                            const SizedBox(width: AppSpace.s8),
                            Expanded(child: Text(insight, style: AppText.label.copyWith(color: c.accentText))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpace.sectionGap),
            _TrendCard(all: all, endDate: window.end.isAfter(today) ? today : window.end.subtract(const Duration(days: 1))),
            const SizedBox(height: AppSpace.sectionGap),
            _CompareCard(range: range, now: parts, before: partsPrev),
            const SizedBox(height: AppSpace.sectionGap),
            _PrCard(all: all, byId: byId),
            const SizedBox(height: AppSpace.sectionGap),
            _BodyWeightCard(today: today),
          ],
        ),
      ),
    );
  }
}

class _RangeTabs extends StatelessWidget {
  const _RangeTabs({required this.value, required this.onChanged});
  final StatRange value;
  final ValueChanged<StatRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.sunken, borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in StatRange.values)
              Semantics(
                button: true,
                selected: r == value,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(r),
                  child: AnimatedContainer(
                    duration: AppMotion.fast,
                    width: 52,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: r == value ? c.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(r.label,
                        style: AppText.label.copyWith(
                          fontSize: 14,
                          color: r == value ? c.text : c.text2,
                          fontWeight: r == value ? FontWeight.w700 : FontWeight.w500,
                        )),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value, required this.unit, required this.delta});
  final String label;
  final String value;
  final String unit;
  final String? delta;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final up = delta?.startsWith('+') ?? false;
    final down = delta?.startsWith('−') ?? false;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: AppText.label.copyWith(color: c.text2)),
            const SizedBox(height: 2),
            Text.rich(TextSpan(children: [
              TextSpan(text: value, style: AppText.numLarge.copyWith(color: c.text)),
              TextSpan(text: ' $unit', style: AppText.label.copyWith(color: c.text2)),
            ])),
            const SizedBox(height: 4),
            if (delta != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: BoxDecoration(
                  color: up ? c.success.withValues(alpha: 0.15) : c.sunken,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('较上期 $delta',
                    style: AppText.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: up ? c.success : (down ? c.text2 : c.text3),
                    )),
              )
            else
              Text('上期没有数据', style: AppText.caption.copyWith(color: c.text3)),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.trailing});
  final String title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(title, style: AppText.titleSmall.copyWith(color: c.text, fontSize: 17)),
                if (trailing != null) ...[
                  const Spacer(),
                  Flexible(
                    child: Text(trailing!,
                        textAlign: TextAlign.end,
                        style: AppText.caption.copyWith(color: c.text3, fontSize: 12)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpace.s12),
            child,
          ],
        ),
      ),
    );
  }
}

class _HeatLegend extends StatelessWidget {
  const _HeatLegend({required this.range});
  final StatRange range;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('少', style: AppText.caption.copyWith(color: c.text3)),
        const SizedBox(width: 6),
        for (final col in c.heat)
          Container(width: 22, height: 8, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text('多（每周平均组数）', style: AppText.caption.copyWith(color: c.text3)),
      ],
    );
  }
}

class _MuscleList extends StatelessWidget {
  const _MuscleList({required this.muscle});
  final Map<String, double> muscle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final entries = muscle.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return Center(child: Text('这段时间还没有训练记录', style: AppText.label.copyWith(color: c.text3)));
    }
    final top = entries.take(6).toList();
    final maxV = top.first.value;
    return Column(
      children: [
        for (final e in top)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(width: 72, child: Text(muscleZh(e.key), style: AppText.label.copyWith(color: c.text))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: e.value / maxV,
                      minHeight: 8,
                      backgroundColor: c.sunken,
                      valueColor: AlwaysStoppedAnimation(c.accent),
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text('${_fmt(e.value)} 组',
                      textAlign: TextAlign.end, style: AppText.label.copyWith(color: c.text2)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _fmt(double v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);

class _TrendCard extends ConsumerWidget {
  const _TrendCard({required this.all, required this.endDate});
  final List<WorkoutView> all;
  final DateTime endDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final metric = ref.watch(trendMetricProvider);
    final bars = weeklyTrend(all, metric, endDate);
    final maxV = bars.fold<double>(0, (m, b) => b.value > m ? b.value : m);
    final cur = bars.last.value;
    return _Card(
      title: '趋势 · 近 8 周',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            children: [
              for (final m in TrendMetric.values)
                ChoiceChip(
                  label: Text(m.label),
                  selected: m == metric,
                  showCheckmark: false,
                  onSelected: (_) => ref.read(trendMetricProvider.notifier).set(m),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.s12),
          Text.rich(TextSpan(children: [
            TextSpan(text: metric == TrendMetric.sets || metric == TrendMetric.count ? '${cur.round()}' : cur.toStringAsFixed(1), style: AppText.numLarge.copyWith(color: c.text)),
            TextSpan(text: ' ${metric.unit} · 当周', style: AppText.label.copyWith(color: c.text2)),
          ])),
          const SizedBox(height: AppSpace.s12),
          SizedBox(
            height: 136,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < bars.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AnimatedContainer(
                            duration: AppMotion.standard,
                            curve: AppMotion.curve,
                            height: maxV <= 0 ? 4 : (4 + (bars[i].value / maxV) * 80),
                            decoration: BoxDecoration(
                              color: i == bars.length - 1 ? c.accent : c.chartBar,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text('${bars[i].weekStart.month}/${bars[i].weekStart.day}',
                              style: AppText.caption.copyWith(color: c.text3, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompareCard extends StatelessWidget {
  const _CompareCard({required this.range, required this.now, required this.before});
  final StatRange range;
  final Map<BodyPart, int> now;
  final Map<BodyPart, int> before;

  int _sum(Map<BodyPart, int> m, List<BodyPart> ps) => ps.fold<int>(0, (s, p) => s + (m[p] ?? 0));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final groups = <(String, List<BodyPart>)>[
      ('胸', [BodyPart.chest]),
      ('背', [BodyPart.back]),
      ('腿臀', [BodyPart.legs, BodyPart.glutes]),
      ('肩', [BodyPart.shoulders]),
      ('手臂', [BodyPart.arms]),
      ('核心', [BodyPart.core]),
    ];
    final maxV = groups.fold<int>(1, (m, g) {
      final a = _sum(now, g.$2), b = _sum(before, g.$2);
      return [m, a, b].reduce((x, y) => x > y ? x : y);
    });
    final label = '本${range.label}';
    final prevLabel = '上${range.label}';
    return _Card(
      title: '$label vs $prevLabel',
      trailing: '各部位完成组数',
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _Dot(color: c.accent, text: label),
              const SizedBox(width: AppSpace.s12),
              _Dot(color: c.info, text: prevLabel),
            ],
          ),
          const SizedBox(height: AppSpace.s8),
          for (final g in groups)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(width: 44, child: Text(g.$1, style: AppText.label.copyWith(color: c.text))),
                  Expanded(
                    child: Column(
                      children: [
                        _Bar(value: _sum(now, g.$2) / maxV, color: c.accent),
                        const SizedBox(height: 3),
                        _Bar(value: _sum(before, g.$2) / maxV, color: c.info),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text('${_sum(now, g.$2)} / ${_sum(before, g.$2)}',
                        textAlign: TextAlign.end, style: AppText.numSmall.copyWith(color: c.text2, fontSize: 15)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(text, style: AppText.caption.copyWith(color: c.text2)),
    ]);
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color});
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: 6,
        backgroundColor: c.sunken,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

class _PrCard extends StatelessWidget {
  const _PrCard({required this.all, required this.byId});
  final List<WorkoutView> all;
  final Map<String, Exercise> byId;

  String _value(PrEvent p) => switch (p.kind) {
        PrKind.reps => '${p.value.round()} 次',
        _ => '${_fmt(p.value)} kg',
      };

  String _sub(PrEvent p) {
    final d = p.date.split('-');
    final kind = switch (p.kind) {
      PrKind.weight => '重量纪录',
      PrKind.reps => '次数纪录',
      PrKind.oneRepMax => '估算 1RM',
    };
    return '${int.parse(d[1])}月${int.parse(d[2])}日 · $kind';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final prs = prHistory(all, byId, limit: 5);
    return _Card(
      title: '最近的个人纪录',
      child: prs.isEmpty
          ? Text('打破自己的最好成绩后，会出现在这里', style: AppText.label.copyWith(color: c.text3))
          : Column(
              children: [
                for (final p in prs)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(Icons.emoji_events_rounded, size: 20, color: c.accent),
                        const SizedBox(width: AppSpace.s12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(byId[p.exerciseId]?.nameZh ?? '动作',
                                  style: AppText.body.copyWith(color: c.text, fontWeight: FontWeight.w600)),
                              Text(_sub(p), style: AppText.caption.copyWith(color: c.text3)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_value(p), style: AppText.numMedium.copyWith(color: c.text)),
                            Text('+${_fmt(p.value - p.previous)}',
                                style: AppText.caption.copyWith(color: c.success, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _BodyWeightCard extends ConsumerWidget {
  const _BodyWeightCard({required this.today});
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final list = ref.watch(bodyMetricsProvider).value ?? const <BodyMetric>[];
    final last = list.isEmpty ? null : list.last;
    final cutoff = DateTime(today.year, today.month, today.day - 30);
    final cutKey = WorkoutRepository.dateKey(cutoff);
    final recent = list.where((m) => m.date.compareTo(cutKey) >= 0).toList();
    String? delta;
    if (recent.length >= 2) {
      final d = recent.last.weightKg! - recent.first.weightKg!;
      delta = '30 天 ${d >= 0 ? '+' : '−'}${d.abs().toStringAsFixed(1)}';
    }

    Future<void> record() async {
      final v = await showNumberPad(
        context,
        title: '今天的体重',
        unit: 'kg',
        initial: last?.weightKg,
        decimal: true,
        steps: const [0.1, 0.5],
        hint: '空腹晨起记录更稳定',
      );
      if (v == null || v <= 0) return;
      await ref.read(bodyRepositoryProvider).setWeight(today, v);
    }

    return _Card(
      title: '体重',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(
                          text: last == null ? '—' : last.weightKg!.toStringAsFixed(1),
                          style: AppText.numLarge.copyWith(color: c.text)),
                      TextSpan(text: ' kg', style: AppText.label.copyWith(color: c.text2)),
                    ])),
                    if (delta != null) Text(delta, style: AppText.label.copyWith(color: c.text2)),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: record,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
                child: const Text('记录体重'),
              ),
            ],
          ),
          if (recent.length >= 2) ...[
            const SizedBox(height: AppSpace.s12),
            SizedBox(
              height: 64,
              child: CustomPaint(
                size: const Size.fromHeight(64),
                painter: _SparkPainter(values: [for (final m in recent) m.weightKg!], color: c.accent, fill: c.accentSoft),
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.s8),
              child: Text(list.isEmpty ? '记录几天后会显示变化曲线' : '再记录一次就能看到曲线了',
                  style: AppText.label.copyWith(color: c.text3)),
            ),
        ],
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.values, required this.color, required this.fill});
  final List<double> values;
  final Color color;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 0.5) {
      final mid = (hi + lo) / 2;
      lo = mid - 0.25;
      hi = mid + 0.25;
    }
    const pad = 6.0;
    Offset pt(int i) => Offset(
          pad + (size.width - 2 * pad) * i / (values.length - 1),
          pad + (size.height - 2 * pad) * (1 - (values[i] - lo) / (hi - lo)),
        );
    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(pt(i).dx, pt(i).dy);
    }
    final area = Path.from(line)
      ..lineTo(pt(values.length - 1).dx, size.height)
      ..lineTo(pt(0).dx, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = fill.withValues(alpha: 0.6));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(pt(values.length - 1), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values || old.color != color;
}
