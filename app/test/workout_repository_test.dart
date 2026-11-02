import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/features/workout/workout_math.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

void main() {
  late AppDatabase db;
  late DateTime clock;
  late WorkoutRepository repo;
  const bench = 'ex-bench';
  const squat = 'ex-squat';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    clock = DateTime(2026, 11, 2, 18, 0);
    repo = WorkoutRepository(db, userId: () => 'u1', now: () => clock);
  });
  tearDown(() => db.close());

  /// 记录并完成一次训练：每个 (重量, 次数) 一组，全部勾选完成。
  Future<WorkoutSummary?> doWorkout(String exerciseId, List<(double, int)> sets, {int minutes = 45}) async {
    final w = await repo.startWorkout();
    final weId = await repo.addExercise(w.id, exerciseId, defaultSets: 0);
    for (final (kg, reps) in sets) {
      final id = await repo.addSet(weId);
      await repo.updateSet(id, weightKg: kg, reps: reps);
      await repo.setCompleted(id, true);
    }
    clock = clock.add(Duration(minutes: minutes));
    final summary = await repo.finishWorkout(w.id);
    clock = clock.add(const Duration(days: 2));
    return summary;
  }

  test('开始训练：重复开始返回同一个进行中的训练，并记录本地日期', () async {
    final a = await repo.startWorkout();
    final b = await repo.startWorkout();
    expect(b.id, a.id);
    expect(a.localDate, '2026-11-02');
    expect((await repo.activeWorkout())?.id, a.id);
  });

  test('加动作默认 3 组空白；加组会复制上一组的重量和次数', () async {
    final w = await repo.startWorkout();
    final weId = await repo.addExercise(w.id, bench);
    var view = (await repo.loadWorkout(w.id))!;
    expect(view.exercises.single.sets.length, 3);

    final first = view.exercises.single.sets.first;
    await repo.updateSet(first.id, weightKg: 60, reps: 10);
    await repo.removeSet(view.exercises.single.sets[1].id);
    await repo.removeSet(view.exercises.single.sets[2].id);
    await repo.addSet(weId);
    view = (await repo.loadWorkout(w.id))!;
    expect(view.exercises.single.sets.length, 2);
    expect(view.exercises.single.sets.last.weightKg, 60);
    expect(view.exercises.single.sets.last.reps, 10);
    expect(view.exercises.single.sets.last.setIndex, 1); // 被删掉的第 2、3 组不占序号
  });

  test('完成训练：统计容量/组数，只保留已完成的组', () async {
    final w = await repo.startWorkout();
    final weId = await repo.addExercise(w.id, bench, defaultSets: 0);
    final s1 = await repo.addSet(weId);
    final s2 = await repo.addSet(weId);
    final s3 = await repo.addSet(weId);
    await repo.updateSet(s1, weightKg: 60, reps: 10);
    await repo.updateSet(s2, weightKg: 80, reps: 5);
    await repo.updateSet(s3, weightKg: 90, reps: 3);
    await repo.setCompleted(s1, true);
    await repo.setCompleted(s2, true);
    clock = clock.add(const Duration(minutes: 50));

    final summary = (await repo.finishWorkout(w.id))!;
    expect(summary.volume, 60 * 10 + 80 * 5);
    expect(summary.setCount, 2);
    expect(summary.duration, const Duration(minutes: 50));
    expect(await repo.activeWorkout(), isNull);
    final done = (await repo.loadWorkout(w.id))!;
    expect(done.exercises.single.sets.length, 2);
    expect(done.workout.endedAt, isNotNull);
  });

  test('一个组都没完成：整次训练作废', () async {
    final w = await repo.startWorkout();
    await repo.addExercise(w.id, bench);
    expect(await repo.finishWorkout(w.id), isNull);
    expect(await repo.loadWorkout(w.id), isNull);
    expect(await repo.activeWorkout(), isNull);
  });

  test('上次成绩：新训练里再加同一动作，自动预填上次的重量与次数', () async {
    await doWorkout(bench, [(60, 10), (70, 8), (80, 5)]);
    final w = await repo.startWorkout();
    await repo.addExercise(w.id, bench);
    final sets = (await repo.loadWorkout(w.id))!.exercises.single.sets;
    expect(sets.map((s) => s.weightKg), [60, 70, 80]);
    expect(sets.map((s) => s.reps), [10, 8, 5]);
    expect(sets.every((s) => !s.completed), isTrue);
  });

  test('PR：第一次练不算，之后超过历史才算', () async {
    final first = await doWorkout(bench, [(80, 5)]);
    expect(first!.prs, isEmpty);
    final second = await doWorkout(bench, [(80, 5)]);
    expect(second!.prs, isEmpty);
    final third = await doWorkout(bench, [(85, 5)]);
    expect(third!.prs[bench], contains(PrKind.weight));
  });

  test('历史最佳不含当前训练；不同动作互不影响', () async {
    await doWorkout(bench, [(100, 5)]);
    await doWorkout(squat, [(140, 5)]);
    expect((await repo.bestBefore(bench)).maxWeightKg, 100);
    expect((await repo.bestBefore(squat)).maxWeightKg, 140);
    expect((await repo.bestBefore('ex-unknown')).maxWeightKg, 0);
  });

  test('放弃训练：软删除，不再是进行中', () async {
    final w = await repo.startWorkout();
    await repo.addExercise(w.id, bench);
    await repo.discardWorkout(w.id);
    expect(await repo.activeWorkout(), isNull);
    final row = await (db.select(db.workouts)..where((t) => t.id.equals(w.id))).getSingle();
    expect(row.deletedAt, isNotNull);
    expect(row.dirty, isTrue);
  });

  test('改动都会标记待同步并更新时间', () async {
    final w = await repo.startWorkout();
    final weId = await repo.addExercise(w.id, bench, defaultSets: 1);
    final set = (await repo.loadWorkout(w.id))!.exercises.single.sets.single;
    clock = clock.add(const Duration(minutes: 3));
    await repo.updateSet(set.id, weightKg: 50, reps: 12);
    await repo.setCompleted(set.id, true);
    final row = await (db.select(db.workoutSets)..where((t) => t.id.equals(set.id))).getSingle();
    expect(row.dirty, isTrue);
    expect(row.updatedAt, clock);
    expect(row.completedAt, clock);
    expect(weId, isNotEmpty);
  });

  test('watchActive：进行中的训练变化会推送新视图', () async {
    final stream = repo.watchActive();
    final events = <int?>[];
    final sub = stream.listen((v) => events.add(v?.exercises.length));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final w = await repo.startWorkout();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await repo.addExercise(w.id, bench);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await sub.cancel();
    expect(events.first, isNull);
    expect(events.last, 1);
  });
}
