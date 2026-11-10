import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/core/db/database_provider.dart';
import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_repository.dart';
import 'package:my_fitness/features/plan/plan_providers.dart';
import 'package:my_fitness/features/stats/body_repository.dart';
import 'package:my_fitness/features/stats/stats_page.dart';
import 'package:my_fitness/features/stats/stats_providers.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

import 'exercises_test.dart' show loadSeed;

class _FakeRepo implements ExerciseRepository {
  _FakeRepo(this.items);
  final List<Exercise> items;
  @override
  Future<List<Exercise>> loadAll() async => items;
}

void main() {
  final all = loadSeed();
  final bench = all.firstWhere((e) => e.nameZh == '杠铃卧推');
  final today = DateTime(2026, 11, 4);

  late AppDatabase db;
  late WorkoutRepository workouts;
  late BodyRepository body;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    workouts = WorkoutRepository(db, userId: () => 'u', now: () => DateTime(2026, 11, 3, 18));
    body = BodyRepository(db, userId: () => 'u', now: () => DateTime(2026, 11, 3, 18));
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      workoutRepositoryProvider.overrideWithValue(workouts),
      bodyRepositoryProvider.overrideWithValue(body),
      exerciseRepositoryProvider.overrideWithValue(_FakeRepo(all)),
      todayProvider.overrideWithValue(today),
    ]);
    // 让页面按测试里的「今天」定位当周
    container.read(statsViewProvider.notifier).reset(today);
  });
  tearDown(() async {
    await db.close();
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 9000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light(), home: const StatsPage()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('没有任何记录：显示空状态，不崩', (tester) async {
    await mount(tester);
    expect(find.text('11月2日 – 11月8日'), findsOneWidget);
    expect(find.text('这段时间还没有训练记录'), findsOneWidget);
    expect(find.text('打破自己的最好成绩后，会出现在这里'), findsOneWidget);
    expect(find.text('记录几天后会显示变化曲线'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('有记录：KPI、肌肉列表、纪录都有内容；切换到月与翻页', (tester) async {
    Future<void> train(DateTime day, double kg) async {
      final repo = WorkoutRepository(db, userId: () => 'u', now: () => day);
      final w = await repo.startWorkout();
      final we = await repo.addExercise(w.id, bench.id, defaultSets: 0);
      for (var i = 0; i < 4; i++) {
        final s = await repo.addSet(we);
        await repo.updateSet(s, weightKg: kg, reps: 8);
        await repo.setCompleted(s, true);
      }
      final end = WorkoutRepository(db, userId: () => 'u', now: () => day.add(const Duration(minutes: 60)));
      await end.finishWorkout(w.id);
    }

    await train(DateTime(2026, 10, 27, 18), 60);
    await train(DateTime(2026, 11, 3, 18), 65);
    await mount(tester);

    // 本周 1 次，容量 65×8×4 = 2080 kg → 2.1 吨；上周 1 次 1920 kg
    expect(find.textContaining('2.1', findRichText: true), findsWidgets);
    expect(find.textContaining('较上期 +8%'), findsOneWidget);
    expect(find.text('胸大肌'), findsOneWidget);
    expect(find.text('杠铃卧推'), findsWidgets); // 个人纪录
    expect(find.text('11月3日  重量纪录'), findsOneWidget);

    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    expect(find.text('2026年11月'), findsOneWidget);

    await tester.tap(find.byTooltip('上一段'));
    await tester.pumpAndSettle();
    expect(find.text('2026年10月'), findsOneWidget);
    expect(find.text('2026年11月'), findsNothing);

    // 回到当前月后，不能再往后翻
    await tester.tap(find.byTooltip('下一段'));
    await tester.pumpAndSettle();
    expect(find.text('2026年11月'), findsOneWidget);
    final next = tester.widget<IconButton>(find.widgetWithIcon(IconButton, AppIcons.chevronRight));
    expect(next.onPressed, isNull);
    await unmount(tester);
  });

  testWidgets('体重：记录一条后显示数值', (tester) async {
    await body.setWeight(DateTime(2026, 10, 20), 73.0);
    await body.setWeight(DateTime(2026, 11, 3), 72.4);
    await mount(tester);
    expect(find.textContaining('72.4', findRichText: true), findsOneWidget);
    expect(find.text('30 天 −0.6'), findsOneWidget);
    await unmount(tester);
  });
}
