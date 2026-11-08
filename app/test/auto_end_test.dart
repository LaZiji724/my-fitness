import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_fitness/app/router.dart';
import 'package:my_fitness/core/db/database_provider.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/features/workout/auto_end.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

void main() {
  late AppDatabase db;
  late DateTime clock;
  late WorkoutRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    clock = DateTime(2026, 11, 8, 9, 0, 0);
    repo = WorkoutRepository(db, userId: () => 'u1', now: () => clock);
  });
  tearDown(() => db.close());

  /// 开始训练并加一个动作 [sets] 组，勾选前 [done] 组。
  Future<WorkoutView> setup({int sets = 2, int done = 2}) async {
    final w = await repo.startWorkout();
    final weId = await repo.addExercise(w.id, 'ex-bench', defaultSets: sets, exactSets: true);
    var view = (await repo.loadWorkout(w.id))!;
    for (final s in view.exercises.single.sets) {
      await repo.updateSet(s.id, weightKg: 60, reps: 10);
    }
    view = (await repo.loadWorkout(w.id))!;
    for (final s in view.exercises.single.sets.take(done)) {
      clock = clock.add(const Duration(minutes: 5));
      await repo.setCompleted(s.id, true);
    }
    expect(weId, isNotEmpty);
    return (await repo.loadWorkout(w.id))!;
  }

  test('全部做完：空闲不足 1 分钟不结束，满 1 分钟按最后一次操作结算', () async {
    final view = await setup();
    final last = clock; // 09:10 最后一次操作
    expect(autoEndAt(view: view, now: last.add(const Duration(seconds: 59))), isNull);
    expect(autoEndAt(view: view, now: last.add(const Duration(minutes: 1))), last);
  });

  test('全部做完后还在休息：从休息结束那一刻起才计 1 分钟，时长不含空闲', () async {
    final view = await setup();
    final restEnd = clock.add(const Duration(seconds: 90));
    expect(autoEndAt(view: view, now: restEnd, holdUntil: restEnd), isNull);
    expect(autoEndAt(view: view, now: restEnd.add(const Duration(seconds: 59)), holdUntil: restEnd), isNull);
    expect(autoEndAt(view: view, now: restEnd.add(const Duration(minutes: 1)), holdUntil: restEnd), restEnd);
  });

  test('还有动作没做完：2 分钟没操作才结束，点过屏幕就重新计时', () async {
    final view = await setup(done: 1);
    final last = clock;
    expect(autoEndAt(view: view, now: last.add(const Duration(minutes: 1, seconds: 59))), isNull);
    expect(autoEndAt(view: view, now: last.add(const Duration(minutes: 2))), last);
    final touch = last.add(const Duration(minutes: 1));
    expect(autoEndAt(view: view, now: last.add(const Duration(minutes: 2)), lastTouch: touch), isNull);
    expect(autoEndAt(view: view, now: touch.add(const Duration(minutes: 2)), lastTouch: touch), touch);
  });

  test('一组都没完成：放宽到 10 分钟', () async {
    final view = await setup(done: 0);
    final last = view.workout.updatedAt;
    expect(autoEndAt(view: view, now: last.add(const Duration(minutes: 9))), isNull);
    expect(autoEndAt(view: view, now: last.add(const Duration(minutes: 10))), last);
  });

  test('自动结束：时长只算到最后一次操作，扣掉多出来的空闲', () async {
    final view = await setup();
    final started = view.workout.startedAt;
    final end = clock; // 最后一次操作
    clock = end.add(const Duration(minutes: 1)); // 过了 1 分钟才被发现
    final s = await repo.finishWorkout(view.workout.id, endedAt: end, auto: true);
    expect(s!.duration, end.difference(started));
    expect(s.auto, isTrue);
    final saved = (await repo.loadWorkout(view.workout.id))!.workout;
    expect(saved.endedAt, end);
  });

  test('同一天继续训练：动作和组保留，计时接着走，不含中间停掉的时间', () async {
    final view = await setup();
    final id = view.workout.id;
    final end = clock; // 09:10，已练 10 分钟
    await repo.finishWorkout(id);
    clock = end.add(const Duration(hours: 2)); // 11:10 回来继续
    final resumed = await repo.resumeWorkout(id);
    expect(resumed, isNotNull);
    expect(resumed!.endedAt, isNull);
    expect(clock.difference(resumed.startedAt), const Duration(minutes: 10));
    expect((await repo.activeWorkout())?.id, id);
    final again = (await repo.loadWorkout(id))!;
    expect(again.exercises.single.sets.where((s) => s.completed).length, 2);

    // 再练 5 分钟结束：总时长 15 分钟
    clock = clock.add(const Duration(minutes: 5));
    final s = await repo.finishWorkout(id);
    expect(s!.duration, const Duration(minutes: 15));
  });

  test('不能继续：不是今天的训练 / 已有进行中的训练', () async {
    final view = await setup();
    final id = view.workout.id;
    await repo.finishWorkout(id);

    await repo.startWorkout(); // 又开了一次新的
    expect(await repo.resumeWorkout(id), isNull);
    final other = (await repo.activeWorkout())!;
    await repo.discardWorkout(other.id);

    clock = clock.add(const Duration(days: 1));
    expect(await repo.resumeWorkout(id), isNull); // 过了一天，进入「过去」
  });

  hostTests();

  test('最后一次操作存在本机：重新打开应用后仍能读回', () async {
    final store = WorkoutActivityStore(db);
    final t = DateTime(2026, 11, 8, 9, 30);
    await store.save('w1', touch: t, hold: t.add(const Duration(minutes: 1)));
    final got = await store.load('w1');
    expect(got.touch, t);
    expect(got.hold, t.add(const Duration(minutes: 1)));
    await store.clear('w1');
    expect((await store.load('w1')).touch, isNull);
  });
}

class _Host {
  static Widget build({
    required AppDatabase db,
    required WorkoutRepository repo,
    required DateTime Function() clock,
    required GoRouter router,
  }) =>
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          workoutRepositoryProvider.overrideWithValue(repo),
          routerProvider.overrideWithValue(router),
          clockProvider.overrideWithValue(clock),
        ],
        child: AutoEndHost(
          checkEvery: const Duration(seconds: 1),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
}

void hostTests() {
  testWidgets('应用在前台：全部做完后 1 分钟没操作 → 自动结束，时长不含空闲，并跳到总结页', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var now = DateTime(2026, 11, 8, 9, 0);
    final repo = WorkoutRepository(db, userId: () => 'u1', now: () => now);
    final w = await repo.startWorkout();
    await repo.addExercise(w.id, 'ex-bench', defaultSets: 1, exactSets: true);
    final set = (await repo.loadWorkout(w.id))!.exercises.single.sets.single;
    await repo.updateSet(set.id, weightKg: 50, reps: 8);
    now = DateTime(2026, 11, 8, 9, 10);
    await repo.setCompleted(set.id, true); // 最后一次操作 09:10

    final router = GoRouter(initialLocation: '/workout', routes: [
      GoRoute(path: '/workout', builder: (_, _) => const Scaffold(body: Text('训练页')), routes: [
        GoRoute(path: 'summary', builder: (_, _) => const Scaffold(body: Text('总结页'))),
      ]),
      GoRoute(path: '/today', builder: (_, _) => const Scaffold(body: Text('首页'))),
    ]);
    await tester.pumpWidget(_Host.build(db: db, repo: repo, clock: () => now, router: router));
    await tester.pump(const Duration(seconds: 2));
    expect((await repo.activeWorkout())?.id, w.id); // 才过了几秒，不会结束

    now = DateTime(2026, 11, 8, 9, 11, 5); // 空闲 65 秒
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(await repo.activeWorkout(), isNull);
    final saved = (await repo.loadWorkout(w.id))!.workout;
    expect(saved.endedAt, DateTime(2026, 11, 8, 9, 10));
    expect(find.text('总结页'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
