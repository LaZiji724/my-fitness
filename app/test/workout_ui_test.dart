import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/core/db/database_provider.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_detail_page.dart';
import 'package:my_fitness/features/exercises/exercise_image.dart';
import 'package:my_fitness/features/exercises/exercise_prefs.dart';
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

  Widget host(Widget home, {List<RouteBase> extra = const [], bool withPrefs = false}) {
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(path: '/start', builder: (_, _) => home),
        GoRoute(path: '/today', builder: (_, _) => const Scaffold(body: Text('首页'))),
        GoRoute(
          path: '/workout/pick',
          builder: (_, _) => const WorkoutPickPage(),
          routes: [GoRoute(path: ':slug', builder: (_, state) => WorkoutPickDetailPage(slug: state.pathParameters['slug']!))],
        ),
        ...extra,
      ],
    );
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        workoutRepositoryProvider.overrideWithValue(repo),
        exerciseRepositoryProvider.overrideWithValue(_FakeRepo(all)),
        if (withPrefs) exercisePrefsRepositoryProvider.overrideWithValue(ExercisePrefsRepository(db, userId: () => 'u1')),
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

  testWidgets('训练中点动作卡片的图片和名字：进入动作详情页看大图，返回后训练还在', (tester) async {
    final w = await repo.startWorkout();
    await repo.addExercise(w.id, bench.id);
    await tester.pumpWidget(host(
      const WorkoutPage(),
      extra: [GoRoute(path: '/exercise/:slug', builder: (_, st) => ExerciseDetailPage(slug: st.pathParameters['slug']!))],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(bench.nameZh).first);
    await tester.pumpAndSettle();
    // 详情页：两张大图（起、止）和动作要领
    expect(find.byType(ExerciseImage), findsNWidgets(bench.imageCount));
    await tester.scrollUntilVisible(find.text('动作要领'), 300);
    expect(find.text(bench.instructionsZh!), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('完成第 1 组'), findsWidgets);
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
    // 先进详情，点「添加动作」才加入
    expect((await repo.loadWorkout(w.id))!.exercises, isEmpty);
    expect(find.text('加入设置'), findsOneWidget);
    await tester.tap(find.text('添加动作'));
    await tester.pumpAndSettle();

    expect(find.text('选择动作'), findsNothing);
    final view = await repo.loadWorkout(w.id);
    expect(view!.exercises, hasLength(1));
  });

  testWidgets('详情页改好模块、组数、次数、负重后加入当前训练', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final w = await repo.startWorkout();
    await tester.pumpWidget(host(const WorkoutPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加动作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(bench.nameZh).first);
    await tester.pumpAndSettle();

    // 放进「热身」，组数 +1，次数 +1，负重 +2.5 两下
    for (final finder in [
      find.text('热身'),
      find.bySemanticsLabel('组数 增加'),
      find.bySemanticsLabel('每组次数 增加'),
      find.bySemanticsLabel('负重 增加'),
      find.bySemanticsLabel('负重 增加'),
    ]) {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }
    expect(find.text('5 kg'), findsOneWidget);
    await tester.tap(find.text('添加动作'));
    await tester.pumpAndSettle();

    final ex = (await repo.loadWorkout(w.id))!.exercises.single;
    expect(ex.exercise.section, 'warmup');
    expect(ex.sets, hasLength(bench.defaultSets == null ? 4 : bench.defaultSets! + 1));
    expect(ex.sets.every((s) => s.weightKg == 5), isTrue);
    expect(ex.sets.first.reps, (bench.defaultReps ?? 10) + 1);
  });

  testWidgets('详情页选「按时间」：训练里按秒记，不出现次数', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final w = await repo.startWorkout();
    await tester.pumpWidget(host(const WorkoutPage(), withPrefs: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加动作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(bench.nameZh).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('按时间'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('每组时间'), findsOneWidget);
    expect(find.text('每组次数'), findsNothing);
    await tester.tap(find.bySemanticsLabel('每组时间 增加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加动作'));
    await tester.pumpAndSettle();

    final ex = (await repo.loadWorkout(w.id))!.exercises.single;
    expect(ex.sets.every((s) => s.reps == null), isTrue);
    expect(ex.sets.first.durationSec, (bench.defaultSeconds ?? 30) + 5);
    // 卸载页面，让监听偏好的数据库流先停下，tearDown 才能关库
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
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
    // 数字与单位分开排版（Text.rich），按整段文字查找
    expect(find.text('52 分钟', findRichText: true), findsOneWidget);
    expect(find.text('12.35 吨', findRichText: true), findsOneWidget);
    expect(find.text('14', findRichText: true), findsOneWidget);
    expect(find.text('重量纪录、1RM 纪录'), findsOneWidget);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsOneWidget);
  });
}
