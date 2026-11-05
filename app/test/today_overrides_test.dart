import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/features/plan/plan_repository.dart';
import 'package:my_fitness/features/plan/today_overrides.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

import 'exercises_test.dart' show loadSeed;

void main() {
  late AppDatabase db;
  late PlanRepository plans;
  late WorkoutRepository workouts;
  late TodayOverridesRepository overrides;
  var uid = 'u1';
  final bench = loadSeed().firstWhere((e) => e.nameZh.contains('卧推'));
  final day = DateTime(2026, 11, 5);

  setUp(() {
    uid = 'u1';
    db = AppDatabase.forTesting(NativeDatabase.memory());
    plans = PlanRepository(db, userId: () => uid, now: () => DateTime(2026, 11, 5, 9));
    workouts = WorkoutRepository(db, userId: () => uid, now: () => DateTime(2026, 11, 5, 9));
    overrides = TodayOverridesRepository(db, userId: () => uid);
  });
  tearDown(() => db.close());

  Future<(String, String)> template() async {
    final t = await plans.createTemplate('推日');
    await plans.addTemplateExercise(t, bench.id);
    final te = (await plans.getTemplate(t))!.exercises.single;
    return (t, te.id);
  }

  test('保存今天的修改不会动模板，也不会标脏等待同步', () async {
    final (t, te) = await template();
    await db.customStatement('UPDATE template_exercises SET dirty = 0');
    await overrides.save(day, t, te, const DoseOverride(targetSets: 5, restSec: 120));

    final tpl = (await plans.getTemplate(t))!;
    expect(tpl.exercises.single.targetSets, 3);
    expect(tpl.exercises.single.restSec, isNull);
    expect(tpl.exercises.single.dirty, isFalse);

    final loaded = await overrides.load(day, t);
    final applied = applyDoseOverrides(tpl, loaded);
    expect(applied.exercises.single.targetSets, 5);
    expect(applied.exercises.single.restSec, 120);
    expect(applied.exercises.single.repsMin, tpl.exercises.single.repsMin);
  });

  test('多次修改叠加，后改的覆盖先改的', () async {
    final (t, te) = await template();
    await overrides.save(day, t, te, const DoseOverride(targetSets: 5));
    await overrides.save(day, t, te, const DoseOverride(restSec: 60));
    await overrides.save(day, t, te, const DoseOverride(targetSets: 4));
    final o = (await overrides.load(day, t))[te]!;
    expect(o.targetSets, 4);
    expect(o.restSec, 60);
  });

  test('换一天不再生效；新的一天写入时顺便清掉旧日子的记录', () async {
    final (t, te) = await template();
    await overrides.save(day, t, te, const DoseOverride(targetSets: 5));
    expect(await overrides.load(day.add(const Duration(days: 1)), t), isEmpty);
    await overrides.save(day.add(const Duration(days: 1)), t, te, const DoseOverride(targetSets: 2));
    expect(await overrides.load(day, t), isEmpty);
    expect((await overrides.load(day.add(const Duration(days: 1)), t))[te]!.targetSets, 2);
  });

  test('不同账号互不影响；恢复后清空', () async {
    final (t, te) = await template();
    await overrides.save(day, t, te, const DoseOverride(targetSets: 5));
    uid = 'u2';
    expect(await overrides.load(day, t), isEmpty);
    uid = 'u1';
    await overrides.clear(day, t);
    expect(await overrides.load(day, t), isEmpty);
  });

  test('按今天的修改开练：训练里是修改后的组数，模板里还是原来的', () async {
    final (t, te) = await template();
    await overrides.save(day, t, te, const DoseOverride(targetSets: 5, restSec: 45));
    final o = await overrides.load(day, t);
    final w = await plans.startFromTemplate(workouts, t, adjust: (v) => applyDoseOverrides(v, o));
    final view = (await workouts.loadWorkout(w.id))!;
    expect(view.exercises.single.sets, hasLength(5));
    expect(view.exercises.single.exercise.restSec, 45);
    expect((await plans.getTemplate(t))!.exercises.single.targetSets, 3);
    expect((await plans.getTemplate(t))!.exercises.single.restSec, isNull);
  });
}
