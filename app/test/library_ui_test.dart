import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/core/db/database_provider.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_repository.dart';
import 'package:my_fitness/features/library/library_page.dart';
import 'package:my_fitness/features/library/library_providers.dart';
import 'package:my_fitness/features/library/library_repository.dart';
import 'package:my_fitness/features/library/program.dart';
import 'package:my_fitness/features/library/program_detail_page.dart';
import 'package:my_fitness/features/library/session_detail_page.dart';
import 'package:my_fitness/features/plan/plan_providers.dart';
import 'package:my_fitness/features/plan/plan_repository.dart';
import 'package:my_fitness/features/sync/sync_providers.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

import 'exercises_test.dart' show loadSeed;
import 'library_test.dart' show loadPrograms;

class _IdleSync extends SyncController {
  @override
  SyncStatus build() => SyncStatus(lastSync: DateTime(2026, 11, 2, 8));
  @override
  Future<void> requestSync() async {}
}

class _FakeRepo implements ExerciseRepository {
  _FakeRepo(this.items);
  final List<Exercise> items;
  @override
  Future<List<Exercise>> loadAll() async => items;
}

class _MemorySource implements ProgramSource {
  _MemorySource(this.items);
  final List<Program> items;
  @override
  Future<List<Program>> loadAll() async => items;
}

void main() {
  late AppDatabase db;
  late WorkoutRepository workouts;
  late PlanRepository plans;
  late ProgramLibraryRepository lib;
  final programs = loadPrograms();
  final exercises = loadSeed();
  final clock = DateTime(2026, 11, 4, 9); // 周三

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    workouts = WorkoutRepository(db, userId: () => 'u1', now: () => clock);
    plans = PlanRepository(db, userId: () => 'u1', now: () => clock);
    lib = ProgramLibraryRepository(db, userId: () => 'u1', now: () => clock);
  });
  tearDown(() => db.close());

  Widget host(Widget home) {
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(path: '/start', builder: (_, _) => home),
        GoRoute(path: '/library', builder: (_, _) => const LibraryPage()),
        GoRoute(
          path: '/library/:slug',
          builder: (_, s) => ProgramDetailPage(slug: s.pathParameters['slug']!),
          routes: [
            GoRoute(
              path: ':key',
              builder: (_, s) => SessionDetailPage(
                slug: s.pathParameters['slug']!,
                sessionKey: s.pathParameters['key']!,
              ),
            ),
          ],
        ),
        GoRoute(path: '/exercise/:slug', builder: (_, _) => const Scaffold(body: Text('动作页'))),
        GoRoute(path: '/workout', builder: (_, _) => const Scaffold(body: Text('训练页'))),
        GoRoute(path: '/plan', builder: (_, _) => const Scaffold(body: Text('计划页'))),
        GoRoute(path: '/calendar', builder: (_, _) => const Scaffold(body: Text('日历页'))),
      ],
    );
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        workoutRepositoryProvider.overrideWithValue(workouts),
        planRepositoryProvider.overrideWithValue(plans),
        libraryRepositoryProvider.overrideWithValue(lib),
        programSourceProvider.overrideWithValue(_MemorySource(programs)),
        exerciseRepositoryProvider.overrideWithValue(_FakeRepo(exercises)),
        profileSummaryProvider.overrideWithValue(null),
        todayProvider.overrideWithValue(DateTime(2026, 11, 4)),
        syncControllerProvider.overrideWith(_IdleSync.new),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  void setViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('计划库：分类栏 + 切换分类 + 难度筛选', (tester) async {
    setViewport(tester);
    await tester.pumpWidget(host(const LibraryPage()));
    await tester.pumpAndSettle();
    for (final label in ['近期上新', '新手入门', '瘦身减脂', '增肌增重', '丰满翘臀']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.textContaining('个计划'), findsWidgets);

    await tester.tap(find.text('增肌增重').first);
    await tester.pumpAndSettle();
    expect(find.text('增肌增重 · ${programs.where((p) => p.category == '增肌增重').length} 个计划'), findsOneWidget);

    await tester.tap(find.text('难度').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('高阶').last);
    await tester.pumpAndSettle();
    final advanced = programs.where((p) => p.category == '增肌增重' && p.level == 3).length;
    expect(find.text('增肌增重 · $advanced 个计划'), findsOneWidget);
    expect(find.text('清除筛选'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('计划库：点卡片进入详情，加入计划后生成模板与计划', (tester) async {
    setViewport(tester);
    final p = programs.firstWhere((p) => p.slug == 'muscle-barbell-novice');
    await tester.pumpWidget(host(const LibraryPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('增肌增重').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(p.name).first);
    await tester.pumpAndSettle();

    expect(find.text('每周安排'), findsOneWidget);
    expect(find.text('课程（${p.sessions.length} 节）'), findsOneWidget);
    expect(find.text('加入计划'), findsOneWidget);

    await tester.tap(find.text('加入计划'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已加入'), findsWidgets);
    final joined = (await tester.runAsync(() => lib.watchJoined().first))!;
    expect(joined.keys, [p.id]);
    expect((await plans.getPlan(joined[p.id]!))!.plan.name, p.name);
    expect((await plans.listTemplates()).length, p.sessions.length);
    await unmount(tester);
  });

  testWidgets('详情：「练这节」直接开始训练，热身组与要点带进训练', (tester) async {
    setViewport(tester);
    final p = programs.firstWhere((p) => p.slug == 'muscle-barbell-novice');
    await tester.pumpWidget(host(ProgramDetailPage(slug: p.slug)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('练这节').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('练这节').first);
    await tester.pumpAndSettle();
    expect(find.text('训练页'), findsOneWidget);

    final active = (await workouts.activeWorkout())!;
    expect(active.sourceProgramId, p.id);
    final view = (await workouts.loadWorkout(active.id))!;
    expect(view.exercises.length, p.sessionByKey('A')!.items.length);
    expect(view.exercises[3].sets.where((s) => s.kind == 'warmup').length, 3);
    await unmount(tester);
  });

  testWidgets('课程详情：动作链逐项列出目标，底部按钮开始训练', (tester) async {
    setViewport(tester);
    final p = programs.firstWhere((p) => p.slug == 'muscle-barbell-novice');
    await tester.pumpWidget(host(SessionDetailPage(slug: p.slug, sessionKey: 'A')));
    await tester.pumpAndSettle();
    expect(find.textContaining('热身 3 组'), findsWidgets);
    expect(find.text('开始这节训练'), findsOneWidget);
    await tester.tap(find.text('开始这节训练'));
    await tester.pumpAndSettle();
    expect(find.text('训练页'), findsOneWidget);
    expect(await workouts.activeWorkout(), isNotNull);
    await unmount(tester);
  });

  testWidgets('详情：星标收藏后出现在「我的收藏」', (tester) async {
    setViewport(tester);
    final p = programs.firstWhere((p) => p.slug == 'stretch-bedtime');
    await tester.pumpWidget(host(ProgramDetailPage(slug: p.slug)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.star_border_rounded));
    await tester.pumpAndSettle();
    expect((await tester.runAsync(() => lib.watchFavoriteIds().first))!, {p.id});
    await unmount(tester);
  });
}
