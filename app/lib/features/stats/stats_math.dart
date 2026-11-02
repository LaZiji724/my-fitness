/// 数据页的统计函数：只依赖训练记录和动作库，不碰界面。
/// 口径与训练页一致：只统计「已完成」且「非热身」的组。
library;

import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/workout/workout_math.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

enum StatRange {
  week('周'),
  month('月'),
  year('年');

  const StatRange(this.label);
  final String label;
}

/// 统计区间：[start, end) 的本地日期。
class StatWindow {
  const StatWindow(this.start, this.end);
  final DateTime start;
  final DateTime end;

  int get days => end.difference(start).inDays;

  bool contains(String dateKey) =>
      dateKey.compareTo(_key(start)) >= 0 && dateKey.compareTo(_key(end)) < 0;

  @override
  bool operator ==(Object other) => other is StatWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

String _key(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

DateTime _d(DateTime t) => DateTime(t.year, t.month, t.day);

/// 包含 [anchor] 的那一周（周一到周日）。
DateTime weekStartOf(DateTime anchor) {
  final d = _d(anchor);
  return DateTime(d.year, d.month, d.day - (d.weekday - 1));
}

StatWindow windowFor(StatRange range, DateTime anchor) {
  final a = _d(anchor);
  switch (range) {
    case StatRange.week:
      final s = weekStartOf(a);
      return StatWindow(s, DateTime(s.year, s.month, s.day + 7));
    case StatRange.month:
      return StatWindow(DateTime(a.year, a.month), DateTime(a.year, a.month + 1));
    case StatRange.year:
      return StatWindow(DateTime(a.year), DateTime(a.year + 1));
  }
}

StatWindow shiftWindow(StatRange range, StatWindow w, int delta) {
  switch (range) {
    case StatRange.week:
      return StatWindow(
        DateTime(w.start.year, w.start.month, w.start.day + 7 * delta),
        DateTime(w.end.year, w.end.month, w.end.day + 7 * delta),
      );
    case StatRange.month:
      return windowFor(range, DateTime(w.start.year, w.start.month + delta));
    case StatRange.year:
      return windowFor(range, DateTime(w.start.year + delta));
  }
}

String windowLabel(StatRange range, StatWindow w) {
  switch (range) {
    case StatRange.week:
      final last = DateTime(w.end.year, w.end.month, w.end.day - 1);
      return '${w.start.month}月${w.start.day}日 – ${last.month}月${last.day}日';
    case StatRange.month:
      return '${w.start.year}年${w.start.month}月';
    case StatRange.year:
      return '${w.start.year}年';
  }
}

List<WorkoutView> inWindow(Iterable<WorkoutView> all, StatWindow w) =>
    all.where((v) => v.workout.endedAt != null && w.contains(v.workout.localDate)).toList();

// ------------------------------------------------------------------ 概览

class Kpis {
  const Kpis({required this.count, required this.volume, required this.sets, required this.minutes});
  final int count;
  final double volume;
  final int sets;
  final int minutes;

  static const zero = Kpis(count: 0, volume: 0, sets: 0, minutes: 0);
}

Kpis kpisFor(Iterable<WorkoutView> ws) {
  var count = 0, sets = 0, minutes = 0;
  var volume = 0.0;
  for (final w in ws) {
    count++;
    volume += w.volume;
    sets += w.setCount;
    minutes += w.workout.endedAt?.difference(w.workout.startedAt).inMinutes ?? 0;
  }
  return Kpis(count: count, volume: volume, sets: sets, minutes: minutes);
}

/// 和上一段相比的变化文案：+12% / −5% / 持平；上一段为 0 时返回 null（没有可比的）。
String? deltaText(num now, num before) {
  if (before <= 0) return null;
  final pct = ((now - before) / before * 100).round();
  if (pct == 0) return '持平';
  return pct > 0 ? '+$pct%' : '−${pct.abs()}%';
}

// ------------------------------------------------------------------ 肌肉

Iterable<(WorkoutSet, Exercise)> _workingSets(Iterable<WorkoutView> ws, Map<String, Exercise> byId) sync* {
  for (final w in ws) {
    for (final b in w.exercises) {
      final ex = byId[b.exercise.exerciseId];
      if (ex == null) continue;
      for (final s in b.sets) {
        if (SetEntry(kind: s.kind, completed: s.completed).counts) yield (s, ex);
      }
    }
  }
}

/// 每块肌肉的组数：主要肌肉每组计 1，次要肌肉计 0.5。键是动作库里的英文肌肉名。
Map<String, double> muscleSets(Iterable<WorkoutView> ws, Map<String, Exercise> byId) {
  final out = <String, double>{};
  for (final (_, ex) in _workingSets(ws, byId)) {
    for (final m in ex.primaryMuscles) {
      out.update(m, (v) => v + 1, ifAbsent: () => 1);
    }
    for (final m in ex.secondaryMuscles) {
      out.update(m, (v) => v + 0.5, ifAbsent: () => 0.5);
    }
  }
  return out;
}

/// 按动作所属大部位统计组数（每组计 1），用于「本期 vs 上期」。
Map<BodyPart, int> partSets(Iterable<WorkoutView> ws, Map<String, Exercise> byId) {
  final out = <BodyPart, int>{};
  for (final (_, ex) in _workingSets(ws, byId)) {
    out.update(ex.bodyPart, (v) => v + 1, ifAbsent: () => 1);
  }
  return out;
}

/// 人体图上的分区：把动作库里的肌肉并成图上有的块。
const Map<String, List<String>> kFigureRegions = {
  'chest': ['chest'],
  'shoulders': ['shoulders'],
  'traps': ['traps'],
  'biceps': ['biceps'],
  'triceps': ['triceps'],
  'forearms': ['forearms'],
  'abs': ['abdominals'],
  'lats': ['lats', 'middle back'],
  'lower_back': ['lower back'],
  'glutes': ['glutes', 'abductors'],
  'quadriceps': ['quadriceps', 'adductors'],
  'hamstrings': ['hamstrings'],
  'calves': ['calves'],
};

/// 图上每个分区的「每周平均组数」。[days] 为统计区间天数。
Map<String, double> regionWeeklySets(Map<String, double> muscle, int days) {
  final weeks = days <= 0 ? 1.0 : days / 7;
  return {
    for (final e in kFigureRegions.entries)
      e.key: e.value.fold<double>(0, (s, m) => s + (muscle[m] ?? 0)) / weeks,
  };
}

/// 一句话提示：找出练得最少的大部位。数据太少（总组数不足）时不提示。
String? insightFor(Map<BodyPart, int> parts, {required int days}) {
  const main = [BodyPart.chest, BodyPart.back, BodyPart.legs, BodyPart.shoulders, BodyPart.arms, BodyPart.core];
  final total = parts.values.fold<int>(0, (a, b) => a + b);
  if (total < 20) return null;
  int setsOf(BodyPart p) => p == BodyPart.legs
      ? (parts[BodyPart.legs] ?? 0) + (parts[BodyPart.glutes] ?? 0)
      : (parts[p] ?? 0);
  final least = main.reduce((a, b) => setsOf(b) < setsOf(a) ? b : a);
  final n = setsOf(least);
  final label = switch (least) {
    BodyPart.legs => '腿臀',
    BodyPart.core => '核心',
    BodyPart.arms => '手臂',
    _ => least.label,
  };
  final weekly = n / (days / 7);
  if (weekly >= 6) return null; // 都练得够，不用唠叨
  return n == 0 ? '$label这段时间一组都没练，可以安排一些。' : '$label这段时间只练了 $n 组，可以多安排一些。';
}

// ------------------------------------------------------------------ 趋势

enum TrendMetric {
  volume('容量'),
  sets('组数'),
  count('次数'),
  hours('时长');

  const TrendMetric(this.label);
  final String label;

  String get unit => switch (this) {
        TrendMetric.volume => '吨',
        TrendMetric.sets => '组',
        TrendMetric.count => '次',
        TrendMetric.hours => '小时',
      };

  double valueOf(Kpis k) => switch (this) {
        TrendMetric.volume => k.volume / 1000,
        TrendMetric.sets => k.sets.toDouble(),
        TrendMetric.count => k.count.toDouble(),
        TrendMetric.hours => k.minutes / 60,
      };
}

class TrendBar {
  const TrendBar(this.weekStart, this.value);
  final DateTime weekStart;
  final double value;
}

/// 以包含 [endDate] 的那一周结尾，往前共 [weeks] 周的趋势（最旧在前）。
List<TrendBar> weeklyTrend(
  Iterable<WorkoutView> all,
  TrendMetric metric,
  DateTime endDate, {
  int weeks = 8,
}) {
  final last = weekStartOf(endDate);
  final bars = <TrendBar>[];
  for (var i = weeks - 1; i >= 0; i--) {
    final s = DateTime(last.year, last.month, last.day - 7 * i);
    final w = StatWindow(s, DateTime(s.year, s.month, s.day + 7));
    bars.add(TrendBar(s, metric.valueOf(kpisFor(inWindow(all, w)))));
  }
  return bars;
}

// ------------------------------------------------------------------ 个人纪录

class PrEvent {
  const PrEvent({
    required this.exerciseId,
    required this.date,
    required this.kind,
    required this.value,
    required this.previous,
  });

  final String exerciseId;
  final String date;
  final PrKind kind;

  /// 本次的值：重量(kg) / 次数 / 估算 1RM(kg)
  final double value;

  /// 之前的最好成绩
  final double previous;
}

/// 按时间顺序回放历史，找出每次打破纪录的时刻（第一次练某个动作不算）。
/// 同一动作同一天只记一条：重量纪录优先，其次 1RM、次数。返回最新的在前。
List<PrEvent> prHistory(Iterable<WorkoutView> all, Map<String, Exercise> byId, {int? limit}) {
  final ordered = all.where((w) => w.workout.endedAt != null).toList()
    ..sort((a, b) => a.workout.startedAt.compareTo(b.workout.startedAt));
  final best = <String, ExerciseBest>{};
  final events = <PrEvent>[];

  for (final w in ordered) {
    for (final b in w.exercises) {
      final id = b.exercise.exerciseId;
      if (byId[id] == null) continue;
      final before = best[id] ?? const ExerciseBest();
      final hasHistory = before.maxWeightKg > 0 || before.maxReps > 0 || before.max1RM > 0;
      var maxW = 0.0, max1 = 0.0;
      var maxR = 0;
      for (final s in b.sets) {
        final e = SetEntry(weightKg: s.weightKg, reps: s.reps, kind: s.kind, completed: s.completed);
        if (!e.counts) continue;
        final wgt = s.weightKg ?? 0;
        final reps = s.reps ?? 0;
        if (wgt > maxW) maxW = wgt;
        if (reps > maxR) maxR = reps;
        final one = estimate1RM(wgt, reps);
        if (one > max1) max1 = one;
      }
      if (hasHistory) {
        if (maxW > before.maxWeightKg) {
          events.add(PrEvent(exerciseId: id, date: w.workout.localDate, kind: PrKind.weight, value: maxW, previous: before.maxWeightKg));
        } else if (max1 > before.max1RM + 0.0001 && maxW > 0) {
          events.add(PrEvent(exerciseId: id, date: w.workout.localDate, kind: PrKind.oneRepMax, value: max1, previous: before.max1RM));
        } else if (maxW == 0 && maxR > before.maxReps) {
          events.add(PrEvent(exerciseId: id, date: w.workout.localDate, kind: PrKind.reps, value: maxR.toDouble(), previous: before.maxReps.toDouble()));
        }
      }
      best[id] = ExerciseBest(
        maxWeightKg: maxW > before.maxWeightKg ? maxW : before.maxWeightKg,
        maxReps: maxR > before.maxReps ? maxR : before.maxReps,
        max1RM: max1 > before.max1RM ? max1 : before.max1RM,
      );
    }
  }
  final out = events.reversed.toList();
  return limit == null || out.length <= limit ? out : out.sublist(0, limit);
}
