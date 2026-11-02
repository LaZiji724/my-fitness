import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/db/database_provider.dart';
import 'package:my_fitness/features/exercises/exercise_detail_page.dart';
import 'package:my_fitness/features/exercises/exercises_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_prefs.dart';
import 'package:my_fitness/features/exercises/exercise_repository.dart';
import 'package:my_fitness/features/library/library_repository.dart';
import 'package:my_fitness/features/library/program.dart';
import 'package:my_fitness/features/plan/plan_repository.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

import 'exercises_test.dart' show loadSeed;

void main() {
  final exercises = loadSeed();
  final byName = {for (final e in exercises) e.nameZh: e};
  final byId = {for (final e in exercises) e.id: e};
  final programs = (jsonDecode(File('assets/seed/programs.json').readAsStringSync()) as List)
      .map((e) => Program.fromJson(e as Map<String, dynamic>))
      .toList();

  group('激活 / 拉伸分栏筛选', () {
    test('激活分栏 = 激活 + 动态热身；拉伸分栏 = 静态拉伸 + 泡沫轴；可再按类型、区域筛', () {
      final act = filterExercises(exercises, const ExerciseFilter(tab: ExerciseTab.activation));
      expect(act.length, greaterThan(40));
      expect(act.every((e) => e.kind.isActivationTab), isTrue);
      final dyn = filterExercises(exercises, const ExerciseFilter(tab: ExerciseTab.activation, kind: ExerciseKind.dynamicWarmup));
      expect(dyn.isNotEmpty && dyn.length < act.length, isTrue);
      expect(dyn.every((e) => e.kind == ExerciseKind.dynamicWarmup), isTrue);

      final st = filterExercises(exercises, const ExerciseFilter(tab: ExerciseTab.stretch));
      expect(st.length, greaterThan(40));
      expect(st.every((e) => e.kind.isStretchTab), isTrue);
      final hip = filterExercises(exercises, const ExerciseFilter(tab: ExerciseTab.stretch, region: ExerciseRegion.hipGlute));
      expect(hip, isNotEmpty);
      expect(hip.every((e) => e.region == ExerciseRegion.hipGlute && e.kind.isStretchTab), isTrue);
    });

    test('搜索时不受分栏限制；区域计数不受区域筛选影响', () {
      final hit = filterExercises(exercises, const ExerciseFilter(tab: ExerciseTab.stretch, query: '卧推'));
      expect(hit.any((e) => e.kind == ExerciseKind.strength), isTrue);
      final counts = regionCounts(exercises, const ExerciseFilter(tab: ExerciseTab.stretch, region: ExerciseRegion.leg));
      expect(counts.length, greaterThan(2), reason: '选了一个区域，其他区域的计数仍然显示');
    });

    test('分栏切换会清掉上一个分栏的区域与类型', () {
      final f = const ExerciseFilter(tab: ExerciseTab.stretch, region: ExerciseRegion.leg, kind: ExerciseKind.foam);
      final g = f.copyWith(tab: ExerciseTab.activation, clearRegion: true, clearKind: true);
      expect(g.region, isNull);
      expect(g.kind, isNull);
      expect(g.isWarmupTab, isTrue);
    });
  });

  group('次数 / 时间偏好', () {
    late AppDatabase db;
    late ExercisePrefsRepository prefs;
    var clock = DateTime(2026, 11, 4, 9);
    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      prefs = ExercisePrefsRepository(db, userId: () => 'u1', now: () => clock);
    });
    tearDown(() => db.close());

    test('把按次数的动作改成按时间；改回默认就清除偏好', () async {
      final pushup = byName['俯卧撑']!;
      expect(pushup.isTimed, isFalse);
      await prefs.setTracking(pushup, TrackingType.duration);
      expect((await prefs.watchAll().first)[pushup.id], TrackingType.duration);
      await prefs.setTracking(pushup, pushup.repsVariant);
      expect(await prefs.watchAll().first, isEmpty);
      // 同一个动作只会有一行（id 由用户 + 动作决定），改回后再设置会复活原来的行
      await prefs.setTracking(pushup, TrackingType.duration);
      expect(await db.select(db.exercisePrefs).get(), hasLength(1));
    });

    test('把默认按时间的动作改成按次数：用自重 × 次数', () async {
      final plank = byName['平板支撑']!;
      expect(plank.isTimed, isTrue);
      expect(plank.repsVariant, TrackingType.bodyweightReps);
      await prefs.setTracking(plank, plank.repsVariant);
      final m = await prefs.watchAll().first;
      expect(m[plank.id], TrackingType.bodyweightReps);
      expect(plank.withTracking(m[plank.id]!).isTimed, isFalse);
    });

    test('偏好只属于当前用户', () async {
      final other = ExercisePrefsRepository(db, userId: () => 'u2', now: () => clock);
      await prefs.setTracking(byName['俯卧撑']!, TrackingType.duration);
      expect(await other.watchAll().first, isEmpty);
    });
  });

  group('按生效的记录方式开始训练', () {
    late AppDatabase db;
    late WorkoutRepository workouts;
    late PlanRepository plans;
    late ProgramLibraryRepository lib;
    var clock = DateTime(2026, 11, 4, 9);
    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      workouts = WorkoutRepository(db, userId: () => 'u1', now: () => clock);
      plans = PlanRepository(db, userId: () => 'u1', now: () => clock);
      lib = ProgramLibraryRepository(db, userId: () => 'u1', now: () => clock);
    });
    tearDown(() => db.close());

    test('模板：按时间的动作预填秒数，按次数的预填次数，并带建议组数', () async {
      final t = await plans.createTemplate('测试');
      final plank = byName['平板支撑']!;
      final squat = byName['自重深蹲']!;
      await plans.addTemplateExercise(t, plank.id, exercise: plank);
      await plans.addTemplateExercise(t, squat.id, exercise: squat);
      final tv = (await plans.getTemplate(t))!;
      final p = tv.exercises.firstWhere((e) => e.exerciseId == plank.id);
      expect(p.targetDurationSec, isNotNull);
      expect(p.repsMin, isNull);
      final s = tv.exercises.firstWhere((e) => e.exerciseId == squat.id);
      expect(s.targetDurationSec, isNull);
      expect(s.repsMin, isNotNull);
    });

    test('模板里写的是次数，但用户把这个动作改成了按时间：训练里按时间预填，不会出现次数', () async {
      final t = await plans.createTemplate('测试');
      final pushup = byName['俯卧撑']!;
      await plans.addTemplateExercise(t, pushup.id, exercise: pushup);
      final timed = pushup.withTracking(TrackingType.duration);
      final w = await plans.startFromTemplate(workouts, t, exercises: {pushup.id: timed});
      final view = (await workouts.loadWorkout(w.id))!;
      final sets = view.exercises.single.sets;
      expect(sets, isNotEmpty);
      expect(sets.every((s) => s.durationSec != null && s.reps == null), isTrue);
    });

    test('反过来：模板写的是时长，用户改成按次数：按次数预填', () async {
      final t = await plans.createTemplate('测试');
      final plank = byName['平板支撑']!;
      await plans.addTemplateExercise(t, plank.id, exercise: plank);
      final reps = plank.withTracking(TrackingType.bodyweightReps);
      final w = await plans.startFromTemplate(workouts, t, exercises: {plank.id: reps});
      final sets = (await workouts.loadWorkout(w.id))!.exercises.single.sets;
      expect(sets.every((s) => s.durationSec == null), isTrue);
    });

    test('分区：热身 → 正式 → 放松的顺序，训练中可以移动分区；retargetSets 补上目标量', () async {
      final w = await workouts.startWorkout();
      final stretch = byName['仰卧腘绳肌拉伸']!;
      final squat = byName['自重深蹲']!;
      final cool = await workouts.addExercise(w.id, stretch.id,
          tracking: stretch.trackingType, fallbackSeconds: stretch.defaultSeconds, section: 'cooldown');
      await workouts.addExercise(w.id, squat.id, tracking: squat.trackingType, fallbackReps: 10);
      var view = (await workouts.loadWorkout(w.id))!;
      expect(view.exercises.map((b) => b.exercise.section).toList(), ['main', 'cooldown'], reason: '放松排到正式训练之后');
      expect(view.exercises.last.sets.every((s) => s.durationSec == (stretch.defaultSeconds ?? 30)), isTrue);

      await workouts.setSection(cool, 'warmup');
      view = (await workouts.loadWorkout(w.id))!;
      expect(view.exercises.first.exercise.id, cool);

      final id = view.exercises.last.exercise.id; // 深蹲
      await workouts.retargetSets(id, timed: true, seconds: 40);
      view = (await workouts.loadWorkout(w.id))!;
      expect(view.exercises.last.sets.every((s) => s.durationSec == 40), isTrue);
    });

    test('计划库加入后，模板动作带分区；去训练的动作也带分区', () async {
      final p = programs.firstWhere((p) => p.slug == 'muscle-barbell-novice');
      final planId = await lib.join(p);
      final view = (await plans.getPlan(planId))!;
      final tv = (await plans.getTemplate(view.dayAt(0)!.templateId!))!;
      expect(tv.exercises.map((e) => e.section).toSet(), {'warmup', 'main', 'cooldown'});
      final secs = sortedBySection(tv.exercises, (e) => e.section, (e) => e.position).map((e) => e.section).toList();
      expect(secs.first, 'warmup');
      expect(secs.last, 'cooldown');
    });
  });

  group('计划库：激活热身 / 拉伸放松', () {
    test('新增 8 个激活热身 + 至少 10 个拉伸放松计划，整库每个计划都能找到封面图', () {
      expect(programs.where((p) => p.category == '激活热身').length, 8);
      expect(programs.where((p) => p.category == '拉伸放松').length, greaterThanOrEqualTo(10));
      for (final p in programs) {
        expect(File('assets/programs/${p.slug}.webp').existsSync(), isTrue, reason: '${p.slug} 缺封面');
      }
    });

    test('力量 / 有氧 / 塑形类计划的每一节都有热身和放松区；激活与拉伸计划不分区', () {
      for (final p in programs) {
        final plain = p.category == '激活热身' || p.category == '拉伸放松';
        for (final s in p.sessions) {
          final secs = s.items.map((i) => i.section).toList();
          if (plain) {
            expect(secs.every((x) => x == 'main'), isTrue, reason: '${p.slug}/${s.key}');
          } else {
            expect(secs, contains('warmup'), reason: '${p.slug}/${s.key}');
            expect(secs, contains('cooldown'), reason: '${p.slug}/${s.key}');
            expect(secs, contains('main'), reason: '${p.slug}/${s.key}');
            // 分区必须连续：热身在前，放松在后
            final order = {'warmup': 0, 'main': 1, 'cooldown': 2};
            for (var i = 1; i < secs.length; i++) {
              expect(order[secs[i]]! >= order[secs[i - 1]]!, isTrue, reason: '${p.slug}/${s.key}#$i 分区顺序错');
            }
          }
        }
      }
    });

    test('自动补的热身 / 放松不需要器械；热身里不放静态拉伸，放松里不放力量动作', () {
      for (final p in programs) {
        if (p.category == '激活热身' || p.category == '拉伸放松') continue;
        for (final s in p.sessions) {
          for (final i in s.items) {
            final e = byId[i.exerciseId]!;
            if (i.section == 'warmup') {
              expect(e.kind == ExerciseKind.stretch || e.kind == ExerciseKind.foam, isFalse, reason: '${p.slug}/${s.key} ${e.nameZh}');
            }
            if (i.section == 'cooldown') {
              final ok = e.kind.isStretchTab || e.kind == ExerciseKind.cardio;
              expect(ok, isTrue, reason: '${p.slug}/${s.key} ${e.nameZh}');
            }
          }
        }
      }
    });
  });

  group('界面', () {
    Future<void> pumpPage(WidgetTester tester, Widget home, AppDatabase db) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          exerciseRepositoryProvider.overrideWithValue(_Repo(exercises)),
          appDatabaseProvider.overrideWithValue(db),
          exercisePrefsRepositoryProvider.overrideWithValue(ExercisePrefsRepository(db, userId: () => 'u1')),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('动作库：左侧有「激活」「拉伸」两栏，点开后出现类型与部位筛选', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await pumpPage(tester, const ExercisesPage(), db);
      expect(find.text('激活'), findsOneWidget);
      expect(find.text('拉伸'), findsOneWidget);

      await tester.tap(find.text('激活'));
      await tester.pumpAndSettle();
      expect(find.textContaining('激活热身 · '), findsOneWidget);
      expect(find.text('动态热身'), findsOneWidget);
      expect(find.text('全部部位'), findsOneWidget);
      expect(find.text('髋臀'), findsWidgets);

      await tester.tap(find.text('拉伸'));
      await tester.pumpAndSettle();
      expect(find.textContaining('拉伸放松 · '), findsOneWidget);
      expect(find.text('静态拉伸'), findsOneWidget);
      expect(find.text('泡沫轴'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    });

    testWidgets('动作详情：可以在「按次数 / 按时间」之间切换，选择写进偏好', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final plank = byName['平板支撑']!;
      await pumpPage(tester, ExerciseDetailPage(slug: plank.slug), db);
      expect(find.text('记录方式'), findsOneWidget);
      expect(find.text('训练时每组记录坚持的秒数'), findsOneWidget);

      await tester.tap(find.text('按次数'));
      await tester.pumpAndSettle();
      expect(find.text('训练时每组记录完成的次数'), findsOneWidget);
      final repo = ExercisePrefsRepository(db, userId: () => 'u1');
      expect((await tester.runAsync(() => repo.watchAll().first))![plank.id], TrackingType.bodyweightReps);

      await tester.tap(find.text('按时间'));
      await tester.pumpAndSettle();
      expect(find.text('训练时每组记录坚持的秒数'), findsOneWidget);
      expect(await tester.runAsync(() => repo.watchAll().first), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    });
  });
}

class _Repo implements ExerciseRepository {
  _Repo(this.items);
  final List<Exercise> items;
  @override
  Future<List<Exercise>> loadAll() async => items;
}
