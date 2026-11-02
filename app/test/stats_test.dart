import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/stats/body_repository.dart';
import 'package:my_fitness/features/stats/stats_math.dart';
import 'package:my_fitness/features/workout/workout_math.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

Exercise ex(String id, BodyPart part, List<String> primary, [List<String> secondary = const []]) => Exercise(
      id: id,
      slug: id,
      nameZh: id,
      nameEn: null,
      bodyPart: part,
      primaryMuscles: primary,
      secondaryMuscles: secondary,
      equipment: 'barbell',
      trackingType: TrackingType.weightReps,
      instructionsZh: null,
      imageCount: 0,
    );

void main() {
  group('统计区间', () {
    test('周：周一到下周一', () {
      final w = windowFor(StatRange.week, DateTime(2026, 11, 4)); // 周三
      expect(w.start, DateTime(2026, 11, 2));
      expect(w.end, DateTime(2026, 11, 9));
      expect(windowLabel(StatRange.week, w), '11月2日 – 11月8日');
      expect(w.contains('2026-11-08'), isTrue);
      expect(w.contains('2026-11-09'), isFalse);
    });
    test('月、年，以及前后翻页（含跨年）', () {
      final m = windowFor(StatRange.month, DateTime(2026, 1, 15));
      expect(windowLabel(StatRange.month, m), '2026年1月');
      expect(m.days, 31);
      final prev = shiftWindow(StatRange.month, m, -1);
      expect(windowLabel(StatRange.month, prev), '2025年12月');
      expect(windowLabel(StatRange.year, shiftWindow(StatRange.year, windowFor(StatRange.year, DateTime(2026, 5, 1)), 1)), '2027年');
      final wk = shiftWindow(StatRange.week, windowFor(StatRange.week, DateTime(2026, 1, 1)), -1);
      expect(wk.start, DateTime(2025, 12, 22));
    });
  });

  test('deltaText', () {
    expect(deltaText(120, 100), '+20%');
    expect(deltaText(80, 100), '−20%');
    expect(deltaText(100, 100), '持平');
    expect(deltaText(5, 0), isNull);
  });

  group('基于真实记录的统计', () {
    late AppDatabase db;
    late DateTime clock;
    late WorkoutRepository repo;
    final bench = ex('bench', BodyPart.chest, ['chest'], ['shoulders', 'triceps']);
    final squat = ex('squat', BodyPart.legs, ['quadriceps'], ['glutes']);
    final pushups = ex('pushups', BodyPart.chest, ['chest']);
    final byId = {for (final e in [bench, squat, pushups]) e.id: e};

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      clock = DateTime(2026, 10, 26, 18);
      repo = WorkoutRepository(db, userId: () => 'u', now: () => clock);
    });
    tearDown(() => db.close());

    Future<void> train(DateTime day, String exId, List<(double, int)> sets,
        {int minutes = 50, bool warmupFirst = false}) async {
      clock = day;
      final w = await repo.startWorkout();
      final we = await repo.addExercise(w.id, exId, defaultSets: 0);
      var first = true;
      for (final (kg, r) in sets) {
        final s = await repo.addSet(we);
        await repo.updateSet(s, weightKg: kg, reps: r, kind: warmupFirst && first ? 'warmup' : 'normal');
        await repo.setCompleted(s, true);
        first = false;
      }
      clock = day.add(Duration(minutes: minutes));
      await repo.finishWorkout(w.id);
    }

    Future<List<WorkoutView>> loadAll() => repo.watchCompleted().first;

    test('KPI：热身不计入组数和容量', () async {
      await train(DateTime(2026, 11, 2, 18), 'bench', [(20, 10), (60, 8), (60, 8)], warmupFirst: true);
      final all = await loadAll();
      final k = kpisFor(inWindow(all, windowFor(StatRange.week, DateTime(2026, 11, 4))));
      expect(k.count, 1);
      expect(k.sets, 2);
      expect(k.volume, 960);
      expect(k.minutes, 50);
    });

    test('区间过滤：只含窗口内的训练', () async {
      await train(DateTime(2026, 10, 28, 18), 'bench', [(60, 8)]);
      await train(DateTime(2026, 11, 3, 18), 'bench', [(60, 8)]);
      final all = await loadAll();
      expect(inWindow(all, windowFor(StatRange.week, DateTime(2026, 11, 3))), hasLength(1));
      expect(inWindow(all, windowFor(StatRange.month, DateTime(2026, 10, 30))), hasLength(1));
      expect(inWindow(all, windowFor(StatRange.year, DateTime(2026, 6, 1))), hasLength(2));
    });

    test('肌肉组数：主要计 1，次要计 0.5；分区按每周平均', () async {
      await train(DateTime(2026, 11, 2, 18), 'bench', [(60, 8), (60, 8), (60, 8), (60, 8)]);
      await train(DateTime(2026, 11, 3, 18), 'squat', [(80, 5), (80, 5)]);
      final all = await loadAll();
      final m = muscleSets(all, byId);
      expect(m['chest'], 4);
      expect(m['shoulders'], 2);
      expect(m['triceps'], 2);
      expect(m['quadriceps'], 2);
      expect(m['glutes'], 1);
      final weekly = regionWeeklySets(m, 7);
      expect(weekly['chest'], 4);
      expect(weekly['quadriceps'], 2);
      expect(weekly['calves'], 0);
      final monthly = regionWeeklySets(m, 28);
      expect(monthly['chest'], 1); // 28 天共 4 组 → 每周 1 组
      expect(partSets(all, byId), {BodyPart.chest: 4, BodyPart.legs: 2});
    });

    test('一句话提示：练得最少的部位；数据太少不提示', () async {
      expect(insightFor({BodyPart.chest: 5}, days: 7), isNull);
      final tip = insightFor(
        {BodyPart.chest: 12, BodyPart.back: 12, BodyPart.legs: 12, BodyPart.shoulders: 12, BodyPart.arms: 12, BodyPart.core: 4},
        days: 7,
      );
      expect(tip, '核心这段时间只练了 4 组，可以多安排一些。');
      expect(
        insightFor({BodyPart.chest: 12, BodyPart.back: 12, BodyPart.legs: 12, BodyPart.shoulders: 12, BodyPart.arms: 12, BodyPart.core: 12}, days: 7),
        isNull,
      );
    });

    test('趋势：近 8 周，最旧在前，空周为 0', () async {
      await train(DateTime(2026, 10, 26, 18), 'bench', [(100, 10)]); // 上上周，容量 1000
      await train(DateTime(2026, 11, 3, 18), 'bench', [(100, 5)]); // 本周，容量 500
      final all = await loadAll();
      final bars = weeklyTrend(all, TrendMetric.volume, DateTime(2026, 11, 4));
      expect(bars, hasLength(8));
      expect(bars.last.weekStart, DateTime(2026, 11, 2));
      expect(bars.last.value, 0.5);
      expect(bars[6].value, 1.0);
      expect(bars[5].value, 0);
      expect(weeklyTrend(all, TrendMetric.count, DateTime(2026, 11, 4)).last.value, 1);
    });

    test('个人纪录：第一次不算，之后重量/1RM/次数打破才算，最新在前', () async {
      await train(DateTime(2026, 10, 12, 18), 'bench', [(60, 8)]); // 基线
      await train(DateTime(2026, 10, 19, 18), 'bench', [(60, 8)]); // 持平，不算
      await train(DateTime(2026, 10, 26, 18), 'bench', [(60, 10)]); // 1RM 变高，重量没变
      await train(DateTime(2026, 11, 2, 18), 'bench', [(70, 5)]); // 重量纪录
      await train(DateTime(2026, 11, 3, 18), 'pushups', [(0, 15)]);
      await train(DateTime(2026, 11, 4, 18), 'pushups', [(0, 20)]); // 自重次数纪录
      final all = await loadAll();
      final prs = prHistory(all, byId);
      expect(prs.map((p) => (p.exerciseId, p.kind, p.value)).toList(), [
        ('pushups', PrKind.reps, 20.0),
        ('bench', PrKind.weight, 70.0),
        ('bench', PrKind.oneRepMax, estimate1RM(60, 10)),
      ]);
      expect(prs[1].previous, 60);
      expect(prHistory(all, byId, limit: 1), hasLength(1));
    });

    test('体重：同一天覆盖，按日期升序', () async {
      final body = BodyRepository(db, userId: () => 'u', now: () => clock);
      await body.setWeight(DateTime(2026, 11, 2), 72.4);
      await body.setWeight(DateTime(2026, 10, 30), 73.2);
      await body.setWeight(DateTime(2026, 11, 2), 72.0);
      final list = await body.all();
      expect(list.map((m) => (m.date, m.weightKg)).toList(), [('2026-10-30', 73.2), ('2026-11-02', 72.0)]);
      await body.remove(list.last.id);
      expect(await body.all(), hasLength(1));
    });
  });
}
