import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/plan/plan_repository.dart';
import 'package:my_fitness/features/plan/today_overrides.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

import 'exercises_test.dart' show loadSeed;

void main() {
  late AppDatabase db;
  late PlanRepository plans;
  late WorkoutRepository workouts;
  final all = loadSeed();
  final bench = all.firstWhere((e) => e.nameZh.contains('卧推'));
  final stretch = all.firstWhere((e) => e.kind.isStretchTab);
  final activation = all.firstWhere((e) => e.kind.isActivationTab);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    plans = PlanRepository(db, userId: () => 'u1');
    workouts = WorkoutRepository(db, userId: () => 'u1');
  });
  tearDown(() => db.close());

  test('默认模块：激活放热身，拉伸放放松，其余放正式训练', () {
    expect(ExerciseDose.defaultSectionFor(activation), WorkoutSection.warmup);
    expect(ExerciseDose.defaultSectionFor(stretch), WorkoutSection.cooldown);
    expect(ExerciseDose.defaultSectionFor(bench), WorkoutSection.main);
    final d = ExerciseDose.initial(bench);
    expect(d.timed, bench.isTimed);
    expect(d.weightKg, isNull);
  });

  test('添加到模板：按详情页设置的模块、次数、负重写入', () async {
    final id = await plans.createTemplate('推日');
    await plans.addTemplateExercise(
      id,
      bench.id,
      exercise: bench,
      dose: const ExerciseDose(section: WorkoutSection.warmup, timed: false, sets: 4, reps: 6, seconds: 30, weightKg: 42.5),
    );
    final e = (await plans.getTemplate(id))!.exercises.single;
    expect(e.section, 'warmup');
    expect(e.targetSets, 4);
    expect(e.repsMin, 6);
    expect(e.repsMax, 6);
    expect(e.targetDurationSec, isNull);
    expect(e.targetWeightKg, 42.5);
  });

  test('添加到模板：按时间时写秒数，不写次数', () async {
    final id = await plans.createTemplate('放松');
    await plans.addTemplateExercise(
      id,
      stretch.id,
      exercise: stretch,
      dose: const ExerciseDose(section: WorkoutSection.cooldown, timed: true, sets: 2, reps: 10, seconds: 45),
    );
    final e = (await plans.getTemplate(id))!.exercises.single;
    expect(e.section, 'cooldown');
    expect(e.targetDurationSec, 45);
    expect(e.repsMin, isNull);
    expect(e.targetWeightKg, isNull);
  });

  test('不传 dose 时行为和以前一样（正式训练、不设负重）', () async {
    final id = await plans.createTemplate('旧');
    await plans.addTemplateExercise(id, bench.id, exercise: bench);
    final e = (await plans.getTemplate(id))!.exercises.single;
    expect(e.section, 'main');
    expect(e.targetWeightKg, isNull);
  });

  test('改模板动作的负重，也可以清除；开练时每个正式组带上模板负重，没设则沿用上次', () async {
    final id = await plans.createTemplate('推日');
    await plans.addTemplateExercise(id, bench.id, exercise: bench);
    final te = (await plans.getTemplate(id))!.exercises.single;
    await plans.updateTemplateExercise(te.id, targetWeightKg: 60);
    var w = await plans.startFromTemplate(workouts, id, exercises: {bench.id: bench});
    var sets = (await workouts.loadWorkout(w.id))!.exercises.single.sets;
    expect(sets, isNotEmpty);
    expect(sets.every((s) => s.weightKg == 60), isTrue);
    await workouts.finishWorkout(w.id);

    await plans.updateTemplateExercise(te.id, clearWeight: true);
    expect((await plans.getTemplate(id))!.exercises.single.targetWeightKg, isNull);
    w = await plans.startFromTemplate(workouts, id, exercises: {bench.id: bench});
    sets = (await workouts.loadWorkout(w.id))!.exercises.single.sets;
    expect(sets.every((s) => s.weightKg == null), isTrue);
  });

  test('今天的修改也能带负重：JSON 往返、叠加、清除', () {
    const a = DoseOverride(targetWeightKg: 50);
    final back = DoseOverride.fromJson(a.toJson());
    expect(back.targetWeightKg, 50);
    expect(a.isEmpty, isFalse);
    final cleared = a.merge(const DoseOverride(clearWeight: true));
    expect(cleared.targetWeightKg, isNull);
    expect(cleared.clearWeight, isTrue);
    expect(DoseOverride.fromJson(cleared.toJson()).clearWeight, isTrue);
    expect(cleared.merge(const DoseOverride(targetWeightKg: 55)).targetWeightKg, 55);
  });
}
