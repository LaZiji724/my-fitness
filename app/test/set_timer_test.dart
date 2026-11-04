import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/core/db/database_provider.dart';
import 'package:my_fitness/core/notifications/reminder_host.dart';
import 'package:my_fitness/core/notifications/reminder_scheduler.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_repository.dart';
import 'package:my_fitness/features/workout/workout_page.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

import 'exercises_test.dart' show loadSeed;

class _FakeRepo implements ExerciseRepository {
  _FakeRepo(this.items);
  final List<Exercise> items;
  @override
  Future<List<Exercise>> loadAll() async => items;
}

/// 记录收到的调用，不碰系统插件。
class _FakeScheduler implements ReminderScheduler {
  _FakeScheduler({this.granted = true});
  final bool granted;
  int permissionAsked = 0;
  int cancelAllCalls = 0;
  final scheduled = <({int id, DateTime at, String title, String body})>[];

  @override
  Future<bool> requestPermission() async {
    permissionAsked++;
    return granted;
  }

  @override
  Future<void> schedule({required int id, required DateTime at, required String title, required String body}) async {
    scheduled.add((id: id, at: at, title: title, body: body));
  }

  final cancelled = <int>[];

  @override
  Future<void> cancel(int id) async => cancelled.add(id);

  @override
  Future<void> cancelAll() async => cancelAllCalls++;
}

void main() {
  late AppDatabase db;
  late WorkoutRepository repo;
  late _FakeScheduler scheduler;
  var now = DateTime.utc(2026, 11, 4, 10);
  final all = loadSeed();
  final plank = all.firstWhere((e) => e.trackingType == TrackingType.duration);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = WorkoutRepository(db, userId: () => 'u1');
    scheduler = _FakeScheduler();
    now = DateTime.utc(2026, 11, 4, 10);
  });
  tearDown(() => db.close());

  /// 让假时钟和测试里的定时器一起前进。
  Future<void> advance(WidgetTester tester, int seconds) async {
    now = now.add(Duration(seconds: seconds));
    await tester.pump(Duration(seconds: seconds));
  }

  Widget host(Widget home) {
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(path: '/start', builder: (_, _) => home),
        GoRoute(path: '/today', builder: (_, _) => const Scaffold(body: Text('首页'))),
      ],
    );
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        workoutRepositoryProvider.overrideWithValue(repo),
        exerciseRepositoryProvider.overrideWithValue(_FakeRepo(all)),
        clockProvider.overrideWithValue(() => now),
        reminderSchedulerProvider.overrideWithValue(scheduler),
      ],
      child: ReminderHost(child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router)),
    );
  }

  /// 一个 30 秒的计时动作，返回组 id。
  Future<({String workoutId, String setId})> timedWorkout() async {
    final w = await repo.startWorkout();
    final weId = await repo.addExercise(w.id, plank.id,
        defaultSets: 0, tracking: TrackingType.duration, defaultDurationSec: 30);
    final setId = await repo.addSet(weId);
    await repo.updateSet(setId, durationSec: 30);
    return (workoutId: w.id, setId: setId);
  }

  Future<bool> isCompleted(String workoutId) async {
    final view = await repo.loadWorkout(workoutId);
    return view!.exercises.single.sets.single.completed;
  }

  testWidgets('点开始后时间固定并读秒，归零自动打勾并开始休息', (tester) async {
    final ids = await timedWorkout();
    await tester.pumpWidget(host(const WorkoutPage()));
    await tester.pumpAndSettle();

    // 开始前：时间可调（点得开数字键盘）、按钮是「开始」
    expect(find.bySemanticsLabel(RegExp('第 1 组时长')), findsOneWidget);
    expect(find.text('开始'), findsOneWidget);

    await tester.tap(find.text('开始'));
    await tester.pump();
    expect(find.text('30', findRichText: true), findsWidgets);
    expect(find.byKey(const Key('set-timer-remaining')), findsOneWidget);
    // 开始后：时间格不能再点开调整，按钮变成「停止」
    expect(find.bySemanticsLabel(RegExp('第 1 组时长')), findsNothing);
    expect(find.text('停止'), findsOneWidget);
    expect(await isCompleted(ids.workoutId), isFalse);

    await advance(tester, 10);
    expect(tester.widget<Text>(find.byKey(const Key('set-timer-remaining'))).data, '20');
    expect(await isCompleted(ids.workoutId), isFalse);

    await advance(tester, 20);
    await tester.pumpAndSettle();
    expect(await isCompleted(ids.workoutId), isTrue);
    expect(find.byKey(const Key('set-timer-remaining')), findsNothing);
    expect(find.text('完成'), findsWidgets); // 按钮显示「完成」
    expect(find.bySemanticsLabel('取消完成第 1 组'), findsOneWidget);
    expect(find.text('组间休息'), findsOneWidget);
    // 时间保持原来设置的 30 秒
    expect((await repo.loadWorkout(ids.workoutId))!.exercises.single.sets.single.durationSec, 30);
  });

  testWidgets('计时中点停止：不打勾，可重新开始', (tester) async {
    final ids = await timedWorkout();
    await tester.pumpWidget(host(const WorkoutPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('开始'));
    await tester.pump();
    await advance(tester, 5);
    await tester.tap(find.text('停止'));
    await tester.pump();
    expect(find.text('开始'), findsOneWidget);

    await advance(tester, 60);
    await tester.pumpAndSettle();
    expect(await isCompleted(ids.workoutId), isFalse);
  });

  testWidgets('没有设置时长不能开始', (tester) async {
    final w = await repo.startWorkout();
    final weId = await repo.addExercise(w.id, plank.id, defaultSets: 0, tracking: TrackingType.duration);
    final setId = await repo.addSet(weId);
    await repo.updateSet(setId, clearReps: true);
    // 直接清空时长
    await (db.update(db.workoutSets)..where((s) => s.id.equals(setId)))
        .write(const WorkoutSetsCompanion(durationSec: Value(null)));

    await tester.pumpWidget(host(const WorkoutPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始'));
    await tester.pump();
    expect(find.text('先设置时长'), findsOneWidget);
    expect(find.text('停止'), findsNothing);
  });

  testWidgets('在前台不安排通知；退到后台才登记，回前台撤销', (tester) async {
    final ids = await timedWorkout();
    await tester.pumpWidget(host(const WorkoutPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('开始'));
    await tester.pump();
    // 前台：只问一次权限，没有任何通知被登记
    expect(scheduler.permissionAsked, 1);
    expect(scheduler.scheduled, isEmpty);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(scheduler.scheduled, isEmpty, reason: 'inactive 只是被遮挡，不算退到后台');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(scheduler.scheduled, hasLength(1));
    expect(scheduler.scheduled.single.id, kSetTimerReminderId);
    expect(scheduler.scheduled.single.at, now.add(const Duration(seconds: 30)));
    expect(scheduler.scheduled.single.body, contains('第 1 组'));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(scheduler.cancelAllCalls, 1);
    expect(await isCompleted(ids.workoutId), isFalse);

    // 回到前台后继续倒数，仍然不登记
    scheduler.scheduled.clear();
    await advance(tester, 5);
    expect(scheduler.scheduled, isEmpty);
    await advance(tester, 25);
    await tester.pumpAndSettle();
    expect(await isCompleted(ids.workoutId), isTrue);
  });

  testWidgets('后台期间动作计时结束：回到前台补上打勾并接着休息', (tester) async {
    final ids = await timedWorkout();
    await tester.pumpWidget(host(const WorkoutPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始'));
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    // 系统把应用冻结了，定时器没触发，时间却过去了 40 秒
    now = now.add(const Duration(seconds: 40));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(await isCompleted(ids.workoutId), isTrue);
    expect(find.text('组间休息'), findsOneWidget);
  });

  testWidgets('后台时动作计时结束后接着休息，休息结束也会登记提醒', (tester) async {
    await timedWorkout();
    await tester.pumpWidget(host(const WorkoutPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始'));
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    scheduler.scheduled.clear();

    await advance(tester, 30); // 后台里定时器恰好还在跑
    await tester.pumpAndSettle();
    // 同一个编号重复登记只会覆盖，不会多弹
    final rest = scheduler.scheduled.where((s) => s.id == kRestReminderId).toList();
    expect(rest, isNotEmpty);
    for (final r in rest) {
      expect(r.at, now.add(const Duration(seconds: kDefaultRestSec)));
      expect(r.title, '休息结束');
    }
  });

  testWidgets('组间休息：后台登记、前台不登记', (tester) async {
    await tester.pumpWidget(host(const SizedBox()));
    final container = ProviderScope.containerOf(tester.element(find.byType(SizedBox).first));

    container.read(restTimerProvider.notifier).start(60, now: now);
    await tester.pump();
    expect(scheduler.scheduled, isEmpty);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(scheduler.scheduled.map((s) => s.id), [kRestReminderId]);
    expect(scheduler.scheduled.single.at, now.add(const Duration(seconds: 60)));

    // 休息已经结束就不再登记
    scheduler.scheduled.clear();
    now = now.add(const Duration(minutes: 5));
    container.read(restTimerProvider.notifier).start(60, now: now.subtract(const Duration(minutes: 3)));
    await tester.pump();
    expect(scheduler.scheduled, isEmpty);
  });

  testWidgets('通知权限被拒绝时训练页给出提示', (tester) async {
    scheduler = _FakeScheduler(granted: false);
    await timedWorkout();
    await tester.pumpWidget(host(const WorkoutPage()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notify-hint')), findsNothing);

    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notify-hint')), findsOneWidget);
  });

  group('iOS：一开始倒数就登记（不依赖退后台那一瞬间）', () {
    // 平台覆盖必须在测试体结束前恢复
    void iosTest(String name, Future<void> Function(WidgetTester) body) {
      testWidgets(name, (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await body(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    iosTest('动作计时一开始就登记；停止就撤销；回前台仍保留', (tester) async {
      await timedWorkout();
      await tester.pumpWidget(host(const WorkoutPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('开始'));
      await tester.pump();
      expect(scheduler.scheduled.where((s) => s.id == kSetTimerReminderId), isNotEmpty);
      expect(scheduler.scheduled.last.at, now.add(const Duration(seconds: 30)));

      // 退后台、回前台：先清空，再把还在倒数的重新登记
      scheduler.scheduled.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(scheduler.cancelAllCalls, 1);
      expect(scheduler.scheduled.where((s) => s.id == kSetTimerReminderId), isNotEmpty);

      // 点停止：撤销已登记的提醒
      scheduler.cancelled.clear();
      await tester.tap(find.text('停止'));
      await tester.pump();
      expect(scheduler.cancelled, contains(kSetTimerReminderId));
    });

    iosTest('组间休息开始时登记', (tester) async {
      await tester.pumpWidget(host(const SizedBox()));
      final container = ProviderScope.containerOf(tester.element(find.byType(SizedBox).first));
      container.read(restTimerProvider.notifier).start(60, now: now);
      await tester.pump();
      expect(scheduler.scheduled.map((s) => s.id), contains(kRestReminderId));
      expect(scheduler.scheduled.last.at, now.add(const Duration(seconds: 60)));
    });
  });
}
