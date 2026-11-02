import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/library/library_repository.dart';
import 'package:my_fitness/features/library/program.dart';
import 'package:my_fitness/features/plan/plan_repository.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

import 'exercises_test.dart' show loadSeed;

List<Program> loadPrograms() {
  final raw = File('assets/seed/programs.json').readAsStringSync();
  return (jsonDecode(raw) as List).map((e) => Program.fromJson(e as Map<String, dynamic>)).toList();
}

void main() {
  final programs = loadPrograms();
  final exercises = loadSeed();
  final byId = {for (final e in exercises) e.id: e};

  Program bySlug(String slug) => programs.firstWhere((p) => p.slug == slug);

  group('计划库数据', () {
    test('覆盖 8 个目标分类，每类至少 5 个计划，总量不少于 60', () {
      expect(programs.length, greaterThanOrEqualTo(60));
      final cats = <String, int>{};
      for (final p in programs) {
        cats[p.category] = (cats[p.category] ?? 0) + 1;
      }
      expect(cats.keys.toSet(), {
        for (final c in LibraryCategory.values)
          if (c.dataKey != null) c.dataKey!,
      });
      for (final e in cats.entries) {
        expect(e.value, greaterThanOrEqualTo(5), reason: e.key);
      }
      expect(programs.any((p) => p.level == 3), isTrue);
      expect(programs.any((p) => p.isNew), isTrue);
    });

    test('id / slug 唯一，基本字段合法，每周安排与课次一一对应', () {
      expect(programs.map((p) => p.id).toSet().length, programs.length);
      expect(programs.map((p) => p.slug).toSet().length, programs.length);
      for (final p in programs) {
        final tag = p.slug;
        expect(RegExp(r'^[a-z0-9-]+$').hasMatch(p.slug), isTrue, reason: tag);
        expect(p.description.length, greaterThan(20), reason: tag);
        expect(p.progression, isNotEmpty, reason: tag);
        expect(p.level, inInclusiveRange(1, 3), reason: tag);
        expect(p.weeks, greaterThan(0), reason: tag);
        expect(p.schedule.length, 7, reason: tag);
        expect(p.daysPerWeek, p.schedule.split('').where((ch) => ch != '.').length, reason: tag);
        expect(p.sessions, isNotEmpty, reason: tag);
        final keys = p.sessions.map((s) => s.key).toList();
        expect(keys.toSet().length, keys.length, reason: tag);
        for (final ch in p.schedule.split('')) {
          if (ch != '.') expect(keys, contains(ch), reason: tag);
        }
        for (final k in keys) {
          expect(p.schedule, contains(k), reason: '$tag $k 没有被排进每周安排');
        }
        expect(p.weekOrder.length, p.daysPerWeek, reason: tag);
        expect(p.totalSessions, p.daysPerWeek * p.weeks, reason: tag);
      }
    });

    test('每节课都有完整动作链：动作存在、目标与记录方式匹配、休息秒数合理', () {
      var items = 0;
      for (final p in programs) {
        for (final s in p.sessions) {
          expect(s.items.length, greaterThanOrEqualTo(3), reason: '${p.slug}/${s.key}');
          expect(s.minutes, greaterThanOrEqualTo(5), reason: '${p.slug}/${s.key}');
          for (var i = 0; i < s.items.length; i++) {
            final it = s.items[i];
            final tag = '${p.slug}/${s.key}#$i';
            items++;
            expect(it.position, i, reason: tag);
            final ex = byId[it.exerciseId];
            expect(ex, isNotNull, reason: '$tag 引用了不存在的动作');
            expect(it.sets, inInclusiveRange(1, 20), reason: tag);
            expect(it.restSec, inInclusiveRange(0, 600), reason: tag);
            if (it.durationSec != null) {
              expect(ex!.trackingType, TrackingType.duration, reason: '$tag 时长目标只能给计时动作');
              expect(it.repsMin, isNull, reason: tag);
            } else {
              expect(ex!.trackingType, isNot(TrackingType.duration), reason: '$tag 计时动作必须有时长目标');
              expect(it.repsMin, isNotNull, reason: tag);
              expect(it.repsMax! >= it.repsMin!, isTrue, reason: tag);
            }
            if (it.warmupSets > 0) {
              expect(ex.trackingType, TrackingType.weightReps, reason: '$tag 热身组只给重量动作');
            }
          }
        }
      }
      expect(items, greaterThan(1000));
    });

    test('有氧类计划带有时间或距离目标；力量计划带有热身组', () {
      final rope = bySlug('rowing-endurance');
      final stable = rope.sessions.firstWhere((s) => s.key == 'B');
      expect(stable.items.any((i) => i.distanceM != null), isTrue);
      final barbell = bySlug('muscle-barbell-novice');
      expect(barbell.sessions.first.items.any((i) => i.warmupSets >= 2), isTrue);
    });

    test('describeItemTarget：次数、时长、热身、距离、休息都能写成人话', () {
      String d(Map<String, dynamic> m) => describeItemTarget(ProgramItem.fromJson({
            'id': 'x', 'exercise_id': 'y', 'position': 0, 'warmup_sets': 0, 'sets': 3,
            'reps_min': null, 'reps_max': null, 'duration_sec': null, 'distance_m': null, 'rest_sec': 60, 'note': null,
            ...m,
          }));
      expect(d({'reps_min': 6, 'reps_max': 8, 'warmup_sets': 2, 'rest_sec': 120}), '3 组 × 6–8 次 · 热身 2 组 · 休息 120 秒');
      expect(d({'sets': 1, 'duration_sec': 1200, 'distance_m': 2500, 'rest_sec': 0}), '1 组 × 20 分钟 · 目标 2.5 公里');
      expect(d({'sets': 4, 'duration_sec': 45}), '4 组 × 45 秒 · 休息 60 秒');
      expect(d({'reps_min': 12, 'reps_max': 12}), '3 组 × 12 次 · 休息 60 秒');
      expect(formatDistance(500), '500 米');
    });
  });

  group('筛选', () {
    final none = <String>{};

    test('分类：新手入门 = 初阶，进阶计划 = 中高阶，近期上新 = 新上线，目标分类按字段', () {
      final beginner = filterPrograms(programs, const LibraryFilter(category: LibraryCategory.beginner), none);
      expect(beginner, isNotEmpty);
      expect(beginner.every((p) => p.level == 1), isTrue);
      final adv = filterPrograms(programs, const LibraryFilter(category: LibraryCategory.advanced), none);
      expect(adv.every((p) => p.level >= 2), isTrue);
      expect(beginner.length + adv.length, programs.length);
      final fresh = filterPrograms(programs, const LibraryFilter(category: LibraryCategory.newest), none);
      expect(fresh.every((p) => p.isNew), isTrue);
      final muscle = filterPrograms(programs, const LibraryFilter(category: LibraryCategory.muscle), none);
      expect(muscle.every((p) => p.category == '增肌增重'), isTrue);
    });

    test('收藏分类只显示已收藏的计划', () {
      final fav = {programs[3].id, programs[10].id};
      final r = filterPrograms(programs, const LibraryFilter(category: LibraryCategory.favorites), fav);
      expect(r.map((p) => p.id).toSet(), fav);
    });

    test('频率 / 难度 / 场景 / 人群叠加在分类上', () {
      final r = filterPrograms(
          programs,
          const LibraryFilter(
              category: LibraryCategory.muscle, frequency: FrequencyBand.three, level: 2, scene: '健身房', audience: '男性'),
          none);
      expect(r, isNotEmpty);
      for (final p in r) {
        expect(p.category, '增肌增重');
        expect(p.daysPerWeek, 3);
        expect(p.level, 2);
        expect(p.scenes, contains('健身房'));
        expect(p.audiences, contains('男性'));
      }
      final many = filterPrograms(programs, const LibraryFilter(frequency: FrequencyBand.many, category: LibraryCategory.beginner), none);
      expect(many.every((p) => p.daysPerWeek >= 5), isTrue);
    });

    test('搜索跨分类，按名称、简介、器械命中', () {
      final r = filterPrograms(programs, const LibraryFilter(query: '肩颈'), none);
      expect(r.any((p) => p.name.contains('肩颈')), isTrue);
      final eq = filterPrograms(programs, const LibraryFilter(query: '跑步机'), none);
      expect(eq.length, greaterThanOrEqualTo(2));
      expect(filterPrograms(programs, const LibraryFilter(query: '不存在xyz'), none), isEmpty);
    });

    test('copyWith 可以把筛选项清回空', () {
      final f = const LibraryFilter(level: 2, scene: '居家').copyWith(level: null);
      expect(f.level, isNull);
      expect(f.scene, '居家');
    });
  });

  group('加入计划 / 添加到日历 / 去训练', () {
    late AppDatabase db;
    late ProgramLibraryRepository lib;
    late WorkoutRepository workouts;
    late PlanRepository plans;
    var clock = DateTime(2026, 11, 4, 9); // 周三

    setUp(() {
      clock = DateTime(2026, 11, 4, 9);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      lib = ProgramLibraryRepository(db, userId: () => 'u1', now: () => clock);
      workouts = WorkoutRepository(db, userId: () => 'u1', now: () => clock);
      plans = PlanRepository(db, userId: () => 'u1', now: () => clock);
    });
    tearDown(() => db.close());

    test('加入：每节课生成一个模板（含热身组/时长/要点），生成按周循环的计划，重复加入不重复', () async {
      final p = bySlug('muscle-barbell-novice');
      final planId = await lib.join(p);
      expect(await lib.join(p), planId);

      final view = (await plans.getPlan(planId))!;
      expect(view.plan.cycleDays, 7);
      expect(view.plan.sourceProgramId, p.id);
      expect(view.plan.isActive, isTrue, reason: '没有别的计划时自动成为当前计划');
      expect(view.plan.startDate, '2026-11-02', reason: '对齐到所在周的周一');
      // 周一、周三、周五练（A.B.A..）
      final trainDays = [for (var i = 0; i < 7; i++) if (view.dayAt(i)?.templateId != null) i];
      expect(trainDays, [0, 2, 4]);
      expect(view.dayAt(0)!.templateId, view.dayAt(4)!.templateId, reason: 'A 节在一周里出现两次');

      final templates = await plans.listTemplates();
      expect(templates.length, p.sessions.length);
      final a = templates.firstWhere((t) => t.template.id == view.dayAt(0)!.templateId);
      final sessionA = p.sessionByKey('A')!;
      expect(a.exercises.length, sessionA.items.length);
      final squat = a.exercises[3]; // 前三项是活动度热身
      expect(squat.warmupSets, 3);
      expect(squat.targetSets, 3);
      expect(squat.repsMin, 5);
      expect(squat.repsMax, 8);
      expect(squat.restSec, 150);
      expect(squat.note, isNotEmpty);
      final plank = a.exercises.last;
      expect(plank.targetDurationSec, 40);
      expect(plank.repsMin, isNull);
    });

    test('已有当前计划时，加入的新计划不抢当前；添加到日历才替换并从所选周一开始', () async {
      final mine = await plans.createPlan('我自己的计划', 7);
      expect((await plans.getPlan(mine))!.plan.isActive, isTrue);
      final p = bySlug('shape-arm-tone');
      final id = await lib.join(p);
      expect((await plans.getPlan(id))!.plan.isActive, isFalse);

      await lib.join(p, activate: true, startFrom: DateTime(2026, 11, 11)); // 下周三
      final view = (await plans.getPlan(id))!;
      expect(view.plan.isActive, isTrue);
      expect(view.plan.startDate, '2026-11-09');
      expect((await plans.getPlan(mine))!.plan.isActive, isFalse);
    });

    test('「设为当前」同样把计划库计划对齐到周一', () async {
      await plans.createPlan('占位', 7);
      final id = await lib.join(bySlug('stretch-bedtime'));
      await plans.activatePlan(id);
      expect((await plans.getPlan(id))!.plan.startDate, '2026-11-02');
    });

    test('去训练：按完成节数轮转课次；开始训练带出热身组、时长目标、休息与要点', () async {
      final p = bySlug('muscle-barbell-novice');
      expect(ProgramLibraryRepository.nextSession(p, 0)!.key, 'A');
      expect(ProgramLibraryRepository.nextSession(p, 1)!.key, 'B');
      expect(ProgramLibraryRepository.nextSession(p, 2)!.key, 'A');

      final r = await lib.startSession(workouts, p, p.sessionByKey('A')!);
      expect(r.created, isTrue);
      expect(r.workout.sourceProgramId, p.id);
      expect(r.workout.name, contains('新手杠铃入门'));

      final view = (await workouts.loadWorkout(r.workout.id))!;
      expect(view.exercises.length, p.sessionByKey('A')!.items.length);
      final squat = view.exercises[3]; // 前三项是活动度热身
      expect(squat.sets.map((s) => s.kind).toList(), ['warmup', 'warmup', 'warmup', 'normal', 'normal', 'normal']);
      expect(squat.exercise.restSec, 150);
      expect(squat.exercise.note, isNotEmpty);
      final plank = view.exercises.last;
      expect(plank.sets.every((s) => s.durationSec == 40), isTrue);
      expect(plank.sets.length, 3);

      // 已有进行中的训练：不会重复创建
      final again = await lib.startSession(workouts, p, p.sessionByKey('B')!);
      expect(again.created, isFalse);
      expect(again.workout.id, r.workout.id);
    });

    test('带距离目标的有氧：目标写进动作要点', () async {
      final p = bySlug('rowing-endurance');
      final r = await lib.startSession(workouts, p, p.sessionByKey('B')!);
      final view = (await workouts.loadWorkout(r.workout.id))!;
      final row = view.exercises.first;
      expect(row.exercise.note, contains('目标 4 公里'));
      expect(row.sets.single.durationSec, 25 * 60);
    });

    test('从加入的计划里开始训练：训练记录继承来源计划，完成后计入「已练几节」', () async {
      final p = bySlug('treadmill-starter');
      final planId = await lib.join(p);
      final view = (await plans.getPlan(planId))!;
      final tid = view.dayAt(0)!.templateId!;
      final w = await plans.startFromTemplate(workouts, tid, planId: planId);
      expect(w.sourceProgramId, p.id);
      expect(w.planId, planId);

      final wv = (await workouts.loadWorkout(w.id))!;
      for (final s in wv.exercises.expand((b) => b.sets)) {
        await workouts.setCompleted(s.id, true);
      }
      await workouts.finishWorkout(w.id);
      final counts = await lib.watchCompletedCounts().first;
      expect(counts[p.id], 1);
      expect((await lib.watchJoined().first)[p.id], planId);
    });

    test('收藏：同一计划在同一账号下 id 固定，取消后再收藏会复原同一行', () async {
      final p = bySlug('glute-home-start');
      expect(lib.favoriteId(p.id), lib.favoriteId(p.id));
      expect(lib.favoriteId(p.id), isNot(ProgramLibraryRepository(db, userId: () => 'u2').favoriteId(p.id)));
      await lib.setFavorite(p.id, true);
      expect(await lib.watchFavoriteIds().first, {p.id});
      await lib.setFavorite(p.id, false);
      expect(await lib.watchFavoriteIds().first, isEmpty);
      await lib.setFavorite(p.id, true);
      expect(await lib.watchFavoriteIds().first, {p.id});
      expect(await db.select(db.favoritePrograms).get(), hasLength(1));
      await lib.setFavorite('不存在', false); // 对没收藏过的取消收藏不报错
    });
  });

  test('本地库从 v4 升级到 v5：旧数据保留，新列有默认值，新表可用', () async {
    final dir = Directory.systemTemp.createTempSync('mf_mig');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    final old = AppDatabase.forTesting(NativeDatabase(file));
    final t = DateTime(2026, 11, 1);
    await old.into(old.templates).insert(TemplatesCompanion.insert(id: 't', createdAt: t, updatedAt: t, userId: 'u', name: '旧模板'));
    await old.into(old.templateExercises).insert(TemplateExercisesCompanion.insert(
        id: 'te', createdAt: t, updatedAt: t, userId: 'u', templateId: 't', exerciseId: 'e', position: 0));
    await old.into(old.plans).insert(PlansCompanion.insert(
        id: 'p', createdAt: t, updatedAt: t, userId: 'u', name: '旧计划', cycleDays: 7, startDate: '2026-11-02'));
    await old.into(old.workouts).insert(WorkoutsCompanion.insert(
        id: 'w', createdAt: t, updatedAt: t, userId: 'u', startedAt: t, localDate: '2026-11-01'));
    // 还原成 v4 的样子
    await old.customStatement('ALTER TABLE template_exercises DROP COLUMN warmup_sets');
    await old.customStatement('ALTER TABLE template_exercises DROP COLUMN target_duration_sec');
    await old.customStatement('ALTER TABLE plans DROP COLUMN source_program_id');
    await old.customStatement('ALTER TABLE workouts DROP COLUMN source_program_id');
    await old.customStatement('DROP TABLE favorite_programs');
    await old.customStatement('PRAGMA user_version = 4');
    await old.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);
    final te = await db.select(db.templateExercises).getSingle();
    expect(te.warmupSets, 0);
    expect(te.targetDurationSec, isNull);
    expect((await db.select(db.plans).getSingle()).sourceProgramId, isNull);
    expect((await db.select(db.workouts).getSingle()).sourceProgramId, isNull);
    expect((await db.select(db.templates).getSingle()).name, '旧模板');
    await db.into(db.favoritePrograms).insert(
        FavoriteProgramsCompanion.insert(id: 'f', createdAt: t, updatedAt: t, userId: 'u', programId: 'x'));
    expect(await db.select(db.favoritePrograms).get(), hasLength(1));
  });
}
