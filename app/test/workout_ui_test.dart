import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/core/db/database_provider.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_repository.dart';
import 'package:my_fitness/features/workout/workout_math.dart';
import 'package:my_fitness/features/workout/workout_page.dart';
import 'package:my_fitness/features/workout/workout_pick_page.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';
import 'package:my_fitness/features/workout/workout_summary_page.dart';

import 'exercises_test.dart' show loadSeed;

class _FakeRepo implements ExerciseRepository {
  _FakeRepo(this.items);
  final List<Exercise> items;
  @override
  Future<List<Exercise>> loadAll() async => items;
}

void main() {
  late AppDatabase db;
  late WorkoutRepository repo;
  final all = loadSeed();
  final bench = all.firstWhere((e) => e.nameZh.contains('卧推'));

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = WorkoutRepository(db, userId: () => 'u1');
  });
  tearDown(() => db.close());

  Widget host(Widget home, {List<RouteBase> extra = const []}) {
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(path: '/start', builder: (_, _) => home),
        GoRoute(path: '/today', builder: (_, _) => const Scaffold(body: Text('首页'))),
        GoRoute(path: '/workout/pick', builder: (_, _) => const WorkoutPickPage()),
        ...extra,
      ],
    );
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        workoutRepositoryProvider.overrideWithValue(repo),
        exerciseRepositoryProvider.overrideWithValue(_FakeRepo(all)),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
  }

  testWidgets('没有进行中的训练时给出回首页入口', (tester) async {
    await tester.pumpWidget(host(const WorkoutPage()));
    await tester.pumpAndSettle();
    expect(find.text('没有进行中的训练'), findsOneWidget);
  });

  testWidgets('训练页显示动作与组，空组不能直接打勾', (tester) async {
    final w = await repo.startWorkout();
    await repo.addExercise(w.id, bench.id);
    await tester.pumpWidget(host(const WorkoutPage()));
    await tester.pumpAndSettle();

    expect(find.text(bench.nameZh), findsWidgets);
    expect(find.bySemanticsLabel('完成第 1 组'), findsWidgets);

    await tester.tap(find.bySemanticsLabel('完成第 1 组').first);
    await tester.pump();
    expect(find.text('先填重量和次数'), findsOneWidget);
  });

  testWidgets('填好重量次数后打勾：该组完成并开始休息计时', (tester) async {
    final w = await repo.startWorkout();
    final weId = await repo.addExercise(w.id, bench.id, defaultSets: 0);
    final setId = await repo.addSet(weId);
    await repo.updateSet(setId, weightKg: 60, reps: 8);

    await tester.pumpWidget(host(const WorkoutPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('完成第 1 组').first);
    await tester.pumpAndSettle();

    final view = await repo.loadWorkout(w.id);
    expect(view!.exercises.single.sets.single.completed, isTrue);
    expect(find.text('组间休息'), findsOneWidget);
    expect(find.bySemanticsLabel('取消完成第 1 组'), findsOneWidget);
  });

  testWidgets('从选择页挑动作加入当前训练', (tester) async {
    final w = await repo.startWorkout();
    await tester.pumpWidget(host(const WorkoutPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加动作').first);
    await tester.pumpAndSettle();
    expect(find.text('选择动作'), findsOneWidget);

    await tester.tap(find.text(
        all.firstWhere((e) => e.bodyPart == BodyPart.chest).nameZh).first);
    await tester.pumpAndSettle();

    expect(find.text('选择动作'), findsNothing);
    final view = await repo.loadWorkout(w.id);
    expect(view!.exercises, hasLength(1));
  });

  testWidgets('总结页展示时长、容量、组数和纪录', (tester) async {
    final summary = WorkoutSummary(
      workoutId: 'w',
      duration: const Duration(minutes: 52),
      volume: 12345,
      setCount: 14,
      exerciseCount: 4,
      prs: {bench.id: {PrKind.weight, PrKind.oneRepMax}},
    );
    await tester.pumpWidget(host(WorkoutSummaryPage(summary: summary)));
    await tester.pumpAndSettle();

    expect(find.text('训练完成'), findsOneWidget);
    expect(find.text('52分钟'), findsOneWidget);
    expect(find.text('12.35 吨'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('重量纪录 · 1RM 纪录'), findsOneWidget);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsOneWidget);
  });
}
