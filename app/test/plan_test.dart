import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/features/plan/plan_math.dart';
import 'package:my_fitness/features/plan/plan_repository.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

void main() {
  group('planDayIndex', () {
    test('起始日是第 1 天，之后循环', () {
      int at(DateTime d) => planDayIndex(startDate: '2026-11-02', cycleDays: 4, date: d);
      expect(at(DateTime(2026, 11, 2)), 0);
      expect(at(DateTime(2026, 11, 3)), 1);
      expect(at(DateTime(2026, 11, 5)), 3);
      expect(at(DateTime(2026, 11, 6)), 0);
      expect(at(DateTime(2026, 12, 31)), (59 % 4));
    });
    test('起始日之前向前推也落在 0..N-1', () {
      expect(planDayIndex(startDate: '2026-11-02', cycleDays: 7, date: DateTime(2026, 11, 1)), 6);
      expect(planDayIndex(startDate: '2026-11-02', cycleDays: 7, date: DateTime(2026, 10, 26)), 0);
    });
    test('跨夏令时不偏移', () {
      expect(planDayIndex(startDate: '2026-03-01', cycleDays: 7, date: DateTime(2026, 3, 29)), 0);
    });
  });

  group('PlanRepository', () {
    late AppDatabase db;
    late PlanRepository plans;
    late WorkoutRepository workouts;
    late DateTime clock;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      clock = DateTime(2026, 11, 2, 9);
      plans = PlanRepository(db, userId: () => 'u1', now: () => clock);
      workouts = WorkoutRepository(db, userId: () => 'u1', now: () => clock);
    });
    tearDown(() => db.close());

    test('模板：增删动作、调整组数次数', () async {
      final id = await plans.createTemplate('推日');
      await plans.addTemplateExercise(id, 'ex-bench');
      await plans.addTemplateExercise(id, 'ex-ohp');
      var tv = (await plans.getTemplate(id))!;
      expect(tv.exercises.map((e) => e.exerciseId), ['ex-bench', 'ex-ohp']);
      expect(tv.exercises.first.targetSets, 3);

      await plans.updateTemplateExercise(tv.exercises.first.id, targetSets: 5, repsMin: 5, repsMax: 5, restSec: 120);
      await plans.removeTemplateExercise(tv.exercises.last.id);
      tv = (await plans.getTemplate(id))!;
      expect(tv.exercises, hasLength(1));
      expect(tv.exercises.single.targetSets, 5);
      expect(tv.exercises.single.restSec, 120);
    });

    test('按模板开始训练：组数与休息来自模板，次数预填下限', () async {
      final id = await plans.createTemplate('推日');
      await plans.addTemplateExercise(id, 'ex-bench');
      final te = (await plans.getTemplate(id))!.exercises.single;
      await plans.updateTemplateExercise(te.id, targetSets: 4, repsMin: 6, restSec: 150);

      final w = await plans.startFromTemplate(workouts, id);
      expect(w.name, '推日');
      expect(w.sourceTemplateId, id);
      final v = (await workouts.loadWorkout(w.id))!;
      expect(v.exercises.single.sets, hasLength(4));
      expect(v.exercises.single.sets.first.reps, 6);
      expect(v.exercises.single.exercise.restSec, 150);
    });

    test('按模板开始：有上次记录时借用重量，但组数以模板为准', () async {
      final h = await workouts.startWorkout();
      final he = await workouts.addExercise(h.id, 'ex-bench', defaultSets: 0);
      final s = await workouts.addSet(he);
      await workouts.updateSet(s, weightKg: 70, reps: 5);
      await workouts.setCompleted(s, true);
      await workouts.finishWorkout(h.id);

      final id = await plans.createTemplate('推日');
      await plans.addTemplateExercise(id, 'ex-bench');
      final w = await plans.startFromTemplate(workouts, id);
      final sets = (await workouts.loadWorkout(w.id))!.exercises.single.sets;
      expect(sets, hasLength(3));
      expect(sets.first.weightKg, 70);
      expect(sets.first.reps, 5);
      expect(sets.last.weightKg, isNull);
    });

    test('已有进行中的训练时，按模板开始返回它而不是新建', () async {
      final id = await plans.createTemplate('A');
      await plans.addTemplateExercise(id, 'ex-bench');
      final a = await plans.startFromTemplate(workouts, id);
      final b = await plans.startFromTemplate(workouts, id);
      expect(b.id, a.id);
      expect((await workouts.loadWorkout(a.id))!.exercises, hasLength(1));
    });

    test('删除模板：计划里引用它的天变成休息日', () async {
      final t = await plans.createTemplate('腿日');
      final p = await plans.createPlan('三分化', 3);
      await plans.setPlanDay(p, 1, t);
      expect((await plans.getPlan(p))!.dayAt(1)?.templateId, t);
      await plans.deleteTemplate(t);
      expect((await plans.getPlan(p))!.dayAt(1)?.templateId, isNull);
      expect(await plans.getTemplate(t), isNull);
    });

    test('计划：第一个计划自动成为当前计划，同一时刻只有一个', () async {
      final a = await plans.createPlan('A', 7);
      final b = await plans.createPlan('B', 4);
      var all = await plans.watchPlans().first;
      expect(all.where((p) => p.plan.isActive).map((p) => p.plan.id), [a]);

      clock = DateTime(2026, 11, 10, 8);
      await plans.activatePlan(b);
      all = await plans.watchPlans().first;
      expect(all.where((p) => p.plan.isActive).map((p) => p.plan.id), [b]);
      expect(all.firstWhere((p) => p.plan.id == b).plan.startDate, '2026-11-10');
    });

    test('改短循环天数会丢掉超出的天；设置某天可覆盖', () async {
      final t = await plans.createTemplate('A');
      final p = await plans.createPlan('P', 5);
      await plans.setPlanDay(p, 4, t);
      await plans.setPlanDay(p, 1, t);
      await plans.setPlanDay(p, 1, null);
      await plans.setCycleDays(p, 3);
      final view = (await plans.getPlan(p))!;
      expect(view.days, hasLength(3));
      expect(view.dayAt(1)?.templateId, isNull);
      expect(view.dayAt(4), isNull);
    });

    test('把完成的训练存成模板', () async {
      final w = await workouts.startWorkout();
      final we = await workouts.addExercise(w.id, 'ex-squat', defaultSets: 0);
      for (final r in [8, 6]) {
        final s = await workouts.addSet(we);
        await workouts.updateSet(s, weightKg: 100, reps: r);
        await workouts.setCompleted(s, true);
      }
      await workouts.finishWorkout(w.id);
      final view = (await workouts.loadWorkout(w.id))!;
      final id = await plans.templateFromWorkout(view, '腿日');
      final te = (await plans.getTemplate(id))!.exercises.single;
      expect(te.targetSets, 2);
      expect(te.repsMin, 6);
      expect(te.repsMax, 8);
    });

    test('watchCompleted 按日期区间过滤，且只含已结束的训练', () async {
      Future<void> doIt(DateTime day) async {
        clock = day;
        final w = await workouts.startWorkout();
        final we = await workouts.addExercise(w.id, 'ex-bench', defaultSets: 0);
        final s = await workouts.addSet(we);
        await workouts.updateSet(s, weightKg: 50, reps: 10);
        await workouts.setCompleted(s, true);
        clock = day.add(const Duration(minutes: 40));
        await workouts.finishWorkout(w.id);
      }

      await doIt(DateTime(2026, 10, 30, 18));
      await doIt(DateTime(2026, 11, 3, 18));
      await workouts.startWorkout(); // 进行中，不应出现
      final nov = await workouts.watchCompleted(fromDate: '2026-11-01', toDate: '2026-11-30').first;
      expect(nov, hasLength(1));
      expect(nov.single.workout.localDate, '2026-11-03');
      final all = await workouts.watchCompleted().first;
      expect(all, hasLength(2));
    });

    test('watchCompleted：训练主记录先到、动作和组后到（重新登录拉取）时，数字会自动刷新', () async {
      final t = DateTime(2026, 11, 4, 23, 7);
      // 先写入训练主记录（模拟同步先拉回 workouts）
      await db.into(db.workouts).insert(WorkoutsCompanion.insert(
          id: 'w1', createdAt: t, updatedAt: t, userId: 'u1', startedAt: t,
          endedAt: Value(t.add(const Duration(minutes: 31))), localDate: '2026-11-04', name: const Value('臂')));
      final seen = <int>[];
      final sub = workouts.watchCompleted().listen((v) => seen.add(v.single.setCount));
      await pumpEventQueue();
      expect(seen.last, 0);

      // 再写入动作和组（模拟同步随后拉回 workout_exercises / workout_sets）
      await db.into(db.workoutExercises).insert(WorkoutExercisesCompanion.insert(
          id: 'we1', createdAt: t, updatedAt: t, userId: 'u1', workoutId: 'w1', exerciseId: 'ex-bench', position: 0));
      for (var i = 0; i < 3; i++) {
        await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
            id: 's$i', createdAt: t, updatedAt: t, userId: 'u1', workoutExerciseId: 'we1', setIndex: i,
            weightKg: const Value(9.5), reps: const Value(12), completed: const Value(true)));
      }
      await pumpEventQueue();
      expect(seen.last, 3);
      await sub.cancel();
    });
  });
}
